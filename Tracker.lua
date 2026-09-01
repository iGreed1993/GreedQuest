--[[
  GreedQuest Tracker
  Zone headers, objective type markers, clear complete state
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Tracker = GQ.Tracker or {}
local Tracker = GQ.Tracker

local MAX_LINES = 80

-- Objective bullets use the same per-quest color as map pin markers.
local function HexByte(x)
  x = math.floor((tonumber(x) or 0) * 255 + 0.5)
  if x < 0 then x = 0 end
  if x > 255 then x = 255 end
  return string.format("%02x", x)
end

function Tracker:QuestMarkerBullet(q)
  local r, g, b = 0.67, 0.67, 0.67
  if GreedQuestConfig and GreedQuestConfig.map and GreedQuestConfig.map.colorCodedObjectives == false then
    return "|cffaaaaaa•|r "
  end
  if q and GQ.Map and GQ.Map.GetQuestMarkerColor then
    -- Ensure colors are assigned (same palette / order as map pins)
    if GQ.Map.RefreshQuestMarkers then
      GQ.Map:RefreshQuestMarkers()
    end
    local c = GQ.Map:GetQuestMarkerColor(q)
    if c then
      r, g, b = c[1] or r, c[2] or g, c[3] or b
    end
  end
  return "|cff" .. HexByte(r) .. HexByte(g) .. HexByte(b) .. "•|r "
end

-- Classic difficulty colors (relative to player level)
function Tracker:LevelColorCode(level)
  if not level or level <= 0 then return "|cffaaaaaa" end
  local pl = UnitLevel("player") or 1
  local diff = level - pl
  local greenRange = 5
  if GetQuestGreenRange then
    greenRange = GetQuestGreenRange() or 5
  end
  if diff >= 5 then
    return "|cffff2020"      -- red
  elseif diff >= 3 then
    return "|cffff8040"      -- orange
  elseif diff >= -2 then
    return "|cffffff00"      -- yellow
  elseif -diff <= greenRange then
    return "|cff40c040"      -- green
  else
    return "|cff808080"      -- grey
  end
end


function Tracker:GetTurnInLine(q)
  if not q then return "Ready to turn in" end
  local DB = GQ.Database
  local qdata = q.questID and DB and DB:GetQuest(q.questID)
  local npcName, zoneName
  if qdata and qdata["end"] and qdata["end"]["U"] then
    local uid = nil
    if GQ.Core and GQ.Core.PreferFactionUnitId then
      uid = GQ.Core:PreferFactionUnitId(qdata["end"]["U"])
    end
    if not uid then
      local _, id
      for _, id in pairs(qdata["end"]["U"]) do uid = id break end
    end
    if uid then
      if GreedQuestDB and GreedQuestDB.unitNames and GreedQuestDB.unitNames[uid] then
        npcName = GreedQuestDB.unitNames[uid]
      end
      local u = DB and DB:GetUnit(uid)
      if u and u.coords and u.coords[1] and u.coords[1][3] then
        local zid = u.coords[1][3]
        if GreedQuestDB and GreedQuestDB.zones then
          zoneName = GreedQuestDB.zones[zid]
        end
      end
    end
  end
  if npcName and zoneName then
    return "Turn in at " .. npcName .. " in " .. zoneName
  elseif npcName then
    return "Turn in at " .. npcName
  elseif zoneName then
    return "Turn in in " .. zoneName
  end
  return "Ready to turn in"
end

function Tracker:LineHeight()
  local cfg = GreedQuestConfig and GreedQuestConfig.tracker
  local fs = (cfg and cfg.fontSize) or 12
  return math.max(12, fs + 2)
end

function Tracker:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", "GreedQuestTrackerFrame", UIParent)
  local width = (GreedQuestConfig and GreedQuestConfig.tracker and GreedQuestConfig.tracker.width) or 240
  f:SetWidth(width)
  f:SetHeight(120)
  f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetFrameStrata("MEDIUM")

  f:SetScript("OnDragStart", function()
    if GreedQuestConfig and GreedQuestConfig.tracker and not GreedQuestConfig.tracker.locked then
      this:StartMoving()
    end
  end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", 8, -8)
  header:SetText("")
  header:Hide()
  f.header = header

  f.lines = {}
  for i = 1, MAX_LINES do
    local btn = CreateFrame("Button", "GQTrackerLine"..i, f)
    btn:SetHeight(14)
    btn:SetPoint("LEFT", f, "LEFT", 8, 0)
    btn:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:Hide()

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints(btn)
    text:SetJustifyH("LEFT")
    btn.text = text

    -- Drag anywhere on a line moves the whole tracker
    btn:SetScript("OnDragStart", function()
      if GreedQuestConfig and GreedQuestConfig.tracker and GreedQuestConfig.tracker.locked then
        return
      end
      local parent = this:GetParent()
      if parent and parent.StartMoving then
        parent:StartMoving()
      end
    end)
    btn:SetScript("OnDragStop", function()
      local parent = this:GetParent()
      if parent and parent.StopMovingOrSizing then
        parent:StopMovingOrSizing()
      end
    end)

    btn:SetScript("OnClick", function()
      Tracker:OnLineClick(this, arg1)
    end)
    btn:SetScript("OnEnter", function()
      this._hovering = true
      if this.lineType == "header" then
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(this.zoneName or "Zone", 1, 0.85, 0.2)
        GameTooltip:AddLine("Left-click: expand/collapse zone", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        return
      end
      if not this.quest then return end
      if IsShiftKeyDown() then
        Tracker:ShowQuestTextTooltip(this.quest, this)
        return
      end
      GameTooltip:SetOwner(this, "ANCHOR_LEFT")
      GameTooltip:ClearLines()
      GameTooltip:AddLine(this.quest.title, 1, 0.85, 0.2)
      if this.quest.complete then
        GameTooltip:AddLine(Tracker:GetTurnInLine(this.quest), 0.3, 1.0, 0.3)
      end
      if this.lineType == "title" then
        GameTooltip:AddLine("Left: collapse  |  Right: show on map  |  Shift-hover: full text", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Shift-click: stop tracking  |  Ctrl-click: cycle color", 0.7, 0.7, 0.7)
      end
      if GQ.Share and GQ.Share.AddProgressToTooltip then
        local dens = GreedQuestConfig and GreedQuestConfig.tooltips and GreedQuestConfig.tooltips.density
        if dens ~= "off" then
          GQ.Share:AddProgressToTooltip(this.quest.questID, this.quest.title)
        end
      end
      GameTooltip:Show()
    end)
    -- Shift-hover full text (1.12: MouseIsOver, not Frame:IsMouseOver)
    btn:SetScript("OnUpdate", function()
      if not this._hovering then return end
      if this.lineType == "header" then return end
      if not this.quest then return end
      if IsShiftKeyDown() then
        if not this._shiftTip then
          this._shiftTip = true
          Tracker:ShowQuestTextTooltip(this.quest, this)
        end
      elseif this._shiftTip then
        this._shiftTip = nil
        local enter = this:GetScript("OnEnter")
        if enter then enter() end
      end
    end)
    btn:SetScript("OnLeave", function()
      this._hovering = nil
      this._shiftTip = nil
      GameTooltip:Hide()
    end)

    f.lines[i] = btn
  end

  self.frame = f
  self:ApplyAppearance()
  self:UpdateVisibility()
  self:Refresh()
  GQ:Debug("Tracker ready")
end

function Tracker:ApplyAppearance()
  if not self.frame then return end
  local cfg = GreedQuestConfig and GreedQuestConfig.tracker or {}
  self.frame:SetWidth(cfg.width or 240)
  local alpha = cfg.alpha
  if alpha == nil then alpha = 0.7 end
  -- Opacity 0 or showBackground off => no backdrop plate
  if cfg.showBackground and alpha > 0 then
    self.frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 12, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    self.frame:SetBackdropColor(0, 0, 0, alpha)
    self.frame:SetBackdropBorderColor(0.4, 0.35, 0.2, math.min(0.9, alpha + 0.2))
  else
    self.frame:SetBackdrop(nil)
  end

  -- Actually change font size (not just line spacing)
  local fs = cfg.fontSize or 12
  if fs < 10 then fs = 10 end
  if fs > 18 then fs = 18 end
  local fontPath = "Fonts\\FRIZQT__.TTF"
  if self.frame.header and self.frame.header.SetFont then
    self.frame.header:SetFont(fontPath, fs + 1, "")
  end
  if self.frame.lines then
    for _, btn in ipairs(self.frame.lines) do
      if btn.text and btn.text.SetFont then
        btn.text:SetFont(fontPath, fs, "")
      end
    end
  end
end

function Tracker:UpdateVisibility()
  if not self.frame then return end
  if GreedQuestConfig and GreedQuestConfig.tracker and GreedQuestConfig.tracker.enabled then
    self.frame:Show()
  else
    self.frame:Hide()
  end
end

function Tracker:Show()
  if not self.frame then self:Init() end
  if GreedQuestConfig then GreedQuestConfig.tracker.enabled = true end
  self.frame:Show()
end

function Tracker:Hide()
  if self.frame then self.frame:Hide() end
  if GreedQuestConfig then GreedQuestConfig.tracker.enabled = false end
end

function Tracker:Toggle()
  if not self.frame then self:Init() end
  if self.frame:IsShown() then self:Hide() else self:Show() end
end

function Tracker:CollapseKey(q)
  return tostring(q.questID or q.title or q.index)
end

function Tracker:IsZoneCollapsed(zoneName)
  if not zoneName or zoneName == "" then return false end
  if not GreedQuestCharDB or not GreedQuestCharDB.collapsedZones then return false end
  return GreedQuestCharDB.collapsedZones[string.lower(zoneName)] and true or false
end

function Tracker:ToggleZoneCollapse(zoneName)
  if not zoneName or zoneName == "" then return end
  if not GreedQuestCharDB then GreedQuestCharDB = {} end
  if not GreedQuestCharDB.collapsedZones then GreedQuestCharDB.collapsedZones = {} end
  local key = string.lower(zoneName)
  if GreedQuestCharDB.collapsedZones[key] then
    GreedQuestCharDB.collapsedZones[key] = nil
  else
    GreedQuestCharDB.collapsedZones[key] = 1
  end
  self:Refresh()
end

function Tracker:IsCollapsed(q)
  local db = GreedQuestCharDB and GreedQuestCharDB.collapsed
  return db and db[self:CollapseKey(q)] and true or false
end

function Tracker:ToggleCollapse(q)
  if not GreedQuestCharDB then GreedQuestCharDB = {} end
  if not GreedQuestCharDB.collapsed then GreedQuestCharDB.collapsed = {} end
  local key = self:CollapseKey(q)
  GreedQuestCharDB.collapsed[key] = not GreedQuestCharDB.collapsed[key]
  self:Refresh()
end


function Tracker:OnLineClick(btn, mouseButton)
  if btn.lineType == "header" then
    if mouseButton == "LeftButton" and btn.zoneName then
      self:ToggleZoneCollapse(btn.zoneName)
    end
    return
  end
  local q = btn.quest
  if not q then return end

  if IsShiftKeyDown() then
    if GQ.Core and GQ.Core.ToggleTrackerForQuest then
      GQ.Core:ToggleTrackerForQuest(q)
    end
    return
  end
  if IsControlKeyDown() then
    if GQ.Map and GQ.Map.CycleQuestColor then
      GQ.Map:CycleQuestColor(q.questID, q.title)
    end
    return
  end
  if mouseButton == "RightButton" then
    if GQ.Map and GQ.Map.FocusQuest then
      GQ.Map:FocusQuest(q.questID, q.title, q.complete and "Turn In" or "Objective")
    end
    return
  end
  -- Left click: collapse / expand this quest's objectives
  if btn.lineType == "title" or btn.lineType == "objective" then
    self:ToggleCollapse(q)
  end
end

function Tracker:ShowQuestTextTooltip(q, owner)
  GameTooltip:SetOwner(owner or self.frame, "ANCHOR_LEFT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(q.title or "Quest", 1, 0.85, 0.2)
  if q.level and q.level > 0 then
    GameTooltip:AddLine("Level " .. q.level, 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine(" ")
  if q.description and q.description ~= "" then
    GameTooltip:AddLine(q.description, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
  end
  if q.objectiveText and q.objectiveText ~= "" then
    GameTooltip:AddLine("Objectives", 1, 0.85, 0.2)
    GameTooltip:AddLine(q.objectiveText, 0.9, 0.9, 0.9, 1)
  elseif q.objectives then
    for _, obj in ipairs(q.objectives) do
      local color = obj.finished and "|cff55ff55" or "|cffffffff"
      GameTooltip:AddLine(color .. (obj.text or "") .. "|r")
    end
  end
  GameTooltip:Show()
end

function Tracker:PassesPreset(q, preset)
  if preset == "incomplete" then return not q.complete end
  if preset == "complete" then return q.complete end
  if preset == "zone" then
    if GQ.Core and GQ.Core.QuestInCurrentZone then
      return GQ.Core:QuestInCurrentZone(q)
    end
  end
  return true
end

function Tracker:SortQuests(list, mode)
  -- Always attach zone name for headers
  for _, q in ipairs(list) do
    q._zoneName = self:GuessZoneName(q)
  end

  if mode == "incomplete" then
    table.sort(list, function(a, b)
      if a.complete ~= b.complete then return not a.complete end
      if (a._zoneName or "") ~= (b._zoneName or "") then
        return (a._zoneName or "") < (b._zoneName or "")
      end
      return (a.index or 0) < (b.index or 0)
    end)
  elseif mode == "level" then
    table.sort(list, function(a, b)
      if (a.level or 0) ~= (b.level or 0) then
        return (a.level or 0) < (b.level or 0)
      end
      return (a._zoneName or "") < (b._zoneName or "")
    end)
  elseif mode == "closest" or mode == "zone" then
    table.sort(list, function(a, b)
      local az = GQ.Core and GQ.Core:QuestInCurrentZone(a)
      local bz = GQ.Core and GQ.Core:QuestInCurrentZone(b)
      if az ~= bz then return az end
      if (a._zoneName or "") ~= (b._zoneName or "") then
        return (a._zoneName or "") < (b._zoneName or "")
      end
      return (a.index or 0) < (b.index or 0)
    end)
  else
    -- log order, but still group by zone for headers
    table.sort(list, function(a, b)
      if (a._zoneName or "") ~= (b._zoneName or "") then
        return (a._zoneName or "") < (b._zoneName or "")
      end
      return (a.index or 0) < (b.index or 0)
    end)
  end
end

-- Known dungeon / instance map IDs (fallback only when quest log header is missing)
local DUNGEON_ZONE_IDS = {
  [718] = true, [719] = true, [1337] = true, [1417] = true, [1477] = true,
  [1517] = true, [1581] = true, [1583] = true, [1584] = true, [1717] = true,
  [1977] = true, [2017] = true, [2057] = true, [2100] = true, [2159] = true,
  [2437] = true, [2557] = true, [2577] = true, [2717] = true, [2797] = true,
  [5132] = true, [5134] = true, [5135] = true, [5136] = true, [5137] = true,
  [5138] = true, [5139] = true, [5140] = true, [5142] = true, [5145] = true,
  [5150] = true, [5152] = true, [5153] = true, [5154] = true, [5155] = true,
  [5156] = true, [5157] = true, [5161] = true, [5162] = true, [5163] = true,
  [5164] = true, [5165] = true, [5166] = true, [721] = true, [796] = true,
  [722] = true, [491] = true, [209] = true, [717] = true,
}

local function IsDungeonZoneId(zid)
  zid = tonumber(zid)
  if not zid then return false end
  if DUNGEON_ZONE_IDS[zid] then return true end
  local name = GreedQuestDB and GreedQuestDB.zones and GreedQuestDB.zones[zid]
  if not name then return false end
  local lower = string.lower(name)
  if string.find(lower, "unused", 1, true) then return false end
  local keys = {
    "deadmines", "stockade", "shadowfang", "wailing cavern", "blackfathom",
    "razorfen", "gnomeregan", "scarlet monastery", "ulda", "zul'", "maraudon",
    "temple of atal", "dire maul", "scholomance", "stratholme", "blackrock depth",
    "blackrock spire", "molten core", "onyxia", "ragefire", "gilneas city",
  }
  local i
  for i = 1, table.getn(keys) do
    if string.find(lower, keys[i], 1, true) then return true end
  end
  return false
end

function Tracker:GuessZoneName(q)
  if not q then return "Other" end

  -- Prefer the quest log header Blizzard/Turtle already assigned
  -- (e.g. "Gilneas City", "Zul'Farrak", "Blacksmithing", "Deadmines")
  if q.logHeader and q.logHeader ~= "" then
    return q.logHeader
  end

  if not q.questID or not GQ.Database then return "Other" end
  local qdata = GQ.Database:GetQuest(q.questID)
  if not qdata then return "Other" end
  local zones = GreedQuestDB and GreedQuestDB.zones

  local function collectFromIds(ids, isUnit, dungeonOnly)
    if not ids then return nil end
    local _, id
    for _, id in pairs(ids) do
      local entry = isUnit and GQ.Database:GetUnit(id) or GQ.Database:GetObject(id)
      if isUnit and entry and GQ.Core and GQ.Core.UnitFactionOk and not GQ.Core:UnitFactionOk(entry) then
        entry = nil
      end
      if entry and entry.coords then
        local _, c
        for _, c in ipairs(entry.coords) do
          local zid = c[3]
          if zid and zones and zones[zid] then
            if (not dungeonOnly) or IsDungeonZoneId(zid) then
              return zones[zid]
            end
          end
        end
      end
    end
    return nil
  end

  local function zoneFromGroup(group, dungeonOnly)
    if not group then return nil end
    return collectFromIds(group["U"], true, dungeonOnly) or collectFromIds(group["O"], false, dungeonOnly)
  end

  -- Objectives first (dungeon interiors), never prefer turn-in city over dungeon work
  local dungeonZone =
    zoneFromGroup(qdata["obj"], true)
    or zoneFromGroup(qdata["start"], true)
  if dungeonZone then return dungeonZone end

  return zoneFromGroup(qdata["obj"], false)
    or zoneFromGroup(qdata["start"], false)
    or zoneFromGroup(qdata["end"], false)
    or "Other"
end

function Tracker:Refresh()
  if not self.frame then return end
  self:ApplyAppearance()

  local cfg = GreedQuestConfig and GreedQuestConfig.tracker or {}
  local gen = GreedQuestConfig and GreedQuestConfig.general or {}
  local showLevel = cfg.showLevel
  if showLevel == nil then showLevel = true end
  local showComplete = cfg.showComplete
  if showComplete == nil then showComplete = true end
  local maxQuests = cfg.maxQuests or 20
  local preset = cfg.filterPreset or "all"
  local sortMode = cfg.sortMode or "log"
  local zoneOnly = gen.currentZoneOnly

  local log = (GQ.Core and GQ.Core.questLog) or {}
  local list = {}
  for _, q in pairs(log) do
    if q and q.title then
      local skip = false
      -- Only show quests on the watch list (shift-click in quest log toggles)
      if GQ.Core and GQ.Core.IsTrackedInLog and not GQ.Core:IsTrackedInLog(q) then
        skip = true
      end
      if not showComplete and q.complete then skip = true end
      if not skip and zoneOnly and GQ.Core and GQ.Core.QuestInCurrentZone and not GQ.Core:QuestInCurrentZone(q) then
        skip = true
      end
      if not skip and not self:PassesPreset(q, preset) then skip = true end
      if not skip and GQ.Core and GQ.Core.ShouldHideQuest and GQ.Core:ShouldHideQuest(q) then
        skip = true
      end
      if not skip then
        table.insert(list, q)
      end
    end
  end

  self:SortQuests(list, sortMode)

  -- Keep chosen sort, but always park collapsed zones at the bottom.
  local i
  for i = 1, getn(list) do
    list[i]._ord = i
  end
  table.sort(list, function(a, b)
    local ac = self:IsZoneCollapsed(a._zoneName) and 1 or 0
    local bc = self:IsZoneCollapsed(b._zoneName) and 1 or 0
    if ac ~= bc then return ac < bc end
    return (a._ord or 0) < (b._ord or 0)
  end)

  local zoneCounts = {}
  for _, q in ipairs(list) do
    local zn = q._zoneName or "Other"
    zoneCounts[zn] = (zoneCounts[zn] or 0) + 1
  end

  -- First time a quest becomes complete, collapse its objectives.
  if not self._didAutoCollapse then self._didAutoCollapse = {} end
  if not GreedQuestCharDB.collapsed then GreedQuestCharDB.collapsed = {} end
  for _, q in ipairs(list) do
    local key = self:CollapseKey(q)
    if q.complete then
      if not self._didAutoCollapse[key] then
        GreedQuestCharDB.collapsed[key] = 1
        self._didAutoCollapse[key] = 1
      end
    else
      self._didAutoCollapse[key] = nil
    end
  end

  local lineH = self:LineHeight()
  local y = -8
  local logCount = 0
  local _, lq
  for _, lq in pairs(log) do
    if lq and lq.title then logCount = logCount + 1 end
  end
  if cfg.showQuestCount then
    if self.frame.header then
      self.frame.header:ClearAllPoints()
      self.frame.header:SetPoint("TOPLEFT", 8, y)
      self.frame.header:SetText("|cffffd100Current quests:|r |cffffffff" .. tostring(logCount) .. "/25|r")
      self.frame.header:Show()
    end
    y = y - lineH
  else
    if self.frame.header then
      self.frame.header:SetText("")
      self.frame.header:Hide()
    end
  end
  local lineIndex = 1
  local shown = 0
  local lastZone = nil

  local function SetLine(i, text, quest, lineType, zoneName)
    local btn = self.frame.lines[i]
    if not btn then return end
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, y)
    btn:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, y)
    btn:SetHeight(lineH)
    btn.text:SetText(text or "")
    btn.quest = quest
    btn.lineType = lineType
    btn.zoneName = zoneName
    btn:Show()
    y = y - lineH
  end

  for _, q in ipairs(list) do
    if shown >= maxQuests then break end

    -- Zone headers (—— Zone ——) whenever quests span zones
    local zname = q._zoneName or self:GuessZoneName(q)
    if zname and zname ~= lastZone then
      lastZone = zname
      if lineIndex <= MAX_LINES then
        local collapsed = self:IsZoneCollapsed(zname)
        local mark = collapsed and "|cffaaaaaa[+]|r " or "|cff808080[-]|r "
        local count = zoneCounts[zname] or 0
        local extra = ""
        if collapsed and count > 0 then
          extra = " |cffaaaaaa(" .. tostring(count) .. ")|r"
        end
        SetLine(lineIndex, mark .. "|cff808080—— " .. zname .. " ——" .. extra .. "|r", nil, "header", zname)
        lineIndex = lineIndex + 1
      end
    end

    -- Skip quest rows while this zone is minimized
    if self:IsZoneCollapsed(zname) then
      -- still count toward "shown" grouping but do not draw title/objectives
      -- do not increment shown so maxQuests applies to visible quests only
    else
    shown = shown + 1

    if lineIndex > MAX_LINES then break end

    -- Title line
    local titleStr = q.title or "Quest"
    local color = "|cffffd100"
    if q.complete then
      color = "|cff55ff55"
      titleStr = titleStr .. " (Complete)"
    end
    if showLevel and q.level and q.level > 0 then
      local lc = self:LevelColorCode(q.level)
      titleStr = lc .. "[" .. q.level .. "]|r " .. color .. titleStr .. "|r"
    else
      titleStr = color .. titleStr .. "|r"
    end
    if q.tag and q.tag ~= "" then
      titleStr = titleStr .. " |cffaaaaaa[" .. q.tag .. "]|r"
    end

    SetLine(lineIndex, titleStr, q, "title")
    lineIndex = lineIndex + 1

    -- Objectives (unless collapsed)
    if not self:IsCollapsed(q) and q.objectives and not q.complete then
      for _, obj in ipairs(q.objectives) do
        if lineIndex > MAX_LINES then break end
        local icon = self:QuestMarkerBullet(q)
        local otext = obj.text or ""
        if obj.finished then
          otext = "|cff55ff55" .. otext .. "|r"
        else
          otext = "|cffffffff" .. otext .. "|r"
        end
        SetLine(lineIndex, "  " .. icon .. otext, q, "objective")
        lineIndex = lineIndex + 1
      end
    elseif not self:IsCollapsed(q) and q.complete then
      if lineIndex <= MAX_LINES then
        SetLine(lineIndex, "  " .. self:QuestMarkerBullet(q) .. "|cff55ff55" .. Tracker:GetTurnInLine(q) .. "|r", q, "objective")
        lineIndex = lineIndex + 1
      end
    end
    end -- zone not collapsed
  end

  -- Hide unused
  for i = lineIndex, MAX_LINES do
    local btn = self.frame.lines[i]
    if btn then
      btn:Hide()
      btn.quest = nil
      btn.lineType = nil
    end
  end

  local totalH = 28 + (lineIndex - 1) * lineH
  if totalH < 40 then totalH = 40 end
  self.frame:SetHeight(totalH)

  if not cfg.showQuestCount then
    if self.frame.header then self.frame.header:SetText("") self.frame.header:Hide() end
  end
end


function Tracker:GetLevelColor(level)
  local pl = UnitLevel("player") or 1
  local diff = level - pl
  if diff >= 5 then return "|cffff2020"
  elseif diff >= 3 then return "|cffff8040"
  elseif diff >= -2 then return "|cffffff00"
  elseif diff >= -5 then return "|cff40c040"
  else return "|cff808080" end
end
