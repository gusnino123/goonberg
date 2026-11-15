-- Luacheck config for Goonberg Terminal. Run `luacheck .` from the repo root.
-- WoW runs addons on Lua 5.1.
std = "lua51"

-- Long lines are the house style; unused `self` and event arguments are normal in
-- WoW handlers, and so is a frame script's own `self` inside a method.
max_line_length = false
unused_args = false
ignore = { "432/self" }

-- Generated data files (rebuilt by the scripts in tools/)
exclude_files = { "Seed/Data.lua", "Loot/Data.lua", "Disenchant/NoDE.lua", ".luals/", "dist/", "Markets/" }

-- Globals the addon creates
globals = {
  "GoonbergTerminalDB",                       -- SavedVariables
  "SLASH_GOONBERG1", "SLASH_GOONBERG2", "SLASH_GOONBERGCRAFT1", "SlashCmdList",
  "GoonbergTerminal_OnAddonCompartmentClick",
}

-- WoW API the addon reads. Luacheck flags any global not listed here, which is how it
-- catches typos: when you start using a new WoW function, add it below.
read_globals = {
  -- Lua extensions in WoW
  "wipe", "tinsert", "tContains", "strsplit", "date", "time", "debugprofilestop",
  "geterrorhandler", "hooksecurefunc", "issecretvalue",

  -- Namespaces and enums
  "C_AddOns", "C_AuctionHouse", "C_ChatInfo", "C_Container", "C_EncounterJournal",
  "C_Item", "C_Timer", "C_TradeSkillUI", "Enum", "Item", "TooltipDataProcessor",
  "AuctionHouseFrameDisplayMode", "SOUNDKIT", "ITEM_QUALITY_COLORS", "STANDARD_TEXT_FONT",

  -- Frames
  "CreateFrame", "UIParent", "Minimap", "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
  "DEFAULT_CHAT_FRAME", "UISpecialFrames", "GameTooltip_Hide", "ChatEdit_InsertLink",
  "GetCursorPosition", "IsMouseButtonDown", "IsModifiedClick", "IsShiftKeyDown",
  "InCombatLockdown", "PlaySound", "Screenshot",

  -- Blizzard templates and their helpers (the native look)
  "C_XMLUtil", "DoesTemplateExist", "GameFontNormal", "GameFontHighlight",
  "PanelTemplates_TabResize", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab",
  "SetPortraitTextureFromCreatureDisplayID", "MenuUtil", "CreateFont", "C_Texture", "GetFileIDFromPath",
  "GetNumGuildMembers", "GetGuildRosterInfo", "ChatFrame_AddMessageEventFilter", "C_GuildInfo", "GuildRoster",

  -- Player, realm, chat
  "UnitName", "UnitExists", "UnitGUID", "UnitFactionGroup", "GetRealmName", "GetCurrentRegion",
  "GetRealZoneText", "GetInstanceInfo", "IsInGuild", "SendChatMessage", "GetTime",

  -- Items, bags, cursor, spells
  "GetItemInfo", "GetItemInfoInstant", "GetAddOnMetadata", "GetSpellInfo",
  "GetContainerItemID", "UseContainerItem", "PickupContainerItem", "CursorHasItem",
  "SpellIsTargeting", "GetInventoryItemID", "GetInventoryItemLink",

  -- Auction House (modern and classic APIs)
  "QueryAuctionItems", "CanSendAuctionQuery", "GetNumAuctionItems", "GetAuctionItemInfo",
  "BrowseName", "AuctionFrameBrowse_Search",

  -- Mail, merchants, loot, Adventure Guide
  "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxInvoiceInfo",
  "GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemLink",
  "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSourceInfo",
  "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex", "EJ_SelectInstance",
  "EJ_GetEncounterInfoByIndex", "EJ_SelectEncounter", "EJ_GetNumLoot", "EJ_GetLootInfoByIndex",
}
