# Third-party notices

The [MIT license](LICENSE) applies to original Apple Copilot application code,
project tooling, and documentation. It does **not** relicense third-party software,
fonts, agent skills, or reproduced Apple documentation.

## Bundled Markdown renderer

The renderer is built from the pinned dependency tree in
[`Scripts/MarkdownRenderer/package-lock.json`](Scripts/MarkdownRenderer/package-lock.json).
Runtime dependencies include Marked and its extensions, DOMPurify, highlight.js,
gemoji, KaTeX and its fonts, and Mermaid, plus their transitive dependencies.

Their package versions, license identifiers, and available license/notice files
are collected by `npm run build` into
[`THIRD_PARTY_LICENSES.txt`](Sources/CopilotUI/Resources/Markdown/THIRD_PARTY_LICENSES.txt).
Retain that file and any notices embedded in the JavaScript bundles when distributing
the app or the resources. Development tools such as esbuild and Playwright are not
bundled into the app.

## Optional agent skills shipped in this repository

The application build and CI do not load `.agents/skills` or `.claude/skills`.
These files remain in the repository as development references; `.claude/skills`
contains relative symbolic links to `.agents/skills`. The recorded origins and
content hashes are in [`skills-lock.json`](skills-lock.json).

| Content | Upstream | License status |
| --- | --- | --- |
| Swift/iOS skills under `.agents/skills`, excluding `apple-design` | [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) | PolyForm Perimeter 1.0.0; [preserved license](Docs/Licenses/swift-ios-skills.txt) |
| `.agents/skills/apple-design` | [dickwu/apple-design-skill](https://github.com/dickwu/apple-design-skill) | No explicit software license located in the upstream root or its README as checked on 2026-10-12; not covered by this repository's MIT license |
| Apple HIG excerpts in the design skill | [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | Upstream attributes the text to Apple Inc.; source links remain in each reference file |

Required Notice: Copyright (c) 2025 dpearson2699 (https://github.com/dpearson2699)

The Swift/iOS skill license includes a noncompetition condition. Consult its
preserved terms before reusing or redistributing these references independently.
The installed snapshot is identified by the lock file's content hashes; it does
not record a Git commit. The preserved license was retrieved from upstream on
2026-10-12, so historical license applicability still needs confirmation.

The Apple design skill is intentionally retained at the repository owner's request.
Its distribution permission remains **unresolved**: attribution or the absence of
an explicit license does not establish a permissive grant. Confirm the relevant
permissions with upstream before treating the entire repository as MIT licensed.

Apple Copilot is an independent project and is not affiliated with or endorsed by
Apple, OpenAI, Anthropic, DeepSeek, or the authors of the development references.
