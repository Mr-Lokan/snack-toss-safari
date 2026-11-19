local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Foods = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Foods"))

-- Один источник моделей для магазина, руки персонажа и полёта.
-- Простые модели остаются резервом для сборок без ToonFoods.
local FoodModel = {}

local rgb = Color3.fromRGB

local function piece(model, size, cframe, color, shape, class)
	local part = Instance.new(class or "Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

local at = CFrame.new

local BUILDERS = {}

function BUILDERS.carrot(m)
	local orange = rgb(255, 140, 30)
	local main = piece(m, Vector3.new(0.65, 0.5, 0.65), at(0, 0.45, 0), orange)
	piece(m, Vector3.new(0.5, 0.45, 0.5), at(0, 0, 0), orange)
	piece(m, Vector3.new(0.35, 0.4, 0.35), at(0, -0.4, 0), orange)
	piece(m, Vector3.new(0.18, 0.3, 0.18), at(0, -0.72, 0), orange)
	for i = -1, 1 do
		piece(m, Vector3.new(0.14, 0.55, 0.14), at(i * 0.12, 0.95, 0) * CFrame.Angles(0, 0, -i * 0.45), rgb(70, 180, 60))
	end
	return main
end

function BUILDERS.apple(m)
	local main = piece(m, Vector3.new(1.3, 1.3, 1.3), at(0, 0, 0), rgb(220, 40, 40), Enum.PartType.Ball)
	piece(m, Vector3.new(0.12, 0.4, 0.12), at(0, 0.75, 0), rgb(110, 70, 40))
	piece(m, Vector3.new(0.4, 0.08, 0.25), at(0.22, 0.8, 0) * CFrame.Angles(0, 0, 0.4), rgb(70, 180, 60))
	return main
end

function BUILDERS.banana(m)
	local yellow = rgb(255, 225, 60)
	local main
	for i = -1, 1 do
		local angle = i * 0.55
		local part = piece(m, Vector3.new(0.38, 0.38, 0.62), CFrame.Angles(angle, 0, 0) * at(0, -0.55, 0), yellow)
		if i == 0 then
			main = part
		end
	end
	for _, side in { -1, 1 } do
		piece(m, Vector3.new(0.2, 0.2, 0.2), CFrame.Angles(side * 0.98, 0, 0) * at(0, -0.55, 0), rgb(110, 80, 40))
	end
	return main
end

function BUILDERS.toast(m)
	local main = piece(m, Vector3.new(1.4, 0.32, 1.3), at(0, 0, 0), rgb(170, 110, 55))
	piece(m, Vector3.new(1.2, 0.34, 1.1), at(0, 0, 0), rgb(240, 205, 140))
	return main
end

function BUILDERS.cheese(m)
	local main = piece(m, Vector3.new(1.0, 0.8, 1.4), at(0, 0, 0), rgb(255, 205, 70), nil, "WedgePart")
	piece(m, Vector3.new(0.22, 0.22, 0.05), at(0.2, -0.15, -0.71), rgb(220, 165, 40))
	piece(m, Vector3.new(0.16, 0.16, 0.05), at(-0.25, -0.2, -0.71), rgb(220, 165, 40))
	return main
end

function BUILDERS.steak(m)
	local main = piece(m, Vector3.new(1.4, 0.3, 1.0), at(0, 0, 0), rgb(160, 55, 50))
	piece(m, Vector3.new(1.42, 0.32, 0.16), at(0, 0, 0.42), rgb(245, 225, 210))
	piece(m, Vector3.new(0.18, 0.18, 1.3), at(0.45, 0.05, 0), rgb(250, 245, 235))
	return main
end

function BUILDERS.melon(m)
	local main = piece(m, Vector3.new(1.4, 0.8, 0.45), at(0, 0.1, 0), rgb(235, 60, 70))
	piece(m, Vector3.new(1.5, 0.22, 0.5), at(0, -0.4, 0), rgb(60, 160, 70))
	for i = -1, 1 do
		piece(m, Vector3.new(0.1, 0.16, 0.48), at(i * 0.35, 0.15 - math.abs(i) * 0.08, 0), rgb(30, 30, 30))
	end
	return main
end

function BUILDERS.cake(m)
	local main = piece(m, Vector3.new(1.0, 0.45, 1.4), at(0, -0.25, 0), rgb(250, 215, 160), nil, "WedgePart")
	piece(m, Vector3.new(1.0, 0.12, 1.4), at(0, 0.03, 0), rgb(255, 120, 160), nil, "WedgePart")
	piece(m, Vector3.new(1.0, 0.4, 1.4), at(0, 0.29, 0), rgb(250, 215, 160), nil, "WedgePart")
	piece(m, Vector3.new(1.04, 0.08, 0.3), at(0, -0.48, 0.55), rgb(255, 245, 250))
	piece(m, Vector3.new(0.3, 0.3, 0.3), at(0, 0.62, 0.5), rgb(220, 30, 50), Enum.PartType.Ball)
	return main
end

function BUILDERS.sushi(m)
	local main = piece(m, Vector3.new(1.3, 0.5, 0.7), at(0, -0.15, 0), rgb(250, 250, 245))
	piece(m, Vector3.new(1.45, 0.2, 0.8), at(0, 0.2, 0), rgb(255, 130, 80))
	for _, x in { -0.25, 0.25 } do
		piece(m, Vector3.new(0.08, 0.22, 0.82), at(x, 0.21, 0), rgb(255, 225, 205))
	end
	piece(m, Vector3.new(0.3, 0.74, 0.74), at(0, 0, 0), rgb(30, 50, 35))
	return main
end

function BUILDERS.goldapple(m)
	local main = piece(m, Vector3.new(1.3, 1.3, 1.3), at(0, 0, 0), rgb(255, 200, 40), Enum.PartType.Ball)
	main.Material = Enum.Material.Foil
	main.Reflectance = 0.2
	piece(m, Vector3.new(0.12, 0.4, 0.12), at(0, 0.75, 0), rgb(110, 70, 40))
	piece(m, Vector3.new(0.4, 0.08, 0.25), at(0.22, 0.8, 0) * CFrame.Angles(0, 0, 0.4), rgb(255, 230, 120)).Material = Enum.Material.Neon
	return main
end

function BUILDERS.candy(m)
	local vertical = CFrame.Angles(0, math.pi / 2, 0)
	local main = piece(m, Vector3.new(0.25, 1.2, 1.2), at(0, 0.3, 0) * vertical, rgb(255, 120, 220), Enum.PartType.Cylinder)
	-- спираль - кольца других цветов поверх диска
	local colors = { rgb(120, 220, 255), rgb(255, 240, 120), rgb(150, 255, 150) }
	for i, color in colors do
		local size = 1.2 - i * 0.28
		piece(m, Vector3.new(0.27 + i * 0.01, size, size), at(0, 0.3, 0) * vertical, color, Enum.PartType.Cylinder)
	end
	piece(m, Vector3.new(0.12, 1.0, 0.12), at(0, -0.65, 0), rgb(250, 250, 250))
	return main
end

-- Мульт-еда из ReplicatedStorage.ToonFoods (импорт toon_foods.glb): Model = Body + Outline.
-- Шаблон называется как еда без пробелов (Golden Apple -> GoldenApple).
-- После импорта лицевая сторона смотрит в +Z, а иконки и бросок ждут ее в -Z: разворот на 180.
-- Центр модели ставится в начало координат, опорная точка там же.
local function buildToon(food)
	local templates = ReplicatedStorage:FindFirstChild("ToonFoods")
	local key = food.name:gsub(" ", "")
	local template = templates and templates:FindFirstChild(key)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	model.Name = food.name
	local box = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position)
	model:PivotTo(CFrame.Angles(0, math.pi, 0))
	model.WorldPivot = CFrame.identity
	return model
end

function FoodModel.Build(foodId)
	local food = Foods.ById[foodId] or Foods[1]
	local toon = buildToon(food)
	if toon then
		return toon
	end

	local model = Instance.new("Model")
	model.Name = food.name
	local build = BUILDERS[food.id]
	local main = build and build(model)
		or piece(model, Vector3.new(1.4, 1.4, 1.4), at(0, 0, 0), food.color, Enum.PartType.Ball)
	model.PrimaryPart = main
	main.PivotOffset = main.CFrame:Inverse()
	return model
end

return FoodModel
