--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Targets = require(Shared.Targets)

local Hud = require(script.Parent.Hud)

local TAKE_CONTROL_ACTION = "HomingMissileTakeControl"
local TOGGLE_MODE_ACTION = "HomingMissileToggleMode"

local LauncherController = {}

local localPlayer = Players.LocalPlayer
local remotes = Net.get()

local mode: "Cursor" | "Homing" = "Cursor"
local equippedTool: Tool? = nil
local fireHeld = false
local controlHeld = false
local steering = false
local lastFireTime = -math.huge
local aimTimer = 0
local lastTouchPosition: Vector2? = nil

local lockCandidate: Instance? = nil
local lockProgress = 0

local hasSteerableRocket: () -> boolean = function()
	return false
end

function LauncherController.getAimRay(): Ray
	local camera = workspace.CurrentCamera
	local screenPoint: Vector2
	if UserInputService.MouseEnabled then
		screenPoint = UserInputService:GetMouseLocation()
	elseif lastTouchPosition then
		screenPoint = lastTouchPosition
	else
		screenPoint = camera.ViewportSize / 2
	end
	return camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
end

function LauncherController.isSteering(): boolean
	return steering
end

local function setSteering(active: boolean)
	if active == steering then
		return
	end
	steering = active
	remotes.SetSteering:FireServer(active)
	if active then
		aimTimer = 0
	end
end

local function refreshSteering()
	setSteering((fireHeld and mode == "Cursor") or (controlHeld and hasSteerableRocket()))
	Hud.setVisible(equippedTool ~= nil or steering)
end

local function sendAim()
	local ray = LauncherController.getAimRay()
	remotes.Aim:FireServer(ray.Origin, ray.Direction.Unit)
end

local function onActivated()
	fireHeld = true
	if os.clock() - lastFireTime < Config.FireCooldown then
		return
	end
	local ray = LauncherController.getAimRay()

	if mode == "Cursor" then
		lastFireTime = os.clock()
		remotes.Fire:FireServer("Cursor", ray.Origin, ray.Direction.Unit)
		refreshSteering()
	elseif lockCandidate then
		lastFireTime = os.clock()
		remotes.Fire:FireServer("Homing", ray.Origin, ray.Direction.Unit, lockCandidate, lockProgress)
	end
end

local function onDeactivated()
	fireHeld = false
	refreshSteering()
end

local function onTakeControl(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		controlHeld = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		controlHeld = false
	end
	refreshSteering()
	return Enum.ContextActionResult.Sink
end

local function onToggleMode(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		mode = if mode == "Cursor" then "Homing" else "Cursor"
		lockCandidate, lockProgress = nil, 0
		Hud.setMode(mode)
		Hud.setLock(nil, nil)
		refreshSteering()
	end
	return Enum.ContextActionResult.Sink
end

local function updateLock(dt: number)
	if mode ~= "Homing" or not equippedTool then
		lockCandidate, lockProgress = nil, 0
		Hud.setLock(nil, nil)
		return
	end

	local ray = LauncherController.getAimRay()
	local direction = ray.Direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character :: Instance }

	local best: Instance? = nil
	local bestAngle = math.rad(Config.LockConeAngle)
	for _, target in Targets.all() do
		local position = Targets.getPosition(target)
		if position then
			local offset = position - ray.Origin
			local distance = offset.Magnitude
			local angle = math.acos(math.clamp(offset.Unit:Dot(direction), -1, 1))
			if distance <= Config.LockRange and angle < bestAngle then
				local hit = workspace:Raycast(ray.Origin, offset, params)
				if hit == nil or Targets.fromPart(hit.Instance) == target then
					best, bestAngle = target, angle
				end
			end
		end
	end

	if best ~= lockCandidate then
		lockCandidate, lockProgress = best, 0
	elseif best then
		lockProgress = math.min(lockProgress + dt / Config.LockTime, 1)
	end

	local position = lockCandidate and Targets.getPosition(lockCandidate)
	if position then
		local screen, onScreen = workspace.CurrentCamera:WorldToViewportPoint(position)
		Hud.setLock(if onScreen then Vector2.new(screen.X, screen.Y) else nil, lockProgress)
	else
		Hud.setLock(nil, nil)
	end
end

local function onRenderStepped(dt: number)
	updateLock(dt)

	if steering and not fireHeld and not hasSteerableRocket() then
		refreshSteering()
	end

	if steering then
		aimTimer -= dt
		if aimTimer <= 0 then
			aimTimer = 1 / Config.AimUpdateRate
			sendAim()
		end
	end
end

local function bindTool(tool: Tool)
	tool.Equipped:Connect(function()
		equippedTool = tool
		ContextActionService:BindAction(
			TOGGLE_MODE_ACTION,
			onToggleMode,
			true,
			Config.ToggleModeKey,
			Enum.KeyCode.ButtonY
		)
		ContextActionService:SetTitle(TOGGLE_MODE_ACTION, "Mode")
		Hud.setMode(mode)
		refreshSteering()
	end)
	tool.Unequipped:Connect(function()
		equippedTool = nil
		fireHeld = false
		ContextActionService:UnbindAction(TOGGLE_MODE_ACTION)
		Hud.setLock(nil, nil)
		refreshSteering()
	end)
	tool.Activated:Connect(onActivated)
	tool.Deactivated:Connect(onDeactivated)
end

local function watchContainer(container: Instance)
	local function check(child: Instance)
		if
			child:IsA("Tool")
			and child.Name == Config.LauncherToolName
			and not child:GetAttribute("HomingMissileBound")
		then
			child:SetAttribute("HomingMissileBound", true)
			bindTool(child)
		end
	end
	for _, child in container:GetChildren() do
		check(child)
	end
	container.ChildAdded:Connect(check)
end

function LauncherController.start(steerableRocketQuery: () -> boolean)
	hasSteerableRocket = steerableRocketQuery
	Hud.create()

	ContextActionService:BindAction(
		TAKE_CONTROL_ACTION,
		onTakeControl,
		true,
		Config.TakeControlKey,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:SetTitle(TAKE_CONTROL_ACTION, "Steer")

	UserInputService.TouchMoved:Connect(function(touch: InputObject)
		lastTouchPosition = Vector2.new(touch.Position.X, touch.Position.Y)
	end)
	UserInputService.TouchStarted:Connect(function(touch: InputObject)
		lastTouchPosition = Vector2.new(touch.Position.X, touch.Position.Y)
	end)

	watchContainer(localPlayer:WaitForChild("Backpack"))
	localPlayer.CharacterAdded:Connect(function(character)
		watchContainer(character)
		watchContainer(localPlayer:WaitForChild("Backpack"))
	end)
	if localPlayer.Character then
		watchContainer(localPlayer.Character)
	end

	RunService.RenderStepped:Connect(onRenderStepped)
end

return LauncherController
