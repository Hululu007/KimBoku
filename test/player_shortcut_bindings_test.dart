import 'package:flutter_test/flutter_test.dart';
import 'package:xiugou_tv/core/settings/models/player_shortcut_bindings.dart';

/// 「广告调试」面板上线后（D 键）的按键占用回归：
/// D 是调试面板，弹幕退到 B，并且任何时候都不能一键两用。
void main() {
  test('默认绑定：D = 广告调试，I = 播放信息，B = 弹幕，且没有重复占用', () {
    const bindings = PlayerShortcutBindings.defaults;
    expect(bindings.keysFor(PlayerShortcutAction.adDebug).single.key, 'keyD');
    expect(bindings.keysFor(PlayerShortcutAction.infoOsd).single.key, 'keyI');
    expect(
        bindings.keysFor(PlayerShortcutAction.toggleDanmaku).single.key, 'keyB');

    final seen = <PlayerKeyBinding>{};
    for (final action in PlayerShortcutAction.values) {
      for (final binding in bindings.keysFor(action)) {
        expect(seen.add(binding), isTrue,
            reason: '${binding.label} 被多个动作同时占用');
      }
    }
  });

  test('旧配置（弹幕仍是 D、没有 adDebug 字段）载入后整体回落新默认', () {
    final legacy = <String, Object>{
      'version': 1,
      'bindings': {
        'playPause': [
          {'key': 'space'}
        ],
        'toggleDanmaku': [
          {'key': 'keyD'}
        ],
      },
    };
    final parsed = PlayerShortcutBindings.fromJson(legacy);
    // 冲突触发整体回落：不会出现「D 既是弹幕又是调试」。
    expect(parsed.keysFor(PlayerShortcutAction.adDebug).single.key, 'keyD');
    expect(
        parsed.keysFor(PlayerShortcutAction.toggleDanmaku).single.key, 'keyB');
  });

  test('自定义过其它键的配置保持原样', () {
    final stored = <String, Object>{
      'version': 1,
      'bindings': {
        'playPause': [
          {'key': 'keyK'}
        ],
        'toggleMute': [
          {'key': 'keyM'}
        ],
        'adDebug': [
          {'key': 'f9'}
        ],
      },
    };
    final parsed = PlayerShortcutBindings.fromJson(stored);
    expect(parsed.keysFor(PlayerShortcutAction.playPause).single.key, 'keyK');
    expect(parsed.keysFor(PlayerShortcutAction.adDebug).single.key, 'f9');
  });
}
