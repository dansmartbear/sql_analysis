/**********************************************************************

Name:       qry_arr_master_waterfall_prior_acv
Type:       Standalone executable query (not yet a table/view)
Created:    08/12/2026 [Dan Girard]
Purpose:    Row-level companion to arr_master_waterfall_new that adds a
            "prior_acv" column - the matched prior-month acv for each
            row's dimension combination. Unlike arr_master_retention_new,
            which pre-aggregates to a fixed ~13-column grain, this keeps
            full row-level detail (including key/invoiceno/dates/
            datasource) so any downstream query can group by an
            arbitrary subset of dimensions and get correct
            sum(acv) / sum(prior_acv) at that grain.

Source:     finance_db.dev_netsuite.arr_master_waterfall_new
            data_master_db.public.dimdate

Match grain (linked dimensions - must match identically to the prior
month for a match):
            globalultimateparentupper, ordertype, source, productgroup,
            productgroup_child, product_group_rollup, ship_region,
            naics_sector, direct_ecomm_flag, product_for_reporting_ns,
            product_for_reporting_group_ns, product_for_reporting_ns_alias,
            product_for_reporting_ns_alias_combined, product_name,
            core_noncore, direct_indirect, product_name_group,
            sbitemcategory_calc, sfdc_ent_core_flag, billing_term,
            pbt_group, sfdc_name

Excluded from match (invoice-level / datasource / system fields -
carried through as row attributes only, not used to find the prior
month's match):
            datasource, datasource_group, key, invoice_date, invoiceno,
            contractitemstartdate, contractitemenddate, ver_date

            -- 08/12/2026 [Dan Girard] invoiceno was not explicitly named
            in the original ask (which called out key, invoice date,
            contract start/end) but is clearly invoice-level like key -
            included here on that basis. Confirm/correct if that's wrong.

            month_start/month_end are excluded from the match grain too
            - they are fully determined by date_under_contract (the
            month axis itself), not independent dimensions.

Design notes:
            - Null/blank dimension values are normalized to '' before
              matching (norm cte) so a null-vs-null join doesn't silently
              fail to match, mirroring the null-guard already used for
              globalultimateparentupper in arr_master_retention_new.
            - Duplicate rows within one match-group+month (e.g. two
              invoices same customer/product/month) each get a
              proportional share of that group's matched prior-month
              acv, based on their share of the group's current acv.
              This keeps sum(prior_acv) correct at any grouping level,
              including the full grain itself.
            - Fully churned combos (acv last month, none this month)
              get a placeholder row - cur acv = 0, invoice-level columns
              null, prior_acv = the full matched amount - so churn is
              visible through this field instead of being dropped.
            - A full month-by-combo scaffold (cross join of every
              distinct dimension combo against every month in the
              waterfall's date range) is required so lag() reflects a
              true calendar prior month rather than the prior *active*
              month. This is heavier than retention's scaffold since it
              runs against ~22 dimensions instead of ~13 - expect a
              large intermediate row count on a table with wide
              dimension cardinality.

***********************************************************************/

with

-- raw pass-through of waterfall detail - no calculations, no joins
base as
(
    select
        w.date_under_contract,
        w.datasource,
        w.key,
        w.invoice_date,
        w.invoiceno,
        w.globalultimateparentupper,
        w.ordertype,
        w.contractitemstartdate,
        w.contractitemenddate,
        w.source,
        w.productgroup,
        w.productgroup_child,
        w.product_group_rollup,
        w.acv,
        w.ship_region,
        w.naics_sector,
        w.direct_ecomm_flag,
        w.product_for_reporting_ns,
        w.product_for_reporting_group_ns,
        w.product_for_reporting_ns_alias,
        w.product_for_reporting_ns_alias_combined,
        w.product_name,
        w.core_noncore,
        w.direct_indirect,
        w.product_name_group,
        w.month_start,
        w.month_end,
        w.sbitemcategory_calc,
        w.sfdc_ent_core_flag,
        w.billing_term,
        w.pbt_group,
        w.datasource_group,
        w.sfdc_name
    from
        finance_db.dev_netsuite.arr_master_waterfall_new w
)

-- normalize the match-grain dimensions so a null on either side of a
-- later join condition doesn't silently fail to match
,norm as
(
    select
        b.date_under_contract,
        b.datasource,
        b.key,
        b.invoice_date,
        b.invoiceno,
        b.contractitemstartdate,
        b.contractitemenddate,
        b.acv,
        b.month_start,
        b.month_end,
        b.datasource_group,
        coalesce(b.globalultimateparentupper, '') as globalultimateparentupper,
        coalesce(b.ordertype, '') as ordertype,
        coalesce(b.source, '') as source,
        coalesce(b.productgroup, '') as productgroup,
        coalesce(b.productgroup_child, '') as productgroup_child,
        coalesce(b.product_group_rollup, '') as product_group_rollup,
        coalesce(b.ship_region, '') as ship_region,
        coalesce(b.naics_sector, '') as naics_sector,
        coalesce(b.direct_ecomm_flag, '') as direct_ecomm_flag,
        coalesce(b.product_for_reporting_ns, '') as product_for_reporting_ns,
        coalesce(b.product_for_reporting_group_ns, '') as product_for_reporting_group_ns,
        coalesce(b.product_for_reporting_ns_alias, '') as product_for_reporting_ns_alias,
        coalesce(b.product_for_reporting_ns_alias_combined, '') as product_for_reporting_ns_alias_combined,
        coalesce(b.product_name, '') as product_name,
        coalesce(b.core_noncore, '') as core_noncore,
        coalesce(b.direct_indirect, '') as direct_indirect,
        coalesce(b.product_name_group, '') as product_name_group,
        coalesce(b.sbitemcategory_calc, '') as sbitemcategory_calc,
        coalesce(b.sfdc_ent_core_flag, '') as sfdc_ent_core_flag,
        coalesce(b.billing_term, '') as billing_term,
        coalesce(b.pbt_group, '') as pbt_group,
        coalesce(b.sfdc_name, '') as sfdc_name
    from
        base b
)

-- sum acv to the full match grain - one row per dimension combo per month
,match_group as
(
    select
        n.globalultimateparentupper,
        n.ordertype,
        n.source,
        n.productgroup,
        n.productgroup_child,
        n.product_group_rollup,
        n.ship_region,
        n.naics_sector,
        n.direct_ecomm_flag,
        n.product_for_reporting_ns,
        n.product_for_reporting_group_ns,
        n.product_for_reporting_ns_alias,
        n.product_for_reporting_ns_alias_combined,
        n.product_name,
        n.core_noncore,
        n.direct_indirect,
        n.product_name_group,
        n.sbitemcategory_calc,
        n.sfdc_ent_core_flag,
        n.billing_term,
        n.pbt_group,
        n.sfdc_name,
        n.date_under_contract,
        sum(n.acv) as group_acv
    from
        norm n
    group by
        all
)

-- distinct dimension combos across all history - drives the month scaffold
,distinct_combo as
(
    select distinct
        mg.globalultimateparentupper,
        mg.ordertype,
        mg.source,
        mg.productgroup,
        mg.productgroup_child,
        mg.product_group_rollup,
        mg.ship_region,
        mg.naics_sector,
        mg.direct_ecomm_flag,
        mg.product_for_reporting_ns,
        mg.product_for_reporting_group_ns,
        mg.product_for_reporting_ns_alias,
        mg.product_for_reporting_ns_alias_combined,
        mg.product_name,
        mg.core_noncore,
        mg.direct_indirect,
        mg.product_name_group,
        mg.sbitemcategory_calc,
        mg.sfdc_ent_core_flag,
        mg.billing_term,
        mg.pbt_group,
        mg.sfdc_name
    from
        match_group mg
)

-- date bounds across the whole waterfall - keeps the scaffold from running past actual data
,waterfall_dates as
(
    select
        min(mg.date_under_contract) as min_date,
        max(mg.date_under_contract) as max_date
    from
        match_group mg
)

-- distinct month_end series spanning the waterfall's date range
,month_dates as
(
    select distinct
        dd.month_end as date_under_contract
    from
        data_master_db.public.dimdate dd
        cross join waterfall_dates wd
    where
        dd.month_end between wd.min_date and wd.max_date
)

-- every distinct dimension combo x every month in range - gives lag() a true calendar prior month instead of the prior active month
,scaffold as
(
    select
        dc.globalultimateparentupper,
        dc.ordertype,
        dc.source,
        dc.productgroup,
        dc.productgroup_child,
        dc.product_group_rollup,
        dc.ship_region,
        dc.naics_sector,
        dc.direct_ecomm_flag,
        dc.product_for_reporting_ns,
        dc.product_for_reporting_group_ns,
        dc.product_for_reporting_ns_alias,
        dc.product_for_reporting_ns_alias_combined,
        dc.product_name,
        dc.core_noncore,
        dc.direct_indirect,
        dc.product_name_group,
        dc.sbitemcategory_calc,
        dc.sfdc_ent_core_flag,
        dc.billing_term,
        dc.pbt_group,
        dc.sfdc_name,
        md.date_under_contract
    from
        distinct_combo dc
        cross join month_dates md
)

-- scaffold filled with actual group acv (0 where no activity that month), plus the true calendar prior-month acv via lag() over the now-continuous series
,group_arr as
(
    select
        sc.globalultimateparentupper,
        sc.ordertype,
        sc.source,
        sc.productgroup,
        sc.productgroup_child,
        sc.product_group_rollup,
        sc.ship_region,
        sc.naics_sector,
        sc.direct_ecomm_flag,
        sc.product_for_reporting_ns,
        sc.product_for_reporting_group_ns,
        sc.product_for_reporting_ns_alias,
        sc.product_for_reporting_ns_alias_combined,
        sc.product_name,
        sc.core_noncore,
        sc.direct_indirect,
        sc.product_name_group,
        sc.sbitemcategory_calc,
        sc.sfdc_ent_core_flag,
        sc.billing_term,
        sc.pbt_group,
        sc.sfdc_name,
        sc.date_under_contract,
        coalesce(mg.group_acv, 0) as group_cur_acv,
        lag(coalesce(mg.group_acv, 0), 1, 0) over (
            partition by
                sc.globalultimateparentupper,
                sc.ordertype,
                sc.source,
                sc.productgroup,
                sc.productgroup_child,
                sc.product_group_rollup,
                sc.ship_region,
                sc.naics_sector,
                sc.direct_ecomm_flag,
                sc.product_for_reporting_ns,
                sc.product_for_reporting_group_ns,
                sc.product_for_reporting_ns_alias,
                sc.product_for_reporting_ns_alias_combined,
                sc.product_name,
                sc.core_noncore,
                sc.direct_indirect,
                sc.product_name_group,
                sc.sbitemcategory_calc,
                sc.sfdc_ent_core_flag,
                sc.billing_term,
                sc.pbt_group,
                sc.sfdc_name
            order by
                sc.date_under_contract
        ) as group_prior_acv
    from
        scaffold sc
        left join match_group mg
            on sc.globalultimateparentupper = mg.globalultimateparentupper
            and sc.ordertype = mg.ordertype
            and sc.source = mg.source
            and sc.productgroup = mg.productgroup
            and sc.productgroup_child = mg.productgroup_child
            and sc.product_group_rollup = mg.product_group_rollup
            and sc.ship_region = mg.ship_region
            and sc.naics_sector = mg.naics_sector
            and sc.direct_ecomm_flag = mg.direct_ecomm_flag
            and sc.product_for_reporting_ns = mg.product_for_reporting_ns
            and sc.product_for_reporting_group_ns = mg.product_for_reporting_group_ns
            and sc.product_for_reporting_ns_alias = mg.product_for_reporting_ns_alias
            and sc.product_for_reporting_ns_alias_combined = mg.product_for_reporting_ns_alias_combined
            and sc.product_name = mg.product_name
            and sc.core_noncore = mg.core_noncore
            and sc.direct_indirect = mg.direct_indirect
            and sc.product_name_group = mg.product_name_group
            and sc.sbitemcategory_calc = mg.sbitemcategory_calc
            and sc.sfdc_ent_core_flag = mg.sfdc_ent_core_flag
            and sc.billing_term = mg.billing_term
            and sc.pbt_group = mg.pbt_group
            and sc.sfdc_name = mg.sfdc_name
            and sc.date_under_contract = mg.date_under_contract
)

-- real invoice-level rows - prior_acv allocated proportionally by this row's share of its match group's current acv
,detail_with_prior as
(
    select
        b.date_under_contract,
        b.datasource,
        b.key,
        b.invoice_date,
        b.invoiceno,
        b.globalultimateparentupper,
        b.ordertype,
        b.contractitemstartdate,
        b.contractitemenddate,
        b.source,
        b.productgroup,
        b.productgroup_child,
        b.product_group_rollup,
        b.acv,
        -- 08/12/2026 [Dan Girard] proportional split keeps sum(prior_acv) correct at any grouping grain when duplicate rows share a match group
        case
            when ga.group_cur_acv = 0 then 0
            else b.acv / ga.group_cur_acv * ga.group_prior_acv
        end as prior_acv,
        b.ship_region,
        b.naics_sector,
        b.direct_ecomm_flag,
        b.product_for_reporting_ns,
        b.product_for_reporting_group_ns,
        b.product_for_reporting_ns_alias,
        b.product_for_reporting_ns_alias_combined,
        b.product_name,
        b.core_noncore,
        b.direct_indirect,
        b.product_name_group,
        b.month_start,
        b.month_end,
        b.sbitemcategory_calc,
        b.sfdc_ent_core_flag,
        b.billing_term,
        b.pbt_group,
        b.datasource_group,
        b.sfdc_name
    from
        base b
        inner join norm n
            on b.date_under_contract = n.date_under_contract
            and b.key = n.key
            and b.invoiceno = n.invoiceno
        inner join group_arr ga
            on n.globalultimateparentupper = ga.globalultimateparentupper
            and n.ordertype = ga.ordertype
            and n.source = ga.source
            and n.productgroup = ga.productgroup
            and n.productgroup_child = ga.productgroup_child
            and n.product_group_rollup = ga.product_group_rollup
            and n.ship_region = ga.ship_region
            and n.naics_sector = ga.naics_sector
            and n.direct_ecomm_flag = ga.direct_ecomm_flag
            and n.product_for_reporting_ns = ga.product_for_reporting_ns
            and n.product_for_reporting_group_ns = ga.product_for_reporting_group_ns
            and n.product_for_reporting_ns_alias = ga.product_for_reporting_ns_alias
            and n.product_for_reporting_ns_alias_combined = ga.product_for_reporting_ns_alias_combined
            and n.product_name = ga.product_name
            and n.core_noncore = ga.core_noncore
            and n.direct_indirect = ga.direct_indirect
            and n.product_name_group = ga.product_name_group
            and n.sbitemcategory_calc = ga.sbitemcategory_calc
            and n.sfdc_ent_core_flag = ga.sfdc_ent_core_flag
            and n.billing_term = ga.billing_term
            and n.pbt_group = ga.pbt_group
            and n.sfdc_name = ga.sfdc_name
            and n.date_under_contract = ga.date_under_contract
)

-- match-group/month combos with prior-month acv but nothing this month - carries the churned amount so it isn't lost when summing prior_acv
,churn_placeholders as
(
    select
        ga.date_under_contract,
        null as datasource,
        null as key,
        null as invoice_date,
        null as invoiceno,
        ga.globalultimateparentupper,
        ga.ordertype,
        null as contractitemstartdate,
        null as contractitemenddate,
        ga.source,
        ga.productgroup,
        ga.productgroup_child,
        ga.product_group_rollup,
        0 as acv,
        ga.group_prior_acv as prior_acv,
        ga.ship_region,
        ga.naics_sector,
        ga.direct_ecomm_flag,
        ga.product_for_reporting_ns,
        ga.product_for_reporting_group_ns,
        ga.product_for_reporting_ns_alias,
        ga.product_for_reporting_ns_alias_combined,
        ga.product_name,
        ga.core_noncore,
        ga.direct_indirect,
        ga.product_name_group,
        date_trunc(month, ga.date_under_contract) as month_start,
        ga.date_under_contract as month_end,
        ga.sbitemcategory_calc,
        ga.sfdc_ent_core_flag,
        ga.billing_term,
        ga.pbt_group,
        null as datasource_group,
        ga.sfdc_name
    from
        group_arr ga
    where
        ga.group_cur_acv = 0
        and ga.group_prior_acv <> 0
)

-- union real detail rows with churn placeholders into one additive row-level stream
select
    d.date_under_contract,
    d.datasource,
    d.key,
    d.invoice_date,
    d.invoiceno,
    d.globalultimateparentupper,
    d.ordertype,
    d.contractitemstartdate,
    d.contractitemenddate,
    d.source,
    d.productgroup,
    d.productgroup_child,
    d.product_group_rollup,
    d.acv,
    d.prior_acv,
    d.ship_region,
    d.naics_sector,
    d.direct_ecomm_flag,
    d.product_for_reporting_ns,
    d.product_for_reporting_group_ns,
    d.product_for_reporting_ns_alias,
    d.product_for_reporting_ns_alias_combined,
    d.product_name,
    d.core_noncore,
    d.direct_indirect,
    d.product_name_group,
    d.month_start,
    d.month_end,
    d.sbitemcategory_calc,
    d.sfdc_ent_core_flag,
    d.billing_term,
    d.pbt_group,
    d.datasource_group,
    d.sfdc_name,
    current_timestamp() as ver_date
from
    detail_with_prior d

union all

select
    c.date_under_contract,
    c.datasource,
    c.key,
    c.invoice_date,
    c.invoiceno,
    c.globalultimateparentupper,
    c.ordertype,
    c.contractitemstartdate,
    c.contractitemenddate,
    c.source,
    c.productgroup,
    c.productgroup_child,
    c.product_group_rollup,
    c.acv,
    c.prior_acv,
    c.ship_region,
    c.naics_sector,
    c.direct_ecomm_flag,
    c.product_for_reporting_ns,
    c.product_for_reporting_group_ns,
    c.product_for_reporting_ns_alias,
    c.product_for_reporting_ns_alias_combined,
    c.product_name,
    c.core_noncore,
    c.direct_indirect,
    c.product_name_group,
    c.month_start,
    c.month_end,
    c.sbitemcategory_calc,
    c.sfdc_ent_core_flag,
    c.billing_term,
    c.pbt_group,
    c.datasource_group,
    c.sfdc_name,
    current_timestamp() as ver_date
from
    churn_placeholders c
;

-- usage example - Dan's DUC + GUP scenario, sum acv and prior_acv:
-- select
--     r.date_under_contract,
--     r.globalultimateparentupper,
--     sum(r.acv) as acv,
--     sum(r.prior_acv) as prior_acv
-- from
--     (<the query above>) r
-- group by
--     all
-- ;

-- add product_name to break it out further:
-- select
--     r.date_under_contract,
--     r.globalultimateparentupper,
--     r.product_name,
--     sum(r.acv) as acv,
--     sum(r.prior_acv) as prior_acv
-- from
--     (<the query above>) r
-- group by
--     all
-- ;
