# Catalogue import (staging)

Explicit, repeatable transfer of the five approved cakes into the staging
database and their images into the persistent media volume. This is a
**deployment-time data import**, not a migration and not a seed.

## Contents

| File | Purpose |
|---|---|
| `catalog.json` | The five approved catalogue records: category, products (name, slug, description, primary image path, status, order), tag relationships, and the verified legacy rating values + provenance. |
| `import-catalog.mjs` | Idempotent importer keyed by `(scope, slug)` for the category, `slug` for products and tags. Uses the application's own `@smshop/db` Prisma client. |
| `run-import.sh` | Host wrapper: runs the importer in the pinned API image on the `db` network with the existing runtime DB secret. |

## Keying and safety

- Category is upserted by `(scope, slug) = (CATALOG, tortai)`.
- Products are upserted by `slug`; tags by `slug`.
- Ratings are written explicitly from the file after the product row exists
  (`ratingAverage`, `ratingCount`, `ratingSourceUrl`, `ratingImportedAt`); no
  migration `UPDATE` is relied upon.
- Existing users, authentication data, e-shop records and unrelated catalogue
  content are never touched. Nothing is published except these five products.
- Descriptions are stored verbatim. `tortas-violeta` is intentionally
  over the 1000-character catalogue editorial limit; the importer preserves it
  and reports the over-limit count so the employee can shorten it in admin
  before its next save. It is never truncated.

## Media

The importer sets `primaryImageUrl` to the application-relative
`/media/products/<uuid>.webp` path. The referenced `.webp` files must exist in
the persistent media volume before the public pages are verified:

```sh
# On the host, after the media volume exists (created by deploy.sh release):
sudo docker run --rm \
  -v sokoladas-staging_media_data:/data \
  -v <staged-media-dir>:/src:ro \
  --entrypoint /bin/sh <api-image@sha256:...> \
  -c 'mkdir -p /data/products && cp -n /src/*.webp /data/products/ && chown -R 10001:10001 /data'
```

## Run

```sh
# On the staging host, after a successful release (migrations applied):
sudo ./run-import.sh <api-image@sha256:...>
```

Re-running is safe (upsert). Verify with the public API afterwards:

```sh
curl -fsS https://sokoladas.eu/api/public/catalog/categories/tortai | jq '.products | length'
```
