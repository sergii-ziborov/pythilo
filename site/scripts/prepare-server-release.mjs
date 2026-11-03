// Collects a standalone build into site/release/, which hetzner/deploy.sh ships.
// Run `pnpm build` first. Usage: node scripts/prepare-server-release.mjs [destination]
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = join(dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(readFileSync(join(site, 'public', 'pyodide', 'pyodide-lock.json'), 'utf8'));
for (const item of Object.values(lock.packages)) {
  const file = join(site, 'public', 'pyodide', item.file_name);
  if (!existsSync(file) || createHash('sha256').update(readFileSync(file)).digest('hex') !== item.sha256) throw new Error(`${item.file_name} is missing or changed. Run pnpm build again.`);
}
if (!existsSync(join(site, '.next', 'standalone', 'server.js'))) throw new Error('Run pnpm build first.');
const destination = resolve(process.argv[2] || join(site, 'release'));
rmSync(destination, { recursive: true, force: true });
mkdirSync(destination, { recursive: true });
// pnpm links inside the traced tree must stay relative when shipped to Linux.
cpSync(join(site, '.next', 'standalone'), join(destination, 'standalone'), { recursive: true, verbatimSymlinks: true });
cpSync(join(site, '.next', 'static'), join(destination, 'static'), { recursive: true });
cpSync(join(site, 'public'), join(destination, 'public'), { recursive: true });
console.log('Prepared standalone server release:', destination);
