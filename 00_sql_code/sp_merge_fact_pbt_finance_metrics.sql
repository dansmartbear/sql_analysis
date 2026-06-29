-- =============================================================================
-- sp_merge_fact_pbt_finance_metrics
-- =============================================================================
-- 06/24/2026 [Dan Girard] Incremental merge proc for fact_pbt_finance_metrics.
--   Implements the change-detection logic from fact_pbt_incremental_ingestion_plan.md:
--     - record_id : deterministic md5 over all dimension columns (the grain key)
--     - row_hash  : md5 over content columns (measures + dims), excluding the key,
--                   audit columns, and the volatile/derived columns
--     - upsert via merge (insert new, update only when row_hash differs)
--     - silent refresh of volatile columns on matched-unchanged rows WITHOUT
--       bumping last_updated_at (keeps Data Cloud from seeing a false "change")
--     - soft-delete rows absent from the current view snapshot
--     - reappear handled automatically by the merge (is_deleted = false on match)
--
-- Decisions confirmed 06/24/2026:
--   O-1  multiyear_flag (varchar 'Y'/'N') -> my_flag int : 'Y' -> 1 else 0
--   O-2  matched-unchanged rows: refresh volatile columns, do NOT bump watermark
--   O-3  elt_metric_id retired; record_id is the sole key
--   Schema: build/test in finance_db.dev_netsuite, promote to public after validation
--   Column names: keep current table DDL names (globalultimateparentupperclean,
--                 closedate, saletype, multiyear_flag)
--
-- TRADEOFF NOTE (staging strategy):
--   Per the confirmed choice, the view is inlined as a CTE inside the merge rather
--   than staged to a transient table. The merge upsert references that CTE once.
--   The soft-delete step re-reads vw_elt_metrics to find absent record_ids -- so the
--   view executes ~2x per cycle. Because the view calls current_timestamp() /
--   current_date() internally (snapshot_date, anchor_date_calc), the two executions
--   can return slightly different volatile values within one run; this is harmless
--   because volatile columns are excluded from record_id and row_hash. If view cost
--   becomes a concern at the 30-min cadence, switch to a transient staging table so
--   the view runs exactly once (see plan Step 2.1).
-- =============================================================================

create or replace procedure finance_db.dev_netsuite.sp_merge_fact_pbt_finance_metrics()
returns string
language sql
as
$$
declare
    rows_inserted integer default 0;
    rows_updated  integer default 0;
    rows_deleted  integer default 0;
    result_msg    string;
begin

    -- -------------------------------------------------------------------------
    -- 1) Upsert: insert new rows, update only rows whose content actually changed,
    --    and silently refresh volatile columns on matched-unchanged rows.
    -- -------------------------------------------------------------------------
    merge into finance_db.dev_netsuite.fact_pbt_finance_metrics m
    using
    (
        with v as
        (
            select
                e.report_month,
                e.source,
                e.product,
                e.type,
                e.core_ent_flag,
                e.direct_ecomm_flag,
                e.direct_indirect,
                e.order_type_final,
                e.amount_usd,
                e.acv,
                e.acv_prior,
                e.my,
                e.invoice_no,
                e.product_for_reporting,
                e.product_name,
                e.product_parent,
                e.product_hub,
                e.pbt_group,
                e.date,
                e.globalultimateparentupperclean,

                -- O-1: view emits multiyear_flag as varchar 'Y'/'N'; table is multiyear_flag int
                case when e.multiyear_flag = 'Y' then 1
                    else 0
                    end as multiyear_flag,
                e.status_inq_pull,
                e.billing_period,
                e.new_expansion,
                e.region,
                e.data_valid_thru,
                e.snapshot_date,
                e.snapshot_date_offset,
                e.pf_hold_flag,
                e.pf_hold_amount,
                e.closedate,
                e.saletype,
                e.currency,
                e.anchor_date_calc,
                e.license_renewal,
                e.billing_category,
                e.source_group,
                e.in_month_flag,
                e.in_quarter_flag,
                e.in_current_year_flag,
                e.in_prev_quarter_flag
            from
                finance_db.dev_netsuite.vw_elt_metrics e
        )
        select
            v.report_month,
            v.source,
            v.product,
            v.type,
            v.core_ent_flag,
            v.direct_ecomm_flag,
            v.direct_indirect,
            v.order_type_final,
            v.amount_usd,
            v.acv,
            v.acv_prior,
            v.my,
            v.invoice_no,
            v.product_for_reporting,
            v.product_name,
            v.product_parent,
            v.product_hub,
            v.pbt_group,
            v.date,
            v.globalultimateparentupperclean,
            v.multiyear_flag,
            v.status_inq_pull,
            v.billing_period,
            v.new_expansion,
            v.region,
            v.data_valid_thru,
            v.snapshot_date,
            v.snapshot_date_offset,
            v.pf_hold_flag,
            v.pf_hold_amount,
            v.closedate,
            v.saletype,
            v.currency,
            v.anchor_date_calc,
            v.license_renewal,
            v.billing_category,
            v.source_group,
            v.in_month_flag,
            v.in_quarter_flag,
            v.in_current_year_flag,
            v.in_prev_quarter_flag,

            -- record_id: deterministic grain key over all dimension columns (plan 4.1)
            md5(
                concat_ws('||',
                    coalesce(v.source, ''),
                    coalesce(to_varchar(v.report_month), ''),
                    coalesce(v.product, ''),
                    coalesce(v.type, ''),
                    coalesce(v.core_ent_flag, ''),
                    coalesce(v.direct_ecomm_flag, ''),
                    coalesce(v.direct_indirect, ''),
                    coalesce(v.order_type_final, ''),
                    coalesce(v.invoice_no, ''),
                    coalesce(to_varchar(v.date), ''),
                    coalesce(v.globalultimateparentupperclean, ''),
                    coalesce(v.status_inq_pull, ''),
                    coalesce(v.billing_period, ''),
                    coalesce(v.new_expansion, ''),
                    coalesce(v.region, ''),
                    coalesce(v.product_for_reporting, ''),
                    coalesce(v.product_name, ''),
                    coalesce(v.product_parent, ''),
                    coalesce(v.product_hub, ''),
                    coalesce(v.pbt_group, ''),
                    coalesce(v.license_renewal, ''),
                    coalesce(v.billing_category, ''),
                    coalesce(v.source_group, '')
                )
            ) as record_id,

            -- row_hash: content hash = all record_id dimension inputs + the measures.
            -- Deliberately EXCLUDES volatile/derived columns (anchor_date_calc, in_*_flag,
            -- snapshot_date, snapshot_date_offset, data_valid_thru, currency) so they
            -- never, by themselves, mark a row as changed (plan 4.2).
            md5(
                concat_ws('||',
                    coalesce(v.source, ''),
                    coalesce(to_varchar(v.report_month), ''),
                    coalesce(v.product, ''),
                    coalesce(v.type, ''),
                    coalesce(v.core_ent_flag, ''),
                    coalesce(v.direct_ecomm_flag, ''),
                    coalesce(v.direct_indirect, ''),
                    coalesce(v.order_type_final, ''),
                    coalesce(v.invoice_no, ''),
                    coalesce(to_varchar(v.date), ''),
                    coalesce(v.globalultimateparentupperclean, ''),
                    coalesce(v.status_inq_pull, ''),
                    coalesce(v.billing_period, ''),
                    coalesce(v.new_expansion, ''),
                    coalesce(v.region, ''),
                    coalesce(v.product_for_reporting, ''),
                    coalesce(v.product_name, ''),
                    coalesce(v.product_parent, ''),
                    coalesce(v.product_hub, ''),
                    coalesce(v.pbt_group, ''),
                    coalesce(v.license_renewal, ''),
                    coalesce(v.billing_category, ''),
                    coalesce(v.source_group, ''),
                    coalesce(to_varchar(v.amount_usd), ''),
                    coalesce(to_varchar(v.acv), ''),
                    coalesce(to_varchar(v.acv_prior), ''),
                    coalesce(to_varchar(v.my), ''),
                    coalesce(to_varchar(v.multiyear_flag), ''),
                    coalesce(to_varchar(v.pf_hold_flag), ''),
                    coalesce(to_varchar(v.pf_hold_amount), ''),
                    coalesce(to_varchar(v.closedate), ''),
                    coalesce(v.saletype, '')
                )
            ) as row_hash
        from
            v
    ) s
    on m.record_id = s.record_id

    -- matched, content changed -> full update + bump watermark, clear any tombstone
    when matched and m.row_hash <> s.row_hash then update set
        m.row_hash = s.row_hash,
        m.acv = s.acv,
        m.acv_prior = s.acv_prior,
        m.amount_usd = s.amount_usd,
        m.anchor_date_calc = s.anchor_date_calc,
        m.billing_category = s.billing_category,
        m.billing_period = s.billing_period,
        m.closedate = s.closedate,
        m.core_ent_flag = s.core_ent_flag,
        m.currency = s.currency,
        m.data_valid_thru = s.data_valid_thru,
        m.date = s.date,
        m.direct_ecomm_flag = s.direct_ecomm_flag,
        m.direct_indirect = s.direct_indirect,
        m.globalultimateparentupperclean = s.globalultimateparentupperclean,
        m.in_current_year_flag = s.in_current_year_flag,
        m.in_month_flag = s.in_month_flag,
        m.in_prev_quarter_flag = s.in_prev_quarter_flag,
        m.in_quarter_flag = s.in_quarter_flag,
        m.invoice_no = s.invoice_no,
        m.is_deleted = false,
        m.last_updated_at = current_timestamp(),
        m.license_renewal = s.license_renewal,
        m.my = s.my,
        m.multiyear_flag = s.multiyear_flag,
        m.new_expansion = s.new_expansion,
        m.order_type_final = s.order_type_final,
        m.pbt_group = s.pbt_group,
        m.pf_hold_amount = s.pf_hold_amount,
        m.pf_hold_flag = s.pf_hold_flag,
        m.product = s.product,
        m.product_for_reporting = s.product_for_reporting,
        m.product_hub = s.product_hub,
        m.product_name = s.product_name,
        m.product_parent = s.product_parent,
        m.region = s.region,
        m.report_month = s.report_month,
        m.saletype = s.saletype,
        m.snapshot_date = s.snapshot_date,
        m.snapshot_date_offset = s.snapshot_date_offset,
        m.source = s.source,
        m.source_group = s.source_group,
        m.status_inq_pull = s.status_inq_pull,
        m.type = s.type

    -- matched, content unchanged -> O-2: silently refresh the volatile/derived
    -- columns only; do NOT touch last_updated_at (so Data Cloud sees no change).
    -- Also un-delete a reappeared row without bumping the watermark.
    when matched and m.row_hash = s.row_hash then update set
        m.anchor_date_calc = s.anchor_date_calc,
        m.currency = s.currency,
        m.data_valid_thru = s.data_valid_thru,
        m.in_current_year_flag = s.in_current_year_flag,
        m.in_month_flag = s.in_month_flag,
        m.in_prev_quarter_flag = s.in_prev_quarter_flag,
        m.in_quarter_flag = s.in_quarter_flag,
        m.snapshot_date = s.snapshot_date,
        m.snapshot_date_offset = s.snapshot_date_offset,
        m.is_deleted = false

    -- not matched -> brand new row
    when not matched then insert
    (
        record_id,
        row_hash,
        acv,
        acv_prior,
        amount_usd,
        anchor_date_calc,
        billing_category,
        billing_period,
        closedate,
        core_ent_flag,
        currency,
        data_valid_thru,
        date,
        direct_ecomm_flag,
        direct_indirect,
        globalultimateparentupperclean,
        in_current_year_flag,
        in_month_flag,
        in_prev_quarter_flag,
        in_quarter_flag,
        invoice_no,
        is_deleted,
        last_updated_at,
        license_renewal,
        my,
        multiyear_flag,
        new_expansion,
        order_type_final,
        pbt_group,
        pf_hold_amount,
        pf_hold_flag,
        product,
        product_for_reporting,
        product_hub,
        product_name,
        product_parent,
        region,
        report_month,
        saletype,
        snapshot_date,
        snapshot_date_offset,
        source,
        source_group,
        status_inq_pull,
        type
    )
    values
    (
        s.record_id,
        s.row_hash,
        s.acv,
        s.acv_prior,
        s.amount_usd,
        s.anchor_date_calc,
        s.billing_category,
        s.billing_period,
        s.closedate,
        s.core_ent_flag,
        s.currency,
        s.data_valid_thru,
        s.date,
        s.direct_ecomm_flag,
        s.direct_indirect,
        s.globalultimateparentupperclean,
        s.in_current_year_flag,
        s.in_month_flag,
        s.in_prev_quarter_flag,
        s.in_quarter_flag,
        s.invoice_no,
        false,
        current_timestamp(),
        s.license_renewal,
        s.my,
        s.multiyear_flag,
        s.new_expansion,
        s.order_type_final,
        s.pbt_group,
        s.pf_hold_amount,
        s.pf_hold_flag,
        s.product,
        s.product_for_reporting,
        s.product_hub,
        s.product_name,
        s.product_parent,
        s.region,
        s.report_month,
        s.saletype,
        s.snapshot_date,
        s.snapshot_date_offset,
        s.source,
        s.source_group,
        s.status_inq_pull,
        s.type
    );

    -- capture insert/update counts from the merge
    select
        coalesce(s.number_of_rows_inserted, 0),
        coalesce(s.number_of_rows_updated, 0)
    into
        :rows_inserted,
        :rows_updated
    from
        table(result_scan(last_query_id())) s;

    -- -------------------------------------------------------------------------
    -- 2) Soft-delete: rows present in the target but absent from the current
    --    view snapshot, and not already tombstoned. Bumps the watermark so
    --    Data Cloud picks up the deletion on its next incremental read.
    -- -------------------------------------------------------------------------
    update finance_db.dev_netsuite.fact_pbt_finance_metrics t
    set
        t.is_deleted = true,
        t.last_updated_at = current_timestamp()
    where
        t.is_deleted = false
        and not exists
        (
            select 1
            from
            (
                with v as
                (
                    select
                        e.source,
                        e.report_month,
                        e.product,
                        e.type,
                        e.core_ent_flag,
                        e.direct_ecomm_flag,
                        e.direct_indirect,
                        e.order_type_final,
                        e.invoice_no,
                        e.date,
                        e.globalultimateparentupperclean,
                        e.status_inq_pull,
                        e.billing_period,
                        e.new_expansion,
                        e.region,
                        e.product_for_reporting,
                        e.product_name,
                        e.product_parent,
                        e.product_hub,
                        e.pbt_group,
                        e.license_renewal,
                        e.billing_category,
                        e.source_group
                    from
                        finance_db.dev_netsuite.vw_elt_metrics e
                )
                select
                    md5(
                        concat_ws('||',
                            coalesce(v.source, ''),
                            coalesce(to_varchar(v.report_month), ''),
                            coalesce(v.product, ''),
                            coalesce(v.type, ''),
                            coalesce(v.core_ent_flag, ''),
                            coalesce(v.direct_ecomm_flag, ''),
                            coalesce(v.direct_indirect, ''),
                            coalesce(v.order_type_final, ''),
                            coalesce(v.invoice_no, ''),
                            coalesce(to_varchar(v.date), ''),
                            coalesce(v.globalultimateparentupperclean, ''),
                            coalesce(v.status_inq_pull, ''),
                            coalesce(v.billing_period, ''),
                            coalesce(v.new_expansion, ''),
                            coalesce(v.region, ''),
                            coalesce(v.product_for_reporting, ''),
                            coalesce(v.product_name, ''),
                            coalesce(v.product_parent, ''),
                            coalesce(v.product_hub, ''),
                            coalesce(v.pbt_group, ''),
                            coalesce(v.license_renewal, ''),
                            coalesce(v.billing_category, ''),
                            coalesce(v.source_group, '')
                        )
                    ) as record_id
                from
                    v
            ) s
            where s.record_id = t.record_id
        );

    rows_deleted := sqlrowcount;

    result_msg := 'sp_merge_fact_pbt_finance_metrics complete. '
        || 'inserted=' || :rows_inserted
        || ', updated=' || :rows_updated
        || ', soft_deleted=' || :rows_deleted;

    return result_msg;

exception
    when other then
        return 'ERROR in sp_merge_fact_pbt_finance_metrics: ' || sqlerrm;
end;
$$
;
