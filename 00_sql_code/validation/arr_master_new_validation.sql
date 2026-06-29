/*==============================================================================
  Validation Query — arr_master_new
  Purpose     Compare finance_db.public.arr_master (original) against
              finance_db.dev_netsuite.arr_master_new (refactored) to confirm
              consistent results across record counts, amounts, and the key
              product classification dimensions (direct_ecomm_flag,
              direct_indirect, product_name) that were refactored as part of
              the 05/18/2026 style and structural overhaul.
  Usage       Run all CTEs together. Review the result sets:
                - summary_compare   : total rows and acv side by side for
                                      ORIGINAL and NEW
                - dimension_diffs   : any dimension combo where the two tables
                                      disagree on row count or acv
              A clean result has 0 rows in dimension_diffs and matching totals
              in summary_compare.
  Owner       Dan Girard
  Created     05/20/2026
==============================================================================*/
with

original as (
    select
        am.direct_ecomm_flag,
        am.direct_indirect,
        am.product_name,
        count(*) as row_count,
        sum(am.acv) as total_acv
    from finance_db.public.arr_master am
    group by all
),

new as (
    select
        amn.direct_ecomm_flag,
        amn.direct_indirect,
        amn.product_name,
        count(*) as row_count,
        sum(amn.acv) as total_acv
    from finance_db.dev_netsuite.arr_master_new amn
    group by all
),

-- ============================================================================
-- summary_compare: top-level row count and acv, both tables side by side.
-- Totals should match between ORIGINAL and NEW.
-- Uncomment the reporting_status lines to break out by datasource_group.
-- ============================================================================
summary_compare as (
    select
        'ORIGINAL' as source,
        -- o.direct_ecomm_flag,
        round(sum(o.row_count), 2) as total_rows,
        round(sum(o.total_acv), 2) as total_acv
    from original o
    -- group by o.direct_ecomm_flag

    union all

    select
        'NEW' as source,
        -- n.direct_ecomm_flag,
        round(sum(n.row_count), 2) as total_rows,
        round(sum(n.total_acv), 2) as total_acv
    from new n
    -- group by n.direct_ecomm_flag
),

-- ============================================================================
-- dimension_diffs: full outer join on all three dimension columns.
-- Any row returned here is a discrepancy between the two tables.
-- Sort by abs(acv_diff) desc to surface the largest gaps first.
-- Uncomment the where clause to filter to rows with actual differences only.
-- ============================================================================
dimension_diffs as (
    select
        coalesce(o.direct_ecomm_flag, n.direct_ecomm_flag) as direct_ecomm_flag,
        coalesce(o.direct_indirect, n.direct_indirect) as direct_indirect,
        coalesce(o.product_name, n.product_name) as product_name,
        o.row_count as orig_row_count,
        n.row_count as new_row_count,
        coalesce(o.row_count, 0) - coalesce(n.row_count, 0) as row_count_diff,
        round(o.total_acv, 2) as orig_acv,
        round(n.total_acv, 2) as new_acv,
        coalesce(round(o.total_acv, 2), 0) - coalesce(round(n.total_acv, 2), 0) as acv_diff
    from original o
        full outer join new n
            on o.direct_ecomm_flag = n.direct_ecomm_flag
            and o.direct_indirect = n.direct_indirect
            and o.product_name = n.product_name
    -- where coalesce(o.row_count, 0)           <> coalesce(n.row_count, 0)
    --    or coalesce(round(o.total_acv, 2), 0) <> coalesce(round(n.total_acv, 2), 0)
)

-- ============================================================================
-- Run one result set at a time. Comment out whichever you don't need.
-- ============================================================================

-- 1. Top-level summary (ORIGINAL vs NEW totals should match)
-- select * from summary_compare;

-- 2. Dimension-level diffs (0 rows = tables are consistent)
select * from dimension_diffs order by abs(acv_diff) desc;
