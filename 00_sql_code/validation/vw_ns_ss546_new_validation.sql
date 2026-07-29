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
==============================================================================*/

with

prod as (
    select
        product_name,
        direct_ecomm_flag,
        direct_indirect,
        -- type,
        coalesce(naics,'N/A') naics,
        coalesce(ship_region,'N/A') ship_region,
        count(*) as row_count,
        sum(amount_usd) as total_amount_usd
    from finance_db.dev_netsuite.vw_ns_ss546
    group by all
),

dev as (
    select
        product_name,
        direct_ecomm_flag,
        direct_indirect,
        -- type,
        coalesce(naics,'N/A') naics,
        coalesce(ship_region,'N/A') ship_region,
        count(*) as row_count,
        sum(amount_usd) as total_amount_usd
    from finance_db.dev_netsuite.vw_ns_ss546_new
    group by all
),

-- ============================================================================
-- summary_compare: top-level totals for both views side by side.
-- Both columns should match exactly.
-- ============================================================================
summary_compare as (
    select
        'PROD'                          as source,
        sum(row_count)                  as total_rows,
        sum(total_amount_usd)           as total_amount_usd
    from prod

    union all

    select
        'DEV'                           as source,
        sum(row_count)                  as total_rows,
        sum(total_amount_usd)           as total_amount_usd
    from dev
),

-- ============================================================================
-- dimension_diffs: full outer join on all dimension columns.
-- Any row returned here is a discrepancy between the two views.
-- Columns prefixed prod_ vs dev_ show where the values diverge.
-- ============================================================================
dimension_diffs as (
    select
        coalesce(p.product_name, d.product_name) as product_name,
        coalesce(p.direct_ecomm_flag, d.direct_ecomm_flag) as direct_ecomm_flag,
        coalesce(p.direct_indirect, d.direct_indirect) as direct_indirect,
        coalesce(p.naics, d.naics) as naics,
        coalesce(p.ship_region, d.ship_region) as ship_region,
        -- coalesce(p.type, d.type) as type,
        coalesce(p.row_count,0) as prod_row_count,
        coalesce(d.row_count,0) as dev_row_count,
        coalesce(p.row_count,0) - coalesce(d.row_count,0) as row_count_diff,
        coalesce(p.total_amount_usd,0) as prod_amount_usd,
        coalesce(d.total_amount_usd,0) as dev_amount_usd,
        coalesce(p.total_amount_usd,0) - coalesce(d.total_amount_usd,0) as amount_usd_diff
    from prod p
        full outer join dev d
            on  p.product_name = d.product_name
            and p.direct_ecomm_flag = d.direct_ecomm_flag
            and p.direct_indirect = d.direct_indirect
            -- and p.type = d.type
            and p.naics = d.naics
            and p.ship_region = d.ship_region
    -- Only surface rows where something doesn't match
    -- where coalesce(p.row_count, 0)          <> coalesce(d.row_count, 0)
    --    or coalesce(p.total_amount_usd, 0)   <> coalesce(d.total_amount_usd, 0)
)

-- ============================================================================
-- Run both result sets. Comment out whichever you don't need.
-- ============================================================================

-- 1. Top-level summary (should show matching totals for PROD and DEV)
select * from summary_compare order by source;

-- 2. Dimension-level diffs (should return 0 rows if views are identical)
select * from dimension_diffs order by abs(amount_usd_diff) desc;
