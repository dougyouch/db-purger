# db-purger

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
- deletes **children before parents**, so foreign-key constraints are never violated
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

`purge!` returns the number of base-table rows deleted.

## The plan DSL

| Method | Meaning |
|---|---|
| `base_table(table, field, opts = {}, &block)` | The root of the purge. Rows where `field = purge_value` are purged. Declare it **first** — every subsequent top-level call nests under it. |
| `child_table(table, field, opts = {}, &block)` | Rows whose `field` matches the **primary key** of the enclosing table's current batch. Purged before that batch is deleted. |
| `child_table(table, :id, foreign_key: :col, &block)` | Inverted relationship: the *enclosing* table holds `col` pointing at this table's `id`. Deleted in the same transaction, right after the enclosing batch. |
| `parent_table(table, field, opts = {}, &block)` | Rows whose `field` matches the original **purge value**. Purged after all of the enclosing table's batches. Use for sibling tables that share the same key (e.g. `company_id`). |
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

`DynamicPlanBuilder` walks the `has_many` associations dynamic-active-model discovered and emits a plan file,
listing every unreachable table as `ignore_table`. Treat the output as a first draft: it only knows about
conventional `<singular_table>_id` foreign keys and cannot infer polymorphic, soft-delete, or search rules.

```ruby
puts DBPurger::DynamicPlanBuilder.new(database).build(:companies, :id)
```

## Validation

`Executor#verify!` (or `DBPurger::PlanValidator.new(database, plan).valid?`) checks that:

- every table in the database is either in the plan or ignored (`missing_tables`)
- every table in the plan exists in the database (`unknown_tables`)
- every field and `foreign_key` named in the plan is a real column

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

Note that these are stored in the global `DBPurger.config`, and every `Executor.new` resets them.

## Metrics and instrumentation

Attach the built-in subscriber once at boot:

```ruby
DBPurger::MetricSubscriber.auto_attach

executor.purge!(42)
DBPurger::MetricSubscriber.metrics.as_json
# => { took: 12.4, started_at: ..., finished_at: ...,
#      purge_stats:  { employments: { duration:, num_purges:, num_records: } },
#      delete_stats: { employments: { duration:, num_delete_queries:, num_deleted:, num_expected_to_delete: } },
#      lookup_stats: { ... }, filter_stats: { ... } }
```

Metrics are reset at the start of each `Plan#purge!`. To feed your own telemetry, subscribe to the raw events
(all in the `db_purger` namespace):

| Event | Payload |
|---|---|
| `purge.db_purger` | `table_name`, `purge_field`, `deleted` |
| `next_batch.db_purger` | `table_name`, `start_id`, `num_records` |
| `delete_records.db_purger` | `table_name`, `num_records`, `records_deleted`, `deleted` |
| `search_filter.db_purger` | `table_name`, `num_records`, `num_records_selected` |

## Caveats

- **Only the base table is the entry point.** Top-level `parent_table`/`child_table` calls made before
  `base_table` are ignored by `Plan#purge!`.
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

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit together.

## License

MIT — see [LICENSE.txt](LICENSE.txt).
