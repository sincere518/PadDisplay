# UU远程分辨率伴侣 — 开发方案

来源：交接文档（2026-10-09）

## 目标
macOS 菜单栏工具：本机被 UU远程 控制时，按控制端设备自动创建对应分辨率的虚拟屏并设为主屏；断开后自动还原。

## 本机环境（已核实）
| 项 | 值 | 影响 |
| --- | --- | --- |
| macOS | 27.0.1 (26A434)，arm64 | 比文档参考的 Tahoe(26) 更新，CGVirtualDisplay 私有 API 需首先验证 |
| 工具链 | 仅 Command Line Tools，Swift 6.4，无 Xcode | 用 SwiftPM 构建 + 脚本打包 .app + ad-hoc 签名 |
| UU远程 | /Applications/UURemote.app，进程：UURemote / UURemoteServer / UURemoteService / UURemoteDaemon / UURemoteHelper.xpc | P0 探测对象 |
| GitHub | gh 已登录 | 可建私有仓库 |

## P0 结论（2026-10-10 实测）
| 验证项 | 结果 |
| --- | --- |
| macOS 27 创建 HiDPI 虚拟屏 | ✅ 2360×1640px / 1180×820pt，单一模式 |
| 虚拟屏设为主屏后 UU 画面跟随 | ✅ iPad Air 11" M4 铺满无黑边（UU 显示列表出现「UUDisplay Probe」，分辨率 1180×820 HiDPI） |
| 读取 UU 设备列表 | ✅ AX 可读分组「电脑」「手机/平板」、设备名、「本机」标记、iOS/安卓图标 |
| 连入信号 | ✅ UURemoteServer 在各屏铺覆盖窗口，CGWindowList 可见，约 2 秒，无需权限 |
| 控制端设备名 | ✅ 主窗口 AX 表格行；通常与连入同秒出现，UU 网络异常时曾延迟 24 秒 |
| 断开信号 | ✅ 覆盖窗口消失，1 秒内；需 1.5 秒防抖（切屏时覆盖窗口会短暂重建） |
| 进程退出/被杀 | ✅ 虚拟屏立即消失，主屏自动回原屏 |

注意：
- UU 的被控端日志（.slog/.xlog）加密，不可用
- 设备名延迟时的兜底：先按「上次连入设备」建屏，名称出现后不一致再重建
- 本进程释放虚拟屏后自身的显示器列表有缓存，判断移除以重配置回调或外部状态为准
- UU 可修改被控屏分辨率，本工具不应依赖它；虚拟屏仍只提供一个模式

## 技术选型
- 语言/UI：Swift + AppKit（`NSStatusItem` 菜单栏）+ SwiftUI（首次向导窗口），`LSUIElement` 隐藏 Dock 图标
- 虚拟屏：复用 FreeDisplay（MIT）的 CGVirtualDisplay ObjC 桥接头文件，放独立 ObjC target
- 主屏切换/还原：`CGBeginDisplayConfiguration` + `CGConfigureDisplayOrigin`（新屏放 (0,0) 即为主屏）
- UU 状态读取：AXUIElement（优先）→ UU 日志 → lsof/nettop → ScreenCaptureKit 截图 + Vision OCR（兜底）
- 配置存储：`~/Library/Application Support/UUDisplay/config.json`
- 自启：`SMAppService.mainApp`

## 模块划分
```
Sources/
  CGVirtualDisplayBridge/   ObjC 私有 API 头文件（来自 FreeDisplay）
  UUDisplay/
    VirtualDisplayManager   创建 / 删除虚拟屏，模式创建后不改
    DisplayArranger         设为主屏、快照与还原原布局
    UUMonitor               连入/断开事件 + 设备名（策略可插拔）
    DeviceStore             设备列表、类型、分辨率配置
    Presets                 分辨率预设表
    SetupWizard             首次启动向导
    StatusBarController     菜单：状态 / 重新配置 / 默认设备 / 暂停 / 退出 / 开机自启
    RecoveryGuard           启动时检查并修复残留状态
```

## 阶段与里程碑

### P0 探测（需用户配合，集中一次完成）
1. **虚拟屏可用性**（新增，因 macOS 27）：最小 CLI 创建 2360×1640 HiDPI 虚拟屏 → 设为主屏 → 退出后确认消失
2. **读取 UU 设备列表**：AX 树 dump UU 主窗口；失败则截图 OCR
3. **连入/断开信号 + 设备名**：依次试 AX（窗口/浮窗/菜单栏）、`~/Library` 下 UU 日志、`lsof -p` 网络连接变化、OCR
4. **UU 是否跟随主屏**：平板连入状态下切换主屏，看远程画面是否切到虚拟屏

→ 汇报 P0 结论，确认方案后进入 P1。任一项不可行时给出替代方案（如手动选择设备）。

### P1 开发
1. 虚拟屏核心 + 布局快照/还原
2. 首次启动向导（设备分类预填、分辨率选择，预设联网核实）
3. 后台监听：连入切换、断开还原、默认设备兜底、防抖
4. 菜单栏 + 开机自启 + 残留恢复
5. 打包脚本 `scripts/build-app.sh`，安装到 m4 / M1 / mini

## 预设分辨率（横屏像素，HiDPI 默认开，开发时联网核实）
平板：OPPO Pad 3 Pro 3000×2120 · iPad Air 11" 2360×1640 · iPad Air 13" 2732×2048 · iPad Pro 11" 2420×1668 · iPad Pro 13" 2752×2064 · iPad mini 2266×1488
手机：iPhone 17 2622×1206 · 通用安卓 20:9 2400×1080
自定义：宽、高、HiDPI 开关；电脑：不切换

## 关键约束
- 虚拟屏创建后不改模式（否则可能无法移除）；先建虚拟屏再枚举显示器
- 不用镜像，虚拟屏设为主屏、物理屏保持扩展
- GPL/AGPL 项目只阅读不复制
- 权限：辅助功能（AX）、屏幕录制（OCR 兜底时）

## 完成标准
- [x] 首次启动读出 UU 设备列表并完成分类和分辨率配置
- [x] 平板连入 5 秒内自动切换，铺满无黑边、文字清晰
- [x] 电脑连入不做任何改动
- [x] 断开 10 秒内恢复原状，无残留虚拟屏
- [x] 连续连接/断开 10 次无错误
- [x] 强退软件后无残留虚拟屏

## 验收记录（2026-10-10）
用户用 iPad Air、OPPO Pad 3 Pro、iPhone 17、OPPO Reno13 Pro、M1 各连入一次：平板/手机自动切换、铺满无黑边；M1 不切换；断开约 1 秒还原。
日志：名称已知时连入→设为主屏约 1 秒；名称延迟时 2.4 秒先按上次设备建屏，识别后重建。

## 新功能：远程时关闭物理屏（2026-10-10，feature/disable-physical）
平板/手机连入：建虚拟屏 → 设主屏 → 禁用物理屏（CGSConfigureDisplayEnabled）；断开：恢复物理屏 → 移除虚拟屏 → 还原布局。电脑连入不动。
兜底：禁用前写盘记录；看门狗 UUDisplayWatchdog（LaunchAgent KeepAlive，被杀 1 秒内拉起）在主程序消失（<1 秒）/心跳超时 10 秒/UU 断开 5 秒时恢复；
热键 ⌃⌥⌘R；启动时先恢复残留；看门狗不在时不禁用；菜单开关；事务超时进入保护状态。
踩坑：
- 禁用不受 .forAppOnly 约束，进程退出不会自动恢复；被禁用屏从在线列表消失
- 热插拔未处理完又建虚拟屏 → WindowServer abort（注销重启）→ 改为目标状态逐步收敛，每步等待稳定
- 虚拟屏未上线即释放 → WindowServer 显示配置卡死（需重启）→ 释放前须上线且存活 ≥2.5 秒
- .terminateLater 期间主队列延时任务不执行 → 先取消退出，收尾后再退出
压测：加固后慢速 35 轮 + 快速 25 轮零错误；强杀/冻结/热键/看门狗拉起均通过。
