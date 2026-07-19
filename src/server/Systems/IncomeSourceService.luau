-- Manages the 5 Planet Hustle income sources and the player's live income/sec
-- stat. DoorDash (Step 4) is always unlocked; Rideshare / Dog Walking /
-- Freelance Gig Hub (Step 6) are activated by ZoneService on zone purchase;
-- Lottery (Step 7) lives in LotteryService but uses the same station pattern.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local EconomyService = require(script.Parent.EconomyService)
local FloatingText = require(ReplicatedStorage.Shared.Modules.FloatingText)

local DOOR_DASH_HOUSE_COUNT = 4
local DOOR_DASH_HOUSE_SPACING = 20
local FLASH_COLOR = Theme.CashPositive

-- Toolbox asset picked by name/thumbnail match — "Pizza Delivery Bike Vehicle
-- Moped Scooter RP" by Charlott3Blad378, free. Screenshot-verified in Studio
-- before wiring in: red cartoon moped w/ built-in delivery box on the rack,
-- which covers the "oversized insulated bag stack" from the visual spec —
-- no separate stack prop needed on top of it.
local DOOR_DASH_MOPED_ASSET_ID = 74198464525165

local DOOR_DASH_HOUSE_COLORS = {
	Color3.fromRGB(235, 149, 50), -- warm orange
	Color3.fromRGB(90, 170, 220), -- sky blue
	Color3.fromRGB(200, 90, 120), -- rose
	Color3.fromRGB(120, 180, 100), -- sage green
}
local ROOF_COLOR = Color3.fromRGB(70, 55, 50)
local DOOR_COLOR = Color3.fromRGB(50, 40, 38)
local MAT_COLOR = Color3.fromRGB(160, 110, 70)
local HEDGE_COLOR = Color3.fromRGB(60, 120, 60)
local MAILBOX_COLOR = Color3.fromRGB(200, 200, 205)
local PORCH_LIGHT_COLOR = Color3.fromRGB(255, 220, 140)

-- Toolbox asset picked by name match, screenshot-verified in Studio before
-- wiring in: "Unturned Taxi #" by jswdjfhfk, free — a boxy low-poly yellow
-- taxi with big rounded wheels and an existing rooftop sign mount, which
-- fits the "blocky compact car" hero from the visual spec well. Front of
-- the model is local +Z (confirmed via bounding-box introspection: the
-- bumper/wedge cluster sits at the most-positive-Z parts).
local RIDESHARE_TAXI_ASSET_ID = 8517749330
local RIDESHARE_BEACON_COLOR = Theme.Brand

local DOG_WALKING_COLOR = Color3.fromRGB(180, 140, 90)

local IncomeSourceService = {}

-- cd[player][station] = os.clock() expiry
local doorDashCooldowns: { [Player]: { [BasePart]: number } } = {}
local rideshareCooldowns: { [Player]: { [BasePart]: number } } = {}
local dogWalkingCooldowns: { [Player]: { [BasePart]: number } } = {}

-- freelanceActive[player] = true while the passive tick loop should keep firing
local freelanceActive: { [Player]: boolean } = {}

local function getStatsFolder(player: Player): Folder?
	return player:FindFirstChild("PlanetHustleStats")
end

-- Moves every part of `model` so its bounding-box center lands at
-- `targetCenter`, rotation preserved. Deliberately bypasses Model:PivotTo /
-- GetPivot, which follow PrimaryPart — marketplace assets often leave that
-- unset or pointing at an arbitrary part, not the geometric center, which
-- silently offsets any position math built on top of it.
local function recenterModel(model: Model, targetCenter: CFrame)
	local boundingCFrame = (model:GetBoundingBox())
	local delta = targetCenter * boundingCFrame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
		end
	end
end

local function pulseStation(station: BasePart)
	local original = station.Color
	local up = TweenService:Create(station, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { Color = FLASH_COLOR })
	up:Play()
	up.Completed:Wait()
	TweenService:Create(station, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Color = original }):Play()
end

local function checkCooldown(cd: { [Player]: { [BasePart]: number } }, player: Player, station: BasePart, cooldown: number): boolean
	local now = os.clock()
	local playerCd = cd[player]
	if playerCd and playerCd[station] and now < playerCd[station] then
		return false
	end
	cd[player] = cd[player] or {}
	cd[player][station] = now + cooldown
	return true
end

local function payReward(player: Player, station: BasePart, reward: number)
	EconomyService.AddCash(player, reward)
	task.spawn(pulseStation, station)
	FloatingText.Show(station, "+$" .. reward, Theme.CashPositive)
end

--------------------------------------------------------------------------------
-- LIFECYCLE / STAT PLUMBING
--------------------------------------------------------------------------------

-- Peaked roof (two wedges), inset door, porch light, welcome mat, mailbox
-- w/ flag, and low hedges flanking the entrance — the "suburban delivery
-- stop" details from the visual spec, all primitives.
local function buildHouseDetails(house: BasePart, folder: Instance)
	local size = house.Size
	local cf = house.CFrame

	local wedgeA = Instance.new("WedgePart")
	wedgeA.Name = "RoofA"
	wedgeA.Anchored = true
	wedgeA.CanCollide = false
	wedgeA.Material = Enum.Material.Slate
	wedgeA.Color = ROOF_COLOR
	wedgeA.Size = Vector3.new(size.X, size.Y * 0.5, size.Z / 2)
	wedgeA.CFrame = cf * CFrame.new(0, size.Y * 0.75, size.Z / 4) * CFrame.Angles(0, math.rad(180), 0)
	wedgeA.Parent = folder

	local wedgeB = wedgeA:Clone()
	wedgeB.Name = "RoofB"
	wedgeB.CFrame = cf * CFrame.new(0, size.Y * 0.75, -size.Z / 4)
	wedgeB.Parent = folder

	local door = Instance.new("Part")
	door.Name = "Door"
	door.Anchored = true
	door.CanCollide = false
	door.Material = Enum.Material.SmoothPlastic
	door.Color = DOOR_COLOR
	door.Size = Vector3.new(size.X * 0.28, size.Y * 0.55, 0.2)
	door.CFrame = cf * CFrame.new(0, -size.Y * 0.18, size.Z / 2 + 0.1)
	door.Parent = folder

	local porchLight = Instance.new("Part")
	porchLight.Name = "PorchLight"
	porchLight.Shape = Enum.PartType.Ball
	porchLight.Anchored = true
	porchLight.CanCollide = false
	porchLight.Material = Enum.Material.Neon
	porchLight.Color = PORCH_LIGHT_COLOR
	porchLight.Size = Vector3.new(0.8, 0.8, 0.8)
	porchLight.CFrame = cf * CFrame.new(size.X * 0.28, 0, size.Z / 2 + 0.3)
	porchLight.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = PORCH_LIGHT_COLOR
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = porchLight

	local mat = Instance.new("Part")
	mat.Name = "Mat"
	mat.Anchored = true
	mat.CanCollide = false
	mat.Material = Enum.Material.Fabric
	mat.Color = MAT_COLOR
	mat.Size = Vector3.new(size.X * 0.35, 0.15, 1.6)
	mat.CFrame = cf * CFrame.new(0, -size.Y / 2 + 0.1, size.Z / 2 + 1.2)
	mat.Parent = folder

	local post = Instance.new("Part")
	post.Name = "MailboxPost"
	post.Anchored = true
	post.CanCollide = false
	post.Material = Enum.Material.Wood
	post.Color = Color3.fromRGB(90, 65, 45)
	post.Size = Vector3.new(0.4, 3.2, 0.4)
	post.CFrame = cf * CFrame.new(size.X / 2 + 1.5, -size.Y / 2 + 1.6, size.Z / 2 + 2.5)
	post.Parent = folder

	local box = Instance.new("Part")
	box.Name = "MailboxBox"
	box.Anchored = true
	box.CanCollide = false
	box.Material = Enum.Material.Metal
	box.Color = MAILBOX_COLOR
	box.Size = Vector3.new(0.8, 0.6, 1.4)
	box.CFrame = post.CFrame * CFrame.new(0, 1.7, 0)
	box.Parent = folder

	local flag = Instance.new("Part")
	flag.Name = "MailboxFlag"
	flag.Anchored = true
	flag.CanCollide = false
	flag.Material = Enum.Material.Metal
	flag.Color = Color3.fromRGB(200, 50, 50)
	flag.Size = Vector3.new(0.1, 0.5, 0.15)
	flag.CFrame = box.CFrame * CFrame.new(0.5, 0, 0.6) * CFrame.Angles(0, 0, math.rad(60))
	flag.Parent = folder

	for _, side in ipairs({ -1, 1 }) do
		local hedge = Instance.new("Part")
		hedge.Name = "Hedge"
		hedge.Shape = Enum.PartType.Ball
		hedge.Anchored = true
		hedge.CanCollide = false
		hedge.Material = Enum.Material.Grass
		hedge.Color = HEDGE_COLOR
		hedge.Size = Vector3.new(1.6, 1.2, 1.6)
		hedge.CFrame = cf * CFrame.new(side * size.X * 0.42, -size.Y / 2 + 0.6, size.Z / 2 + 0.6)
		hedge.Parent = folder
	end
end

-- One dropped soda cup for asymmetry/charm — not every house, just one.
local function buildDroppedCup(house: BasePart, folder: Instance)
	local cup = Instance.new("Part")
	cup.Name = "DroppedCup"
	cup.Shape = Enum.PartType.Cylinder
	cup.Anchored = true
	cup.CanCollide = false
	cup.Material = Enum.Material.SmoothPlastic
	cup.Color = Color3.fromRGB(230, 230, 235)
	cup.Size = Vector3.new(0.9, 0.5, 0.5)
	cup.CFrame = house.CFrame
		* CFrame.new(-2, -house.Size.Y / 2 + 0.25, house.Size.Z / 2 + 3)
		* CFrame.Angles(0, 0, math.rad(90))
	cup.Parent = folder
end

-- Warm string lights sagging between adjacent houses (Beam w/ negative
-- CurveSize reads as a hanging cable, no extra parts needed).
local function buildStringLights(folder: Instance, houses: { BasePart })
	for i = 1, #houses - 1 do
		local a, b = houses[i], houses[i + 1]
		local attA = Instance.new("Attachment")
		attA.Position = Vector3.new(0, a.Size.Y / 2 + 0.2, 0)
		attA.Parent = a
		local attB = Instance.new("Attachment")
		attB.Position = Vector3.new(0, b.Size.Y / 2 + 0.2, 0)
		attB.Parent = b

		local beam = Instance.new("Beam")
		beam.Attachment0 = attA
		beam.Attachment1 = attB
		beam.Width0 = 0.15
		beam.Width1 = 0.15
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 225, 150))
		beam.FaceCamera = true
		beam.Segments = 8
		beam.CurveSize0 = -2
		beam.CurveSize1 = -2
		beam.Parent = a
	end
end

-- The DoorDash "hero": one parked moped with a floating map-ping bubble,
-- centered in front of the house row. Loaded via InsertService so it's
-- code-driven (Rojo-sync-reproducible) rather than a one-off Studio edit.
local function buildMopedHero(folder: Instance, position: Vector3)
	local ok, container = pcall(function()
		return InsertService:LoadAsset(DOOR_DASH_MOPED_ASSET_ID)
	end)
	if not ok or not container then
		warn("[IncomeSourceService] Failed to load DoorDash moped asset: " .. tostring(container))
		return
	end

	local moped = container:FindFirstChildOfClass("Model")
	if not moped then
		container:Destroy()
		return
	end
	moped.Name = "MopedHero"
	moped.Parent = folder
	container:Destroy()

	for _, part in ipairs(moped:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local _, size = moped:GetBoundingBox()
	recenterModel(moped, CFrame.new(position + Vector3.new(0, size.Y / 2, 0)))

	local pingAnchor = Instance.new("Part")
	pingAnchor.Name = "MapPingAnchor"
	pingAnchor.Anchored = true
	pingAnchor.CanCollide = false
	pingAnchor.Transparency = 1
	pingAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	pingAnchor.Position = position + Vector3.new(0, size.Y + 3, 0)
	pingAnchor.Parent = folder

	local gui = Instance.new("BillboardGui")
	gui.Name = "MapPing"
	gui.Adornee = pingAnchor
	gui.Size = UDim2.new(0, 60, 0, 60)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = pingAnchor

	local pin = Instance.new("TextLabel")
	pin.BackgroundTransparency = 1
	pin.Size = UDim2.fromScale(1, 1)
	pin.Font = Enum.Font.GothamBold
	pin.TextScaled = true
	pin.Text = "📍"
	pin.TextColor3 = Theme.Brand
	pin.Parent = gui

	-- Gentle infinite bob — one Play() call, no loop needed.
	TweenService:Create(
		pingAnchor,
		TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = pingAnchor.Position + Vector3.new(0, 1, 0) }
	):Play()
end

-- Curbside details around the Rideshare taxi: PICKUP sign, passenger bench,
-- traffic cone, hanging air freshener, ★★★★★ rating billboard — one per
-- corner of the zone footprint so nothing overlaps the parked taxi.
local function buildRideshareCurbDetails(zoneModel: Model, floor: BasePart, taxi: Model)
	-- PICKUP sign (physical signboard, SurfaceGui text — doesn't face-camera
	-- like a BillboardGui would, since it's meant to read as a real sign).
	local signPost = Instance.new("Part")
	signPost.Name = "PickupSignPost"
	signPost.Anchored = true
	signPost.CanCollide = false
	signPost.Material = Enum.Material.Metal
	signPost.Color = Color3.fromRGB(150, 150, 155)
	signPost.Size = Vector3.new(0.3, 4, 0.3)
	signPost.CFrame = CFrame.new(floor.Position + Vector3.new(-5, 2, -5))
	signPost.Parent = zoneModel

	local signBoard = Instance.new("Part")
	signBoard.Name = "PickupSignBoard"
	signBoard.Anchored = true
	signBoard.CanCollide = false
	signBoard.Material = Enum.Material.SmoothPlastic
	signBoard.Color = Theme.Brand
	signBoard.Size = Vector3.new(3, 1.2, 0.2)
	signBoard.CFrame = signPost.CFrame * CFrame.new(0, 2, 0)
	signBoard.Parent = zoneModel

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = signBoard
	local signLabel = Instance.new("TextLabel")
	signLabel.BackgroundTransparency = 1
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signLabel.Text = "PICKUP"
	signLabel.Parent = signGui

	-- Passenger bench
	local benchSeat = Instance.new("Part")
	benchSeat.Name = "BenchSeat"
	benchSeat.Anchored = true
	benchSeat.CanCollide = true
	benchSeat.Material = Enum.Material.Wood
	benchSeat.Color = Color3.fromRGB(120, 85, 60)
	benchSeat.Size = Vector3.new(4, 0.4, 1.4)
	benchSeat.CFrame = CFrame.new(floor.Position + Vector3.new(5, 1, -5))
	benchSeat.Parent = zoneModel

	local benchBack = Instance.new("Part")
	benchBack.Name = "BenchBack"
	benchBack.Anchored = true
	benchBack.CanCollide = false
	benchBack.Material = Enum.Material.Wood
	benchBack.Color = benchSeat.Color
	benchBack.Size = Vector3.new(4, 1.2, 0.3)
	benchBack.CFrame = benchSeat.CFrame * CFrame.new(0, 0.8, -0.6)
	benchBack.Parent = zoneModel

	-- Traffic cone (two stacked cylinders — simple, no Cone PartType in Roblox)
	local coneBase = Instance.new("Part")
	coneBase.Name = "ConeBase"
	coneBase.Shape = Enum.PartType.Cylinder
	coneBase.Anchored = true
	coneBase.CanCollide = false
	coneBase.Material = Enum.Material.SmoothPlastic
	coneBase.Color = Color3.fromRGB(255, 120, 30)
	coneBase.Size = Vector3.new(0.3, 1.6, 1.6)
	coneBase.CFrame = CFrame.new(floor.Position + Vector3.new(-5, 0.5, 5)) * CFrame.Angles(0, 0, math.rad(90))
	coneBase.Parent = zoneModel

	local coneTop = Instance.new("Part")
	coneTop.Name = "ConeTop"
	coneTop.Shape = Enum.PartType.Cylinder
	coneTop.Anchored = true
	coneTop.CanCollide = false
	coneTop.Material = Enum.Material.SmoothPlastic
	coneTop.Color = coneBase.Color
	coneTop.Size = Vector3.new(1.2, 0.9, 0.9)
	coneTop.CFrame = coneBase.CFrame * CFrame.new(0.6, 0, 0)
	coneTop.Parent = zoneModel

	-- ★★★★★ rating billboard
	local ratingPost = Instance.new("Part")
	ratingPost.Name = "RatingPost"
	ratingPost.Anchored = true
	ratingPost.CanCollide = false
	ratingPost.Material = Enum.Material.Metal
	ratingPost.Color = Color3.fromRGB(150, 150, 155)
	ratingPost.Size = Vector3.new(0.3, 5, 0.3)
	ratingPost.CFrame = CFrame.new(floor.Position + Vector3.new(5, 2.5, 5))
	ratingPost.Parent = zoneModel

	local ratingGui = Instance.new("BillboardGui")
	ratingGui.Name = "RatingBillboard"
	ratingGui.Adornee = ratingPost
	ratingGui.Size = UDim2.new(0, 150, 0, 40)
	ratingGui.StudsOffset = Vector3.new(0, 3, 0)
	ratingGui.AlwaysOnTop = true
	ratingGui.MaxDistance = 80
	ratingGui.Parent = ratingPost
	local ratingLabel = Instance.new("TextLabel")
	ratingLabel.BackgroundTransparency = 1
	ratingLabel.Size = UDim2.fromScale(1, 1)
	ratingLabel.Font = Enum.Font.GothamBold
	ratingLabel.TextScaled = true
	ratingLabel.TextColor3 = Theme.Gold
	ratingLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	ratingLabel.TextStrokeTransparency = 0.4
	ratingLabel.Text = "★★★★★"
	ratingLabel.Parent = ratingGui

	-- Hanging air freshener off the taxi's beacon mount, gently swaying
	local beacon = taxi:FindFirstChild("Beacon")
	if beacon then
		local freshenerAnchor = Instance.new("Part")
		freshenerAnchor.Name = "AirFreshenerAnchor"
		freshenerAnchor.Anchored = true
		freshenerAnchor.CanCollide = false
		freshenerAnchor.Transparency = 1
		freshenerAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
		freshenerAnchor.CFrame = (beacon :: BasePart).CFrame * CFrame.new(0, -1.5, 0)
		freshenerAnchor.Parent = zoneModel

		local gui = Instance.new("BillboardGui")
		gui.Name = "AirFreshener"
		gui.Adornee = freshenerAnchor
		gui.Size = UDim2.new(0, 40, 0, 40)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 60
		gui.Parent = freshenerAnchor
		local tree = Instance.new("TextLabel")
		tree.BackgroundTransparency = 1
		tree.Size = UDim2.fromScale(1, 1)
		tree.Font = Enum.Font.GothamBold
		tree.TextScaled = true
		tree.Text = "🌲"
		tree.TextColor3 = Color3.fromRGB(80, 180, 90)
		tree.Parent = gui

		TweenService:Create(
			freshenerAnchor,
			TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = freshenerAnchor.CFrame * CFrame.Angles(0, 0, math.rad(12)) }
		):Play()
	end
end

-- The Rideshare "hero": the taxi itself (not a separate placeholder block).
-- Googly eyes near the front bumper (front = local +Z, see asset note above)
-- and a glowing rooftop beacon are added directly to the loaded model.
-- Offsets are computed from the taxi's actual bounding size so a future
-- asset swap doesn't silently break placement.
function IncomeSourceService.BuildRideshareHero(zoneModel: Model, floor: BasePart): Model | BasePart
	local ok, container = pcall(function()
		return InsertService:LoadAsset(RIDESHARE_TAXI_ASSET_ID)
	end)
	local taxi = ok and container and container:FindFirstChildOfClass("Model")
	if container then
		if taxi then
			taxi.Parent = nil
		end
		container:Destroy()
	end

	if not taxi then
		warn("[IncomeSourceService] Failed to load Rideshare taxi asset, falling back to placeholder block")
		local fallback = Instance.new("Part")
		fallback.Name = "Hero"
		fallback.Anchored = true
		fallback.CanCollide = true
		fallback.Material = Enum.Material.Neon
		fallback.Color = Color3.fromRGB(220, 90, 90)
		fallback.Size = Vector3.new(6, 3, 10)
		fallback.Position = floor.Position + Vector3.new(0, 3, 0)
		fallback.Parent = zoneModel
		return fallback
	end

	taxi.Name = "Hero"
	taxi.Parent = zoneModel
	for _, part in ipairs(taxi:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local _, boundingSize = taxi:GetBoundingBox()
	local pivot = CFrame.new(floor.Position + Vector3.new(0, boundingSize.Y / 2, 0))
	recenterModel(taxi, pivot)

	local frontZ = boundingSize.Z / 2 - 0.4
	local eyeY = -boundingSize.Y * 0.1

	for _, side in ipairs({ -1, 1 }) do
		local eyeWhite = Instance.new("Part")
		eyeWhite.Name = "GooglyEyeWhite"
		eyeWhite.Shape = Enum.PartType.Ball
		eyeWhite.Anchored = true
		eyeWhite.CanCollide = false
		eyeWhite.Material = Enum.Material.SmoothPlastic
		eyeWhite.Color = Color3.fromRGB(255, 255, 255)
		eyeWhite.Size = Vector3.new(1, 1, 1)
		eyeWhite.CFrame = pivot * CFrame.new(side * boundingSize.X * 0.25, eyeY, frontZ)
		eyeWhite.Parent = taxi

		local pupil = Instance.new("Part")
		pupil.Name = "GooglyEyePupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Anchored = true
		pupil.CanCollide = false
		pupil.Material = Enum.Material.SmoothPlastic
		pupil.Color = Color3.fromRGB(20, 20, 20)
		pupil.Size = Vector3.new(0.45, 0.45, 0.45)
		pupil.CFrame = eyeWhite.CFrame * CFrame.new(side * 0.15, 0.1, 0.4)
		pupil.Parent = taxi
	end

	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = RIDESHARE_BEACON_COLOR
	beacon.Size = Vector3.new(boundingSize.X * 0.3, 1, boundingSize.Z * 0.2)
	beacon.CFrame = pivot * CFrame.new(0, boundingSize.Y / 2 + 0.5, 0)
	beacon.Parent = taxi
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = RIDESHARE_BEACON_COLOR
	beaconLight.Range = 14
	beaconLight.Brightness = 2
	beaconLight.Parent = beacon
	TweenService:Create(
		beacon,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.4 }
	):Play()

	buildRideshareCurbDetails(zoneModel, floor, taxi)

	-- Set only now (after all positioning above) — ActivateRideshare uses
	-- this to find a part to hang the ProximityPrompt on. Setting it earlier
	-- would make PivotTo/GetPivot follow this arbitrary part instead of the
	-- model's true geometric center, which is exactly the bug this function
	-- had to work around above.
	taxi.PrimaryPart = taxi:FindFirstChildWhichIsA("BasePart")

	return taxi
end

local function spawnDoorDashHouses(): Folder
	local existing = workspace:FindFirstChild("DoorDashHouses")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DoorDashHouses"
	folder.Parent = workspace

	local startX = -((DOOR_DASH_HOUSE_COUNT - 1) * DOOR_DASH_HOUSE_SPACING) / 2
	local houseParts = {}
	for i = 1, DOOR_DASH_HOUSE_COUNT do
		local house = Instance.new("Part")
		house.Name = "DoorDashHouse_" .. i
		house.Size = Vector3.new(8, 8, 8)
		house.Anchored = true
		house.Position = Vector3.new(startX + (i - 1) * DOOR_DASH_HOUSE_SPACING, 4, -30)
		house.Color = DOOR_DASH_HOUSE_COLORS[((i - 1) % #DOOR_DASH_HOUSE_COLORS) + 1]
		house.Material = Enum.Material.Wood
		house.Parent = folder

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Deliver"
		prompt.ObjectText = "House " .. i
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = house

		prompt.Triggered:Connect(function(player)
			IncomeSourceService.HandleDoorDashDelivery(player, house)
		end)

		buildHouseDetails(house, folder)
		table.insert(houseParts, house)
	end

	buildDroppedCup(houseParts[2], folder)
	buildStringLights(folder, houseParts)
	buildMopedHero(folder, Vector3.new(0, 0, -22))

	return folder
end

function IncomeSourceService.Init()
	spawnDoorDashHouses()
	Players.PlayerRemoving:Connect(function(player)
		doorDashCooldowns[player] = nil
		rideshareCooldowns[player] = nil
		dogWalkingCooldowns[player] = nil
		IncomeSourceService.DeactivateFreelanceHub(player)
	end)
end

function IncomeSourceService.SetupPlayer(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "PlanetHustleStats"
	stats.Parent = player

	local incomePerSecond = Instance.new("NumberValue")
	incomePerSecond.Name = "IncomePerSecond"
	incomePerSecond.Value = 0
	incomePerSecond.Parent = stats
end

function IncomeSourceService.GetIncomePerSecond(player: Player): number
	local stats = getStatsFolder(player)
	local value = stats and stats:FindFirstChild("IncomePerSecond")
	return value and value.Value or 0
end

function IncomeSourceService.AddIncomePerSecond(player: Player, delta: number)
	local stats = getStatsFolder(player)
	local value = stats and stats:FindFirstChild("IncomePerSecond")
	if value then
		value.Value += delta
	end
end

--------------------------------------------------------------------------------
-- DOOR DASH
--------------------------------------------------------------------------------

function IncomeSourceService.HandleDoorDashDelivery(player: Player, house: BasePart): number?
	if not checkCooldown(doorDashCooldowns, player, house, Config.DoorDash.cooldown) then
		return nil
	end
	local reward = math.random(Config.DoorDash.minReward, Config.DoorDash.maxReward)
	payReward(player, house, reward)
	return reward
end

--------------------------------------------------------------------------------
-- RIDESHARE
--------------------------------------------------------------------------------

-- The taxi itself is the "Hero" (built by BuildRideshareHero on zone
-- purchase); this just attaches the interactive prompt to it rather than
-- spawning a second, separate car block.
function IncomeSourceService.ActivateRideshare(zoneFloor: BasePart)
	local zoneModel = zoneFloor.Parent
	if not zoneModel then
		return
	end
	local hero = zoneModel:FindFirstChild("Hero")
	if not hero or hero:FindFirstChild("DriveTrigger", true) then
		return
	end

	local triggerPart = (hero:IsA("Model") and (hero :: Model).PrimaryPart) or (hero:IsA("BasePart") and hero) or nil
	if not triggerPart then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DriveTrigger"
	prompt.ActionText = "Drive"
	prompt.ObjectText = "Rideshare (+$" .. Config.Rideshare.rewardPerLoop .. ")"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = triggerPart

	prompt.Triggered:Connect(function(player)
		if not checkCooldown(rideshareCooldowns, player, triggerPart :: BasePart, Config.Rideshare.cooldown) then
			return
		end
		payReward(player, triggerPart :: BasePart, Config.Rideshare.rewardPerLoop)
	end)
end

--------------------------------------------------------------------------------
-- DOG WALKING
--------------------------------------------------------------------------------

function IncomeSourceService.ActivateDogWalking(zoneFloor: BasePart)
	local zoneModel = zoneFloor.Parent
	if not zoneModel or zoneModel:FindFirstChild("DogWalkingDog") then
		return
	end

	local dog = Instance.new("Part")
	dog.Name = "DogWalkingDog"
	dog.Anchored = true
	dog.CanCollide = true
	dog.Size = Vector3.new(4, 4, 4)
	dog.Color = DOG_WALKING_COLOR
	dog.Material = Enum.Material.SmoothPlastic
	dog.Position = zoneFloor.Position + Vector3.new(0, 2.5, 0)
	dog.Parent = zoneModel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Walk"
	prompt.ObjectText = "Dog (+$" .. Config.DogWalking.rewardPerLoop .. ")"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = dog

	prompt.Triggered:Connect(function(player)
		if not checkCooldown(dogWalkingCooldowns, player, dog, Config.DogWalking.cooldown) then
			return
		end
		payReward(player, dog, Config.DogWalking.rewardPerLoop)
	end)
end

--------------------------------------------------------------------------------
-- FREELANCE GIG HUB (passive $/sec)
--------------------------------------------------------------------------------

function IncomeSourceService.ActivateFreelanceHub(player: Player)
	if freelanceActive[player] then
		return
	end
	freelanceActive[player] = true
	IncomeSourceService.AddIncomePerSecond(player, Config.FreelanceGigHub.incomePerSecond)

	task.spawn(function()
		while freelanceActive[player] and player.Parent do
			task.wait(1)
			if freelanceActive[player] and player.Parent then
				EconomyService.AddCash(player, Config.FreelanceGigHub.incomePerSecond)
			end
		end
	end)
end

function IncomeSourceService.DeactivateFreelanceHub(player: Player)
	if not freelanceActive[player] then
		return
	end
	freelanceActive[player] = nil
	IncomeSourceService.AddIncomePerSecond(player, -Config.FreelanceGigHub.incomePerSecond)
end

return IncomeSourceService
