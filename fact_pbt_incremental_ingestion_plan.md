# Implementation Plan — Incremental Ingestion for `FACT_PBT_FINANCE_METRICS`

**Goal:** Replace the current `create or replace table` rebuild with an incremental process that **inserts new rows, updates only changed rows, and soft-deletes removed rows** — so that Salesforce Data Cloud (DLO) reads only what actually changed, minimizing Data Cloud credit usage. A Snowflake task runs the process **every 30 minutes, starting at 12:15 AM**.

*Build and validate everything in `finance_db.dev_netsuite` first, then promote to `finance_db.public` once verified.*

---

## 1. Decisions confirmed (from our Q&A)

| Topic | Decision |
|---|---|
| **Merge key** | Deterministic hash (`record_id`) built from **all dimension columns combined** — every categorical/dimension column, excluding numeric measures. |
| **Change detection** | Content hash (`row_hash`) over **all measure + dimension columns**, excluding the key, audit columns, and volatile/derived columns. |
| **Volatile columns** | `anchor_date_calc`, the `in_*_flag` columns, `snapshot_date`, `snapshot_date_offset`, `data_valid_thru`, `currency` are **refreshed silently** and **excluded from change detection** — they must never, by themselves, mark a row as "changed." |
| **Schema** | Build/test in `finance_db.dev_netsuite`; promote to `public` after validation. |
| **Schedule owner** | A **new Snowflake task** owns the cadence (every 30 min from 12:15 AM). No external orchestrator. |

---

## 2. Problems in the current objects that must be fixed first

Before any incremental logic can work, the view and table have to reconcile. These are **blocking** issues found by comparing `vw_elt_metrics.sql` against `tbl_fact_pbt_finance_metrics.sql`:

### 2.1 No stable key
The view's final `select` emits `uuid_string() as elt_metrics_uid` — a **brand-new UUID every run**. It cannot identify "the same row" across two runs, so it is useless as a merge key. The table's `elt_metric_id varchar NOT NULL` expects a stable ID. **We replace this with a deterministic hash key (`record_id`) — see §4.**

### 2.2 Column name mismatches (view → table)
| View column | Table column | Action |
|---|---|---|
| `elt_metrics_uid` | `elt_metric_id` | Replace with `record_id` (hash); align names. |
| `globalultimateparentupperclean` | `global_ultimate_parent_upper_clean` | Map explicitly in the staging select. |
| `multiyear_flag` (varchar) | `my_flag int` | **Type + name mismatch** — confirm intended cast (see open item O-1). |
| `closedate` | `close_date` | Map explicitly. |
| `saletype` | `sale_type` | Map explicitly. |

### 2.3 Column order differs
The view's `select` order does not match the table's column order. The MERGE must reference columns **by name**, never positionally. We will build a staging layer that emits exactly the table's column names.

### 2.4 Missing audit columns
Per the Part 1 plan, the table needs three columns it does not yet have: `record_id`, `last_updated_at`, `is_deleted`. Plus we add a hidden helper, `row_hash`, for change detection.

> **None of the existing `elt_metric_id` / column-name questions were resolved in the original Part 1 plan — they are the reason this plan front-loads a reconciliation step.**

---

## 3. Target table — final column set

The production target (`fact_pbt_finance_metrics`) keeps all existing business columns and **adds four**:

| Column | Type | Purpose |
|---|---|---|
| `record_id` | `varchar(64)` | Deterministic hash of the grain columns. **Primary key** and merge key. Replaces `elt_metric_id`. |
| `row_hash` | `varchar(64)` | Hash of all content columns (measures + dimensions, excluding volatile/derived). Drives change detection. |
| `last_updated_at` | `timestamp_ntz` | Watermark Data Cloud queries against. Refreshed only on insert or real change, and on soft-delete. |
| `is_deleted` | `boolean` | Soft-delete sentinel. `false` for live rows, `true` for tombstones. |

`elt_metric_id` is retired in favor of `record_id`. (If downstream consumers reference `elt_metric_id` by name, keep it as an alias of `record_id` — see open item O-3.)

---

## 4. Key & hash design (the core of the whole approach)

Two hashes, both computed in a **staging CTE** off the view, using a null-safe pattern so that `null` and `''` don't produce unstable keys.

### 4.1 `record_id` — the grain key (all dimension columns)
Concatenate every dimension/categorical column with a delimiter, normalize nulls, then hash:

```sql
-- conceptual; final column list locked in step S-2 of the rollout
md5(
    concat_ws('||',
        coalesce(source,''),
        coalesce(to_varchar(report_month),''),
        coalesce(product,''),
        coalesce(type,''),
        coalesce(core_ent_flag,''),
        coalesce(direct_ecomm_flag,''),
        coalesce(direct_indirect,''),
        coalesce(order_type_final,''),
        coalesce(invoice_no,''),
        coalesce(to_varchar(date),''),
        coalesce(global_ultimate_parent_upper_clean,''),
        coalesce(status_inq_pull,''),
        coalesce(billing_period,''),
        coalesce(new_expansion,''),
        coalesce(region,''),
        coalesce(product_for_reporting,''),
        coalesce(product_name,''),
        coalesce(product_parent,''),
        coalesce(product_hub,''),
        coalesce(pbt_group,''),
        coalesce(license_renewal,''),
        coalesce(billing_category,''),
        coalesce(source_group,'')
    )
) as record_id
```

### 4.2 `row_hash` — content hash (drives "did it change?")
Same null-safe concat, but over **measures + dimensions that constitute meaningful content**, and **deliberately excluding** the volatile/derived columns (`anchor_date_calc`, `in_*_flag`, `snapshot_date`, `snapshot_date_offset`, `data_valid_thru`, `currency`). Includes the numeric measures (`amount_usd`, `acv`, `acv_prior`, `my`, `pf_hold_amount`, `pf_hold_flag`, `my_flag`) that are excluded from `record_id`.

```sql
md5(
    concat_ws('||',
        -- all the record_id dimension inputs, plus:
        coalesce(to_varchar(amount_usd),''),
        coalesce(to_varchar(acv),''),
        coalesce(to_varchar(acv_prior),''),
        coalesce(to_varchar(my),''),
        coalesce(to_varchar(my_flag),''),
        coalesce(to_varchar(pf_hold_flag),''),
        coalesce(to_varchar(pf_hold_amount),''),
        coalesce(to_varchar(close_date),''),
        coalesce(sale_type,'')
    )
) as row_hash
```

> **Why two hashes?** `record_id` answers *"is this the same row?"*; `row_hash` answers *"did its content change?"*. The MERGE updates only when `record_id` matches **and** `row_hash` differs.

### 4.3 Grain must be verified, not assumed
Because branches `actuals`, `scenario`, and `arr` use `group by all` (aggregated) while `sfdc`, `atla`, `stripe` are row-level, **two distinct rows could hash to the same `record_id`** (a collision → silent data loss). **Before promotion we run a profiling query** (rollout step S-2) to confirm `count(*) = count(distinct record_id)` against a full run of the view. If duplicates exist, we extend the grain (e.g. add a deterministic `row_number()` within the duplicate group) before going live.

---

## 5. The four build steps

### Step 1 — Alter the table (add audit columns, set key)
```sql
-- in finance_db.dev_netsuite (mirror to public at promotion)
alter table finance_db.dev_netsuite.fact_pbt_finance_metrics add column record_id      varchar(64);
alter table finance_db.dev_netsuite.fact_pbt_finance_metrics add column row_hash        varchar(64);
alter table finance_db.dev_netsuite.fact_pbt_finance_metrics add column last_updated_at timestamp_ntz;
alter table finance_db.dev_netsuite.fact_pbt_finance_metrics add column is_deleted      boolean default false;

-- backfill from a full view run (one-time seed), then enforce
-- update ... set record_id = <hash>, row_hash = <hash>, last_updated_at = current_timestamp(), is_deleted = false;

alter table finance_db.dev_netsuite.fact_pbt_finance_metrics alter column record_id set not null;
alter table finance_db.dev_netsuite.fact_pbt_finance_metrics add primary key (record_id);
```
*(Snowflake PKs are not enforced but document intent and help the optimizer / Data Cloud. The seed/backfill is a single `merge` from the view — same proc as Step 2 run once against an empty/rebuilt table.)*

### Step 2 — Stored procedure: `sp_merge_fact_pbt_finance_metrics`
Runs three set-based statements against a staging snapshot of the view. Pattern:

1. **Stage** the view once into a temp/transient table (or CTE inside the merge) with `record_id` + `row_hash` computed and all columns mapped to table names. This avoids running the (expensive) view multiple times.
2. **MERGE (upsert):**
   - `when matched and target.row_hash <> source.row_hash then update` → set all business columns + volatile columns, `row_hash = source.row_hash`, `is_deleted = false`, `last_updated_at = current_timestamp()`.
   - `when matched and target.row_hash = source.row_hash then update` → refresh **only** the volatile columns (anchor/flags/snapshot/valid-thru) **without** touching `last_updated_at`. *(This is what keeps the DLO from seeing a "change" every midnight.)* — see open item O-2 on whether to skip this entirely.
   - `when not matched then insert` → new row, `is_deleted = false`, `last_updated_at = current_timestamp()`.
3. **Soft-delete:** rows present in target but absent from the current view, and not already deleted:
   ```sql
   update target t
   set is_deleted = true, last_updated_at = current_timestamp()
   where t.is_deleted = false
     and not exists (select 1 from staging s where s.record_id = t.record_id);
   ```
   A row that **reappears** in the view is automatically un-deleted by the MERGE's `is_deleted = false` on match.

No physical `delete` happens in this proc — deletes are handled by Step 3.

### Step 3 — Cleanup task: `task_cleanup_fact_pbt_finance_metrics`
Physically removes tombstones after Data Cloud has had a chance to read them.
```sql
delete from finance_db.dev_netsuite.fact_pbt_finance_metrics
where is_deleted = true
  and last_updated_at < dateadd(minute, -90, current_timestamp());
```
Scheduled every 2 hours (per Part 1 plan). The 90-minute grace window guarantees at least one DLO read cycle (the DLO reads every 30 min) sees the tombstone before the row disappears.

### Step 4 — Cluster key on the watermark
```sql
alter table finance_db.dev_netsuite.fact_pbt_finance_metrics
cluster by (last_updated_at);
```
Data Cloud's incremental reads filter on `last_updated_at`; clustering lets Snowflake prune micro-partitions instead of scanning all ~2M rows each poll. *(Note: clustering incurs background reclustering credits — see open item O-4 to weigh against the savings. At 2M rows this is small.)*

---

## 6. Scheduling — every 30 min, starting 12:15 AM

The merge proc runs on a **cron-scheduled Snowflake task**. To start at **12:15 AM** and repeat **every 30 minutes** (12:15, 12:45, 1:15, 1:45 …), use two cron entries (Snowflake cron has no "offset from base" syntax, so we list both minute marks):

```sql
create or replace task finance_db.dev_netsuite.task_merge_fact_pbt_finance_metrics
    warehouse = <your_wh>
    schedule  = 'USING CRON 15,45 * * * * America/New_York'   -- :15 and :45 of every hour
as
    call finance_db.dev_netsuite.sp_merge_fact_pbt_finance_metrics();
```

This fires at xx:15 and xx:45 of **every** hour, which includes 00:15 (12:15 AM) and then every 30 minutes thereafter — exactly the requested cadence.

```sql
-- cleanup task, every 2 hours, offset so it never collides with the merge
create or replace task finance_db.dev_netsuite.task_cleanup_fact_pbt_finance_metrics
    warehouse = <your_wh>
    schedule  = 'USING CRON 0 */2 * * * America/New_York'
as
    delete from finance_db.dev_netsuite.fact_pbt_finance_metrics
    where is_deleted = true
      and last_updated_at < dateadd(minute, -90, current_timestamp());

alter task finance_db.dev_netsuite.task_merge_fact_pbt_finance_metrics resume;
alter task finance_db.dev_netsuite.task_cleanup_fact_pbt_finance_metrics resume;
```

> **Timezone:** I've assumed `America/New_York`. Confirm the timezone you want "12:15 AM" interpreted in (open item O-5). Also confirm whether the merge should run a `serverless` task or a dedicated warehouse — serverless avoids keeping a warehouse warm for a 30-min cadence.

---

## 7. Validation (required before promotion)

Per your CLAUDE.md workflow, every rewrite gets a companion validation query. We produce `fact_pbt_finance_metrics_incremental_validation.sql` covering:

1. **Grain uniqueness:** `count(*) = count(distinct record_id)` on a full view run. **Must be zero duplicates** before go-live.
2. **Parity vs. old rebuild:** row counts and `sum(amount_usd)`, `sum(acv)` between a fresh `create or replace` of the view and the post-merge table (live rows only, `is_deleted = false`). Must match exactly.
3. **No-op stability test:** run the merge twice back-to-back with no source change → second run must update **0** rows and change **0** `last_updated_at` values. *(This is the credit-savings proof.)*
4. **Change test:** modify one source value → exactly the affected `record_id`(s) update, `last_updated_at` advances only on those.
5. **Delete test:** remove a source row → its target row flips `is_deleted = true`; after the grace window the cleanup task removes it.
6. **Reappear test:** a previously deleted row returns in the view → `is_deleted` flips back to `false`.

---

## 8. Rollout sequence

| Step | Action | Output |
|---|---|---|
| **S-1** | Resolve open items O-1…O-5 below | confirmed decisions |
| **S-2** | Build staging select off the view with `record_id`/`row_hash`; run grain-uniqueness profiling | `00_sql_code/fact_pbt_staging.sql` + profiling result |
| **S-3** | Write `alter table` + one-time seed (Step 1) | `00_sql_code/fact_pbt_alter_and_seed.sql` |
| **S-4** | Write `sp_merge_fact_pbt_finance_metrics` (Step 2) | `00_sql_code/sp_merge_fact_pbt_finance_metrics.sql` |
| **S-5** | Write cleanup + cluster + tasks (Steps 3–4, §6) | `00_sql_code/fact_pbt_tasks.sql` |
| **S-6** | Write validation script (§7) | `00_sql_code/fact_pbt_incremental_validation.sql` |
| **S-7** | Run validation in `dev_netsuite`; confirm all six checks pass | green validation |
| **S-8** | Promote objects to `finance_db.public`; point DLO/watermark at `last_updated_at`; resume tasks | live |
| **S-9** | Update `MEMORY.md` with decisions | memory updated |

All `.sql` files land in `SQL Analysis/00_sql_code/` per your conventions; this plan and validation notes stay in the root.

---

## 9. Open items to confirm (S-1)

- **O-1 — `multiyear_flag` → `my_flag` (varchar → int):** The view emits `multiyear_flag` as varchar; the table column is `my_flag int`. What's the intended conversion? (e.g. `'Y'`/`'N'` → `1`/`0`, or is it already numeric-as-text?) This affects both the staging cast and the `row_hash`.
- **O-2 — Volatile-column refresh on no-content-change:** Do you want the matched-but-unchanged branch to still refresh the volatile columns (anchor/flags) in place *without* bumping `last_updated_at` (my recommended design), or skip touching those rows entirely until their content changes? The latter means flag columns can go stale between content changes — acceptable only if Data Cloud / Tableau recomputes those flags downstream.
- **O-3 — Retire vs. alias `elt_metric_id`:** Replace `elt_metric_id` with `record_id` outright, or keep `elt_metric_id` as a populated alias of `record_id` for any existing downstream references?
- **O-4 — Cluster key cost:** Confirm you're OK with background reclustering credits on `last_updated_at` (small at ~2M rows, but non-zero). Alternative: rely on natural partition pruning + a search-optimization-free approach first, add clustering only if poll scans are slow.
- **O-5 — Timezone & warehouse:** Confirm timezone for "12:15 AM" (assumed `America/New_York`) and whether tasks run serverless or on a named warehouse.

---

## 10. Note on repeatability

This whole pattern (add `record_id`/`row_hash`/`last_updated_at`/`is_deleted` → merge proc → soft-delete → cleanup task → cluster key) is **identical** for any view→DLO table you build next. It's a strong candidate for a **Claude Skill** — "Snowflake view → incremental Data Cloud table" — that takes a view name + grain columns and generates the staging select, alter/seed, merge proc, tasks, and validation script automatically. Worth creating once this first one is proven, and worth updating your Skills/preferences as the pattern settles.
