# Coffee Shop Menu Analysis: Should the Menu Change?

An end-to-end SQL and Power BI analysis of a coffee chain's sales, waste and promotion data, aimed at one business question: **should the menu change, and if so, how?**
---

## Business Questions

1. Which products generate the most revenue and gross profit?
2. Are any products worth removing from the menu?
3. Do different generations buy different products?
4. Are certain products sold at certain times of day, and could they move to a morning or evening menu?
5. Which items should be promoted, and how much do current promo items rely on discounts?

## Dataset

- **Source:** [Coffee Shop Sample Data (Kaggle)](https://www.kaggle.com/datasets/ylchang/coffee-shop-sample-data-1113), IBM Cognos Analytics sample data for a fictional three-store coffee chain
- **Scope:** April 2019, 9 tables (sales receipts, products, customers, generations, staff, stores, sales targets, pastry inventory, dates)
- **Note:** this is sample data, so the findings demonstrate the analysis approach rather than real business conclusions

## Tools

- **SQL Server (SSMS):** data loading, cleaning, analysis, CTEs, window functions (`RANK`, `SUM() OVER (PARTITION BY ...)`), `CASE`, views
- **Power BI:** star-schema data model, DAX measures (`SUMX`, `RELATED`, `CALCULATE`, `REMOVEFILTERS`, `DIVIDE`), interactive report

---

## Key Findings

**Revenue and profit**
- Menu items generated **$207.5K** in revenue and **$136.7K** in gross profit (**65.9%** gross margin) across 66,869 units.
- Coffee drives revenue (**43.8%**), followed by tea (31.5%), bakery (13.0%) and drinking chocolate (11.7%). Jamaican Coffee River is the top seller at $13.0K.
- Cappuccinos and lattes earn the most per unit (**$3.20**); among pastries, Scottish Cream Scone leads (**$1.58**).

**Menu engineering**
- Using the menu engineering matrix (Kasavana & Smith, 1982), items were classed by popularity and profit per unit, with drinks and pastries analyzed separately.
- **13 items are Dogs** (below average on both). The clearest removal candidates are **Cranberry Scone, Oatmeal Scone, Hazelnut Biscotti**, and the two hot chocolates (**Dark chocolate** at $1.00/unit and **Sustainably Grown Organic** at $1.07/unit). The remaining drink Dogs are only a few cents below average and are borderline.
- **Ginger Scone** is the weakest pastry: the lowest profit per unit ($0.88), the highest waste (**71.9%**), and it ranks as popular only because of promotions. Without promo sales, it would be the least popular pastry.

**Waste**
- Every tracked pastry wastes **more than 50%** of what is baked.

**Promotions**
- About **36%** of Ginger Scone units and **31%** of Ouro Brasileiro shot units were sold on promo.
- The shop's promotions target low-profit items, while high-profit **Puzzle** items (e.g. Scottish Cream Scone, Croissant, Cappuccino, Latte) receive none.

**Customers and timing**
- Sales peak between **8 and 10 AM**. Only about **10%** of sales happen after 6 PM.
- **Chocolate Croissant** sells **62%** of its units in the morning, far more than any other item. Most other items simply follow overall traffic.
- All five generations share the same top 5 drinks. Pastry preferences vary more: some overall Dogs are generational favorites (**Oatmeal Scone is Gen Z's #2 pastry**).

## Recommendations

1. **Review the Dogs for removal:** Cranberry Scone, Oatmeal Scone, Hazelnut Biscotti, and the two hot chocolates. Before cutting Oatmeal Scone, consider its popularity with Gen Z.
2. **Stop promoting Ginger Scone** and cut its production: it has the lowest profit, the highest waste, and relies on discounts for about a third of its sales.
3. **Shift promotions to Puzzles:** high-profit items with below-average sales, such as Scottish Cream Scone, Croissant, Cappuccino and Latte.
4. **Bake less, especially later in the day:** waste exceeds 50% for every tracked pastry, and pastries sell very little in the evening. Keep Chocolate Croissants fully stocked for the morning rush.
5. **No separate morning or evening menu is needed:** evening sales are small and most items follow overall traffic.

---

## Dashboard

| Page | Answers |
|---|---|
| **Overview** | Revenue, profit and margin by item and category (Q1) |
| **Menu Performance** | Menu engineering matrix, pastry waste, promo reliance (Q2, Q5) |
| **Customers & Timing** | Sales by hour, morning share by pastry, generational preferences (Q3, Q4) |

![Menu Performance](images/menu_performance.png)
![Customers & Timing](images/customers_timing.png)

## Data Model

Star schema with `sales_reciepts` as the fact table, linked to `product`, `customer` → `generations`, `sales_outlet` and `dates`. Summary SQL views (`menu_matrix`, `pastry_waste`, `daypart_sales`) feed the matrix, waste and time-of-day visuals.

![Data Model](images/data_model.png)

---

## Data Cleaning and Quality Notes

- Converted `current_retail_price` from text with dollar signs to `DECIMAL(10,2)`.
- Added a composite primary key (`sales_outlet_id + year_month`) to `sales_targets`.
- Dropped two empty columns from the `staff` table.
- Created a `menu_item` column that rolls sizes (Sm/Rg/Lg) and promo versions into one menu item.
- Some names are shared between menu items and retail products (e.g. "Ethiopia" is both a brewed coffee and a bag of beans), so the analysis is filtered to menu categories (Coffee, Tea, Drinking Chocolate, Bakery).
- **24 sales rows (47 Ginger Scones) had $0 revenue.** These were free promo giveaways and were kept, so the cost counts against the item's profit.
- **The promo flag doesn't consistently match what customers paid:** 136 Ginger Scone sales were flagged as promo but charged full price, while most of the 156 Chocolate Croissants sold at $1.00 were not flagged.
- 112 sales recorded between 1–5 AM (outside opening hours) were excluded from the time-of-day analysis.
- Waste was calculated from total wasted ÷ total baked, rather than averaging the daily percentage column (which was stored as text).

## Limitations

- **One month of data**, so there are no trends or seasonality.
- **COGS uses a single wholesale price per product** and excludes milk, cups and other costs, so drink margins are likely overstated. Comparisons between items are more reliable than the exact amounts.
- **Waste is only tracked for 5 of 11 pastries**, and not for drinks (which are made to order).
- **Generation analysis only includes loyalty customers** with birth-year data.
- **Promotion impact can't be measured**, since there's no comparison period without promotions.

---

## Repository Contents

```
├── CoffeeShopSales.sql               # Data cleaning and analysis queries
├── Coffee_Shop_Sales_Dashboard.pbix  # Power BI report
├── images/                           # Dashboard and data model screenshots
└── README.md
```
