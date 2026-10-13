// 内置副本新增：替代 @State 的最小可观察盒子（见 VENDORED.md）
#if os(macOS)
import Combine

@MainActor
final class PermissionFlowStateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
#endif
