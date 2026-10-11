# 系统划词翻译接入

Apple Copilot 的主应用最低版本为 iOS 26、iPadOS 26 和 macOS 26，以便使用系统 Liquid Glass。翻译、BYOK 配置、历史和连续对话共用 `CopilotCore` 与 `CopilotUI`。

## iOS 与 iPadOS

系统从 iOS / iPadOS 18.4 起支持第三方默认翻译应用。Apple Copilot 使用 `TranslationUIProvider` 的真实扩展接口，系统负责弹窗与宿主文本选择，应用提供弹窗内的 SwiftUI 内容。用户仍须在系统“设置 → App → 默认 App → 翻译”选择 Apple Copilot；应用不能自行改变默认设置。

扩展入口为 `AppleCopilotTranslationExtension`，场景为 `TranslationUIProviderSelectedTextScene`。`context.inputText` 是选中文本；`context.allowsReplacement` 决定是否提供替换操作。翻译完成后保持弹窗，方便继续追问；关闭使用系统宿主自带的 ×，只有用户明确选择“替换原文”时才调用 `context.finish(translation:)` 返回译文。追问输入需要更大空间时调用 `context.expandSheet()`。

重构前的 iOS 26.4 模拟器实测会忽略 `finish(translation: nil)` 的关闭请求，因此扩展不提供重复的“完成”按钮。新版移除内层标题栏，关闭继续由系统宿主负责。最终内嵌按钮版已在 iPhone／iPad 正常进程复验自动翻译、两轮追问和系统 × 关闭，关闭后主 App 均读取新会话的六条消息。不会通过返回空串或译文模拟关闭，避免意外替换所选原文。原文替换路径尚需单独验证，版本与截图见 [界面重构验证](UI_REDESIGN_VALIDATION.md)。

扩展中的设置通过译文旁的操作菜单进入，在当前系统容器内切换，不叠加第二张 sheet。设置提供“返回翻译”和工具栏保存；有未保存修改时，允许保存并返回、放弃修改或继续编辑。

主应用的签名 entitlements：

```xml
<key>com.apple.developer.translation-app</key>
<true/>
```

需要访问用户指定大模型 API 时，在主应用与扩展 `Info.plist` 中都声明：

```xml
<key>com.apple.developer.translation-ui-provider.network-access</key>
<true/>
```

扩展 `Info.plist` 使用 Xcode 的 Translation Provider Extension 模板格式：

```xml
<key>EXAppExtensionAttributes</key>
<dict>
    <key>EXExtensionPointIdentifier</key>
    <string>com.apple.public.translation-ui-provider</string>
</dict>
```

此 ExtensionKit 扩展不配置 `NSExtensionPrincipalClass` 或 `NSExtensionMainStoryboard`。应用和扩展需要相同 App Group，以共享设置、历史和访问授权。API 密钥通过 Keychain Access Group 共享，不能写入 UserDefaults、历史、日志或 Info.plist。

本机 Xcode 27 SDK 中的方法签名为 `finish(translation:)`。Apple 介绍文章的旧示例仍使用 `finish(replacingWithTranslation:)`；请以编译器接口及当前符号文档为准。

真实设备验证需要开发者 Team 签名、App Group 与 Keychain Group 的有效 provisioning，并在系统设置中选择默认翻译应用。模拟器构建成功不能替代默认服务的真机验证。

## macOS

本机 macOS 27 SDK 没有 `TranslationUIProvider.framework`；iOS SDK 中也明确把此 API 标记为 macOS unavailable。macOS 不能用公开接口把 BYOK 回复注入苹果自带“翻译”弹窗。

macOS 版本通过公开 `NSServices` 注册“使用 Apple Copilot 翻译”，从其他应用的“服务”菜单或支持服务的文本右键菜单接收选中文本，以原生可调整尺寸 `NSPanel` 显示翻译和连续对话。菜单能否出现取决于源应用的 Services 支持。服务返回后大模型请求异步执行，因此此入口只读取选择；复制译文由用户操作完成。

服务窗口使用原生关闭按钮。追问输入框中的 Escape 只取消输入焦点，空输入可回到折叠胶囊，不关闭服务窗口。设置在当前窗口切换，返回时确认未保存编辑。窗口保持为 floating panel 且不随失去激活隐藏；设置切换完成后恢复前台，实际复验返回时原 panel 标题及追问草稿保留。两轮追问的按钮与 ⌘Return 测试使用 Preview 固定回复，不代表真实 BYOK 验证。

macOS 主应用挂载：

```swift
@NSApplicationDelegateAdaptor(AppleCopilotApplicationDelegate.self)
private var applicationDelegate
```

将主应用的 `CopilotEnvironment` 赋给 `applicationDelegate.environment`，使 Mac 主窗口与同一进程内的翻译窗口共享设置和本地历史。iOS 主应用与同一设备上的扩展通过 App Group 读取本地对话。不同设备和平台之间没有云同步。

macOS 应用 `Info.plist` 服务声明：

```xml
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>
        <dict><key>default</key><string>使用 Apple Copilot 翻译</string></dict>
        <key>NSMessage</key>
        <string>translateSelection</string>
        <key>NSPortName</key>
        <string>Apple Copilot</string>
        <key>NSSendTypes</key>
        <array><string>public.utf8-plain-text</string></array>
        <key>NSRequiredContext</key>
        <dict/>
    </dict>
</array>
```

服务提供者在 `applicationDidFinishLaunching` 设置 `NSApp.servicesProvider`。建议将应用安装到 `/Applications` 后验证系统服务发现，在系统“键盘 → 键盘快捷键 → 服务”开启服务或配置快捷键。沙盒 macOS 应用还需要 `com.apple.security.network.client = true` 访问 BYOK 端点。

## 依据

- [Apple：准备默认翻译应用](https://developer.apple.com/documentation/translationuiprovider/preparing-your-app-to-be-the-default-translation-app)
- [Apple：Translation entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.translation-app)
- [Apple：TranslationUIProviderContext](https://developer.apple.com/documentation/translationuiprovider/translationuiprovidercontext)
- [Apple：finish(translation:)](https://developer.apple.com/documentation/translationuiprovider/translationuiprovidercontext/finish(translation:))
- [Apple：NSServices](https://developer.apple.com/documentation/bundleresources/information-property-list/nsservices)
- [Apple：NSApplication.servicesProvider](https://developer.apple.com/documentation/appkit/nsapplication/servicesprovider)
- [Apple：Providing a Service](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html)
- 本机 Xcode 模板：`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Xcode/Templates/Project Templates/iOS/Application Extension/Translation Provider Extension.xctemplate/`
- 本机 Swift 接口：`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/TranslationUIProvider.framework/Modules/TranslationUIProvider.swiftmodule/arm64e-apple-ios.swiftinterface`
