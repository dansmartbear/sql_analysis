/**********************************************************************

Name:       finance_db.dev_netsuite.vw_sfdc_invoice_data
Type:       View
Created:    05/17/2026 [Dan Girard]
Purpose:    Produces a deduplicated, one-row-per-invoice lookup of SFDC
            close date, salesperson location, core/ent flag, and account
            name. Sourced from two SFDC tables that carry overlapping
            invoice sets:

              sfdc_opps_tbl             — close dates and account names
              sfdc_license_booking_allopps — salesperson location

            Invoice numbers in both tables may be multi-valued (e.g.
            "INV-001/INV-002"), separated by spaces or slashes. The
            LATERAL SPLIT_TO_TABLE step normalizes them to one row per
            invoice. Invoices appearing more than once across rows are
            excluded to prevent ambiguous joins downstream.

            Intended as a replacement for the 6-CTE SFDC block that is
            currently inlined in finance_db.public.master_billing.

Updates:    05/17/2026 [Dan Girard]  Initial extraction from MASTER_BILLING

***********************************************************************/
create or replace view finance_db.dev_netsuite.vw_sfdc_invoice_data as

with

-- ---------------------------------------------------------------------------
-- sfdc_opps: close dates and account names from the opportunities table.
-- Normalize multi-value invoice strings to a consistent slash-delimited form.
-- ---------------------------------------------------------------------------
sfdc_opps as
(
    select distinct
        replace(replace(o.invoice_num__c, ' ', '/'), '///', '/') as inv_list
        , o.closedate as sfdc_closedate
        , o.core_ent_account__c as core_ent_account
        , o.account_name as sfdc_account_name
    from
        sfdc_db.public.sfdc_opps_tbl o
    where
        o.invoice_num__c is not null
        and o.invoice_num__c not ilike '%authorize.net%'
        and o.invoice_num__c not ilike '%bugsnag%'
        and o.invoice_num__c not ilike '%pending%'
        and o.invoice_num__c not ilike '%incorrect%'
        and o.invoice_num__c not ilike '%cancel%'
        and o.invoice_num__c not ilike '%renew%'
        and o.invoice_num__c not ilike '%decline%'
        and o.invoice_num__c not ilike '%complete%'
)

-- ---------------------------------------------------------------------------
-- sfdc_loc: salesperson location and core/ent flag from the bookings table.
-- Same normalization applied to the invoice string.
-- ---------------------------------------------------------------------------
, sfdc_loc as
(
    select distinct
        replace(replace(l.invoice_num__c, ' ', '/'), '///', '/') as inv_list
        , l.line_item_owner_location2__c as sfdc_location
        , l.core_ent_account__c as core_ent_account
    from
        sfdc_db.public.sfdc_license_booking_allopps l
    where
        l.invoice_num__c is not null
        and l.invoice_num__c not ilike '%authorize.net%'
        and l.invoice_num__c not ilike '%bugsnag%'
        and l.invoice_num__c not ilike '%pending%'
        and l.invoice_num__c not ilike '%incorrect%'
        and l.invoice_num__c not ilike '%cancel%'
        and l.invoice_num__c not ilike '%renew%'
        and l.invoice_num__c not ilike '%decline%'
        and l.invoice_num__c not ilike '%complete%'
)

-- ---------------------------------------------------------------------------
-- sfdc_combined: full outer join so neither source drops invoices the other
-- doesn't have. Coalesce resolves which source wins for each field.
-- ---------------------------------------------------------------------------
, sfdc_combined as
(
    select
        coalesce(o.inv_list, l.inv_list) as inv_list
        , o.sfdc_closedate
        , l.sfdc_location
        , coalesce(o.core_ent_account, l.core_ent_account) as core_ent_account
        , o.sfdc_account_name
    from
        sfdc_opps o
        full outer join sfdc_loc l on o.inv_list = l.inv_list
)

-- ---------------------------------------------------------------------------
-- sfdc_split: explode multi-value invoice strings into one row per invoice.
-- The len(value) > 5 filter removes fragments too short to be real invoices.
-- ---------------------------------------------------------------------------
, sfdc_split as
(
    select
        trim(c.value) as invoice_no
        , sc.sfdc_closedate
        , sc.sfdc_location
        , sc.core_ent_account
        , sc.sfdc_account_name
    from
        sfdc_combined sc
        , lateral split_to_table(sc.inv_list, '/') c
    where
        len(trim(c.value)) > 5
)

-- ---------------------------------------------------------------------------
-- sfdc_unique: keep only invoice numbers that appear exactly once.
-- Duplicates indicate conflicting source rows; excluding them prevents bad
-- joins downstream.
-- ---------------------------------------------------------------------------
, sfdc_unique as
(
    select
        su.invoice_no
    from
        sfdc_split su
    group by
        su.invoice_no
    having
        count(su.invoice_no) = 1
)

-- ---------------------------------------------------------------------------
-- Final output: one row per invoice with all enrichment fields cleaned.
-- Empty strings are normalized to null for consistent coalesce behavior
-- in downstream joins.
-- ---------------------------------------------------------------------------
select
    ss.invoice_no
    , ss.sfdc_closedate
    , case
        when ss.sfdc_location = 'India' then 'Bangalore'
        when nullif(trim(ss.sfdc_location), '') is not null then ss.sfdc_location
        else null
        end as sfdc_location
    , case
        when nullif(trim(ss.core_ent_account), '') is not null then ss.core_ent_account
        else 'Core'
        end as sfdc_core_ent_flag
    , case
        when nullif(trim(ss.sfdc_account_name), '') is not null then ss.sfdc_account_name
        else null
        end as sfdc_account_name
from
    sfdc_split ss
    inner join sfdc_unique su on ss.invoice_no = su.invoice_no
;
