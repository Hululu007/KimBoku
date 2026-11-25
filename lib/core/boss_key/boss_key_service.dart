import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../player/models/player_state.dart';
import '../player/mpv_player_engine.dart';
import '../settings/models/player_shortcut_bindings.dart';
import '../settings/settings_repository.dart';
import '../../ui/desktop/window/desktop_window_manager.dart';

/// 全局「老板键」管理服务（基于 Win32 RegisterHotKey）
class BossKeyService {
  static const MethodChannel _channel = MethodChannel('xiugou/boss_key');

  static BossKeyService? _instance;
  static BossKeyService get instance =>
      _instance ??
      (throw StateError('BossKeyService 尚未初始化，请先调用 initialize()'));

  final DesktopWindowManager windowManager;
  final MpvPlayerEngine playerEngine;
  final SettingsRepository settingsRepository;

  final ValueNotifier<String?> registrationErrorNotifier =
      ValueNotifier<String?>(null);

  StreamSubscription? _settingsSub;
  PlayerKeyBinding? _currentRegistered;
  bool _isRegistered = false;

  BossKeyService({
    required this.windowManager,
    required this.playerEngine,
    required this.settingsRepository,
  }) {
    _instance = this;
  }

  /// 校验候选快捷键是否符合全局老板键规范
  static String? validateBossKey(PlayerKeyBinding binding) {
    // 1. 避免系统核心保留快捷键
    if ((binding.alt && binding.key == 'f4') ||
        (binding.control && binding.alt && binding.key == 'delete') ||
        binding.key == 'escape') {
      return '${binding.label} 是系统保留按键，不可作为全局热键。';
    }

    // 2. 必须包含修饰键（Ctrl、Alt 或 Shift）或为功能键（F1~F24）
    final isFunctionKey =
        RegExp(r'^f([1-9]|1[0-9]|2[0-4])$').hasMatch(binding.key);
    final hasModifier = binding.alt || binding.control || binding.shift;
    if (!hasModifier && !isFunctionKey) {
      return '全局老板键必须包含修饰键（Ctrl、Alt 或 Shift）或为功能键（F1~F12），避免影响打字。';
    }

    // 3. 必须是支持映射到 Win32 虚拟键码的按键
    if (getWin32VkCode(binding.key) == null) {
      return '暂不支持将 ${binding.key} 注册为全局热键。';
    }

    return null;
  }

  /// 将 PlayerKeyBinding 的修饰键转换为 Win32 MOD_* 位掩码
  static int getWin32Modifiers(PlayerKeyBinding binding) {
    int mod = 0;
    if (binding.alt) mod |= 0x0001; // MOD_ALT
    if (binding.control) mod |= 0x0002; // MOD_CONTROL
    if (binding.shift) mod |= 0x0004; // MOD_SHIFT
    return mod;
  }

  /// 将 PlayerKeyBinding 的 key 转换为 Win32 虚拟键码 (Virtual Key Code)
  static int? getWin32VkCode(String key) {
    // 字母 keyA..keyZ -> 0x41..0x5A
    if (key.length == 4 && key.startsWith('key')) {
      final char = key.codeUnitAt(3);
      if (char >= 65 && char <= 90) return char;
    }
    // 数字 digit0..digit9 -> 0x30..0x39
    if (key.length == 6 && key.startsWith('digit')) {
      final digit = key.codeUnitAt(5);
      if (digit >= 48 && digit <= 57) return digit;
    }
    // 功能键 f1..f24 -> 0x70..0x87
    if (key.startsWith('f')) {
      final numVal = int.tryParse(key.substring(1));
      if (numVal != null && numVal >= 1 && numVal <= 24) {
        return 0x70 + (numVal - 1);
      }
    }
    // 数字小键盘 0..9 -> 0x60..0x69
    if (key.startsWith('numpad') && key.length == 7) {
      final digit = key.codeUnitAt(6);
      if (digit >= 48 && digit <= 57) {
        return 0x60 + (digit - 48);
      }
    }

    switch (key) {
      case 'space':
        return 0x20;
      case 'escape':
        return 0x1B;
      case 'enter':
      case 'numpadEnter':
        return 0x0D;
      case 'tab':
        return 0x09;
      case 'backspace':
        return 0x08;
      case 'insert':
        return 0x2D;
      case 'delete':
        return 0x2E;
      case 'home':
        return 0x24;
      case 'end':
        return 0x23;
      case 'pageUp':
        return 0x21;
      case 'pageDown':
        return 0x22;
      case 'arrowLeft':
        return 0x25;
      case 'arrowUp':
        return 0x26;
      case 'arrowRight':
        return 0x27;
      case 'arrowDown':
        return 0x28;
      case 'backquote':
        return 0xC0; // ` or ~
      case 'minus':
        return 0xBD;
      case 'equal':
        return 0xBB;
      case 'bracketLeft':
        return 0xDB;
      case 'bracketRight':
        return 0xDD;
      case 'backslash':
        return 0xDC;
      case 'semicolon':
        return 0xBA;
      case 'quote':
        return 0xDE;
      case 'comma':
        return 0xBC;
      case 'period':
        return 0xBE;
      case 'slash':
        return 0xBF;
      case 'numpadAdd':
        return 0x6B;
      case 'numpadSubtract':
        return 0x6D;
      case 'numpadMultiply':
        return 0x6A;
      case 'numpadDivide':
        return 0x6F;
      case 'numpadDecimal':
        return 0x6E;
      default:
        return null;
    }
  }

  /// 初始化服务并开始监听热键触发与偏好变动
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleNativeCall);

    // 首次注册当前偏好
    final initialSettings = settingsRepository.playerSettings;
    await _applySettings(
      enabled: initialSettings.bossKeyEnabled,
      binding: initialSettings.bossKey,
    );

    // 监听后续偏好变动
    _settingsSub = settingsRepository.playerSettingsStream.listen((settings) {
      _applySettings(
        enabled: settings.bossKeyEnabled,
        binding: settings.bossKey,
      );
    });
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onBossKeyPressed') {
      await onBossKeyPressed();
    }
  }

  /// 老板键被按下时的响应动作
  Future<void> onBossKeyPressed() async {
    await windowManager.toggleBossKey(
      onBeforeHide: () {
        // 自动暂停视频播放
        if (playerEngine.status == PlaybackStatus.playing) {
          playerEngine.pause();
        }
      },
    );
  }

  /// 测试某个快捷键是否能成功被系统注册（用于设置弹窗中预先验证占用）
  Future<bool> testRegister(PlayerKeyBinding binding) async {
    final vk = getWin32VkCode(binding.key);
    if (vk == null) return false;
    final mod = getWin32Modifiers(binding);

    try {
      final success = await _channel.invokeMethod<bool>('register', {
        'modifiers': mod,
        'vkCode': vk,
      });

      // 测试完毕后还原之前的全局热键注册
      if (_isRegistered && _currentRegistered != null) {
        final curVk = getWin32VkCode(_currentRegistered!.key);
        if (curVk != null) {
          await _channel.invokeMethod<bool>('register', {
            'modifiers': getWin32Modifiers(_currentRegistered!),
            'vkCode': curVk,
          });
        }
      } else {
        await _channel.invokeMethod<bool>('unregister');
      }

      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applySettings({
    required bool enabled,
    required PlayerKeyBinding binding,
  }) async {
    if (!enabled) {
      if (_isRegistered) {
        try {
          await _channel.invokeMethod<bool>('unregister');
        } catch (_) {}
        _isRegistered = false;
        _currentRegistered = null;
      }
      registrationErrorNotifier.value = null;
      return;
    }

    final vk = getWin32VkCode(binding.key);
    if (vk == null) {
      registrationErrorNotifier.value = '不支持将 ${binding.label} 设为全局热键';
      return;
    }

    final mod = getWin32Modifiers(binding);
    try {
      final success = await _channel.invokeMethod<bool>('register', {
        'modifiers': mod,
        'vkCode': vk,
      });

      if (success == true) {
        _isRegistered = true;
        _currentRegistered = binding;
        registrationErrorNotifier.value = null;
      } else {
        _isRegistered = false;
        registrationErrorNotifier.value =
            '${binding.label} 注册失败，可能已被系统或其他软件占用';
      }
    } catch (e) {
      _isRegistered = false;
      registrationErrorNotifier.value = '热键通道调用失败: $e';
    }
  }

  void dispose() {
    _settingsSub?.cancel();
    if (_isRegistered) {
      unawaited(_channel.invokeMethod<bool>('unregister').catchError((_) => false));
      _isRegistered = false;
    }
  }
}
