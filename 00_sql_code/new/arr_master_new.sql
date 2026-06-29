/**********************************************************************

Name:       finance_db.dev_netsuite.arr_master_new
Type:       Table
Created:    01/10/2023 [Dan Girard]
Purpose:    Central ARR/ACV fact table. Combines AS REPORTED actuals
            from vw_ns_ss546_new with PROFORMA billings from
            arr_master_proforma. ACV and acv_billings are the same
            concept; ACV is the annualized contract value.

            Refactor notes (05/18/2026):
            - 4-CTE inline SFDC block replaced with single join to
              finance_db.dev_netsuite.vw_sfdc_invoice_data.
            - sfdc_ent_core_flag field reference updated to
              sfdc_core_ent_flag to match the view's output name.
            - NS source updated from public.vw_ns_ss546 to
              dev_netsuite.vw_ns_ss546_new.
            - naics join removed; naics_sector pulled directly from
              vw_ns_ss546_new (already computes it internally).
            - Proforma naics_sector stubbed to '' to match.
            - Raw union CTE (main) split into raw_union (pure union)
              and main (all joins and derived fields), following the
              CTE layering convention.
            - ARR_MASTER_PROFORMA DDL reconciled (05/18/2026): column
              aliases corrected throughout proforma branch:
                vendoramount        → amount_usd
                maintenanceenddate  → contractitemenddate
                maintenancestartdate → contractitemstartdate
                sbitemcategory      → sbitemcategory1
                contractdays        → contract_length
                externalid          → transexternalid
                contractitemterm    → null (column absent from DDL)
              naics_sector confirmed in DDL; pulled directly (no stub).
            - datediff argument order corrected on BUGSNAG acv_billings
              branch (was end,start — reversed; now start,end).
            - BUGSNAG transexternalid condition simplified from
              (is not null OR <> '') to coalesce(...) <> ''.
            - ordertype1 CASE made multi-line and given else clause;
              fallback logic ported from master_billing_new.
            - product_name_group and billing_term CASE given else null.
            - All column references qualified with table alias throughout.
            - Keywords lowercased throughout (And, DATE, TRANSEXTERNALID).
            - Trailing commas applied throughout (style update 05/17/2026).
            - prod_map CTE retained for pbt_group lookup (not in
              vw_ns_ss546_new's output for ARR_MASTER's proforma branch).

Updates:    02/14/2023 [Dan Girard]  Add region and NAICS
            06/28/2023 [Dan Girard]  Added DIRECT_ECOMM_FLAG, PRODUCT_FOR_REPORTING_NS,
                                     PRODUCT_FOR_REPORTING_GROUP_NS
            08/28/2023 [Dan Girard]  Added PRODUCT_FOR_REPORTING_NS_ALIAS and
                                     PRODUCT_FOR_REPORTING_NS_ALIAS_COMBINED
            10/12/2023 [Dan Girard]  Created outer select; added GUP map join
            11/28/2023 [Dan Girard]  Added PRODUCT_NAME, CORE_NONCORE,
                                     DIRECT_INDIRECT, PRODUCT_NAME_GROUP;
                                     reworked direct_ecomm_flag and product_for_reporting
            02/07/2024 [Dan Girard]  Added SFDC CTE for invoice/close date join
            02/21/2024 [Dan Girard]  Added sfdc_location / salesperson_location
            07/11/2024 [Dan Girard]  Moved all proforma logic to arr_master_proforma;
                                     added Core/Enterprise flag from SFDC
            11/07/2024 [Dan Girard]  Added billing_term
            11/14/2024 [Dan Girard]  Added stream_revenue
            11/24/2025 [Dan Girard]  Added datasource_group
            01/14/2026 [Dan Girard]  Removed createdfrom and pochecknumber
            03/26/2025 [Dan Girard]  Updated sfdc_ent_core_flag to remove nulls
            06/25/2025 [Dan Girard]  Added prod_map CTE; added pbt_group join
            05/15/2026 [Dan Girard]  Updated for API Hub mapping
            05/18/2026 [Dan Girard]  Style refactor; SFDC block → vw_sfdc_invoice_data;
                                     NAICS join removed; source → vw_ns_ss546_new;
                                     datediff fix; CASE hygiene; alias qualification
            05/20/2026 [Dan Girard]  Renamed ACV_LENGTH_RAW → CONTRACT_LENGTH_RAW;
                                     renamed LENGTH_DAYS → CONTRACT_LENGTH;
                                     renamed REGION → SHIP_REGION (original name was REGION);
                                     added VER_DATE (current_timestamp) to final SELECT

***********************************************************************/
create or replace table finance_db.dev_netsuite.arr_master_new copy grants as
with

-- ============================================================================
-- prod_map: pbt_group lookup from the product hierarchy table.
-- Used to enrich the final SELECT for both NS and proforma rows.
-- Static overrides appended via union all for products not in the dim table.
-- ============================================================================
prod_map as
(
    select distinct
        ph.productgroup as productgroupmap,
        ph.pbt_group
    from
        finance_db.public.dim_product_dm_hierarchy_tbl ph
    -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
    union all select 'API Hub', 'Swagger'
    union all select 'Hiptest', 'Other'
)

-- ============================================================================
-- raw_union: pure union of NS actuals and proforma rows.
-- NS branch: sourced from vw_ns_ss546_new. naics_sector pulled directly —
--   no join to vw_naics_mapping needed (view handles it internally).
-- Proforma branch: sourced from arr_master_proforma. naics_sector stubbed
--   to '' since proforma rows have no NAICS data.
-- No joins, no CASE calculations here — those belong in main.
-- ============================================================================
, raw_union as
(
    -- NS actuals from vw_ns_ss546_new
    select
        'NS' as datasource,
        concat(ns.internalid, concat_ws('-', ns.lineid)) as key,
        ns.invoiceno,
        ns.amount_usd,
        -- 05/20/2026 [Dan Girard] Pre-compute contract length variants used across acv_billings and acv.
        --   contract_length     = datediff + 1 (inclusive day count; used for comparisons and most annualization)
        --   contract_length_raw = datediff without +1 (used in BUGSNAG acv_billings and ecomm non-Cleverbridge acv)
        -- Both are referenced by alias in the CASE blocks below (Snowflake allows forward-alias reference
        -- within the same SELECT list).
        datediff('day', ns.contractitemstartdate, ns.contractitemenddate) + 1 as contract_length,
        datediff('day', ns.contractitemstartdate, ns.contractitemenddate) as contract_length_raw,
        -- 05/18/2026 [Dan Girard] acv_billings: BUGSNAG datediff argument order corrected
        --   (was contractitemenddate, contractitemstartdate — reversed, producing negative denominator).
        --   Also simplified transexternalid check from (is not null OR <> '') to coalesce(...) <> ''.
        -- 05/20/2026 [Dan Girard] Replaced inline datediff expressions with contract_length / contract_length_raw.
        --   ALERTSITE threshold changed from < 364 to <= 364 to close the gap at exactly 364 days.
        case
            when upper(ns.sisense_product_rollup) = 'BUGSNAG'
                and coalesce(ns.transexternalid, '') <> ''
                then div0(ns.amount_usd, contract_length_raw) * 365
            when upper(ns.sisense_product_rollup) = 'ALERTSITE'
                and contract_length <= 364
                then ns.amount_usd
            when upper(ns.sisense_product_rollup) = 'ALERTSITE'
                and contract_length >= 365
                then div0(ns.amount_usd, contract_length) * 365
            when upper(ns.sisense_product_rollup) <> 'ALERTSITE'
                and contract_length < 365
                then ns.amount_usd
            else div0(ns.amount_usd, contract_length) * 365
        end as acv_billings,
        -- 08/08/2024 [Dan Girard] Added ecomm logic for certain products on or after 8/1/2024
        -- 05/20/2026 [Dan Girard] Replaced inline datediff expressions with contract_length / contract_length_raw.
        case
            when ns.date >= '2024-08-01'
                and ns.customercategory = 'ecommerce'
                and lower(ns.sisense_product_rollup) in ('stoplight', 'bitbar', 'loadninja', 'pactflow', 'swagger')
                then div0(ns.amount_usd, contract_length) * 365
            when ns.sisense_product_rollup = 'AlertSite'
                and contract_length < 365
                then ns.amount_usd
            when ns.customercategory = 'ecommerce'
                and upper(ns.name) not like '%CLEVERBRIDGE%'
                then div0(ns.amount_usd, contract_length_raw) * 365
            else div0(ns.amount_usd, contract_length) * 365
        end as acv,
        ns.contractitemenddate,
        ns.contractitemstartdate,
        try_to_number(ns.contractitemterm) as contractitemterm,
        ns.currency,
        ns.customercategory,
        ns.customersite,
        ns.date,
        ns.dateoffirstsale,
        ns.documentnumber,
        ns.duns,
        ns.entitynohierarchy,
        ns.transexternalid,
        ns.globalultimateparent,
        trim(upper(coalesce(ns.globalultimateparent, 'BLANK'))) as globalultimateparentupper,
        case ns.itemcategoryhidden
            when 'License - Perpetual' then 'Perpetual'
            when 'License - Term'      then 'Subscription'
            when 'Maintenance - Renewal' then 'Maintenance'
            when 'Other'               then 'Subscription'
            when 'Services'            then 'PS'
            when 'Support - New'       then 'Maintenance'
            when 'Training'            then 'PS'
            when 'Support - Renewal'   then 'Maintenance'
            else 'Whoopsie!'
        end as itemtype,
        ns.sbitemcategory1,
        ns.itemid,
        ns.lineid,
        ns.lineofbusiness,
        ns.listrate,
        ns.naics,
        ns.name,
        ns.ordertype,
        -- 05/18/2026 [Dan Girard] Made multi-line; added else and fallback per master_billing_new pattern
        case
            when ns.ordertype1 = 'Renewal'              then 'Renewal'
            when ns.ordertype1 in ('New', 'Existing')   then 'License'
            -- 02/11/2026 [Dan Girard] Fallback: use sfdctype when ordertype1 is blank
            when coalesce(ns.ordertype1, '') = ''
                and ns.sfdctype in ('New', 'Expansion') then 'License'
            when coalesce(ns.ordertype1, '') = ''
                and ns.sfdctype = 'Renewal'             then 'Renewal'
            else null
        end as ordertype1,
        ns.pricelevel,
        ns.product,
        ns.quantity,
        ns.quantitytype,
        ns.sfdctype,
        ns.sic,
        ns.templatename,
        ns.terms,
        ns.transactiondiscount,
        ns.type,
        ns.vsoeallocation,
        ns.vsoeamount,
        -- productgroup: maps sisense_product_rollup to standardized product name
        case
            when upper(ns.sisense_product_rollup) = 'RAPI TEST'          then 'ReadyAPI Test'
            when upper(ns.sisense_product_rollup) = 'RAPI PERFORMANCE'   then 'ReadyAPI Performance'
            when upper(ns.sisense_product_rollup) = 'RAPI VIRTUALIZATION' then 'ReadyAPI Virtualization'
            when upper(ns.sisense_product_rollup) = 'SQUAD'              then 'Zephyr Squad'
            -- 06/04/2025 [Dan Girard] Add logic for Test and Contract Testing
            -- 09/04/2025 [Dan Girard] Update logic for Test to be API Hub Test
            -- 12/04/2025 [Dan Girard] Update logic for Test to be Swagger and API Hub to Swagger
            -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
            when upper(ns.sisense_product_rollup) = 'TEST'
                and ns.direct_ecomm_flag = 'Direct'                      then 'API Hub'
            when upper(ns.sisense_product_rollup) = 'TEST'
                and ns.direct_ecomm_flag = 'Ecomm'                       then 'API Hub'
            when upper(ns.sisense_product_rollup) = 'CONTRACT TESTING'   then 'Pactflow'
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when upper(ns.sisense_product_rollup) = 'BUGSNAG'            then 'BugSnag'
            -- 12/15/2025 [Dan Girard] BugSnag RUM Ecomm should just be BugSnag
            when upper(ns.sisense_product_rollup) = 'BUGSNAG RUM'
                and ns.direct_ecomm_flag = 'Ecomm'                       then 'BugSnag'
            when upper(ns.sisense_product_rollup) = 'BUGSNAG RUM'        then 'BugSnag RUM'
            -- 10/15/2025 [Dan Girard] Added Explore and VisualTest
            when upper(ns.sisense_product_rollup) = 'EXPLORE'            then 'Portal'
            when upper(ns.sisense_product_rollup) = 'VISUALTEST'         then 'TestComplete'
            -- 12/09/2025 [Dan Girard] Update for Zephyr Scale Automate
            -- 04/15/2026 [Dan Girard] Change from Scale to Advanced
            when upper(ns.sisense_product_rollup) = 'ZEPHYR SCALE AUTOMATE' then 'Zephyr Advanced'
            else ns.sisense_product_rollup
        end as productgroup,
        0 as plan_amt,
        '0' as flag_plan,
        'Y' as flag_proforma,
        'N/A' as source, -- logic lives on dim_datecontracts
        ns.itemcategoryhidden,
        -- 2/14/2023 [Dan Girard] Add region (originally named REGION; renamed to SHIP_REGION 05/20/2026)
        ns.ship_region as ship_region,
        -- 05/18/2026 [Dan Girard] naics_sector pulled directly from view; no NAICS join needed
        ns.naics_sector,
        -- 11/14/2024 [Dan Girard] Added stream_revenue
        case
            when ns.incomeaccountname ilike '%License Revenue%'                            then 'Perpetual License'
            when ns.incomeaccountname ilike '%SaaS%'                                       then 'SaaS'
            when ns.incomeaccountname ilike '%Training%'                                   then 'Professional Services'
            when ns.incomeaccountname ilike '%Professional Services%'                      then 'Professional Services'
            when ns.incomeaccountname in ('Other - Test', 'Other Travel')                  then 'Professional Services'
            when ns.incomeaccountname ilike '%Subscription Revenue%'                       then 'Subscription License'
            when ns.incomeaccountname ilike '%MAintENANCE REV RENEW : SUB MNT REV RENEW%' then 'Subscription Maintenance'
            when ns.incomeaccountname ilike '%MAintENANCE REV Y1%'                         then 'Subscription Maintenance'
            when ns.incomeaccountname ilike '%Maintenance  Revenue Renewal%'               then 'Perpetual Maintenance'
            when ns.incomeaccountname ilike '%Maintenance Revenue Renewal%'                then 'Perpetual Maintenance'
            when ns.incomeaccountname in (
                'Maintenance  Revenue YR 1 - API',
                'Maintenance  Revenue YR 1 - Dev',
                'Maintenance  Revenue YR 1 - Test',
                'Maintenance  Revenue YR 1 - UXM',
                'Maintenance  Revenue YR 1 - Zephyr',
                'Maintenance  Revenue YR 1 - Other'
            ) then 'Perpetual Maintenance'
            when ns.incomeaccountname in (
                'Maintenance Revenue YR 1 - API',
                'Maintenance Revenue YR 1 - Dev',
                'Maintenance Revenue YR 1 - Test',
                'Maintenance Revenue YR 1 - UXM',
                'Maintenance Revenue YR 1 - Zephyr',
                'Maintenance Revenue YR 1 - Other'
            ) then 'Perpetual Maintenance'
            else 'Undefined'
        end as stream_revenue
    from
        finance_db.dev_netsuite.vw_ns_ss546_new ns
    where
        upper(ns.itemcategoryhidden) not in ('SERVICES', 'LICENSE - PERPETUAL', 'TRAINING') -- CC 1/3/2020: TRAINING ADDED
        and upper(ns.sbitemcategory1) not in ('SERVICES')
        and not (upper(ns.sisense_product_rollup) in ('SQUAD', 'CAPTURE') and ns.date < '2018-10-01')
        and not (upper(ns.sisense_product_rollup) = 'ZEPHYR SCALE' and ns.date < '2020-05-17')
        and not (upper(ns.sisense_product_rollup) = 'BUGSNAG' and ns.date < '2021-05-14') -- cut off date for flat file
        -- 4/4/2024 [Dan Girard] Added filter for Reflect NS data before 3/1/2024
        and not (upper(ns.sisense_product_rollup) = 'REFLECT' and ns.date < '2024-03-01')
        -- 09/29/2024 [Dan Girard] Filter out special SKU uploads
        -- 07/23/2024 [Dan Girard] Filter out the QTM special SKU uploads
        and ns.item not in ('SLS-INT-EC', 'QTM-INT-SBR', 'QTM-INT-SBN', 'QTM4J-INT-EC')

    union all

    -- 7/11/2024 [Dan Girard] Proforma rows from arr_master_proforma
    -- Column notes (from DDL confirmed 05/18/2026):
    --   VENDORAMOUNT     aliased to amount_usd   — proforma equivalent of NS amount_usd
    --   MAINTENANCEENDDATE / MAINTENANCESTARTDATE aliased to contractitemenddate / contractitemstartdate
    --   SBITEMCATEGORY   aliased to sbitemcategory1 — proforma table has no trailing '1'
    --   CONTRACTDAYS     aliased to contract_length   — proforma equivalent of NS contract_length
    --   CONTRACTITEMTERM pulled directly
    --   EXTERNALID       aliased to transexternalid — proforma equivalent of NS transexternalid
    --   NAICS_SECTOR     exists in DDL; pulled directly (no stub needed)
    --   CREATEDFROM, POCHECKNUMBER, PRODUCTLINE exist in DDL but are removed from ARR_MASTER
    --     per 01/14/2026 [Dan Girard] — columns no longer available upstream
    select
        a.datasource,
        a.key,
        a.invoiceno,
        a.vendoramount as amount_usd,
        a.contractdays as contract_length,
        a.contractdays - 1 as contract_length_raw,
        a.acv_billings,
        a.acv,
        a.maintenanceenddate as contractitemenddate,
        a.maintenancestartdate as contractitemstartdate,
        a.contractitemterm,
        a.currency,
        a.customercategory,
        a.customersite,
        a.date,
        a.dateoffirstsale,
        a.documentnumber,
        a.duns,
        a.entitynohierarchy,
        a.externalid as transexternalid,
        a.globalultimateparent,
        a.globalultimateparentupper,
        a.itemtype,
        a.sbitemcategory as sbitemcategory1, -- DDL column is SBITEMCATEGORY (no trailing 1)
        a.itemid,
        a.lineid,
        a.lineofbusiness,
        a.listrate,
        a.naics,
        a.name,
        a.ordertype,
        a.ordertype1,
        a.pricelevel,
        a.product,
        a.quantity,
        a.quantitytype,
        a.sfdctype,
        a.sic,
        a.templatename,
        a.terms,
        a.transactiondiscount,
        a.type,
        a.vsoeallocation,
        a.vsoeamount,
        a.productgroup,
        a.plan_amt,
        a.flag_plan,
        a.flag_proforma,
        a.source,
        a.itemcategoryhidden,
        a.region as ship_region,  -- 05/20/2026 [Dan Girard] renamed from REGION to SHIP_REGION
        -- 05/18/2026 [Dan Girard] NAICS_SECTOR confirmed in ARR_MASTER_PROFORMA DDL; pulled directly
        a.naics_sector,
        -- 11/14/2024 [Dan Girard] proforma rows have no income account; stream_revenue is null
        null as stream_revenue
    from
        finance_db.public.arr_master_proforma a
)

-- ============================================================================
-- main: single transformation layer over raw_union.
-- Joins:
--   b  — dim_globalultimateparent_map  (GUP name override)
--   sf — vw_sfdc_invoice_data          (close date, core/ent flag)
--   p  — prod_map                      (pbt_group)
-- All derived fields computed here. Snowflake allows referencing a
-- calculated column alias defined earlier in the same SELECT list.
-- ============================================================================
, main as
(
    select
        u.datasource,
        u.key,
        u.invoiceno,
        u.amount_usd,
        u.acv_billings,
        u.acv,
        u.contractitemenddate,
        u.contractitemstartdate,
        u.contractitemterm,
        u.currency,
        u.customercategory,
        u.customersite,
        u.date,
        u.dateoffirstsale,
        u.documentnumber,
        u.duns,
        u.entitynohierarchy,
        u.transexternalid,
        coalesce(b.globalultimateparent_mapped, u.globalultimateparent) as globalultimateparent,
        upper(coalesce(b.globalultimateparent_mapped, u.globalultimateparent)) as globalultimateparentupper,
        u.itemtype,
        u.sbitemcategory1,
        u.itemid,
        u.lineid,
        u.lineofbusiness,
        u.listrate,
        u.naics,
        u.name,
        u.ordertype,
        u.ordertype1,
        u.pricelevel,
        u.product,
        u.quantity,
        u.quantitytype,
        u.sfdctype,
        u.sic,
        u.templatename,
        u.terms,
        u.transactiondiscount,
        u.type,
        u.vsoeallocation,
        u.vsoeamount,
        u.productgroup,
        u.contract_length,
        u.plan_amt,
        u.flag_plan,
        u.flag_proforma,
        u.source,
        u.itemcategoryhidden,
        u.ship_region,
        u.naics_sector,
        u.stream_revenue,
        p.pbt_group,
        -- 11/28/2023 [Dan Girard] direct_ecomm_flag
        case
            -- 12/6/2023 [Dan Girard] Added default for Bugsnag proforma
            when u.datasource in ('BS_STRIPE', 'BS_HEROKU')                 then 'Ecomm'
            when u.datasource = 'BS_Direct'                                  then 'Direct'
            when u.productgroup in ('Capture', 'Cucumber', 'Squad', 'Zephyr Scale') then 'Ecomm'
            when u.productgroup in (
                'AlertSite', 'AQTime', 'Collaborator', 'Hiptest', 'LoadComplete',
                'QAComplete', 'RAPI Performance', 'RAPI Test', 'RAPI Virtualization',
                'TestComplete', 'TestEngine', 'Zephyr E'
            ) then 'Direct'
            when u.date <= '2022-06-30'
                and coalesce(u.transexternalid, '') = ''
                and u.productgroup ilike '%CBT%'
                and lower(u.type) in ('invoice', 'credit memo')             then 'Direct'
            when u.date <= '2022-06-30'
                and coalesce(u.transexternalid, '') = ''
                and u.productgroup ilike '%CBT%'
                and lower(u.type) in ('cash sale', 'cash refund')           then 'Ecomm'
            -- 03/04/2026 [Dan Girard] Updated for Swagger Ecomm Reclass
            when u.type = 'Reclass'
                and coalesce(u.transexternalid, '') ilike '%braintree%'     then 'Ecomm'
            when u.date < '2022-01-01'
                and upper(u.productgroup) in ('LOADNINJA', 'PACTFLOW', 'BITBAR')
                and upper(u.name) like '%STRIPE%'                           then 'Ecomm'
            when (
                u.customercategory in ('Reseller', 'End User')
                or (u.customercategory = 'ecommerce' and upper(u.name) like '%CLEVERBRIDGE%')
            ) then 'Direct'
            -- 12/6/2023 [Dan Girard] Added default for type
            -- 02/27/2025 [Dan Girard] Added RECLASS
            when u.type in ('Invoice', 'Credit Memo', 'Reclass')            then 'Direct'
            -- 12/18/2023 [Dan Girard] Added Direct Sales; Ecommerce => Ecomm
            when u.source in ('Sales Assisted', 'Direct Sales')             then 'Direct'
            when u.source ilike 'Ecommerce'                                 then 'Ecomm'
            else 'Ecomm'
        end as direct_ecomm_flag,
        case
            when u.productgroup = 'Cucumber'              then 'Cucumber for Jira'
            when u.productgroup = 'Hiptest'               then 'CucumberStudio'
            when u.productgroup = 'Squad'                 then 'Zephyr Squad'
            when u.productgroup = 'RAPI Test'             then 'ReadyAPI Test'
            when u.productgroup = 'RedayAPI Test'         then 'ReadyAPI Test'
            when u.productgroup = 'TestEngine'            then 'ReadyAPI Test'
            when u.productgroup = 'RAPI Performance'      then 'ReadyAPI Perf'
            when u.productgroup = 'ReadyAPI Performance'  then 'ReadyAPI Perf'
            when u.productgroup = 'RAPI Virtualization'   then 'ReadyAPI Virt'
            when u.productgroup = 'ReadyAPI Virtualization' then 'ReadyAPI Virt'
            when u.productgroup = 'TestServer'            then 'TestComplete'
            when u.productgroup = 'Bitbar'                then 'BitBar'
            else u.productgroup
        end as product_for_reporting_ns,
        case
            when product_for_reporting_ns = 'BitBar'               then 'Functional Test'
            when product_for_reporting_ns ilike 'ReadyAPI%'        then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Swagger%'         then 'API Lifecycle'
            when product_for_reporting_ns ilike '%Pactflow%'       then 'API Lifecycle'
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when product_for_reporting_ns ilike 'API Hub Test'     then 'API Lifecycle'
            -- 03/11/2024 [Dan Girard] Added Reflect
            when product_for_reporting_ns in ('CucumberStudio', 'QAComplete', 'Reflect') then 'Test Management'
            when product_for_reporting_ns ilike 'Zephyr%'          then 'Test Management'
            when product_for_reporting_ns in ('TestComplete', 'LoadNinja') then 'Functional Test'
            when product_for_reporting_ns ilike 'CBT%'             then 'Functional Test'
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_for_reporting_ns ilike '%Bugsnag%'        then 'BugSnag'
            when product_for_reporting_ns in (
                'AlertSite', 'AQTime', 'Capture', 'Collaborator', 'Cucumber for Jira', 'LoadComplete'
            ) then 'Other'
            else product_for_reporting_ns
        end as product_for_reporting_group_ns,
        -- 8/28/2023 [Dan Girard] Added PRODUCT_FOR_REPORTING_NS_ALIAS and _COMBINED
        case
            when direct_ecomm_flag = 'Ecomm' and product_for_reporting_ns = 'CBT'               then 'Device Cloud'
            when direct_ecomm_flag = 'Ecomm' and upper(product_for_reporting_ns) = 'BITBAR'      then 'Device Cloud'
            when direct_ecomm_flag = 'Ecomm' and upper(product_for_reporting_ns) = 'BUGSNAG RUM' then 'BugSnag'
            when direct_ecomm_flag = 'Direct' and upper(product_for_reporting_ns) = 'BUGSNAG RUM' then 'BugSnag RUM'
            else product_for_reporting_ns
        end as product_for_reporting_ns_alias,
        -- 12/09/2025 [Dan Girard] Updated logic for BugSnag RUM
        case
            when product_for_reporting_ns_alias = 'BugSnag RUM' then product_for_reporting_ns_alias
            else concat(product_for_reporting_ns_alias, ' ', direct_ecomm_flag)
        end as product_for_reporting_ns_alias_combined,
        case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Added BugSnag RUM
            -- 12/09/2025 [Dan Girard] Update for BugSnag RUM Direct
            when product_for_reporting_ns_alias = 'BugSnag RUM'
                and direct_ecomm_flag = 'Direct'                                          then product_for_reporting_ns
            when product_for_reporting_ns_alias in ('BugSnag', 'BugSnag RUM', 'Stoplight', 'Swagger') then product_for_reporting_ns_alias_combined
            when product_for_reporting_ns_alias = 'CBT'
                and direct_ecomm_flag = 'Direct'                                          then 'CBT Sales Assisted'
            else product_for_reporting_ns_alias
        end as product_name,
        case
            when product_name in (
                'AlertSite', 'AQTime', 'Collaborator', 'Cucumber for Jira',
                'CucumberStudio', 'LoadComplete', 'LoadNinja', 'QAComplete'
            ) then 'Non-Core'
            -- 08/01/2024 [Dan Girard] Move CBT and BitBar to Non-Core
            when product_name ilike '%bitbar%'        then 'Non-Core'
            when product_name ilike '%CBT%'           then 'Non-Core'
            when product_name ilike 'Device Cloud'    then 'Non-Core'
            else 'Core'
        end as core_noncore,
        case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_name in ('BugSnag RUM', 'Pactflow', 'VisualTest', 'LoadNinja', 'Reflect')
                and direct_ecomm_flag = 'Ecomm'                                           then 'Indirect - Ecomm'
            when product_name in ('BugSnag Ecomm', 'Device Cloud', 'Stoplight Ecomm', 'Swagger Ecomm') then 'Indirect - Ecomm'
            -- 04/06/2026 [Dan Girard] Added Zephyr Advanced
            when product_name in (
                'Capture', 'Cucumber for Jira', 'Zephyr Scale', 'Zephyr Squad',
                'Zephyr Scale Automate', 'Zephyr Scale - Automate', 'QTM4J', 'Zephyr Advanced'
            ) then 'Indirect - Atlassian'
            else 'Direct'
        end as direct_indirect,
        case
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
            when product_name in (
                'Explore', 'Pactflow', 'Portal', 'ReadyAPI Perf', 'ReadyAPI Test',
                'ReadyAPI Virt', 'Stoplight Direct', 'Stoplight Ecomm',
                'Swagger Direct', 'Swagger Ecomm', 'API Hub Test', 'API Hub'
            ) then 'API'
            when product_name in (
                'Capture', 'Cucumber for Jira', 'Zephyr Scale', 'Zephyr Scale Automate',
                'Zephyr Scale - Automate', 'Zephyr Squad', 'Zephyr Advanced'
            ) then 'Marketplace'
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Changed to ILIKE BugSnag
            when product_name ilike 'BugSnag%'                                            then 'Observability'
            when product_name in (
                'AlertSite', 'AQTime', 'Collaborator', 'CucumberStudio', 'LoadComplete', 'QAComplete'
            ) then 'Other'
            -- 03/11/2024 [Dan Girard] Added Reflect
            when product_name in (
                'BitBar', 'CBT Sales Assisted', 'Device Cloud', 'LoadNinja',
                'TestComplete', 'VisualTest', 'Zephyr E', 'Reflect'
            ) then 'Test'
            when product_name in ('QTM', 'QTM4J')                                         then 'Test'
            else null
        end as product_name_group,
        -- 07/11/2024 [Dan Girard] Core/Enterprise flag from SFDC
        -- 03/26/2025 [Dan Girard] Updated logic to remove nulls
        -- 05/18/2026 [Dan Girard] sfdc_ent_core_flag → sfdc_core_ent_flag to match vw_sfdc_invoice_data output
        case
            when coalesce(sf.sfdc_core_ent_flag, '') = '' and direct_ecomm_flag = 'Ecomm'  then 'Ecomm'
            when coalesce(sf.sfdc_core_ent_flag, '') = '' and direct_ecomm_flag = 'Direct' then 'Core'
            else sf.sfdc_core_ent_flag
        end as sfdc_ent_core_flag,
        -- 11/07/2024 [Dan Girard] billing_term
        case
            when u.contract_length <= 33 then 'Monthly'
            when u.contract_length is null then null
            else 'Annual'
        end as billing_term,
        -- 11/24/2025 [Dan Girard] datasource_group
        case
            when u.datasource = 'NS' then 'As Reported'
            else 'Proforma'
        end as datasource_group
    from
        raw_union u
        left join finance_db.public.dim_globalultimateparent_map b
            on upper(u.globalultimateparent) = upper(b.globalultimateparent_orig)
        -- 05/18/2026 [Dan Girard] Replaced 4-CTE inline SFDC block with vw_sfdc_invoice_data
        left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf
            on u.invoiceno = sf.invoice_no
        -- 06/25/2025 [Dan Girard] Added join to prod_map for pbt_group
        left join prod_map p
            on upper(u.productgroup) = upper(p.productgroupmap)
)

-- ============================================================================
-- Final SELECT: clean passthrough from main.
-- All derived columns are already resolved in main; no calculations here.
-- ============================================================================
select
    -- 05/20/2026 [Dan Girard] Added ver_date to match master_billing_new pattern
    current_timestamp() as ver_date,
    m.datasource,
    m.key,
    m.invoiceno,
    m.amount_usd,
    m.acv_billings,
    m.acv,
    m.contractitemenddate,
    m.contractitemstartdate,
    m.contractitemterm,
    m.currency,
    m.customercategory,
    m.customersite,
    m.date,
    m.dateoffirstsale,
    m.documentnumber,
    m.duns,
    m.entitynohierarchy,
    m.transexternalid,
    m.globalultimateparent,
    m.globalultimateparentupper,
    m.itemtype,
    m.sbitemcategory1,
    m.itemid,
    m.lineid,
    m.lineofbusiness,
    m.listrate,
    m.naics,
    m.name,
    m.ordertype,
    m.ordertype1,
    m.pricelevel,
    m.product,
    m.quantity,
    m.quantitytype,
    m.sfdctype,
    m.sic,
    m.templatename,
    m.terms,
    m.transactiondiscount,
    m.type,
    m.vsoeallocation,
    m.vsoeamount,
    m.productgroup,
    m.contract_length,
    m.plan_amt,
    m.flag_plan,
    m.flag_proforma,
    m.source,
    m.itemcategoryhidden,
    m.ship_region,
    m.naics_sector,
    m.stream_revenue,
    m.pbt_group,
    m.direct_ecomm_flag,
    m.product_for_reporting_ns,
    m.product_for_reporting_group_ns,
    m.product_for_reporting_ns_alias,
    m.product_for_reporting_ns_alias_combined,
    m.product_name,
    m.core_noncore,
    m.direct_indirect,
    m.product_name_group,
    m.sfdc_ent_core_flag,
    m.billing_term,
    m.datasource_group
from
    main m
;
