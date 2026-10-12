# Contributing

欢迎贡献问题复现、文档修正、测试和功能改进。Please use Chinese or English in issues and pull requests.

## Before changing code

Read the [architecture](Docs/ARCHITECTURE.md) and [development guide](Docs/DEVELOPMENT.md).
For larger features, describe the user problem in an issue first so the scope and
platform behavior can be discussed. Small fixes can be submitted directly.

The app uses MV with Observation. Keep business rules in `CopilotCore`, presentation
in `CopilotUI`, and platform entry points in their own modules. Dependencies should
remain replaceable in tests. Prefer extracting a focused view or service before
introducing another architecture layer.

## Style and validation

Use four-space indentation and the committed `.swift-format` configuration:

```sh
swift format format --in-place --recursive Package.swift Sources Tests
./Scripts/check.sh
```

Add behavioral regression tests for changes to request encoding, cancellation,
credential scope, persistence, or draft state. A file move or formatting change
usually needs the existing tests and affected builds, not duplicate tests of the
same implementation.

For renderer changes, rebuild and test the shipped resources:

```sh
cd Scripts/MarkdownRenderer
npm ci --ignore-scripts
npx playwright install webkit
cd ../..
./Scripts/check-markdown.sh
```

Commit the renderer source, lock file, generated JavaScript/CSS/fonts, and license
notices together. Change `project.yml` before regenerating `AppleCopilot.xcodeproj`.
Do not commit `Configuration/Local.xcconfig`, build output, API keys, signing
material, private conversation history, or identifying device diagnostics.

## Pull requests

Explain the problem, the resulting behavior, and checks actually run. Mention any
validation you could not perform. Include relevant screenshots for UI changes,
using public fixture text. Keep unrelated cleanup in a separate change when it
would obscure review. Preserve storage compatibility and app/extension sharing,
or explicitly describe a migration.

Contributions to original project files are submitted under the project's
[MIT license](LICENSE). Do not relicense vendored references; consult
[third-party notices](THIRD_PARTY_NOTICES.md) before changing or distributing them.

Treat contributors respectfully, focus reviews on behavior and evidence, and avoid
personal attacks. Report credential exposure or other security issues using the
[private reporting guidance](SECURITY.md).
