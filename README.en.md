# Apple Copilot

[简体中文](README.md) · [Documentation](Docs/README.md) · [Contributing](CONTRIBUTING.md)

A native SwiftUI translation app for **iOS 26, iPadOS 26, and macOS 26**. Bring your own model endpoint and API key, translate selected text, ask follow-up questions, and search local conversation history.

This is an early-stage, source-built project. The interface and detailed documentation are primarily in Chinese; full localization is not available yet.

## Features

- OpenAI Chat Completions, OpenAI Responses, and Anthropic Messages protocols, including compatible endpoints.
- Streaming replies, cancellation, retry, draft recovery, and conversation configuration snapshots.
- Custom target languages and prompt variables.
- Bundled Markdown rendering, code highlighting/copying, tables, math, footnotes, and Mermaid diagrams. Remote images load only after an explicit user action.
- Device-local JSON history and Keychain credentials. The iOS app and extension share data through App Groups and Keychain access groups.
- An iOS/iPadOS Translation Provider Extension and a macOS Services panel.

There is no cross-device sync or image input. macOS integration uses Services; it does not replace Apple's system Translate sheet.

## Build and run

The verified toolchain is **Xcode 27 / Swift 6.4** on macOS. The package manifest requires Swift 6.2 or newer; compatibility with earlier Xcode toolchains has not been verified. Deployment targets start at OS version 26.

```sh
git clone https://github.com/Lakphy/apple-copilot.git
cd apple-copilot
open AppleCopilot.xcodeproj
```

Choose `AppleCopilot-macOS` or `AppleCopilot-iOS`. The iOS scheme builds both iPhone and iPad apps and embeds the translation extension. XcodeGen and Node.js are unnecessary for a normal build because the generated project and renderer resources are committed.

Configure the protocol, endpoint, provider-issued model ID, and API key in Settings, then save. Device installation requires your own signing team, bundle identifiers, App Group, and shared Keychain configuration, with support for the Default Translation App capability. See [setup instructions](Docs/GETTING_STARTED.md).

For iOS/iPadOS system integration, select Apple Copilot in Settings → Apps → Default Apps → Translation. On macOS, select text and use Services → 使用 Apple Copilot 翻译. Services requires the complete app bundle.

## Development

```sh
./Scripts/test.sh       # All Swift tests with an isolated loopback fixture
./Scripts/check.sh      # Style, docs, configuration, tests, and platform builds
```

Renderer work additionally requires Node.js 22 or newer, `npm ci --ignore-scripts`, and Playwright WebKit. See the [development guide](Docs/DEVELOPMENT.md) and [validation scope](Docs/VALIDATION.md).

`CopilotCore` owns model, networking, persistence, and observable state. `CopilotUI` owns shared presentation, organized by feature. App, extension, and macOS entry points remain separate. See [architecture](Docs/ARCHITECTURE.md).

## Privacy and licensing

Translation sends the system prompt, source text, and conversation context to your configured provider. History stays on the device; API keys stay in Keychain. Provider data handling depends on that provider. See [privacy](Docs/PRIVACY.md).

Original application code, tooling, and documentation use the [MIT license](LICENSE). Bundled libraries, fonts, and optional development skills retain their upstream terms. The retained Apple design skill has unresolved redistribution permission; the repository is not uniformly MIT licensed. See [third-party notices](THIRD_PARTY_NOTICES.md).

This independent project is not affiliated with or endorsed by Apple or any model provider. See [security reporting](SECURITY.md) for sensitive issues.
