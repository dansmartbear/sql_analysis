create or replace procedure finance_db.dev_netsuite.sp_arr_master_retention_new()
    returns varchar
    language sql
    execute as owner
as
$$
begin

    -- table: finance_db.dev_netsuite.arr_master_retention_new
    --
    -- purpose:
    --   build arr_master_retention_new with monthly, quarterly, and year-over-year arr views
    --   enable retention analysis by customer, product, and various attributes
    --
    -- target table:
    --   finance_db.dev_netsuite.arr_master_retention_new
    --
    -- primary source tables:
    --   finance_db.dev_netsuite.arr_master_waterfall
    --   data_master_db.public.dimdate
    --   finance_db.public.dim_product_group_map
    --
    -- grain:
    --   one row per section (month, month yoy, quarter, quarter yoy)
    --   per customer / source / productgroup / ship_region / naics_sector / product / attributes / date_under_contract
    --
    -- updated:
    --   2025-11-24 [Dan Girard]: added datasource_group attributes across all views
    --   2025-06-05 [Dan Girard]: added pbt_group attributes across all views
    --   2025-03-25 [Dan Girard]: added sfdc_ent_core_flag (ent/core flag)
    --   2024-11-07 [Dan Girard]: added billing_term alias for billing_period in final output
    --   2024-08-02 [Dan Girard]: added billing_period (monthly/annual) based on contract length
    --   12/29/2025 [Dan Girard]: added date of first sale and age

    create or replace table finance_db.dev_netsuite.arr_master_retention_new copy grants as

    with
    waterfall_dates as
    (
        select
            min(wf.date_under_contract) as min_date,
            max(wf.date_under_contract) as max_date
        from
            finance_db.dev_netsuite.arr_master_waterfall wf
    ),

    dates as
    (
        select distinct
            dd.month_end
        from
            data_master_db.public.dimdate dd
            cross join waterfall_dates wd
        where
            date_trunc(month, dd.date) between wd.min_date and wd.max_date
    ),

    arr as
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
            finance_db.dev_netsuite.arr_master_waterfall a
        group by
            all
    ),

    distinct_group as
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
            ar.billing_period,
            ar.sfdc_ent_core_flag,
            ar.pbt_group,
            ar.datasource_group,
            ar.sfdc_name
        from
            arr ar
    ),

    filler as
    (
        select
            dg.globalultimateparentupper,
            dg.source,
            dg.productgroup,
            dg.ship_region,
            dg.naics_sector,
            d.month_end,
            dg.ordertype,
            dg.product_name,
            dg.core_noncore,
            dg.direct_indirect,
            dg.product_name_group,
            dg.sbitemcategory_calc,
            dg.billing_period,
            dg.sfdc_ent_core_flag,
            dg.pbt_group,
            dg.datasource_group,
            dg.sfdc_name
        from
            distinct_group dg
            cross join dates d
    ),

    mth_detail as
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
                    f.billing_period,
                    f.sfdc_ent_core_flag,
                    f.pbt_group,
                    f.datasource_group,
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
            f.billing_period,
            f.sfdc_ent_core_flag,
            f.pbt_group,
            f.datasource_group,
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
                and f.billing_period = a.billing_period
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag
                and f.pbt_group = a.pbt_group
                and f.datasource_group = a.datasource_group
                and f.sfdc_name = a.sfdc_name
    ),

    mth_yoy_detail as
    (
        select
            'Month YoY' as section,
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
                    f.billing_period,
                    f.sfdc_ent_core_flag,
                    f.pbt_group,
                    f.datasource_group,
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
            f.billing_period,
            f.sfdc_ent_core_flag,
            f.pbt_group,
            f.datasource_group,
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
                and f.billing_period = a.billing_period
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag
                and f.pbt_group = a.pbt_group
                and f.datasource_group = a.datasource_group
                and f.sfdc_name = a.sfdc_name
    ),

    qtr_dates as
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
    ),

    qtr_arr as
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
            finance_db.dev_netsuite.arr_master_waterfall a
        where
            a.date_under_contract = dateadd(day, -1, dateadd(quarter, 1, date_trunc(quarter, a.date_under_contract)))
        group by
            all
    ),

    distinct_group_q as
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
            qa.billing_period,
            qa.sfdc_ent_core_flag,
            qa.pbt_group,
            qa.datasource_group,
            qa.sfdc_name
        from
            qtr_arr qa
    ),

    qtr_filler as
    (
        select
            dg.globalultimateparentupper,
            dg.source,
            dg.productgroup,
            dg.ship_region,
            dg.naics_sector,
            d.quarter_end,
            dg.ordertype,
            dg.product_name,
            dg.core_noncore,
            dg.direct_indirect,
            dg.product_name_group,
            dg.sbitemcategory_calc,
            dg.billing_period,
            dg.sfdc_ent_core_flag,
            dg.pbt_group,
            dg.datasource_group,
            dg.sfdc_name
        from
            distinct_group_q dg
            cross join qtr_dates d
    ),

    qtr_detail as
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
                    f.billing_period,
                    f.sfdc_ent_core_flag,
                    f.pbt_group,
                    f.datasource_group,
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
            f.billing_period,
            f.sfdc_ent_core_flag,
            f.pbt_group,
            f.datasource_group,
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
                and f.billing_period = a.billing_period
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag
                and f.pbt_group = a.pbt_group
                and f.datasource_group = a.datasource_group
                and f.sfdc_name = a.sfdc_name
    ),

    qtr_yoy_detail as
    (
        select
            'Quarter YoY' as section,
            f.globalultimateparentupper,
            f.source,
            f.productgroup,
            f.ship_region,
            f.naics_sector,
            f.quarter_end as date_under_contract,
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
                    f.billing_period,
                    f.sfdc_ent_core_flag,
                    f.pbt_group,
                    f.datasource_group,
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
            f.billing_period,
            f.sfdc_ent_core_flag,
            f.pbt_group,
            f.datasource_group,
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
                and f.billing_period = a.billing_period
                and f.sfdc_ent_core_flag = a.sfdc_ent_core_flag
                and f.pbt_group = a.pbt_group
                and f.datasource_group = a.datasource_group
                and f.sfdc_name = a.sfdc_name
    ),

    main as
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
            a.billing_period,
            a.sfdc_ent_core_flag,
            a.pbt_group,
            a.datasource_group,
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
            a.billing_period,
            a.sfdc_ent_core_flag,
            a.pbt_group,
            a.datasource_group,
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
            a.billing_period,
            a.sfdc_ent_core_flag,
            a.pbt_group,
            a.datasource_group,
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
            a.billing_period,
            a.sfdc_ent_core_flag,
            a.pbt_group,
            a.datasource_group,
            a.sfdc_name
        from
            qtr_yoy_detail a
        where
            (a.cur_arr <> 0 or a.prior_arr <> 0)
    )

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
        m.billing_period,
        -- 11/07/2024 [Dan Girard] Added billing_term as alias for billing_period
        m.billing_period as billing_term,
        m.sfdc_ent_core_flag,
        m.pbt_group,
        m.datasource_group,
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