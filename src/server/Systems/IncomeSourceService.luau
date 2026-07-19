-- Manages the 5 Planet Hustle income sources and the player's live income/sec
-- stat. DoorDash (Step 4) is always unlocked; Rideshare / Dog Walking /
-- Freelance Gig Hub (Step 6) are activated by ZoneService on zone purchase;
-- Lottery (Step 7) lives in LotteryService but uses the same station pattern.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local EconomyService = require(script.Parent.EconomyService)

local DOOR_DASH_HOUSE_COUNT = 4
local DOOR_DASH_HOUSE_SPACING = 20
local DOOR_DASH_HOUSE_COLOR = Color3.fromRGB(140, 90, 60)
local FLASH_COLOR = Color3.fromRGB(90, 255, 120)

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

local function showFloatingReward(anchor: BasePart, reward: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatingReward"
	gui.Adornee = anchor
	gui.Size = UDim2.new(0, 120, 0, 48)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(85, 255, 127)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Text = "+$" .. reward
	label.Parent = gui

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 9, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.85, function()
		gui:Destroy()
	end)
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
	showFloatingReward(station, reward)
end

--------------------------------------------------------------------------------
-- LIFECYCLE / STAT PLUMBING
--------------------------------------------------------------------------------

local function spawnDoorDashHouses(): Folder
	local existing = workspace:FindFirstChild("DoorDashHouses")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DoorDashHouses"
	folder.Parent = workspace

	local startX = -((DOOR_DASH_HOUSE_COUNT - 1) * DOOR_DASH_HOUSE_SPACING) / 2
	for i = 1, DOOR_DASH_HOUSE_COUNT do
		local house = Instance.new("Part")
		house.Name = "DoorDashHouse_" .. i
		house.Size = Vector3.new(8, 8, 8)
		house.Anchored = true
		house.Position = Vector3.new(startX + (i - 1) * DOOR_DASH_HOUSE_SPACING, 4, -30)
		house.Color = DOOR_DASH_HOUSE_COLOR
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
	end
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
