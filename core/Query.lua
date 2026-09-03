--[[
  GreedQuest completed-quest discovery
  1) TurtleWoW: .queststatus -> CHAT_MSG_ADDON "TWQUEST"
  2) IsQuestFlaggedCompleted / GetQuestsCompleted if the client provides them
  3) Import another helper's completed-quest history when present
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Query = GQ.Query or {}
local Query = GQ.Query

local function SplitWords(str)
  local fields = {}
  if not str then return fields end
  string.gsub(str, "([^%s]+)", function(c)
    table.insert(fields, c)
  end)
  return fields
end

local function EnsureCompleted()
  if not GreedQuestCharDB then GreedQuestCharDB = {} end
  if not GreedQuestCharDB.completed then GreedQuestCharDB.completed = {} end
  return GreedQuestCharDB.completed
end

-- Mark one quest + closed quests + prequests
function Query:MarkComplete(qid, stamp)
  if not qid or not tonumber(qid) then return end
  qid = tonumber(qid)
  local completed = EnsureCompleted()
  local key = "id:" .. qid
  if completed[key] then return end

  completed[key] = stamp or (time and time()) or 1

  -- Title key too
  if GreedQuestDB and GreedQuestDB.questTitles and GreedQuestDB.questTitles[qid] then
    completed["t:" .. string.lower(GreedQuestDB.questTitles[qid])] = completed[key]
  end

  local qdata = GQ.Database and GQ.Database:GetQuest(qid)
  if qdata then
    if qdata["close"] then
      for _, cq in pairs(qdata["close"]) do
        self:MarkComplete(cq, stamp)
      end
    end
    if qdata["pre"] then
      for _, pq in pairs(qdata["pre"]) do
        self:MarkComplete(pq, stamp)
      end
    end
  end
end

function Query:ImportExternalHistory()
  if not pfQuest_history then return 0 end
  local n = 0
  for qid, _ in pairs(pfQuest_history) do
    if tonumber(qid) then
      local before = EnsureCompleted()["id:" .. tonumber(qid)]
      self:MarkComplete(tonumber(qid))
      if not before then n = n + 1 end
    end
  end
  return n
end

function Query:TryNativeAPIs()
  local n = 0
  -- Modern / backported API
  if IsQuestFlaggedCompleted and GreedQuestDB and GreedQuestDB.quests then
    for qid, _ in pairs(GreedQuestDB.quests) do
      if type(qid) == "number" and IsQuestFlaggedCompleted(qid) then
        local before = EnsureCompleted()["id:" .. qid]
        self:MarkComplete(qid)
        if not before then n = n + 1 end
      end
    end
  end

  if GetQuestsCompleted then
    local ok, tbl = pcall(GetQuestsCompleted)
    if ok and type(tbl) == "table" then
      for qid, v in pairs(tbl) do
        if v and tonumber(qid) then
          local id = tonumber(qid)
          local before = EnsureCompleted()["id:" .. id]
          self:MarkComplete(id)
          if not before then n = n + 1 end
        end
      end
    end
  end
  return n
end

function Query:FinishBatch(count, source)
  DEFAULT_CHAT_FRAME:AddMessage(string.format(
    "|cff33ffccGreedQuest|r: Marked %d quests completed (%s).",
    count or 0, source or "query"))
  if GQ.Core and GQ.Core.InvalidateAvailableCache then
    GQ.Core:InvalidateAvailableCache()
    if GQ.Core.StartEligibleScan then GQ.Core:StartEligibleScan() end
  end
  if GQ.Map and GQ.Map.BuildNodesFromQuestLog then
    GQ.Map:BuildNodesFromQuestLog()
  end
end

function Query:QueryServer()
  if self.busy then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: Query already running...")
    return
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: Querying server for completed quests...")
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: (Turtle: .queststatus — may take a few seconds)")

  self.busy = true
  self.batchCount = 0
  self.received = false

  if not self.frame then
    self.frame = CreateFrame("Frame")
  end

  local f = self.frame
  f.t0 = GetTime and GetTime() or 0

  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function()
    -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
    if event == "CHAT_MSG_ADDON" and arg1 == "TWQUEST" and arg2 then
      Query.received = true
      local ids = SplitWords(arg2)
      for i = 1, getn(ids) do
        local qid = tonumber(ids[i])
        if qid then
          local before = EnsureCompleted()["id:" .. qid]
          Query:MarkComplete(qid)
          if not before then
            Query.batchCount = (Query.batchCount or 0) + 1
          end
        end
      end
    end
  end)

  f:SetScript("OnUpdate", function()
    local now = GetTime and GetTime() or 0
    if now > (f.t0 or 0) + 4 then
      f:SetScript("OnUpdate", nil)
      f:UnregisterEvent("CHAT_MSG_ADDON")
      Query.busy = false
      if Query.received then
        Query:FinishBatch(Query.batchCount, "Turtle server")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: No TWQUEST response (not Turtle, or query failed). Trying fallbacks...")
        local n = 0
        n = n + (Query:ImportExternalHistory() or 0)
        n = n + (Query:TryNativeAPIs() or 0)
        if n > 0 then
          Query:FinishBatch(n, "fallback")
        else
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: No completed-quest source available. Completions will be tracked going forward.")
        end
      end
    end
  end)

  -- TurtleWoW listens for this GM/command-style chat
  if SendChatMessage then
    SendChatMessage(".queststatus", "GUILD")
  end
end

function Query:AutoImportOnLogin()
  -- Silent import of another helper's history if present
  local n = self:ImportExternalHistory()
  if n > 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r: Imported " .. n .. " completed quests from existing history.")
    if GQ.Core and GQ.Core.InvalidateAvailableCache then
      GQ.Core:InvalidateAvailableCache()
    end
  end
end

function Query:Init()
  self:AutoImportOnLogin()
  GQ:Debug("Query module ready")
end
