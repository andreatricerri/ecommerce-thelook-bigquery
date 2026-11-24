-- =====================================================================
-- 01_data_checks.sql
-- Dataset: bigquery-public-data.thelook_ecommerce
-- Row counts and date range of each table, to choose the analysis window
-- =====================================================================

SELECT
  'orders' AS t,
  COUNT(*) AS n,
  MIN(created_at) AS first_ts,
  MAX(created_at) AS last_ts
FROM `bigquery-public-data.thelook_ecommerce.orders`
UNION ALL
SELECT
  'order_items',
  COUNT(*),
  MIN(created_at),
  MAX(created_at)
FROM `bigquery-public-data.thelook_ecommerce.order_items`
UNION ALL
SELECT
  'users',
  COUNT(*),
  MIN(created_at),
  MAX(created_at)
FROM `bigquery-public-data.thelook_ecommerce.users`
UNION ALL
SELECT
  'events',
  COUNT(*),
  MIN(created_at),
  MAX(created_at)
FROM `bigquery-public-data.thelook_ecommerce.events`
UNION ALL
SELECT
  'products',
  COUNT(*),
  NULL,
  NULL
FROM `bigquery-public-data.thelook_ecommerce.products`;
