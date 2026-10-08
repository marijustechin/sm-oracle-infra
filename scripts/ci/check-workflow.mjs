#!/usr/bin/env node
// check-workflow.mjs — mechanical workflow checks for the sokoladas workspace.
// No dependencies: Node builtins only.
//
// Three checks (structure only — not the factual accuracy of state reconciliation):
//   1. commits — a task ID is required in the subject of new human-authored commits.
//   2. tasks   — new/changed tasks/done/*.md carry the required sections
//                (including acceptance/verification and state reconciliation).
//   3. links   — local Markdown links and images resolve, including heading anchors.
//
// Policy (authoritative wording lives in the repositories' AGENTS.md and
// docs/task-workflow.md):
//
//   Accepted commit subjects (deterministic; no arbitrary substring match):
//     <TASK-ID>: <summary>                                  (prefix style)
//     <type>(<scope>): <summary> (<TASK-ID>)                (Conventional style)
//     <type>: <summary> (<TASK-ID>)
//   TASK-ID = [A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+  -> A-013, D-007, BACKUP-001,
//   CATALOG-002, ROOT-001, HARNESS-CI-001 (multi-part uppercase prefixes).
//
//   Exemptions (exact):
//     - merge commits (2+ parents);
//     - revert commits whose subject starts with `Revert "`;
//     - commits whose author OR committer identity is a bot (`*[bot]` name, or an
//       email containing `[bot]@` or `github-actions@`). A subject that merely
//       *claims* to be automated is NOT exempt.
//
//   Range: only commits introduced by the checked range are validated. The range
//   is never the whole history. If the baseline is unavailable (shallow clone,
//   new branch, zero SHA), the check validates the tip commit and reports that
//   the full range was unavailable — it never silently passes an empty range.
//
//   Links: Markdown inline/reference links and images; fenced code and inline
//   code are ignored; external URLs are skipped (no network). Local targets are
//   resolved under the repository, or under the parent workspace for explicit
//   cross-repository links. Cross-repository targets are validated only when the
//   target repository is present; otherwise they are reported as unchecked.
//   Paths outside the workspace are refused. Anchors follow the GitHub heading
//   slug algorithm (lowercase, punctuation removed, spaces -> hyphens, duplicates
//   suffixed -1, -2, ...). Parser scope excludes HTML anchors.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested)
// ---------------------------------------------------------------------------

export const TASK_ID_SRC = '[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+';
const PREFIX_STYLE = new RegExp(`^(${TASK_ID_SRC}):\\s+\\S`);
const TYPE_STYLE = new RegExp(
  `^[a-z][a-z0-9-]*(?:\\([A-Za-z0-9._/-]+\\))?!?:\\s+.+\\s\\(${TASK_ID_SRC}\\)$`,
);

export function isBotIdentity(name, email) {
  const n = (name || '').toLowerCase();
  const e = (email || '').toLowerCase();
  if (n.endsWith('[bot]')) return true;
  if (/\[bot\]@/.test(e)) return true;
  if (/^github-actions@/.test(e)) return true;
  return false;
}

// commitStatus -> { ok, format?, exempt? }
export function commitStatus({
  subject,
  authorName,
  authorEmail,
  committerName,
  committerEmail,
  parents,
}) {
  const parentList = (parents || '').trim().split(/\s+/).filter(Boolean);
  if (parentList.length > 1) return { ok: true, exempt: 'merge' };
  if (/^Revert "/.test(subject || '')) return { ok: true, exempt: 'revert' };
  if (isBotIdentity(authorName, authorEmail) || isBotIdentity(committerName, committerEmail)) {
    return { ok: true, exempt: 'bot' };
  }
  if (PREFIX_STYLE.test(subject || '')) return { ok: true, format: 'prefix' };
  if (TYPE_STYLE.test(subject || '')) return { ok: true, format: 'type' };
  return { ok: false };
}

export function parseSections(markdown) {
  const sections = new Map();
  let current = null;
  for (const line of markdown.split(/\r?\n/)) {
    const m = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
    if (m) {
      current = m[2].trim();
      if (!sections.has(current)) sections.set(current, []);
    } else if (current) {
      sections.get(current).push(line);
    }
  }
  return sections;
}

// missingSections -> [] when all required headings exist and have a non-empty body.
export function missingSections(markdown, required) {
  const sections = parseSections(markdown);
  const missing = [];
  for (const name of required) {
    if (!sections.has(name)) {
      missing.push(name);
      continue;
    }
    const body = sections.get(name).join('\n').trim();
    if (body.length === 0) missing.push(`${name} (empty)`);
  }
  return missing;
}

export function slugifyHeading(text) {
  return text
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_`~]/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s_-]/gu, '')
    .trim()
    .replace(/\s/g, '-');
}

export function collectAnchors(markdown) {
  const anchors = new Set();
  const counts = new Map();
  let inFence = false;
  for (const line of markdown.split(/\r?\n/)) {
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    const base = slugifyHeading(m[2]);
    if (!base) continue;
    const n = counts.get(base) || 0;
    counts.set(base, n + 1);
    anchors.add(n === 0 ? base : `${base}-${n}`);
  }
  return anchors;
}

// extractLinks -> [{ target, line }]; ignores fenced code and inline code.
export function extractLinks(markdown) {
  const lines = markdown.split(/\r?\n/);
  const defs = new Map();
  let inFence = false;
  for (const line of lines) {
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const def = /^\s*\[([^\]]+)\]:\s*(\S+)/.exec(line);
    if (def) defs.set(def[1].trim().toLowerCase(), def[2]);
  }

  const links = [];
  inFence = false;
  lines.forEach((rawLine, index) => {
    if (/^\s*(```|~~~)/.test(rawLine)) {
      inFence = !inFence;
      return;
    }
    if (inFence) return;
    const line = rawLine.replace(/`+[^`]*`+/g, '');
    const inline = /!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
    let m;
    while ((m = inline.exec(line)) !== null) links.push({ target: m[1], line: index + 1 });
    const reference = /\[[^\]]+\]\[([^\]]*)\]/g;
    while ((m = reference.exec(line)) !== null) {
      const key = m[1].trim().toLowerCase();
      const target = key === '' ? undefined : defs.get(key);
      if (target) links.push({ target, line: index + 1 });
    }
  });
  return links;
}

const EXTERNAL = /^[a-z][a-z0-9+.-]*:/i;

function isInside(root, target) {
  const rel = relative(root, target);
  return rel === '' || (!rel.startsWith('..') && !isAbsolute(rel));
}

// resolveLink -> { status, detail }
// status: ok | missing | anchor-missing | unchecked | unsafe
export function resolveLink(
  rawTarget,
  fileAbs,
  repoRoot,
  workspaceRoot,
  { readFile = readFileSync } = {},
) {
  let target = rawTarget;
  if (EXTERNAL.test(target) || target.startsWith('//')) return { status: 'ok', detail: 'external' };
  target = target.replace(/^<|>$/g, '');
  let decoded;
  try {
    decoded = decodeURIComponent(target);
  } catch {
    decoded = target;
  }
  const hashAt = decoded.indexOf('#');
  const pathPart = hashAt === -1 ? decoded : decoded.slice(0, hashAt);
  const fragment = hashAt === -1 ? '' : decoded.slice(hashAt + 1);

  const resolved = pathPart === '' ? fileAbs : resolve(dirname(fileAbs), pathPart);
  if (!isInside(workspaceRoot, resolved)) return { status: 'unsafe', detail: resolved };

  if (!isInside(repoRoot, resolved)) {
    // Cross-repository link: available only when the sibling root exists.
    const relToWorkspace = relative(workspaceRoot, resolved);
    const firstSegment = relToWorkspace.split(sep)[0];
    if (!firstSegment || !existsSync(join(workspaceRoot, firstSegment))) {
      return { status: 'unchecked', detail: resolved };
    }
  }

  if (!existsSync(resolved)) return { status: 'missing', detail: resolved };
  if (fragment && statSync(resolved).isFile() && resolved.endsWith('.md')) {
    let content;
    try {
      content = readFile(resolved, 'utf8');
    } catch {
      return { status: 'unchecked', detail: resolved };
    }
    const anchors = collectAnchors(content);
    if (!anchors.has(fragment))
      return { status: 'anchor-missing', detail: `${resolved}#${fragment}` };
  }
  return { status: 'ok' };
}

export function listMarkdownFiles(
  root,
  { skipDirs = ['node_modules', '.git', '.next', 'dist', 'coverage'] } = {},
) {
  const out = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        if (skipDirs.includes(entry.name)) continue;
        walk(join(dir, entry.name));
      } else if (entry.isFile() && entry.name.endsWith('.md')) {
        out.push(join(dir, entry.name));
      }
    }
  };
  walk(root);
  return out;
}

export const DEFAULT_REQUIRED_SECTIONS = [
  'Status',
  'Objective',
  'Context',
  'Scope',
  'Acceptance Criteria',
  'Required Verification',
  'Implementation Result',
  'Verification Result',
  'State Reconciliation',
  'Completion',
];

// ---------------------------------------------------------------------------
// Git + CLI
// ---------------------------------------------------------------------------

function git(root, args) {
  return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
}

function tryGit(root, args) {
  try {
    return execFileSync('git', ['-C', root, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return null;
  }
}

function resolveRange(root, base, head) {
  const h = head || tryGit(root, ['rev-parse', 'HEAD']);
  if (!h) throw new Error('cannot resolve HEAD');
  if (base === undefined || base === null || base === '') {
    // No baseline supplied (local invocation): tip commit + working tree.
    return { mode: 'local', base: null, head: h };
  }
  if (/^0+$/.test(String(base))) {
    // New branch / first push: the full new-branch range is unavailable, so define
    // an explicit, bounded fallback (tip commit only) instead of the whole history.
    return { mode: 'tip', base: null, head: h, note: 'zero baseline (new branch/first push)' };
  }
  if (tryGit(root, ['rev-parse', '--verify', `${base}^{commit}`]) === null) {
    // An explicitly supplied, non-zero baseline that cannot be resolved is a hard
    // failure — never a silent fallback to the tip.
    throw new Error(`explicit baseline is unavailable in this clone: ${base}`);
  }
  return { mode: 'range', base, head: h };
}

function commitRecords(root, range) {
  const fmt = '%H%x1f%s%x1f%an%x1f%ae%x1f%cn%x1f%ce%x1f%P';
  const out = git(
    root,
    range.mode === 'range'
      ? ['log', `--format=${fmt}`, `${range.base}..${range.head}`]
      : ['log', `--format=${fmt}`, '-n', '1', range.head],
  );
  if (!out) return [];
  return out.split('\n').map((line) => {
    const [sha, subject, authorName, authorEmail, committerName, committerEmail, parents] =
      line.split('\x1f');
    return { sha, subject, authorName, authorEmail, committerName, committerEmail, parents };
  });
}

function workingTreeFiles(root) {
  const tracked = tryGit(root, ['diff', '--name-only', 'HEAD']) || '';
  const untracked = tryGit(root, ['ls-files', '--others', '--exclude-standard']) || '';
  return [...new Set([...tracked.split('\n'), ...untracked.split('\n')].filter(Boolean))];
}

function changedFiles(root, range, filter = 'ACM') {
  if (range.mode === 'range') {
    const out = git(root, [
      'diff',
      '--name-only',
      `--diff-filter=${filter}`,
      `${range.base}..${range.head}`,
    ]);
    return out ? out.split('\n').filter(Boolean) : [];
  }
  const out =
    tryGit(root, ['diff-tree', '--no-commit-id', '--name-only', '-r', '--root', range.head]) || '';
  const tip = out.split('\n').filter(Boolean);
  if (range.mode === 'local') return [...new Set([...tip, ...workingTreeFiles(root)])];
  return tip;
}

function rangeNotice(scope, range) {
  if (range.mode === 'range') return;
  if (range.mode === 'tip') {
    console.log(
      `[${scope}] ${range.note}; checking the tip commit only (${range.head.slice(0, 12)}).`,
    );
  } else {
    console.log(`[${scope}] no --base supplied; checking the tip commit and working tree only.`);
  }
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      if (v !== undefined) args[k] = v;
      else if (argv[i + 1] && !argv[i + 1].startsWith('--')) args[k] = argv[++i];
      else args[k] = true;
    } else args._.push(a);
  }
  return args;
}

function cmdCommits(root, args) {
  let range;
  try {
    range = resolveRange(root, args.base, args.head);
  } catch (error) {
    console.error(`[commits] ${error.message}`);
    return 1;
  }
  rangeNotice('commits', range);
  const commits = commitRecords(root, range);
  if (commits.length === 0) {
    console.log('[commits] no commits in the checked range; nothing to validate.');
    return 0;
  }
  const failures = [];
  for (const c of commits) {
    const status = commitStatus(c);
    if (!status.ok) failures.push(c);
  }
  for (const c of commits) {
    const status = commitStatus(c);
    const tag = status.ok
      ? `ok${status.exempt ? ` (${status.exempt})` : ` (${status.format})`}`
      : 'FAIL';
    console.log(`[commits] ${tag} ${c.sha.slice(0, 12)} ${c.subject}`);
  }
  if (failures.length) {
    console.error(
      `\n[commits] ${failures.length} commit(s) lack a task ID. Accepted: '<TASK-ID>: …' or '<type>(<scope>): … (<TASK-ID>)'.`,
    );
    return 1;
  }
  return 0;
}

function cmdTasks(root, args) {
  const doneDir = args['done-dir'] || join(root, 'tasks', 'done');
  if (!existsSync(doneDir)) {
    console.log(
      `[tasks] ${relative(root, doneDir) || doneDir} does not exist; not applicable (no task-file directory).`,
    );
    return 0;
  }
  const required = args.require
    ? String(args.require)
        .split(',')
        .map((s) => s.trim())
    : DEFAULT_REQUIRED_SECTIONS;
  let files;
  if (args.all) {
    files = listMarkdownFiles(doneDir);
  } else {
    let range;
    try {
      range = resolveRange(root, args.base, args.head);
    } catch (error) {
      console.error(`[tasks] ${error.message}`);
      return 1;
    }
    rangeNotice('tasks', range);
    const rel = relative(root, doneDir).split(sep).join('/');
    files = changedFiles(root, range)
      .filter((f) => f === `${rel}/` || f.startsWith(`${rel}/`) || f === rel)
      .map((f) => join(root, f))
      .filter((f) => f.endsWith('.md') && existsSync(f));
  }
  const failures = [];
  for (const file of files) {
    const missing = missingSections(readFileSync(file, 'utf8'), required);
    if (missing.length) failures.push({ file, missing });
  }
  if (args.all && !args.strict) {
    // Full-history mode is informational: pre-existing records may predate a rule.
    for (const f of failures)
      console.log(
        `[tasks] (pre-existing) ${relative(root, f.file)}: missing ${f.missing.join(', ')}`,
      );
    console.log(
      `[tasks] scanned ${files.length} task record(s); ${failures.length} informational finding(s).`,
    );
    return 0;
  }
  for (const f of failures)
    console.error(`[tasks] FAIL ${relative(root, f.file)}: missing ${f.missing.join(', ')}`);
  if (failures.length) return 1;
  console.log(`[tasks] ${files.length} changed task record(s) OK.`);
  return 0;
}

function cmdLinks(root, args) {
  const workspaceRoot = args.workspace ? resolve(args.workspace) : resolve(root, '..');
  let files;
  let informational = false;
  if (args.all) {
    files = listMarkdownFiles(root);
    informational = !args.strict;
    if (informational)
      console.log('[links] full-repository scan (report-only; use --strict to fail).');
  } else {
    let range;
    try {
      range = resolveRange(root, args.base, args.head);
    } catch (error) {
      console.error(`[links] ${error.message}`);
      return 1;
    }
    rangeNotice('links', range);
    files = changedFiles(root, range)
      .map((f) => join(root, f))
      .filter((f) => f.endsWith('.md') && existsSync(f));
  }
  const broken = [];
  const unchecked = [];
  for (const file of files) {
    const content = readFileSync(file, 'utf8');
    for (const link of extractLinks(content)) {
      const result = resolveLink(link.target, file, root, workspaceRoot);
      const where = `${relative(root, file)}:${link.line} -> ${link.target}`;
      if (
        result.status === 'missing' ||
        result.status === 'anchor-missing' ||
        result.status === 'unsafe'
      ) {
        broken.push(`${where} [${result.status}]`);
      } else if (result.status === 'unchecked') {
        unchecked.push(where);
      }
    }
  }
  if (unchecked.length) {
    console.log(`[links] ${unchecked.length} unchecked external-workspace link(s):`);
    for (const u of unchecked) console.log(`  ? ${u}`);
  }
  if (broken.length) {
    const label = informational ? 'pre-existing broken local link(s)' : 'broken local link(s)';
    console.error(`[links] ${broken.length} ${label}:`);
    for (const b of broken) console.error(`  x ${b}`);
    return informational ? 0 : 1;
  }
  console.log(`[links] ${files.length} file(s) checked; no broken local links.`);
  return 0;
}

function main(argv) {
  const args = parseArgs(argv);
  const sub = args._[0];
  let root;
  try {
    root = args.root ? resolve(args.root) : git(process.cwd(), ['rev-parse', '--show-toplevel']);
  } catch {
    console.error('[workflow] not inside a Git repository; pass --root <dir>.');
    return 2;
  }
  switch (sub) {
    case 'commits':
      return cmdCommits(root, args);
    case 'tasks':
      return cmdTasks(root, args);
    case 'links':
      return cmdLinks(root, args);
    case 'all': {
      const a = cmdCommits(root, args);
      const b = cmdTasks(root, args);
      const c = cmdLinks(root, args);
      return a || b || c;
    }
    default:
      console.error(
        'usage: check-workflow.mjs <commits|tasks|links|all> [--base <sha>] [--head <sha>] [--root <dir>] [--all] [--strict] [--require "A,B,C"]',
      );
      console.error(
        '  --base: an explicit non-zero baseline that is unavailable makes the check FAIL; a zero baseline (new branch) checks the tip only; omit it for local tip + working-tree checks.',
      );
      return 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exit(main(process.argv.slice(2)));
}
