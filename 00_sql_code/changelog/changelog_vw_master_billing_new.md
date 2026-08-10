# Changelog: vw_master_billing → vw_master_billing_new

**Comparing:** `finance_db.public.vw_master_billing` (original) vs. `finance_db.dev_netsuite.vw_master_billing_new`

A deliberate straight copy of the original view. Dan's call (08/10/2026): repoint and rename only, no restructuring — see Deferred work below for what was considered and set aside.

## Changes

That's the complete list. `diff` between the two files shows nothing else.

1. **View target** — `finance_db.public.vw_master_billing` → `finance_db.dev_netsuite.vw_master_billing_new`.
2. **Base table, 2 references** (the `scaffold` CTE and the `combined` CTE) — `finance_db.public.master_billing` → `finance_db.dev_netsuite.master_billing_new`.
3. **`product_group` → `productgroup`, 3 references** — the base-branch pull, the scaffold-branch null stub, and the final SELECT. This is a genuine rename in `master_billing_new`'s DDL.
4. **`entity` omitted** — 3 references (base branch, scaffold null stub, final SELECT). `master_billing_new` does not carry the column, so the view cannot expose it. Output goes from 116 columns to 115; the relative order of the remaining 115 is unchanged. `transaction_id` and `boomi_external_id` are present — `sp_master_billing_new` gained them on 08/10/2026.
5. Dated line added to the header comment block.

## Deliberately unchanged
- **`finance_db.public.dim_product_dm_hierarchy_tbl`** stays on `public`. Standing rule: this dim table is always referenced from `public`, never `dev_netsuite`. The `pbt_group` join is untouched.
- **`date_of_first_sale`** — not renamed, and worth stating because it looks like it should be. `master_billing_new`'s DDL still declares the column as `date_of_first_sale`; `sp_master_billing_new`'s final SELECT supplies `m.dateoffirstsale`, and the CTAS maps those by position. So `dateoffirstsale` never becomes a table column name — it only exists inside the SP's CTE chain.
- **Everything else** — the date scaffold, the synthetic `invoiceno`, the `pbt_group` join, `annualized_fc_acv`, the `core_ent_flag` CASE, the `master_billing_id` `row_number()`, all formatting and comments: byte-for-byte identical to the original.

## Missing vs. the original view
`entity` is the only gap. It's in `public.vw_master_billing` but not here, because `master_billing_new` doesn't carry it.

`transaction_id` and `boomi_external_id` were also missing when this view was first written, and are now present — `sp_master_billing_new` added them on 08/10/2026, wrapped in `max()` in the `main` CTE so they stay out of the `group by all` grouping set. See `changelog_sp_master_billing_new.md` for why that matters and what `max()` costs.

**Downstream impact:** anything reading `entity` from the production view will find it absent here. Closing it takes two lines here plus three in the SP — see the SP changelog.

## Validation
`00_sql_code/validation/vw_master_billing_new_validation.sql` — same shape as `master_billing_new_validation.sql`: `original` and `new` aggregate CTEs, then `summary_compare` and `dimension_diffs`. Dimensions are `direct_ecomm_flag`, `direct_indirect`, `product_name`, `naics_sector`, `ship_region`.

Clean result: 0 rows in `dimension_diffs`, matching totals in `summary_compare`.

Scaffold rows fold into the aggregates alongside real billing rows — a scaffold cardinality change still surfaces as a `row_count` diff, so it needs no separate check.

**What this validation actually tests.** Because the view logic is identical, any diff means `master_billing_new` and `master_billing` disagree — this is a test of the two base tables seen through identical logic, not of the view. When something fails, `master_billing_new_validation.sql` is where you diagnose it.

`productgroup` values are not compared directly. The rename is a positional passthrough of an already-validated table column, so a value problem would originate in the table, not the view.

### First run, 08/10/2026 — ~200 fewer rows, `total_amount_usd` matches exactly
Row count in the `new` section came in roughly 200 short of `original`, with the dollar total correct. Diagnosis in progress; the leading cause is scaffold cardinality.

`scaffold` is a `select distinct` over 15 dimension columns that requires **all 15 to be non-null**, cross joined to `date_scaff`. Scaffold rows carry `null amount_usd`, so losing them moves the row count without touching a dollar — that pairing is close to a signature. `master_billing_new` has **44 fewer distinct qualifying dimension combinations** than `master_billing` (measured 08/10/2026). At 4 `date_scaff` rows — it filters to the current calendar year, so as of August 2026 it emits Sep–Dec only — that's 176 rows, leaving a possible residual to account for.

Why the base tables can validate clean and still differ here: `master_billing_new_validation.sql` only compares `direct_ecomm_flag`, `direct_indirect`, and `product_name`. The other twelve scaffold dimensions have never been compared — `product_for_reporting_ns`, `product_for_reporting_group_ns`, `product_for_reporting_ns_alias`, `product_for_reporting_ns_alias_combined`, `product_name_group`, `core_noncore`, `order_type_final`, `billing_term`, `core_ent_flag`, `sisense_product_rollup`, `new_expansion`, `stream_reporting`. One extra null in any of them drops a row from the scaffold; a combination that stops appearing at all costs 4 rows. This is exactly where the refactor changed behavior — the new SP sources product dimensions from `dim_product_dm_hierarchy_tbl` instead of CASE logic, and a join miss yields null where the CASE had an `else` fallback.

**Still to confirm:** split the gap by `ver_date is null` (scaffold) vs `not null` (base). If the base half is 0, the gap is entirely scaffold — benign for totals, but 44 dimension combinations lose their forced zero row for Sep–Dec 2026, so downstream views relying on the scaffold to render a visible zero will show a gap instead. If the base half is non-zero, `master_billing_new` is missing real billing rows whose amounts net to zero (offsetting credits/debits are the usual cause), and that belongs in the SP, not here.

**Next step:** per-column null comparison across the 12 uncompared dimensions to identify which one is going null.

## Deferred work
An optimized version was built and then set aside in favour of the straight copy. Recording it here so the analysis isn't lost if it comes up again. None of this is in the current file.

**Two performance issues, both still present:**
- The `scaffold` CTE cross joins the *entire* base table against 12 date rows and only then applies `select distinct` — every base row fans 12× before de-duplication. Splitting the distinct into its own CTE ahead of the cross join cuts the input to a few thousand rows.
- `master_billing_id` is a `row_number()` over 10 sort keys across the whole combined set, forcing a full sort of every base row. `master_billing_new` has a populated identity `master_billing_id` that could be passed through, with scaffold rows offset above `max()`, so only the scaffold needs sorting. Rejected because it changes id values.

**One redundant join, still present:** `master_billing_new` already carries `pbt_group`, so the `dim_product_dm_hierarchy_tbl` join is no longer needed. Removing it would also drop the fan-out risk on its OR-key condition.

**Two latent type issues, both still present:**
- Scaffold branch `year` is a number (`year(current_date())`) while the base branch is `varchar(50)`. Snowflake coerces across the union, so it works, but it's accidental.
- `externalid` and `sfdc_line_item_owner_role` are `null` in *both* union branches, leaving Snowflake nothing to infer a type from.

**Three columns available but not exposed:** `contract_length_raw`, `billing_category`, and `pbt_group` direct from the table.

**Style debt retained** to keep the copy faithful: the `//` comment, `full outer join ... on 1=1` (a cross join in disguise), aliases without `as`, `where not x is null`, and three unqualified column references (`core_ent_flag`, `sfdc_account_name`, `averagerate`).

## Open item
**`stream_reporting` is null on scaffold rows.** The 01/23/2026 change added it as a scaffold dimension — it appears in the distinct list and gets a not-null filter, so it constrains which scaffold rows exist — but the scaffold branch of `combined` emits `null stream_reporting`, so the value never reaches the output. Looks like the change only half-landed. Present in the original and preserved here; check 6 in the validation script confirms both views behave the same. Worth confirming whether emitting it was the intent.
