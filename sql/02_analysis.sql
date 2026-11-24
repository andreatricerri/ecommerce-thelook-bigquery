-- =====================================================================
-- 02_analysis.sql - eight business questions (run one at a time)
-- Window: 2024-11-01 to 2026-10-31 (fixed, because Google regenerates the dataset)
-- Revenue = sale_price of items not cancelled or returned
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Monthly KPIs: orders, revenue, margin, average order value,
--     month-over-month growth (LAG)
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month,
    COUNT(DISTINCT oi.order_id) AS orders,
    ROUND(SUM(oi.sale_price), 2) AS revenue,
    ROUND(SUM(oi.sale_price - p.cost), 2) AS gross_profit
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
    ON p.id = oi.product_id
  WHERE
    oi.status NOT IN ('Cancelled', 'Returned')
    AND DATE(oi.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
  GROUP BY
    month
)
SELECT
  month,
  orders,
  revenue,
  gross_profit,
  ROUND(SAFE_DIVIDE(revenue, orders), 2) AS avg_order_value,
  ROUND(100 * SAFE_DIVIDE(gross_profit, revenue), 1) AS gross_margin_pct,
  ROUND(
    100 * SAFE_DIVIDE(revenue - LAG(revenue) OVER (ORDER BY month), LAG(revenue) OVER (ORDER BY month)),
    1
  ) AS revenue_growth_pct
FROM monthly
ORDER BY
  month;


-- ---------------------------------------------------------------------
-- Q2. Which categories bring the most revenue and margin?
--     SUM(SUM()) OVER () = share of total without a second query
-- ---------------------------------------------------------------------
SELECT
  p.category,
  COUNT(*) AS items_sold,
  ROUND(SUM(oi.sale_price), 2) AS revenue,
  ROUND(SUM(oi.sale_price - p.cost), 2) AS gross_profit,
  ROUND(100 * SAFE_DIVIDE(SUM(oi.sale_price - p.cost), SUM(oi.sale_price)), 1) AS gross_margin_pct,
  ROUND(100 * SUM(oi.sale_price) / SUM(SUM(oi.sale_price)) OVER (), 1) AS revenue_share_pct
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON p.id = oi.product_id
WHERE
  oi.status NOT IN ('Cancelled', 'Returned')
  AND DATE(oi.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
GROUP BY
  p.category
ORDER BY
  revenue DESC;


-- ---------------------------------------------------------------------
-- Q3. Where do we lose sales? Returns and cancellations by category
--     (categories with fewer than 500 items excluded)
-- ---------------------------------------------------------------------
SELECT
  p.category,
  COUNT(*) AS items_ordered,
  ROUND(100 * COUNTIF(oi.status = 'Returned') / COUNT(*), 1) AS return_rate_pct,
  ROUND(100 * COUNTIF(oi.status = 'Cancelled') / COUNT(*), 1) AS cancel_rate_pct,
  ROUND(SUM(IF(oi.status = 'Returned', oi.sale_price, 0)), 2) AS returned_value
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON p.id = oi.product_id
WHERE
  DATE(oi.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
GROUP BY
  p.category
HAVING
  COUNT(*) >= 500
ORDER BY
  return_rate_pct DESC;


-- ---------------------------------------------------------------------
-- Q4. Site funnel by traffic source: one row per session with LOGICAL_OR,
--     ROLLUP adds the 'All sources' total row.
--     Bug fixed: the output alias was first named traffic_source, which
--     shadowed the column in GROUP BY and left the total row empty.
--     Renaming the alias to source fixed it.
-- ---------------------------------------------------------------------
WITH sessions AS (
  SELECT
    session_id,
    ANY_VALUE(traffic_source) AS traffic_source,
    LOGICAL_OR(event_type = 'product') AS viewed_product,
    LOGICAL_OR(event_type = 'cart') AS added_to_cart,
    LOGICAL_OR(event_type = 'purchase') AS purchased
  FROM `bigquery-public-data.thelook_ecommerce.events`
  WHERE
    DATE(created_at) BETWEEN '2024-11-01' AND '2026-10-31'
  GROUP BY
    session_id
)
SELECT
  IFNULL(traffic_source, 'All sources') AS source,
  COUNT(*) AS sessions,
  COUNTIF(viewed_product) AS product_views,
  COUNTIF(added_to_cart) AS carts,
  COUNTIF(purchased) AS purchases,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(added_to_cart), COUNTIF(viewed_product)), 1) AS view_to_cart_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(purchased), COUNTIF(added_to_cart)), 1) AS cart_to_purchase_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(purchased), COUNT(*)), 2) AS conversion_rate_pct
FROM sessions
GROUP BY
  ROLLUP (traffic_source)
ORDER BY
  sessions DESC;


-- ---------------------------------------------------------------------
-- Q5. Do customers come back? Monthly cohort retention
--     cohort = month of first purchase; FIRST_VALUE = cohort size
-- ---------------------------------------------------------------------
WITH customer_months AS (
  SELECT DISTINCT
    user_id,
    DATE_TRUNC(DATE(created_at), MONTH) AS order_month
  FROM `bigquery-public-data.thelook_ecommerce.orders`
  WHERE
    status NOT IN ('Cancelled', 'Returned')
    AND DATE(created_at) BETWEEN '2024-11-01' AND '2026-10-31'
), cohorts AS (
  SELECT
    user_id,
    MIN(order_month) AS cohort_month
  FROM customer_months
  GROUP BY
    user_id
), activity AS (
  SELECT
    c.cohort_month,
    DATE_DIFF(m.order_month, c.cohort_month, MONTH) AS month_number,
    COUNT(DISTINCT m.user_id) AS active_customers
  FROM customer_months AS m
  JOIN cohorts AS c
    USING (user_id)
  GROUP BY
    1,
    2
)
SELECT
  cohort_month,
  month_number,
  active_customers,
  ROUND(
    100 * active_customers / FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month ORDER BY month_number),
    1
  ) AS retention_pct
FROM activity
ORDER BY
  cohort_month,
  month_number;


-- ---------------------------------------------------------------------
-- Q6. Which customers are worth the most? RFM segmentation with NTILE(5)
-- ---------------------------------------------------------------------
WITH customer_stats AS (
  SELECT o.user_id,
    DATE_DIFF(DATE '2026-10-31', MAX(DATE(o.created_at)), DAY) AS days_since_last_order,
    COUNT(DISTINCT o.order_id) AS orders,
    SUM(oi.sale_price) AS spend
  FROM `bigquery-public-data.thelook_ecommerce.orders` AS o
  JOIN `bigquery-public-data.thelook_ecommerce.order_items` AS oi ON oi.order_id = o.order_id
  WHERE o.status NOT IN ('Cancelled', 'Returned') AND oi.status NOT IN ('Cancelled', 'Returned')
    AND DATE(o.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
  GROUP BY o.user_id),
scored AS (
  SELECT *, NTILE(5) OVER (ORDER BY days_since_last_order DESC) AS r_score,
    NTILE(5) OVER (ORDER BY orders, spend) AS f_score,
    NTILE(5) OVER (ORDER BY spend) AS m_score
  FROM customer_stats)
SELECT CASE
    WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
    WHEN r_score >= 4 THEN 'New or occasional'
    WHEN r_score <= 2 AND m_score >= 4 THEN 'At risk, high value'
    WHEN r_score <= 2 THEN 'Lost'
    ELSE 'Needs attention' END AS segment,
  COUNT(*) AS customers, ROUND(AVG(spend), 2) AS avg_spend, ROUND(SUM(spend), 2) AS total_spend,
  ROUND(100 * SUM(spend) / SUM(SUM(spend)) OVER (), 1) AS spend_share_pct
FROM scored GROUP BY segment ORDER BY total_spend DESC;


-- ---------------------------------------------------------------------
-- Q7. Which acquisition channels bring the best customers in each of
--     the top 10 countries? (RANK by country)
-- ---------------------------------------------------------------------
WITH customer_value AS (
  SELECT
    u.id AS user_id,
    u.country,
    u.traffic_source,
    COUNT(DISTINCT oi.order_id) AS orders,
    SUM(oi.sale_price) AS spend
  FROM `bigquery-public-data.thelook_ecommerce.users` AS u
  JOIN `bigquery-public-data.thelook_ecommerce.order_items` AS oi
    ON oi.user_id = u.id
  WHERE
    oi.status NOT IN ('Cancelled', 'Returned')
    AND DATE(oi.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
  GROUP BY
    u.id,
    u.country,
    u.traffic_source
), top_countries AS (
  SELECT
    country
  FROM customer_value
  GROUP BY
    country
  ORDER BY
    SUM(spend) DESC
  LIMIT 10
)
SELECT
  country,
  traffic_source,
  COUNT(*) AS customers,
  ROUND(AVG(spend), 2) AS avg_spend_per_customer,
  ROUND(100 * COUNTIF(orders > 1) / COUNT(*), 1) AS repeat_customer_pct,
  RANK() OVER (PARTITION BY country ORDER BY AVG(spend) DESC) AS channel_rank_in_country
FROM customer_value
WHERE
  country IN (
    SELECT
      country
    FROM top_countries
  )
GROUP BY
  country,
  traffic_source
ORDER BY
  country,
  channel_rank_in_country;


-- ---------------------------------------------------------------------
-- Q8. Does logistics work? Shipping and transit time by distribution
--     centre, 90th percentile with APPROX_QUANTILES
-- ---------------------------------------------------------------------
SELECT
  dc.name AS distribution_center,
  COUNT(*) AS delivered_items,
  ROUND(AVG(TIMESTAMP_DIFF(oi.shipped_at, oi.created_at, HOUR)) / 24, 1) AS avg_days_to_ship,
  ROUND(AVG(TIMESTAMP_DIFF(oi.delivered_at, oi.shipped_at, HOUR)) / 24, 1) AS avg_days_in_transit,
  ROUND(
    APPROX_QUANTILES(TIMESTAMP_DIFF(oi.delivered_at, oi.created_at, HOUR) / 24, 100)[OFFSET(90)],
    1
  ) AS p90_total_days
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON p.id = oi.product_id
JOIN `bigquery-public-data.thelook_ecommerce.distribution_centers` AS dc
  ON dc.id = p.distribution_center_id
WHERE
  oi.delivered_at IS NOT NULL
  AND DATE(oi.created_at) BETWEEN '2024-11-01' AND '2026-10-31'
GROUP BY
  distribution_center
ORDER BY
  avg_days_in_transit DESC;
