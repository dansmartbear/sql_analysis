-- =============================================================================
-- Validation: finance_db.public.vw_naics_mapping vs finance_db.dev_netsuite.vw_naics_mapping_new
-- Purpose: Confirm output of refactored view matches original row-for-row
-- =============================================================================

-- -------------------------------------
-- 1. Row counts — should be equal
-- -------------------------------------
select
    'original' as source
    , count(*) as row_count
from finance_db.public.vw_naics_mapping

union all

select
    'new' as source
    , count(*) as row_count
from finance_db.dev_netsuite.vw_naics_mapping_new;


-- -------------------------------------
-- 2. Rows in original but missing from new
-- -------------------------------------
select
    o.naics_code
    , o.naics_industry_title
    , o.naics_industry_description
    , o.naics_sector_code
    , o.naics_sector
from finance_db.public.vw_naics_mapping o
left join finance_db.dev_netsuite.vw_naics_mapping_new n
    on o.naics_code = n.naics_code
where n.naics_code is null;


-- -------------------------------------
-- 3. Rows in new but missing from original
-- -------------------------------------
select
    n.naics_code
    , n.naics_industry_title
    , n.naics_industry_description
    , n.naics_sector_code
    , n.naics_sector
from finance_db.dev_netsuite.vw_naics_mapping_new n
left join finance_db.public.vw_naics_mapping o
    on n.naics_code = o.naics_code
where o.naics_code is null;


-- -------------------------------------
-- 4. Column-level diffs — rows where any value differs between the two views
-- -------------------------------------
select
    o.naics_code
    , o.naics_industry_title    as orig_naics_industry_title
    , n.naics_industry_title    as new_naics_industry_title
    , o.naics_industry_description as orig_naics_industry_description
    , n.naics_industry_description as new_naics_industry_description
    , o.naics_sector_code       as orig_naics_sector_code
    , n.naics_sector_code       as new_naics_sector_code
    , o.naics_sector            as orig_naics_sector
    , n.naics_sector            as new_naics_sector
from finance_db.public.vw_naics_mapping o
inner join finance_db.dev_netsuite.vw_naics_mapping_new n
    on o.naics_code = n.naics_code
where
    o.naics_industry_title          <> n.naics_industry_title
    or o.naics_industry_description <> n.naics_industry_description
    or o.naics_sector_code          <> n.naics_sector_code
    or o.naics_sector               <> n.naics_sector;
