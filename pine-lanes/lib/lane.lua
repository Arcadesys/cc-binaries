-- Canonical one-lane geometry in meters. X runs toward the pins; Z is across.
local lane = {
  width = 1.0541,
  foulLine = 0,
  headX = 18.288,
  pinSpacing = 0.3048,
  pinRadius = 0.057,
  pinHeight = 0.381,
  ballRadius = 0.1085,
  gutterWidth = 0.22,
  endX = 21.0,
}

function lane.newRack()
  local s, x = lane.pinSpacing, lane.headX
  local locations = {
    {x, 0},
    {x+s*math.sqrt(3)/2, -s/2}, {x+s*math.sqrt(3)/2, s/2},
    {x+s*math.sqrt(3), -s}, {x+s*math.sqrt(3), 0}, {x+s*math.sqrt(3), s},
    {x+3*s*math.sqrt(3)/2, -1.5*s}, {x+3*s*math.sqrt(3)/2, -0.5*s},
    {x+3*s*math.sqrt(3)/2, 0.5*s}, {x+3*s*math.sqrt(3)/2, 1.5*s},
  }
  local rack = {}
  for id, p in ipairs(locations) do
    rack[id] = {id=id,x=p[1],z=p[2],angle=0,tilt=0,down=false}
  end
  return rack
end

return lane
