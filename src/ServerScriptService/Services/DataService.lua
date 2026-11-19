local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Formula = require(Shared:WaitForChild("Formula"))
local Game = require(Config:WaitForChild("Game"))
local Bars = require(Config:WaitForChild("Bars"))

local syncRemote = Net.Event("Sync")
local requestSync = Net.Event("RequestSync")

local STORE_NAME = "SnackToss_v1"
local AUTOSAVE_INTERVAL = 90
local SYNC_INTERVAL = 0.1

local DataService = {}

local profiles = {} -- [player] = { data, canSave, dirty }
local loadedCallbacks = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local function defaults()
	return {
		Cash = 0,
		TotalEarned = 0,
		Throws = 0,
		Power = Game.START_POWER,
		TrainLevel = 1, -- турник дает опыт, полная шкала опыта - новый уровень и прибавка силы
		TrainXP = 0,
		BestDistance = 0,
		Foods = { carrot = true },
		Food = "carrot",
		BarLevel = 1,
		Slots = Game.START_SLOTS,
		Animals = {}, -- животные в вольере: ["a12"] = { id = "zebra", m = "Gold", g = true, pos = { x, z } }
		Carry = false, -- пойманное животное в руках, пока его не поставили в вольер
		Backpack = {}, -- животные, вынесенные из вольера на продажу (массив)
		NextUid = 1,
		Index = {},
		BestOdds = 0, -- самая редкая поимка, "1 из N"
		LastOnline = 0, -- для офлайн-дохода
	}
end

local function reconcile(data)
	-- старые сохранения без уровня тренировки: уровень считаем по уже набранной силе
	if data.Power and not data.TrainLevel then
		local level, total = 1, Game.START_POWER
		while total + Formula.XPNeed(level) <= data.Power do
			total += Formula.XPNeed(level)
			level += 1
		end
		data.TrainLevel = level
		data.TrainXP = data.Power - total
	end
	for key, value in defaults() do
		if data[key] == nil then
			data[key] = value
		end
	end
	-- старый формат: несколько купленных турников вместо уровня
	if data.Bars then
		for index, bar in ipairs(Bars) do
			if data.Bars[bar.id] then
				data.BarLevel = math.max(data.BarLevel, index)
			end
		end
		data.Bars = nil
	end
	data.Held = nil -- было в версии, где пойманные шли в рюкзак
	return data
end

local function keyFor(player)
	return "player_" .. player.UserId
end

local function makeLeaderstats(player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { "Cash", "Power" } do
		local value = Instance.new("StringValue")
		value.Name = name
		value.Parent = folder
	end
	folder.Parent = player
end

local function updateLeaderstats(player, data)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Cash.Value = Format.Money(data.Cash)
		stats.Power.Value = Format.Number(data.Power)
	end
end

local function save(player, profile)
	if not profile.canSave or not store then
		return
	end
	profile.data.LastOnline = os.time()
	local ok, err = pcall(store.UpdateAsync, store, keyFor(player), function()
		return profile.data
	end)
	if not ok then
		warn("Save failed for", player.Name, err)
	end
end

local function load(player)
	local data, canSave = nil, false
	if store then
		-- в Studio без доступа к API не ждем повторов
		local attempts = RunService:IsStudio() and 1 or 3
		for attempt = 1, attempts do
			local ok, result = pcall(store.GetAsync, store, keyFor(player))
			if ok then
				data, canSave = result, true
				break
			end
			warn("Load failed for", player.Name, result)
			if attempt < attempts then
				task.wait(attempt * 2)
			end
		end
	end

	if not canSave and not RunService:IsStudio() then
		player:Kick("Couldn't load your data. Please rejoin.")
		return
	end
	if not player.Parent then
		return
	end
	if not canSave then
		warn("Data won't be saved in this session (enable Studio Access to API Services to test saving)")
	end

	local profile = { data = reconcile(data or {}), canSave = canSave, dirty = {} }
	profiles[player] = profile
	makeLeaderstats(player)

	-- для теста в Studio: game.Players.Имя:SetAttribute("TestPower", 60000) в командной строке сервера
	if RunService:IsStudio() then
		player.AttributeChanged:Connect(function(name)
			local key = string.match(name, "^Test(%a+)$")
			local value = player:GetAttribute(name)
			if key and type(profile.data[key]) == "number" and type(value) == "number" then
				profile.data[key] = value
				DataService.Changed(player, key)
			end
		end)
	end
	updateLeaderstats(player, profile.data)
	syncRemote:FireClient(player, profile.data)

	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile.data)
	end
end

function DataService.Get(player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.GetAll()
	local result = {}
	for player, profile in profiles do
		result[player] = profile.data
	end
	return result
end

-- пометить поля, которые надо отправить клиенту
function DataService.Changed(player, ...)
	local profile = profiles[player]
	if profile then
		for _, key in { ... } do
			profile.dirty[key] = true
		end
	end
end

function DataService.AddCash(player, amount)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Cash += amount
	data.TotalEarned += amount
	DataService.Changed(player, "Cash", "TotalEarned")
end

function DataService.Spend(player, amount)
	local data = DataService.Get(player)
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	DataService.Changed(player, "Cash")
	return true
end

function DataService.OnLoaded(callback)
	table.insert(loadedCallbacks, callback)
end

local function flush()
	for player, profile in profiles do
		if next(profile.dirty) then
			local payload = {}
			for key in profile.dirty do
				payload[key] = profile.data[key]
			end
			profile.dirty = {}
			syncRemote:FireClient(player, payload)
			if payload.Cash or payload.Power then
				updateLeaderstats(player, profile.data)
			end
		end
	end
end

function DataService.Init()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			save(player, profile)
		end
	end)

	requestSync.OnServerEvent:Connect(function(player)
		local profile = profiles[player]
		if profile then
			syncRemote:FireClient(player, profile.data)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= SYNC_INTERVAL then
			elapsed = 0
			flush()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				task.spawn(save, player, profile)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				save(player, profile)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
