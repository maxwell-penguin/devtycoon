-- Cash, leaderstats, and DataStore persistence (cash + owned zones).
-- This is the single owner of each player's persisted save data; other
-- systems (ZoneService, IncomeSourceService) read/write through it rather
-- than keeping their own copy, so there's one source of truth to save.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)

local AUTOSAVE_INTERVAL = 60
local MAX_SAVE_ATTEMPTS = 3

local playerStore = DataStoreService:GetDataStore("PlanetHustle_PlayerData_v1")

local EconomyService = {}

-- profiles[player] = { cash, ownedZones, doorDash, dogWalking, neighborhoodTier }
type DoorDashState = {
	valueTier: number, -- 0 = none, index into Config.DoorDash.valueTiers otherwise
	speedTier: number,
	hasManager: boolean,
	vehicleTier: number, -- 0 = Bike/Moped (start), index into Config.DoorDash.vehicleTiers otherwise
	-- Which of house slots 1-8 are built. 1-4 = starting row (individually
	-- pad-purchased, Phase 4 - no longer bundled free with unlockCost).
	-- 5-6 = Cargo Plane's auto-grant (unchanged). 7-8 = pads beyond that.
	-- A set, not a count: slots are purchased in whatever order the player
	-- walks up to them, not necessarily 1,2,3,4 in sequence.
	ownedHouseSlots: { [number]: boolean },
}
type DogWalkingState = {
	valueTier: number, -- 0 = none, index into Config.DogWalking.valueTiers otherwise
	speedTier: number,
	hasManager: boolean,
	-- Which of the 2 extra stations (beyond the always-free station 1) are
	-- built. Index 1 = station 2, index 2 = station 3.
	extraStations: { [number]: boolean },
}
local profiles: {
	[Player]: {
		cash: number,
		ownedZones: { [string]: boolean },
		doorDash: DoorDashState,
		dogWalking: DogWalkingState,
		neighborhoodTier: number, -- 0 = none, 1 = Neighborhood Upgrade. Shared: boosts both hustles' base reward.
	},
} = {}

local function defaultDoorDash(): DoorDashState
	return {
		valueTier = 0,
		speedTier = 0,
		hasManager = false,
		vehicleTier = 0,
		ownedHouseSlots = {},
	}
end

local function defaultDogWalking(): DogWalkingState
	return {
		valueTier = 0,
		speedTier = 0,
		hasManager = false,
		extraStations = {},
	}
end

local function defaultProfile()
	return {
		cash = 0,
		ownedZones = {},
		doorDash = defaultDoorDash(),
		dogWalking = defaultDogWalking(),
		neighborhoodTier = 0,
	}
end

local function withRetry(fn: () -> any): (boolean, any)
	for attempt = 1, MAX_SAVE_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[EconomyService] DataStore attempt %d/%d failed: %s"):format(attempt, MAX_SAVE_ATTEMPTS, tostring(result)))
		if attempt < MAX_SAVE_ATTEMPTS then
			task.wait(1 * attempt)
		end
	end
	return false, nil
end

local function updateLeaderstats(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	if cashValue then
		cashValue.Value = profiles[player].cash
	end
end

--------------------------------------------------------------------------------
-- LOAD / SAVE
--------------------------------------------------------------------------------

function EconomyService.LoadPlayer(player: Player)
	local ok, saved = withRetry(function()
		return playerStore:GetAsync("Player_" .. player.UserId)
	end)

	profiles[player] = (ok and saved) or defaultProfile()
	-- Migrates saves from before these progression systems existed.
	if not profiles[player].doorDash then
		profiles[player].doorDash = defaultDoorDash()
	end
	if not profiles[player].doorDash.vehicleTier then
		-- Renamed from scaleTier (an earlier, since-replaced Neighborhood-
		-- Upgrade-style draft for DoorDash's own Phase 4 - superseded by the
		-- vehicle tier escalation).
		profiles[player].doorDash.vehicleTier = 0
	end
	if not profiles[player].doorDash.ownedHouseSlots then
		-- Migrates saves from before house slots were individually
		-- pad-purchased (Phase 4) - grandfather in whatever the old
		-- houseCount field says they had (the old model always built
		-- slots 1..N in that fixed order, so this is exact, not a guess).
		local legacyCount = (profiles[player].doorDash :: any).houseCount or 0
		local slots = {}
		for i = 1, legacyCount do
			slots[i] = true
		end
		profiles[player].doorDash.ownedHouseSlots = slots
		local legacyDoorDash = profiles[player].doorDash :: any
		legacyDoorDash.houseCount = nil
	end
	if not profiles[player].dogWalking then
		profiles[player].dogWalking = defaultDogWalking()
	end
	if not profiles[player].dogWalking.extraStations then
		profiles[player].dogWalking.extraStations = {}
	end
	if not profiles[player].neighborhoodTier then
		profiles[player].neighborhoodTier = 0
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cashValue = Instance.new("NumberValue")
	cashValue.Name = "Cash"
	cashValue.Value = profiles[player].cash
	cashValue.Parent = leaderstats
end

function EconomyService.SavePlayer(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local ok = withRetry(function()
		playerStore:SetAsync("Player_" .. player.UserId, profile)
	end)

	if not ok then
		warn("[EconomyService] Failed to save data for " .. player.Name .. " after " .. MAX_SAVE_ATTEMPTS .. " attempts")
	end
end

function EconomyService.ReleasePlayer(player: Player)
	profiles[player] = nil
end

--------------------------------------------------------------------------------
-- CASH
--------------------------------------------------------------------------------

function EconomyService.GetCash(player: Player): number
	local profile = profiles[player]
	return profile and profile.cash or 0
end

function EconomyService.CanAfford(player: Player, amount: number): boolean
	return EconomyService.GetCash(player) >= amount
end

function EconomyService.AddCash(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.cash += amount
	updateLeaderstats(player)
end

function EconomyService.RemoveCash(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return false
	end
	if profile.cash < amount then
		return false
	end
	profile.cash -= amount
	updateLeaderstats(player)
	return true
end

--------------------------------------------------------------------------------
-- ZONE OWNERSHIP (persisted alongside cash)
--------------------------------------------------------------------------------

function EconomyService.IsZoneOwned(player: Player, zoneId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.ownedZones[zoneId] == true
end

function EconomyService.MarkZoneOwned(player: Player, zoneId: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.ownedZones[zoneId] = true
end

function EconomyService.GetOwnedZones(player: Player): { [string]: boolean }
	local profile = profiles[player]
	return profile and profile.ownedZones or {}
end

--------------------------------------------------------------------------------
-- DOOR DASH PROGRESSION (persisted alongside cash)
--------------------------------------------------------------------------------

function EconomyService.GetDoorDashState(player: Player): DoorDashState?
	local profile = profiles[player]
	return profile and profile.doorDash
end

function EconomyService.UpdateDoorDash(player: Player, patch: { [string]: any })
	local profile = profiles[player]
	if not profile then
		return
	end
	for key, value in pairs(patch) do
		(profile.doorDash :: any)[key] = value
	end
end

--------------------------------------------------------------------------------
-- DOG WALKING PROGRESSION (persisted alongside cash)
--------------------------------------------------------------------------------

function EconomyService.GetDogWalkingState(player: Player): DogWalkingState?
	local profile = profiles[player]
	return profile and profile.dogWalking
end

function EconomyService.UpdateDogWalking(player: Player, patch: { [string]: any })
	local profile = profiles[player]
	if not profile then
		return
	end
	for key, value in pairs(patch) do
		(profile.dogWalking :: any)[key] = value
	end
end

--------------------------------------------------------------------------------
-- NEIGHBORHOOD UPGRADE (shared by Dog Walking + DoorDash, persisted alongside cash)
--------------------------------------------------------------------------------

function EconomyService.GetNeighborhoodTier(player: Player): number
	local profile = profiles[player]
	return profile and profile.neighborhoodTier or 0
end

function EconomyService.SetNeighborhoodTier(player: Player, tier: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.neighborhoodTier = tier
end

--------------------------------------------------------------------------------
-- AUTOSAVE
--------------------------------------------------------------------------------

function EconomyService.Init()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				if profiles[player] then
					EconomyService.SavePlayer(player)
				end
			end
		end
	end)
end

return EconomyService
