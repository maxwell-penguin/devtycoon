-- The zone-purchase "money shot": floor flash -> camera shake -> tile
-- cascade (reveals outward from the corner nearest the buyer) -> hero prop
-- rise -> particle burst -> floating result text. Every zone's purchase
-- animation routes through here so the feel stays consistent as zone-
-- specific hero props get built out (Step: visual pass, zone-by-zone).
--
-- Sound picks below were chosen by name/description match only — there's
-- no audio-preview tool available, so LISTEN TO THESE IN STUDIO before
-- shipping and swap the SoundId strings if either doesn't fit:
--   WHOOSH_SOUND_ID: "Wind Burst Alien Vortex Blasts 7 (SFX)" by ProSoundEffects
--   CHIME_SOUND_ID:  "retro coin pickup sound effect powerup" by Greengem353
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local FloatingText = require(ReplicatedStorage.Shared.Modules.FloatingText)

local PurchaseEffects = {}

local WHOOSH_SOUND_ID = "rbxassetid://9120749306"
local CHIME_SOUND_ID = "rbxassetid://93529351909119"

local CAMERA_SHAKE_REMOTE_NAME = "ZoneCameraShake"
local GRID_SIZE = 4
local TILE_TWEEN_TIME = 0.15
local TILE_STAGGER = 0.025
local HERO_RISE_DELAY = 0.35
local HERO_RISE_TIME = 0.45
local RESULT_TEXT_DELAY = 0.55

local function getCameraShakeRemote(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:FindFirstChild(CAMERA_SHAKE_REMOTE_NAME) :: RemoteEvent?
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = CAMERA_SHAKE_REMOTE_NAME
		remote.Parent = remotes
	end
	return remote :: RemoteEvent
end

function PurchaseEffects.Init()
	getCameraShakeRemote()
end

local function playSound(soundId: string, parent: Instance, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

function PurchaseEffects.CameraShake(buyer: Player, duration: number, amplitude: number)
	getCameraShakeRemote():FireClient(buyer, duration, amplitude)
end

-- Nearest of the floor's 4 corners to `fromPosition`, as (0|1, 0|1) grid
-- coordinates — used to order the tile cascade reveal outward from there.
local function nearestCornerGrid(floor: BasePart, fromPosition: Vector3): (number, number)
	local half = floor.Size / 2
	local flat = Vector3.new(1, 0, 1)
	local corners = {
		{ 0, 0, floor.Position + Vector3.new(-half.X, 0, -half.Z) },
		{ 1, 0, floor.Position + Vector3.new(half.X, 0, -half.Z) },
		{ 0, 1, floor.Position + Vector3.new(-half.X, 0, half.Z) },
		{ 1, 1, floor.Position + Vector3.new(half.X, 0, half.Z) },
	}
	local best = corners[1]
	local bestDist = math.huge
	for _, c in ipairs(corners) do
		local dist = ((c[3] :: Vector3) * flat - fromPosition * flat).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = c
		end
	end
	return best[1], best[2]
end

local function buildFloorTiles(zoneModel: Model, floor: BasePart, ownedColor: Color3, animate: boolean, cornerX: number, cornerZ: number)
	if zoneModel:FindFirstChild("FloorTiles") then
		return
	end
	local tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "FloorTiles"
	tilesFolder.Parent = zoneModel

	local tileSizeX = floor.Size.X / GRID_SIZE
	local tileSizeZ = floor.Size.Z / GRID_SIZE
	local cornerRow = cornerZ * (GRID_SIZE - 1)
	local cornerCol = cornerX * (GRID_SIZE - 1)

	local tiles = {}
	for row = 0, GRID_SIZE - 1 do
		for col = 0, GRID_SIZE - 1 do
			local tile = Instance.new("Part")
			tile.Name = "Tile"
			tile.Anchored = true
			tile.CanCollide = false
			tile.Material = Enum.Material.Neon
			tile.Color = ownedColor
			local localX = (col + 0.5) * tileSizeX - floor.Size.X / 2
			local localZ = (row + 0.5) * tileSizeZ - floor.Size.Z / 2
			local finalSize = Vector3.new(tileSizeX * 0.94, 0.3, tileSizeZ * 0.94)
			tile.Position = floor.Position + Vector3.new(localX, 0.15, localZ)
			tile.Parent = tilesFolder

			if animate then
				tile.Size = Vector3.new(0.1, 0.3, 0.1)
				tile.Transparency = 1
				local dist = math.abs(row - cornerRow) + math.abs(col - cornerCol)
				table.insert(tiles, { part = tile, dist = dist, finalSize = finalSize })
			else
				tile.Size = finalSize
				tile.Transparency = 0
			end
		end
	end

	if animate then
		table.sort(tiles, function(a, b)
			return a.dist < b.dist
		end)
		for i, t in ipairs(tiles) do
			task.delay((i - 1) * TILE_STAGGER, function()
				if not t.part.Parent then
					return
				end
				TweenService:Create(t.part, TweenInfo.new(TILE_TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = t.finalSize,
					Transparency = 0,
				}):Play()
			end)
		end
	end
end

local function particleBurst(position: Vector3, zoneModel: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "BurstAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = zoneModel

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.0)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Brand),
		ColorSequenceKeypoint.new(1, Theme.Gold),
	})
	emitter.Parent = anchor
	emitter:Emit(30)

	local ring = Instance.new("Part")
	ring.Name = "BurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Theme.CashPositive
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = zoneModel
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 14, 14),
		Transparency = 1,
	}):Play()

	Debris:AddItem(anchor, 1.5)
	Debris:AddItem(ring, 0.6)
end

local function getHeroPosition(hero: Model | BasePart): Vector3
	if hero:IsA("Model") then
		return hero:GetPivot().Position
	end
	return (hero :: BasePart).Position
end

-- Single Part heroes (current placeholder blocks): scale-up overshoot, same
-- as before. Model heroes (imported multi-part assets like the Rideshare
-- car): Model has no tweenable CFrame property, so TweenService can't
-- animate PivotTo directly — instead we lerp a throwaway NumberValue 0->1
-- with the same easing and drive PivotTo manually off its Changed signal.
-- Models rise up out of the floor (position only, no scale) rather than
-- scaling from tiny, since scaling a multi-part hierarchy frame-by-frame
-- isn't worth the engineering cost for a one-shot cosmetic reveal.
local function riseHero(hero: Model | BasePart, animate: boolean)
	if not animate then
		return
	end

	if hero:IsA("BasePart") then
		local part = hero :: BasePart
		local finalSize = part.Size
		part.Size = Vector3.new(
			math.max(finalSize.X * 0.05, 0.2),
			math.max(finalSize.Y * 0.05, 0.2),
			math.max(finalSize.Z * 0.05, 0.2)
		)
		task.delay(HERO_RISE_DELAY, function()
			if not part.Parent then
				return
			end
			TweenService:Create(part, TweenInfo.new(HERO_RISE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = finalSize,
			}):Play()
		end)
		return
	end

	local model = hero :: Model
	local finalCFrame = model:GetPivot()
	local _, boundingSize = model:GetBoundingBox()
	local startCFrame = finalCFrame * CFrame.new(0, -boundingSize.Y, 0)
	model:PivotTo(startCFrame)

	task.delay(HERO_RISE_DELAY, function()
		if not model.Parent then
			return
		end
		local alpha = Instance.new("NumberValue")
		alpha.Value = 0
		alpha.Parent = model
		local conn: RBXScriptConnection
		conn = alpha:GetPropertyChangedSignal("Value"):Connect(function()
			if model.Parent then
				model:PivotTo(startCFrame:Lerp(finalCFrame, alpha.Value))
			end
		end)
		local tween = TweenService:Create(alpha, TweenInfo.new(HERO_RISE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
		tween.Completed:Connect(function()
			conn:Disconnect()
			if model.Parent then
				model:PivotTo(finalCFrame)
			end
			alpha:Destroy()
		end)
		tween:Play()
	end)
end

export type ApplyVisualsOptions = {
	zoneModel: Model,
	floor: BasePart,
	hero: Model | BasePart,
	ownedColor: Color3,
	animate: boolean,
	buyer: Player?, -- required when animate = true
	resultText: string?, -- required when animate = true
	resultColor: Color3?, -- required when animate = true
}

-- animate=false is the instant rejoin path (SyncPlayerZones): final state,
-- no tweens, no shake, no sound. animate=true is the full money-shot.
function PurchaseEffects.ApplyOwnedVisuals(opts: ApplyVisualsOptions)
	local floor, zoneModel, hero = opts.floor, opts.zoneModel, opts.hero

	if not opts.animate then
		floor.Color = opts.ownedColor
		buildFloorTiles(zoneModel, floor, opts.ownedColor, false, 0, 0)
		return
	end

	local buyer = assert(opts.buyer, "ApplyOwnedVisuals: buyer required when animate=true")
	local resultText = assert(opts.resultText, "ApplyOwnedVisuals: resultText required when animate=true")
	local resultColor = assert(opts.resultColor, "ApplyOwnedVisuals: resultColor required when animate=true")

	-- t=0: floor flash (locked -> affordable-pulse -> owned), camera shake, whoosh
	TweenService:Create(floor, TweenInfo.new(0.08, Enum.EasingStyle.Sine), { Color = Theme.AffordablePulse }):Play()
	task.delay(0.08, function()
		if floor.Parent then
			TweenService:Create(floor, TweenInfo.new(0.07, Enum.EasingStyle.Sine), { Color = opts.ownedColor }):Play()
		end
	end)

	local hrp = buyer.Character and buyer.Character:FindFirstChild("HumanoidRootPart")
	local buyerPos = (hrp and (hrp :: BasePart).Position) or floor.Position
	local cornerX, cornerZ = nearestCornerGrid(floor, buyerPos)
	buildFloorTiles(zoneModel, floor, opts.ownedColor, true, cornerX, cornerZ)

	PurchaseEffects.CameraShake(buyer, 0.35, 0.4)
	playSound(WHOOSH_SOUND_ID, floor, 0.5)

	-- t=0.35: hero rises, particle burst, chime
	riseHero(hero, true)
	task.delay(HERO_RISE_DELAY, function()
		if not floor.Parent then
			return
		end
		particleBurst(getHeroPosition(hero), zoneModel)
		playSound(CHIME_SOUND_ID, floor, 0.6)
	end)

	-- t=0.55: floating result text lands after the hero settles
	task.delay(RESULT_TEXT_DELAY, function()
		if floor.Parent then
			FloatingText.Show(floor, resultText, resultColor)
		end
	end)
end

return PurchaseEffects
