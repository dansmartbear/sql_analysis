# Changelog: sp_master_billing → sp_master_billing_new

**Comparing:** `finance_db.public.master_billing` (original) vs. `finance_db.dev_netsuite.master_billing_new`

## Structural
- CTE chain restructured to `raw_union` → `tiers` → `main` → final SELECT. Original CTE `A` split into a pure `raw_union` (no joins/calcs) and `main` (all joins and derived fields); `mb` renamed to `main`.
- 6 inline SFDC CTEs replaced with a single `left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf` in `main`.
- `dim_country_map` join moved into `main`. `contract_length` now computed once in `raw_union` instead of repeated downstream.
- `new_expansion` and `billing_category` moved from the final SELECT into `main`.
- `naics_sector` join removed entirely — now pulled directly from `vw_ns_ss546_new` (which already performs the NAICS join upstream), eliminating a redundant join.

## Source repointing
- NetSuite source: `finance_db.public.vw_ns_ss546` → `finance_db.dev_netsuite.vw_ns_ss546_new`.
- NAICS source: `finance_db.public.vw_naics_mapping` → `finance_db.dev_netsuite.vw_naics_mapping_new` (superseded by the direct-pull change above).
- Proforma branch now joins `dim_product_dm_hierarchy_tbl ph` directly in `raw_union`.

## Column changes
- `inline_discount` pulled directly (clean decimal from the new view; empty-string guard removed).
- `product_name`, `core_noncore`, `direct_indirect`, `product_name_group` pulled directly from the union — no CASE logic in `main`.
- `product_for_reporting` = `u.product_for_reporting_ns` (straight passthrough, no CASE).
- `pf_billings.salesperson_location` pulled directly as `ns_salesperson_location`.
- Added (net-new): `billing_category` (Direct License / Direct Renewal / Atlassian / SmartBear Ecomm / Uncategorized), `pbt_group` (from `dim_product_dm_hierarchy_tbl`).
- `dateoffirstsale` pulled using the source column name; aliased to `date_of_first_sale` only in the DDL.

## 08/10/2026 — transaction_id and boomi_external_id added
Production `public.master_billing` added `entity` on 06/18/2026 and `transaction_id` / `boomi_external_id` on 07/06/2026. `vw_ns_ss546_new` already exposes all three sources (`entitynohierarchy`, `transaction_id`, `boomi_external_id`) — the gap was only that `sp_master_billing_new` never pulled them through.

Two of the three are now landed. Four touch points, both columns `varchar(500)`:

1. **DDL** — appended after `pbt_group`, so they are the last two columns. DDL and final SELECT are both 114 columns and positionally aligned.
2. **`raw_union`, NS branch** — `ns.transaction_id`, `ns.boomi_external_id`.
3. **`raw_union`, proforma branch** — `''` stubs, matching how production handles the proforma side.
4. **`main`** — `max(u.transaction_id)`, `max(u.boomi_external_id)`. This is the part that matters.
5. **Final SELECT** — plain `m.` passthrough.

**Why `max()`.** `main` aggregates under `group by all` — it computes `sum(u.amount_usd)`, `sum(u.amount)`, `sum(u.acv)` and `sum(u.my)`, so every non-aggregated column in its SELECT list silently becomes a grouping key. A first attempt added the ids as plain columns and the rebuilt table stopped matching: `transaction_id` split groups that previously collapsed into one row, inflating row counts and changing the per-row sums. Wrapping in `max()` keeps them out of the grouping set, so the grain is exactly what it was before. Dan confirmed the rebuilt table matches after the change.

**`max()` is lossy, and by a measurable amount.** The plain-column attempt *did* change the output, which proves `transaction_id` varies within existing groups — some billing lines genuinely span multiple NetSuite transactions, and only one id is reported. Unquantified. To size it:

```sql
select count(*) from (
    select invoiceno, lineid, item, product, count(distinct transaction_id) c
    from finance_db.dev_netsuite.vw_ns_ss546_new
    group by 1,2,3,4
    having c > 1
);
```

If that count is material, the real fix is a grain decision, not an aggregate — production has the same `group by all` structure *and* these columns as plain grouping keys, so production's own grain already reflects the fragmentation. Matching production would mean accepting the split rows here too.

**`entity` deliberately not added.** Low-cardinality and likely functionally dependent on existing keys, so it could go in as a plain column with little grain risk — but it was left out to keep this change to one decision. Closing it would take `ns.entitynohierarchy as entity` / `'Proforma'` in `raw_union`, plus the DDL and final SELECT, and two lines in `vw_master_billing_new`.

## Remaining gaps
- `product_group`: NS branch pulls `ns.product_group`; proforma branch pulls `ph.product_group_map`. Both alias to `product_group` but aren't sourced consistently — align when `vw_ns_ss546_new` exposes `product_group_map`.

## Note on date_of_first_sale
The DDL declares this column as `date_of_first_sale` while the final SELECT supplies `m.dateoffirstsale`. The CTAS maps these by position, so the table's column name is `date_of_first_sale` — `dateoffirstsale` is only an internal alias inside the CTE chain and never surfaces. Intentional, but easy to misread as a rename; `vw_master_billing_new` must reference `date_of_first_sale`.

## Style
- Trailing commas, lowercase keywords, `--` comments throughout. All column references alias-qualified.

## Validation
`00_sql_code/validation/master_billing_new_validation.sql` — clean result: 0 rows in `dimension_diffs`, matching totals in `summary_compare` (dimensions: `direct_ecomm_flag`, `direct_indirect`, `product_name`).

## Open items
- Fan-out risk on the proforma OR join condition (`upper(p.product) = ph.lookup_map_upper OR upper(concat(p.product, '_', p.direct_ecomm_flag)) = ph.lookup_map_upper`) — verify no product matches both keys.
