--[[
  GreedQuest Tooltips
  Adds quest objective progress to unit and item tooltips.

  Item tooltips: match only the correct quest item name (no partial word hits).
  Unit tooltips: match kill objectives by name, AND show loot quests when the
  unit is a known dropper of a required quest item.
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Tooltips = GQ.Tooltips or {}
local Tooltips = GQ.Tooltips

local function StripColors(s)
  if not s then return "" end
  return string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
end

local function Lower(s)
  return string.lower(StripColors(s or ""))
end

-- Strip count suffixes/prefixes from objective text to get the core name.
local function ObjectiveCoreName(ot)
  if not ot or ot == "" then return "" end
  local s = ot
  s = string.gsub(s, "^%d+/%d+%s*", "")
  s = string.gsub(s, "%s*:%s*%d+/%d+%s*$", "")
  s = string.gsub(s, "%s+%d+/%d+%s*$", "")
  s = string.gsub(s, "^collect%s+", "")
  s = string.gsub(s, "^gather%s+", "")
  s = string.gsub(s, "^obtain%s+", "")
  s = string.gsub(s, "^loot%s+", "")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return Lower(s)
end

local function ItemMatchesObjective(itemName, objText)
  local needle = Lower(itemName)
  local core = ObjectiveCoreName(objText)
  if needle == "" or core == "" then return false end
  if core == needle then return true end

  local s, e = string.find(core, needle, 1, true)
  if not s then return false end
  local before = (s == 1) or (string.sub(core, s - 1, s - 1) == " ")
  local after = (e == string.len(core)) or (string.sub(core, e + 1, e + 1) == " ")
  if not (before and after) then return false end

  local nlen = string.len(needle)
  local clen = string.len(core)
  if nlen >= 12 then return true end
  if nlen * 10 >= clen * 7 then return true end
  return false
end

local function LooksLikeItemObjective(objText, otype)
  if otype == "item" or otype == "object" then return true end
  if not objText or objText == "" then return false end
  if string.find(objText, "%d+/%d+") then return true end
  return false
end

-- Cache: lower unit name -> true for units that drop a current quest item
Tooltips._dropperCache = nil
Tooltips._dropperCacheKey = nil

local function LogCacheKey()
  local log = GQ.Core and GQ.Core.questLog
  if not log then return "" end
  local parts = {}
  for _, q in pairs(log) do
    table.insert(parts, tostring(q.questID or q.title or ""))
    if q.objectives then
      for _, o in ipairs(q.objectives) do
        table.insert(parts, o.text or "")
        table.insert(parts, o.finished and "1" or "0")
      end
    end
  end
  return table.concat(parts, "|")
end

-- Build map of lower(unitName) -> list of { quest=q, objectives={obj,...} }
function Tooltips:GetItemDropperMap()
  local key = LogCacheKey()
  if self._dropperCache and self._dropperCacheKey == key then
    return self._dropperCache
  end

  local map = {}
  local log = GQ.Core and GQ.Core.questLog
  local DB = GQ.Database
  local names = GreedQuestDB and GreedQuestDB.unitNames
  if not log or not DB or not names then
    self._dropperCache = map
    self._dropperCacheKey = key
    return map
  end

  for _, q in pairs(log) do
    if q.questID and q.objectives then
      local qdata = DB:GetQuest(q.questID)
      local itemIds = qdata and qdata["obj"] and qdata["obj"]["I"]
      if itemIds then
        -- Collect item-type objective lines for this quest
        local itemObjs = {}
        for _, obj in ipairs(q.objectives) do
          if LooksLikeItemObjective(obj.text, Lower(obj.type or "")) then
            table.insert(itemObjs, obj)
          end
        end
        if getn(itemObjs) > 0 then
          for _, itemID in pairs(itemIds) do
            local item = DB:GetItem(itemID)
            if item and item.U then
              for uid, chance in pairs(item.U) do
                local uname = names[uid]
                if uname and uname ~= "" then
                  local ln = Lower(uname)
                  if not map[ln] then map[ln] = {} end
                  -- avoid duplicate quest entries
                  local found = false
                  for _, entry in ipairs(map[ln]) do
                    if entry.quest == q then found = true break end
                  end
                  if not found then
                    table.insert(map[ln], { quest = q, objectives = itemObjs, dropChance = chance })
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  self._dropperCache = map
  self._dropperCacheKey = key
  return map
end

function Tooltips:FindRelatedQuests(name, isUnit)
  local results = {}
  if not name or name == "" then return results end
  local needle = Lower(name)
  if needle == "" then return results end

  local log = GQ.Core and GQ.Core.questLog
  if not log then return results end

  local seenQuest = {}

  for _, q in pairs(log) do
    if q.objectives then
      local matched = {}
      for _, obj in ipairs(q.objectives) do
        local ot = obj.text or ""
        local otype = Lower(obj.type or "")
        local hit = false

        if LooksLikeItemObjective(ot, otype) then
          -- Item tooltip path: exact-ish item name match only
          if not isUnit and ItemMatchesObjective(name, ot) then
            hit = true
          end
        else
          -- Kill / event: unit name appears in objective text
          local otl = Lower(ot)
          if otl ~= "" and string.find(otl, needle, 1, true) then
            hit = true
          end
        end

        if hit then
          table.insert(matched, obj)
        end
      end
      if getn(matched) > 0 then
        seenQuest[q] = true
        table.insert(results, { quest = q, objectives = matched })
      end
    end
  end

  -- Unit mouseover: also show loot quests whose required item is dropped by this unit
  if isUnit then
    local droppers = self:GetItemDropperMap()
    local list = droppers[needle]
    if list then
      for _, entry in ipairs(list) do
        if not seenQuest[entry.quest] then
          seenQuest[entry.quest] = true
          table.insert(results, entry)
        elseif entry.dropChance then
          local _, r
          for _, r in ipairs(results) do
            if r.quest == entry.quest then
              r.dropChance = entry.dropChance
              break
            end
          end
        end
      end
    end
  end

  return results
end

Tooltips._lastName = nil
Tooltips._lastTime = 0

function Tooltips:AppendQuestProgress(name, isUnit)
  if not name or name == "" then return end
  local dens = GreedQuestConfig and GreedQuestConfig.tooltips and GreedQuestConfig.tooltips.density
  if dens == "off" then return end

  local now = GetTime and GetTime() or 0
  if self._lastName == name and (now - self._lastTime) < 0.15 then
    return
  end

  local related = self:FindRelatedQuests(name, isUnit and true or false)
  if getn(related) == 0 then return end

  self._lastName = name
  self._lastTime = now

  for _, entry in ipairs(related) do
    local q = entry.quest
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(q.title or "Quest", 1, 0.85, 0.2)

    for _, obj in ipairs(entry.objectives) do
      if obj.finished then
        GameTooltip:AddLine("  |cff55ff55" .. (obj.text or "") .. "|r")
      else
        GameTooltip:AddLine("  |cffffffff" .. (obj.text or "") .. "|r")
      end
    end
    if isUnit and entry.dropChance and entry.dropChance > 0 then
      local c = entry.dropChance
      local txt
      if c >= 10 then
        txt = string.format("%.0f%%", c)
      elseif c >= 1 then
        txt = string.format("%.1f%%", c)
      else
        txt = string.format("%.2f%%", c)
      end
      GameTooltip:AddLine("  Drop chance  " .. txt, 0.55, 0.85, 1)
    end

    local showParty = not (GreedQuestConfig and GreedQuestConfig.tooltips and GreedQuestConfig.tooltips.showParty == false)
    if showParty and GQ.Share and dens ~= "compact" then
      local party = GQ.Share:GetPartyProgress(q.questID, q.title)
      if party and getn(party) > 0 then
        GameTooltip:AddLine("Party", 0.5, 0.8, 1)
        for _, p in ipairs(party) do
          if p.complete then
            GameTooltip:AddLine("  |cff55ff55" .. p.player .. ": Complete|r")
          else
            GameTooltip:AddLine("  |cffffd100" .. p.player .. "|r")
          end
        end
      end
    end
  end

  GameTooltip:Show()
end

local function GetTooltipItemName()
  if GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText then
    return GameTooltipTextLeft1:GetText()
  end
  return nil
end

function Tooltips:Init()
  local oldShow = GameTooltip:GetScript("OnShow")
  local oldHide = GameTooltip:GetScript("OnHide")
  GameTooltip:SetScript("OnHide", function()
    GameTooltip.gqPinTooltip = nil
    if oldHide then oldHide() end
  end)

  GameTooltip:SetScript("OnShow", function()
    if oldShow then oldShow() end
    if GameTooltip.gqPinTooltip then return end

    if UnitExists("mouseover") then
      local name = UnitName("mouseover")
      if name then
        Tooltips:AppendQuestProgress(name, true)
      end
      return
    end

    local name = GetTooltipItemName()
    if name and name ~= "" then
      if not UnitExists("mouseover") then
        Tooltips:AppendQuestProgress(name, false)
      end
    end
  end)

  local function PostHook(obj, method)
    if not obj or not obj[method] then return end
    local original = obj[method]
    obj[method] = function(self, a1, a2, a3, a4, a5, a6, a7, a8, a9)
      original(self, a1, a2, a3, a4, a5, a6, a7, a8, a9)
      local name = GetTooltipItemName()
      if name then
        Tooltips:AppendQuestProgress(name, false)
      end
    end
  end

  PostHook(GameTooltip, "SetBagItem")
  PostHook(GameTooltip, "SetInventoryItem")
  PostHook(GameTooltip, "SetLootItem")
  PostHook(GameTooltip, "SetQuestItem")
  PostHook(GameTooltip, "SetQuestLogItem")
  PostHook(GameTooltip, "SetTradePlayerItem")
  PostHook(GameTooltip, "SetTradeTargetItem")
  PostHook(GameTooltip, "SetMerchantItem")
  PostHook(GameTooltip, "SetCraftItem")
  PostHook(GameTooltip, "SetTradeSkillItem")
  if GameTooltip.SetHyperlink then
    PostHook(GameTooltip, "SetHyperlink")
  end

  if GameTooltip.SetUnit then
    local original = GameTooltip.SetUnit
    GameTooltip.SetUnit = function(self, unit, a2, a3, a4)
      original(self, unit, a2, a3, a4)
      local name = unit and UnitName(unit) or UnitName("mouseover")
      if name then
        Tooltips:AppendQuestProgress(name, true)
      end
    end
  end

  GQ:Debug("Tooltips module ready")
end
