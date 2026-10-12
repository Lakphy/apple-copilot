> 开发研究记录：结果对应文中标明的版本与日期，当前整理验证见 [验证说明](VALIDATION.md)。

# DeepSeek 连接分析

检查日期：2026-10-12。

## 结论与证据

输入 `https://api.deepseek.com` 时，已有的 `ProviderConfiguration.resolvedEndpoint()` 会补成 `https://api.deepseek.com/v1/chat/completions`。请求没有遗漏 Chat Completions 后缀，也没有重复拼接。DeepSeek 的[接口文档](https://api-docs.deepseek.com/api/create-chat-completion/)支持 `deepseek-flash`；[官方 WorkBuddy 配置示例](https://api-docs.deepseek.com/zh-cn/quick_start/agent_integrations/workbuddy/)使用上述完整路径。

本机分别向 `/chat/completions` 和 `/v1/chat/completions` 发送不带密钥的 POST，两者均返回 HTTP 401，没有重定向，TLS 校验成功。使用原生 `URLSession.bytes(for:)` 独立检查时，两个路径也均返回 HTTP 401。这证明本机能访问这两个接口，不能证明用户密钥有效、账户余额充足或设备网络可用。

当前 iPad 模拟器共享容器中，已保存的地址仍为 `http://localhost:56343/v1`，模型为 `copilot-test-model`。截图时间附近（18:58–19:01）的应用日志包含 56343 端口请求和 `NSURLErrorDomain Code=-1004`，即无法连接服务器。这与仍在连接已停止的本机测试服务相符。没有读取或输出 Keychain 密钥。

设置输入框是草稿，只有保存成功后才更新翻译使用的 `savedConfiguration`。此外，翻译扩展可以复用同一个环境，而 `CopilotEnvironment.load()` 只初始化一次；之前新弹窗没有再次刷新共享配置。因此，“主应用已保存新地址，但扩展继续使用旧配置”也是代码中存在的独立问题。当前日志不能区分尚未保存和扩展缓存这两种情况。

## 请求调用链

1. `TranslationOverlayView` 打开系统翻译弹窗，载入共享设置。
2. `ConversationStore.translate()` 从 `settings.savedConfiguration` 建立新会话快照。
3. `SettingsStore.credential(for:)` 按协议和最终端点查找对应密钥。
4. `URLSessionLanguageModelClient.makeRequest()` 调用 `resolvedEndpoint()`，发送 POST、Bearer 鉴权、模型 ID、system/user 消息和 `stream: true`。
5. `URLSessionHTTPTransport.stream()` 读取响应，`ModelStreamDecoder` 解析 SSE；已有解析器会忽略 keep-alive 注释和 reasoning 字段，只展示回复文本。

原代码把除取消之外的 `URLError` 全部转成 `networkUnavailable`。用户看到的“无法连接 API 服务”无法区分超时、DNS、离线、连接拒绝或 TLS 失败。HTTP 401、402、404 等响应走的是另一条 HTTP 状态错误分支，不会产生截图中的通用连接错误。

## 本次修改

- 设置展示与请求构造共用的完整端点，并提供“补全路径”；已有完整路径不会再次追加。
- 存在草稿时提示修改尚未保存，翻译继续使用已保存配置。
- 系统翻译弹窗在取得新会话快照前刷新共享设置，保留正在编辑的草稿。
- 流式和普通请求都保留安全的网络错误码，分别说明超时、DNS、连接失败、离线、连接中断及 HTTPS 错误。不会直接显示可能包含原文或密钥的底层错误描述。
- 增加 HTTP 400/422 参数错误、402 余额不足、404 端点或模型不存在的提示；DeepSeek 的[错误码文档](https://api-docs.deepseek.com/quick_start/error_codes/)说明了其 402 余额错误。

## 验证范围

回归测试覆盖 DeepSeek 根地址、版本路径、完整端点、尾部斜杠、普通和流式请求、Bearer 鉴权、网络错误与取消、等价端点保留密钥，以及从旧本机配置刷新后使用 DeepSeek 新配置。

`swift test --filter CopilotCoreTests` 通过，测试框架报告 50 个测试、6 个 suite。需要启动本机 mock server 的流式传输测试因未设置环境变量而跳过。iOS Simulator 与 macOS 的 `xcodebuild` 编译均通过，`git diff --check` 通过。

未使用用户真实密钥调用付费模型。若重新保存 DeepSeek 设置后仍失败，新版提示会给出实际网络错误码，再按该错误定位设备网络或服务状态。
