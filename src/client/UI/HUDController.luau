-- Minimal HUD: big comma-formatted cash counter (top-left) and income/sec
-- (top-right). ScreenGui keeps the default GuiInset so labels sit cleanly
-- below Roblox's topbar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local player = Players.LocalPlayer

local HUDController = {}

function HUDController.Init()
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlanetHustleHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Position = UDim2.new(0, 20, 0, 20)
	cashLabel.Size = UDim2.new(0, 340, 0, 64)
	cashLabel.BackgroundTransparency = 1
	cashLabel.Font = Enum.Font.Code
	cashLabel.TextScaled = true
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
	cashLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	cashLabel.TextStrokeTransparency = 0.4
	cashLabel.Text = "$0"
	cashLabel.Parent = screenGui

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "IncomeLabel"
	incomeLabel.AnchorPoint = Vector2.new(1, 0)
	incomeLabel.Position = UDim2.new(1, -20, 0, 20)
	incomeLabel.Size = UDim2.new(0, 220, 0, 40)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Enum.Font.GothamMedium
	incomeLabel.TextScaled = true
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Right
	incomeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	incomeLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	incomeLabel.TextStrokeTransparency = 0.5
	incomeLabel.Text = "$0/sec"
	incomeLabel.Parent = screenGui

	-- Server creates these after DataStore load / player setup, which can
	-- take a beat, so wire them up in the background instead of blocking
	-- the rest of the client bootstrap.
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		local cashValue = leaderstats:WaitForChild("Cash")
		local function updateCash()
			cashLabel.Text = "$" .. NumberFormatter.WithCommas(cashValue.Value)
		end
		updateCash()
		cashValue:GetPropertyChangedSignal("Value"):Connect(updateCash)
	end)

	task.spawn(function()
		local stats = player:WaitForChild("PlanetHustleStats")
		local incomeValue = stats:WaitForChild("IncomePerSecond")
		local function updateIncome()
			incomeLabel.Text = "$" .. NumberFormatter.Format(incomeValue.Value) .. "/sec"
		end
		updateIncome()
		incomeValue:GetPropertyChangedSignal("Value"):Connect(updateIncome)
	end)
end

return HUDController
