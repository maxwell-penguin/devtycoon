-- Lottery Ticket Booth: server-authoritative weighted roll on ticket buy.
-- The client never sees or influences the RNG — it just walks up, presses
-- E, and watches the floating result text the server spawned. ZoneService
-- calls BuildBoothHero on zone purchase and ActivateBooth right after (also
-- on rejoin for owners).
--
-- All primitives — no Toolbox asset needed for a carnival booth. Foam
-- finger and duck mascot are simple part constructions rather than emoji-
-- BillboardGuis (no unicode glyph reads as either convincingly).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.PlanetHustleConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local EconomyService = require(script.Parent.EconomyService)
local FloatingText = require(ReplicatedStorage.Shared.Modules.FloatingText)
local NumberFormatter = require(ReplicatedStorage.Shared.Modules.NumberFormatter)

local LotteryService = {}

local BOOTH_BODY_COLOR = Theme.Secondary
local BOOTH_TRIM_COLOR = Color3.fromRGB(255, 255, 255)
local MARQUEE_COLOR = Color3.fromRGB(40, 20, 50)
local BULB_COLOR = Theme.Gold
local BALL_COLOR = Theme.Gold
local POST_COLOR = Color3.fromRGB(120, 120, 130)
local TICKET_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 220, 90),
}
local DUCK_COLOR = Color3.fromRGB(255, 210, 60)
local DUCK_BEAK_COLOR = Color3.fromRGB(255, 140, 30)
local FOAM_FINGER_COLOR = Color3.fromRGB(255, 210, 60)

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
	-- Lottery is a shared-world zone (no per-player-plot) - ownership is
	-- still tracked per-player, so only someone who has personally bought
	-- this zone can play, not any passerby.
	if not EconomyService.IsZoneOwned(player, "lottery") then
		return
	end
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

-- Scratch tickets on the ground, a "TODAY'S JACKPOT" flip-board showing the
-- actual configured jackpot range, a coin bucket, a foam #1 finger, and a
-- rubber duck mascot greeting players at the booth.
local function buildBoothDetails(hero: Model, base: Vector3)
	for i, color in ipairs(TICKET_COLORS) do
		local ticket = Instance.new("Part")
		ticket.Name = "ScratchTicket"
		ticket.Anchored = true
		ticket.CanCollide = false
		ticket.Material = Enum.Material.SmoothPlastic
		ticket.Color = color
		ticket.Size = Vector3.new(1.2, 0.05, 0.7)
		ticket.CFrame = CFrame.new(base + Vector3.new(-3 + i * 1.4, 0.05, 3 + (i % 2) * 0.6))
			* CFrame.Angles(0, math.rad(15 * i), 0)
		ticket.Parent = hero
	end

	local jackpotOutcome
	for _, o in ipairs(Config.Lottery.outcomes) do
		if o.name == "jackpot" then
			jackpotOutcome = o
		end
	end
	local jackpotText = "TODAY'S\nJACKPOT\n"
		.. (jackpotOutcome and (jackpotOutcome.minMultiplier .. "x-" .. jackpotOutcome.maxMultiplier .. "x") or "???")

	local flipPost = Instance.new("Part")
	flipPost.Name = "FlipBoardPost"
	flipPost.Anchored = true
	flipPost.CanCollide = false
	flipPost.Material = Enum.Material.Metal
	flipPost.Color = POST_COLOR
	flipPost.Size = Vector3.new(0.3, 4, 0.3)
	flipPost.CFrame = CFrame.new(base + Vector3.new(-4.5, 2, 3.5))
	flipPost.Parent = hero

	local flipBoard = Instance.new("Part")
	flipBoard.Name = "FlipBoard"
	flipBoard.Anchored = true
	flipBoard.CanCollide = false
	flipBoard.Material = Enum.Material.SmoothPlastic
	flipBoard.Color = Color3.fromRGB(20, 20, 25)
	flipBoard.Size = Vector3.new(2.6, 1.8, 0.2)
	flipBoard.CFrame = flipPost.CFrame * CFrame.new(0, 1.9, 0)
	flipBoard.Parent = hero

	local flipGui = Instance.new("SurfaceGui")
	flipGui.Face = Enum.NormalId.Back
	flipGui.Parent = flipBoard
	local flipLabel = Instance.new("TextLabel")
	flipLabel.BackgroundTransparency = 1
	flipLabel.Size = UDim2.fromScale(1, 1)
	flipLabel.Font = Enum.Font.Code
	flipLabel.TextScaled = true
	flipLabel.TextColor3 = BULB_COLOR
	flipLabel.TextWrapped = true
	flipLabel.Text = jackpotText
	flipLabel.Parent = flipGui

	local bucket = Instance.new("Part")
	bucket.Name = "CoinBucket"
	bucket.Shape = Enum.PartType.Cylinder
	bucket.Anchored = true
	bucket.CanCollide = false
	bucket.Material = Enum.Material.Metal
	bucket.Color = Color3.fromRGB(160, 160, 170)
	bucket.Size = Vector3.new(1.4, 1.2, 1.2)
	bucket.CFrame = CFrame.new(base + Vector3.new(4.5, 0.7, 3.5)) * CFrame.Angles(0, 0, math.rad(90))
	bucket.Parent = hero

	for i = 1, 5 do
		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Anchored = true
		coin.CanCollide = false
		coin.Material = Enum.Material.Neon
		coin.Color = Theme.Gold
		coin.Size = Vector3.new(0.15, 0.6, 0.6)
		coin.CFrame = bucket.CFrame * CFrame.new(0.5 + i * 0.05, (i - 3) * 0.15, (i - 3) * 0.1) * CFrame.Angles(0, math.rad(i * 20), math.rad(90))
		coin.Parent = hero
	end

	local fingerBase = Instance.new("Part")
	fingerBase.Name = "FoamFinger"
	fingerBase.Anchored = true
	fingerBase.CanCollide = false
	fingerBase.Material = Enum.Material.SmoothPlastic
	fingerBase.Color = FOAM_FINGER_COLOR
	fingerBase.Size = Vector3.new(0.8, 2.6, 0.5)
	fingerBase.CFrame = CFrame.new(base + Vector3.new(4.2, 1.3, -3)) * CFrame.Angles(0, 0, math.rad(-20))
	fingerBase.Parent = hero

	local fingerGui = Instance.new("SurfaceGui")
	fingerGui.Face = Enum.NormalId.Back
	fingerGui.Parent = fingerBase
	local fingerLabel = Instance.new("TextLabel")
	fingerLabel.BackgroundTransparency = 1
	fingerLabel.Size = UDim2.fromScale(1, 1)
	fingerLabel.Font = Enum.Font.FredokaOne
	fingerLabel.TextScaled = true
	fingerLabel.TextColor3 = Color3.fromRGB(30, 20, 10)
	fingerLabel.Text = "#1"
	fingerLabel.Parent = fingerGui

	local duckBody = Instance.new("Part")
	duckBody.Name = "DuckBody"
	duckBody.Shape = Enum.PartType.Ball
	duckBody.Anchored = true
	duckBody.CanCollide = false
	duckBody.Material = Enum.Material.SmoothPlastic
	duckBody.Color = DUCK_COLOR
	duckBody.Size = Vector3.new(1.6, 1.3, 1.5)
	duckBody.CFrame = CFrame.new(base + Vector3.new(-4.3, 0.65, -3))
	duckBody.Parent = hero

	local duckHead = Instance.new("Part")
	duckHead.Name = "DuckHead"
	duckHead.Shape = Enum.PartType.Ball
	duckHead.Anchored = true
	duckHead.CanCollide = false
	duckHead.Material = Enum.Material.SmoothPlastic
	duckHead.Color = DUCK_COLOR
	duckHead.Size = Vector3.new(0.9, 0.9, 0.9)
	duckHead.CFrame = duckBody.CFrame * CFrame.new(0, 0.9, 0.3)
	duckHead.Parent = hero

	local duckBeak = Instance.new("WedgePart")
	duckBeak.Name = "DuckBeak"
	duckBeak.Anchored = true
	duckBeak.CanCollide = false
	duckBeak.Material = Enum.Material.SmoothPlastic
	duckBeak.Color = DUCK_BEAK_COLOR
	duckBeak.Size = Vector3.new(0.4, 0.25, 0.5)
	duckBeak.CFrame = duckHead.CFrame * CFrame.new(0, -0.1, 0.55) * CFrame.Angles(0, math.rad(90), 0)
	duckBeak.Parent = hero
end

-- The Lottery "hero": ticket booth + canopy, twin posts holding a "JACKPOT"
-- marquee with staggered blinking bulbs, and a giant glowing lottery ball
-- on top. BoothCounter is the interactive part (ActivateBooth attaches the
-- prompt there).
function LotteryService.BuildBoothHero(zoneModel: Model, floor: BasePart): Model
	local hero = Instance.new("Model")
	hero.Name = "Hero"
	hero.Parent = zoneModel

	local base = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)

	local counter = Instance.new("Part")
	counter.Name = "BoothCounter"
	counter.Anchored = true
	counter.CanCollide = true
	counter.Material = Enum.Material.SmoothPlastic
	counter.Color = BOOTH_BODY_COLOR
	counter.Size = Vector3.new(4, 3.5, 3)
	counter.CFrame = CFrame.new(base + Vector3.new(0, 1.75, 0))
	counter.Parent = hero
	hero.PrimaryPart = counter

	local trim = Instance.new("Part")
	trim.Name = "CounterTrim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.Material = Enum.Material.SmoothPlastic
	trim.Color = BOOTH_TRIM_COLOR
	trim.Size = Vector3.new(4.1, 0.4, 3.1)
	trim.CFrame = counter.CFrame * CFrame.new(0, 1.4, 0)
	trim.Parent = hero

	local canopy = Instance.new("WedgePart")
	canopy.Name = "Canopy"
	canopy.Anchored = true
	canopy.CanCollide = false
	canopy.Material = Enum.Material.SmoothPlastic
	canopy.Color = BOOTH_BODY_COLOR
	canopy.Size = Vector3.new(1.4, 4.6, 3.6)
	canopy.CFrame = counter.CFrame * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(-90))
	canopy.Parent = hero

	local postHeight = 9
	for _, side in ipairs({ -1, 1 }) do
		local post = Instance.new("Part")
		post.Name = "MarqueePost"
		post.Anchored = true
		post.CanCollide = false
		post.Material = Enum.Material.Metal
		post.Color = POST_COLOR
		post.Size = Vector3.new(0.5, postHeight, 0.5)
		post.CFrame = CFrame.new(base + Vector3.new(side * 2.6, postHeight / 2, -2.2))
		post.Parent = hero
	end

	local marquee = Instance.new("Part")
	marquee.Name = "MarqueeBoard"
	marquee.Anchored = true
	marquee.CanCollide = false
	marquee.Material = Enum.Material.SmoothPlastic
	marquee.Color = MARQUEE_COLOR
	marquee.Size = Vector3.new(6.5, 2.2, 0.4)
	marquee.CFrame = CFrame.new(base + Vector3.new(0, postHeight - 1, -2.2))
	marquee.Parent = hero

	local marqueeGui = Instance.new("SurfaceGui")
	marqueeGui.Face = Enum.NormalId.Back
	marqueeGui.Parent = marquee
	local marqueeLabel = Instance.new("TextLabel")
	marqueeLabel.BackgroundTransparency = 0
	marqueeLabel.BackgroundColor3 = Color3.fromRGB(200, 30, 40)
	marqueeLabel.Size = UDim2.fromScale(1, 1)
	marqueeLabel.Font = Enum.Font.FredokaOne
	marqueeLabel.TextScaled = true
	marqueeLabel.TextColor3 = Theme.Gold
	marqueeLabel.Text = "JACKPOT"
	marqueeLabel.Parent = marqueeGui

	local bulbCount = 10
	for i = 1, bulbCount do
		local t = (i - 1) / (bulbCount - 1)
		local bulb = Instance.new("Part")
		bulb.Name = "Bulb"
		bulb.Shape = Enum.PartType.Ball
		bulb.Anchored = true
		bulb.CanCollide = false
		bulb.Material = Enum.Material.Neon
		bulb.Color = BULB_COLOR
		bulb.Size = Vector3.new(0.35, 0.35, 0.35)
		bulb.CFrame = marquee.CFrame * CFrame.new(-3.1 + t * 6.2, 1.25, 0.3)
		bulb.Parent = hero
		task.delay((i - 1) * 0.1, function()
			if bulb.Parent then
				TweenService:Create(
					bulb,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0.7 }
				):Play()
			end
		end)
	end

	local ball = Instance.new("Part")
	ball.Name = "LotteryBall"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.Material = Enum.Material.Neon
	ball.Color = BALL_COLOR
	ball.Size = Vector3.new(3, 3, 3)
	ball.CFrame = CFrame.new(base + Vector3.new(0, postHeight + 1.5, -2.2))
	ball.Parent = hero
	local ballLight = Instance.new("PointLight")
	ballLight.Color = BALL_COLOR
	ballLight.Range = 20
	ballLight.Brightness = 2.5
	ballLight.Parent = ball
	TweenService:Create(
		ball,
		TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = Vector3.new(3.3, 3.3, 3.3) }
	):Play()

	buildBoothDetails(hero, base)

	return hero
end

-- BoothCounter (built by BuildBoothHero) is the interactive part; this just
-- attaches the prompt to it rather than spawning a second booth block.
function LotteryService.ActivateBooth(zoneFloor: BasePart)
	local zoneModel = zoneFloor.Parent
	if not zoneModel then
		return
	end
	local hero = zoneModel:FindFirstChild("Hero")
	if not hero or hero:FindFirstChild("BuyTicketTrigger", true) then
		return
	end
	local counter = hero:FindFirstChild("BoothCounter") :: BasePart?
	if not counter then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyTicketTrigger"
	prompt.ActionText = "Buy Ticket"
	prompt.ObjectText = "Lottery ($" .. Config.Lottery.ticketPrice .. ")"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = counter

	prompt.Triggered:Connect(function(player)
		onBoothTriggered(counter, player)
	end)
end

function LotteryService.Init()
	local acc = outcomeCumulative[#outcomeCumulative].cumulative
	if math.abs(acc - 1) > 1e-6 then
		warn(("[LotteryService] outcome weights sum to %f, expected 1.0"):format(acc))
	end
end

return LotteryService
