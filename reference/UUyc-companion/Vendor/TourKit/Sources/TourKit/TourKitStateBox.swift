// 内置副本新增：替代 `@State`（Command Line Tools 环境缺少 SwiftUIMacros 宏插件），见 VENDORED.md
import Combine

final class TourKitStateBox<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
