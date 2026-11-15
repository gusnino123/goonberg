# Goonberg Terminal

## 0.23.0

- **Tracks what you buy on the AH and then use yourself.** Drink a potion, equip a piece of gear, burn mats on an enchant or disenchant something you bought, and the P&L logs it as **Used** (with what those units cost you) instead of leaving it in "holding" forever. Uses don't count against your flipping profit.
  - Only units you actually bought count: if you had 5 bought potions and 3 farmed ones, drinking all 8 logs 5.
  - Putting things in the bank, mailing, trading, vendoring or posting on the AH isn't "using". Neither is crafting (that's already a craft), holding an item on the cursor, or taking gear off and back on.
  - New **Used** filter in Recent trades; the Flipping panel shows "Used yourself" next to what you're still holding.

## 0.22.2

- **Crafting page updates properly.** Clicking a profession on the crafting overview now also moves the highlight on the profession buttons, so the buttons and the recipe list always agree. Newly learned recipes and professions show up without reopening the window.
- **Crafting page is faster.** Price-history lookups are much quicker, and the crafting overview is reused until new prices, recipes, sales or vendor prices come in, so switching tabs and re-sorting no longer stutter (about 120 ms down to 1–2 ms with 500 recipes).

## 0.22.1

- **Loot tab: every dungeon starts closed.** You see one line per dungeon (level range, item count, best drop, gold per run); click it to open its drops, click again to close. "Expand all" opens them all.
  - While you search, or after picking a dungeon in the Dungeons view, the matching dungeons open by themselves so the results aren't hidden.
  - Closed dungeons show a right arrow, open ones a down arrow.

## 0.22.0

- **Loot tab organised by dungeon, lowest level first.** The Items view is now one section per dungeon (Ragefire Chasm and Hall of Thanes at 13-18 first, up to Upper Blackrock Spire at 59-60), each with a header showing its level range, how many sellable drops it has, its best drop and what a run is worth. Its drops are listed underneath; the column headers sort the drops inside each dungeon.
  - Click a dungeon's header to fold it away (or open it again); **Collapse all / Expand all** does every dungeon at once.
  - Inside a section, "Drops from" shows just the boss (or trash, or chest).
  - Filters and search still work: dungeons with nothing matching are left out.
- **Dungeons view** has a Level column and is ordered by level (click any header to sort differently).

## 0.21.0

- **Crafting counts in the P&L.** When you craft ("You create: ..." in chat), Goonberg looks up the recipe and uses up the materials you bought on the AH (oldest first), moving their cost onto what you made. Selling it is then a **Crafted** flip with its real profit, not a "Farmed" sale, and the bought materials no longer sit in "holding".
  - Materials you gathered yourself count at **market price** (default: profit shows whether crafting beat selling the mats) or as **free**: switch it with "Own mats in crafts" on the P&L. Vendor materials always count at the vendor price.
  - The Flipping panel shows "Crafted: N sales +X (ROI)". Recent trades show **Made** (a craft, with what its materials cost) and **Crafted** (selling it); both appear under the Flips filter.
  - Works for crafts made from this version on, for recipes the Crafting tab knows (open each profession window once).

## 0.20.0

- **P&L split into Flipping and Farming.**
  - **Total made on the AH** on top: flipping profit plus farming income.
  - **Flipping** (bought and sold on the AH): profit, ROI, sold for / cost / AH cut, flips sold and your best one, and what you're still holding.
  - **Farming** (found, looted or crafted, then sold): income after the AH cut, sold for / AH cut / number of sales, your top seller, and what your bags are worth at market.
  - **Deals tab tracking:** clicking a deal to find it on the AH remembers it; buying it within 3 days tags the purchase, and when you sell it the card shows "Deals tab: N flips +X (ROI)". So you can see whether the Deals tab's picks really pay.
  - **Recent trades** are labelled Flip, Flip+ (partly bought), Farmed, Bought or Deal, with filter chips (All / Flips / Farmed / Bought).
  - "Share in chat" sends the total with both halves.
  - The "Flips only / All sales" switch is gone: both are always shown.

## 0.19.0

- **Scroll bars** on every list (Overview, Deals, Loot, Crafting recipes, P&L trades, Chart watchlist): the thumb shows where you are and how much of the list you see. Drag it, or click above/below it to jump a page. It hides when everything fits.
- **Click any column header to sort**, click it again to reverse, everywhere:
  - **Deals:** item, type, buy at, sell for, profit each, margin, units, total profit, sold/day (replaces the "Sort by" buttons).
  - **Loot:** item, drops from, req, chance, AH value, per kill, kills; and in Dungeons: dungeon, most valuable drop, bosses, runs, items to sell, gold per clear (replaces the "Sort by" buttons).
  - **Crafting:** recipe list (item, cost, sells for, profit, margin, sold/day; replaces the "Sort by" buttons), By profession, and both profitability lists.
  - **P&L:** recent trades now have a header row (date, type, item, amount).
  - **Chart:** the watchlist (item, price, 7-day change).
  - The sorted column is gold with an arrow; hover a header to see what a click does.
- The status line at the top is shorter ("Scanned 5m ago") and can no longer run into the tabs.

## 0.18.3

- **Fixed: the Loot list jumped back to the top while you scrolled.** It refreshes as the game loads item info in the background (and on new kills and scans), and every refresh reset the scroll. It now goes back to the top only when you change the view, a filter, the sort or the search.
- Same fix for the P&L trade list, which jumped to the top when new AH mail was read.

## 0.18.2

- **Loot tab now has every dungeon drop in the WoW Forever data, trash included.** The bundled tables only had bosses; most rare Bind on Equip drops come from trash. Added:
  - **Trash tables for 26 dungeons** (520 items) with their drop chance per trash mob, shown as "Trash (any mob)".
  - **Chests and other objects** (Dire Maul Tribute, Knot Thimblejack's Cache, Stratholme plans and more: 47 items), shown as "(chest)" and counted in gold per run.
  - Checked against the full Forever data: no item is missing now. 492 blue or epic drops at 5% or less are included, 291 of them from trash.
- Drop chances under 1% show two decimals (0.03%), so very rare drops don't read as 0.0%.
- Gold per run counts bosses and chests only; trash chances are per mob.

## 0.18.1

- **Loot tab comes pre-filled.** WoW Forever loot tables now ship with the addon: 29 dungeons (including Hall of Thanes, Ruins of Lordaeron, Excavation Site and City of Dalaran), 252 bosses, 1,426 items and 1,118 drop chances, from Dungeon Codex (AtlasLootClassic boss loot, foreverchanges.pro Forever drop chances). No need to re-run dungeons.
  - Your and your guild's kills keep refining them: a listed chance weighs as much as 20 kills, so real data takes over as it builds up. The tooltip shows both.
  - Bosses are now recognised by their creature, so kills count even without an encounter event. Kills recorded in 0.18.0 are merged in by boss name.
  - Rare spawns are marked in "Drops from".
- **Goonberg Terminal is now GPL-2.0** (as required by the loot data). See Credits in the README.
- Fixed: a boss in the loot tables could be filed under its encounter instead of its creature.

## 0.18.0

- **New Loot tab** (`/goon loot`): dungeon drops you can sell on the AH, where they drop, how often, and what they're worth.
  - **Items:** each drop with the boss and dungeon it comes from, required level, drop chance, AH value, average gold per kill, and how many kills the chance is based on. Filters for **Twink gear** (Bind on Equip gear that sells for real money in its 19/29/39/49 bracket), **Rare drops** (5% or less and 5g+, or any epic), and **Recipes & mats**.
  - **Dungeons:** what a full run is worth on average from sellable boss drops, and its most valuable drop. Click a dungeon to see its items.
  - Only Bind on Equip and unbound items are listed; Bind on Pickup and quest items never are.
  - **Drop chances are learned from real kills**, since WoW Forever reworked every loot table and none are published: each boss you loot in a dungeon is a kill, and its green-or-better drops are counted. Guildmates' kills arrive through guild sync, and a kill looted by several of you still counts once. Trash drops are listed per dungeon as "seen N times".
  - Dungeons, bosses and any loot the **Adventure Guide** lists show up before anyone has seen them drop.

## 0.17.1

- **P&L counts flips only (new default).** A sale only counts when you bought that item on the AH first: each sale is matched to your earlier purchases of the same item, oldest first, and its profit is what you got after the AH cut minus what those units cost. Items you farmed, crafted or looted and sold aren't counted (they show greyed as "Farmed" in Recent trades), and purchases you haven't sold yet show as "Holding". A sale this week can use stock you bought earlier.
  - **All sales** (the old view) is one click away, under the period buttons.
  - The card reads **Sold / Cost / AH cut**, ROI is profit on what the flips cost, and "Share in chat" says "flips".

## 0.17.0

- **Easier to read, everywhere.**
  - Money shows its units in coin colours (gold, silver, copper), the way the game does, and drops units that add nothing ("5s" instead of "5s 00c"). Prices in tables are white, so gold is left for what matters.
  - No text smaller than 11 points; numbers are sized to sit level with words.
  - **Deals:** the toolbar is now two tidy rows (what to show; minimum margin and sort), so the Disenchant filter no longer hides under the search box. Columns are evenly spaced, renamed Profit each / Total profit, and the type reads as a word (Flip, Vendor, Rare, Disenchant). "Sells daily" explains itself on hover.
  - **Chart:** on a narrow window the chart style and indicator buttons wrap onto a second row instead of running off the edge.
  - **Overview:** the sort arrow sits beside its own column, cards have more room, shorter notes.
  - **Crafting:** the summary cards no longer overlap their notes; a profession's best recipe moved into the row's tooltip.
  - Status lines use a "·" separator throughout.

## 0.16.0

- **Daily prices from Blizzard.** Blizzard's auction house API now covers WoW Forever, and a daily GitHub workflow turns it into 60 days of prices for every market (region, ruleset and faction). New installs and markets nobody in your guild scans start with full charts, fair values and deal checks. Your own scans and guild data always come first: Blizzard's days only fill the gaps.
  - Each market ships as a small load-on-demand addon (GoonbergData_...), and only yours is loaded, during the loading screen and only when it's newer.
  - **/goon market** shows your market. If Goonberg can't tell your ruleset from the realm name, set it once with /goon market normal | pvp | rp | rppvp.
  - The **Latest prices (daily)** release on GitHub always has the newest data.

## 0.15.4

- **Cleaner item tooltip.** Three lines: **Vendor**, **Market** and **Disenchant** (gear only), for the whole stack, with the one that pays the most in green (after the 5% AH cut). How fresh the price is shows next to "Goonberg". Hold **Shift** for the details: price each, lowest listing, 7-day change, sales per day and what the item disenchants into.

## 0.15.3

- **Fixed: scans that never finished.**
  - An error while reading the AH (for example one auction the client couldn't read) left the scan stuck on "processing" until a /reload. Bad auctions are now skipped, and any other error stops the scan cleanly with a message, so /goon scan works again straight away.
  - If the AH first answered with an empty list, the scan "finished" with 0 auctions, marked everything as sold out and then ignored the real data. It now waits for the real list.
  - On a slow realm the scan was asked for again after 90 seconds, though Blizzard's 15-minute limit had already started. It now waits up to 3 minutes, never re-asks within 15 minutes, and still reads a scan that arrives late.
  - A scan with far fewer items than the last one no longer counts the missing items as sold.
  - One broken event handler no longer stops the rest (deals, alerts, guild sync) from running after a scan.
- **Shared price history (groundwork).** The addon can now ship daily prices for the last 60 days in `Seed\Data.lua`, added to your history at login (never over days you already have). `tools/build_seed.py` builds that file from SavedVariables, keeping prices only. The file is empty in this version.

## 0.15.2

- **Much less lag after logging in and when opening the window.**
  - The overview now builds in the background, a little each frame, instead of all at once (on a 6,500-item realm opening the window went from about 0.5 s frozen to about 6 ms). Small realms still build instantly.
  - Item stats are worked out in one pass over the last two weeks instead of seven passes over the whole history (about 40% faster; tooltips too).
  - The Auctionator import at login skips items it already imported and stops after about 6 ms each frame (worst frame went from about 640 ms to about 35 ms).
  - The deal finder also limits itself to about 6 ms per frame.
  - Sorting and searching the overview are about twice as fast (item names and sort values are worked out once).

## 0.15.1

- **Fixed: items not on the AH showed big % changes.** Items with 0 listings now show "-" instead of a change between two old listings, and can't top the gainers/losers.
- **Fixed: the Goonberg Index could slide on noise** (it fell ~50% in an hour on real data). It now only uses deep, liquid trade goods (no gear; 20+ listed in both scans; 20+ sold in a week), and each item's move counts at most -20%/+25% per scan. The index restarts at 100 with the new method.
- **Thin markets** (1-2 listings) are shown with a grey %, sort after real markets when sorting by change, and are kept off the Gainers/Losers filters and the top gainer/loser cards (which now need 5+ listed).

## 0.15.0

- **Interactive charts (TradingView-style).**
  - Crosshair with price and time tags, and a live legend (O/H/L/C, change, est. sold).
  - Mouse wheel zooms around the cursor; click-drag pans back in time; **Back to now** returns.
  - Candles, Line or Area; **MA 7/25** moving averages; optional **usual price** and **typical low** lines.
  - **Right-click** the chart to set a price alert there; **drag** an alert line to move it.
  - The header's change, high, low and est. sold follow the window you're looking at.
- **Fixed: chart timeframes overlapping the item name.** With 8 timeframe buttons on the title row, names got squashed and, on narrow windows, covered. The timeframes now sit in the chart's own top bar.
- **Fixed: when looking at a past window, scans after its end were drawn into its last candle.**
- **Lighter guild sync** (Blizzard's addon policy asks addons not to burden realm performance):
  - Sends nothing at all unless a guildmate runs Goonberg (guildmates greet each other at login).
  - Sends only items whose price or quantity changed since the last broadcast (unchanged ones at most every 2 hours), capped at 600 per scan. A repeat scan with unchanged prices now sends nothing.
  - History for newcomers and catch-up send fewer items and points.

## 0.14.0

- **Rare finds.** Seldom-listed items worth 5g+ that show up at least 20% under their usual price (60-day median) **and** under the cheapest they typically go for (their 10th-percentile day). The second check means items that normally swing a lot don't trigger it. Needs 3+ separate days of history; labelled **RARE** (solid, 6+ days) or **RARE?** (thin), in orange when the whole item is trending down. A new **Rare** filter on the Deals tab and its own pop-up for each new find. `/goon rare` to view and change the rules.
- **Market value now works like TradeSkillMaster's**: a 14-day average of daily prices, counting the latest 3 days triple (was a 7-day median). Flips are judged against it.
- Rarity uses how many days anything was scanned, from your scans, guild scans and the Auctionator import.

## 0.13.1

**Disenchanting accuracy**
- **Uses the WoW Forever disenchanting table, by required level.** Forever's table goes by the item's "Requires Level", not its item level; using item level put a lot of gear in the wrong tier. The bands, materials and quantities now match the Forever table (e.g. required level 21-25 gives 1-2 Soul Dust, 56-60 gives 2-5 Illusion Dust and 1-3 Greater Eternal Essence).
- **Rare gear** gives its band's shard, with the ~0.5% Nexus Crystal chance from level 51. **Epic gear** gives a shard up to level 50 and Nexus Crystals above.
- **Low-level gear** (level 10 and below) has no shard; dust and essence share the chances.
- **Shirts, tabards, bags and quivers** are no longer shown as disenchantable.
- **Materials are valued at what they'd really sell for**: the lower of their market price and the cheapest listing now, and only if seen in the last 7 days.
- **Essences** count at the better of selling as-is or combining/splitting 3:1 (lesser and greater).
- **"Better than AH"** hints compare like with like: what the item would sell for vs. what its materials would sell for (both lose the same 5% AH cut). The vendor hint also uses the realistic sale price.

## 0.13.0

**Accuracy pass**
- **% changes are never measured over the wrong period.** "24h %" now needs a price from 24-48 hours earlier (likewise for every timeframe). Before, a new item could show a "24h" change that was really 3 hours, or a "7d" change that was really 1 day. Changes are also measured back from the item's latest price, so an item last seen yesterday isn't compared across a gap.
- **Est. sold per day is much more accurate.** It now divides by the time actually watched (scans no more than 12 hours apart) instead of calendar days, so imported Auctionator days and nights without scans no longer drag it down. This feeds tooltips, crafting, deals and the Goonberg Index weights.
- **Deals: realistic relist price.** If other sellers are already listed under the fair value, a flip is priced at what you'd actually relist for (just under them), not the fair value.
- **Crafting: realistic sale price.** A crafted item is valued at the lower of its market price and the cheapest listing right now, since that's what you'd have to match. Prices older than 7 days are no longer used (the recipe shows "?" until the item is seen again).
- **Crafting overview:** "getting more / less profitable" compares like with like, and historical prices must be from within 2 days of the date.
- **Overview "listings on AH"** only counts items from a recent scan, not leftovers from old ones.

**Other**
- Removed the 7-day trend line column from the overview; the other columns have more room.

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
