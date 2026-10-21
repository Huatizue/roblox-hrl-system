--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HomingMissile").Config)

local MissileService = require(script.MissileService)
MissileService.start()

require(script.LauncherRig).start()

if Config.Demo.Enabled then
	require(script.Demo.DroneTargets).start()
end
