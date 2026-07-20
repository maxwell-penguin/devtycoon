-- Assigns each player a private neighborhood plot (own folder + origin in
-- workspace) shared by Dog Walking (always-free starter) and DoorDash (cash-
-- gated unlock) — a dog-walker and a delivery driver plausibly work the same
-- block, and Scale-tier upgrades need each player's neighborhood to look
-- different. Ported from the PLOT_ORIGINS pattern proven on
-- refactor/per-player-zones (main@f269629), scoped to these two income
-- sources only — Rideshare/Lottery/FreelanceGigHub stay on the shared global
-- Zone_x model pattern for now.
--
-- Slot assignment is session-based, not tied to a player's UserId across
-- sessions: plotOccupancy is reset every time a plot frees up, first-come-
-- first-served, same as before this pass. What's new is that a genuinely
-- NEW player (no prior save) now has to walk up and claim one of the 6
-- slots via a stand-on-pad marker in a shared lobby, instead of silently
-- landing in the first free one — a RETURNING player (has a prior save,
-- see EconomyService.LoadPlayer's isNewProfile) still gets auto-assigned to
-- any free slot and skipped straight in, exactly like before.
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local IncomeSourceService = require(script.Parent.IncomeSourceService)
local PurchasePad = require(ReplicatedStorage.Shared.Modules.PurchasePad)

local PlotService = {}

-- 6 plots in a row, matches the previous per-player attempt's slot count.
-- Players.MaxPlayers isn't scriptable at runtime, so it can't be kept in
-- sync with this list automatically - set it to 6 in Studio's Game Settings
-- (Players tab) by hand if you want Roblox's own matchmaking to also stop
-- routing new joins here once every plot is taken, on top of the in-game
-- "no free slot" -> teleport-away check below.
local PLOT_ORIGINS: { Vector3 } = {
	Vector3.new(-200, 0, -150),
	Vector3.new(-120, 0, -150),
	Vector3.new(-40, 0, -150),
	Vector3.new(40, 0, -150),
	Vector3.new(120, 0, -150),
	Vector3.new(200, 0, -150),
}

local LOBBY_ORIGIN = Vector3.new(0, 0, -80)

--------------------------------------------------------------------------------
-- ROUNDABOUT (per-plot road ring + sidewalks + streetlights + crosswalk +
-- entrance spur + central park). Pure static geometry, no gameplay logic —
-- called once per plot at build time, positions everything relative to the
-- plot's origin so the same numbers work regardless of which slot the player
-- claimed. Slot positions for houses/stations/kiosks are chosen by
-- IncomeSourceService to sit on the outer sidewalk of this ring.
--------------------------------------------------------------------------------

local ROAD_COLOR = Color3.fromRGB(50, 50, 55)
local SIDEWALK_COLOR = Color3.fromRGB(180, 178, 175)
local STRIPE_COLOR = Color3.fromRGB(240, 240, 240)
local POST_COLOR = Color3.fromRGB(140, 140, 145)
local LAMP_COLOR = Color3.fromRGB(255, 230, 160)
local GRASS_COLOR = Color3.fromRGB(90, 150, 80)
local TRUNK_COLOR = Color3.fromRGB(90, 60, 40)
local LEAF_COLOR = Color3.fromRGB(70, 140, 70)
local MONUMENT_COLOR = Color3.fromRGB(210, 205, 195)

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function buildStreetlight(parent: Instance, position: Vector3)
	local post = makePart(parent, "StreetlightPost", Vector3.new(0.4, 8, 0.4), position + Vector3.new(0, 4, 0), POST_COLOR, Enum.Material.Metal)

	local arm = makePart(parent, "StreetlightArm", Vector3.new(0.4, 0.4, 1.6), position + Vector3.new(0, 7.8, 0.8), POST_COLOR, Enum.Material.Metal)
	local _ = arm

	local lamp = makePart(parent, "StreetlightLamp", Vector3.new(1, 1, 1), position + Vector3.new(0, 7.5, 1.6), LAMP_COLOR, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball

	local light = Instance.new("PointLight")
	light.Color = LAMP_COLOR
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = lamp
end

local function buildTree(parent: Instance, position: Vector3)
	local trunk = makePart(parent, "TreeTrunk", Vector3.new(1, 5, 1), position + Vector3.new(0, 2.5, 0), TRUNK_COLOR, Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))

	for _, offset in ipairs({ Vector3.new(0, 5.5, 0), Vector3.new(-1.2, 5, 0.8), Vector3.new(1.2, 5, -0.8), Vector3.new(0.4, 5.8, -1.2) }) do
		local leaf = makePart(parent, "TreeLeaves", Vector3.new(3.2, 3.2, 3.2), position + offset, LEAF_COLOR, Enum.Material.LeafyGrass)
		leaf.Shape = Enum.PartType.Ball
	end
end

local function buildRoundabout(folder: Folder, origin: Vector3)
	local ring = Instance.new("Model")
	ring.Name = "Roundabout"
	ring.Parent = folder

	-- Road ring (4 straight strips forming a rectangle). North/south run full
	-- 46 wide including corners; east/west are 54 tall to avoid corner double-up.
	makePart(ring, "RoadN", Vector3.new(46, 0.2, 6), origin + Vector3.new(0, 0.1, 30), ROAD_COLOR, Enum.Material.Slate)
	makePart(ring, "RoadS", Vector3.new(46, 0.2, 6), origin + Vector3.new(0, 0.1, -30), ROAD_COLOR, Enum.Material.Slate)
	makePart(ring, "RoadE", Vector3.new(6, 0.2, 54), origin + Vector3.new(20, 0.1, 0), ROAD_COLOR, Enum.Material.Slate)
	makePart(ring, "RoadW", Vector3.new(6, 0.2, 54), origin + Vector3.new(-20, 0.1, 0), ROAD_COLOR, Enum.Material.Slate)

	-- Inner sidewalks (raised 0.1 above road for visible curb). Line the park.
	makePart(ring, "SidewalkN", Vector3.new(34, 0.3, 2), origin + Vector3.new(0, 0.25, 26), SIDEWALK_COLOR, Enum.Material.Concrete)
	makePart(ring, "SidewalkS", Vector3.new(34, 0.3, 2), origin + Vector3.new(0, 0.25, -26), SIDEWALK_COLOR, Enum.Material.Concrete)
	makePart(ring, "SidewalkE", Vector3.new(2, 0.3, 50), origin + Vector3.new(16, 0.25, 0), SIDEWALK_COLOR, Enum.Material.Concrete)
	makePart(ring, "SidewalkW", Vector3.new(2, 0.3, 50), origin + Vector3.new(-16, 0.25, 0), SIDEWALK_COLOR, Enum.Material.Concrete)

	-- Crosswalk across south road (aligned with entrance spur below).
	for i = 1, 5 do
		local stripeX = -2 + (i - 1) * 1
		makePart(ring, "CrosswalkStripe", Vector3.new(0.7, 0.05, 6), origin + Vector3.new(stripeX, 0.22, -30), STRIPE_COLOR, Enum.Material.SmoothPlastic)
	end

	-- Streetlights at inner corners.
	for _, corner in ipairs({ Vector3.new(-18, 0.3, -28), Vector3.new(18, 0.3, -28), Vector3.new(-18, 0.3, 28), Vector3.new(18, 0.3, 28) }) do
		buildStreetlight(ring, origin + corner)
	end

	-- Entrance spur south of the loop (cosmetic; player teleports directly
	-- into the park at origin).
	makePart(ring, "EntranceRoad", Vector3.new(6, 0.2, 18), origin + Vector3.new(0, 0.1, -42), ROAD_COLOR, Enum.Material.Slate)
	makePart(ring, "EntranceSidewalkE", Vector3.new(1, 0.3, 18), origin + Vector3.new(4, 0.25, -42), SIDEWALK_COLOR, Enum.Material.Concrete)
	makePart(ring, "EntranceSidewalkW", Vector3.new(1, 0.3, 18), origin + Vector3.new(-4, 0.25, -42), SIDEWALK_COLOR, Enum.Material.Concrete)

	-- Central park (grass floor + monument + 4 corner trees).
	makePart(ring, "ParkGrass", Vector3.new(30, 0.2, 50), origin + Vector3.new(0, 0.1, 0), GRASS_COLOR, Enum.Material.Grass)

	local pedestal = makePart(ring, "MonumentBase", Vector3.new(3, 1, 3), origin + Vector3.new(0, 0.7, 0), MONUMENT_COLOR, Enum.Material.Concrete)
	local _ = pedestal
	local orb = makePart(ring, "MonumentOrb", Vector3.new(2, 2, 2), origin + Vector3.new(0, 2.5, 0), LAMP_COLOR, Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	local orbLight = Instance.new("PointLight")
	orbLight.Color = LAMP_COLOR
	orbLight.Range = 14
	orbLight.Brightness = 1.6
	orbLight.Parent = orb

	for _, corner in ipairs({ Vector3.new(-12, 0, -22), Vector3.new(12, 0, -22), Vector3.new(-12, 0, 22), Vector3.new(12, 0, 22) }) do
		buildTree(ring, origin + corner)
	end
end

type PlotState = {
	plotIndex: number,
	origin: Vector3,
	folder: Folder,
	characterConn: RBXScriptConnection?,
}

type PlotMarker = {
	model: Model,
	statusLabel: TextLabel,
	pad: BasePart?,
	padConnection: RBXScriptConnection?,
}

local plotOccupancy: { [number]: Player? } = {}
local playerPlots: { [Player]: PlotState } = {}
local plotMarkers: { [number]: PlotMarker } = {}
-- New players sitting in the lobby with no plot claimed yet. Swept whenever
-- the last free slot is taken by someone else, so nobody is ever left
-- standing in front of an all-"Taken" lobby with no path forward.
local waitingPlayers: { [Player]: boolean } = {}

local function teleportToPlot(character: Model, origin: Vector3)
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = CFrame.new(origin + Vector3.new(0, 5, 0))
	end
end

-- Sends a player through matchmaking for this same place again rather than
-- leaving them waiting - Roblox routes them to a different server instance
-- once this one reports itself full. Only meaningfully testable once
-- published with multiple live server instances - Studio Play is a single
-- isolated session, so this path can't be exercised there.
local function sendToAnotherServer(player: Player)
	local ok, err = pcall(function()
		TeleportService:Teleport(game.PlaceId, player)
	end)
	if not ok then
		warn("[PlotService] Failed to route " .. player.Name .. " to another server: " .. tostring(err))
	end
end

function PlotService.HasFreeSlot(): boolean
	for i = 1, #PLOT_ORIGINS do
		if plotOccupancy[i] == nil then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- LOBBY + PLOT MARKERS (sign + claim pad, shown before a slot is claimed)
--------------------------------------------------------------------------------

local function setMarkerStatus(marker: PlotMarker, text: string, color: Color3)
	marker.statusLabel.Text = text
	marker.statusLabel.TextColor3 = color
end

-- Adds (or replaces) the claim pad on an existing marker - split out from
-- buildMarker so ReleasePlot can put a fresh pad back once a slot frees up
-- without rebuilding the sign that was showing "Taken by X".
local function attachMarkerPad(marker: PlotMarker, slot: number, origin: Vector3)
	local pad = PurchasePad.Build(marker.model, origin + Vector3.new(0, 0.5, 0), Theme.CashPositive, 5)
	marker.pad = pad
	marker.padConnection = PurchasePad.Wire(pad, function(p)
		return waitingPlayers[p] == true
	end, function(p)
		return PlotService.ClaimSlot(p, slot)
	end, true)
	setMarkerStatus(marker, "Available", Theme.CashPositive)
end

local function buildMarker(slot: number, origin: Vector3): PlotMarker
	local model = Instance.new("Model")
	model.Name = "PlotMarker_" .. slot
	model.Parent = workspace

	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(1, 1, 1)
	sign.Transparency = 1
	sign.Position = origin + Vector3.new(0, 12, 0)
	sign.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "PlotSign"
	gui.Adornee = sign
	gui.Size = UDim2.new(0, 240, 0, 90)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150
	gui.Parent = sign

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	titleLabel.TextStrokeTransparency = 0.3
	titleLabel.Text = "Plot " .. slot
	titleLabel.Parent = gui

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromScale(0, 0.5)
	statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	statusLabel.TextStrokeTransparency = 0.3
	statusLabel.Parent = gui

	local marker: PlotMarker = { model = model, statusLabel = statusLabel, pad = nil, padConnection = nil }
	attachMarkerPad(marker, slot, origin)

	return marker
end

--------------------------------------------------------------------------------
-- CLAIM / ASSIGN
--------------------------------------------------------------------------------

local function buildPlotForPlayer(player: Player, slot: number)
	local marker = plotMarkers[slot]
	if marker then
		-- Drop just the claim pad - the sign stays up, now showing "Taken by
		-- X" (set by ClaimSlot below), so other players browsing the lobby
		-- still see this slot is spoken for.
		if marker.padConnection then
			marker.padConnection:Disconnect()
			marker.padConnection = nil
		end
		if marker.pad then
			marker.pad:Destroy()
			marker.pad = nil
		end
	end

	local origin = PLOT_ORIGINS[slot]
	local folder = Instance.new("Folder")
	folder.Name = "Neighborhood_" .. player.UserId
	folder.Parent = workspace

	local plot: PlotState = {
		plotIndex = slot,
		origin = origin,
		folder = folder,
		characterConn = nil,
	}
	playerPlots[player] = plot

	buildRoundabout(folder, origin)
	IncomeSourceService.SetupPlayerDogWalking(player, folder, origin)
	IncomeSourceService.SetupPlayerDoorDash(player, folder, origin)
	IncomeSourceService.SetupPlayerNeighborhoodUpgrade(player, folder, origin)

	if player.Character then
		task.spawn(teleportToPlot, player.Character, origin)
	end
	plot.characterConn = player.CharacterAdded:Connect(function(char)
		task.spawn(teleportToPlot, char, origin)
	end)
end

-- Server-authoritative, race-condition-safe: the free-slot check and the
-- occupancy write below happen with no yield in between, so two players
-- touching the same pad in the same tick can't both win - Luau's
-- cooperative scheduler runs one Touched handler to completion before the
-- next starts. Whichever gets here first claims it; the other's attempt
-- just returns false and the pad's fail-flash plays (the plot has already
-- flipped to "Taken" for them to see why).
function PlotService.ClaimSlot(player: Player, slot: number): boolean
	if plotOccupancy[slot] ~= nil then
		return false
	end
	if playerPlots[player] then
		return false -- already has a plot, can't also claim another
	end
	plotOccupancy[slot] = player
	waitingPlayers[player] = nil

	buildPlotForPlayer(player, slot)

	local marker = plotMarkers[slot]
	if marker then
		setMarkerStatus(marker, "Taken by " .. player.Name, Theme.Warning)
	end

	if not PlotService.HasFreeSlot() then
		for waitingPlayer in pairs(waitingPlayers) do
			sendToAnotherServer(waitingPlayer)
		end
	end

	return true
end

-- Returning players (has a prior save) skip the lobby entirely - assigned
-- whichever slot is free and teleported straight in, same as before this
-- pass added the lobby for new players.
function PlotService.AssignFirstFreeSlot(player: Player): boolean
	for i = 1, #PLOT_ORIGINS do
		if plotOccupancy[i] == nil then
			return PlotService.ClaimSlot(player, i)
		end
	end
	return false
end

function PlotService.RegisterWaitingPlayer(player: Player)
	waitingPlayers[player] = true
end

function PlotService.UnregisterWaitingPlayer(player: Player)
	waitingPlayers[player] = nil
end

function PlotService.SendToAnotherServer(player: Player)
	sendToAnotherServer(player)
end

function PlotService.ReleasePlot(player: Player)
	waitingPlayers[player] = nil
	local plot = playerPlots[player]
	if not plot then
		return
	end
	if plot.characterConn then
		plot.characterConn:Disconnect()
	end
	IncomeSourceService.CleanupPlayerDoorDash(player)
	IncomeSourceService.CleanupPlayerDogWalking(player)
	plotOccupancy[plot.plotIndex] = nil
	plot.folder:Destroy()
	playerPlots[player] = nil

	local marker = plotMarkers[plot.plotIndex]
	if marker then
		attachMarkerPad(marker, plot.plotIndex, plot.origin)
	end
end

--------------------------------------------------------------------------------
-- LOBBY (minimal: platform + title sign + the 6 plot markers built above)
--------------------------------------------------------------------------------

local function buildLobby()
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = workspace

	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Anchored = true
	platform.Size = Vector3.new(60, 1, 40)
	platform.Position = LOBBY_ORIGIN
	platform.Color = Theme.Locked
	platform.Material = Enum.Material.SmoothPlastic
	platform.Parent = lobby

	local sign = Instance.new("Part")
	sign.Name = "TitleSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(1, 1, 1)
	sign.Transparency = 1
	sign.Position = LOBBY_ORIGIN + Vector3.new(0, 14, 0)
	sign.Parent = lobby

	local gui = Instance.new("BillboardGui")
	gui.Name = "TitleGui"
	gui.Adornee = sign
	gui.Size = UDim2.new(0, 400, 0, 80)
	gui.AlwaysOnTop = true
	gui.Parent = sign

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 1)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Theme.Brand
	titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.Text = "PLANET HUSTLE\nChoose Your Plot"
	titleLabel.Parent = gui

	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.Position = LOBBY_ORIGIN + Vector3.new(0, 1, 15)
	end
end

function PlotService.Init()
	buildLobby()
	for i, origin in ipairs(PLOT_ORIGINS) do
		plotMarkers[i] = buildMarker(i, origin)
	end
end

return PlotService
