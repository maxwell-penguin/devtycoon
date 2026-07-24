-- Floating gold arrow above whichever BasePart the server currently
-- suggests as the next thing to do. Reads
-- PlanetHustleStats/OnboardingTarget (ObjectValue) - when it's set, arrow
-- + hint label render above the target; when nil, both hide. Fully event-
-- driven off GetPropertyChangedSignal; no per-frame polling here.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local OnboardingPointer = {}

local ARROW_HEIGHT_ABOVE_TARGET = 5
local ARROW_COLOR = Color3.fromRGB(255, 220, 90) -- Theme.Gold; hardcoded here so the client doesn't need to require a shared module
local BOB_TIME = 1.2
local BOB_AMPLITUDE = 0.6

local function buildArrowModel(): (Part, TextLabel)
	-- Simple neon diamond: a Part rotated 45° around Z reads as a floating
	-- gem/marker from any angle. A WedgePart "arrow" is more literal but
	-- only reads as a triangle from one viewing direction, which is
	-- meaningless when the player's camera can be anywhere.
	local arrow = Instance.new("Part")
	arrow.Name = "OnboardingArrow"
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.Material = Enum.Material.Neon
	arrow.Color = ARROW_COLOR
	arrow.Size = Vector3.new(1.6, 1.6, 1.6)

	local light = Instance.new("PointLight")
	light.Color = ARROW_COLOR
	light.Range = 8
	light.Brightness = 2
	light.Parent = arrow

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HintLabel"
	billboard.Adornee = arrow
	billboard.Size = UDim2.new(0, 220, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = arrow

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = billboard

	return arrow, label
end

function OnboardingPointer.Init()
	local arrow, label = buildArrowModel()
	arrow.Parent = workspace
	arrow.Transparency = 1
	label.Text = ""

	-- Same lazy-wait pattern as HUDController/DogWalkingButton - server
	-- creates PlanetHustleStats after DataStore load.
	task.spawn(function()
		local stats = player:WaitForChild("PlanetHustleStats")
		local target = stats:WaitForChild("OnboardingTarget") :: ObjectValue
		local hint = stats:WaitForChild("OnboardingHint") :: StringValue

		local basePosition: Vector3? = nil
		local bobTween: Tween? = nil

		local function anchor()
			local part = target.Value
			if part and part:IsA("BasePart") then
				basePosition = (part :: BasePart).Position + Vector3.new(0, ARROW_HEIGHT_ABOVE_TARGET, 0)
				-- 45° around Z + 45° around X reads as a floating diamond
				-- from any camera angle.
				arrow.CFrame = CFrame.new(basePosition) * CFrame.Angles(math.rad(45), 0, math.rad(45))
				arrow.Transparency = 0
				label.Text = hint.Value

				if bobTween then bobTween:Cancel() end
				bobTween = TweenService:Create(
					arrow,
					TweenInfo.new(BOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Position = basePosition + Vector3.new(0, BOB_AMPLITUDE, 0) }
				)
				(bobTween :: Tween):Play()
			else
				basePosition = nil
				arrow.Transparency = 1
				label.Text = ""
				if bobTween then
					bobTween:Cancel()
					bobTween = nil
				end
			end
		end

		anchor()
		target:GetPropertyChangedSignal("Value"):Connect(anchor)
		hint:GetPropertyChangedSignal("Value"):Connect(function()
			label.Text = hint.Value
		end)
	end)
end

return OnboardingPointer
