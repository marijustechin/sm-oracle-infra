# AGENTS.md — sm-oracle-infra Agent Guidelines

This repository documents and automates the infrastructure used for the `sokoladas.eu` demo/staging environment.

The repository is not merely documentation. It is the source of truth for how the infrastructure is intended to be configured, operated, verified, and rebuilt.

## 1. Operating Model

Human decisions come first.

Marijus authorizes tasks and accepts results. AI assistants may plan, implement, verify, and review; AI review does not substitute for human acceptance.

### Authorization and decisions

- Read-only/audit/planning tasks do not update files, TODO, CHANGELOG, or other project state unless explicitly requested.
- Repository work authorizes only the requested local changes and appropriate verification. It does not authorize deployment, SSH-based changes, OCI mutations, DNS changes, or other external changes.
- Live work requires explicit task authorization identifying the target and intended changes. Do not infer it from repository editing permission or a roadmap item.
- Destructive or potentially access-breaking actions require explicit human approval of the concrete action and scope. Existing explicit approval need not be requested twice unless the scope or risk changes.
- A TODO item is planned work, not an approved architectural decision or authorization to execute it.

Choices affecting public exposure, privilege, persistence, service boundaries, recurring cost, or recovery behavior require an approved direction. Surface unresolved choices before dependent work. Naming, formatting, and implementation mechanics within that direction are ordinary details unless they change those properties; use engineering judgment without requesting approval for each detail.

An explicit human instruction intentionally superseding an older repository rule governs the scoped task, subject to applicable platform/tool constraints. If that intent is ambiguous, surface the conflict. Reflect permanent policy changes in the appropriate document when edits are authorized; a task-specific exception is not permanent policy.

### Review lifecycle

1. **Implemented:** requested edits or authorized live actions have been performed.
2. **Verified:** relevant checks support the claimed result; limitations are recorded.
3. **Ready for review:** implementation, evidence, documentation, and task-log updates are available together in a reviewable diff.
4. **Human accepted:** Marijus has accepted the result after review and any necessary corrections.

Prepare documentation as part of the reviewable result, not after review. Verification or an AI review alone does not establish human acceptance. Commit only after successful verification and review, and only when explicitly requested.

## 2. Core Principles

### Infrastructure must be reproducible

Prefer scripts, configuration files, and declarative infrastructure over undocumented manual commands.

A manual change on the server is acceptable only when:
- it is necessary for the current task,
- it is documented,
- and, where practical, it is later converted into a reproducible script or configuration.

### Keep the host minimal

The host operating system should contain only software required to operate and administer the server.

Do not install application runtimes or application databases directly on the host unless explicitly approved.

In particular, the default direction is:
- Docker Engine on the host;
- Docker Compose for service orchestration;
- application services in containers;
- PostgreSQL in a container;
- Node.js / pnpm inside application build/runtime containers, not on the host;
- reverse proxy in a container unless a later architectural decision says otherwise.

### No undocumented infrastructure changes

Any infrastructure-changing task must leave the repository in a state that explains what changed and how to reproduce or verify it.

### Security by default

Never:
- commit passwords;
- commit API keys;
- commit private SSH keys;
- commit `.env` files containing secrets;
- commit production customer data;
- expose database ports publicly;
- weaken SSH or firewall rules without explicit human approval of the action and reason.

Use least privilege and expose only the ports that are actually required.

Omit secrets from captured logs, review evidence, and change-log entries as well as committed files. Ignore rules are only a local safeguard and do not protect already tracked files. Secret storage, delivery, access, rotation, and recovery must be decided before deploying a service that needs them; do not introduce a secrets platform by default.

### Verify, do not assume

Do not report a task as complete merely because a command exited without an obvious error.

Use appropriate verification commands, tests, health checks, logs, or observable behavior.

If verification fails, the task is not complete.

## 3. Documentation authority

- [AGENTS.md](AGENTS.md) governs agent workflow and authorization boundaries.
- [README.md](README.md) records purpose, intended design, approved decisions, and open questions.
- [docs/server.md](docs/server.md) is the authoritative recorded inventory: dated observations and their evidence, not guaranteed live truth.
- [TODO.md](TODO.md) records unfinished work and dependencies, not authorization.
- [CHANGELOG.md](CHANGELOG.md) records historical changes and verification limitations, not current configuration guarantees.

Authority follows responsibility, not a blanket file ranking. Surface conflicting claims within the same responsibility rather than guessing which file is newer. No document alone authorizes live work; explicit task scope governs execution. Treat changeable values such as public IP addresses as observations unless explicitly recorded as reserved/static.

## 4. Target Network Exposure

The intended public-facing ports are:

- `22/tcp` — SSH
- `80/tcp` — HTTP
- `443/tcp` — HTTPS

Application and data-service ports such as the following must not be exposed directly to the public internet:

- Next.js internal port
- NestJS internal port
- PostgreSQL `5432`
- Redis or other internal service ports

Public HTTP/HTTPS traffic should terminate at the reverse proxy. SSH is a separate administrative service. These are exposure targets, not evidence of current firewall rules.

## 5. ARM64 Constraint

The target server architecture is ARM64.

Any package, Docker image, native dependency, or binary added to this project must support `linux/arm64`.

Do not introduce `amd64`-only infrastructure dependencies without explicitly identifying the incompatibility and obtaining approval.

Prefer multi-architecture images where available.

## 6. Repository Responsibilities

This repository should ultimately contain:

- infrastructure documentation;
- task roadmap;
- change log;
- bootstrap/setup scripts;
- Docker and deployment configuration;
- backup and restore procedures;
- disaster recovery instructions;
- security decisions;
- verification procedures.

Do not store application source code here unless explicitly requested. Application repositories and infrastructure repositories should remain logically separate.

## 7. Task Scope Discipline

For every task:

- read this file first;
- read `README.md`;
- read any files specifically referenced by the task;
- inspect existing implementation before changing it;
- perform only the requested scope;
- do not perform opportunistic refactors unrelated to the task;
- do not add dependencies without a clear reason;
- do not delete working configuration merely to replace it with a preferred style.

Resolve conflicts using the intentional-override rule in section 1; do not silently interpret an ambiguous task as a policy override.

## 8. TODO and Change Log Protocol

The repository is expected to maintain:
- `TODO.md` for unfinished work;
- `CHANGELOG.md` for implemented and verified work, including documentation changes, with review status explicit.

For implemented and verified work, prepare removal of the corresponding completed TODO items and a dated CHANGELOG entry in the reviewable diff. Record what changed, why, important decisions, verification performed, limitations, and follow-up work. Mark the new entry **Ready for review**, not Human accepted; update acceptance status only after explicit human acceptance and authorization to update project state.

Failed or incomplete work remains unfinished; do not log it as completed. Read-only/audit/planning tasks are exempt from these updates unless explicitly requested. TODO is a live roadmap, not an archive; do not accumulate checked-off tasks.

Preserve historical entries. Correct factual errors or add clearly dated evidence qualifications without inventing missing evidence or rewriting historical reports as new observations.

## 9. Commands and Destructive Operations

Before a destructive or potentially access-breaking action, verify its necessity and scope and obtain explicit human approval as defined in section 1.

Before access-breaking work, establish an available, understood recovery path. Record the relevant current access method, fallback, recovery status, and success checks in docs/server.md. Unknown or untested recovery must remain explicit; do not proceed with dependent changes until the required recovery path is established.

For network/access verification, consider effective OCI rules, host firewall rules, and Docker-published ports together. Host firewall configuration alone does not prove that container ports are private.

Examples of destructive or potentially access-breaking actions include:

- deleting files or directories;
- removing Docker volumes;
- pruning Docker data;
- dropping databases;
- resetting firewall rules;
- replacing SSH configuration;
- changing network routes;
- deleting cloud resources.

Never use a destructive command merely as a convenient shortcut.

## 10. Git Discipline

Keep commits focused.

Before considering work ready:
- inspect the diff;
- ensure no secrets are present;
- ensure generated noise is not committed;
- verify the requested behavior;
- update documentation if infrastructure behavior changed.

Do not commit automatically unless the task explicitly asks for a commit.

## 11. Reviewability

Write infrastructure code for a human reviewer.

Prefer:
- explicit configuration;
- small scripts;
- meaningful names;
- comments that explain non-obvious reasons rather than obvious syntax;
- idempotent operations where practical;
- clear failure behavior (`set -euo pipefail` for Bash scripts where appropriate).

Avoid:
- clever shell tricks;
- hidden side effects;
- unexplained one-liners;
- duplicated configuration;
- silent fallback behavior.

## 12. Ready-for-review standard

A change task is Ready for review only when all of the following are true:

- requested scope is implemented;
- result is verified;
- no known relevant errors remain hidden;
- documentation reflects the new state;
- TODO/change-log state is updated when applicable;
- the diff is understandable and reviewable;
- no secrets or private material were introduced.

Human acceptance is a separate subsequent state; do not claim it from these checks alone.
