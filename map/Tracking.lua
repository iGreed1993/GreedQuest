--[[
  GreedQuest Optional Tracking
  Flight masters, mailboxes, innkeepers, repair vendors
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Tracking = GQ.Tracking or {}
local Track = GQ.Tracking

Track.KINDS = {
  -- Service icons from media/; never use quest "!" as fallback
  { key = "flight",    label = "Flight masters",  icon = "Interface\\AddOns\\GreedQuest\\media\\flight" },
  { key = "mailbox",   label = "Mailboxes",       icon = "Interface\\AddOns\\GreedQuest\\media\\mailbox" },
  { key = "innkeeper", label = "Innkeepers",      icon = "Interface\\AddOns\\GreedQuest\\media\\innkeeper" },
  { key = "repair",    label = "Repair vendors",  icon = "Interface\\AddOns\\GreedQuest\\media\\repair" },
}

local function PlayerFactionCode()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if f == "Alliance" then return "A" end
  if f == "Horde" then return "H" end
  return "AH"
end

local function FactionOk(tag)
  if not tag or tag == "" or tag == "AH" then return true end
  local pf = PlayerFactionCode()
  if pf == "AH" then return true end
  if tag == "AH" then return true end
  return tag == pf
end

function Track:IsEnabled(kind)
  local cfg = GreedQuestConfig and GreedQuestConfig.tracking
  if not cfg then return false end
  return cfg[kind] and true or false
end

function Track:AnyEnabled()
  local i
  for i = 1, table.getn(self.KINDS) do
    if self:IsEnabled(self.KINDS[i].key) then return true end
  end
  return false
end

function Track:BuildNodes()
  if not GQ.Map or not GQ.Map.AddNode then return end
  GQ.Map:ClearNodes("tracking")

  if not self:AnyEnabled() then return end
  local meta = GreedQuestDB and GreedQuestDB.tracking
  if not meta then return end
  local DB = GQ.Database
  if not DB then return end

  local function placeCoords(coords, title, texture, typ)
    if not coords then return end
    local i
    for i = 1, table.getn(coords) do
      local c = coords[i]
      local x, y, zone = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
      if zone and zone > 0 and x and y then
        GQ.Map:AddNode({
          mapID   = zone,
          x       = x,
          y       = y,
          title   = title,
          quest   = title,
          texture = texture,
          layer   = 2,
          typ     = typ,
          source  = "tracking",
        })
      end
    end
  end

  local titles = {
    flight = "Flight Master",
    mailbox = "Mailbox",
    innkeeper = "Innkeeper",
    repair = "Repair Vendor",
  }

  local ki
  for ki = 1, table.getn(self.KINDS) do
    local kind = self.KINDS[ki]
    if self:IsEnabled(kind.key) then
      local list = meta[kind.key]
      if list then
        local id, tag
        for id, tag in pairs(list) do
          if FactionOk(tostring(tag)) then
            local absId = tonumber(id) or 0
            if absId < 0 then absId = -absId end
            local entry
            if kind.key == "mailbox" then
              entry = DB:GetObject(absId)
            else
              entry = DB:GetUnit(absId)
              if not entry then entry = DB:GetObject(absId) end
            end
            if entry and type(entry) == "table" and entry.coords then
              placeCoords(entry.coords, titles[kind.key] or kind.label, kind.icon, kind.key)
            end
          end
        end
      end
    end
  end
end

function Track:Refresh()
  self:BuildNodes()
  if GQ.Map then
    if GQ.Map.MarkClustersDirty then GQ.Map:MarkClustersDirty() end
    if GQ.Map.DrawAllPins then
      GQ.Map:DrawAllPins()
    elseif GQ.Map.UpdatePins then
      GQ.Map:UpdatePins()
    end
  end
end

function Track:ToggleKind(key)
  if not GreedQuestConfig then return end
  if not GreedQuestConfig.tracking then GreedQuestConfig.tracking = {} end
  if GreedQuestConfig.tracking[key] then
    GreedQuestConfig.tracking[key] = false
  else
    GreedQuestConfig.tracking[key] = true
  end
  self:Refresh()
  -- rebuild open menu so checks update, keep anchored to minimap button
  if self.menu and self.menu:IsShown() then
    local anchor = self.menuAnchor
    self:CloseMenu()
    self:ShowMenu(anchor)
  end
end

function Track:CloseMenu()
  if self.menuCloser then
    self.menuCloser:Hide()
  end
  if self.menu then
    self.menu:Hide()
  end
end

function Track:ShowMenu(anchor)
  self:CloseMenu()

  if not anchor then
    if GQ.Minimap and GQ.Minimap.button then
      anchor = GQ.Minimap.button
    else
      anchor = Minimap
    end
  end
  self.menuAnchor = anchor

  local rows = table.getn(self.KINDS)
  local f = self.menu
  if not f then
    f = CreateFrame("Frame", "GreedQuestTrackingMenu", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetWidth(180)
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 12, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f:EnableMouse(true)
    self.menu = f
    self.menuRows = {}
  end

  f:SetHeight(12 + rows * 20 + 8)
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)

  -- clear old row frames
  local r
  if self.menuRows then
    for r = 1, table.getn(self.menuRows) do
      if self.menuRows[r] then
        self.menuRows[r]:Hide()
      end
    end
  end
  self.menuRows = {}

  local y = -6
  local i
  for i = 1, rows do
    local kind = self.KINDS[i]
    local key = kind.key
    local labelText = kind.label

    local btn = CreateFrame("Button", nil, f)
    btn:SetPoint("TOPLEFT", 4, y)
    btn:SetPoint("TOPRIGHT", -4, y)
    btn:SetHeight(18)
    btn:EnableMouse(true)
    btn:Show()

    local check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check:SetPoint("LEFT", 4, 0)
    if self:IsEnabled(key) then
      check:SetText("|cff33ff33[x]|r")
    else
      check:SetText("|cff888888[ ]|r")
    end

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 28, 0)
    label:SetText(labelText)

    btn:SetScript("OnClick", function()
      Track:ToggleKind(key)
    end)
    btn:SetScript("OnEnter", function()
      label:SetText("|cffffff00" .. labelText .. "|r")
    end)
    btn:SetScript("OnLeave", function()
      label:SetText(labelText)
    end)

    self.menuRows[i] = btn
    y = y - 20
  end

  -- click-away closer (reuse)
  local closer = self.menuCloser
  if not closer then
    closer = CreateFrame("Button", "GreedQuestTrackingMenuCloser", UIParent)
    closer:SetFrameStrata("FULLSCREEN")
    closer:EnableMouse(true)
    closer:SetScript("OnClick", function()
      Track:CloseMenu()
    end)
    self.menuCloser = closer
  end
  closer:ClearAllPoints()
  closer:SetAllPoints(UIParent)
  closer:Show()

  f:Show()
end

function Track:TogglePanel()
  if self.menu and self.menu:IsShown() then
    self:CloseMenu()
  else
    local anchor = nil
    if GQ.Minimap and GQ.Minimap.button then
      anchor = GQ.Minimap.button
    else
      anchor = Minimap
    end
    self:ShowMenu(anchor)
  end
end

function Track:Init()
  if GreedQuestConfig and not GreedQuestConfig.tracking then
    GreedQuestConfig.tracking = {
      flight = false,
      mailbox = false,
      innkeeper = false,
      repair = false,
    }
  end
end
