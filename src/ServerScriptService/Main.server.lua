local services = script.Parent:WaitForChild("Services")

local MapService = require(services.MapService)
local DataService = require(services.DataService)
local MonetizationService = require(services.MonetizationService)
local PlotService = require(services.PlotService)
local TrainingService = require(services.TrainingService)
local ThrowService = require(services.ThrowService)
local ShopService = require(services.ShopService)
local LeaderboardService = require(services.LeaderboardService)
local CharacterService = require(services.CharacterService)

local map = MapService.Build()

CharacterService.Init()
MonetizationService.Init()
PlotService.Init(map)
TrainingService.Init()
ThrowService.Init()
ShopService.Init(map)
LeaderboardService.Init(map)

-- данные грузим последними, когда все подписались на OnLoaded
DataService.Init()
