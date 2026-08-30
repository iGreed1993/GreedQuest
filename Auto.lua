--[[
  GreedQuest Auto
  Optional auto-accept and auto-turn-in for 1.12 (Turtle / Octo).
  Disabled by default. Reward-choice quests are never auto-completed.
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Auto = GQ.Auto or {}
local Auto = GQ.Auto

local function AutoAcceptEnabled()
  return GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.autoAccept
end

local function AutoTurnInEnabled()
  return GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.autoTurnIn
end

-- QUEST_DETAIL: new quest offered
local function OnQuestDetail()
  if not AutoAcceptEnabled() then return end
  if AcceptQuest then
    AcceptQuest()
  end
end

-- QUEST_PROGRESS: intermediate "continue" dialog; complete if ready
local function OnQuestProgress()
  if not AutoTurnInEnabled() then return end
  if IsQuestCompletable and IsQuestCompletable() then
    if CompleteQuest then
      CompleteQuest()
    end
  end
end

-- QUEST_COMPLETE: final reward screen
-- Only auto if there is no reward choice (GetNumQuestChoices == 0)
local function OnQuestComplete()
  if not AutoTurnInEnabled() then return end
  local numChoices = 0
  if GetNumQuestChoices then
    numChoices = GetNumQuestChoices() or 0
  end
  if numChoices > 0 then
    -- Player must pick a reward; do not auto-complete
    return
  end
  if GetQuestReward then
    -- index 0 / nil is fine when no choices on most 1.12 clients
    GetQuestReward(0)
  elseif CompleteQuest then
    CompleteQuest()
  end
end

-- GOSSIP_SHOW / QUEST_GREETING: multi-quest NPC
-- Auto-select the first available or active quest only when exactly one option
-- of the relevant type exists (avoids grabbing the wrong quest).
local function OnGossipOrGreeting()
  local accept = AutoAcceptEnabled()
  local turnin = AutoTurnInEnabled()
  if not accept and not turnin then return end

  -- Active (turn-in) first when auto-turn-in is on
  if turnin and GetNumGossipActiveQuests and SelectGossipActiveQuest then
    local n = GetNumGossipActiveQuests() or 0
    if n == 1 then
      SelectGossipActiveQuest(1)
      return
    end
  end
  if turnin and GetNumActiveQuests and SelectActiveQuest then
    -- QUEST_GREETING style
    local n = GetNumActiveQuests() or 0
    if n == 1 then
      SelectActiveQuest(1)
      return
    end
  end

  -- Available (accept)
  if accept and GetNumGossipAvailableQuests and SelectGossipAvailableQuest then
    local n = GetNumGossipAvailableQuests() or 0
    if n == 1 then
      SelectGossipAvailableQuest(1)
      return
    end
  end
  if accept and GetNumAvailableQuests and SelectAvailableQuest then
    local n = GetNumAvailableQuests() or 0
    if n == 1 then
      SelectAvailableQuest(1)
      return
    end
  end
end

function Auto:Init()
  local f = CreateFrame("Frame")
  f:RegisterEvent("QUEST_DETAIL")
  f:RegisterEvent("QUEST_PROGRESS")
  f:RegisterEvent("QUEST_COMPLETE")
  f:RegisterEvent("GOSSIP_SHOW")
  f:RegisterEvent("QUEST_GREETING")

  f:SetScript("OnEvent", function()
    if event == "QUEST_DETAIL" then
      OnQuestDetail()
    elseif event == "QUEST_PROGRESS" then
      OnQuestProgress()
    elseif event == "QUEST_COMPLETE" then
      OnQuestComplete()
    elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
      OnGossipOrGreeting()
    end
  end)

  GQ:Debug("Auto module ready (accept/turn-in)")
end
