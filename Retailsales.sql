use retail_events_db;
# Basic Sql Queries to 
#converting  date column string to date;
ALTER TABLE dim_dates modify COLUMN `date` DATE;
UPDATE dim_dates
SET `date` = STR_TO_DATE(`date`, '%d-%m-%Y');
select * from retail_events_db.dim_dates;
SET `date` = STR_TO_DATE(TextColumn, '%Y-%m-%d'); -- Adjust format specifier if needed
SELECT STR_TO_DATE('12/12/2023', '%d/%m/%Y') AS Date from retail_events_db;

# Creating a 2 fact tables to getting a better insight
# Finding the promoted individual values
create  table fact_views as select *,
round(case when promo_type = '50% OFF' then base_price*(50/100)
	 when promo_type = '25% OFF' then base_price-base_price*(25/100)
     when promo_type = 'BOGOF' then base_price*2
     when promo_type = '500 Cashback' then base_price-500
     else base_price-base_price*(33/100)
end ,0)as base_price_promo
 from fact_events ;
 
 
 # finding the promoted revenue baseline revenue, find percentage of baselineRevenue and PromotedRevenue based on products
 
create table fact_sales_view as
select d.`date` ,f.event_id,f.store_id,f.campaign_id,f.product_code,f.promo_type,
f.base_price,f.`quantity_sold(before_promo)`,f.`quantity_sold(after_promo)`,f.base_price_promo,
f.base_price*f.`quantity_sold(before_promo)` as baseline_revenue,f.base_price_promo*f.`quantity_sold(after_promo)` as promoted_revenue,
f.base_price_promo*f.`quantity_sold(after_promo)`- f.base_price*f.`quantity_sold(before_promo)` as revenue,
f.`quantity_sold(after_promo)`-f.`quantity_sold(before_promo)` as sold_units,
round((f.`quantity_sold(after_promo)`-f.`quantity_sold(before_promo)` / SUM(f.`quantity_sold(after_promo)`-f.`quantity_sold(before_promo)`) OVER (PARTITION BY `date`, product_code) * 100),2) AS pct_sold_units,
round((f.base_price_promo*f.`quantity_sold(after_promo)`- f.base_price*f.`quantity_sold(before_promo)` / SUM(f.base_price_promo*f.`quantity_sold(after_promo)`- f.base_price*f.`quantity_sold(before_promo)`) OVER (PARTITION BY `date`, product_code) * 100),2) AS pct_revenue
 from fact_views f
join dim_dates d on d.campaign_id =f.campaign_id 
order by d.`date` asc;

# Store Performance Analysis
# 1)Which are the Top 10 Stores in terms of incremental Revenue generated from the promotions
SELECT s.store_id,f.promo_type,
         SUM(promoted_revenue) AS total_revenue,
         SUM(baseline_revenue) AS Baseline_revenue,
         SUM(promoted_revenue - baseline_revenue) AS incremental_revenue,
         SUM(pct_revenue) as pct_revenue
  FROM fact_pctsales_view f
  INNER JOIN dim_stores s ON f.store_id = s.store_id
  GROUP BY s.store_id,f.promo_type
  order by incremental_revenue desc
  limit 10;
  
  
# Which are the bottom 10 Stores when it comew to Incremental Sol Units during the promotional Period

 SELECT s.store_id,f.promo_type,
         SUM(`quantity_sold(after_promo)`) AS total_units_sold_after_promo,
         SUM(`quantity_sold(before_promo)`) AS total_units_sold_before_promo,
         SUM(`quantity_sold(after_promo)` - `quantity_sold(before_promo)`) AS incremental_units
  FROM fact_sales_view f
  INNER JOIN dim_stores s ON f.store_id = s.store_id
  GROUP BY s.store_id,f.promo_type
  order by incremental_units asc
  limit 10;
  
  # How does the performance of stores Vary by city Are there any common characteristics among the top-performing stores that could be other stores
  
  WITH ranked_stores AS (
  SELECT s.store_id,
         s.city,
         f.campaign_id,
         SUM(promoted_revenue) AS total_revenue,
         SUM(`quantity_sold(after_promo)`) AS total_units_sold,
         SUM(baseline_revenue) AS baseline_revenue,
         SUM(promoted_revenue - baseline_revenue) AS incremental_revenue,
         ROW_NUMBER() OVER (PARTITION BY s.city ORDER BY SUM(promoted_revenue) DESC) AS city_rank
  FROM fact_sales_view f
  INNER JOIN dim_stores s ON f.store_id = s.store_id
  GROUP BY s.store_id, s.city,f.campaign_id
)
SELECT rs.*,
       LAG(total_revenue) OVER (PARTITION BY city ORDER BY city_rank) AS prev_store_revenue,
       LAG(total_units_sold) OVER (PARTITION BY city ORDER BY city_rank) AS prev_store_units,
       rs.total_revenue / LAG(total_revenue) OVER (PARTITION BY city ORDER BY city_rank) - 1 AS revenue_growth,
       rs.total_units_sold / LAG(total_units_sold) OVER (PARTITION BY city ORDER BY city_rank) - 1 AS unit_growth
FROM ranked_stores rs
WHERE city_rank <= 10;

# Promotion Type Analysis:
#  What are the top 2 promotion types that resulted in the highest incremental Revenue
  SELECT
  promo_type,
  SUM(promoted_revenue - baseline_revenue) AS total_incremental_revenue
FROM fact_sales_view
GROUP BY promo_type
ORDER BY total_incremental_revenue DESC
LIMIT 2;


# What are the bottom 2 promotions types in terms of their impact on incremental sold units
WITH ranked_promotions AS (
  SELECT promo_type,
         SUM(`quantity_sold(after_promo)` - `quantity_sold(before_promo)`) AS total_incremental_units,
         ROW_NUMBER() OVER (ORDER BY SUM(`quantity_sold(after_promo)` - `quantity_sold(before_promo)`) ASC) AS promo_rank
  FROM fact_sales_view
  GROUP BY promo_type
)
SELECT promo_type,total_incremental_units,promo_rank
FROM ranked_promotions
WHERE promo_rank <= 2;

# Is there any significant difference in the performance of discount -based promotions versus BoGOF or Cashback promotions?
WITH ranked_promotions AS (
  SELECT promo_type,
         SUM(promoted_revenue) AS total_revenue,
         SUM(`quantity_sold(after_promo)`) AS total_units_sold,
         SUM(baseline_revenue) AS baseline_revenue,
         SUM(promoted_revenue - baseline_revenue) AS incremental_revenue,
         ROW_NUMBER() OVER (ORDER BY SUM(promoted_revenue) DESC) AS overall_rank
  FROM fact_sales_view
  GROUP BY promo_type
)
SELECT rp.*,
       LAG(total_revenue) OVER (ORDER BY overall_rank) AS prev_promo_revenue,
       LAG(total_units_sold) OVER (ORDER BY overall_rank) AS prev_promo_units,
       rp.total_revenue / LAG(total_revenue) OVER (ORDER BY overall_rank) - 1 AS revenue_growth,
       rp.total_units_sold / LAG(total_units_sold) OVER (ORDER BY overall_rank) - 1 AS unit_growth
FROM ranked_promotions rp
WHERE promo_type IN ('50% OFF', '25% OFF','33% OFF','BOGOF', '500 Cashback');

# Which Promotoions strike the best balance between incremental soldunits and maintaing healthy margins?
WITH campaign_metrics AS (
  SELECT 
    promo_type,
    SUM(`quantity_sold(after_promo)`) AS total_units_sold,
    SUM(promoted_revenue) AS total_promoted_revenue,
    SUM(baseline_revenue) AS baseline_revenue
  FROM fact_sales_view
  GROUP BY promo_type
)
SELECT cm.*,
       (total_units_sold - LAG(total_units_sold) OVER (ORDER BY total_promoted_revenue DESC)) / LAG(total_units_sold) OVER (ORDER BY total_promoted_revenue DESC) AS unit_growth,
       total_promoted_revenue  / baseline_revenue AS margin_ratio
FROM campaign_metrics cm
ORDER BY total_promoted_revenue DESC;

# Product and Category Analysis:
 
 #Which product catergories saw the most significant in sales from the promotions
 WITH category_metrics AS (
  SELECT p.category,
  
         SUM(promoted_revenue) AS total_promoted_revenue,
         SUM(baseline_revenue) AS baseline_revenue
  FROM fact_sales_view f
  INNER JOIN dim_products p ON f.product_code = p.product_code
  GROUP BY p.category
)
SELECT cm.*,
       (total_promoted_revenue - baseline_revenue) / baseline_revenue AS lift_ratio,
       RANK() OVER (ORDER BY (total_promoted_revenue - baseline_revenue) / baseline_revenue DESC) AS lift_rank
FROM category_metrics cm
-- Optionally filter for top N categories (e.g., LIMIT 10)
ORDER BY lift_rank;
 
 # Are There specific products that rspond exceptionally well or poorly to promotions?
 WITH product_metrics AS (
  SELECT p.product_code, p.product_name, p.category category,
         SUM(promoted_revenue) AS total_promoted_revenue,
         SUM(baseline_revenue) AS baseline_revenue,
         SUM(`quantity_sold(after_promo)`) AS total_units_sold
  FROM fact_sales_view f
  INNER JOIN dim_products p ON f.product_code = p.product_code
  -- LEFT JOIN dim_categories c ON p.category_id = c.category_id -- Optional join if dim_categories exists
  GROUP BY p.product_code, p.product_name, p.category
)
SELECT pm.*,
       (total_promoted_revenue - baseline_revenue) / baseline_revenue AS lift_ratio,
       (total_units_sold - LAG(total_units_sold) OVER (PARTITION BY category ORDER BY (total_promoted_revenue - baseline_revenue) / baseline_revenue DESC)) / LAG(total_units_sold) OVER (PARTITION BY category ORDER BY (total_promoted_revenue - baseline_revenue) / baseline_revenue DESC) AS unit_growth
FROM product_metrics pm
ORDER BY lift_ratio DESC; -- Analyze both high and low performers

 
 # What is the correlation between product category and promotion types effectiveness?
 
 WITH category_metrics AS (
  SELECT p.category category, f.promo_type,
         SUM(promoted_revenue) AS total_promoted_revenue,
         SUM(baseline_revenue) AS baseline_revenue
  FROM fact_sales_view f
  INNER JOIN dim_products p ON f.product_code = p.product_code
  GROUP BY p.category, f.promo_type
),
correlation_data AS (
  SELECT cm.*,
         (total_promoted_revenue - baseline_revenue) / baseline_revenue AS lift_ratio
  FROM category_metrics cm
),
category_averages AS (
  SELECT category, AVG(lift_ratio) AS avg_lift_ratio
  FROM correlation_data
  GROUP BY category
),
promotion_averages AS (
  SELECT promo_type, AVG(lift_ratio) AS avg_lift_ratio
  FROM correlation_data
  GROUP BY promo_type
)
SELECT cm.*, round(ca.avg_lift_ratio,2) AS category_avg, round(pa.avg_lift_ratio,2) AS promo_avg,
       round(lift_ratio - (ca.avg_lift_ratio * pa.avg_lift_ratio),2) AS residual
FROM correlation_data cm
INNER JOIN category_averages ca ON cm.category = ca.category
INNER JOIN promotion_averages pa ON cm.promo_type = pa.promo_type
-- Optionally filter for specific categories or promotion types
ORDER BY category, promo_type;
