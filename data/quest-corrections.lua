--[[
  Named quest overlays: missing objectives, destinations, scripted
  spawns, hide unimplemented IDs, profession-master breadcrumbs.
]]

GreedQuestDB = GreedQuestDB or {}

-- Hidden / unimplemented on current Octo
GreedQuestDB.turtleRemovedQuests = GreedQuestDB.turtleRemovedQuests or {}
GreedQuestDB.turtleRemovedQuests[55100] = 1 -- Join The League!
GreedQuestDB.turtleRemovedQuests[55101] = 1 -- Help The League?

-- Patch fields merged into GreedQuestDB.quests at load
GreedQuestDB.questCorrections = {
  -- Un'Goro pylons: the whole quest is "find this pylon"
  [4285] = { ["obj"] = { ["O"] = {164955} } }, -- Northern
  [4287] = { ["obj"] = { ["O"] = {164957} } }, -- Eastern
  [4288] = { ["obj"] = { ["O"] = {164956} } }, -- Western

  -- Empty-obj "find this thing" quests
  [1100] = { ["obj"] = { ["O"] = {3972} } },           -- Lonebrow's Journal remains
  [3454] = { ["obj"] = { ["O"] = {149047} } },         -- Torch of Retribution
  [5164] = { ["obj"] = { ["O"] = {176192} } },         -- Catalogue of the Wayward
  [8240] = { ["obj"] = { ["O"] = {180526} } },         -- A Bijou for Zanza (gong)

  -- Data Rescue punch-card terminals
  [2930] = { ["obj"] = { ["I"] = {9316}, ["O"] = {142345, 142475, 142476} } },

  -- Explore mines (areatrigger already exists; keep obj.A so pins always fire)
  [76]   = { ["obj"] = { ["A"] = {87, 342} } },  -- The Jasperlode Mine
  [62]   = { ["obj"] = { ["A"] = {88, 197} } },  -- The Fargodeep Mine

  -- Profession masters: do not require the optional city breadcrumb
  [6607] = { dropPre = 1 }, -- Nat Pagle, Angler Extreme
  [6610] = { dropPre = 1 }, -- Clamlette Surprise
  [6622] = { dropPre = 1 }, -- Triage (Horde)
  [6624] = { dropPre = 1 }, -- Triage (Alliance)

  -- To Survive in the Jungle: min 35, quest level stays 45
  [42041] = { ["min"] = 35, ["lvl"] = 45 },

  -- Maul'ogg Crisis talk-tos (server credit NPC is hidden)
  [40264] = { ["obj"] = { ["U"] = {92180} } }, -- I  Lord Cruk'Zogg
  [40266] = { ["obj"] = { ["U"] = {91854} } }, -- III Seer Bol'ukk
  [40272] = { ["obj"] = { ["U"] = {92180} } }, -- IX  Lord Cruk'Zogg
}

-- Extra map pins that are not in unit/object tables (scripted / destinations)
-- { x, y, zone, typ }  typ: Event | Talk | Object
GreedQuestDB.questWaypoints = {
  -- The Missing Diplomat: go to Sentry Point (Tervosh's DB pin is Theramore)
  [1265] = { { 59.7, 41.2, 15, "Talk" } },
  -- Next step: Private Hendel west of Sentry Point (coords already ok; keep a marker)
  [1266] = { { 45.3, 24.8, 15, "Talk" } },

  -- Resupplying the Excavation: Huldar on the excavation road
  [273]  = { { 52.2, 69.3, 38, "Talk" } },

  -- WANTED: Murkdeep! — scripted spawn at the southern murloc camp
  [4740] = { { 36.4, 76.6, 148, "Kill" } },

  -- Vartrus / Ancient Leaf chain — summoned in Irontree Woods
  [7632] = { { 49.5, 29.7, 361, "Talk" } },
  [7633] = { { 49.5, 29.7, 361, "Talk" } },

  -- Eranikus / Malfurion event
  [8733] = { { 53.2, 17.7, 493, "Talk" } },

  -- Children's Week sightseeing
  [1479] = { { 38.0, 80.0, 1657, "Event" } }, -- Bough of the Eternals, Darnassus
  [1558] = { { 48.0, 14.0, 38, "Event" } },   -- Stonewrought Dam
  [1687] = { { 30.5, 85.6, 40, "Event" } },   -- Westfall lighthouse
  [558]  = { { 66.3, 49.0, 15, "Talk" } },    -- Jaina, Theramore
  [910]  = { { 63.0, 38.1, 17, "Event" } },   -- Ratchet docks
  [911]  = { { 48.0, 7.2, 17, "Event" } },    -- Mor'shan rampart
  [1800] = { { 66.0, 38.0, 1497, "Event" } }, -- Lordaeron throne / Undercity
  [925]  = { { 59.8, 51.6, 1638, "Talk" } },  -- Cairne, Thunder Bluff
}

-- Scripted NPCs that have no standing spawn coords
GreedQuestDB.unitCoordFixes = {
  [10323] = "36.4,76.6,148,0",   -- Murkdeep
  [15625] = "16.0,34.0,10,0",    -- Twilight Corrupter
  [14524] = "49.5,29.7,361,0",   -- Vartrus the Ancient, Irontree
  [15362] = "53.2,17.7,493,0",   -- Malfurion Stormrage (Moonglade event)
}

-- Dungeon/elite kind so [level+] shows before accept
GreedQuestDB.questKind = GreedQuestDB.questKind or {}
GreedQuestDB.questKind[41758] = "d" -- Tainted Brambleheart
GreedQuestDB.questKind[41759] = "d" -- The Gnarled Bramblehide
GreedQuestDB.questKind[41555] = "d" -- Razorfen Grog
GreedQuestDB.questKind[40089] = "d" -- The Rampant Groveweald
GreedQuestDB.questKind[40090] = "d" -- The Unwise Elders
