--[[
  GreedQuest Minimap Button
  Note icon (Greed theme) with standard minimap border
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Minimap = GQ.Minimap or {}
local MM = GQ.Minimap

local BUTTON_SIZE = 31

function MM:Init()
  if self.button then return end

  local btn = CreateFrame("Button", "GreedQuestMinimapButton", Minimap)
  btn:SetWidth(BUTTON_SIZE)
  btn:SetHeight(BUTTON_SIZE)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetWidth(53)
  overlay:SetHeight(53)
  overlay:SetPoint("TOPLEFT", 0, 0)

  if GreedQuestConfig and GreedQuestConfig.minimap then
    GreedQuestConfig.minimap.icon = "Interface\\Icons\\INV_Misc_Note_01"
  end
  local iconPath = "Interface\\Icons\\INV_Misc_Note_01"

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(iconPath)
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  btn.icon = icon

  btn:SetScript("OnClick", function()
    if arg1 == "LeftButton" then
      if IsShiftKeyDown() then
        if GQ.Tracking and GQ.Tracking.TogglePanel then GQ.Tracking:TogglePanel() end
      else
        if GQ.Config and GQ.Config.Toggle then GQ.Config:Toggle() end
      end
    elseif arg1 == "RightButton" then
      if GQ.Tracker and GQ.Tracker.Toggle then GQ.Tracker:Toggle() end
    end
  end)

  btn:SetScript("OnDragStart", function()
    this:SetScript("OnUpdate", function()
      MM:DragUpdate()
    end)
  end)
  btn:SetScript("OnDragStop", function()
    this:SetScript("OnUpdate", nil)
  end)

  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ffccGreedQuest|r", 1, 1, 1)
    GameTooltip:AddLine("Left-click: Settings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Shift-Left: Optional tracking", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Tracker", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.button = btn
  self:UpdatePosition()
  self:UpdateVisibility()
  GQ:Debug("Minimap button ready")
end

function MM:DragUpdate()
  local mx, my = GetCursorPosition()
  local cx, cy = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local dx = mx / scale - cx
  local dy = my / scale - cy
  local angle = math.deg(math.atan2(dy, dx))
  if GreedQuestConfig and GreedQuestConfig.minimap then
    GreedQuestConfig.minimap.angle = angle
  end
  self:UpdatePosition()
end

function MM:UpdatePosition()
  if not self.button then return end
  local angle = (GreedQuestConfig and GreedQuestConfig.minimap and GreedQuestConfig.minimap.angle) or 220
  local radius = (GreedQuestConfig and GreedQuestConfig.minimap and GreedQuestConfig.minimap.radius) or 80
  local rad = math.rad(angle)
  self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

function MM:UpdateVisibility()
  if not self.button then return end
  if GreedQuestConfig and GreedQuestConfig.minimap and GreedQuestConfig.minimap.enabled then
    self.button:Show()
  else
    self.button:Hide()
  end
end
