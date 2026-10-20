# Gold and Economy History Addon Research

This document summarizes existing World of Warcraft addons that track gold and economy data, then proposes design directions and feature sets for an `AltArmy_TBC` "gold and economy history" feature.

## Existing addons to study

### Accountant Classic

- URL: [CurseForge](https://www.curseforge.com/wow/addons/accountant-classic)
- Focus: General money in/out tracking with timeline views.
- Notable features:
  - Tracks income and expenses by source (vendor, loot, quest, etc.)
  - Session plus daily/weekly/monthly/yearly views
  - Character switching and realm-aware storage
  - Location summary support

### Kerzo's Gold Tracker

- URL: [CurseForge](https://www.curseforge.com/wow/addons/kerzos-gold-tracker)
- Focus: Daily history and trend analysis.
- Notable features:
  - Daily transaction logs with source visibility
  - Calendar-based navigation by date
  - Monthly daily overview
  - Graphical trend view

### Gold Tracker Plus

- URL: [CurseForge](https://www.curseforge.com/wow/addons/gold-tracker-plus)
- Focus: Category and timeline-based accumulation.
- Notable features:
  - Categories such as world, instance, questing, sales, purchases, repairs
  - Timelines: day, week, month, year, all-time
  - Archive access for historical month/year records

### Journalator

- URLs:
  - [CurseForge](https://www.curseforge.com/wow/addons/journalator)
  - [GitHub](https://github.com/Auctionator/Journalator)
- Focus: Detailed transaction journaling across systems.
- Notable features:
  - AH postings/sales/expired/cancelled tracking
  - Vendor transactions, repairs, quest rewards, loot, mail, trades
  - Summary section showing gain/loss by source
  - CSV export for external analysis
  - Filtering and ignore options (for categories/transfers)

### Auctionator + Journalator ecosystem

- URLs:
  - [Auctionator (CurseForge)](https://www.curseforge.com/wow/addons/auctionator)
  - [Auctionator (GitHub)](https://github.com/Auctionator/Auctionator)
- Focus: Practical AH workflows and pricing support.
- Notable features:
  - Item tooltip pricing (scan-based)
  - Posting and undercut assistance
  - Search and shopping list workflows
  - Journalator add-on path for transaction history

### TSM Ledger

- URLs:
  - [TSM Ledger docs](https://support.tradeskillmaster.com/en_US/tsm-addon-documentation/tsm-addon-ledger)
  - [TSM Ledger announcement](https://blog.tradeskillmaster.com/introducing-tsm-ledger/)
- Focus: Advanced economy analytics.
- Notable features:
  - Revenue/expense/failed-auction views
  - Filterable analytics by character/profile/server/account
  - Inventory + transaction analysis integration
  - Dashboard and reporting orientation

### MoneyLooter

- URL: [CurseForge](https://www.curseforge.com/wow/addons/moneylooter)
- Focus: Farm-session profitability.
- Notable features:
  - Gold/hour session tracking
  - Loot value with price-source fallback chain
  - "Raw gold + item value" session perspective

### Altoholic (account-wide context pattern)

- URL: [CurseForge](https://www.curseforge.com/wow/addons/altoholic)
- Focus: Multi-character consolidated account data.
- Relevant pattern:
  - Per-character money + subtotals + account grand totals in one view

## Common capabilities in current ecosystem

- Session and lifetime gold tracking
- Per-character and often account/realm totals
- Basic source categorization for income/expenses
- AH-specific tracking in specialized addons
- Basic trend visualization in select tools

## Gaps and opportunities for AltArmy_TBC

- Unified timeline linking gold changes to context (character, zone, activity)
- Strong alt-centric insights instead of only raw totals
- Better handling of internal transfers to avoid misleading net results
- Actionable intelligence layer (detect major spend categories, unusual days)
- Simpler UX than full AH suite addons while keeping useful analytics

## Proposed design direction

### 1) Event-first data model

Store normalized economy events with fields like:

- `timestamp`
- `character`
- `realm` and `faction`
- `deltaCopper` (positive/negative)
- `sourceType` (loot, vendor, repair, quest, mail, trade, AH, etc.)
- `context` (zone, instance, optional activity marker)
- `counterparty` when relevant (mail/trade)

Why this matters:
- Enables future reporting without changing storage format
- Supports rollups for session/day/week/month/all-time with one pipeline

### 2) Core UX views (first release target)

- **Overview dashboard**
  - Net change for today, 7 days, 30 days
  - Top income and expense categories
- **Timeline view**
  - Daily bars with drill-down into event list
- **Character comparison**
  - Per-alt contribution and spend breakdown
- **Session panel**
  - Current session net and gold/hour
- **Transfers view**
  - Mail/trade transfers with "ignore internal transfers" option

### 3) Analytics layer (follow-up)

- Trend smoothing (moving average)
- Outlier day detection
- Maintenance-cost analysis (repairs/flight/postage share)
- Profitability by activity context (instance vs open world)

### 4) Export and interoperability

- CSV export by date range and category/source
- Optional use of external addon price data when available
- Graceful fallback behavior when no external pricing source exists

## Recommended phased feature set

### MVP

- Event capture and persisted history
- Session/day/week/month/all-time rollups
- Character + account totals
- Category breakdowns
- Internal transfer filtering

### Phase 2

- Calendar drill-down
- Zone/activity summaries
- CSV export
- Configurable category/monitor filters

### Phase 3

- Price-aware item-value mode (if external pricing data exists)
- Insight cards/alerts
- Specialized presets (farm mode, raid expense mode, auction mode)

## Product positioning recommendation

For broad usability on WoW: Forever (and TBC Anniversary):

- Keep the entry experience as simple as Accountant Classic
- Add deeper journals and export workflows like Journalator
- Differentiate with AltArmy-style multi-character intelligence and planning insights

This positioning should provide immediate value to casual users while preserving room for advanced economy analysis over time.
