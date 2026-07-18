-- Manages the 5 Planet Hustle income sources (DoorDash, Rideshare, Lottery,
-- Dog Walking, Freelance Gig Hub) and the player's live income/sec stat.
-- DoorDash Runs (Step 4) live here. Rideshare + Dog Walking + Freelance Gig
-- Hub follow the same pattern in Step 6; Lottery is Step 7.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local EconomyService = require(script.Parent.EconomyService)

local DOOR_DASH_HOUSE_COUNT = 4
local DOOR_DASH_HOUSE_SPACING = 20
local DOOR_DASH_HOUSE_COLOR = Color3.fromRGB(140, 90, 60)
local DOOR_DASH_FLASH_COLOR = Color3.fromRGB(90, 255, 120)

local IncomeSourceService = {}

-- doorDashCooldowns[player][house] = os.clock() expiry
local doorDashCooldowns: { [Player]: { [BasePart]: number } } = {}

local function getStatsFolder(player: Player): Folder?
	return player:FindFirstChild("PlanetHustleStats")
end

local function pulseHouse(house: BasePart)
	local original = house.Color
	local up = TweenService:Create(house, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { Color = DOOR_DASH_FLASH_COLOR })
	up:Play()
	up.Completed:Wait()
	TweenService:Create(house, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Color = original }):Play()
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

-- Called by each house's ProximityPrompt.Triggered. Returns the reward paid,
-- or nil when the player is still within the per-house cooldown.
function IncomeSourceService.HandleDoorDashDelivery(player: Player, house: BasePart): number?
	local now = os.clock()
	local playerCooldowns = doorDashCooldowns[player]
	if playerCooldowns and playerCooldowns[house] and now < playerCooldowns[house] then
		return nil
	end
	doorDashCooldowns[player] = doorDashCooldowns[player] or {}
	doorDashCooldowns[player][house] = now + Config.DoorDash.cooldown

	local reward = math.random(Config.DoorDash.minReward, Config.DoorDash.maxReward)
	EconomyService.AddCash(player, reward)
	task.spawn(pulseHouse, house)
	return reward
end

return IncomeSourceService
