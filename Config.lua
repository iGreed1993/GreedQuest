--[[
  GreedQuest Config UI
  Tabbed settings (1.12-safe) + database search
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Config = GQ.Config or {}
local Config = GQ.Config

local TAB_NAMES = { "General", "Tracker", "Map", "Icons", "Filters", "Tooltips", "Database" }

local function RefreshAll()
  if GQ.Core and GQ.Core.NotifyFiltersChanged then GQ.Core:NotifyFiltersChanged() end
  if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
  if GQ.Map then
    if GQ.Map.ApplyIconStyle then GQ.Map:ApplyIconStyle() end
    if GQ.Map.BuildNodesFromQuestLog then GQ.Map:BuildNodesFromQuestLog()
    elseif GQ.Map.UpdatePins then GQ.Map:UpdatePins() end
  end
  if GQ.Minimap and GQ.Minimap.Refresh then GQ.Minimap:Refresh() end
end

local function RefreshTracker()
  if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
end

local function RefreshMap()
  if GQ.Map then
    if GQ.Map.ApplyIconStyle then GQ.Map:ApplyIconStyle() end
    if GQ.Map.UpdateWorldPins then GQ.Map:UpdateWorldPins() end
    if GQ.Map.UpdateMinimapPins then
      GQ.Map._miniNeedsFull = true
      GQ.Map:UpdateMinimapPins()
    end
  end
end

-- ============================================================
-- Widget helpers
-- ============================================================

local function MakeCheckbox(parent, label, y, path, key, onChange, tipText)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", 8, y)
  cb:SetWidth(24)
  cb:SetHeight(24)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  text:SetText(label)
  cb:SetScript("OnClick", function()
    local checked = this:GetChecked() and true or false
    if GreedQuestConfig[path] then GreedQuestConfig[path][key] = checked end
    if onChange then onChange(checked) end
  end)
  if GreedQuestConfig and GreedQuestConfig[path] then
    cb:SetChecked(GreedQuestConfig[path][key] and 1 or 0)
  end
  if tipText then
    cb.gqTip = tipText
    cb:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label, 1, 0.82, 0)
      GameTooltip:AddLine(this.gqTip, 1, 1, 1, 1)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return y - 24
end

local function MakeSlider(parent, label, y, path, key, minV, maxV, step, onChange)
  local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  labelFS:SetPoint("TOPLEFT", 12, y)
  labelFS:SetText(label)
  local valueFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueFS:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)

  local slider = CreateFrame("Slider", nil, parent)
  slider:SetPoint("TOPLEFT", 12, y - 14)
  slider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y - 14)
  slider:SetHeight(16)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(minV, maxV)
  slider:SetValueStep(step)
  slider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 }
  })
  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  thumb:SetWidth(24)
  thumb:SetHeight(24)
  slider:SetThumbTexture(thumb)

  local initial = minV
  if GreedQuestConfig and GreedQuestConfig[path] and GreedQuestConfig[path][key] ~= nil then
    initial = GreedQuestConfig[path][key]
  end
  if initial < minV then initial = minV end
  if initial > maxV then initial = maxV end
  slider:SetValue(initial)
  if step < 1 then
    valueFS:SetText(string.format("%.2f", initial))
  else
    valueFS:SetText(string.format("%.0f", initial))
  end

  slider:SetScript("OnValueChanged", function()
    local val = this:GetValue()
    -- Snap to step
    if step and step > 0 then
      val = math.floor(val / step + 0.5) * step
    end
    -- Keep exact 0 when near zero (opacity "off")
    if minV == 0 and val < step * 0.5 then val = 0 end
    if GreedQuestConfig and GreedQuestConfig[path] then
      GreedQuestConfig[path][key] = val
    end
    if step < 1 then
      valueFS:SetText(string.format("%.2f", val))
    else
      valueFS:SetText(string.format("%.0f", val))
    end
    if onChange then onChange(val) end
  end)
  return y - 40
end

local function Header(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 8, y)
  fs:SetText("|cffffd100" .. text .. "|r")
  return y - 20
end

local function Hint(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", 12, y)
  fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
  fs:SetJustifyH("LEFT")
  fs:SetText("|cff888888" .. text .. "|r")
  return y - 16
end

-- Cycle button: clicks through options list { {label, value}, ... }
local function MakeCycle(parent, label, y, path, key, options, onChange)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 12, y)
  fs:SetText(label)

  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetWidth(130)
  btn:SetHeight(20)
  btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y + 2)

  local function currentIndex()
    local cur = GreedQuestConfig and GreedQuestConfig[path] and GreedQuestConfig[path][key]
    for i, opt in ipairs(options) do
      if opt[2] == cur then return i end
    end
    return 1
  end

  local function updateLabel()
    local i = currentIndex()
    btn:SetText(options[i][1])
  end
  updateLabel()

  btn:SetScript("OnClick", function()
    local i = currentIndex()
    i = i + 1
    if i > getn(options) then i = 1 end
    if GreedQuestConfig and GreedQuestConfig[path] then
      GreedQuestConfig[path][key] = options[i][2]
    end
    btn:SetText(options[i][1])
    if onChange then onChange(options[i][2]) end
  end)
  return y - 26
end

-- ============================================================
-- Build tab content
-- ============================================================

local function BuildGeneral(child)
  local y = -8
  y = Header(child, "Quest tracking", y)
  y = MakeCheckbox(child, "Auto-track all accepted quests", y, "general", "autoTrack", RefreshAll)
  y = Hint(child, "ON = all log quests on the tracker (shift-click to remove). OFF = only shift-clicked quests. Independent of Blizzard watch limit.", y)
  y = MakeCheckbox(child, "Current zone only (tracker + map objectives)", y, "general", "currentZoneOnly", RefreshAll)
  y = y - 4
  y = Header(child, "Minimap button", y)
  y = MakeCheckbox(child, "Show minimap button", y, "minimap", "enabled", function()
    if GQ.Minimap and GQ.Minimap.Refresh then GQ.Minimap:Refresh() end
  end)
  y = y - 4
  y = Header(child, "Automation", y)
  y = MakeCheckbox(child, "Auto-accept quests", y, "general", "autoAccept")
  y = MakeCheckbox(child, "Auto-turn-in quests", y, "general", "autoTurnIn")
  y = Hint(child, "Auto-turn-in skips reward choice dialogs when a choice is required.", y)
  y = y - 6
  y = Header(child, "Advanced", y)
  y = MakeCheckbox(child, "Debug messages", y, "general", "debug")
  return math.abs(y) + 40
end

local function BuildTracker(child)
  local y = -8
  y = Header(child, "Tracker window", y)
  y = MakeCheckbox(child, "Enable tracker", y, "tracker", "enabled", function(c)
    if GQ.Tracker and GQ.Tracker.frame then
      if c then GQ.Tracker.frame:Show() else GQ.Tracker.frame:Hide() end
    end
  end)
  y = MakeCheckbox(child, "Lock position", y, "tracker", "locked")
  y = MakeCheckbox(child, "Show background", y, "tracker", "showBackground", RefreshTracker)
  y = MakeSlider(child, "Background opacity", y, "tracker", "alpha", 0, 1.0, 0.05, RefreshTracker)
  y = Hint(child, "Set to 0 for a fully transparent tracker (text only).", y)
  y = MakeSlider(child, "Tracker width", y, "tracker", "width", 160, 420, 10, RefreshTracker)
  y = MakeSlider(child, "Font size", y, "tracker", "fontSize", 10, 18, 1, RefreshTracker)
  y = MakeSlider(child, "Max quests shown", y, "tracker", "maxQuests", 5, 25, 1, RefreshTracker)
  y = y - 4
  y = Header(child, "Display", y)
  y = MakeCheckbox(child, "Show quest levels", y, "tracker", "showLevel", RefreshTracker)
  y = MakeCheckbox(child, "Show completed (ready to turn in)", y, "tracker", "showComplete", RefreshTracker)
  y = y - 4
  y = Header(child, "Sort mode (click to cycle)", y)
  y = MakeCycle(child, "Sort by", y, "tracker", "sortMode", {
    {"Log order", "log"},
    {"Zone", "zone"},
    {"To-do first", "incomplete"},
    {"Level", "level"},
    {"Closest zone", "closest"},
  }, RefreshTracker)
  y = MakeCycle(child, "Filter preset", y, "tracker", "filterPreset", {
    {"All", "all"},
    {"Current zone", "zone"},
    {"Incomplete", "incomplete"},
    {"Complete only", "complete"},
  }, RefreshTracker)
  y = Hint(child, "Shift-hover: full text · Right-click: collapse · Alt-click: hide/unhide · Shift-click in quest log: track/untrack.", y)
  return math.abs(y) + 40
end

local function BuildMap(child)
  local y = -8
  y = Header(child, "What to show", y)
  y = MakeCheckbox(child, "Show objective pins", y, "map", "showObjectives", RefreshAll)
  y = MakeCheckbox(child, "Show available quests (!)", y, "map", "showGivers", RefreshAll)
  y = MakeCheckbox(child, "Show completed quests / turn-ins (?)", y, "map", "showTurnins", RefreshAll)
  y = Hint(child, "Available and turn-in pins are separate. You can hide ! markers and still see ready-to-turn-in ? pins.", y)
  y = MakeCheckbox(child, "Show patrol paths (world map)", y, "map", "showPaths", RefreshMap)
  y = y - 4
  y = Header(child, "Clustering", y)
  y = MakeCheckbox(child, "Cluster nearby pins", y, "map", "cluster", RefreshAll,
    "When OFF, every individual objective pin is drawn with no pooling limit.\n"
    .. "This can cause heavy map clutter and a noticeable FPS drop in busy zones.\n"
    .. "Leave clustering ON unless you specifically need exact pin positions.")
  y = MakeSlider(child, "Cluster radius", y, "map", "clusterRadius", 1.0, 6.0, 0.5, RefreshAll)
  y = y - 4
  y = Header(child, "Pin size & visibility", y)
  y = MakeSlider(child, "World map pin size", y, "map", "worldPinSize", 4, 24, 1, RefreshMap)
  y = MakeSlider(child, "Continent map pin size", y, "map", "continentPinSize", 4, 24, 1, RefreshMap)
  y = MakeSlider(child, "Zone map pin size", y, "map", "zonePinSize", 4, 28, 1, RefreshMap)
  y = MakeSlider(child, "Minimap pin size", y, "map", "miniPinSize", 6, 18, 1, RefreshMap)
  y = MakeSlider(child, "Pin opacity", y, "map", "pinAlpha", 0, 1.0, 0.05, RefreshMap)
  y = y - 4
  y = Header(child, "Patrol path lines", y)
  y = MakeSlider(child, "Path opacity", y, "map", "pathAlpha", 0, 1.0, 0.05, RefreshMap)
  y = MakeSlider(child, "Path thickness", y, "map", "pathThickness", 1, 4, 1, RefreshMap)
  return math.abs(y) + 40
end

local function BuildIcons(child)
  local y = -8
  y = Header(child, "Icon style", y)
  y = MakeCycle(child, "Pin style", y, "map", "iconStyle", {
    {"Native icons", "native"},
    {"Colored dots", "dots"},
  }, RefreshAll)
  y = Hint(child, "Colored dots use simple circles: yellow available, gold turn-in, red kill, green loot, cyan object.", y)
  y = y - 6
  y = Header(child, "Native icon set (when not using dots)", y)
  y = MakeCycle(child, "Available (!)", y, "map", "iconAvailable", {
    {"Quest !", "quest"},
    {"Gossip", "gossip"},
    {"Yellow dot", "dot"},
  }, RefreshAll)
  y = MakeCycle(child, "Turn-in (?)", y, "map", "iconTurnin", {
    {"Quest ?", "quest"},
    {"Active gossip", "gossip"},
    {"Gold dot", "dot"},
  }, RefreshAll)
  y = MakeCycle(child, "Kill objectives", y, "map", "iconKill", {
    {"Attack cursor", "attack"},
    {"Red dot", "dot"},
    {"Vendor icon", "vendor"},
  }, RefreshAll)
  y = MakeCycle(child, "Loot / items", y, "map", "iconLoot", {
    {"Vendor", "vendor"},
    {"Green dot", "dot"},
    {"Petition", "petition"},
  }, RefreshAll)
  y = MakeCycle(child, "Objects / interact", y, "map", "iconObject", {
    {"Workbench", "workbench"},
    {"Cyan dot", "dot"},
    {"Gossip", "gossip"},
  }, RefreshAll)
  y = y - 4
  y = Hint(child, "Colored dots use a circular marker with fixed colors per objective type.", y)
  return math.abs(y) + 40
end

local function BuildFilters(child)
  local y = -8
  y = Header(child, "Hide quest types", y)
  y = Hint(child, "Hidden types are removed from available pins (map/minimap). Tracker only shows quests you already accepted.", y)
  y = y - 4
  y = MakeCheckbox(child, "Hide PvP quests", y, "general", "hidePvP", RefreshAll)
  y = MakeCheckbox(child, "Hide seasonal / event quests", y, "general", "hideSeasonal", RefreshAll)
  y = MakeCheckbox(child, "Hide low level quests (grey to player)", y, "general", "hideLowLevel", RefreshAll)
  y = MakeCheckbox(child, "Hide repeatable / daily / cloth turn-ins", y, "general", "hideRepeatable", RefreshAll)
  y = y - 6
  y = Header(child, "Manual hides", y)
  y = Hint(child, "Alt-click a pin or tracker quest to hide/unhide. Shift-click in the quest log also restores a hidden quest when tracking it.", y)
  y = y - 4
  local clearBtn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
  clearBtn:SetWidth(180)
  clearBtn:SetHeight(22)
  clearBtn:SetPoint("TOPLEFT", 12, y)
  clearBtn:SetText("Clear manual hides")
  clearBtn:SetScript("OnClick", function()
    if GreedQuestCharDB then GreedQuestCharDB.hiddenQuests = {} end
    RefreshAll()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: cleared manually hidden quests.")
  end)
  y = y - 30
  return math.abs(y) + 40
end

local function BuildTooltips(child)
  local y = -8
  y = Header(child, "Tooltip detail", y)
  y = MakeCycle(child, "Density", y, "tooltips", "density", {
    {"Full", "full"},
    {"Compact", "compact"},
    {"Off", "off"},
  }, function() end)
  y = MakeCheckbox(child, "Show party progress on tooltips", y, "tooltips", "showParty")
  y = y - 6
  y = Header(child, "Map pin tooltips", y)
  y = Hint(child, "Hover pins for name/progress. Shift on available shows full objective text. Alt-click hides.", y)
  return math.abs(y) + 40
end

local function BuildDatabase(child, configSelf)
  local y = -8
  y = Header(child, "Search quest database", y)
  y = Hint(child, "Type a name fragment or quest ID, then Enter. Click a result for full details.", y)
  y = y - 4

  local edit = CreateFrame("EditBox", "GQConfigSearchBox", child)
  edit:SetPoint("TOPLEFT", 12, y)
  edit:SetPoint("TOPRIGHT", child, "TOPRIGHT", -12, y)
  edit:SetHeight(20)
  edit:SetAutoFocus(false)
  edit:SetFontObject(GameFontHighlight)
  edit:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  edit:SetBackdropColor(0, 0, 0, 0.8)
  edit:SetTextInsets(6, 6, 0, 0)
  edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  edit:SetScript("OnEnterPressed", function()
    Config:RunSearch(this:GetText())
    this:ClearFocus()
  end)
  configSelf.searchBox = edit
  y = y - 28

  local info = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 12, y)
  info:SetText("Enter a name fragment or quest ID.")
  configSelf.resultInfo = info
  y = y - 18

  local resultScroll = CreateFrame("ScrollFrame", "GQSearchResultsScroll", child, "UIPanelScrollFrameTemplate")
  resultScroll:SetPoint("TOPLEFT", 8, y)
  resultScroll:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -28, 8)
  local resultChild = CreateFrame("Frame", "GQSearchResultsChild", resultScroll)
  resultChild:SetWidth(320)
  resultChild:SetHeight(600)
  resultScroll:SetScrollChild(resultChild)
  configSelf.resultChild = resultChild

  configSelf.resultButtons = {}
  for i = 1, 50 do
    local b = CreateFrame("Button", nil, resultChild)
    b:SetPoint("TOPLEFT", 0, -((i - 1) * 18))
    b:SetPoint("TOPRIGHT", resultChild, "TOPRIGHT", 0, -((i - 1) * 18))
    b:SetHeight(18)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetAllPoints(b)
    t:SetJustifyH("LEFT")
    b.text = t
    b:SetScript("OnClick", function()
      if not this.questID then return end
      if GQ.QuestDetail then
        if GQ.QuestDetail.ShowQuest then
          GQ.QuestDetail:ShowQuest(this.questID, this.questTitle, this.questLevel)
        elseif GQ.QuestDetail.Show then
          GQ.QuestDetail:Show(this.questID, this.questTitle)
        end
      end
    end)
    b:Hide()
    configSelf.resultButtons[i] = b
  end
  return 400
end

-- ============================================================
-- Main frame
-- ============================================================

function Config:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", "GreedQuestConfigFrame", UIParent)
  f:SetWidth(420)
  f:SetHeight(520)
  f:SetPoint("CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  f:SetBackdropColor(0, 0, 0, 0.92)
  f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  f:Hide()
  tinsert(UISpecialFrames, "GreedQuestConfigFrame")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("|cff33ffccGreedQuest|r Settings")
  title:SetFontObject(GameFontNormal)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)
  close:SetScript("OnClick", function() f:Hide() end)

  -- Tab strip
  local tabs = {}
  local panes = {}
  local tabWidth = 54
  local x0 = 16
  for i, name in ipairs(TAB_NAMES) do
    local tab = CreateFrame("Button", "GQConfigTab"..i, f, "UIPanelButtonTemplate")
    tab:SetWidth(tabWidth)
    tab:SetHeight(20)
    tab:SetPoint("TOPLEFT", x0 + (i - 1) * (tabWidth + 2), -36)
    tab:SetText(name)
    tabs[i] = tab

    local pane = CreateFrame("Frame", "GQConfigPane"..i, f)
    pane:SetPoint("TOPLEFT", 14, -62)
    pane:SetPoint("BOTTOMRIGHT", -14, 14)
    pane:Hide()
    panes[i] = pane
  end

  local function ShowTab(idx)
    for i = 1, getn(panes) do
      if i == idx then panes[i]:Show() else panes[i]:Hide() end
    end
  end

  for i = 1, getn(tabs) do
    local idx = i
    tabs[i]:SetScript("OnClick", function() ShowTab(idx) end)
  end

  -- Build each tab's scroll content
  local builders = {
    BuildGeneral,
    BuildTracker,
    BuildMap,
    BuildIcons,
    BuildFilters,
    BuildTooltips,
    function(child) return BuildDatabase(child, Config) end,
  }

  for i, builder in ipairs(builders) do
    local pane = panes[i]
    local scroll = CreateFrame("ScrollFrame", "GQConfigScroll"..i, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local child = CreateFrame("Frame", "GQConfigChild"..i, scroll)
    child:SetWidth(360)
    local height = builder(child) or 400
    child:SetHeight(math.max(height, 200))
    scroll:SetScrollChild(child)
  end

  ShowTab(1)
  self.frame = f
  self.tabs = tabs
  self.panes = panes
end

function Config:RunSearch(query)
  if not self.resultButtons then return end
  query = string.lower(string.gsub(query or "", "^%s*(.-)%s*$", "%1"))
  for i = 1, 50 do
    self.resultButtons[i]:Hide()
    self.resultButtons[i].questID = nil
  end
  if query == "" then
    if self.resultInfo then self.resultInfo:SetText("Enter a name fragment or quest ID.") end
    return
  end

  local titles = GreedQuestDB and GreedQuestDB.questTitles or {}
  local results = {}
  local asNum = tonumber(query)

  if asNum and titles[asNum] then
    table.insert(results, { id = asNum, title = titles[asNum] })
  end
  for qid, title in pairs(titles) do
    if type(qid) == "number" and title and string.find(string.lower(title), query, 1, true) then
      table.insert(results, { id = qid, title = title })
      if getn(results) >= 50 then break end
    end
  end

  table.sort(results, function(a, b) return (a.title or "") < (b.title or "") end)

  local shown = 0
  for i = 1, getn(results) do
    if i > 50 then break end
    local r = results[i]
    local b = self.resultButtons[i]
    local qdata = GQ.Database and GQ.Database:GetQuest(r.id)
    local lvl = qdata and (qdata["lvl"] or qdata["min"]) or nil
    local lvlstr = lvl and ("[" .. lvl .. "] ") or ""
    b.text:SetText(lvlstr .. r.title .. " |cff888888(" .. r.id .. ")|r")
    b.questID = r.id
    b.questTitle = r.title
    b.questLevel = lvl
    b:Show()
    shown = shown + 1
  end

  if self.resultChild then
    self.resultChild:SetHeight(math.max(40, shown * 18))
  end
  if self.resultInfo then
    self.resultInfo:SetText("Results: " .. shown .. (shown >= 50 and " (max 50)" or ""))
  end
end

function Config:Toggle()
  if not self.frame then self:Init() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function Config:Show()
  if not self.frame then self:Init() end
  self.frame:Show()
end

function Config:Hide()
  if self.frame then self.frame:Hide() end
end
