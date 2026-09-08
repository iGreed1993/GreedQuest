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

local function AppendRewardLine(fs, line)
  if not Visible(fs) or not line then return false end
  local cur = fs:GetText() or ""
  if string.find(cur, "Reward: XP (", 1, true) then
    return true
  end
  if not patched[fs] then patched[fs] = cur end
  local base = patched[fs]
  if base ~= "" then
    fs:SetText(base .. "\n\n" .. line)
  else
    fs:SetText(line)
  end
  return true
end

local gossipXpLabel

local function HideGossipXP()
  if gossipXpLabel then gossipXpLabel:Hide() end
end

local function PlaceBlackBeside(anchor, text)
  if not anchor then return end
  if not gossipXpLabel then
    local parent = anchor:GetParent() or QuestFrame
    gossipXpLabel = parent:CreateFontString("GreedQuestXPLabel", "OVERLAY")
    gossipXpLabel:SetFontObject(QuestFont or GameFontHighlight)
    gossipXpLabel:SetJustifyH("LEFT")
  end
  gossipXpLabel:ClearAllPoints()
  gossipXpLabel:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
  gossipXpLabel:SetTextColor(0, 0, 0)
  gossipXpLabel:SetText(text)
  gossipXpLabel:Show()
end

local origRewardText

local function ApplyRewardLabel()
  RestorePatched()
  HideGossipXP()
  local qid, _, lvl = CurrentQuest()
  local xp = QX:AdjustedXP(qid, lvl)
  if not xp then return end

  local fs = QuestRewardTitleText
  if HasItemOrMoneyReward() and fs and fs.IsShown and fs:IsShown() then
    if not origRewardText then
      origRewardText = fs:GetText() or (REWARDS or "Rewards")
    end
    if origRewardText then fs:SetText(origRewardText) end
    PlaceBlackBeside(fs, tostring(xp) .. " XP")
    return
  end
  if origRewardText and fs and fs.SetText then
    fs:SetText(origRewardText)
  end

  local line = RewardLine(xp)
  if AppendRewardLine(QuestDescription, line) then return end
  if AppendRewardLine(QuestObjectiveText, line) then return end
  AppendRewardLine(QuestProgressText, line)
end

local function RestoreRewardLabel()
  RestorePatched()
  HideGossipXP()
  local fs = QuestRewardTitleText
  if fs and origRewardText and fs.SetText then
    fs:SetText(origRewardText)
  end
end

local origLogRewardText
local logXpLabel

local function HideLogXPLabel()
  if logXpLabel then logXpLabel:Hide() end
end

local function PlaceLogBlackBeside(anchor, text)
  if not anchor then return end
  if not logXpLabel then
    local parent = anchor:GetParent() or QuestLogDetailScrollChildFrame or QuestLogFrame
    logXpLabel = parent:CreateFontString("GreedQuestLogXPLabel", "OVERLAY")
    logXpLabel:SetFontObject(QuestFont or GameFontHighlight)
    logXpLabel:SetJustifyH("LEFT")
  end
  logXpLabel:ClearAllPoints()
  logXpLabel:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
  logXpLabel:SetTextColor(0, 0, 0)
  logXpLabel:SetText(text)
  logXpLabel:Show()
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
  RestorePatched()
  HideLogXPLabel()
  if not QuestLogFrame or not QuestLogFrame:IsShown() then
    return
  end
  local qid, _, lvl = SelectedLogQuest()
  local xp = QX:AdjustedXP(qid, lvl, true)
  if not xp then return end

  local fs = QuestLogRewardTitleText
  if LogHasItemOrMoney() and fs and fs.IsShown and fs:IsShown() then
    if not origLogRewardText then
      origLogRewardText = fs:GetText() or (REWARDS or "Rewards")
    end
    if origLogRewardText then fs:SetText(origLogRewardText) end
    PlaceLogBlackBeside(fs, tostring(xp) .. " XP")
    return
  end
  if origLogRewardText and fs and fs.SetText then
    fs:SetText(origLogRewardText)
  end

  local line = RewardLine(xp)
  if AppendRewardLine(QuestLogQuestDescription, line) then return end
  AppendRewardLine(QuestLogObjectivesText, line)
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
  f:RegisterEvent("QUEST_LOG_UPDATE")
  f:SetScript("OnEvent", function()
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then
      -- Blizzard hides the Rewards header after our event; wait one frame.
      if not QX._defer then QX._defer = CreateFrame("Frame") end
      QX._defer.t = 0
      QX._defer:SetScript("OnUpdate", function()
        QX._defer.t = QX._defer.t + (arg1 or 0.01)
        if QX._defer.t < 0.05 then return end
        QX._defer:SetScript("OnUpdate", nil)
        ApplyRewardLabel()
      end)
    elseif event == "QUEST_LOG_UPDATE" then
      if not QX._logDefer then QX._logDefer = CreateFrame("Frame") end
      QX._logDefer.t = 0
      QX._logDefer:SetScript("OnUpdate", function()
        QX._logDefer.t = QX._logDefer.t + (arg1 or 0.01)
        if QX._logDefer.t < 0.05 then return end
        QX._logDefer:SetScript("OnUpdate", nil)
        ApplyQuestLogXP()
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
