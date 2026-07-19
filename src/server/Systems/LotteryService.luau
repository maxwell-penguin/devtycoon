-- Lottery Ticket Booth: server-authoritative weighted roll on ticket buy.
-- The client never sees or influences the RNG — it just walks up, presses
-- E, and watches the floating result text the server spawned. ZoneService
-- calls ActivateBooth on Lottery zone purchase (and on rejoin for owners).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local EconomyService = require(script.Parent.EconomyService)
local FloatingText = require(ReplicatedStorage.Shared.Modules.FloatingText)
local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local LotteryService = {}

local BOOTH_COLOR = Theme.Secondary
local BOOTH_SIZE = Vector3.new(5, 6, 5)

-- cooldowns[player][booth] = os.clock() expiry
local cooldowns: { [Player]: { [BasePart]: number } } = {}

-- Cumulative-weight prefix table, computed once at module load. Every roll
-- picks a bucket by finding the first cumulative >= u ∈ [0,1).
local outcomeCumulative: { { name: string, cumulative: number, minMultiplier: number, maxMultiplier: number } } = {}
do
	local acc = 0
	for _, o in ipairs(Config.Lottery.outcomes) do
		acc += o.weight
		table.insert(outcomeCumulative, {
			name = o.name,
			cumulative = acc,
			minMultiplier = o.minMultiplier,
			maxMultiplier = o.maxMultiplier,
		})
	end
end

-- Pure roll: pick outcome by weighted CDF, roll multiplier uniformly in the
-- picked bucket, compute payout. No side effects — safe to call in tests.
function LotteryService.RollOutcome(): (string, number, number)
	local u = math.random()
	local picked = outcomeCumulative[#outcomeCumulative]
	for _, o in ipairs(outcomeCumulative) do
		if u <= o.cumulative then
			picked = o
			break
		end
	end
	local multiplier = picked.minMultiplier + math.random() * (picked.maxMultiplier - picked.minMultiplier)
	local payout = math.floor(Config.Lottery.ticketPrice * multiplier)
	return picked.name, multiplier, payout
end

local function showResultText(anchor: BasePart, outcomeName: string, payout: number)
	local ticketPrice = Config.Lottery.ticketPrice
	local net = payout - ticketPrice
	local text: string
	local color: Color3
	local textScale = 1
	if outcomeName == "jackpot" then
		text = "JACKPOT! +$" .. NumberFormatter.WithCommas(net)
		color = Theme.Gold
		textScale = 1.4
	elseif outcomeName == "bigWin" then
		text = "BIG WIN +$" .. NumberFormatter.WithCommas(net)
		color = Theme.CashPositive
		textScale = 1.15
	elseif outcomeName == "modestWin" then
		text = "+$" .. NumberFormatter.WithCommas(net)
		color = Theme.CashPositive
	else
		text = "-$" .. NumberFormatter.WithCommas(-net)
		color = Theme.Warning
	end

	FloatingText.Show(anchor, text, color, {
		size = UDim2.new(0, 220, 0, 64),
		riseDistance = 6,
		duration = 1.0,
		maxDistance = 100,
		textScale = textScale,
	})
end

local function checkCooldown(player: Player, booth: BasePart): boolean
	local now = os.clock()
	local playerCd = cooldowns[player]
	if playerCd and playerCd[booth] and now < playerCd[booth] then
		return false
	end
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][booth] = now + Config.Lottery.cooldown
	return true
end

local function onBoothTriggered(booth: BasePart, player: Player)
	if not checkCooldown(player, booth) then
		return
	end
	if not EconomyService.CanAfford(player, Config.Lottery.ticketPrice) then
		return
	end
	if not EconomyService.RemoveCash(player, Config.Lottery.ticketPrice) then
		return
	end
	local outcomeName, _multiplier, payout = LotteryService.RollOutcome()
	if payout > 0 then
		EconomyService.AddCash(player, payout)
	end
	showResultText(booth, outcomeName, payout)
end

function LotteryService.ActivateBooth(zoneFloor: BasePart)
	local zoneModel = zoneFloor.Parent
	if not zoneModel then
		return
	end
	if zoneModel:FindFirstChild("Booth") then
		return
	end

	local booth = Instance.new("Part")
	booth.Name = "Booth"
	booth.Anchored = true
	booth.CanCollide = true
	booth.Size = BOOTH_SIZE
	booth.Color = BOOTH_COLOR
	booth.Material = Enum.Material.Neon
	booth.Position = zoneFloor.Position + Vector3.new(0, 4 + BOOTH_SIZE.Y / 2, 0)
	booth.Parent = zoneModel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy Ticket"
	prompt.ObjectText = "Lottery ($" .. Config.Lottery.ticketPrice .. ")"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = booth

	prompt.Triggered:Connect(function(player)
		onBoothTriggered(booth, player)
	end)
end

function LotteryService.Init()
	local acc = outcomeCumulative[#outcomeCumulative].cumulative
	if math.abs(acc - 1) > 1e-6 then
		warn(("[LotteryService] outcome weights sum to %f, expected 1.0"):format(acc))
	end
end

return LotteryService
