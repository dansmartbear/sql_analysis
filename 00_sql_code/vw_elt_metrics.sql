-- create or replace view finance_db.public.vw_elt_metrics copy grants as
with 
-- Create the anchor date calculation by checking the current date against the 5th business day
fifth_bd as (
    select 
        case 
        when current_date() >= (
            dateadd(day, 
            case 
                when dayofweek(date_trunc('month', current_date())) = 0 then 4
                when dayofweek(date_trunc('month', current_date())) = 6 then 5
                else 5 - dayofweek(date_trunc('month', current_date()))
            end, 
            date_trunc('month', current_date())
        )) then date_trunc('month', current_date())
        else dateadd(month, -1, date_trunc('month', current_date()))
        end as fifth_business_day
)
,anchor_date as
(
    select 
        case 
            when current_date() >= fifth_business_day then date_trunc('month', current_date())
            else dateadd(month, -1, date_trunc('month', current_date()))
        end as anchor_date_calc
    from fifth_bd
)
,lic_ren_split as
(
    select 'BitBar'        product, .32363942411 license, 1-license renewal union all
    select 'Device Cloud'  product, .32363942411 license, 1-license renewal union all
    
    select 'BugSnag'       product, .08081265803 license, 1-license renewal union all
    select 'Reflect'       product, .27088228901 license, 1-license renewal union all
    select 'Stoplight'     product, .17757720050 license, 1-license renewal union all
    
    select 'Swagger Ecomm' product, .26021798714 license, 1-license renewal union all
    select 'API Hub'       product, .26021798714 license, 1-license renewal union all
    
    select 'LoadNinja'     product, .31544963836 license, 1-license renewal union all
    select 'Pactflow'      product, .34764511066 license, 1-license renewal  
)
-------------------------------------------------------------------------------------
,sfdc as
(
    -- [Dan Girard] Updated to use from table fact_elt_weekly_flash_sfdc which is built by the SFDC Flash to Snowflake prep flow
    select
        report_month,
        case when product_group = 'Zephyr' then 'Zephyr Enterprise'
            when product_group = 'Cucumber' then 'CucumberStudio'
            else product_group
            end product,
        source,
        type,
        core_ent_flag,
        direct_ecomm_flag,
        order_type_final,
        amount_usd,
        contract_length,
        acv,
        invoice_no,
        status_inq_pull,
        multiyear_flag,
        my_amount,
        sfdc_invoice_no invoice_num__c,
        new_expansion,
        close_date date,
        null region,
        reclass_type,
        reclass_product,
        reclass_amount_usd,
        pf_hold_flag,
        pf_hold_amount,
    from
        finance_db.public.fact_elt_weekly_flash_sfdc

    -- 10/07/2025 [Dan Girard] Added where for the data
    where
        close_date <= current_date()
)
,atla_detail as
(
    -- 06/04/2026 [Dan Girard] Replaced with data from the Atlassian Forecasting view
    select
        region,
        sale_date saledate,
        hosting,
        vendor_amount vendoramount,
        sale_type saletype,
        maintenance_start_date maintenancestartdate,
        maintenance_end_date maintenanceenddate,
        contract_length,
        addon_name addonname,
        product,
        status_type,
        current_user_count,
        previous_user_count,
        user_count_change,
        price_per_user,
        expansion_billings, 
        new_billings, 
        license_billings,
        renewal_billings,
        transaction_id transactionid,
        billing_period,
        sale_date purchasedetails_saledate,
        acv_lic,
        acv_ren,
        new_expansion,
    from 
        finance_db.public.vw_atlassian_forecasting
    where
        date(sale_date) between dateadd(month,-1,date_trunc(month,current_date())) and dateadd(day,0,current_date())
)
,atla as
(
    select
        date_trunc(month,saledate) report_month,
        'Atlassian' source,
        product,
        hosting type,
        'License' order_type_final,
        'Ecomm' core_ent_flag,
        'Ecomm' direct_ecomm_flag,
        license_billings amount_usd,
        case when (contract_length) < 370 then amount_usd
            else (amount_usd/contract_length) * 365
            end acv,
        transactionid invoice_no,
        billing_period,
        new_expansion,
        saledate date,
        
        case when maintenancestartdate >= dateadd(day, 2, dateadd(day,-1,dateadd(quarter,1,date_trunc(quarter,current_date())))) then 'Pull'
            else 'INQ'
            end status_inq_pull
    from 
        atla_detail
    where
        license_billings <> 0
        
    union all
    
    select
        date_trunc(month,saledate) report_month,
        'Atlassian' source,
        product,
        hosting type,
        'Renewal' order_type_final,
        'Ecomm' core_ent_flag,
        'Ecomm' direct_ecomm_flag,
        renewal_billings amount_usd,
        case when (contract_length) < 370 then amount_usd
            else (amount_usd/contract_length) * 365
            end acv,
        transactionid invoice_no,
        billing_period,
        'Renewal' new_expansion,
        saledate date,

        case when maintenancestartdate >= dateadd(day, 2, dateadd(day,-1,dateadd(quarter,1,date_trunc(quarter,current_date())))) then 'Pull'
            else 'INQ'
            end status_inq_pull
    from 
        atla_detail
    where
        renewal_billings <> 0
)
-----------------------------------------------------------------------------------
,stripe as
(   
    select 
        date(date_trunc(month,created)) report_month,
        'Stripe' source,
        case when a.product ilike any ('Stoplight%','Reflect%','LoadNinja%','Pactflow%','BitBar%','Bugsnag%') then a.product
            when a.product ilike any ('Smartbear Hubs%') then 'API Hub'
            end productgroup,
        'SaaS' type,
        case 
            when a.product ilike any ('Pactflow','LoadNinja') then 'Core'
            else 'Ecomm' 
            end core_ent_flag,
        case 
            when a.product ilike any ('Pactflow','LoadNinja') then 'Direct'
            else 'Ecomm' 
            end direct_ecomm_flag,
        'License' order_type_final,
        case when a.product ilike any ('Stoplight%','Reflect%','LoadNinja%','Pactflow%','BitBar%') then gross
            when a.product ilike any ('Smartbear Hubs%') then net
            when a.product ilike any ('Bugsnag%') then
                case when reporting_category ilike any ('fee','dispute') then 0 else gross end
            end gross_net,
        gross_net * b.license amount_usd,
        amount_usd acv,
        coalesce(invoice_id,charge_id,balance_transaction_id) invoice_no,
        case when coalesce(datediff(day,period_start,period_end),0) > 35 then 'Annual'
            else 'Monthly'
            end billing_period,
        case 
            when a.product ilike any ('Pactflow','LoadNinja') then 'Direct'
            else 'Indirect - Ecomm'
            end  direct_indirect,
        created date,

        case when period_start >= dateadd(day, 2, dateadd(day,-1,dateadd(quarter,1,date_trunc(quarter,current_date())))) then 'Pull'
            else 'INQ'
            end status_inq_pull
    from 
        stripe_db.analyze_dev.vw_balance_txns_lineitem a
        left join lic_ren_split b on productgroup = b.product
    where
        -- date(created_utc) between dateadd(quarter,-6,date_trunc(quarter,current_date())) and dateadd(day,-1,current_date())
        date(created_utc) between dateadd(month,-1,date_trunc(quarter,current_date())) and dateadd(day,-1,current_date())
        and amount_usd <> 0
        and a.product ilike any ('Stoplight%','Reflect%','LoadNinja%','Pactflow%','Smartbear Hubs%','BitBar%','Bugsnag%')
    
    union all
    
    select 
        date(date_trunc(month,created)) report_month,
        'Stripe' source,
        case when a.product ilike any ('Stoplight%','Reflect%','LoadNinja%','Pactflow%','BitBar%','Bugsnag%') then a.product
            when a.product ilike any ('Smartbear Hubs%') then 'API Hub'
            end productgroup,
        'SaaS' type,
        case 
            when a.product ilike any ('Pactflow','LoadNinja') then 'Core'
            else 'Ecomm' 
            end core_ent_flag,
        case 
            when a.product ilike any ('Pactflow','LoadNinja') then 'Direct'
            else 'Ecomm' 
            end direct_ecomm_flag,
        'Renewal' order_type_final,
        
        case when a.product ilike any ('Stoplight%','Reflect%','LoadNinja%','Pactflow%','BitBar%') then gross
            when a.product ilike any ('Smartbear Hubs%') then net
            when a.product ilike any ('Bugsnag%') then
                case when reporting_category ilike any ('fee','dispute') then 0 else gross end
            end gross_net,

        gross_net * b.renewal amount_usd,
        amount_usd acv,
        coalesce(invoice_id,charge_id,balance_transaction_id) invoice_no,
        case when coalesce(datediff(day,period_start,period_end),0) > 35 then 'Annual'
            else 'Monthly'
            end billing_period,
        case 
            when a.product ilike any ('Pactflow','LoadNinja') then 'Direct'
            else 'Indirect - Ecomm'
            end  direct_indirect,
        created date,

        
        case when period_start >= dateadd(day, 2, dateadd(day,-1,dateadd(quarter,1,date_trunc(quarter,current_date())))) then 'Pull'
            else 'INQ'
            end status_inq_pull
    from 
        stripe_db.analyze_dev.vw_balance_txns_lineitem a
        left join lic_ren_split b on productgroup = b.product
    where
        -- date(created_utc) between dateadd(quarter,-6,date_trunc(quarter,current_date())) and dateadd(day,-1,current_date())
        date(created_utc) between dateadd(month,-1,date_trunc(quarter,current_date())) and dateadd(day,-1,current_date())
        and amount_usd <> 0
        and a.product ilike any ('Stoplight%','Reflect%','LoadNinja%','Pactflow%','Smartbear Hubs%','BitBar%','Bugsnag%')
)
-----------------------------------------------------------------------------------
,actuals_detail as
(
    select
        date_trunc(month,date) report_month,
        'Actuals' source,
        case 
             when a.sisense_product_rollup ilike 'Bugsnag Direct' then 'Bugsnag'
             when a.sisense_product_rollup ilike 'Bugsnag Ecomm' then 'Bugsnag'
             when a.sisense_product_rollup ilike 'Reflect Direct' then 'Reflect'
             when a.sisense_product_rollup ilike 'Reflect Ecomm' then 'Reflect'
             when a.sisense_product_rollup ilike 'Stoplight Direct' then 'Stoplight'
             when a.sisense_product_rollup ilike 'Stoplight Ecomm' then 'Stoplight'
             when a.sisense_product_rollup = 'Squad' then 'Zephyr Squad'
             else a.sisense_product_rollup
             end product,
        a.stream_reporting type,
        case when a.direct_ecomm_flag = 'ecomm' then 'ecomm'
             when coalesce(a.core_ent_flag,'') = '' then 'Core'
             else a.core_ent_flag
             end core_ent_flag,
        a.direct_ecomm_flag,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        a.my my_amount,
        a.date,
    
        -- 08/19/2025 [Dan Girard] Added SFDC Close Date only for direct. Force it to the sale date if it's anything other than direct
        case when direct_indirect = 'Direct' then
            case when date_trunc(quarter,date) > date_trunc(quarter,coalesce(sfdc_closedate,date)) then date
                else coalesce(sfdc_closedate,date)
                end
            else date
            end closedate,
            
        case when coalesce(a.invoiceno,'') = '' then concat('MB',a.date,a.lineid,a.sisense_product_rollup,a.amount_usd) //concat('UID','-',uuid_string())
            else a.invoiceno
            end invoice_no,
            
        a.multiyear_flag,
        a.status_inq_pull,
        
        case when a.sisense_product_rollup = 'Portal' and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'
            else direct_indirect
            end direct_indirect,

        -- 08/20/2025 [Dan Girard] Update the new_expansion logic to use the new new/expansion field from master billing
        -- case when ordertype1 = 'Existing' then 'Expansion'
        --     else ordertype1
        --     end new_expansion,
        new_expansion,

        -- 04/28/2026 [Dan Girard] Added type and aliased as saletype
        type saletype,

        -- 06/04/2026 [Dan Girard] Added the globalultimateparent
        globalultimateparent,
    from
        finance_db.public.master_billing a
        --left join (select distinct core_ent_flag, invoiceno from finance_db.public.dim_salesforce_account_map) b on a.invoiceno = b.invoiceno
    where
        year(date) >= (year(current_date()) - 4)
        and date_trunc(month,date) < date_trunc(month,dateadd(day,-1,current_date()))

        -- 02/02/2026 [Dan Girard] Added filter for blank order_type_final (usually shows in the first few days of the month)
        and coalesce(order_type_final,'') <> ''
)
,actuals as
(
    select
        report_month,
        source,
        product,
        type,
        core_ent_flag,
        direct_ecomm_flag,
        order_type_final,
        sum(amount_usd) amount_usd,
        sum(acv) acv,
        sum(my_amount) my_amount,
        date,
        invoice_no,
        multiyear_flag,
        status_inq_pull,
        direct_indirect,
        new_expansion,

        -- 08/19/2025 [Dan Girard] Added closedate
        closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        saletype,

        -- 06/04/2026 [Dan Girard] Added the globalultimateparent
        globalultimateparent,
    from
        actuals_detail
    group by
        all

    -- 09/24/2025 [Dan Girard] Added new union to Actuals override
    union all

    select
        report_month,
        source,
        product,
        type,
        core_ent_flag,
        direct_ecomm_flag,
        order_type_final,
        sum(amount_usd) amount_usd,
        sum(acv) acv,
        sum(my_amount) my_amount,
        date,
        invoice_no,
        multiyear_flag,
        status_inq_pull,
        direct_indirect,
        new_expansion,
        close_date,

        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype,

        -- 06/04/2026 [Dan Girard] Added the globalultimateparent
        null globalultimateparent,
    from
        finance_db.public.fact_elt_weekly_flash_ns
    group by
        all
)
,scenario as
(
    select 
        a.date report_month,
        a.scenario source,
        a.product_name product,
        'Billing' type,
        a.core_ent_flag,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
        a.order_type_final,
        sum(a.amount_usd) amount_usd,

        -- 12/15/2025 [Dan Girard] Added ACV and MY
        sum(a.acv) acv,
        sum(a.my) my,
        
        '' invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.direct_indirect,
        b.pbt_group,
        a.order_type_final new_expansion,
    from 
        finance_db.public.dim_topline_billing_scenarios a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product_map,'_',direct_ecomm_flag)) = b.lookup_map_upper
    where
        -- year(a.date) >= (year(current_date()) - 2)
        year(a.date) >= year(current_date())
        and date_trunc(quarter,a.date) <= date_trunc(quarter,current_date())
    group by
        all

    union all
    
    select 
        a.date report_month,
        a.scenario source,
        a.product_name product,
        'ARR' type,
        a.core_ent_flag,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
        a.order_type_final,
        null amount_usd,
        sum(a.amount_usd) acv,

        -- 12/15/2025 [Dan Girard] Added MY
        null my,
        
        '' invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.direct_indirect,
        b.pbt_group,
        '' new_expansion,
    from 
        finance_db.public.dim_topline_arr_scenarios a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product_map,'_',direct_ecomm_flag)) = b.lookup_map_upper
     where
        -- year(a.date) >= (year(current_date()) - 2)
        year(a.date) >= year(current_date())
        and date_trunc(quarter,a.date) <= date_trunc(quarter,current_date())
    group by
        all

    union all

    select 
        date_trunc(quarter,a.date) report_month,
        a.scenario source,
        a.product_name product,
        'Ren - INQ' type,
        a.core_ent_flag,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
        a.order_type_final,
        sum(a.amount_usd) amount_usd,
        null acv,

        -- 12/15/2025 [Dan Girard] Added MY
        null my,
        
        '' invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.direct_indirect,
        b.pbt_group,
        '' new_expansion,
    from 
        finance_db.public.dim_topline_renewal_billing_scenarios a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product_map,'_',direct_ecomm_flag)) = b.lookup_map_upper
     where
        -- year(a.date) >= (year(current_date()) - 2)
        year(a.date) >= year(current_date())
        and date_trunc(quarter,a.date) <= date_trunc(quarter,current_date())
        and renewal_metric = 'InQ ACV'
    group by
        all
    
    union all
    
    select 
        date_trunc(quarter,a.date) report_month,
        a.scenario source,
        a.product_name product,
        'Ren - INQ MY' type,
        a.core_ent_flag,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
        a.order_type_final,
        sum(a.amount_usd) amount_usd,
        null acv,

        -- 12/15/2025 [Dan Girard] Added MY
        null my,
        
        '' invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.direct_indirect,
        b.pbt_group,
        '' new_expansion,
    from 
        finance_db.public.dim_topline_renewal_billing_scenarios a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product_map,'_',direct_ecomm_flag)) = b.lookup_map_upper
     where
        -- year(a.date) >= (year(current_date()) - 2)
        year(a.date) >= year(current_date())
        and date_trunc(quarter,a.date) <= date_trunc(quarter,current_date())
        and renewal_metric = 'InQ MultiYear'
    group by
        all
    
    union all
        
    select 
        date_trunc(quarter,a.date) report_month,
        a.scenario source,
        a.product_name product,
        'Ren - PF' type,
        a.core_ent_flag,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
        a.order_type_final,
        sum(a.amount_usd) amount_usd,
        null acv,

        -- 12/15/2025 [Dan Girard] Added MY
        null my,
        
        '' invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.direct_indirect,
        b.pbt_group,
        '' new_expansion,
    from 
        finance_db.public.dim_topline_renewal_billing_scenarios a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product_map,'_',direct_ecomm_flag)) = b.lookup_map_upper
     where
        -- year(a.date) >= (year(current_date()) - 2)
        year(a.date) >= year(current_date())
        and date_trunc(quarter,a.date) <= date_trunc(quarter,current_date())
        and renewal_metric = 'Pull Forward ACV'
    group by
        all
    
    union all
    
    select 
        date_trunc(quarter,a.date) report_month,
        a.scenario source,
        a.product_name product,
        'Ren - PF MY' type,
        a.core_ent_flag,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
        a.order_type_final,
        sum(a.amount_usd) amount_usd,
        null acv,

        -- 12/15/2025 [Dan Girard] Added MY
        null my,
        
        '' invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.direct_indirect,
        b.pbt_group,
        '' new_expansion,
    from 
        finance_db.public.dim_topline_renewal_billing_scenarios a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product_map,'_',direct_ecomm_flag)) = b.lookup_map_upper
     where
        -- year(a.date) >= (year(current_date()) - 2)
        year(a.date) >= year(current_date())
        and date_trunc(quarter,a.date) <= date_trunc(quarter,current_date())
        and renewal_metric = 'Pull Forward MultiYear'
    group by
        all
)
,arr as
(
    select
        date_trunc(quarter,date_under_contract) report_month,
        'ARR' source,
        case when a.direct_indirect = 'Direct' then 'Direct'
             else 'Ecomm'
             end direct_ecomm_flag,
             
        globalultimateparentupper,
        case when globalultimateparentupper = '**BLANK**' then '** Unknown **'
             when globalultimateparentupper = '**NULL**' then '** Unknown **'
             when CONTAINS(globalultimateparentupper,'SALESFORCE') and CONTAINS(upper(productgroup),'BUGSNAG') and upper(direct_ecomm_flag) = 'ECOMM' then '** Unknown **'
             when CONTAINS(globalultimateparentupper,'STRIPE,') and (CONTAINS(upper(productgroup),'BITBAR') or CONTAINS(upper(productgroup),'LOADNINJA')) and upper(direct_ecomm_flag) = 'ECOMM' then '** Unknown **'
             when CONTAINS(globalultimateparentupper,'HEROKU') then '** Unknown **'
             when CONTAINS(globalultimateparentupper,'PAYPAL') and CONTAINS(upper(productgroup),'SWAGGER') and upper(direct_ecomm_flag) = 'ECOMM' then '** Unknown **'
             else globalultimateparentupper
             end globalultimateparentupperclean,
        
        case when a.productgroup = 'Cucumber for Jira' then 'Cucumber'
             when a.productgroup = 'ReadyAPI Test' then 'RAPI Test'
             when a.productgroup = 'ReadyAPI Performance' then 'RAPI Performance'
             when a.productgroup = 'ReadyAPI Virtualization' then 'RAPI Virtualization'
             
             when a.productgroup = 'API Hub Test' then 'Test'
             
             else a.productgroup
             end product,
             
        a.sbitemcategory_calc type,
        case when a.sfdc_ent_core_flag = 'Enterprise' then 'Ent'
            else a.sfdc_ent_core_flag
            end core_ent_flag ,
        a.ordertype order_type_final,
        sum(a.cur_arr) acv,
        sum(prior_arr) acv_prior,
        date_under_contract date,
        direct_indirect,
    from
        finance_db.public.arr_master_retention a
    where
        section = 'Quarter YoY'
        and date_trunc(quarter,date_under_contract) between dateadd(year,-3,date_trunc(year,current_date())) and date_trunc(quarter,current_date())
    group by
        all
)
,combined as
(
    select
        a.report_month,
        a.source,
        a.product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,

        -- 07/07/2025 [Dan Girard] Change to the ACTUALS Direct/Indirect
        -- b.direct_indirect,
        a.direct_indirect,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        null acv_prior,
        a.my_amount my,
        a.invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.pbt_group,
        a.date,
        
        a.globalultimateparent globalultimateparentupperclean,
        
        a.multiyear_flag,
        a.status_inq_pull,
        null billing_period,
        new_expansion,
        null region,

        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        null pf_hold_flag,
        null pf_hold_amount,

        -- 08/19/2025 [Dan Girard] Added new Close Date
        a.closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        a.saletype,
    from
        actuals a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product,'_',a.direct_ecomm_flag)) = b.lookup_map_upper

    union all
    
    select
        a.report_month,
        a.source,
        a.product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,
        'Direct' direct_indirect,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        null acv_prior,
        a.my_amount my,
        a.invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.pbt_group,
        a.date,
        null globalultimateparentupperclean,
        multiyear_flag,
        status_inq_pull,
        null billing_period,
        new_expansion,
        region,
        
        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        null pf_hold_flag,
        null pf_hold_amount,

        -- 08/19/2025 [Dan Girard] Added new Close Date
        a.date closedate,
        
        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype,

    from
        sfdc a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(a.product) = b.sfdc_lookup_upper and b.direct_ecomm_map = 'Direct'
    where
        pf_hold_flag <> 1

    union all

    -- 06/23/2025 [Dan Girard] Added PF_HOLD source data
    select
        a.report_month,
        'SFDC PF Hold' source,
        a.product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,
        'Direct' direct_indirect,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        null acv_prior,
        a.my_amount my,
        a.invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.pbt_group,
        a.date,
        null globalultimateparentupperclean,
        multiyear_flag,
        status_inq_pull,
        null billing_period,
        new_expansion,
        region,
        
        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        pf_hold_flag,
        pf_hold_amount,

        -- 08/19/2025 [Dan Girard] Added new Close Date
        a.date closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype,
    from
        sfdc a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(a.product) = b.sfdc_lookup_upper and b.direct_ecomm_map = 'Direct'
    where
        pf_hold_flag = 1
        
    union all
    
    select
        a.report_month,
        a.source,
        a.product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,
        case when product not ilike 'Swagger%' then b.direct_indirect
            else 'Indirect - Ecomm'
            end direct_indirect,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        null acv_prior,
        null my,
        a.invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.pbt_group,
        a.date,
        null globalultimateparentupperclean,
        null multiyear_flag,
        a.status_inq_pull,
        a.billing_period,
        new_expansion,
        null region,

        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        null pf_hold_flag,
        null pf_hold_amount,
        
        -- 08/19/2025 [Dan Girard] Added new Close Date
        null closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype,
    from
        atla a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product,'_',a.direct_ecomm_flag)) = b.lookup_map_upper

    union all
    
    select
        a.report_month,
        a.source,
        a.productgroup product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,
        b.direct_indirect,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        null acv_prior,
        null my,
        a.invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.pbt_group,
        a.date,
        null globalultimateparentupperclean,
        null multiyear_flag,
        a.status_inq_pull,
        a.billing_period,
        null new_expansion,
        null region,

        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        null pf_hold_flag,
        null pf_hold_amount,
        
        -- 08/19/2025 [Dan Girard] Added new Close Date
        null closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype,
    from
        stripe a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.productgroup,'_',a.direct_ecomm_flag)) = b.lookup_map_upper
   
    union all
    
    select
        a.report_month,
        a.source,
        a.product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,
        a.direct_indirect,
        a.order_type_final,
        a.amount_usd,
        a.acv,
        null acv_prior,
        
        -- 12/15/2025 [Dan Girard] Added MY
        a.my,
        
        a.invoice_no,
        a.product_hub,
        a.product_for_reporting,
        a.product_name,
        a.product_parent,
        a.pbt_group,
        null date,
        null globalultimateparentupperclean,
        null multiyear_flag,
        null status_inq_pull,
        null billing_period,
        new_expansion,
        null region,

        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        null pf_hold_flag,
        null pf_hold_amount,
         
        -- 08/19/2025 [Dan Girard] Added new Close Date
        null closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype
    from
        scenario a

    union all

    select
        a.report_month,
        a.source,
        a.product,
        a.type,
        a.core_ent_flag,
        a.direct_ecomm_flag,
        b.direct_indirect,
        a.order_type_final,
        null amount_usd,
        a.acv,
        a.acv_prior,
        null my,
        null invoice_no,
        b.product_hub,
        b.product_for_reporting,
        b.product_name,
        b.product_parent,
        b.pbt_group,
        a.date,
        a.globalultimateparentupperclean,
        null multiyear_flag,
        null status_inq_pull,
        null billing_period,
        null new_expansion,
        null region,

        -- 06/23/2025 [Dan Girard] Added PF_HOLD
        null pf_hold_flag,
        null pf_hold_amount,
        
        -- 08/19/2025 [Dan Girard] Added new Close Date
        null closedate,

        -- 04/28/2026 [Dan Girard] Added saletype
        null saletype
    from
        arr a
        left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(a.product,'_',a.direct_ecomm_flag)) = b.lookup_map_upper
)
select
    uuid_string() elt_metrics_uid,
    -- row_number() over (order by 1) as elt_metrics_id,
    report_month,
    source,
    product,
    type,
    core_ent_flag,
    direct_ecomm_flag,
    direct_indirect,
    order_type_final,
    amount_usd,
    acv,
    acv_prior,
    my,
    invoice_no,
    product_for_reporting,
    product_name,
    product_parent,
    product_hub,
    pbt_group,
    to_date(date) date,
    globalultimateparentupperclean,
    multiyear_flag,
    status_inq_pull,
    billing_period,
    new_expansion,
    region,
    dateadd(day,-1,current_date()) data_valid_thru,
    current_timestamp () snapshot_date,
    date_part('timezone_hour', snapshot_date::timestamp_tz) snapshot_date_offset,

    -- 06/23/2025 [Dan Girard] Added PF_HOLD
    pf_hold_flag,
    pf_hold_amount,

    -- 08/19/2025 [Dan Girard] Added new Close Date
    closedate,

    -- 04/28/2026 [Dan Girard] Added saletype
    saletype,
    'USD' currency,
    
    anchor_date_calc,

    case when order_type_final = 'Renewal' then 'Renewal'
        else 'License'
        end license_renewal,
    
    case when date_trunc('quarter',report_month) = date_trunc('quarter',anchor_date_calc)
            and date_trunc('month',report_month) = date_trunc('month',anchor_date_calc) then true
        else false
        end  in_month_flag,

    case when date_trunc('quarter',report_month) = date_trunc('quarter',anchor_date_calc) then true
        else false
        end  in_quarter_flag,

    case when date_trunc('year',report_month) = date_trunc('year',anchor_date_calc) then true
        else false
        end  in_current_year_flag,

     case when date_trunc('quarter',report_month) = date_trunc('quarter',dateadd('quarter',-1,anchor_date_calc)) then true
        else false
        end  in_prev_quarter_flag,

    case 
        when source = 'ARR' then 'ARR'
        when source = 'Actuals' then 'Actuals'
        when source = 'Atlassian' then 'In Month'
        when source = 'Braintree' then 'In Month'
        when source = 'SFDC' then 'In Month'
        when source = 'Stripe' then 'In Month'
        when source ilike '%Plan%' then 'Plan'
        when source ilike '%Fcst%' then 'Plan'
        end source_group,

    case 
        when direct_indirect = 'Direct' and license_renewal = 'License' then 'Direct License'
        when direct_indirect = 'Direct' and license_renewal = 'Renewal' then 'Direct Renewal'
        when direct_indirect = 'Indirect - Atlassian' then 'Atlassian'
        when direct_indirect = 'Indirect - Ecomm' then 'SmartBear Ecomm'
        else 'Uncategorized'
        end billing_category,
    
from    
    combined
    left join anchor_date on 1=1
;