-- On-screen Walk button, shown while the player is within PROXIMITY_RADIUS
-- of any Dog Walking LeashPost inside their own plot. Replaces the old
-- ClickDetector-on-3D-model interaction (fiddly small hitbox) - server-side
-- click handling and reward math are unchanged (see
-- IncomeSourceService.HandleDogWalkingDelivery + the DogWalkingClick remote
-- wired in IncomeSourceService.Init).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

local PROXIMITY_RADIUS = 16
local CLICKABLE_TAG = "DogWalkingClickable"
local REWARD_STAT = "DogWalkingReward"

local DogWalkingButton = {}

function DogWalkingButton.Init()
	local playerGui = player:WaitForChild("PlayerGui")
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DogWalkingClick") :: RemoteEvent

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DogWalkingUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "WalkButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 100)
	button.Size = UDim2.new(0, 260, 0, 84)
	button.BackgroundColor3 = Color3.fromRGB(51, 255, 136)
	button.TextColor3 = Color3.fromRGB(10, 30, 20)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextWrapped = true
	button.AutoButtonColor = true
	button.Visible = false
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(10, 10, 20)
	stroke.Parent = button

	local currentPost: BasePart? = nil

	button.MouseButton1Click:Connect(function()
		if currentPost then
			remote:FireServer(currentPost)
		end
	end)

	-- Same lazy-wait pattern as HUDController's cash/income subscriptions:
	-- server creates PlanetHustleStats after DataStore load, which may not
	-- exist yet at Init time.
	task.spawn(function()
		local stats = player:WaitForChild("PlanetHustleStats")
		local rewardValue = stats:WaitForChild(REWARD_STAT)
		local function refreshText()
			button.Text = "Click to Walk\n(+$" .. rewardValue.Value .. ")"
		end
		refreshText()
		rewardValue:GetPropertyChangedSignal("Value"):Connect(refreshText)
	end)

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local myPlot = workspace:FindFirstChild("Neighborhood_" .. player.UserId)
		if not hrp or not myPlot then
			currentPost = nil
			button.Visible = false
			return
		end

		local closest: BasePart? = nil
		local closestDist = PROXIMITY_RADIUS
		for _, tagged in ipairs(CollectionService:GetTagged(CLICKABLE_TAG)) do
			if tagged:IsA("BasePart") and tagged:IsDescendantOf(myPlot) then
				local d = ((tagged :: BasePart).Position - hrp.Position).Magnitude
				if d < closestDist then
					closestDist = d
					closest = tagged :: BasePart
				end
			end
		end
		currentPost = closest
		button.Visible = closest ~= nil
	end)
end

return DogWalkingButton
