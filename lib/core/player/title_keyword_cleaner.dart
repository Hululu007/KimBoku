/// 跨站换源片名清洗与规范化工具。
class TitleKeywordCleaner {
  TitleKeywordCleaner._();

  /// 4 位发行年份正则（1900-2099）
  static final RegExp _yearRegex = RegExp(r'\b(19\d{2}|20\d{2})\b');

  /// 括号匹配（含各种全半角括号）
  static final RegExp _bracketRegex = RegExp(
    r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}|（[^）]*）|【[^】]*】|〔[^〕]*〕',
  );

  /// 常见分隔符（/、|、以及带空格的 - 或 _）
  static final RegExp _separatorRegex = RegExp(r'[/|]|\s+[-_]\s+');

  /// 尾部或修饰性常见质量/版本/语言/集数标记
  static final List<RegExp> _trailingPatterns = [
    RegExp(r'(?:更新至|更新到|全)\s*\d+\s*集?', caseSensitive: false),
    RegExp(r'第?\s*\d+\s*集全?', caseSensitive: false),
    RegExp(r'(?:1080[pP]|720[pP]|4[kK]|2160[pP]|HD|BD|TC|TS|CAM)', caseSensitive: false),
    RegExp(r'(?:蓝光|超清|高清|标清|原画|枪版|抢先版)'),
    RegExp(r'(?:国语|粤语|英语|韩语|日语|中字|双字|配音版)'),
    RegExp(r'(?:未删减版?|加长版?|重制版?|修复版?|自制|正片|全集|完结)'),
  ];

  /// 清洗片名用于跨站搜索：
  /// - 只用「片名」
  /// - 去掉括号块
  /// - 按分隔符取首段
  /// - 剥掉尾部 HD/1080P/国语/全集/更新至N集 之类标记
  /// - **保留年份**
  static String cleanSearchKeyword(String rawTitle) {
    if (rawTitle.trim().isEmpty) return '';

    // 1. 如果有书名号《...》，先提取书名号中的主要片名
    var working = rawTitle.trim();
    final bookMatch = RegExp(r'《([^》]+)》').firstMatch(working);
    if (bookMatch != null && bookMatch.group(1)!.trim().isNotEmpty) {
      working = bookMatch.group(1)!.trim();
    }

    // 2. 检测并提取年份（如果在括号中，避免被整体剥除）
    String? detectedYear;
    final bracketMatches = _bracketRegex.allMatches(working);
    for (final match in bracketMatches) {
      final text = match.group(0)!;
      final yearMatch = _yearRegex.firstMatch(text);
      if (yearMatch != null) {
        detectedYear = yearMatch.group(1);
        break;
      }
    }
    // 如果括号里没有年份，检查整句是否包含明确年份
    if (detectedYear == null) {
      final yearMatch = _yearRegex.firstMatch(working);
      if (yearMatch != null) {
        detectedYear = yearMatch.group(1);
      }
    }

    // 3. 去掉括号块
    working = working.replaceAll(_bracketRegex, ' ');

    // 4. 按分隔符取首段
    if (_separatorRegex.hasMatch(working)) {
      final parts = working.split(_separatorRegex);
      if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
        working = parts.first.trim();
      }
    }

    // 5. 剥掉尾部各种标记
    bool stripped;
    do {
      stripped = false;
      working = working.trim();
      for (final pattern in _trailingPatterns) {
        final match = pattern.firstMatch(working);
        if (match != null && match.end >= working.length - 2) {
          working = working.substring(0, match.start).trim();
          stripped = true;
        }
      }
      // 去除尾部标点
      working = working.replaceAll(RegExp(r'[\s\-_\.:：/]+$'), '').trim();
    } while (stripped && working.isNotEmpty);

    // 6. 如果提取出了年份，且清洗后的片名中尚未包含该年份，则追加年份
    if (detectedYear != null && !working.contains(detectedYear)) {
      if (working.isNotEmpty) {
        working = '$working $detectedYear';
      } else {
        working = detectedYear;
      }
    }

    // 7. 合并多余空白
    working = working.replaceAll(RegExp(r'\s+'), ' ').trim();
    return working.isNotEmpty ? working : rawTitle.trim();
  }

  /// 规范化片名（用于生成缓存 key：去除所有标点、空白，转小写）
  static String normalizeTitle(String rawTitle) {
    final cleaned = cleanSearchKeyword(rawTitle);
    return cleaned
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+'), '');
  }
}
