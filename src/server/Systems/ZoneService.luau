-- Purchasable zones: locked floor + name/price BillboardGui + ProximityPrompt
-- (HoldDuration 0.5 = confirm-by-hold, native equivalent of a Y/N prompt).
-- On buy: EconomyService debit + MarkZoneOwned + build animation +
-- zone.onPurchase callback for hustle-specific activation.
--
-- Zones registered here: Rideshare, Dog Walking, Freelance Gig Hub (Step 6),
-- Lottery Ticket Booth (Step 7). DoorDash isn't a zone (always unlocked) —
-- IncomeSourceService spawns those houses at server init.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local EconomyService = require(script.Parent.EconomyService)
local IncomeSourceService = require(script.Parent.IncomeSourceService)
local LotteryService = require(script.Parent.LotteryService)
local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local ZoneService = {}

type ZoneDef = {
	id: string,
	name: string,
	price: number,
	position: Vector3,
	size: Vector3,
	lockedColor: Color3,
	ownedColor: Color3,
	onPurchase: ((owner: Player, zoneFloor: BasePart) -> ())?,
}

local ZONES: { ZoneDef } = {
	{
		id = "rideshare",
		name = "Rideshare Runs",
		price = Config.Rideshare.unlockCost,
		position = Vector3.new(0, 0.5, 50),
		size = Vector3.new(12, 1, 12),
		lockedColor = Color3.fromRGB(90, 50, 50),
		ownedColor = Color3.fromRGB(220, 90, 90),
		onPurchase = function(_owner, zoneFloor)
			IncomeSourceService.ActivateRideshare(zoneFloor)
		end,
	},
	{
		id = "lottery",
		name = "Lottery Ticket Booth",
		price = Config.Lottery.unlockCost,
		position = Vector3.new(-50, 0.5, 0),
		size = Vector3.new(12, 1, 12),
		lockedColor = Color3.fromRGB(70, 40, 90),
		ownedColor = Color3.fromRGB(180, 90, 220),
		onPurchase = function(_owner, zoneFloor)
			LotteryService.ActivateBooth(zoneFloor)
		end,
	},
	{
		id = "dog_walking",
		name = "Dog Walking Service",
		price = Config.DogWalking.unlockCost,
		position = Vector3.new(50, 0.5, 50),
		size = Vector3.new(12, 1, 12),
		lockedColor = Color3.fromRGB(90, 70, 40),
		ownedColor = Color3.fromRGB(200, 160, 100),
		onPurchase = function(_owner, zoneFloor)
			IncomeSourceService.ActivateDogWalking(zoneFloor)
		end,
	},
	{
		id = "freelance_gig_hub",
		name = "Freelance Gig Hub",
		price = Config.FreelanceGigHub.unlockCost,
		position = Vector3.new(-50, 0.5, 50),
		size = Vector3.new(12, 1, 12),
		lockedColor = Color3.fromRGB(50, 70, 90),
		ownedColor = Color3.fromRGB(100, 180, 240),
		onPurchase = function(owner, _zoneFloor)
			IncomeSourceService.ActivateFreelanceHub(owner)
		end,
	},
}

local zoneById: { [string]: ZoneDef } = {}
for _, z in ipairs(ZONES) do
	zoneById[z.id] = z
end

local zoneFloors: { [string]: BasePart } = {}

local function showFloatingText(anchor: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatingText"
	gui.Adornee = anchor
	gui.Size = UDim2.new(0, 160, 0, 56)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 9, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.95, function()
		gui:Destroy()
	end)
end

local function applyOwnedVisuals(floor: BasePart, zone: ZoneDef, animate: boolean)
	local priceTag = floor:FindFirstChild("PriceTag")
	if priceTag then
		priceTag:Destroy()
	end
	local prompt = floor:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	local existing = floor.Parent and floor.Parent:FindFirstChild("Building")
	if existing then
		return
	end

	local building = Instance.new("Part")
	building.Name = "Building"
	building.Anchored = true
	building.CanCollide = true
	building.Material = Enum.Material.Neon
	building.Color = zone.ownedColor
	building.Position = floor.Position + Vector3.new(0, 4.5, 0)
	building.Parent = floor.Parent

	if animate then
		building.Size = Vector3.new(0.2, 0.2, 0.2)
		local target = Vector3.new(zone.size.X * 0.5, 8, zone.size.Z * 0.5)
		local info = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(building, info, { Size = target }):Play()
		TweenService:Create(floor, TweenInfo.new(0.3), {
			Transparency = 0,
			Color = zone.ownedColor,
		}):Play()
	else
		building.Size = Vector3.new(zone.size.X * 0.5, 8, zone.size.Z * 0.5)
		floor.Transparency = 0
		floor.Color = zone.ownedColor
	end
end

local function spawnZone(zone: ZoneDef)
	local model = Instance.new("Model")
	model.Name = "Zone_" .. zone.id
	model.Parent = workspace

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.Size = zone.size
	floor.Position = zone.position
	floor.Color = zone.lockedColor
	floor.Material = Enum.Material.Neon
	floor.Transparency = 0.5
	floor.Parent = model

	local priceGui = Instance.new("BillboardGui")
	priceGui.Name = "PriceTag"
	priceGui.Adornee = floor
	priceGui.Size = UDim2.new(0, 220, 0, 72)
	priceGui.StudsOffset = Vector3.new(0, 5, 0)
	priceGui.AlwaysOnTop = true
	priceGui.MaxDistance = 100
	priceGui.Parent = floor

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
	nameLabel.Text = zone.name
	nameLabel.Parent = priceGui

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.BackgroundTransparency = 1
	priceLabel.Position = UDim2.fromScale(0, 0.5)
	priceLabel.Size = UDim2.new(1, 0, 0.5, 0)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextScaled = true
	priceLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	priceLabel.TextStrokeTransparency = 0.3
	priceLabel.Text = "$" .. NumberFormatter.Format(zone.price)
	priceLabel.Parent = priceGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy"
	prompt.ObjectText = zone.name .. " ($" .. NumberFormatter.Format(zone.price) .. ")"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = floor

	prompt.Triggered:Connect(function(player)
		ZoneService.AttemptPurchase(player, zone.id)
	end)

	zoneFloors[zone.id] = floor
end

function ZoneService.Init()
	for _, zone in ipairs(ZONES) do
		spawnZone(zone)
	end
end

function ZoneService.IsOwned(player: Player, zoneId: string): boolean
	return EconomyService.IsZoneOwned(player, zoneId)
end

-- Called after EconomyService.LoadPlayer so a re-joining owner sees the
-- already-built state without replaying the purchase animation.
function ZoneService.SyncPlayerZones(player: Player)
	for _, zone in ipairs(ZONES) do
		if EconomyService.IsZoneOwned(player, zone.id) then
			local floor = zoneFloors[zone.id]
			if floor then
				applyOwnedVisuals(floor, zone, false)
				if zone.onPurchase then
					zone.onPurchase(player, floor)
				end
			end
		end
	end
end

function ZoneService.AttemptPurchase(player: Player, zoneId: string): boolean
	local zone = zoneById[zoneId]
	if not zone then
		return false
	end
	local floor = zoneFloors[zoneId]
	if not floor then
		return false
	end
	if EconomyService.IsZoneOwned(player, zoneId) then
		return false
	end

	if not EconomyService.CanAfford(player, zone.price) then
		showFloatingText(floor, "Need $" .. NumberFormatter.Format(zone.price) .. "!", Color3.fromRGB(255, 100, 100))
		return false
	end

	if not EconomyService.RemoveCash(player, zone.price) then
		return false
	end
	EconomyService.MarkZoneOwned(player, zoneId)

	applyOwnedVisuals(floor, zone, true)
	showFloatingText(floor, "PURCHASED!", Color3.fromRGB(85, 255, 127))
	if zone.onPurchase then
		zone.onPurchase(player, floor)
	end
	return true
end

return ZoneService
