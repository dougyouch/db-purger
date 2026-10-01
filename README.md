# db-purger

[![CI](https://github.com/dougyouch/db-purger/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/dougyouch/db-purger/actions/workflows/ci.yml)
[![Coverage](https://raw.githubusercontent.com/dougyouch/db-purger/badges/coverage.svg)](https://github.com/dougyouch/db-purger/actions/workflows/ci.yml)
[![Branch coverage](https://raw.githubusercontent.com/dougyouch/db-purger/badges/branch-coverage.svg)](https://github.com/dougyouch/db-purger/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/db-purger)](https://rubygems.org/gems/db-purger)

Purge every row tied to a single top-level record — a company, an account, a tenant — across all of the
tables that reference it, in batches, from a declarative Ruby plan.

```ruby
executor = DBPurger::Executor.new(database, 'config/company.plan.rb')
executor.verify!          # fail fast if the plan doesn't cover the schema
executor.purge!(42)       # delete company 42 and everything that hangs off it
```

## Why

Deleting a tenant from a relational database is rarely one `DELETE`. Rows are spread across dozens of
tables, some keyed directly on the tenant id, some several joins away, some polymorphic, some that must be
soft-deleted rather than removed. `ON DELETE CASCADE` is often absent, and a single giant delete will lock
tables and blow out replication.

db-purger lets you describe those relationships once, in a plan file, and then:

- deletes in **primary-key batches** (default 10,000) so no single statement gets too large
- deletes rows **only after the rows that reference them**, so foreign-key constraints hold without `ON DELETE CASCADE`
- **validates** the plan against the live schema, so a newly added table can't be silently forgotten
- supports **soft deletes** (`UPDATE ... SET deleted_at = ...`) per table
- has an **explain mode** that prints the SQL it would run instead of running it
- emits **ActiveSupport::Notifications** events, with a built-in subscriber that collects timing and row counts

## Installation

```ruby
# Gemfile
gem 'db-purger'
```

Requires Ruby >= 3.2 and ActiveRecord >= 7.0. Models are supplied by
[dynamic-active-model](https://github.com/dougyouch/dynamic-active-model), which builds ActiveRecord classes
directly from the database schema.

## Quick start

### 1. Load the database

db-purger works against a `DynamicActiveModel::Database`. Anything that responds to `#models` (returning
ActiveRecord classes) will do.

```ruby
require 'active_record'
require 'dynamic-active-model'
require 'db-purger'

module PurgeDB; end

database = DynamicActiveModel::Explorer.explore(
  PurgeDB,
  { adapter: 'mysql2', host: 'localhost', database: 'app', username: 'app' },
  %w[schema_migrations ar_internal_metadata]   # tables to skip entirely
)
```

### 2. Write a plan

A plan is Ruby, evaluated with the plan DSL. Given this schema:

```
companies            (id, website_id, ...)
employments          (id, company_id, user_id, ...)
employment_notes     (id, employment_id, ...)
company_tags         (company_id, tag_id)            -- no primary key
events               (id, model_type, model_id, ...) -- polymorphic
websites             (id, content_id, ...)
contents             (id, ...)
tags, jobs           -- shared lookup tables, never purged
```

a plan to purge one company looks like:

```ruby
# config/company.plan.rb
base_table(:companies, :id)

# Tables keyed directly on the purge value (company_id = 42)
parent_table(:company_tags, :company_id)

# Tables keyed on the base table's primary key, purged batch-by-batch
child_table(:employments, :company_id) do
  child_table(:employment_notes, :employment_id)
  child_table(:events, :model_id, conditions: { model_type: 'PurgeDB::Employment' })
end

child_table(:events, :model_id, conditions: { model_type: 'PurgeDB::Company' })

# The company row points at the website (companies.website_id -> websites.id)
child_table(:websites, :id, foreign_key: :website_id) do
  child_table(:contents, :id, foreign_key: :content_id)
end

# Shared tables that are intentionally left alone
ignore_table :tags
ignore_table :jobs
ignore_table(/\Atmp_/)           # regexps are allowed
```

### 3. Verify and purge

```ruby
executor = DBPurger::Executor.new(database, 'config/company.plan.rb')
executor.verify!            # raises 'purge plan failed verification', errors printed to $stderr
deleted = executor.purge!(42)
```

`purge!` returns the number of root-table rows deleted (the base table, plus any top-level `parent_table`s).

### Plans with several top-level tables

`base_table` is shorthand for "one root table, with everything after it nested underneath". When several tables
are equally top-level (an outreach product's `emails`, `sms_messages` and `calls`, all keyed by `oid`), leave
`base_table` out and declare each root as a top-level `parent_table`:

```ruby
# config/outreach.plan.rb
parent_table(:calls, :oid) do              # calls.email_id -> emails.id, so calls go first
  child_table(:call_notes, :call_id)
  child_table(:call_recordings, :call_id)
  child_table(:call_tags, :call_id)
end

parent_table(:emails, :oid) do
  child_table(:email_attachments, :email_id)
end

parent_table(:sms_messages, :oid) do
  child_table(:sms_deliveries, :sms_message_id)
end

ignore_table :users
```

Each root is purged by `oid = purge_value`, children first, **in declaration order**: when one root's rows
reference another's, declare the referencing root first. Without a `base_table`, top-level `child_table`s are
an error (there is no enclosing batch to take ids from). Existing `base_table` plans run exactly as before.

## The plan DSL

| Method | Meaning |
|---|---|
| `base_table(table, field, opts = {}, &block)` | Optional single root. Rows where `field = purge_value` are purged. Declare it **first** — every subsequent top-level call nests under it. |
| `child_table(table, field, opts = {}, &block)` | Rows whose `field` matches the **primary key** of the enclosing table's current batch. Purged before that batch is deleted. |
| `child_table(table, :id, foreign_key: :col, &block)` | Inverted relationship: the *enclosing* table holds `col` pointing at this table's `id`. Deleted in the same transaction, right after the enclosing batch. |
| `parent_table(table, field, opts = {}, &block)` | Rows whose `field` matches the original **purge value**. At the top level of a plan without a `base_table`, each one is a root, purged in declaration order. Purged after the enclosing table's child tables but before the enclosing table's own rows, so it may both reference the base (`company_tags.company_id → companies.id`) and be referenced by a child table. Use for sibling tables that share the same key (e.g. `company_id`). |
| `nullify_table(table, field, conditions: nil)` | Rows whose `field` matches the **primary key** of the enclosing table's current batch get `field = NULL` instead of being deleted, before anything in that batch is deleted (`ON DELETE SET NULL` at purge time). Use for optional references that must not take the referencing row down with them: a self-referential `parent_id`/"copied from" column, or a link from another tenant's row. Only `conditions:` is supported. |
| `purge_table_search(table, field, opts = {}) { \|batch\| ... }` | Scans the whole table in batches; the block receives each batch and returns the records to purge. For orphans that can't be reached by a key. |
| `ignore_table(name_or_regexp)` | Exclude a table from validation. |

Blocks nest arbitrarily deep. Because `purge_table_search` uses its block as the filter, nest tables under it
with `.nested_plan`:

```ruby
purge_table_search(:users, :id) do |users|
  users = users.index_by(&:id)
  PurgeDB::Employment.where(user_id: users.keys).pluck(:user_id).each { |id| users.delete(id) }
  users.values                                   # users with no remaining employments
end.nested_plan do
  child_table(:events, :model_id, conditions: { model_type: 'PurgeDB::User' })
end
```

### Table options

| Option | Default | Description |
|---|---|---|
| `batch_size:` | `10_000` | Rows fetched and deleted per batch. |
| `conditions:` | none | Extra `where` applied to every query for this table (hash or SQL string). |
| `foreign_key:` | none | See `child_table` above. |
| `mark_deleted_field:` | none | Soft delete: `UPDATE table SET field = value` instead of `DELETE`. |
| `mark_deleted_value:` | `1` | Value written to `mark_deleted_field`. `Time` values are formatted with `datetime_format` in explain output. |

Tables **without a primary key** (e.g. join tables) are purged with a single unbatched `DELETE ... WHERE
field = value`; nested tables are not supported under them.

### Building a plan in code

```ruby
plan = DBPurger::PlanBuilder.build do
  base_table(:companies, :id)
  child_table(:employments, :company_id)
end

DBPurger::Executor.new(database, plan).purge!(42)
# or, without the executor:
plan.purge!(database, 42)
```

### Generating a starting plan

`DynamicPlanBuilder` walks the `has_many`, `has_one` and `has_and_belongs_to_many` associations
dynamic-active-model discovered, using each association's real foreign key, and emits a plan file listing every
unreachable table as `ignore_table`.

```ruby
builder = DBPurger::DynamicPlanBuilder.new(database)
puts builder.build(:companies, :id)   # single base_table plan
puts builder.build_for(:oid)          # one top-level parent_table per table holding oid
```

`build_for` makes **every** table holding the field a root, so rows with a null foreign key to another root
(an `email_recipients` row without an email) are still purged, and orders the roots so a root referencing
another root's rows comes first. HABTM join tables are emitted as leaves, never walking into the shared table on
the other side, and nothing is nested under a table without a primary key. A foreign-key cycle is written as a
comment instead of recursing.

Treat the output as a first draft: it cannot infer polymorphic (`as:`), soft-delete, `belongs_to`-owned
(`foreign_key:`) or search rules.

## Validation

`Executor#verify!` (or `DBPurger::PlanValidator.new(database, plan).valid?`) checks that:

- every table in the database is either in the plan or ignored (`missing_tables`)
- every table in the plan exists in the database (`unknown_tables`)
- every field, `foreign_key` and `mark_deleted_field` named in the plan is a real column
- the plan has a `base_table` or at least one top-level `parent_table`, no top-level `child_table` is left
  unreachable, and every `batch_size` is positive
- tables without a primary key have no nested child, parent or nullify tables (there would be no ids to propagate)
- every `nullify_table` field is a nullable column, and no `nullify_table` is left at the top level without a
  `base_table`

Run it in CI against your schema so a new table can't ship without a purge decision.

## Explain mode (dry run)

```ruby
File.open('purge.sql', 'w') do |io|
  executor = DBPurger::Executor.new(database, 'config/company.plan.rb', explain: true, explain_file: io)
  executor.purge!(42)
end
```

Nothing is deleted; each `DELETE`/`UPDATE` is written to `explain_file` (default `$stdout`). Lookups still run
against the database, so the output reflects real row ids.

| Executor option | Default |
|---|---|
| `explain:` | `false` |
| `explain_file:` | `$stdout` |
| `datetime_format:` | `'%Y-%m-%d %H:%M:%S'` |

Each executor keeps its own settings and applies them only for the duration of its `purge!` (per thread), so
creating another executor can't turn a dry run into a live one. `explain:` must be `true`, `false` or `nil`;
anything else (such as the string `'true'`) raises `ArgumentError` rather than running for real.

## Metrics and instrumentation

Attach the built-in subscriber once at boot:

```ruby
DBPurger::MetricSubscriber.auto_attach

executor.purge!(42)
DBPurger::MetricSubscriber.metrics.as_json
# => { took: 12.4, started_at: ..., finished_at: ...,
#      purge_stats:  { employments: { duration:, num_purges:, num_records: } },
#      delete_stats: { employments: { duration:, num_delete_queries:, num_deleted:, num_expected_to_delete: } },
#      nullify_stats: { cadences: { duration:, num_nullify_queries:, num_nullified: } },
#      lookup_stats: { ... }, filter_stats: { ... } }
```

Metrics are reset at the start of each `Plan#purge!`. To feed your own telemetry, subscribe to the raw events
(all in the `db_purger` namespace):

| Event | Payload |
|---|---|
| `purge.db_purger` | `table_name`, `purge_field`, `deleted` |
| `next_batch.db_purger` | `table_name`, `start_id`, `num_records` |
| `delete_records.db_purger` | `table_name`, `num_records`, `records_deleted`, `deleted` |
| `nullify_records.db_purger` | `table_name`, `nullify_field`, `num_records`, `records_nullified` |
| `search_filter.db_purger` | `table_name`, `num_records`, `num_records_selected` |

## Caveats

- **Declare `base_table` first.** A `child_table` declared before it is never reached (the validator reports
  it); a `parent_table` declared before it becomes a separate root, purged after the base table.
- **Not one big transaction.** Each batch is its own set of statements (foreign-key children share a
  transaction with their parent batch). An interrupted purge is safe to re-run with the same value.
- **Soft-deleted rows still match.** A `mark_deleted_field` table is not filtered on that field; add
  `conditions:` if re-runs should skip already-marked rows.
- Always run explain mode against a copy of production before the first real purge with a new plan.

## Development

```sh
bundle install
bundle exec rspec        # specs run against a throwaway SQLite database
bundle exec rubocop
script/console
```

CI (`.github/workflows/ci.yml`) runs RuboCop and the specs on Ruby 4.0 for every push and pull request.
The HTML coverage report is attached to each run as the `coverage` artifact, and pushes to `master` refresh
the line and branch coverage badges on the `badges` branch.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit together.

## Releasing

1. Bump `s.version` in `db-purger.gemspec` and merge to `master`.
2. Tag and push: `git tag v0.6.0 && git push origin v0.6.0`

`.github/workflows/release.yml` re-runs CI, checks the tag matches the gemspec version, publishes to RubyGems
via trusted publishing (no API key), and creates a GitHub release with the `.gem` attached.

## License

MIT — see [LICENSE.txt](LICENSE.txt).
