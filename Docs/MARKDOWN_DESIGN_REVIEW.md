> 开发研究记录：结果对应文中标明的版本与日期，当前整理验证见 [验证说明](VALIDATION.md)。

# Design review: AI Markdown 阅读体验

## Summary

2026-10-12，按 `apple-design` 审查并修正共享的 SwiftUI + 本地 WebKit 渲染器，覆盖 iOS、iPadOS、macOS。修正后在本报告验证范围内评级 **Excellent**：未发现遗留的 Critical 或 High 问题；完整 VoiceOver 人工操作及任意模型生成图表的语义质量不在这个结论内。

设计主张是安静、可操作的 AI 阅读界面：系统字体承载译文，代码与图表提供直接复制及源码展开；视觉重点属于输出内容。GFM 是内容语法，界面外观遵循 Apple 平台的文字、颜色和交互习惯。

依据为技能目录的 12 份参考：accessibility、layout、typography、color、designing-for-ios、designing-for-macos、buttons、scroll-views、dark-mode、focus-and-selection、generative-ai、feedback。审查包含源代码、WebKit 实际计算样式、原生 Mac 辅助功能树和交互、iPhone/iPad 模拟器画面；对比度从实际 sRGB 数值计算，未从截图估计。

## 已完成的修正

以下严重级别描述修正前的问题，均已解决。

| 级别 | 问题与结果 | 依据 |
| --- | --- | --- |
| Critical | 网页正文固定为常规字重，未接收 SwiftUI 的粗体文本偏好。现在正文及代码用 600 字重，标题 700；Mermaid 标签和公式也响应设置。 | `typography.md › Using custom fonts`: “Implement accessibility features for custom fonts.” |
| High | 界面颜色来自固定 GitHub 配色，原生辅助外观没有明确传入文档。现在从 AppKit/UIKit 动态语义颜色解析正文、页面、代码表面、链接、分隔线和焦点；显式传递增强对比度，必要时保持色相并提高文字对比度。 | `color.md › System colors`: “Avoid hard-coding system color values in your app.” |
| High | 标题仅按正文比例放大，53pt 正文时一级标题达 87.45pt。现在一级至三级标题分别用 `.title`、`.title2`、`.title3` 缩放，AX5 布局用 58/56/55pt 验证；任务状态标记也随文字放大。 | `typography.md › Supporting Dynamic Type`: “Make sure your app’s layout adapts to all font sizes.” |
| Medium | iPhone 复制按钮实测为 43×44pt，缺少按下状态。现在移动端至少 44×44pt、Mac 至少 28×28pt；保留悬停反馈，补齐按下反馈和可见键盘焦点。长语言名称可换行，按钮可移至下一行。 | `accessibility.md › Mobility`: “Offer sufficiently sized controls.”；`buttons.md › Best practices`: “Always include a press state for a custom button.” |
| Medium | 复制结果仅改变按钮标签，代码、图表和公式的操作描述也未区分。现在有独立 `role=status`、`aria-live=polite` 状态区及准确的操作标签；结果复位后保留原标签，流式稳定块保留焦点。 | `feedback.md › Best practices`: “Make sure all feedback is accessible.” |
| Medium | 显示公式可横向溢出，但没有明确的键盘滚动入口。现在公式与代码、表格、图表一样可聚焦，并提供用途标签。Mermaid SVG 按组暴露文本节点，保留作者提供的标题、描述和可展开源码。 | `accessibility.md › Speech`: “use the keyboard alone” |
| Medium | 原生辅助功能树把 Mermaid 装饰路径和边框暴露成大量无名称图片。现在未命名的装饰形状从辅助树隐藏，图表节点文字继续可访问。 | `accessibility.md › Vision`：读屏应能描述并浏览界面和内容。 |
| Medium | Reduce Motion 原先只禁用平滑滚动。现在显式环境偏好及网页媒体偏好均禁用内容动画、过渡和平滑滚动，覆盖 Mermaid 可生成的动画内容。 | `accessibility.md › Cognitive`: “Be cautious with fast-moving and blinking animations.” |

## Craft notes

**Low · 已修正。** 移除一级、二级标题下的重复分隔线，保留 Markdown 原文的水平分隔线、表格网格和代码工具行。字号、字重与间距足以表达标题层次，这是针对阅读界面的设计判断，并非 HIG 要求所有标题都去掉边线。

复制采用简短文字和中性的系统前景色；链接有下划线，提示块保留 NOTE/TIP 等文字，任务状态有勾选形状，信息不依赖颜色区分。Mermaid 用同一套内容色和中性节点表面，避免默认紫色图表与原生阅读界面割裂；复杂图表的源码渐进展开。

### 文字与布局

| 角色 | iOS / iPadOS 默认 | macOS 默认 |
| --- | --- | --- |
| 正文 | 系统字体 17pt | 系统字体 13pt |
| 一级 / 二级 / 三级标题 | 28 / 22 / 20pt，分别按文字样式缩放 | 22 / 17 / 15pt |
| 代码 | 系统等宽字体，正文的 0.88 倍 | 同左 |
| 代码语言与复制标签 | 正文的 0.8 倍 | 正文的 0.8 倍，最低 10pt |

窄宽度和常规宽度均为同一阅读列。正文和语言名称自动换行；代码、表格、宽图表及公式保留内容完整性，在各自容器横向滚动。53pt 正文配合 320pt 视口已验证整页不产生横向溢出。内容层无玻璃或模糊，没有额外的登场动画。

### 颜色与实测对比度

运行时使用语义角色 `surface`、`fg`、`muted`、`panel`、`line`、`accent`，焦点另取系统焦点颜色；下面是本机 macOS 当前样本，不是写入产品的固定系统色值。正文、链接、次级文字在页面和代码表面都检查 4.5:1；增强对比度使用更严格的 7:1。普通分隔线是装饰性结构，增强对比度时提高至 3:1；焦点也检查 3:1。

| 角色 / 前景色 | 浅色背景 / 对比度 | 深色背景 / 对比度 |
| --- | --- | --- |
| 正文：`#000000` / `#ffffff` | `#ffffff` / 21.00:1 | `#1e1e1e` / 16.67:1 |
| 链接：`#0068da` / `#419cff` | `#ffffff` / 5.26:1 | `#1e1e1e` / 5.89:1 |
| 次级文字：`#717171` / `#9a9a9a` | `#f6f6f6` / 4.52:1 | `#282828` / 5.24:1 |
| 增强对比度次级文字：`#545454` / `#b3b3b3` | `#f6f6f6` / 7.01:1 | `#282828` / 7.03:1 |

全组被测文字的最低值：CSS 备用配色浅色 **4.739:1**、深色 **6.113:1**；原生 Mac 调色板浅色 **4.516:1**、深色 **5.239:1**。增强对比度四组最低值分别为 **7.033 / 7.048 / 7.007 / 7.032:1**。颜色包含正文、引用、链接、操作按钮、代码语言、代码注释/高亮和提示标题；这些数字不代表任意第三方图表、用户图片或作者 HTML 的所有像素。

`accessibility.md › Vision`: “Strive to meet color contrast minimum standards.”

## What works

- 继续使用同一共享组件覆盖工作区、历史及翻译扩展；iPhone 和 Mac 的文字及控制尺寸分别适配。
- GFM 保留真实的标题、列表、表格、任务状态和脚注语义；公式保留 MathML，图表保留标题/描述与可读源码。
- 外层对话只负责纵向滚动，宽内容负责横向滚动。Mac 指针悬停 Markdown 的滚轮修复及触控板惯性回归仍通过。
- 流式追加保留稳定段落、选区、代码横向位置及焦点；相同外观不再重复修改整页样式。整个回复不设置 live region，避免逐字播报。
- 复制反馈贴近操作，失败可重试；未闭合或无效图表继续显示源码。

`scroll-views.md › Best practices`: “Support default scrolling gestures and keyboard shortcuts.”

`focus-and-selection.md › Best practices`: “Avoid changing focus without people’s interaction.”

## Platform notes 与验证范围

2026-10-12 最终验证：

- **13 组 WebKit 浏览器测试通过**：保留原来的 GFM/图表/公式/流式/安全边界用例，新增 320pt + AX5 重排、移动端和 Mac 点击尺寸、8 组明暗/增强对比度调色板、键盘复制与焦点保持、粗体及减少动态效果。Mac 原生调色板样本由原生测试导出；独立运行浏览器测试时若没有该文件，只检查 CSS 备用配色。
- **任务列表对齐**：取消复选框的浏览器默认边距，按第一行行高居中定位，不再依赖拉丁字形基线。13/17/53pt、明暗外观、多行/空行/嵌套列表的实际矩形中心偏差均不超过 0.75pt；正文缩进一致，普通列表标记和复选框读屏状态保留。修正仅涉及共享 CSS，无新增滚动或几何计算回调。快照为 `build/MarkdownValidation/task-list-alignment.png`，日志为 `build/markdown-task-alignment-*.log`。
- **7 个原生 Mac UI 测试通过**：含 4 个滚轮回归、原生 WebKit 文件/桥接/图表/颜色/辅助设置用例及 2 个原有输入框用例。
- **iOS / iPadOS 主应用及翻译扩展、macOS 构建通过**，相关日志没有 warning/error。
- **原生 Mac 交互**：Markdown 区域 Page Down 使外层滚动位置从 0 到约 0.270；系统普通键盘导航关闭时，Option-Shift-Tab 可定位复制图表按钮，空格复制成功，辅助功能树出现结果状态。未改变用户的系统键盘导航偏好。
- **原生 Mac 图表辅助树**：最终样例保留“接收文本 / Markdown / 逐步显示”三个文字节点和源码展开入口，无名称装饰图片已消除。
- **原生 iPhone 模拟器**：系统 AX5 最大辅助字号 + 深色 + 增强对比度组合；验证上下滚动、正文换行及尾部脚注可完整进入可见区域。测试后恢复原有字号、外观及对比度设置。iPad 复用共享渲染器并安装最终构建。
- 快照、计算样式数据和日志在忽略目录 `build/MarkdownValidation` 与 `build/markdown-design-*.log`。`mac-native-palettes.json` 是本机动态颜色样本，`design-contrast.json` 是对应的实际样式和计算结果。

完整 VoiceOver 连续阅读、转子、Switch Control、所有 Dynamic Type 档位及不同 Mac 用户强调色还需要在相应设备做人工检查。图表的语义描述质量取决于模型提供的内容；渲染器保留作者描述和节点文字，但未自动推断所有图形关系。当前结果属于明确范围的实现与设计审查，不是 Apple 或 WCAG 的认证。

复现顺序：

```sh
swift test --filter CopilotUITests
cd Scripts/MarkdownRenderer
npm run build
npm test
```

修改渲染源后先重建本地资源，再执行原生测试。详见 [富文本与流式渲染](RICH_TEXT_RENDERING.md)。
