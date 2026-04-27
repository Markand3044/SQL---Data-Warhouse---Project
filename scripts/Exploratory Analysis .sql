USE DataWarehouse;

-- Explore all objects in the Database.
SELECT * FROM INFORMATION_SCHEMA.TABLES


-- Explore all columns in the Databases.
SELECT * FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'dim_customers'

-- Explore all the country our customers comes from.
SELECT DISTINCT country FROM gold.dim_customers

-- Explore All Categaries "The major Divisions".
SELECT DISTINCT category, subcategory, product_name FROM gold.dim_products
ORDER BY 1,2,3

-- Date Exploration 
-- Find the first and last date order 
-- How many years of sales are avaiable
SELECT min(order_date) First_Order_Date,
max(order_date) Last_Order_Date,
DATEDIFF(year, min(order_date), max(order_date)) order_range_years
FROM gold.fact_sales

-- Find the youngest and oldest customer
SELECT min(birthdate) oldest_birthdate,
DATEDIFF(year, MIN(birthdate), GETDATE()) AS oldest_age,
max(birthdate) youngest_birthdate,
DATEDIFF(year, max(birthdate), GETDATE()) AS youngest_age
FROM gold.dim_customers

-- Measures Exploration
-- calculate the key metric of the Business(Big numbers)

-- Find the total Sales
SELECT sum(sales_amount) total_sales FROM gold.fact_sales
-- Find how many items are sold
SELECT SUM(QUANTITY) total_quantity FROM gold.fact_sales
-- Find average selling price 
SELECT AVG(price) avg_price FROM gold.fact_sales
-- Find total number of orders 
SELECT COUNT(order_number) total_orders From gold.fact_sales
SELECT COUNT(DISTINCT(order_number)) total_orders From gold.fact_sales
-- Find the total number of products 
SELECT COUNT(DISTINCT (product_key)) total_product From gold.dim_products
-- Find the total number of customers
SELECT COUNT(DISTINCT(customer_key)) total_customers FROM gold.dim_customers
-- Find the total number of customers that has placed an orders 
SELECT COUNT(DISTINCT(customer_key)) total_customers FROM gold.fact_sales


-- Generate a Report that shows all the key metrics of the Business

SELECT 'Total Sales' As measure_name,sum(sales_amount) total_sales FROM gold.fact_sales
UNION ALL
SELECT 'Total Quantity',SUM(QUANTITY) total_quantity FROM gold.fact_sales
UNION ALL
SELECT 'AVG Price',AVG(price) avg_price FROM gold.fact_sales
UNION ALL
SELECT 'Total Nr. Orders',COUNT(DISTINCT(order_number)) total_orders From gold.fact_sales
UNION ALL
SELECT 'Total Nr. Product',COUNT(DISTINCT (product_key)) total_product From gold.dim_products
UNION ALL
SELECT 'Total Nr. Customers',COUNT(DISTINCT(customer_key)) total_customers FROM gold.dim_customers


-- Compare the measure values by categries

--Find the Total number of customers by countries 
SELECT country, COUNT(customer_key) total_customers FROM gold.dim_customers
group by country
order by total_customers DESC

-- Find total customers by gender 
SELECT gender, COUNT(customer_key) total_customers FROM gold.dim_customers
group by gender
order by total_customers DESC

--Find total products by category
SELECT category,COUNT(DISTINCT(product_key)) total_products FROM gold.dim_products
group by category
order by total_products DESC

-- what is avg cost in each category
SELECT category,AVG(cost) AVG_cost FROM gold.dim_products
group by category
order by AVG_cost DESC

-- What is the total revenue generated for each category 
SELECT 
p.category,
SUM(f.sales_amount) total_revenue 
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
on p.product_key = f.product_key
group by p.category
order by total_revenue DESC

-- what is the total revenue generate by the customers 
SELECT 
c.customer_key,
c.first_name,
c.last_name,
SUM(f.sales_amount) total_revenue 
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
on c.customer_key = f.customer_key
group by c.customer_key,c.first_name, c.last_name
order by total_revenue DESC

-- what is the distribution of sold items across countries?
SELECT 
c.country,
SUM(f.quantity) total_quantity
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
on c.customer_key = f.product_key
group by c.country
order by total_quantity DESC

-- ranking the dimensions 

-- Which 5 Products generates highest revenue 
SELECT TOP 5
p.product_name,
SUM(f.sales_amount) total_revenue 
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
on p.product_key = f.product_key
group by p.product_name
order by total_revenue DESC

-- Alternate way 
SELECT 
*
FROM (
	SELECT 
	p.product_name,
	SUM(f.sales_amount) total_revenue,
	ROW_NUMBER() over(order by SUM(f.sales_amount)DESC) as rank_products
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_products p
	on p.product_key = f.product_key
	group by p.product_name)t
Where rank_products <= 5


-- what are the 5 worst-performing products in term of sales?
SELECT TOP 5
p.product_name,
SUM(f.sales_amount) total_revenue 
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
on p.product_key = f.product_key
group by p.product_name
order by total_revenue 

-- Find the top 10 Customers who have generated the highest revenue 
SELECT TOP 10
c.customer_key,
c.first_name,
c.last_name,
sum(f.sales_amount) total_revenue
FROM gold.fact_sales f 
Left join gold.dim_customers c
on f.customer_key = c.customer_key
group by c.customer_key,c.first_name,c.last_name
order by total_revenue DESC

-- Find the 3 Customers with the fewest orders placed
SELECT TOP 3
c.customer_key,
c.first_name,
c.last_name,
COUNT(DISTINCT(f.order_number)) total_order
FROM gold.fact_sales f 
Left join gold.dim_customers c
on f.customer_key = c.customer_key
group by c.customer_key,c.first_name,c.last_name
order by total_order