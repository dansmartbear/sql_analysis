create or replace view finance_db.dev_netsuite.vw_naics_mapping_new
comment = 'NAICS classification hierarchy from Snowflake Marketplace.
           Walks the parent_classification_code chain up to 4 levels to resolve sector.'
(
    naics_code
    , naics_industry_title
    , naics_industry_description
    , naics_sector_code
    , naics_sector
)
as

with naics_base as (
    -- isolate all NAICS USA rows from the multi-system marketplace table;
    -- deduplicate on classification_id to keep the most recent version per code
    select
        n.classification_id
        , n.classification_code
        , n.classification_title
        , n.parent_classification_code
        , n.classification_official_name
    from industry_classification_systems_naics_anzsic_isic_uksic_etc_.reports.industry_classification_systems n
    where n.classification_official_name ilike 'NAICS % - USA'
    qualify row_number() over (partition by n.classification_code order by n.classification_id desc) = 1
)

-- walk the hierarchy: n=current, np=parent, npp=industry group,
-- nppp=subsector level, npppp=sector (root). coalesce picks the highest ancestor found.
select
    n.classification_code as naics_code
    , n.classification_title as naics_industry_title
    , n.classification_title as naics_industry_description  -- TODO: confirm source for description if different from title
    , coalesce(npppp.classification_code, nppp.parent_classification_code, npp.parent_classification_code
               , np.parent_classification_code, n.parent_classification_code, n.classification_code) as naics_sector_code
    , coalesce(npppp.classification_title, nppp.classification_title, npp.classification_title
               , np.classification_title, n.classification_title) as naics_sector
from naics_base n
    left join naics_base np    on n.parent_classification_code = np.classification_code
                               and n.classification_official_name = np.classification_official_name
    left join naics_base npp   on np.parent_classification_code = npp.classification_code
                               and np.classification_official_name = npp.classification_official_name
    left join naics_base nppp  on npp.parent_classification_code = nppp.classification_code
                               and npp.classification_official_name = nppp.classification_official_name
    left join naics_base npppp on nppp.parent_classification_code = npppp.classification_code
                               and nppp.classification_official_name = npppp.classification_official_name
