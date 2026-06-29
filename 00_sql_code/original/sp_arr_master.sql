create or replace procedure finance_db.dev_netsuite.sp_arr_master()
    returns varchar
    language sql
    execute as owner
as
$$
begin

    create or replace table finance_db.dev_netsuite.arr_master copy grants as
    with 
    
    -- 06/25/2025 [Dan Girard] Pull product data to get PBT Group
    prod_map as
    (
        select distinct productgroup productgroupmap, pbt_group
        from finance_db.public.dim_product_dm_hierarchy_tbl
    
        -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
        union all select 'API Hub' productgroupmap, 'Swagger' pbt_group
        union all select 'Hiptest' productgroupmap, 'Other' pbt_group
    )
    ,main as
    (

        select
            'NS' as datasource,
            concat(internalid, concat_ws('-',lineid)) as key,
            ns.invoiceno,
            ns.amount_usd,
            case
                when upper(sisense_product_rollup) = 'BUGSNAG' and (ns.transexternalid is not null or ns.transexternalid <> '') then div0(amount_usd,datediff(day,ns.contractitemenddate,ns.contractitemstartdate)) * 365
                when upper(sisense_product_rollup) = 'ALERTSITE' and  datediff(day,ns.contractitemstartdate,ns.contractitemenddate) + 1 < 364 then ns.amount_usd
                when upper(sisense_product_rollup) = 'ALERTSITE' and  datediff(day,ns.contractitemstartdate,ns.contractitemenddate) + 1 >= 365 then div0(amount_usd,datediff(day,ns.contractitemstartdate,ns.contractitemenddate) + 1) * 365
                when upper(sisense_product_rollup) <> 'ALERTSITE' And datediff(day,ns.contractitemstartdate,ns.contractitemenddate) + 1 < 365  then ns.amount_usd
                else div0((amount_usd), (datediff(day,ns.contractitemstartdate,ns.contractitemenddate) +1)) * 365
                end as acv_billings,
                
            case
                -- 08/08/2024 [Dan Girard] - Added new logic for ecomm on or after 8/1/2024 for certain products to use the + 1 with the contract length
                when ns.date >= '2024-08-01' and ns.customercategory = 'ecommerce' and lower(ns.sisense_product_rollup) in ('stoplight','bitbar','loadninja','pactflow','swagger') 
                    then div0((amount_usd), (datediff(day,ns.contractitemstartdate,ns.contractitemenddate) + 1)) * 365
                when ns.sisense_product_rollup = 'AlertSite' and datediff(day,ns.contractitemstartdate,ns.contractitemenddate) + 1 < 365 then amount_usd
                when customercategory = 'ecommerce' and upper(name) not like '%CLEVERBRIDGE%' then div0(amount_usd,datediff(day,ns.contractitemstartdate,ns.contractitemenddate)) * 365
                else div0((amount_usd), (datediff(day,ns.contractitemstartdate,ns.contractitemenddate) +1)) * 365 end as acv,
                
            ns.contractitemenddate,
            ns.contractitemstartdate,
            try_to_number(ns.contractitemterm) contractitemterm,

            -- 01/14/2026 [Dan Girard] Removed createdfrom since it's no longer available
            -- ns.createdfrom,
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
            trim(upper(coalesce(ns.globalultimateparent,'BLANK'))) as globalultimateparentupper,
            case ns.itemcategoryhidden
                when 'License - Perpetual' then 'Perpetual'
                when 'License - Term' then 'Subscription'
                when 'Maintenance - Renewal' then 'Maintenance'
                when 'Other' then 'Subscription'
                when 'Services' then 'PS'
                when 'Support - New' then 'Maintenance'
                when 'Training' then 'PS'
                when 'Support - Renewal' then 'Maintenance' 
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
            case when ns.ordertype1 = 'Renewal' then ordertype1 when ns.ordertype1 in ('New','Existing') then 'License' end as ordertype1,

            -- 01/14/2026 [Dan Girard] Removed pochecknumber since it's no longer available
            -- ns.pochecknumber,
            ns.pricelevel,
            ns.product,

            -- 01/14/2026 [Dan Girard] Removed productline since it's no longer available
            -- ns.productline,
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
            case
                when upper(ns.sisense_product_rollup) = 'RAPI TEST' then 'ReadyAPI Test'
                when upper(ns.sisense_product_rollup) = 'RAPI PERFORMANCE' then 'ReadyAPI Performance'
                when upper(ns.sisense_product_rollup) = 'RAPI VIRTUALIZATION' then 'ReadyAPI Virtualization'
                when upper(ns.sisense_product_rollup) = 'SQUAD' then 'Zephyr Squad'
            
                -- 06/04/2025 [Dan Girard] Add logic for Test and Contract Testing
                -- 09/04/2025 [Dan Girard] Update logic for Test to be API Hub Test
                -- 12/04/2025 [Dan Girard] Update logic for Test to be Swagger and API Hub to Swagger
                -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
                -- 05/28/2026 [Dan Girard] Update for Test/API Hub & Direct = API Hub Test, and Test/API Hub & Ecomm = 'Swagger'
                when upper(ns.sisense_product_rollup) in ('TEST','API HUB') and ns.direct_ecomm_flag = 'Direct' then 'API Hub Test' --'Swagger'
                when upper(ns.sisense_product_rollup) in ('TEST','API HUB') and ns.direct_ecomm_flag = 'Ecomm' then 'Swagger'
                -- when upper(ns.sisense_product_rollup) = 'API HUB' then 'Swagger'
                
                when upper(ns.sisense_product_rollup) = 'CONTRACT TESTING' then 'Pactflow'
    
                -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
                when upper(ns.sisense_product_rollup) = 'BUGSNAG' then 'BugSnag'

                -- 12/15/2025 [Dan Girard] BugSnagRUM Ecomm should just be BugSnag
                when upper(ns.sisense_product_rollup) = 'BUGSNAG RUM' and direct_ecomm_flag = 'Ecomm' then 'BugSnag'
                
                when upper(ns.sisense_product_rollup) = 'BUGSNAG RUM' then 'BugSnag RUM'
    
                -- 10/15/2025 [Dan Girard] Added Explore and VisualTest
                when upper(ns.sisense_product_rollup) = 'EXPLORE' then 'Portal'
                when upper(ns.sisense_product_rollup) = 'VISUALTEST' then 'TestComplete'

                -- 12/09/2025 [Dan Girard] Update for Zephyr Scale Automate
                -- 04/15/2026 [Dan Girard] Change from Scale to Advanced
                when upper(ns.sisense_product_rollup) = 'ZEPHYR SCALE AUTOMATE' then 'Zephyr Advanced'
    
                else ns.sisense_product_rollup   
                end as productgroup,
            datediff('day',ns.contractitemstartdate,ns.contractitemenddate) + 1 as length_days,
            /*getyear(adddays(ns.ContractItemStartDate,-1))*4+getquarter(adddays(ns.ContractItemStartDate,-1)) - 1 as ContractQuarter,
            getyear(adddays(ns.ContractItemStartDate,-1))*12+getMonth(adddays(ns.ContractItemStartDate,-1)) - 1 as ContractMonth,
            getyear(ns.ContractItemEndDate)*4+getquarter(ns.ContractItemEndDate) - 1 as ContractEndQuarter,
            getyear(ns.ContractItemEndDate)*12+getMonth(ns.ContractItemEndDate) - 1 as ContractEndMonth,
            getyear(ns.Date)*4+getquarter(ns.Date) - 1 AS TransactionQuarter,*/
            0 as plan_amt,
            '0' as flag_plan,
            'Y' as flag_proforma,
            'N/A' as source, --logic lives on dim_datecontracts
            ns.itemcategoryhidden,
        
            -- 2/14/2023 [Dan Girard] Add region and NAICS Sector
            ns.ship_region as region,
            concat(d.naics_sector_code,' - ',d.naics_sector) as naics_sector,
        
            -- 3/6/2023 [Dan Girard] Add ship country
            -- NS.ship_country AS COUNTRY
        
            -- 6/28/2023 [Dan Girard] Added 3 new columns
            -- NS.DIRECT_ECOMM_FLAG,
            -- NS.PRODUCT_FOR_REPORTING_NS,
            -- NS.PRODUCT_FOR_REPORTING_GROUP_NS,
    
            -- 11/14/2024 [Dan Girard] Added stream_revenue
        case
              when incomeaccountname ilike '%License Revenue%' then 'Perpetual License'
              when incomeaccountname ilike '%SaaS%' then 'SaaS'
              when incomeaccountname ilike '%Training%' then 'Professional Services'
              when incomeaccountname ilike '%Professional Services%' then 'Professional Services'
              when incomeaccountname in ('Other - Test','Other Travel') then 'Professional Services'
              when incomeaccountname ilike '%Subscription Revenue%' then 'Subscription License'
              when incomeaccountname ilike '%MAintENANCE REV RENEW : SUB MNT REV RENEW%' then 'Subscription Maintenance'
              when incomeaccountname ilike '%MAintENANCE REV Y1%' then 'Subscription Maintenance'
              when incomeaccountname ilike '%Maintenance  Revenue Renewal%' then 'Perpetual Maintenance'
              when incomeaccountname ilike '%Maintenance Revenue Renewal%' then 'Perpetual Maintenance'
              when incomeaccountname in ('Maintenance  Revenue YR 1 - API'
                                        ,'Maintenance  Revenue YR 1 - Dev'
                                        ,'Maintenance  Revenue YR 1 - Test'
                                        ,'Maintenance  Revenue YR 1 - UXM'
                                        ,'Maintenance  Revenue YR 1 - Zephyr'
                                        ,'Maintenance  Revenue YR 1 - Other') then 'Perpetual Maintenance'
              when incomeaccountname in ('Maintenance Revenue YR 1 - API'
                                        ,'Maintenance Revenue YR 1 - Dev'
                                        ,'Maintenance Revenue YR 1 - Test'
                                        ,'Maintenance Revenue YR 1 - UXM'
                                        ,'Maintenance Revenue YR 1 - Zephyr'
                                        ,'Maintenance Revenue YR 1 - Other') then 'Perpetual Maintenance'
              else 'Undefined'
              end stream_revenue,
        from
            finance_db.public.vw_ns_ss546 ns
            left join finance_db.public.vw_naics_mapping d on ns.naics = to_char(d.naics_code)  -- 2/14/2023 [Dan Girard] Added join to new NAICS mapping table for the NAICS sector
        
        where 
            upper(itemcategoryhidden) not in ('SERVICES','LICENSE - PERPETUAL','TRAINING') --CC 1/3/2020: TRAINING ADDED
            and upper(ns.sbitemcategory1) not in ('SERVICES')
            and not(upper(ns.sisense_product_rollup) in ('SQUAD','CAPTURE') and date < '2018-10-1')
            and not (upper(ns.sisense_product_rollup) = 'ZEPHYR SCALE' /*AND ns.[GlobalUltimateParent] IS NULL*/ AND DATE < '2020-05-17')
            and not (upper(ns.sisense_product_rollup) = 'BUGSNAG' and ns.date <  '2021-05-14') --cut off date for flat file
    
            -- 4/4/2024 [Dan Girard] Added filter for Reflect NS data before 3/1/2024
            and not (upper(ns.sisense_product_rollup) = 'REFLECT' and ns.date < '2024-03-01')
    
            -- 09/29/2024 [Dan Girard] Filter out special SKU uploads
            -- 07/23/2024 [Dan Girard] Filter out the QTM special SKU uploads
            and ns.item not in ('SLS-INT-EC','QTM-INT-SBR', 'QTM-INT-SBN', 'QTM4J-INT-EC')
            
        union all
    
        -- 7/11/2024 [Dan Girard] Moved all proforma logic to new table
        select 
            datasource
            , key
            , invoiceno
            , vendoramount
            , acv_billings
            , acv
            , maintenanceenddate
            , maintenancestartdate
            , contractitemterm

            -- 01/14/2026 [Dan Girard] Removed createdfrom since it's no longer available
            -- , createdfrom
            , currency
            , customercategory
            , customersite
            , date
            , dateoffirstsale
            , documentnumber
            , duns
            , entitynohierarchy
            , externalid
            , globalultimateparent
            , globalultimateparentupper
            , itemtype
            , sbitemcategory
            , itemid
            , lineid
            , lineofbusiness
            , listrate
            , naics
            , name
            , ordertype
            , ordertype1

            -- 01/14/2026 [Dan Girard] Removed pochecknumber since it's no longer available
            -- , pochecknumber
            , pricelevel
            , product

            -- 01/14/2026 [Dan Girard] Removed productline since it's no longer available
            -- , productline
            , quantity
            , quantitytype
            , sfdctype
            , sic
            , templatename
            , terms
            , transactiondiscount
            , type
            , vsoeallocation
            , vsoeamount
            , productgroup
            , contractdays
            , plan_amt
            , flag_plan
            , flag_proforma
            , source
            , itemcategoryhidden
            , region
            , naics_sector
    
            -- 11/14/2024 [Dan Girard] Added stream_revenue
            , null stream_revenue
        from
            finance_db.public.arr_master_proforma a
            -- left join finance_db.public.dim_product_dm_hierarchy_tbl p on upper(concat(a.productgroup,'_',direct_ecomm_flag)) = p.lookup_map_upper    
    )

    -- 7/11/2024 [Dan Girard] Added logic to pull invoices and Core/Enterprise logic from Salesforce
    ,sfdc_inv_list_full as
    (
        select distinct 
            replace(replace(invoice_num__c, ' ', '/'),'///','/') inv_list  -- To pull apart multiple invoice #s in a single value.
            , closedate sfdc_closedate
            , opp_id_18 sfdc_opp_id_18
            , account_id sfdc_account_id
            , case when salesopsdummy__c is null then 'Core'
                else 'Enterprise'
                end sfdc_ent_core_flag

            -- 05/29/2026 [Dan Girard] Added SFDC Name
            -- 06/24/2026 [Dan Girard] Changed from name to account_name
            , account_name sfdc_name
        from 
            sfdc_db.public.sfdc_opps_tbl
        where 
            invoice_num__c is not null
            and invoice_num__c not ilike '%authorize.net%'
            and invoice_num__c not ilike '%bugsnag%'
            and invoice_num__c not ilike '%pending%'
            and invoice_num__c not ilike '%incorrect%'
            and invoice_num__c not ilike '%cancel%'
            and invoice_num__c not ilike '%renew%'
            and invoice_num__c not ilike '%decline%'
            and invoice_num__c not ilike '%complete%'
    )
    -- 02/07/2024 [Dan Girard] Added SFDC CTE - use the LATERAL to make a unique list of invoices with the close dates
    ,sfdc_data_1 as
    (
        select 
            value as invoice_no
            , sfdc_closedate
            , sfdc_ent_core_flag

            -- 05/29/2026 [Dan Girard] Added SFDC Name
            , sfdc_name
        from sfdc_inv_list_full, lateral split_to_table(inv_list, '/')
        where len(value) > 5  -- filter out garbage invoices
    ),sfdc_data_2 as
    (
        select invoice_no
        from sfdc_data_1
        group by 1
        having count(invoice_no) = 1
    )
    ,sfdc_data as
    (
        select 
            a.invoice_no
            , a.sfdc_closedate
            , coalesce(a.sfdc_ent_core_flag,'Core') sfdc_ent_core_flag

            -- 05/29/2026 [Dan Girard] Added SFDC Name
            , a.sfdc_name
        from sfdc_data_1 a
            inner join sfdc_data_2 b on a.invoice_no = b.invoice_no
    )
    /* 10/12/2023 [Dan Girard] Created the "main" CTE and moved the combined the select logic
                    below. Also, added the left join to the GlobalUltimateParentMap table to
                    overrider any names comning from the proforma data (the NetSuite data is
                    already overridden by the vw_ns_ss546 logic)
    */
    select
        datasource
        , key
        , invoiceno
        , amount_usd
        , acv_billings
        , acv
        , contractitemenddate
        , contractitemstartdate
        , contractitemterm

        -- 01/14/2026 [Dan Girard] Removed createdfrom since it's no longer available
        -- , createdfrom
        , currency
        , customercategory
        , customersite
        , date
        , dateoffirstsale
        , documentnumber
        , duns
        , entitynohierarchy
        , transexternalid
        , coalesce(b.globalultimateparent_mapped, a.globalultimateparent) globalultimateparent
        , upper(coalesce(b.globalultimateparent_mapped, a.globalultimateparent)) globalultimateparentupper
        , itemtype
        , sbitemcategory1
        , itemid
        , lineid
        , lineofbusiness
        , listrate
        , naics
        , name
        , ordertype
        , ordertype1

        -- 01/14/2026 [Dan Girard] Removed pochecknumber since it's no longer available
        -- , pochecknumber
        , pricelevel
        , product

        -- 01/14/2026 [Dan Girard] Removed productline since it's no longer available
        -- , productline
        , quantity
        , quantitytype
        , sfdctype
        , sic
        , templatename
        , terms
        , transactiondiscount
        , type
        , vsoeallocation
        , vsoeamount
        , productgroup
        , length_days
        , plan_amt
        , flag_plan
        , flag_proforma
        , source
        , itemcategoryhidden
        , region
        , naics_sector
    
        -- 11/28/2023 [Dan Girard] Added 4 new columns: PRODUCT_NAME, CORE_NONCORE, DIRECT_INDIRECT, and PRODUCT_NAME_GROUP and
        --                         changed the logic for the direct_ecomm_flag and product_for_reporting* fields.
        , case
    
            -- 12/6/2023 [Dan Girard] Added default for Bugsnag proforma
            when datasource in ('BS_STRIPE','BS_HEROKU') then 'Ecomm'
            when datasource = 'BS_Direct' then 'Direct'
            
            when productgroup in ('Capture','Cucumber','Squad','Zephyr Scale') then 'Ecomm'
    
	    -- 05/28/2026 [Dan Girard] Added Portal
            when productgroup in ('AlertSite','AQTime','Collaborator','Hiptest','LoadComplete','QAComplete','RAPI Performance','RAPI Test','RAPI Virtualization','TestComplete','TestEngine','Zephyr E','Portal') then 'Direct'
            
            when date <= '2022-06-30' and coalesce(TRANSEXTERNALID,'') = '' and productgroup ilike '%CBT%' and lower(type) in ('invoice','credit memo') then 'Direct'
            when date <= '2022-06-30' and coalesce(TRANSEXTERNALID,'') = '' and productgroup ilike '%CBT%' and lower(type) in ('cash sale','cash refund') then 'Ecomm'
            -- when date <= '2022-06-30' and coalesce(TRANSEXTERNALID,'') = '' and productgroup ilike '%CBT%' then 'Direct'
            -- when date <= '2022-06-30' and productgroup ilike '%CBT%' then 'Ecomm'

            -- 03/04/2026 [Dan Girard] Updated for Swagger Ecomm Reclass
            when type = 'Reclass' and coalesce(TRANSEXTERNALID,'') ilike '%braintree%' --and sisense_product_rollup ilike '%Swagger%' 
            then 'Ecomm'
    
            when date < '2022-01-01' and upper(productgroup) in ('LOADNINJA','PACTFLOW','BITBAR') AND upper(name) like '%STRIPE%' then 'Ecomm'
            when (
                customercategory in ('Reseller','End User')
                or (customercategory = 'ecommerce') 
                and upper(name) like '%CLEVERBRIDGE%'
                ) then 'Direct'
    
            -- 12/6/2023 [Dan Girard] - Added default for type
            -- 02/27/2025 [Dan Girard] Added RECLASS
            when type in ('Invoice','Credit Memo','Reclass') then 'Direct'
    
            -- 12/18/2023 [Dan Girard] Added in and "Direct Sales", and "Ecommerce" => "Ecomm"
            when source in ('Sales Assisted','Direct Sales') then 'Direct'
            when source ilike 'Ecommerce' then 'Ecomm'
    
            else 'Ecomm'
            end direct_ecomm_flag
            
        , case
            --when coalesce(product_for_reporting_ns,'') <> '' then product_for_reporting_ns
            when productgroup = 'Cucumber' then 'Cucumber for Jira'
            when productgroup = 'Hiptest' then 'CucumberStudio'
            when productgroup = 'Squad' then 'Zephyr Squad'
            when productgroup = 'RAPI Test' then 'ReadyAPI Test'
            when productgroup = 'RedayAPI Test' then 'ReadyAPI Test'
            when productgroup = 'TestEngine' then 'ReadyAPI Test'
            when productgroup = 'RAPI Performance' then 'ReadyAPI Perf'
            when productgroup = 'ReadyAPI Performance' then 'ReadyAPI Perf'
            when productgroup = 'RAPI Virtualization' then 'ReadyAPI Virt'
            when productgroup = 'ReadyAPI Virtualization' then 'ReadyAPI Virt'
            when productgroup = 'TestServer' then 'TestComplete'
            when productgroup = 'Bitbar' then 'BitBar'
	    -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
            -- when productgroup = 'API Hub' then 'Swagger'
            else productgroup         
            end product_for_reporting_ns
        
        , case 
            --when coalesce(product_for_reporting_group_ns,'') <> '' then product_for_reporting_group_ns
            when product_for_reporting_ns = 'BitBar' then 'Functional Test'
            when product_for_reporting_ns ilike 'ReadyAPI%' then 'API Lifecycle'
            when product_for_reporting_ns ilike 'Swagger%' then 'API Lifecycle'
            when product_for_reporting_ns ilike '%Pactflow%' then 'API Lifecycle'
    
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            when product_for_reporting_ns ilike 'API Hub Test' then 'API Lifecycle'
    
            -- 03/11/2024 [Dan Girard] Added Reflect
            when product_for_reporting_ns in ('CucumberStudio','QAComplete','Reflect') then 'Test Management'
            when product_for_reporting_ns ilike 'Zephyr%' then 'Test Management'
            when product_for_reporting_ns in ('TestComplete','LoadNinja') then 'Functional Test'
            when product_for_reporting_ns ilike 'CBT%' then 'Functional Test'
    
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_for_reporting_ns ilike '%Bugsnag%' then 'BugSnag'
            
            when product_for_reporting_ns in ('AlertSite','AQTime','Capture','Collaborator','Cucumber for Jira','LoadComplete') then 'Other'
            else product_for_reporting_ns
            end product_for_reporting_group_ns
        
        -- 8/28/2023 [Dan Girard] Added 2 new columns: PRODUCT_FOR_REPORTING_NS_ALIAS and PRODUCT_FOR_REPORTING_NS_ALIAS_COMBINED
        , case 
            --when coalesce(product_for_reporting_ns_alias,'') <> '' then product_for_reporting_ns_alias
            when direct_ecomm_flag = 'Ecomm' AND product_for_reporting_ns = 'CBT' then 'Device Cloud'
            when direct_ecomm_flag = 'Ecomm' AND UPPER(product_for_reporting_ns) = 'BITBAR' then 'Device Cloud'
            when direct_ecomm_flag = 'Ecomm' AND UPPER(product_for_reporting_ns) = 'BUGSNAG RUM' then 'BugSnag'
            when direct_ecomm_flag = 'Direct' AND UPPER(product_for_reporting_ns) = 'BUGSNAG RUM' then 'BugSnag RUM'
            else product_for_reporting_ns
            end product_for_reporting_ns_alias

        -- 12/09/2025 [Dan Girard] Updated logic for BugSnag RUM
        , case when product_for_reporting_ns_alias in ('BugSnag RUM')  then product_for_reporting_ns_alias
            else concat(product_for_reporting_ns_alias,' ',direct_ecomm_flag) 
            end product_for_reporting_ns_alias_combined
            
        , case 
            --when coalesce(product_name,'') <> '' then product_name
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Added BugSnag RUM
            -- 12/09/2025 [Dan GIrard] Update for BugSnag RUM Direct
            when product_for_reporting_ns_alias  = 'BugSnag RUM' and direct_ecomm_flag = 'Direct' then product_for_reporting_ns
            
            when product_for_reporting_ns_alias in ('BugSnag','BugSnag RUM','Stoplight','Swagger') then product_for_reporting_ns_alias_combined
            
            when product_for_reporting_ns_alias = 'CBT' and direct_ecomm_flag = 'Direct' then 'CBT Sales Assisted'
            else product_for_reporting_ns_alias
            end product_name
            
        , case
            --when coalesce(core_noncore,'') <> '' then core_noncore
            when product_name in ('AlertSite','AQTime', 'Collaborator','Cucumber for Jira', 'CucumberStudio', 'LoadComplete', 'LoadNinja', 'QAComplete') then 'Non-Core'
            
            -- 08/01/2024 [Dan Girard] move CBT and BitBar to NON-CORE
            when product_name ilike '%bitbar%' then 'Non-Core'
            when product_name ilike '%CBT%' then 'Non-Core'
            when product_name ilike 'Device Cloud' then 'Non-Core'
            else 'Core'
            end core_noncore
            
        , case
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            when product_name in ('BugSnag RUM','Pactflow','VisualTest','LoadNinja','Reflect') and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'
            when product_name in ('BugSnag Ecomm','Device Cloud','Stoplight Ecomm','Swagger Ecomm') then 'Indirect - Ecomm'

            -- 04/06/2026 [Dan Girard] Added Zephyr Advanced
            when product_name in ('Capture','Cucumber for Jira','Zephyr Scale', 'Zephyr Squad','Zephyr Scale','Zephyr Scale Automate','Zephyr Scale - Automate','QTM4J','Zephyr Advanced') then 'Indirect - Atlassian'
            else 'Direct'
            end direct_indirect
            
        , case
            --when coalesce(product_name_group,'') <> '' then product_name_group
            -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
            -- 05/15/2026 [Dan Girard] Updated for API Hub mapping
            when product_name in ('Explore','Pactflow','Portal','ReadyAPI Perf','ReadyAPI Test','ReadyAPI Virt','Stoplight Direct','Stoplight Ecomm','Swagger Direct','Swagger Ecomm','API Hub Test','API Hub') then 'API'
            when product_name in ('Capture','Cucumber for Jira','Zephyr Scale','Zephyr Scale Automate','Zephyr Scale - Automate','Zephyr Squad','Zephyr Advanced') then 'Marketplace'
    
            -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            -- 10/01/2025 [Dan Girard] Changed to ILIKE BugSnag
            when product_name ilike 'BugSnag%' then 'Observability'
            
            when product_name in ('AlertSite','AQTime','Collaborator','CucumberStudio','LoadComplete','QAComplete') then 'Other'
    
            -- 03/11/2024 [Dan Girard] Added Reflect
            when product_name in ('BitBar','CBT Sales Assisted','Device Cloud','LoadNinja','TestComplete','VisualTest','Zephyr E','Reflect') then 'Test'
            -- 03/11/2024 [Dan Girard] Added Reflect
            when product_name in ('QTM','QTM4J') then 'Test'
                end product_name_group
        
        -- 07/11/2024 [Dan Girard] Added Core/Enterprise flag
        -- 03/26/2025 [Dan Girard] Updated logic to remove nulls
        , case when coalesce(sf.sfdc_ent_core_flag,'') = '' and direct_ecomm_flag = 'Ecomm' then 'Ecomm'
            when coalesce(sf.sfdc_ent_core_flag,'') = '' and direct_ecomm_flag = 'Direct' then 'Core'
            else sf.sfdc_ent_core_flag 
            end sfdc_ent_core_flag 
    
        -- 11/07/2024 [Dan Girard] Added billing_term
        , case when length_days <= 33 then 'Monthly'
            else 'Annual'
            end billing_term
            
        -- 11/14/2024 [Dan Girard] Added stream_revenue
        , stream_revenue
    
        -- 06/25/2025 [Dan Girard] Added sisense_product_rollup and pbt_group
        , pbt_group
    
        -- 11/24/2025 [Dan Girard] Added datasource_group logic
        , case when datasource = 'NS' then 'As Reported'
            else 'Proforma'
            end datasource_group

        -- 05/29/2026 [Dan Girard] Added SFDC Name
        , sf.sfdc_name
    from 
        main a
        left join finance_db.public.dim_globalultimateparent_map b on upper(a.globalultimateparent) = upper(b.globalultimateparent_orig)
        
        -- 7/11/2024 [Dan Girard] Join to Salesforce data
        left join sfdc_data sf on a.invoiceno = sf.invoice_no
    
        -- 06/25/2025 [Dan Girard] Added join to the prod table
        left join prod_map p on upper(a.productgroup) = upper(p.productgroupmap)
       ;

    return 'Successfully created or replaced table arr_master.';

end;
$$
;