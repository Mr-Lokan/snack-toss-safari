local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Formula = require(Shared:WaitForChild("Formula"))
local Game = require(Config:WaitForChild("Game"))
local Foods = require(Config:WaitForChild("Foods"))
local Animals = require(Config:WaitForChild("Animals"))

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local MonetizationService = require(script.Parent.MonetizationService)
local TrainingService = require(script.Parent.TrainingService)

local throwRemote = Net.Event("Throw")
local resultRemote = Net.Event("ThrowResult")
local goThrowRemote = Net.Event("GoThrow")

local LANE_SPREAD = 8 -- насколько еда уходит вбок от игрока, каньон узкий

local ThrowService = {}

local rng = Random.new()
local nextThrow = {}
local catching = {} -- еда летит, животное еще не выдано

local function onThrow(player, p)
	if type(p) ~= "number" or p ~= p then
		return
	end
	p = math.clamp(p, 0, 1)

	local data = DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- пока пойманное животное не поставлено в вольер, новое не кидаем
	if not data or not root or data.Carry or catching[player] or TrainingService.IsTraining(player) then
		return
	end
	local now = os.clock()
	if now < (nextThrow[player] or 0) then
		return
	end
	if not Formula.IsOnThrowPad(root.Position) then
		return
	end

	local timing = Formula.Timing(p)
	local distance, zoneIndex = Formula.Distance(data.Power * timing.mult)
	local halfWidth = Game.FIELD_WIDTH / 2 - 15
	local landing = Vector3.new(
		Game.FIELD_START + distance,
		Game.FIELD_Y,
		math.clamp(root.Position.Z + rng:NextNumber(-LANE_SPREAD, LANE_SPREAD), -halfWidth, halfWidth)
	)
	local origin = root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1.5, 0)

	-- удача: еда * дальность полета * буст сервера
	local food = Foods.ById[data.Food] or Foods[1]
	local luck = food.luck * Formula.DistanceLuck(distance) * MonetizationService.LuckMultiplier()
	local rarity = Formula.RollRarity(luck, rng)
	local species = Animals.ByZone[zoneIndex][rarity]
	local mutation, giant = Formula.RollMutation(rng)
	local animal = { id = species.id, m = mutation, g = giant or nil }

	local flightTime = Formula.FlightTime(distance)
	nextThrow[player] = now + flightTime + Game.EAT_TIME

	data.Throws += 1
	data.BestDistance = math.max(data.BestDistance, distance)
	data.BestOdds = math.max(data.BestOdds, Formula.CatchOdds(animal))
	DataService.Changed(player, "Throws", "BestDistance", "BestOdds")

	resultRemote:FireAllClients({
		player = player,
		food = food.id,
		from = origin,
		to = landing,
		time = flightTime,
		timing = table.find(Formula.TIMING, timing),
		zone = zoneIndex,
		luck = luck,
		animal = { id = animal.id, m = animal.m, g = animal.g },
	})

	-- когда животное поест, игрок получает его в руки и переносится к вольеру
	catching[player] = true
	task.delay(flightTime + Game.EAT_TIME + 0.4, function()
		catching[player] = nil
		if player.Parent then
			PlotService.Catch(player, animal)
		end
	end)
end

-- кнопка Throw в меню: сразу на свое место в зоне броска (от дальних вольеров идти втрое дольше)
local LANE_STEP = 9 -- как в ThrowController
local goCooldown = {}

local function goThrow(player)
	local now = os.clock()
	if now < (goCooldown[player] or 0) then
		return
	end
	goCooldown[player] = now + 1
	local data = DataService.Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not humanoid or humanoid.Health <= 0 or data.Carry or catching[player] or TrainingService.IsTraining(player) then
		return
	end
	local plot = PlotService.GetPlot(player)
	local z = plot and math.clamp(plot.index - 3, -2, 2) * LANE_STEP or 0
	local pad = Game.THROW_PAD
	character:PivotTo(CFrame.lookAt(Vector3.new(pad.x, 3.5, z), Vector3.new(pad.x + 10, 3.5, z)))
end

function ThrowService.Init()
	throwRemote.OnServerEvent:Connect(onThrow)
	goThrowRemote.OnServerEvent:Connect(goThrow)
	Players.PlayerRemoving:Connect(function(player)
		nextThrow[player] = nil
		catching[player] = nil
		goCooldown[player] = nil
	end)
end

return ThrowService
