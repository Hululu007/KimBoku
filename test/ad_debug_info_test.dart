import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiugou_tv/core/player/ad_filter_debug.dart';
import 'package:xiugou_tv/core/player/hls_ad_filter.dart';
import 'package:xiugou_tv/core/player/models/player_state.dart';
import 'package:xiugou_tv/core/player/player_engine.dart';
import 'package:xiugou_tv/ui/desktop/player/ad_debug_panel.dart';

class _FakePlayerEngine extends PlayerEngine {
  final ValueNotifier<AdFilterDebugInfo?> _adFilterDebug =
      ValueNotifier<AdFilterDebugInfo?>(null);

  @override
  ValueListenable<AdFilterDebugInfo?> get adFilterDebug => _adFilterDebug;

  void setDebugInfo(AdFilterDebugInfo? info) {
    _adFilterDebug.value = info;
  }

  @override
  Future<void> play(MediaPlaySpec spec) async {
    _adFilterDebug.value = null; // 换集 / 起播时清空
  }

  @override
  Future<void> stop() async {
    _adFilterDebug.value = null;
  }

  @override
  Duration get position => Duration.zero;

  @override
  Stream<Duration> get positionStream => Stream.value(Duration.zero);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AdFilterDebugInfo', () {
    test('完整信息可正确导出报告文本', () {
      const info = AdFilterDebugInfo(
        title: '测试剧集 第 1 集',
        sourceHost: 'example.com',
        proxyHost: '127.0.0.1:54321',
        outcome: AdFilterOutcome.filtered,
        cuts: [
          HlsAdCut(start: 10.0, end: 25.0, placement: HlsAdPlacement.middle, segments: 3),
        ],
        blocks: [
          HlsAdBlock(duration: 10.0, segments: 2, isAd: false),
          HlsAdBlock(duration: 15.0, segments: 3, isAd: true, placement: HlsAdPlacement.middle),
          HlsAdBlock(duration: 100.0, segments: 20, isAd: false),
        ],
        sourceDuration: 125.0,
        filteredDuration: 110.0,
        cutCount: 1,
        removedSeconds: 15.0,
        shiftedStart: Duration(seconds: 5),
        reason: '成功剪除 1 处插播广告',
      );

      final report = info.toReportText();
      expect(report, contains('测试剧集 第 1 集'));
      expect(report, contains('example.com'));
      expect(report, contains('127.0.0.1:54321'));
      expect(report, contains('已剪辑'));
      expect(report, contains('0:10 – 0:25'));
      expect(report, contains('3片'));
      expect(report, contains('成功剪除 1 处插播广告'));
    });

    test('换集/起播时 adFilterDebug 被正确清空', () async {
      final engine = _FakePlayerEngine();
      engine.setDebugInfo(const AdFilterDebugInfo(
        outcome: AdFilterOutcome.filtered,
        sourceHost: 'example.com',
        cuts: [],
        blocks: [],
        sourceDuration: 100.0,
        filteredDuration: 90.0,
      ));

      expect(engine.adFilterDebug.value, isNotNull);
      expect(engine.adFilterDebug.value?.outcome, AdFilterOutcome.filtered);

      // 换集播放第 2 集
      await engine.play(const MediaPlaySpec(
        url: 'http://example.com/ep2.m3u8',
        title: '第 2 集',
      ));

      expect(engine.adFilterDebug.value, isNull,
          reason: '起播新单集时必须清空上一集的广告调试数据');
    });

    testWidgets('AdDebugPanel 正常渲染复制按钮与关闭按钮', (tester) async {
      final engine = _FakePlayerEngine();
      engine.setDebugInfo(const AdFilterDebugInfo(
        title: '测试剧集 第 1 集',
        sourceHost: 'example.com',
        proxyHost: '127.0.0.1:54321',
        outcome: AdFilterOutcome.filtered,
        cuts: [
          HlsAdCut(start: 10.0, end: 25.0, placement: HlsAdPlacement.middle, segments: 3),
        ],
        blocks: [
          HlsAdBlock(duration: 10.0, segments: 2, isAd: false),
          HlsAdBlock(duration: 15.0, segments: 3, isAd: true, placement: HlsAdPlacement.middle),
        ],
        sourceDuration: 125.0,
        filteredDuration: 110.0,
        cutCount: 1,
        removedSeconds: 15.0,
        reason: '成功剪除 1 处插播广告',
      ));

      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdDebugPanel(
            engine: engine,
            onClose: () => closed = true,
          ),
        ),
      ));

      expect(find.text('广告调试'), findsOneWidget);
      expect(find.text('已剪辑'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);

      // 点击复制
      await tester.ensureVisible(find.text('复制'));
      await tester.tap(find.text('复制'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('已复制'), findsOneWidget);

      // 点击右上角关闭
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });
  });
}
