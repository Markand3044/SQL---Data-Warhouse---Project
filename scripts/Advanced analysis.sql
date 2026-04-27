
USE DataWarehouse

-- Analyse how a measure evolves over time.
-- change over time 
-- Analyse sales performance over time.

SELECT 
YEAR(order_date) AS order_year,
MONTH(order_date) AS order_month,
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT(customer_key)) total_customers,
SUM(quantity) as total_quantity
FROM
gold.fact_sales
WHERE order_date is not null
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY YEAR(order_date), MONTH(order_date)

-- Cumulative Analysis
-- Aggregate the data progressively over time.
-- helps to understand whether our business is growing or declining.

-- calculate the total sales per month and the running total of sales over time. 

-----BY MONTH----
SELECT 
order_date,
total_sales,
SUM(total_sales) OVER(PARTITION BY order_date ORDER BY order_date )AS runing_total_sales,
AVG(avg_price) OVER(ORDER BY order_date) AS moving_average_price  
FROM
(
	SELECT 
	DATETRUNC(MONTH,order_date) AS order_date,
	SUM(sales_amount) AS total_sales,
	AVG(price) AS avg_price
	FROM gold.fact_sales
	WHERE order_date is not null 
	GROUP BY DATETRUNC(MONTH,order_date)
	)t

----BY YEAR----
SELECT 
order_date,
total_sales,
SUM(total_sales) OVER(ORDER BY order_date )AS runing_total_sales,
AVG(avg_price) OVER(ORDER BY order_date) AS moving_average_price  
FROM
(
	SELECT 
	DATETRUNC(YEAR,order_date) AS order_date,
	SUM(sales_amount) AS total_sales,
	AVG(price) AS avg_price
	FROM gold.fact_sales
	WHERE order_date is not null 
	GROUP BY DATETRUNC(YEAR,order_date)
	)t

-- Performance Analysis 
-- Comparing the current value to a target value.
-- helps measure success and compare performance.

/*  Analyze the yearly performance of products by comparing each product's sales to both 
	its average sales performance and the previous year's sales. */

WITH yearly_product_sales AS (
	SELECT
	YEAR(f.order_date) AS order_year,
	p.product_name,
	SUM(f.sales_amount) AS current_sales
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_products p
	ON f.product_key = p.product_key
	WHERE f.order_date IS NOT NULL
	GROUP BY 
	YEAR(f.order_date),
	p.product_name
)

SELECT 
order_year,
product_name,
current_sales,
AVG(current_sales) OVER(PARTITION BY product_name) avg_sales,
current_sales - AVG(current_sales) OVER(PARTITION BY product_name) AS diff_avg,
CASE WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'Above Avg'
	 WHEN  current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'Below Avg'
	 ELSE 'Avg'
END avg_change,
LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) py_sales,
current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS diff_py,
CASE WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
	 WHEN  current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
	 ELSE 'No Change'
END py_change
FROM yearly_product_sales
ORDER BY product_name, order_year

-- Part - to whole (proportional analysis)
/* Analyze how an individual part is performing compared to the overall, allowing us to understand which category 
   has the greatest impact on the business. */
-- which category contribute the most to overall sales?

WITH category_sales AS(
SELECT
category,
SUM(f.sales_amount) AS total_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON p.product_key = f.product_key
GROUP BY category)

SELECT 
category,
total_sales,
SUM(total_sales) OVER() overall_sales,
CONCAT(ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) over()) * 100, 2), '%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC

-- Data Segmentation 
-- Group the data based on a specific range.
-- Helps understand the correlation between two measures.

/* Segment products into cost ranges and count how many products fall into each segment  */

WITH product_segment AS(
SELECT 
product_key,
product_name,
cost,
CASE WHEN cost < 100 THEN 'Below 100'
	 WHEN cost BETWEEN 100 AND 500 THEN '100 - 500'
	 WHEN cost BETWEEN 500 AND 1000 THEN '500 - 1000'
	 ELSE 'Above 1000'
END cost_range
FROM gold.dim_products)

SELECT 
cost_range,
COUNT(product_key) AS total_product
FROM product_segment
GROUP BY cost_range
ORDER BY total_product DESC

/* Group customers into three segments based on thier spending behaviour:
		- VIP : Customers with at least 12 months of history and spending more than 5,000.
		- Regular : Customers with at least 12 months of history and spending 5000 or less.
		- New : Customers with a lifespan less than 12 months.
   And find the total number of customer by each group */

WITH customer_spending AS (
SELECT 
c.customer_key,
SUM(f.sales_amount) AS total_sales,
MIN(f.order_date) AS first_oredr,
MAX(f.order_date) AS last_order,
DATEDIFF(MONTH, MIN(f.order_date), MAX(f.order_date)) AS lifespan
FROM gold.dim_customers c
LEFT JOIN gold.fact_sales f
ON c.customer_key = f.customer_key
GROUP BY c.customer_key
)
SELECT 
customer_segment,
COUNT(customer_key) total_customer
FROM(
	SELECT 
	customer_key,
	total_sales,
	lifespan,
	CASE WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
		 WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
		 ELSE 'NEW'
	END customer_segment
	FROM customer_spending)t
GROUP BY customer_segment
ORDER BY total_customer DESC

/* 
===============================================================================
Customer Report
===============================================================================
Purpose:
	- This report consolidates key customer metrics and behaviors

Highlights:
	1. Gathers essential fields such as names, ages, and transaction details.
	2. Segments customers into categories (VIP, Regular, New) and age groups.
	3. Aggregates customer - level metrics:
		- total orders
		- total sales 
		- total quantity purchased 
		- total products
		- lifespan (in months)
	4. calculates valuable KPIs:
		- recency (months since last order)
		- average order value
		- average monthly spend
================================================================================
*/
CREATE VIEW gold.report_customers AS
WITH base_query AS(
/* -----------------------------------------------------------------------------
1) Base Query : Retrives columns from tables
------------------------------------------------------------------------------*/
SELECT 
f.order_number,
f.product_key,
f.order_date,
f.sales_amount,
f.quantity,
c.customer_key,
c.customer_number,
CONCAT(c.first_name, ' ', c.last_name) AS Customer_name,
DATEDIFF(YEAR, c.birthdate, GETDATE()) AS age
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON f.customer_key = c.customer_key
WHERE order_date IS NOT NULL)

, customer_agrregation AS(
/*--------------------------------------------------------------------------------
2) customer Aggregations: Summarizes key metrics at the customer levels
--------------------------------------------------------------------------------*/

SELECT
	customer_key,
	customer_number,
	Customer_name,
	age,
	COUNT(DISTINCT order_number) AS total_order,
	SUM(sales_amount) AS total_sales,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT product_key) AS total_products,
	MAX(order_date) AS last_order_date,
	DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan
FROM base_query
GROUP BY 
	customer_key,
	customer_number,
	Customer_name,
	age
)
SELECT
	customer_key,
	customer_number,
	Customer_name,
	age,
	CASE WHEN age < 20 THEN 'Under 20'
		 WHEN age between 20 and 29 THEN '20-29'
		 WHEN age between 30 and 39 THEN '30-39'
		 WHEN age between 40 and 49 THEN '40-49'
		 ELSE '50 AND ABOVE'
	END AS age_group,
	CASE 
		WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
		WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
		ELSE 'NEW'
	END AS customer_segment,
	total_order,
	total_sales,
	total_quantity,
	total_products,
	last_order_date,
	DATEDIFF(MONTH, last_order_date, GETDATE()) AS recency,
	lifespan,
	--COMPUTE AVERAGE ORDER VALUE (AVO)
	CASE WHEN total_sales = 0 THEN 0
		 ELSE total_sales / total_order
	END AS avg_order_value,

	--COMPUTE AVERAGE MONTHLY SPEND
	CASE WHEN lifespan = 0 THEN total_sales
		 ELSE total_sales / lifespan
	END AS avg_monthly_spend
FROM customer_agrregation

SELECT * FROM gold.report_customers

/* 
============================================================================================
Product	Report
============================================================================================
Purpose:
	- This Report consolidates key product metrics and behaviors.

Highlights:
	1. Gathers essential fields such as product name, category, subcategory, and cost.
	2. segment products by revenue to identify High-Performers, Mid-Range, or Low-Performers
	3. Aggregates product-level metrics:
		- total orders
		- total sales
		- total quantity 
		- total customers(unique)
		- lifespane (in months)
	4. calculates valuable KPIs:
		- recency (months since last sale)
		- average order revenue (AOR)
		- average monthly revenue
==============================================================================================
*/

CREATE VIEW gold.report_product AS
WITH base_query AS(
SELECT 
	f.customer_key,
	f.order_number,
	f.order_date,
	f.sales_amount,
	f.quantity,
	p.product_key,
	p.product_name,
	p.category,
	p.subcategory,
	p.cost
FROM gold.fact_sales f
left join gold.dim_products p
on f.product_key = p.product_key
where order_date is not null
),
product_agrregation AS (
SELECT
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	count(distinct order_number) as total_order,
	sum(quantity) as total_quantity,
	sum(sales_amount) as total_sales,
	DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) as lifespan,
	count(distinct customer_key) as total_customers,
	ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity,0)),1) AS avg_selling_price,
	MAX(order_date) as last_sale_date
FROM base_query
group by product_key,
		 product_name,
		 category,
		 subcategory,
		 cost
)
SELECT 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
	CASE
		 WHEN total_sales > 50000 then 'High-Performer'
		 WHEN total_sales >= 10000 then 'Mid-Range'
		 ELSE 'Low-Performer'
	END as product_segment,
	lifespan,
	total_order,
	total_sales,
	total_quantity,
	total_customers,
	avg_selling_price,
	CASE WHEN total_order = 0 then 0
		 else total_sales / total_order
	END AS avg_order_revenue,

	CASE WHEN lifespan = 0 then total_sales
		 else total_sales / lifespan
	END AS avg_monthly_sales

FROM product_agrregation

SELECT * FROM gold.report_product

