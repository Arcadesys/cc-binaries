-- The furball golf kernel owns shot outcomes; this controller owns commands, forecast and playback.
local golf = require('lib.golf')
local physics = require('lib.physics')
local rules = require('lib.rules')
local course = require('lib.course')
local mascots = require('lib.mascots')
local App = {}
App.__index = App

local DEFAULT = {club = '5i', aim = 0, power = 94}

local function clubIndex(id)
  for i, club in ipairs(physics.clubs) do if club.id == id then return i end end
  return 1
end

function App.new(options)
  local self = setmetatable({options = options or {}, phase = 'TITLE', fine = false, camera = 'tee',
    shotId = 0, running = true, lastInput = 'Ready', fps = 0, mascot = 1,
    message = course.hole.club .. ' | ' .. course.hole.name}, App)
  self.sound = self.options.sound or require('lib.sound').new()
  self:reset()
  return self
end

function App:cue(name, offsetMs) self.sound:play(name, offsetMs) end

function App:emit(kind, data)
  if self.options.record then self.options.record(kind, data, self) end
end

function App:reset()
  self.round = rules.new()
  self.clubIndex = clubIndex(DEFAULT.club); self.aim = DEFAULT.aim; self.power = DEFAULT.power
  self.sim = nil; self.playback = nil; self.displayBall = nil; self.resumePhase = nil
  self:updateForecast()
end

function App:restart()
  self:reset()
  self.phase = 'AIM'
  self.message = 'Par 3, ' .. string.format('%.1f', course.hole.length) .. ' m. Choose club, aim, power; SWING.'
  self:cue('start')
  self:emit('restart')
end

function App:state() return self.round.hole end
function App:shot() return {club = physics.clubs[self.clubIndex].id, aim = self.aim, power = self.power} end

-- Calm-weather forecast of the current settings, from a copy of the hole state.
function App:updateForecast()
  if self:state().phase ~= 'ready' then self.forecast = nil; return end
  local points, finish = golf.forecast(self:state(), self:shot())
  self.forecast = {points = points, finish = finish, penalty = finish.penalties > self:state().penalties}
end

function App:aimAtCup() self.aim = golf.aimToCup(self:state()) end

function App:view()
  local s = self:state()
  return {ball = self.displayBall or s.ball, aim = self.aim, power = self.power, club = physics.clubs[self.clubIndex],
    strokes = s.strokes, penalties = s.penalties, lie = s.lie, toCup = golf.distanceToCup(s),
    carry = s.lastCarry, phase = self.phase, message = self.message, view = self.camera, fine = self.fine,
    lastInput = self.lastInput, fps = self.fps, forecast = self.phase == 'AIM' and self.forecast or nil,
    scoreName = rules.scoreName(s.strokes, course.hole.par), scoreLabel = golf.scoreLabel(s.strokes), mascot = self.mascot}
end

function App:pause(message)
  if self.phase ~= 'PAUSED' and self.phase ~= 'HELP' then self.resumePhase = self.phase end
  self.phase = 'PAUSED'; self.message = message or 'Paused. P or MENU to resume.'
end

function App:resolve()
  local result = self.sim.result
  local ok, err = rules.apply(self.round, self.shotId, result)
  self:emit('resolved', {outcome = result.outcome, surface = result.surface, carry = result.carry, ok = ok})
  local putting = self:shot().club == 'putter'
  self.displayBall = nil; self.playback = nil; self.sim = nil
  if not ok then self.phase = 'AIM'; self.message = 'Shot cancelled: ' .. tostring(err); return end
  local s = self:state()
  self.message = s.message
  if result.outcome == 'holed' then
    self:cue('cup'); self:cue(s.strokes <= course.hole.par and 'cheer' or 'finish', 450)
  elseif result.outcome == 'ob' then self:cue('ob')
  elseif result.surface == 'sand' then self:cue('sand')
  elseif result.surface == 'green' then if not putting then self:cue('green') end
  else self:cue('land') end
  if s.phase == 'finished' then
    self.phase = 'SCORECARD'
    return
  end
  -- Furball's follow-up: face the cup, putter on the green at distance-scaled power, wedge from sand.
  local suggestion = golf.suggestion(s, self:shot())
  self.clubIndex = clubIndex(suggestion.club); self.aim = suggestion.aim; self.power = suggestion.power
  self.phase = 'AIM'
  self:updateForecast()
end

function App:swing()
  local sim, err = physics.begin(self:state(), self:shot())
  if not sim then self.message = 'Shot cancelled: ' .. tostring(err); return end
  self.shotId = self.shotId + 1
  self.sim = sim; self.phase = 'SIMULATE'; self.skipPlayback = false
  self.message = self:shot().club == 'putter' and 'Putting...' or 'Swing!'
  self:cue(self:shot().club == 'putter' and 'putt' or 'swing')
  self:emit('shot', {id = self.shotId, club = self:shot().club, power = self.power, aim = self.aim})
end

function App:action(action)
  if not action then return end
  self.lastInput = action; self:emit('input', action)
  if action == 'start' and (self.phase == 'HELP' or self.phase == 'PAUSED') then
    self.phase = self.resumePhase or 'AIM'; self.resumePhase = nil; return
  end
  if action == 'quit' then self.running = false; return end
  if action == 'view' then self.camera = ({tee = 'overview', overview = 'map', map = 'tee'})[self.camera]; return end
  if action == 'help' or action == 'pause' then
    if self.phase == 'HELP' or self.phase == 'PAUSED' then
      self.phase = self.resumePhase or 'AIM'; self.resumePhase = nil
      self.message = 'Arrows aim/power | Q/E club | A aim at cup | Space swing'
    else
      self.resumePhase = self.phase; self.phase = action == 'help' and 'HELP' or 'PAUSED'
    end
    return
  end
  if action == 'restart' then self:restart(); return end
  if self.phase == 'TITLE' then
    if action == 'aim_left' or action == 'club_prev' then self.mascot=(self.mascot-2)%#mascots.list+1
    elseif action == 'aim_right' or action == 'club_next' then self.mascot=self.mascot%#mascots.list+1
    elseif action == 'start' or action == 'swing' then self:restart() end
    return
  end
  if self.phase == 'SCORECARD' then if action == 'start' or action == 'swing' then self:restart() end; return end
  if action == 'skip' and (self.phase == 'SIMULATE' or self.phase == 'SHOT_PLAYBACK') then
    self.skipPlayback = true
    if self.phase == 'SHOT_PLAYBACK' then
      while not physics.advance(self.sim) do end
      self:resolve()
    end
    return
  end
  if self.phase ~= 'AIM' then return end
  local aimStep = self.fine and 0.5 or 2
  local powerStep = self.fine and 0.5 or 5
  if action == 'aim_left' or action == 'aim_right' then
    -- Furball wraps aim into -180..180 degrees.
    self.aim = (self.aim + (action == 'aim_right' and aimStep or -aimStep) + 540) % 360 - 180
  elseif action == 'power_up' then self.power = math.min(100, self.power + powerStep)
  elseif action == 'power_down' then self.power = math.max(0.5, self.power - powerStep)
  elseif action == 'fine' then self.fine = not self.fine; return
  elseif action == 'club_next' then self.clubIndex = self.clubIndex % #physics.clubs + 1; self:cue('tick')
  elseif action == 'club_prev' then self.clubIndex = (self.clubIndex - 2) % #physics.clubs + 1; self:cue('tick')
  elseif action == 'aim_cup' then self:aimAtCup()
  elseif action == 'swing' then self:swing(); return
  else return end
  self:updateForecast()
end

function App:tick(dt)
  if self.phase == 'SIMULATE' then
    -- Each batch simulates ~2 s of flight, so playback can start at once and stay ahead.
    local done = physics.advance(self.sim, physics.maxBatch)
    if self.skipPlayback then
      while not done do done = physics.advance(self.sim) end
      self:resolve()
    else self.phase = 'SHOT_PLAYBACK'; self.playback = {elapsed = 0, index = 1}; self.message = 'Ball in motion | S / SKIP to finish' end
  elseif self.phase == 'SHOT_PLAYBACK' then
    if not self.sim.done then physics.advance(self.sim, physics.maxBatch) end
    local playback = self.playback
    playback.elapsed = playback.elapsed + dt
    local trajectory = self.sim.trajectory
    while playback.index < #trajectory and trajectory[playback.index + 1].t <= playback.elapsed do
      playback.index = playback.index + 1
    end
    self.displayBall = trajectory[playback.index]
    if self.sim.done and playback.index >= #trajectory then self:resolve() end
  end
end

-- The only event dispatcher. Simulation runs in bounded batches between events.
function App.run(options)
  options = options or {}
  local render = require('lib.render')
  local input = require('lib.input')
  local original = term.current()
  local originalFg, originalBg = original.getTextColor(), original.getBackgroundColor()
  local originalBlink = original.getCursorBlink()
  local target, monitorName = original, nil
  if not options.terminal then
    if options.monitor then
      target = assert(peripheral.wrap(options.monitor), 'Monitor not found: ' .. options.monitor)
      monitorName = options.monitor
      assert(target.isColor and target.isColor(), 'Use an Advanced Monitor')
    else
      peripheral.find('monitor', function(name, mon)
        if not monitorName and mon.isColor() then target = mon; monitorName = name end
      end)
    end
  end
  local app = App.new(options)
  local renderer, displayWidth, displayHeight
  local function rebuild()
    if renderer then pcall(function() renderer:close() end) end
    term.redirect(target); renderer = render.new(target, course)
    displayWidth, displayHeight = target.getSize()
  end
  local ok, err = xpcall(function()
    rebuild()
    if options.diagnostic then app:restart(); app.phase = 'DIAGNOSTIC' end
    local timer = os.startTimer(0.1)
    local function draw()
      local start = os.epoch('utc')
      renderer:draw(app:view())
      local elapsed = os.epoch('utc') - start
      app.fps = elapsed > 0 and math.min(10, 1000 / elapsed) or 10
      app:emit('frame', {renderMs = elapsed, width = select(1, target.getSize()), height = select(2, target.getSize())})
    end
    draw()
    while app.running do
      local event = {os.pullEventRaw()}
      local changed = false
      if event[1] == 'terminate' then app.running = false
      elseif event[1] == 'peripheral_detach' and event[2] == monitorName then
        target = original; monitorName = nil
        app:pause('Monitor detached. P resumes on this computer.'); rebuild(); changed = true
      elseif (event[1] == 'term_resize' and not monitorName) or (event[1] == 'monitor_resize' and event[2] == monitorName) then
        app:pause('Display resized. P / MENU resumes.'); rebuild(); changed = true
      elseif event[1] == 'timer' and event[2] == timer then
        local phase = app.phase
        local width, height = target.getSize()
        if monitorName and not width then
          -- The monitor vanished before its detach event arrived; fall back the same way.
          target = original; monitorName = nil
          app:pause('Monitor detached. P resumes on this computer.'); rebuild(); changed = true
        elseif width ~= displayWidth or height ~= displayHeight then
          -- CraftOS-PC scale changes do not emit monitor_resize.
          app:pause('Display resized. P / MENU resumes.'); rebuild(); changed = true
        elseif phase == 'DIAGNOSTIC' then
          local t = os.clock(); app.displayBall = {x = 6 * math.sin(t), y = 2, z = 20}
          app.message = 'Axes: +X downrange | +Y up | +Z right'; changed = true
        else app:tick(0.1); app.sound:tick(); changed = (phase == 'SIMULATE' or phase == 'SHOT_PLAYBACK') end
        timer = os.startTimer(0.1)
      else
        local action = input.action(event, renderer.buttons or {}, monitorName)
        if action then
          if app.phase == 'DIAGNOSTIC' then
            app.lastInput = action; app:emit('input', action)
            if action == 'quit' then app.running = false elseif action == 'view' then app.camera = app.camera == 'tee' and 'map' or 'tee' end
          else app:action(action); app.sound:tick() end
          changed = true
        end
      end
      if app.running and changed then draw() end
    end
  end, debug.traceback)
  if renderer then pcall(function() renderer:close() end) end
  term.redirect(original)
  original.setTextColor(originalFg); original.setBackgroundColor(originalBg)
  original.setCursorBlink(originalBlink)
  app:emit('exit', {ok = ok, error = err})
  if not ok then error(err, 0) end
  return app
end
return App
