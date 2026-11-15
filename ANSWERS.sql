-- The questions on misata.studio/datasets/hospital-encounters-claims, each with the query that answers it.
-- Run in DuckDB from this folder: duckdb < ANSWERS.sql

create view claims as select * from 'claims.csv';
create view diagnoses as select * from 'diagnoses.csv';
create view encounters as select * from 'encounters.csv';
create view lab_results as select * from 'lab_results.csv';
create view patients as select * from 'patients.csv';
create view prescriptions as select * from 'prescriptions.csv';
create view providers as select * from 'providers.csv';

-- 1. Which payers deny the most claims, and for what reasons?
-- other denies the most (10.3%), most often coding_error.
with reasons as (
  select payer, denial_reason, count(*) as denials,
         row_number() over (partition by payer order by count(*) desc, denial_reason) as rank_in_payer
  from claims
  where status = 'denied'
  group by payer, denial_reason
),
payers as (
  select payer, count(*) as claims,
         sum(case when status = 'denied' then 1 else 0 end) as denied
  from claims
  group by payer
)
select p.payer, p.claims, p.denied,
       round(100.0 * p.denied / p.claims, 1) as denial_rate_pct,
       r.denial_reason as top_reason, r.denials as top_reason_denials
from payers p
left join reasons r on r.payer = p.payer and r.rank_in_payer = 1
order by denial_rate_pct desc;

-- 2. What is the average length of stay by diagnosis category?
-- Longest average stay: gynecologic (1.17 days), shortest: urologic (0.46 days).
-- An encounter with diagnoses in several categories counts once in each.
select d.category,
       count(distinct e.encounter_id) as encounters,
       round(avg(e.los_hours) / 24, 2) as avg_stay_days,
       round(percentile_cont(0.5) within group (order by e.los_hours), 1) as median_stay_hours
from (select distinct encounter_id, category from diagnoses) d
join encounters e on e.encounter_id = d.encounter_id
group by d.category
order by avg_stay_days desc;

-- 3. How much of billed revenue is finally paid?
-- Payers paid $7,938,924 of $18,033,950 billed, 44.0%.
select status,
       count(*) as claims,
       round(sum(billed_amount), 2) as billed,
       round(sum(coalesce(allowed_amount, 0)), 2) as allowed,
       round(sum(coalesce(paid_amount, 0)), 2) as paid_by_payer,
       round(sum(coalesce(patient_responsibility, 0)), 2) as patient_responsibility,
       round(100 * sum(coalesce(paid_amount, 0)) / sum(billed_amount), 1) as paid_pct_of_billed
from claims
group by status
order by billed desc;

-- 4. Which lab flags cluster around which diagnoses?
-- The strongest cluster: LDL cholesterol is abnormal in 70.2% of musculoskeletal encounters against 63.7% overall.
-- Abnormal share of each analyte within encounters coded with each category; pairs with at least 50 results.
with labs as (
  select d.category, l.analyte, l.flag
  from lab_results l
  join (select distinct encounter_id, category from diagnoses) d on d.encounter_id = l.encounter_id
),
base as (
  select analyte, 100.0 * sum(case when flag <> 'normal' then 1 else 0 end) / count(*) as abnormal_pct
  from lab_results
  group by analyte
)
select x.category, x.analyte, count(*) as results,
       round(100.0 * sum(case when x.flag <> 'normal' then 1 else 0 end) / count(*), 1) as abnormal_pct,
       round(b.abnormal_pct, 1) as abnormal_pct_all_encounters
from labs x
join base b on b.analyte = x.analyte
group by x.category, x.analyte, b.abnormal_pct
having count(*) >= 50
order by 100.0 * sum(case when x.flag <> 'normal' then 1 else 0 end) / count(*) - b.abnormal_pct desc
limit 10;
