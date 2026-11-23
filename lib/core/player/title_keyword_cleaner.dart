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

  /// 衍生非正片内容标记（解说/影评/预告/花絮/片段/速看等）
  static final RegExp _contentMarkerPattern = RegExp(
    r'解说|电影解说|影评|吐槽|杂谈|速看|混剪|片段|盘点|幕后|特辑|花絮|预告|试看|原声|主题曲|路演|采访|几分钟',
    caseSensitive: false,
  );

  /// 检查标题是否包含解说/预告等衍生非正片标记
  static bool containsContentMarker(String title) {
    if (title.trim().isEmpty) return false;
    return _contentMarkerPattern.hasMatch(title);
  }

  static const Map<String, int> _chineseDigits = <String, int>{
    '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3,
    '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  };

  static int? _parseChineseNumeral(String value) {
    if (value == '十') return 10;
    final tenIndex = value.indexOf('十');
    if (tenIndex >= 0) {
      final left = value.substring(0, tenIndex);
      final right = value.substring(tenIndex + 1);
      final tens = left.isEmpty ? 1 : _chineseDigits[left];
      final ones = right.isEmpty ? 0 : _chineseDigits[right];
      if (tens == null || ones == null) return null;
      return tens * 10 + ones;
    }
    var result = 0;
    for (final char in value.split('')) {
      final digit = _chineseDigits[char];
      if (digit == null) return null;
      result = result * 10 + digit;
    }
    return result;
  }

  /// 提取季号/部数/序号（如「我不好惹3」中的 3，「庆余年 第二季」中的 2，「钢铁侠3」中的 3）
  static int? extractInstallmentNumber(String rawTitle) {
    if (rawTitle.trim().isEmpty) return null;
    final text = rawTitle.trim();

    // 1. 中文形式：第X季、第X部
    final cnSeasonMatch = RegExp(r'第\s*([0-9零〇一二两三四五六七八九十]{1,4})\s*[季部]').firstMatch(text);
    if (cnSeasonMatch != null) {
      final val = cnSeasonMatch.group(1)!;
      final num = int.tryParse(val);
      if (num != null) return num;
      return _parseChineseNumeral(val);
    }

    // 2. 英文形式：Season X, S2, Part X
    final enSeasonMatch = RegExp(r'(?:\bseason|\bs|\bpart)\s*(\d{1,3})\b', caseSensitive: false).firstMatch(text);
    if (enSeasonMatch != null) {
      return int.tryParse(enSeasonMatch.group(1)!);
    }

    // 3. 罗马数字：I, II, III, IV, V, VI, VII, VIII, IX, X
    final romanMatch = RegExp(r'(?:^|[\s_—–\-:：])(I{1,3}|IV|V|VI{1,3}|IX|X)(?:$|[\s_—–\-:：\[\]\(\)【】])').firstMatch(text);
    if (romanMatch != null) {
      const romanMap = {
        'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5,
        'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10,
      };
      final r = romanMap[romanMatch.group(1)!.toUpperCase()];
      if (r != null) return r;
    }

    // 4. 清理干扰（年份、括号、分辨率如 4K/1080P/720P）后，检查片名主体尾部或独立出现的 1~2 位阿拉伯数字
    var cleaned = text.replaceAll(RegExp(r'\b(19\d{2}|20\d{2})\b'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\b\d+[kKpP]\b'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'4[kK]|8[kK]|1080[pP]|720[pP]|2160[pP]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}|（[^）]*）|【[^】]*】'), ' ');
    if (cleaned.contains(RegExp(r'[:：]|\s+[-_]\s+'))) {
      cleaned = cleaned.split(RegExp(r'[:：]|\s+[-_]\s+')).first;
    }
    cleaned = cleaned.replaceAll(RegExp(r'(?:国语|粤语|英语|中字|双字|原画|超清|高清|蓝光|未删减版?|正片|全集|HD|BD|TC|TS|CAM)\s*$', caseSensitive: false), ' ');

    // 匹配尾部的单个或两位数字（如 我不好惹3，我不好惹 3，叶问4，封神 2）
    final trailingNumMatch = RegExp(r'(?<!\d)(\d{1,2})\s*$').firstMatch(cleaned.trim());
    if (trailingNumMatch != null) {
      return int.tryParse(trailingNumMatch.group(1)!);
    }

    // 检查中文数字（如 封神第二部、大话西游三、叶问四）
    final trailingCnNumMatch = RegExp(r'([一二两三四五六七八九十])\s*$').firstMatch(cleaned.trim());
    if (trailingCnNumMatch != null) {
      return _chineseDigits[trailingCnNumMatch.group(1)!];
    }

    return null;
  }

  /// 提取基础片名（剥离括号、副标题、季号/序号、年份、标点空白转小写）
  static String extractBaseTitle(String rawTitle) {
    var working = rawTitle.trim();
    final bookMatch = RegExp(r'《([^》]+)》').firstMatch(working);
    if (bookMatch != null && bookMatch.group(1)!.trim().isNotEmpty) {
      working = bookMatch.group(1)!.trim();
    }
    working = working.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}|（[^）]*）|【[^】]*】|〔[^〕]*〕'), ' ');
    if (working.contains(RegExp(r'[:：]|\s+[-_]\s+|[/|]'))) {
      working = working.split(RegExp(r'[:：]|\s+[-_]\s+|[/|]')).first;
    }
    working = working.replaceAll(RegExp(r'\b(19\d{2}|20\d{2})\b'), ' ');
    working = working.replaceAll(RegExp(r'第\s*([0-9零〇一二两三四五六七八九十]{1,4})\s*[季部]'), ' ');
    working = working.replaceAll(RegExp(r'(?:\bseason|\bs|\bpart)\s*(\d{1,3})\b', caseSensitive: false), ' ');
    working = working.replaceAll(RegExp(r'(?:1080[pP]|720[pP]|4[kK]|8[kK]|2160[pP]|HD|BD|TC|TS|CAM)', caseSensitive: false), ' ');
    working = working.replaceAll(RegExp(r'(?:蓝光|超清|高清|标清|原画|枪版|抢先版|国语|粤语|英语|韩语|日语|中字|双字|配音版|未删减版?|加长版?|重制版?|修复版?|自制|正片|全集|完结)'), ' ');
    working = working.trim().replaceAll(RegExp(r'(?<!\d)(\d{1,2})\s*$'), ' ');
    working = working.trim().replaceAll(RegExp(r'([一二两三四五六七八九十])\s*$'), ' ');
    return working.toLowerCase().replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]+'), '');
  }

  /// 精准片名匹配（部数/季号/基础片名强一致，拒绝衍生解说与不同续集）
  static bool isExactTitleMatch({
    required String targetTitle,
    required String candidateTitle,
  }) {
    // 1. 衍生内容检查：目标没有衍生标记，候选含有衍生标记，直接拒绝！
    final targetHasMarker = containsContentMarker(targetTitle);
    final candidateHasMarker = containsContentMarker(candidateTitle);
    if (!targetHasMarker && candidateHasMarker) {
      return false;
    }

    // 2. 序号/季号强一致性校验
    final targetNumber = extractInstallmentNumber(targetTitle);
    final candidateNumber = extractInstallmentNumber(candidateTitle);
    if (targetNumber != candidateNumber) {
      return false;
    }

    // 3. 基础片名精确匹配
    final targetBase = extractBaseTitle(targetTitle);
    final candidateBase = extractBaseTitle(candidateTitle);

    if (targetBase.isEmpty || candidateBase.isEmpty) return false;
    return targetBase == candidateBase;
  }
}
