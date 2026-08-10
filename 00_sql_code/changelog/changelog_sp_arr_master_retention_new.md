# Changelog: sp_arr_master_retention → sp_arr_master_retention_new

**Comparing:** `finance_db.public.arr_master_retention` (original) vs. `finance_db.dev_netsuite.arr_master_retention_new`

## Structural
- Full CTE chain rebuilt/expanded: `waterfall_dates` → `dates` → `arr` → `distinct_group` → `filler` → `mth_detail` → `mth_yoy_detail` → `qtr_dates` → `qtr_arr` → `distinct_group_q` → `qtr_filler` → `qtr_detail` → `qtr_yoy_detail` → `main` → final SELECT.
- `join ... on 1=1` cross-join pattern replaced with explicit `cross join` in `dates`, `qtr_dates`, `filler`, `qtr_filler`.
- Dead blank-normalization logic removed from `filler`/`qtr_filler` — redundant, since `arr`/`qtr_arr` already normalize upstream.
- `/* */` block comments converted to `--` style; per-CTE "what it does" comments removed as redundant with the CTE names.
- `group by all` retained in the final SELECT to absorb potential fan-out from the `dim_product_group_map` join.

## Source repointing
- Source table: `finance_db.dev_netsuite.arr_master_waterfall` (legacy dev pointer) → `finance_db.dev_netsuite.arr_master_waterfall_new` (3 references + docstring updated, 07/29/2026 cleanup pass) — retention now reads from the actual `_new` waterfall table instead of a stale intermediate.

## Style
- Table aliases added throughout (previously several unaliased references); `as` keyword added to all column aliases.
- Alias forward references used for `age`, `age_gup`, `age_pbt` (valid Snowflake pattern, consistent with the rest of the refactor effort).

## No gap
- Retention doesn't touch `transaction_id`/`boomi_external_id` in either version — the missing-columns issue affecting `arr_master_new`, `master_billing_new`, and `arr_master_waterfall_new` does **not** apply here.

## Validation
`00_sql_code/validation/arr_master_retention_new_validation.sql` — baselined against `finance_db.dev_netsuite.arr_master_retention` (has been since inception, unlike the other two `_new` validations which were repointed later).

## Open items
- Row-count discrepancy vs. `arr_master_retention` observed during validation, though `cur_arr` totals match — likely a snapshot-timing difference (original table possibly built from a different `arr_master_waterfall` snapshot). Re-run the original SP to refresh the baseline, then re-validate.
- Confirm whether the `billing_period` threshold difference (`<= 33` in `arr` vs. `< 35` in `qtr_arr`) is intentional.
- `dimension_diffs`' `where` filter in the validation script was uncommented to show only row-count mismatches (`where coalesce(o.row_count,0) <> coalesce(n.row_count,0)`), diverging from the other two `_new` validations which still surface all rows — not yet confirmed intentional.

## Uncommitted, working-tree only (as of 08/10/2026 rescan)
- A commented-out scratch query (`-- select * from finance_db.dev_netsuite.arr_master_retention_new;`) was appended after the closing `$$;`. It's outside the procedure body and commented out — no functional or logic change. Flagging only because it's unstaged; strip before commit if it's not meant to stick around.
