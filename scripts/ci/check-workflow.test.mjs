// Fixture tests for check-workflow.mjs. No dependencies: node:test + node:assert.
// Run: node --test scripts/ci/check-workflow.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  commitStatus,
  missingSections,
  slugifyHeading,
  collectAnchors,
  extractLinks,
  resolveLink,
} from './check-workflow.mjs';

const CLI = fileURLToPath(new URL('./check-workflow.mjs', import.meta.url));

function runCli(args, cwd) {
  try {
    const out = execFileSync('node', [CLI, ...args], {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return { code: 0, out };
  } catch (error) {
    return { code: error.status ?? 1, out: `${error.stdout || ''}${error.stderr || ''}` };
  }
}

function initRepo() {
  const dir = mkdtempSync(join(tmpdir(), 'wf-'));
  const git = (args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8' });
  git(['init', '-q']);
  git(['config', 'user.email', 'dev@example.test']);
  git(['config', 'user.name', 'Dev']);
  git(['config', 'commit.gpgsign', 'false']);
  return { dir, git };
}

let commitSeq = 0;
function commit(dir, message, filename = 'file.txt', content = 'x') {
  writeFileSync(join(dir, filename), `${content}\n${commitSeq++}\n`);
  execFileSync('git', ['add', '-A'], { cwd: dir });
  execFileSync('git', ['commit', '-q', '-m', message], { cwd: dir });
}

// ---------------------------------------------------------------------------
// Commit subjects
// ---------------------------------------------------------------------------
test('accepts prefix-style task IDs', () => {
  for (const id of [
    'A-013',
    'D-007',
    'BACKUP-001',
    'CATALOG-002',
    'ROOT-001',
    'HARNESS-CI-001',
    'ORACLE-RELEASE',
  ]) {
    const s = commitStatus({
      subject: `${id}: do the thing`,
      authorName: 'Dev',
      authorEmail: 'a@b.c',
    });
    assert.equal(s.ok, true, id);
    assert.equal(s.format, 'prefix', id);
  }
});

test('accepts Conventional style with a trailing task ID', () => {
  for (const subject of [
    'feat(catalogue): add tags (CATALOG-002)',
    'docs(harness): enforce completion checks (ROOT-001)',
    'fix: align widget (A-013)',
    'backup: encrypted drive (BACKUP-001)',
  ]) {
    assert.equal(
      commitStatus({ subject, authorName: 'D', authorEmail: 'a@b.c' }).ok,
      true,
      subject,
    );
  }
});

test('rejects subjects without a task ID or in the wrong place', () => {
  for (const subject of [
    'docs: reconcile everything',
    'feat(catalogue): add tags',
    'add tags (CATALOG-002) in the body only',
    'a-013: lowercase id',
    'A-013 do the thing',
    'feat(catalogue) add tags (CATALOG-002)',
  ]) {
    assert.equal(
      commitStatus({ subject, authorName: 'D', authorEmail: 'a@b.c' }).ok,
      false,
      subject,
    );
  }
});

test('exempts merges, reverts and bot identities only', () => {
  const base = { subject: 'docs: no id', authorName: 'D', authorEmail: 'a@b.c' };
  assert.equal(commitStatus({ ...base, parents: 'p1 p2' }).exempt, 'merge');
  assert.equal(commitStatus({ ...base, subject: 'Revert "docs: x"' }).exempt, 'revert');
  assert.equal(
    commitStatus({ ...base, authorEmail: 'dependabot[bot]@users.noreply.github.com' }).exempt,
    'bot',
  );
  assert.equal(commitStatus({ ...base, authorEmail: 'github-actions@github.com' }).exempt, 'bot');
  assert.equal(commitStatus({ ...base, authorName: 'renovate[bot]' }).exempt, 'bot');
  // A human subject that merely claims automation is NOT exempt.
  const claimed = commitStatus({ ...base, subject: '[automated] docs: no id' });
  assert.equal(claimed.ok, false);
});

// ---------------------------------------------------------------------------
// Task record sections
// ---------------------------------------------------------------------------
test('missingSections reports absent and empty sections', () => {
  const md = '## Status\n\nDONE\n\n## Objective\n\nThing\n\n## Context\n\nSome context.\n';
  const missing = missingSections(md, ['Status', 'Objective', 'Context', 'Scope']);
  assert.deepEqual(missing, ['Scope']);
  const empty = missingSections('## Status\n\n\n## Objective\n\nX\n', ['Status', 'Objective']);
  assert.deepEqual(empty, ['Status (empty)']);
});

// ---------------------------------------------------------------------------
// Anchors
// ---------------------------------------------------------------------------
test('slugifyHeading matches GitHub rules (em-dash yields a double hyphen)', () => {
  assert.equal(
    slugifyHeading('D-002 first staging deployment verified — 2026-09-15 — Ready for review'),
    'd-002-first-staging-deployment-verified--2026-09-15--ready-for-review',
  );
  assert.equal(
    slugifyHeading('State reconciliation (completion requirement)'),
    'state-reconciliation-completion-requirement',
  );
});

test('collectAnchors de-duplicates repeated headings', () => {
  const anchors = collectAnchors('## Notes\ntext\n## Notes\nmore\n');
  assert.ok(anchors.has('notes'));
  assert.ok(anchors.has('notes-1'));
});

// ---------------------------------------------------------------------------
// Link extraction
// ---------------------------------------------------------------------------
test('extractLinks finds inline, image and reference links, ignoring code', () => {
  const md = [
    'See [a](a.md) and ![img](img.png).',
    '`[not](not.md)` is inline code.',
    '```',
    '[fenced](fenced.md)',
    '```',
    'Reference [b][ref] here.',
    '',
    '[ref]: b.md',
  ].join('\n');
  const targets = extractLinks(md)
    .map((l) => l.target)
    .sort();
  assert.deepEqual(targets, ['a.md', 'b.md', 'img.png']);
});

// ---------------------------------------------------------------------------
// Link resolution
// ---------------------------------------------------------------------------
test('resolveLink handles local, missing, anchors, cross-repo and unsafe paths', () => {
  const ws = mkdtempSync(join(tmpdir(), 'ws-'));
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  writeFileSync(join(repo, 'a.md'), '# Target\n\ntext\n');
  writeFileSync(join(repo, 'b.md'), 'see [a](a.md#target)\n');
  const file = join(repo, 'b.md');

  assert.equal(resolveLink('a.md', file, repo, ws).status, 'ok');
  assert.equal(resolveLink('a.md#target', file, repo, ws).status, 'ok');
  assert.equal(resolveLink('a.md#nope', file, repo, ws).status, 'anchor-missing');
  assert.equal(resolveLink('#target', file, repo, ws).status, 'anchor-missing'); // b.md has no Target heading
  assert.equal(resolveLink('missing.md', file, repo, ws).status, 'missing');
  assert.equal(resolveLink('https://example.com/x', file, repo, ws).status, 'ok');
  assert.equal(resolveLink('../other-repo/x.md', file, repo, ws).status, 'unchecked');
  assert.equal(resolveLink('../../../../etc/passwd', file, repo, ws).status, 'unsafe');
});

// ---------------------------------------------------------------------------
// CLI over a real git range
// ---------------------------------------------------------------------------
test('CLI commits: fails a bad subject, passes a good one, handles a missing baseline', () => {
  const { dir } = initRepo();
  commit(dir, 'initial');
  commit(dir, 'docs: no task id');

  const bad = runCli(['commits', '--root', dir, '--base', 'HEAD~1', '--head', 'HEAD'], dir);
  assert.equal(bad.code, 1);
  assert.match(bad.out, /lack a task ID/);

  commit(dir, 'A-013: fix the widget');
  const passing = runCli(['commits', '--root', dir, '--base', 'HEAD~1', '--head', 'HEAD'], dir);
  assert.equal(passing.code, 0);

  // Missing baseline: validate the tip only, never silently pass.
  const tip = runCli(
    [
      'commits',
      '--root',
      dir,
      '--base',
      '0000000000000000000000000000000000000000',
      '--head',
      'HEAD',
    ],
    dir,
  );
  assert.equal(tip.code, 0);
  assert.match(tip.out, /baseline unavailable/);
});

test('CLI tasks: fails a changed record missing sections', () => {
  const { dir } = initRepo();
  mkdirSync(join(dir, 'tasks', 'done'), { recursive: true });
  commit(dir, 'H-001: scaffold');
  writeFileSync(join(dir, 'tasks', 'done', 'X-001-thing.md'), '## Status\n\nDONE\n');
  execFileSync('git', ['add', '-A'], { cwd: dir });
  execFileSync('git', ['commit', '-q', '-m', 'X-001: incomplete record'], { cwd: dir });

  const res = runCli(['tasks', '--root', dir, '--base', 'HEAD~1', '--head', 'HEAD'], dir);
  assert.equal(res.code, 1);
  assert.match(res.out, /missing/);
});

test('CLI tasks: not applicable without a tasks/done directory', () => {
  const { dir } = initRepo();
  commit(dir, 'A-001: init');
  const res = runCli(['tasks', '--root', dir, '--head', 'HEAD'], dir);
  assert.equal(res.code, 0);
  assert.match(res.out, /not applicable/);
});

test('CLI links: fails a broken changed link and reports unchecked cross-repo links', () => {
  const { dir } = initRepo();
  commit(dir, 'A-001: init');
  writeFileSync(join(dir, 'doc.md'), 'See [missing](nope.md) and [ext](../sibling/x.md).\n');
  execFileSync('git', ['add', '-A'], { cwd: dir });
  execFileSync('git', ['commit', '-q', '-m', 'A-001: add doc'], { cwd: dir });

  const res = runCli(['links', '--root', dir, '--base', 'HEAD~1', '--head', 'HEAD'], dir);
  assert.equal(res.code, 1);
  assert.match(res.out, /broken local link/);
  assert.match(res.out, /unchecked external-workspace link/);
});
