local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Formula = require(Shared:WaitForChild("Formula"))
local Game = require(Config:WaitForChild("Game"))
local Foods = require(Config:WaitForChild("Foods"))

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local notify = Net.Event("Notify")
local buyFood = Net.Event("BuyFood")
local equipFood = Net.Event("EquipFood")

local ShopService = {}

-- место в вольере покупается у таблички на входе, только хозяином
local function buySlot(player)
	local data = DataService.Get(player)
	if not data or data.Slots >= Game.MAX_SLOTS then
		return
	end
	local price = Formula.SlotPrice(data.Slots)
	if not DataService.Spend(player, price) then
		notify:FireClient(player, "You need " .. Format.Money(price), "bad")
		return
	end
	data.Slots += 1
	DataService.Changed(player, "Slots")
	PlotService.Refresh(player)
	notify:FireClient(player, "Your pen now fits " .. data.Slots .. " animals!", "good", "animals")
end

function ShopService.Init(map)
	for _, plot in map.plots do
		plot.spacePrompt.Triggered:Connect(function(player)
			if PlotService.GetPlot(player) == plot then
				buySlot(player)
			end
		end)
	end

	buyFood.OnServerEvent:Connect(function(player, id)
		local data = DataService.Get(player)
		local food = data and type(id) == "string" and Foods.ById[id]
		if not food or data.Foods[id] then
			return
		end
		if not DataService.Spend(player, food.price) then
			notify:FireClient(player, "Not enough cash", "bad")
			return
		end
		data.Foods[id] = true
		data.Food = id
		DataService.Changed(player, "Foods", "Food")
		notify:FireClient(player, "Bought " .. food.name .. "!", "good", "food")
	end)

	equipFood.OnServerEvent:Connect(function(player, id)
		local data = DataService.Get(player)
		if data and type(id) == "string" and data.Foods[id] then
			data.Food = id
			DataService.Changed(player, "Food")
		end
	end)
end

return ShopService
