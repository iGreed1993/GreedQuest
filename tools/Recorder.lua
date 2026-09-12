--[[
  GreedQuest field recorder (testing builds).

  Event-driven only. Writes to SavedVariables GreedQuestRecord.
  After a session, log out and upload:
    WTF/Account/<account>/SavedVariables/GreedQuest.lua
  (the GreedQuestRecord = { ... } table)

  /gqrec on | off | status | clear
]]

GQ = GQ or GreedQuest
GQ.Recorder = GQ.Recorder or {}
local Rec = GQ.Recorder

local MAX_ROWS = 2500

local function now()
  return time and time() or 0
end

local function Chat(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest record|r: " .. tostring(msg))
  end
end

local function EnsureDB()
  if not GreedQuestRecord then GreedQuestRecord = {} end
  local db = GreedQuestRecord
  if db.enabled == nil then db.enabled = true end
  db.sessions = db.sessions or {}
  db.accepts = db.accepts or {}
  db.turnins = db.turnins or {}
  db.objectives = db.objectives or {}
  db.givers = db.givers or {}
  db.loot = db.loot or {}
  db.abandons = db.abandons or {}
  return db
end

local ALLIANCE_RACE = {
  Human = 1, Dwarf = 1, Gnome = 1, ["Night Elf"] = 1, ["High Elf"] = 1,
}
local HORDE_RACE = {
  Orc = 1, Troll = 1, Tauren = 1, Undead = 1, ["Scourge"] = 1, Goblin = 1,
}

local function FactionOfPlayer()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if f == "Alliance" or f == "Horde" then return f end
  local race = UnitRace and UnitRace("player")
  if race and ALLIANCE_RACE[race] then return "Alliance" end
  if race and HORDE_RACE[race] then return "Horde" end
  return f or "?"
end

local function PlayerMeta()
  local name = UnitName and UnitName("player") or "?"
  local class = UnitClass and UnitClass("player") or "?"
  local race = UnitRace and UnitRace("player") or "?"
  local fac = FactionOfPlayer()
  local realm = GetRealmName and GetRealmName() or "?"
  return name, class, race, fac, realm
end

local function Session()
  local db = EnsureDB()
  local name, class, race, fac, realm = PlayerMeta()
  local key = realm .. "/" .. name
  if not db.sessions[key] then
    db.sessions[key] = {
      char = name, class = class, race = race, faction = fac, realm = realm,
      started = now(), rows = 0,
    }
  end
  return db.sessions[key], key
end

local function Pos()
  local x, y = 0, 0
  if GetPlayerMapPosition then
    x, y = GetPlayerMapPosition("player")
  end
  x = tonumber(x) or 0
  y = tonumber(y) or 0
  local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  local sub = (GetSubZoneText and GetSubZoneText()) or (GetMinimapZoneText and GetMinimapZoneText()) or ""
  local zoneID
  if GQ.Map and GQ.Map.playerZoneID then
    zoneID = GQ.Map.playerZoneID
  end
  return {
    x = math.floor(x * 1000 + 0.5) / 10,
    y = math.floor(y * 1000 + 0.5) / 10,
    zone = zone,
    sub = sub,
    zoneID = zoneID,
    level = UnitLevel and UnitLevel("player") or 0,
  }
end

local function TargetInfo()
  if not UnitExists or not UnitExists("target") then return nil end
  if UnitIsPlayer and UnitIsPlayer("target") then return nil end
  return {
    name = UnitName("target"),
    level = UnitLevel and UnitLevel("target") or 0,
    classify = UnitClassification and UnitClassification("target") or "",
    creature = UnitCreatureType and UnitCreatureType("target") or "",
  }
end

local function ResolveQID(title, logIndex)
  if GQ.Core and GQ.Core.ResolveQuestID and title then
    local id = GQ.Core:ResolveQuestID(title)
    if id then return id end
  end
  if logIndex and GetQuestLogTitle then
    local t = GetQuestLogTitle(logIndex)
    if t and GQ.Core and GQ.Core.ResolveQuestID then
      return GQ.Core:ResolveQuestID(t)
    end
  end
  return nil
end

local function Trim(list)
  local n = getn(list)
  if n <= MAX_ROWS then return end
  local drop = n - MAX_ROWS
  local i
  for i = 1, MAX_ROWS do
    list[i] = list[i + drop]
  end
  for i = MAX_ROWS + 1, n do
    list[i] = nil
  end
end

local function Push(list, row)
  local db = EnsureDB()
  if not db.enabled then return end
  row.t = now()
  local sess = Session()
  row.char = sess.char
  table.insert(list, row)
  sess.rows = (sess.rows or 0) + 1
  Trim(list)
end

local pendingXP
local lastLog = {}
local lastMob
local pendingAcceptTitle

local function RememberMob()
  local info = TargetInfo()
  if info and info.name then
    lastMob = info
  end
  return info or lastMob
end

local function ParseCount(text)
  if not text then return nil, nil end
  local _, _, got, need = string.find(text, ":%s*(%d+)%s*/%s*(%d+)")
  return tonumber(got), tonumber(need)
end

local function RecentlyPushed(list, title, seconds)
  local n = getn(list or {})
  if n == 0 then return false end
  local last = list[n]
  if not last or last.title ~= title then return false end
  return (now() - (last.t or 0)) < (seconds or 5)
end

local function SnapshotLog()
  local snap = {}
  if not GetNumQuestLogEntries then return snap end
  local i
  for i = 1, GetNumQuestLogEntries() do
    local title, level, tag, header = GetQuestLogTitle(i)
    if title and not header then
      local objs = {}
      if GetNumQuestLeaderBoards then
        local n = GetNumQuestLeaderBoards(i) or 0
        if n == 0 and SelectQuestLogEntry then
          -- some clients only report boards for the selected row
        end
        local oi
        -- Vanilla: GetQuestLogLeaderBoard(i) uses selected quest. Select briefly.
      end
      snap[string.lower(title)] = { title = title, level = level, tag = tag, index = i, objs = objs }
    end
  end
  -- Fill objectives via selected entry (1.12)
  local prev = GetQuestLogSelection and GetQuestLogSelection() or 0
  local title, rec
  for title, rec in pairs(snap) do
    if SelectQuestLogEntry then SelectQuestLogEntry(rec.index) end
    rec.complete = nil
    if IsCurrentQuestFailed and IsCurrentQuestFailed() then rec.failed = 1 end
    rec.objs = {}
    if GetNumQuestLeaderBoards then
      local n = GetNumQuestLeaderBoards() or 0
      local oi
      for oi = 1, n do
        local text, typ, done = GetQuestLogLeaderBoard(oi)
        table.insert(rec.objs, { text = text, typ = typ, done = done and 1 or 0 })
      end
    end
  end
  if prev and prev > 0 and SelectQuestLogEntry then SelectQuestLogEntry(prev) end
  return snap
end

local function DiffObjectives(oldSnap, newSnap)
  local title, rec
  for title, rec in pairs(newSnap) do
    local prev = oldSnap and oldSnap[title]
    if rec.objs then
      local i
      for i = 1, getn(rec.objs) do
        local a = prev and prev.objs and prev.objs[i]
        local b = rec.objs[i]
        if b and b.text and (not a or a.text ~= b.text or a.done ~= b.done) then
          local got, need = ParseCount(b.text)
          local agot = a and ParseCount(a.text)
          -- Brand-new 0/N (accept) or reset 0/N after turn-in — not a field tick.
          local skip = false
          if got == 0 then
            if not a or (agot and agot > 0) then
              skip = true
            end
          end
          if not skip then
            Push(EnsureDB().objectives, {
              kind = "progress",
              title = rec.title,
              qid = ResolveQID(rec.title, rec.index),
              level = rec.level,
              text = b.text,
              typ = b.typ,
              done = b.done,
              pos = Pos(),
              target = RememberMob(),
            })
          end
        end
      end
    end
  end
end

local function RecordAccept(title, level, tag, idx, npc)
  if not title or title == "" then return end
  local db = EnsureDB()
  if RecentlyPushed(db.accepts, title, 8) then return end
  Push(db.accepts, {
    kind = "accept",
    title = title,
    qid = ResolveQID(title, idx),
    level = level,
    tag = tag,
    pos = Pos(),
    npc = npc or TargetInfo(),
  })
end

local function AcceptFromLogIndex(idx)
  local title, level, tag, header
  if idx and idx > 0 and GetQuestLogTitle then
    title, level, tag, header = GetQuestLogTitle(idx)
    if header then title = nil end
  end
  if (not title or title == "") and GetTitleText then
    title = GetTitleText()
  end
  return title, level, tag, idx
end

function Rec:Init()
  if self._inited then return end
  self._inited = true
  EnsureDB()
  Session()

  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("QUEST_ACCEPTED")
  f:RegisterEvent("QUEST_COMPLETE")
  f:RegisterEvent("QUEST_FINISHED")
  f:RegisterEvent("QUEST_GREETING")
  f:RegisterEvent("GOSSIP_SHOW")
  f:RegisterEvent("QUEST_DETAIL")
  f:RegisterEvent("QUEST_LOG_UPDATE")
  f:RegisterEvent("PLAYER_XP_UPDATE")
  f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
  f:RegisterEvent("CHAT_MSG_SYSTEM")
  f:RegisterEvent("CHAT_MSG_LOOT")
  f:RegisterEvent("PLAYER_LEVEL_UP")
  f:RegisterEvent("PLAYER_TARGET_CHANGED")

  f:SetScript("OnEvent", function()
    local db = EnsureDB()
    if event == "PLAYER_ENTERING_WORLD" then
      lastLog = SnapshotLog()
      local sess = Session()
      if not sess.faction or sess.faction == "?" then
        sess.faction = FactionOfPlayer()
      end
      return
    end
    if event == "PLAYER_TARGET_CHANGED" then
      RememberMob()
      return
    end
    if not db.enabled and event ~= "PLAYER_ENTERING_WORLD" then return end

    if event == "QUEST_ACCEPTED" then
      local idx = arg1
      local title, level, tag = AcceptFromLogIndex(idx)
      if not title or title == "" then
        title = pendingAcceptTitle
      end
      RecordAccept(title, level, tag, idx, TargetInfo())
      pendingAcceptTitle = nil
      lastLog = SnapshotLog()

    elseif event == "QUEST_DETAIL" then
      local title = GetTitleText and GetTitleText() or nil
      pendingAcceptTitle = title
      Push(db.givers, {
        kind = "detail",
        title = title,
        qid = ResolveQID(title),
        pos = Pos(),
        npc = TargetInfo(),
      })

    elseif event == "QUEST_COMPLETE" then
      local title = GetTitleText and GetTitleText() or nil
      local money = GetRewardMoney and GetRewardMoney() or 0
      pendingXP = {
        title = title,
        qid = ResolveQID(title),
        money = money,
        xpBefore = UnitXP and UnitXP("player") or 0,
        xpMax = UnitXPMax and UnitXPMax("player") or 0,
        level = UnitLevel and UnitLevel("player") or 0,
        pos = Pos(),
        npc = TargetInfo(),
        t = now(),
      }

    elseif event == "QUEST_FINISHED" then
      local row = pendingXP
      if row then
        row.xpAfter = UnitXP and UnitXP("player") or 0
        row.levelAfter = UnitLevel and UnitLevel("player") or 0
        local gained = 0
        if row.levelAfter and row.level and row.levelAfter > row.level then
          gained = (row.xpMax - (row.xpBefore or 0)) + (row.xpAfter or 0)
        else
          gained = (row.xpAfter or 0) - (row.xpBefore or 0)
          if gained < 0 then gained = 0 end
        end
        row.xp = row.xp or gained
        row.kind = "turnin"
        Push(db.turnins, row)
        pendingXP = nil
      end
      lastLog = SnapshotLog()

    elseif event == "PLAYER_XP_UPDATE" then
      if pendingXP and not pendingXP.xp then
        local after = UnitXP and UnitXP("player") or 0
        local lvl = UnitLevel and UnitLevel("player") or pendingXP.level
        local gained = after - (pendingXP.xpBefore or 0)
        if lvl and pendingXP.level and lvl > pendingXP.level then
          gained = (pendingXP.xpMax - (pendingXP.xpBefore or 0)) + after
        end
        if gained < 0 then gained = 0 end
        pendingXP.xp = gained
        pendingXP.xpAfter = after
      end

    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" or event == "CHAT_MSG_SYSTEM" then
      local msg = arg1 or ""
      local _, _, n = string.find(msg, "(%d+)%s+[Ee]xperience")
      if not n then
        _, _, n = string.find(msg, "(%d+)%s+[Ee]xp")
      end
      if n and pendingXP and not pendingXP.chatXP then
        pendingXP.chatXP = tonumber(n)
        if not pendingXP.xp then pendingXP.xp = tonumber(n) end
      end
      -- Abandon
      local _, _, ab = string.find(msg, "^Quest abandoned: (.+)$")
      if not ab then
        _, _, ab = string.find(msg, "^Abandoned quest: (.+)$")
      end
      if ab then
        Push(db.abandons, { kind = "abandon", title = ab, qid = ResolveQID(ab), pos = Pos() })
      end

    elseif event == "QUEST_GREETING" then
      local npc = TargetInfo()
      local titles = {}
      if GetNumActiveQuests then
        local i
        for i = 1, GetNumActiveQuests() do
          local t = GetActiveTitle(i)
          if t then table.insert(titles, { state = "active", title = t }) end
        end
      end
      if GetNumAvailableQuests then
        local i
        for i = 1, GetNumAvailableQuests() do
          local t = GetAvailableTitle(i)
          if t then table.insert(titles, { state = "available", title = t }) end
        end
      end
      Push(db.givers, { kind = "greeting", pos = Pos(), npc = npc, quests = titles })

    elseif event == "GOSSIP_SHOW" then
      local npc = TargetInfo()
      local titles = {}
      if GetGossipAvailableQuests then
        -- returns interleaved title, level, ...
        local raw = { GetGossipAvailableQuests() }
        local i = 1
        while raw[i] do
          table.insert(titles, { state = "available", title = raw[i], level = raw[i + 1] })
          i = i + 3
        end
      end
      if GetGossipActiveQuests then
        local raw = { GetGossipActiveQuests() }
        local i = 1
        while raw[i] do
          table.insert(titles, { state = "active", title = raw[i], level = raw[i + 1] })
          i = i + 3
        end
      end
      if getn(titles) > 0 then
        Push(db.givers, { kind = "gossip", pos = Pos(), npc = npc, quests = titles })
      end

    elseif event == "QUEST_LOG_UPDATE" then
      local snap = SnapshotLog()
      -- New log rows that QUEST_ACCEPTED missed (wanted posters, auto-accept).
      local title, rec
      for title, rec in pairs(snap) do
        if not lastLog[title] then
          RecordAccept(rec.title, rec.level, rec.tag, rec.index, TargetInfo())
        end
      end
      DiffObjectives(lastLog, snap)
      lastLog = snap

    elseif event == "CHAT_MSG_LOOT" then
      local msg = arg1 or ""
      -- You receive loot: [Item Name]
      local item
      local _, _, iname = string.find(msg, "%[(.-)%]")
      if iname and lastLog then
        -- only keep if the name appears in an active objective
        local keep = false
        local title, rec
        for title, rec in pairs(lastLog) do
          local oi
          if rec.objs then
            for oi = 1, getn(rec.objs) do
              local t = rec.objs[oi].text or ""
              if string.find(string.lower(t), string.lower(iname), 1, true) then
                keep = true
                Push(db.loot, {
                  kind = "loot",
                  item = iname,
                  title = rec.title,
                  qid = ResolveQID(rec.title, rec.index),
                  obj = t,
                  pos = Pos(),
                  target = RememberMob(),
                })
                break
              end
            end
          end
          if keep then break end
        end
      end
    end
  end)

  SLASH_GQREC1 = "/gqrec"
  SlashCmdList["GQREC"] = function(msg)
    msg = string.lower(msg or "")
    local db = EnsureDB()
    if msg == "off" then
      db.enabled = false
      Chat("recording off")
    elseif msg == "on" then
      db.enabled = true
      Chat("recording on")
    elseif msg == "clear" then
      GreedQuestRecord = { enabled = db.enabled }
      EnsureDB()
      Chat("cleared saved record")
    else
      local a = getn(db.accepts or {})
      local t = getn(db.turnins or {})
      local o = getn(db.objectives or {})
      local g = getn(db.givers or {})
      local l = getn(db.loot or {})
      Chat(string.format("%s  accept %d  turnin %d  objective %d  giver %d  loot %d",
        db.enabled and "ON" or "OFF", a, t, o, g, l))
      Chat("logout to flush. upload WTF/Account/<account>/SavedVariables/GreedQuest.lua")
    end
  end

  local db = EnsureDB()
  if db.enabled then
    Chat("field recorder on  (/gqrec off to stop)")
  end
end

-- Boot after variables
local boot = CreateFrame("Frame")
boot:RegisterEvent("VARIABLES_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  Rec:Init()
end)
