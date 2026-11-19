-- weight: базовый шанс в процентах
-- luck: насколько сильно удача еды поднимает этот шанс (вес * luck ^ это число)
return {
	{ id = "Common", weight = 60, luck = 0, mult = 1, color = Color3.fromRGB(200, 200, 200) },
	{ id = "Uncommon", weight = 25, luck = 0.5, mult = 2.5, color = Color3.fromRGB(90, 220, 90) },
	{ id = "Rare", weight = 10, luck = 1, mult = 6, color = Color3.fromRGB(70, 150, 255) },
	{ id = "Epic", weight = 4, luck = 1, mult = 15, color = Color3.fromRGB(180, 90, 255) },
	{ id = "Legendary", weight = 0.9, luck = 1, mult = 40, color = Color3.fromRGB(255, 165, 40) },
	{ id = "Mythic", weight = 0.09, luck = 1, mult = 120, color = Color3.fromRGB(255, 60, 80) },
	{ id = "Secret", weight = 0.01, luck = 1, mult = 500, color = Color3.fromRGB(255, 255, 255), rainbow = true },
}
