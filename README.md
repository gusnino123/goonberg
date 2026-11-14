# Goonberg Terminal

**A trading terminal for the Auction House.** Built for World of Warcraft: Forever.

Goonberg Terminal turns the Auction House into a stock market screen: candlestick price charts, market depth, price alerts, a market overview with the realm's biggest movers, a deal finder, crafting profit for your professions, a P&L card for your trading, and AH value on every item you hover. Your guild shares its scans, so prices stay fresh even when you're nowhere near an auctioneer.

Type **`/goon`** in game to open it, or click the goblin under your minimap.

---

## Install

1. Download the latest `GoonbergTerminal-x.y.z.zip` from the [Releases page](https://github.com/gusnino123/goonberg/releases).
2. Unzip it so the `GoonbergTerminal` folder sits in your WoW Forever `Interface/AddOns` folder. You should end up with `AddOns/GoonbergTerminal/GoonbergTerminal.toc`, not a folder inside a folder.
3. Quit the game completely and start it again (new addons aren't picked up by `/reload`).
4. At character select, click **AddOns** and make sure **Goonberg Terminal** is ticked.

**Automatic updates:** in [WowUp](https://wowup.io), choose **Get Addons → Install from URL** and paste `https://github.com/gusnino123/goonberg`. WowUp updates Goonberg whenever a new version is released.

---

## How it works

**1. Scanning.** Open the Auction House and Goonberg opens beside it and scans the whole AH on its own, then again every 15 minutes while the AH stays open. That's as often as Blizzard allows (one full scan per 15 minutes per account). Each scan saves every item's price, quantity and depth, which is what builds the charts. If another addon (like Auctionator) runs the full scan, Goonberg reads the same results instead of missing out.

**2. Everything works away from the AH.** Close the AH and the charts, overview, tooltips and crafting margins keep working from your saved data, anywhere in the world. Prices are as fresh as the last scan, yours or your guild's.

**3. Guild sync.** Every guildmate running Goonberg shares their scans with the rest of the guild over the game's addon channel. It's kept light: it sends nothing unless a guildmate runs Goonberg, and after that only items whose price or quantity changed:
- **Live:** when a guildmate scans, your prices update within minutes wherever you are, and your price alerts can fire from their scan.
- **Catch-up:** when you log in after being away, a guildmate fills in everything they scanned while you were gone, so your charts have no gaps.
- **New installs:** if you have little history, a guildmate sends you up to 21 days of daily prices at login.

Only your own scans are sent, nothing is relayed twice, and only guild messages are accepted.

**4. Auctionator import.** If you've used Auctionator, Goonberg adds every day of price history it remembers to your charts at each login, so you start with weeks of history.

**About "est. sold":** the game doesn't show sales. Goonberg counts units that disappear between two scans close together, which includes cancelled and expired auctions, so treat it as an estimate. It gets better the more often you (or your guild) scan.

**The Goonberg Index** is one number for your realm's market. It starts at 100 and moves with the average price change of the 25 most-traded trade goods (deep, liquid markets only; no gear), weighted by gold traded, like a stock index.

---

## The screens

### Overview
The whole market at a glance.
- Cards: the **Goonberg Index**, est. gold traded, listings on the AH, top gainer and top loser.
- Timeframes: **15m · 1h · 6h · 12h · 24h · 7d**. Every number on the screen follows the one you pick.
- Filters by category (Herbs, Ore & Bars, Cloth, Leather, Enchanting, Trade Goods, Consumables, Gear, Recipes, Other), **Gainers / Losers**, and a search box.
- Click any column header to sort; click again to flip. Click a row to open its chart; shift-click to link it in chat.

### Deals
Listings in the latest scan you can buy and make money on:
- **Rare:** a seldom-listed item (worth 5g+) showing up at least 20% under its **usual price** (its 60-day median) **and** under the cheapest it typically goes for. See *Rare finds* below.
- **Flip:** cheaper than the item's **market value**: its average over the last 14 days, counting the latest 3 days more (the same idea TradeSkillMaster uses). Buy and relist.
- **Vendor:** cheaper than what an NPC vendor pays for it. Buy it, vendor it: guaranteed profit, no waiting.
- **Disenchant:** gear cheaper than what it disenchants into.

Each deal shows **Buy at** (the cheapest listing), **Sell for** (what you'd get per item: after the 5% AH cut when you relist on the AH, or the full price from a vendor), **profit per item**, **margin** (profit ÷ what you pay), how many **units** are listed under the deal price and the **total** profit on all of them, plus how fast it sells.

Pick a minimum margin of **5%, 10%, 20% or 50%** after the AH cut (5% shows everything worth doing). Turn on **Sells daily** to skip things nobody buys. Sort by total, per item, margin or sales. **Click** a deal to search for it on the open Auction House, **right-click** for its chart, hover for the full math.

After every live scan you get a pop-up when new deals with a 10%+ margin add up to 5g or more (change it with `/goon deals alert 10`).

Deals are only as fresh as the last scan: someone may have bought them already. Deals from a guildmate's scan know the lowest price but not how many are listed ("1+").

### Rare finds
Rare items (a world-drop epic, a pricey blue, an uncommon recipe) are only listed now and then, so they never build up enough recent history for normal deals. Goonberg judges them over 60 days instead:
- **Usual price:** the median of the item's daily prices over 60 days.
- **Cheapest typical:** the low end it normally hits (cheaper than 90% of its days).
- A listing is a **rare find** when it's at least **20% under the usual price and under the cheapest typical**. That second check matters: an item that swings between 5g and 15g isn't special at 7g; one that's always 9g-11g is.
- Only items worth **5g+**, seen on **3+ separate days**, that are listed on at most half the days the AH was scanned (or usually just a couple at a time).
- **RARE** means solid history (6+ days); **RARE?** means thin (3-5 days). **Orange** means the whole item is trending down (its 14-day price is well under its 60-day one), so it may be cheap because the market is falling.
- Each new rare find gets its own pop-up. Change the rules with `/goon rare 30` (percent), `/goon rare min 10` (gold), `/goon rare days 4`, or turn pop-ups off with `/goon rare off`.

As with every deal, these are listing prices: the game doesn't show what things actually sold for.

### Chart
An interactive chart, TradingView-style:
- **Timeframes** in the chart's top bar: **15M · 1H · 6H · 12H · 1D · 1W · 1M · All**.
- **Crosshair:** move the mouse over the chart for a crosshair with the price on the right axis and the time on the bottom. The **legend** (top left) shows that candle's open, high, low, close, change and est. sold.
- **Zoom:** scroll the mouse wheel to zoom in and out around the cursor. **Pan:** click and drag to look back in time; **Back to now** returns to the present.
- **Styles:** Candles, Line or Area. **MA 7/25:** two moving averages. **Usual price:** shows the item's 60-day usual price and the cheapest it typically goes for.
- **Alerts on the chart:** **right-click** to set a price alert at that level (below the current price = "notify below", above = "notify above"). **Drag** a gold alert line to move it.
- The header's change, high, low and est. sold follow whatever window the chart shows.
- **Market depth** on the right: how many are listed at each price, and where the **wall** is. **Watchlist** on the left (type a name or shift-click an item to add it; right-click to remove). Alerts can also be typed in on the right.

The chart is only as detailed as the scans: zoomed into an hour you'll see a few candles about 15 minutes apart.

### Crafting (`/goon2`)
- **Recipes:** every recipe you know with cost to craft, what it sells for after the 5% AH cut, **profit**, **margin** and how fast it sells. Click a recipe to expand it: each reagent with quantity, price each, where the price came from (AH or vendor) and the line cost, then the total. Filter by profession, show **Profitable only**, sort by profit, margin or sold per day.
- **Overview:** how all your recipes perform: profitable count, median margin, daily profit pool, crafted items you actually sold, a 14-day margin chart, each profession, and which recipes are getting more or less profitable than last week.
- Recipes are learned when you open each profession window once. Vendor prices (vials, thread...) are learned when you open a vendor, so reagents use the cheaper of the vendor and the AH.

### P&L
A shareable profit card for **Today, 7 days, 30 days or All time**: net profit, ROI (when you flip), sold, bought, the AH cut, your best item and what your bags are worth, with a goblin on a pile of gold. **Share in chat** posts it to your guild; **Screenshot** saves the screen. Trades are read from your AH mail invoices, so open a mailbox to update it.

### Tooltips
Hover any item (bags, bank, mail, chat links, the AH) to see:
- Market price, **stack value**, lowest buyout now, **7-day change**, est. sold per day
- **Vendor price**, in green when vendoring pays more than the AH
- **Disenchant value** for green, blue and purple gear, in green when disenchanting beats selling. Hold **Shift** to see what it breaks into. It follows the WoW Forever disenchanting table, which goes by the item's **required level** (an estimate: the game doesn't tell addons what an item breaks into).

### Minimap button
The goblin under your minimap: **click** to open the terminal, **right-click** for your P&L, **drag** to move it. Hover it for the Goonberg Index and when the last scan was.

---

## Commands

Every command starts with `/goon` (or `/goonberg`). Wherever a command takes an `<item>`, you can type the name, shift-click the item into chat, or use its item ID.

### Windows
| Command | What it does |
|---|---|
| `/goon` | Open or close the terminal |
| `/goon overview` | Market overview |
| `/goon deals` | Listings priced under what they're worth |
| `/goon chart <item>` | Price chart for an item |
| `/goon2` or `/goon craft` | Crafting profit for your professions |
| `/goon pnl` | Your profit and loss card |

### Scanning and data
| Command | What it does |
|---|---|
| `/goon loot` | Loot tab: dungeon drops worth selling (where, drop chance, AH value, gold per run) |
| `/goon market` | Which market's daily Blizzard prices you get (`/goon market pvp`, `normal`, `rp`, `rppvp`, `auto`) |
| `/goon scan` | Full Auction House scan now (the AH must be open; once per 15 minutes) |
| `/goon import` | Pull price history from Auctionator now |
| `/goon import off` / `on` | Stop or restart the automatic Auctionator import at login |
| `/goon sync` | Guild sync status: who in your guild runs Goonberg and the last guild scan |
| `/goon sync on` / `off` | Turn guild sync on or off |
| `/goon sync history` | Ask your guild for price history again |
| `/goon sync catchup` | Ask your guild for everything scanned since your last scan |

### Watchlist and alerts
| Command | What it does |
|---|---|
| `/goon watch <item>` | Add an item to your watchlist |
| `/goon unwatch <item>` | Remove it |
| `/goon alert <item> below <price>` | Alert when the lowest price drops below a price, e.g. `/goon alert Black Lotus below 9g50s` |
| `/goon alert <item> above <price>` | Alert when it rises above a price |
| `/goon alert <item> clear` | Remove an item's alerts |

Prices can be written `3g50s`, `3g 50s 20c`, `75s`, `20c` or just `3.5` (gold).

### Deals
| Command | What it does |
|---|---|
| `/goon deals` | Open the deals tab |
| `/goon deals alert 10` | Pop up when new deals add up to 10g or more (any amount in gold) |
| `/goon deals alert off` / `on` | Turn deal pop-ups off or back on |

### Rare finds
| Command | What it does |
|---|---|
| `/goon rare` | Show rare finds (and the current rules) |
| `/goon rare 30` | How far under the usual price a rare find must be (percent; default 20) |
| `/goon rare min 10` | Minimum usual price in gold (default 5) |
| `/goon rare days 4` | Minimum separate days seen (default 3) |
| `/goon rare off` / `on` | Turn rare find pop-ups off or on |

### Sharing
| Command | What it does |
|---|---|
| `/goon post <item>` | Post an item's price, weekly change and wall to guild chat |
| `/goon post <item> party` | Same, to `party`, `raid` or `say` |

### Disenchanting
| Command | What it does |
|---|---|
| `/goon de <item>` | What an item disenchants into, the chance of each and what it's worth |
| `/goon de watch` | Add every disenchant material to your watchlist so values stay priced |

### Settings
| Command | What it does |
|---|---|
| `/goon autoscan on` / `off` | Scan automatically when the AH opens and every 15 minutes while it's open |
| `/goon dock on` / `off` | Open the terminal beside the AH when you visit it |
| `/goon sound on` / `off` | Sound when an alert fires |
| `/goon tooltip on` / `off` | Goonberg lines in item tooltips |
| `/goon minimap on` / `off` / `reset` | Show, hide or re-center the minimap button |
| `/goon scale 0.9` | Shrink or grow the whole window (0.5 to 1.5). You can also drag its bottom-right corner |
| `/goon scale reset` | Put the window's size, scale and position back to default |
| `/goon help` | List the commands in game |

---

## Good to know

- **Charts start empty.** Each scan adds a point, so charts fill in over your first days. Guild sync and the Auctionator import fill them much faster.
- **Changes need real history.** A "24h %" is only shown when there's a price from 24 to 48 hours earlier (the same for every timeframe). With shorter history you see "-" rather than a number measured over the wrong period.
- **Est. sold per day** only counts time actually covered by scans (yours or your guild's) no more than 12 hours apart, so gaps don't drag it down.
- **Alerts only fire on live scans** (yours or a guildmate's), never on catch-up or imported data, which can be out of date.
- **Auctionator is optional.** Goonberg does its own scanning; Auctionator only adds history you already have.
- Data is saved per realm and faction, and the P&L per character.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/gusnino123/goonberg/issues). If something errors in game, type `/console scriptErrors 1` and include the error text.

## Shared price history (for maintainers)

New installs can start with price history that ships with the addon in `Seed/Data.lua`.
To build it, log out of WoW and run:

```
python tools/build_seed.py "C:/Program Files (x86)/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/GoonbergTerminal.lua"
```

Pass several files to combine guildmates' data. Only daily prices and quantities are written;
character names, P&L, alerts and settings are never copied. Commit `Seed/Data.lua`, never the
SavedVariables file itself.

## Daily prices from Blizzard

Blizzard publishes every WoW Forever auction house listing through its Game Data API
(undocumented for Forever so far). The **Blizzard prices** workflow reads it once a day and
keeps 60 days of daily prices for each market: region, ruleset (Normal, PvP, Roleplay,
Roleplay PvP) and faction. Each market is a small load-on-demand addon (`GoonbergData_US_PvP_Horde`
and so on), and Goonberg Terminal only loads your own market, and only when it's newer than
last time. Those days are added to your history without replacing anything you scanned.

- **Install:** unzip everything in the release zip into `Interface/AddOns` (the GoonbergData folders too).
  The **Latest prices (daily)** release always has today's data.
- **Your market** is worked out from the realm name. If Goonberg can't tell, set it once:
  `/goon market normal`, `pvp`, `rp` or `rppvp` (`/goon market` shows what it's using).
- **Setup (repo owner, once):** create a free API client at https://develop.battle.net/access/clients,
  then add its Client ID and Secret as repository secrets `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET`
  (Settings > Secrets and variables > Actions). EU and other regions: add a repository variable
  `GOONBERG_REGIONS`, e.g. `us,eu`. The data lives on the `data` branch, replaced daily.

## Loot tab

Dungeon drops you can sell on the AH (Bind on Equip and unbound items only): where they drop,
how often and what they're worth, plus what a full dungeon run is worth on average.

The loot tables ship with the addon (`Loot/Data.lua`): 29 dungeons with their bosses, rare spawns,
chests and trash drops, and their drop chances (trash chances are per mob), from Dungeon Codex and the
foreverchanges.pro data it carries (see Credits). Goonberg keeps refining the chances from real kills:
every boss corpse looted in a dungeon is one kill and its green-or-better drops are counted, and a
listed chance weighs as much as 20 kills, so your own data takes over as it builds up. With guild sync on, guildmates' kills are shared (one short message per boss
kill), and each kill counts once however many people looted it. Dungeons, bosses and any loot
listed in the in-game Adventure Guide appear before anyone has seen them drop.

- **Twink gear:** Bind on Equip gear for the 19/29/39/49 brackets that sells for at least 5g / 10g / 15g / 25g
  (or is among the priciest drops for its bracket).
- **Rare drops:** 5% or less over 20+ kills and worth 5g+, or any epic with an AH price.

## Credits and license

Goonberg Terminal is free software under the **GNU General Public License v2** (see `LICENSE`).

Dungeon loot tables (`Loot/Data.lua`, built by `tools/build_loot.py`) come from
[Dungeon Codex](https://github.com/dldvlpr-addons-wow/dungeonCodex) (GPL-2.0), whose boss loot
lists come from [AtlasLootClassic](https://github.com/Hoizame/AtlasLootClassic) (GPL-2.0) and whose
WoW Forever drop chances and new items come from [foreverchanges.pro](https://foreverchanges.pro).
Thank you to all of them. To refresh the tables:

```
git clone --depth 1 https://github.com/dldvlpr-addons-wow/dungeonCodex /tmp/dungeonCodex
python tools/build_loot.py /tmp/dungeonCodex
```
