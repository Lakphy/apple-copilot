# 验证说明

本页记录当前整理版本的可复现检查。之前的交互、模拟器诊断和截图证据保存在[历史归档](Archive/VALIDATION_2026-10-12.md)及[界面重构记录](UI_REDESIGN_VALIDATION.md)，不自动视为本轮重新验证。

## 检查入口

| 命令 | 范围 |
| --- | --- |
| `./Scripts/test.sh` | 全部 Swift 核心与原生 Mac 组件测试，以及随机端口 fixture 的真实 HTTP/流式请求 |
| `./Scripts/test.sh --core-only` | 核心模块测试与回环 HTTP，不运行原生 UI 组件 |
| `./Scripts/check.sh` | Swift 风格、文档本地链接、plist、脚本语法、Swift 测试、Mac 与 iOS Simulator 无签名构建 |
| `./Scripts/check-markdown.sh` | 资源重建及 Playwright WebKit 渲染回归；CI 额外检查生成资源一致 |
| `./Scripts/build-simulator.sh` | 可运行 Simulator 包及嵌入 simulated entitlements 检查 |

直接运行 `swift test` 时，未设置 `COPILOT_STREAM_TEST_URL` 会跳过真实 HTTP 用例。`test.sh` 自动启动隔离 fixture 并在结束时清理，无需手动启动第二个终端服务。

## 本轮检查

检查日期：2026-10-12。环境：Xcode 27.0（27A266a）/ Swift 6.4，Apple Silicon Mac；浏览器测试使用 Node.js 22.23.2 / npm 10.9.8。

| 检查 | 结果 | 实际范围 |
| --- | --- | --- |
| Swift 核心测试 | 52 项通过、6 个 suite | 包含三协议真实回环流式请求、新增 HTTP response metadata 和保存条件回归 |
| 原生 Mac 组件测试 | 14 项通过、4 个 suite | 原生 WebKit、语义外观、文本组合、键盘提交和滚轮 |
| Playwright WebKit | 13 项通过 | 使用 `npm ci --ignore-scripts` 后的干净依赖安装与资源重建 |
| macOS 应用构建 | 通过，退出码 0 | 本机架构的无签名 Debug 主应用及共享模块 |
| iOS Simulator 构建 | 通过，退出码 0 | 主应用、共享模块和嵌入的 Translation Provider 扩展 |
| 风格、文档、配置和脚本检查 | 通过 | Swift strict lint、本地链接、六份 plist/entitlements、zsh/Python 语法 |
| XcodeGen 与签名覆盖 | 通过 | 二次生成文件一致；本地 xcconfig 的 Team/App Group/Keychain 覆盖生效；测试覆盖文件已清理 |
| Mac 主页面预览 | 限定实看通过 | 独立 Debug 内存预览：富文本会话、历史选择、设置、⌘N 空白状态 |
| 凭据模式扫描 | 未发现匹配 | 工作区中原创项目文件的 key/private-key 文本模式；不等同全面安全审计 |

原生构建为无签名编译检查。综合构建最初出现 Mac 双架构目的地选择提示；脚本改为明确本机架构后，Mac 构建重新通过且没有该提示。预览检查使用独立 bundle 和固定数据，未操作生产历史或真实密钥。Node 干净安装报告 0 vulnerabilities，这是检查时的包管理器快照。

GitHub CI 配置已增加，尚未在远程运行。未把历史 Simulator 交互结果算作本轮重测。

## 已覆盖的行为

- 三协议请求构造、可见文本解码、完整会话上下文、提示词变量和端点规范化。
- HTTPS/回环 HTTP 校验、重定向拒绝、错误脱敏和密钥 header 校验。
- SSE 换行、跨字节 UTF-8、多行 data、完成/截断/错误事件和 JSON 兼容返回。
- 流式输出、取消、迟到响应、失败重试、草稿保存条件和完整问答持久化。
- 独立文件写入、陈旧会话合并、删除 tombstone、配置刷新和密钥身份隔离。
- macOS 原生文本组合、Return/Option/Command 提交规则、滚轮事件转交、WebKit 本地文件、桥接、测高和外观变化。
- 浏览器 GFM、代码复制、公式、Mermaid、稳定 DOM/选区、图片显式加载与 HTML 注入回归。

## 仍需单独验证

- 拥有对应 capability 的真实设备签名、系统默认翻译调用、替换原文和进程共享路径。
- 各服务商的真实远程连接、账户/模型权限、速率限制和翻译质量。本机 fixture 不证明远程服务可用。
- 完整 VoiceOver、键盘、输入法、最大字号、降低透明度及多平台外观组合。组件测试不等同完整 UI 自动化。
- 发行签名、公证、App Store 提交和更早 Xcode 工具链的兼容性。
- GitHub Actions 的实际运行结果；本轮只验证本地脚本和构建。

开源整理和许可状态见[研究记录](OPEN_SOURCE_REVIEW.md)与[第三方声明](../THIRD_PARTY_NOTICES.md)。
