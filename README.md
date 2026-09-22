# Swift Change Facts

What a change to a codebase DID, as facts a reviewer can hold against a brief — never a judgement.
Extracted from [Sidewatch](https://github.com/Sidewatch) on 22 Sep 2026, where each reader shipped
with a mutation-verified harness; those cases are this package's tests.

```swift
import ChangeFacts

// The statements a change ADDS that can lose data, in SQL and the migration DSLs agents write.
let findings = DestructiveSQL.findings(in: sql, path: "db/migrate/2026_drop_bio.rb", addedLines: [3, 4])
findings.map(\.summary)   // ["remove_column users.bio", "column type changed: users.age"]
DestructiveSQL.tooltip(for: findings)

// A schema as structure — from SQL, a Prisma schema, a Rails schema.rb or a Django models.py —
// and the diff of two of them.
let before = SchemaModel.load(text: old, path: "prisma/schema.prisma")!
let after = SchemaModel.load(text: new, path: "prisma/schema.prisma")!
SchemaDiff.headline(SchemaDiff.compare(old: before, new: after))
// "Schema: 1 table removed, 2 columns removed, 1 type change, 1 index change"

// A manifest's declarations by name, in package.json, composer.json, requirements, Pipfile,
// pyproject, Package.swift, Cargo.toml, go.mod, Gemfile, Podfile, Cartfile, pubspec, mix.exs,
// Gradle and Maven — and what changed between two versions of it.
DependencyChanges.headline(DependencyChanges.facts(oldText: old, newText: new, path: "package.json"))
// "Dependencies: adds stripe ^12.0.0; removes lodash; bumps axios 1.6.0 → 1.7.0"

// What a change starts reading and calling, on its added lines, minus what the file already did.
AddedLineSurface.tooltip(AddedLineSurface.findings(oldText: old, newText: new, path: "src/pay.js", addedLines: added))
// "Reads new environment variable: STRIPE_KEY · Calls new host: api.stripe.com"
```

## Facts, not judgements

Every reader answers *what is this* — a `DROP TABLE` on line 12, a column that is now `NOT NULL`,
a package added by name, a host called for the first time. Whether it should have happened is the
reviewer's call, and nothing here has a threshold or an opinion about "good".

## What is read, and what is not

- **Destructive SQL** on ADDED lines only: a statement already at HEAD is not something this change
  did. Comments in the file's own syntax and string literals in `.sql` files are not statements.
  `DROP INDEX` / `VIEW` / `CONSTRAINT` lose no rows and are not marked. A database dump is one
  finding. Tests and vendored trees are never scanned.
- **Schemas** are built by running their DDL into an in-memory SQLite one statement at a time; a
  statement SQLite cannot take (`CREATE EXTENSION`, an `ALTER … ADD CONSTRAINT`) is skipped, not
  fatal, so a Postgres schema still yields its tables. A rename reads as a removal and an addition,
  which is what the database does too.
- **Dependencies** are declarations, not resolutions: lockfiles yield nothing, and a manifest in a
  format not read here yields nothing rather than a guess.
- **Surface** ignores loopback, private, example, schema and namespace hosts, and manifests,
  lockfiles, prose, tests and vendored trees.

## Requirements

macOS 14+, Swift 6.2. One dependency, [swift-sqlite-reader](https://github.com/Sidewatch/swift-sqlite-reader),
for the in-memory schema build.

## Licence

MIT.
