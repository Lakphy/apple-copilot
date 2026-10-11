# Apple Copilot

原生 SwiftUI 翻译应用，最低支持 **iOS 26、iPadOS 26、macOS 26**。采用 MV + Observation，共享 Swift Package 与平台入口分离。

## 已实现

- BYOK：OpenAI Chat Completions、OpenAI Responses、Anthropic Messages；可配置协议、Base URL、API key、模型。
- 自定义翻译系统提示词与目标语言，支持 `{targetLanguage}` 占位符。
- 翻译后连续追问；完整上下文、请求取消、失败重试和输入恢复。
- 本地可搜索历史；单会话原子 JSON 文件与跨进程锁；Keychain 保存密钥。
- iOS/iPadOS Translation Provider Extension，在系统翻译 sheet 中显示译文与追问，并在系统允许时替换原文。
- macOS 系统 Services 接收选中文字，打开原生可缩放对话窗口。**macOS 的公开接口不提供第三方系统 Translate sheet**。
- 系统标签页、侧栏与 Form；三个平台的设置均嵌入主页面，保存位于工具栏。Mac 的 ⌘, 打开主窗口中的设置分区。
- 原文、译文与追问连续排版；系统翻译内容不复制宿主标题栏，不在阅读页加入 AI 或数据去向 footer；数据说明集中在设置中。
- Liquid Glass 用于导航与浮动操作。全平台共用一个玻璃追问容器：空闲且无文字时折叠为胶囊，默认高为移动端 56 pt、Mac 48 pt；聚焦、非空或生成中时展开为圆角 24 pt 的矩形，文字在顶部，容器随文字自然增高。发送位于容器内部右下角，使用实心系统强调色圆形，图标前景随明暗外观适配（浅色白、深色黑），直径移动端 44 pt、Mac 36 pt；生成时同一按钮用于停止。浅色／深色跟随系统。

## 运行工程

需要 Xcode 26 或更新版本（本工程用 Xcode 27 / Swift 6.4 验证），Swift 6.2+。打开 [AppleCopilot.xcodeproj](AppleCopilot.xcodeproj)，选择 `AppleCopilot-iOS` 或 `AppleCopilot-macOS` scheme。iOS scheme 同时支持 iPhone 与 iPad，并自动嵌入翻译扩展。

工程配置来自 `project.yml`；修改后使用 `xcodegen generate` 更新项目。生成后的项目也已保留，无需安装 XcodeGen 即可打开。

### 仓库目录

| 目录 / 文件 | 内容 |
| --- | --- |
| `Sources/` | 共享核心、SwiftUI 页面、主应用及平台集成入口 |
| `Tests/` | 核心模块的请求、存储与仓库测试 |
| `Configuration/` | 平台 Info.plist 与 entitlements |
| `Resources/` | 原生 AppIcon.icon 和原始图标素材 |
| `Scripts/` | 构建检查、模拟器启动与本地模型测试服务 |
| `Docs/` | 架构、设计审查、验证记录及截图 |
| `project.yml` | XcodeGen 工程配置来源 |
| `AppleCopilot.xcodeproj/` | 可直接打开的 Xcode 工程与共享 schemes |

构建缓存、运行日志、个人 Xcode 状态及签名文件不进入版本库。项目内的 `.agents/`、`.claude/` 以及其他项目配置文件随仓库提交；`.agents/skills/` 保存已安装的技能，`.claude/skills/` 保留指向这些技能的相对符号链接，`skills-lock.json` 记录来源与版本信息。应用构建不依赖这些技能。

### 签名与共享权限

完整真机版本需要支持 Default Translation App 能力的开发者团队。2026-10-12 使用本机 Harry Li 的免费 Personal Team 构建时，Xcode 明确拒绝为该能力创建开发 provisioning profile；已有 Apple Development 证书并不代表团队支持此权限。不要通过删除翻译 entitlement 绕过签名，否则无法验证系统划词翻译。

1. 在主应用、翻译扩展的 Signing & Capabilities 中选择同一开发者 Team。
2. 使用你拥有的 Bundle ID；iOS 扩展 ID 应以主应用 ID 为前缀。
3. 为两者注册并启用相同 App Group；更新 `APP_GROUP_IDENTIFIER`（当前 `group.com.lakphy.applecopilot`）。
4. 两者保留同一个 Keychain access group：`$(AppIdentifierPrefix)$(KEYCHAIN_SHARED_SUFFIX)`。
5. iOS 主应用保留 Translation App entitlement：`com.apple.developer.translation-app`。扩展使用 ExtensionKit 产品类型，不使用普通 Action/Share Extension。

Mac 应用使用 App Sandbox 与 Outgoing Connections，服务运行在主进程内。App Group 不用于跨设备同步。Apple Copilot 不读取全局剪贴板、不监听所有选区；只处理人主动提交的文本。

### USB 安装到自己的 iPhone / iPad

1. 连接并解锁设备，完成“信任此电脑”配对；设备需运行 iOS / iPadOS 26 或更新版本，并开启开发者模式。
2. 打开 `AppleCopilot.xcodeproj`，在主应用 `AppleCopilot-iOS` 和扩展 `AppleCopilotTranslation` 的 Signing & Capabilities 中，选择同一个支持默认翻译权限的 Team，并启用 Automatically manage signing。若修改团队，同步更新 `project.yml` 的两处 `DEVELOPMENT_TEAM`，避免重新生成工程后丢失配置。
3. 在 Xcode 顶部选择 `AppleCopilot-iOS` scheme，运行设备选择连接的真机，按 ⌘R 构建并安装。iPhone 和 iPad 使用同一个 scheme；换设备后再次运行即可。
4. 在 App 的设置中填写自己的 BYOK 配置，然后选择系统默认翻译 App，验证翻译、连续追问和历史。模拟器测试用的 `localhost` 地址在真机上指向设备自身，不能直接用于访问 Mac 上的测试服务。

无需先 Archive 或导出 IPA 即可通过 USB 安装。完整签名成功后的命令行构建产物位置为 `build/DeviceDevelopment/Build/Products/Debug-iphoneos/Apple Copilot.app`；该目录存在不代表产物已成功签名或可安装。

### 开始翻译

启动后在“设置”填写真实模型 ID、服务器地址和 API key，保存后翻译。API key 留空可保留同一服务已保存的密钥；改变协议或端点时需要提供该服务的密钥。历史追问使用原始配置快照，恢复原服务后可以继续。

- iOS/iPadOS：系统“设置 → App → 默认 App → 翻译”选择 Apple Copilot，然后在支持的 App 中选中文字并点“翻译”。安装应用不会自动更改默认 App。
- Mac：选中文字，打开 App 的“服务 → 使用 Apple Copilot 翻译”；若未显示，可在系统“键盘 → 键盘快捷键 → 服务”启用。首次测试使用完整 `.app` bundle，而非 `swift run` 的裸可执行文件。

Mac 支持 ⌘N 新翻译、⌘Return 发送、⌘. 停止、⌘1 翻译工作区、⌘2 历史、⌘, 设置、⌘S 保存设置。Services 弹窗通过原生关闭按钮关闭。追问输入框中的 Escape 只取消焦点；空输入可随之折叠，不关闭服务弹窗。弹窗内编辑设置时 Escape 用于返回翻译，并在未保存时确认处理方式。

## 验证

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --filter CopilotCoreTests
xcodebuild -project AppleCopilot.xcodeproj -scheme AppleCopilot-macOS \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/macOS \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AppleCopilot.xcodeproj -scheme AppleCopilot-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOS \
  CODE_SIGNING_ALLOWED=NO build
```

上述无签名构建用于编译验证。真机共享容器、共享 Keychain 和系统默认翻译发现仍需要正确签名及 provisioning profile；模拟器验证不能代替真机验证。

### 在 iPhone / iPad 模拟器实际运行

模拟器运行使用 Xcode 构建时生成并嵌入的 simulated entitlements。不要将 `CODE_SIGNING_ALLOWED=NO` 的产物事后手动签名作为运行包；这种包在本次验证中安装成功，但启动失败。脚本保留 Xcode 签名步骤，并检查主应用与扩展的 Mach-O 均含 `__entitlements`。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./Scripts/build-simulator.sh
xcrun simctl list devices available
COPILOT_SIMULATOR_UDID='从列表复制完整 UDID'
./Scripts/boot-simulator.sh "$COPILOT_SIMULATOR_UDID"
xcrun simctl install "$COPILOT_SIMULATOR_UDID" \
  'build/SimulatorRuntime/Build/Products/Debug-iphonesimulator/Apple Copilot.app'
xcrun simctl launch "$COPILOT_SIMULATOR_UDID" com.lakphy.applecopilot
```

启动脚本只操作指定 UDID，最多等待 180 秒，并同时检查 `bootstatus` 的完成标记与设备 `Booted` 状态。若 iOS 26.4 首次启动持续卡在 `com.apple.locationd.migrator`，可显式运行 `./Scripts/boot-simulator.sh "$COPILOT_SIMULATOR_UDID" --recover-dasd`：仅在该迁移阶段停滞至少 15 秒时，最多重启两次该模拟器内部的 `dasd`。脚本不会擦除设备或修改宿主机服务、缓存。本次 iPhone 与 iPad 已通过这条恢复路径实际运行。

要复现真实进程间的翻译与追问测试，可启动回环 HTTP 测试服务：

```sh
python3 Scripts/mock_model_server.py --port 56343 --log build/mock-requests.jsonl
```

正常启动 App，在设置中选择 OpenAI Chat Completions，Base URL 填 `http://localhost:56343/v1`，模型填 `copilot-test-model`，API key 填测试字符串 `local-simulator-key`，开启“允许本机 HTTP 服务”。随后保存、选择系统默认翻译 App，再选中文字并点“翻译”。服务只返回固定测试文本并记录脱敏的消息角色，便于检查连续追问是否携带上下文；它不调用远程模型。重构前已实际验证 iPhone 与 iPad 的主应用翻译、系统划词翻译弹窗、两轮连续追问、共享历史和系统 × 关闭。重构中的前一版外置按钮也完成了真实请求和六条消息持久化验证；这些功能证据不代表最终内嵌布局已通过视觉检查。

最终 iOS/iPadOS Simulator 与 macOS 构建均 **PASS**，退出码 0，无 warning／error；最新包均已启动。iPhone／iPad 系统弹窗已完成翻译、内嵌发送两轮追问、系统 × 关闭及共享历史复验，真实本机 HTTP 请求的 1／3／5 条上下文校验通过，每条新会话保留六条消息。Mac 已验证服务窗口同容器设置返回、草稿保留及两种发送入口；最新主工作区也通过 ⌘Return 发送两行追问并打开对应历史。Mac 使用 Preview 固定回复，这些结果不证明真实 BYOK 或翻译质量。

iPhone 追问与主翻译入口在 AX5＋深色＋提高对比度条件下已限定实看：发送图标清楚，44 pt 圆形不随字号扩大，四行输入内部滚动；主翻译动作竖排、标签单行。VoiceOver、降低透明度、中文输入法候选确认和全平台条件覆盖仍未完成。版本边界、截图和具体限制见 [界面重构验证](Docs/UI_REDESIGN_VALIDATION.md)。

Xcode 27 的设备剪贴板命令可将公开测试文本送入指定模拟器，再在界面中粘贴、全选并点击“翻译”：

```sh
printf '%s' 'Good design makes complex things simple.' | \
  xcrun devicectl device pasteboard copy --device "$COPILOT_SIMULATOR_UDID"
```

本次 iPad 上 `simctl pbcopy` 未将文本送达 UIKit 输入框，而上述命令可用；这只是本次环境的观察。连续追问使用 `What does complex mean?` 和 `Make it more natural.`。截图、消息角色与关闭行为详见验证记录。

Debug 主应用可用 `--preview` 启动固定的内存演示数据和本地假模型，便于布局/连续对话检查；它不会读取真实 Keychain、写生产历史或调用远程 API。正式启动不带该参数。Xcode 的 `#Preview` 覆盖空白、已翻译、等待和错误状态。

## 文档

- [架构与平台边界](Docs/ARCHITECTURE.md)
- [系统集成、权限与 Apple 来源](Docs/PlatformIntegration.md)
- [Apple HIG 设计审查](Docs/DESIGN_REVIEW.md)
- [界面重构计划](Docs/UI_REDESIGN_PLAN.md)
- [界面重构验证与版本边界](Docs/UI_REDESIGN_VALIDATION.md)
- [运行验证与剩余验证范围](Docs/VALIDATION.md)

协议依据：[OpenAI Chat](https://developers.openai.com/api/reference/resources/chat)、[OpenAI Responses](https://developers.openai.com/api/reference/resources/responses/methods/create)、[Anthropic Messages](https://docs.claude.com/en/api/messages)。目前为文本非流式 MVP，收到完整回复后显示内容；不包含云同步、图片输入或多供应商账户管理。
