---@meta
-- For the Lua language server only: the game never loads this file.
-- WoW globals the addon reads through _G (so the language server knows they exist).
-- For the whole WoW API in your editor, install the "WoW API" extension (ketho.wow-api).

AuctionHouseFrame = {} ---@type table  modern Auction House
AuctionFrame = {}      ---@type table  classic Auction House
BrowseName = {}        ---@type table  classic AH search box
C_AddOns = {}          ---@type table
Auctionator = {}       ---@type table  the Auctionator addon, when installed

LOOT_ITEM_SELF = ""                  ---@type string
LOOT_ITEM_SELF_MULTIPLE = ""         ---@type string
LOOT_ITEM_PUSHED_SELF = ""           ---@type string
LOOT_ITEM_PUSHED_SELF_MULTIPLE = ""  ---@type string
LOOT_ITEM_CREATED_SELF = ""          ---@type string
LOOT_ITEM_CREATED_SELF_MULTIPLE = "" ---@type string
SPELL_FAILED_CANT_BE_DISENCHANTED = "" ---@type string
