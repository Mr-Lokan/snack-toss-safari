-- уровни турника: у каждого игрока один турник возле вольера, он улучшается по этому списку.
-- power - сколько силы дает одно подтягивание, price - цена улучшения до этого уровня
local Bars = {
	{ id = "wood", name = "Wooden Bar", power = 1, price = 0, color = Color3.fromRGB(150, 100, 60), material = Enum.Material.Wood },
	{ id = "iron", name = "Iron Bar", power = 3, price = 300, color = Color3.fromRGB(125, 125, 135), material = Enum.Material.Metal },
	{ id = "bronze", name = "Bronze Bar", power = 12, price = 8000, color = Color3.fromRGB(205, 127, 50), material = Enum.Material.Metal },
	{ id = "steel", name = "Steel Bar", power = 40, price = 300000, color = Color3.fromRGB(175, 185, 200), material = Enum.Material.DiamondPlate },
	{ id = "gold", name = "Golden Bar", power = 150, price = 12e6, color = Color3.fromRGB(255, 200, 40), material = Enum.Material.Foil },
	{ id = "diamond", name = "Diamond Bar", power = 500, price = 400e6, color = Color3.fromRGB(120, 230, 255), material = Enum.Material.Neon },
}

Bars.ById = {}
for index, bar in ipairs(Bars) do
	bar.index = index
	Bars.ById[bar.id] = bar
end

return Bars
