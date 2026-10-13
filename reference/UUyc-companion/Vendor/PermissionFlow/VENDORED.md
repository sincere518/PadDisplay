# PermissionFlow（内置副本）

- 来源：https://github.com/jaywcjlove/PermissionFlow ，tag `v2.11.3`，MIT 协议（见 LICENSE）
- 只保留 `PermissionFlow`、`SystemSettingsKit` 两个 target

## 本地改动

macOS 27 SDK 中 `@State` 会展开为 `SwiftUIMacros.StateMacro`，宏插件只随完整版 Xcode 提供，
仅有 Command Line Tools 时编译失败。因此把全部 `@State` 换成 `@StateObject` 持有的
`PermissionFlowStateBox`（新增文件 `PermissionFlowStateBox.swift`），行为不变：

- `PermissionFlowButton.swift`：`buttonState`
- `UI/PermissionFlowPanelView.swift`：`HeaderDirectionIcon` 的 `wigglePhase` / `scalePhase`

安装 Xcode 后可改回直接依赖上游包。
