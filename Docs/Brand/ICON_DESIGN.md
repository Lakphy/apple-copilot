# Apple Copilot app icon

## Direction

Two overlapping speech bubbles express translation and continuous conversation. Azure and ice blue connect the mark to the app's primary action color. The mark uses no lettering and preserves one silhouette across platforms and appearances.

The foreground was made with the built-in imagegen tool, with a second cleanup pass for the alpha edges. The PNG source lives at `Resources/IconArtwork/conversation-mark.png` (1254 × 1254, RGB with alpha). The shipping icon is a shared square Icon Composer document at `Resources/AppIcon.icon`; the system supplies masking and Liquid Glass rendering. Its foreground scale is 0.73, leaving approximately one-sixth of the canvas on each side of the combined mark. The default background is an automatic gradient based on `#E3EFFF`; the system derives dark and tinted appearances from the same artwork.

Apple's guidance in `.agents/skills/apple-design/references/hig/app-icons.md` → **Design**, **Icon shape**, and **Visual effects** supports simple overlapping shapes, unmasked artwork, and system-provided effects. Icon Composer exports are previews, not the flattened shipping source.

## Integration and checks

- The iOS and macOS App targets both compile the shared `Resources/AppIcon.icon` resource using `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. iPadOS uses the iOS target.
- XcodeGen generation succeeded. Simulator and macOS builds both exited 0 with no warning or error in `build/icon-simulator-build.log` and `build/icon-mac-build.log`.
- The compiled iOS Info.plist selects AppIcon; the Mac bundle contains AppIcon.icns and Assets.car and selects AppIcon.
- The new package was installed and launched on the existing iPhone and iPad simulators; the new Mac build launched in Preview mode. No data reset was performed.
- Icon Composer exports were inspected at 1024 pixels for default, dark and tinted appearances, and at 64 pixels for legibility. Design Generation 26 and 27 exports were both inspected. These are system-rendered previews, rather than screenshots of every Home Screen appearance.

Previews: [default](app-icon-default.png), [dark](app-icon-dark.png), [tinted](app-icon-tinted.png), [iOS 26](app-icon-default-26.png), [64 px](app-icon-small.png), [macOS](app-icon-macos.png).

## Generation prompt

```text
Use case: logo-brand.
Asset type: original Apple Copilot app icon foreground artwork, for native iOS, iPadOS and macOS layered Liquid Glass app icons. One single centered mark on a genuinely transparent 1024 x 1024 square canvas.
Primary request: create a beautiful, extremely simple, restrained icon mark for a translation and continuous AI conversation utility. Two large softly rounded filled speech bubbles offset diagonally and gracefully overlapping, together forming one compact balanced silhouette. A rear bubble in clear medium azure blue, a front bubble in very pale ice blue with a small understated cyan translucent overlap. The two rounded short speech tails point in opposite directions, expressing a two-way exchange. Only those two shapes, no lettering, no symbols inside them. The shape should feel custom, precise, friendly, calm and polished; not an emoji or a stock chat app logo.
Composition: front-facing flat orthographic graphic, no tilt or perspective; mark occupies approximately 64 percent of the canvas width and height, optically centered; generous completely transparent padding on all sides, strong filled silhouettes, smoothly defined edges that remain readable at 32 px.
Style: clean vector-like artwork designed to be imported as one foreground layer into Apple's Icon Composer; solid colors, slight opacity in overlapping area, no baked lighting or glass effects because system supplies them.
Constraints: transparent background; no outer rounded-square app tile, no border frame, no mockup, no display shadow, no reflections, no blur, no glow, no 3D extrusion, no gradients inside shapes, no fine outlines, no texture, no Apple logo, no text, no letters, no watermark. Single icon only.
```

## Cleanup prompt

```text
Keep the two bubble silhouettes, diagonal overlap, proportions and blue/ice-blue colors. Clean up alpha edges into crisp smooth antialiased edges; remove stray pixels, white specks and halos. Preserve the transparent square canvas. Do not add lettering, extra shapes, shadows, background tiles or baked glass effects.
```
