import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import 'focus_ring.dart';

/// 胶囊式单选按钮：分类条、搜索站点栏、分类筛选行共用同一套主题、悬停与焦点环。
///
/// [count] 非空时在文字后附数量角标（搜索站点栏用）。
class FilterPill extends StatefulWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;

  const FilterPill({
    super.key,
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<FilterPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final palette = context.palette;
    // 选中态底色是品牌色，文字用 onPrimary（随明暗反转）保证对比度。
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return FocusRing(
      onTap: widget.onTap,
      semanticLabel: widget.label,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: _isHovered ? AppMotion.enter : AppMotion.exit,
            curve: AppMotion.ease,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? palette.accent
                  : _isHovered
                      ? palette.accentWash
                      : palette.card,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(
                color: isSelected
                    ? palette.accentInk.withValues(alpha: 0.6)
                    : _isHovered
                        ? palette.accentInk.withValues(alpha: 0.35)
                        : context.glassBorder,
                width: 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: palette.accentInk.withValues(alpha: 0.20),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? onAccent
                          : _isHovered
                              ? palette.textTitle
                              : palette.textBody,
                    ),
                  ),
                ),
                if (widget.count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? onAccent.withValues(alpha: 0.18)
                          : palette.border,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isSelected ? onAccent : palette.textDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 虚线胶囊按钮：用于折叠列表末尾的「展开全部 N 个」与「收起」。
class DashedPill extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const DashedPill({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<DashedPill> createState() => _DashedPillState();
}

class _DashedPillState extends State<DashedPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderColor = _isHovered
        ? palette.accentInk
        : palette.accentInk.withValues(alpha: 0.5);

    return FocusRing(
      onTap: widget.onTap,
      semanticLabel: widget.label,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: CustomPaint(
            painter: DashedRRectPainter(
              color: borderColor,
              strokeWidth: 1.0,
              dash: 4.0,
              gap: 3.0,
              radius: AppRadii.pill,
            ),
            child: AnimatedContainer(
              duration: _isHovered ? AppMotion.enter : AppMotion.exit,
              curve: AppMotion.ease,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _isHovered ? palette.accentWash : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w500,
                      color: _isHovered ? palette.accentInk : palette.textSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 绘制圆角矩形虚线边框
class DashedRRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;
  final double radius;

  const DashedRRectPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dash = 4.0,
    this.gap = 3.0,
    this.radius = AppRadii.pill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = (distance + dash < metric.length) ? dash : metric.length - distance;
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRRectPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dash != oldDelegate.dash ||
      gap != oldDelegate.gap ||
      radius != oldDelegate.radius;
}
