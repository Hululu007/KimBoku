/// 跨站换源集名归一化与映射工具。
///
/// 支持：第3集 / 03 / 3 / EP03 / S01E03 / 第三集 / 第03话 / 03期
/// 并处理零填充等价；若无法通过集名映射，则退回目标线路的默认下标顺序。
class EpisodeNameMapper {
  EpisodeNameMapper._();

  static const Map<String, int> _chineseDigits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };

  /// 解析中文数字（支持 1~999，如「三」「十」「二十三」「一百零五」）
  static int? parseChineseNumber(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;

    // 单个字符
    if (clean.length == 1) {
      if (_chineseDigits.containsKey(clean)) {
        return _chineseDigits[clean];
      }
      if (clean == '十') return 10;
      if (clean == '百') return 100;
      return null;
    }

    var total = 0;
    var currentNumber = 0;

    // 逐字解析
    for (var i = 0; i < clean.length; i++) {
      final char = clean[i];
      if (_chineseDigits.containsKey(char)) {
        currentNumber = _chineseDigits[char]!;
      } else if (char == '十') {
        if (currentNumber == 0) {
          total += 10;
        } else {
          total += currentNumber * 10;
          currentNumber = 0;
        }
      } else if (char == '百') {
        total += (currentNumber == 0 ? 1 : currentNumber) * 100;
        currentNumber = 0;
      } else if (char == '千') {
        total += (currentNumber == 0 ? 1 : currentNumber) * 1000;
        currentNumber = 0;
      }
    }
    total += currentNumber;
    return total > 0 ? total : null;
  }

  /// 从集名中提取整数集号。
  ///
  /// 返回集号（1 基）；未能解析出任何集号时返回 null。
  static int? extractEpisodeNumber(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    // 1. 纯数字："03", "3", " 12 "
    final pureDigitMatch = RegExp(r'^\s*(\d+)\s*$').firstMatch(name);
    if (pureDigitMatch != null) {
      return int.tryParse(pureDigitMatch.group(1)!);
    }

    // 2. S01E03 / s1e3 / EP03 / ep3
    final seMatch = RegExp(r'(?:[Ss]\d+)?\s*[Ee][Pp]?\s*(\d+)', caseSensitive: false).firstMatch(name);
    if (seMatch != null) {
      return int.tryParse(seMatch.group(1)!);
    }

    // 3. 第3集 / 第03话 / 第3期 / 3集 / 03话
    final numEpMatch = RegExp(r'(?:第\s*)?(\d+)\s*(?:集|话|期|回)').firstMatch(name);
    if (numEpMatch != null) {
      return int.tryParse(numEpMatch.group(1)!);
    }

    // 4. "第3"
    final diNumMatch = RegExp(r'^第\s*(\d+)').firstMatch(name);
    if (diNumMatch != null) {
      return int.tryParse(diNumMatch.group(1)!);
    }

    // 5. 中文数字："第三集", "第十话", "第二十三集", "第105集"
    final cnEpMatch = RegExp(r'第\s*([一二三四五六七八九十百千零〇两]+)\s*(?:集|话|期|回)?').firstMatch(name);
    if (cnEpMatch != null) {
      final cnParsed = parseChineseNumber(cnEpMatch.group(1)!);
      if (cnParsed != null) return cnParsed;
    }

    // 6. 尾部数字："剧名 03", "名侦探柯南 1002"
    final trailingNumMatch = RegExp(r'\b(\d+)\b').allMatches(name);
    if (trailingNumMatch.isNotEmpty) {
      return int.tryParse(trailingNumMatch.last.group(1)!);
    }

    return null;
  }

  /// 归一化集名标识（用于哈希比较或日志输出）
  static String normalizeEpisodeKey(String rawName) {
    final num = extractEpisodeNumber(rawName);
    if (num != null) return 'E$num';
    return rawName.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// 将目标集名和目标集下标映射到候选剧集列表中。
  ///
  /// 返回匹配的候选列表索引（0-based）；找不到时退回 [targetIndex] 或 0。
  static int mapEpisodeIndex({
    required String targetName,
    required int targetIndex,
    required List<String> candidateEpisodeNames,
  }) {
    if (candidateEpisodeNames.isEmpty) return 0;

    final targetClean = targetName.trim().toLowerCase();

    // 1. 尝试完全匹配（忽略空白与大小写）
    for (var i = 0; i < candidateEpisodeNames.length; i++) {
      if (candidateEpisodeNames[i].trim().toLowerCase() == targetClean) {
        return i;
      }
    }

    // 2. 提取集号并比较（零填充等价：03 == 3 == 第三集 == EP03）
    final targetNum = extractEpisodeNumber(targetName);
    if (targetNum != null) {
      for (var i = 0; i < candidateEpisodeNames.length; i++) {
        final candNum = extractEpisodeNumber(candidateEpisodeNames[i]);
        if (candNum != null && candNum == targetNum) {
          return i;
        }
      }
    }

    // 3. 退回默认顺序：如果 targetIndex 合法在候选范围之内，直接使用 targetIndex
    if (targetIndex >= 0 && targetIndex < candidateEpisodeNames.length) {
      return targetIndex;
    }

    // 4. 越界时兜底使用第 0 集
    return 0;
  }
}
