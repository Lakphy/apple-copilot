> 历史验证记录。以下结果对应整理前的开发版本，不代表当前修订已复测。当前检查入口见 [验证说明](../VALIDATION.md)。

# 运行与验证记录

## 追问回车发送补充验证（2026-10-12）

共享追问组件原先没有 `onSubmit`，普通 Return 未连接发送。Mac 已接入原生提交动作；iPhone 上实测垂直 `TextField` 即使加上 `onSubmit` 和 `.submitLabel(.send)`，屏幕键盘发送仍会插入换行，因此移动端改用 `UITextView` 原生编辑 delegate。生成中的提交同时在输入组件与会话发送入口保护，停止按钮不再绑定 ⌘Return。

- `ComposerSubmissionTests` 7 项通过：Return 发送、⌥Return 换行、空白输入不发送、生成中保留草稿、⌘Return 只发送一次、生成中 ⌘Return 不停止、已提交的中文输入发送。测试通过实际 AppKit 字段编辑器和键盘事件驱动共享控件。
- 最后一次完整 `swift test` 通过：Core 50 项、UI 14 项，共 64 项；日志为 `build/composer-all-tests.log`。
- macOS arm64 构建、iOS/iPadOS Simulator 主应用及 Translation Provider 扩展构建通过，退出码 0，无 warning／error。日志为 `build/composer-mac-build.log`、`build/composer-ios-build.log`。
- Mac 隔离 Preview 窗口实测普通 Return 后出现追问和回复，输入清空且仍保持焦点。
- iPhone iOS 26.4 Preview 实测候选 `hello`：第一下 Return 确认文字，第二下发送并出现回复。屏幕键盘输入 `a` 并确认后，Send 提交产生追问和回复。原生菜单粘贴 `First line\nSecond line` 保留两行，没有触发提交。这些固定内存回复不涉及远程服务。

本轮未复测 iPad、系统翻译弹窗或真机，也没有证明 Mac 真实中文候选的 Return 确认行为；Mac 中文自动测试覆盖的是 marked text 提交为“你”后再发送。移动端 Shift／Option＋Return 的原生键命令已实现，但 Device Hub 的修饰键转发未获得可靠验证，仍需真实外接键盘验证。此前的最大字号检查属于旧输入控件，本轮原生移动端控件的完整辅助技术覆盖尚未完成。

## 原有验证记录

日期：2026-10-12（Asia/Shanghai）。工具链：Xcode 27.0（27A266a）、Swift 6.4；项目 deployment target 全部为 26.0。

最终代码包含单一玻璃输入容器、初始化／历史行／Mac panel 修复、深色发送前景与 AX5 主翻译动作布局；**iOS/iPadOS Simulator 与 macOS 最后构建均 PASS**，退出码 0，无 warning／error。最新包均已重新启动。最终 iPhone／iPad 系统弹窗的内嵌发送、两轮上下文、系统关闭和六条消息共享历史均已实际复验；Mac 同 panel 设置返回与按钮／⌘Return 使用 Preview 验证。iPhone 追问及主翻译入口在 AX5＋深色＋提高对比度下限定实看通过，见 [界面重构验证](../UI_REDESIGN_VALIDATION.md)。完整辅助技术覆盖尚未完成。

下表的 SDK 检查与测试保留各自已验证范围；其中 Mac 及移动端交互行，以及下方 `mock-requests.jsonl` 的请求和 `BeforeRedesign` 截图，属于重构前的功能基线。重构中的外置按钮版另有 #2–#7 请求及六条消息持久化证据；这些功能数据不作为最终内嵌布局的验收结果。

| 检查 | 结果 | 范围 |
| --- | --- | --- |
| `swift test --filter CopilotCoreTests` | 29 项通过，3 个 suite | 请求格式、解码、错误脱敏、URL 校验、配置快照、持久化、取消、跨进程写入与配置刷新 |
| macOS arm64 Xcode 构建 | PASS | 完整主应用、共享 UI/Core、Mac Services；最终单一外层玻璃输入容器重新构建通过，并已重装启动 |
| iOS Simulator 通用 Xcode 构建 | 通过，退出码 0 | iPhone/iPad 共用主应用，Translation Provider 扩展；两种 Simulator 架构 |
| Simulator 运行包 Xcode 构建 | PASS | Xcode 签名步骤启用；主应用与扩展均嵌入 simulated entitlements；最终单一外层玻璃输入容器重新构建通过，iPhone／iPad 均已重装启动 |
| iOS 真机通用 Xcode 构建 | 通过，退出码 0 | arm64 主应用与扩展；未签名、未安装真机 |
| 六份 plist / entitlements lint | 全部通过 | App Group、共享 Keychain、网络权限、NSServices、ExtensionKit 标识 |
| 扩展包检查 | 通过 | `.app/Extensions/AppleCopilotTranslation.appex`、`XPC!`、正确 EXExtensionPointIdentifier |
| Mac 连续对话 | 实际运行通过 | Debug `--preview` 内存模型；原文→译文→追问→回复；⌘Return 发送 |
| Mac 设置与导航 | 实际运行通过 | ⌘, 设置；已保存 key 对应 SecureField 为空；⌘N 清空；⌘2 历史 |
| Mac 系统 Services | 基线实际运行通过 | 重构前：选中文字后 Services 菜单出现“使用 Apple Copilot 翻译”；真实服务派发打开原生浮动窗口，可追问。当时 Escape 关闭；当前输入框 Escape 改为只取消焦点，不关闭窗口 |
| iPhone / iPad 模拟器启动 | 已恢复，实际运行通过 | iOS 26.4；两台原测试设备均 `Booted`，正常模式主应用已运行 |
| iPhone 系统翻译弹窗 | 实际运行通过 | 系统默认翻译中识别 Apple Copilot；选中文字后打开原生 Translate 弹窗，扩展调用本机 HTTP 测试服务并显示回复 |
| iPhone 弹窗连续追问 | 基线两轮实际运行通过 | 重构前复测请求 13 / 14 / 15 携带 1 / 3 / 5 条消息，聚焦输入后自动展开 sheet；上下文校验通过 |
| iPhone 主应用与共享历史 | 实际运行通过 | 正常模式主应用翻译、两轮追问；主应用历史界面显示扩展创建的会话 |
| iPad 主应用连续对话 | 两轮实际运行通过 | 正常模式翻译及两轮追问；请求 7 / 8 / 9 携带 1 / 3 / 5 条消息，上下文校验通过 |
| iPad 系统翻译弹窗 | 实际运行通过 | 选中文字后打开原生 Translate popover；扩展翻译及两轮追问，请求 10 / 11 / 12 携带 1 / 3 / 5 条消息 |
| iPad 共享历史 | 实际运行通过 | 系统 × 关闭后，主应用历史显示 03:00 创建的弹窗会话及完整六条消息 |
| 扩展关闭交互 | 基线实际运行通过 | 两个平台均使用宿主自带 ×，移除扩展内重复的“完成”按钮；重构前 iPhone 与 iPad 复测均实际关闭成功 |
| 最终 iPad 系统弹窗与共享历史 | 实际运行通过 | `ui-redesign-requests.jsonl` #8／#9／#10：1／3／5 条角色，`context_valid=true`、`errors=[]`；两次内嵌发送，系统 × 关闭，主 App 读取 03:57 新会话的六条消息 |
| 最终 iPhone 系统弹窗与共享历史 | 实际运行通过 | 同一重构日志 #11／#12／#13：1／3／5 条角色，`context_valid=true`、`errors=[]`；两次内嵌发送，系统 × 关闭，主 App 读取 03:59 新会话的六条消息 |
| 最终 Mac 服务窗口 | Preview 实际运行通过 | 设置留在同一 panel；返回标题恢复、追问草稿保留；内嵌按钮与 ⌘Return 成功。固定回复不代表真实 BYOK 或模型质量 |
| Mac 最后构建主工作区与历史 | Preview 实际运行通过 | ⌘Return 发送两行追问，历史打开同一会话，原生选中高亮上的译文／元数据清楚；新图 `mac-history-composer.png`。此前 panel 流程不重复标记为最后纯外观修正后重测 |
| 最新运行修复 | 源码对照与上述复验完成 | 历史选中摘要／元数据改为原生 primary；共享初始化 Task 与选区取消检查；Mac floating panel 保持可见并在设置切换后置前。对比度未测量，调度组合未做专项覆盖 |
| 最后深色发送图标修正 | 构建与 iPhone 限定实看 PASS | AX5＋深色＋提高对比度；黑箭头在亮 accent 底上清楚，固定 44 pt 圆形不随字号扩大，四行输入内部滚动；新图 `iphone-composer-accessibility-final.png`，未测对比度比值 |
| AX5 主翻译动作布局 | 构建与 iPhone 限定实看 PASS | accessibility 字号使用 VStack、标签 fixedSize；语言行与原生翻译按钮竖排，标签单行不互挤；新图 `iphone-translate-accessibility-final.png` 为禁用状态 |
| 本轮设计审查 | 源码与最终截图已对照，验证范围已记录 | 基线 Needs work；见 DESIGN_REVIEW.md。不把旧弹窗或外置按钮版截图当作本版布局证据；VoiceOver、Reduce Transparency、IME 与全平台条件仍有缺口 |

通用 SDK 编译检查使用 `CODE_SIGNING_ALLOWED=NO`。后续 Simulator 运行包使用 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`；这证明本机模拟器的权限与扩展运行路径可用，不能证明真机或发行 provisioning profile。

## 模拟器卡住的原因与恢复

首次启动卡在系统 `CoreLocationMigrator.migrator`，发生于 App 运行前。只读进程采样显示：迁移程序等待 `locationd` 的同步 XPC 回复，`locationd` 等待 `BGSystemTaskScheduler`，该设备内部的 `dasd` 也停在启动阶段的同步调度请求。此前 iPhone 擦除、设备重启和仅该模拟器内的 `locationd` 重启均未解决；后续仅重启指定模拟器内部的 `dasd` 才使迁移完成。该证据定位了本次卡住的等待链，不证明所有同类问题都源于同一原因。

iPhone 恢复后的 `bootstatus` 为 `Finished`、退出码 0；原 iPad 首次恢复在 63 秒完成，后续重新启动在 16 秒完成。两台设备均确认 `Booted` 并启动正常模式主应用。额外创建的任务诊断 iPad Air 也复现迁移等待，恢复后已关闭并保留数据。后续恢复未擦除设备，没有修改其他用户模拟器、宿主机定位服务或系统缓存。

| 设备 | UDID | 已确认状态 |
| --- | --- | --- |
| iPhone 17 Pro | `<IPHONE_SIMULATOR_UDID>` | Booted；正常模式 App 与系统翻译扩展运行 |
| iPad Pro 13-inch (M5) | `<IPAD_SIMULATOR_UDID>` | Booted；正常模式 App、系统翻译扩展与共享历史运行 |

安全复现命令：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/boot-simulator.sh "$COPILOT_SIMULATOR_UDID"
# 仅在匹配本次迁移停滞时显式允许恢复：
./Scripts/boot-simulator.sh "$COPILOT_SIMULATOR_UDID" --recover-dasd
```

脚本要求完整且可用的 UDID，最多等待 180 秒；恢复选项只有在当前状态为迁移阶段、原因包含 `com.apple.locationd.migrator` 且持续至少 15 秒时生效，最多执行两次 `simctl spawn <UDID> launchctl kickstart -k user/$(id -u)/com.apple.dasd`，两次间隔至少 30 秒。不会擦除设备、禁用系统任务或重启宿主机服务。成功须同时满足 `bootstatus` 退出码 0、设备 `Booted`，以及 `Finished` 或已启动设备的精确完成标记。脚本已在上述 Booted iPhone 上无恢复参数实际运行，退出码 0；该次未触发 boot 或服务重启。两个脚本的 `zsh -n` 均通过。

## 模拟器签名与实时测试

之前将无签名构建产物事后 ad hoc 签名，`codesign` 能读取外部签名的 entitlement，但 Mach-O 缺少 `__TEXT/__entitlements`。安装日志成功并不代表能运行：iPhone 启动报告 `NSPOSIXErrorDomain` 163，iPad 启动请求长时间等待。改为让 Xcode 在构建时启用签名步骤，生成 `*-Simulated.xcent` 并链接 simulated entitlements 后，主应用、扩展、共享容器及默认翻译发现均可实际运行。

```sh
./Scripts/build-simulator.sh
COPILOT_SIMULATOR_UDID='从 simctl list devices available 复制完整 UDID'
xcrun simctl install "$COPILOT_SIMULATOR_UDID" \
  'build/SimulatorRuntime/Build/Products/Debug-iphonesimulator/Apple Copilot.app'
xcrun simctl launch "$COPILOT_SIMULATOR_UDID" com.lakphy.applecopilot
```

脚本复现此次成功的 Xcode 构建参数，并检查主应用及扩展 Mach-O 中存在 `__entitlements`。脚本已实际执行成功，退出码 0；它不会安装 App 或操作模拟器。签名中的 App Group、共享 Keychain 与 translation-app entitlement 已检查；本地模拟器签名不提供真机或发行授权。关闭控件调整后的模拟器与 Mac 构建均通过，无诊断。

移动端交互使用正常 App 进程和 `Scripts/mock_model_server.py` 的回环 HTTP 服务，没有使用 `--preview`：

```sh
python3 Scripts/mock_model_server.py --port 56343 --log build/mock-requests.jsonl
```

设置为 OpenAI Chat Completions、`http://localhost:56343/v1`、模型 `copilot-test-model`、测试 key `local-simulator-key`，开启“允许本机 HTTP 服务”。两个平台的主应用和系统弹窗均经真实 `URLSession` 请求得到固定回复；日志记录脱敏的协议、消息角色和上下文校验结果，并仅对预先公开的测试句子保留文本。每组请求均为 1 / 3 / 5 条消息，连续两轮追问的 `context_valid` 均为 true。iPad 主应用对应请求 7 / 8 / 9，系统弹窗对应 10 / 11 / 12，原文均为 `Good design makes complex things simple.`，追问依次为 `What does complex mean?`、`Make it more natural.`。关闭弹窗后，主应用历史界面显示该会话完整六条消息。这验证了选择文本、进程间配置/历史和连续对话请求路径；真实模型翻译质量、远程服务及其网络异常未测试。

| 截图 | 验证内容 |
| --- | --- |
| [iphone-system-chat.png](../Screenshots/BeforeRedesign/iphone-system-chat.png) | 重构前：iPhone 原生系统翻译弹窗及连续追问 |
| [iphone-shared-history.png](../Screenshots/BeforeRedesign/iphone-shared-history.png) | 重构前：iPhone 主应用读取扩展会话历史 |
| [ipad-app-chat.png](../Screenshots/BeforeRedesign/ipad-app-chat.png) | 重构前：iPad 正常模式主应用翻译及两轮追问 |
| [ipad-system-chat.png](../Screenshots/BeforeRedesign/ipad-system-chat.png) | 重构前：iPad 原生系统 popover 中的翻译及两轮追问 |
| [ipad-shared-history.png](../Screenshots/BeforeRedesign/ipad-shared-history.png) | 重构前：iPad 主应用读取弹窗创建的完整会话 |

重构前的 iOS 26.4 系统宿主对自定义“完成”按钮调用 `finish(translation: nil)` 未出现关闭响应；因此扩展移除该重复按钮，使用系统自带的 ×，iPhone 与 iPad 当时均实际关闭成功。最终内嵌布局中，两台设备的系统 × 关闭与共享历史已再次实际验证。当前 Mac 自有窗口使用原生关闭按钮；追问输入框的 Escape 只取消焦点，空输入可折叠，不关闭窗口。Apple 的 [`finish(translation:)` 文档](https://developer.apple.com/documentation/translationuiprovider/translationuiprovidercontext/finish%28translation%3A%29) 描述调用后框架关闭 sheet，`nil` 时不替换原文；上述历史观察与该预期不同。原文替换路径仍需单独验证。

重构前 iPhone 最后一次复测使用与 iPad 相同的公开原文与两个追问；系统会话请求为 13 / 14 / 15，关闭后历史保留六条交替的 user / assistant 消息。该轮共 15 次实际 HTTP 请求的上下文检查全部通过；脱敏记录和共享历史核对结果保存在 [SimulatorEvidence.json](../SimulatorEvidence.json)。这组请求独立于重构验证日志，编号不合并计算。

## 模拟器文本输入复现

Xcode 27 的 `devicectl device pasteboard copy` 从标准输入读取 UTF-8 文本，默认写入多种文本 UTI。命令选择测试设备的剪贴板，输入仅使用公开测试文本：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
COPILOT_SIMULATOR_UDID='<IPAD_SIMULATOR_UDID>'
printf '%s' 'Good design makes complex things simple.' | \
  xcrun devicectl device pasteboard copy --device "$COPILOT_SIMULATOR_UDID"
```

随后在目标 App 的文本框中使用界面“粘贴”，选中该句并点“翻译”；在扩展输入框分别发送上述两个公开追问。本次 iPad 中 `simctl pbcopy` 未使 UIKit 输入框收到文本，Xcode 27 的上述命令可正常粘贴。命令帮助已核对；该差异是环境观察，尚不能归因于具体 pasteboard provider 实现。验证期间在 Device Hub“Edit → Use Shared Clipboard”中调整了测试设备的同步选项；结束后均通过相同菜单恢复原来的开关状态。

iPhone 追问和主翻译入口的 AX5＋深色＋Increase Contrast 限定运行与新图已记录；VoiceOver、Reduce Transparency、中文输入法候选确认，以及全平台字号／外观／控件状态组合尚未完成。

## 发布或真机前需要完成

- 配置开发者 Team、拥有的 Bundle ID、App Group 与共享 Keychain capability。
- 在设备上选择 Apple Copilot 为默认翻译 App，验证系统调用、展开、取消、追问、替换原文及历史共享。
- 使用真实 BYOK 服务分别验证三协议连接、API key 权限、翻译质量和网络异常。测试未持有用户真实密钥；Mac 交互使用内存模型，移动端使用回环 HTTP 测试服务，没有远程模型调用。
- 完成 VoiceOver、完整键盘、Reduce Transparency、IME 和其他平台／控件的字号、外观、提高对比度检查。已测 iPhone 两个界面的条件不能代表全部覆盖；实际对比度比值未测量。
- 完成发行签名及 App Store 元数据。富文本与三协议流式输出已接入，新的验证范围见 [富文本与流式渲染](../RICH_TEXT_RENDERING.md)。
