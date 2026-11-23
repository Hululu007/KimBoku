import 'package:flutter/foundation.dart';

import '../api/models/vod_models.dart';
import '../config/models/vod_config.dart';
import 'cross_site_failover_planner.dart';

/// 体检探活状态。
enum ProbeStatus {
  ok,
  untested,
  fail,
}

/// 某条候选的体检结果。
@immutable
class CandidateProbeResult {
  final ProbeStatus status;
  final int? pingMs;
  final String? failReason;
  final String? resolvedMediaUrl;

  const CandidateProbeResult({
    this.status = ProbeStatus.untested,
    this.pingMs,
    this.failReason,
    this.resolvedMediaUrl,
  });

  bool get isOk => status == ProbeStatus.ok;
  bool get isUntested => status == ProbeStatus.untested;
  bool get isFail => status == ProbeStatus.fail;

  CandidateProbeResult copyWith({
    ProbeStatus? status,
    int? pingMs,
    String? failReason,
    String? resolvedMediaUrl,
  }) {
    return CandidateProbeResult(
      status: status ?? this.status,
      pingMs: pingMs ?? this.pingMs,
      failReason: failReason ?? this.failReason,
      resolvedMediaUrl: resolvedMediaUrl ?? this.resolvedMediaUrl,
    );
  }

  @override
  String toString() => 'CandidateProbeResult(status: $status, pingMs: $pingMs, fail: $failReason)';
}

/// 跨站目标：片名、集名、集数、搜索关键词（可覆盖）。
class CrossSiteTarget {
  final String title;
  final String episodeName;
  final int episodeIndex;
  final int totalEpisodes;
  final String? searchKeyword;
  final String? currentSiteKey;
  final String? currentVodId;
  final Duration currentPosition;
  final VodItem item;

  CrossSiteTarget({
    String? title,
    VodItem? item,
    required this.episodeName,
    int? episodeIndex,
    int? episodeCount,
    int totalEpisodes = 0,
    this.searchKeyword,
    String? siteKey,
    String? currentSiteKey,
    this.currentVodId,
    this.currentPosition = Duration.zero,
  })  : title = title ?? item?.name ?? '',
        item = item ??
            VodItem(
              id: currentVodId ?? '',
              name: title ?? '',
              pic: '',
              siteKey: currentSiteKey ?? siteKey,
            ),
        episodeIndex = episodeIndex ?? 0,
        totalEpisodes = totalEpisodes > 0 ? totalEpisodes : (episodeCount ?? 0),
        currentSiteKey = currentSiteKey ?? siteKey ?? item?.siteKey;

  int get episodeCount => totalEpisodes;
  String? get siteKey => currentSiteKey;
  CrossSiteTitleIdentity get identity => parseCrossSiteTitle(title);
  int? get year => parseCrossSiteYear(item.year);
  CrossSiteCoarseType? get coarseType => inferCrossSiteCoarseType(item.typeName);

  /// 缓存 key = 规范化片名 + 集数（整部剧只搜一次；换集时只换「集名」去目标站里映射）。
  String showCacheKey(String normalizedTitle) {
    final epCount = totalEpisodes > 0 ? totalEpisodes : episodeIndex + 1;
    return '${normalizedTitle}_$epCount';
  }

  CrossSiteTarget copyWith({
    String? title,
    VodItem? item,
    String? episodeName,
    int? episodeIndex,
    int? totalEpisodes,
    String? searchKeyword,
    String? currentSiteKey,
    String? currentVodId,
    Duration? currentPosition,
  }) {
    return CrossSiteTarget(
      title: title ?? this.title,
      item: item ?? this.item,
      episodeName: episodeName ?? this.episodeName,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      searchKeyword: searchKeyword ?? this.searchKeyword,
      currentSiteKey: currentSiteKey ?? this.currentSiteKey,
      currentVodId: currentVodId ?? this.currentVodId,
      currentPosition: currentPosition ?? this.currentPosition,
    );
  }
}

/// 跨站候选：站点、详情 url、命中的剧集/线路、搜索耗时、详情探测耗时、可播性。
class CrossSiteCandidate {
  static const defaultEvidence = CrossSiteMatchEvidence(
    score: 100,
    confidence: CrossSiteConfidence.high,
    yearMatched: false,
    actorOverlap: 0,
    directorMatched: false,
    typeMatched: false,
    episodeCountClose: false,
    remarksConsistent: false,
    contentOverlap: false,
    historyMatched: false,
  );

  final Site site;
  final String detailUrl;
  final String vodName;
  final VodItem item;
  final VodDetail? rawDetail;

  /// 命中的线路名称及索引
  final String lineName;
  final int lineIndex;

  /// 命中的剧集名称、url及在该线路中的索引
  final String episodeName;
  final String episodeUrl;
  final int episodeIndex;

  /// 耗时记录（毫秒）
  final int searchDurationMs;
  final int detailDurationMs;

  /// 可播性与 ping
  final CandidateProbeResult probe;

  /// 行内切换状态：null 表示静止；非空时为 '解析中' / '探活中' / '起播中' 等
  final String? switchingStage;

  // 兼容老规划器与排名的字段
  final int configIndex;
  final PlayFrom? rawSource;
  final CrossSiteEpisodeMatch? rawEpisodeMatch;
  final CrossSiteTitleIdentity? identity;
  final CrossSiteMatchEvidence evidence;
  final bool netdisk;

  CrossSiteCandidate({
    required this.site,
    String? detailUrl,
    String? vodName,
    required this.item,
    VodDetail? detail,
    String? lineName,
    int lineIndex = 0,
    int sourceIndex = 0,
    String? episodeName,
    String? episodeUrl,
    int episodeIndex = 0,
    this.searchDurationMs = 0,
    this.detailDurationMs = 0,
    this.probe = const CandidateProbeResult(),
    this.switchingStage,
    this.configIndex = 0,
    PlayFrom? source,
    CrossSiteEpisodeMatch? episodeMatch,
    this.identity,
    CrossSiteMatchEvidence? evidence,
    this.netdisk = false,
  })  : detailUrl = detailUrl ?? item.id,
        vodName = vodName ?? item.name,
        rawDetail = detail,
        lineIndex = lineIndex != 0 ? lineIndex : sourceIndex,
        lineName = lineName ?? (source != null ? source.name : ''),
        episodeName = episodeName ?? (episodeMatch != null ? episodeMatch.episode.name : ''),
        episodeUrl = episodeUrl ?? (episodeMatch != null ? episodeMatch.episode.url : ''),
        episodeIndex = episodeIndex != 0 ? episodeIndex : (episodeMatch?.episodeIndex ?? 0),
        rawSource = source,
        rawEpisodeMatch = episodeMatch,
        evidence = evidence ?? defaultEvidence;

  /// 候选 key = 站点标识 + 详情 url（稳定、按站点去重）
  String get candidateKey => '${site.key}_$detailUrl';

  VodDetail get detail =>
      rawDetail ?? VodDetail(item: item, sources: [source]);

  /// 该站点详情下的全部可用播放线路
  List<PlayFrom> get availableSources => detail.sources;

  // 兼容旧接口的便捷 getter
  PlayFrom get source =>
      rawSource ??
      ((rawDetail != null && lineIndex < rawDetail!.sources.length)
          ? rawDetail!.sources[lineIndex]
          : PlayFrom(name: lineName, episodes: [VodEpisode(name: episodeName, url: episodeUrl)]));

  int get sourceIndex => lineIndex;
  int get score => evidence.score;
  CrossSiteConfidence get confidence => evidence.confidence;
  CrossSiteEpisodeMatch get episodeMatch =>
      rawEpisodeMatch ??
      CrossSiteEpisodeMatch(
        episodeIndex: episodeIndex,
        episode: VodEpisode(name: episodeName, url: episodeUrl),
        kind: CrossSiteEpisodeMatchKind.sameName,
        unique: true,
        annotation: '',
      );

  bool get isSameName => episodeMatch.kind == CrossSiteEpisodeMatchKind.sameName;

  CrossSiteCandidate copyWith({
    Site? site,
    String? detailUrl,
    String? vodName,
    VodItem? item,
    VodDetail? detail,
    String? lineName,
    int? lineIndex,
    String? episodeName,
    String? episodeUrl,
    int? episodeIndex,
    int? searchDurationMs,
    int? detailDurationMs,
    CandidateProbeResult? probe,
    String? switchingStage,
    bool clearSwitching = false,
    int? configIndex,
    PlayFrom? source,
    CrossSiteEpisodeMatch? episodeMatch,
    CrossSiteTitleIdentity? identity,
    CrossSiteMatchEvidence? evidence,
    bool? netdisk,
  }) {
    return CrossSiteCandidate(
      site: site ?? this.site,
      detailUrl: detailUrl ?? this.detailUrl,
      vodName: vodName ?? this.vodName,
      item: item ?? this.item,
      detail: detail ?? rawDetail,
      lineName: lineName ?? this.lineName,
      lineIndex: lineIndex ?? this.lineIndex,
      episodeName: episodeName ?? this.episodeName,
      episodeUrl: episodeUrl ?? this.episodeUrl,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      searchDurationMs: searchDurationMs ?? this.searchDurationMs,
      detailDurationMs: detailDurationMs ?? this.detailDurationMs,
      probe: probe ?? this.probe,
      switchingStage: clearSwitching ? null : (switchingStage ?? this.switchingStage),
      configIndex: configIndex ?? this.configIndex,
      source: source ?? rawSource,
      episodeMatch: episodeMatch ?? rawEpisodeMatch,
      identity: identity ?? this.identity,
      evidence: evidence ?? this.evidence,
      netdisk: netdisk ?? this.netdisk,
    );
  }
}

/// 跨站候选状态：{searching, candidates, probes(按候选 key), message, episodeKey}。
@immutable
class SourceCandidatesState {
  final bool searching;
  final List<CrossSiteCandidate> candidates;
  final Map<String, CandidateProbeResult> probes;
  final String? message;
  final String? episodeKey;

  const SourceCandidatesState({
    this.searching = false,
    this.candidates = const <CrossSiteCandidate>[],
    this.probes = const <String, CandidateProbeResult>{},
    this.message,
    this.episodeKey,
  });

  SourceCandidatesState copyWith({
    bool? searching,
    List<CrossSiteCandidate>? candidates,
    Map<String, CandidateProbeResult>? probes,
    String? message,
    String? episodeKey,
  }) {
    return SourceCandidatesState(
      searching: searching ?? this.searching,
      candidates: candidates ?? this.candidates,
      probes: probes ?? this.probes,
      message: message ?? this.message,
      episodeKey: episodeKey ?? this.episodeKey,
    );
  }
}

/// 在一组线路中寻找优选线路下标：
/// 遇到该播放源有2条或多条线路的，自动优选线路后缀有 m3u8 的。
int findPreferredLineIndex(List<PlayFrom> sources) {
  if (sources.isEmpty) return 0;
  // 1. 优先找名称以 m3u8 结尾且有选集的线路（如 lzm3u8, ffm3u8, m3u8）
  final suffixIdx = sources.indexWhere((s) {
    final name = s.name.trim().toLowerCase();
    return name.endsWith('m3u8') && s.episodes.isNotEmpty;
  });
  if (suffixIdx >= 0) return suffixIdx;

  // 2. 其次找名称包含 m3u8 且有选集的线路
  final containsIdx = sources.indexWhere((s) {
    final name = s.name.trim().toLowerCase();
    return name.contains('m3u8') && s.episodes.isNotEmpty;
  });
  if (containsIdx >= 0) return containsIdx;

  // 3. 兜底第一条有集的线路
  final firstPlayable = sources.indexWhere((s) => s.episodes.isNotEmpty);
  return firstPlayable >= 0 ? firstPlayable : 0;
}

/// 格式化「播放源名 + 线路」，如「闪电 - 免费分享！切勿上当！」或「TV-西瓜资源 - xigua」
String formatSourceAndLine(String? siteName, String? lineName) {
  final site = siteName?.trim() ?? '';
  final line = lineName?.trim() ?? '';
  if (site.isEmpty) return line;
  if (line.isEmpty) return site;
  if (site.toLowerCase() == line.toLowerCase()) return site;
  if (site.toLowerCase().contains(line.toLowerCase())) return site;
  if (line.toLowerCase().contains(site.toLowerCase())) return line;
  return '$site - $line';
}
