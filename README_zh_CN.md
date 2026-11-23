<div align="center">

<img src="assets/images/icon.png" alt="FlClash" width="88">

# FlClash

基于 ClashMeta 的多平台代理客户端，简单易用，开源无广告。

[English](README.md) · **简体中文**

[![Release](https://img.shields.io/github/v/release/chen08209/FlClash?style=flat-square&label=release)](https://github.com/chen08209/FlClash/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/chen08209/FlClash/total?style=flat-square&logo=github)](https://github.com/chen08209/FlClash/releases)
[![License](https://img.shields.io/github/license/chen08209/FlClash?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-channel-26A5E4?style=flat-square&logo=telegram&logoColor=white)](https://t.me/FlClash)

[官网](https://chen08209.github.io/FlClash/zh) · [下载](#下载) · [更新日志](CHANGELOG.md) · [从源码构建](#从源码构建)

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="snapshots/preview-dark.png">
    <img alt="FlClash 在 MacBook 与手机上的仪表盘" src="snapshots/preview.png" width="92%">
  </picture>
</p>

## 功能

- **一个应用覆盖 Android、Windows、macOS 和 Linux**，桌面端同时提供 x64 与 ARM64 版本。
- **mihomo（Clash.Meta）内核**：规则分流、代理组、延迟测试、系统代理与 TUN 模式。
- **配置管理**：通过订阅链接或文件导入配置，内置编辑器，支持覆写脚本以及自定义规则、代理和代理组。
- **实时查看**连接、请求、DNS 查询和日志。
- **Material You 设计，融合 Apple 式交互**：支持动态取色、浅色与深色主题，连续曲率圆角，弹出面板可在几档高度间吸附，布局随屏幕从手机到桌面自适应。
- **备份与恢复**：通过 WebDAV 或本地文件。
- **平台细节**：Android 上有快捷设置磁贴、分应用代理和 Android TV 支持；桌面端有托盘菜单和全局快捷键。
- **开源无广告**，以 GPL-3.0 协议发布。

## 下载

从 [GitHub Releases](https://github.com/chen08209/FlClash/releases/latest) 获取最新版本，或打开
[官网](https://chen08209.github.io/FlClash/zh#download)，它会自动为你的设备选好安装包。

| 平台 | 安装包 | 说明 |
| --- | --- | --- |
| Android | `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 APK | 绝大多数手机选 `arm64-v8a`。也可以通过下方的 F-Droid 仓库安装。 |
| Windows 10 及以上 | 安装版（`.exe`）或便携版（`.zip`），分 x64 与 ARM64 | 骁龙等 ARM 架构笔记本选 ARM64。 |
| macOS 12 及以上 | Apple Silicon 与 Intel 两种 DMG | 也可以通过 Homebrew 安装。 |
| Linux | `.deb`、`.rpm` 和 AppImage，分 x64 与 ARM64 | 托盘依赖见下方说明。 |

<p>
  <a href="https://chen08209.github.io/FlClash-fdroid-repo/repo?fingerprint=789D6D32668712EF7672F9E58DEEB15FBD6DCEEC5AE7A4371EA72F2AAE8A12FD"><img alt="Get it on F-Droid" src="snapshots/get-it-on-fdroid.svg" height="56"></a>
  <a href="https://github.com/chen08209/FlClash/releases/latest"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" height="56"></a>
</p>

**Homebrew**

```bash
brew tap chen08209/tap
brew install --cask flclash
```

**Linux 托盘图标**

`.deb` 安装包会自动安装所需依赖。使用 AppImage 或 `.rpm` 时，需要先安装 AyatanaAppIndicator 库，托盘图标才能显示：

```bash
sudo apt-get install libayatana-appindicator3-1   # Debian 与 Ubuntu
sudo dnf install libayatana-appindicator-gtk3     # Fedora
```

**无人值守的桌面环境**

FlClash 要在免责声明被接受后才会启动核心。在容器等无人点击的环境里，可在应用的环境变量中设置
`FLCLASH_ACCEPT_DISCLAIMER=1`，首次启动时即视为接受。

## 使用

**通过链接导入配置。** 打开下面格式的链接，即可把订阅导入 FlClash。`clashmeta://` 和 `flclash://` 开头的链接同样可用。

```text
clash://install-config?url=<经过 URL 编码的订阅链接>
```

**Android 自动化。** Tasker、MacroDroid 等应用可以用下面的 Action 启动 Activity，从而启动、停止或切换代理：

```text
com.follow.clash.action.START
com.follow.clash.action.STOP
com.follow.clash.action.TOGGLE
```

在电脑上也可以通过 adb 触发：

```bash
adb shell am start -a com.follow.clash.action.TOGGLE
```

## 从源码构建

需要 [Flutter](https://docs.flutter.dev/get-started/install) 3.47（正式版构建使用 3.47.6）、[Go](https://go.dev/dl/) 1.27，
以及通过 rustup 安装的 [Rust](https://rustup.rs/)。桌面端需要在对应系统上构建，Android 在任意系统上都能构建。

```bash
git clone --recursive https://github.com/chen08209/FlClash.git
cd FlClash
flutter pub get
dart setup.dart android   # 或 windows、macos、linux
```

安装包输出到 `dist/`。Go 内核和 Rust 库会在 Flutter 构建过程中一并编译。

| 平台 | 额外依赖 |
| --- | --- |
| Android | 带 NDK 的 Android SDK。加上 `--arch arm64` 可以只构建单个 ABI。 |
| Windows | 编译内核用的 GCC（MinGW-w64），以及打包安装程序用的 [Inno Setup](https://jrsoftware.org/isinfo.php) 6。 |
| macOS | Xcode 与 Node.js。脚本会通过 npm 安装 `appdmg`。 |
| Linux | Debian 或 Ubuntu。脚本会用 apt 安装构建所需的软件包，并下载 `appimagetool`。 |

其余选项可以运行 `dart setup.dart --help` 查看，例如用 `--targets` 只构建部分安装包格式。

### GVBoard 专属客户端构建

本项目的默认 Release 构建为 GVBoard 专属客户端：自动使用 OSS 配置、GVBoard 登录和订阅，主界面不显示配置管理入口。
如果某个渠道包需要保留 FlClash 的配置管理功能，可以在构建时显式关闭专属界面：

```bash
flutter build windows --dart-define=GVBOARD_DEDICATED_CLIENT=false
flutter build apk --dart-define=GVBOARD_DEDICATED_CLIENT=false
```

专属客户端也可以显式指定：

```bash
flutter build windows --dart-define=GVBOARD_DEDICATED_CLIENT=true
```

这个开关只控制配置管理页面是否显示，不会关闭 GVBoard 登录、商店、我的、自动订阅和离线缓存功能。

### OSS 加密配置

专属客户端构建需要注入 OSS 解密密钥。密钥支持 32 字节 Base64 或 64 位十六进制格式：

```bash
flutter build windows --release \
  --dart-define=GVBOARD_DEDICATED_CLIENT=true \
  --dart-define=GVBOARD_OSS_KEY="<32-byte-base64-key>"
```

将明文配置加密为云端文件：

```bash
dart run tool/encrypt_oss.dart \
  --input client.json \
  --output client.oss \
  --key "<32-byte-base64-key>"
```

然后在 `assets/oss/index.json` 中使用加密 OSS 文件的 HTTPS 地址。客户端获取到的是 AES-256-GCM 加密内容，解密成功后才解析为 OSS 配置。

### 上传 GitHub 与打包客户端

上传仓库时应保留源码、`android/`、`windows/`、`plugins/`、`services/`、`core/`（以及它的 Git submodule）、`assets/`、`lib/`、`tool/`、`pubspec.yaml`、`pubspec.lock`、`build_config.yaml` 和 `.github/`。不要上传 `build/`、`dist/`、`.dart_tool/`、`libclash/`、`android/app/keystore.jks`、`android/local.properties`、`env.json` 或任何个人缓存。

仓库自带 `.github/workflows/package.yml`，在 GitHub 的 **Actions → package clients → Run workflow** 中可手动打包 Android、Windows 或两者。工作流参数可以修改应用名称、Windows 可执行文件名、Android 包名、版本号、构建号和 OSS 地址，产物会作为 Actions Artifact 下载；Windows 产物会自动压缩为 zip。

在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 中配置：

- `GVBOARD_OSS_KEY`：OSS AES-256-GCM 解密密钥；
- `KEYSTORE`：Android 发布签名文件的 Base64；
- `KEY_ALIAS`、`STORE_PASSWORD`、`KEY_PASSWORD`：签名信息。

没有配置签名 Secrets 时，Android 会使用 debug 签名并自动追加 `.dev` 包名后缀，只适合测试安装。正式发布必须配置自己的签名文件。

默认品牌配置集中在根目录 `branding.yaml`：名称、Windows 可执行文件名、Android 包名、版本号以及 Android/Windows 图标源文件都在其中记录。修改图标后，Android 端需要同步替换 `android/app/src/main/res/mipmap-*` 下的启动图标资源，Windows 端替换 `windows/runner/resources/app_icon.ico`；不要只修改 Flutter 页面中的 logo，因为系统桌面图标由原生资源提供。

## 支持

给仓库点一个 Star 是支持项目最简单的方式。问题讨论和更新通知请关注 [Telegram 频道](https://t.me/FlClash)，
Bug 与功能建议请提交到 [GitHub Issues](https://github.com/chen08209/FlClash/issues)。

<a href="https://star-history.com/#chen08209/FlClash&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=chen08209/FlClash&type=Date&theme=dark">
    <img alt="Star history" src="https://api.star-history.com/svg?repos=chen08209/FlClash&type=Date" width="640">
  </picture>
</a>

## 许可证

FlClash 以 [GPL-3.0 协议](LICENSE)发布。
