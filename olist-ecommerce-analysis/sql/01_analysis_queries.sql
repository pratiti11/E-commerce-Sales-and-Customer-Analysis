-- =====================================================================
-- Olist E-commerce Analysis: SQL queries (DuckDB syntax, all tested)
-- Scope: delivered orders, Jan 2017 - Aug 2018 (complete months only)
-- Revenue = item price + freight from order_items
-- =====================================================================

-- Q1. Headline KPIs
WITH delivered AS (
    SELECT o.order_id, c.customer_unique_id
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
order_value AS (
    SELECT order_id, SUM(price + freight_value) AS order_revenue
    FROM order_items
    GROUP BY order_id
)
SELECT COUNT(DISTINCT d.order_id)              AS orders,
       COUNT(DISTINCT d.customer_unique_id)    AS customers,
       ROUND(SUM(v.order_revenue), 0)          AS revenue_brl,
       ROUND(AVG(v.order_revenue), 2)          AS avg_order_value_brl
FROM delivered d
JOIN order_value v ON v.order_id = d.order_id;

-- Q2. Monthly revenue, orders and month-on-month growth (LAG)
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
           COUNT(DISTINCT o.order_id)                      AS orders,
           SUM(i.price + i.freight_value)                  AS revenue
    FROM orders o
    JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY 1
)
SELECT month,
       orders,
       ROUND(revenue, 0)                                                    AS revenue_brl,
       ROUND(revenue / orders, 2)                                           AS aov_brl,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1)                       AS mom_growth_pct
FROM monthly
ORDER BY month;

-- Q3. Top 10 categories by revenue with share and running total
WITH cat_rev AS (
    SELECT COALESCE(t.product_category_name_english, 'unknown') AS category,
           SUM(i.price + i.freight_value)                       AS revenue,
           COUNT(DISTINCT i.order_id)                           AS orders
    FROM order_items i
    JOIN orders o   ON o.order_id = i.order_id AND o.order_status = 'delivered'
    JOIN products p ON p.product_id = i.product_id
    LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
    GROUP BY 1
)
SELECT RANK() OVER (ORDER BY revenue DESC)                                   AS rnk,
       category,
       orders,
       ROUND(revenue, 0)                                                     AS revenue_brl,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1)                      AS share_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS cumulative_pct
FROM cat_rev
ORDER BY revenue DESC
LIMIT 10;

-- Q4. Repeat purchase rate: how many customers ever order again?
WITH per_customer AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT COUNT(*)                                                    AS customers,
       SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END)                AS repeat_customers,
       ROUND(100.0 * SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM per_customer;

-- Q5. RFM segmentation (NTILE quintiles for recency and monetary value)
WITH base AS (
    SELECT c.customer_unique_id,
           MAX(o.order_purchase_timestamp)  AS last_order,
           COUNT(DISTINCT o.order_id)       AS frequency,
           SUM(i.price + i.freight_value)   AS monetary
    FROM orders o
    JOIN customers c   ON c.customer_id = o.customer_id
    JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
),
scored AS (
    SELECT *,
           DATE_DIFF('day', last_order, (SELECT MAX(order_purchase_timestamp) FROM orders WHERE order_status = 'delivered')) AS recency_days,
           NTILE(5) OVER (ORDER BY last_order)  AS r_score,   -- 5 = most recent
           NTILE(5) OVER (ORDER BY monetary)    AS m_score    -- 5 = highest spend
    FROM base
),
segmented AS (
    SELECT *,
           CASE
               WHEN frequency >= 2 AND r_score >= 4                 THEN 'Loyal (repeat, recent)'
               WHEN frequency >= 2                                  THEN 'Repeat, lapsing'
               WHEN r_score >= 4 AND m_score >= 4                   THEN 'New high-value'
               WHEN r_score >= 4                                    THEN 'New low-value'
               WHEN r_score <= 2 AND m_score >= 4                   THEN 'At risk high-value'
               WHEN r_score <= 2                                    THEN 'Lost low-value'
               ELSE 'Needs attention'
           END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                            AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_customers,
       ROUND(SUM(monetary), 0)                             AS revenue_brl,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
       ROUND(AVG(recency_days), 0)                         AS avg_recency_days
FROM segmented
GROUP BY segment
ORDER BY revenue_brl DESC;

-- Q6. Monthly cohort retention (first purchase month vs months since)
WITH cust_orders AS (
    SELECT c.customer_unique_id,
           DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
first_month AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM cust_orders
    GROUP BY 1
),
activity AS (
    SELECT DISTINCT f.cohort_month,
           DATE_DIFF('month', f.cohort_month, co.order_month) AS month_number,
           co.customer_unique_id
    FROM cust_orders co
    JOIN first_month f USING (customer_unique_id)
)
SELECT cohort_month,
       month_number,
       COUNT(*) AS active_customers,
       ROUND(100.0 * COUNT(*) / FIRST_VALUE(COUNT(*)) OVER (PARTITION BY cohort_month ORDER BY month_number), 2) AS retention_pct
FROM activity
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q7. Delivery delay vs customer review score
WITH delivery AS (
    SELECT o.order_id,
           DATE_DIFF('day', o.order_estimated_delivery_date, o.order_delivered_customer_date) AS days_late
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT CASE
           WHEN days_late <= -7 THEN '1. 7+ days early'
           WHEN days_late <=  0 THEN '2. 0-6 days early'
           WHEN days_late <=  3 THEN '3. 1-3 days late'
           WHEN days_late <=  7 THEN '4. 4-7 days late'
           ELSE                      '5. 8+ days late'
       END                                                              AS delivery_bucket,
       COUNT(*)                                                         AS orders,
       ROUND(AVG(r.review_score), 2)                                    AS avg_review,
       ROUND(100.0 * AVG(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END), 1) AS pct_1_2_star
FROM delivery d
JOIN order_reviews r ON r.order_id = d.order_id
GROUP BY 1
ORDER BY 1;

-- Q8. Late-delivery rate by customer state (states with 1,000+ orders)
SELECT c.customer_state,
       COUNT(*)                                                                                   AS orders,
       ROUND(100.0 * AVG(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END), 1) AS late_pct,
       ROUND(AVG(DATE_DIFF('day', o.order_purchase_timestamp, o.order_delivered_customer_date)), 1) AS avg_delivery_days
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY 1
HAVING COUNT(*) >= 1000
ORDER BY late_pct DESC;

-- Q9. Payment methods and instalments
SELECT payment_type,
       COUNT(DISTINCT order_id)                                  AS orders,
       ROUND(100.0 * COUNT(DISTINCT order_id) / SUM(COUNT(DISTINCT order_id)) OVER (), 1) AS pct_orders,
       ROUND(AVG(payment_value), 2)                              AS avg_payment_brl,
       ROUND(AVG(payment_installments), 1)                       AS avg_installments
FROM order_payments
WHERE payment_type <> 'not_defined'
GROUP BY 1
ORDER BY orders DESC;
