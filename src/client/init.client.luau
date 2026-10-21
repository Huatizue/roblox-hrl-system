--!strict

local LauncherController = require(script.LauncherController)
local RocketRenderer = require(script.RocketRenderer)

require(script.ArmPose).start()
RocketRenderer.start(LauncherController)
LauncherController.start(RocketRenderer.hasSteerableRocket)
