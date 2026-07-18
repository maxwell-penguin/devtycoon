-- Cash, leaderstats, and DataStore persistence (cash + owned zones).
-- This is the single owner of each player's persisted save data; other
-- systems (ZoneService, IncomeSourceService) read/write through it rather
-- than keeping their own copy, so there's one source of truth to save.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local AUTOSAVE_INTERVAL = 60
local MAX_SAVE_ATTEMPTS = 3

local playerStore = DataStoreService:GetDataStore("PlanetHustle_PlayerData_v1")

local EconomyService = {}

-- profiles[player] = { cash: number, ownedZones: {[zoneId]: true} }
local profiles: { [Player]: { cash: number, ownedZones: { [string]: boolean } } } = {}

local function defaultProfile()
	return { cash = 0, ownedZones = {} }
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
