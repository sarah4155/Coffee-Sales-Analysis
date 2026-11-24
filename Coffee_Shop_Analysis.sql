/* Create Database CoffeeShopSales */

CREATE DATABASE CoffeeShopSales
GO

Use CoffeeShopSales 
GO
/* Imported CSV files as tables through import wizard */

/* Overall Business Objective: Should the menu change? If so, how?

    Questions to Answer: 
    1. Which products generate the most revenue/what was the gross profit? 
    2. Are any products worth removing? 
    3. Do generations buy different products? 
    4. Are there certain times of the day certain products are being sold and can be moved to a morning/night menu? 
    5. Which items should be promoted, and how much do current promo items rely on discounts? */

-----------------------------------------------------------------------------------------------------------

/** STEP 1: DATA QUALITY (Data QC/Cleaning) */

/* Table relationships will be defined in the Power BI data model  */

/* current_retail_price was imported with dollar signs; converting this into decimal format to align with 
the rest of the price formats */

ALTER TABLE product ALTER COLUMN current_retail_price DECIMAL(10,2)
GO

--QC that the prices converted correctly
select TOP 10 product, current_wholesale_price, current_retail_price 
from [dbo].[product];

/* Making sales_outlet_id + year_month a composite key since this table has no true unique columns
since this only spans over a month of data; the sales_outlet_id would repeat again for the next month, so the unique
identifier here would be sales_outlet_id + year_month */ 

/* Making sure year_month has no nulls; otherwise cannot be assigned as a primary key */

ALTER TABLE sales_targets ALTER COLUMN year_month NVARCHAR(50) NOT NULL
ALTER TABLE sales_targets ADD CONSTRAINT pk_sales_targets
    PRIMARY KEY (sales_outlet_id, year_month);

/* Checking if the sales_reciepts table has nulls in sales_outlet_id (a foreign key linking each sale to a store);
every sale should belong to a store, so this column shouldn't have any nulls */

SELECT COUNT(*) 
FROM [dbo].[sales_reciepts]
WHERE sales_outlet_id IS NULL; -- should expect 0 

/* Alter column to not have nulls if there are */
ALTER TABLE [dbo].[sales_reciepts] ALTER COLUMN sales_outlet_id INT NOT NULL;

/* Confirm column7 and column8 in staff table dont have any values and can be dropped */

SELECT COUNT(*) 
FROM staff 
WHERE column7 IS NOT NULL OR column8 IS NOT NULL;

ALTER TABLE staff DROP COLUMN column7, column8; --Drop the columns since they don't have data 

/* QC location in staff table */

SELECT location, COUNT(*) 
FROM staff 
GROUP BY location; --Some results are numbers and some are text, can't join on sales_outlet_id 

/* Some menu items are listed with 'Sm', 'Rg', 'Lg' or as a promo item 
separately to indicate different sizes of drinks/if it's a promo. We'll need to roll the sizes/promos into 
one menu item for the analysis */

--QC where there's sizes/promos

SELECT product_id, product, product_type, unit_of_measure, current_retail_price
FROM product
ORDER BY product;

--We can add another column called menu_item to caveat this*/

ALTER TABLE product ADD menu_item NVARCHAR(100);

-- Remove the "promo" from the product name
UPDATE product
SET menu_item = TRIM(REPLACE(product, ' Promo', ''));

--Remove the sizes after 
UPDATE product
SET menu_item = LEFT(menu_item, LEN(menu_item) - 3)
WHERE menu_item LIKE '% Sm' OR menu_item LIKE '% Rg' OR menu_item LIKE '% Lg';

--QC the results, make sure there's no duplicates (if there are, indicates a trailing space) 
SELECT menu_item, COUNT(*) AS sizes
FROM product
GROUP BY menu_item
ORDER BY menu_item;

/* While checking promo vs. non-promo sales, found that some line_item_amounts were $0;
   I've investigated the $0 rows: */

SELECT p.product, s.promo_item_yn, s.quantity, s.unit_price, COUNT(*) AS rows
FROM [dbo].[sales_reciepts] s
JOIN [dbo].[product] p ON s.product_id = p.product_id
WHERE s.line_item_amount = 0
GROUP BY p.product, s.promo_item_yn, s.quantity, s.unit_price
ORDER BY rows DESC;

/* - All 24 rows (47 units) were Ginger Scone promo sales: free giveaways
   - Kept in the analysis, since the cost of the giveaway should count against the item's profit */

-----------------------------------------------------------------------------------------------------------

/* STEP 2: ANALYSIS */

/* QUESTION 1: Which products generate the most revenue/what was the gross profit? 
    - Revenue generated for each product sorted from highest to lowest 
    - We can use line_item_amount from the sales_reciept table 
    - Filtering only on the drinks and bakery items; some menu_item names are shared with retail products
(e.g. 'Ethiopia' is both a brewed coffee and a bag of beans), so retail items are excluded */

SELECT p.menu_item, SUM(line_item_amount) AS Revenue
FROM [dbo].[sales_reciepts] s
JOIN [dbo].[product] p ON p.product_id = s.product_id
WHERE p.product_category IN ('Coffee', 'Tea', 'Drinking Chocolate', 'Bakery')
GROUP BY p.menu_item
ORDER BY Revenue DESC;

/* For drinks, Jamaican Coffee River generates the highest revenue at $13,040.45 and Ouro Brasileiro Shot 
generated the lowest revenue at $3014.10
   For bakery items, Chocolate Croissant generated the highest revenue at $3476.64, and the Oatmeal Scone generated
the lowest revenue at $1845.00
*/

/* What were the gross profit margins? 
Gross Margin % = ([Revenue - COGS] / Revenue) x 100
COGS = quantity x wholesale_price 
**Important to note here this is not reflective as true COGS, since it's only based on wholesale price
and does not account for costs of milk, cups, etc. (essentially more of an estimate)
    - Additionally, COGS is based on a single wholesale price per product, not the cost at the time
  of each sale; it may not reflect any cost changes during the month */

--QC for missing/zero costs-- 
SELECT menu_item, current_wholesale_price 
FROM product 
ORDER BY current_wholesale_price; --No missing/zero costs

/* Calculate Gross Profit Margins and profit per unit; 
easiest and cleanest method is to use a CTE (Common Table Expression)*/

WITH product_totals AS (
    SELECT p.product_category,
           p.menu_item,
           SUM(s.quantity)                             AS units_sold,
           SUM(s.line_item_amount)                     AS revenue,
           SUM(s.quantity * p.current_wholesale_price) AS cogs
    FROM [dbo].[sales_reciepts] s
    JOIN [dbo].[product] p ON s.product_id = p.product_id
    WHERE p.product_category IN ('Coffee', 'Tea', 'Drinking Chocolate', 'Bakery')    
    GROUP BY p.product_category, p.menu_item
)
SELECT product_category,
       menu_item,
       units_sold,
       revenue,
       cogs,
       revenue - cogs                                                          AS gross_profit,
       CAST((revenue - cogs) * 100.0 / NULLIF(revenue, 0)    AS DECIMAL(5,1))  AS gross_margin_pct,
       CAST((revenue - cogs) * 1.0   / NULLIF(units_sold, 0) AS DECIMAL(10,2)) AS profit_per_unit
FROM product_totals
ORDER BY profit_per_unit DESC;

/*Cappuccinos and lattes had the highest profit/unit rates, both at $3.20/unit out of all the drinks. Scottish Cream Scone 
had the highest profit/unit rate at $1.58/unit out of all the bakery items */

/* QUESTION 2: Are any products worth removing? 
   We can configure the menu engineering matrix, a common strategy used by many restaurants/cafes 
   to evaluate their menu items based on popularity and profitability.
        - Every item is categorized into four quadrants: 
            -Stars (high profitability, high popularity): These are the best menu item performers; keep these items on 
        the menu and feature them prominently 
            -Puzzles (high profitability, low popularity): These menu items have high margins but are not being
        ordered as often; good candidates for promotions to be featured more
            -Plowhorses (low profitability, high popularity): These are popular menu items with poor profit margins; 
        adjust portions, consider raising prices slightly, or bundle with high-margin menu items
            -Dogs (low profitability, low popularity): These have poor profit margins and are not popular menu items; 
        these should be flagged and should be considered to be removed if performance doesn't improve after making 
        adjustments */
/* Creating the engineering matrix; we'll use a CTE again and partition by whether the item is a bakery item or a drink 
(this is because a customer is not typically making a choice between a bakery item and a drink)*/
WITH item_totals AS (
    SELECT CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END AS segment,
           p.menu_item,
           SUM(s.quantity)                             AS units_sold,
           SUM(s.line_item_amount)                     AS Revenue,
           SUM(s.quantity * p.current_wholesale_price) AS COGS
    FROM [dbo].[sales_reciepts] s
    JOIN [dbo].[product] p ON s.product_id = p.product_id
    WHERE p.product_category IN ('Bakery', 'Coffee', 'Tea', 'Drinking Chocolate')
    GROUP BY CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END, p.menu_item
),
    item_metric AS ( 
       SELECT segment,
           menu_item,
           units_sold,
           units_sold * 100.0 / SUM(units_sold) OVER (PARTITION BY segment)                AS menu_mix_pct,
           (revenue - cogs) * 1.0 / NULLIF(units_sold, 0)                                  AS profit_per_unit,
           100.0 / COUNT(*) OVER (PARTITION BY segment)                                    AS popularity_line,
           AVG((revenue - cogs) * 1.0 / NULLIF(units_sold, 0)) OVER (PARTITION BY segment) AS profit_line
    FROM item_totals
 )
 SELECT segment, menu_item, 
       units_sold,
       CAST(menu_mix_pct    AS DECIMAL(5,2))  AS menu_mix_pct,
       CAST(popularity_line AS DECIMAL(5,2))  AS popularity_line,
       CAST(profit_per_unit AS DECIMAL(10,2)) AS profit_per_unit,
       CAST(profit_line     AS DECIMAL(10,2)) AS profit_line,
       CASE
           WHEN menu_mix_pct >= popularity_line AND profit_per_unit >= profit_line THEN 'Star'
           WHEN menu_mix_pct >= popularity_line AND profit_per_unit <  profit_line THEN 'Plowhorse'
           WHEN menu_mix_pct <  popularity_line AND profit_per_unit >= profit_line THEN 'Puzzle'
           ELSE 'Dog'
       END AS matrix_label
FROM item_metric
ORDER BY segment, matrix_label, profit_per_unit DESC;

/* Now, let's see which bakery items have a high waste percentage. This is not tracked for drinks as they're made
to order, pastries are already made at the beginning of the day

NOTE: the pastry_inventory table has one row per pastry, per store, per day. Instead of using the daily
waste_pct column (which is stored as text, and averaging daily percentages would be inaccurate), 
we'll add up the total amount wasted and the total amount baked for each menu item, then divide to get the overall 
waste percentage */

SELECT p.menu_item,
       SUM(i.start_of_day)  AS baked,
       SUM(i.waste)         AS wasted,
       CAST(SUM(i.waste) * 100.0 / NULLIF(SUM(i.start_of_day), 0) AS DECIMAL(5,1)) AS overall_waste_pct
FROM pastry_inventory i
JOIN product p ON i.product_id = p.product_id
GROUP BY p.menu_item
ORDER BY overall_waste_pct DESC;

/* A couple things to note for the pastries: 
    - *IMPORTANT* Only 5 out of 11 items were tracked for waste, for the other items, we will only consider 
    the engineering matrix results 
    - Ginger Scone has the highest overall waste percentage (at 71.9%) and is considered as a 
  'plowhorse' menu item, with a profit/unit rate at $0.88. Though the item is considered "popular" due to the promotion, 
   the promo should be stopped and it can be considered to be removed from the menu, 
   as it has a very high waste percentage and the lowest profit per unit margin
    - Cranberry Scone, Oatmeal Scone and Hazelnut Biscotti are categorized as 'Dogs' 
   (low popularity and low profitability). Cranberry Scone and Hazelnut Biscotti each waste over 50% of what's baked,
   which is similar to the other tracked pastries (Oatmeal Scone was not tracked for waste). 
   Since all three are below average in both popularity and profit, they can be considered for removal from the menu.
   -  Promo candidates: any item categorized as a 'Puzzle' (particularly the Scottish
   Cream Scone ($1.58 profit/unit) and the Croissant ($1.40 profit/unit); they have high profitability but 
   low popularity (below average sales); promoting them could help increase sales 
   -  Across all the bakery items that were tracked for waste, more than 50% of each item was wasted. 
   It might be beneficial to bake less of each item to reduce waste  */ 

/* Notes for the drinks:
   - Drinks are made to order and aren't tracked for waste, so conclusions are based on the menu engineering matrix 
     only. Profit per unit for drinks is based on wholesale cost alone (excluding milk, cups, etc.), so figures are 
     likely overstated. Comparisons between drinks are more reliable than the exact amounts
   - Sustainably Grown Organic and Dark chocolate (both hot chocolates) have the lowest profit per unit of all 
     drinks ($1.07 and $1.00) along with below-average popularity, making them candidates for removal
   - Cappuccinos and Lattes are 'Puzzles': high profit per unit ($3.20) but below-average sales, 
     making them good candidates for promotions. It's important to note cappuccinos and lattes only come in two sizes
     instead of three like the other brewed drinks, which may contribute to why their popularity is lower */

/* QUESTION 3: Do different generations buy different products? */

/* We need to join on 3 different tables in order to match what each person from each generation is buying */

/* I decided to rank the top 5 products for each generation to determine what products are popular for each group. 
We'll use a CTE again to achieve this since we can't filter on a rank in the same query that creates it*/

/*We'll use window function "RANK" on both the product category and generations to create separate top 5's for pastries 
and drinks */

WITH generation_sales AS (
    SELECT CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END AS segment,
           g.generation,
           p.menu_item,
           SUM(s.quantity) AS units_sold,
           RANK() OVER (PARTITION BY CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END,
           g.generation
             ORDER BY SUM(s.quantity) DESC) AS rank_in_gen
    FROM [dbo].[customer] AS c
    JOIN [dbo].[generations] g ON c.birth_year = g.birth_year
    JOIN [dbo].[sales_reciepts] s ON c.customer_id = s.customer_id 
    JOIN [dbo].[product] p ON p.product_id = s.product_id
    WHERE p.product_category IN ('Bakery', 'Coffee', 'Tea', 'Drinking Chocolate')
    GROUP BY CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END, p.menu_item, g.generation
) 
SELECT segment, generation, rank_in_gen, menu_item, units_sold
FROM generation_sales 
WHERE rank_in_gen <= 5
ORDER BY segment, generation, rank_in_gen;

/* Notes for generational analysis:
    **IMPORTANT TO NOTE: This analysis only includes sales linked to customers with loyalty records (customer and birth year data);
      some bakery differences are only a few units, thus they should only be considered as patterns rather than conclusions
    - Chocolate Croissant was the #1 or #2 bakery item for all five generations
      (#1 for Baby Boomers, Gen Z and Younger Millennials; #2 for Gen X and Older Millennials)
    - Ginger Scone was #1 for Gen X and Older Millennials and in the top 3 for every generation.
      ***Its sales are boosted by promotions, so its popularity may be overstated
    - Some 'Dog' items (low popularity and profit overall) are favourites with specific generations:
        - Oatmeal Scone is the #2 bakery item for Gen Z
        - Cranberry Scone is the #2 bakery item for Younger Millennials
        - Hazelnut Biscotti is the #3 bakery item for Older Millennials
      These items should be reviewed with this in mind before removing them from the menu.
    - All five generations had the same top 5 drinks (all brewed coffees), in slightly different orders;
      may be because brewed coffees come in three sizes, thus they will have more units sold overall than drinks 
      that come in two sizes
    - Overall, drink preferences do not meaningfully differ by generation.
    - Ties: Gen Z (Cranberry Scone and Hazelnut Biscotti) and Older Millennials (Croissant and Oatmeal Scone)
      each have two items tied for 4th place; no item is ranked 5th

*/

/* QUESTION 4: Are there certain times of the day certain products are being sold and can be moved to a morning/night menu? */
/* -  I decided to use a CTE here so that I could filter by the time of day for easier analysis 
   -  We'll split the day into the following parts; 
            MORNING: 6 AM (Opening) - 11 AM 
            AFTERNOON: 11 AM - 6 PM 
            EVENING 6 PM - CLOSING TIME 
   - These times are based on the hourly sales patterns     */

WITH day_sales AS (
    SELECT p.menu_item,
           CASE
               WHEN s.transaction_time < '11:00' THEN 'Morning'
               WHEN s.transaction_time < '18:00' THEN 'Afternoon'
               ELSE 'Evening'
           END AS time_of_day,
           SUM(s.quantity) AS units_sold,
           CAST(SUM(s.quantity) * 100.0
                / SUM(SUM(s.quantity)) OVER (PARTITION BY p.menu_item) AS DECIMAL(5,1)) AS pct_of_item
    FROM [dbo].[sales_reciepts] s
    JOIN [dbo].[product] p ON p.product_id = s.product_id
    WHERE p.product_category IN ('Bakery', 'Coffee', 'Tea', 'Drinking Chocolate')
      AND s.transaction_time >= '06:00'
    GROUP BY p.menu_item,
             CASE
                 WHEN s.transaction_time < '11:00' THEN 'Morning'
                 WHEN s.transaction_time < '18:00' THEN 'Afternoon'
                 ELSE 'Evening'
             END
)
SELECT menu_item, units_sold, pct_of_item
FROM day_sales
WHERE time_of_day = 'Morning' --I just change this to whichever time of day I want to check
ORDER BY pct_of_item DESC;

/* Notes to add here:
    - Only about 12% or lower of each item is sold at night (6pm-close), so it's not really necessary
    to create a separate night menu
    - Most items sell around 44-53% of their total units in the morning, which mostly just reflects the
    morning rush rather than people preferring certain items in the morning
    - The one exception is the Chocolate Croissant, which sells about 62% of its units in the morning; this could
    be a good item to make sure is fully stocked in the morning, and bake less of later in the day
    - Pastries sell very little at night (around 6-10% of their sales); since waste is already over 50% for the
    pastries that were tracked, it might be beneficial to bake fewer pastries for the afternoon and evening
    - **IMPORTANT TO NOTE: 112 sales were recorded between 1-5am (outside of opening hours) and were left out of this analysis
    - Overall, there isn't really a need to create or move items into separate morning/night menus
*/

/* QUESTION 5: Which items should be promoted, and how much do current promo items rely on discounts?
   - We've actually somewhat answered this above in Q2 with the engineering matrix
   - We can see how much each item relies on the promotion below: 
*/ 

SELECT p.menu_item,
       s.promo_item_yn,
       SUM(s.quantity)         AS units_sold,
       SUM(s.line_item_amount) AS total_sales,
       CAST(SUM(s.quantity) * 100.0
            / SUM(SUM(s.quantity)) OVER (PARTITION BY p.menu_item) AS DECIMAL(5,1)) AS pct_of_units
FROM [dbo].[product] AS p
JOIN [dbo].[sales_reciepts] s ON p.product_id = s.product_id
WHERE p.menu_item IN ('Chocolate Croissant', 'Ginger Scone', 'Ouro Brasileiro shot')
GROUP BY p.menu_item, s.promo_item_yn
ORDER BY p.menu_item, s.promo_item_yn; 
GO

/* Notes for promo analysis:
    - Around 36% of Ginger Scone units and 31% of Ouro Brasileiro shot units were sold as promo items,
    so a large part of their sales relied on promos 
    - Chocolate Croissant had almost no promo sales (only 2 units flagged as promo), even though 156 were
    sold at a $1.00 discount. The reason for this discount isn't clear from the data
    - The promo flag doesn't always match what customers actually paid: some Ginger Scone sales were flagged
    as promo but charged full price, and most discounted Chocolate Croissants weren't flagged as promo at all
    - Ginger Scone should no longer be promoted; it has the lowest profit/unit ($0.88), the highest waste
    (71.9%), about a third of its sales come from promotions, and 47 Ginger Scones were given away for free
    - Ouro Brasileiro shot is a borderline 'Dog', so continuing to discount it lowers an already
    below-average profit; this promotion could be reconsidered
    - Promo candidates should be the 'Puzzle' items (high profit/unit but below-average sales), particularly
    the Scottish Cream Scone ($1.58), Croissant ($1.40), Cappuccino and Latte ($3.20)
    - **IMPORTANT TO NOTE: this data only covers one month and has no comparison period without promotions, so it can't
    show whether the promotions actually increased sales
*/
-------------------------------------------------------------------------------------------------------------------------

/* STEP 3: PREP FOR POWER BI DASHBOARD */

/* We'll create views for the queries created in Q2 and Q4 as these are harder to replicate in Power BI itself */

/* View for the engineering matrix from Q2*/

CREATE VIEW menu_matrix AS
    WITH item_totals AS (
        SELECT CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END AS segment,
            p.menu_item,
            SUM(s.quantity)                             AS units_sold,
            SUM(s.line_item_amount)                     AS Revenue,
            SUM(s.quantity * p.current_wholesale_price) AS COGS
        FROM [dbo].[sales_reciepts] s
        JOIN [dbo].[product] p ON s.product_id = p.product_id
        WHERE p.product_category IN ('Bakery', 'Coffee', 'Tea', 'Drinking Chocolate')
        GROUP BY CASE WHEN p.product_category = 'Bakery' THEN 'Bakery Item' ELSE 'Drink' END, p.menu_item
    ),
        item_metric AS ( 
        SELECT segment,
            menu_item,
            units_sold,
            units_sold * 100.0 / SUM(units_sold) OVER (PARTITION BY segment)                AS menu_mix_pct,
            (revenue - cogs) * 1.0 / NULLIF(units_sold, 0)                                  AS profit_per_unit,
            100.0 / COUNT(*) OVER (PARTITION BY segment)                                    AS popularity_line,
            AVG((revenue - cogs) * 1.0 / NULLIF(units_sold, 0)) OVER (PARTITION BY segment) AS profit_line
        FROM item_totals
    )
    SELECT segment, menu_item, 
        units_sold,
        CAST(menu_mix_pct    AS DECIMAL(5,2))  AS menu_mix_pct,
        CAST(popularity_line AS DECIMAL(5,2))  AS popularity_line,
        CAST(profit_per_unit AS DECIMAL(10,2)) AS profit_per_unit,
        CAST(profit_line     AS DECIMAL(10,2)) AS profit_line,
        CASE
            WHEN menu_mix_pct >= popularity_line AND profit_per_unit >= profit_line THEN 'Star'
            WHEN menu_mix_pct >= popularity_line AND profit_per_unit <  profit_line THEN 'Plowhorse'
            WHEN menu_mix_pct <  popularity_line AND profit_per_unit >= profit_line THEN 'Puzzle'
            ELSE 'Dog'
        END AS matrix_label
    FROM item_metric
    GO

/* View for Pastry Waste */
CREATE VIEW pastry_waste AS
    SELECT p.menu_item,
        SUM(i.start_of_day)  AS baked,
        SUM(i.waste)         AS wasted,
        CAST(SUM(i.waste) * 100.0 / NULLIF(SUM(i.start_of_day), 0) AS DECIMAL(5,1)) AS overall_waste_pct
    FROM pastry_inventory i
    JOIN product p ON i.product_id = p.product_id
    GROUP BY p.menu_item;
    GO

/* View for Daypart Sales */ 
CREATE VIEW daypart_sales AS
    WITH day_sales AS (
        SELECT p.menu_item,
            CASE
                WHEN s.transaction_time < '11:00' THEN 'Morning'
                WHEN s.transaction_time < '18:00' THEN 'Afternoon'
                ELSE 'Evening'
            END AS time_of_day,
            SUM(s.quantity) AS units_sold,
            CAST(SUM(s.quantity) * 100.0
                    / SUM(SUM(s.quantity)) OVER (PARTITION BY p.menu_item) AS DECIMAL(5,1)) AS pct_of_item
        FROM [dbo].[sales_reciepts] s
        JOIN [dbo].[product] p ON p.product_id = s.product_id
        WHERE p.product_category IN ('Bakery', 'Coffee', 'Tea', 'Drinking Chocolate')
        AND s.transaction_time >= '06:00'
        GROUP BY p.menu_item,
                CASE
                    WHEN s.transaction_time < '11:00' THEN 'Morning'
                    WHEN s.transaction_time < '18:00' THEN 'Afternoon'
                    ELSE 'Evening'
                END
    )
    SELECT menu_item, time_of_day, units_sold, pct_of_item
    FROM day_sales
    GO
