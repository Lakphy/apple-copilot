# Apple Copilot — 最小版本设计

## 系统版本与平台能力

主应用最低 iOS 26.0、iPadOS 26.0、macOS 26.0，使用 Swift 6 与 SwiftUI 原生 Liquid Glass。TranslationUIProvider 自 iOS/iPadOS 18.4 起提供，但本工程统一以 26 为下限；该框架不支持 macOS 或 Mac Catalyst。

| 平台 | 导航与布局 | 划词入口 | 设置 |
| --- | --- | --- | --- |
| iPhone | 三个标签页，各自保留导航状态 | 用户选择默认翻译 App 后，系统翻译弹窗承载扩展 | App 内 Form |
| iPad | 可转换为侧栏的 TabView；历史分栏 | 同 iPhone；扩展请求展开系统 sheet 以输入追问 | App 内 Form |
| Mac | NavigationSplitView，支持窗口缩放与键盘 | 系统 Services 接收选中文字，打开原生浮动窗口 | 主窗口设置分区，⌘,；工具栏保存，⌘S |

macOS Services 窗口是 App 提供的原生窗口，不能声称为 Apple 的系统 Translate 弹窗。iOS 扩展只在系统允许替换原文时显示“替换”。

## 最小架构

采用 MV + Observation，不添加转发式 ViewModel 或第三方架构库。

- `CopilotCore`：Sendable Codable 领域值、协议适配、URLSession、Keychain、文件仓库、MainActor observable 模型。可用替代依赖测试。
- `CopilotUI`：共享翻译、对话、历史、设置视图。视图使用语义色与系统字体；内容层保持实心，导航和浮动操作层使用玻璃。
- `AppleCopilotApp`：生命周期、平台导航与 Mac 菜单；设置命令导航到主窗口设置分区。
- `TranslationExtension`：仅 iOS/iPadOS，系统负责弹窗，App 提供 SwiftUI 内容。
- `MacIntegration`：AppKit Services 与 NSPanel 适配。

`SettingsStore` 拥有可编辑草稿与已保存配置，Keychain 拥有密钥。`ConversationStore` 拥有一次会话、请求状态、取消和错误。网络协议及持久化通过注入替换；导航由 UI 层拥有。每次成功回复保存完整 user/assistant 对，失败或取消不产生伪造回复。会话保存协议、域名、模型、提示词和语言快照，追问保持原上下文。

`CopilotEnvironment.load()` 共享正在执行的初始化 Task，等待设置与历史加载完成后才标记已加载。系统弹窗在等待前排除空选区，等待后检查任务取消，避免宿主更新选择时并发初始化读取未就绪的配置。

## 数据与权限

iOS 主应用和扩展通过 App Group 共享配置/历史，通过同一 Keychain access group 共享密钥。Mac 服务属于主应用进程。每个会话单独原子保存 JSON，避免两个进程保存不同会话时覆盖整个历史列表。历史仅保存在本地，不添加云同步。

支持 OpenAI Chat Completions、OpenAI Responses 与 Anthropic Messages。Base URL 可以是 API 根路径、版本路径或完整端点。服务地址由用户在设置中配置，数据去向与本地存储说明集中在“数据与隐私”分组，阅读页不重复显示 AI 或域名 footer。只在用户发起翻译或追问时发送文本及本会话上下文。API key 不写入配置、历史或日志。HTTPS 为默认要求，仅显式启用的本机服务允许 HTTP。

## 界面容器

三个平台的设置使用主页面中的分组 Form，保存位于顶部工具栏；没有独立 Settings scene。系统翻译入口由宿主负责标题与关闭，`TranslationOverlayView` 直接提供原文、译文与追问内容，不叠加内层标题栏。弹窗中的设置在同一容器切换，返回时确认未保存修改，保留该段翻译与追问草稿。

追问控件在三个平台及系统弹窗中使用同一个 Liquid Glass 外层容器。空闲且无文字时为默认高 56 pt（移动端）／48 pt（Mac）的 Capsule；聚焦、非空或生成中时展开为圆角 24 pt 的 RoundedRectangle，文字位于顶部，内容自然增高。发送为容器内右下角的实心 `Color.accentColor` 圆形，图标前景随外观适配（浅色白／深色黑），直径移动端 44 pt、Mac 36 pt，生成时用于停止；按钮和输入不叠加独立玻璃。Mac 输入框的 Escape 只取消焦点，空输入可折叠，不关闭服务窗口。正文和历史列表不施加玻璃。

最终版包含初始化、历史选中色、Mac panel、深色发送前景和 AX5 主翻译动作布局修复，iOS/iPadOS Simulator 与 macOS 最后构建均 PASS。辅助字号下主翻译动作使用 VStack，按钮标签保留水平宽度；iPhone AX5＋深色＋提高对比度的追问与主翻译入口已限定实看。最终移动端系统弹窗及共享历史流程通过本机 HTTP fixture 复验；Mac 主工作区、同 panel 设置与追问使用 Preview 验证，见 [界面重构验证](UI_REDESIGN_VALIDATION.md)。控件尺寸来自实现参数，对比度比值、最小窗口和全平台条件仍未完整验证。

## 验证范围

共享逻辑用 Swift Testing 验证请求格式、解码、URL 校验、历史持久化、错误和取消。三个平台分别构建；系统默认翻译选择、签名权限、真实 BYOK 调用及 VoiceOver/最大 Dynamic Type 需要设备或运行环境验证。预览使用固定内存依赖，不读取真实密钥或联网。
