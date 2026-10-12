# 安装与使用

## 工具链与构建

当前完整检查使用 Xcode 27 / Swift 6.4，目标系统最低 iOS/iPadOS/macOS 26。包清单要求 Swift 6.2+；尚未验证更早 Xcode 的全部 API 兼容性。安装完整 Xcode，并在 Xcode 设置中选择 Command Line Tools。脚本使用当前 `xcode-select` 的工具链，也支持通过 `DEVELOPER_DIR` 临时指定其他 Xcode。

打开 `AppleCopilot.xcodeproj`：

- `AppleCopilot-macOS`：Mac 主应用与 Services。
- `AppleCopilot-iOS`：iPhone/iPad 主应用和 `AppleCopilotTranslation` 扩展。

工程已生成并提交。只在修改 `project.yml` 时需要 XcodeGen；普通构建不需要 Node.js，Markdown 引擎与字体已打包。

## iPhone/iPad 真机签名

1. 复制 `Configuration/Local.xcconfig.example` 为 `Configuration/Local.xcconfig`，填写自己的 Team ID、App Group 和 Keychain suffix。该文件被 Git 忽略，由 `Signing.xcconfig` 可选引入。
2. 为 iOS 主应用和翻译扩展设置自己拥有的 Bundle ID。可以修改 `project.yml` 并重新生成工程，或在 Xcode 中修改对应 target。扩展 ID 应以主应用 ID 为前缀。
3. 两个 target 选择同一支持 Default Translation App 能力的 Team，注册并启用相同 App Group，保留一致的共享 Keychain access group。
4. 保留主应用的 `com.apple.developer.translation-app` entitlement，以及主应用和扩展的 translation-provider network-access Info.plist 声明。
5. 连接并解锁设备，完成配对并启用开发者模式。在 Xcode 选择设备，运行 iOS scheme。

共享配置文件不能为所有 target 设置同一个 `PRODUCT_BUNDLE_IDENTIFIER`，否则主应用和扩展会重名。Team 是否支持所需 capability 以 Xcode 和开发者账户为准；编译成功或拥有开发证书都不能替代有效 provisioning。签名失败时检查团队和 capability，不要删除翻译权限来验证系统入口。

项目的默认 Bundle ID 与 App Group 保留原值，以避免现有开发安装丢失共享数据。它们是开发默认值，发行自己的版本时应替换为自己注册的标识。

## Simulator 实际运行

编译检查的无签名产物与模拟器运行包使用不同构建参数。运行包需要 Xcode 在构建时嵌入 simulated entitlements：

```sh
./Scripts/build-simulator.sh
xcrun simctl list devices available
COPILOT_SIMULATOR_UDID='复制列表中的完整 UDID'
./Scripts/boot-simulator.sh "$COPILOT_SIMULATOR_UDID"
xcrun simctl install "$COPILOT_SIMULATOR_UDID" \
  'build/SimulatorRuntime/Build/Products/Debug-iphonesimulator/Apple Copilot.app'
xcrun simctl launch "$COPILOT_SIMULATOR_UDID" com.lakphy.applecopilot
```

如果修改过 Bundle ID，最后一条命令也要更新。不要将无签名构建事后手动签名当作等价运行包。

启动脚本只操作指定设备，最多等待 180 秒，不擦除数据。针对历史记录中的 CoreLocation 迁移停滞，可显式使用 `--recover-dasd`；它仅在匹配条件下最多重启两次该模拟器内部的服务。见脚本 `--help` 和[历史诊断记录](Archive/VALIDATION_2026-10-12.md)。

## 配置模型与开始翻译

在设置中选择协议，填写 HTTPS Base URL、服务商提供的真实模型 ID 和 API key，然后保存。Base URL 可以是根地址、版本路径或完整端点；页面显示实际请求地址，并提供“补全路径”。不要把 key、查询参数或账户密码放进地址。

同一协议和最终端点下，API key 留空会保留已保存密钥。更换协议或服务地址需要输入对应服务的 key。更换模型、提示词或目标语言不会更换密钥身份。历史追问沿用原会话配置，需要恢复该服务的设置才能继续。

模型名称随服务商变化，以其当前文档和账户权限为准。兼容 Chat Completions 的服务可选择相应协议；[DeepSeek 分析](DEEPSEEK_CONNECTION.md)记录了一次具体配置排查，不是永久有效的模型推荐。

iPhone/iPad：系统“设置 → App → 默认 App → 翻译”选择 Apple Copilot，在支持的 App 中选中文字并点“翻译”。安装不会自动更改默认 App。系统宿主负责关闭按钮；仅宿主允许替换时提供“替换原文”。

Mac：运行完整 `.app`，在其他支持 Services 的应用中选中文字，通过“服务 → 使用 Apple Copilot 翻译”打开浮动窗口。必要时在系统设置的“键盘 → 键盘快捷键 → 服务”启用。`swift run` 的裸可执行文件不适合验证 Services 注册。

## 无远程模型的演示与测试

Debug 主应用可用 `--preview` 启动固定内存数据；`--preview-markdown` 使用富文本及逐段输出示例。两者不读取真实 Keychain、不保存生产历史、不调用远程模型。

正常模式下可连接本机测试服务：

```sh
python3 Scripts/mock_model_server.py --port 56343 --log build/mock-requests.jsonl
```

配置 OpenAI Chat Completions、`http://localhost:56343/v1`、`copilot-test-model`、测试 key `local-simulator-key`，开启“允许本机 HTTP 服务”。它只返回固定文本，支持三个协议的 JSON 与 SSE，日志不包含真实密钥或任意提交文本。

本机 fixture 绑定回环地址。真机上的 `localhost` 指真机自身，不能直接访问 Mac 上的该服务。不要为此关闭远程 HTTPS 校验。

## 快捷键

| Mac 操作 | 快捷键 |
| --- | --- |
| 新翻译 | ⌘N |
| 发送 | ⌘Return |
| 停止生成 | ⌘. |
| 翻译 / 历史 | ⌘1 / ⌘2 |
| 设置 / 保存设置 | ⌘, / ⌘S |
| 追问发送 / 换行 | Return / ⌥Return |

移动端屏幕键盘的“发送”提交追问；外接键盘 Shift/Option + Return 插入换行。输入法候选确认和粘贴保持原生编辑行为。Mac 追问框 Escape 取消焦点，窗口关闭使用原生关闭按钮。
