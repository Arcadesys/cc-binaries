-- Furball's phase-1 placeholder players (src/data/placeholderRoster.ts). Light visits and
-- bats first; Dark is home. Only the fields the game uses are kept: name, number, bats.
local roster = {}

local LIGHT = {
  {"Test Fox", 7, "R"}, {"Proto Pup", 12, "L"}, {"Bun Beta", 3, "R"}, {"Mock Cat", 21, "R"}, {"Stub Bear", 44, "L"},
  {"Temp Mouse", 1, "R"}, {"Draft Wolf", 18, "R"}, {"Alpha Otter", 9, "L"}, {"Dummy Deer", 30, "R"},
}
local DARK = {
  {"Sample Skunk", 5, "R"}, {"Null Hyena", 22, "R"}, {"Lorem Lynx", 14, "L"}, {"Ipsum Possum", 2, "R"},
  {"Fixture Fennec", 11, "L"}, {"Seed Raccoon", 33, "R"}, {"Mock Doberman", 8, "R"}, {"Test Tiger", 27, "L"},
  {"Beta Bat", 13, "R"},
}

roster.players = {}
roster.light, roster.dark = {}, {}
for team, seeds in pairs({light = LIGHT, dark = DARK}) do
  for i, s in ipairs(seeds) do
    local id = team .. "-" .. i
    roster.players[id] = {id = id, name = s[1], number = s[2], bats = s[3], team = team}
    roster[team][i] = id
  end
end
roster.teamName = {light = "LIGHT", dark = "DARK"}

return roster
