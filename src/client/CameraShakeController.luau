-- Listens for the server's zone-purchase camera shake and applies a
-- decaying positional offset via Humanoid.CameraOffset. (CameraOffset is
-- positional only — no rotational shake without fighting the default
-- camera script's CFrame control, so the "~0.6°" rotation from the spec is
-- dropped; the positional punch alone reads fine.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local CameraShakeController = {}

local function shake(duration: number, amplitude: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local startTime = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local decay = 1 - (elapsed / duration)
		local amp = amplitude * decay
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2 * amp,
			(math.random() - 0.5) * 2 * amp,
			0
		)
	end)
end

function CameraShakeController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("ZoneCameraShake") :: RemoteEvent
	remote.OnClientEvent:Connect(function(duration: number, amplitude: number)
		shake(duration, amplitude)
	end)
end

return CameraShakeController
