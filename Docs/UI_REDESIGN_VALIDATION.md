> 开发研究记录：结果对应文中标明的版本与日期，当前整理验证见 [验证说明](VALIDATION.md)。

# Apple Copilot 界面重构验证

## 2026-10-12：圆形图标按钮比例修正

工具栏的新翻译、重置和删除按钮统一使用正方形图标标签（macOS 16 pt，iOS 20 pt），显式指定圆形边框，避免 SF Symbol 的不同固有宽高影响按钮比例。重置按钮交由工具栏原生样式呈现，移除显式 glass 按钮样式。追问发送／停止按钮自身固定为 36 × 36 pt（Mac）或 44 × 44 pt（移动端），不再依赖父布局的尺寸提案限制无限拉伸。译文操作／复制按钮使用 plain 样式，菜单隐藏额外指示箭头，保留原有固定尺寸与辅助功能标签。

独立 bundle ID 的 Mac `--preview` 内存副本已实际检查重置、新翻译和删除按钮的圆形外观；两行追问时发送按钮保持圆形，⌘Return 可发送并显示本地假模型回复。macOS 与 iOS Simulator（含翻译扩展）构建通过，无 warning/error；diff 空白检查通过。移动端本轮仅做编译验证，未新增真机或模拟器外观验证；停止状态与系统翻译弹窗菜单未单独做运行时验证。

## 2026-10-12：原生长文本编辑与组字提示

原文编辑器由 SwiftUI TextEditor 和基于绑定值的 overlay 改为 NSTextView（Mac）／UITextView（iOS）桥接。输入法组字可能尚未更新绑定值，旧 overlay 因而误判为空。现在占位提示在原生视图内部渲染，根据控件真实文本及 marked text 状态立即更新，SwiftUI 更新期间不覆盖组字文本，提交后才同步草稿。新建翻译使用已有 newTranslationID 重建编辑器，清除未提交组字。保留原生换行、滚动、撤销、选择和 Writing Tools。桥接的 delegate 和闭包在销毁时清理，避免循环引用。

新增两个 AppKit 集成测试，实际调用 NSTextView 的 setMarkedText、insertText、insertNewline 和 deleteBackward，验证组字隐藏提示且不发布未提交文本、中文提交、换行、删空和取消组字恢复提示。2 项 UI 集成测试与 35 项核心测试通过。运行中 Mac Preview 验证中文粘贴、回车保留两行、删除后提示恢复、新建清空；iPad 模拟器检查原生编辑器布局。最终 macOS、iOS Simulator 和扩展构建通过，无 warning/error。Mac 手动输入法在最终运行检查时处于拉丁输入，最终组字验证依据 AppKit 集成测试，不声称第三方拼音输入法或移动端组字已逐一实测。[最新 Mac 输入框](Screenshots/mac-native-source-editor.png)。

## 2026-10-12：翻译菜单进入空白页

宽屏工作区的翻译菜单改为显式 Button，每次点击调用现有新建翻译流程，并取消历史详情中的生成、清除历史选择与详情。菜单通过键盘选择时也调用相同流程。原文、追问草稿和当前会话清空，已保存历史不删除。

Mac Preview 实测当前结果页点击翻译进入空白页、已选中翻译时重复点击清空未发送草稿、历史详情点击翻译进入空白页。宽屏 iPad 模拟器实测结果页与历史详情返回空白页，历史会话仍可打开。macOS、iOS Simulator 和扩展构建通过，无 warning/error。

## 2026-10-12：侧栏历史小标题

macOS 和宽屏 iPadOS 的“历史”改为次要颜色的小标题，移除菜单图标和导航 tag，禁用行选择；日期分组与历史会话仍在下方，直接选择会话打开详情。窄屏导航保持原有历史入口。Mac Preview 实际点击标题未切换页面，点击会话正常打开；宽屏 iPad 模拟器已检查外观。两平台及扩展构建通过。[Mac](Screenshots/mac-history-heading.png)、[iPad](Screenshots/ipad-history-heading.png)。

## 2026-10-12：圆形重置按钮与原文光标对齐

重置按钮使用 `.buttonBorderShape(.circle)`，已在 Mac Preview 确认圆形玻璃外观。原文占位文字此前在所有平台共用 20 pt 顶部内边距，Mac 原生 TextEditor 起始位置更高，造成占位文字低于光标；Mac 改为 12 pt，移动端保留 20 pt。已实际检查空白输入光标和占位文字，以及输入“输入测试”后的第一行位置一致。[光标对齐截图](Screenshots/mac-source-caret-aligned.png)。macOS、iOS Simulator 与扩展构建通过，无 warning/error。

## 2026-10-12：iPad 设置表单宽度修复

截图中的两侧白条来自 `SettingsView` 对整个 `Form` 使用 `.frame(maxWidth: 720)` 后再用外层无限宽 frame 居中。这同时缩窄了表单背景与滚动区域，而导航栏标题和操作按钮仍使用完整详情栏。宽屏入口是 `AppRootView` → `HistoryView` 的原生两栏 → `SettingsView`；问题不需要调整侧栏宽度或替换分栏容器。

将 720 pt 限宽限定为 macOS，iOS/iPadOS 由原生 grouped Form 管理内容边距并覆盖完整详情区域。同一设置页在紧凑 Tab 导航与 `SettingsEditor` 中复用。若以后需要限制 iPad 内容阅读宽度，应调整滚动内容边距而非整个滚动容器，参考 [Apple contentMargins 文档](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:)-1lt8b)。

使用 `Scripts/build-simulator.sh build/iPadSettingsFix` 构建成功，并安装到 iPadOS/iOS 26.4 模拟器，以 `--preview` 内存配置验证：iPad 横屏与竖屏背景完整、工具栏与表单同处详情栏，横屏表单可滚动至“数据与隐私”；iPhone 设置页与 Tab Bar 显示正常。此轮未验证真实网络、生产配置保存、iPad 分屏窗口或真机。macOS 限宽分支保留，本轮未单独重建 Mac。

[横屏截图](Screenshots/ipad-settings-full-width-landscape.png) · [竖屏截图](Screenshots/ipad-settings-full-width-portrait.png)

## 2026-10-12：iPad 工具栏按钮高度统一

原生圆形重置按钮与保存胶囊的中心相同，但截图中前者外框约 44 pt、后者约 42 pt，造成重置按钮上沿略高。仅修改标签高度或 controlSize 不改变系统工具栏最终外框。最终 iOS 实现为两枚 plain Button 的标签应用系统 `glassEffect`，统一使用相对 body 字号缩放的 44 pt 高度，并隐藏对应 ToolbarItem 的共享背景，避免重复玻璃轮廓。保留重置圆形、保存胶囊形、启用时蓝色强调和禁用逻辑；加载指示器使用相同外框。Mac 保留原有按钮样式。

模拟器构建通过；iPadOS 26.4 横屏 Preview 实测禁用和启用状态，修改目标语言为日语后保存按钮变蓝，点击显示“设置已保存”。启用截图像素检查两个按钮外框上下界一致。保存使用内存 Preview 仓库，不代表生产持久化测试；未单独复测本轮 iPhone、大字号、减少透明度或真机。

[禁用状态](Screenshots/ipad-settings-toolbar-aligned.png) · [启用状态](Screenshots/ipad-settings-toolbar-aligned-enabled.png)

## 2026-10-12：移除保存成功卡片

依据 apple-design 的 `feedback.md › Best practices`：反馈的重要程度应匹配呈现方式，状态反馈放在对应界面附近，常规成功操作不需要额外突出确认。原有 `saved` 状态会在 Form 顶部插入长期存在的“设置已保存”Section，将配置字段整体下推。此轮移除该成功分组及状态；保存过程中仍显示进度，成功后根据原有 `canSave` 禁用保存按钮，失败仍显示错误。成功时发送 `AccessibilityNotification.Announcement` 供辅助技术接收，不改变表单布局。

iOS Simulator 和 macOS 构建通过。iPadOS 26.4 Preview 实际修改目标语言并保存，确认保存按钮由蓝色恢复禁用，表单首个分组始终为“模型服务”，保存前后没有插入卡片。未实际开启 VoiceOver 验证播报，未重测生产持久化。此结果取代前文以成功卡片作为保存成功外观证据的描述。

[保存后截图](Screenshots/ipad-settings-saved-without-card.png)

## 2026-10-12：统一页面与内容背景

依据 apple-design 的 `color.md › Mobile` 背景层级和 `dark-mode.md › Mobile` 系统动态背景建议，统一同一层级的页面底色，保留输入区、设置分组及侧栏的层次。新增 `Surfaces.swift`：iOS 主背景使用 `systemBackground`，次级内容表面使用 `secondarySystemBackground`；Mac 使用 `windowBackgroundColor` 和 `underPageBackgroundColor`。不硬编码明暗色值，原生侧栏和玻璃导航保持系统材质。

翻译编辑、会话详情、历史空态与独立列表、设置、划词翻译 Overlay 共用页面背景；Form 与历史 List 隐藏系统滚动背景，设置各分组显式使用次级背景，提示词 TextEditor 隐藏独立底色。输入编辑器、InlineNotice、内容展开区及减少透明度时的搜索/composer 背景使用同一套次级表面。Mac 的 `controlBackgroundColor` 在当前系统版本与页面底色相同，复验后改用 `underPageBackgroundColor`，恢复编辑区层次。

iOS Simulator（含扩展）和 macOS 构建通过，`git diff --check` 通过。iPadOS 26.4 Preview 实测翻译编辑、历史详情、设置的浅色/深色切换：对三张截图相同页面边缘坐标取样，浅色均为 RGB 255/255/255，深色均为 0/0/0。次级输入区和表单分组浅色为系统浅灰，深色为系统深灰。iPhone 26.4 实测历史列表、设置的浅色与深色；Mac 主应用检查浅色翻译/设置，独立内存 Preview 验证窗口检查深色翻译、历史详情与设置，并在最终次级色调整后复核深色编辑区和设置。模拟器恢复原先浅色，独立 Mac QA 窗口已关闭；未修改系统全局外观或保存生产设置。

本轮未实际复测扩展 Overlay、真机、多窗口的 elevated 背景、最大字号、增加对比度和减少透明度组合；共享路径已完成编译。

| 页面 | 浅色截图 | 深色截图 |
| --- | --- | --- |
| iPad 翻译 | [浅色](Screenshots/ipad-surfaces-translate-light.png) | [深色](Screenshots/ipad-surfaces-translate-dark.png) |
| iPad 历史详情 | [浅色](Screenshots/ipad-surfaces-history-light.png) | [深色](Screenshots/ipad-surfaces-history-dark.png) |
| iPad 设置 | [浅色](Screenshots/ipad-surfaces-settings-light.png) | [深色](Screenshots/ipad-surfaces-settings-dark.png) |
| iPhone 历史列表 | [浅色](Screenshots/iphone-surfaces-history-light.png) | [深色](Screenshots/iphone-surfaces-history-dark.png) |
| iPhone 设置 | [浅色](Screenshots/iphone-surfaces-settings-light.png) | [深色](Screenshots/iphone-surfaces-settings-dark.png) |

## 2026-10-12：设置重置按钮

保存左侧新增仅显示 `arrow.counterclockwise` 图标的玻璃按钮，提供“重置设置”辅助功能标签和“恢复默认配置，保存后生效”提示。点击恢复默认 ProviderConfiguration，清空未保存的密钥输入；已有 Keychain 密钥不删除，配置仍需通过保存生效。加载或保存期间不可操作。

Mac 内存 Preview 实际将目标语言改为日语，点击重置后恢复简体中文，保存按钮恢复禁用（预览原配置即默认配置）。macOS 和 iOS Simulator／扩展构建通过，diff 检查通过。

## 2026-10-12：提示词上下文变量与目标语言对齐

按用户选择的范围提供 14 个内置模板变量，不增加单独的追问提示词。追问继续携带完整历史和最新用户消息，使用创建该会话时的配置与翻译模板；动态变量在每次请求构造时按当前上下文展开。三个协议分别沿用原有 system / instructions 字段，没有插入额外提示词消息。

| 变量 | 内容 |
| --- | --- |
| `{targetLanguage}` | 当前目标语言 |
| `{sourceLanguage}` / `{sourceLanguageCode}` | 原文主语言的英文名称及代码；短于 20 个字符或无法识别时为 Unknown / und |
| `{sourceLength}` | 原文字符数，按 Swift Character 计数 |
| `{model}` / `{apiProtocol}` | 模型及协议名称 |
| `{currentDate}` / `{currentTime}` | 当前请求日期 yyyy-MM-dd 及时间 HH:mm:ss，使用同一设备时区 |
| `{timeZone}` / `{locale}` | 设备时区与地区标识 |
| `{messageCount}` | 当前用户／助手上下文消息数，不含系统提示词 |
| `{followUpCount}` | 当前追问轮次，首次翻译为 0 |
| `{requestType}` | translation 或 followUp |
| `{appName}` | Apple Copilot |

模板只进行一次替换，插入的值不会再次作为模板处理；`{{targetLanguage}}` 输出字面量 `{targetLanguage}`，未知变量和普通 JSON 大括号保留。原文仍作为 user 消息传递。原文语言识别使用 [Apple NaturalLanguage](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)，结果只是识别建议。

设置提供“添加变量”（追加到末尾）和可展开的变量说明与预览；预览使用明确标注的示例原文及当前设备时间。已在 Mac Preview 中实际从菜单添加 `{model}`，核对预览显示 English、简体中文、2026-10-12、Asia/Shanghai、首次追问 0、原文字符数 40 和配置中的模型。目标语言行从 LabeledContent 改为水平居中布局，输入右对齐，菜单整体占 28 pt，避免菜单内边距影响标签和箭头对齐。

最终目标语言行已在运行中的 Mac Preview 核对：[对齐截图](Screenshots/mac-target-language-aligned.png)。

新增模板测试覆盖旧模板兼容、非递归替换、转义与 JSON、Unicode 字符计数、追问上下文、跨时区日期和时间、短文本识别降级，以及三个协议的变量展开与原文保持。35 项测试通过；macOS、iOS Simulator 和扩展最终构建通过。运行验证使用内存 Preview，不声称真实模型／网络、生产持久化或移动端完整手动操作已验证。

## 2026-10-12：目标语言输入与选择

翻译偏好的目标语言同时提供可编辑 TextField 和常用语言菜单，均绑定原有 `settings.configuration.targetLanguage`。菜单列出 16 种常用语言，并用 inline Picker 直接展开选项，当前手动输入不在列表时保留自定义选项，避免无效 selection 或覆盖自定义输入。Mac 使用同一水平中心对齐的标签与输入控件，iPhone/iPad 保留字段标题位于输入上方的布局；原有验证和保存流程未改变。

在独立 Mac Preview 中实际输入“冰岛语”，验证自定义值保留；从菜单选择“日语”，输入框同步更新，“保存设置”可用，保存后显示“设置已保存”。最后 inline 菜单版本再次验证直接选择日语。macOS 和 iOS Simulator/扩展最终构建通过，无 warning/error。保存验证使用内存仓库，不代表生产磁盘持久化或移动端操作已单独重测。[菜单截图](Screenshots/mac-target-language-list.png)。

## 2026-10-12：复制反馈

译文和模型回复使用共享的 `AssistantMessageView`，复制成功后按钮图标以 SF Symbol replace 过渡变为绿色对勾，约 1.5 秒后恢复。每条消息独立保存状态；重复复制改变 task identity，取消旧的复位计时。菜单中的复制和应用定义的正文 context menu 复用同一个复制函数；系统翻译内容的更多操作按钮也会短暂显示对勾。减少动态效果时关闭符号过渡，保留静态对勾及“已复制”辅助功能标签。macOS 仅在 pasteboard 写入成功后展示成功状态。

已在最新独立 Mac Preview 中实际点击译文复制，辅助功能标签变为“已复制”并恢复“复制译文”；发送预览追问后点击回复复制，确认该回复标签变为“已复制”，译文复制状态独立。macOS、iOS Simulator 与扩展构建通过，无 warning/error。本轮未完整操作系统服务更多菜单、移动端复制或开启减少动态效果；AppKit 原生文本选择的 Copy 菜单由系统处理，不将其视为应用自定义 context menu 的已验证路径。

## 2026-10-12：固定侧栏与简化历史菜单

本节记录最新导航，取代下方裁切修复阶段的三栏设计。根据用户的系统设置截图，Mac 默认窗口改为 900×760 pt，最小尺寸 760×600 pt；侧栏占窗口宽度约 31%，限制在 240–320 pt，所有主页面使用相同的两栏比例。Mac 的固定两栏没有收起按钮、分隔条拖拽收起或 `SidebarCommands` 菜单命令。侧栏菜单与历史行铺满可用列宽；设置固定在底部。

iPad 在 regular size class 且可用宽度不少于 760 pt 时使用苹果原生 `NavigationSplitView`、`.sidebar` List 和选中样式，搜索改用胶囊形 Liquid Glass 控件。列可见性固定为 `.all`，移除 `.sidebarToggle`，并通过仅在宽屏布局中安装的 UIKit 桥接设置 `presentsWithGesture = false`、`showsSecondaryOnlyButton = false`、tile 和 oneBesideSecondary，保留原生侧栏外观。窄屏与 iPhone 使用 Tab 导航和独立历史列表。

两个宽屏平台的历史会话均直接列在侧栏“历史”菜单下方，按日期分组；按后续要求，条目只显示单行标题，省略译文摘要、语言、更新时间和追问数。底部设置使用 Mac 的整行按钮及 iPad 的原生 sidebar List 行。iPhone 独立历史列表保留原有详细摘要。

已在 Preview 中实际检查 Mac 两栏、历史选择、底部设置和单行条目；在 iPadOS 26.4 模拟器检查原生侧栏、历史选择、设置切换、清除搜索、横竖屏及侧栏滑动后仍可见。iPhone 已确认仍显示 Tab Bar。本轮 29 项核心测试通过，最终 macOS 与带模拟器 entitlement 的 iOS/扩展构建通过，无 warning/error；没有以 Preview 固定回复代替真实网络或持久化验证。随后按用户要求去掉 Mac 左右栏之间的 `Divider`；两个宽屏平台使用共享 `GlassHistorySearch`，只有外层胶囊施加 `.regular.interactive()`，清除按钮不叠加玻璃，减少透明度时改用系统背景。原生 iPad 的横屏截图：[原生固定侧栏](Screenshots/ipad-native-fixed-sidebar.png)。早期 `ipad-fixed-workspace-sidebar.png` 是原生分栏调整之前的自定义两栏截图，不作为最终 iPad 外观。

本次玻璃搜索的最新截图：[Mac 无左右分割线与玻璃搜索](Screenshots/mac-glass-search-no-divider.png)、[iPad 原生侧栏与玻璃搜索](Screenshots/ipad-glass-search-no-divider.png)。macOS 与 iOS 模拟器最终构建通过，无 warning/error；已实际验证 Mac 输入不匹配关键词出现空结果、清除后恢复历史及打开详情，并静态查看最终 iPad 横屏外观。减少透明度降级路径本次未单独开启系统偏好复测。

## 2026-10-12：macOS 历史分栏裁切修复

本轮根据用户截图检查 `AppRootView` → `HistoryView` → `ConversationDetail` 的布局链路，并在 macOS 27.2、Xcode 27.0 下实际复现。原来主窗口的两栏 `NavigationSplitView` 将另一个两栏 `NavigationSplitView` 放在 detail 中；辅助功能树显示两个嵌套的 `SidebarNavigationSplitView`。应用侧栏展开时，历史详情向右错位，复制按钮和追问输入区到达窗口边缘；收起侧栏后布局明显改变。单独移除嵌套后，详情仍存在宽度溢出，因此不能把所有现象只归因于嵌套容器。

修复包含三部分：macOS 历史页由一个原生三栏分栏容器管理应用导航、历史列表和会话详情；详情列设置 320 pt 最小宽度及弹性最大宽度；阅读区与底部 composer 的宽度 frame 显式使用 `minWidth: 0`，接受所在列的窄宽度提议，同时保留 760／800 pt 最大宽度。主窗口最小宽度由 600 改为 800 pt，为三栏最小宽度留出空间。iPhone／iPad 继续使用原来的独立历史两栏导航。

验证使用 `--preview` 的内存历史和固定回复，后半段使用不同 bundle ID 的独立验证副本，避免与用户正在操作的主窗口冲突。最终辅助功能树只有一个分栏容器、两个分隔条。已实际检查选中历史、应用侧栏展开／收起、调整分隔条压窄详情、两行中文追问用 ⌘Return 发送、Escape 取消输入焦点，以及切换翻译工作区和设置页。以上是 UI 与 Preview 交互验证，不是远程模型或生产历史持久化验证。未实际完成主窗口拖拽到 800 pt 最小宽度的验证，窄布局证据来自调整分隔条。

截图：[三栏历史详情](Screenshots/mac-history-layout-fixed.png)、[收起应用侧栏](Screenshots/mac-history-sidebar-hidden-fixed.png)、[压窄详情列并显示追问](Screenshots/mac-history-narrow-detail-fixed.png)。29 项核心测试通过；macOS 和 iOS Simulator 构建通过。原有系统服务 panel 本轮没有单独重测。

## 2026-10-12：iPhone 历史详情隐藏 Tab

按用户要求，仅 iPhone 在显示历史会话详情时隐藏底部 Tab。`HistoryView.historyDetail` 提供 `.tabBar` 隐藏偏好，历史列表保留系统默认偏好；不在列表强制 `.visible`，以免覆盖详情的隐藏偏好。现有输入框继续使用底部 `safeAreaInset`，随 Tab 隐藏自然下移，保留安全区与外边距。iPad 使用 `.automatic`，Mac 不增加此修饰。

Simulator 构建通过；iPhone 26.4 模拟器已实际核对进入详情、折叠／聚焦展开的输入区、顶部返回后 Tab 恢复，以及再次进入时重新隐藏。iPad 最新包已检查历史详情仍保留顶部 Tab 与分栏。macOS 条件编译检查通过。截图：[iPhone 详情无 Tab](Screenshots/iphone-history-detail-no-tab.png)。本次未以软件键盘、边缘返回手势或删除当前记录路径的验证作为通过依据；追问网络逻辑未修改。

## 重构版本与功能证据

本文区分重构中的外置按钮版功能验证，以及最终单一玻璃容器、内嵌按钮版的构建与截图。前一版使用正常模式 App 与系统 Translation Provider 扩展，向回环 HTTP fixture 发送真实 `URLSession` 请求；它验证请求、连续对话和共享历史的功能链路。回复由本地脚本固定生成，**不代表真实大模型的翻译质量、远程网络表现或真实 BYOK 服务兼容性**。

| 版本与证据 | 当前结论 | 不能据此推断 |
| --- | --- | --- |
| 前一版外置按钮：请求 #2–#7、历史文件与当时的截图 | 两台设备的 1／3／5 条上下文校验通过；两条会话均持久化六条消息，功能证据有效 | 这些请求不是最终内嵌按钮版的新请求；当时截图不是最终布局 |
| 最终代码：单一外层玻璃、运行修复、深色前景与 AX 动作布局 | iOS/iPadOS Simulator 与 macOS 最终构建均 PASS，退出码 0；最新包均重新启动 | 构建不证明全部视觉、命中区或交互条件通过 |
| 最终三平台主界面与系统翻译入口截图 | 已静态查看单一外框、内部圆形发送及上方输入；iPhone／iPad 弹窗与 Mac panel 只保留一处宿主标题 | 不等于全部窗口、字号、背景及辅助技术覆盖 |
| 最终 iPad 系统弹窗：请求 #8–#10 与新历史 | 内嵌发送两轮成功；上下文 1／3／5 校验通过；系统 × 关闭后主 App 显示新会话的六条消息 | 本机 HTTP fixture 的回复不证明真实模型质量或远程 BYOK 兼容性 |
| 最终 iPhone 系统弹窗：请求 #11–#13 与新历史 | 内嵌发送两轮成功；上下文 1／3／5 校验通过；系统 × 关闭后主 App 显示新会话的六条消息 | 同为本机 HTTP fixture；读取 UI 树中的消息不等同于 VoiceOver 验证 |
| 最终 Mac 服务窗口：设置返回、内嵌发送与 ⌘Return | 同一 panel 内打开／返回设置，标题恢复且草稿保留；两轮追问成功 | 使用 Preview 固定回复，不证明网络请求、生产持久化或真实 BYOK |
| Mac 最后构建主工作区：两行追问与选中历史 | ⌘Return 发送成功，打开同一会话；选中摘要与元数据在原生高亮上清楚 | 仍使用 Preview，非生产持久化；不声称最后颜色修改后又重跑服务 panel |
| 最终 iPhone AX5＋深色＋提高对比度 | 黑色发送箭头清楚，44 pt 圆形不随字号扩大；四行输入内部滚动；主翻译动作竖排且标签单行 | 限定两个已列界面，不代表全平台 AX5／深色覆盖；未测对比度比值，未做 VoiceOver |

## 最终内嵌输入容器：构建与截图

共用 `GlassComposer` 只在外层施加 Liquid Glass。空闲、未聚焦且无文字时为 Capsule，默认高移动端 56 pt、Mac 48 pt；聚焦、非空或生成中时为圆角 24 pt 的 RoundedRectangle，文字位于上方，容器自然增高。发送是外层玻璃内部右下角的实心 `Color.accentColor` 圆形，前景图标随明暗外观适配（浅色白／深色黑），直径移动端 44 pt、Mac 36 pt；生成中用于停止。上述数值来自源码参数，未作像素测量。

最终代码包含初始化、历史选中行、Mac panel、深色发送前景与 AX5 主翻译动作布局修复。主任务确认 iOS/iPadOS Simulator 与 macOS 最后构建均 **PASS**，退出码 0，构建日志没有 warning／error；iPhone、iPad 已重新安装启动，Mac 最新包已重新启动为 Preview。文档复核静态查看以下明确版本的截图；最后两项为 AX5＋深色＋提高对比度，其余为浅色：

| 最终版截图 | 可见内容 |
| --- | --- |
| [Mac 折叠](Screenshots/mac-composer-collapsed.png) | 主翻译工作区；空输入为单一胶囊，禁用发送在胶囊内部 |
| [Mac 展开](Screenshots/mac-composer-expanded.png) | 聚焦时有焦点描边；两行文字在上方，实心圆形发送在容器内右下角 |
| [Mac 最终选中历史](Screenshots/mac-history-composer.png) | 最新进程中发送的两行追问与固定回复；04:05 会话选中摘要、语言、追问数和时间在原生高亮上可读 |
| [iPhone 折叠](Screenshots/iphone-composer-collapsed.png) | 历史详情与六条既有消息；空输入胶囊中的禁用发送 |
| [iPhone 展开](Screenshots/iphone-composer-expanded.png) | 同一详情中的四行追问草稿；文字在上方，发送位于外层容器内右下角 |
| [Mac 服务窗口折叠](Screenshots/mac-system-composer-collapsed.png) | 原生 panel 的单一标题、译文及内嵌禁用发送；非 Apple 系统 Translate sheet |
| [Mac 服务窗口两轮对话](Screenshots/mac-system-composer-chat.png) | 两次追问与 Preview 固定回复；阅读区可滚动，追问容器仍在底部 |
| [iPad 系统弹窗折叠](Screenshots/ipad-system-composer-collapsed.png) | 真实选区锚定 popover；仅一处宿主标题和 ×，单一胶囊容器 |
| [iPad 系统弹窗展开](Screenshots/ipad-system-composer-expanded.png) | 追问文字在上方，实心圆形发送位于外层容器内右下角 |
| [iPad 系统弹窗两轮对话](Screenshots/ipad-system-composer-chat.png) | 译文、两轮追问与回复可见，空输入恢复折叠 |
| [iPad 共享历史](Screenshots/ipad-history-composer.png) | 03:57 新会话选中；摘要与元数据在蓝色选中底上可读，详情显示六条消息 |
| [iPhone 系统弹窗折叠](Screenshots/iphone-system-composer-collapsed.png) | 真实划词后自动译文；系统 sheet 单一标题与 ×，空输入胶囊内含禁用发送 |
| [iPhone 系统弹窗展开](Screenshots/iphone-system-composer-expanded.png) | 聚焦时 sheet 扩展；上方追问文字、容器内部右下角实心发送 |
| [iPhone 系统弹窗两轮对话](Screenshots/iphone-system-composer-chat.png) | 译文与两问两答可见；发送后空输入仍有焦点，容器保持展开 |
| [iPhone 最终追问辅助字号](Screenshots/iphone-composer-accessibility-final.png) | AX5＋深色＋提高对比度；黑色箭头位于明亮系统强调色圆形内，输入显示四行并保留内部发送 |
| [iPhone 最终主翻译辅助字号](Screenshots/iphone-translate-accessibility-final.png) | 相同条件；目标语言在上、原生翻译按钮在下，标签保持单行；截图为无原文时的禁用状态 |

这些截图只证明所示条件下的静态布局，不代替主任务的操作结果。最早的 `iphone-system-chat.png` 与 `BeforeRedesign` 目录只保留为历史功能基线，不标为最终弹窗。`iphone-composer-accessibility.png` 采集于最新按钮颜色修复前，不作为最终辅助字号或对比度通过证据。

Mac 当前输入框的 Escape 只取消焦点，空输入可以折叠，不关闭 Services 弹窗；关闭使用原生窗口按钮。这是当前交互定义，不代表完整键盘路径已验证。

## 本轮运行问题与修复复验

| 观察到的问题 | 当前实现 | 已验证范围 |
| --- | --- | --- |
| 历史行选中后 secondary 文字在蓝色背景上过弱 | [HistoryView.swift](../Sources/CopilotUI/History/HistoryView.swift) 的选中摘要与元数据使用原生 primary，分别设为 0.9／0.85 opacity | 最新 iPad 历史截图可见选中摘要、语言、追问数与时间；未测量对比度，也未完成最终 AX5／深色覆盖 |
| 系统选区先为空、随后到达正文时，多个初始化任务可能提前使用未就绪设置 | [CopilotEnvironment.load()](../Sources/CopilotUI/CopilotEnvironment.swift) 共享正在执行的 Task，完成后才记录 hasLoaded；[TranslationOverlayView](../Sources/CopilotUI/Translation/TranslationOverlayView.swift) 在 load 前排除空选区，等待后再次检查取消 | 最终 iPad 正常进程能自动翻译选区并连续追问；本次实际流程验证正常路径，未将其宣称为所有任务调度组合的专项测试 |
| Mac 服务窗口切换设置时失去前台或隐藏 | [MacServices.swift](../Sources/MacIntegration/MacServices.swift) 保持 floating panel、禁用 hidesOnDeactivate；配置切换标题后等待 Task.yield，再将同一 panel 置前 | 主任务实际打开同一 panel 中的设置，返回后恢复标题并保留追问草稿；内嵌发送及 ⌘Return 均成功，详见下方 Preview 范围 |
| AX5＋深色＋提高对比度时，系统强调色变为较亮青蓝，白色发送箭头辨识度下降 | 保留系统强调色圆形背景，前景随外观适配为浅色白／深色黑 | 最后构建 PASS；主任务实看与新图可见黑色箭头清楚、圆形保持 44 pt。未测量对比度比值，不以旧 AX 图作修正后证据 |
| AX5 时主翻译动作的窄 HStack 把标签挤为两行，按钮形状过大 | [TranslateView](../Sources/CopilotUI/Translation/TranslateView.swift) 在 accessibility 字号使用 VStack，翻译按钮标签 fixedSize 保留水平宽度 | 最后构建 PASS；主任务实看与新图显示语言行和原生翻译按钮竖排、标签单行，不互相挤压。截图为禁用状态，不扩大为全部动作状态已测 |

## 限定辅助字号与深色复验

主任务在 iPhone 上使用 **AX5＋深色＋Increase Contrast**，实际检查最终追问输入和主翻译入口。发送箭头以黑色绘制在明亮的系统 accent 圆形里，图标固定 17 pt、圆形框固定 44 pt，未随正文放大；多行追问达到四行后可在输入框内部滚动。文档已静态查看 [修正后的追问图](Screenshots/iphone-composer-accessibility-final.png)，可见箭头与背景区别清楚、按钮仍在容器内部。尺寸来自源码和主任务操作记录，未作像素或对比度比值测量。

主翻译入口改为辅助字号下的竖排操作布局，目标语言和原生翻译按钮互不挤压，标签保持单行；[最终主翻译图](Screenshots/iphone-translate-accessibility-final.png) 显示无原文的禁用状态。两个所示条件的实际复验通过，不能将其扩大为 iPad／Mac、全部控件状态和所有背景的 AX5／深色验证。主任务结束后将 iPhone 偏好恢复为浅色、Large、关闭提高对比度。

## 最终 Mac 服务窗口：同容器设置与两轮追问

主任务实际复验设置仍在原服务 panel 内；返回翻译后标题恢复为“Apple Copilot · 划词翻译”，原追问草稿保留。两轮问题分别通过内嵌发送按钮与 ⌘Return 发送，窗口显示对应回复。该过程使用 Debug Preview 的本地固定模型；上方 [Mac 两轮对话截图](Screenshots/mac-system-composer-chat.png) 中的回复也是固定文本，不用于评价问题理解或翻译质量。该结果不代表真实 BYOK、远程请求或生产历史写入已验证。

Mac 最后构建的进程又在主工作区用 ⌘Return 发送两行问题 `What does simple mean?`／`Please explain.`，随后打开历史并选择同一会话。[最新历史图](Screenshots/mac-history-composer.png)可见对应两行追问、固定回复及原生蓝色高亮上的摘要与元数据；主任务实际观察这些文字清楚。`mac-composer-collapsed.png`／`expanded.png` 已由该最终进程重拍。服务 panel 的设置返回与两轮追问保留为此前内嵌布局的实测结果，不称为最后纯外观修改后再次完整执行的 panel 流程。

## 最终 iPad 系统翻译弹窗：请求与持久化

主任务从真实划词的系统 Translate 菜单打开最终内嵌按钮版 popover，获得自动译文，两轮追问均点击容器内发送按钮。请求日志只读核对如下：

| 请求 | 操作 | 日志中的上下文角色 | 消息数 | 校验 |
| --- | --- | --- | --- | --- |
| #8 | 翻译原文 | `user` | 1 | `context_valid=true`，`errors=[]` |
| #9 | 首轮追问 | `user → assistant → user` | 3 | `context_valid=true`，`errors=[]` |
| #10 | 第二轮追问 | `user → assistant → user → assistant → user` | 5 | `context_valid=true`，`errors=[]` |

主任务点击系统 × 后，在 App 历史选中 03:57 的新会话并看到完整内容。只读磁盘核对：会话 `80301EBC-E9FB-47B4-9D29-6E05FFEF12FB`，更新时间 **2026-10-12 03:57:34.078629 +08:00**，六条角色依次为 `user → assistant → user → assistant → user → assistant`。原文为 `Good design makes complex things simple.`，两个追问依次为 `What does complex mean?`、`Make it more natural.`；内容与 fixture 一致。这是最终版中新建的会话，与前一版 03:32 会话及最早 03:00 基线会话分别记录。

正常 App、系统扩展、真实 URLSession、完整追问上下文、系统关闭与共享历史路径在这次 iPad 流程中通过。回复仍来自回环 HTTP fixture，不将成功扩展为真实远程模型结论。

## 最终 iPhone 系统翻译弹窗：请求与持久化

主任务从真实划词进入最终版系统 sheet，自动翻译后通过容器内的发送按钮完成两轮追问。日志只读核对如下：

| 请求 | 操作 | 日志中的上下文角色 | 消息数 | 校验 |
| --- | --- | --- | --- | --- |
| #11 | 翻译原文 | `user` | 1 | `context_valid=true`，`errors=[]` |
| #12 | 首轮追问 | `user → assistant → user` | 3 | `context_valid=true`，`errors=[]` |
| #13 | 第二轮追问 | `user → assistant → user → assistant → user` | 5 | `context_valid=true`，`errors=[]` |

主任务点击系统 ×，回到主 App 历史，打开 03:59 的新会话；UI 树显示原文、译文、两问两答。只读磁盘核对：会话 `2D61F344-2484-40F9-B43F-68584ACCF3CB`，更新时间 **2026-10-12 03:59:52.203659 +08:00**，六条角色交替为 `user / assistant`，原文及两个追问与上方 iPad 最终流程一致。它是最终版的新会话，不复用外置按钮版 03:29 的数据作为本轮成功证明。

最终 iPhone／iPad 的六个请求 #8–#13 全部通过上下文校验；两台设备关闭系统弹窗后均保留六条消息并由主 App 历史读取。它们验证正常进程与回环 HTTP 的功能链路，不评价远程模型质量，也不将 UI 树读取结果称为 VoiceOver 测试通过。

这组六个请求执行后又追加了深色图标前景与 AX5 主翻译动作布局修正；最新构建和限定辅助字号实看分别记录于上方，不把旧请求编号称为这些最后外观修改后再次执行的请求。

## 前一版功能验证：环境与证据边界

- 日期：2026-10-12；iPhone 首次只读核对时间 03:31 +08:00，随后补充当时外置按钮版的 iPad 证据。
- 运行时：iOS / iPadOS 26.4；正常模式，不使用 `--preview`。
- 测试协议：OpenAI Chat Completions；Base URL `http://localhost:56343/v1`；模型 `copilot-test-model`；仅使用 fixture 的测试凭据。
- 请求证据：`build/ui-redesign-requests.jsonl`。此日志属于本轮重构验证，与旧版 `build/mock-requests.jsonl` 的请求编号分别计数。
- 历史证据：两台测试模拟器中 `group.com.lakphy.applecopilot/AppleCopilot/Conversations/*.json`，通过 `simctl get_app_container` 定位后只读检查。
- 本文的只读检查未操作模拟器界面、未启动或停止服务器、未修改 Swift 源码。构建、系统弹窗操作与截图由主任务执行；本文只静态查看明确列出的最终截图，不能从其他文件存在单独推断布局合格。

| 设备 | UDID | App Group 容器 UUID |
| --- | --- | --- |
| Apple Copilot iPhone | `<IPHONE_SIMULATOR_UDID>` | `<IPHONE_INSTALLATION_ID>` |
| Apple Copilot iPad | `<IPAD_SIMULATOR_UDID>` | `<IPAD_INSTALLATION_ID>` |

## 前一版 iPhone 系统翻译弹窗：请求与持久化

外置按钮版的系统弹窗对应请求 #2、#3、#4；主任务当时通过系统关闭控件关闭弹窗并回到历史。请求日志和磁盘历史分别提供以下证据；这些请求不重新标记为最终内嵌按钮版的运行结果。

| 请求 | 操作 | 日志中的上下文角色 | 消息数 | 校验 |
| --- | --- | --- | --- | --- |
| #2 | 翻译原文 | `user` | 1 | `context_valid=true`，`errors=[]` |
| #3 | 首轮追问 | `user → assistant → user` | 3 | `context_valid=true`，`errors=[]` |
| #4 | 第二轮追问 | `user → assistant → user → assistant → user` | 5 | `context_valid=true`，`errors=[]` |

日志消息数不含 system prompt；发送第二轮追问时尚未获得本轮回复，因此请求含 5 条消息，完成后的历史含 6 条。Fixture 除角色顺序外，还检查先前 assistant 回复完整保留、prompt 非空、模型符合测试配置及非流式请求。

该轮持久化会话：`4780C43D-A215-4ABF-B872-57AB323E4CAA`。文件更新时间为 **2026-10-12 03:29:45.150636 +08:00**。关闭系统弹窗后，在主 App 共用的 App Group 中仍有以下六条消息：

| 顺序 | 角色 | 持久化内容 |
| --- | --- | --- |
| 1 | user | Good design makes complex things simple. |
| 2 | assistant | 优秀的设计让复杂的事情变得简单。 |
| 3 | user | What does complex mean? |
| 4 | assistant | complex 的意思是“复杂的”。这里强调优秀设计帮助人们轻松理解复杂内容。 |
| 5 | user | Make it more natural. |
| 6 | assistant | 自然一点可以译为：“好的设计，能把复杂的事变简单。” 这延续了前面的译文和词义说明。 |

上述原文、两次追问、三次固定回复与本轮日志和 fixture 定义一致。存档保留本次协议、Base URL、模型与目标语言配置；API Key 不属于 Conversation 的可编码结构。

旧弹窗截图不放入最终布局证据。最终版本打开这一既有会话的截图见上方 iPhone 折叠／展开行；显示历史内容不代表已在该版本重新执行 #2–#4。

## 前一版 iPad 系统翻译弹窗：请求与持久化

主任务当时在外置按钮版通过真实划词 → 系统 Translate 菜单进入弹窗，完成初次翻译和两轮追问，再用系统关闭控件返回主 App 历史并选择该会话。其 UI accessibility tree 展示原文、译文、两次追问和两次回复；只读磁盘检查提供同一会话的独立证据。读取树中的文字不能等同于 VoiceOver 交互测试通过。

| 请求 | 操作 | 日志中的上下文角色 | 消息数 | 校验 |
| --- | --- | --- | --- | --- |
| #5 | 翻译原文 | `user` | 1 | `context_valid=true`，`errors=[]` |
| #6 | 首轮追问 | `user → assistant → user` | 3 | `context_valid=true`，`errors=[]` |
| #7 | 第二轮追问 | `user → assistant → user → assistant → user` | 5 | `context_valid=true`，`errors=[]` |

该轮 App Group 会话：`551523E1-3DD3-40CE-93BB-5F7647B1B6A2`，更新时间 **2026-10-12 03:32:13.778819 +08:00**。该文件含六条交替的 `user / assistant` 消息；原文、两个追问及三个回复与上方 iPhone 六条内容一致，也与该轮 #5 / #6 / #7 日志及 fixture 定义一致。它是外置按钮版中新建的会话，未将 03:00 的最早基线会话用于这一结论。

当时的 [iPad 系统弹窗](Screenshots/ipad-system-chat-redesigned.png) 与 [共享历史](Screenshots/ipad-history-redesigned.png) 为外置按钮版记录，不能证明最终单一外层玻璃、内嵌发送布局。最终版的新图单独列于上方，文件名含 `composer`。

## 前一版功能结论的有效范围

两台设备当时的系统弹窗均向 fixture 发送 1 / 3 / 5 条逐步增长的对话上下文；#2–#7 六次请求的 `context_valid` 全部为 true。两条新会话在系统弹窗关闭后保留六条完整消息，并由主 App 历史读取。该次核对日志有七条请求，其中 #1 为准备过程，未混入上述两条系统弹窗流程。

这些连续对话和持久化证据仍有效。此后输入区改为单一外层玻璃、内嵌实心发送按钮，并调整焦点和 Escape 行为；因此旧截图不能承载最终布局结论，保留的历史数据也不能当成最终版重新完成整条翻译流程的证明。

## 只读复核方法

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl get_app_container "$COPILOT_SIMULATOR_UDID" \
  com.lakphy.applecopilot group.com.lakphy.applecopilot
xcrun simctl get_app_container "$COPILOT_SIMULATOR_UDID" \
  com.lakphy.applecopilot group.com.lakphy.applecopilot
```

读取返回路径下的 `AppleCopilot/Conversations`，按 `updatedAt` 排序并核对会话 ID、角色和内容。JSON 日期为 Foundation 默认的 2001-01-01 UTC 参考时间，本文已换算为 +08:00。此流程不会更改默认翻译 App、历史或测试服务器状态。

## 尚未覆盖

- 真实远程模型质量、真实密钥权限、三种协议的远程服务验证。
- 真机安装与发行 provisioning。
- VoiceOver、Reduce Transparency 和完整键盘路径。
- iPad／Mac 最大 Dynamic Type、深色及提高对比度，以及全部控件状态与背景的组合；iPhone 已验证的两个条件不代表全平台覆盖。
- 中文输入法候选确认、长原文和键盘出现后的窄弹窗检查。iPhone 详情已有四行草稿截图，不代表所有宿主和窗口条件已覆盖。

本地 mock 的成功不能将上述项目视为通过；本轮界面评估需要结合重构后的实图与实际交互。
