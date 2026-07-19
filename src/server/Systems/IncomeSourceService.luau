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

local RIDESHARE_CAR_COLOR = Color3.fromRGB(220, 60, 60)
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
	moped:PivotTo(CFrame.new(position + Vector3.new(0, size.Y / 2, 0)))

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

function IncomeSourceService.ActivateRideshare(zoneFloor: BasePart)
	local zoneModel = zoneFloor.Parent
	if not zoneModel or zoneModel:FindFirstChild("RideshareCar") then
		return
	end

	local car = Instance.new("Part")
	car.Name = "RideshareCar"
	car.Anchored = true
	car.CanCollide = true
	car.Size = Vector3.new(6, 3, 10)
	car.Color = RIDESHARE_CAR_COLOR
	car.Material = Enum.Material.Neon
	car.Position = zoneFloor.Position + Vector3.new(0, 3, 0)
	car.Parent = zoneModel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.ObjectText = "Rideshare (+$" .. Config.Rideshare.rewardPerLoop .. ")"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = car

	prompt.Triggered:Connect(function(player)
		if not checkCooldown(rideshareCooldowns, player, car, Config.Rideshare.cooldown) then
			return
		end
		payReward(player, car, Config.Rideshare.rewardPerLoop)
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
