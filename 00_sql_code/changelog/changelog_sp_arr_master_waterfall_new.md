# Changelog: sp_arr_master_waterfall → sp_arr_master_waterfall_new

**Comparing:** `finance_db.public.arr_master_waterfall` (original) vs. `finance_db.dev_netsuite.arr_master_waterfall_new`

## Structural
- Inline `select distinct month_start, month_end from data_master_db.public.dimdate` subquery in the join moved out to its own `dim_date` CTE, per the CTE-over-subquery convention.
- `dd.*` replaced with explicit `dd.month_start, dd.month_end` — no wildcard selects.
- Stored-procedure wrapper had briefly been left commented out while the body was not, leaving the file syntactically invalid. Wrapper (`create or replace procedure ... as $$ begin` / closing `end; $$`) has been restored — the file now runs as a valid procedure.

## Source repointing
- Source table: `finance_db.public.arr_master` → `finance_db.dev_netsuite.arr_master_new`.
- Because of this, `arr.region as ship_region` (original) becomes a direct `arr.ship_region` pull — `arr_master_new` already exposes it under that name.

## Logic fixes / cleanup
- Every bare column reference qualified with the `arr.` alias: `source` in the PACTFLOW_PF branch, `productgroup` in the final `else`, `sfdc_ent_core_flag`, `billing_term`, `pbt_group`, `datasource_group`, `sfdc_name`.
- `current_timestamp` → `current_timestamp()` as `ver_date` (function-call syntax).
- `productgroup_child` and `product_group_rollup` still correctly reference the computed `productgroup` alias from earlier in the same SELECT (valid Snowflake behavior) — preserved, not accidentally "fixed" to `arr.productgroup`.

## Gap vs. production (corrected 08/10/2026)
- **`transaction_id` and `boomi_external_id` are missing** — inherited secondhand. Production `public.arr_master_waterfall` added these on 07/06/2026 (`arr.transaction_id`, `arr.boomi_external_id` in the final SELECT). `arr_master_waterfall_new` doesn't carry them purely because its source, `arr_master_new`, doesn't select them yet (see that changelog for the actual root cause — `vw_ns_ss546_new` already has the columns available; `arr_master_new` just isn't pulling them through the join). Once `arr_master_new` is fixed, add `arr.transaction_id, arr.boomi_external_id` to this file's final SELECT to complete the thread.

## Style
- Keywords lowercased; trailing commas; 4-space indentation throughout.

## Validation
`00_sql_code/validation/arr_master_waterfall_new_validation.sql` — baselined against `finance_db.dev_netsuite.arr_master_waterfall` (per Dan's 07/20/2026 confirmation, consistent with the other two `_new` validations).

## Uncommitted, working-tree only (as of 08/10/2026 rescan)
- An active (not commented-out) scratch query was appended after the closing `$$` — `select * from finance_db.dev_netsuite.arr_master_waterfall where productgroup = 'BearQ'`. It's outside the procedure body, so it doesn't change the procedure's logic, but unlike the retention file's version this one isn't commented out — it will actually execute if the file is run as-is. Worth stripping before this file is committed or deployed.
