# UUDisplay 图标资源

| 文件 | 用途 |
|---|---|
| `AppIcon.svg` | App 图标矢量源文件（1024 画布，已含 macOS 圆角底板与阴影） |
| `AppIcon-1024.png` | App 图标 1024×1024 PNG |
| `AppIcon.icns` | macOS 应用图标，放进 `.app/Contents/Resources/`，并在 Info.plist 设 `CFBundleIconFile = AppIcon` |
| `MenuBarIconTemplate.svg` | 菜单栏图标矢量源文件（18×18 pt） |
| `MenuBarIconTemplate.png` / `@2x.png` | 菜单栏图标 18/36 px，纯黑+透明的模板图 |

## 菜单栏图标用法

必须设为模板图，系统才会在深色菜单栏自动反白：

```swift
let image = NSImage(contentsOf: url)!   // MenuBarIconTemplate.png（同目录放 @2x 会自动选用）
image.isTemplate = true
image.size = NSSize(width: 18, height: 18)
statusItem.button?.image = image
```

文件名以 `Template` 结尾时，从 Bundle 用 `NSImage(named:)` 加载也会自动被识别为模板图。

## 设计说明

方案「双屏叠片」：青色横屏 = 被控电脑，蓝色竖屏 = 平板，交叠处深蓝 = 分辨率对齐。
配色：`#00EAFF → #0FC4FA`（电脑）、`#0A7CFF → #0057F0`（平板）、`#0441F5`（交叠）。
