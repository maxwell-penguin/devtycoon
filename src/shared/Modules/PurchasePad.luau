-- Stand-on-pad auto-purchase, replacing ProximityPrompt + E-press across
-- every zone/upgrade/manager/scale-tier purchase in the game (Sell Lemons-
-- style pressure plate: touch it, and if affordable, it just buys). Shared
-- between ZoneService (Rideshare/Lottery/Freelance) and IncomeSourceService
-- (DoorDash/Dog Walking/Neighborhood), since both need the identical
-- touch-detect + debounce + one-time-vs-repeatable behavior.
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local PurchasePad = {}

local PAD_DEBOUNCE = 0.4
local FAIL_FLASH_COLOR = Color3.fromRGB(255, 60, 60)

-- Flat circular pad (Cylinder shape rotated so its round face points up).
-- `onboardingKey` (optional): string tag stashed as an attribute so
-- OnboardingService can find this pad when suggesting "next thing to buy".
-- Callsites that aren't part of onboarding progression (e.g., the lobby's
-- claim pad) omit it and the pad simply isn't a candidate.
function PurchasePad.Build(parent: Instance, position: Vector3, color: Color3, radius: number?, onboardingKey: string?): BasePart
	local d = (radius or 4) * 2
	local pad = Instance.new("Part")
	pad.Name = "Pad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = color
	pad.Size = Vector3.new(0.3, d, d)
	pad.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	pad.Parent = parent
	if onboardingKey then
		pad:SetAttribute("OnboardingKey", onboardingKey)
	end
	return pad
end

-- allowPlayer(player): gate on who's allowed to even attempt (plot owner
-- for per-player-plot pads, or "anyone" for shared-world zone pads).
-- attemptPurchase(player): the existing Attempt*/AttemptPurchase function -
-- already handles affordability, debiting, and the money-shot itself.
-- oneTime: true disconnects the pad entirely after a SUCCESSFUL purchase
-- (zone unlocks, Manager hires, Neighborhood Upgrade - nothing left to buy
-- again). false keeps listening for the next tier (Value/Speed/Vehicle
-- tracks - multiple purchases over time on the same pad).
function PurchasePad.Wire(
	pad: BasePart,
	allowPlayer: (Player) -> boolean,
	attemptPurchase: (Player) -> boolean,
	oneTime: boolean
): RBXScriptConnection
	local debounce: { [Player]: boolean } = {}
	local connection: RBXScriptConnection
	connection = pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local player = Players:GetPlayerFromCharacter(character :: Model)
		if not player or not allowPlayer(player) then
			return
		end
		if debounce[player] then
			return
		end
		debounce[player] = true
		task.delay(PAD_DEBOUNCE, function()
			debounce[player] = nil
		end)

		local success = attemptPurchase(player)
		if success then
			if oneTime then
				connection:Disconnect()
			end
		else
			local originalColor = pad.Color
			TweenService:Create(pad, TweenInfo.new(0.1), { Color = FAIL_FLASH_COLOR }):Play()
			task.delay(0.15, function()
				if pad.Parent then
					TweenService:Create(pad, TweenInfo.new(0.3), { Color = originalColor }):Play()
				end
			end)
		end
	end)
	return connection
end

return PurchasePad
