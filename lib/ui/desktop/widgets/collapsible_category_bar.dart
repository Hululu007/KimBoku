import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/api/models/vod_models.dart';
import '../../theme/app_tokens.dart';
import 'filter_pill.dart';

/// 首页分类条：按窗口宽度自动换行、可折叠。
///
/// 1. 分类胶囊横向铺满，窗口变宽/变窄时自动换行，不出现横向滚动条；
/// 2. 默认最多显示 2 行；放不下时折叠，最后一行的行末放置虚线胶囊「展开全部 N 个」；
/// 3. 点开后在末尾变「收起」；
/// 4. 纯纯基于 LayoutBuilder 与 TextPainter 模拟换行计算，不使用固定高度 Overflow 裁剪。
class CollapsibleCategoryBar extends StatefulWidget {
  final List<VodCategory> categories;
  final VodCategory? selectedCategory;
  final ValueChanged<VodCategory> onSelectCategory;
  final bool isDoubanViewingSingleCategory;
  final VoidCallback? onReturnToDoubanHall;

  const CollapsibleCategoryBar({
    super.key,
    required this.categories,
    this.selectedCategory,
    required this.onSelectCategory,
    this.isDoubanViewingSingleCategory = false,
    this.onReturnToDoubanHall,
  });

  @override
  State<CollapsibleCategoryBar> createState() => _CollapsibleCategoryBarState();
}

class _CollapsibleCategoryBarState extends State<CollapsibleCategoryBar> {
  bool _isExpanded = false;

  static const double _spacing = 8.0;
  static const double _runSpacing = 8.0;
  static const int _maxCollapsedRows = 2;

  double _measurePillWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // FilterPill 的文本有 maxWidth: 220 约束；加上左右 padding 16*2 + border 1*2 = 34
    final textWidth = math.min(tp.width, 220.0);
    return textWidth + 34.0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty && !widget.isDoubanViewingSingleCategory) {
      return const SizedBox.shrink();
    }

    const textStyle = TextStyle(
      fontSize: AppType.body,
      fontWeight: FontWeight.bold,
    );

    final showDoubanReturn =
        widget.isDoubanViewingSingleCategory && widget.onReturnToDoubanHall != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        if (availableWidth <= 0) return const SizedBox.shrink();

        // 收集所有需要排版的胶囊宽度与元信息
        final itemWidths = <double>[];
        if (showDoubanReturn) {
          itemWidths.add(_measurePillWidth('◀ 返回推荐大厅', textStyle));
        }
        for (final cat in widget.categories) {
          itemWidths.add(_measurePillWidth(cat.name, textStyle));
        }

        final totalItems = itemWidths.length;
        if (totalItems == 0) return const SizedBox.shrink();

        // 1. 先探测是否可以在 _maxCollapsedRows (2) 行内放下全部
        int simulatedRow = 1;
        double currentLineWidth = 0.0;
        bool allFitInMaxRows = true;

        for (int i = 0; i < totalItems; i++) {
          final w = itemWidths[i];
          if (currentLineWidth == 0.0) {
            currentLineWidth = w;
          } else if (currentLineWidth + _spacing + w <= availableWidth) {
            currentLineWidth += _spacing + w;
          } else {
            simulatedRow++;
            if (simulatedRow > _maxCollapsedRows) {
              allFitInMaxRows = false;
              break;
            }
            currentLineWidth = w;
          }
        }

        // 辅助构建具体胶囊 Widget
        Widget buildItemWidget(int itemIndex) {
          if (showDoubanReturn) {
            if (itemIndex == 0) {
              return FilterPill(
                key: const ValueKey('category-douban-return'),
                label: '◀ 返回推荐大厅',
                isSelected: false,
                onTap: widget.onReturnToDoubanHall!,
              );
            }
            final cat = widget.categories[itemIndex - 1];
            return FilterPill(
              key: ValueKey('category-${cat.id}'),
              label: cat.name,
              isSelected: widget.selectedCategory?.id == cat.id,
              onTap: () => widget.onSelectCategory(cat),
            );
          } else {
            final cat = widget.categories[itemIndex];
            return FilterPill(
              key: ValueKey('category-${cat.id}'),
              label: cat.name,
              isSelected: widget.selectedCategory?.id == cat.id,
              onTap: () => widget.onSelectCategory(cat),
            );
          }
        }

        // 如果全部能放下，直接全部渲染，不加折叠按钮
        if (allFitInMaxRows) {
          return Wrap(
            spacing: _spacing,
            runSpacing: _runSpacing,
            children: List.generate(totalItems, buildItemWidget),
          );
        }

        // 放不下且处于展开状态：渲染全部，末尾加「收起」虚线胶囊
        if (_isExpanded) {
          return Wrap(
            spacing: _spacing,
            runSpacing: _runSpacing,
            children: [
              ...List.generate(totalItems, buildItemWidget),
              DashedPill(
                key: const ValueKey('category-toggle-collapse'),
                label: '收起',
                onTap: () => setState(() => _isExpanded = false),
              ),
            ],
          );
        }

        // 放不下且处于折叠状态：计算前 2 行能放几个，预留「展开全部 N 个」胶囊宽度
        // 确保「展开全部」落在最后一行的行末，绝不另起一行
        final totalCount = widget.categories.length;
        final toggleLabel = '展开全部 $totalCount 个';
        final toggleWidth = _measurePillWidth(toggleLabel, textStyle);

        final visibleIndices = <int>[];
        double rowWidth = 0.0;
        int i = 0;

        // 第 1 行：尽可能铺满
        while (i < totalItems) {
          final w = itemWidths[i];
          if (rowWidth == 0.0) {
            rowWidth = w;
            visibleIndices.add(i);
            i++;
          } else if (rowWidth + _spacing + w <= availableWidth) {
            rowWidth += _spacing + w;
            visibleIndices.add(i);
            i++;
          } else {
            break;
          }
        }

        // 第 2 行：排入胶囊的同时，必须严格预留 `_spacing + toggleWidth` 的空间
        rowWidth = 0.0;
        while (i < totalItems) {
          final w = itemWidths[i];
          final neededWithToggle = (rowWidth == 0.0 ? w : rowWidth + _spacing + w) +
              _spacing +
              toggleWidth;
          if (neededWithToggle <= availableWidth) {
            rowWidth = (rowWidth == 0.0 ? w : rowWidth + _spacing + w);
            visibleIndices.add(i);
            i++;
          } else {
            // 第 2 行无法在放该胶囊的同时保留折叠按钮
            break;
          }
        }

        return Wrap(
          spacing: _spacing,
          runSpacing: _runSpacing,
          children: [
            ...visibleIndices.map(buildItemWidget),
            DashedPill(
              key: const ValueKey('category-toggle-expand'),
              label: toggleLabel,
              onTap: () => setState(() => _isExpanded = true),
            ),
          ],
        );
      },
    );
  }
}
