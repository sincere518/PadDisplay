# TourKit（内置副本）

- 来源：https://github.com/rampatra/TourKit ，tag `v1.0.0`（commit `0cac3a5`），MIT 协议（见 LICENSE）
- 只保留 `TourKit` library target，去掉 `TourKitSampleApp`、`TourKitTests` 及示例图片

## 本地改动

macOS 27 SDK 中 `@State` 会展开为 `SwiftUIMacros.StateMacro`，宏插件只随完整版 Xcode 提供，
仅有 Command Line Tools 时编译失败。因此把唯一的 `@State` 换成 `@StateObject` 持有的
`TourKitStateBox`（新增文件 `TourKitStateBox.swift`），行为不变：

- `TourKit.swift`：`TourSlideshowView.currentIndex`

安装 Xcode 后可改回直接依赖上游包：`.package(url: "https://github.com/rampatra/TourKit.git", from: "1.0.0")`。
