import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 分享页与网页播放解析器。
///
/// 针对部分返回网页而非直接媒体直链的站点：
/// 带桌面 UA 与 Referer 请求页面，依次匹配：
/// 1. const url = '...' 赋值
/// 2. 绝对路径 https?://...m3u8
/// 3. 相对路径 /...m3u8（使用页面 Base URI 补全）
/// 并保持 200 条 LRU 内存缓存。
class SharePageResolver {
  static const int maxCacheSize = 200;
  static const Duration requestTimeout = Duration(seconds: 8);
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final Map<String, String> _lruCache = <String, String>{};

  SharePageResolver();

  /// 缓存数量（测试与监控用）
  int get cacheCount => _lruCache.length;

  /// 清空缓存
  void clearCache() => _lruCache.clear();

  /// 判断地址是否可能是网页分享页
  static bool isLikelySharePage(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return false;
    // 如果直接以媒体扩展名结尾且不带明显播放器查询参数，直接视为媒体直链
    final uri = Uri.tryParse(lower);
    final path = uri?.path ?? lower;
    if (path.endsWith('.m3u8') ||
        path.endsWith('.mp4') ||
        path.endsWith('.flv') ||
        path.endsWith('.mkv')) {
      return false;
    }
    return true;
  }

  /// 从页面 HTML 内容中抽取真实 m3u8 地址
  static String? extractM3u8FromHtml(String html, {required String pageUrl}) {
    if (html.isEmpty) return null;

    // 解除转义反斜杠 \/ -> /
    final unescaped = html.replaceAll(r'\/', '/');

    // 1. const url = '...' 赋值或 JSON 中的 "url": "..."
    final jsVarRegex = RegExp(
      r'''(?:const|var|let)\s+url\s*=\s*['"]([^'"]+\.m3u8[^'"]*)['"]|["']url["']\s*:\s*["']([^'"]+\.m3u8[^'"]*)["']''',
      caseSensitive: false,
    );
    final jsMatch = jsVarRegex.firstMatch(unescaped);
    if (jsMatch != null) {
      final raw = jsMatch.group(1) ?? jsMatch.group(2);
      if (raw != null && raw.trim().isNotEmpty) {
        return _resolveUrl(raw.trim(), pageUrl);
      }
    }

    // 2. 绝对地址：https?://...m3u8
    final absRegex = RegExp(r'https?://[^\s"<>]+\.m3u8[^\s"<>]*', caseSensitive: false);
    final absMatch = absRegex.firstMatch(unescaped);
    if (absMatch != null) {
      return absMatch.group(0);
    }

    // 3. 相对路径：/...m3u8
    final relRegex = RegExp(r'''['"](/[^\s"<>]+?\.m3u8[^\s"<>]*?)['"]''', caseSensitive: false);
    final relMatch = relRegex.firstMatch(unescaped);
    if (relMatch != null) {
      final rel = relMatch.group(1);
      if (rel != null && rel.isNotEmpty) {
        return _resolveUrl(rel, pageUrl);
      }
    }

    return null;
  }

  static String _resolveUrl(String extracted, String baseUrl) {
    if (extracted.startsWith('http://') || extracted.startsWith('https://')) {
      return extracted;
    }
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(extracted).toString();
    } catch (_) {
      return extracted;
    }
  }

  /// 解析可能为分享页的播放地址。
  ///
  /// 若判定为分享页，带 UA / Referer 发起 GET 请求并提取 m3u8；
  /// 若提取成功或已有缓存直接返回真实地址，否则返回原地址。
  Future<String> resolveIfSharePage(String playUrl) async {
    final trimmed = playUrl.trim();
    if (!isLikelySharePage(trimmed)) {
      return trimmed;
    }

    // 查 LRU 缓存
    if (_lruCache.containsKey(trimmed)) {
      final cached = _lruCache[trimmed]!;
      _lruCache.remove(trimmed);
      _lruCache[trimmed] = cached;
      return cached;
    }

    HttpClient? client;
    try {
      final uri = Uri.parse(trimmed);
      client = HttpClient();
      client.connectionTimeout = requestTimeout;

      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers.set('User-Agent', defaultUserAgent);
      request.headers.set(
        'Referer',
        uri.hasScheme ? '${uri.scheme}://${uri.host}' : trimmed,
      );

      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 400) {
        final body = await response.transform(utf8.decoder).join();
        final extracted = extractM3u8FromHtml(body, pageUrl: trimmed);
        if (extracted != null && extracted.isNotEmpty) {
          _putCache(trimmed, extracted);
          return extracted;
        }
      }
    } catch (_) {
      // 异常时退回原 url
    } finally {
      client?.close();
    }

    return trimmed;
  }

  void _putCache(String key, String value) {
    if (_lruCache.length >= maxCacheSize) {
      _lruCache.remove(_lruCache.keys.first);
    }
    _lruCache[key] = value;
  }
}
