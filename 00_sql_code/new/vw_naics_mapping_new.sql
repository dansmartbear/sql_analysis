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
with
naics_raw as
(
    select
        classification_id naics_id,
        classification_official_name off_name,
        classification_code naics_code,
        classification_title naics_title,
        parent_classification_code parent_naics_code,
    from 
        industry_classification_systems_naics_anzsic_isic_uksic_etc_.reports.industry_classification_systems n
    where 
        classification_official_name ilike 'NAICS % - USA'
)
select 
	n.naics_code
    , n.naics_title
    , n.naics_title naics_industry_description
	, coalesce(npppp.naics_code, nppp.parent_naics_code, npp.parent_naics_code, np.parent_naics_code, n.parent_naics_code, n.naics_code) sector_naics
    , coalesce(npppp.naics_title, nppp.naics_title, npp.naics_title, np.naics_title, n.naics_title) sector_title
from 
	naics_raw n
    left join naics_raw np on n.parent_naics_code = np.naics_code and n.off_name = np.off_name
    left join naics_raw npp on np.parent_naics_code = npp.naics_code and np.off_name = npp.off_name
    left join naics_raw nppp on npp.parent_naics_code = nppp.naics_code and npp.off_name = nppp.off_name
    left join naics_raw npppp on nppp.parent_naics_code = npppp.naics_code and nppp.off_name = npppp.off_name
where 
    n.off_name ilike 'NAICS % - USA'
qualify 
    row_number() over (partition by n.naics_code order by n.naics_id desc) = 1
;