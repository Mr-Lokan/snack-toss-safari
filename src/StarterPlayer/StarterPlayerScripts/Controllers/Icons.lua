local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimalModel = require(Shared:WaitForChild("AnimalModel"))
local FoodModel = require(Shared:WaitForChild("FoodModel"))

-- 3D-иконки для интерфейса: модель в ViewportFrame со своей камерой
local Icons = {}

local FOV = 35
local VIEW = Vector3.new(-0.75, 0.45, -1).Unit -- спереди-сбоку-сверху, морда смотрит в -Z
-- еда нарисована «лицом» (семечки арбуза, масло на тосте): смотрим почти спереди, чуть сбоку и сверху
local FOOD_VIEW = Vector3.new(-0.45, 0.38, -1).Unit
local FOOD_FIT = 0.8 -- какую долю кадра занимает еда по большей стороне

-- сетки и текстуры еды грузим заранее: иначе в магазине она первые секунды серая
task.spawn(function()
	local foods = ReplicatedStorage:FindFirstChild("ToonFoods")
	if foods then
		pcall(ContentProvider.PreloadAsync, ContentProvider, foods:GetChildren())
	end
end)

local function viewport(parent, size, position)
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = size or UDim2.fromScale(1, 1)
	frame.Position = position or UDim2.new()
	frame.Ambient = Color3.fromRGB(190, 190, 200)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = Vector3.new(-0.6, -1, -0.4)
	frame.Parent = parent
	return frame
end

-- fit - доля кадра по большей стороне модели: высокая морковь и плоский стейк выходят одного размера.
-- Без fit расстояние считается по диагонали коробки (так стоят животные)
local function show(frame, model, view, fit)
	model:PivotTo(CFrame.new())
	model.Parent = frame
	local box, size = model:GetBoundingBox()
	local distance
	if fit then
		local half = math.max(size.X, size.Y) / 2
		distance = half / math.tan(math.rad(FOV / 2)) / fit + size.Z / 2
	else
		distance = size.Magnitude / 2 / math.sin(math.rad(FOV / 2)) * 0.9
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(box.Position + (view or VIEW) * distance, box.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera
end

-- silhouette - черный силуэт для еще не найденных животных
function Icons.Animal(parent, animal, silhouette, size, position)
	local frame = viewport(parent, size, position)
	show(frame, AnimalModel.Build(animal))
	if silhouette then
		frame.ImageColor3 = Color3.new(0, 0, 0)
		frame.Ambient = Color3.new(1, 1, 1)
	end
	return frame
end

function Icons.Food(parent, foodId, size, position)
	local frame = viewport(parent, size, position)
	show(frame, FoodModel.Build(foodId), FOOD_VIEW, FOOD_FIT)
	return frame
end

return Icons
