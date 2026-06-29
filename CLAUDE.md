# SQL Analysis Workstation

## Identity

This workstation handles all SQL-related work: reviewing, optimizing, and refactoring Snowflake SQL queries and views. Route here when working with any SQL code — performance reviews, structural refactors, style compliance checks, or building new queries. This workstation does not handle non-SQL data work, reporting configuration, or BI tool setup.

## Resources

| Resource | Read when... |
|---|---|
| MEMORY.md | Starting any session to pick up where we left off |
| schema_catalog.md | Working with any table or view — check here for join patterns, filter conventions, and column lists before writing code |

## Workflow

1. Read MEMORY.md to load context on active work and conventions.
2. Ask clarifying questions if the goal, source tables, constraints, and target schema aren't clear.
3. Analyze the existing SQL for structure, performance issues, and style violations before making changes.
4. Refactor or write SQL per the conventions in MEMORY.md and the sql-code-review skill.
5. Verify output: column count, no duplicates, no bare column references, all logic preserved.
6. When rewriting a view, always produce a companion validation query to confirm output matches the original.
7. File locations for `.sql` files:
   - `00_sql_code/original/` — read-only reference; never write or modify files here
   - `00_sql_code/new/` — read and write all new or refactored SQL here
   - `00_sql_code/validation/` — read and write all validation queries here
   - Save all other deliverables (docs, notes, catalogs) to the root `SQL Analysis/` folder. Update MEMORY.md with any new decisions.

## Editorial Rules

Follow my voice principles in 00_Resources (voice-principles.md).

- Write SQL keywords in lowercase.
- Prefer CTEs over subqueries. Never nest subqueries that could be a CTE.
- Raw/union CTEs contain only typed raw columns and snapshot filters. No calculations, no joins — those belong in a downstream CTE (typically named `main`).
- All joins to reference/dimension tables belong in `main`, not the union — this prevents the join from executing once per union branch.
- Pre-compute expensive subqueries (e.g. `max(ver_date)`) in their own CTE — never as correlated subqueries.
- When a subquery appears inside a `where` clause, always use a different alias than the outer query to avoid correlated subquery errors.
- Each major clause on its own line. Consistent 4-space indentation.
- Column aliases follow immediately after the column or expression with no padding: `end as type_calc,` not `end                                     as type_calc,`
- Every column reference must include the table alias prefix (e.g. `a.customercategory`, not `customercategory`). This applies in all CTEs and SELECT lists throughout the file.
- Never use `select *` or `alias.*` in any CTE or SELECT list. Always enumerate columns explicitly.
- Table aliases must be descriptive (no `t1`, `a`, `b`). Exception: source table alias `a` is acceptable in union branches when there is only one source table per branch. Use `u` for the union CTE, `m` for main, `g` for GUP join, `e` for employee, `p` for product dim, `s` for subquery aliases.
- Object naming conventions (apply to new assets only — do not rename existing objects):
  - Views: `vw_view_name`
  - Dimension tables: `dim_table_name`
  - Fact tables: `fact_table_name`
- Always use explicit join types (`left join`, `inner join`, etc.).
- Comment complex logic inline using this exact format: `-- MM/DD/YYYY [Dan Girard] Summary of the change`
- Snowflake allows referencing a calculated column alias defined earlier in the same SELECT list. A separate CTE is only needed when a column depends on one defined *after* it in the same SELECT.
- Always build rewritten or new code in `finance_db.dev_netsuite`. All table references should also use `dev_netsuite` — except `finance_db.ingest` (always as-is) and any tables explicitly called out as `public`-only (e.g. `dim_globalultimateparent_map`, `dim_product_dm_hierarchy_tbl`). Override only when explicitly instructed.
