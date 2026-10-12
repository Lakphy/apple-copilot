# AI 富文本与流式渲染

## 代码研究与接入范围

原先 `AssistantMessageView` 直接使用 `Text(message.content)`，原文和 AI 输出都按纯文本显示；`ConversationStore.perform` 等待 `LanguageModelClient.complete` 返回整个字符串，三个 HTTP 协议请求均为 `stream: false`。

翻译工作区、历史详情、iOS/iPadOS Translation Provider 扩展和 Mac Services 窗口都经 `ConversationDetail → ConversationTranscript → AssistantMessageView` 展示输出。因此在共享 `CopilotUI` 包中接入同一渲染组件，不维护平台各异的 Markdown 实现。原文与用户追问仍按文本展示。

## 支持内容

- GFM：标题及稳定锚点、段落、粗体/斜体、删除线、引用、分隔线、嵌套有序/无序列表、任务列表、表格及对齐、自动链接、引用式链接、行内/围栏/缩进代码、硬换行、转义和图片。
- GitHub 常用扩展：脚注及返回链接、NOTE/TIP/IMPORTANT/WARNING/CAUTION 提示块、emoji 短代码、`$…$` / `$` 加反引号的行内公式、`$$…$$` 和 `math` 代码围栏中的显示公式。
- 安全 HTML：如 `details` / `summary`、`kbd`、`sub` / `sup`。脚本、事件处理器、表单、iframe、任意内联样式及危险 URL 会移除。GitHub 仓库特定的 issue/用户引用和自定义站点 emoji 需要仓库上下文，当前不自动扩展。
- 代码块：显式语言由 Highlight.js 全语言包高亮；未知/未指定语言保留可读原文。独立原生剪贴板复制按钮具有成功反馈，复制内容不受高亮 HTML 影响，保留 Unicode、缩进和换行。
- `mermaid` 围栏：包含 Mermaid 的内建图表引擎；代码块完整后渲染 SVG，显示源码折叠区与源码复制。无效/未完整图表保留源码，不阻断其他内容。图表按实际宽度展示，复杂图表可横向滚动。

标题、表格、代码、公式及图表支持窄窗口；代码、表格、宽图表和公式在各自区域横向滚动。SwiftUI 将正文及三种标题的系统字号、粗体文本、增强对比度、减少动态效果传入 WebKit；AppKit/UIKit 语义颜色供给正文、内容表面、链接和焦点。小字号文字在实际背景上检查 4.5:1，增强对比度提高到 7:1。代码复制具有可读屏的结果状态，任务标记随字体放大。详见 [Apple Design 审查](MARKDOWN_DESIGN_REVIEW.md)。

## 本地资源与边界

`Sources/CopilotUI/Resources/Markdown` 通过 Swift Package `.copy` 打包，主应用及翻译扩展都会获得资源 bundle。运行不依赖 Node、网络、CDN 或第三方远程字体。

构建源位于 `Scripts/MarkdownRenderer`，使用精确 npm 版本和 lockfile。Marked 解析 GFM，扩展处理脚注/锚点，DOMPurify 清理 HTML/SVG，Highlight.js 高亮，Mermaid 渲染图表，KaTeX 排版公式，gemoji 提供 Unicode emoji。Mermaid 间接 KaTeX 版本通过 override 与直接依赖统一到已修复的 0.19.0。构建脚本同时生成第三方许可证清单，包括运行时的间接依赖。

WebKit 使用非持久化数据存储；CSP 禁止任意脚本、连接和远程图片请求。文档仅加载资源目录内的本地文件，链接经 SwiftUI `openURL` 转交系统。Mac 背景使用公开的 `underPageBackgroundColor` 与原生外观 API，原生深色快照也已检查。远程图片显示显式加载按钮；用户点击后由原生 URLSession 无 cookie/无模型凭据地读取 PNG/JPEG/GIF/WebP，拒绝重定向，限制为 8 MiB，再以 data URL 显示。Base64 图片直接显示。渲染或进程异常时保留纯文本回退。

## 流式链路

1. `LanguageModelClient.stream` 提供增量回调；旧的注入客户端仍可通过默认实现一次性返回文本。生产客户端发送 `stream: true`，保留完整上下文、提示词、鉴权及 Responses 的 `store: false`。
2. `URLSessionHTTPTransport.stream` 使用 `URLSession.bytes`，保持空行并分块传给 SSE 解码器；任何退出路径关闭连接，重定向处理与非流式请求一致。
3. `ModelStreamDecoder` 跨任意 TCP/UTF-8 分片处理 SSE；支持 LF/CRLF/CR、BOM、多行 data、注释和结尾未换行事件。仅发出 Chat 的 `delta.content`、Responses 的 `response.output_text.delta`、Anthropic 的 `text_delta`，忽略思考和工具参数。
4. 必须收到对应的完整结束标志：Chat `[DONE]`、Responses `response.completed`、Anthropic `message_stop`。错误、截断、提前 EOF 或空回复均失败，不把部分输出视为成功。兼容服务若明确返回 JSON，则在同一请求内读取完整回复，不自动重发请求。
5. Store 首个增量立即显示，此后最多约每 50 ms 发布一次，结束/取消/失败时刷新尾部。临时 user/assistant 与成功消息共用 ID，完成时保留同一个消息视图和 WebKit 文档。
6. 文档以 16 ms 定时器合并更新，重新解析完整 Markdown 以处理后到的链接/脚注定义，但只替换发生变化的顶层块。稳定段落、选区、代码滚动位置和折叠状态保留。使用定时器避免离屏原生 WebKit 暂停动画帧而无法测量初始高度。
7. Mermaid 仅在首次需要绘图时加载包内引擎，普通回复无需初始化大型图表库。图表按源码、外观与字号缓存，串行渲染并忽略已移除节点的异步结果。流式期间未闭合围栏先显示代码，闭合后绘图。用户向上滚动或跳转锚点时停止自动跟随底部。

停止/失败的部分回复只存在当前页面，可阅读和复制；切换会话或重新请求会清除该临时内容。完整成功并保存后才进入历史及下一次上下文。未完成的译文不提供“替换原文”操作。

### macOS 鼠标与触控板滚动

WebKit 文档按内容高度展开，外层 SwiftUI 对话负责纵向滚动。macOS 默认 WKWebView 会先消费指针下的滚轮事件，原先鼠标悬停 Markdown 时无法上下滚动。`MacMarkdownWebView.scrollWheel(with:)` 将纵向事件原样传给最近的外层 `NSScrollView`；横向及 Shift 滚轮仍由 WebKit 处理。触控板手势保持同一方向直到惯性阶段结束，零位移的结束事件也正常转交。实现不修改命中测试，正文选区、链接和复制按钮仍可操作。

新增 4 个原生事件回归用例，覆盖上下方向、横向/Shift 滚轮、触控板方向漂移及惯性、取消后重新开始。实际 Mac 预览中复现旧版悬停无滚动，修复后正文向下滚动使外层滚动条从 0 到 1，代码区域向上滚动使外层位置从约 0.956 到 0.699。源码依据：[WKWebView macOS 滚轮实现](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/mac/WKWebViewMac.mm)、[NSScrollView.scrollWheel](https://developer.apple.com/documentation/appkit/nsscrollview/scrollwheel(with:))。

后续针对 macOS 完成回复后的掉帧，提前跳过未变更的原生更新、缓存语义颜色、将锚点位置与绘制状态分离，并让页面及 backing layer 使用不透明语义表面。Release 单窗口对照中，相同六次往返滚动的累计 hitch 时间减少约 20%；测量方式及限制见 [滚动性能记录](MARKDOWN_PERFORMANCE.md)。

## 验证与复现

2026-10-12 已通过：此前 46 个核心 Swift 测试（含三个协议的真实本机 HTTP 流式用例）；本轮设计复核 7 个 Mac UI 模块测试（含原生 WebKit 文件/桥接/测高/图表/辅助设置和滚轮用例）、12 组 WebKit 浏览器渲染测试；iOS/iPadOS 主应用及翻译扩展、macOS 构建通过，无 warning/error。运行时 npm 依赖审计为 0 vulnerabilities。

实际界面检查使用 `--preview-markdown`：Mac 确认 Markdown、表格、语法颜色、原生代码复制成功反馈、Mermaid、公式及追加追问，并通过 ⌘. 停止逐段输出，确认部分富文本仍可见、标记“未完成的回复”，追问草稿已恢复；iPhone/iPad 模拟器确认共享排版，iPhone 额外验证宽图表横向滚动及 Mermaid 源码复制成功反馈。这些使用内存示例，未调用真实远程模型。对应移动端截图保存在 `build/MarkdownValidation/iphone-native-mermaid-scrolled.png` 和 `ipad-native-code-mermaid.png`；浏览器浅色、深色和大字号截图也位于该忽略目录。

```sh
# 资源重建与 WebKit 浏览器回归
cd Scripts/MarkdownRenderer
npm ci --ignore-scripts
npm run build
npx playwright install webkit
npm test
npm audit --omit=dev
```

浏览器测试覆盖 GFM、GitHub 扩展、公式与本地图表、代码原文复制、流式稳定 DOM/选区、未闭合及无效 Mermaid、多种图表类型、HTML 注入及图片显式加载、链接/脚注桥接。截图生成到忽略目录 `build/MarkdownValidation`。

```sh
# 在仓库根目录执行；第二条在另一终端运行
python3 Scripts/mock_model_server.py --port 56344 --log build/markdown-stream-requests.jsonl
COPILOT_STREAM_TEST_URL=http://localhost:56344/v1 swift test
```

Swift 测试覆盖逐字节 SSE 及 UTF-8 边界、可见文本过滤、错误/EOF/空回复、JSON 兼容、流式状态/取消/持久化。设置上述环境变量还会真实访问本机 HTTP fixture，验证三个协议均在 URLSession 中收到多个增量。原生 Mac WebKit 测试直接加载包内文件，验证 CSP、桥接、测高、表格、高亮和 Mermaid，不仅测试 HTTP 浏览器文档。

Debug 主应用支持 `--preview-markdown`，使用本地富文本示例及逐段流式假模型，不读取生产密钥或保存生产历史。普通 `--preview` 的原有行为保留。Xcode Preview 也包含富文本示例。

真机系统翻译权限、真实 BYOK 服务以及完整 VoiceOver 操作仍需在相应环境单独验证；无签名构建、浏览器测试和模拟器不能代替这些检查。

协议资料：[OpenAI Streaming](https://developers.openai.com/api/docs/guides/streaming-responses)、[Responses 事件](https://developers.openai.com/api/reference/resources/responses/streaming-events)、[Claude Streaming](https://platform.claude.com/docs/en/build-with-claude/streaming)。渲染 API：[Marked](https://marked.js.org/)、[Mermaid](https://mermaid.js.org/)。
