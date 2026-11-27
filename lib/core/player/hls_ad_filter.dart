/// HLS 播放列表「插播广告」识别与剪辑（纯函数，可单测）。
///
/// 识别思路：插播广告的典型形态是
/// `正片块 | #EXT-X-DISCONTINUITY | 短广告块(5~90s / ≤30 片) | #EXT-X-DISCONTINUITY | 正片块`。
/// 结合以下多阶段规则覆盖真实采集源与多断流场景：
/// 1. 基于 `segments > 0` 的非空块视图进行邻接与边缘判断，避免头部/尾部空 `#EXT-X-DISCONTINUITY` 干扰；
/// 2. 精确重复分片 URI 序列检测：识别多断流正片内的隐蔽重复广告，干净多断流 0 误杀；
/// 3. Pass 1（紧致流短边放宽 + 两侧目录前缀隔离）；
/// 4. 动态防过杀阈值：最大段数随片长浮动 `clamp(ceil(totalDur / 300), 6, 30)`，
///    短片（< 600s）占比阈值放宽到 15%（常规 6%），精确重复 URI 豁免数量上限；
/// 5. Pass 2（基于已确认广告的签名/目录/URI/精确小数时长延伸与片尾交替创意识别）；
/// 6. 剪辑时严格仅保留列表级全局头标签，跳过空断流块；
/// 7. 硬性护栏：含 `#EXT-X-BYTERANGE` 或无 `#EXT-X-ENDLIST` 的直播流不处理。
library;

import 'dart:math' as math;

/// 单块最多几片仍可能是广告（整集切片通常几十到几百片）。
const int kAdMaxSegments = 30;

/// 单块时长区间（秒）：短于 5 秒更像切片噪声，长于 90 秒不像贴片广告。
const double kAdMinDuration = 5;
const double kAdMaxDuration = 90;

/// 剪辑时的二次护栏：只删「仍然像广告」的块（比识别条件略宽），宁可少删不误删。
const double kAdCutMinDuration = 5;
const double kAdCutMaxDuration = 120;
const int kAdCutMaxSegments = 40;

/// 第 0 块整块被删除时，仅允许保留的播放列表全局头标签。
final RegExp _playlistGlobalHeaderPattern = RegExp(
  r'^#(?:EXTM3U|EXT-X-VERSION|EXT-X-TARGETDURATION|EXT-X-PLAYLIST-TYPE|'
  r'EXT-X-MEDIA-SEQUENCE|EXT-X-DISCONTINUITY-SEQUENCE|'
  r'EXT-X-INDEPENDENT-SEGMENTS|EXT-X-ALLOW-CACHE)(?=$|:)',
  caseSensitive: false,
);

/// 广告块判定后是否被识别为片头 / 片尾。
enum HlsAdPlacement { middle, head, tail }

/// 播放列表里的一个 chunk（两个 discontinuity 之间的一段）。
class HlsAdBlock {
  const HlsAdBlock({
    required this.duration,
    required this.segments,
    required this.isAd,
    this.placement,
  });

  final double duration;
  final int segments;
  final bool isAd;

  /// 仅 [isAd] 为真时有值：插播 / 片头 / 片尾。
  final HlsAdPlacement? placement;

  HlsAdBlock copyWith({bool? isAd, HlsAdPlacement? placement}) => HlsAdBlock(
        duration: duration,
        segments: segments,
        isAd: isAd ?? this.isAd,
        placement: placement ?? this.placement,
      );

  @override
  String toString() =>
      'HlsAdBlock(${duration.toStringAsFixed(2)}s, $segments片${isAd ? ', 广告' : ''})';
}

/// 一段被判定为广告的区间（**原始时间轴**，秒）。
class HlsAdCut {
  const HlsAdCut({
    required this.start,
    required this.end,
    required this.placement,
    this.segments = 0,
  });

  final double start;
  final double end;
  final HlsAdPlacement placement;
  final int segments;

  double get duration => end - start;

  @override
  String toString() => '${start.toStringAsFixed(1)}s-${end.toStringAsFixed(1)}s'
      '${segments > 0 ? '($segments片)' : ''}';
}

/// 一次分析的结果。位置信息只用于诊断与日志，剪辑不依赖它。
class HlsAdAnalysis {
  const HlsAdAnalysis({
    required this.blocks,
    required this.cuts,
    required this.duration,
    required this.mainDuration,
    required this.edgeAds,
    required this.rejected,
  });

  /// 全部 chunk（含判定结果），下标与播放列表切块顺序一致。
  final List<HlsAdBlock> blocks;

  /// 判定的广告区间，按起始时间升序。
  final List<HlsAdCut> cuts;

  /// 原始总时长（秒，按 `#EXTINF` 累加）。
  final double duration;

  /// 剪掉广告后的正片时长（秒）。
  final double mainDuration;

  /// 片头 + 片尾广告数量。
  final int edgeAds;

  /// 命中过多被判为「整集切片」而放弃。
  final bool rejected;

  bool get hasAds => cuts.isNotEmpty;

  @override
  String toString() => 'HlsAdAnalysis(${blocks.length}块, ${cuts.length}段广告, '
      '${duration.toStringAsFixed(0)}s→${mainDuration.toStringAsFixed(0)}s'
      '${rejected ? ', 已放弃' : ''})';
}

/// 剪辑后的播放列表与统计。
class HlsCutPlaylist {
  const HlsCutPlaylist({
    required this.playlist,
    required this.cuts,
    required this.removedSeconds,
  });

  final String playlist;
  final List<HlsAdCut> cuts;
  final double removedSeconds;
}

/// 播放列表是否是「媒体列表」（含分片）而非主列表。
bool isMediaPlaylistText(String text) =>
    RegExp(r'^#EXTINF', multiLine: true).hasMatch(text);

/// 是否是 master（多码率）播放列表。
bool isMasterPlaylistText(String text) =>
    RegExp(r'^#EXT-X-STREAM-INF', multiLine: true).hasMatch(text);

/// 是否收尾（点播完整列表）；没有它的按直播处理，不碰。
bool hasEndListText(String text) =>
    RegExp(r'^#EXT-X-ENDLIST', multiLine: true).hasMatch(text);

/// 是否使用字节范围（分片偏移绑在同一文件上，删块必坏）。
bool hasByteRangeText(String text) =>
    RegExp(r'^#EXT-X-BYTERANGE', multiLine: true).hasMatch(text);

/// 按 `#EXT-X-DISCONTINUITY` 切块；tag 行本身不属于任何一块。
List<List<String>> splitAdBlocks(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  final blocks = <List<String>>[];
  var current = <String>[];
  for (final line in lines) {
    if (RegExp(r'^#EXT-X-DISCONTINUITY', caseSensitive: false)
        .hasMatch(line.trim())) {
      blocks.add(current);
      current = <String>[];
    } else {
      current.add(line);
    }
  }
  blocks.add(current);
  return blocks;
}

/// 切块的行号区间（`[start, end)`），与 [splitAdBlocks] 顺序严格一致。
List<({int start, int end})> splitAdBlockRanges(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  final blocks = <({int start, int end})>[];
  var start = 0;
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'^#EXT-X-DISCONTINUITY', caseSensitive: false)
        .hasMatch(lines[i].trim())) {
      blocks.add((start: start, end: i));
      start = i + 1;
    }
  }
  blocks.add((start: start, end: lines.length));
  return blocks;
}

class _ChunkInfo {
  const _ChunkInfo({
    required this.duration,
    required this.segments,
    required this.uris,
    required this.uriKey,
    required this.dirSig,
  });

  final double duration;
  final int segments;
  final List<String> uris;
  final String uriKey;
  final String dirSig;
}

String _uriDirSig(String rawUri) {
  var clean = rawUri.trim();
  if (clean.isEmpty) return '';
  final q = clean.indexOf('?');
  if (q >= 0) clean = clean.substring(0, q);
  final hash = clean.indexOf('#');
  if (hash >= 0) clean = clean.substring(0, hash);
  final uri = Uri.tryParse(clean);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final path = uri.path;
    final slash = path.lastIndexOf('/');
    if (slash < 0) return uri.host.toLowerCase();
    return '${uri.host.toLowerCase()}${path.substring(0, slash + 1)}';
  }
  final slash = clean.lastIndexOf('/');
  if (slash < 0) return '';
  return clean.substring(0, slash + 1);
}

_ChunkInfo _blockInfo(List<String> lines) {
  var duration = 0.0;
  var segments = 0;
  final uris = <String>[];
  String? singleDir;
  var mixedDir = false;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      if (!line.startsWith('#EXTINF')) continue;
      // #EXTINF:<时长>,[标题]；标题里可能有冒号，只取第一个冒号到第一个逗号。
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      var value = line.substring(colon + 1);
      final comma = value.indexOf(',');
      if (comma >= 0) value = value.substring(0, comma);
      duration += double.tryParse(value.trim()) ?? 0;
      segments++;
      continue;
    }
    uris.add(line);
    if (!mixedDir) {
      final dir = _uriDirSig(line);
      if (dir.isEmpty) {
        if (singleDir != null && singleDir.isNotEmpty) mixedDir = true;
        singleDir ??= '';
      } else if (singleDir == null) {
        singleDir = dir;
      } else if (singleDir != dir) {
        mixedDir = true;
      }
    }
  }

  return _ChunkInfo(
    duration: duration,
    segments: segments,
    uris: uris,
    uriKey: uris.isEmpty ? '' : uris.join('|'),
    dirSig: mixedDir ? '' : (singleDir ?? ''),
  );
}

bool _isAdShape(_ChunkInfo info) =>
    info.segments >= 1 &&
    info.segments <= kAdMaxSegments &&
    info.duration >= kAdMinDuration &&
    info.duration <= kAdMaxDuration;

String _signature(_ChunkInfo info) =>
    '${info.segments}:${info.duration.round()}';

List<HlsAdBlock> _blockList(
  List<_ChunkInfo> infos,
  Map<int, HlsAdPlacement> adMap,
) =>
    List<HlsAdBlock>.generate(
      infos.length,
      (i) => HlsAdBlock(
        duration: infos[i].duration,
        segments: infos[i].segments,
        isAd: adMap.containsKey(i),
        placement: adMap[i],
      ),
      growable: false,
    );

/// 分析播放列表里的插播 / 片头 / 片尾广告。
HlsAdAnalysis analyzeAdBlocks(String text) {
  final blocks = splitAdBlocks(text);
  final infos = blocks.map(_blockInfo).toList(growable: false);
  final totalDuration = infos.fold<double>(0, (sum, info) => sum + info.duration);

  // 忽略 #EXTM3U 头后或末尾空 #EXT-X-DISCONTINUITY 切出的 0 分片空块，
  // 所有邻接、边缘与断流计数都基于非空块视图，同时映射回原 blocks 下标。
  final nonEmpty = <int>[
    for (var i = 0; i < infos.length; i++)
      if (infos[i].segments > 0) i,
  ];

  // 不足 3 个非空块不可能存在「夹在正片中间」的插播；但片长照常返回（面板要显示）。
  if (nonEmpty.length < 3) {
    return HlsAdAnalysis(
      blocks: _blockList(infos, const {}),
      cuts: const [],
      duration: totalDuration,
      mainDuration: totalDuration,
      edgeAds: 0,
      rejected: false,
    );
  }

  // 精确重复分片 URI 序列检测：识别多断流正片（如 16~319 块）里的隐藏重复插播，
  // 同时对无重复分片的干净多断流流实现 0 误杀。
  final uriCounts = <String, int>{};
  for (final idx in nonEmpty) {
    final info = infos[idx];
    if (_isAdShape(info) && info.uriKey.isNotEmpty) {
      uriCounts[info.uriKey] = (uriCounts[info.uriKey] ?? 0) + 1;
    }
  }
  final dupIndices = <int>{};
  var dupDuration = 0.0;
  for (final idx in nonEmpty) {
    final info = infos[idx];
    if (_isAdShape(info) && (uriCounts[info.uriKey] ?? 0) >= 2) {
      dupIndices.add(idx);
      dupDuration += info.duration;
    }
  }
  if (dupIndices.isNotEmpty && dupDuration > totalDuration * 0.25) {
    dupIndices.clear();
    dupDuration = 0.0;
  }

  // Pass 1：紧致流（<= 30 块）单边短正片放宽 + 全尺寸目录前缀隔离。
  final picked = <int>{...dupIndices};
  final compact = nonEmpty.length <= 30;
  for (var pos = 1; pos < nonEmpty.length - 1; pos++) {
    final idx = nonEmpty[pos];
    if (picked.contains(idx)) continue;
    final cur = infos[idx];
    if (!_isAdShape(cur)) continue;
    final prevIdx = nonEmpty[pos - 1];
    final nextIdx = nonEmpty[pos + 1];
    // 相邻两块不重复命中（除非是已由精确重复 URI 确认的广告）。
    if (picked.contains(prevIdx) && !dupIndices.contains(prevIdx)) continue;

    final left = infos[prevIdx];
    final right = infos[nextIdx];
    final needLong = math.max(180.0, cur.duration * 3);
    final needShort = math.max(45.0, cur.duration * 2);

    final bothLong = left.duration >= needLong && right.duration >= needLong;
    final compactShortSide = compact &&
        ((left.duration >= needLong && right.duration >= needShort) ||
            (right.duration >= needLong && left.duration >= needShort));
    final dirIsolated = left.dirSig.isNotEmpty &&
        left.dirSig == right.dirSig &&
        cur.dirSig.isNotEmpty &&
        cur.dirSig != left.dirSig &&
        math.max(left.duration, right.duration) >= needLong;

    if (bothLong || compactShortSide || dirIsolated) {
      picked.add(idx);
    }
  }

  // 动态防过杀阈值：
  // - 最大允许段数按总时长浮动，每 5 分钟至多 1 段，范围 [6, 30]；
  // - 占比阈值短片（< 600s）放宽至 15%，常规 6%；
  // - 存在精确重复 URI 广告时豁免数量上限，保留 25% 总时长安全线。
  final maxPicked = (totalDuration / 300).ceil().clamp(6, 30);
  final maxTimeRatio = totalDuration < 600 ? 0.15 : 0.06;
  final adDuration = picked.fold<double>(0, (sum, i) => sum + infos[i].duration);
  final hasExactDupes = dupIndices.isNotEmpty;
  final nonDupCount = picked.length - dupIndices.length;

  final exceededCount =
      hasExactDupes ? nonDupCount > maxPicked : picked.length > maxPicked;
  final exceededRatio = hasExactDupes
      ? adDuration > totalDuration * 0.25
      : adDuration > totalDuration * maxTimeRatio;

  if (exceededCount || exceededRatio) {
    return HlsAdAnalysis(
      blocks: _blockList(infos, const {}),
      cuts: const [],
      duration: totalDuration,
      mainDuration: totalDuration,
      edgeAds: 0,
      rejected: true,
    );
  }

  final adMap = <int, HlsAdPlacement>{};
  for (final idx in picked) {
    if (idx == nonEmpty.first) {
      adMap[idx] = HlsAdPlacement.head;
    } else if (idx == nonEmpty.last) {
      adMap[idx] = HlsAdPlacement.tail;
    } else {
      adMap[idx] = HlsAdPlacement.middle;
    }
  }

  // Pass 2：签名 / 目录 / URI / 精确小数时长扩展 + 片尾交替创意物料识别。
  if (picked.isNotEmpty) {
    final adSigs = {for (final i in picked) _signature(infos[i])};
    final adDirs = {
      for (final i in picked)
        if (infos[i].dirSig.isNotEmpty) infos[i].dirSig,
    };
    final adUriKeys = {
      for (final i in picked)
        if (infos[i].uriKey.isNotEmpty) infos[i].uriKey,
    };
    final adExactDurs = [for (final i in picked) infos[i].duration];

    bool matchesAd(_ChunkInfo info, {required bool allowExactDur}) =>
        adSigs.contains(_signature(info)) ||
        (info.dirSig.isNotEmpty && adDirs.contains(info.dirSig)) ||
        (info.uriKey.isNotEmpty && adUriKeys.contains(info.uriKey)) ||
        (allowExactDur &&
            adExactDurs.any((d) => (d - info.duration).abs() <= 0.15));

    // Pass 2.1 非边缘块扩展：命中特征且任意一侧邻块为长正片（或命中路径特征）。
    for (var pos = 1; pos < nonEmpty.length - 1; pos++) {
      final idx = nonEmpty[pos];
      if (adMap.containsKey(idx)) continue;
      final cur = infos[idx];
      if (!_isAdShape(cur)) continue;
      if (!matchesAd(cur, allowExactDur: compact)) continue;

      final leftIdx = nonEmpty[pos - 1];
      final rightIdx = nonEmpty[pos + 1];
      final left = infos[leftIdx];
      final right = infos[rightIdx];
      final needLong = math.max(180.0, cur.duration * 3);
      final oneSideLong =
          (!adMap.containsKey(leftIdx) && left.duration >= needLong) ||
          (!adMap.containsKey(rightIdx) && right.duration >= needLong);
      final pathMatched =
          (cur.uriKey.isNotEmpty && adUriKeys.contains(cur.uriKey)) ||
          (cur.dirSig.isNotEmpty && adDirs.contains(cur.dirSig));
      if (oneSideLong || pathMatched) {
        adMap[idx] = HlsAdPlacement.middle;
        adSigs.add(_signature(cur));
        if (cur.dirSig.isNotEmpty) adDirs.add(cur.dirSig);
        if (cur.uriKey.isNotEmpty) adUriKeys.add(cur.uriKey);
        adExactDurs.add(cur.duration);
      }
    }

    // Pass 2.2 边缘块（片头 / 片尾）扩展。
    final headIdx = nonEmpty.first;
    final headNextIdx = nonEmpty[1];
    if (!adMap.containsKey(headIdx) && _isAdShape(infos[headIdx])) {
      final cur = infos[headIdx];
      final adj = infos[headNextIdx];
      final adjOk = !adMap.containsKey(headNextIdx) &&
          adj.duration >= math.max(45.0, cur.duration * 2);
      final pathOrExactMatch =
          (cur.uriKey.isNotEmpty && adUriKeys.contains(cur.uriKey)) ||
          (cur.dirSig.isNotEmpty && adDirs.contains(cur.dirSig)) ||
          (compact && adExactDurs.any((d) => (d - cur.duration).abs() <= 0.15));
      if (matchesAd(cur, allowExactDur: compact) && (adjOk || pathOrExactMatch)) {
        adMap[headIdx] = HlsAdPlacement.head;
      }
    }

    final tailIdx = nonEmpty.last;
    final tailPrevIdx = nonEmpty[nonEmpty.length - 2];
    if (!adMap.containsKey(tailIdx) && _isAdShape(infos[tailIdx])) {
      final cur = infos[tailIdx];
      final adj = infos[tailPrevIdx];
      final adjOk = !adMap.containsKey(tailPrevIdx) &&
          adj.duration >= math.max(45.0, cur.duration * 2);
      final pathOrExactMatch =
          (cur.uriKey.isNotEmpty && adUriKeys.contains(cur.uriKey)) ||
          (cur.dirSig.isNotEmpty && adDirs.contains(cur.dirSig)) ||
          (compact && adExactDurs.any((d) => (d - cur.duration).abs() <= 0.15));
      final alternatingTail = nonEmpty.length <= 24 &&
          !adMap.containsKey(tailPrevIdx) &&
          adj.duration >= 300.0 &&
          cur.duration >= 10.0 &&
          cur.duration <= 35.0 &&
          cur.segments <= 12 &&
          adExactDurs.any((d) => (cur.duration - d).abs() <= 5.0);

      if ((matchesAd(cur, allowExactDur: compact) && (adjOk || pathOrExactMatch)) ||
          alternatingTail) {
        adMap[tailIdx] = HlsAdPlacement.tail;
      }
    }

    // 二次检验 Pass 2 扩展后的总广告时长占比，确保整体安全上线不被突破。
    final finalAdDuration =
        adMap.keys.fold<double>(0, (sum, i) => sum + infos[i].duration);
    if (finalAdDuration >
        totalDuration * (hasExactDupes ? 0.25 : maxTimeRatio)) {
      return HlsAdAnalysis(
        blocks: _blockList(infos, const {}),
        cuts: const [],
        duration: totalDuration,
        mainDuration: totalDuration,
        edgeAds: 0,
        rejected: true,
      );
    }
  }

  final edgeAds = adMap.values
      .where((p) => p == HlsAdPlacement.head || p == HlsAdPlacement.tail)
      .length;

  // 正片分片在源视频里是连续编码的（PTS 从 0 递增，不含插播时长），
  // 所以广告在「原始时间轴」上的位置 = 它前面所有正片块时长之和。
  final blockStarts = List<double>.filled(blocks.length, 0);
  var dramaAccumulator = 0.0;
  for (var i = 0; i < blocks.length; i++) {
    blockStarts[i] = dramaAccumulator;
    if (!adMap.containsKey(i)) dramaAccumulator += infos[i].duration;
  }

  final cuts = <HlsAdCut>[
    for (final entry in adMap.entries)
      HlsAdCut(
        start: blockStarts[entry.key],
        end: blockStarts[entry.key] + infos[entry.key].duration,
        placement: entry.value,
        segments: infos[entry.key].segments,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));

  return HlsAdAnalysis(
    blocks: _blockList(infos, adMap),
    cuts: cuts,
    duration: totalDuration,
    mainDuration: dramaAccumulator,
    edgeAds: edgeAds,
    rejected: false,
  );
}

/// 「剪辑」：把判定为广告的块整块删掉，重新生成一份干净列表。
///
/// 拼接处保留一个 `#EXT-X-DISCONTINUITY`：分片是从不同时间点切开的，
/// 没有它播放器会按原 PTS 衔接而出现跳帧 / 时间轴错乱。
///
/// ⚠️ 切块方式必须与 [analyzeAdBlocks] 完全一致（表头留在第 0 块），
/// 否则 `analysis.blocks` 的广告标记会整体错位，把正片当广告删掉。
HlsCutPlaylist buildCutPlaylist(String text, HlsAdAnalysis analysis) {
  final lines = text.split(RegExp(r'\r?\n'));
  final ranges = splitAdBlockRanges(text);
  final hadEndList = hasEndListText(text);

  bool safeToCut(int index) {
    if (index < 0 || index >= analysis.blocks.length) return false;
    final block = analysis.blocks[index];
    if (!block.isAd) return false;
    return block.duration >= kAdCutMinDuration &&
        block.duration <= kAdCutMaxDuration &&
        block.segments <= kAdCutMaxSegments;
  }

  final out = <String>[];
  final cuts = <HlsAdCut>[];
  var cursor = 0.0;
  var removed = 0.0;
  var kept = 0;

  void appendPlaylistHeaders(int startLine, int endLine) {
    for (var i = startLine; i < endLine; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('#EXTINF')) break;
      if (_playlistGlobalHeaderPattern.hasMatch(trimmed)) {
        out.add(lines[i]);
      }
    }
  }

  for (var index = 0; index < ranges.length; index++) {
    final range = ranges[index];
    final info = _blockInfo(lines.sublist(range.start, range.end));
    final duration = info.duration;
    final start = cursor;
    cursor += duration;

    if (safeToCut(index)) {
      cuts.add(HlsAdCut(
        start: start,
        end: cursor,
        placement: analysis.blocks[index].placement ?? HlsAdPlacement.middle,
        segments: analysis.blocks[index].segments,
      ));
      removed += duration;
      // 第 0 块被整体删掉时，仅保留列表级全局头标签，绝不把广告块的 KEY/MAP 保留进输出。
      if (index == 0) {
        appendPlaylistHeaders(range.start, range.end);
      }
      continue;
    }

    // 跳过 0 分片空断流块（如头部/尾部紧跟的空 #EXT-X-DISCONTINUITY）：
    // 第 0 块若为空则只保留全局头标签且不计数，避免首尾产生多余断流标签。
    if (info.segments <= 0) {
      if (index == 0) {
        appendPlaylistHeaders(range.start, range.end);
      }
      continue;
    }

    // 块与块之间原本就有 discontinuity；剪掉中间块后仍要保留分界。
    if (kept > 0) out.add('#EXT-X-DISCONTINUITY');
    // ENDLIST 统一在末尾补一次，避免重复或落进被删的块里。
    for (var i = range.start; i < range.end; i++) {
      if (RegExp(r'^#EXT-X-ENDLIST', caseSensitive: false)
          .hasMatch(lines[i].trim())) {
        continue;
      }
      out.add(lines[i]);
    }
    kept++;
  }

  if (hadEndList) out.add('#EXT-X-ENDLIST');

  return HlsCutPlaylist(
    playlist: '${out.join('\n')}\n',
    cuts: cuts,
    removedSeconds: _round2(removed),
  );
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

/// 把「原始时间轴」的续播点换算成剪后时间轴上的位置。
///
/// 剪掉的是广告，用户上次看到的位置不该跟着前移：
/// - 完全落在某个被剪区间之前 → 减去该区间时长；
/// - 落在被剪区间内 → 退到该区间起点（用户看的是广告，重看正片开头更合理）；
/// - 之后同理累加。
Duration? shiftStartAfterCut(Duration? start, List<HlsAdCut> cuts) {
  if (start == null || cuts.isEmpty) return start;
  final seconds = start.inMilliseconds / Duration.millisecondsPerSecond;
  var removed = 0.0;
  for (final cut in cuts) {
    if (cut.end <= seconds) {
      removed += cut.duration;
      continue;
    }
    if (cut.start < seconds) removed += seconds - cut.start;
    break;
  }
  final shifted = seconds - removed;
  return Duration(
      milliseconds: ((shifted < 0 ? 0 : shifted) * 1000).round());
}

/// 把播放列表里的相对地址改成绝对地址（分片行 + `URI="..."` 标签 + master 变体行）。
///
/// 交给我们自己的本地代理之后，播放器的相对地址基准变成了 `127.0.0.1`，
/// 不绝对化就一个分片都拉不到。
String absolutizePlaylist(String text, Uri base) {
  String toAbsolute(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return raw;
    if (RegExp(r'^(https?:)?//', caseSensitive: false).hasMatch(value)) return raw;
    if (value.startsWith('data:')) return raw;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return raw;
    }
  }

  final out = <String>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      out.add('');
      continue;
    }
    if (trimmed.startsWith('#')) {
      // #EXT-X-KEY / #EXT-X-MAP / #EXT-X-MEDIA / #EXT-X-I-FRAME-STREAM-INF 里的 URI
      out.add(line.replaceAllMapped(
        RegExp('URI="([^"]*)"'),
        (match) => 'URI="${toAbsolute(match.group(1) ?? '')}"',
      ));
      continue;
    }
    out.add(toAbsolute(trimmed));
  }
  return out.join('\n');
}

/// 取出 master 列表里的每个变体地址（按出现顺序，已按 [base] 解析）。
List<Uri> masterVariantUris(String text, Uri base) {
  final uris = <Uri>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    try {
      final uri = base.resolve(trimmed);
      if (uri.scheme == 'http' || uri.scheme == 'https') uris.add(uri);
    } catch (_) {
      // 解析不了的变体行直接跳过，不阻断其它变体。
    }
  }
  return uris;
}

/// 把 master 列表里的每个变体行替换成 [replace] 给出的本地地址。
///
/// 只改「变体行」与 `#EXT-X-I-FRAME-STREAM-INF` 的 URI；
/// `#EXT-X-MEDIA`（音轨 / 字幕）、`#EXT-X-KEY`、`#EXT-X-MAP` 保持绝对地址直连，
/// 这些子清单里没有插播广告，没必要绕一圈。
String rewriteMasterVariants(
  String text,
  Uri base,
  String Function(Uri variant, int index) replace,
) {
  final out = <String>[];
  var index = 0;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      if (trimmed.startsWith('#EXT-X-I-FRAME-STREAM-INF')) {
        out.add(line.replaceAllMapped(RegExp('URI="([^"]*)"'), (match) {
          final raw = match.group(1) ?? '';
          final absolute = base.resolve(raw).toString();
          return 'URI="${replace(Uri.parse(absolute), index++)}"';
        }));
        continue;
      }
      out.add(line);
      continue;
    }
    try {
      out.add(replace(base.resolve(trimmed), index++));
    } catch (_) {
      out.add(line);
    }
  }
  return out.join('\n');
}
