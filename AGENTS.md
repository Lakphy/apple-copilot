# Apple Copilot — Repository Instructions

These instructions cover application code, tests, tooling, and documentation in this repository. Follow more specific directory instructions when working in their scope. Preserve existing working-tree changes unrelated to the task.

## Project and entry points

Apple Copilot is a native SwiftUI text-translation app for iOS, iPadOS, and macOS 26+. It uses MV + Observation and user-configured model endpoints. The verified toolchain and setup requirements are maintained in [README.md](README.md).

| Path | Responsibility |
| --- | --- |
| `Sources/CopilotCore/` | Domain values, provider protocols, HTTP, credentials, persistence, and observable stores |
| `Sources/CopilotUI/` | Shared presentation, grouped into Translation, History, Settings, and Markdown |
| `Sources/AppleCopilotApp/` | App lifecycle, windows, and menu commands |
| `Sources/TranslationExtension/` | iOS/iPadOS TranslationUIProvider integration |
| `Sources/MacIntegration/` | macOS Services and NSPanel integration |
| `Tests/CopilotCoreTests/` | Request, streaming, prompt, persistence, and state behavior |
| `Tests/CopilotUITests/` | Native macOS component tests using Swift Testing, AppKit, and WebKit |
| `Scripts/MarkdownRenderer/` | Renderer source and pinned npm dependencies |

Use [architecture](Docs/ARCHITECTURE.md) for module or state-ownership changes, [development](Docs/DEVELOPMENT.md) for build/test workflows, and [system integration](Docs/PlatformIntegration.md) for extension or Services work. Historical design and validation records describe their recorded versions; current verification belongs in [Docs/VALIDATION.md](Docs/VALIDATION.md).

## Architecture and behavior

- Keep reusable validation, provider adaptation, credential scope, and persistence rules in `CopilotCore`; keep navigation and presentation in `CopilotUI`.
- Preserve MainActor isolation for UI-bound observable stores and Sendable boundaries for shared values and injected dependencies.
- Extract focused views or services before adding an architecture layer. Avoid forwarding-only view models.
- Preserve the saved-configuration/draft distinction. Translation uses saved settings; history follow-ups use the conversation's original configuration snapshot.
- Retain cancellation tokens, readable transient streaming output, completed user/assistant pair commits, cross-process file locking, and deletion tombstones.
- Keep existing Codable files readable. Schema changes require explicit compatibility handling and behavioral tests.
- Structure-only UI changes preserve bindings, stable view identity, input-method composition, focus, navigation, and scroll behavior.
- iOS/iPadOS integration uses the system translation host. macOS integration uses Services and a native panel; it cannot be described as a third-party system Translate sheet.

## Sources, style, and generated files

Use the committed `.swift-format`: four-space indentation and a 120-column target. Document public behavior and non-obvious constraints; let the formatter handle mechanical style.

```sh
swift format format --in-place --recursive Package.swift Sources Tests
swift format lint --strict --recursive Package.swift Sources Tests
```

`Package.swift` owns shared modules and resource declarations. `project.yml` owns Xcode targets and schemes: edit it first, run `xcodegen generate`, and include the generated project with the source change.

Renderer changes start in `Scripts/MarkdownRenderer/`. Rebuild rather than hand-edit bundled JavaScript. Keep source, lock file, generated resources, and dependency notices consistent. Assets ship under `Sources/CopilotUI/Resources/Markdown/`; ordinary app builds do not require npm.

Keep documentation aligned with behavior. Update both README languages when changing setup or advertised features. Put temporary logs, screenshots, and build products under the ignored `build/` directory.

## Validation commands

Run commands from the repository root. Native checks require macOS and full Xcode; scripts honor `DEVELOPER_DIR` or the active `xcode-select` toolchain.

| Change | Relevant checks |
| --- | --- |
| Core behavior | `./Scripts/test.sh --core-only` |
| Shared UI or native components | `./Scripts/test.sh` and affected platform builds; `./Scripts/check.sh` covers both |
| Targets, configuration, or cross-platform changes | `./Scripts/check.sh`; regenerate the project if `project.yml` changed |
| Renderer or bundled resources | `./Scripts/check-markdown.sh` and `./Scripts/test.sh` for native WebKit integration |
| Documentation only | `python3 Scripts/check_docs.py` |
| Swift formatting only | Strict formatter lint and `git diff --check` |

`test.sh` starts its own random-port loopback model fixture, enables real URLSession checks, and cleans up its process and temporary logs. These tests use dummy credentials and disposable data; run them and fix task-related failures without requesting approval for each invocation. Bare `swift test` skips live HTTP cases unless `COPILOT_STREAM_TEST_URL` is set.

For renderer setup, use Node.js 22+ and run `npm ci --ignore-scripts` and `npx playwright install webkit` in `Scripts/MarkdownRenderer/`. Add regression tests for changed behavior, not tests that merely restate file moves or formatting. Once relevant checks pass, repeat them only for new changes or unresolved concerns.

For visible UI changes, inspect meaningful states with deterministic previews. Debug `--preview` and `--preview-markdown` use in-memory data. Simulator runtime packages require `./Scripts/build-simulator.sh`; unsigned compilation alone does not verify app/extension runtime behavior.

## Credentials, signing, and third-party content

- Keep API keys in Keychain and out of Codable preferences, history, logs, screenshots, and issue reports. Do not display arbitrary provider error bodies.
- Preserve HTTPS enforcement, explicit loopback-only HTTP opt-in, endpoint-scoped credentials, and redirect refusal.
- Use `Configuration/Local.xcconfig` for ignored local signing overrides; its example is committed. Preserve shared app/extension capabilities and avoid committing personal Team IDs, signing material, or device identifiers.
- Retain bundled license notices. Optional `.agents/skills` and `.claude/skills` are development references with separate upstream terms, not application dependencies. Their licensing status is documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Code Review Rules

Flag changes that send a credential to a different provider identity, persist an incomplete turn, accept a truncated SSE stream as successful, allow a late response to overwrite a new selection, resurrect deleted history, or silently discard edits during settings refresh/save. Explain the concrete trigger and affected behavior.

Report the change, checks actually run, and material remaining limitations. Distinguish local fixtures and previews from remote-provider, real-device, signing, and distribution verification. Do not infer current success from historical reports.

AGENTS.md discovery and scoping reference: [official OpenAI documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
