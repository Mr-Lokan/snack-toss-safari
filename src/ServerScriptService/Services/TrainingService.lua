local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Formula = require(Shared:WaitForChild("Formula"))
local Game = require(Config:WaitForChild("Game"))
local Bars = require(Config:WaitForChild("Bars"))

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)

local notify = Net.Event("Notify")
local trainStart = Net.Event("TrainStart")
local trainState = Net.Event("TrainState")
local trainRep = Net.Event("TrainRep")
local trainStop = Net.Event("TrainStop")
local barUpgrade = Net.Event("BarUpgrade")
local trainBonus = Net.Event("TrainBonus")

local PING_MARGIN = 0.4
local START_RADIUS = 6 -- клиент шлет старт из круга радиусом ~3, тут с запасом
local UPGRADE_PAD_RADIUS = 5 -- с запасом к клиентским 3.6

-- У каждого игрока свой турник возле вольера, уровень турника - data.BarLevel.
-- Встал в круг под турником - висишь и подтягиваешься сам. Каждое подтягивание дает опыт,
-- полная шкала опыта - новый уровень тренировки и прибавка силы.
-- Само движение рисуют клиенты по атрибутам персонажа Hang и HangSince, чтобы было плавно.
local TrainingService = {}

local training = {} -- [player] = { stand, offerId, offerUntil, bonusUntil }
local barOf = {} -- [player] = турник, чтобы сбросить его вид при выходе
local rng = Random.new()

local function paintBar(stand, level, owned)
	local bar = Bars[level] or Bars[1]
	for _, piece in stand.paint do
		piece.Color = bar.color
		piece.Material = bar.material
	end
	if not owned then
		stand.title.Text = "Pull-up Bar"
		stand.title.TextColor3 = Bars[1].color
		stand.info.Text = ""
		stand.nextLabel.Text = ""
		return
	end
	stand.title.Text = bar.name .. " · Lv " .. level
	stand.title.TextColor3 = bar.color
	stand.info.Text = "+" .. Format.Number(bar.power) .. " XP per pull-up"
	local nextBar = Bars[level + 1]
	stand.nextLabel.Text = nextBar and ("Upgrade: " .. Format.Money(nextBar.price)) or "MAX LEVEL"
end

function TrainingService.UpdateBar(player)
	local plot = PlotService.GetPlot(player)
	local data = DataService.Get(player)
	if plot and data then
		barOf[player] = plot.bar
		paintBar(plot.bar, data.BarLevel, true)
	end
end

local function stop(player)
	local state = training[player]
	if not state then
		return
	end
	training[player] = nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character then
		character:SetAttribute("Hang", nil)
		character:SetAttribute("HangSince", nil)
	end
	if humanoid then
		humanoid.PlatformStand = false
	end
	if root then
		root.Anchored = false
		character:PivotTo(state.stand.exit)
	end
	trainState:FireClient(player, false)
end

local function rep(player, state)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local bar = Bars[data.BarLevel] or Bars[1]
	local boosted = os.clock() < (state.bonusUntil or 0)
	local gain = bar.power * MonetizationService.PowerMultiplier(player) * (boosted and 2 or 1)
	data.TrainXP += gain

	local levels, power = 0, 0
	while data.TrainXP >= Formula.XPNeed(data.TrainLevel) do
		local need = Formula.XPNeed(data.TrainLevel)
		data.TrainXP -= need
		data.TrainLevel += 1
		data.Power += need
		levels += 1
		power += need
	end
	DataService.Changed(player, "TrainXP", "TrainLevel", "Power")
	trainRep:FireClient(player, gain, boosted, levels > 0 and data.TrainLevel or nil, power)
end

-- подтягивания идут сами в ритме REP_TIME, пока игрок на турнике
local function repLoop(player, state)
	task.wait(Game.HANG_ENTER)
	while training[player] == state do
		task.wait(Game.REP_TIME)
		if training[player] ~= state then
			return
		end
		rep(player, state)
	end
end

-- кружки с бонусом x2, пока игрок висит на турнике
local function offerLoop(player, state)
	while training[player] == state do
		task.wait(rng:NextNumber(5, 9))
		if training[player] ~= state then
			return
		end
		state.offerId = (state.offerId or 0) + 1
		state.offerUntil = os.clock() + Game.BONUS_CIRCLE_TIME + PING_MARGIN
		trainBonus:FireClient(player, "offer", state.offerId, Game.BONUS_CIRCLE_TIME)
	end
end

local function start(player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if training[player] or not data or data.Carry or not plot or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local stand = plot.bar
	local offset = root.Position - stand.center
	if Vector2.new(offset.X, offset.Z).Magnitude > START_RADIUS then
		return
	end

	-- PlatformStand выключает анимации персонажа, иначе они ломают позу на турнике.
	-- Руки и ноги гнут клиенты (WorldFx), сервер только держит персонажа на месте
	humanoid.PlatformStand = true
	root.Anchored = true
	character:SetAttribute("Hang", stand.hang)
	character:SetAttribute("HangSince", workspace:GetServerTimeNow())
	local state = { stand = stand }
	training[player] = state
	trainState:FireClient(player, true)
	task.spawn(repLoop, player, state)
	task.spawn(offerLoop, player, state)
end

function TrainingService.IsTraining(player)
	return training[player] ~= nil
end

function TrainingService.Init()
	DataService.OnLoaded(TrainingService.UpdateBar)

	trainStart.OnServerEvent:Connect(start)
	trainStop.OnServerEvent:Connect(stop)

	trainBonus.OnServerEvent:Connect(function(player, id)
		local state = training[player]
		if not state or id ~= state.offerId or os.clock() > (state.offerUntil or 0) then
			return
		end
		state.offerUntil = 0 -- один кружок - один бонус
		state.bonusUntil = os.clock() + Game.BONUS_TIME
		trainBonus:FireClient(player, "active", Game.BONUS_TIME)
	end)

	-- улучшать можно только стоя на круглой платформе у своего турника
	barUpgrade.OnServerEvent:Connect(function(player)
		local data = DataService.Get(player)
		local plot = PlotService.GetPlot(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local nextBar = data and Bars[data.BarLevel + 1]
		if not nextBar or not plot or not root then
			return
		end
		local offset = root.Position - plot.bar.upgradePad
		if Vector2.new(offset.X, offset.Z).Magnitude > UPGRADE_PAD_RADIUS then
			return
		end
		if not DataService.Spend(player, nextBar.price) then
			notify:FireClient(player, "You need " .. Format.Money(nextBar.price) .. " for " .. nextBar.name, "bad")
			return
		end
		data.BarLevel += 1
		DataService.Changed(player, "BarLevel")
		TrainingService.UpdateBar(player)
		notify:FireClient(player, "Upgraded to " .. nextBar.name .. "!", "good", "upgrade")
	end)

	local function watch(player)
		player.CharacterRemoving:Connect(function()
			training[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
		if barOf[player] then
			paintBar(barOf[player], 1, false)
			barOf[player] = nil
		end
	end)
end

return TrainingService
