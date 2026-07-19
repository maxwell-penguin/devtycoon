local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Systems = script.Parent.Systems
local EconomyService = require(Systems.EconomyService)
local ZoneService = require(Systems.ZoneService)
local IncomeSourceService = require(Systems.IncomeSourceService)
local LotteryService = require(Systems.LotteryService)
local PurchaseEffects = require(Systems.PurchaseEffects)

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

PurchaseEffects.Init()
EconomyService.Init()
ZoneService.Init()
IncomeSourceService.Init()
LotteryService.Init()

local function onPlayerAdded(player: Player)
	EconomyService.LoadPlayer(player)
	IncomeSourceService.SetupPlayer(player)
	ZoneService.SyncPlayerZones(player)
end

local function onPlayerRemoving(player: Player)
	EconomyService.SavePlayer(player)
	EconomyService.ReleasePlayer(player)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

print("[PlanetHustle] Server initialized")
