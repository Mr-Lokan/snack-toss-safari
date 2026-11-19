local controllers = script.Parent:WaitForChild("Controllers")

local State = require(controllers:WaitForChild("State"))
local UI = require(controllers:WaitForChild("UI"))
local ThrowController = require(controllers:WaitForChild("ThrowController"))
local TrainingController = require(controllers:WaitForChild("TrainingController"))
local PenController = require(controllers:WaitForChild("PenController"))
local WorldFx = require(controllers:WaitForChild("WorldFx"))

UI.Init()
ThrowController.Init()
TrainingController.Init()
PenController.Init()
WorldFx.Init()

-- подписки готовы, теперь просим данные у сервера
State.Init()
