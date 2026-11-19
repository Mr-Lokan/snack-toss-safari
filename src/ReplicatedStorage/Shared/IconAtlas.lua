local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Значки вместо смайликов (вариант 5 «Значки»): все в одной картинке 5 x 5 ячеек по 204 px.
-- Картинка загружена в Roblox вместе с мульт-моделями, ее id лежит в
-- ReplicatedStorage.ToonWorld.Textures.icons_atlas (TextureID). Порядок ячеек - как в
-- world_concepts/make_ingame_assets.py (ICON_ORDER)
local IconAtlas = {}

local CELL = 204
local ORDER = {
	"money", "strength", "luck", "animals", "index", "shop", "backpack", "food", "throw", "upgrade",
	"sell", "trophy", "boost", "star", "z_forest", "z_savanna", "z_desert", "z_jungle", "z_swamp", "z_coast",
}
local INDEX = {}
for i, key in ORDER do
	INDEX[key] = i
end

local atlasId
local function atlas()
	if not atlasId then
		local world = ReplicatedStorage:WaitForChild("ToonWorld", 10)
		local textures = world and world:WaitForChild("Textures", 10)
		local plate = textures and textures:WaitForChild("icons_atlas", 10)
		atlasId = plate and plate.TextureID or ""
	end
	return atlasId
end

-- значок зоны по ее id (forest, savanna...)
function IconAtlas.Zone(zone)
	return "z_" .. zone.id
end

-- показать значок key в готовой картинке (ImageLabel / ImageButton)
function IconAtlas.Apply(image, key)
	local i = INDEX[key] or INDEX.star
	image.Image = atlas()
	image.ImageRectOffset = Vector2.new(((i - 1) % 5) * CELL, math.floor((i - 1) / 5) * CELL)
	image.ImageRectSize = Vector2.new(CELL, CELL)
	image.ScaleType = Enum.ScaleType.Fit
	return image
end

-- новая картинка со значком; props - свойства ImageLabel (Size, Position, Parent...)
function IconAtlas.New(key, props)
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	for name, value in props or {} do
		if name ~= "Parent" then
			image[name] = value
		end
	end
	IconAtlas.Apply(image, key)
	image.Parent = props and props.Parent
	return image
end

return IconAtlas
