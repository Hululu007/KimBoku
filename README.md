# KimBoKu（金播库）

<p align="center">
  <img src="assets/icons/kimboku_banner.png" width="760" alt="KimBoKu 品牌标识">
</p>

<p align="center">
  <a href="https://github.com/jacurtwong/KimBoku/releases/latest"><img src="https://img.shields.io/badge/平台-Windows%2010%2F11%20x64-0078D4?logo=windows" alt="平台"></a>
  <a href="https://github.com/jacurtwong/KimBoku/releases/latest"><img src="https://img.shields.io/badge/版本-1.4.8-2ea44f" alt="版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/许可证-GPL--3.0-blue" alt="许可证"></a>
  <a href="https://github.com/jacurtwong/KimBoku/releases/latest"><img src="https://img.shields.io/github/downloads/jacurtwong/KimBoku/total?color=blueviolet" alt="下载统计"></a>
</p>

---

## 💡 简介

**KimBoKu（金播库）** 是一款面向 Windows 10/11 x64 桌面生态深度定制的高性能视听聚合客户端。

项目融合原生 Direct3D 11 硬件加速解码与独立 JVM 伴随运行时，打造丝滑无损、零冗余的多源流媒体播放体验。导入你自有的影视配置源后，即可在统一优雅的现代桌面界面中完成全站搜片、分类浏览、分集播放与电视直播。

> **免责声明**：本软件为纯播放器与客户端工具，本身不提供、不存储、不分发任何音视频资源或配置。所有流媒体内容均由使用者自行添加的配置源解析呈现。

---

## ⚡ 核心亮点

- 🎬 **原生双核架构**：基于 Flutter 现代交互引擎 + libmpv（media_kit）底层驱动，支持 D3D11VA 与 DXVA2 硬件解码，4K/HDR 播放低功耗无卡顿。
- 🛡️ **HLS 智能广告无感剪辑**：内置本地回环清单过滤代理与切片算法，点播时智能分析识别 `#EXT-X-DISCONTINUITY` 插播广告分片并在播放前无损剪除，直连 CDN 片源。
- 📊 **透明可观测浮层**：
  - **快捷键 `D`**：即时唤出「广告剪辑诊断面板」，清晰查看切片判断逻辑、剪前/剪后时长及各分段明细。
  - **快捷键 `I`**：即时唤出「播放信息 OSD」，实时监控左上角真实视频分辨率、右上角系统时间、左下角进度与右下角底层瞬时下载速度与缓冲秒数。
  - 浮层完全采用鼠标穿透（`IgnorePointer`），不拦截点击、不抢占焦点、不影响全屏与退出。
- 🧩 **全生态影视配置兼容**：遵循开放解析层规范，直接兼容 Tvbox / CatVod spider 插件（JAR/Java、Node、Python、道长 T3/T4），现存配置源直接开箱复用。
- 📺 **点播与直播一体化**：全网聚合搜索多线路聚合筛选、海报墙智能瀑布流、电视直播频道分组、EPG 电子节目单及播放区滚轮切台。
- 🎛️ **专业桌面级控制**：音轨/视轨/字幕轨毫秒级切换，外挂 SRT / ASS / SSA / VTT 字幕及等比字号缩放，0.5x~3.0x 任意倍速，毫秒级片头片尾自动跳过。
- 🔒 **独立自建与安全**：所有配置、播放记录与历史数据严格保存在本地；更新系统彻底独立脱钩，纯净无第三方遥测。

---

## 🖥️ 功能全览

### 1. 内容与源管理
- **配置导入**：支持影视源 JSON、多仓仓库清单及 CMS 资源站导入；相对地址（api / ext / jar）自动补全。
- **本地包导入**：支持一键导入包含配置与 jar 的猫源 ZIP 压缩包，自动识别解压与装载。
- **环境免配**：安装包已随包捆绑预置 JRE、Node.js、Python 等微运行时，无需用户额外配置系统环境变量。
- **健康度体检**：内置站点自检与分类探活机制，秒级定位失效或响应缓慢的站点。
- **浏览器验证穿透**：针对具备验证码或防盗链校验的站点，支持以沙箱浏览器身份完成验证并平滑续播。

### 2. 点播浏览与聚合搜索
- **沉浸式画廊**：高帧率海报瀑布流，站点与分类无缝水平横滚，滚动触底增量加载。
- **多站点聚合搜索**：输入关键字跨站点并发检索，实时聚合各站结果；可根据配置单独勾选参与搜索的站点。
- **影片详情与资料补全**：提供经典与新版两套详情版式，支持展示同站同片历史观看进度，并对豆瓣/TMDB 缺项资料进行同片核验补全。

### 3. 播放控制与解码
- **多轨调度**：视频轨、音轨、字幕轨自由切换，支持软解与 D3D11VA 硬解热切换。
- **外挂字幕**：支持将外部 SRT、ASS、SSA、VTT 字幕拖拽或选择挂载，文字字幕支持 75%~200% 动态字号无损缩放。
- **播放连续性保证**：换线失败自动尝试备用线路；播放过程由伴随服务维持租约，遇异常网络闪断自动实现有界恢复。

### 4. 电视直播
- **多格式导入**：支持 TXT、M3U、M3U8、JSON 频道表导入。
- **EPG 节目单**：支持查看当前正在播放节目与后续时间表。
- **滚轮切台**：播放画面中央及偏左区域滚轮上下滚动即时切台，右侧控制音量。

### 5. 存储与系统
- **数据自主掌控**：支持设置自定义本地数据目录；全量设置、历史、收藏与源一键 JSON 导出与恢复。
- **界面定制**：浅色、深色、跟随系统三种外观主题，支持自定义本地高清壁纸。

---

## 📥 下载与安装

适用于 **Windows 10 / 11 x64** 操作系统。

| 版本类型 | 文件名格式 | 适用场景 |
| :--- | :--- | :--- |
| **标准安装包** | `kimboku-windows-x64-v1.4.3-setup.exe` | 推荐普通用户使用，附带完整开始菜单与快捷方式，支持平滑覆盖升级 |
| **便携绿色版** | `kimboku-windows-x64-v1.4.6-portable.zip` | 解压至任意具备写权限的目录即可直接运行 `KimBoKu.exe`，不留系统注册痕迹 |

> **下载地址**：请前往 [GitHub Releases](https://github.com/jacurtwong/KimBoku/releases/latest) 获取最新发布产物。
>
> 每次发行均附带对应的 `SHA256SUMS` 校验清单文件，建议在下载后使用 `certutil -hashfile <包名> SHA256` 核对哈希一致性。

---

## ⌨️ 快捷键速查

| 按键 | 功能 | 说明 |
| :---: | :--- | :--- |
| **Space** | 播放 / 暂停 | 快速启停 |
| **← / →** | 后退 / 前进 | 步进跳转进度 |
| **↑ / ↓** | 音量调节 | 步进调整系统/引擎音量 |
| **F** | 全屏切换 | 进入 / 退出全屏 |
| **M** | 静音切换 | 快速静音 |
| **D** | 广告剪辑调试面板 | 唤起/隐藏右上角 HLS 广告剪辑决策与分段详情卡片 |
| **I** | 播放信息 OSD | 唤起/隐藏四角实时信息浮层（分辨率、系统时间、进度、缓冲与真实速度） |
| **B** | 弹幕开关 | 开启 / 关闭弹幕渲染 |
| **Esc** | 返回 / 退出 | 退出选集抽屉、退出全屏或退出当前播放页面 |

---

## 🛠️ 从源码构建

### 环境要求
- Windows 10 / 11 x64
- [Flutter SDK](https://flutter.dev) (>= 3.44.0) 与 Dart SDK (>= 3.12.0)
- Visual Studio 2022（需勾选 "Desktop development with C++"）
- Inno Setup 6+（用于打包 Windows 安装程序）
- PowerShell 7+

### 构建步骤
```powershell
# 1. 克隆代码仓库
git clone https://github.com/jacurtwong/KimBoku.git
cd KimBoku

# 2. 安装 Flutter 依赖
flutter pub get

# 3. 运行本地自动化单测
flutter test

# 4. 执行全自动化流水线构建（包含编译 Release、注入 Commit、打包安装器与便携包、生成 SHA256SUMS）
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
```

构建成功后，所有最终物料将输出在 `dist/` 目录下。

---

## 📜 鸣谢与生态开源

- 本项目基于开源仓库 [qfw66/xiugou-tv](https://github.com/qfw66/xiugou-tv) 原版 v1.12.5 修改与演进，在此对其作者与贡献者表达诚挚感谢。
- 本项目的播放内核深度依托于 [media_kit](https://github.com/media-kit/media-kit)（基于卓越的 libmpv 开源多媒体套件）。
- 影视配置与插件兼容规范参考并吸纳了 FongMi（[FongMi/TV](https://github.com/FongMi/TV)）以及 TVBox / CatVod 开放社区的长期实践，特此致敬所有无私奉献的开源作者。
- 更多第三方组件及其遵循的许可证说明，请详见安装目录下的 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

---

## 📄 开源许可证

本项目依据 **GPL-3.0** 开源许可证分发与维护，完整许可条款详见 [LICENSE](LICENSE)。
