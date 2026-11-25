part of 'settings_page.dart';

class PlayerShortcutsPanel extends StatefulWidget {
  final SettingsRepository settingsRepository;

  const PlayerShortcutsPanel({super.key, required this.settingsRepository});

  @override
  State<PlayerShortcutsPanel> createState() => _PlayerShortcutsPanelState();
}

class _PlayerShortcutsPanelState extends State<PlayerShortcutsPanel> {
  late Stream<PlayerSettings> _settingsStream;

  @override
  void initState() {
    super.initState();
    _settingsStream = widget.settingsRepository.playerSettingsStream;
  }

  @override
  void didUpdateWidget(covariant PlayerShortcutsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsRepository != widget.settingsRepository) {
      _settingsStream = widget.settingsRepository.playerSettingsStream;
    }
  }

  Future<void> _edit(PlayerShortcutAction action) => showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ShortcutCaptureDialog(
          action: action,
          settingsRepository: widget.settingsRepository,
        ),
      );

  Future<void> _editBossKey() => showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BossKeyCaptureDialog(
          settingsRepository: widget.settingsRepository,
        ),
      );

  String _description(PlayerSettings settings, PlayerShortcutAction action) {
    final keys =
        settings.shortcuts.keysFor(action).map((key) => key.label).join(' / ');
    if (action != PlayerShortcutAction.seekForward) return keys;
    return '$keys\n长按主键 ${settings.shortcuts.primarySeekForward.label} 超过 0.4 秒，'
        '临时 ${settings.holdRate.toStringAsFixed(0)} 倍速，松开恢复；直播不生效。';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerSettings>(
        stream: _settingsStream,
        initialData: widget.settingsRepository.playerSettings,
        builder: (context, snapshot) {
          final settings =
              snapshot.data ?? widget.settingsRepository.playerSettings;
          final isDefault =
              settings.shortcuts == PlayerShortcutBindings.defaults &&
                  settings.bossKeyEnabled &&
                  settings.bossKey == const PlayerKeyBinding('keyQ', alt: true);
          return _PanelScaffold(
            title: '快捷键',
            subtitle: '更改后立即生效并自动保存，支持 Ctrl、Alt、Shift 组合。',
            actions: [
              FocusOutline(
                child: OutlinedButton.icon(
                  key: const ValueKey('reset-player-shortcuts'),
                  style: _outlinedStyle(context),
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('恢复默认'),
                  onPressed: isDefault
                      ? null
                      : () => unawaited(_saveWithStatus(
                          widget.settingsRepository.resetPlayerShortcuts())),
                ),
              ),
            ],
            children: [
              Text(
                '全局快捷键（系统级）',
                style: TextStyle(
                  color: context.palette.textTitle,
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '在任意应用程序或桌面下按下均可立即响应。',
                style: TextStyle(
                    color: context.palette.textSub,
                    fontSize: AppType.body,
                    height: 1.5),
              ),
              const SizedBox(height: 12),
              _card(
                context,
                child: Column(
                  children: [
                    _SettingRow(
                      title: '老板键',
                      description: settings.bossKeyEnabled
                          ? '执行后自动暂停当前视频播放并完全隐藏窗口；再次按下呼出窗口并保持暂停。\n'
                              '当前按键：${settings.bossKey.label}（支持全局任意应用下呼叫）'
                          : '全局老板键已禁用。开启后可在任意应用界面一键隐藏窗口并暂停。',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FocusOutline(
                            child: OutlinedButton(
                              key: const ValueKey('edit-shortcut-bossKey'),
                              style: _outlinedStyle(context),
                              onPressed: settings.bossKeyEnabled
                                  ? () => unawaited(_editBossKey())
                                  : null,
                              child: Semantics(
                                label: '更改老板键快捷键',
                                child: const Text('更改'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            key: const ValueKey('setting-boss-key-enabled'),
                            value: settings.bossKeyEnabled,
                            onChanged: (val) => unawaited(
                              _saveWithStatus(
                                widget.settingsRepository.setBossKeyEnabled(val),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '播放快捷键（应用内）',
                style: TextStyle(
                  color: context.palette.textTitle,
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '点击“更改”后按下新组合键。更改会替换该动作的全部旧按键；'
                '输入文字或操作抽屉时，播放快捷键暂停响应。',
                style: TextStyle(
                    color: context.palette.textSub,
                    fontSize: AppType.body,
                    height: 1.5),
              ),
              const SizedBox(height: 12),
              _card(context,
                  child: Column(children: [
                    for (final action in PlayerShortcutAction.values) ...[
                      if (action != PlayerShortcutAction.values.first)
                        const _RowDivider(),
                      _SettingRow(
                        title: action.label,
                        description: _description(settings, action),
                        trailing: FocusOutline(
                          child: OutlinedButton(
                            key: ValueKey('edit-shortcut-${action.name}'),
                            style: _outlinedStyle(context),
                            onPressed: () => unawaited(_edit(action)),
                            child: Semantics(
                                label: '更改${action.label}快捷键',
                                child: const Text('更改')),
                          ),
                        ),
                      ),
                    ],
                  ])),
            ],
          );
        },
      );
}

class _ShortcutCaptureDialog extends StatefulWidget {
  final PlayerShortcutAction action;
  final SettingsRepository settingsRepository;

  const _ShortcutCaptureDialog(
      {required this.action, required this.settingsRepository});

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  final FocusNode _captureFocus = FocusNode(debugLabel: 'shortcut-capture');
  final ShortcutManager _dialogShortcuts = ShortcutManager(
    modal: true,
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
      SingleActivator(LogicalKeyboardKey.tab, shift: true):
          PreviousFocusIntent(),
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
  );
  PlayerKeyBinding? _candidate;
  String? _error;
  bool _captureFocused = false;
  bool _saving = false;

  static final _modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  @override
  void dispose() {
    _captureFocus.dispose();
    _dialogShortcuts.dispose();
    super.dispose();
  }

  KeyEventResult _capture(FocusNode node, KeyEvent event) {
    if (_saving) return KeyEventResult.handled;
    // Dialog navigation remains local; Escape cancels and Tab moves to buttons.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (_modifiers.contains(event.logicalKey)) return KeyEventResult.handled;
    final candidate = playerKeyBindingFromEvent(event);
    setState(() {
      _candidate = candidate;
      _error = candidate == null
          ? '该按键保留用于界面或系统操作，请选择其他按键。'
          : widget.settingsRepository.playerSettings.shortcuts
              .validationError(widget.action, candidate);
    });
    return KeyEventResult.handled;
  }

  Future<void> _save() async {
    final candidate = _candidate;
    if (_saving || candidate == null) return;
    final error = widget.settingsRepository.playerSettings.shortcuts
        .validationError(widget.action, candidate);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await _persist(() => widget.settingsRepository
        .setPlayerShortcut(widget.action, candidate));
  }

  Future<void> _restoreDefaults() => _persist(() {
        final current = widget.settingsRepository.playerSettings;
        return widget.settingsRepository.updatePlayerSettings(current.copyWith(
          shortcuts: current.shortcuts.restoreDefaultsFor(widget.action),
        ));
      });

  Future<void> _persist(Future<void> Function() save) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await save();
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _saving = false;
        });
      }
      return;
    } catch (_) {
      // The repository retains the in-memory change and exposes retry in the
      // settings save-status banner, shared with all other settings panels.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Shortcuts.manager(
        // Unrecognized keys stop here even when a dialog button has focus. No
        // global listener is installed, so capture ends when this route closes.
        manager: _dialogShortcuts,
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              if (!_saving) Navigator.of(context).pop();
              return null;
            }),
          },
          child: AlertDialog(
            key: const ValueKey('player-shortcut-capture-dialog'),
            backgroundColor: context.palette.card,
            title: Text('更改${widget.action.label}快捷键'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      '当前：${widget.settingsRepository.playerSettings.shortcuts.keysFor(widget.action).map((key) => key.label).join(' / ')}',
                      style: TextStyle(color: context.palette.textSub)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FocusOutline(
                      child: OutlinedButton.icon(
                        key: const ValueKey('restore-player-shortcut'),
                        style: _outlinedStyle(context),
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        label: const Text('恢复此项默认'),
                        onPressed: _saving
                            ? null
                            : () => unawaited(_restoreDefaults()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Focus(
                    focusNode: _captureFocus,
                    autofocus: true,
                    onFocusChange: (focused) =>
                        setState(() => _captureFocused = focused),
                    onKeyEvent: _capture,
                    child: Semantics(
                      label: '快捷键捕获区，按下新按键，可组合 Ctrl、Alt、Shift',
                      button: true,
                      liveRegion: true,
                      onTap: _captureFocus.requestFocus,
                      child: GestureDetector(
                        key: const ValueKey('player-shortcut-capture-area'),
                        onTap: _captureFocus.requestFocus,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: _captureFocused
                                  ? context.palette.accentInk
                                  : context.palette.borderStrong,
                              width: _captureFocused ? 2 : 1,
                            ),
                          ),
                          child: Text(_candidate?.label ?? '请按下新组合键',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppType.h2,
                                  color: context.palette.textTitle)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      '可组合 Ctrl、Alt、Shift。Tab 切换焦点，Esc 取消。\n'
                      'Enter、Tab、系统快捷键不可绑定。点击捕获区可重新录入。',
                      style: TextStyle(
                          fontSize: AppType.body,
                          height: 1.5,
                          color: context.palette.textSub)),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            key: const ValueKey('player-shortcut-error'),
                            style: TextStyle(
                                color: context.palette.warning, height: 1.4))),
                  ],
                ],
              ),
            ),
            actions: [
              FocusOutline(
                  child: OutlinedButton(
                key: const ValueKey('cancel-player-shortcut'),
                style: _outlinedStyle(context),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              )),
              FocusOutline(
                  child: ElevatedButton(
                key: const ValueKey('save-player-shortcut'),
                style: _primaryStyle(context),
                onPressed: _saving || _candidate == null || _error != null
                    ? null
                    : () => unawaited(_save()),
                child: Text(_saving ? '正在保存…' : '保存'),
              )),
            ],
          ),
        ),
      );
}

class _BossKeyCaptureDialog extends StatefulWidget {
  final SettingsRepository settingsRepository;

  const _BossKeyCaptureDialog({required this.settingsRepository});

  @override
  State<_BossKeyCaptureDialog> createState() => _BossKeyCaptureDialogState();
}

class _BossKeyCaptureDialogState extends State<_BossKeyCaptureDialog> {
  final FocusNode _captureFocus = FocusNode(debugLabel: 'bosskey-capture');
  final ShortcutManager _dialogShortcuts = ShortcutManager(
    modal: true,
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
      SingleActivator(LogicalKeyboardKey.tab, shift: true):
          PreviousFocusIntent(),
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
  );
  PlayerKeyBinding? _candidate;
  String? _error;
  bool _captureFocused = false;
  bool _saving = false;

  static final _modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  @override
  void dispose() {
    _captureFocus.dispose();
    _dialogShortcuts.dispose();
    super.dispose();
  }

  KeyEventResult _capture(FocusNode node, KeyEvent event) {
    if (_saving) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (_modifiers.contains(event.logicalKey)) return KeyEventResult.handled;
    final candidate = playerKeyBindingFromEvent(event);
    setState(() {
      _candidate = candidate;
      _error = candidate == null
          ? '该按键保留用于系统操作，请选择其他按键。'
          : BossKeyService.validateBossKey(candidate);
    });
    return KeyEventResult.handled;
  }

  Future<void> _save() async {
    final candidate = _candidate;
    if (_saving || candidate == null) return;
    final error = BossKeyService.validateBossKey(candidate);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // 预先向系统测试注册是否成功（检测系统或其他程序是否独占）
      try {
        final available = await BossKeyService.instance.testRegister(candidate);
        if (!available) {
          if (mounted) {
            setState(() {
              _error = '${candidate.label} 注册失败，可能已被系统或其他软件占用。';
              _saving = false;
            });
          }
          return;
        }
      } catch (_) {
        // 测试环境或无原生实现时不阻断保存
      }

      await widget.settingsRepository.setBossKey(candidate);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '保存失败: $e';
          _saving = false;
        });
      }
    }
  }

  Future<void> _restoreDefaults() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.settingsRepository
          .setBossKey(const PlayerKeyBinding('keyQ', alt: true));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '恢复失败: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts.manager(
        manager: _dialogShortcuts,
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              if (!_saving) Navigator.of(context).pop();
              return null;
            }),
          },
          child: AlertDialog(
            key: const ValueKey('bosskey-shortcut-capture-dialog'),
            backgroundColor: context.palette.card,
            title: const Text('更改老板键快捷键'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      '当前：${widget.settingsRepository.playerSettings.bossKey.label}',
                      style: TextStyle(color: context.palette.textSub)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FocusOutline(
                      child: OutlinedButton.icon(
                        key: const ValueKey('restore-bosskey-shortcut'),
                        style: _outlinedStyle(context),
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        label: const Text('恢复此项默认 (Alt + Q)'),
                        onPressed: _saving
                            ? null
                            : () => unawaited(_restoreDefaults()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Focus(
                    focusNode: _captureFocus,
                    autofocus: true,
                    onFocusChange: (focused) =>
                        setState(() => _captureFocused = focused),
                    onKeyEvent: _capture,
                    child: Semantics(
                      label: '老板键快捷键捕获区，按下新组合键，必须包含 Ctrl、Alt 或 Shift',
                      button: true,
                      liveRegion: true,
                      onTap: _captureFocus.requestFocus,
                      child: GestureDetector(
                        key: const ValueKey('bosskey-shortcut-capture-area'),
                        onTap: _captureFocus.requestFocus,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: _captureFocused
                                  ? context.palette.accentInk
                                  : context.palette.borderStrong,
                              width: _captureFocused ? 2 : 1,
                            ),
                          ),
                          child: Text(_candidate?.label ?? '请按下新组合键',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppType.h2,
                                  color: context.palette.textTitle)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      '必须包含修饰键（Ctrl、Alt 或 Shift）或为功能键（F1~F12）。\n'
                      '保存时会自动向 Windows 系统测试注册并防范按键冲突。',
                      style: TextStyle(
                          fontSize: AppType.body,
                          height: 1.5,
                          color: context.palette.textSub)),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            key: const ValueKey('bosskey-shortcut-error'),
                            style: TextStyle(
                                color: context.palette.warning, height: 1.4))),
                  ],
                ],
              ),
            ),
            actions: [
              FocusOutline(
                  child: OutlinedButton(
                key: const ValueKey('cancel-bosskey-shortcut'),
                style: _outlinedStyle(context),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              )),
              FocusOutline(
                  child: ElevatedButton(
                key: const ValueKey('save-bosskey-shortcut'),
                style: _primaryStyle(context),
                onPressed: _saving || _candidate == null || _error != null
                    ? null
                    : () => unawaited(_save()),
                child: Text(_saving ? '正在测试并保存…' : '保存'),
              )),
            ],
          ),
        ),
      );
}
