# Goonberg Terminal

**Stock charts for the Auction House.** Built for World of Warcraft: Forever.

Goonberg Terminal turns your AH scans into a trading screen: candlestick price charts, market depth, price alerts, and a market overview with the realm's biggest movers. Hover any item in your bags to see what it's worth.

## Install

1. Download the latest `GoonbergTerminal-x.y.z.zip` from this repository's **Releases** page (https://github.com/gusnino123/goonberg/releases).
2. Unzip it so the `GoonbergTerminal` folder sits in your WoW Forever `Interface/AddOns` folder.
3. Restart the game fully (not just `/reload`).

**Automatic updates:** in [WowUp](https://wowup.io), choose *Get Addons → Install from URL* and paste `https://github.com/gusnino123/goonberg`. WowUp then updates Goonberg whenever a new release is published.

## What you get

- **Candlestick charts** for any item over 1 day, 1 week, 1 month or all time, with est. sales bars underneath. Hover a candle for open, high, low and close.
- **Market depth**: how many are listed at each price, and where the "wall" is (the big stack everyone has to buy through).
- **Price alerts**: set "notify me below 3g50s" or "above 5g". When a scan crosses it you get a toast, a sound and a chat message.
- **Market overview** (`/goon` anywhere): the Goonberg Index, est. gold traded, top gainer and loser, and every item sortable by price, 24h %, 7d %, listings and est. sold. Filter by Herbs, Ore & Bars, Cloth and more.
- **Tooltips everywhere**: market price, stack value, lowest buyout, 7-day change, est. sold per day, vendor price and disenchant value, on every item you hover, with a green hint when vendoring or disenchanting beats the AH.
- **Crafting profit** (`/goon2`): for every recipe you know, the cost of reagents vs. what the item sells for after the AH cut, so you see at a glance what's worth crafting today. Its overview tracks how all your recipes perform over time: margins over 14 days, each profession, and which recipes are getting better or worse.
- **P&L card** (`/goon pnl`): your AH profit for today, 7 days, 30 days or all time, with a goblin sitting on his gold. Share it in guild chat or screenshot it.
- **Share a price**: `/goon post Arcanite Bar` puts a one-line summary in guild chat.

## How it works

1. Open the Auction House. Goonberg Terminal opens beside it and scans the whole AH automatically, then again every 15 minutes while it stays open.
2. Each scan saves a snapshot. Charts and trends build up as you scan, so the more you scan, the better they get.
3. Close the AH and everything keeps working from your saved data.

Blizzard allows one full AH scan every 15 minutes per account. The Scan button shows the countdown.

**Guild sync:** everyone in your guild running Goonberg shares their scans, so prices stay fresh while you're out in the world, a new install gets up to 21 days of history from guildmates on day one, and when you log in, guildmates fill in whatever they scanned while you were away.

**Using Auctionator?** Goonberg imports the price history Auctionator already has at every login, so your charts start weeks deep, and it reads Auctionator's Full Scans too.

**About "est. sold":** the game doesn't show sales. Goonberg Terminal counts units that disappear between two scans close together. That includes cancelled and expired auctions, so it's an estimate, and it gets better the more often you scan.

**The Goonberg Index** is a single number for your realm's market. It started at 100 and moves with the average price change of the 25 most-traded items, weighted by gold traded.

## Commands

| Command | What it does |
|---|---|
| `/goon` | Open or close the window |
| `/goon overview` | Market overview |
| `/goon chart <item>` | Chart for an item |
| `/goon2` or `/goon craft` | Crafting profit for your professions |
| `/goon pnl` | Your profit and loss card |
| `/goon scan` | Full scan (AH must be open) |
| `/goon watch <item>` / `/goon unwatch <item>` | Add or remove from your watchlist |
| `/goon alert <item> below 3g50s` | Price alert (also `above`, or `clear`) |
| `/goon post <item> [guild\|party\|raid\|say]` | Share a price in chat |
| `/goon de <item>` | What it disenchants into and is worth (`/goon de watch` follows all materials) |
| `/goon sync` | Guild sync status (`on`, `off`, `history`) |
| `/goon import` | Pull price history from Auctionator now (`/goon import off` stops the login import) |
| `/goon scale 0.9` / `/goon scale reset` | Shrink or grow the window (or drag its corner) |
| `/goon minimap on\|off\|reset` | Show, hide or re-center the minimap button |
| `/goon autoscan\|dock\|sound\|tooltip on\|off` | Settings |

You can shift-click items into any of these commands or into the watchlist box.
