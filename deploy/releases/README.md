# Release manifests

This directory records **non-secret deployment metadata** for staging releases.
Nothing here is a secret, and nothing here deploys anything by itself.

## Three distinct concepts

| Concept | What it is | Where it lives |
|---|---|---|
| **Build manifest** | What the `smshop` CI built: source commit and immutable image digests. Contains no deployment state. | Produced by the `smshop` `Images` workflow as the `release-manifest` artifact (and its run summary). Not committed here. |
| **Approved staging release manifest** | What the operator intends to deploy: a build manifest plus a staging `releaseId`, the expected infra commit, and optional notes. | Committed here as `deploy/releases/<release-id>.json`. This is the human review/approval artifact. |
| **Host applied state** | What actually ran on the host. | Host-only `/opt/sokoladas-staging/state/applied.json` (+ `state/history/`), written by `deploy.sh release` only after a successful deploy; never committed. |

In short: **desired release** (this directory) vs **applied release** (host) vs
**deployment evidence** (host, plus the infra `CHANGELOG.md`). Do not conflate
them.

## Build manifest schema (produced by `smshop` CI)

```json
{
  "schemaVersion": 1,
  "createdAt": "<ISO-8601 UTC>",
  "source": {
    "repository": "github.com/<owner>/smshop",
    "commit": "<full 40-char SHA>",
    "ref": "<branch or tag>"
  },
  "ci": { "imagesRunId": "<workflow run id>" },
  "images": {
    "web": { "ref": "ghcr.io/<owner>/smshop-web@sha256:<64 hex>", "platform": "linux/arm64", "tag": "sha-<commit>" },
    "api": { "ref": "ghcr.io/<owner>/smshop-api@sha256:<64 hex>", "platform": "linux/arm64", "tag": "sha-<commit>" }
  }
}
```

The build manifest deliberately contains **no** `deployed`, `health`,
`schemaMigrated`, release-status, feature-flag, configuration or secret fields.

## Approved staging release manifest schema

A superset of the build manifest: copy the build manifest and add the staging
fields below. Keep it minimal and evidence-backed.

```json
{
  "schemaVersion": 1,
  "releaseId": "<staging release id, e.g. d005-v1>",
  "createdAt": "<ISO-8601 UTC>",
  "source": { "repository": "github.com/<owner>/smshop", "commit": "<sha>", "ref": "main" },
  "ci": { "imagesRunId": "<run id>" },
  "images": {
    "web": { "ref": "ghcr.io/<owner>/smshop-web@sha256:<64 hex>", "platform": "linux/arm64", "tag": "sha-<commit>" },
    "api": { "ref": "ghcr.io/<owner>/smshop-api@sha256:<64 hex>", "platform": "linux/arm64", "tag": "sha-<commit>" }
  },
  "infra": { "contractCommit": "<infra commit expected for this release>" },
  "notes": "<optional operator note>"
}
```

Rules:

- Image references **must** be immutable `@sha256:` digests. Mutable tags are
  rejected by the resolver.
- No secrets, environment values, or provider credentials.
- Do not create manifests for releases that were never actually reviewed/backed
  by a real build; `example-release.json` here is illustrative only.

## Generating the host-only `images.env`

The resolver reads an approved release manifest and writes exactly:

```
WEB_IMAGE=ghcr.io/<owner>/smshop-web@sha256:<64 hex>
API_IMAGE=ghcr.io/<owner>/smshop-api@sha256:<64 hex>
```

```sh
python3 scripts/resolve_release_manifest.py deploy/releases/<release-id>.json --out images.env
```

`images.env` stays **host-only** and git-ignored. `deploy.sh release <release-id>`
invokes this resolver as its first step and refuses any value that is not an
immutable `@sha256:` digest. Running the resolver directly is only needed for
inspection; the supported path is the `release` command (see
`docs/deployment.md`).

## Example

`example-release.json` uses the real published digests of `smshop` commit
`070e680` (recorded in the deployment contract) but is marked
`"releaseId": "not-applied-example"`. It exists to document the schema and to
exercise the resolver; it has **not** been deployed.
