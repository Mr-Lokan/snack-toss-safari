local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Formula = require(Shared:WaitForChild("Formula"))
local AnimalModel = require(Shared:WaitForChild("AnimalModel"))
local Game = require(Config:WaitForChild("Game"))
local Animals = require(Config:WaitForChild("Animals"))
local Rarities = require(Config:WaitForChild("Rarities"))

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

local notify = Net.Event("Notify")
local placeRemote = Net.Event("PlaceCarry")
local pickUpRemote = Net.Event("PickUp")
local equipRemote = Net.Event("EquipBackpack")
local equipBestRemote = Net.Event("EquipBest")
local sellRemote = Net.Event("SellAnimals")
local sellBackpackRemote = Net.Event("SellBackpack")

local CARRY_HEIGHT = 2.7 -- над корнем персонажа, примерно макушка
local CARRY_MAX_SIZE = 4.5 -- крупных животных над головой уменьшаем
local PLACE_REACH = 70 -- насколько далеко от центра вольера можно стоять, когда ставишь животное

-- Вольеры игроков. data.Animals - животные в вольере (список в интерфейсе совпадает с вольером).
-- Пойманное животное (data.Carry) игрок несет над головой и ставит в вольер кликом.
-- data.Backpack - животные, вынесенные из вольера на продажу.
local PlotService = {}

local plots -- из MapService
local plotOf = {} -- [player] = plot
local modelsOf = {} -- [player] = { [uid] = model }
local incomeOf = {}
local carried = {} -- [player] = модель над головой
local farmFolder
local rng = Random.new()

local function countAnimals(data)
	local n = 0
	for _ in data.Animals do
		n += 1
	end
	return n
end

local function randomSpot(plot)
	local r = plot.half - 4
	return { x = rng:NextNumber(-r, r), z = rng:NextNumber(-r, r) }
end

local function spotCFrame(plot, pos)
	local position = plot.center + Vector3.new(pos.x, 0, pos.z)
	return CFrame.lookAt(position, position + Vector3.xAxis)
end

local function buildModel(player, uid, animal, plot)
	local model = AnimalModel.Build(animal)
	model.Name = uid

	-- над животным имя цветом редкости и доход
	local species = Animals.ById[animal.id]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag" -- клиент прячет подписи, которые налезают на соседние (WorldFx)
	gui.Size = UDim2.fromScale(7, 2.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, AnimalModel.Height(model) + 1.4, 0)
	gui.MaxDistance = 50
	gui.LightInfluence = 0
	gui.Adornee = model.PrimaryPart
	local lines = {
		{ Formula.AnimalName(animal), Rarities[species.rarity].color },
		{ Format.Money(Formula.Income(animal)) .. "/s", Color3.fromRGB(130, 255, 130) },
	}
	for i, line in lines do
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromScale(0, (i - 1) * 0.5)
		text.Size = UDim2.fromScale(1, 0.5)
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.Text = line[1]
		text.TextColor3 = line[2]
		text.TextStrokeTransparency = 0
		text.Parent = gui
	end
	gui.Parent = model

	-- клиент по этим атрибутам водит животное по вольеру
	local cframe = spotCFrame(plot, animal.pos)
	model:PivotTo(cframe)
	model:SetAttribute("Home", cframe)
	model:SetAttribute("PenCenter", plot.center)
	model:SetAttribute("PenHalf", plot.half)
	model.Parent = farmFolder:FindFirstChild(player.Name) or farmFolder
	return model
end

local function render(player, data)
	local plot = plotOf[player]
	local models = modelsOf[player]
	if not plot or not models then
		return
	end
	-- вольер растет с каждым купленным местом: животным новые границы, гуляют они уже по большому
	if plot.resize(Formula.PenSize(data.Slots)) then
		for uid, model in models do
			local animal = data.Animals[uid]
			if animal and animal.pos then
				model:SetAttribute("Home", spotCFrame(plot, animal.pos))
			end
			model:SetAttribute("PenCenter", plot.center)
			model:SetAttribute("PenHalf", plot.half)
		end
	end
	local count = 0
	for uid, animal in data.Animals do
		count += 1
		if not animal.pos then
			animal.pos = randomSpot(plot)
		end
		if not models[uid] then
			models[uid] = buildModel(player, uid, animal, plot)
		end
	end
	for uid, model in models do
		if not data.Animals[uid] then
			model:Destroy()
			models[uid] = nil
		end
	end
	plot.incomeLabel.Text = "+" .. Format.Money(incomeOf[player] or 0) .. "/s"
	plot.countLabel.Text = count .. "/" .. data.Slots
	plot.countLabel.Parent.Visible = true

	-- табличка расширения вольера у входа
	if data.Slots >= Game.MAX_SLOTS then
		plot.spaceTitle.Text = tostring(data.Slots)
		plot.spacePrice.Text = "MAX"
	else
		plot.spaceTitle.Text = data.Slots .. " > " .. data.Slots + 1
		plot.spacePrice.Text = Format.Money(Formula.SlotPrice(data.Slots))
	end
end

-- пересчитать доход и перерисовать вольер
function PlotService.Refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local income = 0
	for _, animal in data.Animals do
		income += Formula.Income(animal)
	end
	income *= MonetizationService.CashMultiplier(player)
	incomeOf[player] = income
	player:SetAttribute("Income", income)
	render(player, data)
end

function PlotService.GetPlot(player)
	return plotOf[player]
end

local function detachCarry(player)
	if carried[player] then
		carried[player]:Destroy()
		carried[player] = nil
	end
end

-- модель животного, которое сейчас в руках, над головой игрока
local function attachCarry(player)
	detachCarry(player)
	local data = DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local animal = data and data.Carry
	if not animal or not root then
		return
	end

	local model = AnimalModel.Build(animal)
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > CARRY_MAX_SIZE then
		model:ScaleTo(model:GetScale() * CARRY_MAX_SIZE / biggest)
	end

	local main = model.PrimaryPart
	local mainOffset = model:GetPivot():ToObjectSpace(main.CFrame)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part ~= main then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = main
				weld.Part1 = part
				weld.Parent = main
			end
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
		end
	end
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = main
	weld.C0 = CFrame.new(0, CARRY_HEIGHT, 0) * mainOffset
	weld.Parent = main

	model.Name = "Carried"
	model.Parent = character
	carried[player] = model
end

-- к своему вольеру; новичок (еще ни разу не кидал) - лицом к зоне броска
local function teleportHome(player, character)
	local plot = plotOf[player]
	character = character or player.Character
	if plot and character and character:FindFirstChild("HumanoidRootPart") then
		local data = DataService.Get(player)
		local fresh = data and (data.Throws or 0) == 0 and not data.Carry
		character:PivotTo(fresh and plot.welcome or plot.spawn)
	end
end

-- поймал животное: оно над головой, игрок у своего вольера
function PlotService.Catch(player, animal)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Carry = animal
	data.Index[animal.id] = true
	DataService.Changed(player, "Carry", "Index")
	attachCarry(player)
	teleportHome(player)
end

local function addToPen(data, animal, pos)
	animal.pos = pos
	local uid = "a" .. data.NextUid
	data.NextUid += 1
	data.Animals[uid] = animal
	return uid
end

local function changedAll(player)
	DataService.Changed(player, "Animals", "Backpack", "Carry", "NextUid")
	PlotService.Refresh(player)
	attachCarry(player)
end

function PlotService.SellAnimals(player, uids)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local total, count = 0, 0
	for _, uid in uids do
		local animal = data.Animals[uid]
		if animal then
			total += Formula.SellPrice(animal)
			count += 1
			data.Animals[uid] = nil
		end
	end
	if count == 0 then
		return
	end
	DataService.AddCash(player, total)
	DataService.Changed(player, "Animals")
	PlotService.Refresh(player)
	notify:FireClient(player, "Sold " .. count .. " for " .. Format.Money(total), "good", "sell")
end

-- point - место в вольере, которое игрок выбрал курсором
local function placeCarry(player, point)
	local data = DataService.Get(player)
	local plot = plotOf[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not data or not data.Carry or not plot or not root or typeof(point) ~= "Vector3" then
		return
	end
	if (root.Position - plot.center).Magnitude > PLACE_REACH then
		notify:FireClient(player, "Come closer to your pen", "bad")
		return
	end
	local offset = point - plot.center
	if math.abs(offset.X) > plot.half or math.abs(offset.Z) > plot.half then
		return
	end
	local animal = data.Carry
	-- вольер полон: животное уходит в рюкзак, его можно продать в Sell Shop
	if countAnimals(data) >= data.Slots then
		if #data.Backpack >= Game.BACKPACK_SIZE then
			notify:FireClient(player, "Your pen and backpack are full! Sell animals at the Sell Shop", "bad")
			return
		end
		table.insert(data.Backpack, animal)
		data.Carry = false
		changedAll(player)
		notify:FireClient(player, "Your pen is full! " .. Formula.AnimalName(animal) .. " went to your backpack", "bad")
		return
	end
	local r = plot.half - 3
	addToPen(data, animal, { x = math.clamp(offset.X, -r, r), z = math.clamp(offset.Z, -r, r) })
	data.Carry = false
	changedAll(player)
	notify:FireClient(player, Formula.AnimalName(animal) .. " joined your pen!", "good", "animals")
end

local function validIndex(data, index)
	return type(index) == "number" and index % 1 == 0 and data.Backpack[index] ~= nil
end

-- лучшие животные (вольер + рюкзак) встают в вольер, остальные уходят в рюкзак
function PlotService.EquipBest(player)
	local data = DataService.Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return
	end
	local all = {}
	for uid, animal in data.Animals do
		table.insert(all, { animal = animal, uid = uid, income = Formula.Income(animal) })
	end
	for _, animal in data.Backpack do
		table.insert(all, { animal = animal, income = Formula.Income(animal) })
	end
	table.sort(all, function(a, b)
		return a.income > b.income
	end)
	local pen, backpack = {}, {}
	for i, entry in all do
		if i <= data.Slots then
			if entry.uid then
				pen[entry.uid] = entry.animal
			else
				local uid = "a" .. data.NextUid
				data.NextUid += 1
				entry.animal.pos = randomSpot(plot)
				pen[uid] = entry.animal
			end
		else
			entry.animal.pos = nil
			table.insert(backpack, entry.animal)
		end
	end
	data.Animals = pen
	data.Backpack = backpack
	changedAll(player)
end

local function sellBackpack(player, which)
	local data = DataService.Get(player)
	if not data then
		return
	end
	-- which: номер в рюкзаке, "carry" - то, что в руках, "all" - рюкзак и руки
	local sold = {}
	if which == "all" then
		sold = data.Backpack
		data.Backpack = {}
	elseif validIndex(data, which) then
		table.insert(sold, table.remove(data.Backpack, which))
	end
	if (which == "all" or which == "carry") and data.Carry then
		table.insert(sold, data.Carry)
		data.Carry = false
	end
	if #sold == 0 then
		return
	end
	local total = 0
	for _, animal in sold do
		total += Formula.SellPrice(animal)
	end
	DataService.AddCash(player, total)
	DataService.Changed(player, "Backpack", "Carry")
	attachCarry(player)
	notify:FireClient(player, "Sold " .. #sold .. " for " .. Format.Money(total), "good", "sell")
end

local function assignPlot(player)
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			plotOf[player] = plot
			modelsOf[player] = {}
			plot.ownerLabel.Text = player.DisplayName
			plot.avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
			plot.avatar.Visible = true
			local playerFolder = Instance.new("Folder")
			playerFolder.Name = player.Name
			playerFolder.Parent = farmFolder
			player:SetAttribute("Plot", plot.index)
			return plot
		end
	end
	return nil
end

local function releasePlot(player)
	local plot = plotOf[player]
	plotOf[player] = nil
	modelsOf[player] = nil
	incomeOf[player] = nil
	carried[player] = nil
	local playerFolder = farmFolder:FindFirstChild(player.Name)
	if playerFolder then
		playerFolder:Destroy()
	end
	if plot then
		plot.owner = nil
		plot.ownerLabel.Text = "Free Pen"
		plot.incomeLabel.Text = ""
		plot.countLabel.Parent.Visible = false
		plot.avatar.Visible = false
		plot.spaceTitle.Text = "Pen Space"
		plot.spacePrice.Text = ""
		plot.resize(Game.PEN_SIZE)
	end
end

-- доход за время, пока игрока не было
local function payOffline(player, data)
	if (data.LastOnline or 0) <= 0 then
		return
	end
	local away = math.min(os.time() - data.LastOnline, Game.OFFLINE_HOURS * 3600)
	local earned = (incomeOf[player] or 0) * away * Game.OFFLINE_RATE
	if away < 60 or earned <= 0 then
		return
	end
	DataService.AddCash(player, earned)
	task.delay(3, function()
		if player.Parent then
			notify:FireClient(player, "Your animals earned " .. Format.Money(earned) .. " while you were away!", "good", "money")
		end
	end)
end

local function isUid(value)
	return type(value) == "string" and #value < 20
end

function PlotService.Init(map)
	plots = map.plots
	farmFolder = Instance.new("Folder")
	farmFolder.Name = "Farm"
	farmFolder.Parent = workspace

	DataService.OnLoaded(function(player, data)
		-- вольеров пять, на сервере до 5 игроков (Players.MaxPlayers). Если сервер все же пустил шестого,
		-- без вольера играть нельзя: отправляем на другой сервер
		if not assignPlot(player) then
			player:Kick("This server is full (5 players). Please join another server!")
			return
		end
		PlotService.Refresh(player)
		teleportHome(player)
		attachCarry(player)
		payOffline(player, data)

		-- для теста в Studio: game.Players.Имя:SetAttribute("TestGive", "fox,bunny,owl:Gold")
		-- в командной строке сервера кладет этих животных в вольер (после двоеточия - мутация)
		if RunService:IsStudio() then
			player:GetAttributeChangedSignal("TestGive"):Connect(function()
				local value = player:GetAttribute("TestGive")
				local plot = plotOf[player]
				if type(value) ~= "string" or not plot then
					return
				end
				for entry in string.gmatch(value, "[^,%s]+") do
					local id, mutation = string.match(entry, "^(%w+):?(%a*)$")
					if id and Animals.ById[id] then
						addToPen(data, { id = id, m = mutation ~= "" and mutation or nil }, randomSpot(plot))
					end
				end
				player:SetAttribute("TestGive", nil)
				changedAll(player)
			end)
		end
	end)

	local function watchCharacter(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			task.wait()
			teleportHome(player, character)
			attachCarry(player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(releasePlot)

	MonetizationService.OnPassChanged(function(player)
		PlotService.Refresh(player)
	end)

	-- доход раз в секунду
	task.spawn(function()
		while true do
			task.wait(1)
			for player, income in incomeOf do
				if income > 0 then
					DataService.AddCash(player, income)
				end
			end
		end
	end)

	placeRemote.OnServerEvent:Connect(placeCarry)

	-- вынести животное из вольера в рюкзак, на продажу
	pickUpRemote.OnServerEvent:Connect(function(player, uid)
		local data = DataService.Get(player)
		local animal = data and isUid(uid) and data.Animals[uid]
		if not animal then
			return
		end
		if #data.Backpack >= Game.BACKPACK_SIZE then
			notify:FireClient(player, "Your backpack is full!", "bad")
			return
		end
		data.Animals[uid] = nil
		animal.pos = nil
		table.insert(data.Backpack, animal)
		changedAll(player)
	end)

	-- поставить животное из рюкзака в вольер на случайное место
	equipRemote.OnServerEvent:Connect(function(player, index)
		local data = DataService.Get(player)
		local plot = plotOf[player]
		if not data or not plot or not validIndex(data, index) then
			return
		end
		if countAnimals(data) >= data.Slots then
			notify:FireClient(player, "Your pen is full! Sell animals or upgrade your pen", "bad")
			return
		end
		addToPen(data, table.remove(data.Backpack, index), randomSpot(plot))
		changedAll(player)
	end)

	equipBestRemote.OnServerEvent:Connect(PlotService.EquipBest)
	sellBackpackRemote.OnServerEvent:Connect(sellBackpack)

	sellRemote.OnServerEvent:Connect(function(player, uids)
		if type(uids) ~= "table" or #uids > Game.MAX_SLOTS + 5 then
			return
		end
		local clean = {}
		for _, uid in ipairs(uids) do
			if isUid(uid) then
				table.insert(clean, uid)
			end
		end
		PlotService.SellAnimals(player, clean)
	end)
end

return PlotService
