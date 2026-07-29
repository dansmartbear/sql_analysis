/*==============================================================================
  Validation Query — arr_master_retention_new
  Purpose     Compare finance_db.dev_netsuite.arr_master_retention (original)
              against finance_db.dev_netsuite.arr_master_retention_new
              (refactored) to confirm consistent results across record counts,
              cur_arr totals, and the key dimensions (section, direct_indirect,
              product_name) that span the retention analysis grain.
  Usage       Run all CTEs together. Review the result sets:
                - summary_compare   : total rows and cur_arr side by side for
                                      ORIGINAL and NEW, broken out by section
                - dimension_diffs   : any dimension combo where the two tables
                                      disagree on row count or cur_arr
              A clean result has 0 rows in dimension_diffs and matching totals
              in summary_compare.
  Owner       Dan Girard
  Created     06/29/2026
==============================================================================*/
with

original as (
    select
        section,
        direct_indirect,
        product_name,
        coalesce(naics_sector,'N/A/') as naics_sector,
        coalesce(ship_region,'N/A') as ship_region,
        count(*) as row_count,
        sum(round(cur_arr,2)) as total_cur_arr
    from finance_db.dev_netsuite.arr_master_retention r
    where section = 'Month'
    group by all
),

new as (
    select
        section,
        direct_indirect,
        product_name,
        coalesce(naics_sector,'N/A/') as naics_sector,
        coalesce(ship_region,'N/A') as ship_region,
        count(*) as row_count,
        sum(round(cur_arr,2)) as total_cur_arr
    from finance_db.dev_netsuite.arr_master_retention_new rn
    where section = 'Month'
    group by all
),

-- ============================================================================
-- summary_compare: top-level row count and cur_arr, both tables side by side.
-- Totals should match between ORIGINAL and NEW within each section.
-- Uncomment the section lines to break out by section.
-- ============================================================================
summary_compare as (
    select
        'ORIGINAL' as source,
        o.section,
        sum(o.row_count) as total_rows,
        round(sum(o.total_cur_arr), 2) as total_cur_arr
    from original o
    group by o.section

    union all

    select
        'NEW' as source,
        n.section,
        sum(n.row_count)as total_rows,
        round(sum(n.total_cur_arr), 2) as total_cur_arr
    from new n
    group by n.section
),

-- ============================================================================
-- dimension_diffs: full outer join on section, direct_indirect, product_name.
-- Any row returned here is a discrepancy between the two tables.
-- Sort by abs(cur_arr_diff) desc to surface the largest gaps first.
-- Uncomment the where clause to filter to rows with actual differences only.
-- ============================================================================
dimension_diffs as (
    select
        coalesce(o.section, n.section) as section,
        coalesce(o.direct_indirect, n.direct_indirect) as direct_indirect,
        coalesce(o.product_name, n.product_name) as product_name,
        coalesce(o.naics_sector, n.naics_sector) as naics_sector,
        coalesce(o.ship_region, n.ship_region) as ship_region,
        o.row_count as orig_row_count,
        n.row_count as new_row_count,
        coalesce(o.row_count, 0) - coalesce(n.row_count, 0) as row_count_diff,
        round(o.total_cur_arr, 0) as orig_cur_arr,
        round(n.total_cur_arr, 0) as new_cur_arr,
        coalesce(round(o.total_cur_arr, 2), 0) - coalesce(round(n.total_cur_arr, 2), 0) as cur_arr_diff
    from original o
        full outer join new n
            on o.section = n.section
            and o.direct_indirect = n.direct_indirect
            and o.product_name = n.product_name
            and o.naics_sector = n.naics_sector
            and o.ship_region = n.ship_region
    where coalesce(o.row_count, 0)                  <> coalesce(n.row_count, 0)
       or coalesce(round(o.total_cur_arr, 2), 0)    <> coalesce(round(n.total_cur_arr, 2), 0)
)

-- ============================================================================
-- Run one result set at a time. Comment out whichever you don't need.
-- ============================================================================

-- 1. Section-level summary (ORIGINAL vs NEW totals should match per section)
select * from summary_compare order by section, source;

-- 2. Dimension-level diffs (0 rows = tables are consistent)
select * from dimension_diffs order by abs(cur_arr_diff) desc;
;




select * exclude ver_date, cur_arr, prior_arr
from finance_db.dev_netsuite.arr_master_retention
where section = 'Month'
    -- and globalultimateparentupper = 'SILICOMM CORPORATION'
    -- and date_under_contract = '2012-02-29'
    and productgroup = 'Zephyr Scale'
    and naics_sector =  'N/A'
    and ship_region = 'North America'
except
select * exclude ver_date, cur_arr, prior_arr
from finance_db.dev_netsuite.arr_master_retention_new
where section = 'Month'
    -- and globalultimateparentupper = 'SILICOMM CORPORATION'
    -- and date_under_contract = '2012-02-29'
    and productgroup = 'Zephyr Scale'
    and naics_sector =  'N/A'
    and ship_region = 'North America'
order by date_under_contract, 1

;
select * exclude (ver_date, cur_arr, prior_arr)
from finance_db.dev_netsuite.arr_master_retention_new
where section = 'Month'
    -- and globalultimateparentupper = 'SILICOMM CORPORATION'
    -- and date_under_contract = '2012-02-29'
    and productgroup = 'Zephyr Scale'
    and naics_sector =  'N/A'
    and ship_region = 'North America'
except
select * exclude (ver_date, cur_arr, prior_arr)
from finance_db.dev_netsuite.arr_master_retention
where section = 'Month'
    -- and globalultimateparentupper = 'SILICOMM CORPORATION'
    -- and date_under_contract = '2012-02-29'
    and productgroup = 'Zephyr Scale'
    and naics_sector =  'N/A'
    and ship_region = 'North America'
order by date_under_contract, 1


;


select 'New', cur_arr,  * exclude ver_date
from finance_db.dev_netsuite.arr_master_retention
where section = 'Month'
    and globalultimateparentupper = 'GREENE, TWEED & CO., INC.'
    and date_under_contract = '2022-05-31'
    and productgroup = 'Zephyr Scale'
    and naics_sector =  'N/A'
    and ship_region = 'North America'
union all
select 'Old', cur_arr, * exclude ver_date
from finance_db.dev_netsuite.arr_master_retention_new
where section = 'Month'
    and globalultimateparentupper = 'GREENE, TWEED & CO., INC.'
    and date_under_contract = '2022-05-31'
    and productgroup = 'Zephyr Scale'
    and naics_sector =  'N/A'
    and ship_region = 'North America'
order by date_under_contract, 1


;
select table_name, last_altered
from finance_db.information_schema.tables
where table_schema = 'DEV_NETSUITE'
  and table_name in ('ARR_MASTER_RETENTION', 'ARR_MASTER_RETENTION_NEW');