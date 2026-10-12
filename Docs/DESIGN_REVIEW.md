> 开发研究记录：结果对应文中标明的版本与日期，当前整理验证见 [验证说明](VALIDATION.md)。

# Apple Copilot 平台设计检查

## Summary

基线评级：**Needs work**。撤回旧报告的 Excellent 评级：用户指出的发送控件过大、系统弹窗标题叠加、历史与设置布局问题，影响日常阅读和操作；使用原生组件并不能证明这些问题已经解决。产品应以“原文—译文—连续追问”为唯一阅读主线，让导航与玻璃控件退到内容周围。

本轮依据是用户反馈、[重构计划](UI_REDESIGN_PLAN.md)、当前 SwiftUI 源码、主任务操作记录和明确版本的最终截图。最终版包含单一外层玻璃、运行问题、深色发送前景和 AX5 主翻译动作修复，iOS/iPadOS Simulator 与 macOS 最后构建均 **PASS**。移动端两轮发送、关闭与共享历史已实际复验；Mac 工作区和同 panel 设置／追问用 Preview 复验。iPhone 追问与主翻译入口的 AX5＋深色＋提高对比度限定实看及新图已确认，完整辅助技术覆盖仍有缺口。以下保留基线评级，区分实现、构建、截图与实际交互，不授予新版 Excellent。

## 基线问题与本轮对照

| 优先级与问题 | 为什么需要修复 | 本轮处理与证据 | 尚待确认 |
| --- | --- | --- | --- |
| **High — 发送按钮过大，且前一版输入与发送分离。** 用户明确要求同一个玻璃容器包住文字和发送；旧报告仅检查最小命中区，没有完整判断比例与组合关系。 | [buttons.md › Style](../.agents/skills/apple-design/references/hig/buttons.md#style)：“Use style — not size — to visually distinguish the preferred choice”。命中区与视觉强调是两项不同检查；统一容器关系来自本轮用户要求。 | 共用 [GlassComposer](../Sources/CopilotUI/Translation/GlassComposer.swift) 已实现：空闲为空时 Capsule，默认高移动端 56 pt、Mac 48 pt；聚焦、非空或生成中为圆角 24 pt 的 RoundedRectangle，文字在顶部并自然增高。发送内嵌右下角，图标前景随外观适配（浅色白／深色黑），直径移动端 44 pt、Mac 36 pt；同一按钮承担停止。移动端两轮发送实际成功；iPhone AX5＋深色＋提高对比度新图中黑箭头清楚，圆形不随字号扩大。 | 最小宽度、停止／失败后状态及完整命中区检查；当前限定复验不代表所有平台与条件。前一版分离控件截图不能证明本版通过。 |
| **High — 系统翻译宿主与应用内层重复显示标题。** 旧报告将这项阅读空间损失降为 Low，判断偏低。 | [toolbars.md › Titles](../.agents/skills/apple-design/references/hig/toolbars.md#titles)：“If titling a toolbar seems redundant, you can leave the title area empty.” | [TranslationViews.swift](../Sources/CopilotUI/Translation/TranslationOverlayView.swift) 的 `TranslationOverlayView` 已去掉内层 NavigationStack 与品牌标题；内容直接交给系统容器，译文旁提供复制／替换／设置操作。最终 iPhone sheet、iPad popover 与 Mac panel 截图各有一处宿主标题，未叠加应用内标题栏。 | 各平台软件键盘出现时的宿主布局，当前截图不覆盖全部输入条件。 |
| **High — 历史列表与详情层级重复，摘要难扫描。** 用户反馈与重构计划明确要求整理容器和阅读层级。 | [layout.md › Visual hierarchy](../.agents/skills/apple-design/references/hig/layout.md#visual-hierarchy)：“Align elements to make them easier to scan”。[lists-and-tables.md › Content](../.agents/skills/apple-design/references/hig/lists-and-tables.md#content)：“Keep item text succinct so row content is comfortable to read.” | [HistoryView.swift](../Sources/CopilotUI/History/HistoryView.swift) 已使用日期分组 plain List；每条记录展示摘要、目标语言、追问数和时间，详情标题 inline。选中行摘要／元数据改用原生 primary（0.9／0.85 opacity）；最新 iPad 与 Mac 浅色图可见选中摘要及元数据，主任务已实际选择对应会话。 | 最小列宽、Mac 窄窗及最大字号；选中色对比度比值未测量，浅色图不覆盖暗色／提高对比度的历史行。 |
| **High — 设置布局与使用路径不符，保存位于长表单末尾。** 用户要求设置嵌入主页面；关键动作还需要保持可发现。 | [layout.md › Desktop (macOS)](../.agents/skills/apple-design/references/hig/layout.md#desktop-macos)：“Avoid placing controls or critical information at the bottom of a window.” [toolbars.md › Actions](../.agents/skills/apple-design/references/hig/toolbars.md#actions) 建议将关键动作作为 trailing 主动作。 | [AppRootView.swift](../Sources/CopilotUI/AppRootView.swift) 的 Mac 导航已有设置分区；[SettingsView.swift](../Sources/CopilotUI/Settings/SettingsView.swift) 分组表单，保存置于工具栏。`SettingsEditor` 在弹窗原容器切换，提供返回及未保存确认；Mac 支持 ⌘,／⌘S。最新 Mac panel 可见性修复后，实际返回设置恢复原标题并保留追问草稿。 | 移动端最终弹窗的配置往返与未保存确认；保存失败时不关闭或丢失编辑；真实 BYOK 验证仍待完成。 |

## 保留的设计方向

原文、译文与修订对话采用连续排版；正文保持可选择，长原文允许展开，阅读列最大 760 pt。用分区文字、对齐和留白表达翻译过程，比重复品牌标题或玻璃卡片更适合这个工具；这是产品设计判断。

阅读页不再显示 AI／接收域名 footer，服务地址及数据处理说明集中在设置的“数据与隐私”分组；该调整减少反复阅读时的附属文字，符合本轮用户要求。

玻璃只用于浮动输入容器及系统导航，正文、历史行、表单内容保持正常表面。本版把文字与发送合并为一个外层玻璃容器，内部按钮使用实心强调色，不叠加第二个玻璃形状；参考图不扩展成附件或语音功能。依据 [liquid-glass.md › Where the material belongs](../.agents/skills/apple-design/references/hig/liquid-glass.md#where-the-material-belongs)：“Don't use Liquid Glass in the content layer.” Reduce Transparency 分支仍需在新版中运行检查。

设置中的协议 Picker、SecureField 和动态校验值得保留。依据 [entering-data.md › Best practices](../.agents/skills/apple-design/references/hig/entering-data.md#best-practices)：“Never prepopulate a password field.” 保留密钥状态提示，不把旧密钥回填输入框。

Mac 将设置嵌入主导航是用户明确选择，已保留 App 菜单与 ⌘, 的熟悉入口。[settings.md › Desktop (macOS)](../.agents/skills/apple-design/references/hig/settings.md#desktop-macos)通常描述独立设置窗口；本轮采用嵌入方案，并把这一平台取舍记录清楚。

## 验证边界与下一次复核

本次文档复核未执行构建、GUI 或辅助技术测试。构建、重新安装启动与界面操作结果由主开发代理提供；文档复核静态查看已明确版本的三平台主界面、Mac 服务窗口、iPhone／iPad 最终系统弹窗和共享历史截图，完整链接见 [重构验证](UI_REDESIGN_VALIDATION.md)。图中可见容器内部的圆形发送及上方文字，iPhone 详情展示四行草稿，最终 sheet／popover 各有单一标题与两轮问答；未测量物理命中区或材质叠加后的对比度，未据此推断完整键盘或辅助技术体验。

前一版外置按钮的真实请求 #2–#7、1／3／5 条上下文与六条消息持久化仍是有效功能证据，见 [重构验证](UI_REDESIGN_VALIDATION.md)。那些截图和较早的系统弹窗截图不作为最终内嵌布局证明。`iphone-composer-accessibility.png` 采集于最新按钮颜色修复前，不作为本版 AX5 或对比度结论。

最终移动端新请求 #8–#13 的 `context_valid=true`、`errors=[]`，以及 iPad 03:57／iPhone 03:59 两条新会话的六条消息均已只读核对；主任务实际点击发送、关闭系统弹窗并在 App 中打开历史。Mac 同 panel 设置返回及两轮按钮／⌘Return 发送使用 Preview 固定回复。两者均不能证明真实远程模型的翻译质量。初始化等待与取消处理的修复已有源码对照与正常流程复验，尚不等同于所有并发调度情况的专项测试。

本轮深色实看发现系统 accent 在提高对比度下变亮后，白色箭头辨识度下降；修正保留系统强调色、前景随明暗外观适配。[最终追问辅助字号图](Screenshots/iphone-composer-accessibility-final.png)与主任务实际操作确认黑箭头清楚、圆形固定 44 pt、多行输入内部滚动。[最终主翻译辅助字号图](Screenshots/iphone-translate-accessibility-final.png)显示 AX5 下操作改为 VStack、原生翻译标签保持单行，截图为禁用状态。旧 `iphone-composer-accessibility.png` 不用于这次颜色验收。两个限定条件实看通过，不等同于全平台 AX5／深色或对比度比值测量通过。

后续实际复核至少记录下列项目及截图／操作结果：

- 验证停止／失败后状态、长原文、历史继续追问，以及移动端设置保存与返回。已有最终移动端发送与关闭、Mac Preview 设置返回和限定字号／外观复验，按其具体范围记录，不扩大为全部交互通过。
- 最小支持宽度、iPad 窄窗、Mac 缩放窗口，以及 AX5：无文本裁切、重叠或无法触达的关键操作。依据 [typography.md › Supporting Dynamic Type](../.agents/skills/apple-design/references/hig/typography.md#supporting-dynamic-type)：“Make sure your app’s layout adapts to all font sizes.”
- 补齐其他平台／控件状态的深色与 Increase Contrast、Reduce Transparency、VoiceOver、完整键盘及 IME。Mac 追问框 Escape 只取消焦点，不关闭服务窗口；已测 ⌘Return 发送不代表全部键盘路径。参考色对和两个限定实图不能代替实测对比度比值。依据 [accessibility.md › Vision](../.agents/skills/apple-design/references/hig/accessibility.md#vision)：“Strive to meet color contrast minimum standards.”

实际验证结果由主开发代理在本报告后追加，注明平台、条件与限制；只有完成这些复核后才能更新新版评级。

## 本轮已读参考

基础：accessibility、layout、typography、color、designing-for-ios、designing-for-macos。组件与流程：buttons、toolbars、lists-and-tables、settings、entering-data、liquid-glass。引用均来自项目内 apple-design 参考文件，未阅读的页面不作为本轮依据。
