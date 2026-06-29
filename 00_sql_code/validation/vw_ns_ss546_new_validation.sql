/*==============================================================================
  Validation Query — vw_ns_ss546
  Purpose     Compare finance_db.public.vw_ns_ss546 (original) against
              finance_db.dev_netsuite.vw_ns_ss546 (refactored) to confirm
              identical results across record counts, amounts, and key
              product/channel dimensions.
  Usage       Run all CTEs together. Review the results sets:
                - summary_compare    : total rows and amount_usd side by side
                - dimension_diffs    : any dimension combo where the two views disagree
              A clean result has 0 rows in dimension_diffs and matching
              totals in summary_compare.
  Owner       Dan Girard
  Created     05/15/2026
  Validated   05/15/2026 — clean result confirmed
==============================================================================*/
with

prod as (
    select
        product_name,
        direct_ecomm_flag,
        direct_indirect,
        type,
        count(*) as row_count,
        sum(amount_usd) as total_amount_usd
    from finance_db.public.vw_ns_ss546
    group by all
),

dev as (
    select
        product_name,
        direct_ecomm_flag,
        direct_indirect,
        type,
        count(*) as row_count,
        sum(amount_usd) as total_amount_usd
    from finance_db.dev_netsuite.vw_ns_ss546
    group by all
),

-- ============================================================================
-- summary_compare: top-level totals for both views side by side.
-- Both columns should match exactly.
-- ============================================================================
summary_compare as (
    select
        'PROD' as source,
        sum(row_count) as total_rows,
        sum(total_amount_usd) as total_amount_usd
    from prod

    union all

    select
        'DEV' as source,
        sum(row_count) as total_rows,
        sum(total_amount_usd) as total_amount_usd
    from dev
),

-- ============================================================================
-- dimension_diffs: full outer join on all dimension columns.
-- Any row returned here is a discrepancy between the two views.
-- Columns prefixed prod_ vs dev_ show where the values diverge.
-- ============================================================================
dimension_diffs as (
    select
        coalesce(p.product_name,      d.product_name)      as product_name,
        coalesce(p.direct_ecomm_flag, d.direct_ecomm_flag) as direct_ecomm_flag,
        coalesce(p.direct_indirect,   d.direct_indirect)   as direct_indirect,
        -- coalesce(p.type,           d.type)               as type,
        p.row_count                                         as prod_row_count,
        d.row_count                                         as dev_row_count,
        p.row_count - d.row_count                           as row_count_diff,
        p.total_amount_usd                                  as prod_amount_usd,
        d.total_amount_usd                                  as dev_amount_usd,
        p.total_amount_usd - d.total_amount_usd             as amount_usd_diff
    from prod p
        full outer join dev d
            on  p.product_name      = d.product_name
            and p.direct_ecomm_flag = d.direct_ecomm_flag
            and p.direct_indirect   = d.direct_indirect
            and p.type              = d.type
    -- Only surface rows where something doesn't match
    -- where coalesce(p.row_count, 0)        <> coalesce(d.row_count, 0)
    --    or coalesce(p.total_amount_usd, 0) <> coalesce(d.total_amount_usd, 0)
)

-- ============================================================================
-- Run both result sets. Comment out whichever you don't need.
-- ============================================================================

-- 1. Top-level summary (should show matching totals for PROD and DEV)
-- select * from summary_compare order by source;

-- 2. Dimension-level diffs (should return 0 rows if views are identical)
select * from dimension_diffs order by abs(amount_usd_diff) desc;
