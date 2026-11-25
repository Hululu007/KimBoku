import 'package:flutter_test/flutter_test.dart';
import 'package:xiugou_tv/core/boss_key/boss_key_service.dart';
import 'package:xiugou_tv/core/player/models/player_settings.dart';
import 'package:xiugou_tv/core/settings/models/player_shortcut_bindings.dart';

void main() {
  group('PlayerSettings 老板键偏好测试', () {
    test('默认配置开启老板键，且默认快捷键为 Alt + Q', () {
      const settings = PlayerSettings();
      expect(settings.bossKeyEnabled, isTrue);
      expect(settings.bossKey.key, 'keyQ');
      expect(settings.bossKey.alt, isTrue);
      expect(settings.bossKey.control, isFalse);
      expect(settings.bossKey.shift, isFalse);
      expect(settings.bossKey.label, 'Alt + Q');
    });

    test('空 JSON 反序列化时自动赋默认值', () {
      final settings = PlayerSettings.fromJson({});
      expect(settings.bossKeyEnabled, isTrue);
      expect(settings.bossKey.label, 'Alt + Q');
    });

    test('从 JSON 反序列化自定义老板键', () {
      final settings = PlayerSettings.fromJson({
        'bossKeyEnabled': false,
        'bossKey': {
          'key': 'keyH',
          'control': true,
          'shift': true,
        },
      });
      expect(settings.bossKeyEnabled, isFalse);
      expect(settings.bossKey.key, 'keyH');
      expect(settings.bossKey.control, isTrue);
      expect(settings.bossKey.shift, isTrue);
      expect(settings.bossKey.alt, isFalse);
      expect(settings.bossKey.label, 'Ctrl + Shift + H');
    });

    test('toJson 序列化正确保存老板键状态与按键', () {
      const custom = PlayerSettings(
        bossKeyEnabled: false,
        bossKey: PlayerKeyBinding('keyZ', control: true, alt: true),
      );
      final json = custom.toJson();
      expect(json['bossKeyEnabled'], isFalse);
      expect(json['bossKey'], {
        'key': 'keyZ',
        'control': true,
        'alt': true,
      });
    });
  });

  group('BossKeyService 快捷键编码与映射测试', () {
    test('Win32 修饰键掩码正确计算', () {
      expect(
          BossKeyService.getWin32Modifiers(
              const PlayerKeyBinding('keyQ', alt: true)),
          0x0001); // MOD_ALT
      expect(
          BossKeyService.getWin32Modifiers(
              const PlayerKeyBinding('keyQ', control: true)),
          0x0002); // MOD_CONTROL
      expect(
          BossKeyService.getWin32Modifiers(
              const PlayerKeyBinding('keyQ', shift: true)),
          0x0004); // MOD_SHIFT
      expect(
          BossKeyService.getWin32Modifiers(
              const PlayerKeyBinding('keyQ', alt: true, control: true)),
          0x0003); // MOD_ALT | MOD_CONTROL
      expect(
          BossKeyService.getWin32Modifiers(const PlayerKeyBinding(
              'keyQ', alt: true, control: true, shift: true)),
          0x0007);
    });

    test('Win32 虚拟键码正确映射', () {
      expect(BossKeyService.getWin32VkCode('keyQ'), 0x51); // 'Q'
      expect(BossKeyService.getWin32VkCode('keyA'), 0x41); // 'A'
      expect(BossKeyService.getWin32VkCode('digit1'), 0x31); // '1'
      expect(BossKeyService.getWin32VkCode('f1'), 0x70); // VK_F1
      expect(BossKeyService.getWin32VkCode('f12'), 0x7B); // VK_F12
      expect(BossKeyService.getWin32VkCode('space'), 0x20); // VK_SPACE
      expect(BossKeyService.getWin32VkCode('backquote'), 0xC0); // VK_OEM_3 (~)
      expect(BossKeyService.getWin32VkCode('escape'), 0x1B); // VK_ESCAPE
    });

    test('BossKeyService 快捷键合法性校验', () {
      // 合法快捷键：包含修饰键
      expect(
          BossKeyService.validateBossKey(
              const PlayerKeyBinding('keyQ', alt: true)),
          isNull);
      expect(
          BossKeyService.validateBossKey(
              const PlayerKeyBinding('keyH', control: true, shift: true)),
          isNull);
      // 合法快捷键：功能键（F1~F24）允许无修饰键
      expect(
          BossKeyService.validateBossKey(const PlayerKeyBinding('f12')),
          isNull);

      // 非法快捷键：纯字母/符号无修饰键（避免拦截正常打字）
      expect(
          BossKeyService.validateBossKey(const PlayerKeyBinding('keyQ')),
          contains('必须包含修饰键'));
      expect(
          BossKeyService.validateBossKey(const PlayerKeyBinding('space')),
          contains('必须包含修饰键'));

      // 非法快捷键：系统保留按键
      expect(
          BossKeyService.validateBossKey(
              const PlayerKeyBinding('f4', alt: true)),
          contains('系统保留按键'));
      expect(
          BossKeyService.validateBossKey(
              const PlayerKeyBinding('delete', control: true, alt: true)),
          contains('系统保留按键'));
      expect(
          BossKeyService.validateBossKey(const PlayerKeyBinding('escape')),
          contains('系统保留按键'));
    });
  });
}
