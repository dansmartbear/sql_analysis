# SQL Analysis Memory

## Contacts

| Name | Role | Notes |
|---|---|---|
| Dan Girard | Owner | dan.girard@smartbear.com |

## Key Decisions

### 2026-05-15 — vw_ns_ss546 Refactor

**View:** `finance_db.dev_netsuite.vw_ns_ss546`

**Sources:**
- `finance_db.ingest.ns_ss546_cm_pm_stg` — current + prior month, refreshed hourly
- `finance_db.ingest.ns_ss546_stat_stg` — full history, refreshed daily
- `finance_db.public.dim_globalultimateparent_map` — GUP mapping
- `finance_db.ingest.employee_stg_tbl` — salesperson lookup (join on max ver_date)
- `finance_db.public.dim_product_dm_hierarchy_tbl` — product hierarchy; overrides `direct_indirect`

**What changed:**
- Raw union contains only typed raw columns — no calculations, no joins.
- `type_calc`, `sisense_product_rollup_calc`, GUP join, and all direct_ecomm logic moved to the `main` CTE.
- All product dimension columns (`product_name`, `direct_indirect`, `core_noncore`, etc.) removed from SQL logic entirely — sourced from `dim_product_dm_hierarchy_tbl` via join.
- New columns from dim table added to output: `product_hub`, `product_parent`, `pbt_group`, `ai`.
- CTE chain: `employee_max` → `raw_union` → `main` → final SELECT.
- Snowflake allows referencing a calculated column alias defined earlier in the same SELECT list — no extra CTEs needed for that pattern.
- When using subqueries inside a `where` clause, always use a different alias than the outer query to avoid correlated subquery errors (e.g. `where to_date(a.ver_date) = (select max(to_date(ver_date)) from ... s)`).

**Validation:** Passed 05/15/2026 — `dimension_diffs` returned 0 rows, summary totals matched exactly between `public.vw_ns_ss546` and `dev_netsuite.vw_ns_ss546`.

### 2026-05-15 — vw_ns_ss546_new: NAICS sector join

Added a `left join` to `finance_db.dev_netsuite.vw_naics_mapping_new` (alias `n`) on `m.naics = n.naics_code` in the final SELECT. New output column `naics_sector` = `concat(n.naics_sector_code, ' - ', n.naics_sector)`. Existing `naics` column retained unchanged. Validation queries 3–5 added to `vw_ns_ss546_new_validation.sql`.

**Deliverable:** `SQL Analysis/00_sql_code/vw_ns_ss546_new.sql`
**Validation query:** `SQL Analysis/00_sql_code/vw_ns_ss546_new_validation.sql`

**Naming note:** `vw_ns_ss546_new` is a temporary name to avoid overwriting the existing production view during development. Final name will be `vw_ns_ss546` in `finance_db.public` once promoted. `ns_ss546` refers to NetSuite Saved Search 546 (billing transaction lines).

## Session Startup Checklist

At the start of every session involving a refactor or new view, ask these questions before writing any code:

1. **DDL for reference/dimension tables** — Do you have the `create table` DDL for any tables being joined? Knowing the column list upfront prevents mid-session refactors (e.g. discovering a dim table already has calculated columns).
2. **Structural intent** — Should calculated columns be computed inline, or sourced from a dim/reference table? Any other structural preferences (CTE naming, union strategy)?
3. **Source table structure** — Can you share a `describe table` or sample columns for the source tables? Especially useful when union branches may differ.
4. **Target schema** — Confirm `dev_netsuite` unless told otherwise.
5. **Alias preferences** — Any specific table aliases you want used? (Defaults are in CLAUDE.md.)
6. **Column name verification** — Before referencing any column from a view or table that has been recently refactored, confirm the exact output column names. Watch especially for: aliased columns whose name differs from the source (e.g. `dateoffirstsale` vs `date_of_first_sale`), renamed dim table columns (e.g. `product_group` → `product_group_map`), and columns that exist in `public` but not yet in the `dev_netsuite` equivalent.

---

## Schema Inventory

See `schema_catalog.md` in this folder for the full catalog of tracked tables and views.

---

### 2026-05-17/18 — master_billing_new: refactor complete (final working state)

**Table:** `finance_db.dev_netsuite.master_billing_new`
**File:** `SQL Analysis/00_sql_code/new/sp_master_billing_new.sql`
**Companion view:** `SQL Analysis/00_sql_code/new/vw_sfdc_invoice_data.sql`
**Validation:** `SQL Analysis/00_sql_code/validation/master_billing_new_validation.sql`

**CTE chain:** `raw_union` → `tiers` → `main` → final SELECT

**Key changes from original `public.master_billing`:**
- 6 inline SFDC CTEs replaced with `left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf` in `main`.
- CTE `A` split into `raw_union` (pure union, no joins/calcs) and `main` (all joins and derived fields). CTE `mb` renamed to `main`.
- NS source: `finance_db.public.vw_ns_ss546` → `finance_db.dev_netsuite.vw_ns_ss546_new`.
- `dim_country_map` join moved into `main`. `contract_length` computed once in `raw_union`.
- `new_expansion` and `billing_category` moved from final SELECT into `main`.
- NAICS join: `public.vw_naics_mapping` → `dev_netsuite.vw_naics_mapping_new`.
- `inline_discount` pulled directly (clean decimal from new view; guard removed).
- `dateoffirstsale` pulled using source column name; aliased to `date_of_first_sale` in DDL only.
- Proforma branch joins `dim_product_dm_hierarchy_tbl ph` directly in `raw_union`. Join key: `upper(p.product) = ph.lookup_map_upper OR upper(concat(p.product, '_', p.direct_ecomm_flag)) = ph.lookup_map_upper`.
- `pf_billings.salesperson_location` now pulled directly as `ns_salesperson_location`.
- `product_for_reporting` = `u.product_for_reporting_ns` (passthrough, no CASE).
- `product_name`, `core_noncore`, `direct_indirect`, `product_name_group` all pulled directly from the union — no CASE logic in `main`.
- `product_group` column: NS branch pulls `ns.product_group`; proforma branch pulls `ph.product_group_map`. Both alias to `product_group`. **When `vw_ns_ss546_new` is updated to expose `product_group_map`, align both branches.**
- `billing_category` (net-new): Direct License / Direct Renewal / Atlassian / SmartBear Ecomm / Uncategorized.
- `pbt_group` (net-new): sourced from `dim_product_dm_hierarchy_tbl`.
- Style: trailing commas, lowercase keywords, `--` comments throughout.

**Validation script — `master_billing_new_validation.sql`:**
- Compares `finance_db.public.master_billing` vs `finance_db.dev_netsuite.master_billing_new`.
- Dimensions: `direct_ecomm_flag`, `direct_indirect`, `product_name`.
- `summary_compare`: total rows and `amount_usd` side-by-side (reporting_status grouping available, commented out).
- `dimension_diffs`: full outer join; `row_count_diff` and `amount_usd_diff`; ordered by `abs(amount_usd_diff) desc`; where filter commented out to show all rows.
- Clean result: 0 rows in `dimension_diffs` with matching totals in `summary_compare`.

**Open items:**
- Fan-out risk on proforma OR join condition — verify no product matches both product-only and compound key.
- `vw_ns_ss546_new` exposes `product_group` not `product_group_map` — align when view is updated.

### 2026-05-18 — master_billing_new: naics_sector sourced from vw_ns_ss546_new

`naics_sector` was previously computed in the final SELECT via a `left join finance_db.dev_netsuite.vw_naics_mapping_new nm on m.naics = to_char(nm.naics_code)`. That join was redundant — `vw_ns_ss546_new` already performs this join and exposes `naics_sector` as an output column.

**Change:** NS branch of `raw_union` now pulls `ns.naics_sector` directly. Proforma branch stubs it as `''`. `main` passes it through as `u.naics_sector`. Final SELECT uses `m.naics_sector` — the `vw_naics_mapping_new` join is removed entirely.

### 2026-05-18 — arr_master_new: first-pass refactor complete

**Table:** `finance_db.dev_netsuite.arr_master_new`
**File:** `SQL Analysis/00_sql_code/new/sp_arr_master_new.sql`
**Status:** First-pass refactor written; not yet validated against `public.arr_master`.

**CTE chain:** `prod_map` → `raw_union` → `main` → final SELECT

**Key changes from original `public.arr_master`:**
- 4-CTE inline SFDC block replaced with single `left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf` in `main`. Field reference updated from `sfdc_ent_core_flag` to `sfdc_core_ent_flag` to match view output.
- NS source: `finance_db.public.vw_ns_ss546` → `finance_db.dev_netsuite.vw_ns_ss546_new`.
- `left join vw_naics_mapping d` removed; `naics_sector` pulled directly from both sources (confirmed in `arr_master_proforma` DDL).
- Original `main` CTE split into `raw_union` (pure union, no joins) and `main` (all joins and derived fields).
- `acv_billings` BUGSNAG branch: `datediff` argument order corrected (was `end, start` — reversed; fixed to `start, end`).
- `transexternalid` guard simplified from `(is not null or <> '')` to `coalesce(...) <> ''`.
- `ordertype1` CASE made multi-line; `else null` added; blank-ordertype fallback ported from `master_billing_new`.
- `product_name_group` and `billing_term` given explicit `else null`.
- All column references qualified with table alias; trailing commas; keywords lowercased throughout.

**ARR_MASTER_PROFORMA DDL reconciliation (05/18/2026):**
Proforma branch column aliases corrected to match actual DDL:
- `vendoramount` → `amount_usd`
- `maintenanceenddate` → `contractitemenddate`
- `maintenancestartdate` → `contractitemstartdate`
- `sbitemcategory` → `sbitemcategory1` (DDL has no trailing `1`)
- `contractdays` → `length_days`
- `externalid` → `transexternalid`
- `contractitemterm` — pulled directly as `a.contractitemterm` (confirmed in DDL after MAINTENANCESTARTDATE)
- `naics_sector` — confirmed in DDL; pulled directly
- `createdfrom`, `pochecknumber`, `productline` — present in DDL but excluded per 01/14/2026 removal

**Validation:** `SQL Analysis/00_sql_code/validation/arr_master_new_validation.sql` — created 05/20/2026.
- Compares `finance_db.public.arr_master` vs `finance_db.dev_netsuite.arr_master_new`.
- Dimensions: `direct_ecomm_flag`, `direct_indirect`, `product_name`.
- `summary_compare`: total rows and `acv` side-by-side (direct_ecomm_flag grouping available, commented out).
- `dimension_diffs`: full outer join; `row_count_diff` and `acv_diff`; ordered by `abs(acv_diff) desc`; where filter commented out to show all rows.

**Open items:**
- Run validation and confirm clean result (0 rows in dimension_diffs, matching totals in summary_compare).
- Confirm whether proforma `contractitemterm` should remain null or be derived from `contractdays`.
- Fan-out risk on `prod_map` join — verify `dim_product_dm_hierarchy_tbl` has unique `productgroup` values before promoting.

**Net effect:** One fewer join in `master_billing_new`; `naics_sector` values are identical to what the view computes.

### 2026-06-29 — arr_master_retention_new: refactor complete

**Procedure:** `finance_db.dev_netsuite.sp_arr_master_retention_new()`
**File:** `SQL Analysis/00_sql_code/new/sp_arr_master_retention_new.sql`
**Target table:** `finance_db.dev_netsuite.arr_master_retention_new`
**Validation:** `SQL Analysis/00_sql_code/validation/arr_master_retention_new_validation.sql`

**CTE chain:** `waterfall_dates` → `dates` → `arr` → `distinct_group` → `filler` → `mth_detail` → `mth_yoy_detail` → `qtr_dates` → `qtr_arr` → `distinct_group_q` → `qtr_filler` → `qtr_detail` → `qtr_yoy_detail` → `main` → final SELECT

**Key changes from original:**
- `join ... on 1=1` (cross join pattern) → explicit `cross join` in `dates`, `qtr_dates`, `filler`, `qtr_filler`
- Dead blank-normalization removed from `filler`/`qtr_filler` — `arr`/`qtr_arr` already normalize upstream
- Table aliases added throughout; `as` keyword added to all column aliases
- `/* */` block comment → `--` style; per-CTE "what" comments removed
- `group by all` retained in final SELECT — required to handle potential fan-out from `dim_product_group_map` join
- `ver_date` retained in `main` union branches (computed as `current_timestamp()` in each branch)
- `sum(m.cur_arr)` retained in window function CASE in final SELECT — works within `group by all` aggregation context
- Alias forward references used for `age`, `age_gup`, `age_pbt` (valid in Snowflake)

**Source:** `finance_db.dev_netsuite.arr_master_waterfall`
**dim_product_group_map note:** Join on `upper(m.productgroup) = upper(p.product_name)` — potential fan-out if dim has duplicate product_name entries; `group by all` handles this.

**Open items:**
- Row count discrepancy vs `arr_master_retention` observed during validation (cur_arr totals match). Likely a timing issue — original table may have been built from a different snapshot of `arr_master_waterfall`. Re-run original SP to refresh baseline, then re-validate.
- Confirm whether `billing_period` threshold difference (`<= 33` in `arr` vs `< 35` in `qtr_arr`) is intentional.

---

### 2026-05-17 — pf_billings structure confirmed

All four product alias fields (`product_for_reporting_ns_alias`, `product_for_reporting_ns_alias_combined`, `product_for_reporting_ns`, `product_for_reporting_group_ns`) are **already populated** in `pf_billings`. `salesperson_location` is populated and now pulled directly. See schema_catalog.md for full column list.

---

## SQL Conventions (this environment)

### Comma Style — UPDATED 05/17/2026
The style guide has been formally updated. **Commas are trailing (end of line), not leading.** All new SQL must use trailing commas. Existing files written with leading commas are not retroactively corrected unless a file is being substantially rewritten.

```sql
-- correct
select
    o.order_id,
    o.customer_name,
    o.amount

-- incorrect
select
    o.order_id
    , o.customer_name
    , o.amount
```

### Database & Schemas

- **Database:** `finance_db`
- **Schemas:**
  - `finance_db.public` — production schema
  - `finance_db.dev_netsuite` — development schema (assume this for all new/rewritten code)
  - `finance_db.ingest` — staging tables; always reference as-is regardless of context
- **Default schema for rewrites:** `finance_db.dev_netsuite` — all `create or replace view` statements and all references to non-INGEST tables should use `dev_netsuite` unless explicitly told otherwise.
- `public` and `dev_netsuite` should mirror each other in theory but may drift — do not assume they are identical.

### Table & Filter Patterns

- `ver_date` pattern: filter to `max(ver_date)` to get latest snapshot from staging tables
- `finance_db.public.dim_globalultimateparent_map`: join on `upper(globalultimateparent) = upper(globalultimateparent_orig)` — always reference from `public`, not `dev_netsuite`
- `finance_db.public.dim_product_dm_hierarchy_tbl`: join on `upper(concat(sisense_product_rollup_calc,'_',direct_ecomm_flag)) = lookup_map_upper` — always reference from `public`, not `dev_netsuite`. For proforma joins where no `sisense_product_rollup_calc` exists, use: `upper(p.product) = ph.lookup_map_upper OR upper(concat(p.product, '_', p.direct_ecomm_flag)) = ph.lookup_map_upper`. Watch for fan-out if both keys match.
- `finance_db.public.dim_country_map`: join on `u.ship_country = scm.original_country`. Outputs `mapped_subregion` (geo_2) and `mapped_region` (geo_1).
- `finance_db.public.pf_billings`: no snapshot filter — assumed full table scan. No invoice number column.

### Column Name Watchpoints

- `dateoffirstsale` — actual column name in `vw_ns_ss546_new`. Do NOT alias to `date_of_first_sale` in the union branch; use the raw name and let the DDL column position handle it.
- `product_group` vs `product_group_map` — `vw_ns_ss546_new` currently exposes `product_group`; `dim_product_dm_hierarchy_tbl` has `product_group_map`. Both surfaces must be aligned when the view is updated.
- `inline_discount` — `vw_ns_ss546_new` outputs a clean decimal (already divided by 100); no empty-string guard needed. `public.vw_ns_ss546` returned a raw string and required the guard.

### Union Branch Column Parity (added 05/20/2026)

When reviewing or writing any `union all`, always verify:
1. **Column count matches** across all branches — Snowflake will error if counts differ, but silent positional mismatches (same count, wrong order) are harder to catch.
2. **Column order matches** — list both branches side by side mentally or in a script and confirm position-by-position that aliases align.
3. **Type compatibility** — flag where one branch uses `try_to_number(x)` and the other passes a raw column that may be a different type.
4. Flag any branch that passes `acv_billings` / `acv` as pre-computed values (from a source table) while the other branch computes them inline — document which is which in a comment.

### Snowflake Column Alias Reference (confirmed 05/21/2026)

Snowflake allows a column alias defined earlier in the same SELECT list to be referenced by subsequent expressions in the same SELECT list. This applies both within a single SELECT and within a CTE's SELECT. A separate CTE is only needed when a column depends on one defined *after* it in the same SELECT list.

```sql
-- valid in Snowflake — direct_ecomm_flag referenced later in the same SELECT
select
    case when ... end as direct_ecomm_flag,
    case when direct_ecomm_flag = 'Ecomm' then ... end as product_name
from raw_union u
```

This also means a `join on` clause **cannot** reference a SELECT-list alias from the same CTE — join conditions are evaluated before the SELECT list resolves. To use a calculated value as a join key, resolve it in a prior CTE first.

### Style Guide (as of 05/17/2026)

Full style guide saved externally by Dan. Key rules for generated SQL:
- **Keywords:** lowercase (`select`, `from`, `where`, `join`, etc.)
- **Commas:** trailing (end of line) — not leading
- **Indentation:** 4 spaces
- **Aliases:** immediately after expression, no padding (`sum(x) as total`, not `sum(x)    as total`)
- **CASE:** always multi-line; `end as col_name` on the closing line; always include `else`
- **Column refs:** always qualified with table alias — no bare column names
- **JOIN type:** always explicit (`inner join`, `left join`) — never bare `join`
- **SELECT \*:** never permitted
- **CTEs:** preferred over subqueries; raw/union CTEs contain only typed raw columns and snapshot filters — no joins, no calculations
- **Comments:** `--` only; `//` not permitted
