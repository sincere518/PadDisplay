# PadDisplay · 远程桌面助手

独立的原生 macOS 应用。读取 UU远程当前的连接设备名称，按每台设备保存的尺寸创建高清虚拟屏幕；断开后移除虚拟屏幕并恢复原显示器布局。

## 使用

1. 退出 UU远程伴侣，保留 UU远程本身运行。
2. 把 `dist/PadDisplay.app` 拖入「应用程序」并打开。
3. 点击「授权识别连接」，在系统隐私设置中允许 **PadDisplay** 使用辅助功能。macOS 27 中这一项可能显示为「设备控制和数据访问」。旧伴侣的授权不能代替新应用的授权。
4. 保持 UU远程主界面可读取，打开「自动匹配设备」。软件按「本机被控中」的设备名称识别，不依赖是否出现远控覆盖窗口。
5. 已有设备自动应用自己的配置；明确型号的新设备会自动预填。无法确定型号时，点击「添加设备」，填写 UU远程中显示的完整设备名并选择型号或自定义尺寸。
6. 在 iPad / 手机的 UU远程显示器列表里选中 **PadDisplay · 设备名**。Mac 主屏已切换不代表 UU 客户端一定会自动切换其采集的显示器。

「恢复原桌面」会结束当前调整，并暂停本次连接的自动调整。下一次连接继续识别。「立即使用这个屏幕」可在无连接识别权限时手动验证显示效果。关闭主窗口后程序继续在菜单栏工作；退出程序会先恢复桌面。

## 每台设备的配置

- 设备名称：与 UU远程中的名字完全一致。
- 此设备连入时调整桌面：电脑可以关闭此项。
- 尺寸：填写最终输出像素，默认横屏；「交换宽高」设置竖屏。UU未提供可核实的旋转事件，因此当前版本按保存的方向应用。
- 高清文字：使用两倍像素密度，例如 iPad Air 13 寸输出 2732 × 2048 像素、逻辑桌面 1366 × 1024。
- 自定义尺寸：640–8192 像素；高清模式要求宽高均为偶数。

同时有多台设备连接时暂停调整，以免替另一台设备选错尺寸。

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
./script/build_and_run.sh
./script/build_and_run.sh --package
```

默认构建并打开应用；`--package` 生成 Release `.app`、ZIP 和 SHA-256。支持 `--build`、`--debug`、`--logs`、`--telemetry`、`--verify`。构建脚本优先使用本机 Xcode-beta（如已安装），也可以通过 `DEVELOPER_DIR` 指定其他工具链。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun swift test --build-system native --scratch-path build/swift-native --disable-sandbox
```

`.codex/environments/environment.toml` 已绑定 Run 按钮。

## 验证和边界

设备解析和策略测试在 `Tests/PadDisplayCoreTests/`。运行记录在 `docs/validation.md`；显示器自测 JSON 在 `evidence/`。本机创建、切换和恢复成功，不等同于已经在每一台真实客户端上验证全屏显示。

应用不请求网络连接，不读取 UU账号令牌。设置保存在独立的 `local.PadDisplay` 偏好域；临时布局记录保存在 `~/Library/Application Support/PadDisplay/display-session.json`。恢复时同时核对显示器 ID、厂商、型号和序列号，避免把旧布局应用到不匹配的显示器。

虚拟屏幕使用 macOS 私有 `CGVirtualDisplay` 接口，系统升级可能需要适配。当前安装包为本地 ad-hoc 签名，未经过 Apple 公证；重新编译产生新签名后，辅助功能权限可能需要重新授权。

## 源码关系

`Sources/PadDisplay*` 和 `Sources/DisplayBridge` 是本次独立实现，无第三方包依赖。之前检查的 UUyc companion 源码保存在 `reference/UUyc-companion/`，其原许可证仍在该目录；该参考项目不参加 PadDisplay 的构建，也不会打入安装包。其虚拟屏幕生命周期处理和失败案例用于设计参考。
