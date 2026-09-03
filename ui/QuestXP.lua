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

function QX:BaseXP(qid, questLevel)
  if GetRewardXP then
    local ok, v = pcall(GetRewardXP)
    if ok and type(v) == "number" and v > 0 then return v, true end
  end
  if GetQuestLogRewardXP then
    local ok, v = pcall(GetQuestLogRewardXP)
    if ok and type(v) == "number" and v > 0 then return v, true end
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

function QX:AdjustedXP(qid, questLevel)
  local base, live = self:BaseXP(qid, questLevel)
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

local origRewardText

local function ApplyRewardLabel()
  local fs = QuestRewardTitleText
  if not fs or not fs.SetText then return end
  if not origRewardText then
    origRewardText = fs:GetText() or (REWARDS or "Rewards")
  end
  local qid, _, lvl = CurrentQuest()
  local xp, grey = QX:AdjustedXP(qid, lvl)
  if not xp or xp < 0 then
    fs:SetText(origRewardText)
    return
  end
  local extra
  if xp == 0 then
    extra = "|cff888888(0 XP)|r"
  elseif grey then
    extra = "|cffaaaaaa" .. tostring(xp) .. " XP|r"
  else
    extra = "|cff33ffcc" .. tostring(xp) .. " XP|r"
  end
  fs:SetText(origRewardText .. "   " .. extra)
end

local function RestoreRewardLabel()
  local fs = QuestRewardTitleText
  if fs and origRewardText and fs.SetText then
    fs:SetText(origRewardText)
  end
end

function QX:Init()
  if self._inited then return end
  self._inited = true
  local f = CreateFrame("Frame")
  f:RegisterEvent("QUEST_DETAIL")
  f:RegisterEvent("QUEST_COMPLETE")
  f:RegisterEvent("QUEST_FINISHED")
  f:RegisterEvent("QUEST_GREETING")
  f:SetScript("OnEvent", function()
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
      ApplyRewardLabel()
    else
      RestoreRewardLabel()
    end
  end)
end
