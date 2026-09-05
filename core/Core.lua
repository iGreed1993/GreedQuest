--[[
  GreedQuest Core
  Quest log scanning, filters, title→ID matching
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Core = GQ.Core or {}
local Core = GQ.Core

local function BitHit(mask, flag)
  if not mask or not flag or flag == 0 then return true end
  if bit and bit.band then
    return bit.band(mask, flag) ~= 0
  end
  -- Lua 5.0 fallback
  local v = 1
  local limit = 65536
  while v <= limit do
    local inMask = math.mod(mask, v * 2) >= v
    local inFlag = math.mod(flag, v * 2) >= v
    if inMask and inFlag then return true end
    v = v * 2
  end
  return false
end


Core.questLog = {}
Core.prevLogKeys = {}
Core.titleIndex = nil

local SEASONAL_KEYWORDS = {
  -- Feast of Winter Veil
  "winter veil", "feast of winter", "greatfather", "great father",
  "metzen", "smokywood", "px-238", "winter's veil", "winters veil",
  "treats for greatfather", "stolen treats", "you're a mean one",
  "metzen the reindeer", "the reason for the season", "greatfather winter",
  "jolly green", "holly preserve",
  "gaily wrapped", "gently shaken", "carefully wrapped",
  "ticking present", "festive gift", "winter veil gift",
  "smokywood pastures",
  -- Lunar Festival
  "lunar festival", "coin of ancestry", "valadar", "festival lantern",
  "lunar fortune", "elders of the", "lunar firecracker", "omen of luck",
  "elune's candle", "elunes candle",
  -- Love is in the Air
  "love is in the air", "lovely charm", "gift of adoration",
  "handful of rose petals", "crushing the competition",
  "something is in the air", "bane of our existence",
  "testaments of true love", "testament of true love",
  -- Noblegarden
  "noblegarden", "brightly colored egg", "great egg hunt",
  -- Children's Week
  "children's week", "childrens week", "orphan's story",
  "cairne's hoofprint", "bough of the eternals", "squeaky clean",
  -- Midsummer Fire Festival
  "midsummer", "flame warden", "flame keeper", "fire festival",
  "torch toss", "torch catch", "stealing the flame", "honor the flame",
  "desecrate this fire", "festival of fire", "midsummer fire",
  "a light in dark places", "incense for the festival",
  "flickering flame", "flickering flames",
  -- Hallow's End
  "hallow's end", "hallows end", "hallowsend", "wickerman",
  "tricky treat", "candy bucket", "headless horseman",
  "fire brigade practice", "stinking up southshore", "rotten eggs",
  "masked orphan", "horror of halloween", "halloween",
  -- Harvest Festival
  "harvest festival", "honoring a hero",
  -- Pilgrim's Bounty
  "pilgrim's bounty", "pilgrims bounty", "bountiful table",
  "turkey time", "bountiful feast",
  -- Brewfest / Turtle Brewing Festival
  "brewfest", "brew fest", "brewing festival", "direbrew",
  "chug and chuck", "bark for ", "ram racing", "there and back again",
  "pink elekk", "brew of the month", "barleybrew", "thunderbrew",
  -- Darkmoon Faire
  "darkmoon faire", "darkmoon", "your fortune awaits",
  "sayge's fortune", "darkmoon faire deck",
  -- New Year
  "new year", "new year's", "new years",
  -- Weekly / special events often filtered with seasonal
  "fishing extravaganza", "rare fish - ", "apprentice angler",
  "scourge invasion",
}

-- Known seasonal / holiday quest IDs (vanilla + common Turtle holiday content)
local SEASONAL_QUEST_IDS = {
  [172] = 1,
  [1468] = 1,
  [1657] = 1,
  [1658] = 1,
  [6961] = 1,
  [6962] = 1,
  [6963] = 1,
  [6964] = 1,
  [6984] = 1,
  [7021] = 1,
  [7022] = 1,
  [7023] = 1,
  [7024] = 1,
  [7025] = 1,
  [7042] = 1,
  [7045] = 1,
  [7061] = 1,
  [7062] = 1,
  [7063] = 1,
  [7905] = 1,
  [7907] = 1,
  [7926] = 1,
  [7927] = 1,
  [7928] = 1,
  [7929] = 1,
  [7930] = 1,
  [7931] = 1,
  [7932] = 1,
  [7933] = 1,
  [7934] = 1,
  [7940] = 1,
  [7981] = 1,
  [8149] = 1,
  [8150] = 1,
  [8311] = 1,
  [8312] = 1,
  [8409] = 1,
  [8746] = 1,
  [8762] = 1,
  [8827] = 1,
  [8828] = 1,
  [8860] = 1,
  [8861] = 1,
  [8867] = 1,
  [8868] = 1,
  [8870] = 1,
  [8871] = 1,
  [8872] = 1,
  [8873] = 1,
  [8874] = 1,
  [8875] = 1,
  [8883] = 1,
  [8979] = 1,
  [9024] = 1,
  [9322] = 1,
  [9323] = 1,
  [40743] = 1,
  [40744] = 1,
  [40745] = 1,
  [40746] = 1,
  [40748] = 1,
  [40772] = 1,
  [40778] = 1,
  [40779] = 1,
  [40780] = 1,
  [40781] = 1,
  [40782] = 1,
  [40783] = 1,
  [40784] = 1,
  [41553] = 1,
  [41554] = 1,
  [41894] = 1,
  [50330] = 1,
  [80740] = 1,
}

local function GetQuestLogTitleSafe(i)
  local title, level, tag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
  return title, level, tag, isHeader, isCollapsed, isComplete
end

function Core:NormalizeTitle(title)
  if not title then return nil end
  -- strip color codes / texture escapes common on private servers
  title = string.gsub(title, "|c%x%x%x%x%x%x%x%x", "")
  title = string.gsub(title, "|r", "")
  title = string.gsub(title, "|T.-|t", "")
  title = string.gsub(title, "^%s+", "")
  title = string.gsub(title, "%s+$", "")
  -- strip trailing complete markers some UIs add
  title = string.gsub(title, "%s*%(%s*[Cc]omplete%s*%)%s*$", "")
  title = string.gsub(title, "%s*%(%s*[Ff]ailed%s*%)%s*$", "")
  return title
end

function Core:BuildTitleIndex()
  -- Map normalized title -> list of quest IDs (Alliance/Horde share many titles)
  self.titleIndex = {}
  local titles = GreedQuestDB and GreedQuestDB.questTitles
  if not titles then return end
  for qid, title in pairs(titles) do
    if type(qid) == "number" and title and title ~= "" then
      local norm = string.lower(self:NormalizeTitle(title) or title)
      if not self.titleIndex[norm] then
        self.titleIndex[norm] = { qid }
      else
        table.insert(self.titleIndex[norm], qid)
      end
    end
  end
  local n = 0
  for _ in pairs(self.titleIndex) do n = n + 1 end
  GQ:Debug("Title index built:", n, "entries")
end

-- Score a candidate quest ID for this player (higher = better). Used when
-- multiple quests share the same title (e.g. Art of the Armorsmith A/H).
function Core:ScoreQuestCandidate(qid)
  local qdata = GQ.Database and GQ.Database:GetQuest(qid)
  if not qdata then return 0 end
  local score = 1
  local prace = 0
  if self.GetPlayerRaceMask then
    prace = self:GetPlayerRaceMask() or 0
  end
  if qdata["race"] and qdata["race"] ~= 0 and prace and prace ~= 0 then
    if BitHit(qdata["race"], prace) then
      score = score + 50
    else
      return -100  -- hard reject opposite race
    end
  end
  if self.StartFactionOk and not self:StartFactionOk(qdata) then
    return -50
  end
  if self.StartFactionOk and self:StartFactionOk(qdata) then
    score = score + 20
  end
  -- Prefer turn-in NPCs matching player faction
  if qdata["end"] and qdata["end"]["U"] and self.PreferFactionUnitId then
    local uid = self:PreferFactionUnitId(qdata["end"]["U"])
    if uid then score = score + 10 end
  end
  return score
end

function Core:ResolveQuestID(title)
  if not title then return nil end
  if not self.titleIndex then self:BuildTitleIndex() end
  if not self.titleIndex then return nil end
  local norm = string.lower(self:NormalizeTitle(title) or title)
  local list = self.titleIndex[norm]
  if type(list) == "number" then
    -- legacy single-id shape
    return list
  end
  if type(list) == "table" then
    if table.getn(list) == 1 then return list[1] end
    local bestId, bestScore = list[1], -9999
    local i
    for i = 1, table.getn(list) do
      local s = self:ScoreQuestCandidate(list[i])
      if s > bestScore then
        bestScore = s
        bestId = list[i]
      end
    end
    return bestId
  end
  -- fallback: partial match
  for dbTitle, ids in pairs(self.titleIndex) do
    if string.find(norm, dbTitle, 1, true) or string.find(dbTitle, norm, 1, true) then
      if type(ids) == "table" then
        return self:ResolveQuestID(dbTitle) or ids[1]
      end
      return ids
    end
  end
  return nil
end

function Core:IsSeasonalTitle(title)
  if not title then return false end
  local lower = string.lower(title)
  for _, kw in ipairs(SEASONAL_KEYWORDS) do
    if string.find(lower, kw, 1, true) then return true end
  end
  return false
end

function Core:IsSeasonalQuest(qid, title, tag)
  -- Explicit seasonal event ID on quest (calendar festivals)
  if qid and GQ.Database then
    local qdata = GQ.Database:GetQuest(qid)
    -- Any event-tagged quest is seasonal/holiday content
    if qdata and qdata["event"] then
      return true
    end
  end
  if qid and SEASONAL_QUEST_IDS[qid] then return true end
  if tag and self:IsSeasonalTitle(tag) then return true end
  if title and self:IsSeasonalTitle(title) then return true end
  if qid then
    local dbTitle = GreedQuestDB and GreedQuestDB.questTitles and GreedQuestDB.questTitles[qid]
    if dbTitle and self:IsSeasonalTitle(dbTitle) then return true end
    local obj = GreedQuestDB and GreedQuestDB.questObjectives and GreedQuestDB.questObjectives[qid]
    if obj and self:IsSeasonalTitle(obj) then return true end
  end
  return false
end


function Core:IsPvPQuest(tag, title, qid)
  -- Explicit Type-41 PvP IDs from the Turtle/Octo server table
  if qid and GreedQuestDB and GreedQuestDB.pvpQuestIds and GreedQuestDB.pvpQuestIds[qid] then
    return true
  end
  if tag then
    local tl = string.lower(tag)
    if string.find(tl, "pvp", 1, true) then return true end
  end
  if title then
    local lower = string.lower(title)
    if string.find(lower, "pvp", 1, true) then return true end
    -- Battleground / honor quest title patterns (vanilla + Turtle)
    local keywords = {
      "warsong gulch", "arathi basin", "alterac valley",
      "battleground", "battle of warsong", "call to arms",
      "mark of honor", "marks of honor", "for great honor",
      "concerted efforts", "remember alterac", "the battle for",
      "claiming the", "defending the", "towers of", "graveyards of",
      "stables of", "blacksmith of", "lumber mill of", "gold mine",
      "farm of", "mine of", "the legionnaire", "the protector",
      "out of the abyss", "taking back", "invading",
      "honor points", "battlefield",
      "past victories", "past victory",
    }
    local i
    for i = 1, table.getn(keywords) do
      if string.find(lower, keywords[i], 1, true) then return true end
    end
  end
  -- Quest starts / ends inside a battleground map
  if qid and GQ.Database then
    local qdata = GQ.Database:GetQuest(qid)
    if qdata then
      local bgZones = {
        [2597] = true, -- Alterac Valley
        [3277] = true, -- Warsong Gulch
        [3358] = true, -- Arathi Basin
      }
      local function inBg(group)
        if not group then return false end
        local kind, list
        for kind, list in pairs(group) do
          if type(list) == "table" then
            local _, id
            for _, id in pairs(list) do
              local entry
              if kind == "U" then
                entry = GQ.Database:GetUnit(id)
              elseif kind == "O" then
                entry = GQ.Database:GetObject(id)
              end
              if entry and entry.coords then
                local ci
                for ci = 1, table.getn(entry.coords) do
                  local z = entry.coords[ci][3]
                  if z and bgZones[z] then return true end
                end
              end
            end
          end
        end
        return false
      end
      if inBg(qdata["start"]) or inBg(qdata["end"]) or inBg(qdata["obj"]) then
        return true
      end
    end
  end
  return false
end



local REPEATABLE_TITLE_PATTERNS = {
  "a donation of",
  "additional runecloth",
  "needs more",
  "needs runecloth",
  "needs wool",
  "needs silk",
  "needs mageweave",
  "craftsman's writ",
  "craftsmans writ",
  "cartel gold donations",
  "donations to ",
  "repeatable",
  "daily:",
  "(daily)",
  "another pile",
  "more armor kits",
  "more thorium shells",
  "more dense grinding stones",
}

function Core:IsRepeatableQuest(q)
  if not q then return false end
  if q.questID and GreedQuestDB and GreedQuestDB.questFlags then
    local f = GreedQuestDB.questFlags[q.questID]
    if f and (f["repeatable"] or f["daily"] or f["yearly"]) then
      return true
    end
  end
  local title = q.title or ""
  local lower = string.lower(title)
  local tag = q.tag and string.lower(q.tag) or ""

  if tag == "daily" or string.find(tag, "daily", 1, true) then
    return true
  end
  if string.find(lower, "daily", 1, true) then
    return true
  end

  for _, pat in ipairs(REPEATABLE_TITLE_PATTERNS) do
    if string.find(lower, pat, 1, true) then
      return true
    end
  end

  -- DB event flag often marks festival/repeatable content
  if q.questID and GQ.Database then
    local qdata = GQ.Database:GetQuest(q.questID)
    if qdata and qdata["event"] then
      -- only treat as repeatable-style when title also looks donation-like or "additional"
      if string.find(lower, "donation", 1, true)
         or string.find(lower, "additional", 1, true)
         or string.find(lower, "needs more", 1, true) then
        return true
      end
    end
  end

  return false
end

function Core:IsEliteStyleQuest(qid, title, tag, header)
  -- Elite / Dungeon / Raid cue for tooltips ([level+]) even before accept.
  if tag and tag ~= "" then
    local tl = string.lower(tostring(tag))
    if string.find(tl, "elite", 1, true)
       or string.find(tl, "dungeon", 1, true)
       or string.find(tl, "raid", 1, true)
       or tl == "group" then
      return true
    end
  end
  if header and header ~= "" then
    local hl = string.lower(tostring(header))
    if hl == "dungeon" or hl == "raid" or string.find(hl, "dungeon", 1, true) or string.find(hl, "raid", 1, true) then
      return true
    end
  end
  if qid and GreedQuestDB and GreedQuestDB.questFlags then
    local f = GreedQuestDB.questFlags[qid]
    if f and (f["elite"] or f["dungeon"] or f["raid"] or f["group"]) then
      return true
    end
  end
  if qid and GreedQuestDB and GreedQuestDB.questKind then
    local k = GreedQuestDB.questKind[qid]
    if k == "d" or k == "e" or k == "r" then return true end
  end
  local lower = string.lower(title or "")
  if string.find(lower, "(elite)", 1, true)
     or string.find(lower, "[dungeon]", 1, true)
     or string.find(lower, "[raid]", 1, true)
     or string.find(lower, " dungeon", 1, true) then
    return true
  end
  return false
end

function Core:FormatQuestLevel(level, qid, title, tag, header)
  if not level then return nil end
  if self:IsEliteStyleQuest(qid, title, tag, header) then
    return tostring(level) .. "+"
  end
  return tostring(level)
end

function Core:MaybeWipeFreshCharacter()
  -- Same-name recreate / Hardcore restart reuses 1.12 per-character SV.
  -- Level 1 with 0 XP after a previous "played" life means a new character.
  if not GreedQuestCharDB then return end
  local lvl = UnitLevel and UnitLevel("player") or 0
  local xp = UnitXP and UnitXP("player") or 0
  if lvl == 1 and (not xp or xp == 0) then
    if GreedQuestCharDB.lifeToken ~= "fresh" then
      GreedQuestCharDB.completed = {}
      GreedQuestCharDB.lifeToken = "fresh"
      if GQ.Debug then
        GQ:Debug("Fresh level-1 character: cleared inherited quest history")
      end
    end
  else
    GreedQuestCharDB.lifeToken = "played"
  end
end

function Core:IsLowLevelQuest(level)
  -- Grey difficulty: more than GetQuestGreenRange levels below the player
  if not level then return false end
  level = tonumber(level) or 0
  if level <= 0 then return false end
  local pl = UnitLevel("player") or 1
  local greenRange = 5
  if GetQuestGreenRange then
    greenRange = GetQuestGreenRange() or 5
  end
  return level < (pl - greenRange)
end

function Core:ShouldHideQuest(q)
  if GQ.Map and GQ.Map.IsQuestHidden and GQ.Map:IsQuestHidden(q.questID, q.title) then
    return true
  end
  if q.questID and GreedQuestDB then
    if GreedQuestDB.turtleRemovedQuests and GreedQuestDB.turtleRemovedQuests[q.questID] then
      return true
    end
    if GreedQuestDB.questFlags then
      local f = GreedQuestDB.questFlags[q.questID]
      if f and f["disabled"] then return true end
    end
  end
  local cfg = GreedQuestConfig and GreedQuestConfig.general
  if not cfg then return false end

  if cfg.hidePvP and self:IsPvPQuest(q.tag, q.title, q.questID) then return true end
  if cfg.hideSeasonal and self:IsSeasonalQuest(q.questID, q.title, q.tag) then return true end
  if cfg.hideLowLevel then
    local lvl = q.level
    if not lvl and q.questID and GQ.Database then
      local qd = GQ.Database:GetQuest(q.questID)
      if qd then lvl = qd["lvl"] or qd["min"] end
    end
    if self:IsLowLevelQuest(lvl) then return true end
  end
  if cfg.hideRepeatable and self:IsRepeatableQuest(q) then return true end
  return false
end

function Core:QuestInCurrentZone(q)
  if not q then return false end
  local zoneID = GQ.Map and GQ.Map.playerZoneID
  if not zoneID then return true end
  local DB = GQ.Database
  if not DB then return true end
  local qid = q.questID
  if not qid then return true end
  local qdata = DB:GetQuest(qid)
  if not qdata then return true end

  local function entityInZone(id, isUnit)
    local entry = isUnit and DB:GetUnit(id) or DB:GetObject(id)
    if not entry or not entry.coords then return false end
    for _, c in ipairs(entry.coords) do
      if c[3] and c[3] == zoneID then return true end
    end
    return false
  end

  local function groupInZone(group)
    if not group then return false end
    if group["U"] then
      for _, uid in pairs(group["U"]) do
        if entityInZone(uid, true) then return true end
      end
    end
    if group["O"] then
      for _, oid in pairs(group["O"]) do
        if entityInZone(oid, false) then return true end
      end
    end
    -- Item objectives: units/objects that drop the item
    if group["I"] then
      for _, itemID in pairs(group["I"]) do
        local item = DB:GetItem(itemID)
        if item then
          if item.U then
            for uid, _ in pairs(item.U) do
              if entityInZone(uid, true) then return true end
            end
          end
          if item.O then
            for oid, _ in pairs(item.O) do
              if entityInZone(oid, false) then return true end
            end
          end
        end
      end
    end
    return false
  end

  if groupInZone(qdata["start"]) then return true end
  if groupInZone(qdata["end"]) then return true end
  if groupInZone(qdata["obj"]) then return true end
  return false
end

function Core:PartyAnnounce(msg)
  if not msg or msg == "" then return end
  if not GetNumPartyMembers or (GetNumPartyMembers() or 0) <= 0 then return end
  if not SendChatMessage then return end
  msg = string.gsub(msg, "|", "/")
  msg = string.gsub(msg, "%%", "/")
  if string.len(msg) > 240 then
    msg = string.sub(msg, 1, 240)
  end
  if pcall then
    pcall(SendChatMessage, msg, "PARTY")
  else
    SendChatMessage(msg, "PARTY")
  end
end

function Core:AnnounceLogDiff(oldKeys, newKeys)
  local cfg = GreedQuestConfig and GreedQuestConfig.general
  if not cfg then return end
  if not GetNumPartyMembers or (GetNumPartyMembers() or 0) <= 0 then return end
  -- First scan has no baseline; do not dump the whole log as "Accepted".
  if not oldKeys then return end
  newKeys = newKeys or {}

  local function objSig(q)
    if not q or not q.objectives then return "" end
    local s = ""
    local i
    for i = 1, getn(q.objectives) do
      local o = q.objectives[i]
      s = s .. (o.text or "") .. (o.finished and "1" or "0") .. ";"
    end
    return s
  end

  if cfg.announceAcceptDrop or cfg.announceComplete then
    local key, q
    for key, q in pairs(newKeys) do
      if not oldKeys[key] then
        if cfg.announceAcceptDrop then
          self:PartyAnnounce("Accepted: " .. (q.title or "Quest"))
        end
      end
    end
    for key, oldq in pairs(oldKeys) do
      if not newKeys[key] then
        if oldq and oldq.complete then
          if cfg.announceComplete or cfg.announceAcceptDrop then
            self:PartyAnnounce("Turned in: " .. (oldq.title or "Quest"))
          end
        elseif cfg.announceAcceptDrop then
          self:PartyAnnounce("Abandoned: " .. ((oldq and oldq.title) or "Quest"))
        end
      end
    end
  end

  if cfg.announceProgress or cfg.announceComplete then
    local key, q
    for key, q in pairs(newKeys) do
      local oldq = oldKeys[key]
      if oldq and q then
        if cfg.announceComplete and q.complete and not oldq.complete then
          self:PartyAnnounce("Completed: " .. (q.title or "Quest"))
        end
        if cfg.announceProgress and objSig(oldq) ~= objSig(q) then
          -- Prefer the objective line that changed
          local msg = nil
          if q.objectives then
            local i
            for i = 1, getn(q.objectives) do
              local o = q.objectives[i]
              local oo = oldq.objectives and oldq.objectives[i]
              if o and ((not oo) or (oo.text ~= o.text) or (oo.finished ~= o.finished)) then
                msg = (q.title or "Quest") .. ": " .. (o.text or "")
                break
              end
            end
          end
          if msg then self:PartyAnnounce(msg) end
        end
      end
    end
  end
end

function Core:ScanQuestLog()
  self.questLog = {}
  local numEntries = GetNumQuestLogEntries() or 0
  local prevSelection = GetQuestLogSelection and GetQuestLogSelection() or 0

  -- Expand all headers so every quest is visible to the API (1.12)
  if ExpandQuestHeader then
    ExpandQuestHeader(0)
  end
  numEntries = GetNumQuestLogEntries() or 0

  local currentHeader = "Other"
  for i = 1, numEntries do
    local title, level, tag, isHeader, isCollapsed, isComplete = GetQuestLogTitleSafe(i)
    if title and isHeader then
      -- Blizzard / Turtle quest log zone or category header (e.g. "Gilneas City", "Blacksmithing")
      currentHeader = title
    elseif title and not isHeader then
      local qid = self:ResolveQuestID(title)
      if not qid and title then
        qid = self:ResolveQuestID(self:NormalizeTitle(title))
      end
      if SelectQuestLogEntry then
        SelectQuestLogEntry(i)
      end

      local objectives = {}
      -- Prefer index-aware API when present; fall back to selected-entry API
      local numObj = 0
      if GetNumQuestLeaderBoards then
        numObj = GetNumQuestLeaderBoards(i) or GetNumQuestLeaderBoards() or 0
      end
      for oi = 1, numObj do
        local text, otype, finished
        if GetQuestLogLeaderBoard then
          text, otype, finished = GetQuestLogLeaderBoard(oi, i)
          if not text then
            text, otype, finished = GetQuestLogLeaderBoard(oi)
          end
        end
        if text then
          table.insert(objectives, {
            text = text,
            type = otype,
            finished = (finished == 1 or finished == true),
            index = oi,
          })
        end
      end

      local description, objectiveText = nil, nil
      if GetQuestLogQuestText then
        description, objectiveText = GetQuestLogQuestText()
      end

      -- Talk / event quests often have no leaderboard row. Keep the objective text.
      if getn(objectives) == 0 and objectiveText and objectiveText ~= "" then
        local line = objectiveText
        local _, _, first = string.find(objectiveText, "^([^\n]+)")
        if first and first ~= "" then line = first end
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")
        if line ~= "" then
          table.insert(objectives, {
            text = line,
            type = "event",
            finished = (isComplete == 1 or isComplete == true),
            index = 1,
          })
        end
      end

      local entry = {
        index         = i,
        title         = title,
        level         = level or 0,
        tag           = tag,
        complete      = (isComplete == 1 or isComplete == true),
        failed        = (isComplete == -1),
        questID       = qid,
        objectives    = objectives,
        description   = description,
        objectiveText = objectiveText,
        logHeader     = currentHeader, -- quest log category/zone (Dungeon headers, professions, etc.)
      }

      table.insert(self.questLog, entry)
    end
  end

  if prevSelection and prevSelection > 0 then
    SelectQuestLogEntry(prevSelection)
  end

  -- Track completions when quests leave the log
  local newKeys = {}
  for _, q in pairs(self.questLog) do
    local key = q.questID and ("id:" .. q.questID) or ("t:" .. string.lower(q.title or ""))
    newKeys[key] = q
  end
  if self.prevLogKeys then
    for key, oldq in pairs(self.prevLogKeys) do
      if not newKeys[key] then
        -- Left the log: only record completion if it was ready to turn in.
        -- Abandoning an incomplete quest must NOT mark it complete.
        local pending = self._pendingTurnIn
        local pendingHit = false
        if pending and oldq then
          if pending.title and oldq.title and string.lower(pending.title) == string.lower(oldq.title) then
            pendingHit = true
          elseif pending.questID and oldq.questID and pending.questID == oldq.questID then
            pendingHit = true
          end
        end
        local allDone = oldq and oldq.complete
        if not allDone and oldq and oldq.objectives and getn(oldq.objectives) > 0 then
          allDone = true
          local oi
          for oi = 1, getn(oldq.objectives) do
            if oldq.objectives[oi] and not oldq.objectives[oi].finished then
              allDone = false
              break
            end
          end
        end
        if oldq and (oldq.complete or pendingHit or allDone) then
          if pendingHit then self._pendingTurnIn = nil end
          if not GreedQuestCharDB then GreedQuestCharDB = {} end
          if not GreedQuestCharDB.completed then GreedQuestCharDB.completed = {} end
          if not GreedQuestCharDB.completed[key] then
            GreedQuestCharDB.completed[key] = (time and time()) or 1
          end
          if oldq.questID then
            GreedQuestCharDB.completed["id:" .. tostring(oldq.questID)] = GreedQuestCharDB.completed[key]
          end
          if oldq.title then
            GreedQuestCharDB.completed["t:" .. string.lower(oldq.title)] = GreedQuestCharDB.completed[key]
          end
          self._needAvailableRefresh = true
        end
        self:InvalidateAvailableCache()
      end
    end
  end
  -- Drop tracker-off entries for quests that left the log
  self:PruneTrackerOff(newKeys)
  self:AnnounceLogDiff(self.prevLogKeys, newKeys)
  self.prevLogKeys = newKeys

  -- Detect whether quest set / complete flags changed (not just objective counts)
  local structureChanged = false
  local progKey = ""
  for _, q in pairs(self.questLog) do
    local k = tostring(q.questID or q.title or "")
    progKey = progKey .. k .. ":"
    if q.complete then progKey = progKey .. "C" end
    if q.objectives then
      for _, o in ipairs(q.objectives) do
        progKey = progKey .. (o.text or "") .. (o.finished and "1" or "0")
      end
    end
    progKey = progKey .. ";"
  end
  if self._lastStructKey ~= nil and self._lastStructKey ~= progKey then
    -- always true when progress changes; refine below
  end
  local oldStruct = self._lastQuestSetKey
  local setKey = ""
  for _, q in pairs(self.questLog) do
    setKey = setKey .. tostring(q.questID or q.title) .. (q.complete and "C" or "I") .. ";"
  end
  structureChanged = (oldStruct ~= setKey)
  self._lastQuestSetKey = setKey
  self._lastStructKey = progKey

  if structureChanged or self._needAvailableRefresh then
    self._needAvailableRefresh = nil
    self:InvalidateAvailableCache()
    self:StartEligibleScan()
    if GQ.Map and GQ.Map.BuildNodesFromQuestLog then
      GQ.Map:BuildNodesFromQuestLog()
    end
    self:ScheduleAvailableRefresh()
  end

  if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
  -- Progress-only: still refresh map greys for turn-ins if complete flipped
  if structureChanged and GQ.Map and GQ.Map.UpdateMinimapPins then
    GQ.Map._miniNeedsFull = true
    GQ.Map:UpdateMinimapPins()
  end
end

function Core:GetQuestByIndex(index)
  return self.questLog[index]
end

function Core:GetQuestByID(questID)
  if not questID then return nil end
  for _, q in pairs(self.questLog) do
    if q.questID == questID then return q end
  end
  return nil
end


-- Classic race bitmasks

-- ============================================================
-- Available quest eligibility + cached / batched scanning
-- ============================================================

local RACE_BITS = {
  -- Classic (1.12 UnitRace returns localized names with spaces)
  Human = 1, Orc = 2, Dwarf = 4,
  NightElf = 8, ["Night Elf"] = 8,
  Scourge = 16, Undead = 16,
  Tauren = 32, Gnome = 64, Troll = 128,
  -- Turtle expanded races (bit 256 / 512 used in race masks 434 / 589)
  Goblin = 256,
  BloodElf = 512, ["Blood Elf"] = 512,
  HighElf = 512, ["High Elf"] = 512,
}
local CLASS_BITS = {
  Warrior = 1, Paladin = 2, Hunter = 4, Rogue = 8, Priest = 16,
  Shaman = 64, Mage = 128, Warlock = 256, Druid = 1024,
}

-- eligibleCache: level/race/class/filter based (ignores quest log)
-- availableCache: eligible minus in-log / completed
Core.eligibleCache = nil
Core.eligibleCacheKey = nil
Core.availableCache = nil
Core.scanState = nil  -- active batched scan
Core.BATCH_SIZE = 80  -- quests processed per frame


function Core:GetPlayerRaceMask()
  -- 1.12 UnitRace returns localized name only ("Night Elf", not "NightElf")
  local r1, r2 = UnitRace("player")
  local race = r2 or r1
  if not race then return 0 end
  local mask = RACE_BITS[race] or (r1 and RACE_BITS[r1]) or (r2 and RACE_BITS[r2])
  if mask then return mask end
  -- Unknown race: do not treat as "all races" (that leaked opposite-faction quests)
  return 0
end

function Core:GetPlayerFactionCode()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if f == "Alliance" then return "A" end
  if f == "Horde" then return "H" end
  return nil
end

-- True if unit is usable by the player faction (nil/empty fac = neutral / ok)
function Core:UnitFactionOk(unitEntry)
  if not unitEntry then return true end
  local fac = self:GetPlayerFactionCode()
  if not fac then return true end
  local f = unitEntry.fac
  if not f or f == "" then return true end
  return f == fac
end

-- Pick best unit id from a list for this player (prefer matching fac, skip opposite)
function Core:PreferFactionUnitId(idList)
  if not idList or not GQ.Database then return nil end
  local DB = GQ.Database
  local fallback = nil
  local _, uid
  for _, uid in pairs(idList) do
    local u = DB:GetUnit(uid)
    if u then
      if self:UnitFactionOk(u) then
        -- Prefer one that actually has coords
        if u.coords and u.coords[1] then return uid end
        if not fallback then fallback = uid end
      end
    elseif not fallback then
      fallback = uid
    end
  end
  return fallback
end

-- True if quest starter NPCs are compatible with player faction.
-- Used when race mask is missing or as a second gate.
function Core:StartFactionOk(qdata)
  if not qdata or not qdata["start"] then return true end
  local fac = self:GetPlayerFactionCode()
  if not fac then return true end
  local DB = GQ.Database
  if not DB then return true end

  local function entryOk(entry)
    if not entry or type(entry) ~= "table" then return true end
    local f = entry.fac
    if not f or f == "" or f == "AH" then return true end
    return f == fac
  end

  local saw = false
  local ok = false
  local start = qdata["start"]
  if start["U"] then
    local _, uid
    for _, uid in pairs(start["U"]) do
      local u = DB:GetUnit(uid)
      if u and u.fac and u.fac ~= "" then
        saw = true
        if entryOk(u) then ok = true end
      end
    end
  end
  if start["O"] then
    local _, oid
    for _, oid in pairs(start["O"]) do
      local o = DB:GetObject(oid)
      if o and o.fac and o.fac ~= "" then
        saw = true
        if entryOk(o) then ok = true end
      end
    end
  end
  if not saw then return true end
  return ok
end

function Core:GetPlayerClassMask()
  local c1, c2 = UnitClass("player")
  local class = c2 or c1
  if not class then return 4294967295 end
  return CLASS_BITS[class] or CLASS_BITS[c1] or 4294967295
end

function Core:IsQuestInLog(questID, title)
  for _, q in pairs(self.questLog or {}) do
    if questID and q.questID == questID then return true end
    if title and q.title and string.lower(q.title) == string.lower(title) then return true end
  end
  return false
end

function Core:IsQuestCompleted(questID, title)
  if not GreedQuestCharDB or not GreedQuestCharDB.completed then return false end
  if questID and GreedQuestCharDB.completed["id:" .. tostring(questID)] then return true end
  if title and GreedQuestCharDB.completed["t:" .. string.lower(title)] then return true end
  -- Resolve title from ID for prereq checks
  if questID and GreedQuestDB and GreedQuestDB.questTitles then
    local tname = GreedQuestDB.questTitles[questID]
    if tname and GreedQuestCharDB.completed["t:" .. string.lower(tname)] then
      return true
    end
  end
  return false
end

function Core:FilterConfigKey()
  local g = GreedQuestConfig and GreedQuestConfig.general or {}
  return string.format("%s:%s:%s:%s",
    tostring(g.hidePvP and 1 or 0),
    tostring(g.hideSeasonal and 1 or 0),
    tostring(g.hideRepeatable and 1 or 0),
    tostring(g.hideLowLevel and 1 or 0))
end

function Core:CompletedFingerprint()
  local c = GreedQuestCharDB and GreedQuestCharDB.completed
  if not c then return "0" end
  local n = 0
  local k
  for k, _ in pairs(c) do
    n = n + 1
  end
  return tostring(n)
end

function Core:EligibleCacheKey()
  local lvl = UnitLevel("player") or 1
  return string.format("%d:%d:%d:%s:%s",
    lvl, self:GetPlayerRaceMask(), self:GetPlayerClassMask(),
    self:FilterConfigKey(), self:CompletedFingerprint())
end

function Core:InvalidateAvailableCache()
  self.eligibleCache = nil
  self.eligibleCacheKey = nil
  -- Keep availableCache until the new scan finishes so ! pins do not vanish
  -- for a second after a turn-in.
  if self.scanState then
    self.scanState.cancelled = true
    self.scanState = nil
  end
end

function Core:MeetsPrereqs(qdata)
  -- If a pre list exists, at least ONE must be completed
  if not qdata or not qdata["pre"] then return true end
  local hasPre = false
  for _, preId in pairs(qdata["pre"]) do
    hasPre = true
    if self:IsQuestCompleted(preId, nil) then
      return true
    end
    -- also treat "pre currently in log and complete" as done
    local q = self:GetQuestByID(preId)
    if q and q.complete then return true end
  end
  if not hasPre then return true end
  return false
end

function Core:CanAcceptQuest(qid, qdata)
  -- Mirrors pfDatabase:QuestFilter (level / race / class / pre / faction)
  if not qdata then return false end
  local playerLevel = UnitLevel("player") or 1
  local minLevel = tonumber(qdata["min"])
  local qlvl = tonumber(qdata["lvl"])

  -- Strict: player must meet the quest's minimum required level to accept
  if minLevel and minLevel > playerLevel then return false end
  -- Optional: hide grey-difficulty quests (only when filter enabled)
  if GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.hideLowLevel then
    if self:IsLowLevelQuest(qlvl or minLevel) then return false end
  end

  local prace = self:GetPlayerRaceMask()
  if qdata["race"] and qdata["race"] ~= 0 then
    if prace == 0 or not BitHit(qdata["race"], prace) then return false end
  end
  if qdata["class"] and qdata["class"] ~= 0 then
    if not BitHit(qdata["class"], self:GetPlayerClassMask()) then return false end
  end

  -- Faction gate via starter NPC/object fac (covers quests missing race masks)
  if not self:StartFactionOk(qdata) then return false end

  local start = qdata["start"]
  if not start or (not start["U"] and not start["O"] and not start["I"]) then return false end
  -- Item-start quests still need race/faction checks above; allow if I-only start
  if not start["U"] and not start["O"] and start["I"] then
    -- keep allowed if race/faction already passed
  end
  if not self:MeetsPrereqs(qdata) then return false end
  return true
end

-- Cheap pass: eligible list filtered by current log/completed
function Core:FilterEligibleToAvailable(eligible)
  local out = {}
  if not eligible then return out end
  for _, aq in ipairs(eligible) do
    if not self:IsQuestInLog(aq.questID, aq.title)
       and not self:IsQuestCompleted(aq.questID, aq.title) then
      table.insert(out, aq)
    end
  end
  return out
end

function Core:GetAvailableQuests()
  -- Fast path: log-only invalidation can reuse eligible cache
  local key = self:EligibleCacheKey()
  if self.eligibleCache and self.eligibleCacheKey == key then
    self.availableCache = self:FilterEligibleToAvailable(self.eligibleCache)
    return self.availableCache
  end

  -- Stale or missing: return last availableCache while scan runs
  if self.scanState and not self.scanState.cancelled then
    return self.availableCache or {}
  end

  self:StartEligibleScan()
  return self.availableCache or {}
end

function Core:StartEligibleScan()
  local key = self:EligibleCacheKey()
  if self.scanState and self.scanState.key == key and not self.scanState.cancelled then
    return  -- already scanning this key
  end

  local DB = GQ.Database
  if not DB or not DB:IsReady() then return end

  local playerLevel = UnitLevel("player") or 1
  local candidates
  if DB.GetAvailableCandidateIds then
    candidates = DB:GetAvailableCandidateIds(playerLevel, 8)
  else
    candidates = DB.questIdList or {}
  end

  self.scanState = {
    key = key,
    candidates = candidates,
    index = 1,
    results = {},
    cancelled = false,
  }

  local BATCH = self.BATCH_SIZE or 80
  local function step()
    local state = Core.scanState
    if not state or state.cancelled then return end
    local DB = GQ.Database
    if not DB then return end
    local titles = GreedQuestDB and GreedQuestDB.questTitles or {}
    local n = getn(state.candidates)
    local last = state.index + BATCH - 1
    if last > n then last = n end
    local i
    for i = state.index, last do
      local qid = state.candidates[i]
      local qdata = DB:GetQuest(qid)
      if qdata and Core:CanAcceptQuest(qid, qdata) then
        local title = titles[qid] or ("Quest " .. qid)
        local synthetic = {
          questID = qid,
          title = title,
          level = tonumber(qdata["lvl"]) or tonumber(qdata["min"]) or 0,
          tag = nil,
          complete = false,
          available = true,
        }
        if not Core:ShouldHideQuest(synthetic) then
          table.insert(state.results, {
            questID = qid,
            title = title,
            qdata = qdata,
            level = synthetic.level,
          })
        end
      end
    end
    state.index = last + 1
    if state.index > n then
      if not state.cancelled and state.key == Core:EligibleCacheKey() then
        Core.eligibleCache = state.results
        Core.eligibleCacheKey = state.key
        Core.availableCache = Core:FilterEligibleToAvailable(state.results)
        Core.scanState = nil
        GQ:Debug("Available scan done (" .. getn(Core.availableCache) .. " shown)")
        if GQ.Map and GQ.Map.BuildNodesFromQuestLog then
          GQ.Map:BuildNodesFromQuestLog()
        end
      else
        Core.scanState = nil
      end
    else
      if GQ.Scheduler then
        GQ.Scheduler:Enqueue(step, "eligible scan", "eligible")
      end
    end
  end
  if GQ.Scheduler then
    GQ.Scheduler:Enqueue(step, "eligible scan", "eligible")
  else
    step()
  end
end

function Core:NotifyFiltersChanged()
  self:InvalidateAvailableCache()
  self:StartEligibleScan()
end

function Core:ScheduleZoneRefresh()
  -- GetRealZoneText often lags ZONE_CHANGED; defer so zone ID is correct
  if not self.zoneRefreshFrame then
    self.zoneRefreshFrame = CreateFrame("Frame")
  end
  local f = self.zoneRefreshFrame
  f.t = 0
  f:SetScript("OnUpdate", function()
    f.t = f.t + (arg1 or 0.05)
    if f.t < 0.35 then return end
    f:SetScript("OnUpdate", nil)
    if GQ.Map and GQ.Map.ResolvePlayerZone then
      GQ.Map:ResolvePlayerZone()
    end
    if GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.currentZoneOnly then
      if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
      if GQ.Map and GQ.Map.BuildNodesFromQuestLog then GQ.Map:BuildNodesFromQuestLog() end
    else
      if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
      if GQ.Map and GQ.Map.UpdatePins then GQ.Map:UpdatePins() end
    end
  end)
end


function Core:ScheduleAvailableRefresh()
  if not self._availRefresh then
    self._availRefresh = CreateFrame("Frame")
  end
  local f = self._availRefresh
  f.t = 0
  f:SetScript("OnUpdate", function()
    f.t = f.t + (arg1 or 0.05)
    if f.t < 0.45 then return end
    f:SetScript("OnUpdate", nil)
    Core:InvalidateAvailableCache()
    Core:StartEligibleScan()
    if GQ.Map and GQ.Map.BuildNodesFromQuestLog then
      GQ.Map:BuildNodesFromQuestLog()
    end
  end)
end

function Core:HideBlizzardTracker()
  -- Hide Blizzard objective tracker only. Tracking state is owned by GreedQuest
  -- (no IsQuestWatched / watch limit).
  if QuestWatchFrame then
    QuestWatchFrame:Hide()
    local noop = function() end
    if not QuestWatchFrame._gqHidden then
      QuestWatchFrame._gqHidden = true
      QuestWatchFrame.Show = noop
    end
  end
end

function Core:QuestTrackKey(q)
  if not q then return nil end
  if q.questID then return "id:" .. tostring(q.questID) end
  if q.title then return "t:" .. string.lower(q.title) end
  return nil
end

function Core:EnsureTrackerOff()
  if not GreedQuestCharDB then GreedQuestCharDB = {} end
  if not GreedQuestCharDB.trackerOff then GreedQuestCharDB.trackerOff = {} end
  return GreedQuestCharDB.trackerOff
end

-- Show on GreedQuest tracker unless the player shift-clicked it off.
-- autoTrack (default on): every accepted quest is tracked unless excluded.
-- autoTrack off: only quests the player has shift-clicked ON appear
--   (stored as trackerOff[key] == false explicitly? simpler: use trackerOn set)
function Core:IsTrackedInLog(q)
  if not q then return false end
  local key = self:QuestTrackKey(q)
  if not key then return true end

  local auto = true
  if GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.autoTrack == false then
    auto = false
  end

  local off = GreedQuestCharDB and GreedQuestCharDB.trackerOff
  local on = GreedQuestCharDB and GreedQuestCharDB.trackerOn

  if auto then
    -- Default: tracked. Shift-click stores exclusion in trackerOff.
    if off and off[key] then return false end
    return true
  else
    -- Manual mode: only show if shift-clicked on (trackerOn).
    if on and on[key] then return true end
    return false
  end
end

function Core:ToggleTrackerForQuest(q)
  if not q then return end
  local key = self:QuestTrackKey(q)
  if not key then return end

  local auto = true
  if GreedQuestConfig and GreedQuestConfig.general and GreedQuestConfig.general.autoTrack == false then
    auto = false
  end

  local title = q.title or key
  if auto then
    local off = self:EnsureTrackerOff()
    if off[key] then
      off[key] = nil
      -- Re-tracking also clears Alt-hide so the quest can fully return
      if GreedQuestCharDB and GreedQuestCharDB.hiddenQuests then
        GreedQuestCharDB.hiddenQuests[key] = nil
        if q.questID then GreedQuestCharDB.hiddenQuests["id:" .. tostring(q.questID)] = nil end
        if q.title then GreedQuestCharDB.hiddenQuests["t:" .. string.lower(q.title)] = nil end
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r tracking: " .. title)
    else
      off[key] = 1
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r untracked: " .. title)
    end
  else
    if not GreedQuestCharDB then GreedQuestCharDB = {} end
    if not GreedQuestCharDB.trackerOn then GreedQuestCharDB.trackerOn = {} end
    local on = GreedQuestCharDB.trackerOn
    if on[key] then
      on[key] = nil
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r untracked: " .. title)
    else
      on[key] = 1
      if GreedQuestCharDB.hiddenQuests then
        GreedQuestCharDB.hiddenQuests[key] = nil
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccGreedQuest|r tracking: " .. title)
    end
  end

  if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
  if GQ.Map and GQ.Map.BuildNodesFromQuestLog then
    GQ.Map:BuildNodesFromQuestLog()
  end
end

function Core:PruneTrackerOff(newKeys)
  if not GreedQuestCharDB then return end
  if GreedQuestCharDB.trackerOff then
    for key in pairs(GreedQuestCharDB.trackerOff) do
      if not newKeys[key] then
        GreedQuestCharDB.trackerOff[key] = nil
      end
    end
  end
  if GreedQuestCharDB.trackerOn then
    for key in pairs(GreedQuestCharDB.trackerOn) do
      if not newKeys[key] then
        GreedQuestCharDB.trackerOn[key] = nil
      end
    end
  end
end

-- Shift-click in the Blizzard quest log toggles GreedQuest tracking (not Blizzard watches).
function Core:HookQuestLogTracking()
  if self._questLogHooked then return end
  self._questLogHooked = true

  local function HandleShiftToggle(btn)
    local idx = nil
    if btn and btn.GetID then idx = btn:GetID() end
    if (not idx or idx <= 0) and this and this.GetID then idx = this:GetID() end
    if not idx or idx <= 0 then return end

    local q = nil
    for _, entry in pairs(Core.questLog or {}) do
      if entry.index == idx then
        q = entry
        break
      end
    end
    if not q then
      local title, level, tag, isHeader = GetQuestLogTitle(idx)
      if not title or isHeader then return end
      local qid = nil
      if Core.ResolveQuestID then qid = Core:ResolveQuestID(title) end
      q = {
        index = idx,
        title = title,
        level = level,
        tag = tag,
        questID = qid,
      }
    end
    Core:ToggleTrackerForQuest(q)
  end

  if QuestLogTitleButton_OnClick then
    local original = QuestLogTitleButton_OnClick
    QuestLogTitleButton_OnClick = function(button)
      if IsShiftKeyDown and IsShiftKeyDown() then
        HandleShiftToggle(this)
        -- Undo any Blizzard watch so the limited watch list is never used
        if RemoveQuestWatch and this and this.GetID then
          local idx = this:GetID()
          if idx and IsQuestWatched and IsQuestWatched(idx) then
            RemoveQuestWatch(idx)
          end
        end
        if QuestWatch_Update then QuestWatch_Update() end
        Core:HideBlizzardTracker()
        if GQ.Tracker and GQ.Tracker.Refresh then GQ.Tracker:Refresh() end
        return
      end
      if original then original(button) end
      Core:HideBlizzardTracker()
    end
    GQ:Debug("Quest log shift-click tracking hooked")
  else
    GQ:Debug("QuestLogTitleButton_OnClick missing; shift-track may not work")
  end
end

function Core:Init()
  self:BuildTitleIndex()
  -- Quest log tracker works immediately; available-map scan waits ~1s
  -- so the first moments in-world stay smooth.
  self:InvalidateAvailableCache()
  if not self._deferFrame then
    self._deferFrame = CreateFrame("Frame")
  end
  local df = self._deferFrame
  df.t = 0
  df:SetScript("OnUpdate", function()
    df.t = df.t + (arg1 or 0.05)
    if df.t < 1.0 then return end
    df:SetScript("OnUpdate", nil)
    if GQ.Database and GQ.Database.IsReady and not GQ.Database:IsReady() then return end
    Core:StartEligibleScan()
    GQ:Debug("Deferred available-quest scan started")
  end)

  -- Debounced quest-log scan (loot can update counts a frame after the event)
  if not self._scanDebounce then
    self._scanDebounce = CreateFrame("Frame")
  end
  function Core:RequestScanQuestLog(delay)
    delay = delay or 0.15
    local f = self._scanDebounce
    f.t = 0
    f.delay = delay
    f:SetScript("OnUpdate", function()
      f.t = f.t + (arg1 or 0.05)
      if f.t < (f.delay or 0.15) then return end
      f:SetScript("OnUpdate", nil)
      Core:ScanQuestLog()
    end)
  end

  local f = CreateFrame("Frame")
  f:RegisterEvent("QUEST_LOG_UPDATE")
  f:RegisterEvent("QUEST_WATCH_UPDATE")
  f:RegisterEvent("PLAYER_LEVEL_UP")
  f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  f:RegisterEvent("ZONE_CHANGED")
  f:RegisterEvent("ZONE_CHANGED_INDOORS")
  f:RegisterEvent("BAG_UPDATE")
  f:RegisterEvent("UNIT_INVENTORY_CHANGED")
  f:RegisterEvent("QUEST_COMPLETE")
  f:RegisterEvent("QUEST_FINISHED")
  f:RegisterEvent("QUEST_TURNED_IN")

  f:SetScript("OnEvent", function()
    if event == "QUEST_COMPLETE" or event == "QUEST_FINISHED" or event == "QUEST_TURNED_IN" then
      local title = GetTitleText and GetTitleText() or nil
      Core._pendingTurnIn = { title = title, at = GetTime and GetTime() or 0 }
      Core:RequestScanQuestLog(0.05)
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" then
      Core:HideBlizzardTracker()
      Core:RequestScanQuestLog(0.12)
    elseif event == "BAG_UPDATE" then
      -- Item objectives often update via bags before/without a clean log event
      Core:RequestScanQuestLog(0.25)
    elseif event == "UNIT_INVENTORY_CHANGED" then
      if arg1 == "player" then
        Core:RequestScanQuestLog(0.25)
      end
    elseif event == "PLAYER_LEVEL_UP" then
      Core:InvalidateAvailableCache()
      Core:StartEligibleScan()
      Core:RequestScanQuestLog(0.1)
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
      if GQ.Map and GQ.Map.ResolvePlayerZone then
        GQ.Map:ResolvePlayerZone()
      end
      Core:ScheduleZoneRefresh()
    end
  end)

  Core:HideBlizzardTracker()
  Core:HookQuestLogTracking()
  Core:ScanQuestLog()
  GQ:Debug("Core initialized (debounced log scan)")
end
