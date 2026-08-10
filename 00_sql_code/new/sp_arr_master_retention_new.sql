create or replace procedure finance_db.dev_netsuite.sp_arr_master_retention_new()
    returns varchar
    language sql
    execute as owner
as
$$
begin

    /*
      table: finance_db.dev_netsuite.arr_master_retention_new
    
      purpose:
        - build finance_db.dev_netsuite.arr_master_retention with monthly, quarterly, and year-over-year arr views
        - enable retention analysis by customer, product, and various attributes
    
      target table:
        - finance_db.dev_netsuite.arr_master_retention_new
    
      primary source tables:
        - finance_db.dev_netsuite.arr_master_waterfall_new
        - data_master_db.public.dimdate
        - finance_db.public.dim_product_group_map
    
      grain:
        - one row per section (month, month yoy, quarter, quarter yoy)
          per customer / source / productgroup / ship_region / naics_sector / product / attributes / date_under_contract
    
      updated:
        - 2025-11-24 [Dan Girard]: added datasource_group attributes across all views
        - 2025-06-05 [Dan Girard]: added pbt_group attributes across all views
        - 2025-03-25 [Dan Girard]: added sfdc_ent_core_flag (ent/core flag)
        - 2024-11-07 [Dan Girard]: added billing_term alias for billing_period in final output
        - 2024-08-02 [Dan Girard]: added billing_period (monthly/annual) based on contract length
        - 12/29/2025 [Dan Girard]: Added date of first sale and age
    */
    
    -- create target table from cte stack
    create or replace table finance_db.dev_netsuite.arr_master_retention_new copy grants as 
    
    with 
    -- cte: waterfall_dates
    -- purpose: get min and max contract dates from arr_master_waterfall_new to bound calendar ranges
    waterfall_dates as
    (
        select 
            min(wf.date_under_contract) as min_date,
            max(wf.date_under_contract) as max_date
        from
            finance_db.dev_netsuite.arr_master_waterfall_new wf
    )

    -- cte: dates
    -- purpose: build month_end date series within the min/max contract date window
    ,dates as
    (
        select distinct
            dd.month_end
        from
            data_master_db.public.dimdate dd
            cross join waterfall_dates wd
        where
            date_trunc(month, dd.date) between wd.min_date and wd.max_date
    )

    -- cte: arr
    -- purpose: normalize arr detail by customer/product/date with billing_period and flags
    ,arr as
    (
        select
            case 
                when a.globalultimateparentupper = '' then '**BLANK**' 
                when a.globalultimateparentupper is null then '**NULL**'
                else a.globalultimateparentupper 
            end as globalultimateparentupper,
            a.source,
            case
                when coalesce(a.ship_region, '') = '' then 'N/A'
                else a.ship_region
            end as ship_region,
            case 
                when coalesce(a.naics_sector, '') = '' then 'N/A' 
                else a.naics_sector 
            end as naics_sector,
            a.date_under_contract,
            sum(a.acv) as cur_arr,
            case 
                when a.ordertype = 'Renewal' then 'Renewal' 
                else 'License' 
            end as ordertype,
            a.productgroup,
            a.product_name,
            a.core_noncore,
            a.direct_indirect,
            a.product_name_group,
            a.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            case
                when datediff(day, a.contractitemstartdate, a.contractitemenddate) <= 33 then 'Monthly'
                else 'Annual'
            end as billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            -- case
            --     when a.sfdc_ent_core_flag is null then 'N/A'
            --     else a.sfdc_ent_core_flag
            -- end as sfdc_ent_core_flag,
            'Core' sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            a.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            a.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            coalesce(a.sfdc_name, '') as sfdc_name
        from
            finance_db.dev_netsuite.arr_master_waterfall_new a
        group by
            all
    )

    -- cte: distinct_group
    -- purpose: derive distinct attribute combinations for use in month/quarter fillers
    ,distinct_group as
    (
        select distinct 
            ar.globalultimateparentupper,
            ar.source,
            ar.ship_region,
            ar.naics_sector,
            ar.ordertype,
            ar.productgroup,
            ar.product_name,
            ar.core_noncore,
            ar.direct_indirect,
            ar.product_name_group,
            ar.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            ar.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            ar.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            ar.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            ar.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            ar.sfdc_name
        from 
            arr ar
    )

    -- cte: filler
    -- purpose: cross join attribute groups to all month_end dates to ensure full time series
    ,filler as
    (
        select
            dg.globalultimateparentupper,
            dg.source,
            dg.productgroup,
            case 
                when dg.ship_region = '' then 'N/A' 
                else dg.ship_region 
            end as ship_region,
            case 
                when dg.naics_sector = '' then 'N/A' 
                else dg.naics_sector 
            end as naics_sector,
            d.month_end,
            dg.ordertype,
            dg.product_name,
            dg.core_noncore,
            dg.direct_indirect,
            dg.product_name_group,
            dg.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            dg.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            dg.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            dg.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            dg.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            dg.sfdc_name
        from
            distinct_group dg
            cross join dates d
    )

    -- cte: mth_detail
    -- purpose: monthly arr with prior-month arr for same attribute grain
    ,mth_detail as
    (
        select
            'Month' as section,
            f.globalultimateparentupper,
            f.source,
            f.productgroup,
            f.ship_region,
            f.naics_sector,
            f.month_end as date_under_contract,
            coalesce(a.cur_arr, 0) as cur_arr,
            lag(coalesce(a.cur_arr, 0), 1, 0) over (
                partition by
                    f.globalultimateparentupper,
                    f.source,
                    f.productgroup,
                    f.ship_region,
                    f.naics_sector,
                    f.ordertype,
                    f.product_name,
                    f.core_noncore,
                    f.direct_indirect,
                    f.product_name_group,
                    f.sbitemcategory_calc,

                    -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                    f.billing_period,

                    -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                    f.sfdc_ent_core_flag,

                    -- 06/05/2025 [Dan Girard] Added PBT_Group
                    f.pbt_group,

                    -- 11/24/2025 [Dan Girard] Added datasource_group
                    f.datasource_group,
                    
                    -- 05/29/2026 [Dan Girard] Added SFDC_Name
                    f.sfdc_name
                order by
                    f.month_end
            ) as prior_arr,
            f.ordertype,
            f.product_name,
            f.core_noncore,
            f.direct_indirect,
            f.product_name_group,
            f.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            f.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            f.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            f.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            f.datasource_group,
            
            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            f.sfdc_name
        from
            filler f
            left join arr a
                on f.globalultimateparentupper = a.globalultimateparentupper
                and f.source = a.source
                and f.productgroup = a.productgroup
                and f.ship_region = a.ship_region
                and f.naics_sector = a.naics_sector
                and f.month_end = a.date_under_contract
                and f.ordertype = a.ordertype
                and f.product_name = a.product_name
                and f.core_noncore = a.core_noncore
                and f.direct_indirect = a.direct_indirect
                and f.product_name_group = a.product_name_group
                and f.sbitemcategory_calc = a.sbitemcategory_calc

                -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                and f.billing_period = a.billing_period

                -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag

                -- 06/05/2025 [Dan Girard] Added PBT_Group
                and f.pbt_group = a.pbt_group

                -- 11/24/2025 [Dan Girard] Added datasource_group
                and f.datasource_group = a.datasource_group
                -- 05/29/2026 [Dan Girard] Added SFDC_Name
                and f.sfdc_name = a.sfdc_name
    )

    -- cte: mth_yoy_detail
    -- purpose: monthly arr with prior-year same-month arr for yoy comparison
    ,mth_yoy_detail AS
    (
        select
            'Month YoY' AS section,
            f.globalultimateparentupper,
            f.source,
            f.productgroup,
            f.ship_region,
            f.naics_sector,
            f.month_end as date_under_contract,
            coalesce(a.cur_arr, 0) as cur_arr,
            lag(coalesce(a.cur_arr, 0), 12, 0) over (
                partition by
                    f.globalultimateparentupper,
                    f.source,
                    f.productgroup,
                    f.ship_region,
                    f.naics_sector,
                    f.ordertype,
                    f.product_name,
                    f.core_noncore,
                    f.direct_indirect,
                    f.product_name_group,
                    f.sbitemcategory_calc,

                    -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                    f.billing_period,

                    -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                    f.sfdc_ent_core_flag,

                    -- 06/05/2025 [Dan Girard] Added PBT_Group
                    f.pbt_group,

                    -- 11/24/2025 [Dan Girard] Added datasource_group
                    f.datasource_group,

                    -- 05/29/2026 [Dan Girard] Added SFDC_Name
                    f.sfdc_name
                order by
                    f.month_end
            ) as prior_arr,
            f.ordertype,
            f.product_name,
            f.core_noncore,
            f.direct_indirect,
            f.product_name_group,
            f.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            f.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            f.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            f.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            f.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            f.sfdc_name
        from
            filler f
            left join arr a
                on f.globalultimateparentupper = a.globalultimateparentupper
                and f.source = a.source
                and f.productgroup = a.productgroup
                and f.ship_region = a.ship_region
                and f.naics_sector = a.naics_sector
                and f.month_end = a.date_under_contract
                and f.ordertype = a.ordertype
                and f.product_name = a.product_name
                and f.core_noncore = a.core_noncore
                and f.direct_indirect = a.direct_indirect
                and f.product_name_group = a.product_name_group
                and f.sbitemcategory_calc = a.sbitemcategory_calc

                -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                and f.billing_period = a.billing_period

                -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag

                -- 06/05/2025 [Dan Girard] Added PBT_Group
                and f.pbt_group = a.pbt_group

                -- 11/24/2025 [Dan Girard] Added datasource_group
                and f.datasource_group = a.datasource_group

                -- 05/29/2026 [Dan Girard] Added SFDC_Name
                and f.sfdc_name = a.sfdc_name
    )

    -- cte: qtr_dates
    -- purpose: derive quarter_end dates within contract date window
    ,qtr_dates as
    (
        select 
            max(dd.month_end) as quarter_end
        from
            data_master_db.public.dimdate dd
            cross join waterfall_dates wd
        where
            date_trunc(month, dd.date) between wd.min_date and wd.max_date
        group by
            dd.yearquarternum
    )

    -- cte: qtr_arr
    -- purpose: arr detail filtered to quarter_end dates only
    ,qtr_arr as
    (
        select
            case 
                when a.globalultimateparentupper = '' then '**BLANK**' 
                when a.globalultimateparentupper is null then '**NULL**'
                else a.globalultimateparentupper 
            end as globalultimateparentupper,
            a.source,
            a.productgroup,
            case 
                when coalesce(a.ship_region, '') = '' then 'N/A'
                else a.ship_region
            end as ship_region,
            case 
                when coalesce(a.naics_sector, '') = '' then 'N/A' 
                else a.naics_sector 
            end as naics_sector,
            a.date_under_contract,
            sum(a.acv) as cur_arr,
            case 
                when a.ordertype = 'Renewal' then 'Renewal' 
                else 'License' 
            end as ordertype,
            a.product_name,
            a.core_noncore,
            a.direct_indirect,
            a.product_name_group,
            a.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            -- note: threshold is < 35 here vs <= 33 in arr — verify intentional
            case
                when datediff(day, a.contractitemstartdate, a.contractitemenddate) < 35 then 'Monthly'
                else 'Annual'
            end as billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            case
                when a.sfdc_ent_core_flag is null then 'N/A'
                else a.sfdc_ent_core_flag
            end as sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            a.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            a.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            coalesce(a.sfdc_name, '') as sfdc_name
        from
            finance_db.dev_netsuite.arr_master_waterfall_new a
        where
            a.date_under_contract = dateadd(day, -1, dateadd(quarter, 1, date_trunc(quarter, a.date_under_contract)))
        group by
            all
    )
    
    -- cte: distinct_group
    -- purpose: derive distinct attribute combinations for use in month/quarter fillers
    ,distinct_group_q as
    (
        select distinct 
            qa.globalultimateparentupper,
            qa.source,
            qa.ship_region,
            qa.naics_sector,
            qa.ordertype,
            qa.productgroup,
            qa.product_name,
            qa.core_noncore,
            qa.direct_indirect,
            qa.product_name_group,
            qa.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            qa.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            qa.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            qa.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            qa.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            qa.sfdc_name,
        from 
            qtr_arr qa
    )
    
    -- cte: qtr_filler
    -- purpose: cross join attribute groups to all quarter_end dates to ensure full quarterly series
    ,qtr_filler as
    (
        select
            dg.globalultimateparentupper,
            dg.source,
            dg.productgroup,
            case 
                when dg.ship_region = '' then 'N/A' 
                else dg.ship_region 
            end as ship_region,
            case 
                when dg.naics_sector = '' then 'N/A' 
                else dg.naics_sector 
            end as naics_sector,
            d.quarter_end,
            dg.ordertype,
            dg.product_name,
            dg.core_noncore,
            dg.direct_indirect,
            dg.product_name_group,
            dg.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            dg.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            dg.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            dg.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            dg.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            dg.sfdc_name
        from
            distinct_group_q dg
            cross join qtr_dates d
    )

    -- cte: qtr_detail
    -- purpose: quarterly arr with prior-quarter arr for same attribute grain
    ,qtr_detail as
    (
        select
            'Quarter' as section,
            f.globalultimateparentupper,
            f.source,
            f.productgroup,
            f.ship_region,
            f.naics_sector,
            f.quarter_end as date_under_contract,
            coalesce(a.cur_arr, 0) as cur_arr,
            lag(coalesce(a.cur_arr, 0), 1, 0) over (
                partition by
                    f.globalultimateparentupper,
                    f.source,
                    f.productgroup,
                    f.ship_region,
                    f.naics_sector,
                    f.ordertype,
                    f.product_name,
                    f.core_noncore,
                    f.direct_indirect,
                    f.product_name_group,
                    f.sbitemcategory_calc,

                    -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                    f.billing_period,

                    -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                    f.sfdc_ent_core_flag,

                    -- 06/05/2025 [Dan Girard] Added PBT_Group
                    f.pbt_group,

                    -- 11/24/2025 [Dan Girard] Added datasource_group
                    f.datasource_group,

                    -- 05/29/2026 [Dan Girard] Added SFDC_Name
                    f.sfdc_name
                order by
                    f.quarter_end
            ) as prior_arr,
            f.ordertype,
            f.product_name,
            f.core_noncore,
            f.direct_indirect,
            f.product_name_group,
            f.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            f.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            f.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            f.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            f.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            f.sfdc_name
        from
            qtr_filler f
            left join qtr_arr a
                on f.globalultimateparentupper = a.globalultimateparentupper
                and f.source = a.source
                and f.productgroup = a.productgroup
                and f.ship_region = a.ship_region
                and f.naics_sector = a.naics_sector
                and f.quarter_end = a.date_under_contract
                and f.ordertype = a.ordertype
                and f.product_name = a.product_name
                and f.core_noncore = a.core_noncore
                and f.direct_indirect = a.direct_indirect
                and f.product_name_group = a.product_name_group
                and f.sbitemcategory_calc = a.sbitemcategory_calc

                -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                and f.billing_period = a.billing_period

                -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag

                -- 06/05/2025 [Dan Girard] Added PBT_Group
                and f.pbt_group = a.pbt_group

                -- 11/24/2025 [Dan Girard] Added datasource_group
                and f.datasource_group = a.datasource_group

                -- 05/29/2026 [Dan Girard] Added SFDC_Name
                and f.sfdc_name = a.sfdc_name
    )

    -- cte: qtr_yoy_detail
    -- purpose: quarterly arr with prior-year same-quarter arr for yoy comparison
    ,qtr_yoy_detail as
    (
        select
            'Quarter YoY' as section,
            f.globalultimateparentupper,
            f.source,
            f.productgroup,
            f.ship_region,
            f.naics_sector,
            f.quarter_end AS date_under_contract,
            coalesce(a.cur_arr, 0) as cur_arr,
            lag(coalesce(a.cur_arr, 0), 4, 0) over (
                partition by
                    f.globalultimateparentupper,
                    f.source,
                    f.productgroup,
                    f.ship_region,
                    f.naics_sector,
                    f.ordertype,
                    f.product_name,
                    f.core_noncore,
                    f.direct_indirect,
                    f.product_name_group,
                    f.sbitemcategory_calc,

                    -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                    f.billing_period,

                    -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                    f.sfdc_ent_core_flag,

                    -- 06/05/2025 [Dan Girard] Added PBT_Group
                    f.pbt_group,

                    -- 11/24/2025 [Dan Girard] Added datasource_group
                    f.datasource_group,

                    -- 05/29/2026 [Dan Girard] Added SFDC_Name
                    f.sfdc_name
                order by
                    f.quarter_end
            ) AS prior_arr,
            f.ordertype,
            f.product_name,
            f.core_noncore,
            f.direct_indirect,
            f.product_name_group,
            f.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            f.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            f.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            f.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            f.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            f.sfdc_name
        from
            qtr_filler f
            left join qtr_arr a
                on f.globalultimateparentupper = a.globalultimateparentupper
                                and f.source = a.source 
                                and f.productgroup = a.productgroup 
                		        and f.ship_region = a.ship_region
                                and f.naics_sector = a.naics_sector
                                and f.quarter_end = a.date_under_contract
                                and f.ordertype = a.ordertype
                                and f.product_name = a.product_name
                                and f.core_noncore = a.core_noncore
                                and f.direct_indirect = a.direct_indirect
                                and f.product_name_group = a.product_name_group
                                and f.sbitemcategory_calc = a.sbitemcategory_calc

                -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
                and f.billing_period = a.billing_period

                -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag

                -- 06/05/2025 [Dan Girard] Added PBT_Group
                and f.pbt_group = a.pbt_group

                -- 11/24/2025 [Dan Girard] Added datasource_group
                and f.datasource_group = a.datasource_group

                -- 05/29/2026 [Dan Girard] Added SFDC_Name
                and f.sfdc_name = a.sfdc_name
    )

    -- cte: main
    -- purpose: union all monthly, monthly yoy, quarterly, and quarterly yoy detail into one stream
    ,main as
    (
        select
            a.section,
            a.globalultimateparentupper,
            a.source,
            a.productgroup,
            a.ship_region,
            a.naics_sector,
            a.date_under_contract,
            a.cur_arr,
            a.prior_arr,
            current_timestamp() as ver_date,
            a.ordertype,
            a.product_name,
            a.core_noncore,
            a.direct_indirect,
            a.product_name_group,
            a.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            a.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            a.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            a.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            a.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            a.sfdc_name
        from 
            mth_detail a
        where
            (a.cur_arr <> 0 or a.prior_arr <> 0)
    
        union all
    
        select
            a.section,
            a.globalultimateparentupper,
            a.source,
            a.productgroup,
            a.ship_region,
            a.naics_sector,
            a.date_under_contract,
            a.cur_arr,
            a.prior_arr,
            current_timestamp() as ver_date,
            a.ordertype,
            a.product_name,
            a.core_noncore,
            a.direct_indirect,
            a.product_name_group,
            a.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            a.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            a.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            a.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            a.datasource_group,
            
            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            a.sfdc_name
        from 
            mth_yoy_detail a
        where
            (a.cur_arr <> 0 or a.prior_arr <> 0)
    
        union all
    
        select
            a.section,
            a.globalultimateparentupper,
            a.source,
            a.productgroup,
            a.ship_region,
            a.naics_sector,
            a.date_under_contract,
            a.cur_arr,
            a.prior_arr,
            current_timestamp() as ver_date,
            a.ordertype,
            a.product_name,
            a.core_noncore,
            a.direct_indirect,
            a.product_name_group,
            a.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            a.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            a.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            a.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            a.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            a.sfdc_name
        from 
            qtr_detail a
        where
            (a.cur_arr <> 0 or a.prior_arr <> 0)
    
        union all    
    
        select
            a.section,
            a.globalultimateparentupper,
            a.source,
            a.productgroup,
            a.ship_region,
            a.naics_sector,
            a.date_under_contract,
            a.cur_arr,
            a.prior_arr,
            current_timestamp() as ver_date,
            a.ordertype,
            a.product_name,
            a.core_noncore,
            a.direct_indirect,
            a.product_name_group,
            a.sbitemcategory_calc,

            -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
            a.billing_period,

            -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
            a.sfdc_ent_core_flag,

            -- 06/05/2025 [Dan Girard] Added PBT_Group
            a.pbt_group,

            -- 11/24/2025 [Dan Girard] Added datasource_group
            a.datasource_group,

            -- 05/29/2026 [Dan Girard] Added SFDC_Name
            a.sfdc_name
        from 
            qtr_yoy_detail a
        where
            (a.cur_arr <> 0 or a.prior_arr <> 0)
    ) 

    -- final select
    -- purpose: join to product group map and expose billing_term alias
    select
        m.section,
        m.globalultimateparentupper,
        m.source,
        m.productgroup,
        p.product_group as productgrouprollup,
        m.ship_region,
        m.naics_sector,
        m.date_under_contract,
        m.cur_arr,
        m.prior_arr,
        m.ver_date,
        m.ordertype,
        m.product_name,
        m.core_noncore,
        m.direct_indirect,
        m.product_name_group,
        m.sbitemcategory_calc,

        -- 08/02/2024 [Dan Girard] Add Billing Period (Monthly/Annual) based on contract length
        m.billing_period,

        -- 11/07/2024 [Dan Girard] Added billing_term as a alias for the billing_period
        m.billing_period as billing_term,

        -- 03/25/2025 [Dan Girard] Added Ent/Core Flag
        m.sfdc_ent_core_flag,

        -- 06/05/2025 [Dan Girard] Added PBT_Group
        m.pbt_group,

        -- 11/24/2025 [Dan Girard] Added datasource_group
        m.datasource_group,

        -- 05/29/2026 [Dan Girard] Added SFDC_Name
        m.sfdc_name,
        -- 12/29/2025 [Dan Girard] Added date of first sale and age
        min(case when sum(m.cur_arr) <> 0 then m.date_under_contract end) over (partition by m.globalultimateparentupper, m.source, m.product_name) as dateoffirstsale,
        min(case when sum(m.cur_arr) <> 0 then m.date_under_contract end) over (partition by m.globalultimateparentupper, m.source) as dateoffirstsale_gup,
        min(case when sum(m.cur_arr) <> 0 then m.date_under_contract end) over (partition by m.globalultimateparentupper, m.pbt_group) as dateoffirstsale_pbt,
        datediff(quarter, dateoffirstsale, m.date_under_contract) + 1 as age,
        datediff(quarter, dateoffirstsale_gup, m.date_under_contract) + 1 as age_gup,
        datediff(quarter, dateoffirstsale_pbt, m.date_under_contract) + 1 as age_pbt
    from
        main m
        left join finance_db.public.dim_product_group_map p on upper(m.productgroup) = upper(p.product_name)
    group by
        all
      ;

    return 'Successfully created or replaced table finance_db.dev_netsuite.arr_master_retention_new.';

end;
$$
;

-- select * from finance_db.dev_netsuite.arr_master_retention_new;