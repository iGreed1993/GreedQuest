--[[
  GreedQuest Map
  World map + minimap pins.
  1.12 compatible.
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Map = GQ.Map or {}
local Map = GQ.Map

-- Performance: avoid full rebuilds on movement; coalesce pin draws
Map._clustersDirty = true
Map._miniNeedsFull = true
Map._pinUpdateQueued = false
Map._miniOnlyQueued = false

-- ============================================================
-- Constants / icons
-- ============================================================

Map.ICON = {
  -- Native GossipFrame icons (1.12-safe), sized small on pins
  available = "Interface\\GossipFrame\\AvailableQuestIcon",
  daily     = "Interface\\GossipFrame\\DailyQuestIcon",
  dailyActive = "Interface\\GossipFrame\\DailyActiveQuestIcon",
  complete  = "Interface\\GossipFrame\\ActiveQuestIcon",
  giver     = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin    = "Interface\\GossipFrame\\ActiveQuestIcon",
  kill      = "Interface\\Cursor\\Attack",
  loot      = "Interface\\GossipFrame\\VendorGossipIcon",
  talk      = "Interface\\GossipFrame\\GossipGossipIcon",
  object    = "Interface\\GossipFrame\\WorkbenchGossipIcon",
  item      = "Interface\\GossipFrame\\PetitionGossipIcon",
  event     = "Interface\\GossipFrame\\HealerGossipIcon",
  cluster   = "Interface\\GossipFrame\\AvailableQuestIcon",
  default   = "Interface\\GossipFrame\\AvailableQuestIcon",
}


-- Texture catalog for user-selectable native icons
Map.ICON_CHOICES = {
  availableWhite = "Interface\AddOns\GreedQuest\media\available",
  quest     = "Interface\\GossipFrame\\AvailableQuestIcon",
  questActive = "Interface\\GossipFrame\\ActiveQuestIcon",
  gossip    = "Interface\\GossipFrame\\GossipGossipIcon",
  attack    = "Interface\\Cursor\\Attack",
  vendor    = "Interface\\GossipFrame\\VendorGossipIcon",
  petition  = "Interface\\GossipFrame\\PetitionGossipIcon",
  workbench = "Interface\\GossipFrame\\WorkbenchGossipIcon",
  healer    = "Interface\\GossipFrame\\HealerGossipIcon",
  dot       = "Interface\\AddOns\\GreedQuest\\media\\dot",
}

function Map:ApplyIconStyle()
  local cfg = GreedQuestConfig and GreedQuestConfig.map or {}
  local style = cfg.iconStyle or "native"

  if style == "dots" then
    local dot = self.ICON_CHOICES.dot
    -- Keep ! / ? as quest icons; only objectives become colored dots.
    self.ICON.available = "Interface\AddOns\GreedQuest\media\available"
    self.ICON.giver     = self.ICON.available
    self.ICON.complete  = "Interface\AddOns\GreedQuest\media\complete"
    self.ICON.turnin    = self.ICON.complete
    self.ICON.kill      = dot
    self.ICON.loot      = dot
    self.ICON.talk      = dot
    self.ICON.object    = dot
    self.ICON.item      = dot
    self.ICON.event     = dot
    self.ICON.cluster   = dot
    self.ICON.default   = dot
  else
    local avail = cfg.iconAvailable or "quest"
    local turn  = cfg.iconTurnin or "quest"
    local kill  = cfg.iconKill or "attack"
    local loot  = cfg.iconLoot or "vendor"
    local obj   = cfg.iconObject or "workbench"
    self.ICON.available = self.ICON_CHOICES[avail] or self.ICON_CHOICES.quest
    self.ICON.giver     = self.ICON.available
    if turn == "quest" then
      self.ICON.turnin = self.ICON_CHOICES.questActive
      self.ICON.complete = self.ICON_CHOICES.questActive
    else
      self.ICON.turnin = self.ICON_CHOICES[turn] or self.ICON_CHOICES.questActive
      self.ICON.complete = self.ICON.turnin
    end
    self.ICON.kill   = self.ICON_CHOICES[kill] or self.ICON_CHOICES.attack
    self.ICON.loot   = self.ICON_CHOICES[loot] or self.ICON_CHOICES.vendor
    self.ICON.item   = self.ICON.loot
    self.ICON.object = self.ICON_CHOICES[obj] or self.ICON_CHOICES.workbench
    self.ICON.talk   = self.ICON_CHOICES.gossip
    self.ICON.event  = self.ICON_CHOICES.healer
    self.ICON.cluster = self.ICON.available
    self.ICON.default = self.ICON.available
  end
end

-- Prefer primary texture; if it fails to load, keep fallback (1.12-safe).
function Map:SetTextureWithFallback(texObj, primary, fallback)
  if not texObj then return end
  -- Neutral ring — never leave a leftover quest "!" from the pin pool
  local neutral = "Interface\\AddOns\\GreedQuest\\media\\ring"
  fallback = fallback or neutral
  if primary and primary ~= "" then
    texObj:SetTexture(neutral)
    texObj:SetTexture(primary)
  else
    texObj:SetTexture(fallback)
  end
end

-- Returns texture path and vertex color (r,g,b) for a pin type
-- PvP / daily-repeatable / seasonal tint for available quest pins

-- Apply vertex color; clear desaturate so it never traps pins in pure grey.
function Map:ApplyPinTextureTint(tex, r, g, b, typ, hasSpecialTint)
  if not tex then return end
  if tex.SetDesaturated then
    tex:SetDesaturated(false)
  end
  tex:SetVertexColor(r or 1, g or 1, b or 1)
end

-- Returns "pvp" | "seasonal" | "repeatable" | "lowlevel" | nil
function Map:GetAvailableKind(qid, title)
  if not GQ.Core then return nil end
  if GQ.Core.IsPvPQuest and GQ.Core:IsPvPQuest(nil, title, qid) then
    return "pvp"
  end
  if GQ.Core.IsSeasonalQuest and GQ.Core:IsSeasonalQuest(qid, title, nil) then
    return "seasonal"
  end
  if GQ.Core.IsRepeatableQuest and GQ.Core:IsRepeatableQuest({ questID = qid, title = title }) then
    return "repeatable"
  end
  if qid and GQ.Core.IsLowLevelQuest then
    local lvl = nil
    if GQ.Database and GQ.Database.GetQuest then
      local qd = GQ.Database:GetQuest(qid)
      if qd then lvl = qd["lvl"] or qd["min"] end
    end
    if GQ.Core:IsLowLevelQuest(lvl) then
      return "lowlevel"
    end
  end
  return nil
end

-- RGB for tooltips / dots (nil = default)
function Map:GetAvailableTint(qid, title)
  local kind = self:GetAvailableKind(qid, title)
  if kind == "pvp" then return 1.0, 0.25, 0.25 end
  if kind == "seasonal" then return 0.20, 0.95, 0.30 end
  if kind == "repeatable" then return 0.15, 0.35, 1.00 end
  if kind == "lowlevel" then return 0.55, 0.55, 0.55 end
  return nil
end

function Map:ResolvePinVisual(typ, grey, node)
  local cfg = GreedQuestConfig and GreedQuestConfig.map or {}
  local style = cfg.iconStyle or "native"
  local tex = self.ICON.default
  local r, g, b = 1, 1, 1

  if typ == "Available" or typ == "Quest Giver" then
    local kind = nil
    if node then
      kind = self:GetAvailableKind(node.questID, node.title or node.quest)
      if node.members and getn(node.members) > 1 then
        local rank = { pvp = 4, seasonal = 3, repeatable = 2, lowlevel = 1 }
        local best, bestKind = 0, kind
        for _, mem in ipairs(node.members) do
          local k = self:GetAvailableKind(mem.questID, mem.title or mem.quest)
          local rk = k and rank[k] or 0
          if rk > best then best, bestKind = rk, k end
        end
        kind = bestKind
      end
    end
    local availChoice = cfg.iconAvailable or "quest"
    -- Dots mode and the default "Quest !" choice use typed media icons.
    if style == "dots" or availChoice == "quest" then
      local media = "Interface\\AddOns\\GreedQuest\\media\\"
      if kind == "repeatable" then
        tex = media .. "repeatable"
      elseif kind == "pvp" then
        tex = media .. "pvpquest"
      elseif kind == "seasonal" then
        tex = media .. "eventquest"
      elseif kind == "lowlevel" then
        tex = media .. "available_gray"
      else
        tex = media .. "available"
      end
      r, g, b = 1, 1, 1
    elseif availChoice == "dot" then
      tex = (self.ICON_CHOICES and self.ICON_CHOICES.dot) or self.ICON.available
      if kind == "repeatable" then r, g, b = 0.15, 0.45, 1.00
      elseif kind == "pvp" then r, g, b = 1.0, 0.25, 0.25
      elseif kind == "seasonal" then r, g, b = 0.20, 0.95, 0.30
      elseif kind == "lowlevel" then r, g, b = 0.55, 0.55, 0.55
      else r, g, b = 1, 0.85, 0.1
      end
    else
      tex = self.ICON.available or self.ICON_CHOICES.gossip
      r, g, b = 1, 1, 1
    end
  elseif typ == "Turn In" then
    if node and node.talkTo and node.grey then
      return self.ICON.event or "Interface\GossipFrame\HealerGossipIcon", 1, 1, 1
    end
    local kind = node and self:GetAvailableKind(node.questID, node.title or node.quest)
    local turnChoice = cfg.iconTurnin or "quest"
    if style == "dots" or turnChoice == "quest" then
      local media = "Interface\\AddOns\\GreedQuest\\media\\"
      if kind == "repeatable" then
        tex = media .. "repeatable_complete"
      elseif kind == "pvp" then
        tex = media .. "pvpquest_complete"
      elseif kind == "seasonal" then
        tex = media .. "eventquest_complete"
      else
        tex = media .. "complete"
      end
      r, g, b = 1, 1, 1
    elseif turnChoice == "dot" then
      tex = (self.ICON_CHOICES and self.ICON_CHOICES.dot) or self.ICON.turnin
      if kind == "repeatable" then r, g, b = 0.15, 0.45, 1.00
      elseif kind == "pvp" then r, g, b = 1.0, 0.25, 0.25
      elseif kind == "seasonal" then r, g, b = 0.20, 0.95, 0.30
      else r, g, b = 1, 0.75, 0.1
      end
    else
      tex = self.ICON.turnin or self.ICON_CHOICES.questActive
      r, g, b = 1, 1, 1
    end
  elseif typ == "Kill" then
    tex = self.ICON.kill
    if style == "dots" or (cfg.iconKill == "dot") then
      r = cfg.dotKillR or 0.95; g = cfg.dotKillG or 0.25; b = cfg.dotKillB or 0.2
    end
  elseif typ == "Loot" then
    tex = self.ICON.loot or self.ICON.item
    if style == "dots" or (cfg.iconLoot == "dot") then
      r = cfg.dotLootR or 0.3; g = cfg.dotLootG or 0.9; b = cfg.dotLootB or 0.35
    end
  elseif typ == "Object" then
    tex = self.ICON.object
    if style == "dots" or (cfg.iconObject == "dot") then
      r = cfg.dotObjR or 0.3; g = cfg.dotObjG or 0.85; b = cfg.dotObjB or 0.95
    end
  elseif typ == "mailbox" or typ == "Mailbox" then
    tex = "Interface\\AddOns\\GreedQuest\\media\\mailbox"
  elseif typ == "flight" then
    tex = "Interface\\AddOns\\GreedQuest\\media\\flight"
  elseif typ == "innkeeper" then
    tex = "Interface\\AddOns\\GreedQuest\\media\\innkeeper"
  elseif typ == "repair" then
    tex = "Interface\\AddOns\\GreedQuest\\media\\repair"
  end

  if grey then
    r, g, b = r * 0.45, g * 0.45, b * 0.45
  end
  return tex, r, g, b
end

-- Per-quest accent colors for the "•" marker on pins.
Map.QUEST_MARKER_PALETTE = {
  { 1.00, 0.12, 0.12 }, -- red
  { 0.12, 0.32, 1.00 }, -- blue
  { 1.00, 0.90, 0.05 }, -- yellow
  { 0.78, 0.12, 1.00 }, -- violet
  { 1.00, 0.48, 0.00 }, -- orange
  { 0.95, 0.95, 0.95 }, -- white
  { 1.00, 0.10, 0.62 }, -- magenta
  { 0.50, 0.26, 0.08 }, -- brown
  { 0.12, 0.48, 0.14 }, -- forest (dark green, not cyan)
  { 0.35, 0.10, 0.55 }, -- deep purple
  { 0.90, 0.72, 0.12 }, -- gold
  { 0.70, 0.08, 0.22 }, -- wine
  { 0.40, 0.75, 1.00 }, -- sky
  { 1.00, 0.42, 0.42 }, -- coral
  { 0.20, 0.20, 0.55 }, -- navy
  { 0.62, 1.00, 0.18 }, -- lime
  { 0.55, 0.55, 0.55 }, -- gray
  { 0.85, 0.45, 0.10 }, -- amber
  { 0.45, 0.18, 0.90 }, -- orchid
  { 0.15, 0.35, 0.15 }, -- pine
}


local function MarkerColorDist(a, b)
  -- Weight R/B more than G so green vs cyan-ish colors stay far apart.
  local dr = (a[1] or 0) - (b[1] or 0)
  local dg = (a[2] or 0) - (b[2] or 0)
  local db = (a[3] or 0) - (b[3] or 0)
  return dr * dr * 1.4 + dg * dg * 0.35 + db * db * 1.5
end

-- Assign colors so quests that share a zone get the most different dots.
function Map:RefreshQuestMarkers()
  self._questMarkerColor = {}
  local log = GQ.Core and GQ.Core.questLog
  if not log then return end
  local list = {}
  for _, q in pairs(log) do
    if q and q.questID then
      table.insert(list, q)
    end
  end
  table.sort(list, function(a, b)
    local ia = tonumber(a.index) or 999
    local ib = tonumber(b.index) or 999
    if ia ~= ib then return ia < ib end
    return tostring(a.questID) < tostring(b.questID)
  end)
  local palette = self.QUEST_MARKER_PALETTE
  local pcount = getn(palette)
  if pcount < 1 then return end

  local byZone = {}
  local zi
  for zi = 1, getn(list) do
    local q = list[zi]
    local z = "Other"
    if GQ.Tracker and GQ.Tracker.GuessZoneName then
      z = GQ.Tracker:GuessZoneName(q) or "Other"
    end
    if not byZone[z] then byZone[z] = {} end
    table.insert(byZone[z], q)
  end

  local zname, qs
  for zname, qs in pairs(byZone) do
    local usedIdx = {}
    local qi
    for qi = 1, getn(qs) do
      local q = qs[qi]
      local bestI, bestScore = 1, -1
      local pi
      for pi = 1, pcount do
        local col = palette[pi]
        local minD = 100
        local ui
        for ui = 1, getn(usedIdx) do
          local d = MarkerColorDist(col, palette[usedIdx[ui]])
          if d < minD then minD = d end
        end
        if getn(usedIdx) == 0 then minD = 100 end
        if minD > bestScore then
          bestScore = minD
          bestI = pi
        end
      end
      table.insert(usedIdx, bestI)
      self._questMarkerColor[tostring(q.questID)] = palette[bestI]
    end
  end
  -- Player overrides (ctrl-click) win
  if GreedQuestCharDB and GreedQuestCharDB.questColorIdx then
    local qid, idx
    for qid, idx in pairs(GreedQuestCharDB.questColorIdx) do
      idx = tonumber(idx)
      if idx and palette[idx] then
        self._questMarkerColor[tostring(qid)] = palette[idx]
      end
    end
  end
  self:MergeSharedObjectiveColors()
  self:AssignKillEntityColors()
end

function Map:AssignKillEntityColors()
  if not self._questMarkerColor or not self.nodes then return end
  local palette = self.QUEST_MARKER_PALETTE
  local pcount = palette and getn(palette) or 0
  if pcount < 1 then return end
  local byQuest = {}
  local mapID, list, _, n
  for mapID, list in pairs(self.nodes) do
    if list then
      for _, n in ipairs(list) do
        if n.typ == "Kill" and n.questID then
          local qk = tostring(n.questID)
          local ek = tostring(n.entityId or n.entityName or "")
          if ek ~= "" then
            if not byQuest[qk] then byQuest[qk] = {} end
            local seen = false
            local j
            for j = 1, getn(byQuest[qk]) do
              if byQuest[qk][j] == ek then seen = true break end
            end
            if not seen then table.insert(byQuest[qk], ek) end
          end
        end
      end
    end
  end
  local qk, ents
  for qk, ents in pairs(byQuest) do
    if getn(ents) > 1 then
      local base = self._questMarkerColor[qk]
      local i
      for i = 1, getn(ents) do
        local idx = i
        if base then
          local pi
          for pi = 1, pcount do
            if palette[pi] == base then idx = pi + i - 1 break end
          end
        end
        while idx > pcount do idx = idx - pcount end
        local col = palette[idx]
        self._questMarkerColor["k:" .. qk .. ":" .. ents[i]] = col
        local nm
        if GreedQuestDB and GreedQuestDB.unitNames then
          local nid = tonumber(ents[i])
          nm = nid and GreedQuestDB.unitNames[nid]
        end
        if nm and nm ~= "" then
          self._questMarkerColor["k:" .. qk .. ":" .. nm] = col
          self._questMarkerColor["k:" .. qk .. ":" .. string.lower(nm)] = col
        end
      end
    end
  end
end

function Map:MergeSharedObjectiveColors()
  if not self._questMarkerColor or not self.nodes then return end
  local byEnt = {}
  local mapID, list, _, n
  for mapID, list in pairs(self.nodes) do
    if list then
      for _, n in ipairs(list) do
        local typ = n.typ or ""
        if (typ == "Kill" or typ == "Loot") and n.questID then
          local ent = tostring(n.entityId or n.entityName or "")
          if ent ~= "" then
            if not byEnt[ent] then byEnt[ent] = {} end
            local qk = tostring(n.questID)
            local seen = false
            local j
            for j = 1, getn(byEnt[ent]) do
              if byEnt[ent][j] == qk then seen = true break end
            end
            if not seen then table.insert(byEnt[ent], qk) end
          end
        end
      end
    end
  end
  local ent, qids
  for ent, qids in pairs(byEnt) do
    if getn(qids) > 1 then
      local primary = self._questMarkerColor[qids[1]]
      local i
      for i = 2, getn(qids) do
        if primary then
          self._questMarkerColor[qids[i]] = primary
        end
      end
    end
  end
end

function Map:GetQuestMarkerColor(node)
  if not node or not self._questMarkerColor then return nil end
  if node.questID and (node.typ == "Kill" or node.entityId or node.entityName) then
    local qk = tostring(node.questID)
    if node.entityId then
      local ek = "k:" .. qk .. ":" .. tostring(node.entityId)
      if self._questMarkerColor[ek] then return self._questMarkerColor[ek] end
    end
    if node.entityName and node.entityName ~= "" then
      local ek = "k:" .. qk .. ":" .. node.entityName
      if self._questMarkerColor[ek] then return self._questMarkerColor[ek] end
      ek = "k:" .. qk .. ":" .. string.lower(node.entityName)
      if self._questMarkerColor[ek] then return self._questMarkerColor[ek] end
    end
  end
  if not node.questID then return nil end
  return self._questMarkerColor[tostring(node.questID)]
end

function Map:CycleQuestColor(qid, title)
  qid = qid or title
  if not qid then return end
  if not GreedQuestCharDB then GreedQuestCharDB = {} end
  if not GreedQuestCharDB.questColorIdx then GreedQuestCharDB.questColorIdx = {} end
  local key = tostring(qid)
  local palette = self.QUEST_MARKER_PALETTE
  local pcount = getn(palette)
  if pcount < 1 then return end
  local cur = tonumber(GreedQuestCharDB.questColorIdx[key]) or 0
  local nxt = math.mod(cur, pcount) + 1
  GreedQuestCharDB.questColorIdx[key] = nxt
  if not self._questMarkerColor then self._questMarkerColor = {} end
  self._questMarkerColor[key] = palette[nxt]
  if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
  self._miniNeedsFull = true
  if self.UpdateWorldPins then self:UpdateWorldPins() end
  if self.UpdateMinimapPins then self:UpdateMinimapPins() end
end

function Map:QuestObjectiveCount(qid)
  if not qid or not GQ.Core or not GQ.Core.GetQuestByID then return 0 end
  local q = GQ.Core:GetQuestByID(qid)
  if q and q.objectives then return getn(q.objectives) end
  return 0
end

function Map:IsSingleObjectiveQuest(node)
  if not node or not node.questID then return false end
  local typ = node.typ or ""
  if typ ~= "Kill" and typ ~= "Loot" and typ ~= "Object" then return false end
  return self:QuestObjectiveCount(node.questID) == 1
end

function Map:AdjustPinDrawSize(base, node)
  local s = tonumber(base) or 12
  if not node then return s end
  if node.typ == "Turn In" then
    s = s + 1
  end
  if self:IsSingleObjectiveQuest(node) then
    s = s + 1
  end
  return s
end

-- Colored "•" over the pin; pure text color so the tint always reads.


function Map:ApplyQuestMarker(pin, node, pinSize)
  if not pin or not pin.numText then return end
  local on = true
  if GreedQuestConfig and GreedQuestConfig.map and GreedQuestConfig.map.colorCodedObjectives == false then
    on = false
  end
  if not on then
    pin.numText:Hide()
    return
  end
  local c = self:GetQuestMarkerColor(node)
  if not c then
    pin.numText:Hide()
    return
  end
  pin.numText:SetText("•")
  local sz = tonumber(pinSize) or 16
  local fontSize = 10
  if sz <= 10 then
    fontSize = 8
  elseif sz <= 14 then
    fontSize = 9
  elseif sz >= 22 then
    fontSize = 12
  end
  if pin.numText.SetFont then
    pin.numText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
  end
  pin.numText:SetTextColor(c[1], c[2], c[3])
  pin.numText:Show()
end

Map.LAYER = {
  objective = 1,
  giver     = 3,
  turnin    = 4,
  cluster   = 5,
}

-- Default cluster radius in map units (0-100 scale)
Map.CLUSTER_RADIUS = 2.5

-- Soft defaults only; pools grow on demand (no hard pin cap)
local WORLD_POOL_SIZE = 200
local MINI_POOL_SIZE  = 150
local LINE_POOL_SIZE  = 200

-- ============================================================
-- State
-- ============================================================

Map.nodes     = {}   -- raw nodes [mapID] = { node, ... }
Map.clusters  = {}   -- clustered result [mapID] = { clusterNode, ... }
Map.worldPins = {}
Map.miniPins  = {}
Map.linePool  = {}
Map.paths     = {}  -- active path segments to draw
Map.playerZoneID = nil
Map.zoneByName = nil

-- ============================================================
-- Helpers
-- ============================================================

local function GetPlayerMapPositionSafe()
  local x, y = GetPlayerMapPosition("player")
  if not x or not y then return 0, 0 end
  return x, y
end

local function ToNormalized(x, y)
  return (x or 0) / 100, (y or 0) / 100
end

local function Dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx*dx + dy*dy
end

-- ============================================================
-- Node management
-- ============================================================

function Map:ClearNodes(filter)
  self:ClearPaths()
  if filter then
    for mapID, list in pairs(self.nodes) do
      local keep = {}
      for _, node in ipairs(list) do
        if node.source ~= filter then
          table.insert(keep, node)
        end
      end
      self.nodes[mapID] = keep
    end
  else
    self.nodes = {}
  end
  self.clusters = {}
  self:MarkClustersDirty()
  -- Do not UpdatePins here — caller rebuilds nodes then draws once
end

function Map:AddNode(node)
  if not node or not node.mapID or not node.x or not node.y then return end
  self:MarkClustersDirty()

  local mapID = tonumber(node.mapID) or node.mapID
  node.mapID = mapID
  -- Force numeric coords (packed data can yield strings)
  node.x = tonumber(node.x) or 0
  node.y = tonumber(node.y) or 0
  if not self.nodes[mapID] then
    self.nodes[mapID] = {}
  end

  local rx = math.floor(node.x * 10 + 0.5) / 10
  local ry = math.floor(node.y * 10 + 0.5) / 10

  for _, existing in ipairs(self.nodes[mapID]) do
    if existing.title == node.title
       and existing.questID == node.questID
       and existing.typ == node.typ
       and math.abs(existing.x - rx) < 0.15
       and math.abs(existing.y - ry) < 0.15 then
      -- Same spawn used by multiple objectives (e.g. Harpy + Ambusher): keep one pin, merge entities
      if node.entityId and existing.entityId and node.entityId ~= existing.entityId then
        if not existing.entityIds then
          existing.entityIds = { existing.entityId }
          existing.entityNames = { existing.entityName }
        end
        local already = false
        local _, eid
        for _, eid in ipairs(existing.entityIds) do
          if eid == node.entityId then already = true break end
        end
        if not already then
          table.insert(existing.entityIds, node.entityId)
          table.insert(existing.entityNames, node.entityName or "")
        end
      end
      return
    end
  end

  node.x = rx
  node.y = ry
  node.layer = node.layer or 1
  node.texture = node.texture or self.ICON.default
  table.insert(self.nodes[mapID], node)
end

-- ============================================================
-- Clustering
-- ============================================================

function Map:GetClusterRadius()
  local cfg = GreedQuestConfig and GreedQuestConfig.map
  if cfg and cfg.clusterRadius then
    return cfg.clusterRadius
  end
  return self.CLUSTER_RADIUS
end

function Map:IsClusteringEnabled()
  local cfg = GreedQuestConfig and GreedQuestConfig.map
  if cfg and cfg.cluster ~= nil then
    return cfg.cluster and true or false
  end
  return true
end

-- Group key: objectives stay per-quest; Available/Turn In stack by NPC + position
-- so several quests from the same giver share one pin (tooltip lists them all).
local function GroupKey(node)
  local typ = tostring(node.typ or "")
  if typ == "Available" or typ == "Turn In" then
    local ent = node.entityId or node.turninID or node.entityName or ""
    local rx = math.floor(((tonumber(node.x) or 0) * 2) + 0.5) / 2
    local ry = math.floor(((tonumber(node.y) or 0) * 2) + 0.5) / 2
    return typ .. "|" .. tostring(ent) .. "|" .. tostring(rx) .. "|" .. tostring(ry) .. "|" .. tostring(node.mapID or "")
  end
  -- Kill + loot on the same mob share one pin across quests (Candles + Gold Dust).
  if typ == "Kill" or typ == "Loot" then
    local ent = node.entityId or node.entityName or ""
    return "mob|" .. tostring(ent) .. "|" .. tostring(node.mapID or "")
  end
  local ent = node.entityId or node.entityName or ""
  return tostring(node.questID or node.title or "") .. "|" .. typ .. "|" .. tostring(ent)
end

--[[
  Greedy distance clustering per map and per group key.
  Returns a list of display nodes (some may be clusters with .count > 1).
]]

-- Active objectives always beat nearby available "!" so stacked pins
-- do not flip type across reloads (pairs() order is unstable on 1.12).
local function PinPriority(n)
  local typ = n.typ or ""
  -- Ready-to-turn-in "?" always wins overlaps vs available "!"
  if typ == "Turn In" and not n.grey then return 80 end
  if typ == "Kill" or typ == "Loot" or typ == "Object" then return 40 end
  if typ == "Turn In" then return 35 end
  if typ == "Available" or typ == "Quest Giver" then return 8 end
  if n.source == "tracking" then return 5 end
  return 20
end

local function TypRank(typ)
  typ = typ or ""
  if typ == "Turn In" then return 5 end
  if typ == "Object" then return 4 end
  if typ == "Loot" then return 3 end
  if typ == "Kill" then return 2 end
  if typ == "Available" or typ == "Quest Giver" then return 1 end
  return 0
end

local function IsAvailablePin(n)
  if not n then return false end
  return n.typ == "Available" or n.typ == "Quest Giver" or n.source == "available"
end

function Map:StabilizeDisplayNodes(list, skipGiverCluster)
  if not list or getn(list) == 0 then return list end
  table.sort(list, function(a, b)
    local pa, pb = PinPriority(a), PinPriority(b)
    if pa ~= pb then return pa > pb end
    local qa = tonumber(a.questID) or 0
    local qb = tonumber(b.questID) or 0
    if qa ~= qb then return qa < qb end
    local ta, tb = TypRank(a.typ), TypRank(b.typ)
    if ta ~= tb then return ta > tb end
    if (a.x or 0) ~= (b.x or 0) then return (a.x or 0) < (b.x or 0) end
    return (a.y or 0) < (b.y or 0)
  end)

  local OVERLAP = 0.9
  local o2 = OVERLAP * OVERLAP
  local keep = {}
  local i, j
  for i = 1, getn(list) do
    local n = list[i]
    local drop = false
    local nudged = false
    for j = 1, getn(keep) do
      local k = keep[j]
      local dx = (n.x or 0) - (k.x or 0)
      local dy = (n.y or 0) - (k.y or 0)
      if dx * dx + dy * dy <= o2 then
        local nAvail = IsAvailablePin(n)
        local kAvail = IsAvailablePin(k)
        local nt = n.typ or ""
        local kt = k.typ or ""
        local nObj = (nt == "Kill" or nt == "Loot" or nt == "Object")
        local kObj = (kt == "Kill" or kt == "Loot" or kt == "Object")
        local nTurn = (nt == "Turn In")
        local kTurn = (kt == "Turn In")
        local sameGiver = false
        if n.entityId and k.entityId and tostring(n.entityId) == tostring(k.entityId) then
          sameGiver = true
        elseif n.entityName and k.entityName and n.entityName ~= "" and n.entityName == k.entityName then
          sameGiver = true
        elseif n.turninID and k.entityId and tostring(n.turninID) == tostring(k.entityId) then
          sameGiver = true
        elseif k.turninID and n.entityId and tostring(k.turninID) == tostring(n.entityId) then
          sameGiver = true
        end
        -- Same NPC: keep "?" and drop "!". Different NPCs on the same spot stay both.
        if nAvail and kTurn and sameGiver then
          drop = true
          break
        elseif nTurn and kAvail and sameGiver then
          -- keep the turn-in we are adding
        elseif nAvail and not kAvail then
          if skipGiverCluster then
            -- leave ! next to objectives on true coords
          elseif not nudged then
            n.x = (n.x or 0) + 1.2
            n.y = (n.y or 0) - 0.4
            nudged = true
          end
        elseif (not nAvail) and kAvail then
          -- keep both
        elseif nObj and kObj then
          local sameMob = false
          if n.entityId and k.entityId and tostring(n.entityId) == tostring(k.entityId) then
            sameMob = true
          elseif n.entityName and k.entityName and n.entityName ~= "" and n.entityName == k.entityName then
            sameMob = true
          end
          if sameMob then
            -- Same enemy: keep kill over loot, one pin.
            if kTurn or (kt == "Kill" and nt == "Loot") then
              drop = true
              break
            elseif nt == "Kill" and kt == "Loot" then
              -- keep incoming kill
            else
              drop = true
              break
            end
          elseif tostring(n.questID or "") ~= tostring(k.questID or "") then
            if not nudged then
              n.x = (n.x or 0) + 0.9
              n.y = (n.y or 0) - 0.5
              nudged = true
            end
          else
            drop = true
            break
          end
        else
          drop = true
          break
        end
      end
    end
    if not drop then
      table.insert(keep, n)
    end
  end
  return keep
end

function Map:ClusterNodesForMap(mapID, skipGiverCluster)
  local raw = self.nodes[mapID]
  if not raw or getn(raw) == 0 then return {} end

  if not self:IsClusteringEnabled() then
    local out = {}
    for _, n in ipairs(raw) do
      local c = {}
      for k, v in pairs(n) do c[k] = v end
      c.x = tonumber(n.x) or n.x
      c.y = tonumber(n.y) or n.y
      c.count = 1
      c.members = { n }
      c.isCluster = false
      table.insert(out, c)
    end
    return self:StabilizeDisplayNodes(out, skipGiverCluster)
  end

  local radius = self:GetClusterRadius()
  local r2 = radius * radius
  local MAX_MEMBERS = 20

  -- Bucket by quest+type so different objectives never merge
  local buckets = {}
  for _, node in ipairs(raw) do
    local key = GroupKey(node)
    local typ = tostring(node.typ or "")
    if skipGiverCluster and (typ == "Available" or typ == "Turn In" or typ == "Quest Giver") then
      key = typ .. "|exact|" .. tostring(node.questID or node.title or "") .. "|" .. tostring(node.x) .. "|" .. tostring(node.y) .. "|" .. tostring(node.entityId or "")
    end
    if not buckets[key] then buckets[key] = {} end
    table.insert(buckets[key], node)
  end

  local result = {}

  local bucketKeys = {}
  for key, _ in pairs(buckets) do
    table.insert(bucketKeys, key)
  end
  table.sort(bucketKeys)
  local _, key
  for _, key in ipairs(bucketKeys) do
    local group = buckets[key]
    local n = getn(group)
    local used = {}
    for i = 1, n do used[i] = false end
    local centers = {}  -- existing cluster centers for even spread

    local remaining = n
    while remaining > 0 do
      -- Pick seed: farthest from existing centers (even spatial spread)
      local seedIdx, bestDist = nil, -1
      for i = 1, n do
        if not used[i] then
          local minD = 1e9
          if getn(centers) == 0 then
            minD = 1e9
            -- prefer first unused as start, but still iterate
            seedIdx = i
            break
          else
            for _, c in ipairs(centers) do
              local d = Dist2(group[i].x, group[i].y, c[1], c[2])
              if d < minD then minD = d end
            end
            if minD > bestDist then
              bestDist = minD
              seedIdx = i
            end
          end
        end
      end
      if not seedIdx then break end

      -- Gather up to MAX_MEMBERS nearest points within radius (or nearest overall if isolated)
      local candidates = {}
      for i = 1, n do
        if not used[i] then
          local d = Dist2(group[seedIdx].x, group[seedIdx].y, group[i].x, group[i].y)
          table.insert(candidates, { i = i, d = d })
        end
      end
      table.sort(candidates, function(a, b) return a.d < b.d end)

      local members = {}
      for _, cand in ipairs(candidates) do
        if getn(members) >= MAX_MEMBERS then break end
        -- Prefer within radius; allow first seed always
        if getn(members) == 0 or cand.d <= r2 then
          table.insert(members, group[cand.i])
          used[cand.i] = true
          remaining = remaining - 1
        elseif getn(members) == 0 then
          table.insert(members, group[cand.i])
          used[cand.i] = true
          remaining = remaining - 1
        else
          break
        end
      end
      if getn(members) == 0 then break end

      -- Centroid of members
      local cx, cy = 0, 0
      local count = getn(members)
      for _, m in ipairs(members) do
        cx = cx + m.x
        cy = cy + m.y
      end
      cx = cx / count
      cy = cy / count
      table.insert(centers, { cx, cy })

      local rep = members[1]
      local mi
      for mi = 1, getn(members) do
        if members[mi].typ == "Kill" then
          rep = members[mi]
          break
        end
      end
      table.insert(result, {
        mapID   = mapID,
        x       = cx,
        y       = cy,
        title   = rep.title,
        texture = rep.texture,
        layer   = count > 1 and self.LAYER.cluster or rep.layer,
        quest   = rep.quest,
        questID = rep.questID,
        typ     = rep.typ,
        source  = rep.source,
        level   = rep.level,
        grey    = rep.grey,
        entityId = rep.entityId,
        entityName = rep.entityName,
        entityIds = rep.entityIds,
        entityNames = rep.entityNames,
        isUnit = rep.isUnit,
        itemID = rep.itemID,
        itemName = rep.itemName,
        dropChance = rep.dropChance,
        turninID = rep.turninID,
        turninName = rep.turninName,
        turninZone = rep.turninZone,
        count   = count,
        members = members,
        isCluster = count > 1,
      })
    end
  end

  return self:StabilizeDisplayNodes(result, skipGiverCluster)
end

function Map:RebuildClusters()
  self.clusters = {}
  self.clustersWide = nil
  for mapID, _ in pairs(self.nodes) do
    -- Always keep available / turn-in on true coords (zone, mini, continent).
    self.clusters[mapID] = self:ClusterNodesForMap(mapID, true)
  end
  -- Cluster list changed — minimap must reassign pins (do not early-return)
  self._miniNeedsFull = true
  self._lastMiniX = nil
  self._lastMiniY = nil
end

-- ============================================================
-- Pin pools
-- ============================================================



function Map:CollectObjectiveQuests(node)
  local out = {}
  local seen = {}
  local function add(n)
    if not n then return end
    local qid = n.questID
    local title = n.title or n.quest
    local key = qid and ("id:" .. tostring(qid)) or ("t:" .. tostring(title or ""))
    if key == "id:" or key == "t:" then return end
    if seen[key] then return end
    seen[key] = true
    local q = nil
    if qid and GQ.Core and GQ.Core.GetQuestByID then
      q = GQ.Core:GetQuestByID(qid)
    end
    table.insert(out, { questID = qid, title = title, quest = q, node = n })
  end
  if node.members then
    local _, m
    for _, m in ipairs(node.members) do add(m) end
  end
  add(node)
  return out
end

function Map:CollectNearbyAvailable(node)
  local out = {}
  local seen = {}
  local function add(n)
    if not n then return end
    if n.typ ~= "Available" and n.source ~= "available" then return end
    local key = n.questID and ("id:" .. tostring(n.questID)) or ("t:" .. tostring(n.title or n.quest or ""))
    if key == "id:" or key == "t:" then return end
    if seen[key] then return end
    seen[key] = true
    table.insert(out, n)
  end

  if node.members then
    for _, m in ipairs(node.members) do
      add(m)
    end
  end
  add(node)

  -- Also pick up separate pins sitting on top of each other (clustering off / edge cases)
  local mapID = node.mapID
  local raw = mapID and self.nodes and self.nodes[mapID]
  if raw then
    local nx = tonumber(node.x) or 0
    local ny = tonumber(node.y) or 0
    local r2 = 2.5 * 2.5
    for _, n in ipairs(raw) do
      if n.typ == "Available" or n.source == "available" then
        local dx = (tonumber(n.x) or 0) - nx
        local dy = (tonumber(n.y) or 0) - ny
        if (dx * dx + dy * dy) <= r2 then
          add(n)
        end
      end
    end
  end
  return out
end

function Map:ShowPinTooltip(pin)
  local n = pin and pin.node
  if not n then return end

  local tip = GameTooltip
  if WorldMapFrame and WorldMapFrame:IsVisible() and WorldMapTooltip then
    tip = WorldMapTooltip
  end
  tip:SetOwner(pin, "ANCHOR_RIGHT")
  -- Always above map pins (pins use HIGH; tooltip must be higher)
  if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
  if tip.SetFrameLevel then tip:SetFrameLevel(125) end
  tip.gqPinTooltip = 1  -- prevent Tooltips.lua from re-appending progress
  tip:ClearLines()

  local title = n.title or n.quest
  -- For stacked available pins, the body lists every quest; keep header short
  if (n.typ == "Available" or n.source == "available") then
    local nearby = self:CollectNearbyAvailable(n)
    if getn(nearby) > 1 then
      tip:AddLine("Quest giver", 1, 0.82, 0)
    elseif title and title ~= "" then
      tip:AddLine(title, 1, 0.82, 0)
    else
      tip:AddLine("Available quest", 1, 0.82, 0)
    end
  elseif (n.typ == "Kill" or n.typ == "Loot") and n.members and getn(n.members) > 1 then
    local name = n.entityName
    if (not name or name == "") and n.entityId and GreedQuestDB and GreedQuestDB.unitNames then
      name = GreedQuestDB.unitNames[n.entityId]
    end
    tip:AddLine(name or "Quest objectives", 1, 0.82, 0)
  elseif title and title ~= "" then
    tip:AddLine(title, 1, 0.82, 0)
  else
    tip:AddLine("Unknown quest", 1, 0.2, 0.2)
  end

  do
    local qlvl = n.level
    if not qlvl and n.questID and GreedQuestDB and GreedQuestDB.quests then
      local qd = GreedQuestDB.quests[n.questID]
      if qd then qlvl = qd["lvl"] or qd["min"] end
    end
    if not qlvl and n.questID and GQ.Core and GQ.Core.GetQuestByID then
      local qq = GQ.Core:GetQuestByID(n.questID)
      if qq then qlvl = qq.level end
    end
    local mlvl = n.mobLevel
    if not mlvl and n.entityId and GreedQuestDB and GreedQuestDB.units then
      local u = GreedQuestDB.units[n.entityId]
      if u and u["lvl"] then mlvl = u["lvl"] end
    end
    if mlvl and n.typ == "Kill" then
      tip:AddLine("Mob level  " .. tostring(mlvl), 0.75, 0.75, 0.75)
    elseif qlvl then
      local shown = qlvl
      if GQ.Core and GQ.Core.FormatQuestLevel then
        shown = GQ.Core:FormatQuestLevel(qlvl, n.questID, title, n.tag, n.logHeader)
      end
      tip:AddLine("Quest level  " .. tostring(shown), 0.75, 0.75, 0.75)
    end
    if n.entrance then
      tip:AddLine("Dungeon entrance", 0.7, 0.85, 1)
    end
  end

  if n.source == "tracking" then
    tip:AddLine(n.typ or "Tracking", 0.6, 0.9, 1)
  elseif n.typ == "Available" then
    -- filled below via CollectNearbyAvailable (may list several quests)
  elseif n.typ == "Turn In" then
    local npcName = n.turninName
    local zoneName = n.turninZone
    if not npcName and n.turninID and GreedQuestDB and GreedQuestDB.unitNames then
      npcName = GreedQuestDB.unitNames[n.turninID]
    end
    if not zoneName and n.mapID and GreedQuestDB and GreedQuestDB.zones then
      zoneName = GreedQuestDB.zones[n.mapID]
    end
    if not n.grey then
      -- Completed / ready to turn in
      if npcName and zoneName then
        tip:AddLine("Turn in at " .. npcName .. " in " .. zoneName, 0.3, 1.0, 0.3)
      elseif npcName then
        tip:AddLine("Turn in at " .. npcName, 0.3, 1.0, 0.3)
      elseif zoneName then
        tip:AddLine("Turn in in " .. zoneName, 0.3, 1.0, 0.3)
      else
        tip:AddLine("Ready to turn in", 0.3, 1.0, 0.3)
      end
    else
      tip:AddLine("Turn in  ·  in progress", 0.7, 0.7, 0.7)
      if npcName and zoneName then
        tip:AddLine(npcName .. " · " .. zoneName, 0.6, 0.6, 0.6)
      end
    end
  elseif n.typ then
    tip:AddLine(n.typ, 0.75, 0.75, 0.75)
  end

  -- Loot pins: drop % only while Ctrl is held (always shown on enemy unit tooltips)
  if n.typ == "Loot" then
    local function fmtChance(c)
      if not c or c <= 0 then return nil end
      if c >= 10 then
        return string.format("%.0f%%", c)
      elseif c >= 1 then
        return string.format("%.1f%%", c)
      else
        return string.format("%.2f%%", c)
      end
    end
    local lo, hi = n.dropChance, n.dropChance
    if n.members then
      local _, m
      for _, m in ipairs(n.members) do
        if m.dropChance and m.dropChance > 0 then
          if not lo or m.dropChance < lo then lo = m.dropChance end
          if not hi or m.dropChance > hi then hi = m.dropChance end
        end
      end
    end
    local a = fmtChance(lo)
    local b = fmtChance(hi)
    if n.rareArea then
      tip:AddLine("Rare drop area  (<1%)", 0.75, 0.7, 0.45)
    end
    if a then
      if IsControlKeyDown() then
        if b and a ~= b then
          tip:AddLine("Drop chance  " .. a .. " – " .. b, 0.55, 0.85, 1)
        else
          tip:AddLine("Drop chance  " .. a, 0.55, 0.85, 1)
        end
      else
        tip:AddLine("|cffaaaaaaHold Ctrl for drop chance|r", 0.7, 0.7, 0.7)
      end
    end
  end

  if n.count and n.count > 1 and n.typ ~= "Available" and n.source ~= "available" then
    tip:AddLine(string.format("%d nearby locations", n.count), 0.5, 0.8, 1)
  end

  local objQuests = nil
  if n.typ == "Kill" or n.typ == "Loot" or n.typ == "Object" then
    objQuests = self:CollectObjectiveQuests(n)
  end
  if objQuests and getn(objQuests) > 1 then
    local qi
    for qi = 1, getn(objQuests) do
      local e = objQuests[qi]
      tip:AddLine(e.title or "Quest", 1, 0.82, 0)
      local q = e.quest
      if q and q.objectives then
        local _, obj
        for _, obj in ipairs(q.objectives) do
          local t = obj.text or ""
          if t ~= "" then
            if obj.finished then
              tip:AddLine("  |cff55ff55" .. t .. "|r")
            else
              tip:AddLine("  |cffffffff" .. t .. "|r")
            end
          end
        end
      end
    end
  end

  -- Single progress block (deduped by objective text)
  local q = nil
  if not (objQuests and getn(objQuests) > 1) then
  if n.questID and GQ.Core and GQ.Core.GetQuestByID then
    q = GQ.Core:GetQuestByID(n.questID)
  end
  if not q and title and GQ.Core and GQ.Core.questLog then
    for _, qq in pairs(GQ.Core.questLog) do
      if qq.title == title then q = qq break end
    end
  end
  if q and q.objectives and getn(q.objectives) > 0 then
    -- Resolve entity name for this pin (cluster reps may need a refresh)
    local entName = n.entityName
    if (not entName or entName == "") and n.entityId and GreedQuestDB and GreedQuestDB.unitNames then
      entName = GreedQuestDB.unitNames[n.entityId]
      n.entityName = entName
    end
    local entLower = entName and string.lower(entName) or nil
    local ntyp = string.lower(n.typ or "")

    -- Turn-in / available pins should not list kill/loot objectives
    local showObjs = (ntyp ~= "turn in" and ntyp ~= "available" and n.source ~= "available" and n.source ~= "tracking")
    if showObjs then
      local seen = {}
      local matched = {}
      -- Build match keys: entity names + item name (loot pins)
      local nameList = {}
      if n.entityNames and type(n.entityNames) == "table" then
        local _, nm
        for _, nm in ipairs(n.entityNames) do
          if nm and nm ~= "" then table.insert(nameList, string.lower(nm)) end
        end
      elseif entLower and entLower ~= "" then
        table.insert(nameList, entLower)
      end
      if n.itemName and n.itemName ~= "" then
        table.insert(nameList, string.lower(n.itemName))
      end
      -- Match any objective whose text contains any name key
      if getn(nameList) > 0 then
        for _, obj in ipairs(q.objectives) do
          local t = obj.text or ""
          if t ~= "" and not seen[t] then
            local tl = string.lower(t)
            local _, nl
            for _, nl in ipairs(nameList) do
              if string.find(tl, nl, 1, true) then
                seen[t] = true
                table.insert(matched, obj)
                break
              end
            end
          end
        end
      end
      -- Loot pins: also accept item-type objectives (mob name rarely appears in "Fang: 0/10")
      if getn(matched) == 0 and ntyp == "loot" then
        local itemMatches = {}
        for _, obj in ipairs(q.objectives) do
          local t = obj.text or ""
          local ot = string.lower(obj.type or "")
          if t ~= "" and not seen[t] and (ot == "item" or ot == "") then
            -- Prefer objectives that look like item progress (contain : or /)
            table.insert(itemMatches, obj)
          end
        end
        if n.itemID and getn(itemMatches) > 1 then
          -- Multiple item objectives: keep those that mention this pin's entity if possible, else all item objs
          matched = itemMatches
        elseif getn(itemMatches) >= 1 then
          matched = itemMatches
        end
      end
      -- Fallback: exactly one objective of this type on the quest
      if getn(matched) == 0 then
        local typeMatches = {}
        for _, obj in ipairs(q.objectives) do
          local t = obj.text or ""
          if t ~= "" and not seen[t] then
            local ot = string.lower(obj.type or "")
            local ok = false
            if ntyp == "kill" and (ot == "monster" or ot == "mob" or ot == "") then ok = true end
            if ntyp == "loot" and (ot == "item" or ot == "") then ok = true end
            if ntyp == "object" and (ot == "object" or ot == "") then ok = true end
            if ok then table.insert(typeMatches, obj) end
          end
        end
        if getn(typeMatches) == 1 then
          matched = typeMatches
        end
      end
      for _, obj in ipairs(matched) do
        local t = obj.text or ""
        if obj.finished then
          tip:AddLine("  |cff55ff55" .. t .. "|r")
        else
          tip:AddLine("  |cffffffff" .. t .. "|r")
        end
      end
      if getn(matched) == 0 and getn(nameList) > 0 then
        local _, nl
        for _, nl in ipairs(nameList) do
          tip:AddLine("  |cffffffff" .. nl .. "|r", 0.8, 0.8, 0.8)
        end
      end
    end
  end

  end -- single-quest progress
  -- Available: compact list; Shift shows title once with objective under it (no duplicate names)
  if (n.typ == "Available" or n.source == "available") then
    local nearby = self:CollectNearbyAvailable(n)
    local count = getn(nearby)

    local function QuestLabel(aq)
      local title = aq.title or aq.quest or ("Quest " .. tostring(aq.questID or "?"))
      local lvl = aq.level or aq.lvl
      if lvl then
        local shown = lvl
        if GQ.Core and GQ.Core.FormatQuestLevel then
          shown = GQ.Core:FormatQuestLevel(lvl, aq.questID, title, aq.tag, aq.logHeader)
        end
        return string.format("[%s] %s", tostring(shown), title), title
      end
      return title, title
    end

    local function AddWrappedObjective(text)
      if not text or text == "" then return end
      local maxLen = 72
      local rest = text
      while string.len(rest) > maxLen do
        local chunk = string.sub(rest, 1, maxLen)
        local br = maxLen
        local i = maxLen
        while i > 24 do
          if string.sub(chunk, i, i) == " " then br = i break end
          i = i - 1
        end
        tip:AddLine(string.sub(rest, 1, br), 0.92, 0.92, 0.92)
        rest = string.sub(rest, br + 1)
      end
      if string.len(rest) > 0 then
        tip:AddLine(rest, 0.92, 0.92, 0.92)
      end
    end

    if IsShiftKeyDown() then
      -- One block per quest: [level] Title then objective text (no second title)
      if count > 1 then
        tip:AddLine(string.format("%d available quests", count), 0.5, 0.85, 1)
      else
        local one = nearby[1] or n
        local tr, tg, tb = self:GetAvailableTint(one.questID, one.title or one.quest)
        if tr then
          if tr > 0.8 and tg < 0.4 then tip:AddLine("PvP", tr, tg, tb)
          elseif tg > 0.7 and tr < 0.5 then tip:AddLine("Seasonal", tr, tg, tb)
          elseif tb > 0.7 then tip:AddLine("Daily / Repeatable", tr, tg, tb)
          end
        else
          tip:AddLine("Available", 0.3, 1.0, 0.3)
        end
      end
      for _, aq in ipairs(nearby) do
        local label, _ = QuestLabel(aq)
        local tr, tg, tb = self:GetAvailableTint(aq.questID, aq.title or aq.quest)
        if tr then
          tip:AddLine(label, tr, tg, tb)
        else
          tip:AddLine(label, 1, 0.85, 0.2)
        end
        local qid = aq.questID
        local objText = qid and GreedQuestDB and GreedQuestDB.questObjectives and GreedQuestDB.questObjectives[qid]
        if objText and objText ~= "" then
          AddWrappedObjective(objText)
        else
          tip:AddLine("|cffaaaaaa(No objective text)|r", 0.6, 0.6, 0.6)
        end
      end
    else
      -- No shift: names only (compact)
      if count <= 1 then
        local one = nearby[1] or n
        local lvl = one.level or one.lvl
        if lvl then
          local shown = lvl
          if GQ.Core and GQ.Core.FormatQuestLevel then
            shown = GQ.Core:FormatQuestLevel(lvl, one.questID, one.title or one.quest, one.tag, one.logHeader)
          end
          tip:AddLine("Available  ·  level " .. tostring(shown), 0.3, 1.0, 0.3)
        else
          tip:AddLine("Available quest", 0.3, 1.0, 0.3)
        end
        local tr, tg, tb = self:GetAvailableTint(one.questID, one.title or one.quest)
        if tr then
          if tr > 0.8 and tg < 0.4 then tip:AddLine("PvP", tr, tg, tb)
          elseif tg > 0.7 and tr < 0.5 then tip:AddLine("Seasonal", tr, tg, tb)
          elseif tb > 0.7 then tip:AddLine("Daily / Repeatable", tr, tg, tb)
          end
        end
      else
        tip:AddLine(string.format("%d available quests here", count), 0.5, 0.85, 1)
        for _, aq in ipairs(nearby) do
          local label, _ = QuestLabel(aq)
          local tr, tg, tb = self:GetAvailableTint(aq.questID, aq.title or aq.quest)
          if tr then
            tip:AddLine("• " .. label, tr, tg, tb)
          else
            tip:AddLine("• " .. label, 1, 0.85, 0.2)
          end
        end
      end
      tip:AddLine("|cffaaaaaaHold Shift for objectives  ·  Alt-click hide|r", 0.7, 0.7, 0.7)
    end
  end

  tip:Show()
  if tip.SetFrameStrata then tip:SetFrameStrata("TOOLTIP") end
  if tip.SetFrameLevel then tip:SetFrameLevel(125) end
end


function Map:OnPinClick(pin)
  local n = pin and pin.node
  if not n then return end
  if IsControlKeyDown() then
    self:CycleQuestColor(n.questID, n.title or n.quest)
    return
  end
  if IsAltKeyDown() then
    self:ToggleHideQuest(n.questID, n.title or n.quest)
  end
end

local function CreateWorldPin(parent, index)
  local pin = CreateFrame("Frame", "GQWorldPin"..index, parent)
  pin:SetWidth(16)
  pin:SetHeight(16)
  if pin.SetFrameStrata then pin:SetFrameStrata("HIGH") end
  pin:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 5) + 50)
  pin:EnableMouse(true)

  -- Black icon silhouette slightly larger (depth / shadow)
  local backdrop = pin:CreateTexture(nil, "BACKGROUND")
  backdrop:SetPoint("CENTER", pin, "CENTER", 0, 0)
  backdrop:SetWidth(20)
  backdrop:SetHeight(20)
  backdrop:SetTexture(Map.ICON.default)
  backdrop:SetVertexColor(0, 0, 0, 1)
  backdrop:Hide()
  pin.backdrop = backdrop

  -- Main icon
  local tex = pin:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(pin)
  tex:SetTexture(Map.ICON.default)
  pin.texture = tex

  -- Quest index number (1-25) overlaid on the icon
  local numText = pin:CreateFontString(nil, "OVERLAY")
  numText:SetPoint("CENTER", pin, "CENTER", 0, 0)
  if numText.SetFont then
    numText:SetFont("Fonts\\FRIZQT__.TTF", 6, "OUTLINE")
  end
  numText:SetText("")
  numText:SetTextColor(1, 1, 1)
  numText:Hide()
  pin.numText = numText

  local badge = pin:CreateTexture(nil, "OVERLAY")
  badge:SetWidth(8)
  badge:SetHeight(8)
  badge:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 2, 2)
  badge:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  badge:Hide()
  pin.badge = badge

  local badgeText = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
  badgeText:SetText("")
  badgeText:Hide()
  pin.badgeText = badgeText

  pin:EnableMouse(true)
  pin:SetScript("OnEnter", function()
    Map:ShowPinTooltip(this)
  end)
  pin:SetScript("OnLeave", function() GameTooltip:Hide() if WorldMapTooltip then WorldMapTooltip:Hide() end end)
  pin:SetScript("OnMouseUp", function()
    Map:OnPinClick(this)
  end)
  pin:Hide()
  return pin
end

local function CreateMiniPin(parent, index)
  local pin = CreateFrame("Frame", "GQMiniPin"..index, parent)
  pin:SetWidth(12)
  pin:SetHeight(12)
  pin:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 5) + 8)

  local tex = pin:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(pin)
  tex:SetTexture(Map.ICON.default)
  pin.texture = tex

  local numText = pin:CreateFontString(nil, "OVERLAY")
  numText:SetPoint("CENTER", pin, "CENTER", 0, 0)
  if numText.SetFont then
    numText:SetFont("Fonts\\FRIZQT__.TTF", 5, "OUTLINE")
  end
  numText:SetText("")
  numText:SetTextColor(1, 1, 1)
  numText:Hide()
  pin.numText = numText

  pin:EnableMouse(true)
  pin:SetScript("OnMouseUp", function()
    Map:OnPinClick(this)
  end)
  pin:SetScript("OnEnter", function()
    this._gqHover = 1
    this._gqShift = IsShiftKeyDown() and 1 or 0
    this._gqCtrl = IsControlKeyDown() and 1 or 0
    Map:ShowPinTooltip(this)
  end)
  pin:SetScript("OnUpdate", function()
    if not this._gqHover then return end
    local s = IsShiftKeyDown() and 1 or 0
    local c = IsControlKeyDown() and 1 or 0
    if s ~= this._gqShift or c ~= this._gqCtrl then
      this._gqShift = s
      this._gqCtrl = c
      Map:ShowPinTooltip(this)
    end
  end)
  pin:SetScript("OnLeave", function()
    this._gqHover = nil
    GameTooltip:Hide()
  end)
  pin:Hide()
  return pin
end

function Map:EnsureWorldPool(needed)
  if not WorldMapButton then return end
  needed = needed or WORLD_POOL_SIZE
  -- Rebuild pool if pin chrome is outdated
  if getn(self.worldPins) > 0 then
    local p0 = self.worldPins[1]
    if p0 and (not p0.backdrop or not p0.numText or p0.outline or p0.centerDot) then
      for _, p in ipairs(self.worldPins) do p:Hide() end
      self.worldPins = {}
    end
  end
  while getn(self.worldPins) < needed do
    table.insert(self.worldPins, CreateWorldPin(WorldMapButton, getn(self.worldPins) + 1))
  end
end

function Map:EnsureMiniPool(needed)
  if not Minimap then return end
  needed = needed or MINI_POOL_SIZE
  if getn(self.miniPins) > 0 then
    local p0 = self.miniPins[1]
    if p0 and (p0.centerDot or not p0.numText) then
      for _, p in ipairs(self.miniPins) do p:Hide() end
      self.miniPins = {}
    end
  end
  while getn(self.miniPins) < needed do
    table.insert(self.miniPins, CreateMiniPin(Minimap, getn(self.miniPins) + 1))
  end
end

-- ============================================================
-- Positioning
-- ============================================================

function Map:GetWorldMapParent()
  -- Parent pins to WorldMapButton so mouse/tooltips work
  if WorldMapButton then
    return WorldMapButton
  end
  if WorldMapDetailFrame then
    return WorldMapDetailFrame
  end
  return nil
end

function Map:GetWorldMapSize()
  -- Coordinate space should match the painted detail frame
  if WorldMapDetailFrame and WorldMapDetailFrame.GetWidth then
    return WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
  end
  local p = self:GetWorldMapParent()
  if p then return p:GetWidth(), p:GetHeight() end
  return 1002, 668
end


-- Approximate zone centers on continent maps (0-100). Used when zoomed out.
-- cont: 1 = Kalimdor, 2 = Eastern Kingdoms
Map.ZONE_CONTINENT = {
  -- Eastern Kingdoms
  [12]  = { 2, 48, 71 },  -- Elwynn
  [40]  = { 2, 40, 76 },  -- Westfall
  [44]  = { 2, 54, 72 },  -- Redridge
  [10]  = { 2, 47, 79 },  -- Duskwood
  [33]  = { 2, 55, 62 },  -- Stranglethorn
  [51]  = { 2, 54, 55 },  -- Searing Gorge
  [46]  = { 2, 57, 50 },  -- Burning Steppes
  [28]  = { 2, 48, 52 },  -- WPL
  [139] = { 2, 58, 42 },  -- EPL
  [11]  = { 2, 58, 78 },  -- Wetlands
  [38]  = { 2, 52, 58 },  -- Loch Modan
  [1]   = { 2, 48, 48 },  -- Dun Morogh
  [3]   = { 2, 52, 52 },  -- Badlands
  [8]   = { 2, 58, 72 },  -- Swamp of Sorrows
  [4]   = { 2, 56, 78 },  -- Blasted Lands
  [85]  = { 2, 42, 38 },  -- Tirisfal
  [130] = { 2, 42, 42 },  -- Silverpine
  [36]  = { 2, 48, 58 },  -- Alterac
  [267] = { 2, 50, 55 },  -- Hillsbrad
  [45]  = { 2, 56, 48 },  -- Arathi
  [47]  = { 2, 62, 55 },  -- Hinterlands
  [41]  = { 2, 48, 82 },  -- Deadwind
  [1519] = { 2, 47, 68 }, -- Stormwind
  [1537] = { 2, 49, 46 }, -- Ironforge
  [1497] = { 2, 43, 36 }, -- Undercity
  -- Kalimdor
  [14]  = { 1, 58, 48 },  -- Durotar
  [215] = { 1, 48, 52 },  -- Mulgore
  [141] = { 1, 42, 28 },  -- Teldrassil
  [17]  = { 1, 52, 42 },  -- Barrens
  [406] = { 1, 42, 48 },  -- Stonetalon
  [405] = { 1, 40, 58 },  -- Desolace
  [357] = { 1, 42, 68 },  -- Feralas
  [440] = { 1, 55, 72 },  -- Tanaris
  [15]  = { 1, 58, 62 },  -- Dustwallow
  [400] = { 1, 52, 55 },  -- Thousand Needles
  [16]  = { 1, 58, 38 },  -- Ashenvale
  [331] = { 1, 52, 32 },  -- Ashenvale alt / Felwood area
  [361] = { 1, 52, 28 },  -- Felwood
  [490] = { 1, 55, 28 },  -- Un'Goro
  [493] = { 1, 52, 22 },  -- Moonglade
  [1377] = { 1, 48, 78 }, -- Silithus
  [1637] = { 1, 58, 48 }, -- Orgrimmar
  [1638] = { 1, 48, 55 }, -- Thunder Bluff
  [1657] = { 1, 40, 28 }, -- Darnassus
}

-- Zone span on continent map (how much local 0-100 compresses into continent %)
Map.ZONE_CONT_SPAN = 7

function Map:GetZoneContinent(mapID)
  -- Returns 0 (EK) or 1 (Kalimdor)
  mapID = tonumber(mapID)
  if not mapID then return 0 end
  local zq = GreedQuestDB and GreedQuestDB.zoneBoundsGQ and GreedQuestDB.zoneBoundsGQ[mapID]
  if zq and zq.continent ~= nil then return tonumber(zq.continent) or 0 end
  local wma = GreedQuestDB and GreedQuestDB.worldMapArea and GreedQuestDB.worldMapArea[mapID]
  if wma and wma[1] ~= nil then return tonumber(wma[1]) or 0 end
  local parent = GreedQuestDB and GreedQuestDB.zoneParent and GreedQuestDB.zoneParent[mapID]
  if parent and parent ~= 0 and parent ~= mapID then
    return self:GetZoneContinent(parent)
  end
  local proxy = GreedQuestDB and GreedQuestDB.zoneProxy and GreedQuestDB.zoneProxy[mapID]
  if proxy and proxy ~= mapID then
    return self:GetZoneContinent(proxy)
  end
  if mapID >= 141 and mapID < 400 then return 1 end
  return 0
end


function Map:IsContinentView()
  if not GetCurrentMapZone then return false end
  local z = GetCurrentMapZone()
  return (not z or z == 0)
end

function Map:ZoneToContinentCoords(zoneID, x, y)
  -- Project zone-local 0-100 coords onto continent map.
  -- Preferred: Turtle WorldMapArea bounds (includes Balor, Gilneas, etc.)
  -- Fallback: parent chain, then older worldMapArea table.
  zoneID = tonumber(zoneID)
  x = tonumber(x) or 50
  y = tonumber(y) or 50

  local function projectBounds(z, contBounds, continentId)
    -- WorldMapArea extractor conversion:
    --   worldY = yMin + ((100-x)/100) * (yMax-yMin)
    --   worldX = xMin + ((100-y)/100) * (xMax-xMin)
    --   cx = 100 - ((worldY - c.yMin)/ch)*100
    --   cy = 100 - ((worldX - c.xMin)/cw)*100
    local zw = z.xMax - z.xMin
    local zh = z.yMax - z.yMin
    if zw == 0 or zh == 0 then return nil end
    local worldY = z.yMin + ((100 - x) / 100) * zh
    local worldX = z.xMin + ((100 - y) / 100) * zw
    local cw = contBounds.xMax - contBounds.xMin
    local ch = contBounds.yMax - contBounds.yMin
    if cw == 0 or ch == 0 then return nil end
    local contX = 100 - ((worldY - contBounds.yMin) / ch) * 100
    local contY = 100 - ((worldX - contBounds.xMin) / cw) * 100
    if contX < -5 or contX > 105 or contY < -5 or contY > 105 then
      return nil
    end
    -- wantCont: 1=Kalimdor, 2=EK (Blizzard GetCurrentMapContinent style for world fold)
    local wantCont = (continentId == 1) and 1 or 2
    return contX, contY, wantCont
  end

  -- 1) Compiled zone bounds (covers Turtle islands accurately)
  local zq = GreedQuestDB and GreedQuestDB.zoneBoundsGQ and GreedQuestDB.zoneBoundsGQ[zoneID]
  if zq then
    local cq = GreedQuestDB.continentBoundsGQ and GreedQuestDB.continentBoundsGQ[zq.continent]
    if cq then
      local cx, cy, wc = projectBounds(zq, cq, zq.continent)
      if cx then return cx, cy, wc end
    end
  end

  -- 2) Parent subzone → parent zone bounds
  local parent = GreedQuestDB and GreedQuestDB.zoneParent and GreedQuestDB.zoneParent[zoneID]
  if parent and parent ~= 0 and parent ~= zoneID then
    return self:ZoneToContinentCoords(parent, x, y)
  end

  -- 3) Legacy worldMapArea table (classic zones)
  local wma = GreedQuestDB and GreedQuestDB.worldMapArea and GreedQuestDB.worldMapArea[zoneID]
  if wma then
    -- wma = { mapId, zL, zR, zT, zB } in our packed form
    local mapId, zL, zR, zT, zB = wma[1], wma[2], wma[3], wma[4], wma[5]
    local contBounds = GreedQuestDB.continentBounds and GreedQuestDB.continentBounds[mapId]
    if contBounds then
      local z = { xMin = zL, xMax = zR, yMin = zT, yMax = zB }
      -- Our legacy pack uses a different axis convention; convert via existing math path
      local cL, cR, cT, cB = contBounds[1], contBounds[2], contBounds[3], contBounds[4]
      local xf = x / 100
      local yf = y / 100
      local worldX = zL + (zR - zL) * xf
      local worldY = zT + (zB - zT) * yf
      local contW = cL - cR
      local contH = cT - cB
      if contW ~= 0 and contH ~= 0 then
        local contX = (cL - worldX) / contW * 100
        local contY = (cT - worldY) / contH * 100
        local wantCont = (mapId == 0) and 2 or (mapId == 1) and 1 or 0
        if contX >= -5 and contX <= 105 and contY >= -5 and contY <= 105 then
          return contX, contY, wantCont
        end
      end
    end
  end

  -- 4) Explicit continent % override (last resort, approximate)
  local pos = GreedQuestDB and GreedQuestDB.zoneContinentPos and GreedQuestDB.zoneContinentPos[zoneID]
  if pos and pos.x and pos.y and pos.cont then
    local ox = (x - 50) * 0.12
    local oy = (y - 50) * 0.12
    return pos.x + ox, pos.y + oy, pos.cont
  end

  -- 5) Classic proxy
  local proxy = GreedQuestDB and GreedQuestDB.zoneProxy and GreedQuestDB.zoneProxy[zoneID]
  if proxy and proxy ~= zoneID then
    return self:ZoneToContinentCoords(proxy, 50, 50)
  end

  return nil
end


-- When zoomed fully out to the World map (both continents), fold continent % into world %
-- Vanilla/Turtle world map: Kalimdor left half, Eastern Kingdoms right half
-- Map continent-space coordinates onto the Turtle dual-continent world texture.
-- Continent maps are already correct using full contX/contY as frame %.
-- Land does NOT use cont 0-100; it sits in a sub-range. That sub-range is
-- stretched onto the world-map landmass box for each continent.
-- Continent → world mapping from user overlay calibration.
-- Method: continent map screenshots (1200x800) were scaled until landmass
-- art matched the world map, then measured:
--   World map capture: 1204 x 806
--   Kalimdor overlay:  974 x 662  → frame = 80.897% x 82.134% of world
--   EK overlay:       1040 x 660  → frame = 86.379% x 81.886% of world
-- Origins fitted so known coast points (Darkshore, Tirisfal/STV) land correctly.
--
-- worldX = originX + (contX/100) * scaleX
-- worldY = originY + (contY/100) * scaleY
local WORLD_FRAME = {
  -- [continent] = { originX, originY, scaleX, scaleY }  (all in world-map %)
  -- Origins nudged: Kalimdor +2% X, EK +4% X (user feedback 0.8.33)
  [1] = { -17.933, 6.201, 80.897, 82.134 },  -- Kalimdor
  [2] = {  34.000, 6.799, 86.150, 81.886 },  -- Eastern Kingdoms
}

function Map:ContinentToWorldCoords(wantCont, contX, contY)
  local f = WORLD_FRAME[wantCont]
  if not f or not contX or not contY then return nil end
  local wx = f[1] + (contX / 100) * f[3]
  local wy = f[2] + (contY / 100) * f[4]
  if wx < 0 then wx = 0 elseif wx > 100 then wx = 100 end
  if wy < 0 then wy = 0 elseif wy > 100 then wy = 100 end
  return wx, wy
end

function Map:ZoneToWorldCoords(zoneID, x, y)
  -- local → continent (correct on continent maps) → measured world land box
  local contX, contY, wantCont = self:ZoneToContinentCoords(zoneID, x, y)
  if not contX then return nil end
  return self:ContinentToWorldCoords(wantCont, contX, contY)
end


function Map:ZoneToDisplayedMapCoords(zoneID, x, y)
  local curCont = 0
  if GetCurrentMapContinent then
    curCont = GetCurrentMapContinent() or 0
  end
  local shownZone = nil
  if self.GetDisplayedZoneID then
    shownZone = self:GetDisplayedZoneID()
  end

  -- Zone map view only (never while the two-continent / continent map is up)
  if shownZone and zoneID and tonumber(shownZone) == tonumber(zoneID) then
    if not self:IsContinentView() then
      return tonumber(x), tonumber(y)
    end
  end

  local contX, contY, wantCont = self:ZoneToContinentCoords(zoneID, x, y)
  if not contX then
    -- No WorldMapArea data (custom zone) — only drawable on its own zone map
    return nil
  end

  -- World / cosmic view (both continents): project into the zone's world-map rect
  if not curCont or curCont == 0 or curCont == -1 then
    local wx, wy = self:ZoneToWorldCoords(zoneID, x, y)
    if wx then return wx, wy end
    -- Fallback if zone has no rect
    return self:ContinentToWorldCoords(wantCont, contX, contY)
  end
  -- Single continent view: only show pins that belong on this continent
  if curCont ~= wantCont then
    return nil
  end
  return contX, contY
end



-- Capitals / city maps painted onto the overworld zone they sit in.
-- City-local 0-100 is scaled into a small box so districts stay distinct.
Map.CITY_EMBEDS = {
  -- x,y = center of the city footprint on the PARENT zone map (0-100).
  -- box = how wide/tall that footprint is, so districts spread across it.
  [1519] = { -- Stormwind: large NW block on Elwynn
    { parent = 12,   x = 23, y = 29, box = 18 },
    { parent = 5581, x = 18, y = 20, box = 16 },
  },
  [4411] = { -- Harbor sits on the west edge of that same block
    { parent = 12,   x = 16, y = 26, box = 8 },
    { parent = 5581, x = 12, y = 16, box = 8 },
  },
  [1537] = { { parent = 1,   x = 53, y = 27, box = 14 } }, -- Ironforge, north Dun Morogh
  [1637] = { { parent = 14,  x = 46, y = 11, box = 14 } }, -- Orgrimmar, north Durotar
  [1638] = { { parent = 215, x = 37, y = 27, box = 12 } }, -- Thunder Bluff mesa
  -- Darnassus (1657) already has working Teldrassil coords — do not embed.
  [1497] = { { parent = 85,  x = 62, y = 69, box = 10 } }, -- Undercity, south Tirisfal
}

function Map:EmbedCityPoint(embed, x, y)
  local box = embed.box or 6
  local cx = tonumber(x) or 50
  local cy = tonumber(y) or 50
  local px = embed.x + (cx - 50) / 100 * box
  local py = embed.y + (cy - 50) / 100 * box
  if px < 1 then px = 1 end
  if px > 99 then px = 99 end
  if py < 1 then py = 1 end
  if py > 99 then py = 99 end
  return px, py
end

function Map:ForCityEmbedsOnZone(parentZone, fn)
  if not parentZone or not self.CITY_EMBEDS then return end
  local cityID, embeds
  for cityID, embeds in pairs(self.CITY_EMBEDS) do
    local i
    for i = 1, getn(embeds) do
      if embeds[i].parent == parentZone then
        fn(cityID, embeds[i])
      end
    end
  end
end

function Map:LookupZoneName(name)
  if not name or name == "" then return nil end
  if not self.zoneByName then self:ResolvePlayerZone() end
  local lower = string.lower(name)
  lower = string.gsub(lower, "%s+$", "")
  if self.zoneByName and self.zoneByName[lower] then
    return self.zoneByName[lower]
  end
  return nil
end

function Map:GetDisplayedZoneID()
  -- Resolve the zone the world map is showing.
  -- Returns nil on continent / cosmic view OR when the open zone is not in our DB
  -- (do NOT fall back to the player's real zone — that paints zone coords on the world map).
  if not self.zoneByName then
    self:ResolvePlayerZone()
  end

  if not GetCurrentMapZone or not GetMapZones or not GetCurrentMapContinent then
    return nil
  end

  local z = GetCurrentMapZone()
  local cont = GetCurrentMapContinent() or 0

  -- Cosmic / continent: zone index 0. Never use GetRealZoneText here.
  if not z or z == 0 then
    -- Instance detail maps also report zone 0, but the map TITLE is the dungeon.
    if cont <= 0 then
      local title
      if WorldMapFrameTitle and WorldMapFrameTitle.GetText then
        title = WorldMapFrameTitle:GetText()
      end
      local id = self:LookupZoneName(title)
      if id and GQ.Database and GQ.Database.IsDungeonZone and GQ.Database:IsDungeonZone(id) then
        return id
      end
    end
    return nil
  end
  if cont == 0 or cont == -1 then
    return nil
  end

  local names = { GetMapZones(cont) }
  local name = names[z]
  if not name or name == "" then
    return nil
  end
  local lower = string.lower(name)
  -- strip trailing spaces (Turtle typo zones like "Northwind ")
  lower = string.gsub(lower, "%s+$", "")

  if self.zoneByName and self.zoneByName[lower] then
    return self.zoneByName[lower]
  end
  -- exact-ish fuzzy: name contained in DB name or vice versa
  if self.zoneByName then
    for n, id in pairs(self.zoneByName) do
      if n == lower then return id end
    end
    for n, id in pairs(self.zoneByName) do
      if string.find(n, lower, 1, true) or string.find(lower, n, 1, true) then
        return id
      end
    end
  end
  -- Unknown custom zone: no ID — caller must not draw player-zone pins
  return nil
end

function Map:IsNodeOnDisplayedMap(node)
  if not node or not node.mapID then return false end
  local shown = self:GetDisplayedZoneID()
  if not shown then
    return false
  end
  return node.mapID == shown
end

function Map:IsQuestHidden(qid, title)
  if not GreedQuestCharDB or not GreedQuestCharDB.hiddenQuests then return false end
  if qid and GreedQuestCharDB.hiddenQuests["id:" .. tostring(qid)] then return true end
  if title and GreedQuestCharDB.hiddenQuests["t:" .. string.lower(title)] then return true end
  return false
end

function Map:ToggleHideQuest(qid, title)
  if not GreedQuestCharDB then GreedQuestCharDB = {} end
  if not GreedQuestCharDB.hiddenQuests then GreedQuestCharDB.hiddenQuests = {} end
  local key = qid and ("id:" .. tostring(qid)) or ("t:" .. string.lower(title or ""))
  if GreedQuestCharDB.hiddenQuests[key] then
    GreedQuestCharDB.hiddenQuests[key] = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: Unhid quest " .. (title or key))
  else
    GreedQuestCharDB.hiddenQuests[key] = 1
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: Hidden quest " .. (title or key) .. " (Alt-click pin again to unhide)")
  end
  if GQ.Core and GQ.Core.NotifyFiltersChanged then
    GQ.Core:NotifyFiltersChanged()
  end
  self:BuildNodesFromQuestLog()
end

function Map:PositionWorldPin(pin, x, y)
  -- Always anchor to the painted map (DetailFrame). Fall back to Button.
  local anchor = WorldMapDetailFrame or WorldMapButton or WorldMapFrame
  if not anchor then return end
  local nx = (x or 0) / 100
  local ny = (y or 0) / 100
  local w = anchor:GetWidth() or 1002
  local h = anchor:GetHeight() or 668
  if w < 10 then w = 1002 end
  if h < 10 then h = 668 end
  local px = nx * w
  local py = -ny * h
  pin:ClearAllPoints()
  pin:SetParent(anchor)
  pin:EnableMouse(true)
  if pin.SetFrameStrata then pin:SetFrameStrata("TOOLTIP") end
  pin:SetFrameLevel((anchor.GetFrameLevel and anchor:GetFrameLevel() or 10) + 20)
  pin:SetPoint("CENTER", anchor, "TOPLEFT", px, py)
  pin:Show()
end

-- Outdoor/indoor zoom yards by Minimap:GetZoom() level
local MINI_ZOOM_OUTDOOR = {
  [0] = 466 + 2/3,
  [1] = 400,
  [2] = 333 + 1/3,
  [3] = 266 + 2/6,
  [4] = 200,
  [5] = 133 + 1/3,
}
local MINI_ZOOM_INDOOR = {
  [0] = 300,
  [1] = 240,
  [2] = 180,
  [3] = 120,
  [4] = 80,
  [5] = 50,
}

-- Indoor zoom detect. Do not call SetZoom (it blurs Blizzard party arrows).
-- When CVars are equal / unknown, assume outdoor so pins use the wider range.
local _indoorCache, _indoorZoom, _indoorAt = nil, nil, 0
local function MinimapIsIndoor()
  local z = 0
  if Minimap and Minimap.GetZoom then z = Minimap:GetZoom() or 0 end
  local now = GetTime and GetTime() or 0
  if _indoorCache ~= nil and _indoorZoom == z and (now - _indoorAt) < 2.0 then
    return _indoorCache
  end
  local inside = false
  if GetCVar then
    local curZoom = tonumber(GetCVar("minimapZoom"))
    local curInside = tonumber(GetCVar("minimapInsideZoom"))
    if curZoom and curInside and curZoom ~= curInside then
      inside = (curInside == z)
    end
  end
  _indoorCache = inside and 0 or 1
  _indoorZoom = z
  _indoorAt = now
  return _indoorCache
end

function Map:GetMiniLayout()
  local pxf, pyf = GetPlayerMapPositionSafe()
  if not pxf or not pyf or (pxf == 0 and pyf == 0) then
    return nil
  end
  local mapID = self.playerZoneID
  local sizes = GreedQuestDB and GreedQuestDB.minimapSizes
  local dims = mapID and sizes and sizes[mapID]
  local mapWidth, mapHeight
  if dims and dims[1] and dims[1] ~= 0 and dims[2] and dims[2] ~= 0 then
    mapWidth, mapHeight = dims[1], dims[2]
  else
    mapWidth, mapHeight = 2000, 1330
  end
  local mZoom = 0
  if Minimap and Minimap.GetZoom then
    mZoom = Minimap:GetZoom() or 0
  end
  local indoor = MinimapIsIndoor()
  local zoomTbl = (indoor == 0) and MINI_ZOOM_INDOOR or MINI_ZOOM_OUTDOOR
  local mapZoom = zoomTbl[mZoom] or zoomTbl[0]
  local mw = Minimap:GetWidth() or 140
  local mh = Minimap:GetHeight() or 140
  -- DFUI and similar skins can report a stretched frame. Keep the
  -- layout on the visible circle or pins run off the gold rim.
  if mw < 80 or mw > 200 then mw = 140 end
  if mh < 80 or mh > 200 then mh = 140 end
  local xScale = mapZoom / mapWidth
  local yScale = mapZoom / mapHeight
  local radius = math.min(mw, mh) / 2
  return {
    xPlayer = pxf * 100,
    yPlayer = pyf * 100,
    xDraw = mw / xScale / 100,
    yDraw = mh / yScale / 100,
    maxR2 = (radius * 0.98) * (radius * 0.98),
    pxf = pxf,
    pyf = pyf,
    zoom = mZoom,
  }
end

function Map:PositionMiniPin(pin, x, y, layout)
  layout = layout or self:GetMiniLayout()
  if not layout then
    pin:Hide()
    return false
  end
  local xPos = ((x or 0) - layout.xPlayer) * layout.xDraw
  local yPos = ((y or 0) - layout.yPlayer) * layout.yDraw
  if (xPos * xPos + yPos * yPos) > layout.maxR2 then
    pin:Hide()
    return false
  end
  if pin._gqMiniParent ~= Minimap then
    pin:SetParent(Minimap)
    pin._gqMiniParent = Minimap
    pin:EnableMouse(true)
    pin:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 2) + 8)
  end
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", Minimap, "CENTER", xPos, -yPos)
  if not pin:IsShown() then pin:Show() end
  return true
end



-- ============================================================
-- Pin updates: world and minimap are independent
-- ============================================================

function Map:RequestPinUpdate()
  -- Full node rebuild already done by caller; just draw
  if self._pinUpdateQueued then return end
  self._pinUpdateQueued = true
  if not self._coalesceFrame then
    self._coalesceFrame = CreateFrame("Frame")
  end
  self._coalesceFrame:SetScript("OnUpdate", function()
    Map._pinUpdateQueued = false
    Map._coalesceFrame:SetScript("OnUpdate", nil)
    Map:DrawAllPins()
  end)
end

function Map:RequestMiniReposition()
  if self._miniOnlyQueued then return end
  self._miniOnlyQueued = true
  if not self._miniFrame then
    self._miniFrame = CreateFrame("Frame")
  end
  self._miniFrame:SetScript("OnUpdate", function()
    Map._miniOnlyQueued = false
    Map._miniFrame:SetScript("OnUpdate", nil)
    Map:UpdateMinimapPins()
  end)
end

function Map:MarkClustersDirty()
  self._clustersDirty = true
  self._miniNeedsFull = true
end

function Map:EnsureClusters()
  local hasNodes = false
  if self.nodes then
    for _, list in pairs(self.nodes) do
      if list and getn(list) > 0 then hasNodes = true break end
    end
  end
  local clusterCount = 0
  if self.clusters then
    for _, list in pairs(self.clusters) do
      if list then clusterCount = clusterCount + getn(list) end
    end
  end
  if self._clustersDirty or (hasNodes and clusterCount == 0) then
    self:RebuildClusters()
    self._clustersDirty = false
  end
end

-- Draw both layers from current node data (does NOT clear node data)
function Map:DrawAllPins()
  self:EnsureClusters()
  self:UpdateWorldPins()
  self:UpdateMinimapPins()
end

-- Back-compat name used across the addon
function Map:UpdatePins()
  self:DrawAllPins()
end

-- WORLD MAP ONLY — never touches minimap pins

-- When showAllOnContinent is off, only show available pins that are "near" the player
-- (same continent) and cap total available markers for performance.
function Map:ContinentAvailableAllowed(mapID, typ)
  if typ ~= "Available" then return true end
  local cfg = GreedQuestConfig and GreedQuestConfig.map
  if cfg and cfg.showAllOnContinent then return true end
  -- Always allow turn-ins and objectives of active quests (typ ~= Available already true)
  local playerCont = 0
  if GetCurrentMapContinent then
    playerCont = GetCurrentMapContinent() or 0
  end
  -- Normalize: GetCurrentMapContinent uses 1=Kalimdor, 2=EK
  -- GetZoneContinent uses 1=Kalimdor, 0=EK
  local playerZc = nil
  if playerCont == 1 then playerZc = 1
  elseif playerCont == 2 then playerZc = 0
  end
  local zc = 0
  if self.GetZoneContinent then
    zc = self:GetZoneContinent(mapID) or 0
  end
  if playerZc ~= nil and zc ~= playerZc then
    return false
  end
  return true
end

function Map:UpdateWorldPins()
  local mapOpen = WorldMapFrame and (WorldMapFrame:IsVisible() or WorldMapFrame:IsShown())
  if not mapOpen then return end
  local curCont = 0
  if GetCurrentMapContinent then curCont = GetCurrentMapContinent() or 0 end
  local curZone = 0
  if GetCurrentMapZone then curZone = GetCurrentMapZone() or 0 end
  local paintKey = tostring(curCont) .. ":" .. tostring(curZone)
    .. ":" .. tostring(self:GetDisplayedZoneID() or "?")
    .. ":" .. tostring(self._nodeRev or 0)
    .. ":" .. tostring((GreedQuestConfig.map and GreedQuestConfig.map.iconStyle) or "")
  if self._worldPaintKey == paintKey and self._worldPaintDone then
    return
  end
  self._worldPaintKey = paintKey
  self._worldPaintDone = false

  self:EnsureWorldPool()
  self:EnsureClusters()
  self:RefreshQuestMarkers()

  for _, pin in ipairs(self.worldPins) do
    pin:Hide()
    if pin.badge then pin.badge:Hide() end
    if pin.badgeText then pin.badgeText:Hide() end
    if pin.numText then pin.numText:Hide() end
    if pin.centerDot then pin.centerDot:Hide() end
    if pin.backdrop then pin.backdrop:Hide() end
    if pin.outline then pin.outline:Hide() end
  end

  if self.HideBlizzardQuestPOIs then self:HideBlizzardQuestPOIs() end
  if not GreedQuestConfig or not GreedQuestConfig.map then return end

  if self.UpdatePathLines then
    self:UpdatePathLines()
  end

  local continent = self:IsContinentView()
  local shownZone = self:GetDisplayedZoneID()
  if not continent and not shownZone then
    return
  end

  local worldIndex = 1
  local cfgMap = GreedQuestConfig.map
  local pinAlpha = (cfgMap.pinAlpha) or 1
  local iconStyle = cfgMap.iconStyle or "native"
  -- Separate sizes for world / continent / zone views
  local baseSize
  if continent then
    local curCont = 0
    if GetCurrentMapContinent then curCont = GetCurrentMapContinent() or 0 end
    if not curCont or curCont == 0 or curCont == -1 then
      baseSize = cfgMap.worldPinSize or 9
    else
      baseSize = cfgMap.continentPinSize or 10
    end
  else
    baseSize = cfgMap.zonePinSize or 12
  end
  -- Objective dots stay half size; available / turn-in keep icon size

  local function paint(node, px, py)
    if worldIndex > getn(self.worldPins) then
      self:EnsureWorldPool(worldIndex + 32)
    end
    local pin = self.worldPins[worldIndex]
    if not pin then return end
    pin.node = node
    pin:EnableMouse(true)
    if pin.SetFrameStrata then pin:SetFrameStrata("HIGH") end
    if pin.SetFrameLevel then
      local parent = pin:GetParent()
      local boost = 40
      if node.typ == "Turn In" then
        boost = 58
      elseif self:IsSingleObjectiveQuest(node) then
        boost = 52
      elseif node.typ == "Available" or node.typ == "Quest Giver" then
        boost = 32
      end
      pin:SetFrameLevel((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 10) + boost)
    end
    pin:SetScript("OnEnter", function()
      this._gqHover = 1
      this._gqShift = IsShiftKeyDown() and 1 or 0
      this._gqCtrl = IsControlKeyDown() and 1 or 0
      Map:ShowPinTooltip(this)
    end)
    pin:SetScript("OnUpdate", function()
      if not this._gqHover then return end
      local s = IsShiftKeyDown() and 1 or 0
      local c = IsControlKeyDown() and 1 or 0
      if s ~= this._gqShift or c ~= this._gqCtrl then
        this._gqShift = s
        this._gqCtrl = c
        Map:ShowPinTooltip(this)
      end
    end)
    pin:SetScript("OnLeave", function()
      this._gqHover = nil
      GameTooltip:Hide()
      if WorldMapTooltip then WorldMapTooltip:Hide() end
    end)
    pin:SetScript("OnMouseUp", function()
      Map:OnPinClick(this)
    end)
    if pin.texture then
      local tex, r, g, b = self:ResolvePinVisual(node.typ, node.grey, node)
      if node.source == "tracking" and node.texture then
        tex = node.texture
        r, g, b = 1, 1, 1
      end
      local primary = tex or node.texture
      if node.source == "tracking" then
        self:SetTextureWithFallback(pin.texture, primary, primary)
      else
        pin.texture:SetTexture(primary)
      end
      local special = false
      if (node.typ == "Available" or node.typ == "Quest Giver") then
        if not (math.abs((r or 1) - 1) < 0.01 and math.abs((g or 1) - 1) < 0.01 and math.abs((b or 1) - 1) < 0.01) then
          special = true
        end
        if (GreedQuestConfig.map.iconStyle or "native") == "dots" then
          local ar = GreedQuestConfig.map.dotAvailR or 1
          local ag = GreedQuestConfig.map.dotAvailG or 0.85
          if math.abs((r or 1) - ar) < 0.02 and math.abs((g or 1) - ag) < 0.02 then
            special = false
          end
        end
      end
      self:ApplyPinTextureTint(pin.texture, r, g, b, node.typ, special)
    end
    local drawSize = baseSize
    if iconStyle == "dots" then
      local typ = node.typ or ""
      if typ ~= "Available" and typ ~= "Quest Giver" and typ ~= "Turn In" then
        drawSize = math.max(3, math.floor(baseSize * 0.5))
      end
    end
    drawSize = self:AdjustPinDrawSize(drawSize, node)
    if pin.texture and pin.texture.GetTexture then
      local tp = pin.texture:GetTexture() or ""
      if string.find(string.lower(tostring(tp)), "media\\dot") or string.find(string.lower(tostring(tp)), "media/dot") then
        if (GreedQuestConfig.map.iconStyle or "native") ~= "dots" then
          drawSize = math.max(4, math.floor(baseSize * 0.5))
        end
      end
    end
    pin:SetWidth(drawSize)
    pin:SetHeight(drawSize)
    pin:SetAlpha(pinAlpha)
    -- Simple black silhouette behind the pin (+2px)
    local texPath = nil
    if pin.texture and pin.texture.GetTexture then
      texPath = pin.texture:GetTexture()
    end
    if pin.backdrop then
      local backSize = drawSize + 2
      if texPath then pin.backdrop:SetTexture(texPath) end
      pin.backdrop:ClearAllPoints()
      pin.backdrop:SetPoint("CENTER", pin, "CENTER", 0, 0)
      pin.backdrop:SetWidth(backSize)
      pin.backdrop:SetHeight(backSize)
      pin.backdrop:SetVertexColor(0, 0, 0, 1)
      pin.backdrop:Show()
    end
    if pin.outline then pin.outline:Hide() end
    if pin.centerDot then pin.centerDot:Hide() end
    if pin.shadow then pin.shadow:Hide() end
    if pin.shadows then
      for _, sh in ipairs(pin.shadows) do sh:Hide() end
    end
    if pin.glow then pin.glow:Hide() end
    self:ApplyQuestMarker(pin, node, drawSize)

    self:PositionWorldPin(pin, px, py)
    pin:Show()
    worldIndex = worldIndex + 1
  end

  if continent then
    -- Available + turn-in only, projected to continent OR full world map
    -- Prioritize current player zone's pins first
    local priorityZone = self.playerZoneID
    local function paintList(mapID, list)
      for _, node in ipairs(list) do
        local typ = node.typ or ""
        if typ == "Available" or typ == "Turn In" then
          if self:ContinentAvailableAllowed(mapID, typ) then
            local cx, cy = self:ZoneToDisplayedMapCoords(mapID, node.x, node.y)
            if cx and cy then
              paint(node, cx, cy)
            end
          end
        end
      end
    end
    if priorityZone and self.clusters[priorityZone] then
      paintList(priorityZone, self.clusters[priorityZone])
    end
    for mapID, list in pairs(self.clusters) do
      if not priorityZone or mapID ~= priorityZone then
        paintList(mapID, list)
      end
    end
  else
    local list = self.clusters[shownZone]
    if list then
      for _, node in ipairs(list) do
        paint(node, node.x, node.y)
      end
    end
    -- Cities that sit inside this zone (Stormwind on Elwynn, etc.)
    if self.ForCityEmbedsOnZone then
      self:ForCityEmbedsOnZone(shownZone, function(cityID, embed)
        local clist = self.clusters[cityID]
        if not clist then return end
        local _, node
        for _, node in ipairs(clist) do
          local px, py = self:EmbedCityPoint(embed, node.x, node.y)
          paint(node, px, py)
        end
      end)
    end
  end
  self._worldPaintDone = true
end

-- MINIMAP ONLY — independent of world map open/closed
-- Only recalculates when player pos / zoom actually changed (anti-jitter)
function Map:UpdateMinimapPins()
  self:EnsureMiniPool()
  self:EnsureClusters()
  self:RefreshQuestMarkers()

  if not GreedQuestConfig or not GreedQuestConfig.map then return end
  if not Minimap then return end

  local playerZoneID = self.playerZoneID
  if not playerZoneID then
    for _, pin in ipairs(self.miniPins) do
      pin:Hide()
      pin.node = nil
    end
    return
  end

  -- Full rebuild only when nodes / zone / style changed. Movement uses RepositionMiniPinsOnly.
  if not self._miniNeedsFull then
    self:RepositionMiniPinsOnly()
    return
  end
  self._miniNeedsFull = false

  local list = self.clusters[playerZoneID]
  if not list then
    local hi
    for hi = 1, getn(self.miniPins) do
      local p = self.miniPins[hi]
      if p then p.node = nil p:Hide() end
    end
    return
  end

  local miniSize = (GreedQuestConfig.map.miniPinSize) or 10
  local miniDots = (GreedQuestConfig.map.iconStyle or "native") == "dots"
  local pinAlpha = (GreedQuestConfig.map.pinAlpha) or 1

  local layout = self:GetMiniLayout()
  if layout then
    self._lastMiniAssignX = layout.pxf
    self._lastMiniAssignY = layout.pyf
  end
  local miniIndex = 1
  for _, node in ipairs(list) do
    if miniIndex > getn(self.miniPins) then
      self:EnsureMiniPool(miniIndex + 32)
    end
    local pin = self.miniPins[miniIndex]
    if pin then
      local nx = tonumber(node.x) or node.x
      local ny = tonumber(node.y) or node.y
      pin.node = node
      pin:EnableMouse(true)
      if pin.texture then
        local tex, r, g, b = self:ResolvePinVisual(node.typ, node.grey, node)
        if node.source == "tracking" and node.texture then
          tex = node.texture
          r, g, b = 1, 1, 1
        end
        local primary = tex or node.texture
        if node.source == "tracking" then
          self:SetTextureWithFallback(pin.texture, primary, primary)
        else
          pin.texture:SetTexture(primary)
        end
        local special = false
        if (node.typ == "Available" or node.typ == "Quest Giver") then
          if not (math.abs((r or 1) - 1) < 0.01 and math.abs((g or 1) - 1) < 0.01 and math.abs((b or 1) - 1) < 0.01) then
            special = true
          end
        end
        self:ApplyPinTextureTint(pin.texture, r, g, b, node.typ, special)
      end
      -- Per-pin half size when this node is a circular dot under mixed native mode
      local size = miniSize
      if miniDots then
        local typ = node.typ or ""
        if typ ~= "Available" and typ ~= "Quest Giver" and typ ~= "Turn In" then
          size = math.max(3, math.floor(miniSize * 0.5))
        end
      end
      size = self:AdjustPinDrawSize(size, node)
      if pin.texture and pin.texture.GetTexture then
        local tp = tostring(pin.texture:GetTexture() or "")
        if string.find(string.lower(tp), "media\\dot") or string.find(string.lower(tp), "media/dot") then
          if (GreedQuestConfig.map.iconStyle or "native") ~= "dots" then
            size = math.max(3, math.floor(size * 0.5))
          end
        end
      end
      pin:SetWidth(size)
      pin:SetHeight(size)
      pin:SetAlpha(pinAlpha)
      self:ApplyQuestMarker(pin, node, size)
      self:PositionMiniPin(pin, nx, ny, layout)
      miniIndex = miniIndex + 1
    end
  end
  if self.ForCityEmbedsOnZone then
    self:ForCityEmbedsOnZone(playerZoneID, function(cityID, embed)
      local clist = self.clusters[cityID]
      if not clist then return end
      local _, node
      for _, node in ipairs(clist) do
        if miniIndex > getn(self.miniPins) then
          self:EnsureMiniPool(miniIndex + 32)
        end
        local pin = self.miniPins[miniIndex]
        if pin then
          local px, py = self:EmbedCityPoint(embed, node.x, node.y)
          local copy = {}
          local k, v
          for k, v in pairs(node) do copy[k] = v end
          copy.x = px
          copy.y = py
          copy.mapID = playerZoneID
          pin.node = copy
          pin:EnableMouse(true)
          if pin.texture then
            local tex, r, g, b = self:ResolvePinVisual(node.typ, node.grey, node)
            local primary = tex or node.texture
            pin.texture:SetTexture(primary)
            self:ApplyPinTextureTint(pin.texture, r, g, b, node.typ, false)
          end
          local size = miniSize
          if miniDots then
            local typ = node.typ or ""
            if typ ~= "Available" and typ ~= "Quest Giver" and typ ~= "Turn In" then
              size = math.max(3, math.floor(miniSize * 0.5))
            end
          end
          size = self:AdjustPinDrawSize(size, node)
          pin:SetWidth(size)
          pin:SetHeight(size)
          pin:SetAlpha(pinAlpha)
          self:ApplyQuestMarker(pin, copy, size)
          self:PositionMiniPin(pin, px, py, layout)
          miniIndex = miniIndex + 1
        end
      end
    end)
  end
  local rest
  for rest = miniIndex, getn(self.miniPins) do
    local p = self.miniPins[rest]
    if p then
      p.node = nil
      p:Hide()
    end
  end
end

-- Lightweight: only shift existing visible minimap pins (movement)
function Map:RepositionMiniPinsOnly()
  if not self.miniPins then return end
  local layout = self:GetMiniLayout()
  if not layout then return end
  -- Skip tiny steps so pins do not twitch from GetPlayerMapPosition noise
  if self._lastMiniX and self._lastMiniZoom == layout.zoom then
    local dx = layout.pxf - self._lastMiniX
    local dy = layout.pyf - (self._lastMiniY or 0)
    if (dx * dx + dy * dy) < 0.00000004 then
      return
    end
  end
  self._lastMiniX = layout.pxf
  self._lastMiniY = layout.pyf
  self._lastMiniZoom = layout.zoom

  local i
  for i = 1, getn(self.miniPins) do
    local pin = self.miniPins[i]
    local n = pin and pin.node
    if n then
      self:PositionMiniPin(pin, tonumber(n.x) or n.x, tonumber(n.y) or n.y, layout)
    end
  end
end

function Map:BuildNodesFromQuestLog()
  self._nodeRev = (self._nodeRev or 0) + 1
  self._buildGen = (self._buildGen or 0) + 1
  local gen = self._buildGen
  self._worldPaintKey = nil
  self:ClearNodes("questlog")
  self:ClearNodes("available")

  if not (GQ.Database and GQ.Database:IsReady()) then return end
  if not GreedQuestConfig or not GreedQuestConfig.map then return end
  local cfg = GreedQuestConfig.map

  local DB = GQ.Database
  if not DB then return end

  local log = (GQ.Core and GQ.Core.questLog) or {}

  local zoneOnly = GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.currentZoneOnly

  local pinned = 0
  for _, q in pairs(log) do
    local qid = q.questID
    if (not qid) and q.title and GQ.Core and GQ.Core.ResolveQuestID then
      qid = GQ.Core:ResolveQuestID(q.title)
      q.questID = qid
    end
    if qid then
      local skip = false
      if self:IsQuestHidden(qid, q.title) then skip = true end
      if GQ.Core and GQ.Core.IsTrackedInLog and not GQ.Core:IsTrackedInLog(q) then skip = true end
      if GQ.Core and GQ.Core.ShouldHideQuest and GQ.Core:ShouldHideQuest(q) then skip = true end
      if zoneOnly and GQ.Core and GQ.Core.QuestInCurrentZone and not GQ.Core:QuestInCurrentZone(q) then skip = true end
      if not skip then
        if cfg.showObjectives or cfg.showGivers or cfg.showTurnins then
          local qdata = DB:GetQuest(qid)
          if qdata then
            if gen ~= self._buildGen then return end
            self:AddQuestNodes(qid, qdata, q.title, q.complete)
            pinned = pinned + 1
          else
            GQ:Debug("No qdata for", qid, q.title)
          end
        end
      end
    else
      GQ:Debug("Unresolved quest title:", q.title)
    end
  end
  GQ:Debug("Map pinned quests from log:", pinned)

  self:BuildAvailableNodes()
  if GQ.Tracking and GQ.Tracking.BuildNodes then
    GQ.Tracking:BuildNodes()
  end
  self._miniNeedsFull = true
  self:DrawAllPins()
end

function Map:BuildAvailableNodes()
  local DB = GQ.Database
  if not DB then return end
  if not GreedQuestConfig or not GreedQuestConfig.map or not GreedQuestConfig.map.showGivers then
    return
  end
  if not GQ.Core or not GQ.Core.GetAvailableQuests then return end

  local available = GQ.Core:GetAvailableQuests()
  local tex = self.ICON.available
  local pLevel = UnitLevel("player") or 1

  for _, aq in ipairs(available) do
    local qdata = aq.qdata
    local qid = aq.questID
    local hide = false
    if GQ.Core and GQ.Core.ShouldHideQuest then
      hide = GQ.Core:ShouldHideQuest({
        questID = qid,
        title = aq.title,
        tag = aq.tag,
        level = aq.level or (qdata and (qdata["lvl"] or qdata["min"])),
      })
    end
    if qdata and not hide and not self:IsQuestHidden(qid, aq.title) and qdata["start"] then
      local minL = tonumber(qdata["min"])
      local qlvl = tonumber(qdata["lvl"])
      local levelOk = true
      -- Must be high enough to accept
      if minL and minL > pLevel then levelOk = false end
      -- Grey low-level filter only when option enabled (ShouldHideQuest also covers this)
      if levelOk and GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.hideLowLevel then
        if GQ.Core and GQ.Core.IsLowLevelQuest and GQ.Core:IsLowLevelQuest(qlvl or minL) then
          levelOk = false
        end
      end
      if levelOk then
        local title = aq.title or (GreedQuestDB.questTitles and GreedQuestDB.questTitles[qid]) or ("Quest " .. tostring(qid))
        local function place(id, isUnit)
          local entry = isUnit and DB:GetUnit(id) or DB:GetObject(id)
          if not entry or not entry.coords then return end
          -- Skip opposite-faction givers
          if entry.fac and entry.fac ~= "" and entry.fac ~= "AH" then
            local pf = GQ.Core and GQ.Core.GetPlayerFactionCode and GQ.Core:GetPlayerFactionCode()
            if pf and entry.fac ~= pf then return end
          end
          for _, c in ipairs(entry.coords) do
            local x, y, zone = c[1], c[2], c[3]
            if zone and zone > 0 and x and y then
              self:AddNode({
                mapID   = zone,
                x       = x,
                y       = y,
                title   = title,
                quest   = title,
                texture = tex,
                layer   = self.LAYER.giver,
                questID = qid,
                typ     = "Available",
                source  = "available",
                level   = aq.level or qlvl,
                entityId = id,
                isUnit = isUnit and true or false,
              })
            end
          end
        end
        if qdata["start"]["U"] then
          for _, uid in pairs(qdata["start"]["U"]) do
            place(uid, true)
          end
        end
        if qdata["start"]["O"] then
          for _, oid in pairs(qdata["start"]["O"]) do
            place(oid, false)
          end
        end
      end
    end
  end
end

function Map:AddQuestNodes(qid, qdata, title, isComplete)
  local cfg = GreedQuestConfig.map
  local DB = GQ.Database

  local logQuest = GQ.Core and GQ.Core.GetQuestByID and GQ.Core:GetQuestByID(qid)

  local function EntityFinished(entityName, typ)
    if not logQuest or not logQuest.objectives or not entityName or entityName == "" then
      return false
    end
    local nl = string.lower(entityName)
    local oi
    for oi = 1, getn(logQuest.objectives) do
      local o = logQuest.objectives[oi]
      if o and o.finished and o.text then
        if string.find(string.lower(o.text), nl, 1, true) then
          return true
        end
      end
    end
    return false
  end

  local function EventObjectiveDone()
    if not logQuest or not logQuest.objectives then return false end
    local oi
    for oi = 1, getn(logQuest.objectives) do
      local o = logQuest.objectives[oi]
      if o and o.finished then
        local ot = string.lower(o.type or "")
        if ot == "event" then return true end
      end
    end
    return false
  end

  local function placeEntity(id, isUnit, texture, layer, typ, grey, extra)
    extra = extra or {}
    local entityName
    if isUnit and GreedQuestDB and GreedQuestDB.unitNames then
      entityName = GreedQuestDB.unitNames[id]
    end
    if typ ~= "Turn In" and typ ~= "Available" then
      if EntityFinished(entityName, typ) then return end
      if extra.itemName and EntityFinished(extra.itemName, typ) then return end
      if typ == "Object" and EventObjectiveDone() and not entityName then
        return
      end
    end
    if isUnit then
      self:LoadPathsForUnit(id, title)
    end
    local entry = isUnit and DB:GetUnit(id) or DB:GetObject(id)
    if not entry then return end
    if isUnit and entry["lvl"] and not extra.mobLevel then
      extra.mobLevel = entry["lvl"]
    end
    if not extra.level and logQuest then
      extra.level = logQuest.level
    end
    local coords = entry.coords
    if not coords then return end

    for _, c in ipairs(coords) do
      local x, y, zone = c[1], c[2], c[3]
      if zone and zone > 0 and x and y then
        local turninName, turninID
        if typ == "Turn In" and isUnit then
          turninID = id
          if GreedQuestDB and GreedQuestDB.unitNames then
            turninName = GreedQuestDB.unitNames[id]
          end
        end
        local turninZone
        if typ == "Turn In" and GreedQuestDB and GreedQuestDB.zones then
          turninZone = GreedQuestDB.zones[zone]
        end
        local entityName
        if isUnit and GreedQuestDB and GreedQuestDB.unitNames then
          entityName = GreedQuestDB.unitNames[id]
        end
        self:AddNode({
          mapID   = zone,
          x       = x,
          y       = y,
          title   = title or ("Quest "..qid),
          texture = texture,
          layer   = layer,
          quest   = title,
          questID = qid,
          typ     = typ,
          source  = "questlog",
          grey    = grey,
          turninID = turninID,
          turninName = turninName,
          turninZone = turninZone,
          entityId = id,
          entityName = entityName,
          isUnit = isUnit and true or false,
          itemID = extra.itemID,
          itemName = extra.itemName,
          dropChance = extra.dropChance,
          talkTo = extra.talkTo,
          level = extra.level,
          mobLevel = extra.mobLevel,
        })
      end
    end
  end

  -- In-progress: do NOT show available "!" at giver. Show "?" at turn-in.
  -- Grey "?" while incomplete; normal yellow "?" when complete (ready to turn in).
  local function IsTalkQuest()
    if isComplete then return false end
    if logQuest and logQuest.objectives then
      local oi, anyKillLoot = 1, false
      local anyTalk = false
      for oi = 1, getn(logQuest.objectives) do
        local o = logQuest.objectives[oi]
        if o then
          local ot = string.lower(o.type or "")
          local tx = string.lower(o.text or "")
          if ot == "monster" or ot == "mob" or ot == "item" or ot == "object" then
            anyKillLoot = true
          end
          if ot == "event" or string.find(tx, "talk to", 1, true) or string.find(tx, "speak with", 1, true) then
            anyTalk = true
          end
        end
      end
      if anyTalk and not anyKillLoot then return true end
      if getn(logQuest.objectives) == 0 then return true end
    end
    if qdata and qdata["obj"] then
      if qdata["obj"]["U"] or qdata["obj"]["I"] or qdata["obj"]["O"] then
        return false
      end
    end
    return true
  end

  if cfg.showTurnins and qdata["end"] then
    local tex = self.ICON.turnin or self.ICON.complete
    local grey = not isComplete
    local talkTo = IsTalkQuest()
    if qdata["end"]["U"] then
      local placed = false
      local _, uid
      for _, uid in pairs(qdata["end"]["U"]) do
        local u = DB:GetUnit(uid)
        if u and GQ.Core and GQ.Core.UnitFactionOk and not GQ.Core:UnitFactionOk(u) then
          -- skip opposite-faction turn-in NPC
        else
          placeEntity(uid, true, tex, self.LAYER.turnin, "Turn In", grey, { talkTo = talkTo })
          placed = true
        end
      end
      -- If every end NPC was opposite faction, fall back to all (neutral data gaps)
      if not placed then
        for _, uid in pairs(qdata["end"]["U"]) do
          placeEntity(uid, true, tex, self.LAYER.turnin, "Turn In", grey, { talkTo = talkTo })
        end
      end
    end
    if qdata["end"]["O"] then
      for _, oid in pairs(qdata["end"]["O"]) do
        placeEntity(oid, false, tex, self.LAYER.turnin, "Turn In", grey, { talkTo = talkTo })
      end
    end
  end

  -- Once the quest is complete (ready to turn in), hide all objective pins;
  -- only the turn-in "?" should remain.
  if cfg.showObjectives and qdata["obj"] and not isComplete then
    -- Kill / talk NPCs
    if qdata["obj"]["U"] then
      for _, uid in pairs(qdata["obj"]["U"]) do
        placeEntity(uid, true, self.ICON.kill, self.LAYER.objective, "Kill")
      end
    end
    -- World objects to interact with
    if qdata["obj"]["O"] then
      for _, oid in pairs(qdata["obj"]["O"]) do
        placeEntity(oid, false, self.ICON.object, self.LAYER.objective, "Object")
      end
    end
    -- Explore / scout area triggers (Jasperlode, Fargodeep, etc.)
    local aids = qdata["obj"]["A"]
    if not aids and GreedQuestDB and GreedQuestDB.questAreatriggers then
      aids = GreedQuestDB.questAreatriggers[qid]
    end
    if aids and not EventObjectiveDone() then
      local ai, aid
      for ai = 1, getn(aids) do
        aid = aids[ai]
        local at = DB:GetAreatrigger(aid)
        if at and at.coords then
          local _, c
          for _, c in ipairs(at.coords) do
            local x, y, zone = c[1], c[2], c[3]
            if zone and zone > 0 and x and y then
              self:AddNode({
                mapID = zone, x = x, y = y,
                title = title or ("Quest "..qid),
                texture = self.ICON.event,
                layer = self.LAYER.objective,
                quest = title, questID = qid,
                typ = "Event", source = "questlog",
                level = logQuest and logQuest.level,
              })
            end
          end
        end
      end
    end
    -- Tame / use-item-on-target (hunter Taming the Beast, etc.)
    local rods = qdata["obj"]["IR"]
    if not rods and GreedQuestDB and GreedQuestDB.questItemReq then
      rods = GreedQuestDB.questItemReq[qid]
    end
    if rods then
      local _, itemID
      for _, itemID in pairs(rods) do
        local targets = DB:GetItemReqTargets(itemID)
        if targets then
          local ti, tid
          for ti = 1, getn(targets) do
            tid = targets[ti]
            if tid and tid > 0 then
              placeEntity(tid, true, self.ICON.kill, self.LAYER.objective, "Kill")
            elseif tid and tid < 0 then
              placeEntity(-tid, false, self.ICON.object, self.LAYER.objective, "Object")
            end
          end
        end
      end
    end
    -- Item objectives: units/objects that drop the item (loot)
    local skipLoot = false
    if logQuest and logQuest.objectives then
      local anyItem, pendingItem = false, false
      local oi
      for oi = 1, getn(logQuest.objectives) do
        local o = logQuest.objectives[oi]
        local ot = string.lower((o and o.type) or "")
        if ot == "item" then
          anyItem = true
          if not o.finished then pendingItem = true end
        end
      end
      if anyItem and not pendingItem then skipLoot = true end
    end
    if qdata["obj"]["I"] and not skipLoot then
      for _, itemID in pairs(qdata["obj"]["I"]) do
        local item = DB:GetItem(itemID)
        if item then
          local itemName = nil
          local function placeDrops(dropMap, isUnit)
            if not dropMap then return end
            local rareZones = {}
            local eid, chance
            for eid, chance in pairs(dropMap) do
              chance = tonumber(chance) or 0
              if chance > 0 and chance < 1 then
                local entry = isUnit and DB:GetUnit(eid) or DB:GetObject(eid)
                if entry and entry.coords then
                  local _, c
                  for _, c in ipairs(entry.coords) do
                    local x, y, zone = c[1], c[2], c[3]
                    if zone and zone > 0 and x and y then
                      local b = rareZones[zone]
                      if not b then
                        b = { sx = 0, sy = 0, n = 0, chance = chance }
                        rareZones[zone] = b
                      end
                      b.sx = b.sx + x
                      b.sy = b.sy + y
                      b.n = b.n + 1
                      if chance > (b.chance or 0) then b.chance = chance end
                    end
                  end
                end
              else
                placeEntity(eid, isUnit, self.ICON.loot, self.LAYER.objective, "Loot", nil, {
                  itemID = itemID, itemName = itemName, dropChance = chance
                })
              end
            end
            local zone, b
            for zone, b in pairs(rareZones) do
              if b.n and b.n > 0 then
                self:AddNode({
                  mapID = zone,
                  x = b.sx / b.n,
                  y = b.sy / b.n,
                  title = title or ("Quest " .. qid),
                  texture = self.ICON.loot,
                  layer = self.LAYER.objective,
                  quest = title,
                  questID = qid,
                  typ = "Loot",
                  source = "questlog",
                  itemID = itemID,
                  itemName = itemName,
                  dropChance = b.chance,
                  rareArea = true,
                })
              end
            end
          end
          placeDrops(item.U, true)
          placeDrops(item.O, false)
        end
      end
    end
  end

  -- Outdoor door pin while a dungeon quest is still in progress
  if cfg.showObjectives and not isComplete then
    self:AddDungeonEntrancePins(qid, qdata, title, logQuest)
  end
end

function Map:AddDungeonEntrancePins(qid, qdata, title, logQuest)
  local DB = GQ.Database
  if not DB or not DB.IsDungeonZone then return end
  local seen = {}
  local function considerZone(zid)
    if not zid or seen[zid] or not DB:IsDungeonZone(zid) then return end
    seen[zid] = true
    local doors = DB:GetDungeonEntrances(zid)
    if not doors then return end
    local _, door
    for _, door in ipairs(doors) do
      local oz, ox, oy = door[1], door[2], door[3]
      if oz and ox and oy then
        self:AddNode({
          mapID = oz,
          x = ox,
          y = oy,
          title = title or ("Quest "..qid),
          texture = self.ICON.event,
          layer = self.LAYER.objective,
          quest = title,
          questID = qid,
          typ = "Event",
          source = "questlog",
          entrance = true,
          level = logQuest and logQuest.level,
        })
      end
    end
  end
  local function walkUnits(list)
    if not list then return end
    local _, uid
    for _, uid in pairs(list) do
      local u = DB:GetUnit(uid)
      if u and u.coords then
        local _, c
        for _, c in ipairs(u.coords) do
          considerZone(c[3])
        end
      end
    end
  end
  if qdata and qdata["obj"] then
    walkUnits(qdata["obj"]["U"])
  end
  if qdata and qdata["end"] then
    walkUnits(qdata["end"]["U"])
  end
  -- Also honor compiled dungeon kind even if coords didn't unpack
  if DB.QuestKind and DB:QuestKind(qid) == "d" then
    -- nothing extra; considerZone already fired from units if present
  end
end

-- ============================================================
-- Zone tracking
-- ============================================================

function Map:SetPlayerZone(zoneID)
  self.playerZoneID = zoneID
  self:UpdatePins()
end

function Map:ResolvePlayerZone()
  local zoneName = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  if zoneName == "" and GetMinimapZoneText then
    zoneName = GetMinimapZoneText() or ""
  end
  if not zoneName or zoneName == "" then return end

  if not self.zoneByName then
    self.zoneByName = {}
    local zones = GreedQuestDB and GreedQuestDB.zones
    if zones then
      for zid, name in pairs(zones) do
        if type(name) == "string" then
          self.zoneByName[string.lower(name)] = zid
        end
      end
    end
  end

  local zid = self.zoneByName[string.lower(zoneName)]
  if zid then
    if zid ~= self.playerZoneID then
      GQ:Debug("Player zone → " .. zoneName .. " (" .. zid .. ")")
    end
    self.playerZoneID = zid
    self.playerZoneName = zoneName
  else
    -- Keep last known ID but record name for debugging
    self.playerZoneName = zoneName
    GQ:Debug("Zone name not in DB map: " .. zoneName)
  end
end


-- ============================================================
-- Patrol path lines (world map only)
-- ============================================================

function Map:ClearPaths()
  self.paths = {}
  for _, line in ipairs(self.linePool) do
    line:Hide()
  end
end

function Map:AddPath(zoneID, packedPath, title)
  -- packedPath = "x,y;x,y;x,y;..."
  if not packedPath or packedPath == "" then return end
  local points = {}
  for entry in string.gfind(packedPath, "[^;]+") do
    local _, _, x, y = string.find(entry, "([^,]+),([^,]+)")
    if x and y then
      table.insert(points, { tonumber(x), tonumber(y) })
    end
  end
  if getn(points) < 2 then return end
  table.insert(self.paths, {
    mapID = zoneID,
    points = points,
    title = title,
  })
end

function Map:LoadPathsForUnit(unitID, title)
  local DB = GQ.Database
  if not DB or not DB.GetWaypoints then return end
  local wp = DB:GetWaypoints(unitID)
  if not wp then return end
  for zoneID, pathlist in pairs(wp) do
    for _, packed in ipairs(pathlist) do
      self:AddPath(zoneID, packed, title)
    end
  end
end

local function CreateLineFrame(parent, index)
  local line = CreateFrame("Frame", "GQPathLine"..index, parent)
  line:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 5) + 5)
  local tex = line:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(line)
  -- Thin solid line look
  tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  tex:SetVertexColor(0.3, 0.7, 1.0, 0.7)  -- soft blue
  line.texture = tex
  line:Hide()
  return line
end

function Map:EnsureLinePool()
  if not WorldMapButton then return end
  if getn(self.linePool) > 0 then return end
  for i = 1, LINE_POOL_SIZE do
    table.insert(self.linePool, CreateLineFrame(WorldMapButton, i))
  end
end

-- Draw a line segment between two map coords (0-100) on WorldMapButton
function Map:DrawLineSegment(line, x1, y1, x2, y2)
  if not WorldMapButton then return end
  local w = WorldMapButton:GetWidth()
  local h = WorldMapButton:GetHeight()

  local nx1, ny1 = x1 / 100, y1 / 100
  local nx2, ny2 = x2 / 100, y2 / 100

  local px1, py1 = nx1 * w, -ny1 * h
  local px2, py2 = nx2 * w, -ny2 * h

  local dx = px2 - px1
  local dy = py2 - py1
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 1 then
    line:Hide()
    return
  end

  -- Midpoint
  local mx = (px1 + px2) / 2
  local my = (py1 + py2) / 2

  -- Angle in radians
  local angle = math.atan2(dy, dx)

  line:ClearAllPoints()
  line:SetPoint("CENTER", WorldMapButton, "TOPLEFT", mx, my)
  local thickness = (GreedQuestConfig and GreedQuestConfig.map and GreedQuestConfig.map.pathThickness) or 2
  line:SetWidth(length)
  line:SetHeight(thickness)

  -- Rotate via texture coordinates (works on 1.12 without SetRotation)
  -- Approximate rotation by setting the frame width/height and using a rotated texture approach.
  -- Full arbitrary rotation on 1.12 is limited; we use the standard diagonal method:
  local cos_a = math.cos(angle)
  local sin_a = math.sin(angle)

  -- For a simple implementation, stretch a thin texture and use SetTexCoord
  -- to simulate rotation. This is the approach many 1.12 map addons use.
  local tex = line.texture
  if tex then
    -- Reset and apply rotation via texcoords for a unit line along the angle
    -- Simpler fallback: just show axis-aligned if nearly horizontal/vertical,
    -- otherwise use a slightly thicker segment for visibility.
    if math.abs(sin_a) < 0.15 then
      -- mostly horizontal
      line:SetWidth(length)
      line:SetHeight(2)
    elseif math.abs(cos_a) < 0.15 then
      -- mostly vertical
      line:SetWidth(2)
      line:SetHeight(length)
    else
      -- diagonal: use both dimensions for a visible band
      line:SetWidth(math.max(2, math.abs(dx)))
      line:SetHeight(math.max(2, math.abs(dy)))
      if tex.SetTexCoord then
        -- shear approximation
        if (dx > 0 and dy > 0) or (dx < 0 and dy < 0) then
          tex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
        else
          tex:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0)
        end
      end
    end
  end

  line:Show()
end

function Map:UpdatePathLines()
  self:EnsureLinePool()
  local cfg = GreedQuestConfig and GreedQuestConfig.map
  local _, line
  for _, line in ipairs(self.linePool) do
    line:Hide()
    if line.texture and line.texture.SetTexCoord then
      line.texture:SetTexCoord(0, 1, 0, 1)
    end
  end

  if not (WorldMapFrame and WorldMapFrame:IsVisible()) then return end

  local lineIndex = 1
  local maxLines = getn(self.linePool)

  -- Patrol paths
  if cfg and cfg.showPaths and self.paths then
    local _, path
    for _, path in ipairs(self.paths) do
      local pts = path.points
      if pts then
        local i
        for i = 1, getn(pts) - 1 do
          if lineIndex > maxLines then break end
          local ln = self.linePool[lineIndex]
          if ln then
            self:DrawLineSegment(ln, pts[i][1], pts[i][2], pts[i+1][1], pts[i+1][2])
            if ln.texture then
              ln.texture:SetVertexColor(
                cfg.pathColorR or 0.3, cfg.pathColorG or 0.7, cfg.pathColorB or 1.0, cfg.pathAlpha or 0.7)
            end
            lineIndex = lineIndex + 1
          end
        end
      end
    end
  end

  -- Zone-bound debug rectangles (cyan = Kalimdor, yellow = EK)
  if cfg and cfg.debugZoneBounds and GreedQuestDB and GreedQuestDB.zoneBoundsGQ then
    local zid, zb
    for zid, zb in pairs(GreedQuestDB.zoneBoundsGQ) do
      if lineIndex + 3 > maxLines then break end
      local corners = { {0,0}, {100,0}, {100,100}, {0,100} }
      local pts = {}
      local i, ok = 1, true
      for i = 1, 4 do
        local px, py = self:ZoneToDisplayedMapCoords(zid, corners[i][1], corners[i][2])
        if not px or not py then ok = false break end
        pts[i] = { px, py }
      end
      if ok then
        local edges = { {1,2}, {2,3}, {3,4}, {4,1} }
        local e
        for e = 1, 4 do
          local ln = self.linePool[lineIndex]
          local a, b = edges[e][1], edges[e][2]
          self:DrawLineSegment(ln, pts[a][1], pts[a][2], pts[b][1], pts[b][2])
          if ln.texture then
            if zb.continent == 1 then
              ln.texture:SetVertexColor(0.15, 0.95, 1.0, 0.9)
            else
              ln.texture:SetVertexColor(1.0, 0.85, 0.1, 0.9)
            end
          end
          lineIndex = lineIndex + 1
        end
      end
    end
  end
end




-- ============================================================
-- Focus / highlight from tracker click
-- ============================================================

Map.highlightQuestID = nil
Map.highlightTitle   = nil

function Map:ClearHighlight()
  self.highlightQuestID = nil
  self.highlightTitle = nil
  -- Reset pin sizes/alphas
  for _, pin in ipairs(self.worldPins) do
    if pin.node then
      if pin.node.isCluster then
        pin:SetWidth(18)
        pin:SetHeight(18)
      else
        pin:SetWidth(16)
        pin:SetHeight(16)
      end
      pin:SetAlpha(1)
    end
  end
end

function Map:FocusQuest(questID, title, preferredType)
  self.highlightQuestID = questID
  self.highlightTitle = title

  -- Find a good node to center on
  local best = nil
  local bestScore = -1

  for mapID, list in pairs(self.nodes) do
    for _, node in ipairs(list) do
      local match = false
      if questID and node.questID == questID then match = true end
      if title and node.title == title then match = true end
      if match then
        local score = 1
        if preferredType and node.typ == preferredType then score = 3 end
        if node.typ == "Objective" then score = score + 1 end
        if score > bestScore then
          bestScore = score
          best = node
        end
      end
    end
  end

  -- Open world map
  if WorldMapFrame then
    ShowUIPanel(WorldMapFrame)
  end

  -- Try to set player zone if we have a best node
  if best and best.mapID then
    self.playerZoneID = best.mapID
    -- Best-effort: if we know the zone name, we cannot always force the
    -- world map to that zone on pure 1.12, but pins will still highlight.
  end

  self:UpdatePins()

  -- Apply highlight pass
  self:ApplyHighlight()
end

function Map:ApplyHighlight()
  if not self.highlightQuestID and not self.highlightTitle then return end

  for _, pin in ipairs(self.worldPins) do
    local n = pin.node
    if n and pin:IsShown() then
      local match = false
      if self.highlightQuestID and n.questID == self.highlightQuestID then match = true end
      if self.highlightTitle and n.title == self.highlightTitle then match = true end
      if match then
        pin:SetWidth(22)
        pin:SetHeight(22)
        pin:SetAlpha(1)
      else
        pin:SetAlpha(0.35)
      end
    end
  end
end


-- ============================================================
-- Init
-- ============================================================


function Map:HideBlizzardQuestPOIs()
  local function mute(f)
    if not f or not f.Hide then return end
    f:Hide()
    if not f._gqHidden then
      f._gqHidden = true
      f.Show = function() end
    end
  end
  mute(getglobal("WorldMapBlobFrame"))
  mute(getglobal("QuestPOIFrame"))
  mute(getglobal("QuestMapFrame"))
  mute(getglobal("MiniMapQuestFrame"))
  mute(getglobal("WatchFrameLines"))
  local i
  for i = 1, 40 do
    mute(getglobal("QuestPOI_" .. i))
    mute(getglobal("WorldMapQuestPOI" .. i))
    mute(getglobal("WorldMapBlob"..i))
  end
  local function hideQuestTex(frame)
    if not frame or type(frame) ~= "table" then return end
    if frame.GetTexture then
      local ok, tex = pcall(function() return frame:GetTexture() end)
      if ok and tex and tex ~= "" then
        tex = string.lower(tostring(tex))
        if string.find(tex, "questpoi", 1, true)
           or string.find(tex, "questblob", 1, true)
           or string.find(tex, "ui-questpoi", 1, true)
           or string.find(tex, "questobjective", 1, true) then
          mute(frame)
        end
      end
    end
    if frame.GetChildren then
      local ok, kids = pcall(function() return { frame:GetChildren() } end)
      if ok and kids then
        local k
        for k = 1, getn(kids) do
          hideQuestTex(kids[k])
        end
      end
    end
    if frame.GetRegions then
      local ok, regs = pcall(function() return { frame:GetRegions() } end)
      if ok and regs then
        local r
        for r = 1, getn(regs) do
          hideQuestTex(regs[r])
        end
      end
    end
  end
  hideQuestTex(WorldMapButton)
  hideQuestTex(WorldMapDetailFrame)
  hideQuestTex(Minimap)
end

function Map:Init()
  self:ApplyIconStyle()
  if self.HideBlizzardQuestPOIs then self:HideBlizzardQuestPOIs() end
  self:EnsureWorldPool()
  self:EnsureMiniPool()

  local f = CreateFrame("Frame")
  f:RegisterEvent("WORLD_MAP_UPDATE")
  f:RegisterEvent("ZONE_CHANGED")
  f:RegisterEvent("ZONE_CHANGED_INDOORS")
  f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  f:RegisterEvent("MINIMAP_UPDATE")

  f:SetScript("OnEvent", function()
    if event == "WORLD_MAP_UPDATE" then
      -- World map only — do NOT rebuild/hide minimap here
      local open = WorldMapFrame and (WorldMapFrame:IsVisible() or WorldMapFrame:IsShown())
      if open then
        Map:ResolvePlayerZone()
        Map:UpdateWorldPins()
        if Map.highlightQuestID or Map.highlightTitle then
          Map:ApplyHighlight()
        end
      else
        Map:ClearHighlight()
        if WorldMapTooltip then WorldMapTooltip:Hide() end
      end
    elseif event == "MINIMAP_UPDATE" then
      -- Zoom / rotate: move existing pins, do not rebuild textures
      Map._lastMiniZoom = nil
      Map:RepositionMiniPinsOnly()
    else
      Map:ResolvePlayerZone()
      Map._miniNeedsFull = true
      Map:UpdateMinimapPins()
    end
  end)

  -- Movement: ~20 Hz check, but only redraw when position actually changed
  local ticker = CreateFrame("Frame")
  local elapsed = 0
  ticker:SetScript("OnUpdate", function()
    elapsed = elapsed + (arg1 or 0.03)
    if elapsed < 0.05 then return end
    elapsed = 0
    if not Map.playerZoneID then return end
    -- Idle: no pins assigned and no pending full rebuild
    local any
    if Map.miniPins then
      local hi
      for hi = 1, getn(Map.miniPins) do
        if Map.miniPins[hi] and Map.miniPins[hi].node then any = true break end
      end
    end
    if (not any) and not Map._miniNeedsFull then
      return
    end
    local lx, ly = GetPlayerMapPosition("player")
    if lx and ly and Map._lastMiniAssignX then
      local dx = lx - Map._lastMiniAssignX
      local dy = ly - (Map._lastMiniAssignY or 0)
      -- Rediscover after ~4% zone movement (pins that were outside the circle)
      if (dx * dx + dy * dy) > 0.0016 then
        Map._miniNeedsFull = true
        Map:UpdateMinimapPins()
      else
        Map:RepositionMiniPinsOnly()
      end
    else
      Map:RepositionMiniPinsOnly()
    end
  end)

  self:ResolvePlayerZone()

  if WorldMapFrame then
    local prevShow = WorldMapFrame:GetScript("OnShow")
    WorldMapFrame:SetScript("OnShow", function()
      if prevShow then prevShow() end
      Map:ResolvePlayerZone()
      if not Map._wmShowFrame then Map._wmShowFrame = CreateFrame("Frame") end
      local wf = Map._wmShowFrame
      wf.t = 0
      wf:SetScript("OnUpdate", function()
        wf.t = wf.t + (arg1 or 0.01)
        if wf.t < 0.05 then return end
        wf:SetScript("OnUpdate", nil)
        -- Only world pins; minimap data is already valid
        Map:UpdateWorldPins()
      end)
    end)
    local prevHide = WorldMapFrame:GetScript("OnHide")
    WorldMapFrame:SetScript("OnHide", function()
      if prevHide then prevHide() end
      Map:ClearHighlight()
      if WorldMapTooltip then WorldMapTooltip:Hide() end
      -- Restore zone so GetPlayerMapPosition matches minimap again
      if SetMapToCurrentZone then
        SetMapToCurrentZone()
      end
      Map:ResolvePlayerZone()
      Map._lastMiniX = nil
      Map._miniNeedsFull = true
      Map:UpdateMinimapPins()
    end)
  end

  GQ:Debug("Map module ready (split world/minimap updates)")
end


-- Show a quest from database search (givers / turn-ins / objectives)
function Map:ShowQuestInDatabase(qid, title)
  local DB = GQ.Database
  if not DB or not qid then return end
  local qdata = DB:GetQuest(qid)
  if not qdata then return end
  self:ClearNodes("search")
  self:AddQuestNodes(qid, qdata, title or ("Quest " .. qid), false)
  -- Mark nodes as search source for clear
  if self.nodes then
    for mapID, list in pairs(self.nodes) do
      for _, n in ipairs(list) do
        if n.questID == qid and not n.source then
          n.source = "search"
        end
      end
    end
  end
  self.highlightQuestID = qid
  self.highlightTitle = title
  if WorldMapFrame and not WorldMapFrame:IsVisible() and ToggleWorldMap then
    ToggleWorldMap()
  end
  self:UpdatePins()
end
