--[[
  Tiny frame-budgeted job queue for 1.12.
  Caps work so pin plans / scans cannot stall a frame.
]]

GreedQuest = GreedQuest or {}
local GQ = GreedQuest

GQ.Scheduler = GQ.Scheduler or {}
local S = GQ.Scheduler

S.maxJobsPerFrame = 2
S.maxSecondsPerFrame = 0.004
S.queue = S.queue or {}
S.head = S.head or 1
S.tail = S.tail or 0
S.delayed = S.delayed or {}
S.generation = S.generation or 0

local function Now()
  if GetTime then return GetTime() end
  return 0
end

function S:Bump()
  self.generation = (self.generation or 0) + 1
  return self.generation
end

function S:IsCurrent(gen)
  return gen and gen == self.generation
end

function S:Enqueue(fn, label, key)
  if not fn then return end
  -- Replace an existing queued job with the same key
  if key then
    local i
    for i = self.head, self.tail do
      local job = self.queue[i]
      if job and job.key == key then
        job.fn = fn
        job.label = label
        return
      end
    end
  end
  self.tail = self.tail + 1
  self.queue[self.tail] = { fn = fn, label = label, key = key }
  self:EnsureTicker()
end

function S:After(delay, fn, key)
  delay = delay or 0
  if delay <= 0 then
    self:Enqueue(fn, "timer", key)
    return
  end
  table.insert(self.delayed, { t = delay, fn = fn, key = key })
  self:EnsureTicker()
end

function S:CancelKey(key)
  if not key then return end
  local i
  for i = self.head, self.tail do
    local job = self.queue[i]
    if job and job.key == key then
      self.queue[i] = nil
    end
  end
  local keep = {}
  local _, d
  for _, d in ipairs(self.delayed) do
    if d.key ~= key then table.insert(keep, d) end
  end
  self.delayed = keep
end

function S:EnsureTicker()
  if self._frame then return end
  local f = CreateFrame("Frame")
  self._frame = f
  f:SetScript("OnUpdate", function()
    S:Tick(arg1 or 0.01)
  end)
end

function S:Tick(dt)
  -- Promote delayed jobs
  if getn(self.delayed) > 0 then
    local keep = {}
    local _, d
    for _, d in ipairs(self.delayed) do
      d.t = d.t - dt
      if d.t <= 0 then
        self:Enqueue(d.fn, "timer", d.key)
      else
        table.insert(keep, d)
      end
    end
    self.delayed = keep
  end

  local jobs = 0
  local started = Now()
  while self.head <= self.tail and jobs < self.maxJobsPerFrame do
    local job = self.queue[self.head]
    self.queue[self.head] = nil
    self.head = self.head + 1
    if job and job.fn then
      local ok, err = pcall(job.fn)
      if not ok and GQ.Debug then
        GQ:Debug("Scheduler: " .. tostring(err))
      end
      jobs = jobs + 1
      if GetTime and (Now() - started) >= self.maxSecondsPerFrame then
        break
      end
    end
  end

  if self.head > self.tail then
    self.head = 1
    self.tail = 0
    self.queue = {}
    if getn(self.delayed) == 0 then
      -- stay ticking; cheap and avoids recreate
    end
  end
end
