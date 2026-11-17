# Finances

Native macOS app (SwiftUI + SwiftData) for a summer-only job: forecast earnings from your real schedule, then stretch that money through the school year.

Built around Julian’s schedule defaults: **$20/hr** (no tax), **Mon–Thu ~4–5 hrs**, **Friday ~7–8 hrs**, summer **May 21 → ~Aug 17**, school-year runway until the next **May 21**.

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

On first launch the app seeds **Stocks (25%)**, **Savings (25%)**, **Gas (10%)**, and leaves the rest for school-year living — plus a schedule-based income plan.

If you already ran v1, delete the app (or its data) once so SwiftData can pick up the new plan fields cleanly, or just edit the Income Plan dates/hours and tap Save.

## What’s in v2

| Area | Behavior |
|------|----------|
| **Income plan** | Mon–Thu + Friday hours, $20/hr default, summer date range, optional total override. |
| **School-year runway** | Living pool after Stocks/Savings; safe weekly/monthly spend; weeks left; on-track vs actual burn. |
| **Allocations** | Percent or dollar buckets; custom categories; planned vs remaining (unallocated = living money). |
| **Tracking** | Paychecks and spending; optional category tags. |
| **Overview** | Summer plan vs earned/spent, runway cards, allocation progress, recent activity. |

Data is stored locally with **SwiftData** (no account or server).

## Project layout

```
Finances.xcodeproj     Xcode project
Finances/
  FinancesApp.swift    App entry + SwiftData container
  ContentView.swift    macOS NavigationSplitView shell
  Models/              IncomePlan, BudgetCategory, MoneyEntry
  Views/               Overview, Income, Allocations, Tracking
  Utilities/           Formatting, season calendar, seed/math
  Assets.xcassets
```

## Notes

- Cloud Linux agents cannot compile or run the Mac UI; build and run on a Mac with Xcode.
- If code signing prompts appear, choose your personal team under Signing & Capabilities, or leave Automatic signing for local Run.
