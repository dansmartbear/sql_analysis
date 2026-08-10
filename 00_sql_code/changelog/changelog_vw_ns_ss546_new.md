# Changelog: vw_ns_ss546 → vw_ns_ss546_new

**Comparing:** `finance_db.public.vw_ns_ss546` (original) vs. `finance_db.dev_netsuite.vw_ns_ss546_new`

## Structural
- CTE chain restructured to `employee_max` → `raw_union` → `main` → final SELECT. Raw union CTE now contains only typed raw columns and snapshot filters — no calcs, no joins.
- `type_calc`, `sisense_product_rollup_calc`, the GUP join, and direct_ecomm logic moved out of the union and into `main`.
- `max(ver_date)` for the employee lookup pre-computed in its own `employee_max` CTE instead of a correlated subquery.

## Column changes
- Removed from SQL logic entirely: `product_name`, `direct_indirect`, `core_noncore`, and related product dimension columns — no longer computed with CASE logic, now sourced via join to `dim_product_dm_hierarchy_tbl`.
- Added: `product_hub`, `product_parent`, `pbt_group`, `ai` (new columns exposed from the product hierarchy join).
- Added: `naics_sector` — new `left join vw_naics_mapping_new n`, output as `concat(n.naics_sector_code, ' - ', n.naics_sector)`. Original `naics` column retained unchanged.
- `inline_discount` now returns a clean decimal (pre-divided) rather than a raw string requiring a downstream empty-string guard.

## Correction (08/10/2026)
An earlier version of this changelog claimed `transaction_id`/`boomi_external_id` were missing from `vw_ns_ss546_new`. That was wrong — caused by a `&&`-chained grep that silently short-circuited before checking this file. **`vw_ns_ss546_new` already outputs both columns** (added 06/23/2026, confirmed present in the current file). No gap exists here. See `changelog_sp_arr_master_new.md` and `changelog_sp_master_billing_new.md` for where the real gap actually is (downstream, not in this view).

## Style
- All column references qualified with table alias; keywords lowercased; trailing commas throughout.

## Validation
`00_sql_code/validation/vw_ns_ss546_new_validation.sql` — dimension diffs and summary totals passed (05/15/2026); NAICS sector checks added 05/15/2026.
