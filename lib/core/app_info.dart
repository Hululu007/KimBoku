import 'package:package_info_plus/package_info_plus.dart';

/// 程序显示名：窗口标题、关于页、侧栏、安装器统一用它。
const String appDisplayName = 'KimBoKu';

/// 窄位置（侧栏）用的短名。
const String appShortName = 'KimBoKu';

/// 构建注入的应用版本（`package_info_plus` 读取 exe 版本资源），供备份等
/// 非 UI 路径使用；未加载或读取失败时为 null（调用方兜底为「未知版本」）。
String? appVersionLabel;

/// 读取并缓存版本号；失败时保持 null（不写占位版本）。
///
/// 只取 `version`，不拼 build 号：build 号是构建自增标记，不参与更新判断
/// （`AppVersion.tryParse` 会丢弃 `+` 后缀），展示出来只会造成歧义。
Future<String?> loadAppVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    appVersionLabel = info.version;
  } catch (_) {
    appVersionLabel = null;
  }
  return appVersionLabel;
}
