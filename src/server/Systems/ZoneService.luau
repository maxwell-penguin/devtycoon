-- Purchasable zones: locked floor + name/price BillboardGui + ProximityPrompt
-- (HoldDuration 0.5 = confirm-by-hold, native equivalent of a Y/N prompt).
-- On buy: EconomyService debit + MarkZoneOwned + PurchaseEffects money-shot
-- + zone.onPurchase callback for hustle-specific activation.
--
-- Each zone supplies buildHero(zoneModel, floor) which constructs its final-
-- state hero prop (and any per-zone decorative details) the first time the
-- zone is owned; PurchaseEffects then either animates the reveal (fresh
-- purchase) or shows it instantly (rejoin sync). Visual pass replaces the
-- generic placeholder hero with a real prop per zone, one at a time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local EconomyService = require(script.Parent.EconomyService)
local IncomeSourceService = require(script.Parent.IncomeSourceService)
local LotteryService = require(script.Parent.LotteryService)
local PurchaseEffects = require(script.Parent.PurchaseEffects)
local FloatingText = require(ReplicatedStorage.Shared.Modules.FloatingText)
local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local ZoneService = {}

type ZoneDef = {
	id: string,
	name: string,
	price: number,
	position: Vector3,
	size: Vector3,
	ownedColor: Color3,
	buildHero: (zoneModel: Model, floor: BasePart) -> Model | BasePart,
	onPurchase: ((owner: Player, zoneFloor: BasePart) -> ())?,
}

local ZONES: { ZoneDef } = {
	{
		id = "rideshare",
		name = "Rideshare Runs",
		price = Config.Rideshare.unlockCost,
		position = Vector3.new(0, 0.5, 50),
		size = Vector3.new(12, 1, 12),
		ownedColor = Color3.fromRGB(220, 90, 90),
		buildHero = function(zoneModel, floor)
			return IncomeSourceService.BuildRideshareHero(zoneModel, floor)
		end,
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
		ownedColor = Theme.Secondary,
		buildHero = function(zoneModel, floor)
			return LotteryService.BuildBoothHero(zoneModel, floor)
		end,
		onPurchase = function(_owner, zoneFloor)
			LotteryService.ActivateBooth(zoneFloor)
		end,
	},
	{
		id = "freelance_gig_hub",
		name = "Freelance Gig Hub",
		price = Config.FreelanceGigHub.unlockCost,
		position = Vector3.new(-50, 0.5, 50),
		size = Vector3.new(12, 1, 12),
		ownedColor = Color3.fromRGB(100, 180, 240),
		buildHero = function(zoneModel, floor)
			return IncomeSourceService.BuildFreelanceHero(zoneModel, floor)
		end,
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

local function applyOwnedVisuals(zoneModel: Model, floor: BasePart, zone: ZoneDef, animate: boolean, buyer: Player?)
	local priceTag = floor:FindFirstChild("PriceTag")
	if priceTag then
		priceTag:Destroy()
	end
	local prompt = floor:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	if zoneModel:FindFirstChild("Hero") then
		return
	end

	local hero = zone.buildHero(zoneModel, floor)

	PurchaseEffects.ApplyOwnedVisuals({
		zoneModel = zoneModel,
		floor = floor,
		hero = hero,
		ownedColor = zone.ownedColor,
		animate = animate,
		buyer = buyer,
		resultText = animate and "PURCHASED!" or nil,
		resultColor = animate and Theme.CashPositive or nil,
	})
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
	floor.Color = Theme.Locked
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
	priceLabel.TextColor3 = Theme.Gold
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
				applyOwnedVisuals(floor.Parent :: Model, floor, zone, false, nil)
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
		FloatingText.Show(floor, "Need $" .. NumberFormatter.Format(zone.price) .. "!", Theme.Warning)
		return false
	end

	if not EconomyService.RemoveCash(player, zone.price) then
		return false
	end
	EconomyService.MarkZoneOwned(player, zoneId)

	applyOwnedVisuals(floor.Parent :: Model, floor, zone, true, player)
	if zone.onPurchase then
		zone.onPurchase(player, floor)
	end
	return true
end

return ZoneService
