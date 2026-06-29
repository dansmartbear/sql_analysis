/*==============================================================================
  Validation Query — arr_master_waterfall_new
  Purpose     Compare finance_db.public.arr_master_waterfall (original)
              against finance_db.dev_netsuite.arr_master_waterfall_new
              (refactored) to confirm consistent results across record
              counts, acv totals, and the three computed classification
              dimensions added by the waterfall query: source,
              productgroup, and product_group_rollup.
  Usage       Run all CTEs together. Review the result sets:
                - summary_compare   : total rows and acv side by side for
                                      ORIGINAL and NEW
                - dimension_diffs   : any dimension combo where the two
                                      tables disagree on row count or acv
              A clean result has 0 rows in dimension_diffs and matching
              totals in summary_compare.
  Owner       Dan Girard
  Created     06/29/2026
==============================================================================*/
with

original as (
    select
        wf.source,
        wf.productgroup,
        wf.product_group_rollup,
        count(*) as row_count,
        sum(wf.acv) as total_acv
    from finance_db.public.arr_master_waterfall wf
    group by all
),

new as (
    select
        wfn.source,
        wfn.productgroup,
        wfn.product_group_rollup,
        count(*) as row_count,
        sum(wfn.acv) as total_acv
    from finance_db.dev_netsuite.arr_master_waterfall_new wfn
    group by all
),

-- ============================================================================
-- summary_compare: top-level row count and acv, both tables side by side.
-- Totals should match between ORIGINAL and NEW.
-- Uncomment the source lines to break out by source classification.
-- ============================================================================
summary_compare as (
    select
        'ORIGINAL' as version,
        -- o.source,
        round(sum(o.row_count), 2) as total_rows,
        round(sum(o.total_acv), 2) as total_acv
    from original o
    -- group by o.source

    union all

    select
        'NEW' as version,
        -- n.source,
        round(sum(n.row_count), 2) as total_rows,
        round(sum(n.total_acv), 2) as total_acv
    from new n
    -- group by n.source
),

-- ============================================================================
-- dimension_diffs: full outer join on all three computed dimension columns.
-- Any row returned here is a discrepancy between the two tables.
-- Sort by abs(acv_diff) desc to surface the largest gaps first.
-- Uncomment the where clause to filter to rows with actual differences only.
-- ============================================================================
dimension_diffs as (
    select
        coalesce(o.source, n.source) as source,
        coalesce(o.productgroup, n.productgroup) as productgroup,
        coalesce(o.product_group_rollup, n.product_group_rollup) as product_group_rollup,
        o.row_count as orig_row_count,
        n.row_count as new_row_count,
        coalesce(o.row_count, 0) - coalesce(n.row_count, 0) as row_count_diff,
        round(o.total_acv, 2) as orig_acv,
        round(n.total_acv, 2) as new_acv,
        coalesce(round(o.total_acv, 2), 0) - coalesce(round(n.total_acv, 2), 0) as acv_diff
    from original o
        full outer join new n
            on o.source = n.source
            and o.productgroup = n.productgroup
            and o.product_group_rollup = n.product_group_rollup
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
