local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Systems = script.Parent.Systems
local EconomyService = require(Systems.EconomyService)
local ZoneService = require(Systems.ZoneService)
local IncomeSourceService = require(Systems.IncomeSourceService)
local LotteryService = require(Systems.LotteryService)
local PurchaseEffects = require(Systems.PurchaseEffects)
local PlotService = require(Systems.PlotService)
local OnboardingService = require(Systems.OnboardingService)

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

PurchaseEffects.Init()
EconomyService.Init()
ZoneService.Init()
IncomeSourceService.Init()
LotteryService.Init()
PlotService.Init()
OnboardingService.Init()

local function onPlayerAdded(player: Player)
	local isNewProfile = EconomyService.LoadPlayer(player)
	IncomeSourceService.SetupPlayer(player)
	ZoneService.SyncPlayerZones(player)

	if isNewProfile then
		-- Genuinely new player: stays at the lobby spawn point and picks a
		-- plot themselves via the claim pads, unless the server's already
		-- full even for that.
		if not PlotService.HasFreeSlot() then
			PlotService.SendToAnotherServer(player)
			return
		end
		PlotService.RegisterWaitingPlayer(player)
	else
		-- Returning player: skip the lobby, auto-assign same as before this
		-- pass added plot selection.
		if not PlotService.AssignFirstFreeSlot(player) then
			PlotService.SendToAnotherServer(player)
		end
	end
end

local function onPlayerRemoving(player: Player)
	PlotService.UnregisterWaitingPlayer(player)
	PlotService.ReleasePlot(player)
	EconomyService.SavePlayer(player)
	EconomyService.ReleasePlayer(player)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

print("[PlanetHustle] Server initialized")
