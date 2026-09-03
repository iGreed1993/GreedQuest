--[[
  GreedQuest Quest Detail panel
  Shown from Database search. Uses live quest log text/rewards when the
  quest is in the log; otherwise shows structured DB info (1.12 has no
  full quest text API for unaccepted quests).
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.QuestDetail = GQ.QuestDetail or {}
local QD = GQ.QuestDetail

local function FS(parent, template)
  return parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
end

function QD:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", "GreedQuestDetailFrame", UIParent)
  f:SetWidth(420)
  f:SetHeight(460)
  f:SetPoint("CENTER", 80, 20)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  f:SetBackdropColor(0, 0, 0, 0.95)
  f:Hide()

  local title = FS(f, "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("|cff33ffccGreedQuest|r")
  f.headerTitle = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)
  close:SetScript("OnClick", function() f:Hide() end)

  local scroll = CreateFrame("ScrollFrame", "GQDetailScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 18, -40)
  scroll:SetPoint("BOTTOMRIGHT", -40, 50)

  local child = CreateFrame("Frame", "GQDetailChild", scroll)
  child:SetWidth(360)
  child:SetHeight(800)
  scroll:SetScrollChild(child)
  f.child = child

  -- body text (multi-line via fontstring with set width)
  local body = FS(child, "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", 4, -4)
  body:SetWidth(350)
  body:SetJustifyH("LEFT")
  body:SetJustifyV("TOP")
  f.body = body

  local mapBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  mapBtn:SetWidth(120)
  mapBtn:SetHeight(22)
  mapBtn:SetPoint("BOTTOMLEFT", 20, 18)
  mapBtn:SetText("Show on Map")
  mapBtn:SetScript("OnClick", function()
    if f.questID and GQ.Map and GQ.Map.ShowQuestInDatabase then
      GQ.Map:ShowQuestInDatabase(f.questID, f.questTitle)
    end
  end)

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  closeBtn:SetWidth(80)
  closeBtn:SetHeight(22)
  closeBtn:SetPoint("BOTTOMRIGHT", -20, 18)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  self.frame = f
end

local function RaceText(mask)
  if not mask or mask == 0 or mask == 255 then return "Any" end
  local names = {
    {1, "Human"}, {2, "Orc"}, {4, "Dwarf"}, {8, "Night Elf"},
    {16, "Undead"}, {32, "Tauren"}, {64, "Gnome"}, {128, "Troll"},
  }
  local out = {}
  for i = 1, getn(names) do
    local bitv, name = names[i][1], names[i][2]
    if math.mod(mask, bitv * 2) >= bitv then
      table.insert(out, name)
    end
  end
  if getn(out) == 0 then return "Any" end
  return table.concat(out, ", ")
end

local function ClassText(mask)
  if not mask or mask == 0 then return "Any" end
  local names = {
    {1, "Warrior"}, {2, "Paladin"}, {4, "Hunter"}, {8, "Rogue"},
    {16, "Priest"}, {64, "Shaman"}, {128, "Mage"}, {256, "Warlock"}, {1024, "Druid"},
  }
  local out = {}
  for i = 1, getn(names) do
    local bitv, name = names[i][1], names[i][2]
    if math.mod(mask, bitv * 2) >= bitv then
      table.insert(out, name)
    end
  end
  if getn(out) == 0 then return "Any" end
  return table.concat(out, ", ")
end

local function FormatIdList(ids, label)
  if not ids then return nil end
  local parts = {}
  for _, id in pairs(ids) do
    table.insert(parts, tostring(id))
  end
  if getn(parts) == 0 then return nil end
  return label .. ": " .. table.concat(parts, ", ")
end

function QD:FindInQuestLog(questID, title)
  if not GQ.Core or not GQ.Core.questLog then return nil end
  for _, q in pairs(GQ.Core.questLog) do
    if questID and q.questID == questID then return q end
    if title and q.title and string.lower(q.title) == string.lower(title) then return q end
  end
  return nil
end

function QD:BuildText(questID, title)
  local lines = {}
  local qdata = GQ.Database and GQ.Database:GetQuest(questID)
  local logQ = self:FindInQuestLog(questID, title)

  title = title or (GreedQuestDB and GreedQuestDB.questTitles and GreedQuestDB.questTitles[questID]) or ("Quest " .. tostring(questID))

  table.insert(lines, "|cffffd100" .. title .. "|r")
  table.insert(lines, "|cffaaaaaaID: " .. tostring(questID) .. "|r")
  table.insert(lines, " ")

  local lvl = qdata and qdata["lvl"]
  local minL = qdata and qdata["min"]
  if logQ and logQ.level and logQ.level > 0 then lvl = logQ.level end
  if lvl then table.insert(lines, "Level: |cffffffff" .. tostring(lvl) .. "|r") end
  if minL then table.insert(lines, "Required level: |cffffffff" .. tostring(minL) .. "|r") end
  if qdata and qdata["race"] then
    table.insert(lines, "Race: |cffffffff" .. RaceText(qdata["race"]) .. "|r")
  end
  if qdata and qdata["class"] then
    table.insert(lines, "Class: |cffffffff" .. ClassText(qdata["class"]) .. "|r")
  end

  -- Live quest log content when available
  if logQ then
    table.insert(lines, " ")
    table.insert(lines, "|cff33ffcc—— From your quest log ——|r")
    if logQ.complete then
      table.insert(lines, "|cff55ff55Status: Ready to turn in|r")
    else
      table.insert(lines, "|cffffd100Status: In progress|r")
    end
    if logQ.description and logQ.description ~= "" then
      table.insert(lines, " ")
      table.insert(lines, "|cffffd100Description|r")
      table.insert(lines, logQ.description)
    end
    if logQ.objectiveText and logQ.objectiveText ~= "" then
      table.insert(lines, " ")
      table.insert(lines, "|cffffd100Objectives|r")
      table.insert(lines, logQ.objectiveText)
    end
    if logQ.objectives and getn(logQ.objectives) > 0 then
      table.insert(lines, " ")
      table.insert(lines, "|cffffd100Progress|r")
      for _, obj in ipairs(logQ.objectives) do
        if obj.finished then
          table.insert(lines, "  |cff55ff55" .. (obj.text or "") .. "|r")
        else
          table.insert(lines, "  |cffffffff" .. (obj.text or "") .. "|r")
        end
      end
    end

    -- Rewards from log entry
    if logQ.index and SelectQuestLogEntry then
      local prev = GetQuestLogSelection and GetQuestLogSelection() or 0
      SelectQuestLogEntry(logQ.index)
      local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney() or 0
      local numRew = GetNumQuestLogRewards and GetNumQuestLogRewards() or 0
      local numChoice = GetNumQuestLogChoices and GetNumQuestLogChoices() or 0
      local xp = 0
      if GetQuestLogRewardXP then xp = GetQuestLogRewardXP() or 0 end

      table.insert(lines, " ")
      table.insert(lines, "|cffffd100Rewards|r")
      if money and money > 0 then
        table.insert(lines, "  Money: |cffffffff" .. tostring(money) .. "c|r")
      end
      if xp and xp > 0 then
        table.insert(lines, "  XP: |cffffffff" .. tostring(xp) .. "|r")
      end
      if numRew and numRew > 0 and GetQuestLogRewardInfo then
        for i = 1, numRew do
          local name, texture, numItems, quality, isUsable = GetQuestLogRewardInfo(i)
          if name then
            local count = (numItems and numItems > 1) and (" x" .. numItems) or ""
            table.insert(lines, "  |cff33ff33" .. name .. count .. "|r")
          end
        end
      end
      if numChoice and numChoice > 0 and GetQuestLogChoiceInfo then
        table.insert(lines, "  |cffffd100Choose one:|r")
        for i = 1, numChoice do
          local name, texture, numItems = GetQuestLogChoiceInfo(i)
          if name then
            local count = (numItems and numItems > 1) and (" x" .. numItems) or ""
            table.insert(lines, "  |cff66ccff" .. name .. count .. "|r")
          end
        end
      end
      if (not money or money == 0) and (not numRew or numRew == 0) and (not numChoice or numChoice == 0) and (not xp or xp == 0) then
        table.insert(lines, "  |cff888888(No item/money rewards listed)|r")
      end
      if prev and prev > 0 then SelectQuestLogEntry(prev) end
    end
  else
    table.insert(lines, " ")
    table.insert(lines, "|cff888888Not in your quest log — full Blizzard quest text is only available for accepted quests on 1.12.|r")
    local objText = GreedQuestDB and GreedQuestDB.questObjectives and GreedQuestDB.questObjectives[questID]
    if objText and objText ~= "" then
      table.insert(lines, " ")
      table.insert(lines, "|cffffd100Objectives|r")
      local rest = objText
      while rest and rest ~= "" do
        local br = string.find(rest, "\n", 1, true)
        local piece
        if br then
          piece = string.sub(rest, 1, br - 1)
          rest = string.sub(rest, br + 1)
        else
          piece = rest
          rest = ""
        end
        if piece and piece ~= "" then
          table.insert(lines, "  |cffffffff" .. piece .. "|r")
        end
      end
    end
  end

  -- Database structure
  if qdata then
    table.insert(lines, " ")
    table.insert(lines, "|cff33ffcc—— Database ——|r")

    if qdata["pre"] then
      local pres = {}
      for _, pid in pairs(qdata["pre"]) do
        local pt = GreedQuestDB and GreedQuestDB.questTitles and GreedQuestDB.questTitles[pid]
        table.insert(pres, (pt or ("#" .. pid)))
      end
      if getn(pres) > 0 then
        table.insert(lines, "Requires: |cffffffff" .. table.concat(pres, ", ") .. "|r")
      end
    end

    if qdata["start"] then
      local s = FormatIdList(qdata["start"]["U"], "Start NPC IDs")
      if s then table.insert(lines, s) end
      s = FormatIdList(qdata["start"]["O"], "Start object IDs")
      if s then table.insert(lines, s) end
      s = FormatIdList(qdata["start"]["I"], "Start item IDs")
      if s then table.insert(lines, s) end
    end

    if qdata["obj"] then
      table.insert(lines, "|cffffd100Objectives (DB)|r")
      local s = FormatIdList(qdata["obj"]["U"], "  Kill/talk NPC IDs")
      if s then table.insert(lines, s) end
      s = FormatIdList(qdata["obj"]["O"], "  Object IDs")
      if s then table.insert(lines, s) end
      s = FormatIdList(qdata["obj"]["I"], "  Item IDs")
      if s then table.insert(lines, s) end
    end

    if qdata["end"] then
      local s = FormatIdList(qdata["end"]["U"], "Turn-in NPC IDs")
      if s then table.insert(lines, s) end
      s = FormatIdList(qdata["end"]["O"], "Turn-in object IDs")
      if s then table.insert(lines, s) end
    end
  end

  return table.concat(lines, "\n"), title
end

function QD:ShowQuest(questID, title, level)
  self:Show(questID, title)
end

function QD:Show(questID, title)
  self:Init()
  local text, resolvedTitle = self:BuildText(questID, title)
  self.frame.questID = questID
  self.frame.questTitle = resolvedTitle
  self.frame.headerTitle:SetText("|cff33ffccQuest|r")
  self.frame.body:SetText(text)

  -- Approximate height from line count
  local _, count = string.gsub(text, "\n", "\n")
  local h = math.max(200, (count + 2) * 14)
  self.frame.child:SetHeight(h)
  self.frame:Show()
end

function QD:Hide()
  if self.frame then self.frame:Hide() end
end
