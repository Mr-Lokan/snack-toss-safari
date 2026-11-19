-- еда покупается навсегда и влияет только на удачу (редкость животного), не на дальность.
-- rarity - номер редкости для цвета карточки в магазине
local Foods = {
	{ id = "carrot", name = "Carrot", emoji = "🥕", price = 0, luck = 1, rarity = 1, color = Color3.fromRGB(255, 140, 30) },
	{ id = "apple", name = "Apple", emoji = "🍎", price = 100, luck = 1.5, rarity = 1, color = Color3.fromRGB(220, 40, 40) },
	{ id = "banana", name = "Banana", emoji = "🍌", price = 2500, luck = 2, rarity = 2, color = Color3.fromRGB(255, 225, 60) },
	{ id = "toast", name = "Toast", emoji = "🍞", price = 60000, luck = 3, rarity = 2, color = Color3.fromRGB(215, 160, 90) },
	{ id = "cheese", name = "Cheese", emoji = "🧀", price = 1.5e6, luck = 5, rarity = 3, color = Color3.fromRGB(255, 200, 70) },
	{ id = "steak", name = "Steak", emoji = "🥩", price = 40e6, luck = 8, rarity = 3, color = Color3.fromRGB(190, 60, 60) },
	{ id = "melon", name = "Watermelon", emoji = "🍉", price = 1e9, luck = 12, rarity = 4, color = Color3.fromRGB(60, 170, 70) },
	{ id = "cake", name = "Cake", emoji = "🍰", price = 25e9, luck = 18, rarity = 4, color = Color3.fromRGB(255, 180, 200) },
	{ id = "sushi", name = "Sushi", emoji = "🍣", price = 600e9, luck = 28, rarity = 5, color = Color3.fromRGB(255, 120, 80) },
	{ id = "goldapple", name = "Golden Apple", emoji = "🍏", price = 15e12, luck = 45, rarity = 6, color = Color3.fromRGB(255, 200, 40) },
	{ id = "candy", name = "Rainbow Candy", emoji = "🍭", price = 400e12, luck = 75, rarity = 7, color = Color3.fromRGB(255, 120, 220) },
}

Foods.ById = {}
for index, food in ipairs(Foods) do
	food.index = index
	Foods.ById[food.id] = food
end

return Foods
