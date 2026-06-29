# Schema Catalog — finance_db

Tracked objects across all SQL Analysis sessions. Add entries as new tables/views are worked on.

---

## finance_db.ingest
Staging schema. Always reference as-is regardless of dev/prod context.

| Object | Type | Description | Notes |
|---|---|---|---|
| `ns_ss546_cm_pm_stg` | Table | NetSuite SS546 — current + prior month | Refreshed hourly. Filter: `where a.ver_date = (select max(ver_date) from finance_db.ingest.ns_ss546_cm_pm_stg)` |
| `ns_ss546_stat_stg` | Table | NetSuite SS546 — full history | Refreshed daily. Filter: `where to_date(a.ver_date) = (select max(to_date(ver_date)) from finance_db.ingest.ns_ss546_stat_stg s)` — use a different alias in the subquery to avoid correlated subquery error |
| `employee_stg_tbl` | Table | Salesperson lookup | Join: `a.salesperson = e.employee_id and to_date(e.ver_date) = (select max_ver_date from employee_max)`. Always pre-compute max ver_date in a CTE. |

---

## finance_db.public
Production schema. Reference tables that always stay in `public` even when building in `dev_netsuite`.

| Object | Type | Description | Notes |
|---|---|---|---|
| `dim_globalultimateparent_map` | Table | Global Ultimate Parent mapping | Join: `upper(u.globalultimateparent) = upper(g.globalultimateparent_orig)`. Always reference from `public`. |
| `dim_product_dm_hierarchy_tbl` | Table | Product dimension hierarchy | Join key: `upper(concat(sisense_product_rollup_calc,'_',direct_ecomm_flag)) = p.lookup_map_upper`. Always reference from `public`. See columns below. |
| `vw_ns_ss546` | View | NetSuite SS546 billing transaction lines (production) | Grain: one row per transaction line. To be replaced by `dev_netsuite.vw_ns_ss546_new` upon promotion. |
| `pf_billings` | Table | Proforma billing rows from acquired companies not yet in NetSuite | Grain: one row per billing line. No invoice number — joins to master_billing as a union branch only. See columns and notes below. |

### pf_billings columns
`product`, `order_type`, `amount_usd`, `date`, `stream`, `contract_start_date`, `contract_end_date`, `ver_date`, `direct_ecomm_flag`, `product_for_reporting_ns`, `product_for_reporting_group_ns`, `product_for_reporting_ns_alias`, `product_for_reporting_ns_alias_combined`, `reporting_status`, `salesperson_location`

**Key observations from sample data (05/17/2026):**
- `reporting_status` is populated (value: `PROFORMA`) — pulled directly in raw_union, not hard-coded.
- `salesperson_location` is populated (e.g. `Somerville`) — now pulled directly as `ns_salesperson_location` in master_billing_new raw_union (fixed 05/17/2026).
- All four product alias fields (`product_for_reporting_ns`, `product_for_reporting_group_ns`, `product_for_reporting_ns_alias`, `product_for_reporting_ns_alias_combined`) are **already populated** in the source — proforma rows carry real product classification data. This means the `product_name`, `core_noncore`, `direct_indirect`, and `product_name_group` CASE logic in `main` should already resolve correctly for proforma rows without additional stub handling.
- `stream` maps to `incomeaccountname` and `itemcategoryhidden`/`sbitemcategory1` in the union — values include `SaaS`, `Professional Services`, `Term License`, `Perpetual License`, `Maintenance`.
- No `amount` column separate from `amount_usd` — both union branches map `p.amount_usd` to both fields.
- No `ver_date` filter documented; assumed full table scan (no snapshot pattern).

### dim_product_dm_hierarchy_tbl columns
`sisense_product_rollup_map`, `direct_ecomm_map`, `lookup_map_upper`, `proforma_lookup_upper`, `sfdc_lookup_upper`, `sfdc_open_pipe_lookup_upper`, `direct_indirect`, `core_noncore`, `pbt_group`, `ai`, `product_for_reporting`, `product_name`, `product_parent`, `product_name_group`, `product_hub`, `productgroup`, `product_for_reporting_ns`, `product_for_reporting_group_ns`, `product_for_reporting_ns_alias`, `product_for_reporting_ns_alias_combined`, `product_group_map`

**Note (05/18/2026):** `productgroup` and `product_group_map` are two distinct columns. `product_group_map` is the column added during the master_billing_new refactor (formerly named `product_group` before rename). `productgroup` is the original pre-existing column. Column order above matches the source table as of 05/18/2026.

---

## finance_db.dev_netsuite
Development schema. Default target for all new/rewritten code.

| Object | Type | Description | Notes |
|---|---|---|---|
| `vw_ns_ss546` | View | Refactored NetSuite SS546 view | Validated 05/15/2026 against `public.vw_ns_ss546`. |
| `vw_ns_ss546_new` | View | Further refactored — raw union only, all transforms in `main` CTE, product columns from dim table | Validated 05/15/2026. Temporary name — will be promoted to `public.vw_ns_ss546`. File: `00_sql_code/vw_ns_ss546_new.sql` |
| `vw_naics_mapping_new` | View | NAICS classification hierarchy from Snowflake Marketplace | Walks parent_classification_code up to 4 levels to resolve sector. Temporary name — staying in dev_netsuite for now. Source: Marketplace shared table. File: `00_sql_code/vw_naics_mapping_new.sql`. Validation: `00_sql_code/vw_naics_mapping_new_validation.sql`. TODO: confirm whether `naics_industry_description` should differ from `naics_industry_title`. |
| `vw_sfdc_invoice_data` | View | Deduplicated SFDC invoice lookup — one row per invoice | Sourced from `sfdc_db.public.sfdc_opps_tbl` and `sfdc_db.public.sfdc_license_booking_allopps`. Outputs: `invoice_no`, `sfdc_closedate`, `sfdc_location` (India normalized to Bangalore), `sfdc_core_ent_flag` (defaults to `'Core'`), `sfdc_account_name`. Invoices appearing more than once are excluded to prevent fan-out joins. Join: `left join finance_db.dev_netsuite.vw_sfdc_invoice_data sf on u.invoiceno = sf.invoice_no`. File: `00_sql_code/vw_sfdc_invoice_data.sql` |
| `master_billing_new` | Table | Central billing fact table — AS REPORTED actuals unioned with PROFORMA rows | Sources: `dev_netsuite.vw_ns_ss546_new`, `public.pf_billings`. CTE chain: `proforma_raw` → `raw_union` → `tiers` → `main` → final SELECT. `proforma_raw` joins `pf_billings` to `dim_product_dm_hierarchy_tbl` to resolve product alias fields before the union. Joins in main: `vw_sfdc_invoice_data`, `dim_country_map`, `tiers`. Joins in final SELECT: `dim_product_group_map`, `vw_naics_mapping_new`. Temporary name — will be promoted to `public.master_billing`. File: `00_sql_code/master_billing_new.sql` |
| `arr_master_new` | Table | Central ARR/ACV fact table — AS REPORTED actuals unioned with PROFORMA rows | Sources: `dev_netsuite.vw_ns_ss546_new`, `public.arr_master_proforma`. CTE chain: `prod_map` → `raw_union` → `main` → final SELECT. Joins in main: `dim_globalultimateparent_map`, `vw_sfdc_invoice_data`, `prod_map`. Temporary name — will replace `public.arr_master`. File: `00_sql_code/arr_master_new.sql` |

### arr_master_proforma columns (DDL confirmed 05/18/2026)
`datasource`, `key`, `invoiceno`, `vendoramount` (→ `amount_usd`), `acv_billings`, `acv`, `maintenanceenddate` (→ `contractitemenddate`), `maintenancestartdate` (→ `contractitemstartdate`), `contractitemterm` (pulled directly — confirmed in DDL after MAINTENANCESTARTDATE), `createdfrom` (present in DDL but removed from ARR_MASTER per 01/14/2026), `currency`, `customercategory`, `customersite`, `date`, `dateoffirstsale`, `documentnumber`, `duns`, `entitynohierarchy`, `externalid` (→ `transexternalid`), `globalultimateparent`, `globalultimateparentupper`, `itemtype`, `sbitemcategory` (→ `sbitemcategory1` — no trailing `1` in DDL), `itemid`, `lineid`, `lineofbusiness`, `listrate`, `naics`, `name`, `ordertype`, `ordertype1`, `pochecknumber` (present in DDL but removed from ARR_MASTER per 01/14/2026), `pricelevel`, `product`, `productline` (present in DDL but removed from ARR_MASTER per 01/14/2026), `quantity`, `quantitytype`, `sfdctype`, `sic`, `templatename`, `terms`, `transactiondiscount`, `type`, `vsoeallocation`, `vsoeamount`, `productgroup`, `contractdays` (→ `length_days`), `plan_amt`, `flag_plan`, `flag_proforma`, `source`, `itemcategoryhidden`, `region`, `naics_sector` (present in DDL — pulled directly, no stub needed)
