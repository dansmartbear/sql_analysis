call finance_db.dev_netsuite.sp_master_billing()
;

create or replace procedure finance_db.dev_netsuite.sp_master_billing()
    returns varchar
    language sql
    execute as owner
as
$$
begin

/**********************************************************************

Name:       finance_db.dev_netsuite.master_billing
Type:       Table
Created:    Dan Girard (1/10/2023)
Purpose:    This query will create a table called MASTER_BILLING to act
            as the Snowflake version of the downloaded data from the
            NetSuite application.
            
Updates:    2/14/2023 [Dan Girard]  Add region and NAICS
            6/28/2023 [Dan Girard]  Added DIRECT_ECOMM_FLAG, PRODUCT_FOR_REPORTING_NS, and PRODUCT_FOR_REPORTING_GROUP_NS
            8/28/2023 [Dan Girard]  Updated default settings for the bill and ship columns, and the INCOMEACCOUNTNAME in the PROFORMA BILLING section
                                    Added 2 new fields for PRODUCT_FOR_REPORTING_NS_ALIAS and PRODUCT_FOR_REPORTING_NS_ALIAS_COMBINED
            12/21/2023 [Dan Girard] Added new product dimension fields: product_name, core_noncore, direct_indirect, and product_name_group
            01/24/2023 [Dan Girard] Changed hard coded "PROFORMA" for reporting_status to a column pull.
            01/30/2024 [Dan Girard] Added Salesperson Location
            02/07/2024 [Dan Girard] Added the SFDC CTE to pull invoice #s and close dates
            02/08/2024 [Dan Girard] Added logic for blank salesperson locations (direct only)
            02/21/2024 [Dan Girard] Added logic for pulling sfdc location from new sfdc_db.public.sfdc_license_booking_allopps table and
                                    updated salesperson_location logic.
            05/01/2024 [Dan Girard] Changed calculations referencing AMOUNT to AMOUNT_USD, updated logic for PULL_IN field, updated logic for INVOICE_AMOUNT
            08/01/2024 [Dan Girard] Move CBT and BitBar to NON-CORE
            08/19/2024 [Dan Girard] Added sfdc_deal_reg
            10/21/2024 [Dan Girard] Added date_of_first_sale
            11/07/2024 [Dan Girard] Added billing_term
            12/04/2024 [Dan Girard] Added ACV_FC (ACV based on AMOUNTFOREIGNCURRENCY)
            12/17/2024 [Dan Girard] Added Scale Automate, Capture, and Cucumber for Jira to Atlassian Hosting field
            03/03/2025 [Dan Girard] Added CORE_ENT_FLAG from Salesforce data
            03/31/2025 [Dan Girard] Moved ACV and MY logic the A CTE
            04/04/2025 [Dan Girard] Added Scale Automate to Indirect Atlassian and to Reporting Channel
            05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role, account name and averagerate
            05/14/2025 [Dan Girard] Removed line_item_owner_role for now
            05/28/2025 [Dan Girard] Add TRANSEXTERNALID
            06/04/2025 [Dan Girard] Add logic for Test and Contract Testing product name mapping
	        09/04/2025 [Dan Girard] Update logic for Test to be API Hub Test
            09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
            11/17/2025 [Dan Girard] Add Stripe_User_ID and Braintree_User_ID
            12/04/2025 [Dan Girard] Changed from BugSnag RUM Direct to just BugSnag RUM
            01/14/2026 [Dan Girard] Removed externalid since it is no longer available
            02/11/2025 [Dan Girard] Added logic for blank ordertype1
            02/19/2026 [Dan Girard] Added unique identifier MASTER_BILLING_ID
            04/06/2026 [Dan Girard] Added Zephyr Advanced to direct_indirect
            04/22/2026 [Dan Girard] Added back fields per Mike Curran (03/20/2026 [Dan Girard] Added back per Mike Curran)
***********************************************************************/
create or replace table finance_db.dev_netsuite.master_billing copy grants
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
    , acv                                         float              
    , my                                          float              
    , product_for_reporting                       varchar(500)     
    , product_group                               varchar(500)    
    , order_type_final                            varchar(30)      
    , reporting_channel                           varchar(50)      
    , recurring_status                            varchar(50)      
    , stream_revenue                              varchar(50)      
    , stream_reporting                            varchar(50)      
    , atlassian_hosting                           varchar(50)      
    , shipped_subregion                           varchar(50) -- geo_2
    , shipped_region                              varchar(50) -- geo_1
    , year                                        varchar(50)
    , annualized_acv                              float
    , status                                      varchar(50)
    , status_inq_pull                              varchar(50)
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
    -- 2/14/2023 [dan girard] add region and naics
    , ship_region                                 varchar(500)
    , naics_sector                                varchar(500)
    -- 6/28/2023 [dan girard] added 3 new columns
    , direct_ecomm_flag                           varchar(50)
    , product_for_reporting_ns                    varchar(500)
    , product_for_reporting_group_ns              varchar(500)
    -- 10/3/2023 [dan girard] added 2 new columns
    , product_for_reporting_ns_alias              varchar(500)
    , product_for_reporting_ns_alias_combined     varchar(500)
    -- 12/21/2023 [Dan Girard] Added new product dimension fields: product_name, core_noncore, direct_indirect, and product_name_group
    , product_name                                varchar(500)
    , core_noncore                                varchar(500)
    , direct_indirect                             varchar(500)
    , product_name_group                          varchar(500)
      -- 1/30/2024 [Dan Girard] Added Salesperson Location
    , salesperson_location                        varchar(500)
    -- 02/07/2024 [Dan Girard] Added sfdc_closedate
    , sfdc_closedate                              date
    , sfdc_deal_reg                                varchar(5)
    , bill_to_company                             varchar(500)
    -- 01/20/2026 [Dan Girard] Removed bill_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    , bill_to_name                                varchar(500)
    , bill_to_address1                            varchar(500)
    , bill_to_address2                            varchar(500)
    , bill_to_address3                            varchar(500)
    , ship_to_company                             varchar(500)
    
    -- 01/20/2026 [Dan Girard] Removed ship_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran    
    , ship_to_name                                varchar(500)
    , ship_to_address1                            varchar(500)
    , ship_to_address2                            varchar(500)
    , ship_to_address3                            varchar(500)

    -- 10/21/2024 [Dan Girard] Added date_of_first_sale
    , date_of_first_sale                           date

    -- 11/07/2024 [Dan Girard] Added billing_term
    , billing_term                                varchar(50)

    -- 12/04/2024 [Dan Girard] Added ACV_FC
    , acv_fc                                      float

    -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
    , core_ent_flag                               varchar(50)

    -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role, account name, and averagerate
    -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
    -- , sfdc_line_item_owner_role                   varchar(500)
    , sfdc_account_name                           varchar(500)
    , averagerate                                 float

    -- 05/28/2025 [Dan Girard] Add TRANSEXTERNALID
    , transexternalid                             varchar(500)

    -- 08/07/2025 [Dan Girard] Added new column for salesperson
    , salesperson                                 varchar(500)

    -- 08/07/2025 [Dan Girard] Added new column for New/Expansion/Renewal type
    , new_expansion                               varchar(500)

    -- 11/17/2025 [Dan Girard] Add Stripe_User_ID and Braintree_User_ID
    , stripe_user_id                              varchar(500)
    , braintree_user_id                           varchar(500)

    -- 06/18/2026 [Dan Girard] Added entity
    , entity                                      varchar(500)
) as

-- 02/07/2024 [Dan Girard] Added CTEs to pull all invoice #s, close dates, opp_id_18s, and account ids
-- 02/21/2024 [Dan Girard] Added CTEs to pull all invoice #s, close dates, and sfdc location
with 
sfdc_inv_list_date as
(
    select distinct 
        replace(replace(invoice_num__c, ' ', '/'),'///','/') inv_list  -- To pull apart multiple invoice #s in a single value.
        , closedate sfdc_closedate
        , null sfdc_location
        , core_ent_account__c
        , account_name
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
-- select * from sfdc_inv_list_date where inv_list ilike '%IR-654956%';
,sfdc_inv_list_loc as
(
    select distinct 
        replace(replace(invoice_num__c, ' ', '/'),'///','/') inv_list  -- To pull apart multiple invoice #s in a single value.
        , null sfdc_closedate
        , line_item_owner_location2__c sfdc_location

        -- 03/03/2025 [Dan Girard] Added CORE_ENT_ACCOUNT__C
        , core_ent_account__c

        -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        -- , line_item_owner_role__c
    from 
        sfdc_db.public.sfdc_license_booking_allopps
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
-- select * from sfdc_inv_list_loc where inv_list ilike '%IR-654956%';
,
sfdc_inv_list_full as
(
    select
        coalesce(a.inv_list,b.inv_list) inv_list
        , coalesce(a.sfdc_closedate,b.sfdc_closedate) sfdc_closedate
        , coalesce(a.sfdc_location,b.sfdc_location) sfdc_location

        -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
        , coalesce(a.core_ent_account__c,b.core_ent_account__c) sfdc_core_ent_flag

        -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role and account name
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        -- , coalesce(a.line_item_owner_role__c, b.line_item_owner_role__c) sfdc_line_item_owner_role
        , account_name sfdc_account_name
    from 
        sfdc_inv_list_date a
        full outer join sfdc_inv_list_loc b on a.inv_list = b.inv_list
)
--select * from sfdc_inv_list_full where inv_list ilike '%IR-654956%';
-- 02/07/2024 [Dan Girard] Added SFDC CTE - use the LATERAL to make a unique list of invoices with the close dates
,sfdc_data_1 as
(
    select 
        value as invoice_no
        , sfdc_closedate
        , sfdc_location

        -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
        , sfdc_core_ent_flag

        -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role and account_name
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        -- , sfdc_line_item_owner_role
        , sfdc_account_name
    from sfdc_inv_list_full, lateral split_to_table(inv_list, '/')
    where len(value) > 5  -- filter out garbage invoices
)
--select * from sfdc_data_1 where invoice_no ilike '%IR-654956%';
,sfdc_data_2 as
(
    select invoice_no
    from sfdc_data_1
    group by 1
    having count(invoice_no) = 1
)
-- select * from sfdc_data_2 where invoice_no ilike '%IR-654956%';
,sfdc_data as
(
    select 
        a.invoice_no
        , a.sfdc_closedate
        , case when a.sfdc_location <> '' then a.sfdc_location
            else null
            end sfdc_location
        
        -- 03/03/2025 [Dan Girard] Added SFDC_CORE_ENT_FLAG
        , case when a.sfdc_core_ent_flag <> '' then a.sfdc_core_ent_flag
            else 'Core'
            end sfdc_core_ent_flag

        -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role and account name
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        -- , case when a.sfdc_line_item_owner_role <> '' then a.sfdc_line_item_owner_role
        --     else null
        --     end sfdc_line_item_owner_role
        , case when a.sfdc_account_name <> '' then a.sfdc_account_name
            else null
            end sfdc_account_name
    from 
        sfdc_data_1 a
        inner join sfdc_data_2 b on a.invoice_no = b.invoice_no
)
,A as
(
    -- Pull data from the NetSuite main view VW_NS_SS546
    select
        'AS REPORTED' as reporting_status
        , ns.customercategory
        , ns.date
        , ns.invoiceno
        , ns.name
        , ns.item
        , ns.lineid
        , ns.salesdescription
        , ns.description
        , ns.sfdctype
        , ns.quantity
        , ns.documentnumber
        , ns.amount_usd
        , ns.amount
        , ns.currency
        , ns.amountforeigncurrency * -1 as amountforeigncurrency -- Multiply foreign currency to get opposite of what's in the table
        , ns.contractitemstartdate
        , ns.contractitemenddate
        , ns.type
        , ns.itemcategoryhidden
        , ns.sbitemcategory1

        -- 01/14/2026 [Dan Girard] Removed since externalid is no longer available
        -- , ns.externalid
        , ns.product
        , ns.ordertype1
        , ns.duns
        , ns.customersite
        , ns.globalultimateparent
        , ns.sisense_product_rollup
        , ns.bill_country
        , ns.bill_state
        , ns.bill_city
        , ns.ship_country
        , ns.ship_state
        , ns.ship_city
        , ns.incomeaccountname
        , case when ns.inline_discount = '' then 0 else ns.inline_discount/100 end inline_discount
        -- 2/14/2023 [Dan Girard] Add region and NAICS
        , ns.ship_region
        , ns.naics
        -- 6/28/2023 [Dan Girard] Added 3 new columns
        , ns.direct_ecomm_flag
        , ns.product_for_reporting_ns
        , ns.product_for_reporting_group_ns
        -- 10/3/2023 [Dan Girard] Added 2 new columns
        , ns.product_for_reporting_ns_alias
        , ns.product_for_reporting_ns_alias_combined
        -- 1/30/2024 [Dan Girard] Added Salesperson Location
        -- 2/8/2024  [Dan Girard] Added logic for blank salesperson locations (direct only)
        -- 02/21/2024 [Dan Girard] Updated logic to include new SFDC_location field
        
        , case
            when sf.sfdc_location = 'India' then 'Bangalore'
            when coalesce(sf.sfdc_location,'') <> '' then sf.sfdc_location
            when coalesce(ns.salesperson_location,'') <> '' then ns.salesperson_location
            when coalesce(ns.salesperson_location,'') = '' and ns.direct_ecomm_flag = 'Direct' then 'Somerville'
            else ''
            end salesperson_location
        
        -- 02/07/2024 [Dan Girard] Added sfdc_closedate
        , sf.sfdc_closedate
        
        -- 08/19/2024 [Dan Girard] Added sfdc_deal_reg
        , ns.sfdc_deal_reg

        -- 2024-09-10 [Dan Girard] Added Bill To and Ship To info
        , ns.bill_to_company
        
        -- 01/20/2026 [Dan Girard] Removed bill_to_name
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        , ns.bill_to_name
        , ns.bill_to_address1
        , ns.bill_to_address2
        , ns.bill_to_address3
        , ns.ship_to_company
        
        -- 01/20/2026 [Dan Girard] Removed ship_to_name
	-- 03/20/2026 [Dan Girard] Added back per Mike Curran
        , ns.ship_to_name
        , ns.ship_to_address1
        , ns.ship_to_address2
        , ns.ship_to_address3

        -- 10/21/2024 [Dan Girard] Added date_of_first_sale
        , ns.dateoffirstsale date_of_first_sale

        -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
        , case when ns.direct_ecomm_flag = 'Ecomm' then 'Ecomm'
            else sf.sfdc_core_ent_flag 
            end core_ent_flag

        -- 03/31/2025 [Dan Girard] Moved ACV and MY logic to here
        , datediff(day, ifnull(ns.contractitemstartdate, current_date()), ifnull(ns.contractitemenddate,current_date())) + 1 as contract_length
        , case 
              when contract_length = 0 then 0
              when sbitemcategory1 = 'license - perpetual' then amount_usd
              when contract_length <= 366 then amount_usd
              else (amount_usd / contract_length) * 365
              end acv
        , (amount_usd - acv) my

        -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role, account name, and averagerate
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        -- , sfdc_line_item_owner_role
        , sfdc_account_name
        , averagerate

        -- 05/28/2025 [Dan Girard] Add TRANSEXTERNALID
        , ns.transexternalid

        -- 08/07/2024 [Dan Girard] Added new column for salesperson
        , ns.salesperson

        -- 11/17/2025 [Dan Girard] Add Stripe_User_ID and Braintree_User_ID
        , ns.stripe_user_id
        , ns.braintree_user_id

        -- 06/18/2026 [Dan Girard] Added entitynohierarchy
        , ns.entitynohierarchy entity
    from 
        finance_db.public.vw_ns_ss546 ns
        -- 02/07/2024 [Dan Girard] Added SFDC_CloseDate JOIN
        left join sfdc_data sf on ns.invoiceno = sf.invoice_no


    -- Union NS view with Proforma table, need all columns to be common between tables, below defines columns as "" 
    -- if they do not already exist in the proforma table
    
    union all
    
    -- Pull same data from the ProForma billings table as a UNION ALL
    select 
        reporting_status
        , '' as customercategory
        , p.date
        , '' as invoiceno
        , 'unknown - proforma' as name
        , '' as item
        , 0  as lineid
        , '' as salesdescription
        , '' as description
        , '' as sfdctype
        , 0 as quantity
        , 'proforma' as documentnumber
        , p.amount_usd as amount
        , p.amount_usd
        , 'usd' as currency
        , p.amount_usd as amountforeigncurrency
        , p.contract_start_date as contractitemstartdate
        , p.contract_end_date as contractitemenddate
        , '' as type
        , p.stream as itemcategoryhidden
        , p.stream as sbitemcategory1

        -- 01/14/2026 [Dan Girard] Removed since externalid is no longer available
        -- , '' as externalid
        , p.product
        , order_type as ordertype1
        , '' as duns
        , '' as customersite
        , 'unkown - proforma' as globalultimateparent
        , p.product as sisense_product_rollup
        -- 8/28/2023 [Dan Girard] updated default settings for the bill and ship columns, and the INCOMEACCOUNTNAME
        , 'United States' as bill_country
        , 'Proforma' as bill_state
        , 'Proforma' as bill_city
        , 'United States' as ship_country
        , 'Proforma' as ship_state
        , 'Proforma' as ship_city
        , p.stream as incomeaccountname
        , 0 as inline_discount
        -- 2/14/2023 [Dan Girard] Add region and NAICS
        , '' ship_region
        , '' naics              
        -- 6/28/2023 [Dan Girard] Added 3 new columns
        , p.direct_ecomm_flag
        , p.product_for_reporting_ns
        , p.product_for_reporting_group_ns
        -- 10/3/2023 [Dan Girard] Added 2 new columns
        , p.product_for_reporting_ns_alias
        , p.product_for_reporting_ns_alias_combined
        -- 1/30/2024 [Dan Girard] Added Salesperson Location
        , '' salesperson_location
        -- 02/07/2024 [Dan Girard] Added sfdc_closedate
        , null sfdc_closedate
        -- 08/19/2024 [Dan Girard] Added sfdc_deal_reg
        , null sfdc_deal_reg

        -- 2024-09-10 [Dan Girard] Added Bill To and Ship To info
        , null bill_to_company

        -- 01/20/2026 [Dan Girard] Removed bill_to_name
        -- 03/20/2026 [Dan Girard] Added back per Mike Curran
        , null bill_to_name
        , null bill_to_address1
        , null bill_to_address2
        , null bill_to_address3
        , null ship_to_company
        
        -- 01/20/2026 [Dan Girard] Removed ship_to_name
	-- 03/20/2026 [Dan Girard] Added back per Mike Curran
        , null ship_to_name
        , null ship_to_address1
        , null ship_to_address2
        , null ship_to_address3

        -- 10/21/2024 [Dan Girard] Added date_of_first_sale
        , null date_of_first_sale

        -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
        , case when p.direct_ecomm_flag = 'Ecomm' then 'Ecomm'
            else 'Core'
            end core_ent_flag

        -- 03/31/2025 [Dan Girard] Moved ACV and MY logic to here
        , datediff(day, ifnull(p.contract_start_date, current_date()), ifnull(p.contract_end_date,current_date())) + 1 as contract_length
        , case 
              when contract_length = 0 then 0
              when contract_length <= 366 then amount_usd
              else (amount_usd / contract_length) * 365
              end acv
        , (amount_usd - acv) my

        -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role ,account_name, and averagerate
        -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
        -- , null sfdc_line_item_owner_role
        , null sfdc_account_name
        , 1 averagerate

        -- 05/28/2025 [Dan Girard] Add TRANSEXTERNALID
        , '' transexternalid

        -- 08/07/2024 [Dan Girard] Added new column for salesperson
        , '' salesperson

        -- 11/17/2025 [Dan Girard] Add Stripe_User_ID and Braintree_User_ID
        , '' stripe_user_id
        , '' braintree_user_id

        -- 06/18/2026 [Dan Girard] Added entitynohierarchy
        , 'Proforma' entity
    from
        finance_db.public.pf_billings p
)
,tiers as
(
    -- Build an overall invoice amount (group by) and
    -- then bin it in the 7 different amount bins
    select
        invoiceno
        , to_number(sum(amount_usd),38,2) as invoice_amount  -- 5/1/2024 [Dan Girard] Change from to_number to to_decimal and change from amount to amount_usd
        , case 
              when abs(invoice_amount) > 250000 then '$250k+'
              when abs(invoice_amount) > 100000 then '$100-250k'
              when abs(invoice_amount) > 50000  then '$50-100k'
              when abs(invoice_amount) > 25000  then '$25-50k'
              when abs(invoice_amount) > 10000  then '$10-25k'
              when abs(invoice_amount) > 5000   then '$5-10k'
              when abs(invoice_amount) > 0      then '$0-5k'
              else ''
              end tier
    from
        A
    where
        upper(reporting_status) = 'AS REPORTED'
        and invoiceno is not null
    group by
        invoiceno
)
,mb as
(
    -- Get the main data and add the calculated fields
    select 
    a.reporting_status
    , a.customercategory
    , a.date
    , a.invoiceno
    , a.name
    , a.item
    , a.lineid
    , a.salesdescription
    , a.description
    , a.sfdctype
    , a.quantity
    , a.documentnumber
    , sum(a.amount_usd) as amount_usd
    , sum(a.amount) as amount
    , a.currency
    , a.amountforeigncurrency
    , a.contractitemstartdate
    , a.contractitemenddate
    , a.type
    , a.itemcategoryhidden
    , a.sbitemcategory1
    
    -- 01/14/2026 [Dan Girard] Removed since externalid is no longer available
    -- , a.externalid
    , a.product
    , a.ordertype1
    , a.duns
    , a.customersite
    , a.globalultimateparent
    , a.sisense_product_rollup
    , a.bill_country, a.bill_state, a.bill_city, a.ship_country, a.ship_state, a.ship_city
    , a.incomeaccountname
    , datediff(day, ifnull(contractitemstartdate, current_date()), ifnull(contractitemenddate,current_date())) + 1 as contract_length
    
    -- 03/31/2025 [Dan Girard] Moved ACV and MY to above
    -- , case 
    --       when contract_length = 0 then 0
    --       when sbitemcategory1 = 'license - perpetual' then amount_usd
    --       when contract_length <= 366 then amount_usd
    --       else (amount_usd / contract_length) * 365
    --       end acv
    -- , (amount_usd - acv) my
    , sum(acv) acv
    , sum(my) my
    
    , case 
          -- Wildcard statements used for CleverBridge order
          -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
          when sisense_product_rollup = 'Bugsnag' and CUSTOMERCATEGORY <> 'ecommerce' then 'BugSnag Direct'
          when sisense_product_rollup = 'Bugsnag' and NAME in ('CleverBridge Online Orders - IRE','CleverBridge - US') then 'BugSnag Direct'
          when sisense_product_rollup in ('Bugsnag') and LOWER(NAME) like '%cleverbridge%' then 'BugSnag Direct'
          when sisense_product_rollup = 'Bugsnag' then 'BugSnag Ecomm'

          -- 12/9/2025 [Dan Girard] Changed from BugSnag RUM Direct to just BugSnag RUM
          when sisense_product_rollup ilike 'Bugsnag RUM' and CUSTOMERCATEGORY <> 'ecommerce' then 'BugSnag RUM'
          when sisense_product_rollup ilike 'Bugsnag RUM' and NAME in ('CleverBridge Online Orders - IRE','CleverBridge - US') then 'BugSnag RUM'
          when sisense_product_rollup ilike any ('Bugsnag RUM') and LOWER(NAME) like '%cleverbridge%' then 'BugSnag RUM'
          when sisense_product_rollup = 'Bugsnag RUM' then 'BugSnag Ecomm'
          
          when sisense_product_rollup = 'CBT' and NAME in ('CleverBridge Online Orders - IRE','CleverBridge - US') then 'CBT Sales Assisted'
          when sisense_product_rollup = 'CBT' then 'CBT Ecomm'
          when sisense_product_rollup in ('CBT') and LOWER(NAME) like '%cleverbridge%' then 'CBT Sales Assisted'
          when sisense_product_rollup in ('Swagger') and LOWER(NAME) like '%cleverbridge%' then 'Swagger Direct'
          when sisense_product_rollup = 'Swagger' and NAME in ('CleverBridge Online Orders - IRE','CleverBridge - US') then 'Swagger Direct'
          when sisense_product_rollup = 'Swagger' and CUSTOMERCATEGORY = 'ecommerce' then 'Swagger Ecomm'
          when sisense_product_rollup = 'Swagger' then 'Swagger Direct'

          -- 05/15/2025 [Dan Girard] Put API Hub to Swagger
          when sisense_product_rollup = 'API Hub' and NAME in ('CleverBridge Online Orders - IRE','CleverBridge - US') then 'Swagger Direct'
          when sisense_product_rollup = 'API Hub' and CUSTOMERCATEGORY = 'ecommerce' then 'Swagger Ecomm'
          when sisense_product_rollup = 'API Hub' then 'Swagger Ecomm'
          
          when sisense_product_rollup = 'Cucumber' then 'Cucumber for Jira'
          when sisense_product_rollup = 'Hiptest' then 'CucumberStudio'
          when sisense_product_rollup = 'Squad' then 'Zephyr Squad'
          when sisense_product_rollup = 'RAPI Test' then 'ReadyAPI Test'
          when sisense_product_rollup = 'TestEngine' then 'ReadyAPI Test'
          when sisense_product_rollup = 'RAPI Performance' then 'ReadyAPI Perf'
          when sisense_product_rollup = 'RAPI Virtualization' then 'ReadyAPI Virt'
          when sisense_product_rollup = 'Bitbar' then 'BitBar'
          when sisense_product_rollup = 'TestServer' then 'TestComplete'

          -- 06/04/2025 [Dan Girard] Add logic for Test and Contract Testing
          -- 09/04/2025 [Dan Girard] Update logic for Test to be API Hub Test
          when sisense_product_rollup = 'Test' and direct_ecomm_flag = 'Direct' then 'API Hub Test'
          when sisense_product_rollup = 'Test' and direct_ecomm_flag = 'Ecomm' then 'Swagger Ecomm'
          
          when sisense_product_rollup = 'Contract Testing' then 'Pactflow'

          -- 12/09/2025 [Dan Girard] Added Zephyr Scale Automate
          when sisense_product_rollup = 'Zephyr Scale Automate' then 'Zephyr Advanced'
          
          else sisense_product_rollup
          end product_for_reporting

     -- 02/11/2025 [Dan Girard] Added logic for blank ordertype1
    , case 
          when ordertype1 in ('New','Existing') then 'License'
          when ordertype1 in ('Renewal') then 'Renewal'
          when ordertype1 = '' then
            case when sfdctype in ('New','Expansion') then 'License'
                when sfdctype in ('Renewal') then 'Renewal'
                else '-'
                end
          else ordertype1
          end order_type_final

    -- 04/04/2025 [Dan Girard] Added Scale Automate to Ecomm channel
    , case 
          -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
          when product_for_reporting ilike any ('Zephyr Squad','Zephyr Scale','CBT Ecomm','Capture','Cucumber for Jira','BugSnag Ecomm','Swagger Ecomm','Zephyr Scale Automate','Zephyr Advanced') then 'Ecomm'
          
          else 'Direct'
          end reporting_channel
    , case 
          when sbitemcategory1 in ('Services','License - Perpetual') then 'Non-Reccuring'
          when sbitemcategory1 is null then 'Unknown'
          when sbitemcategory1 = '' then 'Unknown'
          else 'Recurring'
          end  recurring_status
    // 8/2/2023 [Dan Girard] Update logic
    , case
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
          end stream_revenue
    , case 
          when stream_revenue in ('Subscription Maintenance','Perpetual Maintenance') then 'Maintenance'
          else stream_revenue
          end stream_reporting
    -- Replaced case statement on SHIP_CUNTRY with left join to new DIM_COUNTRY_MAP table
    , scm.mapped_subregion shipped_subregion  -- GEO_2
    , scm.mapped_region shipped_region      -- GEO_1
    , to_char(year(date)) year
    -- New fields from the Billings and Discounting Excel files
    , dateadd('day',-1,date_trunc('quarter',dateadd('month',3,date))) quarter_end
    , case 
          when contract_length = 0 then 0 
          else (amount_usd / contract_length) * 365 
          end annualized_acv
    , case 
          when order_type_final = 'Renewal' then
              -- case when CONTRACTITEMSTARTDATE < '2022-10-02' then 'INQ'
              case when contractitemstartdate <= dateadd(day,1,quarter_end) then 'INQ'
              else 'Pull'
              end
          else 'INQ'
          end status
          -- if the Contract Start < Quarter End Date (field) + 1 then In Quarter, else Pull
    -- 5/20/2024 [Dan Girard] Duplicated the original status column with new logic
    , case 
          when contractitemstartdate <= dateadd(day,1,quarter_end) then 'INQ'
          else 'Pull'
          end status_inq_pull
          -- if the Contract Start < Quarter End Date (field) + 1 then In Quarter, else Pull
    , case 
          when amount = 0 then 0
          else
              case when amount > 0 then 1
              else -1
              end
          end deal_count
    -- 05/01/2024 [Dan Girard] changed logic from = INQ to <> INQ, added the ELSE INQ
    , case 
          when status <> 'INQ' and datediff(day,quarter_end,contractitemstartdate)+1 < 31 then '30 Days'
          when status <> 'INQ' and datediff(day,quarter_end,contractitemstartdate)+1 < 61 then '60 Days'
          when status <> 'INQ' and datediff(day,quarter_end,contractitemstartdate)+1 < 91 then '90 Days'
          when status <> 'INQ' and datediff(day,quarter_end,contractitemstartdate)+1 >= 91 then '+90 Days'
          else 'INQ'
          end pull_in
        -- Same as status - use the compare logic.
    -- 5/1/2024 [Dan Girard] change from amount to amount_usd
    , case 
          when contract_length = 0 then 0
          when contract_length <= 366 then +amount_usd
          else (amount_usd/contract_length) * 365
          end one_year_or_less
    -- 5/1/2024 [Dan Girard] change from amount to amount_usd
    , case 
          when contract_length = 0 then 0
          when contract_length > 731 then (amount_usd/contract_length) * (contract_length-731)
          else 0
          end greater_than_2_years
    -- 5/1/2024 [Dan Girard] change from amount to amount_usd
    , case 
          when contract_length >= 367 then (amount_usd - one_year_or_less - greater_than_2_years)
          else 0
          end one_to_two_years
    , case
          when one_to_two_years = 0 then '1 Year or Less'
          else '1 Year or More'
          end one_year_more_or_less
          
    -- 01/14/2026 [Dan Girard] Removed since externalid is no longer available and changed to default value
    -- , case 
        --   when a.externalid = '' then 'No ID'
        --   else 'ID Present'
        --   end 
    , 'No ID' external_id_present
    
    -- 5/1/2024 [Dan Girard] change from amount to amount_usd
    , case
          when contract_length = 0 then 0
          when contract_length < 32 then ((amount_usd/contract_length) * 365) / 3
          else (amount_usd/contract_length) * 365
          end monthly_arr
    , case
          when contract_length > 548 then 1
          else 0
          end multiyear_flag
    , concat('q',quarter(date),year(date)) close_quarter

    -- 03/18/2026 [Dan Girard] Updated the values and added the 1 year bucket.
    , case 
          when contract_length > 1096 then '3 years plus'
          when contract_length > 730 then '3 years'
          when contract_length > 366 then '2 years'
          when contract_length > 363 then '1 year' 
          else 'Less than 1 year'
          end term
    , 365 * 3 cap
    , contract_length - cap overage
    -- 5/1/2024 [Dan Girard] change from amount to amount_usd
    , case
          when contract_length = 0 then 0
          else (amount_usd/contract_length) * overage
          end difference
    , case
          when dateadd('day',-1,contractitemstartdate) > quarter_end then 'Yes'
          else 'No'
          end pullin_dis
    , t.invoice_amount invoice_amount
    , t.tier tier
    , a.inline_discount
    , case 
          when 1 - a.inline_discount = 0 then a.amountforeigncurrency
          else a.amountforeigncurrency / (1 - a.inline_discount)
          end list_price
    , 1 - div0(a.amountforeigncurrency,list_price) discount
    -- 2/14/2023 [Dan Girard] Add region and NAICS
    , a.ship_region
    , a.naics
    -- 6/28/2023 [Dan Girard] Added 3 new columns
    , a.direct_ecomm_flag
    , a.product_for_reporting_ns
    , a.product_for_reporting_group_ns
    -- 10/3/2023 [Dan Girard] Added 2 new columns
    , a.product_for_reporting_ns_alias
    , a.product_for_reporting_ns_alias_combined
    -- 12/21/2023 [Dan Girard] Added new product dimension fields: product_name, core_noncore, direct_indirect, and product_name_group
    , case 
        --when coalesce(product_name,'') <> '' then product_name
        
        -- 12/09/2025 [Dan Girard] Change for BugSnag RUM and Zephyr Scale Automate
        when a.product_for_reporting_ns_alias ilike any ('BugSnag RUM','Zephyr Scale Automate','Zephyr Advanced') then product_for_reporting_ns_alias
        
        -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
        when a.product_for_reporting_ns_alias ilike any ('BugSnag%','Stoplight%','Swagger%','Reflect%') then product_for_reporting_ns_alias_combined
        
        when a.product_for_reporting_ns_alias = 'CBT' and a.direct_ecomm_flag = 'Direct' then 'CBT Sales Assisted'
        else a.product_for_reporting_ns_alias
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

    -- 04/04/2025 [Dan Girard] Added Scale Automate to Indirect Atlassian
    -- 06/12/2025 [Dan Girard] Added QTM4J for Indirect Atlassian
    , case
        --when coalesce(direct_indirect,'') <> '' then direct_indirect
        -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
        -- 10/01/2025 [Dan Girard] Change BugSnag RUM
        when product_name in ('Pactflow','VisualTest','LoadNinja') and direct_ecomm_flag = 'Ecomm' then 'Indirect - Ecomm'

        -- 11/20/2025 [Dan Girard] Change from Reflect to Reflect Ecomm
        when product_name in ('BugSnag Ecomm','Device Cloud','Stoplight Ecomm','Swagger Ecomm','Reflect Ecomm') then 'Indirect - Ecomm'

        -- 04/06/2026 [Dan Girard] Added Zephyr Advanced
        when product_name in ('Capture','Cucumber for Jira','Zephyr Scale', 'Zephyr Squad','Zephyr Scale Automate','QTM4J','Zephyr Advanced') then 'Indirect - Atlassian'
        else 'Direct'
        end direct_indirect
    , case
        --when coalesce(product_name_group,'') <> '' then product_name_group
        -- 09/04/2025 [Dan Girard] Update logic for API Hub Test
        when product_name in ('Explore','Pactflow','Portal','ReadyAPI Perf','ReadyAPI Test','ReadyAPI Virt','Stoplight Direct','Stoplight Ecomm','Swagger Direct','Swagger Ecomm','API Hub Ecomm','API Hub','API Hub Test') then 'API'
        when product_name in ('Capture','Cucumber for Jira','Zephyr Scale','Zephyr Scale Automate','Zephyr Scale - Automate','Zephyr Squad','QTM4J','Zephyr Advanced') then 'Marketplace'

        -- 09/11/2025 [Dan Girard] Changed from Bugsnag to BugSnag
        when product_name ilike 'BugSnag%' then 'Observability'
        
        when product_name in ('AlertSite','AQTime','Collaborator','CucumberStudio','LoadComplete','QAComplete') then 'Other'
        when product_name in ('BitBar','CBT Sales Assisted','Device Cloud','LoadNinja','TestComplete','VisualTest','Zephyr E','Reflect Ecomm','Reflect Direct') then 'Test'
        end product_name_group
    -- 1/30/2024 [Dan Girard] Added Salesperson Location
    , a.salesperson_location
    -- 02/07/2024 [Dan Girard] Added sfdc_closedate
    , a.sfdc_closedate
    -- 08/19/2024 [Dan Girard] Added sfdc_deal_reg
    , a.sfdc_deal_reg

    -- 2024-09-10 [Dan Girard] Added Bill To and Ship To info
    , a.bill_to_company
    
    -- 01/20/2026 [Dan Girard] Removed bill_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    , a.bill_to_name
    , a.bill_to_address1
    , a.bill_to_address2
    , a.bill_to_address3
    , a.ship_to_company
    
    -- 01/20/2026 [Dan Girard] Removed ship_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    , a.ship_to_name
    , a.ship_to_address1
    , a.ship_to_address2
    , a.ship_to_address3

    -- 10/21/2024 [Dan Girard] Added date_of_first_sale
    , a.date_of_first_sale

    -- 11/07/2024 [Dan Girard] Added billing_term
    , case when contract_length <= 33 then 'Monthly'
        else 'Annual'
        end billing_term

    -- 12/04/2024 [Dan Girard] Added ACV_FC based on ACV calc
    , case 
          when contract_length = 0 then 0
          when sbitemcategory1 = 'license - perpetual' then a.amountforeigncurrency
          when contract_length <= 366 then amountforeigncurrency
          else (amountforeigncurrency / contract_length) * 365
          end acv_fc

    -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
    , a.core_ent_flag

    -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role, account_name and averagerate
    -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
    -- , a.sfdc_line_item_owner_role
    , a.sfdc_account_name
    , a.averagerate

    -- 05/28/2025 [Dan Girard] Add TRANSEXTERNALID
    , a.transexternalid

    -- 08/07/2024 [Dan Girard] Added new column for salesperson
    , a.salesperson

    , case
      -- 9/11/2025 [Dan Girard] Updated Atlassian Hosting logic
      when direct_indirect = 'Indirect - Atlassian' then
        case
            when a.sbitemcategory1 ilike '%SaaS%' then 'Cloud'
            when a.sbitemcategory1 ilike '%Term%' then 'Data Center'
            else 'Server'
            end 
            else ''
            end atlassian_hosting

    -- 11/17/2025 [Dan Girard] Add Stripe_User_ID and Braintree_User_ID
    , a.stripe_user_id
    , a.braintree_user_id

    -- 06/18/2026 [Dan Girard] Added entitynohierarchy
    , a.entity
from
    a   //Unioned table of the NS actuals (A) and the Proforma (P) is then renamed A
    left join finance_db.public.dim_country_map scm on a.ship_country = scm.original_country
    left join tiers t on a.invoiceno = t.invoiceno
group by
    -- 10/3/2023 [Dan Girard] change to "all"
    all
)
select
    -- 02/19/2026 [Dan Girard] Added master_billing_id for unique id
    -- row_number() over (order by 1) as master_billing_id
    1 master_billing_id
    , mb.reporting_status
    , current_timestamp()
    , mb.customercategory
    , mb.date
    , mb.invoiceno
    , mb.name
    , mb.item
    , mb.lineid
    , mb.salesdescription
    , mb.description
    , mb.sfdctype
    , mb.quantity
    , mb.documentnumber
    , mb.amount_usd
    , mb.amount
    , mb.currency
    , mb.amountforeigncurrency
    , mb.contractitemstartdate
    , mb.contractitemenddate
    , mb.type
    , mb.itemcategoryhidden
    , mb.sbitemcategory1
    -- 01/14/2026 [Dan Girard] Removed since externalid is no longer available
    -- , mb.externalid
    , mb.product
    , mb.ordertype1
    , mb.duns
    , mb.customersite
    , mb.globalultimateparent
    , mb.sisense_product_rollup
    , mb.bill_country
    , mb.bill_state
    , mb.bill_city
    , mb.ship_country
    , mb.ship_state
    , mb.ship_city
    , mb.incomeaccountname
    , mb.contract_length
    , mb.acv
    , mb.my
    , mb.product_for_reporting
    , pg.product_group
    , mb.order_type_final
    , mb.reporting_channel
    , mb.recurring_status
    , mb.stream_revenue
    , mb.stream_reporting
    , mb.atlassian_hosting
    , mb.shipped_subregion   -- geo_2
    , mb.shipped_region      -- geo_1
    , mb.year
    , mb.annualized_acv
    , mb.status
    -- 05/24/2024 [Dan Girard] Duplicated the original status column with new logic
    , mb.status_inq_pull
    , mb.deal_count
    , mb.pull_in
    , mb.one_year_or_less
    , mb.greater_than_2_years
    , mb.one_to_two_years
    , mb.one_year_more_or_less
    , mb.external_id_present
    , mb.monthly_arr
    , mb.multiyear_flag
    , mb.quarter_end
    , mb.close_quarter
    , mb.term
    , mb.cap
    , mb.overage
    , mb.difference
    , mb.pullin_dis
    , mb.invoice_amount
    , mb.tier
    , mb.inline_discount
    , mb.list_price
    , mb.discount
    -- 2/14/2023 [Dan Girard] Add region and NAICS Sector
    , mb.ship_region
    , concat(nm.naics_sector_code,' - ',nm.naics_sector) as naics_sector
    -- 6/28/2023 [Dan Girard] Added 3 new columns
    , mb.direct_ecomm_flag
    , mb.product_for_reporting_ns
    , mb.product_for_reporting_group_ns
    -- 10/3/2023 [Dan Girard] Added 2 new columns
    , mb.product_for_reporting_ns_alias
    , mb.product_for_reporting_ns_alias_combined
    -- 12/21/2023 [Dan Girard] Added new product dimension fields: product_name, core_noncore, direct_indirect, and product_name_group
    , mb.product_name
    , mb.core_noncore
    , mb.direct_indirect
    , mb.product_name_group
    -- 1/30/2024 [Dan Girard] Added Salesperson Location
    , mb.salesperson_location
    -- 02/07/2024 [Dan Girard] Added sfdc_closedate
    , mb.sfdc_closedate
    -- 08/19/2024 [Dan Girard] Added sfdc_deal_reg
    , mb.sfdc_deal_reg

    -- 2024-09-10 [Dan Girard] Added Bill To and Ship To info
    , mb.bill_to_company
    
    -- 01/20/2026 [Dan Girard] Removed bill_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    , mb.bill_to_name
    , mb.bill_to_address1
    , mb.bill_to_address2
    , mb.bill_to_address3
    , mb.ship_to_company
    
    -- 01/20/2026 [Dan Girard] Removed ship_to_name
    -- 03/20/2026 [Dan Girard] Added back per Mike Curran
    , mb.ship_to_name
    , mb.ship_to_address1
    , mb.ship_to_address2
    , mb.ship_to_address3

    -- 10/21/2024 [Dan Girard] Added date_of_first_sale
    , mb.date_of_first_sale

    -- 11/07/2024 [Dan Girard] Added billing_term
    , mb.billing_term

    -- 12/04/2024 [Dan Girard] Added ACV_FC
    , mb.acv_fc

    -- 03/03/2025 [Dan Girard] Added CORE_ENT_FLAG
    , mb.core_ent_flag

    -- 05/09/2025 [Dan Girard] Added sfdc_line_item_owner_role,  sfdc_account_name and averagerate
    -- 05/14/2025 [Dan Girard] Removed line_item_owner_role for now
    -- , mb.sfdc_line_item_owner_role
    , mb.sfdc_account_name
    , mb.averagerate

    -- 05/28/2025 [Dan Girard] Add TRANSEXTERNALID
    , mb.transexternalid

    -- 08/07/2025 [Dan Girard] Added new column for salesperson
    , mb. salesperson

    -- 08/20/2025 [Dan Girard] Added new column for the New/Expansion/Renewal type 
    , case when mb.order_type_final = 'Renewal' then 'Renewal'
             when mb.sfdctype = 'New' then 'New'
             when mb.sfdctype <> '' then 'Expansion'
             when mb.sfdctype = '' and mb.ordertype1 = 'Existing' then 'Expansion'
             else mb.ordertype1
             end new_expansion

    -- 11/17/2025 [Dan Girard] Add Stripe_User_ID and Braintree_User_ID
    , mb.stripe_user_id
    , mb.braintree_user_id

    -- 06/18/2026 [Dan Girard] Added entitynohierarchy
    , mb.entity
from
    mb
    left join finance_db.public.dim_product_group_map pg on upper(mb.product_for_reporting) = upper(pg.product_name)
    -- 2/14/2023 [Dan Girard] Add lookup for NAICS data
    left join finance_db.public.vw_naics_mapping nm on mb.naics = to_char(nm.naics_code)
    ;

    return 'Successfully created or replaced table finance_db.dev_netsit.master_billing.';

end;
$$
;