# GVBoard Client

这是一个基于 Flutter 和 mihomo（Clash.Meta）核心的客户端项目。本仓库已经包含 GVBoard 专属客户端、远程 OSS 配置、Android/Windows GitHub Actions 打包流程以及 `core/Clash.Meta` Git submodule。

本文面向 Fork 本项目后自行制作客户端的用户，说明从配置、OSS 加密到 GitHub Actions 打包的完整流程。

## 目录

- [Fork 后的准备工作](#fork-后的准备工作)
- [GitHub Actions 打包](#github-actions-打包)
- [GitHub Secrets](#github-secrets)
- [品牌和版本配置](#品牌和版本配置)
- [OSS 配置](#oss-配置)
- [创建和加密 OSS 文件](#创建和加密-oss-文件)
- [本地构建](#本地构建)
- [常见问题和注意事项](#常见问题和注意事项)

## Fork 后的准备工作

### 1. 确认 submodule 可访问

本项目依赖 `core/Clash.Meta`。仓库根目录的 `.gitmodules` 中记录了它的地址和 `FlClash` 分支。克隆时必须递归拉取 submodule：

```bash
git clone --recursive https://github.com/<你的用户名>/gvboard-client.git
cd gvboard-client
```

如果已经普通克隆过仓库，再执行：

```bash
git submodule update --init --recursive
```

如果你修改了 `.gitmodules`，或者使用了私有的 Clash.Meta Fork，必须确保 GitHub Actions 使用的 Token 也有权限读取该 submodule。公开 submodule 不需要额外授权。

### 2. 确认 Actions 权限

进入 Fork 后的仓库：

`Settings → Actions → General`

确认允许 Actions 执行，并允许工作流创建和上传 Artifact。首次使用时，在：

`Actions → package clients`

点击启用工作流（如果 GitHub 显示该按钮）。

## GitHub Actions 打包

仓库中的 `.github/workflows/package.yml` 提供手动打包流程。使用步骤：

1. 打开 GitHub 仓库的 **Actions**。
2. 选择 **package clients**。
3. 点击 **Run workflow**。
4. 填写参数并点击运行。
5. 等待任务完成，在任务页面底部的 **Artifacts** 下载产物。

工作流参数如下：

| 参数 | 作用 | 示例 |
| --- | --- | --- |
| `name` | 客户端显示名称、窗口标题及 Android 应用名称 | `My Client` |
| `binary_name` | Windows 可执行文件名，不要填写 `.exe` | `MyClient` |
| `application_id` | Android applicationId，必须是合法且唯一的包名 | `com.example.myclient` |
| `version` | 客户端版本名称 | `1.0.0` |
| `build_number` | Android versionCode，必须是整数且应递增 | `2026112401` |
| `oss_url` | 远程加密 OSS 文件的 HTTPS 地址 | `https://example.com/client.oss` |
| `platforms` | 构建平台，可选 `android`、`windows` 或 `both` | `both` |

Android 会生成以下 ABI 的 APK：

- `arm64-v8a`：绝大多数现代 Android 手机；
- `armeabi-v7a`：旧款 32 位 ARM 设备；
- `x86_64`：部分模拟器及 x86 设备。

Windows 会生成：

```text
<binary_name>-<version>-windows-x64.zip
```

压缩包内是 Windows Release 程序目录，解压后运行自定义名称的 `.exe`。

### 签名未配置时的行为

如果没有配置 Android 签名 Secrets，工作流仍然可以完成构建，但会使用 debug 签名，并给 Android 包名自动追加 `.dev` 后缀。这种 APK 仅适合测试，不能作为正式发布包，也不能覆盖安装到已经使用正式签名发布的同包名应用上。

## GitHub Secrets

进入：

`Settings → Secrets and variables → Actions → New repository secret`

### OSS 密钥

添加：

| Secret | 内容 |
| --- | --- |
| `GVBOARD_OSS_KEY` | OSS 加密所使用的 32 字节密钥，填写 Base64 或 64 位十六进制字符串 |

密钥必须与加密 OSS 文件时使用的密钥完全一致。不要把密钥写入 Git 仓库、`index.json`、明文 OSS 文件或 Issue。

### Android 正式签名

添加以下四个 Secrets：

| Secret | 内容 |
| --- | --- |
| `KEYSTORE` | `keystore.jks` 文件的 Base64 编码内容 |
| `KEY_ALIAS` | keystore 中的 alias |
| `STORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | alias 对应的 key 密码 |

Windows 不使用 Android keystore。签名文件只应保存在 GitHub Secrets 中，不要上传 `android/app/keystore.jks` 或 `android/local.properties`。

PowerShell 将 keystore 转成 Base64 的示例：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/keystore.jks")) | Set-Clipboard
```

然后把剪贴板内容粘贴到 `KEYSTORE` Secret。不要把 Base64 内容提交到文件中。

## 品牌和版本配置

### GitHub Actions 中临时修改

最简单的方式是在 **Run workflow** 页面直接修改 `name`、`binary_name`、`application_id`、`version` 和 `build_number`。这些值只影响本次运行，不会修改仓库文件。

### 默认值：`branding.yaml`

仓库根目录的 `branding.yaml` 用于记录默认品牌信息：

```yaml
name: FlClash
binary_name: FlClash
application_id: com.follow.clash
version: 0.9.2
build_number: 2026102401
android_icon: assets/images/icon.png
windows_icon: windows/runner/resources/app_icon.ico
```

当前 GitHub 工作流的输入默认值写在 `.github/workflows/package.yml` 中。修改 `branding.yaml` 不会自动修改 Actions 输入框的默认值；如果要改变 GitHub 页面中的默认值，需要同时修改 `package.yml` 对应的 `default`。

### 直接修改源码默认值

如果需要让本地构建也使用自己的默认品牌，可以修改：

- Android 包名和应用名：`android/app/build.gradle.kts`；
- Android 公共模块应用名：`android/common/build.gradle.kts`；
- Flutter 内部默认显示名：`lib/common/constant.dart`；
- Windows 构建名称和文件属性：`windows/CMakeLists.txt`、`windows/runner/build_config.h.in`、`windows/runner/Runner.rc`；
- 窗口标题及桌面端行为：`lib/manager/window_manager.dart` 等窗口管理代码。

通常不需要改这些源码文件。优先使用 Actions 参数或本地构建时的环境变量：

```powershell
$env:CLIENT_NAME = "My Client"
$env:CLIENT_APPLICATION_ID = "com.example.myclient"
$env:CLIENT_BINARY_NAME = "MyClient"
flutter build windows --release --build-name 1.0.0 --build-number 2026112401 --dart-define=CLIENT_NAME="My Client"
```

Android 使用 `CLIENT_APPLICATION_ID` 和 `CLIENT_NAME`，Windows 使用 `CLIENT_NAME` 和 `CLIENT_BINARY_NAME`。Flutter 页面使用 `--dart-define=CLIENT_NAME=...` 获取名称，因此本地构建时建议同时设置环境变量和 `--dart-define`。

### 图标

- Android 图标源文件：`assets/images/icon.png`。GitHub Actions 会用 ImageMagick 自动生成 `mipmap-mdpi` 到 `mipmap-xxxhdpi` 的启动图标。
- Windows 图标：`windows/runner/resources/app_icon.ico`。

Android 图标建议使用正方形 PNG，Windows 必须使用有效的 `.ico` 文件。替换图标后应提交资源文件；不要提交本地生成的 `build/` 目录。

## OSS 配置

OSS 配置用于告诉客户端使用哪个网站、API、客服地址、离线策略和更新信息。字段完整示例见：

`assets/oss/example.jsonc`

程序实际读取的入口是：

`assets/oss/index.json`

默认入口如下：

```json
{
  "configs": [
    "https://example.com/client.oss",
    "assets/oss/default.json"
  ]
}
```

`configs` 会按顺序尝试：

1. HTTPS 地址：下载 Base64 编码的 AES-256-GCM 密文，使用 `GVBOARD_OSS_KEY` 解密；
2. 本地路径：读取 Flutter Asset 中的明文 JSON，例如 `assets/oss/default.json`。

远程配置失败时，程序会继续尝试后面的配置。建议保留本地 `default.json` 作为首次启动或远程服务暂时不可用时的兜底配置。正式使用时可以把它改成自己的安全默认配置，但不要在里面放服务器密码、支付密钥或其他后端 Secret。

### OSS 字段说明

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `schema_version` | 是 | 当前填写 `1`。用于区分配置格式版本。 |
| `oss_id` | 是 | 配置唯一 ID，用于本地缓存。不同客户端建议使用不同值。 |
| `website_url` | 是 | 客户端网站或主站地址。 |
| `brand.name` | 是 | 完整品牌名称。 |
| `brand.short_name` | 是 | 短品牌名称，用于空间较小的界面。 |
| `brand.logo_url` | 否 | 在线 Logo 地址；没有时填写空字符串。 |
| `apis` | 是 | API 列表，至少要有一个可用 API。 |
| `apis[].id` | 是 | API 节点标识。 |
| `apis[].base_url` | 是 | API 根地址，不要写具体业务路径除非服务端要求。 |
| `apis[].priority` | 是 | 优先级，数值越小通常越优先。 |
| `customer_service` | 是 | 客服类型和地址。当前常用 `web`。 |
| `offline.enabled` | 是 | 是否允许使用已缓存的 OSS 配置。 |
| `offline.max_days` | 是 | 离线允许使用的最长天数。 |
| `client_update` | 是 | 客户端更新提示信息；不启用时各值可为空。 |
| `network.oss_timeout_seconds` | 是 | 下载 OSS 的超时时间。 |
| `network.api_timeout_seconds` | 是 | API 请求超时时间。 |
| `network.api_retry_count` | 是 | API 请求失败后的重试次数。 |
| `cache_ttl_seconds` | 是 | 本地缓存有效期，单位为秒。 |

### `index.json` 与远程地址的注意事项

- 远程地址必须使用 HTTPS，并且返回内容必须是纯文本 Base64，不要返回 JSON 包装对象、HTML 错误页或带 Markdown 的内容。
- `oss_url` 传给 GitHub Actions 的值会替换 `assets/oss/index.json` 中 `configs[0]` 的内容，因此它应当指向加密后的 `.oss` 文件，而不是明文 `.json`。
- 如果使用 GitHub Pages、对象存储或 CDN 托管文件，确认匿名请求可以读取文件，并确认 CDN 不会把内容改写成 HTML。
- 每次更新远程 OSS 文件后，不需要重新打包客户端；客户端下次启动或缓存过期时会重新获取。若要切换密钥，则必须重新打包并更新 `GVBOARD_OSS_KEY`。

## 创建和加密 OSS 文件

### 1. 创建明文配置

复制示例文件并删除其中的注释，保存为 JSON 文件，例如：

```text
client.json
```

JSON 不支持注释。`assets/oss/example.jsonc` 是给人阅读和复制的模板，不能直接作为程序配置使用，必须先去掉 `//` 注释并保存为 `.json`。

至少要提供一个有效的 API：

```json
"apis": [
  {
    "id": "primary",
    "base_url": "https://api.example.com",
    "priority": 1
  }
]
```

### 2. 生成 32 字节密钥

推荐使用 OpenSSL：

```bash
openssl rand -base64 32
```

保存输出结果。这个密钥既用于加密，也要填写到 GitHub Secret `GVBOARD_OSS_KEY`。不要把它提交到仓库。

也可以使用 64 位十六进制密钥，例如：

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

### 3. 加密 OSS 文件

在项目根目录执行：

```bash
dart run tool/encrypt_oss.dart \
  --input client.json \
  --output client.oss \
  --key "<你的32字节Base64密钥>"
```

PowerShell 写法：

```powershell
dart run tool/encrypt_oss.dart `
  --input client.json `
  --output client.oss `
  --key "<你的32字节Base64密钥>"
```

该工具使用 AES-256-GCM 加密，并把 `nonce + 密文 + authentication tag` 组合后再进行 Base64 编码。不要自行手动修改 `.oss` 文件。

### 4. 托管并配置地址

把 `client.oss` 上传到自己的 HTTPS 静态文件地址，测试它返回的是否是 Base64 文本。然后任选一种方式使用：

- GitHub Actions：运行工作流时把地址填到 `oss_url`；
- 本地/固定配置：把地址写到 `assets/oss/index.json` 的 `configs[0]`。

如果要将 OSS 文件随客户端一起打包，也可以把明文文件放入 `assets/oss/` 并在 `index.json` 中使用相对路径。但这种方式不具备远程加密配置的保护能力，且每次修改都需要重新构建客户端。

## 本地构建

建议使用与工作流一致的工具版本：Flutter `3.47.6`、Go `1.27.1`、Android NDK `r28c`。Android 还需要 JDK 17 和 Android SDK；Windows 需要 Windows、Flutter Windows Desktop 支持以及 Go 环境。

首次构建：

```bash
flutter pub get
git submodule update --init --recursive
```

Windows：

```powershell
$env:CLIENT_NAME = "My Client"
$env:CLIENT_BINARY_NAME = "MyClient"
flutter build windows --release `
  --build-name 1.0.0 `
  --build-number 2026112401 `
  --dart-define=CLIENT_NAME="My Client" `
  --dart-define=GVBOARD_OSS_KEY="<你的密钥>" `
  --dart-define=GVBOARD_DEDICATED_CLIENT=true
```

Android：

```bash
CLIENT_NAME="My Client" \
CLIENT_APPLICATION_ID="com.example.myclient" \
flutter build apk --release --split-per-abi \
  --build-name 1.0.0 \
  --build-number 2026112401 \
  --dart-define=CLIENT_NAME="My Client" \
  --dart-define=GVBOARD_OSS_KEY="<你的密钥>" \
  --dart-define=GVBOARD_DEDICATED_CLIENT=true
```

`GVBOARD_DEDICATED_CLIENT=true` 会启用 GVBoard 专属客户端界面。将其设为 `false` 可以保留原有配置管理入口，但不会关闭 GVBoard 登录、商店、我的、自动订阅和离线缓存功能。

本地 Release Android 构建如果没有 `android/app/keystore.jks` 和 `android/local.properties` 中的签名信息，也会使用 debug 签名并追加 `.dev` 包名后缀。正式发布前请使用自己的签名文件。

## 常见问题和注意事项

### 修改了 `branding.yaml`，为什么 Actions 默认值没变？

`branding.yaml` 是品牌配置记录文件，当前工作流不会自动解析它。GitHub Actions 页面显示的默认值来自 `.github/workflows/package.yml`，需要同步修改该文件的 `default`。

### OSS 修改后客户端没有立即变化

客户端会缓存成功加载的配置，缓存时间由 `cache_ttl_seconds` 控制。可以等待缓存过期、清除应用数据，或提高 `oss_id` 让客户端使用一个新的缓存键。修改 `oss_id` 后必须确保 API 和其他字段都完整有效。

### 远程 OSS 加载失败

依次检查：URL 是否为 HTTPS、文件是否可匿名访问、返回值是否为纯 Base64、加密密钥是否一致、明文配置是否为合法 JSON，以及 `apis` 是否至少包含一个有效 API。客户端失败后会尝试 `index.json` 中的下一个配置。

### 包名或版本号不合法

Android `application_id` 必须符合 Android 包名格式，例如 `com.example.client`，不能包含空格、短横线或中文。`build_number` 必须是整数；上传新版本时通常需要递增。Windows `binary_name` 只填写文件名，不要包含 `.exe`、路径或特殊字符。

### 不要提交的文件

以下文件不应上传到 GitHub：

- `build/`、`dist/`、`.dart_tool/`、`coverage/`、`libclash/`；
- `env.json`、`android/local.properties`；
- `android/app/keystore.jks`、其他签名文件；
- OSS 明文密钥、后端 Secret、个人缓存和本地构建产物。

提交前可以查看：

```bash
git status
git diff --cached --stat
```

## 许可证

本项目使用 [GPL-3.0](LICENSE) 许可证。Fork、修改和重新发布时请遵守许可证及上游项目的版权声明。
