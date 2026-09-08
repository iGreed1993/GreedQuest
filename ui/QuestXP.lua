--[[
  Show quest XP on the Blizzard accept / turn-in "Rewards" header.
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.QuestXP = GQ.QuestXP or {}
local QX = GQ.QuestXP

local function GreyFactor(questLevel, playerLevel)
  if not questLevel or not playerLevel then return 1 end
  local diff = playerLevel - questLevel
  if questLevel < 10 then
    if diff <= 4 then return 1 end
    diff = diff - 1
  end
  if diff <= 5 then return 1 end
  if diff == 6 then return 0.8 end
  if diff == 7 then return 0.6 end
  if diff == 8 then return 0.4 end
  if diff == 9 then return 0.2 end
  return 0.1
end

local function RoundXP(xp)
  xp = tonumber(xp) or 0
  if xp <= 0 then return 0 end
  if xp <= 100 then
    return 5 * math.floor((xp + 2) / 5)
  elseif xp <= 500 then
    return 10 * math.floor((xp + 5) / 10)
  elseif xp <= 1000 then
    return 25 * math.floor((xp + 12) / 25)
  end
  return 50 * math.floor((xp + 25) / 50)
end

function QX:BaseXP(qid, questLevel, skipLive)
  if not skipLive then
    if GetRewardXP then
      local ok, v = pcall(GetRewardXP)
      if ok and type(v) == "number" and v > 0 then return v, true end
    end
    if GetQuestLogRewardXP then
      local ok, v = pcall(GetQuestLogRewardXP)
      if ok and type(v) == "number" and v > 0 then return v, true end
    end
  end
  local db = GreedQuestDB and GreedQuestDB.questXP
  if qid and db and db[qid] and db[qid] > 0 then
    return db[qid], false
  end
  local by = GreedQuestDB and GreedQuestDB.questXPByLevel
  if questLevel and by and by[questLevel] then
    return by[questLevel], false
  end
  return nil, false
end

function QX:AdjustedXP(qid, questLevel, skipLive)
  local base, live = self:BaseXP(qid, questLevel, skipLive)
  if not base then return nil end
  if live then return base, false end
  local pl = UnitLevel and UnitLevel("player") or 1
  if pl >= 60 then return 0, true end
  local factor = GreyFactor(questLevel or pl, pl)
  return RoundXP(base * factor), factor < 1
end

local function CurrentQuest()
  local title
  if GetTitleText then title = GetTitleText() end
  local qid, lvl
  if title and title ~= "" and GQ.Core and GQ.Core.ResolveQuestID then
    qid = GQ.Core:ResolveQuestID(title)
  end
  if qid and GreedQuestDB and GreedQuestDB.quests and GreedQuestDB.quests[qid] then
    lvl = GreedQuestDB.quests[qid]["lvl"]
  end
  if (not lvl) and GQ.Core and qid and GQ.Core.GetQuestByID then
    local q = GQ.Core:GetQuestByID(qid)
    if q then lvl = q.level end
  end
  return qid, title, lvl
end

local function XPString(xp, grey)
  if not xp or xp < 0 then return nil end
  if xp == 0 then
    return "|cff8888880 XP|r"
  elseif grey then
    return "|cffaaaaaa" .. tostring(xp) .. " XP|r"
  end
  return "|cff33ffcc" .. tostring(xp) .. " XP|r"
end

function QX:FormatXP(qid, questLevel, skipLive)
  local xp, grey = self:AdjustedXP(qid, questLevel, skipLive)
  return XPString(xp, grey), xp, grey
end

local function RewardLine(xp)
  if not xp or xp < 0 then return nil end
  return "Reward: XP (" .. tostring(xp) .. ")"
end

local function HasItemOrMoneyReward()
  local money = (GetRewardMoney and GetRewardMoney()) or 0
  local nRew = (GetNumQuestRewards and GetNumQuestRewards()) or 0
  local nChoice = (GetNumQuestChoices and GetNumQuestChoices()) or 0
  local spell
  if GetRewardSpell then spell = GetRewardSpell() end
  if money and money > 0 then return true end
  if nRew and nRew > 0 then return true end
  if nChoice and nChoice > 0 then return true end
  if spell then return true end
  return false
end

-- Remember the Blizzard text so we can append without stacking.
local patched = {}

local function Visible(fs)
  return fs and fs.GetText and (not fs.IsShown or fs:IsShown())
end

local function RestorePatched()
  local fs, base
  for fs, base in pairs(patched) do
    if fs and fs.SetText then fs:SetText(base) end
  end
  patched = {}
end

local function AlreadyHasRewardLine(fs)
  if not fs or not fs.GetText then return false end
  local cur = fs:GetText() or ""
  return string.find(cur, "Reward: XP (", 1, true) and true or false
end

local function AppendRewardLine(fs, line)
  if not Visible(fs) or not line then return false end
  if AlreadyHasRewardLine(fs) then return true end
  local cur = fs:GetText() or ""
  if not patched[fs] then patched[fs] = cur end
  if cur ~= "" then
    fs:SetText(cur .. "\n\n" .. line)
  else
    fs:SetText(line)
  end
  return true
end

local function MakeBlackLabel(existing, name, parent)
  if existing then return existing end
  if not parent then return nil end
  local lab = parent:CreateFontString(name, "OVERLAY", "QuestFont")
  if not lab.GetFont or not lab:GetFont() then
    lab:SetFont("Fonts\\FRIZQT__.TTF", 12)
  end
  lab:SetJustifyH("LEFT")
  lab:SetTextColor(0, 0, 0)
  return lab
end

local function PlaceBlackAfter(lab, anchor, text)
  if not lab or not anchor then return end
  local w = 60
  if anchor.GetStringWidth then
    w = anchor:GetStringWidth() or w
  end
  if w < 20 then w = 60 end
  lab:ClearAllPoints()
  lab:SetPoint("LEFT", anchor, "LEFT", w + 10, 0)
  lab:SetTextColor(0, 0, 0)
  lab:SetText(text)
  if lab.SetFrameLevel and anchor.GetFrameLevel then
    lab:SetFrameLevel(anchor:GetFrameLevel() + 2)
  end
  lab:Show()
end

local function FirstShown(list)
  local i
  for i = 1, getn(list) do
    local fs = list[i]
    if fs and fs.GetText and (not fs.IsShown or fs:IsShown()) then
      local t = fs:GetText()
      if t and t ~= "" then return fs end
    end
  end
  -- Prefer a shown frame even if text is empty
  for i = 1, getn(list) do
    local fs = list[i]
    if fs and (not fs.IsShown or fs:IsShown()) then return fs end
  end
  return list[1]
end

local function PlaceUnderBody(lab, text, candidates)
  if not lab then return false end
  local anchor = FirstShown(candidates)
  if not anchor then return false end
  lab:ClearAllPoints()
  lab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
  lab:SetTextColor(0, 0, 0)
  lab:SetText(text)
  if lab.SetFrameLevel and anchor.GetFrameLevel then
    lab:SetFrameLevel(anchor:GetFrameLevel() + 2)
  end
  lab:Show()
  return true
end

local gossipXpLabel

local function HideGossipXP()
  if gossipXpLabel then gossipXpLabel:Hide() end
end

local origRewardText
local lastGossipKey

local function ApplyRewardLabel()
  local qid, _, lvl = CurrentQuest()
  local xp = QX:AdjustedXP(qid, lvl)
  local key = tostring(qid or "") .. ":" .. tostring(xp or 0) .. ":" .. tostring(HasItemOrMoneyReward())
  if lastGossipKey == key then
    if gossipXpLabel and gossipXpLabel:IsShown() then return end
    if AlreadyHasRewardLine(QuestDescription) or AlreadyHasRewardLine(QuestObjectiveText) or AlreadyHasRewardLine(QuestProgressText) then
      return
    end
  end
  lastGossipKey = key
  if not xp then
    HideGossipXP()
    return
  end

  local fs = QuestRewardTitleText
  if HasItemOrMoneyReward() and fs and fs.GetText then
    if not origRewardText then
      origRewardText = fs:GetText() or (REWARDS or "Rewards")
    end
    gossipXpLabel = MakeBlackLabel(gossipXpLabel, "GreedQuestXPLabel", fs:GetParent() or QuestFrame)
    PlaceBlackAfter(gossipXpLabel, fs, tostring(xp) .. " XP")
    return
  end
  HideGossipXP()

  local line = RewardLine(xp)
  gossipXpLabel = MakeBlackLabel(gossipXpLabel, "GreedQuestXPLabel", QuestFrame)
  PlaceUnderBody(gossipXpLabel, line, {
    QuestDescription,
    QuestObjectiveText,
    QuestProgressText,
  })
end

local function RestoreRewardLabel()
  lastGossipKey = nil
  RestorePatched()
  HideGossipXP()
  local fs = QuestRewardTitleText
  if fs and origRewardText and fs.SetText then
    fs:SetText(origRewardText)
  end
end

local origLogRewardText
local logXpLabel
local lastLogKey

local function HideLogXPLabel()
  if logXpLabel then logXpLabel:Hide() end
end

local function SelectedLogQuest()
  local idx = GetQuestLogSelection and GetQuestLogSelection() or 0
  if not idx or idx <= 0 then return nil end
  local title, level, tag, isHeader = GetQuestLogTitle(idx)
  if isHeader or not title then return nil end
  local qid
  if GQ.Core and GQ.Core.ResolveQuestID then
    qid = GQ.Core:ResolveQuestID(title)
  end
  return qid, title, level
end

local function LogHasItemOrMoney()
  local money = (GetQuestLogRewardMoney and GetQuestLogRewardMoney()) or 0
  local nRew = (GetNumQuestLogRewards and GetNumQuestLogRewards()) or 0
  local nChoice = (GetNumQuestLogChoices and GetNumQuestLogChoices()) or 0
  if money and money > 0 then return true end
  if nRew and nRew > 0 then return true end
  if nChoice and nChoice > 0 then return true end
  return false
end

local function ApplyQuestLogXP()
  if not QuestLogFrame or not QuestLogFrame:IsShown() then
    return
  end
  local qid, _, lvl = SelectedLogQuest()
  local xp = QX:AdjustedXP(qid, lvl, true)
  local hasRew = LogHasItemOrMoney()
  local key = tostring(qid or "") .. ":" .. tostring(xp or 0) .. ":" .. tostring(hasRew)
  if lastLogKey == key then
    if hasRew and logXpLabel and logXpLabel.IsShown and logXpLabel:IsShown() then
      return
    end
    if (not hasRew) and (AlreadyHasRewardLine(QuestLogQuestDescription) or AlreadyHasRewardLine(QuestLogObjectivesText)) then
      return
    end
  end
  lastLogKey = key
  if not xp then
    HideLogXPLabel()
    return
  end

  local parent = QuestLogDetailScrollChildFrame or QuestLogFrame
  local fs = QuestLogRewardTitleText
  logXpLabel = MakeBlackLabel(logXpLabel, "GreedQuestLogXPLabel", (fs and fs.GetParent and fs:GetParent()) or parent)
  if hasRew and fs and fs.GetText then
    PlaceBlackAfter(logXpLabel, fs, tostring(xp) .. " XP")
    return
  end

  PlaceUnderBody(logXpLabel, RewardLine(xp), {
    QuestLogQuestDescription,
    QuestLogObjectivesText,
    QuestLogObjectiveText,
  })
end

function QX:Init()
  if self._inited then return end
  self._inited = true
  local f = CreateFrame("Frame")
  f:RegisterEvent("QUEST_DETAIL")
  f:RegisterEvent("QUEST_PROGRESS")
  f:RegisterEvent("QUEST_COMPLETE")
  f:RegisterEvent("QUEST_FINISHED")
  f:RegisterEvent("QUEST_GREETING")
  f:SetScript("OnEvent", function()
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then
      lastGossipKey = nil
      -- Blizzard hides the Rewards header after our event; wait one frame.
      if not QX._defer then QX._defer = CreateFrame("Frame") end
      QX._defer.t = 0
      QX._defer:SetScript("OnUpdate", function()
        QX._defer.t = QX._defer.t + (arg1 or 0.01)
        if QX._defer.t < 0.05 then return end
        QX._defer:SetScript("OnUpdate", nil)
        ApplyRewardLabel()
      end)
    else
      RestoreRewardLabel()
    end
  end)

  if QuestLogFrame then
    local prevShow = QuestLogFrame:GetScript("OnShow")
    QuestLogFrame:SetScript("OnShow", function()
      if prevShow then prevShow() end
      ApplyQuestLogXP()
    end)
    local prevHide = QuestLogFrame:GetScript("OnHide")
    QuestLogFrame:SetScript("OnHide", function()
      if prevHide then prevHide() end
      lastLogKey = nil
      HideLogXPLabel()
      RestorePatched()
      if QuestLogRewardTitleText and origLogRewardText then
        QuestLogRewardTitleText:SetText(origLogRewardText)
      end
    end)
  end
  if QuestLog_Update then
    local orig = QuestLog_Update
    QuestLog_Update = function()
      orig()
      ApplyQuestLogXP()
    end
  end
end
