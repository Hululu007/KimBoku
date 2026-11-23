import 'dart:async';
import 'dart:io';

import 'cross_site_models.dart';

typedef SocketConnector = Future<dynamic> Function(
  dynamic host,
  int port, {
  Duration? timeout,
});

/// 跨站换源体检探活工具。
///
/// 遵循原则：
/// - 对媒体 URL 的 host:port 做真实的 **TCP connect**，建连耗时即为 ping 值；
/// - 绝不能用 HTTP HEAD 判活（CDN 对 HEAD 易返回 404/502，对 GET 正常）；
/// - 判定：ok / 未测 / fail（原因短句）；
/// - 排序：ok 按 ping 升序 -> 未测（保持搜索顺序）-> fail。
class CrossSiteHealthProbe {
  static const Duration defaultTimeout = Duration(seconds: 6);

  final SocketConnector _socketConnect;

  CrossSiteHealthProbe({SocketConnector? socketConnector})
      : _socketConnect = socketConnector ?? _defaultConnect;

  static Future<dynamic> _defaultConnect(
    dynamic host,
    int port, {
    Duration? timeout,
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return socket;
  }

  /// 对解析后的真实媒体 URL 发起 TCP 建连测试。
  Future<CandidateProbeResult> probeMediaUrl(
    String mediaUrl, {
    Duration timeout = defaultTimeout,
  }) async {
    final trimmed = mediaUrl.trim();
    if (trimmed.isEmpty) {
      return const CandidateProbeResult(
        status: ProbeStatus.fail,
        failReason: '媒体地址为空',
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return const CandidateProbeResult(
        status: ProbeStatus.fail,
        failReason: '无效地址',
      );
    }

    final host = uri.host;
    final port = uri.hasPort
        ? uri.port
        : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);

    final stopwatch = Stopwatch()..start();
    try {
      final res = await _socketConnect(host, port, timeout: timeout);
      stopwatch.stop();
      if (res is Socket) {
        res.destroy();
      }
      final ping = stopwatch.elapsedMilliseconds;
      return CandidateProbeResult(
        status: ProbeStatus.ok,
        pingMs: ping,
        resolvedMediaUrl: trimmed,
      );
    } on TimeoutException {
      return const CandidateProbeResult(
        status: ProbeStatus.fail,
        failReason: '连接超时',
      );
    } on SocketException catch (e) {
      return CandidateProbeResult(
        status: ProbeStatus.fail,
        failReason: '建连失败: ${e.osError?.message ?? e.message}',
      );
    } catch (e) {
      return CandidateProbeResult(
        status: ProbeStatus.fail,
        failReason: '异常: $e',
      );
    }
  }

  /// 候选列表排序规则：
  /// 1. ok 优先，按 ping 升序排列
  /// 2. 未测次之，保持搜索返回的先后顺序
  /// 3. fail 置于末尾（行置灰但仍可点）
  static List<CrossSiteCandidate> sortCandidates(
    List<CrossSiteCandidate> candidates, {
    bool deduplicateBySite = false,
  }) {
    final list = List<CrossSiteCandidate>.of(candidates);
    // 使用带稳定下标的比对
    final indexed = list.asMap().entries.toList();

    indexed.sort((aEntry, bEntry) {
      final a = aEntry.value;
      final b = bEntry.value;
      final statusA = a.probe.status;
      final statusB = b.probe.status;

      // 1. ok 组内部按 ping 升序
      if (statusA == ProbeStatus.ok && statusB == ProbeStatus.ok) {
        final pingA = a.probe.pingMs ?? 999999;
        final pingB = b.probe.pingMs ?? 999999;
        final cmp = pingA.compareTo(pingB);
        return cmp != 0 ? cmp : aEntry.key.compareTo(bEntry.key);
      }
      if (statusA == ProbeStatus.ok) return -1;
      if (statusB == ProbeStatus.ok) return 1;

      // 2. 未测保持原相对次序
      if (statusA == ProbeStatus.untested && statusB == ProbeStatus.untested) {
        return aEntry.key.compareTo(bEntry.key);
      }
      if (statusA == ProbeStatus.untested) return -1;
      if (statusB == ProbeStatus.untested) return 1;

      // 3. fail 组放末尾，保持相对次序
      return aEntry.key.compareTo(bEntry.key);
    });

    final sorted = indexed.map((e) => e.value).toList();
    if (!deduplicateBySite) {
      return sorted;
    }

    // 4. 同源去重：每个站点（无论 key 还是展示名称）至多只保留 1 条最优记录（ok 优先、低延迟优先）
    final seenKeys = <String>{};
    final seenNames = <String>{};
    final unique = <CrossSiteCandidate>[];

    for (final c in sorted) {
      final key = c.site.key.trim();
      final name = c.site.name.trim();
      final hasKey = key.isNotEmpty;
      final hasName = name.isNotEmpty;

      if (hasKey && seenKeys.contains(key)) continue;
      if (hasName && seenNames.contains(name)) continue;

      if (hasKey) seenKeys.add(key);
      if (hasName) seenNames.add(name);
      unique.add(c);
    }

    return unique;
  }
}
