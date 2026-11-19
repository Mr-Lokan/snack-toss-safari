-- Gold и Rainbow взаимоисключающие, Giant катится отдельно и перемножается с ними
return {
	Gold = { chance = 1 / 25, mult = 2, color = Color3.fromRGB(255, 196, 40) },
	Rainbow = { chance = 1 / 250, mult = 5 },
	Giant = { chance = 1 / 50, mult = 3, scale = 2 },
}
