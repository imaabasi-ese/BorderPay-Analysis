# BorderPay: Revenue Leak Audit

**Tools:** MySQL · Power BI  
**Industry:** FinTech · Cross-Border Payments  
**Level:** Advanced  
**Timeline:** 2023 to 2024



## The Story Behind This Project

BorderPay is a fast-growing cross-border payments platform that helps freelancers and remote workers across Africa, Asia, and Latin America receive international payments from clients worldwide.

On paper, the company was growing. Transaction volumes were rising month after month. But something was off. Customer complaints kept increasing, support teams were overwhelmed, and when analysts looked closely at the raw transaction logs, a troubling pattern emerged. Thousands of payment attempts were never completing. Users were retrying failed payments out of frustration. Some were abandoning the platform entirely.

The company had been celebrating growth while silently bleeding money.

Nobody was measuring the cost of what was going wrong. That is where this project begins.



## The Objective

This project audits the hidden cost of transaction failures at BorderPay. Rather than reporting on revenue earned, the analysis investigates revenue lost, specifically:

* How much transaction value is disappearing before it reaches the books
* How users are responding when their payments fail
* Which customers are leaving the platform because of repeated failures
* Which payment corridors are creating the most friction
* When failures are most likely to happen during the day and week
* How much operational pressure failures are placing on support teams

The findings are delivered through a three-page Power BI executive dashboard designed to give leadership a clear, prioritised roadmap for recovery.



## Dashboard Preview

### Page 1: Revenue Leakage Analysis

*How Much Are Failed Transactions Costing BorderPay?*

!\[Revenue Leakage Dashboard](screenshots/page1\_revenue\_leakage.png)

BorderPay attempted over $63 million in transactions across the analysis period. Only $30 million settled successfully. The remaining $29 million, representing a 45.26% revenue leakage rate, vanished into failed transactions before ever reaching a recipient.

The page breaks down where transactions drop off in the processing pipeline, whether leakage is improving or worsening month by month, and which failure reasons are responsible for the largest financial losses.



### Page 2: Customer Friction Monitor

*How Are Payment Failures Affecting Our Users?*

!\[Customer Friction Monitor](screenshots/page2\_customer\_friction.png)

When a payment fails, users do not simply wait quietly. This page tracks what happens next. On average, users attempted 5.63 retries after a failed transaction. 66.13% eventually recovered and completed a successful payment. But 36.61% of users who experienced failures showed no platform activity for the following 30 days, a signal that repeated failures are quietly driving customers away.

Nigeria generated the highest failure rate at 54.1%, followed closely by Bangladesh at 50.7% and Ghana at 49.3%. The combo chart confirms a direct relationship between transaction failures and support ticket volume, with peak failure months correlating with spikes in customer complaints.



### Page 3: Recovery Opportunity Dashboard

*Which Problems Should BorderPay Fix First?*

!\[Recovery Opportunity Dashboard](screenshots/page3\_recovery\_opportunity.png)

This page shifts from diagnosis to decision. The USD to NGN corridor recorded the highest failure rate at 54.78%, making it the single most urgent corridor to address. All five NGN corridors, regardless of sending currency, appear at the top of the failure ranking, confirming that the problem lies with Nigerian receiving infrastructure rather than any specific sending currency.

The recovery scenarios table estimates that a 25% reduction in failures could recover $7.15 million in lost revenue. A 50% reduction would recover $14.30 million. The hour-of-day analysis reveals that failures peak sharply between midnight and 3am, likely due to scheduled bank maintenance windows across multiple markets running simultaneously.



## Data Model

The project uses five interrelated tables:

|Table|Description|Rows|
|-|-|-|
|transactions|Every payment attempt including status, amount, corridor and failure reason|25,000|
|users|Customer profiles including country and registration date|3,000|
|retries|All retry attempts linked to original failed transactions|15,032|
|user\_activity|Login and platform activity logs used for abandonment analysis|49,190|
|support\_tickets|Customer complaints linked to failed transactions|5,091|

All five tables were imported as raw messy CSVs and cleaned entirely in SQL before any analysis was performed.



## Data Cleaning

Raw data rarely arrives in a usable state. Before writing a single analysis query, a full diagnostic audit was run across all five tables to identify every problem present. The issues found and fixed are documented below.

**Problems identified:**

* 375 duplicate transaction records
* Inconsistent date formats across all tables, for example 2023-01-15 versus 01/15/2023 versus 15-Jan-2023
* Inconsistent text casing in status columns, for example Settled versus settled versus SETTLED versus Setteld
* 226 failed transactions missing a failure reason
* 237 settled transactions missing a settled amount
* 503 corridor values with leading or trailing whitespace
* Misspelled country names including Nigria, Phillipines and Bangldesh
* Missing email addresses in the users table

**How each problem was fixed:**

Duplicates were removed using ROW\_NUMBER() with PARTITION BY on the primary key, keeping only the first occurrence of each record. Date formats were standardised using STR\_TO\_DATE() with CASE WHEN logic to detect and convert each format pattern. Status inconsistencies were corrected using CASE WHEN combined with UPPER() and TRIM() to catch every variation regardless of casing or spacing. Blank values were handled using COALESCE() and NULLIF(), replacing missing failure reasons with Unclassified and missing settled amounts with 0.00. The corridor column was rebuilt entirely using CONCAT(sender\_currency, ' - ', receiver\_currency) to resolve a character encoding conflict from the CSV import. Country misspellings were corrected in SQL for the transactions and users tables. For the user\_activity and support\_tickets tables, country standardisation was completed in Power Query due to a character encoding issue in MySQL that prevented UPPER() and TRIM() from matching the stored values correctly.

A clean version of each table was created using CREATE TABLE AS SELECT, preserving the original raw data throughout.



## SQL Skills Demonstrated

|Skill|Where It Was Used|
|-|-|
|CTEs|Breaking complex multi-step queries into readable, logical stages|
|ROW\_NUMBER()|Identifying and removing duplicate records|
|RANK()|Ranking payment corridors by failure rate|
|STR\_TO\_DATE()|Converting text dates into proper DATETIME values|
|CASE WHEN|Standardising status values and classifying abandonment|
|COALESCE and NULLIF|Handling NULL and blank values cleanly|
|TRIM and UPPER|Removing whitespace and normalising text casing|
|CONCAT|Rebuilding the corridor column from two clean currency fields|
|HOUR and DAYOFWEEK|Extracting time components for failure pattern analysis|
|LEFT JOIN|Preserving users with no activity records in abandonment analysis|
|INNER JOIN|Connecting transactions to users and tickets for support analysis|
|DATEDIFF|Calculating days between last failure and last login|
|UNION ALL|Combining hourly and daily failure analysis into one output|
|Conditional Aggregation|Calculating metrics per category within a single query using SUM(CASE WHEN)|
|GROUP BY|Summarising data by corridor, country, hour and failure reason|



## Analysis Queries

Six business questions were answered through SQL before the data was visualised in Power BI.

**Query 1: Revenue Leakage Analysis**
How much transaction value was attempted versus successfully settled, and what is the overall revenue leakage rate?

**Query 2: Retry Behaviour Analysis**
When payments fail, do users recover by completing a successful retry, or do they give up entirely? A recovered user is defined as someone who experienced a failed transaction and completed a successful retry within the same session.

**Query 3: Customer Abandonment Analysis**
Which users experienced transaction failures and then showed no platform activity for the following 30 days? The 5 8730-day threshold was chosen because BorderPay's users are freelancers whose natural payment cycles span two to four weeks, meaning shorter thresholds risk misclassifying users who are simply between projects.

**Query 4: Payment Corridor Performance**
How does each currency route perform in terms of success rate, failure rate, revenue leakage, and processing time? Corridors are ranked from highest to lowest failure rate.

**Query 5: Time-Based Failure Analysis**
Are there specific hours of the day or days of the week where failure rates consistently spike, suggesting infrastructure bottlenecks or banking maintenance windows?

**Query 6: Support Burden Analysis**
How many support tickets are being generated per 1,000 failed transactions by country, and which complaint categories are most common? This measures the operational cost of technical friction beyond the direct revenue impact.



## Power BI Skills Demonstrated

* DAX measures including CALCULATE, DIVIDE, SUMX, AVERAGEX, TREATAS and SELECTEDVALUE
* TOPN for identifying the highest risk corridor and highest cost failure category as dynamic card values
* Funnel chart for transaction pipeline drop-off and user recovery journey
* Line and column combo chart for correlating failed transactions with support ticket volume
* Matrix table with conditional formatting for corridor performance analysis
* Scatter chart for corridor priority analysis plotting failure rate against revenue lost
* Treemap for visualising transaction volume distribution across corridors
* Recovery scenario table built from a manually entered reference table
* Year slicer using tile format for clean year-on-year filtering
* Hour of Day column created from the transaction datetime for time-based visual analysis



## Key Findings

BorderPay's growth story has a shadow. While transaction volumes climbed consistently, nearly half of every dollar attempted never reached its destination. The $29 million in failed transaction value represents not just lost revenue but lost trust, with over a third of affected users disappearing from the platform entirely within 30 days of their last failure.

The problem is not evenly distributed. All five NGN corridors, covering payments from USD, GBP, EUR, CAD and AUD into Nigeria, sit at the top of the failure ranking regardless of sending currency. This confirms the issue is concentrated in Nigerian receiving infrastructure rather than any specific sending currency or gateway.

Fraud Filter Triggered was the most expensive single failure reason, responsible for $7.1 million in lost revenue. This suggests the fraud detection model is generating significant false positives, blocking legitimate transactions and frustrating genuine users.

Failures peak sharply between midnight and 3am, a window that aligns with scheduled bank maintenance periods across multiple African and Asian markets running simultaneously. Addressing this single operational window could meaningfully reduce the platform's overall failure rate.



## Recommendations

The analysis does not stop at identifying problems. Each finding points to a specific action that BorderPay's product, engineering and operations teams can act on immediately.

**1. Audit the Fraud Filter Model**

Fraud Filter Triggered is responsible for $7.1 million in lost revenue and accounts for nearly 25% of all failures. At that scale, a significant proportion of these rejections are almost certainly false positives blocking legitimate transactions from real users. A threshold review and model recalibration should be the first engineering priority. Even a modest improvement in fraud filter accuracy could recover millions in currently blocked revenue.

**2. Address Nigerian Receiving Infrastructure**

Every single NGN corridor sits at the top of the failure ranking, with rates between 53% and 55% regardless of which currency is being sent. This is not a gateway problem or a sending currency problem. It is a receiving infrastructure problem specific to Nigeria. BorderPay should negotiate dedicated settlement windows with Nigerian banking partners or evaluate alternative local settlement providers to reduce dependency on unstable connections.

**3. Introduce Maintenance Window Awareness for Users**

Failures peak sharply between midnight and 3am across multiple markets at the same time. Users attempting payments during this window have no way of knowing the platform is experiencing elevated instability. Surfacing a real-time alert before a user submits a payment during a known high-risk window would reduce failed attempts, reduce frustration and reduce the support tickets that follow.

**4. Launch a Re-engagement Campaign for Churned Users**

36.61% of users who experienced failures showed no platform activity for 30 days afterward. These users have not officially closed their accounts but they have stopped transacting. They represent $11.4 million in at-risk revenue. A targeted re-engagement campaign offering fee waivers or priority customer support for recently inactive users could recover a meaningful portion of this group before they permanently switch to a competing platform.

**5. Automate Post-Failure Status Notifications**

Bangladesh generates the highest support ticket volume per 1,000 failures in the dataset. Payment Not Received is the dominant complaint category across every market. In most cases users are raising tickets not because they need human intervention but because they have no visibility into what happened to their payment. Automated status update notifications sent immediately after a failure would address the root cause of the majority of inbound support volume without requiring additional headcount.

## About

This project is part of a professional data analytics portfolio built to demonstrate end-to-end analytical capability across SQL, Power BI and business storytelling. The dataset was synthetically generated to reflect realistic cross-border payment patterns and contains intentional data quality issues to demonstrate practical data cleaning skills.



