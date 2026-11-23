import 'package:flutter_test/flutter_test.dart';
import 'package:xiugou_tv/core/player/title_keyword_cleaner.dart';

void main() {
  group('精准片名匹配测试', () {
    const target = '我不好惹3';

    test('目标: 我不好惹3，必须精准匹配以下真源', () {
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹 3'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3 4K'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3[国语中字]'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3 HD'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹 第三季'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹 第3部'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3：贝基之怒'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3: 贝基之怒'), isTrue);
    });

    test('目标: 我不好惹3，必须坚决拒绝以下假源/解说/其他部', () {
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹[电影解说]'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹电影解说'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹'), isFalse); // 第1部
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹2'), isFalse); // 第2部
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹4'), isFalse); // 第4部
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹预告片'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不好惹3预告片'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: target, candidateTitle: '我不是药神'), isFalse);
    });

    test('目标为无序号片名时的匹配规则', () {
      const singleTarget = '狂飙';
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙 4K超清'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙[全集]'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '《狂飙》'), isTrue);

      // 拒绝解说和续集
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙[电视剧解说]'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙解说'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙2'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: singleTarget, candidateTitle: '狂飙第二季'), isFalse);
    });

    test('特殊片名：4位历史数字与2位部数序号测试', () {
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '大明王朝1566', candidateTitle: '大明王朝1566 4K'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '大明王朝1566', candidateTitle: '大明王朝1566[国语]'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '大明王朝1566', candidateTitle: '大明王朝1566解说'), isFalse);

      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '速度与激情10', candidateTitle: '速度与激情10 4K'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '速度与激情10', candidateTitle: '速度与激情9'), isFalse);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '速度与激情10', candidateTitle: '速度与激情'), isFalse);

      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '死有对证', candidateTitle: '死有对证粤语'), isTrue);
      expect(TitleKeywordCleaner.isExactTitleMatch(targetTitle: '死有对证粤语', candidateTitle: '死有对证'), isTrue);
    });
  });
}
