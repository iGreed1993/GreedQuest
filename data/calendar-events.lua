-- Seasonal calendar windows (Turtle/Octo 2026)
GreedQuestDB = GreedQuestDB or {}
GreedQuestDB.calendarEvents = {
  [1] = { name="Midsummer Fire Festival", startMonth=6, startDay=21, endMonth=7, endDay=12 },
  [2] = { name="Feast of Winter Veil", startMonth=12, startDay=3, endMonth=1, endDay=14 },
  [7] = { name="Lunar Festival", startMonth=2, startDay=16, endMonth=3, endDay=4 },
  [8] = { name="Love is in the Air", startMonth=2, startDay=1, endMonth=2, endDay=16 },
  [9] = { name="Noblegarden", startMonth=4, startDay=17, endMonth=5, endDay=8 },
  [11] = { name="Harvest Festival", startMonth=10, startDay=1, endMonth=10, endDay=8 },
  [12] = { name="Hallow's End", startMonth=10, startDay=20, endMonth=11, endDay=2 },
  [26] = { name="Brewfest", startMonth=9, startDay=20, endMonth=10, endDay=6 },
  [28] = { name="Noblegarden", startMonth=4, startDay=17, endMonth=5, endDay=8 },
}
-- Seasonal event IDs for hide-seasonal (even without date window)
GreedQuestDB.seasonalEventIds = {
  [1] = true,
  [2] = true,
  [7] = true,
  [8] = true,
  [9] = true,
  [10] = true,
  [11] = true,
  [12] = true,
  [26] = true,
  [28] = true,
}
