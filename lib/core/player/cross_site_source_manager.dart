import 'dart:async';
import 'package:flutter/foundation.dart';

import '../api/models/vod_models.dart';
import '../api/parse_engine.dart';
import '../api/search_cancel_token.dart';
import '../api/search_engine.dart';
import '../api/site_api.dart';
import '../config/models/vod_config.dart';
import 'cross_site_health_probe.dart';
import 'cross_site_models.dart';
import 'episode_name_mapper.dart';
import 'models/player_state.dart';
import 'share_page_resolver.dart';
import 'title_keyword_cleaner.dart';

/// 跨站换源聚合管理核心服务。
///
/// 职责：
/// 1. 全源搜索（最多 500 个站点，候选上限 24，总预算 20s）
/// 2. 关键词清洗（保留年份、0 结果退回原标题再搜）
/// 3. 并发详情探测（4 路并发，单条 6s 超时）
/// 4. 并发 TCP 体检（6 路并发，单条 6s 超时，真解析 + TCP connect）
/// 5. 排序维护（ok 升序 -> 未测 -> fail）
/// 6. 剧集级缓存（以「规范化片名 + 集数」为 key，换集不重搜全量）
/// 7. 换源执行（行内阶段反馈，支持最多 3 条备用线路重试，会话 epoch 防窜台）
/// 8. 预取支持（ensure 语义）
class CrossSiteSourceManager extends ValueNotifier<SourceCandidatesState> {
  final SearchEngine _searchEngine;
  final SiteApi _siteApi;
  final SharePageResolver _shareResolver;
  final CrossSiteHealthProbe _healthProbe;

  static const int maxSiteCount = 500;
  static const int maxCandidatesCount = 24;
  static const Duration totalSearchBudget = Duration(seconds: 20);
  static const Duration probeTimeout = Duration(seconds: 6);

  /// 剧集级内存缓存：showCacheKey -> List<CrossSiteCandidate>
  final Map<String, List<CrossSiteCandidate>> _showCache = {};

  SearchCancelToken? _currentSearchCancelToken;
  int _searchEpoch = 0;
  String? _lastShowCacheKey;

  CrossSiteSourceManager({
    required SearchEngine searchEngine,
    required SiteApi siteApi,
    SharePageResolver? shareResolver,
    CrossSiteHealthProbe? healthProbe,
  })  : _searchEngine = searchEngine,
        _siteApi = siteApi,
        _shareResolver = shareResolver ?? SharePageResolver(),
        _healthProbe = healthProbe ?? CrossSiteHealthProbe(),
        super(const SourceCandidatesState());

  /// 清空当前状态与缓存
  void clear() {
    cancelCurrentSearch();
    _showCache.clear();
    _lastShowCacheKey = null;
    value = const SourceCandidatesState();
  }

  /// 取消当前正在进行的搜索与探测
  void cancelCurrentSearch() {
    _searchEpoch++;
    _currentSearchCancelToken?.cancel();
    _currentSearchCancelToken = null;
  }

  /// 预取入口（起播 3 秒后后台调用；具备 ensure 语义，已缓存或当前正在搜索则直接复用）
  Future<void> ensurePrefetch({
    required CrossSiteTarget target,
    required List<Site> sites,
    ParseEngine? parseEngine,
    List<Parse> parses = const [],
  }) async {
    final normTitle = TitleKeywordCleaner.normalizeTitle(target.title);
    if (normTitle.isEmpty) return;
    final cacheKey = target.showCacheKey(normTitle);

    // 已有缓存，无需重搜
    if (_showCache.containsKey(cacheKey)) return;

    // 当前正在搜索同一个 showKey，无需重开
    if (value.searching && _lastShowCacheKey == cacheKey) return;

    await searchOrUpdate(
      target: target,
      sites: sites,
      parseEngine: parseEngine,
      parses: parses,
      forceRefresh: false,
    );
  }

  /// 发起搜索或切换剧集更新候选
  Future<void> searchOrUpdate({
    required CrossSiteTarget target,
    required List<Site> sites,
    ParseEngine? parseEngine,
    List<Parse> parses = const [],
    bool forceRefresh = false,
  }) async {
    final normTitle = TitleKeywordCleaner.normalizeTitle(target.title);
    if (normTitle.isEmpty) {
      value = const SourceCandidatesState(message: '片名为空，无法换源');
      return;
    }

    final cacheKey = target.showCacheKey(normTitle);
    _lastShowCacheKey = cacheKey;

    // 1. 如果已有缓存且非强制刷新，检查是否只需换集映射
    if (!forceRefresh && _showCache.containsKey(cacheKey)) {
      final cachedList = _showCache[cacheKey]!;
      _remapCachedCandidates(cachedList, target, parseEngine, parses);
      return;
    }

    // 2. 开始全新搜索
    cancelCurrentSearch();
    final epoch = ++_searchEpoch;
    final cancelToken = SearchCancelToken();
    _currentSearchCancelToken = cancelToken;

    value = SourceCandidatesState(
      searching: true,
      candidates: const [],
      message: '正在全源查找同片来源…',
      episodeKey: target.episodeName,
    );

    final swTotal = Stopwatch()..start();

    try {
      final keyword = target.searchKeyword?.trim().isNotEmpty == true
          ? target.searchKeyword!.trim()
          : TitleKeywordCleaner.cleanSearchKeyword(target.title);

      // 搜索站点（上限 500 个有效站）
      final searchSites = sites
          .where((s) => s.key.isNotEmpty && s.key != target.currentSiteKey)
          .take(maxSiteCount)
          .toList();

      if (searchSites.isEmpty) {
        if (epoch == _searchEpoch) {
          value = SourceCandidatesState(
            searching: false,
            candidates: const [],
            message: '未发现其他可用站点',
            episodeKey: target.episodeName,
          );
        }
        return;
      }

      // 执行增量搜索并收集候选
      var rawHits = await _collectSearchHits(
        keyword: keyword,
        sites: searchSites,
        cancelToken: cancelToken,
        epoch: epoch,
        timeout: totalSearchBudget,
      );

      // 若清洗后 0 候选，用原标题再搜一次
      if (rawHits.isEmpty &&
          !cancelToken.isCancelled &&
          target.title.trim() != keyword) {
        rawHits = await _collectSearchHits(
          keyword: target.title.trim(),
          sites: searchSites,
          cancelToken: cancelToken,
          epoch: epoch,
          timeout: Duration(seconds: (20 - swTotal.elapsed.inSeconds).clamp(4, 20)),
        );
      }

      if (cancelToken.isCancelled || epoch != _searchEpoch) return;

      if (rawHits.isEmpty) {
        value = SourceCandidatesState(
          searching: false,
          candidates: const [],
          message: swTotal.elapsed >= totalSearchBudget
              ? '20秒超时，未找到同片其他来源'
              : '未找到同片其他来源',
          episodeKey: target.episodeName,
        );
        return;
      }

      // 过滤与排序候选命中（最多 24 个）
      final candidateHits = _filterMatchingHits(rawHits, target).take(maxCandidatesCount).toList();

      if (candidateHits.isEmpty) {
        value = SourceCandidatesState(
          searching: false,
          candidates: const [],
          message: '未找到同片匹配来源',
          episodeKey: target.episodeName,
        );
        return;
      }

      // 并发 4 路探测详情
      final candidateList = <CrossSiteCandidate>[];
      final seenCandidateSiteKeys = <String>{};
      final seenCandidateSiteNames = <String>{};
      value = SourceCandidatesState(
        searching: true,
        candidates: const [],
        message: '找到 ${candidateHits.length} 个候选，正在探测详情…',
        episodeKey: target.episodeName,
      );

      await _runWithConcurrency<(Site, VodItem)>(
        candidateHits,
        4,
        (hit) async {
          if (cancelToken.isCancelled || epoch != _searchEpoch) return;
          final site = hit.$1;
          final item = hit.$2;

          final siteKey = site.key.trim();
          final siteName = site.name.trim();
          if (siteKey.isNotEmpty && seenCandidateSiteKeys.contains(siteKey)) return;
          if (siteName.isNotEmpty && seenCandidateSiteNames.contains(siteName)) return;

          final sw = Stopwatch()..start();
          try {
            final detail = await _siteApi.fetchDetail(site, vodId: item.id).timeout(probeTimeout);
            sw.stop();
            if (detail == null || detail.sources.isEmpty) return;

            // 遇到该播放源有2条或多条线路的，自动优选线路后缀有 m3u8 的线路（如 lzm3u8, ffm3u8）
            final preferredLineIdx = findPreferredLineIndex(detail.sources);
            final source = detail.sources[preferredLineIdx];
            if (source.episodes.isEmpty) return;

            final epNames = source.episodes.map((e) => e.name).toList();
            final mappedIdx = EpisodeNameMapper.mapEpisodeIndex(
              targetName: target.episodeName,
              targetIndex: target.episodeIndex,
              candidateEpisodeNames: epNames,
            );
            final ep = source.episodes[mappedIdx];

            final candidate = CrossSiteCandidate(
              site: site,
              detailUrl: item.id,
              vodName: item.name,
              item: item,
              detail: detail,
              lineName: source.name,
              lineIndex: preferredLineIdx,
              episodeName: ep.name,
              episodeUrl: ep.url,
              episodeIndex: mappedIdx,
              searchDurationMs: 0,
              detailDurationMs: sw.elapsedMilliseconds,
              probe: const CandidateProbeResult(status: ProbeStatus.untested),
            );

            if (siteKey.isNotEmpty && !seenCandidateSiteKeys.add(siteKey)) return;
            if (siteName.isNotEmpty && !seenCandidateSiteNames.add(siteName)) return;

            candidateList.add(candidate);

            if (epoch == _searchEpoch) {
              value = SourceCandidatesState(
                searching: true,
                candidates: CrossSiteHealthProbe.sortCandidates(candidateList, deduplicateBySite: true),
                message: '正在探测 (${candidateList.length}/${candidateHits.length})…',
                episodeKey: target.episodeName,
              );
            }
          } catch (_) {
            // 单条详情超时或失败，忽略
          }
        },
      );

      if (cancelToken.isCancelled || epoch != _searchEpoch) return;

      // 存入缓存
      _showCache[cacheKey] = List.of(candidateList);

      // 并发 6 路做媒体解析与 TCP connect 体检
      value = SourceCandidatesState(
        searching: true,
        candidates: CrossSiteHealthProbe.sortCandidates(candidateList, deduplicateBySite: true),
        message: '正在对 ${candidateList.length} 个可用源进行体检…',
        episodeKey: target.episodeName,
      );

      await _probeAllHealth(candidateList, parseEngine, parses, cancelToken, epoch, target.episodeName);

      if (cancelToken.isCancelled || epoch != _searchEpoch) return;

      value = SourceCandidatesState(
        searching: false,
        candidates: CrossSiteHealthProbe.sortCandidates(candidateList, deduplicateBySite: true),
        message: candidateList.isEmpty ? '未发现可用换源线路' : null,
        episodeKey: target.episodeName,
      );
    } catch (e) {
      if (epoch == _searchEpoch) {
        value = SourceCandidatesState(
          searching: false,
          candidates: const [],
          message: '换源搜索失败: $e',
          episodeKey: target.episodeName,
        );
      }
    } finally {
      if (epoch == _searchEpoch) {
        _currentSearchCancelToken = null;
      }
    }
  }

  /// 换集映射已有缓存候选，并触发新集体检
  void _remapCachedCandidates(
    List<CrossSiteCandidate> cachedList,
    CrossSiteTarget target,
    ParseEngine? parseEngine,
    List<Parse> parses,
  ) {
    final updatedList = <CrossSiteCandidate>[];
    for (final c in cachedList) {
      if (c.detail.sources.isEmpty) continue;
      final source = c.lineIndex < c.detail.sources.length
          ? c.detail.sources[c.lineIndex]
          : c.detail.sources.first;
      final epNames = source.episodes.map((e) => e.name).toList();
      final mappedIdx = EpisodeNameMapper.mapEpisodeIndex(
        targetName: target.episodeName,
        targetIndex: target.episodeIndex,
        candidateEpisodeNames: epNames,
      );
      final ep = source.episodes[mappedIdx];

      updatedList.add(c.copyWith(
        episodeName: ep.name,
        episodeUrl: ep.url,
        episodeIndex: mappedIdx,
        probe: const CandidateProbeResult(status: ProbeStatus.untested),
        clearSwitching: true,
      ));
    }

    final epoch = ++_searchEpoch;
    final cancelToken = SearchCancelToken();
    _currentSearchCancelToken = cancelToken;

    value = SourceCandidatesState(
      searching: true,
      candidates: CrossSiteHealthProbe.sortCandidates(updatedList, deduplicateBySite: true),
      message: '已加载缓存，正在体检当前集…',
      episodeKey: target.episodeName,
    );

    _probeAllHealth(updatedList, parseEngine, parses, cancelToken, epoch, target.episodeName).then((_) {
      if (epoch == _searchEpoch && !cancelToken.isCancelled) {
        value = SourceCandidatesState(
          searching: false,
          candidates: CrossSiteHealthProbe.sortCandidates(updatedList, deduplicateBySite: true),
          episodeKey: target.episodeName,
        );
      }
    });
  }

  /// 对候选列表执行并发 6 路真解析与 TCP 建连体检
  Future<void> _probeAllHealth(
    List<CrossSiteCandidate> list,
    ParseEngine? parseEngine,
    List<Parse> parses,
    SearchCancelToken cancelToken,
    int epoch,
    String episodeKey,
  ) async {
    await _runWithConcurrency<CrossSiteCandidate>(
      list,
      6,
      (c) async {
        if (cancelToken.isCancelled || epoch != _searchEpoch) return;
        final probeResult = await _probeCandidateMedia(c, parseEngine, parses);

        final idx = list.indexWhere((e) => e.candidateKey == c.candidateKey);
        if (idx >= 0) {
          list[idx] = list[idx].copyWith(probe: probeResult);
        }

        if (epoch == _searchEpoch && !cancelToken.isCancelled) {
          value = SourceCandidatesState(
            searching: true,
            candidates: CrossSiteHealthProbe.sortCandidates(list, deduplicateBySite: true),
            message: '体检中…',
            episodeKey: episodeKey,
          );
        }
      },
    );
  }

  /// 真实解析并做 TCP 建连体检单条候选
  Future<CandidateProbeResult> _probeCandidateMedia(
    CrossSiteCandidate candidate,
    ParseEngine? parseEngine,
    List<Parse> parses,
  ) async {
    try {
      var playUrl = candidate.episodeUrl;
      // 真实解析
      if (parseEngine != null) {
        try {
          final spec = await _siteApi.resolvePlayback(
            candidate.site,
            id: candidate.episodeUrl,
            flag: candidate.lineName,
            parseEngine: parseEngine,
            parses: parses,
          ).timeout(probeTimeout);
          playUrl = spec.url;
        } catch (e) {
          return CandidateProbeResult(
            status: ProbeStatus.fail,
            failReason: '解析失败: ${e.toString().split('\n').first}',
          );
        }
      }

      // 分享页处理
      final realMediaUrl = await _shareResolver.resolveIfSharePage(playUrl);

      // TCP connect 探活
      return await _healthProbe.probeMediaUrl(realMediaUrl, timeout: probeTimeout);
    } catch (e) {
      return CandidateProbeResult(
        status: ProbeStatus.fail,
        failReason: '探活异常: $e',
      );
    }
  }

  /// 执行换源切换操作（含多线路重试 ≤3 条、行内状态更新、取消保护）
  Future<bool> executeSwitch({
    required CrossSiteCandidate candidate,
    required CrossSiteTarget target,
    required ParseEngine parseEngine,
    required List<Parse> parses,
    required Future<void> Function(
      MediaPlaySpec spec,
      CrossSiteCandidate candidate,
      PlayFrom line,
      int episodeIndex,
    ) onPlay,
  }) async {
    final candidateKey = candidate.candidateKey;
    final currentEpoch = _searchEpoch;

    void updateStage(String stage) {
      if (currentEpoch != _searchEpoch) return;
      final updated = value.candidates.map((c) {
        if (c.candidateKey == candidateKey) {
          return c.copyWith(switchingStage: stage);
        }
        return c.copyWith(clearSwitching: true);
      }).toList();
      value = value.copyWith(candidates: updated);
    }

    void clearStage() {
      if (currentEpoch != _searchEpoch) return;
      final updated = value.candidates.map((c) => c.copyWith(clearSwitching: true)).toList();
      value = value.copyWith(candidates: updated);
    }

    // 优先尝试当前点击的线路，若失败再尝试该站其它备用线路（≤ 3 条）
    final detail = candidate.detail;
    final allLines = detail.sources;
    final linesToTry = <PlayFrom>[];
    if (allLines.isNotEmpty) {
      if (candidate.lineIndex >= 0 && candidate.lineIndex < allLines.length) {
        linesToTry.add(allLines[candidate.lineIndex]);
      }
      for (var i = 0; i < allLines.length && linesToTry.length < 3; i++) {
        if (i != candidate.lineIndex) {
          linesToTry.add(allLines[i]);
        }
      }
    } else {
      linesToTry.add(PlayFrom(name: candidate.lineName, episodes: [
        VodEpisode(name: candidate.episodeName, url: candidate.episodeUrl)
      ]));
    }

    String lastError = '未知错误';

    for (var i = 0; i < linesToTry.length; i++) {
      final line = linesToTry[i];
      final epNames = line.episodes.map((e) => e.name).toList();
      final epIdx = EpisodeNameMapper.mapEpisodeIndex(
        targetName: target.episodeName,
        targetIndex: target.episodeIndex,
        candidateEpisodeNames: epNames,
      );
      final ep = line.episodes[epIdx];

      try {
        updateStage('解析中 (${line.name})');
        final spec = await _siteApi.resolvePlayback(
          candidate.site,
          id: ep.url,
          flag: line.name,
          parseEngine: parseEngine,
          parses: parses,
        ).timeout(const Duration(seconds: 12));

        if (currentEpoch != _searchEpoch) return false;

        updateStage('探活中');
        final realMediaUrl = await _shareResolver.resolveIfSharePage(spec.url);
        await _healthProbe.probeMediaUrl(realMediaUrl, timeout: const Duration(seconds: 5));

        // 哪怕 probe 报错，只要不是完全不可用依然尝试起播（探测不是权威）
        updateStage('起播中');
        final sourceLabel = formatSourceAndLine(candidate.site.name, line.name);
        final finalSpec = spec.copyWith(
          url: realMediaUrl,
          title: '${candidate.vodName} - ${ep.name} ($sourceLabel)',
          startPosition: target.currentPosition,
        );

        final actualLineIdx = allLines.indexOf(line);
        final switchedCandidate = candidate.copyWith(
          lineName: line.name,
          lineIndex: actualLineIdx >= 0 ? actualLineIdx : candidate.lineIndex,
          episodeName: ep.name,
          episodeUrl: ep.url,
          episodeIndex: epIdx,
        );

        await onPlay(finalSpec, switchedCandidate, line, epIdx);
        clearStage();
        return true;
      } catch (e) {
        lastError = '线路[${line.name}]失败: ${e.toString().split('\n').first}';
      }
    }

    // 3 条线路均失败
    clearStage();
    value = value.copyWith(message: '换源失败: $lastError');
    return false;
  }

  /// 收集搜索命中
  Future<List<(Site, VodItem)>> _collectSearchHits({
    required String keyword,
    required List<Site> sites,
    required SearchCancelToken cancelToken,
    required int epoch,
    required Duration timeout,
  }) async {
    final hits = <(Site, VodItem)>[];
    final seen = <String>{};
    final completer = Completer<List<(Site, VodItem)>>();
    Timer? timer;
    StreamSubscription<SearchBatch>? sub;

    void done() {
      if (completer.isCompleted) return;
      timer?.cancel();
      sub?.cancel();
      completer.complete(hits);
    }

    timer = Timer(timeout, done);
    cancelToken.onCancel(done);

    try {
      final stream = _searchEngine.searchAllIncremental(
        sites,
        keyword,
        cancelToken: cancelToken,
      );
      sub = stream.listen(
        (batch) {
          if (cancelToken.isCancelled || epoch != _searchEpoch) {
            done();
            return;
          }
          for (final item in batch.items) {
            final key = '${batch.site.key}_${item.id}';
            if (seen.add(key)) {
              hits.add((batch.site, item));
            }
          }
          // 达到上限即可返回
          if (hits.length >= maxCandidatesCount * 2) {
            done();
          }
        },
        onError: (_) {},
        onDone: done,
        cancelOnError: false,
      );
    } catch (_) {
      done();
    }

    return completer.future;
  }

  /// 过滤出片名吻合的命中，并按站点去重优选最佳匹配项
  List<(Site, VodItem)> _filterMatchingHits(
    List<(Site, VodItem)> hits,
    CrossSiteTarget target,
  ) {
    final targetNorm = TitleKeywordCleaner.normalizeTitle(target.title);
    final siteBestHit = <String, (Site, VodItem, int)>{};

    for (final hit in hits) {
      final site = hit.$1;
      final item = hit.$2;
      final itemNorm = TitleKeywordCleaner.normalizeTitle(item.name);
      if (itemNorm.isEmpty) continue;

      // 只要规范化片名互相包含，即视为命中
      final isMatch = itemNorm == targetNorm ||
          itemNorm.contains(targetNorm) ||
          targetNorm.contains(itemNorm);
      if (!isMatch) continue;

      // 匹配质量打分
      var score = 100;
      if (itemNorm == targetNorm) {
        score += 1000;
      } else {
        score += (200 - (itemNorm.length - targetNorm.length).abs() * 10).clamp(0, 200);
      }

      final isTrailer = item.name.contains('预告') || item.name.contains('花絮') || item.name.contains('特辑');
      final targetIsTrailer = target.title.contains('预告') || target.title.contains('花絮');
      if (isTrailer && !targetIsTrailer) {
        score -= 500;
      }

      // 同源（同站点）优先保留匹配得分最高的 1 条
      final siteKey = site.key.trim().isNotEmpty ? site.key.trim() : site.name.trim();
      final existing = siteBestHit[siteKey];
      if (existing == null || score > existing.$3) {
        siteBestHit[siteKey] = (site, item, score);
      }
    }

    // 按得分降序
    final sortedHits = siteBestHit.values.toList()
      ..sort((a, b) => b.$3.compareTo(a.$3));

    return sortedHits.map((e) => (e.$1, e.$2)).toList();
  }

  /// 轻量并发执行器
  Future<void> _runWithConcurrency<T>(
    List<T> items,
    int maxConcurrent,
    Future<void> Function(T item) worker,
  ) async {
    if (items.isEmpty) return;
    var cursor = 0;
    final workerCount = items.length < maxConcurrent ? items.length : maxConcurrent;
    final futures = <Future<void>>[];

    for (var i = 0; i < workerCount; i++) {
      futures.add(() async {
        while (true) {
          if (cursor >= items.length) break;
          final current = items[cursor++];
          await worker(current);
        }
      }());
    }
    await Future.wait(futures);
  }
}
