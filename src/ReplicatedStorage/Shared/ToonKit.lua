local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Мульт-модельки окружения (world_concepts/export_world.py -> Studio Import 3D -> ToonWorld.rbxmx).
-- В ReplicatedStorage.ToonWorld у каждой модельки две детали: Body (текстура с окрасом) и Outline
-- (вывернутая черная копия - контур). Детали лежат относительно начала координат модельки - точки
-- на земле, как в Blender. Импорт Studio развернул модельки на 180° вокруг вертикали, Place
-- поворачивает их обратно, и дальше оси как на макете (Roblox X = Blender X, Z = -Blender Y):
--   деревья, кусты, постройки - начало внизу по центру; перед построек смотрит к +X;
--   модули скал - начало в нижнем углу лицевой стороны: длина вдоль +X, лицом к +Z, тело к -Z.
-- Textures - плашки с загруженными картинками пола (их TextureID), их же берет IconAtlas.
local ToonKit = {}

local folder = ReplicatedStorage:WaitForChild("ToonWorld")
local textures = folder:WaitForChild("Textures")
local IMPORT_FIX = CFrame.Angles(0, math.pi, 0)

function ToonKit.Has(name)
	return folder:FindFirstChild(name) ~= nil
end

-- растянуть детали модельки по ее осям (k - Vector3): модули скал под длину участка, жерди забора
local function stretch(model, k)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local rotation = part.CFrame.Rotation
			part.Size *= k
			part.CFrame = CFrame.new(part.Position * k) * rotation
		end
	end
end

-- копия модельки name: ее начало координат встает в cframe; scale - общий масштаб,
-- k - растяжение по осям модельки
function ToonKit.Place(parent, name, cframe, scale, k)
	local template = folder:FindFirstChild(name)
	if not template then
		warn("ToonKit: нет модельки " .. tostring(name))
		return nil
	end
	local model = template:Clone()
	-- детали шаблона лежат вокруг начала координат мира: это и есть точка модельки
	model.WorldPivot = CFrame.identity
	if k and k ~= Vector3.one then
		stretch(model, k)
	end
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(cframe * IMPORT_FIX)
	model.Parent = parent
	return model
end

-- модуль стены лицом в сторону face (горизонтальный вектор) длиной length:
-- от corner (нижний угол лицевой стороны) вдоль face:Cross(Y), тело уходит назад от face.
-- baseLength - длина модуля в Blender, height - растяжение по высоте
function ToonKit.Wall(parent, name, corner, face, length, baseLength, height)
	local along = face:Cross(Vector3.yAxis).Unit
	-- длина модуля идет по его +X, а это -along при лицевой стороне к face: начало на дальнем конце
	local origin = corner + along * length
	local cf = CFrame.lookAt(origin, origin - face)
	return ToonKit.Place(parent, name, cf, 1, Vector3.new(length / baseLength, height or 1, 1))
end

-- поворот, при котором +X модельки (перед постройки) смотрит в сторону face
function ToonKit.Facing(position, face)
	return CFrame.lookAt(position, position + face) * CFrame.Angles(0, math.pi / 2, 0)
end

function ToonKit.TextureId(name)
	local plate = textures:FindFirstChild(name)
	return plate and plate.TextureID or ""
end

-- рисунок на грани детали: studs - сколько студов на одну плитку картинки.
-- В картинках пола уже есть шахматка 2 x 2, поэтому клетка - половина плитки
function ToonKit.Paint(part, name, studs, face, color)
	local texture = Instance.new("Texture")
	texture.Name = "Toon_" .. name
	texture.Texture = ToonKit.TextureId(name)
	texture.Face = face or Enum.NormalId.Top
	texture.StudsPerTileU = studs
	texture.StudsPerTileV = studs
	if color then
		texture.Color3 = color
	end
	texture.Parent = part
	return texture
end

return ToonKit
