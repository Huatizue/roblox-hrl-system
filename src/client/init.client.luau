--!strict

local LauncherController = require(script.LauncherController)
local RocketRenderer = require(script.RocketRenderer)

RocketRenderer.start(LauncherController)
LauncherController.start(RocketRenderer.hasSteerableRocket)
