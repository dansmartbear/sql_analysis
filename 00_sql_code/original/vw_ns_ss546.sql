/*==============================================================================
View Name
    finance_db.public.vw_ns_ss546

Source Tables
    finance_db.ingest.ns_ss546_cm_pm_stg
    finance_db.ingest.ns_ss546_stat_stg

Reference Tables
    finance_db.public.dim_globalultimateparent_map

Grain
    One row per NetSuite transaction line.f

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
        
Owner
    Dan Girard

==============================================================================*/
create or replace view finance_db.public.vw_ns_ss546 as
with unioned as
(
    select
        customercategory,
        to_date(date) as date,
        invoiceno,
        entitynohierarchy,
        name,
        itemid,
        sbitemcategoryid,
        item,
        salesdescription,
        description,
        sfdctype,
        to_number(quantity,10,0) as quantity,
        listrate,
        documentnumber,
        
        -- 01/20/2026 [Dan Girard] Removed pochecknumber
        '' pochecknumber,
        
        to_number(amount_usd,20,2) as amount_usd,
        to_number(amount,20,2) as amount,
        currency,
        to_number(amountforeigncurrency,20,2)as amountforeigncurrency,
        contractitemterm as contractitemterm,
        try_to_date(contractitemstartdate) as contractitemstartdate,
        try_to_date(contractitemenddate) as contractitemenddate,
        templatename,
        revrecterminmonths,
        try_to_date(revrecstartdate) as revrecstartdate,
        try_to_date(revrecenddate) as revrecenddate,
        terms,
        pricelevel,
        type,

        -- 05/05/2026 [Dan Girard] Added new type_calc to put values back to the original state
        case when type = 'creditmemo' then 'Credit Memo'
            when type = 'cashsale' then 'Cash Sale'
            when type = 'cashrefund' then 'Cash Refund'
            when type = 'customsale_reclass' then 'Reclass'
            when type = 'invoice' then 'Invoice'
            else type
            end type_calc,
        itemcategoryhidden,
        sbitemcategory1,
        internalid,
        lineid,
        vsoeallocation,
        vsoeamount,

        -- 01/20/2026 [Dan Girard] Removed createdfrom
        '' createdfrom,
        
        transexternalid,

        -- 01/20/2026 [Dan Girard] Removed externalid
        '' externalid,
        
        transactiondiscount,
        quantitytype,
        product,
        ordertype,
        ordertype1,
        duns,
        internalid1,
        customersite,
        -- 10/12/2023 [Dan Girard] Replaced GLOBALULTIMATEPARENT with new mapping logic
        coalesce(globalultimateparent_mapped, globalultimateparent) globalultimateparent,
        industrycategory,
        lineofbusiness,
        naics,

        -- 01/20/2026 [Dan Girard] Removed productline
        '' productline,
        
        sic,
        try_to_date(dateoffirstsale) as dateoffirstsale,
        averagerate,
    
        -- 04/14/2026 [Dan Girard] New override for Zephyr Advanced
        case when left(new_item_id_name,3) = 'ZA-' then 'Zephyr Advanced'
             when sisense_product_rollup = 'Zephyr Scale Automate' then 'Zephyr Advanced'
            else sisense_product_rollup
            end sisense_product_rollup_calc,
            
        order_type_classification,
        bill_country,
        bill_state,
        bill_city,
        ship_country,
        ship_state,
        ship_city,
        incomeaccountname,
        bill_region,
        ship_region,
        inline_discount,
        aws_mkt_private_offer,
        aws_mkt_cosell,
        a.ver_date,
    
        -- 6/21/2023 [Dan Girard] Added direct_ecomm_flag, product_for_reporting_ns, and product_for_reporting_group_ns
        --    product_for_reporting_ns and product_for_reporting_group_ns logic based on the MASTER_BILLING logic for
        --    product_for_reporting and product_group
        case 
            when sisense_product_rollup_calc in ('Capture','Cucumber','Squad','Zephyr Scale') then 'Ecomm'
    
            -- 8/17/2023 [Dan Girard] Added the SISENSE check for DIRECT and the 3 date based logic lines
            when sisense_product_rollup_calc in ('AlertSite','AQTime','Collaborator','Hiptest','LoadComplete','QAComplete','RAPI Performance','RAPI Test','RAPI Virtualization','TestComplete','TestEngine','Zephyr E') then 'Direct'
            
            when date <= '2022-06-30' and coalesce(transexternalid,'') = '' and sisense_product_rollup_calc ilike '%CBT%' then 'Direct'
            when date <= '2022-06-30' and sisense_product_rollup_calc ilike '%CBT%' then 'Ecomm'
            when date < '2022-01-01' and upper(sisense_product_rollup_calc) in ('LOADNINJA','PACTFLOW','BITBAR') and upper(name) like '%STRIPE%' then 'Ecomm'
            
            -- 07/03/2025 [Dan Girard] Updated for Swagger Ecomm Reclass
            when type_calc = 'Reclass' and coalesce(transexternalid,'') ilike '%braintree%' --and sisense_product_rollup_calc ilike '%Swagger%' 
                then 'Ecomm'
            
            -- 06/05/2025 [Dan Girard] Updated to match the CM version   
            -- 07/07/2025 [Dan Girard] Changed default for Reclass to DIRECT
            -- when type = 'Reclass' and coalesce(transexternalid,'') <> '' then 'Ecomm'
            when type_calc = 'Reclass' then 'Direct'
    
            when (
                customercategory in ('Reseller','End User') or 
                (customercategory = 'ecommerce') 
                    and 
                        (upper(name) like '%CLEVERBRIDGE%' or
                        upper(name) like '%AMAZON ONLINE ORDERS%')
                        
                ) then 'Direct'
                
            -- 02/27/2025 [Dan Girard] Added RECLASS
            when type_calc in ('Invoice','Credit Memo','Reclass') then 'Direct'
            
            else 'Ecomm'
            
            -- 07/08/2025 [Dan Girard] renamed from direct_ecomm_flag to direct_ecomm_base for override
            end direct_ecomm_base,
            
        -- 07/08/2025 [Dan Girard] new override field for DIRECT/ECOMM
        case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Removed BugSnag RUM from the forced Direct
            when direct_ecomm_base = 'Ecomm' and sisense_product_rollup_calc in ('LoadNinja', 'Pactflow', 'Portal', 'VisualTest','Contract Testing') then 'Direct'
            else direct_ecomm_base
            end direct_ecomm_flag,
        case 
            when sisense_product_rollup_calc = 'Cucumber' then 'Cucumber for Jira'
            when sisense_product_rollup_calc = 'Hiptest' then 'CucumberStudio'
            when sisense_product_rollup_calc = 'Squad' then 'Zephyr Squad'
            when sisense_product_rollup_calc = 'RAPI Test' then 'ReadyAPI Test'
            when sisense_product_rollup_calc = 'TestEngine' then 'ReadyAPI Test'
            when sisense_product_rollup_calc = 'RAPI Performance' then 'ReadyAPI Perf'
            when sisense_product_rollup_calc = 'RAPI Virtualization' then 'ReadyAPI Virt'
    
            -- 10/15/2025 [Dan Girard] Added for VisualTest
            when sisense_product_rollup_calc = 'TestServer' then 'TestComplete'
            when sisense_product_rollup_calc = 'VisualTest' then 'TestComplete'          
            
            when sisense_product_rollup_calc = 'Bitbar' then 'BitBar'
    
            -- 05/15/2025 [Dan Girard] Put API Hub to Swagger
            when sisense_product_rollup_calc = 'API Hub' then 'Swagger'
    
            -- 06/04/2025 [Dan Girard] Add logic for Test and Contract Testing
            -- 09/04/2025 [Dan Girard] Update logic for Test to be API Hub Test
            when sisense_product_rollup_calc = 'Test' and direct_ecomm_flag = 'Direct' then 'API Hub Test'
            when sisense_product_rollup_calc = 'Test' and direct_ecomm_flag = 'Ecomm' then 'Swagger'
            
            when sisense_product_rollup_calc = 'Contract Testing' then 'Pactflow'
    
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when sisense_product_rollup_calc = 'Bugsnag' then 'BugSnag'
    
            -- 12/15/2025 [Dan Girard] BugSnagRUM Ecomm should just be BugSnag
            when sisense_product_rollup_calc = 'Bugsnag RUM' and direct_ecomm_flag = 'Ecomm' then 'BugSnag'
            
            when sisense_product_rollup_calc = 'Bugsnag RUM' then 'BugSnag RUM'
    
            -- 10/15/2025 [Dan Girard] Added for Explore
            when sisense_product_rollup_calc = 'Explore' then 'Portal'
    
            -- 12/09/2025 [Dan Girard] Added for Zephyr Scale Automate
            when sisense_product_rollup_calc = 'Zephyr Scale Automate' then 'Zephyr Scale'
            
            else sisense_product_rollup_calc
            end product_for_reporting_ns,
        case 
            when product_for_reporting_ns ilike 'ReadyAPI%' then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Swagger%' then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Pactflow%' then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Stoplight%' then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Explore%' then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Portal%' then 'API Lifecycle'
    
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when product_for_reporting_ns ilike 'API Hub Test%' then 'API Lifecycle'
            
            when product_for_reporting_ns in ('CucumberStudio','QAComplete') then 'Test Management'
            when product_for_reporting_ns ilike 'Zephyr%' then 'Test Management'
            when product_for_reporting_ns ilike 'Reflect%' then 'Test Management'
            when product_for_reporting_ns ilike 'VisualTest%' then 'Test Management'
            when product_for_reporting_ns in ('TestComplete','LoadNinja','BitBar') then 'Functional Test'
            when product_for_reporting_ns ilike 'CBT%' then 'Functional Test'
    
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_for_reporting_ns ilike 'Bugsnag%' then 'BugSnag'
            when product_for_reporting_ns ilike 'Aspecto%' then 'BugSnag'
            
            when product_for_reporting_ns in ('AlertSite','AQTime','Capture','Collaborator','Cucumber for Jira','LoadComplete') then 'Other'
            else product_for_reporting_ns
            end product_for_reporting_group_ns,
        
        -- 8/28/2023 [Dan Girard] Added 2 new columns: product_for_reporting_ns_ALIAS and product_for_reporting_ns_ALIAS_COMBINED
        case 
            when direct_ecomm_flag = 'Ecomm' and product_for_reporting_ns = 'CBT' then 'Device Cloud'
            when direct_ecomm_flag = 'Ecomm' and upper(product_for_reporting_ns) = 'BITBAR' then 'Device Cloud'
            else product_for_reporting_ns
            end product_for_reporting_ns_ALIAS,
    
        -- 10/3/2023 [Dan Girard] changed name to product_for_reporting_ns_ALIAS_COMBINED
        -- 10/15/2023 [Dan Girard] Added logic for BugSnag RUM Ecomm
        -- 12/09/2025 [Dan Girard] Added logic for BugSnag RUM Direct to be just BugSnag RUM
        case when product_for_reporting_ns_alias = 'BugSnag RUM' and direct_ecomm_flag = 'Ecomm' then 'BugSnag Ecomm'
            when product_for_reporting_ns_alias = 'BugSnag RUM' and direct_ecomm_flag <> 'Ecomm' then 'BugSnag RUM'
            else concat(product_for_reporting_ns_alias,' ',direct_ecomm_flag) 
            end product_for_reporting_ns_alias_combined,
    
        -- 11/28/2023 [Dan Girard] Added 4 new columns: PRODUCT_NAME, CORE_NONCORE, DIRECT_INDIRECT, and PRODUCT_NAME_GROUP
        case 
            -- 10/01/2025 [Dan Girard] Moved BugSnag RUM Ecomm to BugSnag Ecomm
            when product_for_reporting_ns_alias_combined = 'BugSnag RUM Ecomm' then 'BugSnag Ecomm'
            
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_for_reporting_ns_alias in ('BugSnag','BugSnag RUM','Stoplight','Swagger','Reflect') then product_for_reporting_ns_alias_combined
            
            when product_for_reporting_ns_alias = 'CBT' and direct_ecomm_flag = 'Direct' then 'CBT Sales Assisted'
            else product_for_reporting_ns_alias
            end product_name,
        case
            when product_name in ('AlertSite','AQTime', 'Collaborator','Cucumber for Jira', 'CucumberStudio', 'LoadComplete', 'LoadNinja', 'QAComplete') then 'Non-Core'
            else 'Core'
            end core_noncore,
        case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Change from BugSnag RUM to BugSnag Ecomm
            when product_name in ('BugSnag Ecomm','Pactflow','VisualTest','LoadNinja') and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'
            when product_name in ('BugSnag Ecomm','Device Cloud','Stoplight Ecomm','Swagger Ecomm','Reflect Ecomm') then 'Indirect - Ecomm'
            
            when product_name in ('Capture','Cucumber for Jira','Zephyr Scale', 'Zephyr Squad') then 'Indirect - Atlassian'
    
            -- 07/07/2025 [Dan Girard] Update for Portal
            -- when product_name = 'Portal' and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'
            
            else 'Direct'
            end direct_indirect,
        case
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when product_name in ('Explore','Pactflow','Portal','ReadyAPI Perf','ReadyAPI Test','ReadyAPI Virt','Stoplight Direct','Stoplight Ecomm','Stoplight','Swagger Direct','Swagger Ecomm','API Hub Test') then 'API'
    
            -- 04/14/2026 [Dan Girard] Added Zephyr Advanced
            when product_name in ('Capture','Cucumber for Jira','Zephyr Scale','Zephyr Scale Automate','Zephyr Scale - Automate','Zephyr Squad','Zephyr Advanced') then 'Marketplace'
    
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_name ilike 'BugSnag%' then 'Observability'
            
            when product_name in ('AlertSite','AQTime','Collaborator','CucumberStudio','LoadComplete','QAComplete') then 'Other'
            when product_name in ('BitBar','CBT Sales Assisted','Device Cloud','LoadNinja','TestComplete','VisualTest','Zephyr E','Reflect Direct','Reflect Ecomm','Reflect') then 'Test'
            end product_name_group,
    
        -- 08/07/2025 [Dan Girard] Added salesperson
	-- 05/04/2026 [Dan Girard] Use new join table for salesperson
        concat(e.first_name,' ',e.last_name) salesperson,

        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        e.location salesperson_location,
            sfdc_deal_reg,
    
        -- 2024-09-10 [Dan Girard] Added Bill To and Ship To info
        bill_to_company,
    
        -- 01/20/2026 [Dan Girard] Removed bill_to_name
        -- 05/04/2026 [Dan Girard] Changed to bill_to
        bill_to bill_to_name,
        bill_to_address1,
        bill_to_address2,
        bill_to_address3,
        ship_to_company,
    
        -- 01/20/2026 [Dan Girard] Removed ship_to_name
        -- 05/04/2026 [Dan Girard] Changed to 
        ship_to ship_to_name,
        ship_to_address1,
        ship_to_address2,
        ship_to_address3,
    
        -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
        stripe_user_id,
        braintree_user_id,
    
        -- 04/14/2026 [Dan Girard] Added 2 new columns for Zephyr Advanced historical override
        new_item_id,
        new_item_id_name,

        -- 06/23/2026 [Dan Girard] Added transaction_id (netsuite_id) and boomi_external_id
        transaction_id,
        boomi_external_id,
        
    from 
        -- 04/23/2026 [Dan Girard] Use new INGEST staging table
        finance_db.ingest.ns_ss546_cm_pm_stg a
        left join finance_db.public.dim_globalultimateparent_map b on upper(a.globalultimateparent) = upper(b.globalultimateparent_orig)

        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        -- 05/05/2026 [Dan Girard] Change to use the max date from the employee table
        left join finance_db.ingest.employee_stg_tbl e on a.salesperson = e.employee_id and to_date(e.ver_date) = (select max(ver_date) from finance_db.ingest.employee_stg_tbl) --current_date()
    where 
        a.ver_date = (select max(ver_date) from finance_db.ingest.ns_ss546_cm_pm_stg) --revmoed to_date from ver_date to get the latest file
    
    union all
    
    select
        customercategory,
        to_date(date) as date,
        invoiceno,
        entitynohierarchy,
        name,
        itemid,
        sbitemcategoryid,
        item,
        salesdescription,
        description,
        sfdctype,
        to_number(quantity,10,0) as quantity,
        listrate,
        documentnumber,

        -- 01/20/2026 [Dan Girard] Removed pochecknumber
        '' pochecknumber,
        
        to_number(amount_usd,20,2) as amount_usd,
        to_number(amount,20,2) as amount,
        currency,
        to_number(amountforeigncurrency,20,2)as amountforeigncurrency,
        contractitemterm as contractitemterm,
        try_to_date(contractitemstartdate) as contractitemstartdate,
        try_to_date(contractitemenddate) as contractitemenddate,
        templatename,
        revrecterminmonths,
        try_to_date(revrecstartdate) as revrecstartdate,
        try_to_date(revrecenddate) as revrecenddate,
        terms,
        pricelevel,
        type,

        -- 05/05/2026 [Dan Girard] Added new type_calc to put values back to the original state
        case when type = 'creditmemo' then 'Credit Memo'
            when type = 'cashsale' then 'Cash Sale'
            when type = 'cashrefund' then 'Cash Refund'
            when type = 'customsale_reclass' then 'Reclass'
            when type = 'invoice' then 'Invoice'
            else type
            end type_calc,
        itemcategoryhidden,
        sbitemcategory1,
        internalid,
        lineid,
        vsoeallocation,
        vsoeamount,

        -- 01/20/2026 [Dan Girard] Removed createdfrom
        '' createdfrom,
        
        transexternalid,

        -- 01/20/2026 [Dan Girard] Removed externalid
        '' externalid,
        
        transactiondiscount,
        quantitytype,
        product,
        ordertype,
        ordertype1,
        duns,
        internalid1,
        customersite,
        -- 10/12/2023 [Dan Girard] Replaced GLOBALULTIMATEPARENT with new mapping logic
        coalesce(globalultimateparent_mapped, globalultimateparent) globalultimateparent,
        industrycategory,
        lineofbusiness,
        naics,

        -- 01/20/2026 [Dan Girard] Removed productline
        '' productline,
        
        sic,
        try_to_date(dateoffirstsale) as dateoffirstsale,
        averagerate,
    
        -- 04/14/2026 [Dan Girard] New override for Zephyr Advanced
        case when left(new_item_id_name,3) = 'ZA-' then 'Zephyr Advanced'
             when sisense_product_rollup = 'Zephyr Scale Automate' then 'Zephyr Advanced'
            else sisense_product_rollup
            end sisense_product_rollup_calc,
        
        order_type_classification,
        bill_country,
        bill_state,
        bill_city,
        ship_country,
        ship_state,
        ship_city,
        incomeaccountname,
        bill_region,
        ship_region,
        inline_discount,
        aws_mkt_private_offer,
        aws_mkt_cosell,
        a.ver_date,
        -- 6/21/2023 [Dan Girard] Added direct_ecomm_flag, product_for_reporting_ns, and product_for_reporting_group_ns
        -- product_for_reporting_ns and product_for_reporting_group_ns logic based on the MASTER_BILLING logic for
        -- product_for_reporting and product_group
        case 
            when sisense_product_rollup_calc in ('Capture','Cucumber','Squad','Zephyr Scale') then 'Ecomm'
    
            -- 8/17/2023 [Dan Girard] Added the SISENSE check for DIRECT and the 3 date based logic lines
            when sisense_product_rollup_calc in ('AlertSite','AQTime','Collaborator','Hiptest','LoadComplete','QAComplete','RAPI Performance','RAPI Test','RAPI Virtualization','TestComplete','TestEngine','Zephyr E') then 'Direct'
            
            when date <= '2022-06-30' and coalesce(transexternalid,'') = '' and sisense_product_rollup_calc ilike '%CBT%' then 'Direct'
            when date <= '2022-06-30' and sisense_product_rollup_calc ilike '%CBT%' then 'Ecomm'
            when date < '2022-01-01' and upper(sisense_product_rollup_calc) in ('LOADNINJA','PACTFLOW','BITBAR') and upper(name) like '%STRIPE%' then 'Ecomm'
            
            -- 07/03/2025 [Dan Girard] Updated for Swagger Ecomm Reclass
            when type_calc = 'Reclass' and coalesce(transexternalid,'') ilike '%braintree%' --and sisense_product_rollup_calc ilike '%Swagger%' 
                then 'Ecomm'
            
            -- 06/05/2025 [Dan Girard] Updated to match the CM version   
            -- 07/07/2025 [Dan Girard] Changed default for Reclass to DIRECT
            -- when type = 'Reclass' and coalesce(transexternalid,'') <> '' then 'Ecomm'
            when type_calc = 'Reclass' then 'Direct'
    
            when (
                customercategory in ('Reseller','End User') or 
                (customercategory = 'ecommerce') 
                    and 
                        (upper(name) like '%CLEVERBRIDGE%' or
                        upper(name) like '%AMAZON ONLINE ORDERS%')
                        
                ) then 'Direct'
                
            -- 02/27/2025 [Dan Girard] Added RECLASS
            when type_calc in ('Invoice','Credit Memo','Reclass') then 'Direct'
            
            else 'Ecomm'
            
            -- 07/08/2025 [Dan Girard] renamed from direct_ecomm_flag to direct_ecomm_base for override
            end direct_ecomm_base,
            
        -- 07/08/2025 [Dan Girard] new override field for DIRECT/ECOMM
        case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Removed BugSnag RUM from the forced Direct
            when direct_ecomm_base = 'Ecomm' and sisense_product_rollup_calc in ('LoadNinja', 'Pactflow', 'Portal', 'VisualTest','Contract Testing') then 'Direct'
            else direct_ecomm_base
            end direct_ecomm_flag,
            
        case 
                when sisense_product_rollup_calc = 'Cucumber' then 'Cucumber for Jira'
                when sisense_product_rollup_calc = 'Hiptest' then 'CucumberStudio'
                when sisense_product_rollup_calc = 'Squad' then 'Zephyr Squad'
                when sisense_product_rollup_calc = 'RAPI Test' then 'ReadyAPI Test'
                when sisense_product_rollup_calc = 'TestEngine' then 'ReadyAPI Test'
                when sisense_product_rollup_calc = 'RAPI Performance' then 'ReadyAPI Perf'
                when sisense_product_rollup_calc = 'RAPI Virtualization' then 'ReadyAPI Virt'
    
                -- 10/15/2025 [Dan Girard] Added for VisualTest
                when sisense_product_rollup_calc = 'VisualTest' then 'TestComplete'
                when sisense_product_rollup_calc = 'TestServer' then 'TestComplete'
                when sisense_product_rollup_calc = 'Bitbar' then 'BitBar'
    
                -- 05/15/2025 [Dan Girard] Put API Hub to Swagger
                when sisense_product_rollup_calc = 'API Hub' then 'Swagger'
    
                -- 06/04/2025 [Dan Girard] Add logic for Test and Contract Testing
                -- 09/04/2025 [Dan Girard] Update logic for Test to be API Hub Test
                when sisense_product_rollup_calc = 'Test' and direct_ecomm_flag = 'Direct' then 'API Hub Test'
                when sisense_product_rollup_calc = 'Test' and direct_ecomm_flag = 'Ecomm' then 'Swagger'
                
                when sisense_product_rollup_calc = 'Contract Testing' then 'Pactflow'
    
                -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
                when sisense_product_rollup_calc = 'Bugsnag' then 'BugSnag'
    
                -- 12/15/2025 [Dan Girard] BugSnagRUM Ecomm should just be BugSnag
                when sisense_product_rollup_calc = 'Bugsnag RUM' and direct_ecomm_flag = 'Ecomm' then 'BugSnag'
                
                when sisense_product_rollup_calc = 'Bugsnag RUM' then 'BugSnag RUM'
    
                -- 10/15/2025 [Dan Girard] Added for Explore
                when sisense_product_rollup_calc = 'Explore' then 'Portal'
                
                -- 12/09/2025 [Dan Girard] Added for Zephyr Scale Automate
                when sisense_product_rollup_calc = 'Zephyr Scale Automate' then 'Zephyr Scale'
                
                else sisense_product_rollup_calc
                end product_for_reporting_ns,
        case 
                when product_for_reporting_ns ilike 'ReadyAPI%' then 'API Lifecycle'
                when product_for_reporting_ns ilike 'Swagger%' then 'API Lifecycle'
                when product_for_reporting_ns ilike 'Pactflow%' then 'API Lifecycle'
                when product_for_reporting_ns ilike 'Stoplight%' then 'API Lifecycle'
                when product_for_reporting_ns ilike 'Explore%' then 'API Lifecycle'
                when product_for_reporting_ns ilike 'Portal%' then 'API Lifecycle'
    
                -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
                when product_for_reporting_ns ilike 'API Hub Test%' then 'API Lifecycle'
                
                when product_for_reporting_ns in ('CucumberStudio','QAComplete') then 'Test Management'
                when product_for_reporting_ns ilike 'Zephyr%' then 'Test Management'
                when product_for_reporting_ns ilike 'Reflect%' then 'Test Management'
                when product_for_reporting_ns ilike 'VisualTest%' then 'Test Management'       
                when product_for_reporting_ns in ('TestComplete','LoadNinja','BitBar') then 'Functional Test'
                when product_for_reporting_ns ilike 'CBT%' then 'Functional Test'
    
                -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
                when product_for_reporting_ns ilike 'Bugsnag%' then 'BugSnag'
                when product_for_reporting_ns ilike 'Aspecto%' then 'BugSnag' 
                
                -- 12/09/2025 [Dan Girard] Added for Zephyr Scale Automate
                when sisense_product_rollup_calc = 'Zephyr Scale Automate' then 'Zephyr Advanced'
                
                when product_for_reporting_ns in ('AlertSite','AQTime','Capture','Collaborator','Cucumber for Jira','LoadComplete') then 'Other'
                else product_for_reporting_ns
                end product_for_reporting_group_ns,
        -- 8/28/2023 [Dan Girard] Added 2 new columns: product_for_reporting_ns_ALIAS and product_for_reporting_ns_ALIAS_COMBINED
        case when direct_ecomm_flag = 'Ecomm' and product_for_reporting_ns = 'CBT' then 'Device Cloud'
                when direct_ecomm_flag = 'Ecomm' and upper(product_for_reporting_ns) = 'BITBAR' then 'Device Cloud'
                else product_for_reporting_ns
                end product_for_reporting_ns_ALIAS,
    
        -- 10/3/2023 [Dan Girard] Changed name to product_for_reporting_ns_ALIAS_COMBINED
        -- 10/15/2023 [Dan Girard] Added logic for BugSnag RUM Ecomm
        -- 12/09/2025 [Dan Girard] Added logic for BugSnag RUM Direct to be just BugSnag RUM
        case when product_for_reporting_ns_alias = 'BugSnag RUM' and direct_ecomm_flag = 'Ecomm' then 'BugSnag Ecomm'
            when product_for_reporting_ns_alias = 'BugSnag RUM' and direct_ecomm_flag <> 'Ecomm' then 'BugSnag RUM'
            else concat(product_for_reporting_ns_alias,' ',direct_ecomm_flag) 
            end product_for_reporting_ns_alias_combined,
    
        -- 11/28/2023 [Dan Girard] Added 4 new columns: PRODUCT_NAME, CORE_NONCORE, DIRECT_INDIRECT, and PRODUCT_NAME_GROUP    
        case 
            -- 10/01/2025 [Dan Girard] Moved BugSnag RUM Ecomm to BugSnag Ecomm
            when product_for_reporting_ns_alias_combined = 'BugSnag RUM Ecomm' then 'BugSnag Ecomm'
            
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_for_reporting_ns_alias in ('BugSnag','BugSnag RUM','Stoplight','Swagger','Reflect') then product_for_reporting_ns_alias_combined
            
            when product_for_reporting_ns_alias = 'CBT' and direct_ecomm_flag = 'Direct' then 'CBT Sales Assisted'
            else product_for_reporting_ns_alias
            end product_name,
        case
            when product_name in ('AlertSite','AQTime', 'Collaborator','Cucumber for Jira', 'CucumberStudio', 'LoadComplete', 'LoadNinja', 'QAComplete') then 'Non-Core'
            else 'Core'
            end core_noncore,
        case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Change from BugSnag RUM to BugSnag Ecomm
            when product_name in ('BugSnag Ecomm','Pactflow','VisualTest','LoadNinja') and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'
            when product_name in ('BugSnag Ecomm','Device Cloud','Stoplight Ecomm','Swagger Ecomm','Reflect Ecomm') then 'Indirect - Ecomm'
            
            when product_name in ('Capture','Cucumber for Jira','Zephyr Scale', 'Zephyr Squad') then 'Indirect - Atlassian'
            
            -- 07/07/2025 [Dan Girard] Update for Portal
            -- when product_name = 'Portal' and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'
            
            else 'Direct'
            end direct_indirect,
        case
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when product_name in ('Explore','Pactflow','Portal','ReadyAPI Perf','ReadyAPI Test','ReadyAPI Virt','Stoplight Direct','Stoplight Ecomm','Stoplight','Swagger Direct','Swagger Ecomm','API Hub Test') then 'API'
    
            -- 04/14/2026 [Dan Girard] Added Zephyr Advanced
            when product_name in ('Capture','Cucumber for Jira','Zephyr Scale','Zephyr Scale Automate','Zephyr Scale - Automate','Zephyr Squad','Zephyr Advanced') then 'Marketplace'
            
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_name ilike 'BugSnag%' then 'Observability'
            
            when product_name in ('AlertSite','AQTime','Collaborator','CucumberStudio','LoadComplete','QAComplete') then 'Other'
            when product_name in ('BitBar','CBT Sales Assisted','Device Cloud','LoadNinja','TestComplete','VisualTest','Zephyr E','Reflect Direct','Reflect Ecomm','Reflect') then 'Test'
            end product_name_group,
    
        -- 08/07/2025 [Dan Girard] Added salesperson
        -- 05/04/2026 [Dan Girard] Use new join table for salesperson
        concat(e.first_name,' ',e.last_name) salesperson,

        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        e.location salesperson_location,
        sfdc_deal_reg,
    
        -- 2024-09-10 [Dan Girard] Added Bill To and Ship To info
        bill_to_company,
        
        -- 01/20/2026 [Dan Girard] Removed bill_to_name
        -- 05/04/2026 [Dan Girard] Changed to bill_to
        bill_to bill_to_name,
        bill_to_address1,
        bill_to_address2,
        bill_to_address3,
        ship_to_company,
        
        -- 01/20/2026 [Dan Girard] Removed ship_to_name
        -- 05/04/2026 [Dan Girard] Changed to ship_to
        ship_to ship_to_name,
        ship_to_address1,
        ship_to_address2,
        ship_to_address3,
    
        -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
        stripe_user_id,
        braintree_user_id,
        -- 04/14/2026 [Dan Girard] Added 2 new columns for Zephyr Advanced historical override
        new_item_id,
        new_item_id_name,
        
        -- 06/23/2026 [Dan Girard] Added transaction_id (netsuite_id) and boomi_external_id
        transaction_id,
        boomi_external_id,
        
    from 
        -- 04/23/2026 [Dan Girard] Use new INGEST staging table
        finance_db.ingest.ns_ss546_stat_stg a
        -- 10/12/2023 [Dan Girard] Added left join to Global Ultimate Parent Map table
        left join finance_db.public.dim_globalultimateparent_map b on upper(a.globalultimateparent) = upper(b.globalultimateparent_orig)

        -- 05/04/2026 [Dan Girard] Use new join table for salesperson location
        -- 05/05/2026 [Dan Girard] Change to use the max date from the employee table
        left join finance_db.ingest.employee_stg_tbl e on a.salesperson = e.employee_id and to_date(e.ver_date) = (select max(ver_date) from finance_db.ingest.employee_stg_tbl)
    where 
        to_date(a.ver_date) = (select max(to_date(ver_date)) from finance_db.ingest.ns_ss546_stat_stg)
)
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
    -- 05/05/2026 [Dan Girard] Added new type_calc to put values back to the original state
    u.type_calc type,
    u.itemcategoryhidden,
    u.sbitemcategory1,
    u.internalid,
    u.lineid,
    u.vsoeallocation,
    u.vsoeamount,
    u.createdfrom,
    u.transexternalid,
    u.transactiondiscount,
    u.quantitytype,
    u.product,
    u.ordertype,
    u.ordertype1,
    u.duns,
    u.internalid1,
    u.customersite,
    u.globalultimateparent,
    u.industrycategory,
    u.lineofbusiness,
    u.naics,
    u.sic,
    u.dateoffirstsale,
    u.averagerate,
    u.sisense_product_rollup_calc sisense_product_rollup,
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
    u.direct_ecomm_base,
    u.direct_ecomm_flag,
    u.product_for_reporting_ns,
    u.product_for_reporting_group_ns,
    u.product_for_reporting_ns_alias,
    u.product_for_reporting_ns_alias_combined,
    u.product_name,
    u.core_noncore,
    
    -- u.direct_indirect,
    p.direct_indirect,
    
    u.product_name_group,
    u.salesperson,
    u.salesperson_location,
    u.sfdc_deal_reg,
    u.bill_to_name,
    u.bill_to_company,
    u.bill_to_address1,
    u.bill_to_address2,
    u.bill_to_address3,
    u.ship_to_name,
    u.ship_to_company,
    u.ship_to_address1,
    u.ship_to_address2,
    u.ship_to_address3,
    u.stripe_user_id,
    u.braintree_user_id,
    u.new_item_id,
    u.new_item_id_name,
    u.pochecknumber,
    u.externalid,
    u.productline,
from 
    unioned u
    left join finance_db.public.dim_product_dm_hierarchy_tbl p on upper(concat(u.sisense_product_rollup_calc,'_',u.direct_ecomm_flag)) = p.lookup_map_upper
;