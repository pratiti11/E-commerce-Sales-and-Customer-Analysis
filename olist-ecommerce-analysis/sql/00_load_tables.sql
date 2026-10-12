-- Load the Olist CSV files into DuckDB, run from the project folder
-- For PostgreSQL/MySQL, create the tables and import the same CSVs instead.
CREATE TABLE customers      AS SELECT * FROM read_csv_auto('data/olist_customers_dataset.csv');
CREATE TABLE orders         AS SELECT * FROM read_csv_auto('data/olist_orders_dataset.csv');
CREATE TABLE order_items    AS SELECT * FROM read_csv_auto('data/olist_order_items_dataset.csv');
CREATE TABLE order_payments AS SELECT * FROM read_csv_auto('data/olist_order_payments_dataset.csv');
CREATE TABLE order_reviews  AS SELECT * FROM read_csv_auto('data/olist_order_reviews_dataset.csv');
CREATE TABLE products       AS SELECT * FROM read_csv_auto('data/olist_products_dataset.csv');
CREATE TABLE sellers        AS SELECT * FROM read_csv_auto('data/olist_sellers_dataset.csv');
CREATE TABLE category_translation AS SELECT * FROM read_csv_auto('data/product_category_name_translation.csv');
