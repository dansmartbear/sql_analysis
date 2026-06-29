create or replace procedure finance_db.dev_netsuite.sp_arr_master_waterfall()
    returns varchar
    language sql
    execute as owner
as
$$
begin

    create or replace table finance_db.dev_netsuite.arr_master_waterfall copy grants as
    
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
            when arr.datasource in ('Swagger Adj','ZS_Direct_Pre','Pre ZephryJC','BS_STRIPE','BS_HEROKU','SWAG_GLOBAL') then 'Ecomm'
            when arr.datasource = 'PACTFLOW_PF' then source
	    
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

            -- 12/15/2025 [Dan Girard] Added for BugSnag RUM Ecomm
            when upper(arr.productgroup) = 'BUGSNAG RUM' and source = 'Ecomm' then 'BugSnag'
            
            else productgroup
            end as productgroup,
        case
            when upper(productgroup) = 'HIPTEST' then 'CucumberStudio'
            when upper(productgroup) = 'CUCUMBER' then 'Cucumber for Jira'

            -- 12/09/2025 [Dan Girard] Added for Zephyr Scale Automate
            when upper(arr.productgroup) = 'ZEPHYR SCALE AUTOMATE' then 'Zephyr Scale'

            else productgroup
            end as productgroup_child,
        case
            when upper(productgroup) in ('AQTIME','ALERTSITE','CAPTURE','COLLABORATOR','CUCUMBER','LOADCOMPLETE','CUCUMBERSTUDIO','CUCUMBER FOR JIRA') then 'Collab, Monitor & Other'
            when upper(productgroup) in ('BITBAR', 'CBT', 'LOADNINJA', 'TESTCOMPLETE') then 'Functional Test'
    
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when upper(productgroup) in ('BUGSNAG', 'BUGSNAG RUM') then 'BugSnag'
            when upper(productgroup) in ('HIPTEST','QACOMPLETE','SQUAD','ZEPHYR E','ZEPHYR SCALE','ZEPHYR SQUAD','REFLECT','QTM','QTM4J') then 'Test Management'
    
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when upper(productgroup) in ('RAPI PERFORMANCE','RAPI TEST','RAPI VIRTUALIZATION','SWAGGER','TESTENGINE','PACTFLOW','TESTSERVER','EXPLORER','DOC PORTAL','READYAPI TEST','READYAPI PERFORMANCE','READYAPI VIRTUALIZATION','STOPLIGHT','API HUB','API HUB TEST') then 'API Lifecycle'
            else 'Other'
            end product_group_rollup,
        arr.acv,
        arr.region as ship_region,
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
        dd.*,
        case
            when arr.sbitemcategory1 ilike 'cloud' then 'SaaS'
            when arr.sbitemcategory1 ilike 'saas' then 'SaaS'
            when arr.sbitemcategory1 ilike 'support%' then 'Support'
            when arr.sbitemcategory1 ilike 'server' then 'Support'
            else 'License - Term'
            end sbitemcategory_calc,
            
        --7/12/2024 [Dan Girard] Added Core/Enterprise flag
        sfdc_ent_core_flag,
        
        -- 11/07/2024 [Dan Girard] Added billing_term
        billing_term,
        
        current_timestamp ver_date,
    
        -- 06/05/2025 [Dan Girard] Added pbt_group
        pbt_group,
    
         -- 11/24/2025 [Dan Girard] Added datasource_group
        datasource_group,

        -- 05/29/2026 [Dan Girard] Added SFDC_Name
        sfdc_name,
    from
        finance_db.dev_netsuite.arr_master arr
        left join (select distinct month_start, month_end from data_master_db.public.dimdate) dd on dd.month_end between arr.contractitemstartdate
            and arr.contractitemenddate

    ;

    return 'Successfully created or replaced table finance_db.public.arr_master_waterfall.';

end;
$$