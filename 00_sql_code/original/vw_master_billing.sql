create or replace view finance_db.public.vw_master_billing copy grants
comment='Use this instead of the direct table reference.

Created 05/24/2023 [Dan Girard]
Updated 10/04/2023 [Dan Girard] Added , mb.product_for_reporting_ns_alias and , mb.product_for_reporting_ns_alias_combined
Updated 01/30/2024 [Dan Girard] Added salesperson_location
Updated 02/15/2024 [Dan Girard] Added sfdc_closedate
Updated 05/20/2024 [Dan Girard] Added status_inq_pull
Updated 09/10/2024 [Dan Girard] Added bill to and ship to info
Updated 09/11/2024 [Dan Girard] Added sfdc_deal_reg
Updated 12/04/2024 [Dan Girard] Added ACV_FC (ACV based on AMOUNTFOREIGNCURRENCY)
Updated 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
Updated 05/13/2025 [Dan Girard] Added SFDC_LINE_ITEM_OWNER_ROLE, ACCOUNT NAME and AVERAGERATE
Updated 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
Updated 05/28/2025 [Dan Girard] Added TRANSEXTERNALID
Updated 05/30/2025 [Dan Girard] Added PBT Group
Updated 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
Updated 03/30/2026 [Dan Girard] Added unique row number id to final output
Updated 06/19/2026 [Dan Girard] Added Entity
'
as

-- 02/21/2025 [Dan Girard] Scaffold the dates for the current year (for future months only)
with date_scaff as
(
    select
        date_trunc('month', dateadd(month, seq4() + 1, current_date)) as date,
    from
        table(generator(rowcount => 12))
    where
        date_trunc('year', dateadd(month, seq4() + 1, current_date)) = date_trunc('year', current_date)
)
-- 02/21/2025 [Dan Girard] Scaffold the main connection points to the Scenario data
,scaffold as
(
    select distinct 
        ds.date,
        mb.direct_ecomm_flag,
        mb.product_for_reporting_ns,
        mb.product_for_reporting_group_ns,
        mb.product_for_reporting_ns_alias,
        mb.product_for_reporting_ns_alias_combined,
        mb.product_name,
        mb.product_name_group,
        mb.direct_indirect,
        mb.core_noncore,
        mb.order_type_final,
        mb.billing_term,
        mb.core_ent_flag,
        mb.sisense_product_rollup,
        mb.new_expansion,

        -- 01/23/2026 [Dan Girard] Added stream_reporting
        mb.stream_reporting,
    from
        finance_db.public.master_billing mb
        full outer join date_scaff ds on 1=1
        --full outer join (select 'Ent' core_ent_flag union all select 'Core' core_ent_flag) on 1=1
    where
        not mb.direct_ecomm_flag is null
        and not mb.product_for_reporting_ns is null
        and not mb.product_for_reporting_group_ns is null
        and not mb.product_for_reporting_ns_alias is null
        and not mb.product_for_reporting_ns_alias_combined is null
        and not mb.product_name is null
        and not mb.product_name_group is null
        and not mb.direct_indirect is null
        and not mb.core_noncore is null
        and not mb.order_type_final is null
        and not mb.billing_term is null
        and not mb.core_ent_flag is null
        and not mb.sisense_product_rollup is null
        and not mb.new_expansion is null

         -- 01/23/2026 [Dan Girard] Added stream_reporting
        and not mb.stream_reporting is null
),
-- Updated 05/30/2025 [Dan Girard] Added new combined CTE
combined as
(
    select
        mb.reporting_status,
        mb.ver_date,
        mb.customercategory,
        mb.date,

        case when coalesce(mb.invoiceno,'') = '' then concat('MB',mb.date,mb.lineid,mb.sisense_product_rollup,mb.amount_usd) //concat('UID','-',uuid_string())
            else mb.invoiceno
            end invoiceno,
        
        mb.name,
        mb.item,
        mb.lineid,
        mb.salesdescription,
        mb.description,
        mb.sfdctype,
        mb.quantity,
        mb.documentnumber,
        mb.amount_usd,
        mb.amount,
        mb.currency,
        mb.amountforeigncurrency,
        mb.contractitemstartdate,
        mb.contractitemenddate,
        mb.type,
        mb.itemcategoryhidden,
        mb.sbitemcategory1,

        -- 01/27/2026 [Dan Girard] Removed externalid
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        null externalid,
        
        mb.product,
        mb.ordertype1,
        mb.duns,
        mb.customersite,
        mb.globalultimateparent,
        mb.sisense_product_rollup,
        mb.bill_country,
        mb.bill_state,
        mb.bill_city,
        mb.ship_country,
        mb.ship_state,
        mb.ship_city,
        mb.incomeaccountname,
        mb.contract_length,
        mb.acv,
        mb.my,
        mb.product_for_reporting,
        mb.product_group,
        mb.order_type_final,
        mb.reporting_channel,
        mb.recurring_status,
        mb.stream_revenue,
        mb.stream_reporting,
        mb.atlassian_hosting,
        mb.shipped_subregion,
        mb.shipped_region,
        mb.year,
        mb.annualized_acv,
        mb.status,
        
        -- 05/20/2024 [Dan Girard] Added status_inq_pull
        mb.status_inq_pull,
        
        mb.deal_count,
        mb.pull_in,
        mb.one_year_or_less,
        mb.greater_than_2_years,
        mb.one_to_two_years,
        mb.one_year_more_or_less,
        mb.external_id_present,
        mb.monthly_arr,
        mb.multiyear_flag,
        mb.quarter_end,
        mb.close_quarter,
        mb.term,
        mb.cap,
        mb.overage,
        mb.difference,
        mb.pullin_dis,
        mb.invoice_amount,
        mb.tier,
        mb.inline_discount,
        mb.list_price,
        mb.discount,
        mb.ship_region,
        mb.naics_sector,
    
        -- 9/28/2023 [Dan Girard] Added direct_ecomm_flag, product_for_reporting_ns, and product_for_reporting_group_ns
        mb.direct_ecomm_flag,
        mb.product_for_reporting_ns,
        mb.product_for_reporting_group_ns,
    
        -- 10/4/2023 [Dan Girard] Added product_for_reporting_ns_alias, product_for_reporting_ns_alias_combined
        mb.product_for_reporting_ns_alias,
        mb.product_for_reporting_ns_alias_combined,
    
        -- 1/3/2024 [Dan Girard] Add additional product dimensions
        mb.product_name,
        mb.product_name_group,
        mb.direct_indirect,
        mb.core_noncore,
    
        -- 1/30/2024 [Dan Girard] Added salesperson_location
        mb.salesperson_location,
    
        -- 2/15/2024 [Dan Girard] Added sfdc_closedate
        mb.sfdc_closedate,
    
        -- 09/10/2024 [Dan Girard] Added Bill To and Ship To info
        mb.bill_to_company,
        
        -- 01/27/2026 [Dan Girard] Removed bill_to_name
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        mb.bill_to_name,
        mb.bill_to_address1,
        mb.bill_to_address2,
        mb.bill_to_address3,
        mb.ship_to_company,
        
        -- 01/27/2026 [Dan Girard] Removed ship_to_name
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        mb.ship_to_name,
        mb.ship_to_address1,
        mb.ship_to_address2,
        mb.ship_to_address3,
    
        -- 09/11/2024 [Dan Girard] Added sfdc_deal_reg
        mb.sfdc_deal_reg,
    
        -- 10/23/2024 [Dan Girard] Added date_of_first_sale
        mb.date_of_first_sale,
    
        -- 11/07/2024 [Dan Girard] Added billing_term
        mb.billing_term,
    
        -- 12/04/2024 [Dan Girard] Added ACV_FC (ACV based on AMOUNTFOREIGNCURRENCY)
        mb.acv_fc,
    
        -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
        case when mb.direct_ecomm_flag = 'Ecomm' then 'Ecomm'
            when mb.core_ent_flag is null then 'Core'
            else core_ent_flag
            end core_ent_flag,
    
        -- 05/13/2025 [Dan Girard] Added sfdc_line_item_owner_role, account name and averagerate
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        null sfdc_line_item_owner_role, 
        sfdc_account_name,
        averagerate,
    
        -- 05/28/2025 [Dan Giard] Added TRANSEXTERNALID
        mb.transexternalid,

        -- 08/07/2025 [Dan Girard] Added SALESPERSON
        mb.salesperson,

        -- 08/20/2025 [Dan Girard] Added new/expansion/renewal type
        mb.new_expansion,

        -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
        mb.stripe_user_id,
        mb.braintree_user_id,

        -- 01/16/2026 [Dan Girard] Added new logic
        case 
          when mb.contract_length = 0 then 0 
          else (mb.amountforeigncurrency / mb.contract_length) * 365 
          end annualized_fc_acv,

        -- 06/18/2026 [Dan Girard] Added Entity
        mb.entity,

        -- 07/06/2026 [Dan Girard] Added TRANSACTION_ID and BOOMI_EXTERNAL_ID,
        mb.transaction_id,
        mb.boomi_external_id
    from
        finance_db.public.master_billing mb
        
    -- 02/21/2025 [Dan Girard] Union the scaffold data
    union all
    
    select
        null reporting_status,
        null ver_date,
        null customercategory,
        
        date,
        
        null invoiceno,
        null name,
        null item,
        null lineid,
        null salesdescription,
        null description,
        null sfdctype,
        null quantity,
        null documentnumber,
        null amount_usd,
        null amount,
        null currency,
        null amountforeigncurrency,
        null contractitemstartdate,
        null contractitemenddate,
        null type,
        null itemcategoryhidden,
        null sbitemcategory1,
        
        -- 01/27/2026 [Dan Girard] Removed externalid
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        null externalid,
        
        null product,
        null ordertype1,
        null duns,
        null customersite,
        null globalultimateparent,
        sisense_product_rollup,
        null bill_country,
        null bill_state,
        null bill_city,
        null ship_country,
        null ship_state,
        null ship_city,
        null incomeaccountname,
        null contract_length,
        null acv,
        null my,
        null product_for_reporting,
        null product_group,
        order_type_final,
        null reporting_channel,
        null recurring_status,
        null stream_revenue,
        null stream_reporting,
        null atlassian_hosting,
        null shipped_subregion,
        null shipped_region,
        year(current_date()) year,
        null annualized_acv,
        null status,
        null status_inq_pull,
        null deal_count,
        null pull_in,
        null one_year_or_less,
        null greater_than_2_years,
        null one_to_two_years,
        null one_year_more_or_less,
        null external_id_present,
        null monthly_arr,
        null multiyear_flag,
        null quarter_end,
        null close_quarter,
        null term,
        null cap,
        null overage,
        null difference,
        null pullin_dis,
        null invoice_amount,
        null tier,
        null inline_discount,
        null list_price,
        null discount,
        null ship_region,
        null naics_sector,
        direct_ecomm_flag,
        product_for_reporting_ns,
        product_for_reporting_group_ns,
        product_for_reporting_ns_alias,
        product_for_reporting_ns_alias_combined,
        product_name,
        product_name_group,
        direct_indirect,
        core_noncore,
        null salesperson_location,
        null sfdc_closedate,
        null bill_to_company,
        
        -- 01/27/2026 [Dan Girard] Removed bill_to_name
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        null bill_to_name,
        
        null bill_to_address1,
        null bill_to_address2,
        null bill_to_address3,
        null ship_to_company,
        
        -- 01/27/2026 [Dan Girard] Removed ship_to_name
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        null ship_to_name,
        
        null ship_to_address1,
        null ship_to_address2,
        null ship_to_address3,
        null sfdc_deal_reg,
        null date_of_first_sale,
        billing_term,
        null acv_fc,
        
        -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
        core_ent_flag,
    
        -- 05/13/2025 [Dan Girard] Added sfdc_line_item_owner_role, account name and averagerate
        null sfdc_line_item_owner_role, 
        null sfdc_account_name,
        null averagerate,
    
        -- 05/28/2025 [Dan Giard] Added TRANSEXTERNALID
        null transexternalid,
        
        -- 08/07/2025 [Dan Girard] Added SALESPERSON
        null salesperson,

        -- 08/20/2025 [Dan Girard] Added new/expansion/renewal type
        new_expansion, 

        -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
        null stripe_user_id,
        null braintree_user_id,

        -- 01/16/2026 [Dan Girard] Added new logic
        null annualized_fc_acv,

        -- 06/18/2026 [Dan Girard] Added Entity
        null entity,

        -- 07/06/2026 [Dan Girard] Added TRANSACTION_ID and BOOMI_EXTERNAL_ID,
        null transaction_id,
        null boomi_external_id
    from
       scaffold
)
-- Updated 05/30/2025 [Dan Girard] Added new selection section
select

    row_number() over (
        order by
          coalesce(c.invoiceno,''),
          c.lineid,
          coalesce(c.documentnumber,''),
          coalesce(c.item,''),
          coalesce(c.product,''),
          c.date,
          c.contractitemstartdate,
          c.contractitemenddate,
          c.amount_usd,
          c.amount
      ) as master_billing_id,
      
    c.reporting_status,
    c.ver_date,
    c.customercategory,
    c.date,
    c.invoiceno,
    c.name,
    c.item,
    c.lineid,
    c.salesdescription,
    c.description,
    c.sfdctype,
    c.quantity,
    c.documentnumber,
    c.amount_usd,
    c.amount,
    c.currency,
    c.amountforeigncurrency,
    c.contractitemstartdate,
    c.contractitemenddate,
    c.type,
    c.itemcategoryhidden,
    c.sbitemcategory1,

    -- 01/27/2026 [Dan Girard] Removed externalid
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    c.externalid,
    c.product,
    c.ordertype1,
    c.duns,
    c.customersite,
    c.globalultimateparent,
    c.sisense_product_rollup,
    c.bill_country,
    c.bill_state,
    c.bill_city,
    c.ship_country,
    c.ship_state,
    c.ship_city,
    c.incomeaccountname,
    c.contract_length,
    c.acv,
    c.my,
    c.product_for_reporting,
    c.product_group,
    c.order_type_final,
    c.reporting_channel,
    c.recurring_status,
    c.stream_revenue,
    c.stream_reporting,
    c.atlassian_hosting,
    c.shipped_subregion,
    c.shipped_region,
    c.year,
    c.annualized_acv,
    c.status,
    c.status_inq_pull,
    c.deal_count,
    c.pull_in,
    c.one_year_or_less,
    c.greater_than_2_years,
    c.one_to_two_years,
    c.one_year_more_or_less,
    c.external_id_present,
    c.monthly_arr,
    c.multiyear_flag,
    c.quarter_end,
    c.close_quarter,
    c.term,
    c.cap,
    c.overage,
    c.difference,
    c.pullin_dis,
    c.invoice_amount,
    c.tier,
    c.inline_discount,
    c.list_price,
    c.discount,
    c.ship_region,
    c.naics_sector,
    c.direct_ecomm_flag,
    c.product_for_reporting_ns,
    c.product_for_reporting_group_ns,
    c.product_for_reporting_ns_alias,
    c.product_for_reporting_ns_alias_combined,
    c.product_name,
    c.product_name_group,
    c.direct_indirect,
    c.core_noncore,
    c.salesperson_location,
    c.sfdc_closedate,
    c.bill_to_company,
    
    -- 01/27/2026 [Dan Girard] Removed bill_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    c.bill_to_name,
    c.bill_to_address1,
    c.bill_to_address2,
    c.bill_to_address3,
    c.ship_to_company,
    
    -- 01/27/2026 [Dan Girard] Removed ship_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    c.ship_to_name,
    c.ship_to_address1,
    c.ship_to_address2,
    c.ship_to_address3,
    c.sfdc_deal_reg,
    c.date_of_first_sale,
    c.billing_term,
    c.acv_fc,
    c.core_ent_flag,
    c.sfdc_line_item_owner_role, 
    c.sfdc_account_name,
    c.averagerate,
    c.transexternalid,

    -- Updated 05/30/2025 [Dan Girard] Added PBT Group
    b.pbt_group,

    -- 08/07/2025 [Dan Girard] Added SALESPERSON
    c.salesperson,

    -- 08/20/2025 [Damn Girard] Added new/expansion/renewal type
    c.new_expansion,

    -- 11/17/2025 [Dan Girard] Added stripe_user_id and braintree_user_id
    c.stripe_user_id,
    c.braintree_user_id,

    -- 01/16/2026 [Dan Girard] Added new logic
    c.annualized_fc_acv,

    -- 06/18/2026 [Dan Girard] Added Entity
    c.entity,

    -- 07/06/2026 [Dan Girard] Added TRANSACTION_ID and BOOMI_EXTERNAL_ID,
    c.transaction_id,
    c.boomi_external_id
from
    combined c

    --Updated 05/30/2025 [Dan Girard] Added PBT Group
    left join finance_db.public.dim_product_dm_hierarchy_tbl b on upper(concat(c.sisense_product_rollup,'_',c.direct_ecomm_flag)) = b.lookup_map_upper
;