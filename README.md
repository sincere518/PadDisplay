# PadDisplay · 远程桌面助手

独立的原生 macOS 应用。读取 UU远程当前的连接设备名称，按每台设备保存的尺寸创建高清虚拟屏幕；断开后移除虚拟屏幕并恢复原显示器布局。

源码与打包版本为 **0.2.2**，采用原生侧边栏、Liquid Glass 控件、配置浮层、设置和关于窗口。0.2.0 已通过回归测试与隔离原生 UI 验证；0.2.1 将 iPhone 机身示意固定为竖直展示；0.2.2 固定使用本机配置的 Apple 签名证书，避免升级时临时签名变化导致已有权限失效。真实 iPad / 手机连入和断开记录对应 0.1.0，当前签名与安装验证见 [签名记录](docs/signing-2026-10-13.md)。

## 使用

1. 退出 UU远程伴侣，保留 UU远程本身运行。
2. 把 `dist/PadDisplay.app` 拖入「应用程序」并打开。
3. 点击授权提示中的「打开系统设置」，或从侧边栏进入「设置」，在系统隐私设置中允许 **PadDisplay** 使用辅助功能。macOS 27 中这一项可能显示为「设备控制和数据访问」。旧伴侣的授权不能代替新应用的授权。
4. 保持 UU远程主界面可读取，打开工具栏的「自动匹配」。软件按「本机被控中」的设备名称识别，不依赖是否出现远控覆盖窗口。
5. 已有设备自动应用自己的配置；明确型号的新设备会自动预填。无法确定型号时，点击「添加设备」，填写 UU远程中显示的完整设备名并选择型号或自定义尺寸。
6. 在 iPad / 手机的 UU远程显示器列表里选中 **PadDisplay · 设备名**。Mac 主屏已切换不代表 UU 客户端一定会自动切换其采集的显示器。

从 0.2.1 及更早的临时签名版本升级到 0.2.2 时，需要重新授权一次：在该隐私设置中移除旧的 PadDisplay 项，重新添加「应用程序」中的 PadDisplay 并开启权限。后续保持相同证书和 Bundle ID 打包时，正常升级通常能沿用授权；系统或用户撤销权限时仍需重新开启。

选择侧边栏设备只查看配置，不切换屏幕。未连接设备显示「配置预览」，尺寸明确标为保存参数。「恢复原桌面」会结束当前调整，并暂停本次连接的自动调整；点击「继续自动匹配」恢复识别，下一次连接也会继续识别。「立即应用」可在无连接识别权限时手动验证显示效果；手动屏幕保持到恢复、切换自动匹配开关或退出。关闭主窗口后程序继续在菜单栏工作；退出程序会先恢复桌面。

## 每台设备的配置

- 设备名称：与 UU远程中的名字完全一致。
- 此设备连入时调整桌面：电脑可以关闭此项。
- 尺寸：点击「编辑配置…」填写最终输出像素，默认横屏；「屏幕方向」切换横竖屏时交换宽高。UU未提供可核实的旋转事件，因此当前版本按保存的方向应用。
- 高清文字：使用两倍像素密度，例如 iPad Air 13 寸输出 2732 × 2048 像素、逻辑桌面 1366 × 1024。
- 自定义尺寸：640–8192 像素；高清模式要求宽高均为偶数。

添加和编辑只修改草稿；取消不会新增空配置或改变当前屏幕，有未保存修改时显示确认。手动添加的配置默认不调整桌面，未知设备的尺寸留空；确认尺寸后打开「此设备连入时调整桌面」并保存。自动匹配时，多台设备同时连接会暂停调整，结合 UU 显示的设备数量判断，包括同名设备。名称仍是配置匹配依据；同名设备需要不同尺寸时，请先在 UU 中改为不同名称。

侧边栏「关于 PadDisplay」及标准应用菜单均可打开关于窗口，展示作者 **耳过清风**、小红书号 **5397290838**、实际包版本及本地许可；号码支持复制。`⌘,` 打开设置，`Escape` 取消编辑，`Return` 保存有效配置。

设备预览使用原创蓝紫流线壁纸，跟随浅色 / 深色外观；iPad 默认横屏，iPhone 使用写实机身 PNG，固定竖直展示并保留灵动岛和侧键。远程屏幕的实际方向仍按保存配置应用。壁纸仅用于应用内预览，素材来源和使用说明见 [DevicePreviews](Resources/DevicePreviews/README.md)。

内置尺寸来自 Apple 官方技术规格：

| 型号 | 横屏像素 | 来源 |
| --- | --- | --- |
| iPad Air 13 英寸 | 2732 × 2048 | [Apple](https://www.apple.com.cn/ipad-air/specs/) |
| iPad Air 11 英寸 | 2360 × 1640 | [Apple](https://www.apple.com.cn/ipad-air/specs/) |
| iPad Pro 13 英寸 M4 / M5 | 2752 × 2064 | [Apple](https://www.apple.com/hk/en/ipad-pro/specs/) |
| iPhone Air | 2736 × 1260 | [Apple](https://www.apple.com/hk/en/iphone-air/specs/) |
| iPhone 17 Pro Max | 2868 × 1320 | [Apple](https://support.apple.com/zh-cn/125091) |

## 构建

需要 macOS 14+，Swift 5.9+，以及提供 macOS SDK 的 Xcode / Command Line Tools。当前产物针对 Apple Silicon。

正式应用必须使用固定的 Apple 签名证书。先查看钥匙串中的有效代码签名身份，选择一张含私钥的证书，并将它的 SHA-1 指纹写入被 Git 忽略的本机配置：

```sh
security find-identity -v -p codesigning
printf '%s\n' '填入选定证书的 SHA-1 指纹' > script/signing.identity.local
```

后续版本复用这份配置。也可通过 `SIGN_IDENTITY` 显式指定证书；缺少配置、指定证书不可用或指定临时签名 `-` 时，脚本会在构建和结束旧进程前停止，不会自动改用其他身份。该配置只记录证书指纹，私钥由钥匙串管理。

```sh
./script/build_and_run.sh --build
./script/build_and_run.sh --package
./script/build_and_run.sh
./script/build_and_run.sh --preview ready light
```

`--build` 只构建，`--package` 生成 Release `.app`、ZIP 和 SHA-256。默认构建并打开应用，仅结束本项目 `dist/` 中的旧进程；已安装应用运行时会提示先退出，避免中断其远程连接。打包不退出已安装应用；项目 `dist/` 中的应用仍运行时则拒绝覆盖它。

`--preview [场景] [light|dark]` 创建不同 Bundle ID 的「PadDisplay UI验证」应用，使用独立临时偏好和模拟连接状态，不读取实际连接、不操作显示器、辅助功能权限或登录项。支持 `ready`、`phone`、`idle`、`permission`、`paused`、`busy`、`failed`、`multiple`、`unknown`、`companion`。退出验证应用后再切换场景；它不代表真实客户端验收。

支持 `--debug`、`--logs`、`--telemetry`、`--verify`。构建脚本优先使用本机 Xcode-beta（如已安装），也可以通过 `DEVELOPER_DIR` 指定其他工具链。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/build/clang-cache" \
  xcrun swift test --build-system native --scratch-path build/swift-native \
  --cache-path build/swift-cache --disable-sandbox
bash Tests/ScriptTests/check_build_guard.sh
bash Tests/ScriptTests/check_signing.sh
```

`.codex/environments/environment.toml` 已绑定 Run 按钮。

## 目录

| 路径 | 用途 |
| --- | --- |
| `Sources/PadDisplayCore/` | 设备配置、尺寸校验、UU 字段解析与连接策略 |
| `Sources/PadDisplay/` | 原生界面、连接读取、显示器生命周期和诊断 |
| `Sources/DisplayBridge/` | Objective-C 虚拟显示接口桥接 |
| `Tests/` | 核心策略、隔离恢复记录、构建脚本回归测试 |
| `script/` | 构建打包、图标生成、只读显示器记录器 |
| `Resources/` | 离线设备预览图片与素材许可 |
| `docs/` | 审查结论与按版本区分的验证记录 |
| `evidence/` | 真实设备原始记录和本次审查证据 |
| `build/`、`dist/` | 可重新生成的缓存和安装包，不提交 Git |

## 验证和边界

[代码审查](docs/review-2026-10-13.md) 记录 0.1.1 的全量检查。0.2.0 的 19 项 XCTest 与 5 个脚本场景通过，恢复测试使用临时目录；[原生 UI 验证](docs/native-ui-2026-10-13.md) 记录浅深色截图、配置校验、草稿取消、窗口和关于交互。

0.2.2 的 7 个签名配置场景与 5 个进程保护场景通过；使用同一证书签名的 0.2.2 与仅用于验证的下一版本副本，代码哈希不同，但双方均通过对方的应用身份要求校验。详见 [签名记录](docs/signing-2026-10-13.md)。

[0.1.0 验证记录](docs/validation.md) 保存本机虚拟屏自测、真实 iPad 验收及 iPhone 17 Pro Max 连入 / 断开 / iPad 重连证据。0.2.2 已确认重新授权后自动识别真实 iPad 连接，创建 2732 × 2048 像素、1366 × 1024 逻辑桌面的主虚拟屏幕；本次没有重新测试手机切换及远程断开恢复。Liquid Glass 在 macOS 26+ 启用，旧系统使用标准控件样式；本轮原生运行验证在 macOS 27 完成，未单独运行 macOS 26。

应用不请求网络连接，不读取 UU账号令牌。设置保存在独立的 `local.PadDisplay` 偏好域；临时布局记录保存在 `~/Library/Application Support/PadDisplay/display-session.json`。恢复时同时核对显示器 ID、厂商、型号和序列号，避免把旧布局应用到不匹配的显示器。

虚拟屏幕使用 macOS 私有 `CGVirtualDisplay` 接口，系统升级可能需要适配。当前安装包使用固定的 Apple Development 证书，供本机开发使用，未经过 Apple 公证；对外公开分发应使用 Developer ID Application 证书及公证流程。`--preview` 的隔离 UI 副本仍使用临时签名和独立 Bundle ID，不用于实际远程连接。

## 源码关系

`Sources/PadDisplay*` 和 `Sources/DisplayBridge` 是独立实现，无第三方包依赖。设计参考过 [UUyc companion 的固定版本 25d240a](https://github.com/aoyamashou/UUyc-companion/tree/25d240a9698d718343a5a0113a095b0d290a166f)。未参与构建的参考副本、第三方示例和下载归档已从工作目录移除，原始导入仍可从 Git 历史恢复。
