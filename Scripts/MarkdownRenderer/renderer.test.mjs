import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { webkit } from 'playwright';

const resources = new URL('../../Sources/CopilotUI/Resources/Markdown/', import.meta.url);
let server, browser, baseURL;
before(async () => {
  server = createServer(async (request, response) => {
    try {
      const path = request.url === '/' ? 'index.html' : request.url.slice(1);
      if (path.includes('..')) throw new Error('invalid path');
      const data = await readFile(new URL(path, resources));
      const type = path.endsWith('.js') ? 'application/javascript' : path.endsWith('.css') ? 'text/css' : path.endsWith('.woff2') ? 'font/woff2' : 'text/html';
      response.writeHead(200, { 'Content-Type': type }); response.end(data);
    } catch { response.writeHead(404); response.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  baseURL = `http://127.0.0.1:${server.address().port}/`;
  browser = await webkit.launch();
});
after(async () => { await browser?.close(); await new Promise(resolve => server.close(resolve)); });

async function pageFor(viewport = { width: 390, height: 844 }) {
  const page = await browser.newPage({ viewport });
  await page.addInitScript(() => {
    window.messages = [];
    window.webkit = { messageHandlers: { markdown: { postMessage: value => window.messages.push(value) } } };
  });
  await page.goto(baseURL);
  await page.waitForFunction(() => window.messages.some(m => m.type === 'ready'));
  return page;
}

async function update(page, markdown, options = {}) {
  const revision = await page.locator('#content').getAttribute('data-render-revision');
  await page.evaluate(payload => window.copilotUpdate(payload), {
    markdown, streaming: false, dark: false, fontSize: 17, ...options,
  });
  await page.waitForFunction(revision => document.getElementById('content').dataset.renderRevision !== revision &&
    document.getElementById('content').dataset.renderRevision !== undefined, revision);
}

const fixture = `# 富文本回复

支持 **粗体**、*斜体*、~~删除线~~、\`行内代码\` 和 https://example.com。

> 引用可以包含 **强调**。

> [!TIP]
> 内容随生成逐步出现。

1. 有序列表
   - 嵌套项目
2. 第二项

- [x] 已完成
- [ ] 待完成

| 能力 | iPhone | iPad | Mac |
| :--- | :---: | :---: | ---: |
| Markdown | ✓ | ✓ | ✓ |
| Mermaid | ✓ | ✓ | ✓ |

\`\`\`swift
let message = "你好🙂"
print(message)
\`\`\`

\`\`\`mermaid
flowchart LR
    A[接收文本] --> B[Markdown]
    B --> C[逐步显示]
\`\`\`

公式 $E = mc^2$ 与脚注[^1]。

$$
\\frac{a}{b} + \\sqrt{x}
$$

<details><summary>更多说明</summary>可以展开阅读。</details>

[^1]: 脚注支持返回正文。
`;

test('task markers align with the first line at every text size, including loose and nested lists', async () => {
  const page = await pageFor({ width: 320, height: 844 });
  const tasks = `- [x] 已完成
- [ ] 待完成
- [ ] **粗体任务** with a long description that wraps onto multiple lines at narrow widths
  - [x] 嵌套任务
  - 普通项目

---

- [x] 空行任务 with a long description that wraps onto multiple lines at narrow widths

  第二段说明。

- [ ] 待完成的空行任务
`;
  for (const fontSize of [13, 17, 53]) {
    for (const dark of [false, true]) {
      await update(page, tasks, { fontSize, dark, platform: fontSize === 13 ? 'macOS' : 'iOS', boldText: fontSize === 53 });
      const layout = await page.evaluate(() => [...document.querySelectorAll('input[type="checkbox"]')].map(input => {
        const line = input.parentElement;
        const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
        let text;
        while ((text = walker.nextNode()) && !text.textContent.trim()) { /* Skip parser whitespace. */ }
        const firstCharacter = document.createRange();
        const start = text.textContent.search(/\S/);
        firstCharacter.setStart(text, start); firstCharacter.setEnd(text, start + 1);
        const label = firstCharacter.getBoundingClientRect();
        const marker = input.getBoundingClientRect();
        const item = input.closest('li');
        return {
          label: item.textContent.trim().slice(0, 24),
          offset: marker.y + marker.height / 2 - label.y - label.height / 2,
          markerStart: marker.x, markerEnd: marker.right, textStart: label.x,
          listStyle: getComputedStyle(item).listStyleType,
          disabled: input.disabled, accessibleLabel: input.getAttribute('aria-label'),
        };
      }));
      assert.equal(layout.length, 6);
      assert.equal(layout.every(row => Math.abs(row.offset) <= .75), true, JSON.stringify({ fontSize, dark, layout }));
      assert.equal(layout.every(row => row.markerStart >= 0 && row.markerEnd < row.textStart), true, JSON.stringify(layout));
      assert.equal(layout.every(row => row.listStyle === 'none' && row.disabled && row.accessibleLabel), true, JSON.stringify(layout));
      assert.notEqual(await page.locator('li').filter({ hasText: /^普通项目$/ }).evaluate(n => getComputedStyle(n).listStyleType), 'none');
      assert.equal(await page.locator('#content').evaluate(n => n.scrollWidth), 320);
    }
  }
  await update(page, '- [x] 已完成\n- [ ] 待完成', { fontSize: 17 });
  const directory = fileURLToPath(new URL('../../build/MarkdownValidation/', import.meta.url));
  await mkdir(directory, { recursive: true });
  await page.locator('#content').screenshot({ path: `${directory}/task-list-alignment.png` });
  await page.close();
});

test('GFM, GitHub extensions, math and local Mermaid render in WebKit', async () => {
  const page = await pageFor();
  await update(page, fixture);
  await page.waitForSelector('.mermaid-diagram svg');
  assert.equal(await page.locator('h1').textContent(), '富文本回复');
  assert.equal(await page.locator('del').textContent(), '删除线');
  assert.equal(await page.locator('input[type=checkbox]').count(), 2);
  assert.equal(await page.locator('input[type=checkbox]:checked').count(), 1);
  assert.equal(await page.locator('input[type=checkbox]:disabled').count(), 2);
  assert.equal(await page.locator('.table-scroll table').count(), 1);
  assert.equal(await page.locator('li ul').count(), 1);
  assert.equal(await page.locator('.markdown-alert.tip').count(), 1);
  assert.equal(await page.locator('.hljs-keyword').first().textContent(), 'let');
  assert.equal(await page.locator('.katex').count(), 2);
  assert.equal(await page.locator('.katex svg').count() > 0, true);
  assert.equal(await page.locator('.footnotes li').count(), 1);
  assert.equal(await page.locator('.mermaid-diagram').textContent().then(s => s.includes('逐步显示')), true);
  assert.equal(await page.locator('.mermaid-diagram svg').getAttribute('role'), 'group');
  assert.equal(await page.locator('.mermaid-diagram text').count() >= 3, true);
  const width = await page.evaluate(() => document.getElementById('content').getBoundingClientRect().width);
  assert.equal(width, 390);
  const directory = fileURLToPath(new URL('../../build/MarkdownValidation/', import.meta.url));
  await mkdir(directory, { recursive: true });
  await page.screenshot({ path: `${directory}/iphone-light.png`, fullPage: true });
  await update(page, fixture, { dark: true, fontSize: 23 });
  await page.waitForSelector('.mermaid-diagram svg');
  await page.screenshot({ path: `${directory}/iphone-dark-large-type.png`, fullPage: true });
  await page.setViewportSize({ width: 760, height: 1024 });
  await update(page, fixture, { dark: true, fontSize: 17 });
  await page.waitForSelector('.mermaid-diagram svg');
  await page.screenshot({ path: `${directory}/ipad-dark.png`, fullPage: true });
  await page.setViewportSize({ width: 760, height: 900 });
  await update(page, fixture, { fontSize: 13, platform: 'macOS', headingSizes: [22, 17, 15] });
  await page.waitForSelector('.mermaid-diagram svg');
  await page.screenshot({ path: `${directory}/mac-light.png`, fullPage: true });
  await page.close();
});

test('copy uses the exact unhighlighted code, including Unicode and HTML', async () => {
  const page = await pageFor();
  const source = 'let value = "你好🙂"\n<script>literal</script>';
  await update(page, `\`\`\`swift\n${source}\n\`\`\``);
  await page.locator('.copy-code').click();
  const copy = await page.evaluate(() => window.messages.find(m => m.type === 'copy'));
  assert.equal(copy.text, source);
  await page.evaluate(id => window.copilotCopyResult(id, true), copy.id);
  assert.equal(await page.locator('.copy-code').textContent(), '已复制');
  assert.equal(await page.locator('#content script').count(), 0);
  await page.close();
});

test('streaming reuses stable DOM and selection, supports partial fences and stable heading IDs', async () => {
  const page = await pageFor();
  const prefix = '# 标题\n\nStable paragraph.\n\n';
  await update(page, prefix + 'Partial', { streaming: true });
  await page.evaluate(() => {
    window.stable = document.querySelectorAll('.markdown-block')[1];
    const range = document.createRange(); range.selectNodeContents(window.stable);
    window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
    window.initialSelection = window.getSelection().toString();
  });
  await update(page, prefix + 'Partial **strong**\n\n```swift\nlet x = 1', { streaming: true });
  assert.equal(await page.evaluate(() => window.stable === document.querySelectorAll('.markdown-block')[1]), true);
  assert.equal(await page.evaluate(() => window.getSelection().toString() === window.initialSelection), true);
  assert.equal(await page.locator('h1').getAttribute('id'), '标题');
  assert.equal(await page.locator('.hljs-keyword').textContent(), 'let');
  assert.equal(await page.locator('pre code').textContent(), 'let x = 1');
  await update(page, '# 标题\n\n# 标题\n');
  assert.deepEqual(await page.locator('h1').evaluateAll(nodes => nodes.map(n => n.id)), ['标题', '标题-1']);
  await page.close();
});

test('Mermaid waits for a closing fence and gracefully exposes invalid diagram source', async () => {
  const page = await pageFor();
  const source = '```mermaid\nsequenceDiagram\nAlice->>Bob: Hello';
  await update(page, source, { streaming: true });
  assert.equal(await page.evaluate(() => !!window.copilotMermaid), false);
  assert.equal(await page.locator('.mermaid-diagram').count(), 0);
  assert.equal(await page.locator('.diagram-status').textContent(), '图表生成中…');
  await update(page, source + '\n```', { streaming: true });
  await page.waitForSelector('.mermaid-diagram svg');
  assert.equal(await page.locator('.code-block details pre').textContent(), 'sequenceDiagram\nAlice->>Bob: Hello');
  await update(page, '```mermaid\nthis is not a diagram\n```');
  await page.waitForFunction(() => document.querySelector('.diagram-status')?.textContent.includes('暂时无法'));
  assert.equal(await page.locator('pre').textContent(), 'this is not a diagram');
  await page.close();
});

test('multiple Mermaid diagram families render locally', async () => {
  const page = await pageFor({ width: 760, height: 900 });
  for (const source of [
    'classDiagram\nAnimal <|-- Duck\nAnimal : +eat()',
    'stateDiagram-v2\n[*] --> Idle\nIdle --> Active',
    'erDiagram\nUSER ||--o{ MESSAGE : writes',
    'pie title Usage\n"Markdown" : 70\n"Diagrams" : 30',
    'gantt\ntitle Schedule\ndateFormat YYYY-MM-DD\nsection Work\nBuild :a1, 2026-10-12, 2d',
    'mindmap\n  root((Copilot))\n    Markdown\n    Mermaid',
  ]) {
    await update(page, `\`\`\`mermaid\n${source}\n\`\`\``);
    await page.waitForSelector('.mermaid-diagram svg');
  }
  await page.close();
});

test('hostile HTML stays inert and remote images require an explicit click', async () => {
  const page = await pageFor();
  const requests = [];
  await page.route('https://example.com/**', route => { requests.push(route.request().url()); route.abort(); });
  await update(page, '<script>window.hacked = true</script>\n\n<img src="https://example.com/tracker.png" onerror="window.hacked = true">\n\n<iframe src="https://example.com"></iframe>\n\n[unsafe](javascript:alert(1))\n\n<input type="image" src="https://example.com/tracker2.png">\n\n<div style="background:url(https://example.com/tracker3.png)">safe</div>');
  assert.equal(await page.evaluate(() => window.hacked), undefined);
  assert.equal(await page.locator('#content script, #content iframe, #content [onerror], #content [style], #content input').count(), 0);
  assert.equal(await page.locator('a[href^="javascript:"]').count(), 0);
  assert.equal(await page.locator('.image-placeholder button').count(), 1);
  assert.deepEqual(requests, []);
  await page.locator('.image-placeholder button').click();
  assert.equal(await page.evaluate(() => window.messages.find(m => m.type === 'image')?.url), 'https://example.com/tracker.png');
  const id = await page.evaluate(() => window.messages.find(m => m.type === 'image').id);
  await page.evaluate(id => window.copilotImageResult(id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII='), id);
  assert.equal(await page.locator('.image-placeholder').count(), 0);
  await page.close();
});

test('links and footnote anchors are routed through the native bridge', async () => {
  const page = await pageFor();
  await update(page, '# Heading\n\n[Link](https://example.com/path) and footnote[^1].\n\n[^1]: Footnote');
  await page.locator('a[href="https://example.com/path"]').click();
  assert.equal(await page.evaluate(() => window.messages.find(m => m.type === 'link')?.url), 'https://example.com/path');
  await page.locator('a[data-footnote-ref]').click();
  assert.equal(await page.evaluate(() => window.messages.some(m => m.type === 'anchor' && m.offset >= 0)), true);
  assert.equal(page.url(), baseURL);
  await page.close();
});

test('emoji, reference links, table alignment, hard breaks and math fences', async () => {
  const page = await pageFor();
  await update(page, ':smile: :+1:\n\n[reference][target]  \nnext line\n\nhttps://example.org。\n\n| left | right |\n| :--- | ---: |\n| a | b |\n\n```math\n\\sum_{i=1}^{n} i\n```\n\n[target]: https://example.com');
  assert.equal(await page.locator('#content').textContent().then(s => s.includes('😄 👍')), true);
  assert.equal(await page.locator('a[href="https://example.com"]').textContent(), 'reference');
  assert.equal(await page.locator('a[href="https://example.org"]').textContent(), 'https://example.org');
  assert.equal(await page.locator('br').count(), 1);
  assert.equal(await page.locator('th').last().getAttribute('align'), 'right');
  assert.equal(await page.locator('.fenced-math .katex').count(), 1);
  await page.close();
});

test('compact layouts survive AX5 text; mobile and Mac controls retain comfortable targets', async () => {
  const page = await pageFor({ width: 320, height: 844 });
  const markdown = fixture + '\n\n```a-very-long-language-name-that-must-wrap-without-truncation\n' + 'wide source '.repeat(40) + '\n```';
  for (const options of [
    { fontSize: 17, headingSizes: [28, 22, 20], minimum: 44 },
    { fontSize: 53, headingSizes: [58, 56, 55], boldText: true, minimum: 44 },
    { fontSize: 13, platform: 'macOS', headingSizes: [22, 17, 15], minimum: 28 },
  ]) {
    await update(page, markdown, options);
    await page.waitForSelector('.mermaid-diagram svg');
    const layout = await page.evaluate(() => ({
      contentWidth: document.getElementById('content').scrollWidth,
      viewport: innerWidth, heading: getComputedStyle(document.querySelector('h1')).fontSize,
      targets: [...document.querySelectorAll('button')].map(n => {
        const r = n.getBoundingClientRect(); return [r.width, r.height];
      }),
      horizontalCode: [...document.querySelectorAll('pre')].some(n => n.scrollWidth > n.clientWidth),
    }));
    assert.equal(layout.contentWidth, layout.viewport, JSON.stringify(layout));
    assert.equal(layout.heading, `${options.headingSizes[0]}px`);
    assert.equal(layout.targets.every(([w, h]) => w >= options.minimum && h >= options.minimum), true, JSON.stringify(layout.targets));
    assert.equal(layout.horizontalCode, true);
    if (options.fontSize === 53) {
      const directory = fileURLToPath(new URL('../../build/MarkdownValidation/', import.meta.url));
      await page.screenshot({ path: `${directory}/iphone-ax5-bold.png`, fullPage: true });
    }
  }
  await page.close();
});

test('small text contrast meets AA on real surfaces, including native semantic palettes', async () => {
  const page = await pageFor();
  let nativePalettes = [];
  try { nativePalettes = JSON.parse(await readFile(new URL('../../build/MarkdownValidation/mac-native-palettes.json', import.meta.url))); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const metrics = [];
  for (const options of [{ dark: false }, { dark: true },
    { dark: false, increasedContrast: true }, { dark: true, increasedContrast: true },
    ...nativePalettes.map(options => ({ ...options, platform: 'macOS', fontSize: 13 }))]) {
    await update(page, fixture + '\n\n> [!WARNING]\n> Warning\n\n> [!IMPORTANT]\n> Important\n\n> [!CAUTION]\n> Caution', options);
    await page.waitForFunction(() => document.querySelector('.mermaid-diagram svg') || document.querySelector('.diagram-status')?.textContent.includes('暂时无法'));
    const diagramError = await page.locator('.diagram-status').count() ? await page.locator('.diagram-status').textContent() : null;
    assert.equal(diagramError, null, JSON.stringify({ options, diagramError }));
    const values = await page.evaluate(() => {
      const rgb = value => value.startsWith('#') ? value.slice(1).match(/.{2}/g).map(v => parseInt(v, 16)) : value.match(/[\d.]+/g).slice(0, 3).map(Number);
      const luminance = values => values.map(v => v / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
        .reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
      const ratio = (a, b) => (Math.max(luminance(a), luminance(b)) + .05) / (Math.min(luminance(a), luminance(b)) + .05);
      const rootStyle = getComputedStyle(document.documentElement);
      const surface = rgb(rootStyle.getPropertyValue('--surface').trim().replace(/^#fff$/, '#ffffff'));
      return [...document.querySelectorAll('p, a, button, .code-header, .hljs-keyword, .hljs-string, .hljs-built_in, .hljs-comment, .alert-title')]
        .map(n => ({
          selector: n.className || n.tagName, text: n.textContent.slice(0, 24),
          foreground: getComputedStyle(n).color,
          background: n.closest('.code-block') ? getComputedStyle(n.closest('.code-block')).backgroundColor : rootStyle.getPropertyValue('--surface').trim(),
          ratio: ratio(rgb(getComputedStyle(n).color), n.closest('.code-block') ? rgb(getComputedStyle(n.closest('.code-block')).backgroundColor) : surface),
        }));
    });
    const floor = options.increasedContrast ? 7 : 4.5;
    assert.equal(values.every(v => v.ratio >= floor), true, JSON.stringify({ options, failed: values.filter(v => v.ratio < floor) }));
    metrics.push({ options, minimum: Math.min(...values.map(v => v.ratio)), values });
  }
  const directory = fileURLToPath(new URL('../../build/MarkdownValidation/', import.meta.url));
  await import('node:fs/promises').then(fs => fs.writeFile(`${directory}/design-contrast.json`, JSON.stringify(metrics, null, 2)));
  await page.close();
});

test('keyboard copy announces its result, keeps focus through streaming, and preserves the action label', async () => {
  const page = await pageFor();
  const prefix = '```swift\nlet x = 1\n```\n\n';
  await update(page, prefix + 'Generating', { streaming: true, palette: { fg: '#171717', muted: '#555555' } });
  await page.locator('.copy-code').focus();
  assert.equal(await page.locator('.copy-code').evaluate(n => n.matches(':focus-visible')), true);
  await page.keyboard.press('Enter');
  const copy = await page.evaluate(() => window.messages.find(m => m.type === 'copy'));
  assert.equal(copy.text, 'let x = 1');
  await page.evaluate(id => window.copilotCopyResult(id, true), copy.id);
  await page.waitForFunction(() => document.getElementById('action-status').textContent.includes('已复制'));
  assert.equal(await page.locator('#action-status').getAttribute('aria-live'), 'polite');
  await page.evaluate(() => {
    window.appearanceMutations = 0;
    new MutationObserver(records => { window.appearanceMutations += records.length; })
      .observe(document.documentElement, { attributes: true });
  });
  await update(page, prefix + 'Generating more', { streaming: true, palette: { muted: '#555555', fg: '#171717' } });
  assert.equal(await page.evaluate(() => window.appearanceMutations), 0);
  assert.equal(await page.locator('.copy-code').evaluate(n => n === document.activeElement), true);
  assert.equal(await page.locator('#content').getAttribute('aria-live'), null);
  await page.waitForFunction(() => document.querySelector('.copy-code').textContent === '复制');
  assert.equal(await page.locator('.copy-code').getAttribute('aria-label'), '复制 swift 代码');
  await page.close();
});

test('system accessibility flags reach text and suppress animated content', async () => {
  const page = await pageFor();
  await update(page, fixture, { boldText: true, increasedContrast: true, reduceMotion: true });
  assert.equal(await page.locator('body').evaluate(n => getComputedStyle(n).fontWeight), '600');
  assert.equal(await page.locator('h1').evaluate(n => getComputedStyle(n).fontWeight), '700');
  assert.equal(await page.locator('.katex').first().evaluate(n => getComputedStyle(n).fontWeight), '700');
  const checkbox = await page.locator('input[type=checkbox]').first().evaluate(n => n.getBoundingClientRect().width);
  assert.equal(checkbox >= 14, true);
  await page.waitForSelector('.mermaid-diagram svg');
  assert.equal(await page.locator('.mermaid-diagram text').first().evaluate(n => getComputedStyle(n).fontWeight), '600');
  assert.equal(await page.locator('html').getAttribute('data-contrast'), 'more');
  assert.equal(await page.locator('button').first().evaluate(n => {
    n.style.animation = 'pulse 2s infinite'; return getComputedStyle(n).animationName;
  }), 'none');
  await page.close();
});
