# Apple Copilot 界面重构验证

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
| 历史行选中后 secondary 文字在蓝色背景上过弱 | [HistoryView.swift](../Sources/CopilotUI/HistoryView.swift) 的选中摘要与元数据使用原生 primary，分别设为 0.9／0.85 opacity | 最新 iPad 历史截图可见选中摘要、语言、追问数与时间；未测量对比度，也未完成最终 AX5／深色覆盖 |
| 系统选区先为空、随后到达正文时，多个初始化任务可能提前使用未就绪设置 | [CopilotEnvironment.load()](../Sources/CopilotUI/CopilotEnvironment.swift) 共享正在执行的 Task，完成后才记录 hasLoaded；[TranslationOverlayView](../Sources/CopilotUI/TranslationViews.swift) 在 load 前排除空选区，等待后再次检查取消 | 最终 iPad 正常进程能自动翻译选区并连续追问；本次实际流程验证正常路径，未将其宣称为所有任务调度组合的专项测试 |
| Mac 服务窗口切换设置时失去前台或隐藏 | [MacServices.swift](../Sources/MacIntegration/MacServices.swift) 保持 floating panel、禁用 hidesOnDeactivate；配置切换标题后等待 Task.yield，再将同一 panel 置前 | 主任务实际打开同一 panel 中的设置，返回后恢复标题并保留追问草稿；内嵌发送及 ⌘Return 均成功，详见下方 Preview 范围 |
| AX5＋深色＋提高对比度时，系统强调色变为较亮青蓝，白色发送箭头辨识度下降 | 保留系统强调色圆形背景，前景随外观适配为浅色白／深色黑 | 最后构建 PASS；主任务实看与新图可见黑色箭头清楚、圆形保持 44 pt。未测量对比度比值，不以旧 AX 图作修正后证据 |
| AX5 时主翻译动作的窄 HStack 把标签挤为两行，按钮形状过大 | [TranslateView](../Sources/CopilotUI/TranslationViews.swift) 在 accessibility 字号使用 VStack，翻译按钮标签 fixedSize 保留水平宽度 | 最后构建 PASS；主任务实看与新图显示语言行和原生翻译按钮竖排、标签单行，不互相挤压。截图为禁用状态，不扩大为全部动作状态已测 |

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
| Apple Copilot iPhone | `A5A74FB8-85CA-4CE5-BD4F-87F4F1803A03` | `FD85C53C-FEA4-4C70-9CAA-A011D800ADB2` |
| Apple Copilot iPad | `F4920C68-7254-4F22-81FD-39EDF97016A2` | `EE9EDB0C-E6A0-4CE9-A2FD-9EBBF82657B3` |

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
xcrun simctl get_app_container A5A74FB8-85CA-4CE5-BD4F-87F4F1803A03 \
  com.lakphy.applecopilot group.com.lakphy.applecopilot
xcrun simctl get_app_container F4920C68-7254-4F22-81FD-39EDF97016A2 \
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
