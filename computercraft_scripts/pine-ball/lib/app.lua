-- Match controller: furball-simulator src/game/match.ts flow on a pausable game clock.
-- The kernel (lib/baseball.lua) and play rules (lib/plays.lua) decide every outcome;
-- this module owns timing, input capture, presentation state and the event loop.
local bb = require("lib.baseball")
local plays = require("lib.plays")
local roster = require("lib.roster")
local rng = require("lib.rng")
local App = {}
App.__index = App

-- Strike zone and release as drawn at the plate (match.ts), metres.
App.ZONE_HALF_WIDTH, App.ZONE_CENTER_Y, App.ZONE_HALF_HEIGHT = 0.26, 0.8, 0.32
App.RELEASE = {x = 0.15, y = 1.9, z = -plays.MOUND_DISTANCE + 1.2}
App.CATCHER_BALL_DEPTH = 1.3
local IMPACT_HOLD_MS = {weak = 12, good = 20, perfect = 28}

function App.new(options)
  options = options or {}
  local self = setmetatable({options = options, running = true, mode = options.mode or "cpu",
    innings = options.innings or bb.DEFAULT_INNINGS, phase = "SETUP", clock = 0, held = {},
    message = "Choose CPU or 2-player duel, then START.", lastInput = "Ready"}, App)
  self.seed = math.floor(tonumber(options.seed) or ((os.epoch and os.epoch("utc") or os.time()) % 1000000))
  self:newGame()
  return self
end

function App:emit(kind, data) if self.options.record then self.options.record(kind, data, self) end end

function App:newGame()
  self.state = bb.createGame({light = roster.light, dark = roster.dark}, self.innings)
  self.next = rng.create(self.seed)
  self.fieldingNext = rng.create(bit32.bxor(self.seed, plays.FIELDING_SEED_SALT))
  self.fielding = bb.copy(bb.DEFAULT_FIELDING)
  self.pitch, self.swing, self.play, self.flash, self.board = nil, nil, nil, nil, nil
  self.draft = {type = 1, x = 0, y = 0}
end

-- Pausable presentation clock: overlays and resizes freeze every deadline.
function App:advance(dt)
  if self.phase == "HELP" or self.phase == "PAUSED" then return end
  self.clock = self.clock + math.max(0, math.min(250, dt))
  self:update()
end

function App:aim()
  local h = self.held
  return {x = (h.right and 1 or 0) - (h.left and 1 or 0), y = (h.up and 1 or 0) - (h.down and 1 or 0)}
end

function App:batter() return roster.players[bb.currentBatter(self.state)] end

function App:roles()
  if self.mode ~= "duel" then return nil end
  return bb.battingTeam(self.state) == "light" and {batter = "P1 LIGHT", pitcher = "P2 DARK"} or {batter = "P2 DARK", pitcher = "P1 LIGHT"}
end

function App:start()
  self:newGame()
  self.phase = "INTRO"; self.deadline = self.clock + plays.INTRO_MS
  self.message = "PLAY BALL! " .. self:batter().name .. " leads off."
  self:emit("start", {mode = self.mode, seed = self.seed})
end

function App:nextPitch()
  self.swing, self.play, self.pitch = nil, nil, nil
  self.board = nil
  if self.mode == "duel" then
    self.phase = "PITCH_SELECT"
    self.message = self:roles().pitcher .. " pitches: 1-4 type, WASD spot, E throw"
  else
    self:beginWindup(bb.cpuPitch(self.next))
  end
end

function App:beginWindup(pitch)
  self.phase = "WINDUP"; self.deadline = self.clock + plays.WINDUP_MS
  self.pitch = {pitch = pitch, releasedAt = self.deadline, arrivesAt = self.deadline + bb.PITCH_TRAVEL_MS[pitch.type]}
  self.message = "Now batting: " .. self:batter().name .. " #" .. self:batter().number
  self:emit("delivery", pitch)
end

-- swingPresentation.ts captureSwing + visibleSwingTiming; outcome resolved at the press.
function App:captureSwing(at, aim)
  local p = self.pitch
  local offset = at + bb.SWING_DRIVE_MS - p.arrivesAt
  local tier = bb.contactTier(p.pitch.location, offset)
  local batter = self:batter()
  local event = bb.resolvePitch(p.pitch, {timingOffsetMs = offset, aim = aim, bats = batter.bats}, self.next)
  local contact = tier ~= nil and (event.kind == "IN_PLAY" or event.kind == "FOUL")
  self.swing = {inputAt = at, offset = offset, aim = aim, tier = contact and tier or nil, event = event,
    location = p.pitch.location, visibleContactAt = contact and math.max(p.arrivesAt, at) or at + bb.SWING_DRIVE_MS,
    holdMs = contact and IMPACT_HOLD_MS[tier] or 0, batterId = batter.id}
  self:emit("swing", {offset = offset, aim = aim, event = event})
end

function App:swingPressed()
  if self.phase == "INTRO" then self:nextPitch(); return end
  if self.phase == "FINAL" then self:start(); return end
  if (self.phase == "WINDUP" or self.phase == "PITCH") and not self.swing then
    self:captureSwing(self.clock, self:aim())
  end
end

function App:commit(t, info)
  local prev = self.state
  local label, big = plays.headline(t.callouts, 0)
  local detail, runs = plays.detail(t, prev, info or {})
  label = plays.headline(t.callouts, runs)
  for _, c in ipairs(t.callouts) do
    if c == "SIDE_RETIRED" then
      -- Hold the completed half on the board through the third-out presentation.
      self.board = bb.copy(prev); self.board.score = bb.copy(t.state.score); self.board.outs = bb.OUTS_PER_HALF
    end
  end
  self.state = t.state
  if label then self.flash = {label = label, big = big, detail = detail} end
  self:emit("commit", {callouts = t.callouts, runs = runs, label = label, detail = detail})
end

function App:presentEvent(event)
  local t = bb.applyPitchEvent(self.state, event)
  local miss = self.swing and self.swing.event.kind == "SWINGING_STRIKE" and self.swing or nil
  self:commit(t, {miss = miss})
  self.phase = "RESULT"
  self.deadline = self.clock + ((event.kind == "SWINGING_STRIKE" and self.swing) and plays.MISS_FEEDBACK_MS or plays.PITCH_RESULT_MS)
end

function App:beginInPlay(result, start)
  local batterId = bb.currentBatter(self.state)
  local r = plays.resolveInPlay(self.state, {light = roster.light, dark = roster.dark}, result, self.fielding, self.fieldingNext)
  local endMs = r.groundThrow and r.groundThrow.arrivalMs or plays.FLIGHT_MS
  self.play = {start = start, result = r.result, resolved = r.resolved, pending = r.pending, fielder = r.fielder,
    groundThrow = r.groundThrow, moves = plays.runnerMoves(self.state, r.pending, batterId), batterId = batterId,
    prev = self.state, commitAt = start + endMs, committed = false, untilMs = start + endMs + plays.IN_PLAY_HOLD_MS}
  self.phase = "IN_PLAY"
  self.message = "In play!"
  self:emit("inPlay", {result = r.result, resolved = r.resolved, fielding = r.fielder and r.fielder.plan and r.fielder.plan.outcome})
end

function App:afterEvent()
  self.flash = nil
  if self.state.status == "final" then
    self.phase = "FINAL"
    local s = self.state.score
    self.message = (s.light > s.dark and "LIGHT" or "DARK") .. " WINS " .. math.max(s.light, s.dark) .. "-" .. math.min(s.light, s.dark) .. "! SPACE plays again."
    self:emit("final", {score = s})
  else self:nextPitch() end
end

function App:update()
  local now, p = self.clock, self.pitch
  if self.phase == "INTRO" then
    if now >= self.deadline then self:nextPitch() end
  elseif self.phase == "WINDUP" then
    if now >= self.deadline then self.phase = "PITCH" end
  elseif self.phase == "PITCH" then
    local s = self.swing
    if s and now >= s.visibleContactAt then
      if s.tier then
        self.phase = "CONTACT"; self.launchAt = now + s.holdMs
      elseif now >= math.max(p.arrivesAt + bb.CONTACT_WINDOW_MS, s.inputAt + bb.SWING_DURATION_MS) then
        self:presentEvent(s.event)
      end
    elseif not s and now >= p.arrivesAt + bb.CONTACT_WINDOW_MS then
      self:presentEvent(bb.resolvePitch(p.pitch, {timingOffsetMs = nil, aim = {x = 0, y = 0}, bats = self:batter().bats}, self.next))
    end
  end
  if self.phase == "CONTACT" and now >= self.launchAt then
    if self.swing.event.kind == "FOUL" then
      self.phase = "FOUL"; self.foulStart = self.launchAt
    else self:beginInPlay(self.swing.event.result, self.launchAt) end
  end
  if self.phase == "FOUL" and now >= self.foulStart + plays.FOUL_FLIGHT_MS then
    self:commit(bb.applyPitchEvent(self.state, {kind = "FOUL"}), {})
    self.phase = "RESULT"; self.deadline = now + plays.PITCH_RESULT_MS
  elseif self.phase == "IN_PLAY" then
    local play = self.play
    if not play.committed and now >= play.commitAt then
      play.committed = true
      self:commit(play.pending, {groundThrow = play.groundThrow, fielding = play.fielder and play.fielder.plan and play.fielder.plan.outcome})
    end
    if now >= play.untilMs then self:afterEvent() end
  elseif self.phase == "RESULT" then
    if now >= self.deadline then self:afterEvent() end
  end
end

function App:pause(message)
  if self.phase ~= "PAUSED" and self.phase ~= "HELP" then self.resumePhase = self.phase end
  self.phase = "PAUSED"; self.message = message or "Paused. P or MENU resumes."
end
function App:resume() self.phase = self.resumePhase or "SETUP"; self.resumePhase = nil end

function App:action(action)
  if not action then return end
  self.lastInput = action; self:emit("input", action)
  if action == "quit" then
    if self.phase == "PAUSED" or self.phase == "HELP" or self.phase == "SETUP" or self.phase == "FINAL" or self.smallDisplay then self.running = false end
    return
  end
  if self.smallDisplay then return end
  if action == "pause" then if self.phase == "PAUSED" then self:resume() else self:pause() end; return end
  if action == "help" then
    if self.phase == "HELP" then self:resume()
    else if self.phase ~= "PAUSED" then self.resumePhase = self.phase end; self.phase = "HELP" end
    return
  end
  if self.phase == "HELP" or self.phase == "PAUSED" then
    if action == "swing" or action == "start" then self:resume()
    elseif action == "restart" then self.phase = "SETUP"; self.resumePhase = nil; self:newGame() end
    return
  end
  if self.phase == "SETUP" then
    if action == "mode" or action == "hold_up" or action == "hold_down" then self.mode = self.mode == "cpu" and "duel" or "cpu"
    elseif action == "innings_up" or action == "hold_right" then self.innings = math.min(9, self.innings + 1)
    elseif action == "innings_down" or action == "hold_left" then self.innings = math.max(1, self.innings - 1)
    elseif action == "swing" or action == "start" then self:start() end
    return
  end
  -- Held aim keys; a touch AIM button cycles the same values.
  local hold = action:match("^hold_(%a+)$")
  if hold then self.held[hold] = true; return end
  local release = action:match("^release_(%a+)$")
  if release then self.held[release] = nil; return end
  if action == "aim_x" then
    local x = self:aim().x; self.held.left, self.held.right = x == 0 and true or nil, x == -1 and true or nil; return
  elseif action == "aim_y" then
    local y = self:aim().y; self.held.down, self.held.up = y == 0 and true or nil, y == -1 and true or nil; return
  end
  if action == "swing" or (action == "start" and self.phase == "FINAL") then self:swingPressed(); return end
  if action == "restart" and self.phase == "FINAL" then self.phase = "SETUP"; self:newGame(); return end
  if self.phase == "PITCH_SELECT" then
    local d = self.draft
    local n = tonumber(action:match("^pitch_(%d)$"))
    if action == "pitch_cycle" then d.type = d.type % #bb.PITCH_TYPES + 1
    elseif n then d.type = n
    elseif action == "pitch_left" then d.x = math.max(-bb.PITCH_LOCATION_LIMIT, d.x - bb.PITCH_AIM_STEP)
    elseif action == "pitch_right" then d.x = math.min(bb.PITCH_LOCATION_LIMIT, d.x + bb.PITCH_AIM_STEP)
    elseif action == "pitch_up" then d.y = math.min(bb.PITCH_LOCATION_LIMIT, d.y + bb.PITCH_AIM_STEP)
    elseif action == "pitch_down" then d.y = math.max(-bb.PITCH_LOCATION_LIMIT, d.y - bb.PITCH_AIM_STEP)
    elseif action == "throw" then
      local pitch = bb.copyPlayerPitch({type = bb.PITCH_TYPES[d.type], location = {x = d.x, y = d.y}})
      if pitch then self:beginWindup(pitch) end
    end
  end
end

-- Positions for the renderer, all in furball field metres (home at origin, CF toward -z).
local function smooth(t) return t * t * (3 - 2 * t) end
function App:pitchPoint(now)
  local p = self.pitch
  local duration = p.arrivesAt - p.releasedAt
  local elapsed = math.max(0, now - p.releasedAt)
  local t = math.min(1, elapsed / duration)
  local s = smooth(t)
  local plate = {x = p.pitch.location.x * App.ZONE_HALF_WIDTH, y = App.ZONE_CENTER_Y + p.pitch.location.y * App.ZONE_HALF_HEIGHT, z = 0}
  local r = App.RELEASE
  return {x = r.x + (plate.x - r.x) * s - bb.PITCH_BREAK[p.pitch.type] * 0.52 * (1 - s) ^ 2,
    y = r.y + (plate.y - r.y) * s + math.sin(math.pi * t) ^ 2 * 0.25,
    z = math.min(App.CATCHER_BALL_DEPTH, r.z + (plate.z - r.z) * elapsed / duration)}
end

local function flightPoint(o, e, progress, apex)
  local t = math.max(0, math.min(1, progress))
  local bounce = apex < 1 and math.abs(math.sin(t * math.pi * 4)) or 1
  return {x = o.x + (e.x - o.x) * t, y = o.y + (e.y - o.y) * t + 4 * apex * t * (1 - t) * bounce, z = o.z + (e.z - o.z) * t}
end

function App:scene()
  local now = self.clock
  local s = {camera = "batting", runners = {}, fielders = {}, batter = nil}
  local playState = self.play and self.play.prev or self.state
  local defense = plays.fielders(playState, {light = roster.light, dark = roster.dark})
  for i, f in ipairs(defense) do s.fielders[i] = {id = f.id, pos = f.pos, x = f.x, z = f.z, team = bb.fieldingTeam(playState)} end
  local batting = bb.battingTeam(playState)
  for k, base in pairs({first = 2, second = 3, third = 4}) do
    local id = playState.bases[k]
    if id then s.runners[#s.runners + 1] = {id = id, x = plays.BASES[base].x, z = plays.BASES[base].z, team = batting} end
  end
  if self.phase ~= "SETUP" and self.phase ~= "FINAL" then
    local batter = roster.players[bb.currentBatter(playState)]
    s.batter = {id = batter.id, bats = batter.bats, team = batting, x = batter.bats == "R" and -1.15 or 1.15, z = 0.25}
  end
  if self.phase == "WINDUP" then
    s.ball = {x = App.RELEASE.x, y = 1.5 + 0.4 * math.max(0, 1 - (self.deadline - now) / plays.WINDUP_MS), z = App.RELEASE.z - 0.4}
  elseif self.phase == "PITCH" or self.phase == "RESULT" and self.pitch and not self.play then
    s.ball = self:pitchPoint(math.min(now, self.pitch.arrivesAt + 400))
    s.zone = true
  elseif self.phase == "CONTACT" then
    s.ball = self:pitchPoint(self.pitch.arrivesAt); s.zone = true; s.impact = self.swing.tier
  elseif self.phase == "FOUL" then
    local o = self:pitchPoint(self.pitch.arrivesAt)
    local sideSign = (self.swing.offset <= 0 and -1 or 1) * (self:batter().bats == "L" and -1 or 1)
    s.ball = flightPoint(o, {x = sideSign * 14, y = 0.4, z = 8}, (now - self.foulStart) / plays.FOUL_FLIGHT_MS, 5)
  elseif self.phase == "IN_PLAY" then
    local play = self.play
    local elapsed = now - play.start
    s.camera = "field"
    local spot, land = plays.landingSpot(play.result)
    local fielder = play.fielder
    local caught = fielder and fielder.plan and fielder.plan.outcome == "caught"
    local target = caught and {x = fielder.to.x, y = 1.2, z = fielder.to.z} or {x = spot.x, y = 0, z = spot.z}
    local origin = self.pitch and self:pitchPoint(self.pitch.arrivesAt) or {x = 0, y = 1, z = 0}
    s.ball = flightPoint(origin, target, elapsed / plays.FLIGHT_MS, land.apex)
    if play.groundThrow and elapsed > play.groundThrow.releaseMs then
      local base = plays.BASES[play.groundThrow.base + 1]
      local t = math.min(1, (elapsed - play.groundThrow.releaseMs) / plays.GROUND_THROW_MS)
      s.ball = flightPoint({x = fielder.to.x, y = 1.25, z = fielder.to.z}, {x = base.x, y = 1.25, z = base.z}, t, 1.5)
    end
    if fielder then
      local progress = fielder.plan and bb.pursuitProgress(fielder.plan, elapsed) or math.min(1, elapsed / plays.FLIGHT_MS)
      for _, f in ipairs(s.fielders) do
        if f.id == fielder.id then f.x = fielder.from.x + (fielder.to.x - fielder.from.x) * progress; f.z = fielder.from.z + (fielder.to.z - fielder.from.z) * progress end
      end
    end
    -- Runners leave once the swing finishes and take the whole flight to arrive.
    s.runners, s.batter = {}, nil
    local runT = math.min(1, elapsed / plays.FLIGHT_MS)
    for _, m in ipairs(play.moves) do
      if not (m.out and runT >= 1) and not (m.to == 4 and runT >= 1) then
        local at = plays.basepathPoint(m.from + (m.to - m.from) * runT)
        s.runners[#s.runners + 1] = {id = m.id, x = at.x, z = at.z, team = batting, out = m.out}
      end
    end
    s.landing = spot
  end
  return s
end

function App:view()
  local board = self.board or self.state
  local batter = (self.phase ~= "SETUP") and self:batter() or nil
  return {phase = self.phase, mode = self.mode, innings = self.innings, board = board, state = self.state,
    batter = batter, roles = self:roles(), aim = self:aim(), draft = self.draft, flash = self.flash,
    message = self.message, lastInput = self.lastInput, scene = self:scene(), pitch = self.pitch,
    swing = self.swing, smallDisplay = self.smallDisplay}
end

function App.run(options)
  options = options or {}
  local render = require("lib.render"); local input = require("lib.input")
  local original = term.current(); local fg, bg, blink = original.getTextColor(), original.getBackgroundColor(), original.getCursorBlink()
  local target, monitorName = original, nil
  if not options.terminal then
    if options.monitor then
      target = assert(peripheral.wrap(options.monitor), "Monitor not found: " .. options.monitor); monitorName = options.monitor
      assert(target.isColor and target.isColor(), "Use an Advanced Monitor")
    else peripheral.find("monitor", function(name, mon) if not monitorName and mon.isColor() then target = mon; monitorName = name end end) end
  end
  local app = App.new(options); local renderer, width, height
  local function rebuild()
    if renderer then pcall(function() renderer:close() end) end
    term.redirect(target); renderer = render.new(target); width, height = target.getSize(); app.smallDisplay = width < 39 or height < 19
  end
  local ok, err = xpcall(function()
    rebuild()
    local last = os.epoch("utc")
    local timer = os.startTimer(0.05)
    local function draw()
      local start = os.epoch("utc"); renderer:draw(app:view())
      app:emit("frame", {renderMs = os.epoch("utc") - start, width = width, height = height})
    end
    local function tick()
      local now = os.epoch("utc"); app:advance(now - last); last = now
    end
    draw()
    while app.running do
      local event = {os.pullEventRaw()}
      if event[1] == "terminate" then app.running = false
      elseif event[1] == "peripheral_detach" and event[2] == monitorName then
        target = original; monitorName = nil; app:pause("Monitor detached. Resume here."); rebuild()
      elseif (event[1] == "monitor_resize" and event[2] == monitorName) or (event[1] == "term_resize" and not monitorName) then
        app:pause("Display resized. Resume when ready."); rebuild()
      elseif event[1] == "timer" and event[2] == timer then
        local w, h = target.getSize()
        if monitorName and not w then target = original; monitorName = nil; app:pause("Monitor detached. Resume here."); rebuild()
        elseif w ~= width or h ~= height then app:pause("Display resized. Resume when ready."); rebuild() end
        tick()
        -- Fast frames while the ball is live; a slower idle cadence otherwise.
        local live = app.phase == "WINDUP" or app.phase == "PITCH" or app.phase == "CONTACT" or app.phase == "FOUL" or app.phase == "IN_PLAY"
        timer = os.startTimer(live and 0.05 or 0.1)
      else
        -- Advance the clock to this exact event before acting, so swing timing uses the press time.
        local action = input.action(event, renderer.buttons or {}, monitorName)
        if action then tick(); app:action(action) end
      end
      if app.running then draw() end
    end
  end, debug.traceback)
  if renderer then pcall(function() renderer:close() end) end
  term.redirect(original); original.setTextColor(fg); original.setBackgroundColor(bg); original.setCursorBlink(blink)
  app:emit("exit", {ok = ok, error = err}); if not ok then error(err, 0) end
  return app
end

return App
