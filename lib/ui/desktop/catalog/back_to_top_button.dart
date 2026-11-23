import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// 桌面端悬浮回到顶部按钮（滚动超过阈值时浮现，点击平滑滚回顶部）。
class BackToTopButton extends StatefulWidget {
  final ScrollController controller;
  final double threshold;
  final Duration duration;
  final Curve curve;

  const BackToTopButton({
    super.key,
    required this.controller,
    this.threshold = 200.0,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<BackToTopButton> createState() => _BackToTopButtonState();
}

class _BackToTopButtonState extends State<BackToTopButton> {
  bool _visible = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  @override
  void didUpdateWidget(covariant BackToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    try {
      if (!widget.controller.hasClients) {
        if (_visible) setState(() => _visible = false);
        return;
      }
      final positions = widget.controller.positions;
      if (positions.isEmpty) {
        if (_visible) setState(() => _visible = false);
        return;
      }
      final pos = positions.first;
      if (!pos.hasPixels) return;
      final show = pos.pixels > widget.threshold;
      if (show != _visible) {
        setState(() => _visible = show);
      }
    } catch (_) {
      // 容错保护：视图切换或 position 附着期静默吸收，不影响宿主渲染
    }
  }

  void _scrollToTop() {
    try {
      if (!widget.controller.hasClients) return;
      final positions = widget.controller.positions;
      if (positions.isEmpty) return;
      for (final pos in positions) {
        if (pos.hasPixels) {
          pos.animateTo(
            0,
            duration: widget.duration,
            curve: widget.curve,
          );
        }
      }
    } catch (_) {
      // 容错保护
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final highlighted = _isHovered;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation,
            child: child,
          ),
        );
      },
      child: _visible
          ? Tooltip(
              key: const ValueKey('back-to-top-visible'),
              message: '回到顶部',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _scrollToTop,
                  customBorder: const CircleBorder(),
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  splashFactory: AppMotion.reduced(context)
                      ? NoSplash.splashFactory
                      : InkSparkle.splashFactory,
                  onHover: (hovering) => setState(() => _isHovered = hovering),
                  child: AnimatedContainer(
                    duration: highlighted ? AppMotion.enter : AppMotion.exit,
                    curve: AppMotion.ease,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: highlighted ? palette.raised : palette.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: highlighted ? palette.accentInk : palette.borderStrong,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 20,
                        color: highlighted ? palette.accentInk : palette.textTitle,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('back-to-top-hidden')),
    );
  }
}
