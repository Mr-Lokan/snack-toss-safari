-- power: сколько силы нужно, чтобы еда долетела до начала зоны
-- base: доход Common-животного зоны в секунду
-- ground - пол каньона (шахматка светлее на тон), wall - земляные стены каньона
return {
	{
		id = "forest", emoji = "🌲", name = "Forest Edge", power = 1, length = 250, base = 2,
		ground = Color3.fromRGB(100, 205, 70), wall = Color3.fromRGB(150, 92, 50), material = Enum.Material.Plastic,
	},
	{
		id = "savanna", emoji = "🦒", name = "Savanna", power = 100, length = 250, base = 20,
		ground = Color3.fromRGB(235, 200, 75), wall = Color3.fromRGB(170, 105, 60), material = Enum.Material.Plastic,
	},
	{
		id = "desert", emoji = "🌵", name = "Desert", power = 800, length = 250, base = 200,
		ground = Color3.fromRGB(245, 222, 150), wall = Color3.fromRGB(215, 165, 100), material = Enum.Material.Plastic,
	},
	{
		id = "jungle", emoji = "🌴", name = "Jungle", power = 6000, length = 250, base = 2000,
		ground = Color3.fromRGB(55, 180, 80), wall = Color3.fromRGB(120, 78, 45), material = Enum.Material.Plastic,
	},
	{
		id = "swamp", emoji = "🐊", name = "Swamp", power = 50000, length = 250, base = 20000,
		ground = Color3.fromRGB(95, 150, 85), wall = Color3.fromRGB(100, 85, 60), material = Enum.Material.Plastic,
	},
	{
		id = "coast", emoji = "🌊", name = "Coast", power = 400000, length = 250, base = 200000,
		ground = Color3.fromRGB(250, 232, 175), wall = Color3.fromRGB(205, 180, 135), material = Enum.Material.Plastic,
	},
}
