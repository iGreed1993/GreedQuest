--[[
  GreedQuest - Main loader
  Hybrid questing addon for WoW 1.12 (Turtle / Octo)
]]

GreedQuest = GreedQuest or CreateFrame("Frame", "GreedQuest")
GreedQuest.version = "0.8.80-alpha"

-- Soft-migrate map pin sizes for existing SavedVariables
local function GQ_EnsurePinSizeDefaults()
  if not GreedQuestConfig then return end
  if not GreedQuestConfig.map then GreedQuestConfig.map = {} end
  local m = GreedQuestConfig.map
  if m.worldPinSize == nil then m.worldPinSize = 9 end
  if m.continentPinSize == nil then m.continentPinSize = 10 end
  if m.zonePinSize == nil then m.zonePinSize = 12 end
end

local GQ = GreedQuest

-- Account-wide defaults (GreedQuestConfig)
GQ.defaults = {
  minimap = {
    enabled = true,
    angle = 220,
    radius = 80,
    icon = "Interface\\Icons\\INV_Misc_Note_01",
  },
  tracker = {
    enabled = true,
    locked = false,
    scale = 1.0,
    alpha = 0.70,
    width = 240,
    maxQuests = 25,
    showLevel = true,
    showComplete = true,
    fadeInactive = true,
    showBackground = true,
    fontSize = 12,
    growUp = false,
    sortMode = "zone",      -- log | zone | incomplete | level | closest
    filterPreset = "all",   -- all | zone | incomplete | complete
  },
  map = {
    showObjectives = true,
    showGivers = true,
    showTurnins = true,
    showPaths = true,
    showAllOnContinent = false,
    cluster = true,
    clusterRadius = 3.0,
    worldPinSize = 9,
    continentPinSize = 10,
    zonePinSize = 12,
    pinShadowAlpha = 0.35,
    pinShadowPad = 1,
    miniPinSize = 10,
    pinAlpha = 1.0,
    pathColorR = 0.3,
    pathColorG = 0.7,
    pathColorB = 1.0,
    pathAlpha = 0.7,
    pathThickness = 2,
    iconStyle = "native",
    iconAvailable = "quest",
    iconTurnin = "quest",
    iconKill = "attack",
    iconLoot = "vendor",
    iconObject = "workbench",
    dotAvailR = 1.0, dotAvailG = 0.85, dotAvailB = 0.1,
    dotTurnR = 1.0,  dotTurnG = 0.75,  dotTurnB = 0.1,
    dotKillR = 0.95, dotKillG = 0.25,  dotKillB = 0.2,
    dotLootR = 0.3,  dotLootG = 0.9,   dotLootB = 0.35,
    dotObjR = 0.3,   dotObjG = 0.85,   dotObjB = 0.95,
  },
  tooltips = {
    density = "full",       -- full | compact | off
    showParty = true,
  },
  tracking = {
    flight = false,
    mailbox = false,
    innkeeper = false,
    repair = false,
  },
  general = {
    autoTrack = true,
    currentZoneOnly = false,
    debug = false,
    hidePvP = false,
    hideSeasonal = false,
    hideLowLevel = false,
    hideRepeatable = false,
    autoAccept = false,
    autoTurnIn = false,
  },
}

-- Per-character defaults (GreedQuestCharDB)
GQ.charDefaults = {
  collapsed = {},
  completed = {},         -- [questID or title] = timestamp
  hiddenQuests = {},      -- Alt-click hide from map + tracker
  trackerOff = {},        -- shift-click removed (autoTrack on)
  trackerOn = {},         -- shift-click added (autoTrack off)
}

local function deepcopy(src)
  if type(src) ~= "table" then return src end
  local copy = {}
  for k, v in pairs(src) do
    copy[k] = deepcopy(v)
  end
  return copy
end

local function mergeDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = deepcopy(v)
    elseif type(v) == "table" and type(target[k]) == "table" then
      mergeDefaults(target[k], v)
    end
  end
end

function GQ:LoadConfig()
  if not GreedQuestConfig then
    GreedQuestConfig = deepcopy(self.defaults)
  else
    mergeDefaults(GreedQuestConfig, self.defaults)
  end
  -- Strip removed keys from older SavedVariables
  if GreedQuestConfig.general then
    GreedQuestConfig.general.partyShare = nil
    GreedQuestConfig.general.hideItemDropQuests = nil
  end
  if GreedQuestConfig.tracker then
    GreedQuestConfig.tracker.focusMode = nil
  end
  self.db = GreedQuestConfig

  if not GreedQuestCharDB then
    GreedQuestCharDB = deepcopy(self.charDefaults)
  else
    mergeDefaults(GreedQuestCharDB, self.charDefaults)
  end
  -- Strip journey / focus leftovers
  GreedQuestCharDB.journey = nil
  GreedQuestCharDB.focusQuestKey = nil
  self.chardb = GreedQuestCharDB
end

function GQ:Debug(a1, a2, a3, a4, a5, a6, a7, a8)
  if not (GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.debug) then
    return
  end
  local parts = {}
  if a1 ~= nil then table.insert(parts, tostring(a1)) end
  if a2 ~= nil then table.insert(parts, tostring(a2)) end
  if a3 ~= nil then table.insert(parts, tostring(a3)) end
  if a4 ~= nil then table.insert(parts, tostring(a4)) end
  if a5 ~= nil then table.insert(parts, tostring(a5)) end
  if a6 ~= nil then table.insert(parts, tostring(a6)) end
  if a7 ~= nil then table.insert(parts, tostring(a7)) end
  if a8 ~= nil then table.insert(parts, tostring(a8)) end
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGQ|r: " .. table.concat(parts, " "))
end

GQ:RegisterEvent("ADDON_LOADED")
GQ:RegisterEvent("PLAYER_LOGIN")

GQ:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "GreedQuest" then
    GQ:LoadConfig()
    GQ_EnsurePinSizeDefaults()
    GQ:Debug("Config loaded (account + character)")
  elseif event == "PLAYER_LOGIN" then
    if GQ.Core and GQ.Core.MaybeWipeFreshCharacter then
      GQ.Core:MaybeWipeFreshCharacter()
    end
    if GQ.Database and GQ.Database.Load then
      local u, o, i, q = GQ.Database:Load()
      if (u or 0) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
          "|cff33ffccGreedQuest|r v%s | Units:%d Objects:%d Items:%d Quests:%d",
          GQ.version, u, o, i, q))
      else
        local n = (GQ.Database.questIdList and getn(GQ.Database.questIdList)) or 0
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
          "|cff33ffccGreedQuest|r v%s loaded | %d startable quests indexed",
          GQ.version, n))
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r v" .. GQ.version .. " loaded.")
    end

    if GQ.Map and GQ.Map.Init then GQ.Map:Init() end
    if GQ.Tracking and GQ.Tracking.Init then GQ.Tracking:Init() end
    if GQ.Minimap and GQ.Minimap.Init then GQ.Minimap:Init() end
    if GQ.Tracker and GQ.Tracker.Init then GQ.Tracker:Init() end
    if GQ.Core and GQ.Core.Init then GQ.Core:Init() end
    if GQ.Share and GQ.Share.Init then GQ.Share:Init() end
    if GQ.Tooltips and GQ.Tooltips.Init then GQ.Tooltips:Init() end
    if GQ.Query and GQ.Query.Init then GQ.Query:Init() end
    if GQ.Auto and GQ.Auto.Init then GQ.Auto:Init() end
  end
end)

SLASH_GREEDQUEST1 = "/gq"
SLASH_GREEDQUEST2 = "/greedquest"
SlashCmdList["GREEDQUEST"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "config" or msg == "settings" or msg == "" then
    if GQ.Config and GQ.Config.Toggle then GQ.Config:Toggle() end
  elseif msg == "tracker" then
    if GQ.Tracker and GQ.Tracker.Toggle then GQ.Tracker:Toggle() end
  elseif msg == "query" then
    if GQ.Query and GQ.Query.QueryServer then GQ.Query:QueryServer() end
  elseif msg == "zonebounds" then
    if not GreedQuestConfig.map then GreedQuestConfig.map = {} end
    GreedQuestConfig.map.debugZoneBounds = not GreedQuestConfig.map.debugZoneBounds
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r zone bounds debug: " .. (GreedQuestConfig.map.debugZoneBounds and "ON (cyan=Kalimdor yellow=EK)" or "OFF"))
    if GQ.Map and GQ.Map.UpdatePathLines then GQ.Map:UpdatePathLines() end
  elseif msg == "debug" then
    if GreedQuestConfig and GreedQuestConfig.general then
      GreedQuestConfig.general.debug = not GreedQuestConfig.general.debug
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGQ|r debug: " .. tostring(GreedQuestConfig.general.debug))
    end
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: /gq | /gq config | /gq tracker | /gq query | /gq debug")
  end
end
