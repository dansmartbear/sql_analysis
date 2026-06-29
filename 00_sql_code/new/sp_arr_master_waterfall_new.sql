create or replace procedure finance_db.dev_netsuite.sp_arr_master_waterfall_new()
    returns varchar
    language sql
    execute as owner
as
$$
begin

    /**********************************************************************

    Name:       finance_db.dev_netsuite.arr_master_waterfall_new
    Type:       Table
    Created:    06/29/2026 [Dan Girard]
    Purpose:    Waterfall expansion of arr_master. Joins each contract row
                to dimdate to produce one row per calendar month the contract
                is active (month_end between contractitemstartdate and
                contractitemenddate). Used for period-by-period ARR reporting.

                Refactor notes (06/29/2026):
                - Stored procedure wrapper removed; converted to standalone
                create or replace table statement.
                - Inline dimdate subquery moved to dim_date CTE per
                CTE-over-subquery convention.
                - dd.* replaced with explicit dd.month_start, dd.month_end.
                - All column references qualified with table alias throughout:
                    bare `source` in PACTFLOW_PF branch → arr.source
                    bare `productgroup` in else clause → arr.productgroup
                    bare `sfdc_ent_core_flag` → arr.sfdc_ent_core_flag
                    bare `billing_term`       → arr.billing_term
                    bare `pbt_group`          → arr.pbt_group
                    bare `datasource_group`   → arr.datasource_group
                    bare `sfdc_name`          → arr.sfdc_name
                - current_timestamp → current_timestamp() as ver_date.
                - Keywords lowercased; trailing commas; 4-space indentation.

    Note:       productgroup_child and product_group_rollup reference the
                computed `productgroup` alias from earlier in the same SELECT
                list. This is valid Snowflake behavior (prior-alias reference).
                The ZEPHYR SCALE AUTOMATE branch in productgroup_child uses
                arr.productgroup (raw) intentionally — preserved from original.

                Re-pointed to arr_master_new on 06/29/2026 [Dan Girard]:
                arr.region updated to arr.ship_region (column renamed in new table)

    ***********************************************************************/
    create or replace table finance_db.dev_netsuite.arr_master_waterfall_new copy grants as
    with

    -- dim_date: distinct month start/end pairs used to expand contracts into monthly rows
    dim_date as
    (
        select distinct
            dd.month_start,
            dd.month_end
        from
            data_master_db.public.dimdate dd
    )

    select
        dd.month_end as date_under_contract,
        arr.datasource,
        arr.key,
        arr.date as invoice_date,
        arr.invoiceno,
        arr.globalultimateparentupper,
        arr.ordertype1 as ordertype,
        arr.contractitemstartdate,
        arr.contractitemenddate,
        case
            when arr.contractitemstartdate <= '2022-01-01'
                and arr.customercategory = 'ecommerce'
                and upper(arr.name) not like '%CLEVERBRIDGE%' then 'Ecomm'
            when arr.datasource in ('Swagger Adj', 'ZS_Direct_Pre', 'Pre ZephryJC', 'BS_STRIPE', 'BS_HEROKU', 'SWAG_GLOBAL') then 'Ecomm'
            -- arr.source passes through the source value stored on the arr_master row
            when arr.datasource = 'PACTFLOW_PF' then arr.source
            -- 05/28/2026 [Dan Girard] Added Portal
            when arr.productgroup = 'Portal' then 'Sales Assisted'
            when arr.direct_ecomm_flag ilike '%Ecomm%' then 'Ecomm'
            when arr.direct_ecomm_flag ilike '%Direct%' then 'Sales Assisted'
            else 'Sales Assisted'
        end as source,
        case
            when upper(arr.productgroup) in ('TESTSERVER', 'TESTENGINE', 'SOAPUI') then 'ReadyAPI Test'
            when upper(arr.productgroup) = 'LOADUI' then 'ReadyAPI Performance'
            when upper(arr.productgroup) = 'SERVICEV' then 'ReadyAPI Virtualization'
            when upper(arr.productgroup) = 'HIPTEST' then 'CucumberStudio'
            when upper(arr.productgroup) = 'CUCUMBER' then 'Cucumber for Jira'
            -- 12/09/2025 [Dan Girard] Added for Zephyr Scale Automate
            when upper(arr.productgroup) = 'ZEPHYR SCALE AUTOMATE' then 'Zephyr Scale'
            -- 12/15/2025 [Dan Girard] Added for BugSnag RUM Ecomm; source alias resolved from earlier in SELECT
            when upper(arr.productgroup) = 'BUGSNAG RUM' and source = 'Ecomm' then 'BugSnag'
            else arr.productgroup
        end as productgroup,
        case
            when upper(productgroup) = 'HIPTEST' then 'CucumberStudio'
            when upper(productgroup) = 'CUCUMBER' then 'Cucumber for Jira'
            -- 12/09/2025 [Dan Girard] Added for Zephyr Scale Automate; checks raw column intentionally
            when upper(arr.productgroup) = 'ZEPHYR SCALE AUTOMATE' then 'Zephyr Scale'
            else productgroup
        end as productgroup_child,
        case
            when upper(productgroup) in ('AQTIME', 'ALERTSITE', 'CAPTURE', 'COLLABORATOR', 'CUCUMBER', 'LOADCOMPLETE', 'CUCUMBERSTUDIO', 'CUCUMBER FOR JIRA') then 'Collab, Monitor & Other'
            when upper(productgroup) in ('BITBAR', 'CBT', 'LOADNINJA', 'TESTCOMPLETE') then 'Functional Test'
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when upper(productgroup) in ('BUGSNAG', 'BUGSNAG RUM') then 'BugSnag'
            when upper(productgroup) in ('HIPTEST', 'QACOMPLETE', 'SQUAD', 'ZEPHYR E', 'ZEPHYR SCALE', 'ZEPHYR SQUAD', 'REFLECT', 'QTM', 'QTM4J') then 'Test Management'
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when upper(productgroup) in ('RAPI PERFORMANCE', 'RAPI TEST', 'RAPI VIRTUALIZATION', 'SWAGGER', 'TESTENGINE', 'PACTFLOW', 'TESTSERVER', 'EXPLORER', 'DOC PORTAL', 'READYAPI TEST', 'READYAPI PERFORMANCE', 'READYAPI VIRTUALIZATION', 'STOPLIGHT', 'API HUB', 'API HUB TEST') then 'API Lifecycle'
            else 'Other'
        end as product_group_rollup,
        arr.acv,
        arr.ship_region,
        arr.naics_sector,
        arr.direct_ecomm_flag,
        arr.product_for_reporting_ns,
        arr.product_for_reporting_group_ns,
        arr.product_for_reporting_ns_alias,
        arr.product_for_reporting_ns_alias_combined,
        arr.product_name,
        arr.core_noncore,
        arr.direct_indirect,
        arr.product_name_group,
        dd.month_start,
        dd.month_end,
        case
            when arr.sbitemcategory1 ilike 'cloud' then 'SaaS'
            when arr.sbitemcategory1 ilike 'saas' then 'SaaS'
            when arr.sbitemcategory1 ilike 'support%' then 'Support'
            when arr.sbitemcategory1 ilike 'server' then 'Support'
            else 'License - Term'
        end as sbitemcategory_calc,
        -- 07/12/2024 [Dan Girard] Added Core/Enterprise flag
        arr.sfdc_ent_core_flag,
        -- 11/07/2024 [Dan Girard] Added billing_term
        arr.billing_term,
        current_timestamp() as ver_date,
        -- 06/05/2025 [Dan Girard] Added pbt_group
        arr.pbt_group,
        -- 11/24/2025 [Dan Girard] Added datasource_group
        arr.datasource_group,
        -- 05/29/2026 [Dan Girard] Added SFDC_Name
        arr.sfdc_name
    from
        finance_db.dev_netsuite.arr_master_new arr
        left join dim_date dd
            on dd.month_end between arr.contractitemstartdate and arr.contractitemenddate
    ;

    return 'Successfully created or replaced table finance_db.dev_netsuite.sp_arr_master_waterfall_new.';

end;
$$