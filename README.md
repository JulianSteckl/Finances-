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

On first launch the app seeds starter categories (**Stocks**, **Savings**, **Gas**) and a default income plan so you can start immediately.

## What’s in v1

| Area | Behavior |
|------|----------|
| **Income plan** | Set hours/week, hourly wage, and season length — or a total summer target. |
| **Allocations** | Split planned income by **percent** or **dollars** across categories; add/delete custom buckets; see planned vs remaining. |
| **Tracking** | Log paychecks and spending (optionally tagged to a category); compare actuals on Overview. |
| **Overview** | Planned vs earned, spending, allocation progress, and recent activity. |

Data is stored locally with **SwiftData** (no account or server).

## Project layout

```
Finances.xcodeproj     Xcode project
Finances/
  FinancesApp.swift    App entry + SwiftData container
  ContentView.swift    macOS NavigationSplitView shell
  Models/              IncomePlan, BudgetCategory, MoneyEntry
  Views/               Overview, Income, Allocations, Tracking
  Utilities/           Formatting + seed/math helpers
  Assets.xcassets
```

## Notes

- Cloud Linux agents cannot compile or run the Mac UI; build and run on a Mac with Xcode.
- If code signing prompts appear, choose your personal team under Signing & Capabilities, or leave Automatic signing for local Run.
