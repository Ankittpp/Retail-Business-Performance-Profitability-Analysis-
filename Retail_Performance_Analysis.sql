sql
-- 1. Create cleaned transactions table (remove nulls, standardize types)
CREATE TABLE cleaned_transactions AS
SELECT
  order_id,
  CAST(order_date AS DATE) AS order_date,
  COALESCE(region, 'Unknown') AS region,
  store_id,
  product_id,
  COALESCE(category, 'Unknown') AS category,
  COALESCE(sub_category, 'Unknown') AS sub_category,
  COALESCE(quantity, 0) AS quantity,
  COALESCE(unit_price, 0.0) AS unit_price,
  COALESCE(unit_cost, 0.0) AS unit_cost,
  COALESCE(inventory_days, NULL) AS inventory_days,
  COALESCE(supplier, 'Unknown') AS supplier,
  COALESCE(promotion_flag, 0) AS promotion_flag
FROM transactions
WHERE order_id IS NOT NULL
  AND product_id IS NOT NULL;

-- 2. Add revenue, cost, profit, margin
DROP TABLE IF EXISTS tx_financials;
CREATE TABLE tx_financials AS
SELECT
  order_id,
  order_date,
  region,
  store_id,
  product_id,
  category,
  sub_category,
  quantity,
  unit_price,
  unit_cost,
  (quantity * unit_price) AS revenue,
  (quantity * unit_cost) AS cost,
  (quantity * (unit_price - unit_cost)) AS profit,
  CASE WHEN (quantity * unit_price) = 0 THEN 0
       ELSE ROUND(100.0 * (quantity * (unit_price - unit_cost)) / (quantity * unit_price), 2)
  END AS profit_margin_pct,
  inventory_days,
  supplier,
  promotion_flag
FROM cleaned_transactions;

-- 3. Profit by category / sub-category
-- Top losing sub-categories (negative profits or low margins)
SELECT category, sub_category,
       SUM(revenue) AS total_revenue,
       SUM(cost) AS total_cost,
       SUM(profit) AS total_profit,
       ROUND(100.0 * SUM(profit) / NULLIF(SUM(revenue),0),2) AS category_margin_pct,
       COUNT(DISTINCT product_id) AS distinct_products
FROM tx_financials
GROUP BY category, sub_category
ORDER BY total_profit ASC; -- ascending to surface loss-makers

-- 4. Inventory days vs profitability per product (aggregate)
SELECT product_id,
       category,
       sub_category,
       AVG(inventory_days) AS avg_inventory_days,
       SUM(revenue) AS total_revenue,
       SUM(profit) AS total_profit,
       ROUND(100.0 * SUM(profit) / NULLIF(SUM(revenue),0),2) AS margin_pct
FROM tx_financials
GROUP BY product_id, category, sub_category
ORDER BY avg_inventory_days DESC;

-- 5. Seasonal sales (month-level)
SELECT DATE_TRUNC('month', order_date)::date AS month,
       category,
       SUM(revenue) AS month_revenue,
       SUM(profit) AS month_profit
FROM tx_financials
GROUP BY month, category
ORDER BY month, month_revenue DESC;

-- 6. Overstock / slow-moving candidates:
-- items with high inventory_days and low sales in last 90 days
WITH recent_sales AS (
  SELECT product_id, SUM(quantity) AS qty_90d
  FROM tx_financials
  WHERE order_date >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY product_id
)
SELECT p.product_id, p.category, p.sub_category, p.avg_inventory_days, COALESCE(r.qty_90d,0) AS qty_90d
FROM (
  SELECT product_id, AVG(inventory_days) AS avg_inventory_days
  FROM tx_financials
  GROUP BY product_id
) p
LEFT JOIN recent_sales r USING (product_id)
WHERE p.avg_inventory_days > 60 AND COALESCE(r.qty_90d,0) < 10
ORDER BY p.avg_inventory_days DESC;
```

Notes: adjust `DATE_TRUNC` and `INTERVAL` syntax if your SQL dialect differs (MySQL vs Postgres). For MySQL, use `DATE_FORMAT` / `TIMESTAMPDIFF` equivalents.

