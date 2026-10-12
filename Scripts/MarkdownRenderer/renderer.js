import { Marked } from 'marked';
import markedFootnote from 'marked-footnote';
import { gfmHeadingId } from 'marked-gfm-heading-id';
import DOMPurify from 'dompurify';
import hljs from 'highlight.js';
import katex from 'katex';
import { gemoji } from 'gemoji';

const root = document.getElementById('content');
const parser = new Marked({ gfm: true, breaks: false });
parser.use(markedFootnote({ description: '脚注', backRefLabel: '返回正文' }), gfmHeadingId());
const emoji = new Map(gemoji.flatMap(entry => entry.names.map(name => [name, entry.emoji])));
parser.use({ extensions: [{
  name: 'emoji', level: 'inline', start(src) { return src.indexOf(':'); },
  tokenizer(src) {
    const match = src.match(/^:([\w+-]+):/);
    if (match && emoji.has(match[1])) return { type: 'emoji', raw: match[0], text: emoji.get(match[1]) };
  },
  renderer(token) { return token.text; },
}] });
let current = { markdown: '', streaming: false, dark: false, fontSize: 17 };
let blocks = [];
let diagramQueue = Promise.resolve();
let diagramID = 0;
const diagrams = new Map();
let mermaidEngine;
const copyRequests = new Map();
let copyID = 0;
const imageRequests = new Map();
let imageID = 0;
let lastAppearance;

const escape = text => text.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const bridge = payload => window.webkit?.messageHandlers?.markdown?.postMessage(payload);

function closedFence(raw) {
  const open = raw.match(/^ {0,3}(`{3,}|~{3,})[^\n]*\n/);
  if (!open) return false;
  const fence = open[1];
  return new RegExp(`^ {0,3}${fence[0]}{${fence.length},}\\s*$`, 'm').test(raw.slice(open[0].length));
}

parser.use({ renderer: {
  link(token) {
    const suffix = token.autolink && token.href.match(/[。！？、，；：）】》」』]+$/)?.[0];
    if (!suffix) return false;
    const label = this.parser.parseInline(token.tokens);
    return `<a href="${escape(token.href.slice(0, -suffix.length))}">${label.slice(0, -suffix.length)}</a>${escape(suffix)}`;
  },
  code({ text, lang, raw }) {
    const language = (lang || '').trim().split(/\s+/)[0].toLowerCase();
    return `<pre data-code="true" data-language="${escape(language)}" data-closed="${closedFence(raw)}"><code>${escape(text)}</code></pre>`;
  },
  blockquote(token) {
    const match = token.text.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:\n|$)/i);
    if (!match) return `<blockquote>${this.parser.parse(token.tokens)}</blockquote>`;
    const kind = match[1].toLowerCase();
    const body = this.parser.parse(token.tokens).replace(/^<p>\[![A-Z]+\](?:\n|<br\s*\/?>\s*)?/i, '<p>');
    return `<aside class="markdown-alert ${kind}" role="note"><p class="alert-title">${match[1]}</p>${body}</aside>`;
  },
} });

// GitHub's inline and display math. Code tokens are handled before these extensions.
parser.use({ extensions: [{
  name: 'displayMath', level: 'block',
  start(src) { return src.indexOf('$$'); },
  tokenizer(src) {
    const match = src.match(/^\$\$\n?([\s\S]+?)\n?\$\$(?:\n|$)/);
    if (match) return { type: 'displayMath', raw: match[0], text: match[1] };
  },
  renderer(token) { return math(token.text, true); },
}, {
  name: 'inlineMath', level: 'inline',
  start(src) { return src.search(/\$(?:`|[^\s$\d])/); },
  tokenizer(src) {
    const match = src.match(/^\$`([^\n]+?)`\$/) || src.match(/^\$([^\s$](?:[^\n$]*?[^\s$])?)\$(?!\d)/);
    if (match) return { type: 'inlineMath', raw: match[0], text: match[1] };
  },
  renderer(token) { return math(token.text, false); },
}] });

function math(text, displayMode) {
  return `<span class="copilot-math" data-display="${displayMode}">${escape(text)}</span>`;
}

function sanitize(html) {
  return DOMPurify.sanitize(html, {
    // GFM and inert HTML, including details/summary and accessible KaTeX MathML.
    USE_PROFILES: { html: true, mathMl: true }, ADD_TAGS: ['input'], ADD_ATTR: ['target'],
    FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'form', 'video', 'audio'],
    FORBID_ATTR: ['style', 'srcset'],
    ALLOW_DATA_ATTR: true,
  });
}

function copyButton(text, title = '复制代码') {
  const button = document.createElement('button');
  button.type = 'button'; button.className = 'copy-code';
  button.textContent = '复制'; button.setAttribute('aria-label', title);
  button.title = title; button.dataset.copyLabel = title;
  button.addEventListener('click', () => {
    const id = ++copyID;
    copyRequests.set(id, button);
    bridge({ type: 'copy', id, text });
  });
  return button;
}

window.copilotCopyResult = (id, succeeded) => {
  const button = copyRequests.get(id);
  copyRequests.delete(id);
  if (!button?.isConnected) return;
  button.textContent = succeeded ? '已复制' : '复制失败';
  button.setAttribute('aria-label', succeeded ? `${button.dataset.copyLabel.replace(/^复制\s*/, '')}已复制` : '复制失败，请重试');
  const status = document.getElementById('action-status');
  status.textContent = '';
  setTimeout(() => { status.textContent = succeeded ? `${button.dataset.copyLabel}：已复制` : '复制失败，请重试'; }, 20);
  const revision = String(id);
  button.dataset.copyRevision = revision;
  setTimeout(() => {
    if (button.isConnected && button.dataset.copyRevision === revision) {
      button.textContent = '复制'; button.setAttribute('aria-label', button.dataset.copyLabel);
    }
  }, 1500);
};

window.copilotImageResult = (id, dataURL) => {
  const request = imageRequests.get(id);
  imageRequests.delete(id);
  if (!request?.holder.isConnected) return;
  const { holder, button, image } = request;
  if (typeof dataURL === 'string' && /^data:image\/(png|jpeg|gif|webp);base64,/i.test(dataURL)) {
    image.addEventListener('load', reportHeight, { once: true });
    image.addEventListener('error', () => {
      button.disabled = false; button.textContent = `重新加载图片：${image.alt}`;
      image.replaceWith(holder); reportHeight();
    }, { once: true });
    image.src = dataURL; holder.replaceWith(image);
  } else { button.disabled = false; button.textContent = `重新加载图片：${image.alt}`; }
};

function decorate(block, options) {
  for (const formula of block.querySelectorAll('.copilot-math')) {
    try {
      const html = katex.renderToString(formula.textContent, {
        displayMode: formula.dataset.display === 'true', throwOnError: false,
        trust: false, strict: 'ignore', maxExpand: 1000,
      });
      formula.innerHTML = DOMPurify.sanitize(html, { USE_PROFILES: { html: true, mathMl: true, svg: true } });
    } catch { /* Keep the readable formula source. */ }
  }
  // Prevent remote image loading until the user explicitly requests it. No tracking
  // requests are made merely by reading a model reply; data images remain inline.
  for (const image of block.querySelectorAll('img')) {
    const src = image.getAttribute('src') || '';
    if (/^data:image\/(png|jpeg|gif|webp);base64,/i.test(src)) continue;
    const holder = document.createElement('span'); holder.className = 'image-placeholder';
    const alt = image.getAttribute('alt') || '图片';
    const button = document.createElement('button'); button.type = 'button';
    button.textContent = `加载图片：${alt}`;
    if (/^https?:\/\//i.test(src)) {
      button.addEventListener('click', () => {
        const id = ++imageID;
        imageRequests.set(id, { holder, button, image });
        button.disabled = true; button.textContent = '正在加载图片…';
        bridge({ type: 'image', id, url: src });
      });
      holder.append(button);
    } else holder.textContent = alt;
    image.removeAttribute('src'); image.alt = alt; image.loading = 'lazy';
    image.replaceWith(holder);
  }
  for (const input of block.querySelectorAll('input')) {
    if (input.type !== 'checkbox') { input.remove(); continue; }
    input.disabled = true; input.setAttribute('aria-label', input.checked ? '已完成' : '未完成');
  }
  for (const table of block.querySelectorAll('table')) {
    const wrapper = document.createElement('div'); wrapper.className = 'table-scroll';
    wrapper.tabIndex = 0; wrapper.setAttribute('aria-label', '表格，可横向滚动');
    table.replaceWith(wrapper); wrapper.append(table);
  }
  for (const pre of block.querySelectorAll('pre[data-code]')) {
    const code = pre.querySelector('code');
    if (!code) continue;
    const text = code.textContent;
    const language = pre.dataset.language || '';
    const container = document.createElement('section'); container.className = 'code-block';
    const header = document.createElement('div'); header.className = 'code-header';
    const label = document.createElement('span'); label.textContent = language || '纯文本';
    header.append(label, copyButton(text, language === 'mermaid' ? '复制图表源码' : language === 'math' ? '复制公式源码' : `复制 ${language || '纯文本'} 代码`));
    pre.replaceWith(container); container.append(header, pre);
    pre.tabIndex = 0; pre.setAttribute('aria-label', `${language || '纯文本'}代码，可横向滚动`);
    if (language === 'mermaid') {
      const complete = !options.streaming || pre.dataset.closed === 'true';
      const status = document.createElement('p'); status.className = 'diagram-status';
      status.textContent = complete ? '正在绘制图表…' : '图表生成中…';
      status.setAttribute('role', 'status'); container.append(status);
      if (complete) drawDiagram(container, pre, status, text, options);
    } else if (language === 'math') {
      try {
        const formula = document.createElement('div'); formula.className = 'fenced-math';
        formula.innerHTML = DOMPurify.sanitize(katex.renderToString(text, {
          displayMode: true, throwOnError: false, trust: false, strict: 'ignore', maxExpand: 1000,
        }), { USE_PROFILES: { html: true, mathMl: true, svg: true } });
        const details = document.createElement('details'); const summary = document.createElement('summary');
        summary.textContent = '公式源码'; details.append(summary, pre); container.append(formula, details);
      } catch { /* The original formula remains readable and copyable. */ }
    } else if (language && hljs.getLanguage(language)) {
      // Explicit languages only: avoid unstable auto-detection on partial code.
      code.innerHTML = hljs.highlight(text, { language, ignoreIllegals: true }).value;
      code.classList.add('hljs');
    }
  }
  for (const formula of block.querySelectorAll('.katex-display')) {
    formula.tabIndex = 0; formula.setAttribute('role', 'group');
    formula.setAttribute('aria-label', '公式，可横向滚动');
  }
}

function drawDiagram(container, pre, status, text, options) {
  const colors = appearanceColors();
  const key = `${options.dark}:${options.fontSize}:${options.boldText}:${JSON.stringify(colors)}:${text}`;
  const show = svg => {
    if (!container.isConnected) return;
    const diagram = document.createElement('div'); diagram.className = 'mermaid-diagram';
    diagram.tabIndex = 0; diagram.setAttribute('aria-label', 'Mermaid 图表，可横向滚动');
    diagram.innerHTML = DOMPurify.sanitize(svg, { USE_PROFILES: { svg: true, svgFilters: true }, FORBID_TAGS: ['foreignObject'] });
    const graphic = diagram.querySelector('svg');
    if (graphic) {
      if (graphic.viewBox.baseVal.width > 0) graphic.setAttribute('width', String(Math.ceil(graphic.viewBox.baseVal.width)));
      // A group keeps individual SVG text nodes traversable in VoiceOver.
      graphic.setAttribute('role', 'group');
      if (!graphic.hasAttribute('aria-labelledby')) graphic.setAttribute('aria-label', '生成的图表，可展开图表源码阅读文字');
      for (const shape of graphic.querySelectorAll('defs, path, rect, circle, ellipse, polygon, polyline, line, use, image')) {
        if (!shape.hasAttribute('aria-label') && !shape.hasAttribute('aria-labelledby')) shape.setAttribute('aria-hidden', 'true');
      }
      // Inline Mermaid styles otherwise ignore the system Bold Text setting.
      if (options.boldText) for (const label of graphic.querySelectorAll('text')) label.style.fontWeight = '600';
    }
    for (const link of diagram.querySelectorAll('[href],[xlink\\:href]')) {
      for (const attr of ['href', 'xlink:href']) if (link.hasAttribute(attr) && !link.getAttribute(attr).startsWith('#')) link.removeAttribute(attr);
    }
    status.replaceWith(diagram);
    const details = document.createElement('details'); const summary = document.createElement('summary');
    summary.textContent = '图表源码'; details.append(summary, pre); container.append(details);
    reportHeight();
  };
  diagramQueue = diagramQueue.then(async () => {
    if (!container.isConnected) return;
    if (diagrams.has(key)) { show(diagrams.get(key)); return; }
    try {
      const mermaid = await loadMermaid();
      if (!container.isConnected) return;
      mermaid.initialize({
        startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
        theme: 'base', fontFamily: '-apple-system, sans-serif',
        fontSize: options.fontSize, themeVariables: {
          darkMode: !!options.dark, fontSize: `${options.fontSize}px`, background: colors.surface,
          primaryColor: colors.panel, secondaryColor: colors.panel, tertiaryColor: colors.surface,
          primaryTextColor: colors.fg, secondaryTextColor: colors.fg, tertiaryTextColor: colors.fg,
          primaryBorderColor: colors.muted, secondaryBorderColor: colors.muted, tertiaryBorderColor: colors.muted,
          lineColor: colors.muted, textColor: colors.fg, nodeTextColor: colors.fg,
          actorBkg: colors.panel, actorBorder: colors.muted, actorTextColor: colors.fg,
          signalColor: colors.fg, signalTextColor: colors.fg,
          labelBoxBkgColor: colors.panel, labelBoxBorderColor: colors.muted, labelTextColor: colors.fg,
          noteBkgColor: colors.panel, noteBorderColor: colors.muted, noteTextColor: colors.fg,
        },
        htmlLabels: false, flowchart: { htmlLabels: false }, maxTextSize: 100000,
        secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'suppressErrorRendering', 'htmlLabels', 'theme', 'themeVariables', 'themeCSS', 'fontFamily', 'flowchart'],
      });
      const { svg } = await mermaid.render(`copilot-diagram-${++diagramID}`, text);
      diagrams.set(key, svg);
      if (diagrams.size > 32) diagrams.delete(diagrams.keys().next().value);
      show(svg);
    } catch {
      if (container.isConnected) { status.textContent = '暂时无法绘制图表，请检查下方源码。'; reportHeight(); }
    }
  });
}

function loadMermaid() {
  // Ordinary replies never load the larger diagram engine into their JS context.
  mermaidEngine ??= new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL('mermaid.js', document.baseURI).href;
    script.onload = () => window.copilotMermaid ? resolve(window.copilotMermaid) : reject(new Error('Mermaid unavailable'));
    script.onerror = () => reject(new Error('Mermaid unavailable'));
    document.head.append(script);
  });
  return mermaidEngine;
}

// Reuse unchanged block DOM so code scroll positions, details, focus, and text
// selection survive streaming. Reference definitions are resolved over the full text.
function render(options) {
  current = options;
  applyAppearance(options);
  const html = parser.parse(options.markdown);
  const template = document.createElement('template');
  template.innerHTML = sanitize(html);
  const next = [];
  const appearance = JSON.stringify([options.dark, options.fontSize, options.boldText, appearanceColors()]);
  let index = 0;
  for (const child of [...template.content.childNodes]) {
    if (child.nodeType === Node.TEXT_NODE && !child.textContent.trim()) continue;
    const source = child.nodeType === Node.ELEMENT_NODE ? child.outerHTML : escape(child.textContent);
    const previous = blocks[index];
    const hasDiagram = /data-language="mermaid"/.test(source);
    // The final streaming state controls rendering of an unclosed Mermaid fence.
    const key = source + (hasDiagram ? `:${appearance}:${options.streaming}` : '');
    if (previous?.key === key) next.push(previous);
    else {
      const node = document.createElement('div'); node.className = 'markdown-block'; node.append(child);
      next.push({ key, node, decorate: true });
    }
    index++;
  }
  // Replace only changed blocks. Do not detach the stable prefix.
  for (const block of next) if (block.decorate) { decorate(block.node, options); delete block.decorate; }
  next.forEach(({ node }, i) => {
    if (root.children[i] !== node) root.insertBefore(node, root.children[i] || null);
  });
  while (root.children.length > next.length) root.lastElementChild.remove();
  blocks = next;
  for (const [id, button] of copyRequests) if (!button.isConnected) copyRequests.delete(id);
  for (const [id, request] of imageRequests) if (!request.holder.isConnected) imageRequests.delete(id);
  reportHeight();
}

function appearanceColors() {
  const style = getComputedStyle(document.documentElement);
  return Object.fromEntries(['surface', 'fg', 'muted', 'panel'].map(key => [key, style.getPropertyValue(`--${key}`).trim()]));
}

// Native semantic colors can be translucent, or tuned for larger control text.
// Preserve their hue while meeting the stricter small-text floor on both the
// page and code surface; syntax colors are evaluated on their actual surface.
function accessibleColor(color, backgrounds, minimum, dark) {
  const rgb = hex => {
    const value = hex.length === 4 ? hex.slice(1).split('').map(c => c + c).join('') : hex.slice(1);
    return value.match(/.{2}/g).map(c => parseInt(c, 16) / 255);
  };
  const luminance = values => values.map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
    .reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
  const bg = backgrounds.map(rgb).map(luminance);
  const channels = rgb(color);
  for (let amount = 0; amount <= 100; amount++) {
    const next = channels.map(v => Math.round((v + ((dark ? 1 : 0) - v) * amount / 100) * 255));
    const value = luminance(next.map(v => v / 255));
    if (bg.every(b => (Math.max(value, b) + .05) / (Math.min(value, b) + .05) >= minimum)) {
      return '#' + next.map(v => v.toString(16).padStart(2, '0')).join('');
    }
  }
  return dark ? '#ffffff' : '#000000';
}

function applyAppearance(options) {
  const highContrast = options.increasedContrast || matchMedia('(prefers-contrast: more)').matches;
  const palette = options.palette && Object.keys(options.palette).sort().map(key => [key, options.palette[key]]);
  const signature = JSON.stringify([options.dark, options.fontSize, options.platform, options.boldText,
    highContrast, options.reduceMotion, options.headingSizes, palette]);
  if (signature === lastAppearance) return;
  lastAppearance = signature;
  const element = document.documentElement;
  element.dataset.theme = options.dark ? 'dark' : 'light';
  element.dataset.platform = options.platform || 'iOS';
  element.dataset.bold = String(!!options.boldText);
  element.dataset.contrast = highContrast ? 'more' : 'normal';
  element.dataset.reduceMotion = String(!!options.reduceMotion);
  element.style.setProperty('--body-size', `${options.fontSize}px`);
  for (let i = 0; i < 3; i++) {
    const size = options.headingSizes?.[i];
    if (Number.isFinite(size) && size > 0) element.style.setProperty(`--heading-${i + 1}`, `${size}px`);
    else element.style.removeProperty(`--heading-${i + 1}`);
  }
  const roles = ['surface', 'fg', 'muted', 'panel', 'line', 'accent', 'focus', 'keyword', 'string', 'title', 'number', 'meta', 'tip', 'important', 'warning', 'caution'];
  for (const role of roles) {
    element.style.removeProperty(`--${role}`);
    const value = options.palette?.[role];
    if (/^#[0-9a-f]{6}$/i.test(value || '')) element.style.setProperty(`--${role}`, value);
  }
  const style = getComputedStyle(element);
  const value = role => style.getPropertyValue(`--${role}`).trim();
  // Normalize the short CSS fallback surface before calculating luminance.
  const surface = value('surface').length === 4 ? '#' + value('surface').slice(1).split('').map(c => c + c).join('') : value('surface');
  const panel = value('panel');
  for (const role of ['fg', 'muted', 'accent', 'focus', 'keyword', 'string', 'title', 'number', 'meta', 'tip', 'important', 'warning', 'caution', ...(highContrast ? ['line'] : [])]) {
    const backgrounds = ['keyword', 'string', 'title', 'number', 'meta'].includes(role) ? [panel] : [surface, panel];
    element.style.setProperty(`--${role}`, accessibleColor(value(role), backgrounds, ['line', 'focus'].includes(role) ? 3 : highContrast ? 7 : 4.5, !!options.dark));
  }
}

let frame = null;
let pending = null;
let renderRevision = 0;
window.copilotUpdate = options => {
  pending = options;
  if (frame !== null) return;
  // WebKit suspends requestAnimationFrame in an offscreen/native zero-height
  // view. A timer lets the first layout report its height to SwiftUI reliably.
  frame = setTimeout(() => {
    frame = null;
    try { render(pending); }
    catch {
      root.textContent = pending.markdown; blocks = []; reportHeight();
    }
    root.dataset.renderRevision = String(++renderRevision);
  }, 16);
};

let lastHeight = 0;
function reportHeight() {
  const height = Math.max(1, Math.ceil(root.getBoundingClientRect().height));
  if (height !== lastHeight) { lastHeight = height; bridge({ type: 'height', height }); }
}
new ResizeObserver(reportHeight).observe(root);
document.fonts.ready.then(reportHeight);
document.addEventListener('toggle', reportHeight, true);
document.addEventListener('click', event => {
  const link = event.target.closest('a');
  if (!link) return;
  event.preventDefault();
  const href = link.getAttribute('href') || '';
  if (href.startsWith('#')) {
    const target = document.getElementById(decodeURIComponent(href.slice(1)));
    if (target) bridge({ type: 'anchor', offset: target.getBoundingClientRect().top + window.scrollY });
  } else if (/^(https?:|mailto:)/i.test(href)) bridge({ type: 'link', url: href });
});
bridge({ type: 'ready' });
