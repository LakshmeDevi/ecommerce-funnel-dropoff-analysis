-- E-Commerce Funnel Drop-off Analysis
-- Database: PostgreSQL | Data: 1% user sample of Kaggle "eCommerce behavior data" (Oct 2019)

-- 1. Create table
CREATE TABLE events (
  event_time TEXT,
  event_type TEXT,
  product_id BIGINT,
  category_id BIGINT,
  category_code TEXT,
  brand TEXT,
  price NUMERIC,
  user_id BIGINT,
  user_session TEXT
);

-- (Import events_sample.csv into this table with pgAdmin: Import/Export Data, Header on, delimiter ",")

-- 2. Check row count (expected: 419989)
SELECT COUNT(*) FROM events;

-- 3. Convert event_time from text to timestamp
ALTER TABLE events
ALTER COLUMN event_time TYPE TIMESTAMP
USING REPLACE(event_time, ' UTC', '')::timestamp;

-- 4. Raw counts per stage (not a strict funnel: some buyers have no cart event)
SELECT
  COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'view') AS viewers,
  COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'cart') AS cart_users,
  COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'purchase') AS buyers
FROM events;

-- 5. Strict funnel (each step is a subset of the previous one)
WITH u AS (
  SELECT user_id,
    bool_or(event_type = 'view') AS v,
    bool_or(event_type = 'cart') AS c,
    bool_or(event_type = 'purchase') AS p
  FROM events
  GROUP BY user_id
)
SELECT
  COUNT(*) FILTER (WHERE v) AS viewers,
  COUNT(*) FILTER (WHERE v AND c) AS cart_users,
  COUNT(*) FILTER (WHERE v AND c AND p) AS buyers
FROM u;

-- 6. Funnel shaped for the Power BI funnel chart (exported as funnel.csv)
WITH u AS (
  SELECT user_id,
    bool_or(event_type = 'view') AS v,
    bool_or(event_type = 'cart') AS c,
    bool_or(event_type = 'purchase') AS p
  FROM events
  GROUP BY user_id
)
SELECT '1. View' AS stage, COUNT(*) FILTER (WHERE v) AS users FROM u
UNION ALL
SELECT '2. Cart', COUNT(*) FILTER (WHERE v AND c) FROM u
UNION ALL
SELECT '3. Purchase', COUNT(*) FILTER (WHERE v AND c AND p) FROM u;

-- 7. Buyers without a cart event (direct buy or cart created before the period)
WITH u AS (
  SELECT user_id,
    bool_or(event_type = 'cart') AS c,
    bool_or(event_type = 'purchase') AS p
  FROM events
  GROUP BY user_id
)
SELECT
  COUNT(*) FILTER (WHERE p) AS all_buyers,
  COUNT(*) FILTER (WHERE p AND NOT c) AS buyers_without_cart
FROM u;

-- 8. Drop-off by product category (exported as category.csv)
WITH uc AS (
  SELECT user_id,
    COALESCE(NULLIF(split_part(category_code, '.', 1), ''), 'unknown') AS category,
    bool_or(event_type = 'view') AS v,
    bool_or(event_type = 'cart') AS c,
    bool_or(event_type = 'purchase') AS p
  FROM events
  GROUP BY 1, 2
)
SELECT category,
  COUNT(*) FILTER (WHERE v) AS viewers,
  COUNT(*) FILTER (WHERE v AND c) AS cart_users,
  COUNT(*) FILTER (WHERE v AND c AND p) AS buyers,
  ROUND(100.0 * (COUNT(*) FILTER (WHERE v) - COUNT(*) FILTER (WHERE v AND c))
    / NULLIF(COUNT(*) FILTER (WHERE v), 0), 1) AS drop_view_to_cart_pct,
  ROUND(100.0 * (COUNT(*) FILTER (WHERE v AND c) - COUNT(*) FILTER (WHERE v AND c AND p))
    / NULLIF(COUNT(*) FILTER (WHERE v AND c), 0), 1) AS drop_cart_to_buy_pct
FROM uc
GROUP BY category
ORDER BY viewers DESC;

-- 9. Drop-off by price band, per user-product pair (exported as price_band.csv)
WITH up AS (
  SELECT user_id, product_id,
    CASE WHEN MAX(price) < 50 THEN '1. Under 50'
         WHEN MAX(price) < 200 THEN '2. 50-200'
         WHEN MAX(price) < 500 THEN '3. 200-500'
         ELSE '4. 500+' END AS price_band,
    bool_or(event_type = 'view') AS v,
    bool_or(event_type = 'cart') AS c,
    bool_or(event_type = 'purchase') AS p
  FROM events
  WHERE price > 0
  GROUP BY user_id, product_id
)
SELECT price_band,
  COUNT(*) FILTER (WHERE v) AS viewed,
  COUNT(*) FILTER (WHERE v AND c) AS carted,
  COUNT(*) FILTER (WHERE v AND c AND p) AS bought,
  ROUND(100.0 * (COUNT(*) FILTER (WHERE v) - COUNT(*) FILTER (WHERE v AND c))
    / NULLIF(COUNT(*) FILTER (WHERE v), 0), 1) AS drop_view_to_cart_pct,
  ROUND(100.0 * (COUNT(*) FILTER (WHERE v AND c) - COUNT(*) FILTER (WHERE v AND c AND p))
    / NULLIF(COUNT(*) FILTER (WHERE v AND c), 0), 1) AS drop_cart_to_buy_pct
FROM up
GROUP BY price_band
ORDER BY price_band;