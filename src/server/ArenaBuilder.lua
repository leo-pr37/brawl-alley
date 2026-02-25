--[[
	ArenaBuilder (Server)
	Builds level-specific arenas. Each level has unique geometry,
	props, lighting, and spawn points.
]]

local ArenaBuilder = {}

------------------------------------------------------------
-- SHARED HELPERS
------------------------------------------------------------
local function makePart(parent, name, size, pos, brickColor, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Anchored = true
	p.BrickColor = BrickColor.new(brickColor)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function makeSpawn(parent, pos)
	local sp = Instance.new("SpawnLocation")
	sp.Name = "SpawnLocation"
	sp.Size = Vector3.new(8, 1, 8)
	sp.Position = pos
	sp.Anchored = true
	sp.Transparency = 1
	sp.CanCollide = false
	sp.Parent = parent
end

local function makeWalls(parent, w, d, height, thickness, wallColor, material)
	local h = height or 12
	local t = thickness or 3
	makePart(parent, "BackWall",  Vector3.new(w+20, h, t), Vector3.new(0, h/2, -d/2 - t/2), wallColor, material)
	makePart(parent, "FrontWall", Vector3.new(w+20, h, t), Vector3.new(0, h/2,  d/2 + t/2), wallColor, material)
	makePart(parent, "LeftWall",  Vector3.new(t, h, d+20), Vector3.new(-w/2 - t/2, h/2, 0), wallColor, material)
	makePart(parent, "RightWall", Vector3.new(t, h, d+20), Vector3.new( w/2 + t/2, h/2, 0), wallColor, material)
end

local function addLamp(parent, pos, lightColor)
	lightColor = lightColor or Color3.fromRGB(255, 200, 100)
	local pole = makePart(parent, "LampPost", Vector3.new(0.5, 10, 0.5), pos, "Medium stone grey", Enum.Material.Metal)
	local head = makePart(parent, "LampHead", Vector3.new(1.5, 0.5, 1.5), pos + Vector3.new(0, 5.25, 0), "Institutional white", Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = lightColor
	light.Brightness = 2
	light.Range = 30
	light.Parent = pole
end

------------------------------------------------------------
-- LEVEL: ALLEY DISTRICT
------------------------------------------------------------
local function buildAlley(folder, W, D)
	-- Ground
	makePart(folder, "Ground", Vector3.new(W+20, 1, D+20), Vector3.new(0, -0.5, 0), "Dark stone grey", Enum.Material.Concrete)

	-- Street lines
	for i = -W/2, W/2, 10 do
		makePart(folder, "StreetLine", Vector3.new(1, 0.05, 4), Vector3.new(i, 0.03, 0), "Institutional white", Enum.Material.SmoothPlastic)
	end

	makeWalls(folder, W, D, 12, 3, "Dark taupe", Enum.Material.Brick)

	-- Props
	local props = {
		{"Dumpster",  Vector3.new(4,3,3),   Vector3.new(-25,1.5,-18), "Earth green",    Enum.Material.Metal},
		{"Dumpster2", Vector3.new(4,3,3),   Vector3.new(30,1.5,20),   "Earth green",    Enum.Material.Metal},
		{"Barrel1",   Vector3.new(2,3,2),   Vector3.new(-15,1.5,-20), "Brown",          Enum.Material.Wood},
		{"Barrel2",   Vector3.new(2,3,2),   Vector3.new(-13,1.5,-20), "Brown",          Enum.Material.Wood},
		{"Barrel3",   Vector3.new(2,3,2),   Vector3.new(20,1.5,18),   "Brown",          Enum.Material.Wood},
		{"Crate1",    Vector3.new(3,3,3),   Vector3.new(10,1.5,-22),  "Brick yellow",   Enum.Material.Wood},
		{"Crate2",    Vector3.new(3,3,3),   Vector3.new(13,1.5,-22),  "Brick yellow",   Enum.Material.Wood},
		{"Crate3",    Vector3.new(3,4.5,3), Vector3.new(11.5,3,-22),  "Brick yellow",   Enum.Material.Wood},
		{"Bench",     Vector3.new(5,1,1.5), Vector3.new(0,0.5,22),    "Reddish brown",  Enum.Material.Wood},
	}
	for _, p in ipairs(props) do
		makePart(folder, p[1], p[2], p[3], p[4], p[5])
	end

	addLamp(folder, Vector3.new(-20, 5, 0))
	addLamp(folder, Vector3.new(20, 5, 0))

	makeSpawn(folder, Vector3.new(0, 0.5, 10))
end

------------------------------------------------------------
-- LEVEL: SUBWAY YARD
------------------------------------------------------------
local function buildSubway(folder, W, D)
	-- Platform floor – dark concrete
	makePart(folder, "Ground", Vector3.new(W+20, 1, D+20), Vector3.new(0, -0.5, 0), "Really black", Enum.Material.Concrete)

	-- Tiled platform strip
	makePart(folder, "Platform", Vector3.new(W-10, 0.6, 10), Vector3.new(0, 0.1, -D/4), "Medium stone grey", Enum.Material.Marble)

	-- Rail tracks (two parallel rails)
	for _, z in ipairs({3, -3}) do
		makePart(folder, "Rail", Vector3.new(W-4, 0.15, 0.3), Vector3.new(0, 0.08, z), "Dark stone grey", Enum.Material.Metal)
	end
	-- Track bed
	makePart(folder, "TrackBed", Vector3.new(W-4, 0.1, 8), Vector3.new(0, 0.02, 0), "Brown", Enum.Material.Slate)

	-- Concrete walls (underground feel)
	makeWalls(folder, W, D, 10, 4, "Medium stone grey", Enum.Material.Concrete)

	-- Ceiling (low overhead)
	makePart(folder, "Ceiling", Vector3.new(W+20, 1, D+20), Vector3.new(0, 10.5, 0), "Dark stone grey", Enum.Material.Concrete)

	-- Pillars along the platform
	for x = -W/2 + 10, W/2 - 10, 15 do
		makePart(folder, "Pillar", Vector3.new(1.5, 10, 1.5), Vector3.new(x, 5, -D/4), "Medium stone grey", Enum.Material.Concrete)
	end

	-- Abandoned train car
	makePart(folder, "TrainBody", Vector3.new(20, 5, 6), Vector3.new(18, 2.8, 0), "Bright blue", Enum.Material.Metal)
	makePart(folder, "TrainRoof", Vector3.new(20, 0.5, 6.5), Vector3.new(18, 5.5, 0), "Dark stone grey", Enum.Material.Metal)
	-- Train windows (neon strips to suggest windows)
	makePart(folder, "TrainWindow", Vector3.new(18, 1.2, 0.15), Vector3.new(18, 3.8, -3.1), "Pastel Blue", Enum.Material.Neon)
	makePart(folder, "TrainWindow2", Vector3.new(18, 1.2, 0.15), Vector3.new(18, 3.8, 3.1), "Pastel Blue", Enum.Material.Neon)

	-- Ticket booth
	makePart(folder, "TicketBooth", Vector3.new(4, 4, 3), Vector3.new(-25, 2, -D/4), "Brick yellow", Enum.Material.Wood)

	-- Bench
	makePart(folder, "Bench", Vector3.new(5, 1, 1.5), Vector3.new(-10, 0.5, -D/4 + 3), "Dark stone grey", Enum.Material.Metal)

	-- Overhead fluorescent lights
	for x = -W/2 + 8, W/2 - 8, 16 do
		local lp = makePart(folder, "SubwayLight", Vector3.new(3, 0.3, 0.6), Vector3.new(x, 10, 0), "Institutional white", Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(200, 255, 200)
		light.Brightness = 1.5
		light.Range = 25
		light.Parent = lp
	end

	makeSpawn(folder, Vector3.new(-20, 0.5, 0))
end

------------------------------------------------------------
-- LEVEL: ROOFTOP RUN
------------------------------------------------------------
local function buildRooftops(folder, W, D)
	-- Rooftop surface
	makePart(folder, "Ground", Vector3.new(W+20, 1, D+20), Vector3.new(0, -0.5, 0), "Medium stone grey", Enum.Material.Concrete)

	-- Gravel texture overlay
	makePart(folder, "Gravel", Vector3.new(W, 0.05, D), Vector3.new(0, 0.03, 0), "Dark stone grey", Enum.Material.Slate)

	-- Low parapet walls (shorter, open sky)
	local parapetH = 4
	makePart(folder, "BackWall",  Vector3.new(W+8, parapetH, 2), Vector3.new(0, parapetH/2, -D/2-1), "Dark stone grey", Enum.Material.Concrete)
	makePart(folder, "FrontWall", Vector3.new(W+8, parapetH, 2), Vector3.new(0, parapetH/2,  D/2+1), "Dark stone grey", Enum.Material.Concrete)
	makePart(folder, "LeftWall",  Vector3.new(2, parapetH, D+8), Vector3.new(-W/2-1, parapetH/2, 0), "Dark stone grey", Enum.Material.Concrete)
	makePart(folder, "RightWall", Vector3.new(2, parapetH, D+8), Vector3.new( W/2+1, parapetH/2, 0), "Dark stone grey", Enum.Material.Concrete)

	-- Water tower (cylinder-ish with parts)
	makePart(folder, "WaterTowerBase",  Vector3.new(6, 8, 6), Vector3.new(-28, 4, -15), "Reddish brown", Enum.Material.Metal)
	makePart(folder, "WaterTowerTop",   Vector3.new(7, 1, 7), Vector3.new(-28, 8.5, -15), "Dark stone grey", Enum.Material.Metal)
	makePart(folder, "WaterTowerLeg1",  Vector3.new(0.5, 4, 0.5), Vector3.new(-31, -2, -18), "Medium stone grey", Enum.Material.Metal)
	makePart(folder, "WaterTowerLeg2",  Vector3.new(0.5, 4, 0.5), Vector3.new(-25, -2, -18), "Medium stone grey", Enum.Material.Metal)
	makePart(folder, "WaterTowerLeg3",  Vector3.new(0.5, 4, 0.5), Vector3.new(-31, -2, -12), "Medium stone grey", Enum.Material.Metal)
	makePart(folder, "WaterTowerLeg4",  Vector3.new(0.5, 4, 0.5), Vector3.new(-25, -2, -12), "Medium stone grey", Enum.Material.Metal)

	-- AC units / vents
	makePart(folder, "ACUnit1", Vector3.new(4, 3, 4), Vector3.new(20, 1.5, -18), "Medium stone grey", Enum.Material.Metal)
	makePart(folder, "ACUnit2", Vector3.new(3, 2.5, 3), Vector3.new(25, 1.25, 15), "Medium stone grey", Enum.Material.Metal)
	makePart(folder, "Vent1",   Vector3.new(2, 1.5, 2), Vector3.new(-10, 0.75, 20), "Dark stone grey", Enum.Material.Metal)

	-- Satellite dish
	makePart(folder, "DishPole",  Vector3.new(0.5, 5, 0.5), Vector3.new(30, 2.5, -20), "Medium stone grey", Enum.Material.Metal)
	makePart(folder, "DishHead",  Vector3.new(3, 3, 0.4), Vector3.new(30, 5.5, -20), "Institutional white", Enum.Material.Metal)

	-- Neon sign
	makePart(folder, "NeonSign", Vector3.new(10, 2, 0.3), Vector3.new(0, 4, D/2), "Really red", Enum.Material.Neon)

	-- Skylight / hatch
	makePart(folder, "Skylight", Vector3.new(5, 0.2, 5), Vector3.new(-15, 0.15, 5), "Pastel Blue", Enum.Material.Glass)

	-- Pipes
	makePart(folder, "Pipe1", Vector3.new(0.4, 3, 0.4), Vector3.new(10, 1.5, -22), "Dark stone grey", Enum.Material.Metal)
	makePart(folder, "Pipe2", Vector3.new(12, 0.4, 0.4), Vector3.new(10, 3, -22), "Dark stone grey", Enum.Material.Metal)

	-- City ambiance lights at edges
	for x = -W/2 + 5, W/2 - 5, 20 do
		local lp = makePart(folder, "EdgeLight", Vector3.new(1, 1, 1), Vector3.new(x, 0.5, D/2 - 2), "Institutional white", Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 180, 100)
		light.Brightness = 1.5
		light.Range = 20
		light.Parent = lp
	end

	makeSpawn(folder, Vector3.new(20, 0.5, 0))
end

------------------------------------------------------------
-- SPAWN POINTS PER LEVEL
------------------------------------------------------------
local ARENA_WIDTH = 120
local ARENA_DEPTH = 80

ArenaBuilder.SpawnPoints = {
	Alley = {
		{pos = Vector3.new(-ARENA_WIDTH/2 + 3, 3, -10)},
		{pos = Vector3.new(-ARENA_WIDTH/2 + 3, 3, 10)},
		{pos = Vector3.new( ARENA_WIDTH/2 - 3, 3, -10)},
		{pos = Vector3.new( ARENA_WIDTH/2 - 3, 3, 10)},
		{pos = Vector3.new(-20, 3, -ARENA_DEPTH/2 + 3)},
		{pos = Vector3.new( 15, 3, -ARENA_DEPTH/2 + 3)},
		{pos = Vector3.new(0, 3, ARENA_DEPTH/2 - 3)},
		{pos = Vector3.new(-25, 12, -5)},
		{pos = Vector3.new( 30, 12, 5)},
	},
	Subway = {
		{pos = Vector3.new(-ARENA_WIDTH/2 + 5, 3, -5)},
		{pos = Vector3.new(-ARENA_WIDTH/2 + 5, 3, 5)},
		{pos = Vector3.new( ARENA_WIDTH/2 - 5, 3, -5)},
		{pos = Vector3.new( ARENA_WIDTH/2 - 5, 3, 5)},
		{pos = Vector3.new(-10, 3, ARENA_DEPTH/2 - 5)},
		{pos = Vector3.new( 10, 3, ARENA_DEPTH/2 - 5)},
		{pos = Vector3.new(0, 3, -ARENA_DEPTH/2 + 5)},
	},
	Rooftops = {
		{pos = Vector3.new(-ARENA_WIDTH/2 + 5, 3, -8)},
		{pos = Vector3.new(-ARENA_WIDTH/2 + 5, 3, 8)},
		{pos = Vector3.new( ARENA_WIDTH/2 - 5, 3, -8)},
		{pos = Vector3.new( ARENA_WIDTH/2 - 5, 3, 8)},
		{pos = Vector3.new(0, 3, -ARENA_DEPTH/2 + 5)},
		{pos = Vector3.new(0, 3,  ARENA_DEPTH/2 - 5)},
		{pos = Vector3.new(-20, 12, 0)},
		{pos = Vector3.new( 25, 12, 0)},
	},
}

ArenaBuilder.PlayerSpawns = {
	Alley    = Vector3.new(0, 4, 10),
	Subway   = Vector3.new(-20, 4, 0),
	Rooftops = Vector3.new(20, 4, 0),
}

------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------
local builders = {
	Alley    = buildAlley,
	Subway   = buildSubway,
	Rooftops = buildRooftops,
}

function ArenaBuilder.Build(arenaFolder, levelKey)
	arenaFolder:ClearAllChildren()
	local builder = builders[levelKey] or builders.Alley
	builder(arenaFolder, ARENA_WIDTH, ARENA_DEPTH)
end

function ArenaBuilder.GetRandomSpawnPos(levelKey)
	local points = ArenaBuilder.SpawnPoints[levelKey] or ArenaBuilder.SpawnPoints.Alley
	local sp = points[math.random(1, #points)]
	local jitter = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	return sp.pos + jitter
end

function ArenaBuilder.GetPlayerSpawn(levelKey)
	return ArenaBuilder.PlayerSpawns[levelKey] or ArenaBuilder.PlayerSpawns.Alley
end

return ArenaBuilder
