-- Suggests the "next thing to do/buy" for players still learning the game,
-- via a client-rendered arrow anchored to a target BasePart. Server picks
-- the target and publishes it to PlanetHustleStats.OnboardingTarget
-- (ObjectValue) + OnboardingHint (StringValue) - client subscribes to
-- those, no polling on the client side.
--
-- Targeting rules (see feature/onboarding-pointer plan for the design pass):
--   1. If any purchase candidate is currently affordable, target the
--      cheapest one's pad.
--   2. Otherwise, if the player hasn't made any purchases yet, fall back
--      to the Dog Walking LeashPost as an interaction hint ("start here").
--   3. Otherwise (afford nothing, but has bought at least one thing), hide.
--
-- Step 2 (this file's initial commit) fires OnPlotBuilt once and doesn't
-- re-evaluate; step 3 adds the 2s live-refresh loop; step 4 adds the
-- "player is past onboarding, permanently silent" cutoff.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local EconomyService = require(script.Parent.EconomyService)
local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local OnboardingService = {}

local ONBOARDING_KEY_ATTR = "OnboardingKey"
local TARGET_VALUE_NAME = "OnboardingTarget"
local HINT_VALUE_NAME = "OnboardingHint"
local INTERACTION_HINT_KEY = "dogWalkingClick"
local INTERACTION_HINT_TEXT = "Walk dogs to earn cash"

-- One entry per possible purchase candidate. `getSpec(player)` returns
-- either { cost, label } for a purchase that's currently AVAILABLE (all
-- prereqs met, not already owned/maxed) or nil to skip. Costs get sorted
-- ascending downstream; the cheapest affordable one wins.
type CandidateSpec = { cost: number, label: string, key: string }

local function fmtCost(n: number): string
	return "$" .. NumberFormatter.Format(n)
end

local CANDIDATES: { (player: Player) -> CandidateSpec? } = {
	-- Dog Walking Value / Speed / Scale / Manager / Extra Stations
	function(player)
		local dw = EconomyService.GetDogWalkingState(player)
		local nextTier = dw and Config.DogWalking.valueTiers[dw.valueTier + 1]
		if not nextTier then return nil end
		return { key = "dogWalkingValue", cost = nextTier.cost, label = nextTier.name .. " — " .. fmtCost(nextTier.cost) }
	end,
	function(player)
		local dw = EconomyService.GetDogWalkingState(player)
		local nextTier = dw and Config.DogWalking.speedTiers[dw.speedTier + 1]
		if not nextTier then return nil end
		return { key = "dogWalkingSpeed", cost = nextTier.cost, label = nextTier.name .. " — " .. fmtCost(nextTier.cost) }
	end,
	function(player)
		local dw = EconomyService.GetDogWalkingState(player)
		local nextTier = dw and Config.DogWalking.scaleTiers[dw.scaleTier + 1]
		if not nextTier or nextTier.locked then return nil end -- skip Brainrot teaser
		return { key = "dogWalkingScale", cost = nextTier.cost, label = nextTier.name .. " — " .. fmtCost(nextTier.cost) }
	end,
	function(player)
		local dw = EconomyService.GetDogWalkingState(player)
		if not dw or dw.hasManager then return nil end
		return { key = "dogWalkingManager", cost = Config.DogWalking.managerCost, label = "Hire a Dog Walker — " .. fmtCost(Config.DogWalking.managerCost) }
	end,
	function(player)
		local dw = EconomyService.GetDogWalkingState(player)
		if not dw then return nil end
		for extraIndex, cost in ipairs(Config.DogWalking.stationCosts) do
			if not dw.extraStations[extraIndex] then
				local stationIndex = extraIndex + 1
				return { key = "dogWalkingStation" .. stationIndex, cost = cost, label = "Station " .. stationIndex .. " — " .. fmtCost(cost) }
			end
		end
		return nil
	end,

	-- DoorDash: unlock, then Value/Speed/Manager/Vehicle/houses (all gated
	-- on unlock being owned since their pads don't exist until then).
	function(player)
		if EconomyService.IsZoneOwned(player, "doordash") then return nil end
		return { key = "doorDashUnlock", cost = Config.DoorDash.unlockCost, label = "Unlock DoorDash — " .. fmtCost(Config.DoorDash.unlockCost) }
	end,
	function(player)
		if not EconomyService.IsZoneOwned(player, "doordash") then return nil end
		local dd = EconomyService.GetDoorDashState(player)
		local nextTier = dd and Config.DoorDash.valueTiers[dd.valueTier + 1]
		if not nextTier then return nil end
		return { key = "doorDashValue", cost = nextTier.cost, label = nextTier.name .. " — " .. fmtCost(nextTier.cost) }
	end,
	function(player)
		if not EconomyService.IsZoneOwned(player, "doordash") then return nil end
		local dd = EconomyService.GetDoorDashState(player)
		local nextTier = dd and Config.DoorDash.speedTiers[dd.speedTier + 1]
		if not nextTier then return nil end
		return { key = "doorDashSpeed", cost = nextTier.cost, label = nextTier.name .. " — " .. fmtCost(nextTier.cost) }
	end,
	function(player)
		if not EconomyService.IsZoneOwned(player, "doordash") then return nil end
		local dd = EconomyService.GetDoorDashState(player)
		if not dd or dd.hasManager then return nil end
		return { key = "doorDashManager", cost = Config.DoorDash.managerCost, label = "Hire a Dispatcher — " .. fmtCost(Config.DoorDash.managerCost) }
	end,
	function(player)
		if not EconomyService.IsZoneOwned(player, "doordash") then return nil end
		local dd = EconomyService.GetDoorDashState(player)
		local nextTier = dd and Config.DoorDash.vehicleTiers[dd.vehicleTier + 1]
		if not nextTier then return nil end
		return { key = "doorDashVehicle", cost = nextTier.cost, label = nextTier.name .. " — " .. fmtCost(nextTier.cost) }
	end,
	function(player)
		if not EconomyService.IsZoneOwned(player, "doordash") then return nil end
		local dd = EconomyService.GetDoorDashState(player)
		if not dd then return nil end
		for slotIndex = 1, 4 do
			local cost = Config.DoorDash.startingHouseCosts[slotIndex]
			if cost and not dd.ownedHouseSlots[slotIndex] then
				return { key = "doorDashHouse" .. slotIndex, cost = cost, label = "House " .. slotIndex .. " — " .. fmtCost(cost) }
			end
		end
		-- Slots 7-8 (extra pad-purchased) only unlock once Cargo Plane
		-- (vehicleTier == 4) is owned - slots 5-6 are Cargo Plane's
		-- auto-grant, never pointed at as a purchase.
		if dd.vehicleTier >= 4 then
			for extraIndex, cost in ipairs(Config.DoorDash.extraHousePadCosts) do
				local slotIndex = 6 + extraIndex
				if not dd.ownedHouseSlots[slotIndex] then
					return { key = "doorDashHouse" .. slotIndex, cost = cost, label = "House " .. slotIndex .. " — " .. fmtCost(cost) }
				end
			end
		end
		return nil
	end,

	-- Neighborhood Upgrade (shared buff)
	function(player)
		if EconomyService.GetNeighborhoodTier(player) > 0 then return nil end
		return { key = "neighborhoodUpgrade", cost = Config.Neighborhood.upgradeCost, label = "Neighborhood Upgrade — " .. fmtCost(Config.Neighborhood.upgradeCost) }
	end,

	-- Global zones
	function(player)
		if EconomyService.IsZoneOwned(player, "rideshare") then return nil end
		return { key = "zone_rideshare", cost = Config.Rideshare.unlockCost, label = "Unlock Rideshare — " .. fmtCost(Config.Rideshare.unlockCost) }
	end,
	function(player)
		if EconomyService.IsZoneOwned(player, "lottery") then return nil end
		return { key = "zone_lottery", cost = Config.Lottery.unlockCost, label = "Unlock Lottery — " .. fmtCost(Config.Lottery.unlockCost) }
	end,
	function(player)
		if EconomyService.IsZoneOwned(player, "freelance_gig_hub") then return nil end
		return { key = "zone_freelance_gig_hub", cost = Config.FreelanceGigHub.unlockCost, label = "Unlock Freelance Gig Hub — " .. fmtCost(Config.FreelanceGigHub.unlockCost) }
	end,
}

-- Total number of things the player has purchased across all tracks. Used
-- both for the "$0 fresh profile" interaction-hint gate here (== 0) and
-- for the later cutoff logic in step 4 (>= 6).
local function countPurchases(player: Player): number
	local dw = EconomyService.GetDogWalkingState(player)
	local dd = EconomyService.GetDoorDashState(player)
	local n = 0
	if dw then
		n += dw.valueTier + dw.speedTier + dw.scaleTier
		if dw.hasManager then n += 1 end
		for _ in pairs(dw.extraStations) do n += 1 end
	end
	if dd then
		n += dd.valueTier + dd.speedTier + dd.vehicleTier
		if dd.hasManager then n += 1 end
		for _ in pairs(dd.ownedHouseSlots) do n += 1 end
	end
	n += EconomyService.GetNeighborhoodTier(player)
	if EconomyService.IsZoneOwned(player, "doordash") then n += 1 end
	if EconomyService.IsZoneOwned(player, "rideshare") then n += 1 end
	if EconomyService.IsZoneOwned(player, "lottery") then n += 1 end
	if EconomyService.IsZoneOwned(player, "freelance_gig_hub") then n += 1 end
	return n
end

-- Finds a BasePart tagged with the given OnboardingKey attribute. Scoped
-- to the player's plot folder for per-player pads; zone_* keys also check
-- the corresponding Zone_<id> workspace model. Called per compute pass -
-- one DFS walk of ~50 descendants, negligible at a 2s cadence.
local function findPadByKey(player: Player, key: string): BasePart?
	local plotFolder = workspace:FindFirstChild("Neighborhood_" .. player.UserId)
	if plotFolder then
		for _, part in ipairs(plotFolder:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute(ONBOARDING_KEY_ATTR) == key then
				return part
			end
		end
	end
	if string.sub(key, 1, 5) == "zone_" then
		local zoneModel = workspace:FindFirstChild("Zone_" .. string.sub(key, 6))
		if zoneModel then
			for _, part in ipairs(zoneModel:GetDescendants()) do
				if part:IsA("BasePart") and part:GetAttribute(ONBOARDING_KEY_ATTR) == key then
					return part
				end
			end
		end
	end
	return nil
end

local function computeTarget(player: Player): (BasePart?, string?)
	local cash = EconomyService.GetCash(player)

	local specs: { CandidateSpec } = {}
	for _, fn in ipairs(CANDIDATES) do
		local spec = fn(player)
		if spec then
			table.insert(specs, spec)
		end
	end
	table.sort(specs, function(a, b) return a.cost < b.cost end)

	for _, spec in ipairs(specs) do
		if cash >= spec.cost then
			local pad = findPadByKey(player, spec.key)
			if pad then
				return pad, spec.label
			end
		end
	end

	-- Nothing affordable. Interaction-hint fallback for the brand-new
	-- $0 profile: point at the Dog Walking LeashPost.
	if countPurchases(player) == 0 then
		local post = findPadByKey(player, INTERACTION_HINT_KEY)
		if post then
			return post, INTERACTION_HINT_TEXT
		end
	end

	return nil, nil
end

local function getOrCreateStatValues(player: Player): (ObjectValue?, StringValue?)
	local stats = player:FindFirstChild("PlanetHustleStats")
	if not stats then
		return nil, nil
	end
	local target = stats:FindFirstChild(TARGET_VALUE_NAME) :: ObjectValue?
	if not target then
		target = Instance.new("ObjectValue")
		target.Name = TARGET_VALUE_NAME
		target.Parent = stats
	end
	local hint = stats:FindFirstChild(HINT_VALUE_NAME) :: StringValue?
	if not hint then
		hint = Instance.new("StringValue")
		hint.Name = HINT_VALUE_NAME
		hint.Parent = stats
	end
	return target, hint
end

local REFRESH_INTERVAL = 2

-- Per-player flag: true while the heartbeat loop should keep spinning.
-- Cleared on PlayerRemoving so the loop exits at the next tick.
local activeLoops: { [Player]: boolean } = {}

local function publishTarget(player: Player)
	local target, hint = getOrCreateStatValues(player)
	if not target or not hint then
		return
	end
	local pad, label = computeTarget(player)
	target.Value = pad
	hint.Value = label or ""
end

-- Called once by PlotService.buildPlotForPlayer after the plot's pads have
-- been built - publishes an initial target immediately and starts the
-- heartbeat loop. Every REFRESH_INTERVAL seconds the target is
-- recomputed; the client's arrow re-anchors automatically via
-- GetPropertyChangedSignal on the ObjectValue. Step 4 adds the "past
-- onboarding" cutoff that stops the loop for players who don't need
-- guidance anymore.
function OnboardingService.OnPlotBuilt(player: Player)
	publishTarget(player)
	if activeLoops[player] then
		return
	end
	activeLoops[player] = true
	task.spawn(function()
		while activeLoops[player] and player.Parent do
			task.wait(REFRESH_INTERVAL)
			if not (activeLoops[player] and player.Parent) then
				break
			end
			publishTarget(player)
		end
	end)
end

function OnboardingService.Init()
	Players.PlayerRemoving:Connect(function(player)
		activeLoops[player] = nil
	end)
end

return OnboardingService
