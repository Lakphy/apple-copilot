> 开发研究记录：结果对应文中标明的版本与日期，当前整理验证见 [验证说明](VALIDATION.md)。

# macOS Markdown 滚动性能

2026-10-12，针对“回复生成结束后，macOS 上滚动掉帧”进行检查与优化。使用 `swiftui-performance` 的代码检查、Release 测量和同场景复测流程。

## 已实施的优化

1. **未变更输入直接返回。** `MarkdownWebView.Coordinator.update` 在解析系统颜色和修改原生视图之前比较 Markdown、流式状态及外观输入。高度、父视图状态等无关变化不会重复设置 WebKit 外观或提交文档更新。
2. **按需解析语义颜色。** 同一文档的流式增量复用颜色；明暗模式、增强对比度及 macOS 系统颜色通知仍会刷新。销毁视图时移除通知监听。
3. **锚点位置不触发视图刷新。** 最新原点保存在视图拥有的非观察对象中，只在用户打开页内链接时读取。几何回调无需改变用于绘制的 SwiftUI 状态。
4. **不透明绘制图层。** macOS `WKWebView.isOpaque` 原本为 true，其 backing layer 的 `isOpaque` 却为 false。现在图层使用对应的原生页面背景并声明不透明，网页也采用同一语义表面，减少外层滚动时的透明合成。iOS 的透明背景行为保留。

没有改动滚轮方向分发、触控板惯性、代码横向滚动、复制、Mermaid、公式或流式稳定块算法。

## Release 测量

### 无输入变化时的更新路径

原生 WebKit 测试先等待包内文档及 Mermaid 完成，再对相同输入重复调用 Coordinator；耗时只记录，不作为容易受机器负载影响的 CI 阈值。

| 指标 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 2,000 次相同输入更新 | 67.769ms | 0.239ms |
| 100 次相同输入引发的 NSAppearance 写入 | 100 | 0 |
| WebKit backing layer 不透明标记 | false | true |

这些数字衡量更新路径开销，不代表帧率提高了同样倍数。回归断言检查相同输入不写原生外观、图层不透明，以及系统颜色通知仍能刷新文档。

### 实际滚动记录

使用本机 Mac、Release 优化等级、900×760pt 窗口和约 **15,741 字符**的已完成回复。测试文档包括 GFM、代码、Mermaid、公式以及 30 个长正文章节；仅用内存预览，不访问模型服务。Release 构建额外启用现有 DEBUG 预览入口，未开启逐帧日志。

每次捕获只运行一个性能样例窗口，Instruments SwiftUI 模板附加到明确 PID，记录 15 秒；通过 CUA 在 Markdown 内容区执行相同的 **六次向下/向上往返滚动**，并检查辅助功能状态。优化前后使用同一份 fixture 和操作序列。

| 指标 | 优化前 | 优化后 | 变化 |
| --- | ---: | ---: | ---: |
| Instruments 检测的 hitch 事件 | 259 | 214 | −17.4% |
| 累计 hitch 时间 | 2,358.30ms | 1,887.47ms | −20.0% |
| 最大单次 hitch | 25.00ms | 16.67ms | −33.3% |
| 采样的应用 CPU 时间 | 1,000.1ms | 874.3ms | −12.6% |
| 采样的主线程 CPU 时间 | 748.1ms | 687.1ms | −8.2% |

这是本机的一组成对测量；存在 Instruments、辅助功能查询和系统负载开销，不能直接换算成固定 FPS，也不表示所有回复长度或机器都没有掉帧。优化前的 SwiftUI trace 显示滚动期间 Markdown body 仅更新 2 次、representable 4 次，因而未把整页 SwiftUI 重算当作主要原因。

探索阶段尝试过 Markdown 块的 CSS 绘制隔离；它没有改善 hitch 记录，已撤回。早期同时开着多个 WebKit 样例的记录也未作为最终对比依据。

## 验证与资料

- 7 个原生 UI 测试通过，包含相同输入更新、系统颜色通知、图层、原生 WebKit、4 个滚轮/触控板回归及原有文本输入测试。
- 12 组 WebKit 渲染测试通过，覆盖 GFM、Mermaid、公式、复制、链接/脚注、稳定流式 DOM、最大字号及对比度。
- iOS/iPadOS 与 macOS 构建通过，相关构建与测试日志没有 warning/error。
- 原生深色快照重新检查；真实滚动中确认位移和公式、代码等内容可见，页内返回链接仍能通过原生桥接处理。

数据位于忽略目录 `build/MarkdownPerformance`：最终对照为 `before-clean.trace` 与 `final-clean.trace`，对应 XML 包含 hitch 及 Time Profiler 数据。`fixture.md` 是两版共用的压力样例。无输入更新的日志为 `build/markdown-perf-baseline-native.log` 与 `build/markdown-perf-final-native.log`。

```sh
swift test -c release --filter CopilotUITests
cd Scripts/MarkdownRenderer
npm test
```

采集示例（PID 必须使用实际测试应用的 PID）：

```sh
xcrun xctrace record --template SwiftUI --attach PID --time-limit 15s --output sample.trace
xcrun xctrace export --input sample.trace --toc --output sample-toc.xml
```

参考：技能中的 `optimizing-swiftui-performance-instruments.md › Keep representable updates idempotent`、`demystify-swiftui-performance-wwdc23.md › Dependencies and invalidation`。富文本功能与边界见 [RICH_TEXT_RENDERING.md](RICH_TEXT_RENDERING.md)。
