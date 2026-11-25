# Finances

Native macOS app (SwiftUI + SwiftData) for planning and tracking summer-job money: expected income, allocation buckets, paychecks, and spending.

## Requirements

- A Mac with **macOS 14 Sonoma** or later
- **Xcode 15+** (Xcode 16 recommended) from the Mac App Store

## Open and run

1. Clone this repository on your Mac:
   ```bash
   git clone https://github.com/JulianSteckl/Finances-.git
   cd Finances-
   ```
2. Open the project:
   ```bash
   open Finances.xcodeproj
   ```
   Or double-click `Finances.xcodeproj` in Finder.
3. In Xcode, select the **Finances** scheme and **My Mac** as the run destination.
4. Press **⌘R** (Product → Run).

On first launch the app creates the base money plan ($20/hr, 29.5 hrs/week, 13 weeks, $15/week allowance, $45/week spending, $50 gas every two weeks, $1,600 savings goal) so you can start immediately.

## What’s in v2

Black-and-white design with light and dark mode. Money goes into four buckets: **Stocks, Savings, Spending, Gas**. Gas, spending and savings get fixed amounts for the year; Stocks gets whatever is left.

| Area | Behavior |
|------|----------|
| **Overview** | Saved + invested, earned so far, projected total at week 52, and money left to spend this week. Year outlook chart for all four buckets, weekly pay chart, spending ring, "Move your money" checklist for the latest paycheck, and recent activity. |
| **Paychecks & log** | Log paychecks (with hours), spending, gas and allowance. Live split preview, pay forecast chart, and the full log with delete confirmation. |
| **Year plan** | What-if sliders (pay, hours, weeks, spending, savings goal, stock return), where the year's money goes, and stocks over 5 years. Save a what-if as your plan. |
| **Plan settings** | Season dates, pay schedule, overtime, tips, bonuses, target override, and the year budget (allowance, spending, gas, savings goal, starting money, tax, returns). Saves when you leave the screen. |

**Backup:** Plan settings can back up everything to a file, restore it (with undo), and export the log as a spreadsheet. Backup files are not encrypted.

**Menu bar quick log:** while the app is running, the menu bar shows what's left to spend this week. Click it to log a purchase, gas or allowance.

The sidebar shows each bucket's balance: money moved in from the checklist (or allowance), minus spending and gas.

Data is stored locally with **SwiftData** (no account or server).

## Project layout

```
Finances.xcodeproj     Xcode project
Finances/
  FinancesApp.swift    App entry + SwiftData container
  ContentView.swift    macOS NavigationSplitView shell
  Models/              IncomePlan, MoneyEntry, Bucket (BudgetCategory is legacy)
  Views/               Overview, Paychecks, Year plan, Plan settings
  Utilities/           Theme, PlanMath (year math), Ledger (balances), formatting, seed data
  Assets.xcassets
```

## Notes

- Cloud Linux agents cannot compile or run the Mac UI; build and run on a Mac with Xcode.
- If code signing prompts appear, choose your personal team under Signing & Capabilities, or leave Automatic signing for local Run.
