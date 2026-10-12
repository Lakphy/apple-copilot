# 开发指南

## 环境

使用完整 Xcode；当前验证 Xcode 27 / Swift 6.4，目标系统 26+。脚本尊重 `DEVELOPER_DIR` 或当前 `xcode-select` 选择，不更改全局工具链。

普通构建无需第三方 Swift 依赖、Node.js 或 XcodeGen。修改工程配置时安装 XcodeGen 并执行 `xcodegen generate`；修改 Markdown 资源时使用 Node.js 22+ 与 npm。开发技能在 `.agents/skills`，只供辅助开发使用，不参与应用编译或 CI，其许可另见[第三方声明](../THIRD_PARTY_NOTICES.md)。

## 常用检查

```sh
# 核心和原生 Mac 组件测试；自动开启真实 URLSession 回环测试
./Scripts/test.sh

# 只跑核心
./Scripts/test.sh --core-only

# 综合检查及两个平台构建
./Scripts/check.sh

# 风格修复 / 严格检查
swift format format --in-place --recursive Package.swift Sources Tests
swift format lint --strict --recursive Package.swift Sources Tests

# 文档本地链接
python3 Scripts/check_docs.py
```

`test.sh` 使用 Python 标准库在随机端口启动 fixture，等待就绪后设置 `COPILOT_STREAM_TEST_URL`，结束时清理自己的子进程和临时日志。没有固定端口冲突，也不需要真实 API key。直接运行 `swift test` 仍可执行内存/原生测试，但未设置变量时会跳过回环 HTTP 用例。

`CopilotUITests` 是 macOS 的 Swift Testing 原生组件测试，使用 AppKit/WebKit，并非 XCUITest。需要可运行原生 UI 的 macOS 环境。核心依赖 Darwin 与 Security，当前不支持 Linux 构建。

## 工程与签名

`project.yml` 管理 target、依赖、资源和 schemes，生成后的 Xcode 工程与源配置一起提交。共享 Swift 文件由 Package.swift 自动发现，按 feature 移动文件通常不需要修改 Xcode 源文件列表。

`Configuration/Signing.xcconfig` 保存开发默认共享标识，并可选引入被忽略的 `Local.xcconfig`。个人 Team 和签名文件不提交。真机配置见[安装说明](GETTING_STARTED.md)。命令行 `xcodebuild` 参数也可覆盖设置。

```sh
xcodegen generate
xcodebuild -project AppleCopilot.xcodeproj -scheme AppleCopilot-macOS \
  -destination 'platform=macOS' -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AppleCopilot.xcodeproj -scheme AppleCopilot-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
```

无签名构建只检查编译与打包。需要实际模拟器运行时执行 `./Scripts/build-simulator.sh`；需要真机运行时配置有效签名。不要将两种验证等同。

## Swift 风格与责任边界

- 使用四空格缩进和 120 列目标行宽，交给 `.swift-format` 统一 imports、换行和分号规则。
- 为公开接口和不明显的生命周期约束写简短文档注释；注释解释约束和原因，避免重复代码。
- 状态与业务规则留在核心模型，视图声明布局并通过简短动作调用模型。
- 按状态所有权、平台适配或渲染职责拆分文件，不为单纯转发引入新层。
- 保留 MainActor 和 Sendable 边界，不使用 unchecked conformance 掩盖并发问题。
- 格式或结构整理应保持 API、存储编码、视图身份和取消语义。行为改变需要对应回归测试。

## Markdown 引擎

源文件位于 `Scripts/MarkdownRenderer`；应用读取 `Sources/CopilotUI/Resources/Markdown` 的生成产物。依赖精确版本固定在 package.json，完整解析由 lock file 固定。

```sh
cd Scripts/MarkdownRenderer
npm ci --ignore-scripts
npx playwright install webkit
cd ../..
./Scripts/check-markdown.sh
```

资源生成会打包 renderer 与 Mermaid、复制 KaTeX CSS/字体，并收集运行时依赖的 license/notice。浏览器回归使用 Playwright WebKit；原生 Swift 测试直接加载包内文件，检查真实 WKWebView 桥接。临时截图写入忽略目录 `build/MarkdownValidation`。

升级依赖时更新 lock file，重建全部资源，检查第三方 notices，并执行原生与浏览器测试。CI 重建后要求生成资源与提交内容一致。包管理器 audit 结果是检查时的快照，不能替代依赖审查。

## CI

[CI 工作流](../.github/workflows/ci.yml)分两个任务：原生任务执行综合检查，WebKit 任务安装锁定依赖、重建并测试资源。工作流使用只读仓库权限，不需要签名或模型服务凭据。

原生任务使用 GitHub 的 `xcode-27` runner 标签，与本机验证工具链一致；截至整理日期，该镜像仍标为 preview。可用镜像以 [GitHub runner-images](https://github.com/actions/runner-images#available-images) 为准。升级工具链时一起检查 Package.swift、project.yml、格式化结果与 runner 配置。

本机运行通过不代表 GitHub 工作流已运行；远程状态由对应 Actions run 提供。真机系统扩展、发行签名和远程模型测试不在 CI 范围内。
