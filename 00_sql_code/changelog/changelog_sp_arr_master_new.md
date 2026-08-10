# Changelog: sp_arr_master → sp_arr_master_new

**Comparing:** `finance_db.public.arr_master` (original) vs. `finance_db.dev_netsuite.arr_master_new`

## Structural
- CTE chain restructured to `prod_map` → `raw_union` → `main` → final SELECT. Original `main` split into a pure `raw_union` (no joins) and `main` (all joins and derived fields).
- 4-CTE inline SFDC block replaced with a single `left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf` in `main`.
- `left join vw_naics_mapping d` removed — `naics_sector` now pulled directly from both the NS and proforma sources.

## Source repointing
- NetSuite source: `finance_db.public.vw_ns_ss546` → `finance_db.dev_netsuite.vw_ns_ss546_new`.
- SFDC field reference updated: `sfdc_ent_core_flag` → `sfdc_core_ent_flag` to match the new SFDC view's output.

## Logic fixes
- `acv_billings` BUGSNAG branch: `datediff` argument order corrected — was `(end, start)`, reversed to `(start, end)`.
- `transexternalid` guard simplified from `(is not null or <> '')` to `coalesce(...) <> ''`.
- `product_name_group` CASE gained `when product_name in ('BearQ') then 'BearQ'` (07/29/2026 cleanup pass).
- `ordertype1` CASE made multi-line with `else null` added; blank-ordertype fallback ported over from `master_billing_new`.
- `product_name_group` and `billing_term` given explicit `else null` (previously implicit).

## Proforma column reconciliation (against `arr_master_proforma` DDL)
Several proforma branch aliases were corrected to match the actual source DDL rather than the assumed names:
- `vendoramount` → `amount_usd`
- `maintenanceenddate`/`maintenancestartdate` → `contractitemenddate`/`contractitemstartdate`
- `sbitemcategory` → `sbitemcategory1`
- `contractdays` → `length_days`
- `externalid` → `transexternalid`
- `createdfrom`, `pochecknumber`, `productline` excluded per prior 01/14/2026 removal decision

## Gap vs. production (corrected 08/10/2026)
- **`transaction_id` and `boomi_external_id` are missing from the output — but the fix is smaller than previously reported.** Production `public.arr_master` added these on 07/06/2026 (`ns.transaction_id`, `ns.boomi_external_id`, threaded through the proforma stub and final SELECT). `arr_master_new` already joins `vw_ns_ss546_new` as `ns` in the NS branch, and that view **already exposes both columns** (an earlier version of this changelog incorrectly said it didn't). The gap is simply that `sp_arr_master_new`'s SELECT list never references `ns.transaction_id`/`ns.boomi_external_id` — they're available at the join, just not pulled through. Fix: add both columns to the NS branch of `raw_union`, stub them in the proforma branch (`'' as transaction_id`, `'' as boomi_external_id`, matching the pattern used for other NS-only fields), and pass through in `main` and the final SELECT.
- This also blocks `arr_master_waterfall_new`, which reads from `arr_master_new` and inherits the same gap — fixing it here resolves waterfall too, no separate waterfall change needed.

## Style
- All column references alias-qualified; trailing commas; keywords lowercased throughout.

## Validation
`00_sql_code/validation/arr_master_new_validation.sql` — baselined against `finance_db.dev_netsuite.arr_master` (not `public`, per Dan's 07/20/2026 confirmation). Dimensions: `direct_ecomm_flag`, `direct_indirect`, `product_name`.

## Open items
- Run/confirm validation is clean (0 rows in `dimension_diffs`, matching totals in `summary_compare`).
- Confirm whether proforma `contractitemterm` should remain null or be derived from `contractdays`.
- Fan-out risk on `prod_map` join — verify `dim_product_dm_hierarchy_tbl` has unique `productgroup` values before promoting.
