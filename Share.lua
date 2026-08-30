--[[
  GreedQuest Party Progress Share
  Broadcasts objective progress to party; receives others' progress.
  Uses SendAddonMessage when available (common on 1.12 private servers).
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Share = GQ.Share or {}
local Share = GQ.Share

local PREFIX = "GreedQuest"

-- partyProgress[playerName][questKey] = {
--   complete = bool,
--   objectives = { { text=..., finished=bool }, ... }
-- }
Share.partyProgress = {}
Share.lastSend = 0

local function IsShareEnabled()
  -- Party progress share is always on; display is controlled by tooltips.showParty
  return true
end

local function InParty()
  return (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
end

local function SanitizeAddonText(s)
  s = tostring(s or "")
  s = string.gsub(s, "|", "/")
  s = string.gsub(s, "%%", "/")
  s = string.gsub(s, "	", " ")
  s = string.gsub(s, "~", "-")
  return s
end

local function SafeSend(msg)
  if not SendAddonMessage then return end
  if not InParty() then return end
  if not msg or msg == "" then return end
  -- DFRL / some 1.12 clients parse addon payloads like chat (|T texture, % escapes).
  if string.find(msg, "|", 1, true) or string.find(msg, "%%", 1, true) then
    msg = string.gsub(msg, "|", "/")
    msg = string.gsub(msg, "%%", "/")
  end
  if pcall then
    pcall(SendAddonMessage, PREFIX, msg, "PARTY")
  else
    SendAddonMessage(PREFIX, msg, "PARTY")
  end
end

function Share:QuestKey(title, questID)
  if questID then return "id:" .. tostring(questID) end
  if title then return "t:" .. string.lower(title) end
  return nil
end

function Share:BuildPayload()
  local log = GQ.Core and GQ.Core.questLog
  if not log then return {} end

  local messages = {}
  for _, q in pairs(log) do
    if q.title then
      -- Format: Q|<title>|<complete 0/1>|<objText>~<0/1>|...
      local parts = {}
      table.insert(parts, "Q")
      table.insert(parts, SanitizeAddonText(q.title))
      table.insert(parts, q.complete and "1" or "0")
      if q.objectives then
        for _, obj in ipairs(q.objectives) do
          local ot = SanitizeAddonText(obj.text or "")
          table.insert(parts, ot .. "~" .. (obj.finished and "1" or "0"))
        end
      end
      -- Tab delimiter: "|" + "The ..." becomes "|T..." which 1.12 treats as a texture escape.
      local msg = table.concat(parts, "	")
      -- Keep under typical addon message limits
      if string.len(msg) > 240 then
        msg = string.sub(msg, 1, 240)
      end
      table.insert(messages, msg)
    end
  end
  return messages
end

function Share:Broadcast()
  if not IsShareEnabled() then return end
  if not InParty() then return end
  if not SendAddonMessage then
    GQ:Debug("Share: SendAddonMessage not available on this client")
    return
  end

  local now = GetTime and GetTime() or 0
  if now - self.lastSend < 1.0 then return end  -- throttle
  self.lastSend = now

  local msgs = self:BuildPayload()
  for _, msg in ipairs(msgs) do
    SafeSend(msg)
  end
end

function Share:ParseMessage(sender, msg)
  if not msg or not sender then return end
  local sep = "	"
  if string.sub(msg, 1, 2) == "Q	" then
    sep = "	"
  elseif string.sub(msg, 1, 2) == "Q|" then
    sep = "|"
  else
    return
  end

  -- Q<sep>title<sep>complete<sep>obj~fin...
  local fields = {}
  local pat = "[^" .. sep .. "]+"
  for part in string.gfind(msg, pat) do
    table.insert(fields, part)
  end
  if getn(fields) < 3 then return end
  if fields[1] ~= "Q" then return end

  local title = fields[2]
  local complete = fields[3] == "1"
  local objectives = {}
  for i = 4, getn(fields) do
    local _, _, text, fin = string.find(fields[i], "^(.*)~([01])$")
    if text then
      table.insert(objectives, {
        text = text,
        finished = (fin == "1"),
      })
    end
  end

  local player = sender
  -- strip realm if present
  local _, _, plain = string.find(sender, "([^%-]+)")
  if plain then player = plain end

  if not self.partyProgress[player] then
    self.partyProgress[player] = {}
  end

  local key = self:QuestKey(title, nil)
  self.partyProgress[player][key] = {
    title = title,
    complete = complete,
    objectives = objectives,
    time = GetTime and GetTime() or 0,
  }

  -- Also index by resolved questID if we know it
  if GQ.Core and GQ.Core.ResolveQuestID then
    local qid = GQ.Core:ResolveQuestID(title)
    if qid then
      self.partyProgress[player][self:QuestKey(nil, qid)] = self.partyProgress[player][key]
    end
  end
end

function Share:GetPartyProgress(questID, title)
  local results = {}
  local keyId = questID and self:QuestKey(nil, questID) or nil
  local keyTitle = title and self:QuestKey(title, nil) or nil

  for player, quests in pairs(self.partyProgress) do
    local data = (keyId and quests[keyId]) or (keyTitle and quests[keyTitle])
    if data then
      table.insert(results, {
        player = player,
        complete = data.complete,
        objectives = data.objectives,
      })
    end
  end
  return results
end

function Share:AddProgressToTooltip(questID, title, skipLocal)
  local dens = GreedQuestConfig and GreedQuestConfig.tooltips and GreedQuestConfig.tooltips.density
  if dens == "off" then return end
  local compact = dens == "compact"
  local showParty = not (GreedQuestConfig and GreedQuestConfig.tooltips and GreedQuestConfig.tooltips.showParty == false)

  -- Local objectives (skipped when caller already printed them)
  if not skipLocal then
    local localQ = nil
    if GQ.Core and GQ.Core.questLog then
      for _, q in pairs(GQ.Core.questLog) do
        if (questID and q.questID == questID) or (title and q.title == title) then
          localQ = q
          break
        end
      end
    end

    if localQ and localQ.objectives and getn(localQ.objectives) > 0 then
      GameTooltip:AddLine(" ")
      for _, obj in ipairs(localQ.objectives) do
        if obj.finished then
          GameTooltip:AddLine("  |cff55ff55" .. (obj.text or "") .. "|r")
        else
          GameTooltip:AddLine("  |cffffffff" .. (obj.text or "") .. "|r")
        end
        if compact then break end
      end
    end
  end

  -- Party progress
  if not IsShareEnabled() or not showParty then return end
  local party = self:GetPartyProgress(questID, title)
  if getn(party) == 0 then return end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Party progress", 1, 0.85, 0.2)
  for _, entry in ipairs(party) do
    if entry.complete then
      GameTooltip:AddLine("  |cff55ff55" .. entry.player .. ": Complete|r")
    else
      GameTooltip:AddLine("  |cffffd100" .. entry.player .. "|r")
      if entry.objectives then
        for _, obj in ipairs(entry.objectives) do
          if obj.finished then
            GameTooltip:AddLine("    |cff55ff55" .. (obj.text or "") .. "|r")
          else
            GameTooltip:AddLine("    |cffaaaaaa" .. (obj.text or "") .. "|r")
          end
        end
      end
    end
  end
end

function Share:Init()
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("PARTY_MEMBERS_CHANGED")
  f:RegisterEvent("QUEST_LOG_UPDATE")

  f:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
      -- arg1 = prefix, arg2 = message, arg3 = channel, arg4 = sender
      if arg1 == PREFIX then
        local me = UnitName("player")
        if arg4 and arg4 ~= me then
          Share:ParseMessage(arg4, arg2)
        end
      end
    elseif event == "QUEST_LOG_UPDATE" then
      Share:Broadcast()
    elseif event == "PARTY_MEMBERS_CHANGED" then
      Share:Broadcast()
    end
  end)

  -- Initial broadcast shortly after login if in party
  local delay = CreateFrame("Frame")
  local t = 0
  delay:SetScript("OnUpdate", function()
    t = t + (arg1 or 0.1)
    if t > 3 then
      delay:SetScript("OnUpdate", nil)
      Share:Broadcast()
    end
  end)

  GQ:Debug("Share module ready")
end
