-- One-lane geometry in furball-simulator scene units (lib/pindeck.lua).
-- Pine axes: X runs from the release point toward the pins, Y is up, Z is across (+ right).
-- A furball scene point (x, z) maps to Pine (X = RELEASE_Z - z, Z = x).
local deck = require("lib.pindeck")

local lane = {
  width = deck.GUTTER_EDGE * 2,
  foulLine = 0,
  headX = deck.RELEASE_Z - deck.HEAD_PIN_Z,
  rowDepth = deck.PIN_ROW_DEPTH,
  pinSpacing = 1.1,
  pinRadius = deck.PIN_RADIUS,
  pinHeight = 1.25, -- furball pinModel.ts: 15 regulation inches at 2.4 in belly radius
  ballRadius = deck.BALL_RADIUS,
  gutterWidth = (deck.GUTTER_CENTER - deck.GUTTER_EDGE) * 2,
  gutterCenter = deck.GUTTER_CENTER,
  deckStartX = deck.RELEASE_Z - deck.DECK_BOUNDS.maxZ,
  endX = deck.RELEASE_Z - deck.DECK_BOUNDS.minZ,
}

function lane.toPine(x, z) return deck.RELEASE_Z - z, x end

function lane.newRack()
  local rack = {}
  for _, pin in ipairs(deck.PINS) do
    rack[pin.id] = {id=pin.id, x=lane.headX + pin.row * lane.rowDepth, z=pin.x, angle=0, tilt=0, down=false}
  end
  return rack
end

return lane
