-- Assigns each player a private DoorDash plot (own folder + origin in
-- workspace) so DoorDash's Scale tier (more houses / Neighborhood Upgrade /
-- Office Building) can look different per player. Ported from the
-- PLOT_ORIGINS pattern proven on refactor/per-player-zones (main@f269629),
-- scoped down to DoorDash only — the other 4 income sources stay on the
-- shared global Zone_x model pattern for now.
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
	folder.Name = "DoorDashPlot_" .. player.UserId
	folder.Parent = workspace

	local plot: PlotState = {
		plotIndex = slot,
		origin = origin,
		folder = folder,
		characterConn = nil,
	}
	playerPlots[player] = plot

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
	plotOccupancy[plot.plotIndex] = nil
	plot.folder:Destroy()
	playerPlots[player] = nil
end

return PlotService
