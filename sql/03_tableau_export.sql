-- =====================================================================
-- 03_tableau_export.sql
-- Tableau Public cannot connect to BigQuery, so the results are saved
-- as CSV and loaded into Tableau:
--   sales_monthly.csv -> this query
--   funnel / channels -> Q4 in 02_analysis.sql
--   cohorts           -> Q5 in 02_analysis.sql
--   rfm               -> Q6 in 02_analysis.sql
-- Window: 2024-11-01 to 2026-10-31 (fixed, because Google regenerates the dataset)
-- Note: do not sum 'orders' across categories in Tableau (an order with
-- items in several categories would be counted more than once).
-- =====================================================================

SELECT
  DATE_TRUNC(DATE(oi.created_at), MONTH) AS month,
  p.category,
  p.department,
  u.country,
  COUNT(DISTINCT oi.order_id) AS orders,
  COUNT(*) AS items,
  ROUND(SUM(IF(oi.status NOT IN ('Cancelled', 'Returned'), oi.sale_price, 0)), 2) AS revenue,
  ROUND(SUM(IF(oi.status NOT IN ('Cancelled', 'Returned'), oi.sale_price - p.cost, 0)), 2) AS gross_profit,
  COUNTIF(oi.status = 'Returned') AS returned_items,
  COUNTIF(oi.status = 'Cancelled') AS cancelled_items
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON p.id = oi.product_id
JOIN `bigquery-public-data.thelook_ecommerce.users` AS u
  ON u.id = oi.user_id
WHERE
  DATE(oi.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
GROUP BY
  month,
  p.category,
  p.department,
  u.country
ORDER BY
  month,
  p.category,
  p.department,
  u.country;
