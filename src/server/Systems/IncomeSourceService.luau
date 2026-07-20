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
local PurchaseEffects = require(script.Parent.PurchaseEffects)
local FloatingText = require(ReplicatedStorage.Shared.Modules.FloatingText)
local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local DOOR_DASH_HOUSE_COUNT = 4
local DOOR_DASH_HOUSE_SPACING = 20
local FLASH_COLOR = Theme.CashPositive

-- Toolbox asset picked by name/thumbnail match — "Pizza Delivery Bike Vehicle
-- Moped Scooter RP" by Charlott3Blad378, free. Screenshot-verified in Studio
-- before wiring in: red cartoon moped w/ built-in delivery box on the rack,
-- which covers the "oversized insulated bag stack" from the visual spec —
-- no separate stack prop needed on top of it.
local DOOR_DASH_MOPED_ASSET_ID = 74198464525165

-- Vehicle tier escalation (Phase 4) hero assets, each replacing the moped
-- as DoorDash's "hero" prop. Screenshot-verified in Studio before wiring
-- in: a plain white box-truck (blank cargo panel, easy to re-skin later),
-- a quadcopter carrying a package, a plain blocky blue helicopter (first
-- helicopter candidate found had a cartoonish face - swapped for this one
-- since it read as too big a tonal swing next to the other 3 vehicles),
-- and a simple white 4-engine cargo plane. All 4 are oversized as authored
-- and get Model:ScaleTo() down to fit our prop scale, same technique as
-- the Dog Walking beagle.
local DOOR_DASH_VAN_ASSET_ID = 117216307672484
local DOOR_DASH_DRONE_ASSET_ID = 376960362
local DOOR_DASH_HELICOPTER_ASSET_ID = 12236677
local DOOR_DASH_CARGO_PLANE_ASSET_ID = 15335647

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

-- Toolbox asset picked by name match, screenshot-verified in Studio before
-- wiring in: "Beagle Dog" by dragonkeeper1a, free — a nicely-faceted low-
-- poly beagle. Modeled at a much larger scale than needed (~5.8 studs tall,
-- nearly character-height) so it gets Model:ScaleTo() down to dog-size on
-- load. All 3 copies keep the model's natural beagle coloring — recoloring
-- would mean guessing at this asset's internal part structure for little
-- payoff, the tangle-of-leashes is what sells the "walking a pack" gag.
local DOG_WALKING_DOG_ASSET_ID = 9587310814
local DOG_WALKING_TARGET_HEIGHT = 2.2 -- studs, knee-high to a player
local HYDRANT_COLOR = Color3.fromRGB(210, 50, 50)
local BOWL_COLOR = Color3.fromRGB(90, 150, 200)
local TENNIS_BALL_COLOR = Color3.fromRGB(200, 230, 60)
local SHOE_COLOR = Color3.fromRGB(120, 80, 55)
local PAW_PRINT_COLOR = Color3.fromRGB(60, 45, 40)
local LEASH_POST_COLOR = Color3.fromRGB(140, 140, 145)

-- All primitives — a pop-up tent + desk is squarely primitives territory
-- per the visual spec, no Toolbox asset needed. Freelance has no
-- interactive prompt at all (ActivateFreelanceHub is pure passive income,
-- no "walk up and press E" loop), so this hero is purely decorative.
local TENT_CANOPY_COLOR = Theme.Secondary
local TENT_TRIM_COLOR = Color3.fromRGB(255, 255, 255)
local TENT_POLE_COLOR = Color3.fromRGB(90, 90, 95)
local DESK_COLOR = Color3.fromRGB(120, 90, 65)
local LAPTOP_COLORS = {
	Color3.fromRGB(220, 220, 225),
	Color3.fromRGB(60, 60, 65),
	Color3.fromRGB(200, 90, 120),
}
local WIFI_BAR_COLOR = Theme.AffordablePulse
local BEAN_BAG_COLOR = Color3.fromRGB(200, 90, 60)
local WHITEBOARD_COLOR = Color3.fromRGB(245, 245, 245)
local MONSTERA_POT_COLOR = Color3.fromRGB(180, 100, 70)
local MONSTERA_LEAF_COLOR = Color3.fromRGB(50, 130, 70)
local COLD_BREW_COLOR = Color3.fromRGB(70, 45, 30)
local CABLE_COLOR = Color3.fromRGB(30, 30, 30)

local IncomeSourceService = {}

-- cd[player][station] = os.clock() expiry
local doorDashCooldowns: { [Player]: { [BasePart]: number } } = {}
local rideshareCooldowns: { [Player]: { [BasePart]: number } } = {}
local dogWalkingCooldowns: { [Player]: { [BasePart]: number } } = {}

-- Per-player neighborhood plot state (upgrade/manager/scale systems read/
-- write this to know which houses/stations belong to which player).
type DoorDashPlot = {
	folder: Folder,
	origin: Vector3,
	houses: { BasePart },
}
local doorDashPlots: { [Player]: DoorDashPlot } = {}

type DogWalkingPlot = {
	folder: Folder,
	origin: Vector3,
	hero: Model,
	post: BasePart?,
}
local dogWalkingPlots: { [Player]: DogWalkingPlot } = {}

-- freelanceActive[player] = true while the passive tick loop should keep firing
local freelanceActive: { [Player]: boolean } = {}

-- dogWalkingManagerActive[player] = true while the auto-collect loop should keep firing
local dogWalkingManagerActive: { [Player]: boolean } = {}

-- doorDashManagerActive[player] = true while the auto-collect loops (one per
-- house) should keep firing
local doorDashManagerActive: { [Player]: boolean } = {}

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

-- Generic tier-upgrade kiosk builder - one physical sign per track rather
-- than a multi-button menu, shared by both Dog Walking and DoorDash (and any
-- future hustle that gets this same Value/Speed pattern). Placed early in
-- the file since both hustles' sections below need it.
local function buildTierKiosk(folder: Instance, position: Vector3, trackLabel: string, boardColor: Color3)
	local post = Instance.new("Part")
	post.Name = trackLabel .. "KioskPost"
	post.Anchored = true
	post.CanCollide = false
	post.Material = Enum.Material.Metal
	post.Color = Color3.fromRGB(150, 150, 155)
	post.Size = Vector3.new(0.3, 3, 0.3)
	post.CFrame = CFrame.new(position)
	post.Parent = folder

	local board = Instance.new("Part")
	board.Name = trackLabel .. "KioskBoard"
	board.Anchored = true
	board.CanCollide = false
	board.Material = Enum.Material.SmoothPlastic
	board.Color = boardColor
	board.Size = Vector3.new(3, 1.8, 0.2)
	board.CFrame = post.CFrame * CFrame.new(0, 2.1, 0)
	board.Parent = folder

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.Parent = board

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0, 0)
	titleLabel.Size = UDim2.new(1, 0, 0.32, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Text = trackLabel
	titleLabel.Parent = gui

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromScale(0, 0.32)
	statusLabel.Size = UDim2.new(1, 0, 0.68, 0)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = Theme.Gold
	statusLabel.TextWrapped = true
	statusLabel.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = board

	return board, statusLabel, prompt
end

-- Generic tier-list display renderer, shared by both hustles' Value/Speed
-- kiosks - caller resolves the next tier from its own state/tier-list.
local function renderTierKioskDisplay(nextTier: { name: string, cost: number }?, statusLabel: TextLabel, prompt: ProximityPrompt)
	if nextTier then
		statusLabel.Text = nextTier.name .. "\n$" .. NumberFormatter.Format(nextTier.cost)
		prompt.ActionText = "Upgrade"
		prompt.ObjectText = nextTier.name .. " ($" .. NumberFormatter.Format(nextTier.cost) .. ")"
		prompt.Enabled = true
	else
		statusLabel.Text = "MAXED"
		prompt.Enabled = false
	end
end

-- Tweens a Model back and forth between two CFrames forever via a
-- NumberValue-lerp-driven PivotTo — same technique PurchaseEffects.riseHero
-- uses for Model heroes (Model has no tweenable CFrame property), just with
-- infinite repeat+reverse instead of a one-shot rise. Cheap cosmetic patrol,
-- no pathfinding. Shared by both hustles' hired-Manager NPCs.
local function loopModelBetweenPoints(model: Model, cframeA: CFrame, cframeB: CFrame, duration: number)
	model:PivotTo(cframeA)
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	alpha.Parent = model
	alpha:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:PivotTo(cframeA:Lerp(cframeB, alpha.Value))
		end
	end)
	TweenService:Create(alpha, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Value = 1 }):Play()
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
	signGui.Face = Enum.NormalId.Back
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

local function loadDogModel(): Model?
	local ok, container = pcall(function()
		return InsertService:LoadAsset(DOG_WALKING_DOG_ASSET_ID)
	end)
	local dog = ok and container and container:FindFirstChildOfClass("Model")
	if container then
		if dog then
			dog.Parent = nil
		end
		container:Destroy()
	end
	return dog
end

-- Scales the (much-too-large) dog asset down to DOG_WALKING_TARGET_HEIGHT
-- via Model:ScaleTo, then recenters+rotates it into place with the same
-- delta-transform technique as recenterModel — ScaleTo alone scales around
-- whatever the model's implicit pivot happens to be, which isn't
-- necessarily where we want the dog to actually stand.
local function scaleAndPositionDog(dog: Model, targetPosition: Vector3, targetYaw: number): Vector3
	local _, sizeBeforeScale = dog:GetBoundingBox()
	dog:ScaleTo(DOG_WALKING_TARGET_HEIGHT / sizeBeforeScale.Y)

	local boundingCFrame, sizeAfterScale = dog:GetBoundingBox()
	local targetCenter = CFrame.new(targetPosition + Vector3.new(0, sizeAfterScale.Y / 2, 0)) * CFrame.Angles(0, targetYaw, 0)
	local delta = targetCenter * boundingCFrame:Inverse()
	for _, part in ipairs(dog:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CFrame = delta * part.CFrame
		end
	end
	return sizeAfterScale
end

-- Fire hydrant, dog bowl, tennis balls, "BEWARE OF DOG (he's friendly)"
-- sign, a chewed shoe, a poop-bag dispenser, and paw-print ground decals —
-- the suburban dog-walking details from the visual spec.
local function buildDogWalkingDetails(zoneModel: Model, base: Vector3)
	local hydrantBody = Instance.new("Part")
	hydrantBody.Name = "HydrantBody"
	hydrantBody.Anchored = true
	hydrantBody.CanCollide = true
	hydrantBody.Material = Enum.Material.SmoothPlastic
	hydrantBody.Color = HYDRANT_COLOR
	hydrantBody.Size = Vector3.new(1.2, 2, 1.2)
	hydrantBody.CFrame = CFrame.new(base + Vector3.new(4.5, 1, 4))
	hydrantBody.Parent = zoneModel

	local hydrantCap = Instance.new("Part")
	hydrantCap.Name = "HydrantCap"
	hydrantCap.Anchored = true
	hydrantCap.CanCollide = false
	hydrantCap.Material = Enum.Material.SmoothPlastic
	hydrantCap.Color = HYDRANT_COLOR
	hydrantCap.Size = Vector3.new(0.7, 0.4, 0.7)
	hydrantCap.CFrame = hydrantBody.CFrame * CFrame.new(0, 1.2, 0)
	hydrantCap.Parent = zoneModel

	for _, side in ipairs({ -1, 1 }) do
		local nub = Instance.new("Part")
		nub.Name = "HydrantNub"
		nub.Anchored = true
		nub.CanCollide = false
		nub.Material = Enum.Material.SmoothPlastic
		nub.Color = HYDRANT_COLOR
		nub.Size = Vector3.new(0.5, 0.5, 0.5)
		nub.CFrame = hydrantBody.CFrame * CFrame.new(side * 0.75, 0.3, 0)
		nub.Parent = zoneModel
	end

	local bowl = Instance.new("Part")
	bowl.Name = "DogBowl"
	bowl.Shape = Enum.PartType.Cylinder
	bowl.Anchored = true
	bowl.CanCollide = false
	bowl.Material = Enum.Material.SmoothPlastic
	bowl.Color = BOWL_COLOR
	bowl.Size = Vector3.new(0.5, 1.4, 1.4)
	bowl.CFrame = CFrame.new(base + Vector3.new(-4, 0.25, 4)) * CFrame.Angles(0, 0, math.rad(90))
	bowl.Parent = zoneModel

	for i = 1, 3 do
		local ball = Instance.new("Part")
		ball.Name = "TennisBall"
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.Material = Enum.Material.SmoothPlastic
		ball.Color = TENNIS_BALL_COLOR
		ball.Size = Vector3.new(0.6, 0.6, 0.6)
		ball.CFrame = CFrame.new(base + Vector3.new(-3.5 + i * 0.7, 0.3, 5.2))
		ball.Parent = zoneModel
	end

	local signPost = Instance.new("Part")
	signPost.Name = "BewarePost"
	signPost.Anchored = true
	signPost.CanCollide = false
	signPost.Material = Enum.Material.Wood
	signPost.Color = Color3.fromRGB(110, 80, 55)
	signPost.Size = Vector3.new(0.3, 3.5, 0.3)
	signPost.CFrame = CFrame.new(base + Vector3.new(4.5, 1.75, -4))
	signPost.Parent = zoneModel

	local signBoard = Instance.new("Part")
	signBoard.Name = "BewareBoard"
	signBoard.Anchored = true
	signBoard.CanCollide = false
	signBoard.Material = Enum.Material.WoodPlanks
	signBoard.Color = Color3.fromRGB(230, 220, 200)
	signBoard.Size = Vector3.new(2.6, 1.4, 0.15)
	signBoard.CFrame = signPost.CFrame * CFrame.new(0, 1.2, 0)
	signBoard.Parent = zoneModel

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.Parent = signBoard
	local signLabel = Instance.new("TextLabel")
	signLabel.BackgroundTransparency = 1
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(40, 30, 20)
	signLabel.TextWrapped = true
	signLabel.Text = "BEWARE OF DOG\n(he's friendly)"
	signLabel.Parent = signGui

	local shoe = Instance.new("Part")
	shoe.Name = "ChewedShoe"
	shoe.Anchored = true
	shoe.CanCollide = false
	shoe.Material = Enum.Material.SmoothPlastic
	shoe.Color = SHOE_COLOR
	shoe.Size = Vector3.new(1.4, 0.6, 0.7)
	shoe.CFrame = CFrame.new(base + Vector3.new(-4.5, 0.3, -3.5)) * CFrame.Angles(0, math.rad(35), 0)
	shoe.Parent = zoneModel

	local dispenserPost = Instance.new("Part")
	dispenserPost.Name = "DispenserPost"
	dispenserPost.Anchored = true
	dispenserPost.CanCollide = false
	dispenserPost.Material = Enum.Material.Metal
	dispenserPost.Color = LEASH_POST_COLOR
	dispenserPost.Size = Vector3.new(0.3, 3, 0.3)
	dispenserPost.CFrame = CFrame.new(base + Vector3.new(-4.5, 1.5, 4.5))
	dispenserPost.Parent = zoneModel

	local dispenserBox = Instance.new("Part")
	dispenserBox.Name = "DispenserBox"
	dispenserBox.Anchored = true
	dispenserBox.CanCollide = false
	dispenserBox.Material = Enum.Material.SmoothPlastic
	dispenserBox.Color = Color3.fromRGB(60, 150, 90)
	dispenserBox.Size = Vector3.new(0.9, 0.7, 0.5)
	dispenserBox.CFrame = dispenserPost.CFrame * CFrame.new(0, 1.3, 0)
	dispenserBox.Parent = zoneModel

	for i = 1, 5 do
		local paw = Instance.new("Part")
		paw.Name = "PawPrint"
		paw.Anchored = true
		paw.CanCollide = false
		paw.Material = Enum.Material.SmoothPlastic
		paw.Color = PAW_PRINT_COLOR
		paw.Transparency = 0.3
		paw.Size = Vector3.new(0.5, 0.02, 0.5)
		paw.CFrame = CFrame.new(base + Vector3.new(-2 + i * 0.8, 0.02, -2 + (i % 2) * 1.2))
			* CFrame.Angles(0, math.rad(i * 25), 0)
		paw.Parent = zoneModel
	end
end

-- The Dog Walking "hero": a leash post with a tangle of 3 dogs on Beam
-- leashes (CurveSize gives them a bit of sag/slack). LeashPost is the
-- interactive part — a fixed, always-findable anchor, unlike picking one
-- of the 3 dogs arbitrarily. `base` is a ground-level world position (was
-- previously derived from a Zone floor part; Dog Walking is now the
-- always-free per-plot starter, so it's just the plot-relative spot).
function IncomeSourceService.BuildDogWalkingHero(zoneModel: Model, base: Vector3): Model
	local hero = Instance.new("Model")
	hero.Name = "Hero"
	hero.Parent = zoneModel

	local post = Instance.new("Part")
	post.Name = "LeashPost"
	post.Anchored = true
	post.CanCollide = true
	post.Material = Enum.Material.Metal
	post.Color = LEASH_POST_COLOR
	post.Size = Vector3.new(0.5, 3, 0.5)
	post.CFrame = CFrame.new(base + Vector3.new(0, 1.5, 0))
	post.Parent = hero
	hero.PrimaryPart = post

	local leashTop = Instance.new("Attachment")
	leashTop.Name = "LeashTop"
	leashTop.Position = Vector3.new(0, 1.4, 0)
	leashTop.Parent = post

	local dogOffsets = {
		{ position = Vector3.new(2.2, 0, 1.2), yaw = math.rad(-30) },
		{ position = Vector3.new(-2.0, 0, 1.6), yaw = math.rad(150) },
		{ position = Vector3.new(0.4, 0, 2.6), yaw = math.rad(200) },
	}

	local anyDogLoaded = false
	for i, offset in ipairs(dogOffsets) do
		local dog = loadDogModel()
		if dog then
			anyDogLoaded = true
			dog.Name = "Dog" .. i
			dog.Parent = hero
			local size = scaleAndPositionDog(dog, base + offset.position, offset.yaw)

			local dogCenter = (dog:GetBoundingBox())
			local collar = Instance.new("Attachment")
			collar.Name = "Collar" .. i
			collar.Parent = post
			collar.WorldPosition = dogCenter.Position + Vector3.new(0, size.Y * 0.3, size.Z * 0.35)

			local leash = Instance.new("Beam")
			leash.Name = "Leash" .. i
			leash.Attachment0 = leashTop
			leash.Attachment1 = collar
			leash.Width0 = 0.08
			leash.Width1 = 0.08
			leash.Color = ColorSequence.new(Color3.fromRGB(200, 60, 60))
			leash.FaceCamera = true
			leash.Segments = 3
			leash.CurveSize0 = 0.3
			leash.CurveSize1 = -0.3
			leash.Parent = post
		end
	end

	if not anyDogLoaded then
		warn("[IncomeSourceService] Failed to load any Dog Walking asset copies, tangle will be post-only")
	end

	buildDogWalkingDetails(zoneModel, base)

	return hero
end

-- Sticker-covered laptops, a cold-brew can, a bean bag, a "HUSTLE"
-- whiteboard, tangled charging cables, a potted monstera, and a pinned
-- "1★ client" complaint note — the co-working clutter from the visual
-- spec. Deliberately the densest/most cluttered of the five zones so it
-- reads as the most "established" — someone's clearly been working here.
local function buildFreelanceDetails(zoneModel: Model, floor: BasePart, desk: BasePart)
	local base = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)

	for i, color in ipairs(LAPTOP_COLORS) do
		local laptopBase = Instance.new("Part")
		laptopBase.Name = "LaptopBase"
		laptopBase.Anchored = true
		laptopBase.CanCollide = false
		laptopBase.Material = Enum.Material.SmoothPlastic
		laptopBase.Color = color
		laptopBase.Size = Vector3.new(1.2, 0.1, 0.8)
		laptopBase.CFrame = desk.CFrame * CFrame.new(-1.2 + (i - 1) * 1.2, 0.35, 0)
		laptopBase.Parent = zoneModel

		local laptopScreen = Instance.new("Part")
		laptopScreen.Name = "LaptopScreen"
		laptopScreen.Anchored = true
		laptopScreen.CanCollide = false
		laptopScreen.Material = Enum.Material.SmoothPlastic
		laptopScreen.Color = color
		laptopScreen.Size = Vector3.new(1.2, 0.8, 0.06)
		laptopScreen.CFrame = laptopBase.CFrame * CFrame.new(0, 0.4, -0.37) * CFrame.Angles(math.rad(-100), 0, 0)
		laptopScreen.Parent = zoneModel

		-- A small bright "sticker" square on the lid back
		local sticker = Instance.new("Part")
		sticker.Name = "LaptopSticker"
		sticker.Anchored = true
		sticker.CanCollide = false
		sticker.Material = Enum.Material.SmoothPlastic
		sticker.Color = LAPTOP_COLORS[((i) % #LAPTOP_COLORS) + 1]
		sticker.Size = Vector3.new(0.3, 0.3, 0.02)
		sticker.CFrame = laptopScreen.CFrame * CFrame.new(0.3, 0.15, -0.04)
		sticker.Parent = zoneModel
	end

	-- WiFi signal bars, floating above the tent
	local wifiBase = desk.Position + Vector3.new(0, 6, 0)
	for i = 1, 4 do
		local bar = Instance.new("Part")
		bar.Name = "WifiBar"
		bar.Anchored = true
		bar.CanCollide = false
		bar.Material = Enum.Material.Neon
		bar.Color = WIFI_BAR_COLOR
		local barHeight = 0.5 + i * 0.4
		bar.Size = Vector3.new(0.5, barHeight, 0.5)
		bar.CFrame = CFrame.new(wifiBase + Vector3.new(-1.2 + i * 0.8, barHeight / 2, 0))
		bar.Parent = zoneModel
		task.delay((i - 1) * 0.15, function()
			if bar.Parent then
				TweenService:Create(
					bar,
					TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0.55 }
				):Play()
			end
		end)
	end

	-- Bean bag
	local beanBag = Instance.new("Part")
	beanBag.Name = "BeanBag"
	beanBag.Shape = Enum.PartType.Ball
	beanBag.Anchored = true
	beanBag.CanCollide = true
	beanBag.Material = Enum.Material.Fabric
	beanBag.Color = BEAN_BAG_COLOR
	beanBag.Size = Vector3.new(2.6, 1.6, 2.6)
	beanBag.CFrame = CFrame.new(base + Vector3.new(4, 0.8, 3))
	beanBag.Parent = zoneModel

	-- "HUSTLE" whiteboard with a pinned 1-star complaint note
	local whiteboardPost = Instance.new("Part")
	whiteboardPost.Name = "WhiteboardPost"
	whiteboardPost.Anchored = true
	whiteboardPost.CanCollide = false
	whiteboardPost.Material = Enum.Material.Metal
	whiteboardPost.Color = TENT_POLE_COLOR
	whiteboardPost.Size = Vector3.new(0.3, 4, 0.3)
	whiteboardPost.CFrame = CFrame.new(base + Vector3.new(-4.5, 2, -3.5))
	whiteboardPost.Parent = zoneModel

	local whiteboard = Instance.new("Part")
	whiteboard.Name = "Whiteboard"
	whiteboard.Anchored = true
	whiteboard.CanCollide = false
	whiteboard.Material = Enum.Material.SmoothPlastic
	whiteboard.Color = WHITEBOARD_COLOR
	whiteboard.Size = Vector3.new(3, 2, 0.15)
	whiteboard.CFrame = whiteboardPost.CFrame * CFrame.new(0, 1.8, 0)
	whiteboard.Parent = zoneModel

	local whiteboardGui = Instance.new("SurfaceGui")
	whiteboardGui.Face = Enum.NormalId.Back
	whiteboardGui.Parent = whiteboard
	local whiteboardLabel = Instance.new("TextLabel")
	whiteboardLabel.BackgroundTransparency = 1
	whiteboardLabel.Size = UDim2.fromScale(1, 1)
	whiteboardLabel.Font = Enum.Font.Bangers
	whiteboardLabel.TextScaled = true
	whiteboardLabel.TextColor3 = Color3.fromRGB(200, 60, 60)
	whiteboardLabel.Text = "HUSTLE"
	whiteboardLabel.Parent = whiteboardGui

	local noteBoard = Instance.new("Part")
	noteBoard.Name = "ComplaintNote"
	noteBoard.Anchored = true
	noteBoard.CanCollide = false
	noteBoard.Material = Enum.Material.SmoothPlastic
	noteBoard.Color = Color3.fromRGB(255, 240, 180)
	noteBoard.Size = Vector3.new(0.9, 0.7, 0.05)
	noteBoard.CFrame = whiteboard.CFrame * CFrame.new(1.6, 0.4, -0.11) * CFrame.Angles(0, 0, math.rad(-8))
	noteBoard.Parent = zoneModel

	local noteGui = Instance.new("SurfaceGui")
	noteGui.Face = Enum.NormalId.Back
	noteGui.Parent = noteBoard
	local noteLabel = Instance.new("TextLabel")
	noteLabel.BackgroundTransparency = 1
	noteLabel.Size = UDim2.fromScale(1, 1)
	noteLabel.Font = Enum.Font.Code
	noteLabel.TextScaled = true
	noteLabel.TextColor3 = Color3.fromRGB(40, 30, 10)
	noteLabel.TextWrapped = true
	noteLabel.Text = '1 star\n"never\nresponds"'
	noteLabel.Parent = noteGui

	-- Potted monstera (pot + a few fanned flat "leaves")
	local pot = Instance.new("Part")
	pot.Name = "MonsteraPot"
	pot.Shape = Enum.PartType.Cylinder
	pot.Anchored = true
	pot.CanCollide = true
	pot.Material = Enum.Material.SmoothPlastic
	pot.Color = MONSTERA_POT_COLOR
	pot.Size = Vector3.new(1.4, 1.2, 1.2)
	pot.CFrame = CFrame.new(base + Vector3.new(4.5, 0.7, -3.5)) * CFrame.Angles(0, 0, math.rad(90))
	pot.Parent = zoneModel

	for i = 1, 4 do
		local leaf = Instance.new("Part")
		leaf.Name = "MonsteraLeaf"
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.Material = Enum.Material.SmoothPlastic
		leaf.Color = MONSTERA_LEAF_COLOR
		leaf.Size = Vector3.new(0.1, 1.6, 0.9)
		leaf.CFrame = pot.CFrame * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, math.rad(i * 80), math.rad(15))
		leaf.Parent = zoneModel
	end

	-- Cold-brew can
	local can = Instance.new("Part")
	can.Name = "ColdBrewCan"
	can.Shape = Enum.PartType.Cylinder
	can.Anchored = true
	can.CanCollide = false
	can.Material = Enum.Material.Metal
	can.Color = COLD_BREW_COLOR
	can.Size = Vector3.new(0.7, 0.5, 0.5)
	can.CFrame = desk.CFrame * CFrame.new(1.6, 0.35, 0.5) * CFrame.Angles(0, 0, math.rad(90))
	can.Parent = zoneModel

	-- Tangled charging cables on the ground near the desk
	for i = 1, 3 do
		local cable = Instance.new("Part")
		cable.Name = "ChargingCable"
		cable.Shape = Enum.PartType.Cylinder
		cable.Anchored = true
		cable.CanCollide = false
		cable.Material = Enum.Material.SmoothPlastic
		cable.Color = CABLE_COLOR
		cable.Size = Vector3.new(0.08, 1.4, 0.08)
		cable.CFrame = CFrame.new(base + Vector3.new(-1.5 + i * 0.5, 0.05, 1.5))
			* CFrame.Angles(math.rad(90), math.rad(i * 40), 0)
		cable.Parent = zoneModel
	end
end

-- The Freelance Gig Hub "hero": a pop-up co-working tent (4 poles + 2 roof
-- wedges + a trim stripe) over a laptop-covered desk, with glowing WiFi
-- bars overhead. No interactive prompt — ActivateFreelanceHub just flips
-- on passive income, there's no "walk up and press E" loop here.
function IncomeSourceService.BuildFreelanceHero(zoneModel: Model, floor: BasePart): Model | BasePart
	local hero = Instance.new("Model")
	hero.Name = "Hero"
	hero.Parent = zoneModel

	local base = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)
	local tentHeight = 5

	for _, corner in ipairs({ Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) }) do
		local pole = Instance.new("Part")
		pole.Name = "TentPole"
		pole.Anchored = true
		pole.CanCollide = true
		pole.Material = Enum.Material.Metal
		pole.Color = TENT_POLE_COLOR
		pole.Size = Vector3.new(0.3, tentHeight, 0.3)
		pole.CFrame = CFrame.new(base + corner + Vector3.new(0, tentHeight / 2, 0))
		pole.Parent = hero
	end

	local roofA = Instance.new("WedgePart")
	roofA.Name = "RoofA"
	roofA.Anchored = true
	roofA.CanCollide = false
	roofA.Material = Enum.Material.Fabric
	roofA.Color = TENT_CANOPY_COLOR
	roofA.Size = Vector3.new(6.6, 1.8, 3.3)
	roofA.CFrame = CFrame.new(base + Vector3.new(0, tentHeight + 0.5, 1.65)) * CFrame.Angles(0, math.rad(180), 0)
	roofA.Parent = hero

	local roofB = roofA:Clone()
	roofB.Name = "RoofB"
	roofB.CFrame = CFrame.new(base + Vector3.new(0, tentHeight + 0.5, -1.65))
	roofB.Parent = hero

	local trim = Instance.new("Part")
	trim.Name = "RoofTrim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.Material = Enum.Material.SmoothPlastic
	trim.Color = TENT_TRIM_COLOR
	trim.Size = Vector3.new(6.7, 0.2, 0.3)
	trim.CFrame = CFrame.new(base + Vector3.new(0, tentHeight + 0.5, 0))
	trim.Parent = hero

	local desk = Instance.new("Part")
	desk.Name = "Desk"
	desk.Anchored = true
	desk.CanCollide = true
	desk.Material = Enum.Material.WoodPlanks
	desk.Color = DESK_COLOR
	desk.Size = Vector3.new(4.4, 0.25, 1.8)
	desk.CFrame = CFrame.new(base + Vector3.new(0, 2.2, 0))
	desk.Parent = hero
	hero.PrimaryPart = desk

	for _, side in ipairs({ -1, 1 }) do
		for _, endSign in ipairs({ -1, 1 }) do
			local leg = Instance.new("Part")
			leg.Name = "DeskLeg"
			leg.Anchored = true
			leg.CanCollide = false
			leg.Material = Enum.Material.WoodPlanks
			leg.Color = DESK_COLOR
			leg.Size = Vector3.new(0.2, 2.1, 0.2)
			leg.CFrame = desk.CFrame * CFrame.new(side * 2, -1.1, endSign * 0.8)
			leg.Parent = hero
		end
	end

	buildFreelanceDetails(zoneModel, floor, desk)

	return hero
end

-- Actually builds the houses/moped once DoorDash is unlocked (fresh
-- purchase or already-owned rejoin) - same layout as before the role swap,
-- just gated behind a one-time cash unlock instead of being free from spawn.
-- Neighborhood Upgrade visual: a thin gold band on each DoorDash house plus
-- one new apartment building at the end of the row. Called both when the
-- upgrade is purchased (retrofits whatever houses already exist) and when
-- houses are built later (covers buying the upgrade before ever unlocking
-- DoorDash) - either ordering ends up looking correct.
local function addHouseUpgradeTrim(house: BasePart)
	if house:FindFirstChild("UpgradeTrim") then
		return
	end
	local trim = Instance.new("Part")
	trim.Name = "UpgradeTrim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.Material = Enum.Material.Neon
	trim.Color = Theme.Gold
	trim.Size = Vector3.new(house.Size.X * 1.05, 0.3, house.Size.Z * 1.05)
	trim.CFrame = house.CFrame * CFrame.new(0, house.Size.Y * 0.42, 0)
	trim.Parent = house
end

local function buildApartmentBuilding(areaModel: Instance, origin: Vector3)
	if areaModel:FindFirstChild("ApartmentBuilding") then
		return
	end
	local startX = -((DOOR_DASH_HOUSE_COUNT - 1) * DOOR_DASH_HOUSE_SPACING) / 2
	local apartmentX = startX + DOOR_DASH_HOUSE_COUNT * DOOR_DASH_HOUSE_SPACING

	local building = Instance.new("Part")
	building.Name = "ApartmentBuilding"
	building.Anchored = true
	building.CanCollide = true
	building.Material = Enum.Material.Concrete
	building.Color = Color3.fromRGB(180, 175, 165)
	building.Size = Vector3.new(8, 16, 8)
	building.Position = origin + Vector3.new(apartmentX, 8, -30)
	building.Parent = areaModel

	for i = 1, 3 do
		local window = Instance.new("Part")
		window.Name = "ApartmentWindow"
		window.Anchored = true
		window.CanCollide = false
		window.Material = Enum.Material.Neon
		window.Color = Color3.fromRGB(255, 220, 140)
		window.Size = Vector3.new(1.2, 1.2, 0.1)
		window.CFrame = building.CFrame * CFrame.new(-2 + (i - 1) * 2, 4 - (i - 1) * 4, 4.05)
		window.Parent = areaModel
	end
end

local function applyNeighborhoodUpgradeVisuals(areaModel: Instance, origin: Vector3)
	local anyHouse = false
	for _, c in ipairs(areaModel:GetChildren()) do
		if c.Name:match("^DoorDashHouse_") then
			anyHouse = true
			addHouseUpgradeTrim(c :: BasePart)
		end
	end
	if anyHouse then
		buildApartmentBuilding(areaModel, origin)
	end
end

--------------------------------------------------------------------------------
-- DOOR DASH reward/cooldown mechanics (built before the house-building
-- functions below since they call these)
--------------------------------------------------------------------------------

-- state.valueTier/speedTier/vehicleTier (0 = none/start) index directly into
-- their tier arrays (1-based). Reads live every payout so kiosk purchases,
-- Manager auto-collect, and vehicle tier swaps all apply immediately - same
-- pattern as Dog Walking's getDogWalkingCooldown/getDogWalkingReward.
local function getDoorDashCooldown(player: Player): number
	local state = EconomyService.GetDoorDashState(player)
	local speedTier = state and Config.DoorDash.speedTiers[state.speedTier]
	local cooldown = speedTier and speedTier.cooldown or Config.DoorDash.cooldown
	local vehicleTier = state and Config.DoorDash.vehicleTiers[state.vehicleTier]
	local cooldownMultiplier = vehicleTier and vehicleTier.cooldownMultiplier or 1
	return cooldown * cooldownMultiplier
end

local function getDoorDashRewardRange(player: Player): (number, number)
	local state = EconomyService.GetDoorDashState(player)
	local valueTier = state and Config.DoorDash.valueTiers[state.valueTier]
	local valueMultiplier = valueTier and valueTier.multiplier or 1
	local vehicleTier = state and Config.DoorDash.vehicleTiers[state.vehicleTier]
	local vehicleMultiplier = vehicleTier and vehicleTier.valueMultiplier or 1
	local neighborhoodMultiplier = if EconomyService.GetNeighborhoodTier(player) > 0
		then Config.Neighborhood.upgradeMultiplier
		else 1
	local totalMultiplier = valueMultiplier * vehicleMultiplier * neighborhoodMultiplier
	return Config.DoorDash.minReward * totalMultiplier, Config.DoorDash.maxReward * totalMultiplier
end

local function refreshDoorDashHousePrompts(player: Player)
	local plot = doorDashPlots[player]
	if not plot then
		return
	end
	local minR, maxR = getDoorDashRewardRange(player)
	local rangeText = if math.floor(minR) == math.floor(maxR)
		then "$" .. math.floor(minR)
		else "$" .. math.floor(minR) .. "-" .. math.floor(maxR)
	for i, house in ipairs(plot.houses) do
		local prompt = house:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.ObjectText = "House " .. i .. " (+" .. rangeText .. ")"
		end
	end
end

function IncomeSourceService.HandleDoorDashDelivery(player: Player, house: BasePart): number?
	if not checkCooldown(doorDashCooldowns, player, house, getDoorDashCooldown(player)) then
		return nil
	end
	local minR, maxR = getDoorDashRewardRange(player)
	local reward = math.floor(minR + math.random() * (maxR - minR) + 0.5)
	payReward(player, house, reward)
	return reward
end

local function refreshDoorDashValueKioskDisplay(player: Player, statusLabel: TextLabel, prompt: ProximityPrompt)
	local state = EconomyService.GetDoorDashState(player)
	renderTierKioskDisplay(Config.DoorDash.valueTiers[state.valueTier + 1], statusLabel, prompt)
end

local function refreshDoorDashSpeedKioskDisplay(player: Player, statusLabel: TextLabel, prompt: ProximityPrompt)
	local state = EconomyService.GetDoorDashState(player)
	renderTierKioskDisplay(Config.DoorDash.speedTiers[state.speedTier + 1], statusLabel, prompt)
end

-- Standalone (not just a Triggered closure) so it's directly callable, same
-- as AttemptDogWalkingValueUpgrade.
function IncomeSourceService.AttemptDoorDashValueUpgrade(player: Player, board: BasePart, statusLabel: TextLabel, prompt: ProximityPrompt): boolean
	local state = EconomyService.GetDoorDashState(player)
	local nextTier = Config.DoorDash.valueTiers[state.valueTier + 1]
	if not nextTier then
		return false
	end
	if not EconomyService.CanAfford(player, nextTier.cost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(nextTier.cost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, nextTier.cost) then
		return false
	end
	EconomyService.UpdateDoorDash(player, { valueTier = state.valueTier + 1 })
	FloatingText.Show(board, nextTier.name .. "!", Theme.CashPositive)
	refreshDoorDashValueKioskDisplay(player, statusLabel, prompt)
	refreshDoorDashHousePrompts(player)
	return true
end

function IncomeSourceService.AttemptDoorDashSpeedUpgrade(player: Player, board: BasePart, statusLabel: TextLabel, prompt: ProximityPrompt): boolean
	local state = EconomyService.GetDoorDashState(player)
	local nextTier = Config.DoorDash.speedTiers[state.speedTier + 1]
	if not nextTier then
		return false
	end
	if not EconomyService.CanAfford(player, nextTier.cost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(nextTier.cost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, nextTier.cost) then
		return false
	end
	EconomyService.UpdateDoorDash(player, { speedTier = state.speedTier + 1 })
	FloatingText.Show(board, nextTier.name .. "!", Theme.CashPositive)
	refreshDoorDashSpeedKioskDisplay(player, statusLabel, prompt)
	return true
end

-- The "Dispatcher" hired NPC: a primitive delivery-person figure carrying a
-- package, patrolling a back-and-forth loop along the house row so
-- automation feels alive without any pathfinding.
local function buildDispatcherNpc(folder: Instance, origin: Vector3): Model
	local npc = Instance.new("Model")
	npc.Name = "DispatcherNpc"
	npc.Parent = folder

	local startPos = origin + Vector3.new(-30, 3, -27)

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Anchored = true
	torso.CanCollide = false
	torso.Material = Enum.Material.SmoothPlastic
	torso.Color = Theme.Brand
	torso.Size = Vector3.new(1.4, 2, 0.8)
	torso.CFrame = CFrame.new(startPos)
	torso.Parent = npc
	npc.PrimaryPart = torso

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Anchored = true
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(255, 213, 170)
	head.Size = Vector3.new(1, 1, 1)
	head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = npc

	for _, side in ipairs({ -1, 1 }) do
		local leg = Instance.new("Part")
		leg.Name = "Leg"
		leg.Anchored = true
		leg.CanCollide = false
		leg.Material = Enum.Material.SmoothPlastic
		leg.Color = Color3.fromRGB(40, 40, 45)
		leg.Size = Vector3.new(0.5, 1.6, 0.6)
		leg.CFrame = torso.CFrame * CFrame.new(side * 0.35, -1.8, 0)
		leg.Parent = npc
	end

	local package = Instance.new("Part")
	package.Name = "Package"
	package.Anchored = true
	package.CanCollide = false
	package.Material = Enum.Material.SmoothPlastic
	package.Color = Color3.fromRGB(200, 160, 110)
	package.Size = Vector3.new(0.8, 0.8, 0.8)
	package.CFrame = torso.CFrame * CFrame.new(0.9, -0.3, 0)
	package.Parent = npc

	local pointA = torso.CFrame
	local pointB = torso.CFrame * CFrame.new(60, 0, 0)
	loopModelBetweenPoints(npc, pointA, pointB, 8)

	return npc
end

-- Auto-collect: one loop PER HOUSE (unlike Dog Walking's single station),
-- each firing HandleDoorDashDelivery on its own independent cooldown timer -
-- matches "each owned house pays out automatically" from the original spec.
-- Manual E-presses route through the same function and share the same
-- cooldown table, so whichever fires first just resets that house's timer.
local function startDoorDashHouseLoop(player: Player, house: BasePart)
	task.spawn(function()
		while doorDashManagerActive[player] and player.Parent and house.Parent do
			task.wait(getDoorDashCooldown(player))
			if not (doorDashManagerActive[player] and player.Parent and house.Parent) then
				break
			end
			IncomeSourceService.HandleDoorDashDelivery(player, house)
		end
	end)
end

function IncomeSourceService.StartDoorDashManagerLoops(player: Player)
	local plot = doorDashPlots[player]
	if not plot or doorDashManagerActive[player] then
		return
	end
	doorDashManagerActive[player] = true
	for _, house in ipairs(plot.houses) do
		startDoorDashHouseLoop(player, house)
	end
end

function IncomeSourceService.AttemptDoorDashManagerHire(
	player: Player,
	folder: Instance,
	origin: Vector3,
	board: BasePart,
	statusLabel: TextLabel,
	prompt: ProximityPrompt
): boolean
	local state = EconomyService.GetDoorDashState(player)
	if state.hasManager then
		return false
	end
	if not EconomyService.CanAfford(player, Config.DoorDash.managerCost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(Config.DoorDash.managerCost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, Config.DoorDash.managerCost) then
		return false
	end
	EconomyService.UpdateDoorDash(player, { hasManager = true })

	statusLabel.Text = "HIRED"
	prompt.Enabled = false
	FloatingText.Show(board, "Dispatcher Hired!", Theme.CashPositive)

	buildDispatcherNpc(folder, origin)
	IncomeSourceService.StartDoorDashManagerLoops(player)
	return true
end

-- Cargo Plane's "+2 houses" go behind the main row (not extending it
-- sideways) - extending in +X would collide with the ApartmentBuilding the
-- Neighborhood Upgrade places at startX + houseCount*spacing, and could
-- approach a neighboring plot's footprint (PLOT_ORIGINS are 80 studs apart
-- in X). Sits further back in -Z instead, which nothing else occupies.
local DOOR_DASH_EXTRA_HOUSE_OFFSETS = {
	Vector3.new(-12, 4, -55),
	Vector3.new(12, 4, -55),
}

local function buildHouseAt(player: Player, areaModel: Model, position: Vector3, index: number): BasePart
	local house = Instance.new("Part")
	house.Name = "DoorDashHouse_" .. index
	house.Size = Vector3.new(8, 8, 8)
	house.Anchored = true
	house.Position = position
	house.Color = DOOR_DASH_HOUSE_COLORS[((index - 1) % #DOOR_DASH_HOUSE_COLORS) + 1]
	house.Material = Enum.Material.Wood
	house.Parent = areaModel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Deliver"
	prompt.ObjectText = "House " .. index
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = house

	prompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.HandleDoorDashDelivery(player, house)
	end)

	buildHouseDetails(house, areaModel)
	return house
end

-- Adds Cargo Plane's extra houses - called both at purchase time and (on
-- rejoin) from buildDoorDashNeighborhood if the tier was already owned.
function IncomeSourceService.AddDoorDashExtraHouses(player: Player, count: number)
	local plot = doorDashPlots[player]
	if not plot then
		return
	end
	local areaModel = plot.folder:FindFirstChild("DoorDashArea") :: Model
	for i = 1, math.min(count, #DOOR_DASH_EXTRA_HOUSE_OFFSETS) do
		local index = #plot.houses + 1
		local house = buildHouseAt(player, areaModel, plot.origin + DOOR_DASH_EXTRA_HOUSE_OFFSETS[i], index)
		if EconomyService.GetNeighborhoodTier(player) > 0 then
			addHouseUpgradeTrim(house)
		end
		table.insert(plot.houses, house)
		-- Cargo Plane can be bought after the Dispatcher is already hired -
		-- give the new house its own auto-collect loop immediately rather
		-- than waiting for a rejoin.
		if doorDashManagerActive[player] then
			startDoorDashHouseLoop(player, house)
		end
	end
	-- Persist the new count - without this, a rejoin's extraCount
	-- calculation in buildDoorDashNeighborhood would see the stale saved
	-- count and silently fail to rebuild these houses.
	EconomyService.UpdateDoorDash(player, { houseCount = #plot.houses })
end

-- Vehicle tier escalation (Phase 4): each tier REPLACES DoorDash's hero prop
-- (moped -> van -> drone -> helicopter -> cargo plane). Finds whichever
-- vehicle is currently there under either name - "MopedHero" (built at
-- unlock, before any vehicle tier is bought) or "VehicleHero" (every tier
-- after that) - so the swap works regardless of which one is live.
local function findCurrentDoorDashVehicle(areaModel: Instance): Model?
	return (areaModel:FindFirstChild("VehicleHero") :: Model?) or (areaModel:FindFirstChild("MopedHero") :: Model?)
end

local DOOR_DASH_VEHICLE_ASSET_IDS = {
	[1] = DOOR_DASH_VAN_ASSET_ID,
	[2] = DOOR_DASH_DRONE_ASSET_ID,
	[3] = DOOR_DASH_HELICOPTER_ASSET_ID,
	[4] = DOOR_DASH_CARGO_PLANE_ASSET_ID,
}
-- Target height (studs) each vehicle gets scaled to - keeps the escalation
-- readable at our prop scale (houses are 8 studs tall) without each tier
-- being wildly bigger than the last.
local DOOR_DASH_VEHICLE_TARGET_HEIGHTS = { [1] = 6, [2] = 3, [3] = 6, [4] = 8 }
-- Drone/Helicopter hover above the ground instead of sitting on it.
local DOOR_DASH_VEHICLE_HOVER_HEIGHTS = { [2] = 6, [3] = 7 }

local function buildDoorDashVehicleHero(areaModel: Instance, origin: Vector3, vehicleTier: number): Model?
	local old = findCurrentDoorDashVehicle(areaModel)
	if old then
		old:Destroy()
	end

	local assetId = DOOR_DASH_VEHICLE_ASSET_IDS[vehicleTier]
	if not assetId then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	local vehicle = ok and container and container:FindFirstChildOfClass("Model")
	if container then
		if vehicle then
			vehicle.Parent = nil
		end
		container:Destroy()
	end
	if not vehicle then
		warn("[IncomeSourceService] Failed to load DoorDash vehicle tier " .. vehicleTier .. " asset")
		return nil
	end

	vehicle.Name = "VehicleHero"

	-- Some Toolbox vehicle listings (the Delivery Van in particular) are
	-- full drivable-car kits with embedded chassis Scripts, seats, and
	-- sounds - strip all of that BEFORE parenting into the live game so
	-- those scripts never get a chance to start. This is meant to be an
	-- inert decorative hero prop, not a functional vehicle.
	for _, descendant in ipairs(vehicle:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Seat") or descendant:IsA("VehicleSeat") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end

	vehicle.Parent = areaModel
	for _, part in ipairs(vehicle:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local _, sizeBeforeScale = vehicle:GetBoundingBox()
	local targetHeight = DOOR_DASH_VEHICLE_TARGET_HEIGHTS[vehicleTier] or 6
	vehicle:ScaleTo(targetHeight / sizeBeforeScale.Y)

	local hoverHeight = DOOR_DASH_VEHICLE_HOVER_HEIGHTS[vehicleTier]
	local _, finalSize = vehicle:GetBoundingBox()
	local groundY = hoverHeight or (finalSize.Y / 2)
	recenterModel(vehicle, CFrame.new(origin + Vector3.new(0, groundY, -22)))

	return vehicle
end

local function refreshDoorDashVehicleKioskDisplay(player: Player, statusLabel: TextLabel, prompt: ProximityPrompt)
	local state = EconomyService.GetDoorDashState(player)
	renderTierKioskDisplay(Config.DoorDash.vehicleTiers[state.vehicleTier + 1], statusLabel, prompt)
end

-- Standalone (not just a Triggered closure) so it's directly callable, same
-- as the Value/Speed/Manager Attempt* functions.
function IncomeSourceService.AttemptDoorDashVehicleUpgrade(
	player: Player,
	areaModel: Model,
	origin: Vector3,
	vehicleFloor: BasePart,
	board: BasePart,
	statusLabel: TextLabel,
	prompt: ProximityPrompt
): boolean
	local state = EconomyService.GetDoorDashState(player)
	local nextTier = Config.DoorDash.vehicleTiers[state.vehicleTier + 1]
	if not nextTier then
		return false
	end
	if not EconomyService.CanAfford(player, nextTier.cost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(nextTier.cost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, nextTier.cost) then
		return false
	end
	local newVehicleTier = state.vehicleTier + 1
	EconomyService.UpdateDoorDash(player, { vehicleTier = newVehicleTier })

	if nextTier.extraHouses then
		IncomeSourceService.AddDoorDashExtraHouses(player, nextTier.extraHouses)
	end

	local vehicle = buildDoorDashVehicleHero(areaModel, origin, newVehicleTier)
	refreshDoorDashVehicleKioskDisplay(player, statusLabel, prompt)
	refreshDoorDashHousePrompts(player)

	PurchaseEffects.ApplyOwnedVisuals({
		zoneModel = areaModel,
		floor = vehicleFloor,
		hero = (vehicle :: Model) or vehicleFloor,
		ownedColor = Theme.CashPositive,
		animate = true,
		buyer = player,
		resultText = nextTier.name .. " UNLOCKED!",
		resultColor = Theme.Gold,
	})
	return true
end

local function buildDoorDashNeighborhood(player: Player, areaModel: Model, origin: Vector3, vehicleFloor: BasePart)
	local startX = -((DOOR_DASH_HOUSE_COUNT - 1) * DOOR_DASH_HOUSE_SPACING) / 2
	local houseParts = {}
	for i = 1, DOOR_DASH_HOUSE_COUNT do
		local position = origin + Vector3.new(startX + (i - 1) * DOOR_DASH_HOUSE_SPACING, 4, -30)
		table.insert(houseParts, buildHouseAt(player, areaModel, position, i))
	end

	buildDroppedCup(houseParts[2], areaModel)
	buildStringLights(areaModel, houseParts)
	buildMopedHero(areaModel, origin + Vector3.new(0, 0, -22))

	doorDashPlots[player] = { folder = areaModel.Parent :: Folder, origin = origin, houses = houseParts }

	if EconomyService.GetNeighborhoodTier(player) > 0 then
		applyNeighborhoodUpgradeVisuals(areaModel, origin)
	end

	local state = EconomyService.GetDoorDashState(player)
	local extraCount = state.houseCount - DOOR_DASH_HOUSE_COUNT
	if extraCount > 0 then
		IncomeSourceService.AddDoorDashExtraHouses(player, extraCount)
	end

	-- Rejoin with a vehicle tier already bought: replace the moped that was
	-- just built above with whichever vehicle the player currently owns.
	if state.vehicleTier > 0 then
		buildDoorDashVehicleHero(areaModel, origin, state.vehicleTier)
	end

	local valueBoard, valueStatus, valuePrompt = buildTierKiosk(areaModel, origin + Vector3.new(-24, 0, -24), "Value", Theme.Brand)
	refreshDoorDashValueKioskDisplay(player, valueStatus, valuePrompt)
	valuePrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDoorDashValueUpgrade(player, valueBoard, valueStatus, valuePrompt)
	end)

	local speedBoard, speedStatus, speedPrompt = buildTierKiosk(areaModel, origin + Vector3.new(24, 0, -24), "Speed", Theme.Secondary)
	refreshDoorDashSpeedKioskDisplay(player, speedStatus, speedPrompt)
	speedPrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDoorDashSpeedUpgrade(player, speedBoard, speedStatus, speedPrompt)
	end)

	local managerBoard, managerStatus, managerPrompt = buildTierKiosk(areaModel, origin + Vector3.new(-8, 0, -24), "Manager", Theme.Gold)
	if state.hasManager then
		managerStatus.Text = "HIRED"
		managerPrompt.Enabled = false
		buildDispatcherNpc(areaModel, origin)
		IncomeSourceService.StartDoorDashManagerLoops(player)
	else
		managerStatus.Text = "Hire a Dispatcher\n$" .. NumberFormatter.Format(Config.DoorDash.managerCost)
		managerPrompt.ActionText = "Hire"
		managerPrompt.ObjectText = "Hire a Dispatcher ($" .. NumberFormatter.Format(Config.DoorDash.managerCost) .. ")"
	end
	managerPrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDoorDashManagerHire(player, areaModel, origin, managerBoard, managerStatus, managerPrompt)
	end)

	local vehicleBoard, vehicleStatus, vehiclePrompt = buildTierKiosk(areaModel, origin + Vector3.new(8, 0, -24), "Vehicle", Theme.AffordablePulse)
	refreshDoorDashVehicleKioskDisplay(player, vehicleStatus, vehiclePrompt)
	vehiclePrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDoorDashVehicleUpgrade(player, areaModel, origin, vehicleFloor, vehicleBoard, vehicleStatus, vehiclePrompt)
	end)

	refreshDoorDashHousePrompts(player)
end

-- DoorDash is now a cash-gated unlock inside the shared per-plot
-- neighborhood (swapped roles with Dog Walking) rather than the always-free
-- starter. Mirrors ZoneService's locked-floor + price tag + hold-to-confirm
-- prompt pattern, scoped to one player's own plot instead of a shared world
-- zone, and routes through the same PurchaseEffects money-shot on unlock.
function IncomeSourceService.SetupPlayerDoorDash(player: Player, folder: Folder, origin: Vector3)
	local areaModel = Instance.new("Model")
	areaModel.Name = "DoorDashArea"
	areaModel.Parent = folder

	-- This floor is always built (owned or not) - once unlocked it becomes
	-- the permanent "vehicle bay" pad the Phase 4 vehicle tier upgrades
	-- reveal their new hero against, reusing the same money-shot floor
	-- rather than building a separate one per vehicle tier.
	local unlockFloor = Instance.new("Part")
	unlockFloor.Name = "Floor"
	unlockFloor.Anchored = true
	unlockFloor.CanCollide = false
	unlockFloor.Size = Vector3.new(10, 1, 10)
	unlockFloor.Position = origin + Vector3.new(0, 0.5, -18)
	unlockFloor.Material = Enum.Material.Neon
	unlockFloor.Parent = areaModel

	if EconomyService.IsZoneOwned(player, "doordash") then
		unlockFloor.Color = Theme.CashPositive
		unlockFloor.Transparency = 0
		buildDoorDashNeighborhood(player, areaModel, origin, unlockFloor)
		return
	end

	unlockFloor.Color = Theme.Locked
	unlockFloor.Transparency = 0.5

	local priceGui = Instance.new("BillboardGui")
	priceGui.Name = "PriceTag"
	priceGui.Adornee = unlockFloor
	priceGui.Size = UDim2.new(0, 220, 0, 72)
	priceGui.StudsOffset = Vector3.new(0, 5, 0)
	priceGui.AlwaysOnTop = true
	priceGui.MaxDistance = 100
	priceGui.Parent = unlockFloor

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = "DoorDash Runs"
	nameLabel.Parent = priceGui

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.BackgroundTransparency = 1
	priceLabel.Position = UDim2.fromScale(0, 0.5)
	priceLabel.Size = UDim2.new(1, 0, 0.5, 0)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextScaled = true
	priceLabel.TextColor3 = Theme.Gold
	priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	priceLabel.TextStrokeTransparency = 0.3
	priceLabel.Text = "$" .. NumberFormatter.Format(Config.DoorDash.unlockCost)
	priceLabel.Parent = priceGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Unlock"
	prompt.ObjectText = "DoorDash Runs ($" .. NumberFormatter.Format(Config.DoorDash.unlockCost) .. ")"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = unlockFloor

	prompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDoorDashUnlock(player, areaModel, unlockFloor, priceGui, prompt, origin)
	end)
end

-- Standalone (not just a Triggered closure) so it's directly callable, same
-- as ZoneService.AttemptPurchase / HandleDoorDashDelivery.
function IncomeSourceService.AttemptDoorDashUnlock(
	player: Player,
	areaModel: Model,
	unlockFloor: BasePart,
	priceGui: BillboardGui,
	prompt: ProximityPrompt,
	origin: Vector3
): boolean
	if EconomyService.IsZoneOwned(player, "doordash") then
		return false
	end
	if not EconomyService.CanAfford(player, Config.DoorDash.unlockCost) then
		FloatingText.Show(unlockFloor, "Need $" .. NumberFormatter.Format(Config.DoorDash.unlockCost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, Config.DoorDash.unlockCost) then
		return false
	end
	EconomyService.MarkZoneOwned(player, "doordash")

	priceGui:Destroy()
	prompt.Enabled = false
	buildDoorDashNeighborhood(player, areaModel, origin, unlockFloor)

	local moped = areaModel:FindFirstChild("MopedHero")
	PurchaseEffects.ApplyOwnedVisuals({
		zoneModel = areaModel,
		floor = unlockFloor,
		hero = (moped :: Model) or unlockFloor,
		ownedColor = Theme.CashPositive,
		animate = true,
		buyer = player,
		resultText = "DOORDASH UNLOCKED!",
		resultColor = Theme.CashPositive,
	})
	return true
end

function IncomeSourceService.CleanupPlayerDoorDash(player: Player)
	doorDashCooldowns[player] = nil
	doorDashManagerActive[player] = nil
	doorDashPlots[player] = nil
end

function IncomeSourceService.Init()
	Players.PlayerRemoving:Connect(function(player)
		rideshareCooldowns[player] = nil
		IncomeSourceService.CleanupPlayerDogWalking(player)
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
		-- Rideshare is a shared-world zone (no per-player-plot), but
		-- ownership is still tracked per-player - only someone who has
		-- personally bought this zone can collect from the shared Hero,
		-- not any passerby.
		if not EconomyService.IsZoneOwned(player, "rideshare") then
			return
		end
		if not checkCooldown(rideshareCooldowns, player, triggerPart :: BasePart, Config.Rideshare.cooldown) then
			return
		end
		payReward(player, triggerPart :: BasePart, Config.Rideshare.rewardPerLoop)
	end)
end

--------------------------------------------------------------------------------
-- DOG WALKING (always-free per-plot starter — swapped roles with DoorDash)
--------------------------------------------------------------------------------

-- state.valueTier/speedTier (0 = none) index directly into the tier arrays
-- (1-based) - tier N bought means valueTiers[N] is the active tier. Reads
-- live every payout so kiosk purchases and the (future) Neighborhood
-- Upgrade apply immediately without touching this call site again.
local function getDogWalkingCooldown(player: Player): number
	local state = EconomyService.GetDogWalkingState(player)
	local tier = state and Config.DogWalking.speedTiers[state.speedTier]
	return tier and tier.cooldown or Config.DogWalking.cooldown
end

local function getDogWalkingReward(player: Player): number
	local state = EconomyService.GetDogWalkingState(player)
	local valueTier = state and Config.DogWalking.valueTiers[state.valueTier]
	local valueMultiplier = valueTier and valueTier.multiplier or 1
	local neighborhoodMultiplier = if EconomyService.GetNeighborhoodTier(player) > 0
		then Config.Neighborhood.upgradeMultiplier
		else 1
	-- Fractional multipliers (1.5x etc.) on an integer base would otherwise
	-- pay out fractional cash ($22.5) - round to whole dollars.
	return math.floor(Config.DogWalking.rewardPerLoop * valueMultiplier * neighborhoodMultiplier + 0.5)
end

local function refreshDogWalkingPromptText(player: Player)
	local plot = dogWalkingPlots[player]
	if not plot or not plot.post then
		return
	end
	local gui = plot.post:FindFirstChild("ClickLabel")
	local label = gui and gui:FindFirstChild("Label")
	if label then
		(label :: TextLabel).Text = "Click to Walk\n(+$" .. getDogWalkingReward(player) .. ")"
	end
end

-- Standalone (not just a Triggered closure) so it's directly callable, same
-- as HandleDoorDashDelivery.
function IncomeSourceService.HandleDogWalkingDelivery(player: Player, post: BasePart): number?
	if not checkCooldown(dogWalkingCooldowns, player, post, getDogWalkingCooldown(player)) then
		return nil
	end
	local reward = getDogWalkingReward(player)
	payReward(player, post, reward)
	return reward
end

-- LeashPost (built by BuildDogWalkingHero) is the clickable part - a simple
-- click-and-collect button (ClickDetector) rather than a walk-up-and-hold-E
-- prompt, so the manual step reads as "click a button" like Sell Lemons'
-- lemon stand rather than "walk to a delivery location". Owner-gated like
-- DoorDash's houses since this lives in the player's own plot.
function IncomeSourceService.ActivateDogWalking(player: Player, hero: Model): ClickDetector?
	local post = hero:FindFirstChild("LeashPost") :: BasePart?
	if not post or post:FindFirstChildOfClass("ClickDetector") then
		return nil
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 16
	clickDetector.Parent = post

	local gui = Instance.new("BillboardGui")
	gui.Name = "ClickLabel"
	gui.Adornee = post
	gui.Size = UDim2.new(0, 150, 0, 56)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = post

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextWrapped = true
	label.Text = "Click to Walk\n(+$" .. getDogWalkingReward(player) .. ")"
	label.Parent = gui

	clickDetector.MouseClick:Connect(function(clicker)
		if clicker ~= player then
			return
		end
		IncomeSourceService.HandleDogWalkingDelivery(player, post)
	end)

	return clickDetector
end

-- One physical sign per track (Value / Speed) rather than a multi-button
-- menu - reuses the same single-ProximityPrompt hold-to-confirm purchase
-- pattern as everything else. Triggering buys whichever tier is next in
-- that track's list; the sign re-renders to the tier after that, or "MAXED".
-- Generic tier-upgrade kiosk builder - one physical sign per track rather
-- than a multi-button menu, reused by both Dog Walking and DoorDash (and
-- any future hustle that gets this same Value/Speed pattern).
local function refreshValueKioskDisplay(player: Player, statusLabel: TextLabel, prompt: ProximityPrompt)
	local state = EconomyService.GetDogWalkingState(player)
	renderTierKioskDisplay(Config.DogWalking.valueTiers[state.valueTier + 1], statusLabel, prompt)
end

local function refreshSpeedKioskDisplay(player: Player, statusLabel: TextLabel, prompt: ProximityPrompt)
	local state = EconomyService.GetDogWalkingState(player)
	renderTierKioskDisplay(Config.DogWalking.speedTiers[state.speedTier + 1], statusLabel, prompt)
end

-- Standalone (not just a Triggered closure) so it's directly callable, same
-- as ZoneService.AttemptPurchase / AttemptDoorDashUnlock.
function IncomeSourceService.AttemptDogWalkingValueUpgrade(player: Player, board: BasePart, statusLabel: TextLabel, prompt: ProximityPrompt): boolean
	local state = EconomyService.GetDogWalkingState(player)
	local nextTier = Config.DogWalking.valueTiers[state.valueTier + 1]
	if not nextTier then
		return false
	end
	if not EconomyService.CanAfford(player, nextTier.cost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(nextTier.cost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, nextTier.cost) then
		return false
	end
	EconomyService.UpdateDogWalking(player, { valueTier = state.valueTier + 1 })
	FloatingText.Show(board, nextTier.name .. "!", Theme.CashPositive)
	refreshValueKioskDisplay(player, statusLabel, prompt)
	refreshDogWalkingPromptText(player)
	return true
end

function IncomeSourceService.AttemptDogWalkingSpeedUpgrade(player: Player, board: BasePart, statusLabel: TextLabel, prompt: ProximityPrompt): boolean
	local state = EconomyService.GetDogWalkingState(player)
	local nextTier = Config.DogWalking.speedTiers[state.speedTier + 1]
	if not nextTier then
		return false
	end
	if not EconomyService.CanAfford(player, nextTier.cost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(nextTier.cost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, nextTier.cost) then
		return false
	end
	EconomyService.UpdateDogWalking(player, { speedTier = state.speedTier + 1 })
	FloatingText.Show(board, nextTier.name .. "!", Theme.CashPositive)
	refreshSpeedKioskDisplay(player, statusLabel, prompt)
	return true
end

-- The "Dog Walker" hired NPC: a primitive blocky figure with a 4th leashed
-- dog, pacing a short loop near the station so automation feels alive
-- without any pathfinding.
local function buildDogWalkerNpc(folder: Instance, base: Vector3): Model
	local npc = Instance.new("Model")
	npc.Name = "DogWalkerNpc"
	npc.Parent = folder

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Anchored = true
	torso.CanCollide = false
	torso.Material = Enum.Material.SmoothPlastic
	torso.Color = Theme.Secondary
	torso.Size = Vector3.new(1.4, 2, 0.8)
	torso.CFrame = CFrame.new(base + Vector3.new(-4, 3, -2))
	torso.Parent = npc
	npc.PrimaryPart = torso

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Anchored = true
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(255, 213, 170)
	head.Size = Vector3.new(1, 1, 1)
	head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = npc

	for _, side in ipairs({ -1, 1 }) do
		local leg = Instance.new("Part")
		leg.Name = "Leg"
		leg.Anchored = true
		leg.CanCollide = false
		leg.Material = Enum.Material.SmoothPlastic
		leg.Color = Color3.fromRGB(40, 40, 45)
		leg.Size = Vector3.new(0.5, 1.6, 0.6)
		leg.CFrame = torso.CFrame * CFrame.new(side * 0.35, -1.8, 0)
		leg.Parent = npc
	end

	local dog = loadDogModel()
	if dog then
		dog.Name = "WalkerDog"
		dog.Parent = npc
		scaleAndPositionDog(dog, base + Vector3.new(-5.5, 0, -2), math.rad(90))
	end

	local pointA = torso.CFrame
	local pointB = torso.CFrame * CFrame.new(9, 0, 0)
	loopModelBetweenPoints(npc, pointA, pointB, 4)

	return npc
end

function IncomeSourceService.AttemptDogWalkingManagerHire(
	player: Player,
	folder: Instance,
	base: Vector3,
	post: BasePart,
	board: BasePart,
	statusLabel: TextLabel,
	prompt: ProximityPrompt
): boolean
	local state = EconomyService.GetDogWalkingState(player)
	if state.hasManager then
		return false
	end
	if not EconomyService.CanAfford(player, Config.DogWalking.managerCost) then
		FloatingText.Show(board, "Need $" .. NumberFormatter.Format(Config.DogWalking.managerCost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, Config.DogWalking.managerCost) then
		return false
	end
	EconomyService.UpdateDogWalking(player, { hasManager = true })

	statusLabel.Text = "HIRED"
	prompt.Enabled = false
	FloatingText.Show(board, "Dog Walker Hired!", Theme.CashPositive)

	buildDogWalkerNpc(folder, base)
	IncomeSourceService.StartDogWalkingManagerLoop(player, post)
	return true
end

-- Auto-collect loop: fires HandleDogWalkingDelivery on the Speed track's
-- current cooldown. Manual E-presses route through the same function and
-- share the same cooldown table (checkCooldown), so whichever fires first -
-- manual or auto - simply resets that station's own timer; no double-pay.
function IncomeSourceService.StartDogWalkingManagerLoop(player: Player, post: BasePart)
	if dogWalkingManagerActive[player] then
		return
	end
	dogWalkingManagerActive[player] = true
	task.spawn(function()
		while dogWalkingManagerActive[player] and player.Parent do
			task.wait(getDogWalkingCooldown(player))
			if not (dogWalkingManagerActive[player] and player.Parent) then
				break
			end
			IncomeSourceService.HandleDogWalkingDelivery(player, post)
		end
	end)
end

-- Builds the always-free Dog Walking station + its Value/Speed/Manager
-- kiosks in a player's shared neighborhood plot — no purchase to unlock the
-- station itself, available the moment the plot exists.
function IncomeSourceService.SetupPlayerDogWalking(player: Player, folder: Folder, origin: Vector3)
	local base = origin + Vector3.new(0, 0, 15)
	local hero = IncomeSourceService.BuildDogWalkingHero(folder, base)
	IncomeSourceService.ActivateDogWalking(player, hero)
	local post = hero:FindFirstChild("LeashPost") :: BasePart?
	dogWalkingPlots[player] = { folder = folder, origin = origin, hero = hero, post = post }

	local valueBoard, valueStatus, valuePrompt = buildTierKiosk(folder, base + Vector3.new(-8, 0, 5), "Value", Theme.Brand)
	refreshValueKioskDisplay(player, valueStatus, valuePrompt)
	valuePrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDogWalkingValueUpgrade(player, valueBoard, valueStatus, valuePrompt)
	end)

	local speedBoard, speedStatus, speedPrompt = buildTierKiosk(folder, base + Vector3.new(8, 0, 5), "Speed", Theme.Secondary)
	refreshSpeedKioskDisplay(player, speedStatus, speedPrompt)
	speedPrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDogWalkingSpeedUpgrade(player, speedBoard, speedStatus, speedPrompt)
	end)

	local managerBoard, managerStatus, managerPrompt = buildTierKiosk(folder, base + Vector3.new(0, 0, 5), "Manager", Theme.Gold)
	local dogWalkingState = EconomyService.GetDogWalkingState(player)
	local post = hero:FindFirstChild("LeashPost") :: BasePart
	if dogWalkingState.hasManager then
		managerStatus.Text = "HIRED"
		managerPrompt.Enabled = false
		buildDogWalkerNpc(folder, base)
		IncomeSourceService.StartDogWalkingManagerLoop(player, post)
	else
		managerStatus.Text = "Hire a Dog Walker\n$" .. NumberFormatter.Format(Config.DogWalking.managerCost)
		managerPrompt.ActionText = "Hire"
		managerPrompt.ObjectText = "Hire a Dog Walker ($" .. NumberFormatter.Format(Config.DogWalking.managerCost) .. ")"
	end
	managerPrompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptDogWalkingManagerHire(player, folder, base, post, managerBoard, managerStatus, managerPrompt)
	end)
end

function IncomeSourceService.CleanupPlayerDogWalking(player: Player)
	dogWalkingCooldowns[player] = nil
	dogWalkingManagerActive[player] = nil
	dogWalkingPlots[player] = nil
end

--------------------------------------------------------------------------------
-- NEIGHBORHOOD UPGRADE (Phase 4 scale - shared by Dog Walking + DoorDash)
--------------------------------------------------------------------------------

-- Standalone (not just a Triggered closure) so it's directly callable, same
-- as AttemptDoorDashUnlock / AttemptDogWalkingValueUpgrade.
function IncomeSourceService.AttemptNeighborhoodUpgrade(
	player: Player,
	areaModel: Model,
	origin: Vector3,
	unlockFloor: BasePart,
	priceGui: BillboardGui,
	prompt: ProximityPrompt
): boolean
	if EconomyService.GetNeighborhoodTier(player) > 0 then
		return false
	end
	if not EconomyService.CanAfford(player, Config.Neighborhood.upgradeCost) then
		FloatingText.Show(unlockFloor, "Need $" .. NumberFormatter.Format(Config.Neighborhood.upgradeCost) .. "!", Theme.Warning)
		return false
	end
	if not EconomyService.RemoveCash(player, Config.Neighborhood.upgradeCost) then
		return false
	end
	EconomyService.SetNeighborhoodTier(player, 1)

	priceGui:Destroy()
	prompt.Enabled = false
	refreshDogWalkingPromptText(player)

	local plot = doorDashPlots[player]
	local doorDashArea = plot and (plot.folder:FindFirstChild("DoorDashArea") :: Instance)
	local hero = doorDashArea and doorDashArea:FindFirstChild("MopedHero")
	if doorDashArea then
		applyNeighborhoodUpgradeVisuals(doorDashArea, origin)
	end
	PurchaseEffects.ApplyOwnedVisuals({
		zoneModel = areaModel,
		floor = unlockFloor,
		hero = (hero :: Model) or unlockFloor,
		ownedColor = Theme.Gold,
		animate = true,
		buyer = player,
		resultText = "NEIGHBORHOOD UPGRADED!",
		resultColor = Theme.Gold,
	})
	return true
end

-- One-time shared purchase (locked floor + price tag + hold-to-confirm
-- prompt, same pattern as DoorDash's unlock) sitting between the Dog
-- Walking and DoorDash areas since it boosts both.
function IncomeSourceService.SetupPlayerNeighborhoodUpgrade(player: Player, folder: Folder, origin: Vector3)
	local areaModel = Instance.new("Model")
	areaModel.Name = "NeighborhoodUpgradeArea"
	areaModel.Parent = folder

	if EconomyService.GetNeighborhoodTier(player) > 0 then
		return
	end

	local unlockFloor = Instance.new("Part")
	unlockFloor.Name = "Floor"
	unlockFloor.Anchored = true
	unlockFloor.CanCollide = false
	unlockFloor.Size = Vector3.new(8, 1, 8)
	unlockFloor.Position = origin + Vector3.new(0, 0.5, -3)
	unlockFloor.Color = Theme.Locked
	unlockFloor.Material = Enum.Material.Neon
	unlockFloor.Transparency = 0.5
	unlockFloor.Parent = areaModel

	local priceGui = Instance.new("BillboardGui")
	priceGui.Name = "PriceTag"
	priceGui.Adornee = unlockFloor
	priceGui.Size = UDim2.new(0, 220, 0, 72)
	priceGui.StudsOffset = Vector3.new(0, 5, 0)
	priceGui.AlwaysOnTop = true
	priceGui.MaxDistance = 100
	priceGui.Parent = unlockFloor

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = "Neighborhood Upgrade"
	nameLabel.Parent = priceGui

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.BackgroundTransparency = 1
	priceLabel.Position = UDim2.fromScale(0, 0.5)
	priceLabel.Size = UDim2.new(1, 0, 0.5, 0)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextScaled = true
	priceLabel.TextColor3 = Theme.Gold
	priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	priceLabel.TextStrokeTransparency = 0.3
	priceLabel.Text = "$" .. NumberFormatter.Format(Config.Neighborhood.upgradeCost)
	priceLabel.Parent = priceGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Upgrade"
	prompt.ObjectText = "Neighborhood Upgrade ($" .. NumberFormatter.Format(Config.Neighborhood.upgradeCost) .. ")"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = unlockFloor

	prompt.Triggered:Connect(function(triggeredBy)
		if triggeredBy ~= player then
			return
		end
		IncomeSourceService.AttemptNeighborhoodUpgrade(player, areaModel, origin, unlockFloor, priceGui, prompt)
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
