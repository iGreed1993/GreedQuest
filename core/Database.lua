--[[
  GreedQuest Database
  - Self-contained quest/unit/object/item tables for Turtle/Octo
  - Packed coords/drops, lazy unpack
  - Min-level index for available-quest scans
  - Data files are listed in the TOC (reliable on 1.12 clients)
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GreedQuestDB = GreedQuestDB or {}

GQ.Database = GQ.Database or {}
local DB = GQ.Database

DB.ready = false

function DB.UnpackCoords(str)
  if not str or str == "" then return {} end
  local result = {}
  for entry in string.gfind(str, "[^;]+") do
    local _, _, x, y, z, r = string.find(entry, "([^,]+),([^,]+),([^,]+),([^,]+)")
    if not x then
      _, _, x, y, z = string.find(entry, "([^,]+),([^,]+),([^,]+)")
      r = 0
    end
    if x then
      table.insert(result, {
        tonumber(x), tonumber(y), tonumber(z), tonumber(r)
      })
    end
  end
  return result
end

function DB.UnpackDropData(str)
  if not str or str == "" then return {} end
  local result = {}
  for entry in string.gfind(str, "[^,]+") do
    local _, _, id, chance = string.find(entry, "([^:]+):([^:]+)")
    if id then
      result[tonumber(id)] = tonumber(chance)
    end
  end
  return result
end

local coordMeta = {
  __index = function(t, key)
    if key == "coords" then
      local packed = rawget(t, "_coords")
      if packed ~= nil then
        local unpacked = DB.UnpackCoords(packed)
        rawset(t, "coords", unpacked)
        return unpacked
      end
    end
    return rawget(t, key)
  end
}

local dropMeta = {
  __index = function(t, key)
    if key == "U" or key == "O" or key == "V" or key == "R" then
      local packed = rawget(t, "_" .. key)
      if packed ~= nil then
        local unpacked = DB.UnpackDropData(packed)
        rawset(t, key, unpacked)
        return unpacked
      end
    end
    return rawget(t, key)
  end
}

function DB.MakeLazyCoords(entry)
  if type(entry) ~= "table" then return nil end
  if rawget(entry, "_coords") ~= nil then
    setmetatable(entry, coordMeta)
  end
  return entry
end

function DB.MakeLazyDrops(entry)
  if type(entry) ~= "table" then return nil end
  setmetatable(entry, dropMeta)
  return entry
end

function DB:MergeTurtle()
  local function apply(src, dest)
    if not src or not dest then return end
    local id, packed
    for id, packed in pairs(src) do
      local e = dest[id]
      if e then
        e._coords = packed
        rawset(e, "coords", nil)
        DB.MakeLazyCoords(e)
      else
        dest[id] = { _coords = packed }
        DB.MakeLazyCoords(dest[id])
      end
    end
  end
  apply(GreedQuestDB.turtleUnitCoords, GreedQuestDB.units)
  apply(GreedQuestDB.turtleObjectCoords, GreedQuestDB.objects)
end

function DB:BuildQuestIndexes()
  self.questIndexByMin = {}
  self.questIndexByLvl = {}
  self.questIdList = {}

  local quests = GreedQuestDB.quests or {}
  for qid, qdata in pairs(quests) do
    if type(qid) == "number" and type(qdata) == "table" then
      local start = qdata["start"]
      if start and (start["U"] or start["O"] or start["I"]) then
        local minL = qdata["min"] or 1
        local lvl  = qdata["lvl"] or minL
        if not self.questIndexByMin[minL] then self.questIndexByMin[minL] = {} end
        if not self.questIndexByLvl[lvl] then self.questIndexByLvl[lvl] = {} end
        table.insert(self.questIndexByMin[minL], qid)
        table.insert(self.questIndexByLvl[lvl], qid)
        table.insert(self.questIdList, qid)
      end
    end
  end
  GQ:Debug("Quest indexes built (" .. getn(self.questIdList) .. " startable quests)")
end

function DB:ZoneHasStarters(zoneID)
  local t = GreedQuestDB and GreedQuestDB.mapStarters
  if not t or not zoneID then return true end -- unknown: scan
  local list = t[zoneID]
  return list and getn(list) > 0
end

function DB:GetStartersForZone(zoneID)
  local t = GreedQuestDB and GreedQuestDB.mapStarters
  if not t or not zoneID then return nil end
  return t[zoneID]
end

function DB:IsDungeonZone(zoneID)
  return GreedQuestDB and GreedQuestDB.dungeonZones and GreedQuestDB.dungeonZones[zoneID] and true or false
end

function DB:GetDungeonEntrances(zoneID)
  return GreedQuestDB and GreedQuestDB.dungeonEntrances and GreedQuestDB.dungeonEntrances[zoneID]
end

function DB:QuestKind(qid)
  return GreedQuestDB and GreedQuestDB.questKind and GreedQuestDB.questKind[qid]
end

function DB:GetAvailableCandidateIds(playerLevel, levelBand)
  levelBand = levelBand or 5
  local maxLvl = playerLevel + levelBand
  local seen = {}
  local out = {}
  for lvl = 1, maxLvl do
    local bucket = self.questIndexByLvl and self.questIndexByLvl[lvl]
    if bucket then
      for _, qid in ipairs(bucket) do
        if not seen[qid] then
          local qdata = GreedQuestDB.quests[qid]
          local minL = (qdata and qdata["min"]) or 1
          if minL <= playerLevel then
            seen[qid] = true
            table.insert(out, qid)
          end
        end
      end
    end
  end
  return out
end

function DB:GetUnit(id)
  local entry = GreedQuestDB.units and GreedQuestDB.units[id]
  if type(entry) == "table" then return self.MakeLazyCoords(entry) end
end

function DB:GetObject(id)
  local entry = GreedQuestDB.objects and GreedQuestDB.objects[id]
  if type(entry) == "table" then return self.MakeLazyCoords(entry) end
end

function DB:GetItem(id)
  local entry = GreedQuestDB.items and GreedQuestDB.items[id]
  if entry then return self.MakeLazyDrops(entry) end
end

function DB:GetQuest(id)
  return GreedQuestDB.quests and GreedQuestDB.quests[id]
end

function DB:GetAreatrigger(id)
  local packed = GreedQuestDB.areatriggers and GreedQuestDB.areatriggers[id]
  if not packed then return nil end
  if type(packed) == "table" then
    return self.MakeLazyCoords(packed)
  end
  return { coords = self.UnpackCoords(packed) }
end

function DB:GetItemReqTargets(itemID)
  return GreedQuestDB.itemReq and GreedQuestDB.itemReq[itemID]
end

function DB:IsVanillaQuest(id)
  return true
end

function DB:GetUnits()   return GreedQuestDB.units   or {} end
function DB:GetObjects() return GreedQuestDB.objects or {} end
function DB:GetItems()   return GreedQuestDB.items   or {} end
function DB:GetQuests()  return GreedQuestDB.quests  or {} end

function DB:GetWaypoints(unitID)
  return GreedQuestDB.waypoints and GreedQuestDB.waypoints[unitID]
end

function DB:IsReady()
  return self.ready == true
end

function DB:Load()
  self:MergeTurtle()
  self:BuildQuestIndexes()

  local u, o, i, q = 0, 0, 0, 0
  local debug = GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.debug
  if debug then
    if GreedQuestDB.units   then for _ in pairs(GreedQuestDB.units)   do u = u + 1 end end
    if GreedQuestDB.objects then for _ in pairs(GreedQuestDB.objects) do o = o + 1 end end
    if GreedQuestDB.items   then for _ in pairs(GreedQuestDB.items)   do i = i + 1 end end
    if GreedQuestDB.quests  then for _ in pairs(GreedQuestDB.quests)  do q = q + 1 end end
    GQ:Debug(string.format("DB ready - Units:%d Objects:%d Items:%d Quests:%d", u, o, i, q))
  else
    q = self.questIdList and getn(self.questIdList) or 0
  end

  collectgarbage()
  self.ready = true
  return u, o, i, q
end

GreedQuestDB.units   = GreedQuestDB.units   or {}
GreedQuestDB.objects = GreedQuestDB.objects or {}
GreedQuestDB.items   = GreedQuestDB.items   or {}
GreedQuestDB.quests  = GreedQuestDB.quests  or {}
