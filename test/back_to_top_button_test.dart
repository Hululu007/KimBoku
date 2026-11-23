import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiugou_tv/ui/desktop/catalog/back_to_top_button.dart';

void main() {
  group('BackToTopButton 悬浮回到顶部按钮测试', () {
    testWidgets('滚动未超过阈值时不显示，超过阈值后显示，点击滚回顶部', (tester) async {
      final controller = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemBuilder: (_, index) => SizedBox(
                    height: 50,
                    child: Text('Item $index'),
                  ),
                ),
                Positioned(
                  right: 56,
                  bottom: 72,
                  child: BackToTopButton(controller: controller),
                ),
              ],
            ),
          ),
        ),
      );

      // 初始状态：未滚动，按钮不可见
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      // 向下滚动 150px (未超过 threshold 200)
      controller.jumpTo(150);
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      // 向下滚动 300px (超过 threshold 200)
      controller.jumpTo(300);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      // 点击回到顶部
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      // 验证已滚回顶部 (offset == 0)
      expect(controller.offset, equals(0.0));

      // 验证按钮自动隐藏
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });

    testWidgets('当控制器具有多位置或无像素时静默安全容错，不抛出异常', (tester) async {
      final controller = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ListView(
                    controller: controller,
                    children: const [SizedBox(height: 1000)],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    children: const [SizedBox(height: 1000)],
                  ),
                ),
                BackToTopButton(controller: controller),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      // Even with 2 views attached, no crash
      expect(tester.takeException(), isNull);
    });
  });
}
