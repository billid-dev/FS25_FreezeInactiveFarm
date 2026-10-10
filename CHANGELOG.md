# Changelog

All notable changes to **Farm Freeze** (`FS25_FreezeInactiveFarm`) are documented here.

> Versions 1.0.1.0 – 1.0.5.0 were internal test builds made while the mod was being developed. They are listed for completeness.

## 1.0.7.0

- The settings menu is now translated: Polish when the game language is Polish, English in every other language.

## 1.0.6.0

- Fixed manure still increasing on frozen farms: the manure production rate (kept in the straw part of a husbandry) was not frozen.
- Fixed Bank & Credit compatibility: the mod could not see the Bank & Credit classes, so loan payments were still collected for frozen farms. The hook now attaches correctly and is confirmed in the log at start-up.

## 1.0.5.0

- Bank & Credit: fixed loans being repaid on frozen farms while the bank balance stayed frozen.
- Loan payments, interest and fees are now skipped for frozen farms when either the loan or the bank balance freeze is on.
- Taking, repaying and drawing loans is blocked for frozen farms (closing a revolving line only with the loan freeze on).
- The Bank & Credit compatibility hook is now confirmed in the log at start-up and retried if the mod loads later.

## 1.0.4.0

- New separate switch in the settings menu for manure and slurry.
- Added a note that, when used with Enhanced Animal System, animals need some feed and water (if water is required) to survive on a frozen farm.
- All mod versions on the server and on the players' machines must be the same.

## 1.0.3.0

- Compatibility with Bank & Credit (FS25_BankCredit): loan payments and interest are not collected for frozen farms (the remaining loan balance and term stay unchanged while the farm is frozen).
- Compatible with Enhanced Animal System.
- NOT compatible with Animal Planner (FS25_AnimalPlanner): with it installed, animals do not generate pallets or products (eggs, milk, wool, etc.).
- Extra safeguard: manure and slurry stored in husbandries no longer increase on frozen farms.

## 1.0.2.0

- Added optional debug messages for balance and loan (visible only when debug is enabled).
- Author set to billiD.

## 1.0.1.0

- Fix: vehicle age and operating hours are now also frozen on dedicated servers. The server sends the list of frozen farms to the clients, which restore the age of those farms' vehicles.

## 1.0.0.0

- Initial release.
- Freezes, while no manager of a farm is online: bank balance, loans, vehicle age and operating hours, animal time (aging, reproduction, health), feed, water and straw in husbandries, and husbandry production (eggs, milk, wool, manure, slurry).
- In-game settings menu with a switch for every feature (server admin only, synced to all players).
