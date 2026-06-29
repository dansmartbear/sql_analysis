/*==============================================================================
  View Name   finance_db.dev_netsuite.vw_ns_ss546_new
  Source Tables
              finance_db.ingest.ns_ss546_cm_pm_stg
              finance_db.ingest.ns_ss546_stat_stg
  Reference Tables
              finance_db.public.dim_globalultimateparent_map
              finance_db.public.dim_product_dm_hierarchy_tbl
              finance_db.dev_netsuite.vw_naics_mapping_new
  Grain       One row per NetSuite transaction line.

  Change History
  06/21/2023  Dan Girard  Added Direct/Ecomm and product reporting logic
  10/12/2023  Dan Girard  Added Global Ultimate Parent mapping
  11/28/2023  Dan Girard  Added product_name and grouping fields
  07/03/2025  Dan Girard  Updated Reclass and Swagger Ecomm logic
  07/08/2025  Dan Girard  Added Direct/Ecomm override field
  09/04/2025  Dan Girard  Updated API Hub Test classification
  12/09/2025  Dan Girard  Updated BugSnag and Zephyr Scale Automate logic
  01/14/2026  Dan Girard  Change from the old NetSuite tables to the new v2 API
  01/20/2026  Dan Girard  Removed ship_to_name and bill_to_name
  04/14/2026  Dan Girard  Added unioned CTE and updated override logic for Zephyr Advanced
  04/23/2026  Dan Girard  Updated to use new INGEST staging tables
  05/04/2026  Dan Girard  Added updated BILL_TO and SHIP_TO names, Use new join table for salesperson and salesperson_location
  05/15/2026  Dan Girard  Refactored: moved all calculated columns out of union into downstream CTEs;
                          replaced product dimension calculations with dim_product_dm_hierarchy_tbl join
  05/15/2026  Dan Girard  Added join to vw_naics_mapping_new; added naics_sector column (NAICS_SECTOR_CODE - NAICS_SECTOR)
  05/18/2026  Dan Girard  Added product_group from dim_product_dm_hierarchy_tbl
  05/18/2026  Dan Girard  Added productgroup from dim_product_dm_hierarchy_tbl
  06/23/2026  Dan Girard  Added transaction_id (netsuite_id) and boomi_external_id
  
  Owner       Dan Girard
==============================================================================*/
create or replace view finance_db.dev_netsuite.vw_ns_ss546_new as

with

-- ============================================================================
-- Pre-compute the max employee ver_date once to avoid a correlated subquery
-- executing once per row inside the union branches.
-- ============================================================================
employee_max as (
    select max(to_date(ver_date)) as max_ver_date
    from finance_db.ingest.employee_stg_tbl
),

-- ============================================================================
-- raw_union: union the two source tables with only raw/typed columns and
-- snapshot filters. No calculations, no joins — those all live in main below.
-- Type casting (to_date, to_number, try_to_date) is applied here since it is
-- required for both union branches to produce matching column types.
-- ============================================================================
raw_union as (

    -- CM_PM: current month + previous month, refreshed hourly
    select
        a.customercategory,
        to_date(a.date) as date,
        a.invoiceno,
        a.entitynohierarchy,
        a.name,
        a.itemid,
        a.sbitemcategoryid,
        a.item,
        a.salesdescription,
        a.description,
        a.sfdctype,
        to_number(a.quantity, 10, 0) as quantity,
        a.listrate,
        a.documentnumber,
        -- 01/20/2026 [Dan Girard] Removed pochecknumber
        '' as pochecknumber,
        to_number(a.amount_usd, 20, 2) as amount_usd,
        to_number(a.amount, 20, 2) as amount,
        a.currency,
        to_number(a.amountforeigncurrency, 20, 2) as amountforeigncurrency,
        a.contractitemterm,
        try_to_date(a.contractitemstartdate) as contractitemstartdate,
        try_to_date(a.contractitemenddate) as contractitemenddate,
        a.templatename,
        a.revrecterminmonths,
        try_to_date(a.revrecstartdate) as revrecstartdate,
        try_to_date(a.revrecenddate) as revrecenddate,
        a.terms,
        a.pricelevel,
        a.type,
        a.itemcategoryhidden,
        a.sbitemcategory1,
        a.internalid,
        a.lineid,
        a.vsoeallocation,
        a.vsoeamount,
        -- 01/20/2026 [Dan Girard] Removed createdfrom
        '' as createdfrom,
        a.transexternalid,
        -- 01/20/2026 [Dan Girard] Removed externalid
        '' as externalid,
        a.transactiondiscount,
        a.quantitytype,
        a.product,
        a.ordertype,
        a.ordertype1,
        a.duns,
        a.internalid1,
        a.customersite,
        a.globalultimateparent,
        a.industrycategory,
        a.lineofbusiness,
        a.naics,
        -- 01/20/2026 [Dan Girard] Removed productline
        '' as productline,
        a.sic,
        try_to_date(a.dateoffirstsale) as dateoffirstsale,
        a.averagerate,
        a.sisense_product_rollup,
        a.order_type_classification,
        a.bill_country,
        a.bill_state,
        a.bill_city,
        a.ship_country,
        a.ship_state,
        a.ship_city,
        a.incomeaccountname,
        a.bill_region,
        a.ship_region,
        a.inline_discount,
        a.aws_mkt_private_offer,
        a.aws_mkt_cosell,
        a.ver_date,
        -- 08/07/2025 [Dan Girard] Added salesperson
        -- 05/04/2026 [Dan Girard] Use new join table for salesperson
        concat(e.first_name, ' ', e.last_name) as salesperson,
        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        e.location as salesperson_location,
        a.sfdc_deal_reg,
        -- 09/10/2024 [Dan Girard] Added Bill To and Ship To info
        a.bill_to_company,
        -- 05/04/2026 [Dan Girard] Changed to bill_to
        a.bill_to as bill_to_name,
        a.bill_to_address1,
        a.bill_to_address2,
        a.bill_to_address3,
        a.ship_to_company,
        -- 05/04/2026 [Dan Girard] Changed to ship_to
        a.ship_to as ship_to_name,
        a.ship_to_address1,
        a.ship_to_address2,
        a.ship_to_address3,
        -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
        a.stripe_user_id,
        a.braintree_user_id,
        -- 04/14/2026 [Dan Girard] Added for Zephyr Advanced historical override
        a.new_item_id,
        a.new_item_id_name,
        -- 06/23/2026 [Dan Girard] Added transaction_id (netsuite_id) and boomi_external_id
        a.transaction_id,
        a.boomi_external_id
    from finance_db.ingest.ns_ss546_cm_pm_stg a
        left join finance_db.ingest.employee_stg_tbl e
            on a.salesperson = e.employee_id
            and to_date(e.ver_date) = (select max_ver_date from employee_max)
    -- Filter to latest CM_PM snapshot; ver_date is not wrapped in to_date() per source table convention
    where a.ver_date = (select max(ver_date) from finance_db.ingest.ns_ss546_cm_pm_stg)

    union all

    -- STAT: full historical data, refreshed daily
    select
        a.customercategory,
        to_date(a.date) as date,
        a.invoiceno,
        a.entitynohierarchy,
        a.name,
        a.itemid,
        a.sbitemcategoryid,
        a.item,
        a.salesdescription,
        a.description,
        a.sfdctype,
        to_number(a.quantity, 10, 0) as quantity,
        a.listrate,
        a.documentnumber,
        -- 01/20/2026 [Dan Girard] Removed pochecknumber
        '' as pochecknumber,
        to_number(a.amount_usd, 20, 2) as amount_usd,
        to_number(a.amount, 20, 2) as amount,
        a.currency,
        to_number(a.amountforeigncurrency, 20, 2) as amountforeigncurrency,
        a.contractitemterm,
        try_to_date(a.contractitemstartdate) as contractitemstartdate,
        try_to_date(a.contractitemenddate) as contractitemenddate,
        a.templatename,
        a.revrecterminmonths,
        try_to_date(a.revrecstartdate) as revrecstartdate,
        try_to_date(a.revrecenddate) as revrecenddate,
        a.terms,
        a.pricelevel,
        a.type,
        a.itemcategoryhidden,
        a.sbitemcategory1,
        a.internalid,
        a.lineid,
        a.vsoeallocation,
        a.vsoeamount,
        -- 01/20/2026 [Dan Girard] Removed createdfrom
        '' as createdfrom,
        a.transexternalid,
        -- 01/20/2026 [Dan Girard] Removed externalid
        '' as externalid,
        a.transactiondiscount,
        a.quantitytype,
        a.product,
        a.ordertype,
        a.ordertype1,
        a.duns,
        a.internalid1,
        a.customersite,
        a.globalultimateparent,
        a.industrycategory,
        a.lineofbusiness,
        a.naics,
        -- 01/20/2026 [Dan Girard] Removed productline
        '' as productline,
        a.sic,
        try_to_date(a.dateoffirstsale) as dateoffirstsale,
        a.averagerate,
        a.sisense_product_rollup,
        a.order_type_classification,
        a.bill_country,
        a.bill_state,
        a.bill_city,
        a.ship_country,
        a.ship_state,
        a.ship_city,
        a.incomeaccountname,
        a.bill_region,
        a.ship_region,
        a.inline_discount,
        a.aws_mkt_private_offer,
        a.aws_mkt_cosell,
        a.ver_date,
        -- 08/07/2025 [Dan Girard] Added salesperson
        -- 05/04/2026 [Dan Girard] Use new join table for salesperson
        concat(e.first_name, ' ', e.last_name) as salesperson,
        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        e.location as salesperson_location,
        a.sfdc_deal_reg,
        -- 09/10/2024 [Dan Girard] Added Bill To and Ship To info
        a.bill_to_company,
        -- 05/04/2026 [Dan Girard] Changed to bill_to
        a.bill_to as bill_to_name,
        a.bill_to_address1,
        a.bill_to_address2,
        a.bill_to_address3,
        a.ship_to_company,
        -- 05/04/2026 [Dan Girard] Changed to ship_to
        a.ship_to as ship_to_name,
        a.ship_to_address1,
        a.ship_to_address2,
        a.ship_to_address3,
        -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
        a.stripe_user_id,
        a.braintree_user_id,
        -- 04/14/2026 [Dan Girard] Added for Zephyr Advanced historical override
        a.new_item_id,
        a.new_item_id_name,
        -- 06/23/2026 [Dan Girard] Added transaction_id (netsuite_id) and boomi_external_id
        a.transaction_id,
        a.boomi_external_id
    from finance_db.ingest.ns_ss546_stat_stg a
        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        left join finance_db.ingest.employee_stg_tbl e
            on a.salesperson = e.employee_id
            and to_date(e.ver_date) = (select max_ver_date from employee_max)
    -- Filter to latest STAT snapshot
    where to_date(a.ver_date) = (select max(to_date(s.ver_date)) from finance_db.ingest.ns_ss546_stat_stg s)

),

-- ============================================================================
-- main: single transformation layer applied after the union.
-- Handles:
--   1. dim_globalultimateparent_map join (once, against unioned data)
--   2. type_calc: normalizes raw type values to display strings
--   3. sisense_product_rollup_calc: Zephyr Advanced override
--   4. direct_ecomm_base: core Direct vs Ecomm channel classification
--   5. direct_ecomm_flag: product-level override on direct_ecomm_base
-- Snowflake allows later columns in the same SELECT to reference earlier
-- calculated aliases, so all five steps can live in one CTE.
-- ============================================================================
main as (
    select
        u.customercategory,
        u.date,
        u.invoiceno,
        u.entitynohierarchy,
        u.name,
        u.itemid,
        u.sbitemcategoryid,
        u.item,
        u.salesdescription,
        u.description,
        u.sfdctype,
        u.quantity,
        u.listrate,
        u.documentnumber,
        u.pochecknumber,
        u.amount_usd,
        u.amount,
        u.currency,
        u.amountforeigncurrency,
        u.contractitemterm,
        u.contractitemstartdate,
        u.contractitemenddate,
        u.templatename,
        u.revrecterminmonths,
        u.revrecstartdate,
        u.revrecenddate,
        u.terms,
        u.pricelevel,
        u.type,
        -- 05/05/2026 [Dan Girard] type_calc normalizes raw type values back to display strings;
        --   used as an input to direct_ecomm_base logic below
        case
            when u.type = 'creditmemo'         then 'Credit Memo'
            when u.type = 'cashsale'           then 'Cash Sale'
            when u.type = 'cashrefund'         then 'Cash Refund'
            when u.type = 'customsale_reclass' then 'Reclass'
            when u.type = 'invoice'            then 'Invoice'
            else u.type
        end as type_calc,
        u.itemcategoryhidden,
        u.sbitemcategory1,
        u.internalid,
        u.lineid,
        u.vsoeallocation,
        u.vsoeamount,
        u.createdfrom,
        u.transexternalid,
        u.externalid,
        u.transactiondiscount,
        u.quantitytype,
        u.product,
        u.ordertype,
        u.ordertype1,
        u.duns,
        u.internalid1,
        u.customersite,
        -- 10/12/2023 [Dan Girard] Replaced GLOBALULTIMATEPARENT with new mapping logic
        coalesce(g.globalultimateparent_mapped, u.globalultimateparent) as globalultimateparent,
        u.industrycategory,
        u.lineofbusiness,
        u.naics,
        u.productline,
        u.sic,
        u.dateoffirstsale,
        u.averagerate,
        -- 04/14/2026 [Dan Girard] sisense_product_rollup_calc: Zephyr Advanced override;
        --   used as the primary product dimension input for the dim table join key
        case
            when left(u.new_item_id_name, 3) = 'ZA-'               then 'Zephyr Advanced'
            when u.sisense_product_rollup = 'Zephyr Scale Automate' then 'Zephyr Advanced'
            else u.sisense_product_rollup
        end as sisense_product_rollup_calc,
        u.order_type_classification,
        u.bill_country,
        u.bill_state,
        u.bill_city,
        u.ship_country,
        u.ship_state,
        u.ship_city,
        u.incomeaccountname,
        u.bill_region,
        u.ship_region,
        u.inline_discount,
        u.aws_mkt_private_offer,
        u.aws_mkt_cosell,
        u.ver_date,
        u.salesperson,
        u.salesperson_location,
        u.sfdc_deal_reg,
        u.bill_to_company,
        u.bill_to_name,
        u.bill_to_address1,
        u.bill_to_address2,
        u.bill_to_address3,
        u.ship_to_company,
        u.ship_to_name,
        u.ship_to_address1,
        u.ship_to_address2,
        u.ship_to_address3,
        u.stripe_user_id,
        u.braintree_user_id,
        u.new_item_id,
        u.new_item_id_name,
        u.transaction_id,
        u.boomi_external_id,

        -- 06/21/2023 [Dan Girard] direct_ecomm_base: first pass at Direct vs Ecomm channel
        --   based on product, customer category, transaction type, and date-based rules
        -- 07/08/2025 [Dan Girard] Renamed from direct_ecomm_flag to direct_ecomm_base for override
        -- 08/17/2023 [Dan Girard] Added SISENSE check for DIRECT and 3 date-based logic lines
        case
            when sisense_product_rollup_calc in ('Capture','Cucumber','Squad','Zephyr Scale') then 'Ecomm'
            when sisense_product_rollup_calc in ('AlertSite','AQTime','Collaborator','Hiptest','LoadComplete','QAComplete','RAPI Performance','RAPI Test','RAPI Virtualization','TestComplete','TestEngine','Zephyr E') then 'Direct'
            when u.date <= '2022-06-30' and coalesce(u.transexternalid,'') = '' and sisense_product_rollup_calc ilike '%CBT%' then 'Direct'
            when u.date <= '2022-06-30' and sisense_product_rollup_calc ilike '%CBT%' then 'Ecomm'
            when u.date < '2022-01-01' and upper(sisense_product_rollup_calc) in ('LOADNINJA','PACTFLOW','BITBAR') and upper(u.name) like '%STRIPE%' then 'Ecomm'
            -- 07/03/2025 [Dan Girard] Updated for Swagger Ecomm Reclass
            when type_calc = 'Reclass' and coalesce(u.transexternalid,'') ilike '%braintree%' then 'Ecomm'
            -- 06/05/2025 [Dan Girard] Updated to match the CM version
            -- 07/07/2025 [Dan Girard] Changed default for Reclass to DIRECT
            when type_calc = 'Reclass' then 'Direct'
            when (
                u.customercategory in ('Reseller','End User')
                or (
                    u.customercategory = 'ecommerce'
                    and (
                        upper(u.name) like '%CLEVERBRIDGE%'
                        or upper(u.name) like '%AMAZON ONLINE ORDERS%'
                    )
                )
            ) then 'Direct'
            -- 02/27/2025 [Dan Girard] Added RECLASS
            when type_calc in ('Invoice','Credit Memo','Reclass') then 'Direct'
            else 'Ecomm'
        end as direct_ecomm_base,

        -- 07/08/2025 [Dan Girard] Override: force certain Ecomm products to Direct
        -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
        -- 10/01/2025 [Dan Girard] Removed BugSnag RUM from the forced Direct list
        case
            when direct_ecomm_base = 'Ecomm'
            and sisense_product_rollup_calc in ('LoadNinja','Pactflow','Portal','VisualTest','Contract Testing') then 'Direct'
            else direct_ecomm_base
        end as direct_ecomm_flag

    from raw_union u
        -- 10/12/2023 [Dan Girard] Added left join to Global Ultimate Parent Map table
        left join finance_db.public.dim_globalultimateparent_map g
            on upper(u.globalultimateparent) = upper(g.globalultimateparent_orig)
)

-- ============================================================================
-- Final SELECT: join main to dim_product_dm_hierarchy_tbl on lookup_map_upper.
-- All product dimension columns sourced from the dim table.
-- direct_ecomm_base and direct_ecomm_flag are the only locally computed
-- product columns retained, as they drive the join key.
-- ============================================================================
select
    m.customercategory,
    m.date,
    m.invoiceno,
    m.entitynohierarchy,
    m.name,
    m.itemid,
    m.sbitemcategoryid,
    m.item,
    m.salesdescription,
    m.description,
    m.sfdctype,
    m.quantity,
    m.listrate,
    m.documentnumber,
    m.amount_usd,
    m.amount,
    m.currency,
    m.amountforeigncurrency,
    m.contractitemterm,
    m.contractitemstartdate,
    m.contractitemenddate,
    m.templatename,
    m.revrecterminmonths,
    m.revrecstartdate,
    m.revrecenddate,
    m.terms,
    m.pricelevel,
    -- 05/05/2026 [Dan Girard] Expose type_calc as type (original raw type col dropped from output)
    m.type_calc as type,
    m.itemcategoryhidden,
    m.sbitemcategory1,
    m.internalid,
    m.lineid,
    m.vsoeallocation,
    m.vsoeamount,
    m.createdfrom,
    m.transexternalid,
    m.transactiondiscount,
    m.quantitytype,
    m.product,
    m.ordertype,
    m.ordertype1,
    m.duns,
    m.internalid1,
    m.customersite,
    m.globalultimateparent,
    m.industrycategory,
    m.lineofbusiness,
    m.naics,
    -- 05/15/2026 [Dan Girard] Added NAICS sector lookup from vw_naics_mapping_new
    concat(n.naics_sector_code, ' - ', n.naics_sector) as naics_sector,
    m.sic,
    m.dateoffirstsale,
    m.averagerate,
    m.sisense_product_rollup_calc as sisense_product_rollup,
    m.order_type_classification,
    m.bill_country,
    m.bill_state,
    m.bill_city,
    m.ship_country,
    m.ship_state,
    m.ship_city,
    m.incomeaccountname,
    m.bill_region,
    m.ship_region,
    m.inline_discount,
    m.aws_mkt_private_offer,
    m.aws_mkt_cosell,
    m.ver_date,
    m.direct_ecomm_base,
    m.direct_ecomm_flag,
    -- 05/15/2026 [Dan Girard] All product dimension columns sourced from dim_product_dm_hierarchy_tbl
    p.product_for_reporting_ns,
    p.product_for_reporting_group_ns,
    p.product_for_reporting_ns_alias,
    p.product_for_reporting_ns_alias_combined,
    p.product_name,
    p.core_noncore,
    p.direct_indirect,
    p.product_name_group,
    p.product_hub,
    p.product_parent,
    p.pbt_group,
    p.ai,
    -- 05/18/2026 [Dan Girard] Added product_group from dim_product_dm_hierarchy_tbl
    p.product_group,
    -- 05/18/2026 [Dan Girard] Added productgroup from dim_product_dm_hierarchy_tbl
    p.productgroup,
    m.salesperson,
    m.salesperson_location,
    m.sfdc_deal_reg,
    m.bill_to_name,
    m.bill_to_company,
    m.bill_to_address1,
    m.bill_to_address2,
    m.bill_to_address3,
    m.ship_to_name,
    m.ship_to_company,
    m.ship_to_address1,
    m.ship_to_address2,
    m.ship_to_address3,
    m.stripe_user_id,
    m.braintree_user_id,
    m.new_item_id,
    m.new_item_id_name,
    m.pochecknumber,
    m.externalid,
    m.productline,
    -- 06/23/2026 [Dan Girard] Added transaction_id (netsuite_id) and boomi_external_id
    m.transaction_id,
    m.boomi_external_id

from main m
    left join finance_db.public.dim_product_dm_hierarchy_tbl p
        on upper(concat(m.sisense_product_rollup_calc, '_', m.direct_ecomm_flag)) = p.lookup_map_upper
    -- 05/15/2026 [Dan Girard] Added join to NAICS sector mapping view
    left join finance_db.dev_netsuite.vw_naics_mapping_new n
        on m.naics = n.naics_code
;
