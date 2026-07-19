-- Shared floating BillboardGui text: rises + fades over ~0.8-1s. Used for
-- reward pop-ups, purchase confirmations, and afford-fail warnings. Server-
-- only (creates real Instances), but lives in shared/ since it has no
-- server-specific dependencies and multiple server systems require it.
local TweenService = game:GetService("TweenService")

local FloatingText = {}

export type ShowOptions = {
	size: UDim2?, -- default 160x56
	studsOffset: Vector3?, -- default (0, 4, 0)
	riseDistance: number?, -- default 5 studs
	duration: number?, -- default 0.9s
	maxDistance: number?, -- default 80
	textScale: number?, -- multiplies the default TextScaled sizing via a UIScale, default 1
}

function FloatingText.Show(anchor: BasePart, text: string, color: Color3, opts: ShowOptions?)
	opts = opts or {}
	local size = opts.size or UDim2.new(0, 160, 0, 56)
	local startOffset = opts.studsOffset or Vector3.new(0, 4, 0)
	local riseDistance = opts.riseDistance or 5
	local duration = opts.duration or 0.9
	local maxDistance = opts.maxDistance or 80

	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatingText"
	gui.Adornee = anchor
	gui.Size = size
	gui.StudsOffset = startOffset
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui

	if opts.textScale and opts.textScale ~= 1 then
		local scale = Instance.new("UIScale")
		scale.Scale = opts.textScale
		scale.Parent = label
	end

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = startOffset + Vector3.new(0, riseDistance, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	task.delay(duration + 0.05, function()
		gui:Destroy()
	end)
end

return FloatingText
