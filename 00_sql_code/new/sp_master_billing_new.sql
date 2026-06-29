create or replace procedure finance_db.dev_netsuite.sp_master_billing_new()
    returns varchar
    language sql
    execute as owner
as
$$
begin

    /**********************************************************************
    Name:       finance_db.dev_netsuite.master_billing_new
    Type:       Table
    Created:    01/10/2023 [Dan Girard]
    Purpose:    Central billing fact table. Combines AS REPORTED actuals
                from vw_ns_ss546_new with PROFORMA billings from acquired
                companies not yet migrated into NetSuite. Together these
                produce the full billing picture used across all financial
                reporting.
                Refactor notes (05/18/2026):
                - Style conventions applied throughout: trailing commas,
                lowercase keywords, qualified column references, -- comments.
                - raw_union split from SFDC join and salesperson_location
                logic; those moved into main per CTE layer convention.
                - CTE mb renamed to main.
                - new_expansion and billing_category moved from final SELECT
                into main.
                - contract_length computed once in raw_union; removed
                duplicate recompute in main.
                - NAICS join updated to dev_netsuite.vw_naics_mapping_new.
                - product_group field name updated in DDL and references.
                - inline_discount empty-string guard removed (vw_ns_ss546_new
                outputs a clean decimal).
                - dateoffirstsale pulled directly (view already aliases it).
                - pf_billings joined to dim_product_dm_hierarchy_tbl in
                raw_union for product dimension fields.
    Updates:    02/14/2023 [Dan Girard]  Add region and NAICS
                06/28/2023 [Dan Girard]  Added DIRECT_ECOMM_FLAG, PRODUCT_FOR_REPORTING_NS, PRODUCT_FOR_REPORTING_GROUP_NS
                08/28/2023 [Dan Girard]  Updated defaults for bill/ship columns and INCOMEACCOUNTNAME in proforma section;
                                        added PRODUCT_FOR_REPORTING_NS_ALIAS and PRODUCT_FOR_REPORTING_NS_ALIAS_COMBINED
                12/21/2023 [Dan Girard]  Added product_name, core_noncore, direct_indirect, product_name_group
                01/24/2024 [Dan Girard]  Changed hard-coded PROFORMA for reporting_status to column pull
                01/30/2024 [Dan Girard]  Added salesperson_location
                02/07/2024 [Dan Girard]  Added SFDC CTE to pull invoice #s and close dates
                02/08/2024 [Dan Girard]  Added logic for blank salesperson locations (direct only)
                02/21/2024 [Dan Girard]  Added logic for sfdc_location from sfdc_license_booking_allopps; updated salesperson_location logic
                05/01/2024 [Dan Girard]  Changed calculations from AMOUNT to AMOUNT_USD; updated PULL_IN and INVOICE_AMOUNT logic
                08/01/2024 [Dan Girard]  Move CBT and BitBar to NON-CORE
                08/19/2024 [Dan Girard]  Added sfdc_deal_reg
                10/21/2024 [Dan Girard]  Added dateoffirstsale
                11/07/2024 [Dan Girard]  Added billing_term
                12/04/2024 [Dan Girard]  Added ACV_FC
                12/17/2024 [Dan Girard]  Added Scale Automate, Capture, Cucumber for Jira to Atlassian Hosting field
                03/03/2025 [Dan Girard]  Added CORE_ENT_FLAG from Salesforce data
                03/31/2025 [Dan Girard]  Moved ACV and MY logic to raw_union
                04/04/2025 [Dan Girard]  Added Scale Automate to Indirect Atlassian and Reporting Channel
                05/09/2025 [Dan Girard]  Added sfdc_account_name and averagerate
                05/14/2025 [Dan Girard]  Removed sfdc_line_item_owner_role
                05/28/2025 [Dan Girard]  Added TRANSEXTERNALID
                06/04/2025 [Dan Girard]  Added logic for Test and Contract Testing product name mapping
                09/04/2025 [Dan Girard]  Updated logic for Test to be API Hub Test
                09/11/2025 [Dan Girard]  Changed from Bugsnag to BugSnag
                11/17/2025 [Dan Girard]  Added Stripe_User_ID and Braintree_User_ID
                12/04/2025 [Dan Girard]  Changed BugSnag RUM Direct to BugSnag RUM
                01/14/2026 [Dan Girard]  Removed externalid
                02/11/2026 [Dan Girard]  Added logic for blank ordertype1
                02/19/2026 [Dan Girard]  Added MASTER_BILLING_ID unique identifier
                04/06/2026 [Dan Girard]  Added Zephyr Advanced to direct_indirect
                04/22/2026 [Dan Girard]  Added back bill_to_name and ship_to_name per Mike Curran
                05/18/2026 [Dan Girard]  Style refactor; NAICS to vw_naics_mapping_new; product_group rename;
                                        new_expansion and billing_category moved into main CTE;
                                        naics_sector pulled directly from vw_ns_ss546_new; redundant
                                        vw_naics_mapping_new join removed from final SELECT
                05/20/2026 [Dan Girard]  Added CONTRACT_LENGTH_RAW (datediff without +1) to match ARR_MASTER_NEW
    ***********************************************************************/
    create or replace table finance_db.dev_netsuite.master_billing_new copy grants
    (
        master_billing_id                             number(38,0) identity(1,1)
        , reporting_status                            varchar(30)
        , ver_date                                    timestamp
        , customercategory                            varchar(30)
        , date                                        date
        , invoiceno                                   varchar(30)
        , name                                        varchar(500)
        , item                                        varchar(100)
        , lineid                                      int
        , salesdescription                            varchar(500)
        , description                                 varchar(500)
        , sfdctype                                    varchar(30)
        , quantity                                    int
        , documentnumber                              varchar(30)
        , amount_usd                                  float
        , amount                                      float
        , currency                                    varchar(30)
        , amountforeigncurrency                       float
        , contractitemstartdate                       date
        , contractitemenddate                         date
        , type                                        varchar(30)
        , itemcategoryhidden                          varchar(30)
        , sbitemcategory1                             varchar(30)
        -- 01/14/2026 [Dan Girard] Removed since externalid is no longer available
        -- , externalid                                  varchar(30)
        , product                                     varchar(100)
        , ordertype1                                  varchar(30)
        , duns                                        varchar(500)
        , customersite                                varchar(500)
        , globalultimateparent                        varchar(500)
        , sisense_product_rollup                      varchar(30)
        , bill_country                                varchar(500)
        , bill_state                                  varchar(500)
        , bill_city                                   varchar(500)
        , ship_country                                varchar(500)
        , ship_state                                  varchar(500)
        , ship_city                                   varchar(500)
        , incomeaccountname                           varchar(500)
        , contract_length                             int
        -- 05/20/2026 [Dan Girard] Added to match ARR_MASTER_NEW; datediff without +1
        , contract_length_raw                         int
        , acv                                         float
        , my                                          float
        , product_for_reporting                       varchar(500)
        -- 05/18/2026 [Dan Girard] Renamed from product_group to productgroup per dim table update
        , productgroup                                varchar(500)
        , order_type_final                            varchar(30)
        , reporting_channel                           varchar(50)
        , recurring_status                            varchar(50)
        , stream_revenue                              varchar(50)
        , stream_reporting                            varchar(50)
        , atlassian_hosting                           varchar(50)
        , shipped_subregion                           varchar(50)  -- geo_2
        , shipped_region                              varchar(50)  -- geo_1
        , year                                        varchar(50)
        , annualized_acv                              float
        , status                                      varchar(50)
        , status_inq_pull                             varchar(50)
        , deal_count                                  int
        , pull_in                                     varchar(50)
        , one_year_or_less                            float
        , greater_than_2_years                        float
        , one_to_two_years                            float
        , one_year_more_or_less                       varchar(15)
        , external_id_present                         varchar(15)
        , monthly_arr                                 float
        , multiyear_flag                              int
        , quarter_end                                 date
        , close_quarter                               varchar(10)
        , term                                        varchar(25)
        , cap                                         int
        , overage                                     int
        , difference                                  float
        , pullin_dis                                  varchar(5)
        , invoice_amount                              int
        , tier                                        varchar(10)
        , inline_discount                             float
        , list_price                                  float
        , discount                                    float
        , ship_region                                 varchar(500)
        , naics_sector                                varchar(500)
        , direct_ecomm_flag                           varchar(50)
        , product_for_reporting_ns                    varchar(500)
        , product_for_reporting_group_ns              varchar(500)
        , product_for_reporting_ns_alias              varchar(500)
        , product_for_reporting_ns_alias_combined     varchar(500)
        , product_name                                varchar(500)
        , core_noncore                                varchar(500)
        , direct_indirect                             varchar(500)
        , product_name_group                          varchar(500)
        , salesperson_location                        varchar(500)
        , sfdc_closedate                              date
        , sfdc_deal_reg                               varchar(5)
        , bill_to_company                             varchar(500)
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        , bill_to_name                                varchar(500)
        , bill_to_address1                            varchar(500)
        , bill_to_address2                            varchar(500)
        , bill_to_address3                            varchar(500)
        , ship_to_company                             varchar(500)
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        , ship_to_name                                varchar(500)
        , ship_to_address1                            varchar(500)
        , ship_to_address2                            varchar(500)
        , ship_to_address3                            varchar(500)
        , date_of_first_sale                          date
        , billing_term                                varchar(50)
        , acv_fc                                      float
        , core_ent_flag                               varchar(50)
        -- 05/14/2025 [Dan Girard] Removed sfdc_line_item_owner_role
        -- , sfdc_line_item_owner_role                   varchar(500)
        , sfdc_account_name                           varchar(500)
        , averagerate                                 float
        , transexternalid                             varchar(500)
        , salesperson                                 varchar(500)
        , new_expansion                               varchar(500)
        , stripe_user_id                              varchar(500)
        , braintree_user_id                           varchar(500)
        , billing_category                            varchar(500)
        , pbt_group                                   varchar(500)
    ) as
    with
    -- ============================================================================
    -- raw_union: pure union of NS actuals and proforma rows.
    -- NS branch: pulls from vw_ns_ss546_new; product dim columns sourced from
    --   the view's join to dim_product_dm_hierarchy_tbl.
    -- Proforma branch: joins dim_product_dm_hierarchy_tbl directly since pf_billings
    --   has no equivalent dim join upstream.
    -- No calculations or SFDC joins here — those belong in main.
    -- ACV and MY are pre-computed here (03/31/2025 decision) because they are
    -- summed in main and must be consistent across both union branches.
    -- ============================================================================
    raw_union as
    (
        -- NS actuals from vw_ns_ss546_new
        select
            'AS REPORTED' as reporting_status,
            ns.customercategory,
            ns.date,
            ns.invoiceno,
            ns.name,
            ns.item,
            ns.lineid,
            ns.salesdescription,
            ns.description,
            ns.sfdctype,
            ns.quantity,
            ns.documentnumber,
            ns.amount_usd,
            ns.amount,
            ns.currency,
            ns.amountforeigncurrency * -1 as amountforeigncurrency,  -- flip sign to match expected direction
            ns.contractitemstartdate,
            ns.contractitemenddate,
            ns.type,
            ns.itemcategoryhidden,
            ns.sbitemcategory1,
            ns.product,
            ns.ordertype1,
            ns.duns,
            ns.customersite,
            ns.globalultimateparent,
            ns.sisense_product_rollup,
            ns.bill_country,
            ns.bill_state,
            ns.bill_city,
            ns.ship_country,
            ns.ship_state,
            ns.ship_city,
            ns.incomeaccountname,
            ns.inline_discount,  -- vw_ns_ss546_new outputs a clean decimal; no empty-string guard needed
            ns.ship_region,
            ns.naics,
            -- 05/18/2026 [Dan Girard] naics_sector pulled directly from view; eliminates redundant NAICS join in final SELECT
            ns.naics_sector,
            ns.direct_ecomm_flag,
            ns.product_for_reporting_ns,
            ns.product_for_reporting_group_ns,
            ns.product_for_reporting_ns_alias,
            ns.product_for_reporting_ns_alias_combined,
            ns.sfdc_deal_reg,
            ns.bill_to_company,
            ns.bill_to_name,
            ns.bill_to_address1,
            ns.bill_to_address2,
            ns.bill_to_address3,
            ns.ship_to_company,
            ns.ship_to_name,
            ns.ship_to_address1,
            ns.ship_to_address2,
            ns.ship_to_address3,
            ns.dateoffirstsale,  -- vw_ns_ss546_new already aliases dateoffirstsale
            ns.averagerate,
            ns.transexternalid,
            ns.salesperson,
            ns.salesperson_location as ns_salesperson_location,
            ns.stripe_user_id,
            ns.braintree_user_id,
            -- product dim columns sourced from view's dim_product_dm_hierarchy_tbl join
            ns.product_name,
            ns.core_noncore,
            ns.direct_indirect,
            ns.product_name_group,
            ns.productgroup,  -- 05/18/2026 [Dan Girard] renamed from product_group
            ns.pbt_group,
            -- 03/31/2025 [Dan Girard] ACV and MY pre-computed so main can sum them
            datediff(day, ifnull(ns.contractitemstartdate, current_date()), ifnull(ns.contractitemenddate, current_date())) + 1 as contract_length,
            -- 05/20/2026 [Dan Girard] contract_length_raw: datediff without +1; matches ARR_MASTER_NEW convention
            datediff(day, ifnull(ns.contractitemstartdate, current_date()), ifnull(ns.contractitemenddate, current_date())) as contract_length_raw,
            case
                when contract_length = 0                        then 0
                when ns.sbitemcategory1 = 'license - perpetual' then ns.amount_usd
                when contract_length <= 366                      then ns.amount_usd
                else (ns.amount_usd / contract_length) * 365
            end as acv,
            ns.amount_usd - acv as my
        from
            finance_db.dev_netsuite.vw_ns_ss546_new ns
        union all
        -- Proforma billings from acquired companies not yet in NetSuite.
        -- Joins dim_product_dm_hierarchy_tbl to resolve product dimension fields
        -- since pf_billings carries raw product values only.
        select
            p.reporting_status,
            '' as customercategory,
            p.date,
            '' as invoiceno,
            'unknown - proforma' as name,
            '' as item,
            0 as lineid,
            '' as salesdescription,
            '' as description,
            '' as sfdctype,
            0 as quantity,
            'proforma' as documentnumber,
            p.amount_usd as amount_usd,
            p.amount_usd as amount,
            'usd' as currency,
            p.amount_usd as amountforeigncurrency,
            p.contract_start_date as contractitemstartdate,
            p.contract_end_date as contractitemenddate,
            '' as type,
            p.stream as itemcategoryhidden,
            p.stream as sbitemcategory1,
            p.product,
            p.order_type as ordertype1,
            '' as duns,
            '' as customersite,
            'unknown - proforma' as globalultimateparent,
            p.product as sisense_product_rollup,
            -- 08/28/2023 [Dan Girard] Default geography stubs for proforma rows
            'United States' as bill_country,
            'Proforma' as bill_state,
            'Proforma' as bill_city,
            'United States' as ship_country,
            'Proforma' as ship_state,
            'Proforma' as ship_city,
            p.stream as incomeaccountname,
            0 as inline_discount,
            '' as ship_region,
            '' as naics,
            -- 05/18/2026 [Dan Girard] proforma rows have no NAICS data; stub to empty string
            '' as naics_sector,
            p.direct_ecomm_flag,
            ph.product_for_reporting_ns,
            ph.product_for_reporting_group_ns,
            ph.product_for_reporting_ns_alias,
            ph.product_for_reporting_ns_alias_combined,
            null as sfdc_deal_reg,
            null as bill_to_company,
            null as bill_to_name,
            null as bill_to_address1,
            null as bill_to_address2,
            null as bill_to_address3,
            null as ship_to_company,
            null as ship_to_name,
            null as ship_to_address1,
            null as ship_to_address2,
            null as ship_to_address3,
            null as dateoffirstsale,
            1 as averagerate,
            '' as transexternalid,
            '' as salesperson,
            p.salesperson_location as ns_salesperson_location,  -- 05/17/2026 [Dan Girard] populated in pf_billings; pull directly
            '' as stripe_user_id,
            '' as braintree_user_id,
            ph.product_name,
            ph.core_noncore,
            ph.direct_indirect,
            ph.product_name_group,
            ph.product_group_map,  -- 05/18/2026 [Dan Girard] renamed from product_group
            ph.pbt_group,
            -- 03/31/2025 [Dan Girard] ACV and MY pre-computed so main can sum them
            datediff(day, ifnull(p.contract_start_date, current_date()), ifnull(p.contract_end_date, current_date())) + 1 as contract_length,
            -- 05/20/2026 [Dan Girard] contract_length_raw: datediff without +1; matches ARR_MASTER_NEW convention
            datediff(day, ifnull(p.contract_start_date, current_date()), ifnull(p.contract_end_date, current_date())) as contract_length_raw,
            case
                when contract_length = 0   then 0
                when contract_length <= 366 then p.amount_usd
                else (p.amount_usd / contract_length) * 365
            end as acv,
            p.amount_usd - acv as my
        from
            finance_db.public.pf_billings p
            left join finance_db.public.dim_product_dm_hierarchy_tbl ph
                on upper(p.product) = ph.lookup_map_upper
                or upper(concat(p.product, '_', p.direct_ecomm_flag)) = ph.lookup_map_upper
    )
    -- ============================================================================
    -- tiers: invoice-level amount buckets for tier and invoice_amount fields.
    -- Filtered to AS REPORTED rows only — proforma rows have no invoice number.
    -- ============================================================================
    , tiers as
    (
        select
            u.invoiceno,
            to_number(sum(u.amount_usd), 38, 2) as invoice_amount,
            -- 05/01/2024 [Dan Girard] Changed from amount to amount_usd
            case
                when abs(invoice_amount) > 250000 then '$250k+'
                when abs(invoice_amount) > 100000 then '$100-250k'
                when abs(invoice_amount) > 50000  then '$50-100k'
                when abs(invoice_amount) > 25000  then '$25-50k'
                when abs(invoice_amount) > 10000  then '$10-25k'
                when abs(invoice_amount) > 5000   then '$5-10k'
                when abs(invoice_amount) > 0      then '$0-5k'
                else ''
            end as tier
        from
            raw_union u
        where
            upper(u.reporting_status) = 'AS REPORTED'
            and u.invoiceno is not null
        group by
            u.invoiceno
    )
    -- ============================================================================
    -- main: single transformation layer over the union.
    -- Joins:
    --   sf  — vw_sfdc_invoice_data  (close date, location, core/ent flag, account)
    --   scm — dim_country_map       (mapped region and subregion from ship_country)
    --   t   — tiers                 (invoice amount and tier bucket)
    -- Computes all derived fields. Snowflake allows referencing a calculated column
    -- alias defined earlier in the same SELECT list, so dependent expressions chain
    -- without additional CTEs.
    -- ============================================================================
    , main as
    (
        select
            u.reporting_status,
            u.customercategory,
            u.date,
            u.invoiceno,
            u.name,
            u.item,
            u.lineid,
            u.salesdescription,
            u.description,
            u.sfdctype,
            u.quantity,
            u.documentnumber,
            sum(u.amount_usd) as amount_usd,
            sum(u.amount) as amount,
            u.currency,
            u.amountforeigncurrency,
            u.contractitemstartdate,
            u.contractitemenddate,
            u.type,
            u.itemcategoryhidden,
            u.sbitemcategory1,
            u.product,
            u.ordertype1,
            u.duns,
            u.customersite,
            u.globalultimateparent,
            u.sisense_product_rollup,
            u.bill_country,
            u.bill_state,
            u.bill_city,
            u.ship_country,
            u.ship_state,
            u.ship_city,
            u.incomeaccountname,
            u.contract_length,
            u.contract_length_raw,
            sum(u.acv) as acv,
            sum(u.my) as my,
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
            u.dateoffirstsale,
            u.averagerate,
            u.transexternalid,
            u.salesperson,
            u.direct_ecomm_flag,
            u.product_for_reporting_ns,
            u.product_for_reporting_group_ns,
            u.product_for_reporting_ns_alias,
            u.product_for_reporting_ns_alias_combined,
            u.ship_region,
            u.naics,
            u.naics_sector,
            u.inline_discount,
            u.stripe_user_id,
            u.braintree_user_id,
            u.product_name,
            u.core_noncore,
            u.direct_indirect,
            u.product_name_group,
            u.productgroup,
            u.pbt_group,
            -- ---- SFDC enrichment -----------------------------------------------
            -- 02/07/2024 [Dan Girard] sfdc_closedate from vw_sfdc_invoice_data
            sf.sfdc_closedate,
            -- 02/21/2024 [Dan Girard] salesperson_location: sfdc source takes precedence;
            --   India normalized to Bangalore in the view; fall back to NS location or Somerville for direct
            case
                when sf.sfdc_location = 'India'                        then 'Bangalore'
                when coalesce(sf.sfdc_location, '') <> ''              then sf.sfdc_location
                when coalesce(u.ns_salesperson_location, '') <> ''     then u.ns_salesperson_location
                when u.direct_ecomm_flag = 'Direct'                    then 'Somerville'
                else ''
            end as salesperson_location,
            -- 03/03/2025 [Dan Girard] core_ent_flag: ecomm rows tagged as Ecomm; others from sfdc
            case
                when u.direct_ecomm_flag = 'Ecomm' then 'Ecomm'
                else sf.sfdc_core_ent_flag
            end as core_ent_flag,
            sf.sfdc_account_name,
            -- ---- Geography enrichment ------------------------------------------
            scm.mapped_subregion as shipped_subregion,  -- geo_2
            scm.mapped_region as shipped_region,         -- geo_1
            -- ---- Invoice tier --------------------------------------------------
            t.invoice_amount,
            t.tier,
            -- ---- Calculated fields ---------------------------------------------
            -- product_for_reporting sourced from product_for_reporting_ns per current logic
            u.product_for_reporting_ns as product_for_reporting,
            -- 02/11/2026 [Dan Girard] order_type_final: normalize ordertype1; fall back to sfdctype when blank
            case
                when u.ordertype1 in ('New', 'Existing') then 'License'
                when u.ordertype1 = 'Renewal'            then 'Renewal'
                when u.ordertype1 = ''                   then
                    case
                        when u.sfdctype in ('New', 'Expansion') then 'License'
                        when u.sfdctype = 'Renewal'             then 'Renewal'
                        else '-'
                    end
                else u.ordertype1
            end as order_type_final,
            -- 04/04/2025 [Dan Girard] reporting_channel
            case
                when u.product_for_reporting_ns ilike any ('Zephyr Squad', 'Zephyr Scale', 'CBT Ecomm', 'Capture', 'Cucumber for Jira', 'BugSnag Ecomm', 'Swagger Ecomm', 'Zephyr Scale Automate', 'Zephyr Advanced') then 'Ecomm'
                else 'Direct'
            end as reporting_channel,
            case
                when u.sbitemcategory1 in ('Services', 'License - Perpetual') then 'Non-Reccuring'
                when u.sbitemcategory1 is null                                 then 'Unknown'
                when u.sbitemcategory1 = ''                                    then 'Unknown'
                else 'Recurring'
            end as recurring_status,
            -- 08/02/2023 [Dan Girard] Updated stream_revenue logic
            case
                when u.incomeaccountname ilike '%License Revenue%'                             then 'Perpetual License'
                when u.incomeaccountname ilike '%SaaS%'                                        then 'SaaS'
                when u.incomeaccountname ilike '%Training%'                                    then 'Professional Services'
                when u.incomeaccountname ilike '%Professional Services%'                       then 'Professional Services'
                when u.incomeaccountname in ('Other - Test', 'Other Travel')                   then 'Professional Services'
                when u.incomeaccountname ilike '%Subscription Revenue%'                        then 'Subscription License'
                when u.incomeaccountname ilike '%MAintENANCE REV RENEW : SUB MNT REV RENEW%'  then 'Subscription Maintenance'
                when u.incomeaccountname ilike '%MAintENANCE REV Y1%'                          then 'Subscription Maintenance'
                when u.incomeaccountname ilike '%Maintenance  Revenue Renewal%'                then 'Perpetual Maintenance'
                when u.incomeaccountname ilike '%Maintenance Revenue Renewal%'                 then 'Perpetual Maintenance'
                when u.incomeaccountname in (
                    'Maintenance  Revenue YR 1 - API',
                    'Maintenance  Revenue YR 1 - Dev',
                    'Maintenance  Revenue YR 1 - Test',
                    'Maintenance  Revenue YR 1 - UXM',
                    'Maintenance  Revenue YR 1 - Zephyr',
                    'Maintenance  Revenue YR 1 - Other'
                ) then 'Perpetual Maintenance'
                when u.incomeaccountname in (
                    'Maintenance Revenue YR 1 - API',
                    'Maintenance Revenue YR 1 - Dev',
                    'Maintenance Revenue YR 1 - Test',
                    'Maintenance Revenue YR 1 - UXM',
                    'Maintenance Revenue YR 1 - Zephyr',
                    'Maintenance Revenue YR 1 - Other'
                ) then 'Perpetual Maintenance'
                else 'Undefined'
            end as stream_revenue,
            case
                when stream_revenue in ('Subscription Maintenance', 'Perpetual Maintenance') then 'Maintenance'
                else stream_revenue
            end as stream_reporting,
            to_char(year(u.date)) as year,
            dateadd('day', -1, date_trunc('quarter', dateadd('month', 3, u.date))) as quarter_end,
            case
                when u.contract_length = 0 then 0
                else (amount_usd / u.contract_length) * 365
            end as annualized_acv,
            case
                when order_type_final = 'Renewal' then
                    case
                        when u.contractitemstartdate <= dateadd(day, 1, quarter_end) then 'INQ'
                        else 'Pull'
                    end
                else 'INQ'
            end as status,
            case
                when u.contractitemstartdate <= dateadd(day, 1, quarter_end) then 'INQ'
                else 'Pull'
            end as status_inq_pull,
            case
                when amount = 0 then 0
                when amount > 0 then 1
                else -1
            end as deal_count,
            -- 05/01/2024 [Dan Girard] Changed logic from = INQ to <> INQ
            case
                when status <> 'INQ' and datediff(day, quarter_end, u.contractitemstartdate) + 1 < 31  then '30 Days'
                when status <> 'INQ' and datediff(day, quarter_end, u.contractitemstartdate) + 1 < 61  then '60 Days'
                when status <> 'INQ' and datediff(day, quarter_end, u.contractitemstartdate) + 1 < 91  then '90 Days'
                when status <> 'INQ' and datediff(day, quarter_end, u.contractitemstartdate) + 1 >= 91 then '+90 Days'
                else 'INQ'
            end as pull_in,
            case
                when u.contract_length = 0   then 0
                when u.contract_length <= 366 then amount_usd
                else (amount_usd / u.contract_length) * 365
            end as one_year_or_less,
            case
                when u.contract_length = 0   then 0
                when u.contract_length > 731 then (amount_usd / u.contract_length) * (u.contract_length - 731)
                else 0
            end as greater_than_2_years,
            case
                when u.contract_length >= 367 then (amount_usd - one_year_or_less - greater_than_2_years)
                else 0
            end as one_to_two_years,
            case
                when one_to_two_years = 0 then '1 Year or Less'
                else '1 Year or More'
            end as one_year_more_or_less,
            -- 01/14/2026 [Dan Girard] externalid removed; hardcoded to No ID
            'No ID' as external_id_present,
            case
                when u.contract_length = 0  then 0
                when u.contract_length < 32 then ((amount_usd / u.contract_length) * 365) / 3
                else (amount_usd / u.contract_length) * 365
            end as monthly_arr,
            case
                when u.contract_length > 548 then 1
                else 0
            end as multiyear_flag,
            concat('q', quarter(u.date), year(u.date)) as close_quarter,
            -- 03/18/2026 [Dan Girard] Updated term buckets; added 1 year bucket
            case
                when u.contract_length > 1096 then '3 years plus'
                when u.contract_length > 730  then '3 years'
                when u.contract_length > 366  then '2 years'
                when u.contract_length > 363  then '1 year'
                else 'Less than 1 year'
            end as term,
            365 * 3 as cap,
            u.contract_length - cap as overage,
            case
                when u.contract_length = 0 then 0
                else (amount_usd / u.contract_length) * overage
            end as difference,
            case
                when dateadd('day', -1, u.contractitemstartdate) > quarter_end then 'Yes'
                else 'No'
            end as pullin_dis,
            case
                when 1 - u.inline_discount = 0 then u.amountforeigncurrency
                else u.amountforeigncurrency / (1 - u.inline_discount)
            end as list_price,
            1 - div0(u.amountforeigncurrency, list_price) as discount,
            -- 11/07/2024 [Dan Girard] billing_term
            case
                when u.contract_length <= 33 then 'Monthly'
                else 'Annual'
            end as billing_term,
            -- 12/04/2024 [Dan Girard] acv_fc: ACV based on foreign currency amount
            case
                when u.contract_length = 0                        then 0
                when u.sbitemcategory1 = 'license - perpetual'    then u.amountforeigncurrency
                when u.contract_length <= 366                      then u.amountforeigncurrency
                else (u.amountforeigncurrency / u.contract_length) * 365
            end as acv_fc,
            -- 09/11/2025 [Dan Girard] atlassian_hosting: cloud/DC/server for Atlassian indirect rows
            case
                when u.direct_indirect = 'Indirect - Atlassian' then
                    case
                        when u.sbitemcategory1 ilike '%SaaS%' then 'Cloud'
                        when u.sbitemcategory1 ilike '%Term%' then 'Data Center'
                        else 'Server'
                    end
                else ''
            end as atlassian_hosting,
            -- 08/20/2025 [Dan Girard] new_expansion: New / Expansion / Renewal classification
            case
                when order_type_final = 'Renewal'                    then 'Renewal'
                when u.sfdctype = 'New'                              then 'New'
                when u.sfdctype <> ''                                then 'Expansion'
                when u.sfdctype = '' and u.ordertype1 = 'Existing'  then 'Expansion'
                else u.ordertype1
            end as new_expansion,
            -- billing_category: high-level channel classification
            case
                when u.direct_indirect = 'Direct' and order_type_final = 'License' then 'Direct License'
                when u.direct_indirect = 'Direct' and order_type_final = 'Renewal' then 'Direct Renewal'
                when u.direct_indirect = 'Indirect - Atlassian'                    then 'Atlassian'
                when u.direct_indirect = 'Indirect - Ecomm'                        then 'SmartBear Ecomm'
                else 'Uncategorized'
            end as billing_category
        from
            raw_union u
            left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf on u.invoiceno = sf.invoice_no
            left join finance_db.public.dim_country_map scm on u.ship_country = scm.original_country
            left join tiers t on u.invoiceno = t.invoiceno
        group by
            all
    )
    -- ============================================================================
    -- Final SELECT: clean passthrough from main. naics_sector is carried through
    -- from main (sourced from vw_ns_ss546_new) — no NAICS join needed here.
    -- master_billing_id assigned via row_number() with a stable, deterministic sort key.
    -- ============================================================================
    select
        -- 02/19/2026 [Dan Girard] Unique row identifier
        row_number() over (
            order by
                coalesce(m.invoiceno, ''),
                m.lineid,
                coalesce(m.documentnumber, ''),
                coalesce(m.item, ''),
                coalesce(m.product, ''),
                m.date,
                m.contractitemstartdate,
                m.contractitemenddate,
                m.amount_usd,
                m.amount
        ) as master_billing_id,
        m.reporting_status,
        current_timestamp() as ver_date,
        m.customercategory,
        m.date,
        m.invoiceno,
        m.name,
        m.item,
        m.lineid,
        m.salesdescription,
        m.description,
        m.sfdctype,
        m.quantity,
        m.documentnumber,
        m.amount_usd,
        m.amount,
        m.currency,
        m.amountforeigncurrency,
        m.contractitemstartdate,
        m.contractitemenddate,
        m.type,
        m.itemcategoryhidden,
        m.sbitemcategory1,
        m.product,
        m.ordertype1,
        m.duns,
        m.customersite,
        m.globalultimateparent,
        m.sisense_product_rollup,
        m.bill_country,
        m.bill_state,
        m.bill_city,
        m.ship_country,
        m.ship_state,
        m.ship_city,
        m.incomeaccountname,
        m.contract_length,
        m.contract_length_raw,
        m.acv,
        m.my,
        m.product_for_reporting,
        m.productgroup,
        m.order_type_final,
        m.reporting_channel,
        m.recurring_status,
        m.stream_revenue,
        m.stream_reporting,
        m.atlassian_hosting,
        m.shipped_subregion,   -- geo_2
        m.shipped_region,      -- geo_1
        m.year,
        m.annualized_acv,
        m.status,
        m.status_inq_pull,
        m.deal_count,
        m.pull_in,
        m.one_year_or_less,
        m.greater_than_2_years,
        m.one_to_two_years,
        m.one_year_more_or_less,
        m.external_id_present,
        m.monthly_arr,
        m.multiyear_flag,
        m.quarter_end,
        m.close_quarter,
        m.term,
        m.cap,
        m.overage,
        m.difference,
        m.pullin_dis,
        m.invoice_amount,
        m.tier,
        m.inline_discount,
        m.list_price,
        m.discount,
        m.ship_region,
        -- 05/18/2026 [Dan Girard] naics_sector passed through from main; no NAICS join needed here
        m.naics_sector,
        m.direct_ecomm_flag,
        m.product_for_reporting_ns,
        m.product_for_reporting_group_ns,
        m.product_for_reporting_ns_alias,
        m.product_for_reporting_ns_alias_combined,
        m.product_name,
        m.core_noncore,
        m.direct_indirect,
        m.product_name_group,
        m.salesperson_location,
        m.sfdc_closedate,
        m.sfdc_deal_reg,
        m.bill_to_company,
        m.bill_to_name,
        m.bill_to_address1,
        m.bill_to_address2,
        m.bill_to_address3,
        m.ship_to_company,
        m.ship_to_name,
        m.ship_to_address1,
        m.ship_to_address2,
        m.ship_to_address3,
        m.dateoffirstsale,
        m.billing_term,
        m.acv_fc,
        m.core_ent_flag,
        m.sfdc_account_name,
        m.averagerate,
        m.transexternalid,
        m.salesperson,
        m.new_expansion,
        m.stripe_user_id,
        m.braintree_user_id,
        m.billing_category,
        m.pbt_group
    from
        main m
    ;

    return 'Successfully created or replaced table finance_db.dev_netsuite.sp_master_billing_new.';

end;
$$
;