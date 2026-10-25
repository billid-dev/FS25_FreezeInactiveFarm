<p align="center">
  <img src="icon.png" alt="Farm Freeze logo" width="200">
</p>

<h1 align="center">Farm Freeze – Offline Farm Pause</h1>

<p align="center">
  A multiplayer mod for <b>Farming Simulator 25</b>: when nobody who manages a farm is online, that farm is frozen until a manager returns.
</p>

<p align="center">
  <img alt="Farming Simulator 25" src="https://img.shields.io/badge/Farming%20Simulator-25-4c9a2a">
  <img alt="Multiplayer" src="https://img.shields.io/badge/multiplayer-supported-2b7bb9">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0.0-e08a1e">
  <a href="https://discord.gg/gxwC8vUUch"><img alt="Discord" src="https://img.shields.io/badge/discord-join-5865F2?logo=discord&logoColor=white"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.pl.md">Polski</a>
</p>

---

## What is this?

You play with friends, each of you on a separate farm, but you are not all online at the same time. As soon as one player skips time, the farms of absent players keep living: money drains through costs, machines age and lose value, animals grow old, feed runs out, loans get repaid.

**Farm Freeze stops that.** A farm whose managers are all offline is paused, and everything that belongs to it stays exactly as it was. When a manager joins the server again, the farm is unfrozen automatically and continues from where it stopped.

> Mod ID: `FS25_FreezeInactiveFarm` · Author: **billiD**

## What gets frozen

While none of a farm's managers is online:

| Area | What is frozen |
|---|---|
| Bank balance | Income, costs and fees do not change the balance |
| Loans | No interest, no payments; the loan balance and remaining term stay unchanged (including loans from the *Bank & Credit* mod) |
| Vehicles | Age and operating hours |
| Animals | Aging, reproduction and health changes |
| Feed, water, straw | Consumption in the farm's husbandries |
| Husbandry production | Milk, eggs, wool and other pallet products |
| Manure and slurry | Production in the farm's husbandries (separate switch) |

Fields, factories and production outside husbandries are **not** frozen.

## Features

- Works fully on the **server side**; nothing to set up.
- Farms **unfreeze automatically** the moment one of their managers joins.
- **In-game settings menu** (Settings → *Farm Freeze*) with a master switch and a separate switch for every feature, each with a description.
- Only the **server admin** can change the settings; changes are synchronised to all players and saved between sessions.
- Menu available in **English and Polish** (follows the game language; every language other than Polish shows English).
- Compatible with **Bank & Credit** and **Enhanced Animal System** (see below).

## Compatibility

| Mod | Status | Notes |
|---|---|---|
| Bank & Credit (`FS25_BankCredit`) | ✅ Compatible | Loan payments, interest and fees are skipped for frozen farms, and taking, repaying or drawing loans is blocked for them. |
| Enhanced Animal System | ✅ Compatible | Animals can die in this mod, so they need some feed and water (if water is required) on a frozen farm – see [Good to know](#good-to-know). |
| Animal Planner (`FS25_AnimalPlanner`) | ❌ Not compatible | With Animal Planner installed, animals do not generate pallets or products (eggs, milk, wool, etc.). |

Mods that rewrite husbandry or banking logic may not be fully covered. If you find one that conflicts, please [open an issue](../../issues/new?template=bug_report.md).

## Installation

1. Download `FS25_FreezeInactiveFarm.zip` from the [Releases](../../releases) page (or from GIANTS ModHub once the mod is published there).
2. Put the ZIP – **do not unzip it** – into your mods folder:
   - Windows: `Documents\My Games\FarmingSimulator2025\mods`
   - macOS: `~/Library/Application Support/FarmingSimulator2025/mods`
3. **Dedicated server:** upload the ZIP to the server's mods folder and restart the server.
4. Enable the mod when you create or load a savegame.

> ⚠️ **The mod version must be identical on the server and on every player's machine.** Mixed versions can break the synchronisation of the settings and of vehicle age.

## Settings

Open **Settings → Farm Freeze** in the game menu. Server admins can change the switches; other players see them but cannot change them.

| Switch | What it controls |
|---|---|
| Farm Freeze: mod enabled | Master switch. When off, no farm is frozen, whatever the other switches say. |
| Freeze bank balance | The farm's bank balance. |
| Freeze loans | Loan interest and payments (also in Bank & Credit). |
| Freeze vehicle age | Age and operating hours of the farm's vehicles. |
| Freeze animal time | Aging, reproduction and health of the farm's animals. |
| Freeze feed, water and husbandry production | Consumption of feed, water and straw, and production of milk, eggs and wool. |
| Freeze manure and slurry | Production of manure and slurry in the farm's husbandries. |

Settings are stored on the server in `modSettings/FS25_FreezeInactiveFarm.xml` (inside the server's profile folder). All switches are on by default.

## Good to know

- **"Frozen" means frozen.** While no manager of a farm is online, everything listed above stays as it was – *even if another, non-manager member of that farm is playing*. Money changes made in that time are reverted.
- **A farm with no manager at all stays frozen permanently.**
- **Animals need feed and water.** Freezing keeps what a husbandry contains; it does not refill it. With Enhanced Animal System, animals that have no feed or no water (where required) can still lose health and die on a frozen farm, so stock your husbandries before you leave the server.
- **The mod does not undo the past.** A loan that was repaid, or manure that was produced, before the mod was installed or while the farm was not frozen is not restored.
- A farm unfrozen with an empty feed trough will starve like any other farm.

## How it works

The mod runs on the server and checks every farm once per second. A farm is *frozen* when none of its managers is connected. For a frozen farm:

- **Money** – the balance is recorded when the farm freezes and any change is reverted. **Loans** – the stored loan is restored; for *Bank & Credit* the monthly collection is skipped entirely (otherwise the money would be refunded while the principal was already reduced).
- **Vehicles** – age and operating hours are restored on the server, and the server sends the list of frozen farms to the clients, which restore them locally too (clients count vehicle age themselves, so this is needed on dedicated servers).
- **Animals** – the hourly/daily/monthly husbandry events are blocked.
- **Feed, water, straw** – levels are recorded and any drop is put back through the game's husbandry functions.
- **Production** – production rates are set to zero, the production factors of the output calculation are zeroed, and pallet fill levels cannot rise. Manure is produced by the straw part of a husbandry (`outputLitersPerHour`), slurry by the liquid-manure part; both are zeroed under their own switch.

Nothing is written into the savegame; settings live in the server's `modSettings` folder.

## Troubleshooting

Look for these lines in `log.txt` after the map has loaded (on a dedicated server: the server's log):

```
[FarmFreeze] Mod loaded (version 1.0.0.0).
[FarmFreeze] Bank & Credit compatibility active (...)      <- only if Bank & Credit is installed
```

- The first line confirms which version is running. If it is missing or shows another version, the game is using a different file.
- If the mod hits an error, the game writes a Lua error mentioning `FarmFreeze` to the log; please include those lines (and a few lines around them) in bug reports.
- For detailed diagnostics set `FarmFreeze.DEBUG = true` at the top of `FarmFreeze.lua` (unzip the mod, edit the file, zip it again with the files at the root of the archive).

## Reporting bugs

Please [open an issue](../../issues/new?template=bug_report.md) and include:

- mod version and game version,
- single player, player-hosted multiplayer or dedicated server,
- the list of installed mods (especially animal, bank and time mods),
- what you expected and what happened,
- the `[FarmFreeze]` lines from `log.txt`.

You can also ask on the [Discord server](https://discord.gg/gxwC8vUUch).

## For developers

Repository layout:

```
modDesc.xml              mod descriptor (version, descriptions, changelog)
FarmFreeze.lua           core logic: freezing, restoring, hooks, Bank & Credit compatibility
FarmFreezeGui.lua        settings menu, fallback translations, settings synchronisation
FarmFreezeStateSync.lua  server → client list of frozen farms
icon_FreezeInactiveFarm.dds   mod icon (DDS without mipmaps, named as ModHub requires)
icon.png                 logo used by this README (not part of the mod ZIP)
l10n/l10n_en.xml         English texts (also used for every language without its own file)
l10n/l10n_pl.xml         Polish texts
```

Build the mod ZIP with the files at the **root** of the archive (not inside a folder):

```bash
zip -r FS25_FreezeInactiveFarm.zip modDesc.xml FarmFreeze.lua FarmFreezeGui.lua FarmFreezeStateSync.lua icon_FreezeInactiveFarm.dds l10n
```

### Adding a translation

1. Copy `l10n/l10n_en.xml` to `l10n/l10n_<code>.xml` (for example `l10n_de.xml`).
2. Translate the `text="..."` values and keep the `name="farmFreeze_..."` keys unchanged.
3. Build the ZIP so that it includes the `l10n` folder.

The game picks the file that matches its language; any language without a file uses English. Pull requests with new translations are welcome.

## Credits

Made by **billiD** ([@billid-dev](https://github.com/billid-dev)).

## License

Copyright © 2026 billiD. All rights reserved unless a `LICENSE` file in this repository states otherwise.
