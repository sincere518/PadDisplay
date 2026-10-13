# PadDisplay · 远程桌面助手

独立的原生 macOS 应用。读取 UU远程当前的连接设备名称，按每台设备保存的尺寸创建高清虚拟屏幕；断开后移除虚拟屏幕并恢复原显示器布局。

源码与打包版本为 **0.1.1**。此次审查只生成项目内的安装包，当前 Mac 已安装的 **0.1.0** 未被替换。0.1.1 已通过回归测试与打包验证，真实 iPad / 手机连接记录对应 0.1.0。

## 使用

1. 退出 UU远程伴侣，保留 UU远程本身运行。
2. 把 `dist/PadDisplay.app` 拖入「应用程序」并打开。
3. 点击「授权识别连接」，在系统隐私设置中允许 **PadDisplay** 使用辅助功能。macOS 27 中这一项可能显示为「设备控制和数据访问」。旧伴侣的授权不能代替新应用的授权。
4. 保持 UU远程主界面可读取，打开「自动匹配设备」。软件按「本机被控中」的设备名称识别，不依赖是否出现远控覆盖窗口。
5. 已有设备自动应用自己的配置；明确型号的新设备会自动预填。无法确定型号时，点击「添加设备」，填写 UU远程中显示的完整设备名并选择型号或自定义尺寸。
6. 在 iPad / 手机的 UU远程显示器列表里选中 **PadDisplay · 设备名**。Mac 主屏已切换不代表 UU 客户端一定会自动切换其采集的显示器。

「恢复原桌面」会结束当前调整，并暂停本次连接的自动调整。下一次连接继续识别。「立即使用这个屏幕」可在无连接识别权限时手动验证显示效果；手动屏幕保持到恢复、切换自动匹配开关或退出。关闭主窗口后程序继续在菜单栏工作；退出程序会先恢复桌面。

## 每台设备的配置

- 设备名称：与 UU远程中的名字完全一致。
- 此设备连入时调整桌面：电脑可以关闭此项。
- 尺寸：填写最终输出像素，默认横屏；「交换宽高」设置竖屏。UU未提供可核实的旋转事件，因此当前版本按保存的方向应用。
- 高清文字：使用两倍像素密度，例如 iPad Air 13 寸输出 2732 × 2048 像素、逻辑桌面 1366 × 1024。
- 自定义尺寸：640–8192 像素；高清模式要求宽高均为偶数。

手动添加的配置默认不调整桌面；确认尺寸后打开「此设备连入时调整桌面」并保存。自动匹配时，多台设备同时连接会暂停调整，结合 UU 显示的设备数量判断，包括同名设备。名称仍是配置匹配依据；同名设备需要不同尺寸时，请先在 UU 中改为不同名称。

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

```sh
./script/build_and_run.sh --build
./script/build_and_run.sh --package
./script/build_and_run.sh
```

`--build` 只构建，`--package` 生成 Release `.app`、ZIP 和 SHA-256。默认构建并打开应用，仅结束本项目 `dist/` 中的旧进程；已安装应用运行时会提示先退出，避免中断其远程连接。打包不退出已安装应用；项目 `dist/` 中的应用仍运行时则拒绝覆盖它。

支持 `--debug`、`--logs`、`--telemetry`、`--verify`。构建脚本优先使用本机 Xcode-beta（如已安装），也可以通过 `DEVELOPER_DIR` 指定其他工具链。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/build/clang-cache" \
  xcrun swift test --build-system native --scratch-path build/swift-native \
  --cache-path build/swift-cache --disable-sandbox
bash Tests/ScriptTests/check_build_guard.sh
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
| `docs/` | 审查结论与按版本区分的验证记录 |
| `evidence/` | 真实设备原始记录和本次审查证据 |
| `build/`、`dist/` | 可重新生成的缓存和安装包，不提交 Git |

## 验证和边界

本次 [代码审查](docs/review-2026-10-13.md) 覆盖全部活动源码、构建配置、脚本及文档。14 项 XCTest 与 4 个脚本场景通过；恢复测试使用临时目录，不更改真实显示布局。

[0.1.0 验证记录](docs/validation.md) 保存本机虚拟屏自测、真实 iPad 验收及 iPhone 17 Pro Max 连入 / 断开 / iPad 重连证据。0.1.1 尚未重新进行真实客户端切换验收。

应用不请求网络连接，不读取 UU账号令牌。设置保存在独立的 `local.PadDisplay` 偏好域；临时布局记录保存在 `~/Library/Application Support/PadDisplay/display-session.json`。恢复时同时核对显示器 ID、厂商、型号和序列号，避免把旧布局应用到不匹配的显示器。

虚拟屏幕使用 macOS 私有 `CGVirtualDisplay` 接口，系统升级可能需要适配。当前安装包为本地 ad-hoc 签名，未经过 Apple 公证；重新编译产生新签名后，辅助功能权限可能需要重新授权。

## 源码关系

`Sources/PadDisplay*` 和 `Sources/DisplayBridge` 是独立实现，无第三方包依赖。设计参考过 [UUyc companion 的固定版本 25d240a](https://github.com/aoyamashou/UUyc-companion/tree/25d240a9698d718343a5a0113a095b0d290a166f)。未参与构建的参考副本、第三方示例和下载归档已从工作目录移除，原始导入仍可从 Git 历史恢复。
