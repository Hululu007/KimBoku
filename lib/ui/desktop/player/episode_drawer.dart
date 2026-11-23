import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/models/vod_models.dart';
import '../../../core/api/parse_engine.dart';
import '../../../core/config/models/vod_config.dart';
import '../../../core/player/cross_site_models.dart';
import '../../../core/player/cross_site_source_manager.dart';
import '../../../core/player/models/player_state.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import '../widgets/app_message.dart';
import '../widgets/focus_ring.dart';

/// 播放页「选集」里的一集（宿主装配，组件保持哑视图）。
class PlayerEpisodeOption {
  /// 0 基列表下标：只用于回调定位与测试构造，界面一律读 [ordinal]。
  final int index;
  final String name;
  final bool current;

  const PlayerEpisodeOption({
    required this.index,
    required this.name,
    this.current = false,
  });

  /// 1 基列表位置（`index + 1`，不补零）：显示 / Tooltip / 复制共用。
  int get ordinal => index + 1;
}

/// 顶部的一条线路（`index` 是 `PlaybackSession.sources` 的下标）。
class PlayerLineChoice {
  final int index;
  final String name;

  /// 实际正在播放的线路。
  final bool current;

  /// 当前展示目录的线路；缺少当前集时可与 [current] 不同。
  final bool browsing;

  /// 本次会话里确认失败的线路（灰显不可点）。
  final bool unavailable;

  const PlayerLineChoice({
    required this.index,
    required this.name,
    this.current = false,
    this.browsing = false,
    this.unavailable = false,
  });
}

/// 播放页选集与换源视图模型。
class PlayerEpisodeListNav {
  final List<PlayerEpisodeOption> episodes;
  final List<PlayerLineChoice> lines;

  /// 当前线路名（副标题用）；为空时不显示。
  final String? lineName;

  /// 当前播放源/站点名（如「闪电」）；用于在抽屉左侧展示「本片播放源」。
  final String? currentSiteName;

  /// 切集 / 换线进行中：整块禁用，防重复触发。
  final bool switching;

  /// 选集回调：参数是当前浏览线路里的集下标。
  final ValueChanged<int> onSelectEpisode;

  /// 当前目录是否就是实际播放线路；否则选集时走跨线路切集事务。
  final bool browsingPlayingLine;

  /// 换线路回调：参数是 `PlaybackSession.sources` 的下标。
  final ValueChanged<int> onSelectLine;

  /// 跨站换源聚合管理核心服务（若宿主装配则展示「可换来源」）
  final CrossSiteSourceManager? sourceManager;
  final CrossSiteTarget? crossSiteTarget;
  final List<Site>? allSites;
  final ParseEngine? parseEngine;
  final List<Parse> parses;
  final Future<void> Function(
    MediaPlaySpec spec,
    CrossSiteCandidate candidate,
    PlayFrom line,
    int episodeIndex,
  )? onSwitchSource;

  const PlayerEpisodeListNav({
    required this.episodes,
    required this.lines,
    required this.onSelectEpisode,
    required this.onSelectLine,
    this.browsingPlayingLine = true,
    this.lineName,
    this.currentSiteName,
    this.switching = false,
    this.sourceManager,
    this.crossSiteTarget,
    this.allSites,
    this.parseEngine,
    this.parses = const [],
    this.onSwitchSource,
  });
}

/// 播放页居中模态弹窗（左侧：播放源与可换来源；右侧：选集播放三列网格）。
class EpisodeDrawerLayer extends StatefulWidget {
  final bool open;
  final PlayerEpisodeListNav? nav;
  final VoidCallback onClose;
  final Widget child;

  const EpisodeDrawerLayer({
    super.key,
    required this.open,
    required this.nav,
    required this.onClose,
    required this.child,
  });

  @override
  State<EpisodeDrawerLayer> createState() => _EpisodeDrawerLayerState();
}

class _EpisodeDrawerLayerState extends State<EpisodeDrawerLayer> {
  static const double _dialogMaxWidth = 780;
  static const double _dialogMaxHeight = 490;
  static const double _leftPanelWidth = 280;

  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightGridController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'episode-source-dialog');

  bool _dialogMounted = false;
  CrossSiteSourceManager? _subscribedManager;

  int get _currentIndex {
    final episodes = widget.nav?.episodes ?? const <PlayerEpisodeOption>[];
    final index = episodes.indexWhere((episode) => episode.current);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _dialogMounted = widget.open;
    _attachManagerListener();
    if (widget.open) {
      _triggerSearchIfNeeded();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.open) return;
        _scrollToCurrentEpisode(animate: false);
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant EpisodeDrawerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nav?.sourceManager != oldWidget.nav?.sourceManager) {
      _detachManagerListener();
      _attachManagerListener();
    }

    if (widget.open && !oldWidget.open) {
      _dialogMounted = true;
      _triggerSearchIfNeeded();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.open) return;
        _scrollToCurrentEpisode(animate: false);
        _focusNode.requestFocus();
      });
    } else if (!widget.open && oldWidget.open) {
      _focusNode.unfocus();
    }

    if (widget.open) {
      final length = widget.nav?.episodes.length ?? 0;
      if (length == 0 && widget.nav?.lines.isEmpty == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.open) widget.onClose();
        });
      }
    }
  }

  @override
  void dispose() {
    _detachManagerListener();
    _leftScrollController.dispose();
    _rightGridController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _attachManagerListener() {
    final mgr = widget.nav?.sourceManager;
    if (mgr != null && mgr != _subscribedManager) {
      _subscribedManager = mgr;
      mgr.addListener(_onSourceManagerUpdate);
    }
  }

  void _detachManagerListener() {
    _subscribedManager?.removeListener(_onSourceManagerUpdate);
    _subscribedManager = null;
  }

  void _onSourceManagerUpdate() {
    if (mounted) setState(() {});
  }

  void _triggerSearchIfNeeded({bool force = false}) {
    final nav = widget.nav;
    if (nav == null) return;
    final manager = nav.sourceManager;
    final target = nav.crossSiteTarget;
    final sites = nav.allSites;
    if (manager != null && target != null && sites != null && sites.isNotEmpty) {
      unawaited(manager.searchOrUpdate(
        target: target,
        sites: sites,
        parseEngine: nav.parseEngine,
        parses: nav.parses,
        forceRefresh: force,
      ));
    }
  }

  void _scrollToCurrentEpisode({bool animate = true}) {
    if (!_rightGridController.hasClients) return;
    final index = _currentIndex;
    final row = index ~/ 3;
    const rowHeight = 44.0 + 8.0;
    final target = (row * rowHeight - 60).clamp(0.0, _rightGridController.position.maxScrollExtent);
    if (animate) {
      _rightGridController.animateTo(target, duration: AppMotion.enter, curve: AppMotion.ease);
    } else {
      _rightGridController.jumpTo(target);
    }
  }

  void _selectEpisode(int index) {
    final nav = widget.nav;
    if (nav == null || nav.switching) return;
    if (index < 0 || index >= nav.episodes.length) return;
    nav.onSelectEpisode(index);
    widget.onClose();
  }

  Future<void> _handleSwitchCandidate(CrossSiteCandidate candidate) async {
    final nav = widget.nav;
    if (nav == null || nav.switching) return;
    final manager = nav.sourceManager;
    final target = nav.crossSiteTarget;
    final parseEngine = nav.parseEngine;
    final onSwitch = nav.onSwitchSource;
    if (manager == null || target == null || parseEngine == null || onSwitch == null) return;

    final success = await manager.executeSwitch(
      candidate: candidate,
      target: target,
      parseEngine: parseEngine,
      parses: nav.parses,
      onPlay: onSwitch,
    );

    if (success && mounted) {
      widget.onClose();
    }
  }

  Future<void> _copyEpisode(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppMessage('已复制选集名称: $text', type: AppMessageType.success);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final nav = widget.nav;
    if (nav == null || (!_dialogMounted && !widget.open)) {
      return widget.child;
    }

    return LayoutBuilder(builder: (context, constraints) {
      final dialogWidth = math.min(_dialogMaxWidth, constraints.maxWidth * 0.92);
      final dialogHeight = math.min(_dialogMaxHeight, constraints.maxHeight * 0.88);

      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          // 半透明遮罩层
          AnimatedOpacity(
            duration: widget.open ? AppMotion.enter : AppMotion.exit,
            opacity: widget.open ? 1 : 0,
            child: IgnorePointer(
              ignoring: !widget.open,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: const ColoredBox(color: Color(0x77000000)),
              ),
            ),
          ),
          // 居中主弹窗
          AnimatedOpacity(
            duration: widget.open ? AppMotion.enter : AppMotion.exit,
            opacity: widget.open ? 1 : 0,
            onEnd: () {
              if (!widget.open && _dialogMounted) {
                setState(() => _dialogMounted = false);
              }
            },
            child: Center(
              child: IgnorePointer(
                ignoring: !widget.open,
                child: Focus(
                  focusNode: _focusNode,
                  onKeyEvent: _onKey,
                  child: SizedBox(
                    width: dialogWidth,
                    height: dialogHeight,
                    child: _buildDialogContent(context, nav),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildDialogContent(BuildContext context, PlayerEpisodeListNav nav) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xE61E1F24), // 磨砂深色底色，贴合截图设计
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x88000000),
                blurRadius: 36,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧面板：播放源（本片线路 + 可换来源）
              SizedBox(
                width: _leftPanelWidth,
                child: _buildLeftPanel(context, nav, palette),
              ),
              // 中部分隔线
              Container(
                width: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              // 右侧面板：选集播放（3 列网格）
              Expanded(
                child: _buildRightPanel(context, nav, palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧面板：播放源与可换来源
  Widget _buildLeftPanel(
    BuildContext context,
    PlayerEpisodeListNav nav,
    AppPalette palette,
  ) {
    final candidatesState = nav.sourceManager?.value ?? const SourceCandidatesState();
    final isSearching = candidatesState.searching;
    final candidates = candidatesState.candidates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 头部：≡ 播放源 + 刷新按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
          child: Row(
            children: [
              Icon(
                Icons.view_headline_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                '播放源',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              FocusRing(
                onTap: isSearching ? null : () => _triggerSearchIfNeeded(force: true),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: IconButton(
                  icon: isSearching
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 17,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                  tooltip: '重新探测所有来源',
                  onPressed: isSearching ? null : () => _triggerSearchIfNeeded(force: true),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.06)),
        Expanded(
          child: ListView(
            controller: _leftScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              // 1. 本片播放源区块
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '本片播放源',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _buildCurrentSiteItem(context, nav, palette),
              const SizedBox(height: 10),
              // 2. 本片线路区块
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '本片线路',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              for (final line in nav.lines) _buildCurrentSiteLineItem(context, nav, line, palette),
              const SizedBox(height: 10),
              // 3. 可换来源区块
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '可换来源',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isSearching) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· 探测中',
                        style: TextStyle(
                          color: palette.accentInk,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Builder(builder: (context) {
                final currentSiteKey = nav.crossSiteTarget?.currentSiteKey?.trim();
                final currentSiteName = nav.currentSiteName?.trim();
                final uniqueCandidates = <CrossSiteCandidate>[];
                final seenKeys = <String>{};
                final seenNames = <String>{};

                for (final c in candidates) {
                  final k = c.site.key.trim();
                  final n = c.site.name.trim();
                  // 过滤当前播放源（上方已展示）
                  if (currentSiteKey != null && currentSiteKey.isNotEmpty && k == currentSiteKey) continue;
                  if (currentSiteName != null && currentSiteName.isNotEmpty && n == currentSiteName) continue;
                  // 同源（同站点）去重，确保每个源只出现 1 次
                  if (k.isNotEmpty && seenKeys.contains(k)) continue;
                  if (n.isNotEmpty && seenNames.contains(n)) continue;
                  if (k.isNotEmpty) seenKeys.add(k);
                  if (n.isNotEmpty) seenNames.add(n);
                  uniqueCandidates.add(c);
                }

                if (uniqueCandidates.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        isSearching ? '正在跨站搜索中…' : (candidatesState.message ?? '暂无其他匹配源'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final candidate in uniqueCandidates)
                      _buildCandidateItem(context, nav, candidate, palette),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// 本片当前播放源（展示站点名称与「当前」状态）
  Widget _buildCurrentSiteItem(
    BuildContext context,
    PlayerEpisodeListNav nav,
    AppPalette palette,
  ) {
    final siteName = nav.currentSiteName?.trim();
    final displayName = (siteName != null && siteName.isNotEmpty)
        ? siteName
        : (nav.crossSiteTarget?.currentSiteKey ?? '当前源');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF4ADE80),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accentInk.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: palette.accentInk.withValues(alpha: 0.4),
                width: 0.6,
              ),
            ),
            child: Text(
              '当前',
              style: TextStyle(
                color: palette.accentInk,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 本片当前站点线路条目
  Widget _buildCurrentSiteLineItem(
    BuildContext context,
    PlayerEpisodeListNav nav,
    PlayerLineChoice line,
    AppPalette palette,
  ) {
    final isCurrent = line.current || line.browsing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: nav.switching || line.unavailable
            ? null
            : () {
                if (!line.browsing) nav.onSelectLine(line.index);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: isCurrent
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCurrent
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (line.current)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 可换来源单条渲染
  Widget _buildCandidateItem(
    BuildContext context,
    PlayerEpisodeListNav nav,
    CrossSiteCandidate candidate,
    AppPalette palette,
  ) {
    final isSwitching = candidate.switchingStage != null;
    final isFail = candidate.probe.isFail;
    final isOk = candidate.probe.isOk;

    // 右侧徽标
    Widget badge;
    if (isSwitching) {
      badge = Text(
        candidate.switchingStage!,
        style: TextStyle(color: palette.accentInk, fontSize: 11, fontWeight: FontWeight.bold),
      );
    } else if (isOk) {
      final ping = candidate.probe.pingMs;
      final pingText = ping != null ? '$ping ms' : '可用';
      badge = Text(
        '✓ $pingText',
        style: const TextStyle(
          color: Color(0xFF4ADE80), // 鲜绿
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (isFail) {
      badge = Text(
        '✕ 失败',
        style: TextStyle(
          color: Colors.redAccent.withValues(alpha: 0.8),
          fontSize: 11,
        ),
      );
    } else {
      badge = Text(
        '未测',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: nav.switching ? null : () => _handleSwitchCandidate(candidate),
        child: Opacity(
          opacity: isFail ? 0.45 : 1.0, // 失败置灰但仍可点击尝试
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSwitching
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSwitching
                    ? palette.accentInk.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.06),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                // 红色/橙色圆点标记
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(right: 7),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatCandidateTitle(candidate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        candidate.episodeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                badge,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 右侧面板：选集播放（共 N 集 · 线路名，3 列网格）
  Widget _buildRightPanel(
    BuildContext context,
    PlayerEpisodeListNav nav,
    AppPalette palette,
  ) {
    final lineDisplay = formatSourceAndLine(nav.currentSiteName, nav.lineName);
    final subtitle = lineDisplay.isEmpty
        ? '共 ${nav.episodes.length} 集'
        : '共 ${nav.episodes.length} 集 · $lineDisplay';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 头部：⊞ 选集播放 + 共 N 集 · 线路名 + × 关闭按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
          child: Row(
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 17,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                '选集播放',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              FocusRing(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  tooltip: '关闭 (Esc)',
                  onPressed: widget.onClose,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.06)),
        // 3 列剧集网格
        Expanded(
          child: GridView.builder(
            controller: _rightGridController,
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.8,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: nav.episodes.length,
            itemBuilder: (context, index) {
              final episode = nav.episodes[index];
              final isCurrent = episode.current;
              return _buildEpisodeGridCard(context, nav, episode, isCurrent, palette);
            },
          ),
        ),
      ],
    );
  }

  /// 选集 3 列网格中的单张卡片
  Widget _buildEpisodeGridCard(
    BuildContext context,
    PlayerEpisodeListNav nav,
    PlayerEpisodeOption episode,
    bool isCurrent,
    AppPalette palette,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: nav.switching ? null : () => _selectEpisode(episode.index),
      onSecondaryTap: () => unawaited(_copyEpisode(episode.name)),
      child: AnimatedContainer(
        duration: AppMotion.enter,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isCurrent
              ? Colors.white.withValues(alpha: 0.18) // 当前集高亮背景（贴合截图）
              : Colors.white.withValues(alpha: 0.06), // 普通集深灰微透
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isCurrent
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Text(
          episode.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent
                ? Colors.white
                : Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 格式化候选条目标题（只展示源名/站点名，不显示线路，因为上方已有本片线路展示）
String _formatCandidateTitle(CrossSiteCandidate candidate) =>
    candidate.site.name.trim();
