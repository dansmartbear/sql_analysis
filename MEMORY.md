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

### 2026-07-20 — original/ files refreshed to match live PUBLIC production

`sp_arr_master.sql`, `sp_arr_master_retention.sql`, `sp_arr_master_waterfall.sql`, `sp_master_billing.sql`, and `vw_ns_ss546.sql` in `00_sql_code/original/` were updated to reflect what's currently deployed in `finance_db.public`. This is a resync of the reference copies, not new dev work.

**Why:** Dan confirmed the `dev_netsuite` → `public` schema-reference reversion in the four SPs was deliberate — it matches what's actually running in `public` today, not a regression against the `_new`/`dev_netsuite` refactor effort.

**How to apply:** The `dev_netsuite`-suffixed (`_new`) objects (`arr_master_new`, `master_billing_new`, `vw_ns_ss546_new`, etc.) are now behind production on these points — check before assuming parity:
- `transaction_id`/`boomi_external_id`: **`vw_ns_ss546_new` already has these** (added 06/23/2026, confirmed present as of 08/10/2026 — corrects an earlier session's mistaken claim that the view was missing them, which came from a `&&`-chained grep that silently short-circuited). The actual gap is downstream: `sp_arr_master_new` and `sp_master_billing_new` both join `vw_ns_ss546_new` (alias `ns`) but never select `ns.transaction_id`/`ns.boomi_external_id` into their output. `sp_arr_master_waterfall_new` inherits the gap secondhand since it sources from `arr_master_new`. **Status 08/10/2026: closed in `sp_master_billing_new` (via `max()` — see that entry). Still open in `sp_arr_master_new` and, downstream of it, `sp_arr_master_waterfall_new`.** Check whether `arr_master_new`'s equivalent CTE also aggregates under `group by all` before adding them as plain columns.
- `vw_ns_ss546`: `inline_discount` now `coalesce(to_double(inline_discount),0)` in the raw union (was a raw passthrough). `master_billing`'s inline_discount guard was simplified to rely on this.
- `sp_arr_master`: `product_name_group` CASE gained an `else product_name` fallback (was previously implicit null).

Before resuming any `_new` refactor work on these objects, port these production changes over first.

### 2026-08-10 — original/ rescan: cosmetic-only, plus out-of-scope vw_elt_metrics rewrite

Rescanned `00_sql_code/original/` against git HEAD. Findings for the 5 tracked queries: no functional changes.
- `sp_arr_master.sql`: one blank line removed inside the `main` CTE — whitespace only.
- `sp_arr_master_retention.sql` / `sp_master_billing.sql`: header docstring comments corrected from `dev_netsuite` to `public` (the actual `create table`/`create or replace procedure` targets were already `public`; only the comment text was stale). No code change.
- `sp_arr_master_waterfall.sql`, `vw_ns_ss546.sql`: unchanged.

**Not one of the 5 tracked queries, but flagging since it's in `original/`:** `vw_elt_metrics.sql` was substantially rewritten — `fifth_bd`/`anchor_date` CTEs replaced by a join to a new `finance_db.public.vw_elt_metrics_anchor_date` object; added `final` CTE; added `elt_metrics_id` (row_number), `record_id` and `row_hash` (both `md5` hashes over key dimension/measure columns) replacing the old `uuid_string()` PK. No `_new` counterpart exists yet — out of current refactor scope, but worth a look if this view feeds anything Dan cares about.

### 2026-07-20 — validation baselines intentionally repointed to dev_netsuite

`arr_master_new_validation.sql` and `arr_master_waterfall_new_validation.sql` had their `original` CTE source changed from `finance_db.public.arr_master(_waterfall)` to `finance_db.dev_netsuite.arr_master(_waterfall)`. Dan confirmed this was deliberate, not a mistake.

**Why:** Not stated beyond "intentional" — worth asking again if it comes up, but treat `dev_netsuite.arr_master`/`arr_master_waterfall` as the correct baseline for these two validations going forward, matching `arr_master_retention_new_validation.sql` (which was always baselined against `dev_netsuite.arr_master_retention`).

**How to apply:** All three `_new` validation files now consistently baseline against `dev_netsuite`, not `public`. Header docstrings in `arr_master_new_validation.sql` and `arr_master_waterfall_new_validation.sql` were updated to match (previously said `public`, now say `dev_netsuite`).

**Still open:** `arr_master_retention_new_validation.sql`'s `dimension_diffs` `where` filter was uncommented (`where coalesce(o.row_count,0) <> coalesce(n.row_count,0)`) — now only surfaces row-count mismatches, not amount-only diffs, and differs from the other two files which still dump all rows. Not yet confirmed whether this is intentional.

### 2026-07-29 — arr_master_new/waterfall_new/retention_new: cleanup pass

- **`sp_arr_master_new.sql`**: `product_name_group` CASE gained `when product_name in ('BearQ') then 'BearQ'`.
- **`sp_arr_master_waterfall_new.sql`**: the `create or replace procedure ... as $$ begin` wrapper had been commented out while the body and closing `end; $$` were not — the file was syntactically invalid. Wrapper uncommented; file is now a valid, runnable procedure.
- **`sp_arr_master_retention_new.sql`**: source table repointed from `finance_db.dev_netsuite.arr_master_waterfall` (legacy) to `finance_db.dev_netsuite.arr_master_waterfall_new` (3 references + docstring) — retention now reads from the actual `_new` waterfall table.

### 2026-08-10 — vw_master_billing_new: straight copy, repoint + rename only

**View:** `finance_db.dev_netsuite.vw_master_billing_new`
**File:** `SQL Analysis/00_sql_code/new/vw_master_billing_new.sql`
**Changelog:** `SQL Analysis/00_sql_code/changelog/changelog_vw_master_billing_new.md`
**Validation:** `SQL Analysis/00_sql_code/validation/vw_master_billing_new_validation.sql` — written 08/10/2026, not yet run.
Deliberately the same shape as `master_billing_new_validation.sql`: `original` / `new` aggregate CTEs → `summary_compare` + `dimension_diffs`, dimensions `direct_ecomm_flag`, `direct_indirect`, `product_name`, `naics_sector`, `ship_region`. Clean = 0 rows in `dimension_diffs`, matching totals in `summary_compare`. Scaffold rows fold into the aggregates — a scaffold cardinality change still shows up as a `row_count` diff, so no separate scaffold check is needed.

**Approach — Dan's call, and the one to repeat.** An optimized rewrite was built first, then discarded in favour of a straight copy of the original with only the mechanical changes applied. Default to minimal-change repoints on this family of objects unless Dan asks for optimization; the analysis behind the rejected optimizations is preserved under "Deferred work" in the changelog rather than in the SQL.

**The complete change list** (a `diff` against `original/vw_master_billing.sql` shows nothing else):
1. View target → `finance_db.dev_netsuite.vw_master_billing_new`.
2. Base table, 2 refs (`scaffold` and `combined` CTEs) → `finance_db.dev_netsuite.master_billing_new`.
3. `product_group` → `productgroup`, 3 refs.
4. `entity` omitted, 3 refs — `master_billing_new` doesn't carry it. Output 116 → 115 columns; order of the remaining 115 unchanged. `transaction_id` and `boomi_external_id` are present.
5. Dated header comment line.

**`dim_product_dm_hierarchy_tbl` stayed on `public`** per the standing rule — the `pbt_group` join is untouched. CTE chain unchanged: `date_scaff` → `scaffold` → `combined` → final SELECT.

**What the validation actually tests:** the view logic is identical to the original's, so any diff means `master_billing_new` and `master_billing` disagree. It's a test of the two base tables through identical logic, not of the view. Diagnose failures in `master_billing_new_validation.sql`.

**Open items:**
- **`entity` is the only remaining parity gap.** `transaction_id` / `boomi_external_id` landed 08/10/2026 — see the `sp_master_billing_new` entry below. Closing `entity` takes `ns.entitynohierarchy as entity` / `'Proforma'` in `raw_union`, the DDL and final SELECT, plus 2 lines in the view. Low grain risk (low cardinality, likely functionally dependent on existing keys) so a plain column is probably safe.
- `productgroup` rename is surfaced to consumers — downstream Tableau/Sisense field references need updating at promotion.
- `stream_reporting` is null on scaffold rows. The 01/23/2026 change made it a scaffold dimension (so it constrains which scaffold rows exist) but the scaffold branch of `combined` emits `null stream_reporting` — the value never reaches the output. The change only half-landed. Present in the original, preserved here. Confirm whether emitting it was the intent.
- Known-but-unaddressed in this view, detailed in the changelog: the `select distinct` after the cross join, the `row_number()` full sort, the now-redundant `pbt_group` join, and two untyped-null / numeric-vs-varchar union quirks.

**First validation run, 08/10/2026 — ~200 fewer rows in `new`, `total_amount_usd` exact.** Diagnosis in progress. Scaffold cardinality is the leading cause and the pairing is close to a signature: scaffold rows carry `null amount_usd`, so losing them moves row count without moving a dollar. Measured: `master_billing_new` has **44 fewer distinct qualifying scaffold dimension combinations** than `master_billing`. `date_scaff` emits 4 rows as of Aug 2026 (it filters to the current calendar year → Sep–Dec), so 44 × 4 = 176, leaving a possible residual.

**The reusable insight:** `scaffold` is a `select distinct` over 15 dimension columns with an `is not null` filter on **all 15**. `master_billing_new_validation.sql` only compares 3 of them (`direct_ecomm_flag`, `direct_indirect`, `product_name`) — so the base tables can validate clean while the view's row count still diverges. One extra null in any of the other 12 drops a scaffold row; a combination that stops appearing costs 4. Prime suspect is the refactor's shift from CASE logic to a `dim_product_dm_hierarchy_tbl` join for product dimensions: a join miss yields null where the CASE had an `else` fallback.

**Next step:** split the gap by `ver_date is null` (scaffold) vs `not null` (base) — `ver_date` is the clean discriminator since the scaffold branch stubs it null. Base half = 0 means the gap is entirely scaffold (benign for totals, but 44 combos lose their forced zero row for Sep–Dec 2026, so downstream views relying on the scaffold to render a visible zero show a gap instead). Base half > 0 means real billing rows are missing whose amounts net to zero — offsetting credits/debits — and that's an SP problem. Then per-column null comparison across the 12 uncompared dimensions.

### 2026-08-10 — sp_master_billing_new: transaction_id / boomi_external_id added via max()

**File:** `SQL Analysis/00_sql_code/new/sp_master_billing_new.sql`
**Changelog:** `SQL Analysis/00_sql_code/changelog/changelog_sp_master_billing_new.md`

Both columns `varchar(500)`, at 4 touch points: DDL (appended after `pbt_group`), both `raw_union` branches (`ns.*` / `''` stubs), `main` (as `max()`), final SELECT. DDL and final SELECT both 114 columns, positionally aligned. `entity` deliberately not added. Dan confirmed the rebuilt table matches the original.

**The insight worth keeping — `group by all` in `main` is a trap.** `main` computes `sum(u.amount_usd)`, `sum(u.amount)`, `sum(u.acv)`, `sum(u.my)` under `group by all`, so **every non-aggregated column in its SELECT list silently becomes a grouping key.** A first attempt added the ids as plain columns and broke validation — `transaction_id` split groups that previously collapsed, changing row counts and the per-row sums. `max()` keeps them out of the grouping set. Any future column added to `main` needs the same decision.

**Corollary: `max()` is lossy.** Because the plain-column version *did* change the output, `transaction_id` demonstrably varies within existing groups — some billing lines span multiple NetSuite transactions and only one id is reported. Unquantified; diagnostic in the changelog. Production has the same `group by all` *and* these columns as plain keys, so production's grain already reflects the fragmentation.

**Validation baseline caveat:** `dev_netsuite.master_billing` was built from an older SP and lags production. Keep that in mind when a diff looks like a regression.

**Static parity checks earned their keep** on this change: union branch column count/order, and DDL vs. final SELECT positional alignment. Same-count/wrong-order fails silently in both a union and a CTAS. Note that ad-hoc regex column parsers throw false positives on multi-line `CASE` blocks, `row_number() over (order by ...)` lists, and `null as x` — use a paren-depth-aware accumulator.

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

- `dateoffirstsale` — actual column name in `vw_ns_ss546_new`. Do NOT alias to `date_of_first_sale` in the union branch; use the raw name and let the DDL column position handle it. **Consequence:** `master_billing_new`'s own column is named `date_of_first_sale` (that's what its DDL declares); `dateoffirstsale` never becomes a table column name, it only lives inside the SP's CTE chain. Anything reading `master_billing_new` must use `date_of_first_sale`. Easy to misread as a rename — it isn't one.
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
