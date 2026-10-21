--!strict

local Players = game:GetService("Players")

local Hud = {}

local gui: ScreenGui
local modeLabel: TextLabel
local hintLabel: TextLabel
local lockBox: Frame
local lockStroke: UIStroke
local lockLabel: TextLabel

local ACQUIRING = Color3.fromRGB(255, 210, 60)
local LOCKED = Color3.fromRGB(255, 60, 60)

local function label(name: string, position: UDim2, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 1)
	text.Position = position
	text.Size = UDim2.fromOffset(600, size + 6)
	text.BackgroundTransparency = 1
	text.TextSize = size
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.5
	text.Parent = gui
	return text
end

function Hud.create()
	gui = Instance.new("ScreenGui")
	gui.Name = "MissileHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	modeLabel = label("Mode", UDim2.new(0.5, 0, 1, -64), 20)
	hintLabel = label("Hint", UDim2.new(0.5, 0, 1, -40), 14)

	lockBox = Instance.new("Frame")
	lockBox.Name = "LockBox"
	lockBox.AnchorPoint = Vector2.new(0.5, 0.5)
	lockBox.Size = UDim2.fromOffset(56, 56)
	lockBox.BackgroundTransparency = 1
	lockBox.Visible = false
	lockBox.Parent = gui
	lockStroke = Instance.new("UIStroke")
	lockStroke.Thickness = 2
	lockStroke.Parent = lockBox
	lockLabel = Instance.new("TextLabel")
	lockLabel.AnchorPoint = Vector2.new(0.5, 0)
	lockLabel.Position = UDim2.new(0.5, 0, 1, 4)
	lockLabel.Size = UDim2.fromOffset(120, 16)
	lockLabel.BackgroundTransparency = 1
	lockLabel.TextSize = 13
	lockLabel.TextStrokeTransparency = 0.5
	lockLabel.Parent = lockBox
end

function Hud.setMode(mode: string)
	if mode == "Cursor" then
		modeLabel.Text = ""
		hintLabel.Text = "Hold click to fire and steer  ·  Hold E to steer your last rocket  ·  Q: lock-on mode"
	else
		modeLabel.Text = "LOCK-ON HOMING"
		hintLabel.Text = "Aim at a target, then click: lock % is the chance to hit  ·  Q: cursor mode"
	end
end

function Hud.setLock(screenPosition: Vector2?, progress: number?)
	if not screenPosition or not progress then
		lockBox.Visible = false
		return
	end
	local locked = progress >= 1
	local color = if locked then LOCKED else ACQUIRING
	lockBox.Visible = true
	lockBox.Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y)
	local size = 80 - 32 * math.clamp(progress, 0, 1)
	lockBox.Size = UDim2.fromOffset(size, size)
	lockStroke.Color = color
	lockLabel.TextColor3 = color
	lockLabel.Text = if locked then "LOCKED 100%" else `{math.floor(progress * 100)}% HIT`
end

function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
end

return Hud
