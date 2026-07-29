/*==============================================================================
  Validation Query — master_billing_new
  Purpose     Compare finance_db.dev_netsuite.master_billing (original) against
              finance_db.dev_netsuite.master_billing_new (refactored) to confirm
              consistent results across record counts, amounts, and the product
              classification dimensions that were refactored to pull from
              dim_product_dm_hierarchy_tbl (product_for_reporting, product_name,
              core_noncore, direct_indirect, product_name_group).
  Usage       Run all CTEs together. Review the result sets:
                - summary_compare   : total rows and amount_usd by reporting_status,
                                      side by side for ORIGINAL and NEW
                - dimension_diffs   : any dimension combo where the two tables disagree
              A clean result has 0 rows in dimension_diffs and matching totals
              in summary_compare.
  Owner       Dan Girard
  Created     05/18/2026
==============================================================================*/
with

original as (
    select
        direct_ecomm_flag,
        direct_indirect,
        product_name,
        coalesce(naics_sector,'N/A') naics_sector,
        coalesce(ship_region,'N/A') ship_region,
        count(*) as row_count,
        sum(amount_usd) as total_amount_usd
    from finance_db.dev_netsuite.master_billing
    group by all
),

new as (
    select
        direct_ecomm_flag,
        direct_indirect,
        product_name,
        coalesce(naics_sector,'N/A') naics_sector,
        coalesce(ship_region,'N/A') ship_region,
        count(*) as row_count,
        sum(amount_usd) as total_amount_usd
    from finance_db.dev_netsuite.master_billing_new
    group by all
),

-- ============================================================================
-- summary_compare: top-level row count and amount_usd by reporting_status,
-- both tables side by side. Rows should match within each reporting_status.
-- ============================================================================
summary_compare as (
    select
        'ORIGINAL' as source,
        -- o.reporting_status,
        round(sum(o.row_count),2) as total_rows,
        round(sum(o.total_amount_usd),2) as total_amount_usd
    from original o
    -- group by o.reporting_status

    union all

    select
        'NEW' as source,
        -- n.reporting_status,
        round(sum(n.row_count),2) as total_rows,
        round(sum(n.total_amount_usd),2) as total_amount_usd
    from new n
    -- group by n.reporting_status
),

-- ============================================================================
-- dimension_diffs: full outer join on all dimension columns.
-- Any row returned here is a discrepancy between the two tables.
-- Columns prefixed orig_ vs new_ show where the values diverge.
-- Sort by abs(amount_usd_diff) desc to surface the largest gaps first.
-- ============================================================================
dimension_diffs as (
    select
        coalesce(o.direct_ecomm_flag, n.direct_ecomm_flag) as direct_ecomm_flag,
        coalesce(o.direct_indirect, n.direct_indirect) as direct_indirect,
        coalesce(o.product_name, n.product_name) as product_name,
        coalesce(o.naics_sector, n.naics_sector) as naics_sector,
        coalesce(o.ship_region, n.ship_region) as ship_region,
        o.row_count as orig_row_count,
        n.row_count as new_row_count,
        coalesce(o.row_count, 0) - coalesce(n.row_count, 0) as row_count_diff,
        round(o.total_amount_usd,2) as orig_amount_usd,
        round(n.total_amount_usd ,2) as new_amount_usd,
        coalesce(round(o.total_amount_usd,2), 0) - coalesce(round(n.total_amount_usd,2), 0) as amount_usd_diff
    from original o
        full outer join new n
            on o.direct_ecomm_flag = n.direct_ecomm_flag
            and o.direct_indirect = n.direct_indirect
            and o.product_name = n.product_name
            and o.naics_sector = n.naics_sector
            and o.ship_region = n.ship_region
    -- where coalesce(o.row_count, 0)        <> coalesce(n.row_count, 0)
    --    or coalesce(round(o.total_amount_usd,2), 0) <> coalesce(round(n.total_amount_usd,2), 0)
)

-- ============================================================================
-- Run one result set at a time. Comment out whichever you don't need.
-- ============================================================================

-- 1. Top-level summary by reporting_status (ORIGINAL vs NEW should match)
-- select * from summary_compare;

-- 2. Dimension-level diffs (0 rows = tables are consistent)
select * from dimension_diffs order by abs(amount_usd_diff) desc;
;


