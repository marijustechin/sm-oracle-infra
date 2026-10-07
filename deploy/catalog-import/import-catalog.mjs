#!/usr/bin/env node
// Explicit, repeatable staging catalogue import for the sokoladas.eu release.
//
// Idempotent and keyed by stable unique identifiers:
//   - catalogue category by (scope, slug);
//   - catalogue product by slug;
//   - catalogue tag by slug, with product<->tag links set from the file.
//
// It writes the verified legacy rating fields (average/count/source/importedAt)
// explicitly, after the product row exists, and never relies on migration UPDATE
// statements. Existing unrelated rows (users, auth, shop, other catalogue) are
// untouched. Descriptions are stored verbatim; an over-limit legacy description
// is reported by char count but never truncated.
//
// Runs inside the API image (which contains the built @smshop/db Prisma client).
// See README.md for the exact host invocation.

import { readFile } from 'node:fs/promises';
import { PrismaClient, ProductScope, ProductStatus } from '@smshop/db';

const file = process.env.CATALOG_IMPORT_FILE ?? '/app/apps/api/catalog.json';

let data;
try {
  data = JSON.parse(await readFile(file, 'utf8'));
} catch (error) {
  console.error(`catalog-import: cannot read ${file}: ${error.message}`);
  process.exit(1);
}

if (!data?.category?.slug || !Array.isArray(data?.products) || data.products.length === 0) {
  console.error('catalog-import: invalid import file (category.slug and products[] required)');
  process.exit(1);
}

const prisma = new PrismaClient();
let created = 0;
let updated = 0;
let overLimit = 0;

try {
  const category = await prisma.category.upsert({
    where: { scope_slug: { scope: ProductScope.CATALOG, slug: data.category.slug } },
    update: { name: data.category.name, isActive: true },
    create: {
      scope: ProductScope.CATALOG,
      name: data.category.name,
      slug: data.category.slug,
      isActive: true,
    },
  });

  for (const product of data.products) {
    const description = String(product.description ?? '');
    if (description.length > 1000) {
      overLimit += 1;
    }

    const existing = await prisma.catalogProduct.findUnique({
      where: { slug: product.slug },
      select: { id: true },
    });

    const fields = {
      categoryId: category.id,
      name: product.name,
      description,
      primaryImageUrl: product.primaryImageUrl,
      status: product.status ?? ProductStatus.PUBLISHED,
      featured: Boolean(product.featured),
      displayOrder: product.displayOrder ?? 0,
      ratingAverage: product.ratingAverage ?? null,
      ratingCount: product.ratingCount ?? null,
      ratingSourceUrl: product.ratingSourceUrl ?? null,
      ratingImportedAt: product.ratingImportedAt ? new Date(product.ratingImportedAt) : null,
    };

    const saved = await prisma.catalogProduct.upsert({
      where: { slug: product.slug },
      update: fields,
      create: { slug: product.slug, ...fields },
    });

    const tagIds = [];
    for (const tag of product.tags ?? []) {
      const savedTag = await prisma.catalogTag.upsert({
        where: { slug: tag.slug },
        update: { name: tag.name },
        create: { name: tag.name, slug: tag.slug },
      });
      tagIds.push(savedTag.id);
    }
    await prisma.catalogProduct.update({
      where: { id: saved.id },
      data: { tags: { set: tagIds.map((id) => ({ id })) } },
    });

    if (existing) {
      updated += 1;
    } else {
      created += 1;
    }
    console.log(
      `catalog-import: ${existing ? 'updated' : 'created'} ${product.slug} ` +
        `(${description.length} chars, ${tagIds.length} tags)`,
    );
  }
} finally {
  await prisma.$disconnect();
}

console.log(
  `catalog-import: done (${created} created, ${updated} updated)` +
    (overLimit > 0 ? `; ${overLimit} description(s) exceed the 1000-char editorial limit` : ''),
);
