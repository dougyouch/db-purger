# Architecture

db-purger is small (~900 lines) and splits cleanly into three layers: **describe** a purge (plan + DSL),
**check** it (validator), and **run** it (purgers + instrumentation).

```
            plan file / PlanBuilder.build { ... }
                          │
                          ▼
  ┌──────────────┐   ┌─────────┐   ┌─────────┐
  │ PlanBuilder  │──▶│  Plan   │──▶│  Table  │──┐ each Table owns a nested Plan
  │ (DSL)        │   │         │   │         │◀─┘ (recursive tree)
  └──────────────┘   └─────────┘   └─────────┘
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 ▼                  ▼
  PlanValidator      Executor ─────▶ PurgeTable / PurgeTableScanner
  (schema check)     (entry point)          │ (PurgeTableHelper)
                                            ▼
                               ActiveSupport::Notifications
                                  (*.db_purger events)
                                            │
                                            ▼
                               MetricSubscriber ─▶ Metrics
```

## Components

| File | Responsibility |
|---|---|
| `lib/db-purger.rb` | Autoloads everything; holds the global `DBPurger.config`. |
| `config.rb` | Global options: `explain?`, `explain_file`, `datetime_format`. |
| `table.rb` | Value object for one table in the plan: name, match field, options, and a lazily created nested `Plan`. |
| `plan.rb` | A node in the plan tree: one optional `base_table` plus lists of parent, child, search and ignored tables. `#purge!` is the run entry point. |
| `plan_builder.rb` | The DSL. `instance_eval`s a plan file or block against a `Plan`; nested blocks get a new builder bound to that table's nested plan. |
| `plan_validator.rb` | `ActiveModel::Validations` over plan vs. schema: missing tables, unknown tables, unknown columns. |
| `executor.rb` | Convenience façade: loads a plan file, applies config options, `verify!`, `purge!`. |
| `purge_table.rb` | Purges one table by `field = value(s)` in primary-key batches. Recurses into nested tables. |
| `purge_table_scanner.rb` | Purges a `purge_table_search` table: full `find_in_batches` scan filtered through the user's `search_proc`. |
| `purge_table_helper.rb` | Shared behaviour for both purgers: nested-table recursion, delete vs. soft delete vs. explain, transactions. |
| `metrics.rb` / `metric_subscriber.rb` | Aggregate timing and row counts per table from the notification events. |
| `dynamic_plan_builder.rb` | Generates plan-file source from `has_many` associations; a bootstrap tool, not used at purge time. |

## The plan tree

`PlanBuilder` always attaches tables to the *current* plan's `base_table.nested_plan` once a base table
exists. So a plan file is really:

```
Plan (root)
└── base_table: companies(:id)
    └── nested Plan
        ├── parent_tables: [company_tags(:company_id)]
        ├── child_tables:  [employments(:company_id) ─▶ nested Plan ..., websites(:id, fk: website_id) ...]
        ├── search_tables: [users(:id)]
        └── ignore_tables
```

`Plan#tables` flattens this tree for validation; `Table#foreign_keys` collects the `foreign_key:` columns of
a table's direct children so the purger can `SELECT` them alongside the primary key.

## Purge algorithm

`Plan#purge!` resets metrics and starts a `PurgeTable` on the base table with the purge value. Each
`PurgeTable#purge!` does:

```
each_batch = loop:
    batch = SELECT pk, <child foreign_keys> FROM t
            WHERE field IN (values) [AND conditions] [AND pk > last_pk]
            ORDER BY pk LIMIT batch_size
    break if batch empty

purge_children(batch) =
    for each child_table without foreign_key:      # rows pointing at us
      PurgeTable(child, child.field, batch.pks).purge!    (recursive)

delete_rows(batch) =
    if any child has foreign_key:                  # rows we point at
      TRANSACTION
        delete batch by pk
        for each fk child: PurgeTable(child, child.field, batch.<fk values>).purge!
    else
      delete batch by pk

if table has a primary key:
  if no parent_tables:
    each_batch: purge_children(batch); delete_rows(batch)
  else:                                            # two passes
    each_batch: purge_children(batch)
    for each parent_table:                         # siblings sharing the key
      PurgeTable(parent, parent.field, original purge value).purge!
    each_batch: delete_rows(batch)
else:
  raise if nested child/parent tables              # no ids to propagate
  single DELETE WHERE field = value [AND conditions]

for each search_table:
  PurgeTableScanner(search_table).purge!
```

Key properties:

- **Depth-first, children first.** A row is only deleted after everything referencing it, so FK
  constraints hold without `ON DELETE CASCADE`.
- **Two passes when there are parent tables.** A parent table can reference this table (e.g.
  `company_tags.company_id → companies.id`) *and* be referenced by one of its children, so it is purged
  between the child pass and the delete pass. Tables without parent tables keep the single pass.
- **Keyset pagination** (`pk > last_pk`) rather than `OFFSET`, so batches stay cheap on large tables and still
  advance in explain mode where nothing is actually deleted.
- **Bounded memory.** Only one batch of ids per level of the tree is held at a time.
- **Idempotent re-runs.** Every step re-derives its rows from the database; there is no saved cursor, so a
  crashed purge is resumed by running it again.
- **Parent vs. child** is about *which value* is propagated: children get the enclosing batch's primary keys,
  parents get the original purge value.

`PurgeTableScanner` follows the same shape but sources batches from `find_in_batches` over the entire table
(plus `conditions`) and narrows each batch with `search_proc` before recursing and deleting.

## Delete strategies

`PurgeTableHelper#delete_records_with_instrumentation` picks one of three actions for every scope:

1. **explain** (`DBPurger.config.explain?`) — rewrite `scope.to_sql` into `DELETE`/`UPDATE ... SET`, write it
   to `explain_file`, return `scope.count`.
2. **soft delete** (`mark_deleted_field`) — `scope.update_all(field => value)`.
3. **hard delete** — `scope.delete_all`.

All three go through ActiveRecord's `*_all` methods: no model callbacks or validations run.

## Instrumentation

Every unit of work is wrapped in `ActiveSupport::Notifications.instrument` under the `db_purger` namespace
(`purge`, `next_batch`, `delete_records`, `search_filter`). The purgers never talk to `Metrics` directly;
`MetricSubscriber` (an `ActiveSupport::Subscriber`) translates events into `Metrics` counters. This keeps the
purge code free of reporting concerns and lets callers attach their own subscribers (StatsD, logs, progress
bars) without changes to the library.

`PurgeTableScanner` uses the lower-level `instrumenter.start/finish` pair for `next_batch` because the batch
fetch happens inside `find_in_batches` rather than in a block the scanner controls.

## Dependencies and boundaries

- **ActiveRecord** is the only database interface. The library relies on `where`, `select`, `order`,
  `limit`, `find_in_batches`, `delete_all`, `update_all`, `transaction`, `to_sql` and
  `connection.quote*`, so it is adapter-agnostic (specs use SQLite).
- **dynamic-active-model** supplies the `database` object. The purge code only calls `database.models` and
  matches on `model.table_name`, so any object with that shape works. `DynamicPlanBuilder` additionally
  relies on `reflect_on_all_associations`.
- **Config scoping.** `DBPurger.config` returns the config set by `DBPurger.with_config` for the current
  thread, falling back to a process-wide default. `Executor#purge!` wraps the run in `with_config`, so executors
  with different explain settings can't interfere. `MetricSubscriber.metrics` is still process-wide.

## Testing

- `spec/db-purger/*` — unit specs for the builder, validator, executor and purger.
- `spec/integrations/*` — end-to-end purges over the schema in `spec/support/db/schema.rb`, asserting row-count
  deltas per table and, for explain mode, the exact SQL in `spec/fixtures/delete_plan.sql`.
- `spec/support/test_db.rb` builds a fresh SQLite database and dynamic models (`TestDB::*`) for each run.
- `spec/fixtures/*.plan.rb` — plan files used for loading and validation cases.
