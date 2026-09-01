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
  otype = otype or ""
  if otype == "monster" or otype == "mob" or otype == "kill" or otype == "event" then
    return false
  end
  if otype == "item" or otype == "object" then return true end
  if not objText or objText == "" then return false end
  local low = string.lower(objText)
  if string.find(low, "slain", 1, true) or string.find(low, "killed", 1, true) then
    return false
  end
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

        if isUnit then
          -- Kill / talk: unit name in the objective line (ignore 0/10 item heuristic)
          local otl = Lower(ot)
          local core = ObjectiveCoreName(ot)
          if (otl ~= "" and string.find(otl, needle, 1, true))
             or (core ~= "" and string.find(core, needle, 1, true)) then
            hit = true
          end
        elseif LooksLikeItemObjective(ot, otype) then
          if ItemMatchesObjective(name, ot) then
            hit = true
          end
        else
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

function Tooltips:UnitOffersTurnIn(name)
  local out = {}
  if not name or name == "" then return out end
  local names = GreedQuestDB and GreedQuestDB.unitNames
  local log = GQ.Core and GQ.Core.questLog
  if not names or not log or not GQ.Database then return out end
  local needle = Lower(name)
  local _, q
  for _, q in pairs(log) do
    if q and q.questID then
      local qdata = GQ.Database:GetQuest(q.questID)
      local endU = qdata and qdata["end"] and qdata["end"]["U"]
      if endU then
        local matched = false
        local __, uid
        for __, uid in pairs(endU) do
          local un = names[uid]
          if un and Lower(un) == needle then
            matched = true
            break
          end
        end
        if matched then
          table.insert(out, q)
        end
      end
    end
  end
  return out
end

function Tooltips:UnitOffersAvailable(name)
  local out = {}
  if not name or name == "" then return out end
  if not GQ.Core or not GQ.Core.GetAvailableQuests then return out end
  local names = GreedQuestDB and GreedQuestDB.unitNames
  if not names then return out end
  local needle = Lower(name)
  local available = GQ.Core:GetAvailableQuests() or {}
  local ai
  for ai = 1, getn(available) do
    local aq = available[ai]
    local qdata = aq.qdata
    if (not qdata) and aq.questID and GQ.Database then
      qdata = GQ.Database:GetQuest(aq.questID)
    end
    local startU = qdata and qdata["start"] and qdata["start"]["U"]
    if startU then
      local _, uid
      for _, uid in pairs(startU) do
        local un = names[uid]
        if un and Lower(un) == needle then
          table.insert(out, aq)
          break
        end
      end
    end
  end
  return out
end

local function FormatGiverQuestLabel(q)
  local title = q.title or ("Quest " .. tostring(q.questID or "?"))
  local lvl = q.level
  local label = title
  if lvl and GQ.Core and GQ.Core.FormatQuestLevel then
    label = string.format("[%s] %s", GQ.Core:FormatQuestLevel(lvl, q.questID, title, q.tag), title)
  elseif lvl then
    label = string.format("[%s] %s", tostring(lvl), title)
  end
  if q.complete then
    label = label .. " (completed)"
  end
  return label, title
end

function Tooltips:AppendAvailableGiver(name)
  local avail = self:UnitOffersAvailable(name)
  local turn = self:UnitOffersTurnIn(name)
  if getn(avail) == 0 and getn(turn) == 0 then return false end
  local i
  if getn(turn) > 0 then
    GameTooltip:AddLine(" ")
    if getn(turn) == 1 then
      GameTooltip:AddLine("Quest turn in", 1.0, 0.82, 0.2)
    else
      GameTooltip:AddLine(string.format("%d quest turn ins", getn(turn)), 1.0, 0.82, 0.2)
    end
    for i = 1, getn(turn) do
      local q = turn[i]
      local label = FormatGiverQuestLabel(q)
      if q.complete then
        GameTooltip:AddLine(label, 0.35, 1.0, 0.35)
      else
        GameTooltip:AddLine(label, 1.0, 0.85, 0.2)
      end
    end
  end
  if getn(avail) > 0 then
    GameTooltip:AddLine(" ")
    if getn(avail) == 1 then
      GameTooltip:AddLine("Available quest", 0.3, 1.0, 0.3)
    else
      GameTooltip:AddLine(string.format("%d available quests", getn(avail)), 0.5, 0.85, 1)
    end
    for i = 1, getn(avail) do
      local aq = avail[i]
      local title = aq.title or ("Quest " .. tostring(aq.questID or "?"))
      local lvl = aq.level
      local label = title
      if lvl and GQ.Core and GQ.Core.FormatQuestLevel then
        label = string.format("[%s] %s", GQ.Core:FormatQuestLevel(lvl, aq.questID, title, aq.tag), title)
      elseif lvl then
        label = string.format("[%s] %s", tostring(lvl), title)
      end
      local tr, tg, tb = 1, 0.85, 0.2
      if GQ.Map and GQ.Map.GetAvailableTint then
        local r, g, b = GQ.Map:GetAvailableTint(aq.questID, title)
        if r then tr, tg, tb = r, g, b end
      end
      GameTooltip:AddLine(label, tr, tg, tb)
    end
  end
  return true
end

function Tooltips:AppendShiftObjectives(name)
  if GameTooltip.gqGQShiftObjs then return end
  local list = self:UnitOffersAvailable(name)
  local turn = self:UnitOffersTurnIn(name)
  if getn(list) == 0 and getn(turn) == 0 then return end
  local i
  local any = false
  local function addObj(qid)
    local objText = qid and GreedQuestDB and GreedQuestDB.questObjectives and GreedQuestDB.questObjectives[qid]
    if objText and objText ~= "" then
      if not any then
        GameTooltip:AddLine(" ")
        any = true
      end
      GameTooltip:AddLine(objText, 0.92, 0.92, 0.92)
    end
  end
  for i = 1, getn(turn) do
    addObj(turn[i].questID)
  end
  for i = 1, getn(list) do
    addObj(list[i].questID)
  end
  if any then
    GameTooltip.gqGQShiftObjs = 1
    GameTooltip:Show()
  end
end

function Tooltips:AppendQuestProgress(name, isUnit)
  if not name or name == "" then return end
  if not GameTooltip:IsVisible() then return end
  -- One pass per tooltip show so we do not fight vendor-price addons or duplicate lines.
  local stamp = tostring(isUnit and 1 or 0) .. ":" .. name
  if GameTooltip.gqGQStamp == stamp then return end

  local dens = GreedQuestConfig and GreedQuestConfig.tooltips and GreedQuestConfig.tooltips.density
  if dens == "off" then
    GameTooltip.gqGQStamp = stamp
    return
  end

  local related = self:FindRelatedQuests(name, isUnit and true or false)
  local addedAvail = false
  if isUnit then
    addedAvail = self:AppendAvailableGiver(name)
  end
  if getn(related) == 0 then
    if addedAvail then
      GameTooltip.gqGQStamp = stamp
      GameTooltip:Show()
    end
    return
  end
  GameTooltip.gqGQStamp = stamp

  self._lastName = name
  self._lastTime = GetTime and GetTime() or 0

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

function Tooltips:QueueUnitOrItem(isUnit)
  if GameTooltip.gqPinTooltip then return end
  if not self._defer then
    self._defer = CreateFrame("Frame")
  end
  self._pendUnit = isUnit and true or false
  self._pendT = 0
  self._defer:SetScript("OnUpdate", function()
    Tooltips._pendT = (Tooltips._pendT or 0) + (arg1 or 0.01)
    -- Wait a tick so other tooltip addons (vendor prices) finish writing.
    if Tooltips._pendT < 0.03 then return end
    if not GameTooltip:IsVisible() then
      this:SetScript("OnUpdate", nil)
      return
    end
    if GameTooltip.gqPinTooltip then
      this:SetScript("OnUpdate", nil)
      return
    end
    if Tooltips._pendUnit then
      if UnitExists("mouseover") then
        local name = UnitName("mouseover")
        if name then
          local shift = IsShiftKeyDown() and 1 or 0
          if Tooltips._lastShift ~= shift then
            Tooltips._lastShift = shift
            if shift == 0 and GameTooltip.gqGQShiftObjs then
              -- Rebuild the unit tooltip without objective text
              GameTooltip.gqGQStamp = nil
              GameTooltip.gqGQShiftObjs = nil
              if GameTooltip.SetUnit then
                GameTooltip:SetUnit("mouseover")
              end
            end
          end
          Tooltips:AppendQuestProgress(name, true)
          if shift == 1 then
            Tooltips:AppendShiftObjectives(name)
          end
        end
      else
        Tooltips._lastShift = nil
        this:SetScript("OnUpdate", nil)
      end
    else
      local name = GetTooltipItemName()
      if name and name ~= "" then
        Tooltips:AppendQuestProgress(name, false)
      end
      this:SetScript("OnUpdate", nil)
    end
  end)
end

function Tooltips:Init()
  local oldShow = GameTooltip:GetScript("OnShow")
  local oldHide = GameTooltip:GetScript("OnHide")
  GameTooltip:SetScript("OnHide", function()
    GameTooltip.gqPinTooltip = nil
    GameTooltip.gqGQStamp = nil
    GameTooltip.gqGQShiftObjs = nil
    Tooltips._lastShift = nil
    if oldHide then oldHide() end
  end)

  GameTooltip:SetScript("OnShow", function()
    if oldShow then oldShow() end
    if GameTooltip.gqPinTooltip then return end
    if UnitExists("mouseover") then
      Tooltips:QueueUnitOrItem(true)
    else
      Tooltips:QueueUnitOrItem(false)
    end
  end)

  local function PostHook(obj, method)
    if not obj or not obj[method] then return end
    local original = obj[method]
    obj[method] = function(self, a1, a2, a3, a4, a5, a6, a7, a8, a9)
      original(self, a1, a2, a3, a4, a5, a6, a7, a8, a9)
      Tooltips:QueueUnitOrItem(false)
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
