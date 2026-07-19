-- Assigns each player a private neighborhood plot (own folder + origin in
-- workspace) shared by Dog Walking (always-free starter) and DoorDash (cash-
-- gated unlock) — a dog-walker and a delivery driver plausibly work the same
-- block, and Scale-tier upgrades need each player's neighborhood to look
-- different. Ported from the PLOT_ORIGINS pattern proven on
-- refactor/per-player-zones (main@f269629), scoped to these two income
-- sources only — Rideshare/Lottery/FreelanceGigHub stay on the shared global
-- Zone_x model pattern for now.
local Players = game:GetService("Players")

local IncomeSourceService = require(script.Parent.IncomeSourceService)

local PlotService = {}

-- 6 plots in a row, matches the previous per-player attempt's slot count.
-- Bump this + Studio's MaxPlayers together to add more slots.
local PLOT_ORIGINS: { Vector3 } = {
	Vector3.new(-200, 0, -150),
	Vector3.new(-120, 0, -150),
	Vector3.new(-40, 0, -150),
	Vector3.new(40, 0, -150),
	Vector3.new(120, 0, -150),
	Vector3.new(200, 0, -150),
}

type PlotState = {
	plotIndex: number,
	origin: Vector3,
	folder: Folder,
	characterConn: RBXScriptConnection?,
}

local plotOccupancy: { [number]: Player? } = {}
local playerPlots: { [Player]: PlotState } = {}

local function teleportToPlot(character: Model, origin: Vector3)
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = CFrame.new(origin + Vector3.new(0, 5, 0))
	end
end

function PlotService.AssignPlot(player: Player)
	local slot: number?
	for i = 1, #PLOT_ORIGINS do
		if plotOccupancy[i] == nil then
			slot = i
			break
		end
	end
	if not slot then
		warn("[PlotService] no free DoorDash plot for " .. player.Name)
		return
	end
	plotOccupancy[slot] = player

	local origin = PLOT_ORIGINS[slot]
	local folder = Instance.new("Folder")
	folder.Name = "Neighborhood_" .. player.UserId
	folder.Parent = workspace

	local plot: PlotState = {
		plotIndex = slot,
		origin = origin,
		folder = folder,
		characterConn = nil,
	}
	playerPlots[player] = plot

	IncomeSourceService.SetupPlayerDogWalking(player, folder, origin)
	IncomeSourceService.SetupPlayerDoorDash(player, folder, origin)

	if player.Character then
		task.spawn(teleportToPlot, player.Character, origin)
	end
	plot.characterConn = player.CharacterAdded:Connect(function(char)
		task.spawn(teleportToPlot, char, origin)
	end)
end

function PlotService.ReleasePlot(player: Player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	if plot.characterConn then
		plot.characterConn:Disconnect()
	end
	IncomeSourceService.CleanupPlayerDoorDash(player)
	IncomeSourceService.CleanupPlayerDogWalking(player)
	plotOccupancy[plot.plotIndex] = nil
	plot.folder:Destroy()
	playerPlots[player] = nil
end

return PlotService
