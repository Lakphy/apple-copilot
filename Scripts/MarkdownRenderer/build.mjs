import { build } from 'esbuild';
import { readFile, writeFile, cp, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const output = fileURLToPath(new URL('../../Sources/CopilotUI/Resources/Markdown/', import.meta.url));
for (const name of ['renderer', 'mermaid']) {
  await build({
    entryPoints: [fileURLToPath(new URL(`${name}.js`, import.meta.url))],
    outfile: `${output}${name}.js`, bundle: true, format: 'iife',
    target: 'safari18', minify: true, legalComments: 'eof',
  });
}
// Runtime resources are committed; Node/npm are only needed to rebuild or test.
await cp(new URL('node_modules/katex/dist/katex.min.css', import.meta.url), `${output}katex.css`);
await cp(new URL('node_modules/katex/dist/fonts', import.meta.url), `${output}fonts`, { recursive: true });
const lock = JSON.parse(await readFile(new URL('package-lock.json', import.meta.url), 'utf8'));
const packages = Object.entries(lock.packages).filter(([path, pkg]) => path && !pkg.dev).map(([path]) => path);
const notices = [];
for (const path of packages) {
  const root = new URL(`${path}/`, import.meta.url);
  const pkg = JSON.parse(await readFile(new URL('package.json', root), 'utf8'));
  const files = (await readdir(root)).filter(name => /^(licen[sc]e|copying|notice)(\.|$)/i.test(name));
  const licenses = await Promise.all(files.map(name => readFile(new URL(name, root), 'utf8').catch(() => '')));
  notices.push(`${pkg.name} ${pkg.version} (${pkg.license || 'see upstream license'})\n${licenses.join('\n')}`);
}
await writeFile(`${output}THIRD_PARTY_LICENSES.txt`, notices.join('\n\n--------------------\n\n'));
