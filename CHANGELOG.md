# Goonberg Terminal

## 0.12.2

- **Deals show profit per item.** New columns: **Buy at** (cheapest listing), **Sell for** (what you get per item: after the 5% AH cut when you relist, or the full vendor price), **Per item**, **Margin**, **Units** and **Total** (every unit under the deal price).
- **Deals are judged by real margin** (profit per item after the AH cut, divided by what you pay) instead of discount. Choose **5% · 10% · 20% · 50%**; the default 5% shows every deal worth doing and hides ones the AH cut would eat.
- Sort by **Total, Per item, Margin** or **Sold/day**. Hover a deal for the full math.
- Deal pop-ups count deals with at least a 10% margin and show the per-item profit.

## 0.12.1

- **Smoother deal alerts.** The deal search no longer freezes the game after a scan:
  - It runs in the background, a slice per frame, instead of all at once.
  - It waits 2 seconds after a scan so several guild scans arriving together cause one search, not several.
  - The alert and the Deals tab share one search per scan; changing filters only re-filters.
  - Fair values are cached for 3 hours, and vendor and disenchant values once per item.
  - On a 6,000-item test AH: the worst frame went from one ~45 ms stall to about 1.5 ms.

## 0.12.0

- **Deals tab** (`/goon deals`): listings in the latest scan priced well under what they're worth.
  - **Flip**: at least 20/30/50% under the item's fair value (its 7-day median price). Buy and relist.
  - **Vendor**: under what an NPC vendor pays. Buy and vendor it, guaranteed profit.
  - **Disenchant**: gear under its estimated disenchant value.
  - For each deal: lowest price, what it's worth, the discount, how many units are under the deal price, total profit after the 5% AH cut, and how fast it sells. Filter by type, discount and "Sells daily"; sort by profit, discount or sales.
  - Click a deal to search for it on the open Auction House; right-click for its chart.
- **Deal alerts**: after each live scan, a pop-up when new deals add up to 5g or more. Click it to open Deals. `/goon deals alert 10` sets the amount; `/goon deals alert off` turns it off.

## 0.11.1

- **15-minute timeframe** on the overview (15m) and charts (15M): what moved since the previous scan. Needs a scan from at least 15 minutes ago (yours or your guild's).

## 0.11.0

- **More timeframes.**
  - Overview: filter by **1h, 6h, 12h, 24h or 7d**. The change column, est. sold, gold traded, the Goonberg Index change, top gainer/loser and the Gainers/Losers filter all follow it. The 7D % column stays for comparison.
  - Charts: **1H, 6H, 12H**, 1D, 1W, 1M and All. The header change and est. sold follow the timeframe.
  - Short windows need a scan (yours or your guild's) at least that old, so a "-" means there isn't one yet.
- Chart header tidied: timeframes sit on the title row, the time info on its own line.

## 0.10.0

- **Disenchant value.** Uncommon, rare and epic armor and weapons show "Disenchant ~X" in their tooltip: the expected value of what they break into, priced at your AH prices. When disenchanting beats selling on the AH, the line turns green and says so. It shows even for gear that's never been on the AH. Hold Shift to see each possible material, its chance and its value.
- `/goon de <item>` prints the breakdown; `/goon de watch` adds every disenchant material to your watchlist so they stay priced.
- Estimates use the Classic disenchant tables (item level, quality, armor vs. weapon); Forever's custom gear may differ.

## 0.9.0

- **Cleaner look.**
  - Header tabs are plain text with a gold underline on the open tab, like a trading terminal.
  - Toggle groups (timeframes, views, sorting) sit in one dark track instead of loose buttons.
  - Tables have a header band and faint alternating row stripes, with a little more space per row.
  - A soft shadow lifts the window off the game world.
  - Crafting: the side panel is gone. Recipes expand in place, so the table uses the full width and names no longer get cut short.

## 0.8.1

- **Crafting: click a crafted item to expand it.** Right under it you see every reagent with how many you need, the price each, whether that price is from the AH or a vendor, and the cost of that line, then a total line with cost to craft, what it sells for, profit and margin. Click again to collapse. Click a reagent to open its chart; hover for its tooltip.

## 0.8.0

- **Catch-up at login.** If you were away for more than 20 minutes, Goonberg asks your guild for everything they scanned while you were gone. The guildmate with the freshest data whispers it (up to 24 points per item for the 400 busiest items), and your charts fill in with no gap. Est. sold is worked out across the filled-in time too. `/goon sync catchup` asks on demand.
- **Auto-rescan.** While the Auction House stays open, Goonberg scans again every 15 minutes (Blizzard's limit), so long AH sessions keep feeding you and your guild.
- Price alerts only fire on live scans (yours or a guildmate's), never on catch-up, history or Auctionator data, which can be out of date.

## 0.7.0

- **Guild sync.** When you scan, your prices go to guildmates running Goonberg; when they scan, theirs come to you, wherever you are. Charts, tooltips, the overview, crafting margins and price alerts all update from guild scans.
  - Busiest items go first (up to 2,000 per scan). Sending runs in the background at the game's message limits, so a full scan takes a few minutes to go out.
  - Only your own scans are sent; nothing is relayed, and the same scan is never counted twice.
  - The header shows "Last scan 3 min ago by Name (guild)".
- **History for newcomers.** A new install with little history asks the guild at login, and one guildmate whispers up to 21 days of daily prices for the 400 most-traded items.
- `/goon sync` shows who in your guild runs Goonberg; `/goon sync on|off`; `/goon sync history` asks again.

## 0.6.0

- **Imports Auctionator's price history.** If you use Auctionator, every day of prices it remembers is added to Goonberg's charts at login, so history starts weeks deep. Days Goonberg scanned itself are kept as they are and nothing is counted twice. `/goon import` runs it on demand; `/goon import off` stops the login import.
- **Reads Auctionator's Full Scans** (or any other addon's). Blizzard allows one full scan per 15 minutes per account, so when another addon takes it, Goonberg reads the same results instead of missing out.
- Tooltips and charts say "From Auctionator" when a price came from there.

## 0.5.1

- **Resizable window**: drag the bottom-right corner. Size and position are remembered. Never opens bigger than your screen.
- Every screen adapts: tables keep their columns aligned to the right edge, taller windows show more rows, the chart grows to fill the space.
- `/goon scale 0.9` (0.5 to 1.5) shrinks or grows everything; `/goon scale reset` puts size, scale and position back.
- Crafting: column headers no longer run into each other; profession buttons have their own row; costs with unpriced reagents show "?" instead of "0c?".

## 0.5.0

- **Crafting overview** (Crafting tab, Overview): how all your recipes are doing.
  - Cards: recipes known, profitable now, median margin (and your best recipe), daily profit pool, and what crafted items actually earned you on the AH in the last 7 days.
  - Median margin of your recipes for each of the last 14 days, rebuilt from price history.
  - By profession: recipes, profitable, median margin, profit pool and best recipe. Click one to see its recipes.
  - Recipes getting more and less profitable compared with 7 days ago. Click one to open it.

## 0.4.0

- **Crafting tab** (`/goon2` or `/goon craft`): every recipe you know, with cost to craft, what it sells for after the 5% AH cut, profit, margin and how fast it sells. Filter by profession, show profitable only, sort by profit, margin or sold/day.
- Click a recipe to see each reagent and where its price came from (AH or vendor). "Watch reagents" adds them and the crafted item to your watchlist.
- Recipes are learned when you open each profession window. Vendor prices are learned when you open any vendor, so vials and thread are priced at the NPC's price.

## 0.3.1

- **Minimap button**: the goblin sits in a round button under the minimap. Click to open the terminal, right-click for your P&L, drag to move it. Hover for the Goonberg Index and when you last scanned.
- `/goon minimap on|off|reset`.

## 0.3.0

- **New name: Goonberg Terminal** (was Forever Index). The command is now `/goon` (also `/goonberg`).
- The market number is now the **Goonberg Index**.
- The goblin now sits in the header as the logo.
- Saved data starts fresh under the new name; delete the old ForeverIndex folder from your AddOns.

## 0.2.0

- **P&L tab** (`/goon pnl`): a shareable profit card for Today, 7 days, 30 days or all time: net profit, ROI (when you flip), sold, bought, AH cut, best item and what your bags are worth at market. Features a goblin and his gold.
- Trades come from your AH mail invoices. Open the mailbox to update.
- "Share in chat" posts your P&L line to guild; "Screenshot" saves the screen.

## 0.1.0 (first test build)

- Full Auction House scans (one every 15 minutes, Blizzard's limit), automatic when the AH opens.
- Price history with candlestick charts (1D, 1W, 1M, All) and est. sales bars.
- Market depth with wall detection.
- Watchlist and price alerts (toast, sound, screen flash, chat).
- Market overview: the Goonberg Index, gold traded, top movers, sortable and filterable item table with 7-day trend lines.
- Item tooltips: market price, stack value, lowest buyout, 7-day change, est. sold per day, vendor price.
- `/goon post` to share a price in chat.
