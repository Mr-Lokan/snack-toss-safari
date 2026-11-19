local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Config:WaitForChild("Game"))
local Zones = require(Config:WaitForChild("Zones"))
local Bars = require(Config:WaitForChild("Bars"))
local Formula = require(Shared:WaitForChild("Formula"))
local Looks = require(Config:WaitForChild("Looks"))
local Format = require(Shared:WaitForChild("Format"))
local ToonKit = require(Shared:WaitForChild("ToonKit"))
local IconAtlas = require(Shared:WaitForChild("IconAtlas"))

-- Вся карта строится кодом при старте сервера, в стиле «мульт с контуром»: скалы, деревья, постройки
-- и помост зоны броска - мульт-модельки из ReplicatedStorage.ToonWorld (ToonKit), полы - детали
-- с нарисованной текстурой. Невидимые детали под модельками держат игрока (у моделек нет столкновений).
-- Ось X: вольеры (вход на -45, растут назад), у входа свой Food Shop и турник (-34) -> Sell Shop
-- у правой скалы -> помост броска (9) -> каньон (20 и дальше). Вокруг базы кольцо гор
local MapService = {}

local PLOT_COUNT = 5
-- вольер растет с каждым купленным местом (Formula.PenSize): вход на линии GATE_X стоит на месте,
-- а пол с забором раздвигаются назад и в стороны
local GATE_X = -45
local PEN_MAX = Formula.PenSize(Game.MAX_SLOTS)
local PLOT_SPACING = PEN_MAX + 6 -- даже два полных вольера рядом не касаются
local EDGE_WALL_X = 4 -- лицевая сторона скал по краю базы, перед ней доски рейтинга и Sell Shop
local SELL_Z = 38 -- Sell Shop у правой скалы
-- горы стоят с запасом за самыми большими вольерами
local BASE_MIN_X = GATE_X - PEN_MAX - 10
local BASE_MAX_X = 14 -- край обрыва над каньоном
local BASE_HALF_Z = math.floor(PLOT_COUNT / 2) * PLOT_SPACING + PEN_MAX / 2 + 10
local FIELD_HALF_WIDTH = 180
local TOP_Y = 14.9 -- верх гор и обрывов: трава на одном уровне со всех сторон
local FAR = 800 -- до куда тянется плато вокруг

local rng = Random.new(20261103)
local rgb = Color3.fromRGB
local DIRT = Zones[1].wall
-- трава и пол вольера: мягкие пятна, клевер и ромашки (world_concepts/make_paths.py, как концепт G)
local GRASS = "soft_grass"
local PEN_GRASS = "soft_pen"

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function decor(parent, size, cframe, color, material, shape)
	return part(parent, {
		Size = size, CFrame = cframe, Color = color, Material = material or Enum.Material.SmoothPlastic,
		Shape = shape or Enum.PartType.Block, CanCollide = false, CanQuery = false, CanTouch = false,
	})
end

-- невидимая деталь: держит игрока там, где стоит моделька без столкновений
local function solid(parent, name, size, cframe)
	return part(parent, { Name = name, Size = size, CFrame = cframe, Transparency = 1, CanQuery = false })
end

-- пол с нарисованной текстурой сверху; color - цвет боков.
-- Поверх основной картинки - крупные светлые и темные пятна (macro) с другой плиткой,
-- не кратной основной: на больших полях не видно, где картинка повторяется
local MACRO_STUDS = 157

local function floorPart(parent, name, size, position, texture, studs, color, props)
	local p = part(parent, { Name = name, Size = size, Position = position, Color = color or DIRT })
	for key, value in props or {} do
		p[key] = value
	end
	ToonKit.Paint(p, texture, studs)
	if texture ~= "planks" and texture ~= "water" then
		ToonKit.Paint(p, "macro", math.max(MACRO_STUDS, studs * 3.7))
	end
	return p
end

-- моделька на земле с поворотом вокруг вертикали
local function prop(parent, name, x, y, z, yaw, scale)
	return ToonKit.Place(parent, name, CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0), scale)
end

-- светящиеся площадки: неон с прозрачностью, чтобы не слепил
local GLOW = 0.45

local function glowing(p, transparency)
	p.Transparency = transparency or GLOW
	return p
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function label(parent, text, size, position, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Text = text
	l.TextScaled = true
	l.Font = font or Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.Parent = parent
	return l
end

-- надпись со значком слева (значки из атласа, как в интерфейсе вместо смайликов).
-- iconWidth - доля ширины под значок; значок чуть выше строки. Возвращает саму надпись
local function iconLabel(parent, key, text, size, position, color, iconWidth)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = size
	holder.Position = position
	holder.Parent = parent
	local w = iconWidth or 0.22
	IconAtlas.New(key, {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(w, 1.35), Parent = holder,
	})
	return label(holder, text, UDim2.fromScale(1 - w, 1), UDim2.fromScale(w, 0), color)
end

-- невидимая точка с табличкой над ней.
-- size в scale - размер в студах, в offset - постоянный размер на экране
local function billboard(parent, position, size, maxDistance)
	local anchor = part(parent, {
		Size = Vector3.new(1, 1, 1), Position = position, Transparency = 1,
		CanCollide = false, CanQuery = false, CanTouch = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 250
	gui.Parent = anchor
	return gui, anchor
end

local function prompt(parent, position, actionText, objectText)
	local anchor = part(parent, {
		Size = Vector3.new(1, 1, 1), Position = position, Transparency = 1,
		CanCollide = false, CanQuery = false, CanTouch = false,
	})
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 11
	p.RequiresLineOfSight = false
	p.Parent = anchor
	return p
end

-- случайный элемент списка { {имя, вес}, ... }
local function pick(list)
	local total = 0
	for _, item in list do
		total += item[2]
	end
	local roll = rng:NextNumber() * total
	for _, item in list do
		roll -= item[2]
		if roll <= 0 then
			return item[1]
		end
	end
	return list[#list][1]
end

-- забор из столбиков и двух жердей (мульт-модельки); невидимая стенка внутри не дает пройти насквозь.
-- a и b - концы на земле
local function railFence(parent, a, b)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local posts = math.max(1, math.round(length / 4.5))
	local yaw = math.atan2(-dir.Z, dir.X)
	for i = 0, posts do
		local point = a:Lerp(b, i / posts)
		ToonKit.Place(parent, "FencePost", CFrame.new(point.X, 0, point.Z) * CFrame.Angles(0, yaw, 0))
	end
	local mid = (a + b) / 2
	for _, y in { 1.6, 3.2 } do
		ToonKit.Place(parent, "FenceRail", ToonKit.Facing(Vector3.new(mid.X, y, mid.Z), dir), 1, Vector3.new(length / 10, 1, 1))
	end
	part(parent, { Name = "FenceWall", Size = Vector3.new(0.6, 4.5, length), CFrame = CFrame.lookAt(Vector3.new(mid.X, 2.25, mid.Z), Vector3.new(b.X, 2.25, b.Z)), Transparency = 1 })
end

local function lightingEffect(className)
	local effect = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
	effect.Parent = Lighting
	return effect
end

-- цветокор из Config/Looks.lua: солнце, цвет картинки, свечение, воздух
local function setupLighting(look)
	Lighting.ClockTime = look.clock
	Lighting.Brightness = look.brightness
	Lighting.Ambient = look.ambient
	Lighting.OutdoorAmbient = look.outdoor
	Lighting.EnvironmentDiffuseScale = look.diffuse or 0.5
	-- блики от неба на круглых мульт-модельках выглядят как масло: в матовых вариантах их нет
	Lighting.EnvironmentSpecularScale = look.specular or 0.3
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = look.shadowSoftness
	local grade = lightingEffect("ColorCorrectionEffect")
	grade.Saturation = look.saturation
	grade.Contrast = look.contrast
	grade.Brightness = look.exposure
	grade.TintColor = look.tint
	local bloom = lightingEffect("BloomEffect")
	bloom.Intensity = look.bloom.intensity
	bloom.Size = look.bloom.size
	bloom.Threshold = look.bloom.threshold
	local rays = lightingEffect("SunRaysEffect")
	rays.Intensity = look.rays
	rays.Spread = 0.6
	local atmosphere = lightingEffect("Atmosphere")
	atmosphere.Density = look.air.density
	atmosphere.Haze = look.air.haze
	atmosphere.Glare = look.air.glare
	atmosphere.Color = look.air.color
	atmosphere.Decay = look.air.decay
end

-- поле - каньон: узкая полоса, по бокам уступы и скалы с декором
local LANE_HALF = Game.FIELD_WIDTH / 2
local LEDGE_WIDTH = 10
local FLOOR = Game.FIELD_Y -- дно каньона ниже базы, уступы и скалы считаются от него
local LEDGE_HEIGHT = 10
local CLIFF_HEIGHT = 30

-- помост броска: доски до края с выступом над обрывом (world_concepts/world_platforms.py, variant_forest)
local DECK_EDGE = 15.9
-- верх настила: на 0.1 выше доски-плиты помоста под ним (вплотную они мерцали)
local DECK_TOP = 0.13
local DECK_PARTS = { "DeckFrame", "DeckRail", "DeckVines", "DeckEndA", "DeckEndB" }
local DECK_END_SHIFT = { DeckEndA = 2.5, DeckEndB = -2.5 }
local LINE_HALF = Game.THROW_PAD.halfZ - 2.5 -- пунктир у кромки помоста кончается до скал
-- фонари на перилах (центры светящихся стекол)
local LANTERN_X, LANTERN_Y = DECK_EDGE - 0.45, 2.55
local LANTERN_Z = { 22.5, 14.5, 6.5, -1.5, -9.5, -17.5, -25.5 }

local function buildBase(map)
	local base = folder(map, "Base")
	local width = BASE_MAX_X - BASE_MIN_X
	local centerX = BASE_MIN_X + width / 2
	-- трава базы: до начала помоста, чтобы два пола не лежали друг на друге (мерцали бы)
	local grassX1 = Game.THROW_PAD.x - Game.THROW_PAD.halfX
	floorPart(base, "Ground", Vector3.new(grassX1 - BASE_MIN_X, 2, BASE_HALF_Z * 2), Vector3.new((BASE_MIN_X + grassX1) / 2, -1, 0), GRASS, 40)

	-- невидимые стены, чтобы не уходить с базы и не бегать по полю
	local walls = {
		{ Vector3.new(1, 60, BASE_HALF_Z * 2), Vector3.new(BASE_MIN_X - 0.5, 30, 0) },
		{ Vector3.new(width, 60, 1), Vector3.new(centerX, 30, BASE_HALF_Z + 0.5) },
		{ Vector3.new(width, 60, 1), Vector3.new(centerX, 30, -BASE_HALF_Z - 0.5) },
		{ Vector3.new(1, 60, BASE_HALF_Z * 2), Vector3.new(13.5, 30, 0) },
	}
	for _, wall in walls do
		part(base, { Name = "Wall", Size = wall[1], Position = wall[2], Transparency = 1 })
	end

	-- обрыв перед зоной броска: база стоит выше каньона, еда летит вниз. Видна мульт-скала под помостом
	solid(base, "Edge", Vector3.new(12, -2 - Game.FIELD_Y, BASE_HALF_Z * 2 + 20), CFrame.new(8, (Game.FIELD_Y - 2) / 2, 0))
	ToonKit.Wall(base, "Under", Vector3.new(14.2, FLOOR - 0.4, -30), Vector3.xAxis, 60, 60)

	-- зона броска - лесной помост во всю ширину каньона: настил из досок до самого края с выступом
	-- над обрывом, перила из бревен с фонарями, по краям бочки и ящики с едой. Встает игрок
	-- по-прежнему в Game.THROW_PAD (места игроков - по номеру вольера), мишеней нет
	local pad = Game.THROW_PAD
	local padX0 = pad.x - pad.halfX
	-- доски чуть просвечивают светлым деревом: под золотым светом без этого они почти оранжевые
	local throwPad = floorPart(base, "ThrowPad", Vector3.new(DECK_EDGE - padX0, 0.2, pad.halfZ * 2),
		Vector3.new((padX0 + DECK_EDGE) / 2, DECK_TOP - 0.1, 0), "planks", 6, rgb(232, 200, 160))
	throwPad:FindFirstChildOfClass("Texture").Transparency = 0.3
	-- торцы помоста упираются в горы, а камни гор выступают на пару студов:
	-- бочки и грибы с торцов сдвинуты внутрь, иначе они наполовину в скале
	for _, name in DECK_PARTS do
		local shift = DECK_END_SHIFT[name] or 0
		ToonKit.Place(base, name, CFrame.new(0, 0, shift))
	end
	for _, z in LANTERN_Z do
		-- стекла крестом выглядывают из рамки фонаря с четырех сторон
		local glass = decor(base, Vector3.new(0.36, 0.42, 0.62), CFrame.new(LANTERN_X, LANTERN_Y, z), rgb(255, 217, 138), Enum.Material.Neon)
		decor(base, Vector3.new(0.62, 0.42, 0.36), CFrame.new(LANTERN_X, LANTERN_Y, z), rgb(255, 217, 138), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 200, 120)
		light.Range = 9
		light.Brightness = 0.8
		light.Parent = glass
	end
	-- по границе с травой светящийся пунктир (клиент делает ему мягкую пульсацию)
	local line = folder(base, "ThrowLine")
	local DASH, GAP = 2, 1
	local dashes = math.floor((LINE_HALF * 2 + GAP) / (DASH + GAP))
	local lineX = padX0
	for i = 0, dashes - 1 do
		local z = -(dashes * (DASH + GAP) - GAP) / 2 + i * (DASH + GAP) + DASH / 2
		-- яркая сердцевина и мягкий ореол вокруг
		decor(line, Vector3.new(0.4, 0.12, DASH), CFrame.new(lineX, DECK_TOP + 0.05, z), Color3.new(1, 1, 1), Enum.Material.Neon)
		glowing(decor(line, Vector3.new(1.4, 0.06, DASH + 0.4), CFrame.new(lineX, DECK_TOP + 0.04, z), rgb(255, 245, 220), Enum.Material.Neon), 0.8)
	end
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(rgb(255, 225, 150))
	sparkles.LightEmission = 0.5
	sparkles.Size = NumberSequence.new(0.35, 0)
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.Lifetime = NumberRange.new(0.8, 1.3)
	sparkles.Rate = 10
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.SpreadAngle = Vector2.new(10, 10)
	sparkles.Parent = throwPad
	-- клиент прячет эту надпись, пока игрок стоит в зоне
	local gui = billboard(base, Vector3.new(pad.x, 9, 0), UDim2.fromScale(16, 3.5), 250)
	gui.Name = "ThrowSign"
	iconLabel(gui, "throw", "THROW ZONE", UDim2.fromScale(1, 1), UDim2.new(), rgb(255, 230, 120), 0.24)

	-- точку появления не видно: платформу под ней пользователь просил не делать
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(-37, 0.5, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = base
end

-- встал в круг перед ларьком - открылась панель (клиент проверяет расстояние)
local SHOP_PAD_RADIUS = 4

-- магазин-домик (HutFood / HutSell): стены из досок, черепичная крыша, прилавок со ставнями.
-- facing: 1 - прилавок и круг в сторону +X, -1 - в сторону -X (домик спиной к скале).
-- solidWalls - невидимые стены домика (у личного Food Shop их нет: чужим игрокам его не видно)
local function buildStall(parent, position, kind, padColor, iconKey, title, opens, facing, solidWalls)
	local x, z = position.X, position.Z
	local f = facing or 1
	local face = Vector3.new(f, 0, 0)
	ToonKit.Place(parent, kind == "food" and "HutFood" or "HutSell", ToonKit.Facing(Vector3.new(x, 0, z), face))
	if solidWalls then
		solid(parent, "ShopWall", Vector3.new(4.8, 7.5, 12.6), CFrame.new(x, 3.75, z))
	end
	-- над прилавком, на шаг перед домиком: у Sell Shop сзади скала, табличка в ней обрезалась
	local gui = billboard(parent, Vector3.new(x + f * 3, 11.2, z), UDim2.fromOffset(250, 58), 150)
	iconLabel(gui, iconKey, title, UDim2.fromScale(1, 1), UDim2.new(), Color3.new(1, 1, 1), 0.3)

	local vertical = CFrame.Angles(0, 0, math.pi / 2)
	local padX = x + 7 * f
	glowing(decor(parent, Vector3.new(0.3, SHOP_PAD_RADIUS * 2 + 1, SHOP_PAD_RADIUS * 2 + 1), CFrame.new(padX, 0.15, z) * vertical, Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Cylinder), 0.55)
	local pad = glowing(decor(parent, Vector3.new(0.4, SHOP_PAD_RADIUS * 2, SHOP_PAD_RADIUS * 2), CFrame.new(padX, 0.2, z) * vertical, padColor, Enum.Material.Neon, Enum.PartType.Cylinder))
	pad.Name = "ShopPad"
	pad:SetAttribute("Opens", opens)
	pad:SetAttribute("Radius", SHOP_PAD_RADIUS)
	local light = Instance.new("PointLight")
	light.Color = padColor
	light.Range = 8
	light.Brightness = 0.5
	light.Parent = pad
end

-- общий магазин у зоны броска: Sell Shop спиной к правой скале.
-- Food Shop у каждого игрока свой, у его вольера (buildPlots)
local function buildHub(map)
	local hub = folder(map, "Hub")
	buildStall(hub, Vector3.new(EDGE_WALL_X - 5, 0, SELL_Z), "sell", rgb(255, 70, 70), "sell", "SELL SHOP", "Sell", -1, true)
end

local BAR_RING = 3.2 -- радиус пунктирного круга: встал в него - залез на турник
local BAR_HALF = 3.8 -- от середины перекладины до стойки
local BAR_GRIP = 1.2 -- ручки под ладонями (хват на ширине плеч): от середины перекладины
-- труба и ручки тоньше прорези в кисти (между большим пальцем и остальными, там Roblox держит
-- инструменты): проходят внутри кулака и не торчат из него
local BAR_THICK = 0.2
local GRIP_THICK = 0.23

-- турник игрока на бревнах (мульт-моделька LogBar): бревна-стойки на камнях, мох сверху, обмотки.
-- Перекладина и ручки - детали игры: цвет перекладины меняется с уровнем (TrainingService)
local function buildBar(parent, position, ownerOnly)
	local x, z = position.X, position.Z
	local stand = folder(parent, "Bar")
	local up = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра вверх
	local along = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра вдоль перекладины
	local top = Game.BAR_Y + 0.55
	local cylinder = Enum.PartType.Cylinder
	ToonKit.Place(stand, "LogBar", CFrame.new(x, 0, z))
	for _, dz in { -BAR_HALF, BAR_HALF } do
		-- сами бревна твердые: сквозь них не пройти
		part(stand, {
			Size = Vector3.new(top, 1, 1), CFrame = CFrame.new(x, top / 2, z + dz) * up, Shape = cylinder, Transparency = 1,
		})
	end
	local beam = decor(stand, Vector3.new(BAR_HALF * 2, BAR_THICK, BAR_THICK), CFrame.new(x, Game.BAR_Y, z) * along, Bars[1].color, Bars[1].material, cylinder)
	local paint = { beam } -- детали цвета уровня
	for _, dz in { -BAR_GRIP, BAR_GRIP } do
		decor(stand, Vector3.new(1.1, GRIP_THICK, GRIP_THICK), CFrame.new(x, Game.BAR_Y, z + dz) * along, rgb(35, 35, 40), Enum.Material.Plastic, cylinder)
	end

	-- пунктирный круг на земле
	for i = 0, 13 do
		local angle = i / 14 * math.pi * 2
		glowing(decor(stand, Vector3.new(0.9, 0.08, 0.35),
			CFrame.new(x, 0.14, z) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -BAR_RING), rgb(255, 225, 215), Enum.Material.Neon), 0.3)
	end

	local gui = billboard(stand, Vector3.new(x, 13, z), UDim2.fromOffset(170, 72), 60)
	local title = label(gui, "Pull-up Bar", UDim2.fromScale(1, 0.42), UDim2.new(), Bars[1].color)
	local info = label(gui, "", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.42))
	local nextLabel = label(gui, "", UDim2.fromScale(1, 0.28), UDim2.fromScale(0, 0.72), rgb(120, 255, 120))
	parent:SetAttribute("BarSpot", Vector3.new(x, 0.3, z))
	parent:SetAttribute("BarRing", BAR_RING)

	-- круглая платформа перед турником: только стоя на ней можно улучшить турник.
	-- Лежит в OwnerOnly - клиент показывает ее только хозяину вольера
	local padPosition = Vector3.new(x + 8, 0.3, z)
	local vertical = CFrame.Angles(0, 0, math.pi / 2)
	glowing(decor(ownerOnly, Vector3.new(0.3, 7, 7), CFrame.new(x + 8, 0.15, z) * vertical, Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Cylinder), 0.55)
	glowing(decor(ownerOnly, Vector3.new(0.4, 6, 6), CFrame.new(x + 8, 0.2, z) * vertical, rgb(70, 160, 255), Enum.Material.Neon, Enum.PartType.Cylinder))
	local padGui = billboard(ownerOnly, Vector3.new(x + 8, 4.5, z), UDim2.fromOffset(170, 44), 45)
	iconLabel(padGui, "upgrade", "UPGRADE", UDim2.fromScale(1, 1), UDim2.new(), rgb(150, 210, 255), 0.3)
	parent:SetAttribute("UpgradePad", padPosition)

	return {
		center = Vector3.new(x, 0.3, z),
		upgradePad = padPosition,
		beam = beam,
		paint = paint,
		title = title,
		info = info,
		nextLabel = nextLabel,
		hang = CFrame.lookAt(Vector3.new(x, Game.BAR_Y - 3.3, z), Vector3.new(x + 1, Game.BAR_Y - 3.3, z)),
		-- сходим с турника назад, за круг (спереди платформа улучшения)
		exit = CFrame.lookAt(Vector3.new(x - BAR_RING - 2.5, 3.5, z), Vector3.new(x + 10, 3.5, z)),
	}
end

-- вольер: лужайка с забором, вход со стороны хаба; животные ходят внутри сами
local PEN_GATE = 6 -- половина ширины входа
local PEN_TOP = 0.15 -- верх пола вольера (трава базы на 0)

-- табличка "6 > 7 / $500" у входа (значок лапки слева), подписи меняет PlotService, покупку - ShopService.
-- Доска - мульт-моделька PenSign, надпись на невидимой детали прямо перед ней
local function buildSpaceSign(parent, x, z)
	ToonKit.Place(parent, "PenSign", CFrame.new(x, 0, z))
	local board = part(parent, {
		Name = "SpaceSign", Size = Vector3.new(0.5, 3.6, 6), Position = Vector3.new(x + 0.06, 5.6, z),
		Transparency = 1, CanCollide = false, CanQuery = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local title = iconLabel(gui, "animals", "Pen Space", UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.05), rgb(255, 235, 170), 0.26)
	local price = label(gui, "", UDim2.fromScale(0.9, 0.4), UDim2.fromScale(0.05, 0.55), rgb(120, 255, 120))
	local p = prompt(parent, Vector3.new(x + 1.5, 3, z), "Upgrade Pen", "Pen Space")
	p.MaxActivationDistance = 8
	return title, price, p
end

local PEN_FLOWERS = { { "Flower1", 1 }, { "Flower2", 1 }, { "Flower3", 1 }, { "Tuft1", 1.2 }, { "Tuft2", 1.2 } }

-- Пол и забор вольера со стороной size, вход на линии GATE_X. Пол - тонкая плита вровень с землей,
-- без ступеньки на входе. При росте вольера старые пол и забор снимаются и строятся заново
local function buildPen(plotFolder, cz, size)
	local old = plotFolder:FindFirstChild("Pen")
	if old then
		old:Destroy()
	end
	local pen = folder(plotFolder, "Pen")
	local half = size / 2
	local cx = GATE_X - half
	-- пол на 0.15 выше травы базы: два пола вплотную мерцали бы друг сквозь друга
	floorPart(pen, "Floor", Vector3.new(size, 0.3, size), Vector3.new(cx, PEN_TOP - 0.15, cz), PEN_GRASS, 32, rgb(120, 200, 80))
	local function corner(sx, sz)
		return Vector3.new(cx + sx * half, 0, cz + sz * half)
	end
	railFence(pen, corner(-1, -1), corner(-1, 1))
	for _, side in { -1, 1 } do
		railFence(pen, corner(-1, side), corner(1, side))
		railFence(pen, corner(1, side), Vector3.new(GATE_X, 0, cz + side * PEN_GATE))
	end
	-- вход: лесная арка из ветки с листвой и табличкой с лапкой
	ToonKit.Place(pen, "ForestGate", CFrame.new(GATE_X, 0, cz))
	for _, side in { -1, 1 } do
		solid(pen, "GatePost", Vector3.new(1.3, 6, 1.3), CFrame.new(GATE_X, 3, cz + side * PEN_GATE))
	end
	-- цветы и трава вдоль забора снаружи
	local flowers = Random.new(math.floor(cz) * 7 + size)
	for _ = 1, 12 do
		local x = flowers:NextNumber(cx - half + 1, GATE_X - 1)
		local z = cz + (flowers:NextNumber() < 0.5 and -1 or 1) * (half + flowers:NextNumber(0.8, 2.2))
		local name = PEN_FLOWERS[flowers:NextInteger(1, #PEN_FLOWERS)][1]
		prop(pen, name, x, 0, z, flowers:NextNumber(0, 6.28), flowers:NextNumber(1.2, 1.7))
	end
	return Vector3.new(cx, PEN_TOP, cz), half
end

local function buildPlots(map)
	local plotsFolder = folder(map, "Plots")
	local plots = {}
	for i = 1, PLOT_COUNT do
		local cz = (i - 3) * PLOT_SPACING
		local plotFolder = folder(plotsFolder, "Plot" .. i)

		-- табличка над вольером: аватарка хозяина, ник, доход и сколько животных
		local gui, labelAnchor = billboard(plotFolder, Vector3.new(GATE_X - Game.PEN_SIZE / 2, 15, cz), UDim2.fromScale(14, 9.5), 250)
		local avatar = Instance.new("ImageLabel")
		avatar.AnchorPoint = Vector2.new(0.5, 0)
		avatar.Position = UDim2.fromScale(0.5, 0)
		avatar.Size = UDim2.fromScale(0.42, 0.4)
		avatar.BackgroundColor3 = rgb(255, 200, 90)
		avatar.Visible = false
		avatar.Parent = gui
		Instance.new("UIAspectRatioConstraint").Parent = avatar
		local avatarCorner = Instance.new("UICorner")
		avatarCorner.CornerRadius = UDim.new(0.5, 0)
		avatarCorner.Parent = avatar
		local avatarStroke = Instance.new("UIStroke")
		avatarStroke.Thickness = 4
		avatarStroke.Color = rgb(120, 70, 30)
		avatarStroke.Parent = avatar
		local owner = label(gui, "Free Pen", UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.4), rgb(255, 205, 110))
		local income = label(gui, "", UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.65), rgb(120, 255, 120))
		local count = iconLabel(gui, "animals", "", UDim2.fromScale(0.5, 0.15), UDim2.fromScale(0.25, 0.84), Color3.new(1, 1, 1), 0.3)
		count.Parent.Visible = false
		local spaceTitle, spacePrice, spacePrompt = buildSpaceSign(plotFolder, GATE_X + 2.5, cz - PEN_GATE - 9)
		-- если смотреть от зоны броска на вход: свой Food Shop слева, турник справа.
		-- Магазин и круг улучшения турника лежат в OwnerOnly - их видит только хозяин вольера
		local ownerOnly = folder(plotFolder, "OwnerOnly")
		buildStall(ownerOnly, Vector3.new(GATE_X + 9, 0, cz + 13), "food", rgb(60, 210, 255), "food", "FOOD SHOP", "Food", 1, false)

		local plot = {
			index = i,
			folder = plotFolder,
			-- после поимки игрока ставят сюда, лицом ко входу
			spawn = CFrame.lookAt(Vector3.new(GATE_X + 4, 4, cz), Vector3.new(GATE_X - 10, 4, cz)),
			-- новичок появляется лицом к зоне броска, а не к вольеру
			welcome = CFrame.lookAt(Vector3.new(GATE_X + 4, 4, cz), Vector3.new(GATE_X + 20, 4, cz)),
			bar = buildBar(plotFolder, Vector3.new(GATE_X + 11, 0, cz - 12), ownerOnly),
			ownerLabel = owner,
			incomeLabel = income,
			countLabel = count,
			avatar = avatar,
			spaceTitle = spaceTitle,
			spacePrice = spacePrice,
			spacePrompt = spacePrompt,
		}
		-- вольер под размер (PlotService зовет при покупке места и при смене хозяина).
		-- Вернет true, если размер поменялся
		function plot.resize(size)
			if plot.size == size then
				return false
			end
			plot.size = size
			plot.center, plot.half = buildPen(plotFolder, cz, size)
			plotFolder:SetAttribute("Center", plot.center)
			plotFolder:SetAttribute("Half", plot.half)
			labelAnchor.Position = Vector3.new(plot.center.X, 15, cz)
			return true
		end
		plot.resize(Game.PEN_SIZE)
		plots[i] = plot
	end
	return plots
end

-- Каменные тропы (как концепт G «Мшёный камень», world_concepts/make_paths.py): прозрачные картинки
-- с камнями поверх травы, в щелях видна трава. Камни нарисованы в координатах мира, плитки сходятся
-- без шва. Двор перед вольером (проход вдоль базы, дорожки ко входу, к Food Shop и к турнику)
-- у всех вольеров одинаковый: плитки y1..y4 и gate общие, рисунок повторяется с шагом PLOT_SPACING (58).
-- У помоста, Sell Shop, досок рейтинга и на концах прохода свои плитки - они дорисовывают свои камни.
-- Game.PATHS - вариант рисунка: H плитняк, I галька, J плиты-ступеньки, K мшистый камень
local PATH_Y = 0.1 -- верх троп над травой (вплотную мерцали бы)
local PATH_GATE_Y = PEN_TOP + 0.1 -- камни у входа внутри вольера лежат на его полу
local YARD_TILES = {
	y1 = { -45, -28.5, -29, 0 },
	y2 = { -45, -28.5, 0, 29 },
	y3 = { -28.5, -12, -29, 0 },
	y4 = { -28.5, -12, 0, 29 },
}
local GATE_TILE = { -53, -45, -9, 9 }
local HUB_TILES = {
	deck1 = { -20, 5.5, -24, 0 },
	deck2 = { -20, 5.5, 0, 24 },
	sell = { -20, -2, 30, 46 },
	board1 = { -20, 0, -96, -70 },
	board2 = { -20, 0, -70, -44 },
	capN = { -28.5, -12, 145, 152 },
	capS = { -28.5, -12, -152, -145 },
}

local function setPathStyle(texture, style)
	local tile = texture.Parent.Name:sub(6)
	texture.Name = "Toon_path_" .. style .. "_" .. tile
	texture.Texture = ToonKit.TextureId("path_" .. style .. "_" .. tile)
end

-- невидимая плитка, на верх которой ровно один раз ложится картинка; rect - { x0, x1, z0, z1 }
local function pathTile(parent, tile, rect, dz, top)
	local x0, x1, z0, z1 = rect[1], rect[2], rect[3] + dz, rect[4] + dz
	local p = part(parent, {
		Name = "Path_" .. tile, Size = Vector3.new(x1 - x0, 0.05, z1 - z0), Position = Vector3.new((x0 + x1) / 2, top - 0.025, (z0 + z1) / 2),
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	})
	local texture = Instance.new("Texture")
	texture.Face = Enum.NormalId.Top
	texture.StudsPerTileU = x1 - x0
	texture.StudsPerTileV = z1 - z0
	texture.Parent = p
	setPathStyle(texture, Game.PATHS)
	return p
end

local function buildPaths(map)
	assert(PLOT_SPACING == 58, "картинки двора нарисованы под шаг вольеров 58 (make_paths.py PERIOD)")
	local paths = folder(map, "Paths")
	for i = 1, PLOT_COUNT do
		local cz = (i - 3) * PLOT_SPACING
		for tile, rect in YARD_TILES do
			pathTile(paths, tile, rect, cz, PATH_Y)
		end
		pathTile(paths, "gate", GATE_TILE, cz, PATH_GATE_Y)
	end
	for tile, rect in HUB_TILES do
		pathTile(paths, tile, rect, 0, PATH_Y)
	end
	-- в Studio вариант можно сменить на лету: workspace:SetAttribute("Paths", "K") в Server-контексте
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("Paths"):Connect(function()
			local style = workspace:GetAttribute("Paths")
			for _, texture in paths:GetDescendants() do
				if texture:IsA("Texture") then
					setPathStyle(texture, style)
				end
			end
		end)
	end
end

-- что растет в каждой зоне: на уступах и на верху скал, камни у полосы и текстура пола
local ZONE_DECOR = {
	forest = {
		ground = GRASS,
		rock = "Rock2",
		list = { { "Tree1", 1 }, { "Tree2", 1 }, { "Tree3", 1 }, { "Pine1", 1 }, { "Pine2", 1 },
			{ "Bush1", 0.7 }, { "Bush2", 0.7 }, { "Bush3", 0.7 }, { "Rock1", 0.4 }, { "Rock3", 0.4 }, { "Stump", 0.3 }, { "Mushroom", 0.3 } },
	},
	savanna = {
		ground = "soft_savanna",
		rock = "RockSand",
		list = { { "Acacia1", 1.4 }, { "Acacia2", 1.4 }, { "DryTuft", 1.5 }, { "RockSand", 0.6 }, { "Bush2", 0.3 } },
	},
	desert = {
		ground = "soft_sand",
		rock = "RockSand",
		list = { { "Cactus1", 1.5 }, { "Cactus2", 1.5 }, { "RockSand", 1 }, { "DryTuft", 0.5 } },
	},
	jungle = {
		ground = "soft_jungle",
		rock = "Rock2",
		list = { { "Palm1", 1.4 }, { "Palm2", 1.4 }, { "Bush1", 0.8 }, { "Bush2", 0.8 }, { "Tree3", 0.5 }, { "Tuft2", 0.6 } },
	},
	swamp = {
		ground = "soft_swamp",
		rock = "Rock2",
		list = { { "DeadTree1", 1.2 }, { "DeadTree2", 1.2 }, { "Reeds", 1.4 }, { "Mushroom", 0.6 }, { "Bush2", 0.5 } },
	},
	coast = {
		ground = "soft_sand",
		rock = "RockGrey",
		list = { { "Palm1", 1.3 }, { "Palm2", 1.3 }, { "RockGrey", 1 }, { "Tuft1", 0.6 } },
	},
}

local MODULE_LENGTH = 42 -- длина модулей уступов и скал каньона в Blender

-- табличка зоны на левом уступе, в стороне от линии полета
local function buildZoneSign(f, zone, index, x)
	local z = -(LANE_HALF + LEDGE_WIDTH / 2)
	local board = part(f, {
		Name = "Sign", Size = Vector3.new(1, 6, 14), Position = Vector3.new(x, FLOOR + LEDGE_HEIGHT + 7, z),
		Color = rgb(85, 55, 35), Material = Enum.Material.Wood, CanCollide = false,
	})
	for _, dz in { -6, 6 } do
		decor(f, Vector3.new(1, 10, 1), CFrame.new(x, FLOOR + LEDGE_HEIGHT + 5, z + dz), rgb(130, 85, 50), Enum.Material.Wood)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Parent = board
	iconLabel(gui, IconAtlas.Zone(zone), "ZONE " .. index .. " · " .. string.upper(zone.name), UDim2.fromScale(0.96, 0.56), UDim2.fromScale(0.02, 0.04), rgb(255, 235, 150), 0.14)
	iconLabel(gui, "strength", "Needs " .. Format.Number(zone.power), UDim2.fromScale(0.6, 0.36), UDim2.fromScale(0.2, 0.6), Color3.new(1, 1, 1), 0.2)
end

local function buildField(map)
	local field = folder(map, "Field")
	local width = FIELD_HALF_WIDTH * 2
	for index, zone in ipairs(Zones) do
		local zoneFolder = folder(field, zone.id)
		local look = ZONE_DECOR[zone.id] or ZONE_DECOR.forest
		local x0 = Game.FIELD_START + zone.start
		local x1 = x0 + zone.length
		if index == 1 then
			x0 = 13 -- закрываем щель между обрывом и полем
		end
		local length = x1 - x0
		-- дно каньона: своя текстура зоны, сверху крупные пятна
		floorPart(zoneFolder, "Ground", Vector3.new(length, 2, width), Vector3.new((x0 + x1) / 2, FLOOR - 1, 0), look.ground, 36, zone.ground, { CanQuery = false })
		if index > 1 then
			decor(zoneFolder, Vector3.new(1.5, 0.1, width), CFrame.new(x0, FLOOR + 0.05, 0), Color3.new(1, 1, 1))
			buildZoneSign(zoneFolder, zone, index, Game.FIELD_START + zone.start + 2)
		end

		-- стены каньона: уступ пониже у полосы, за ним скала (мульт-модули по ~42 студа).
		-- Под ними детали тех же размеров: держат и закрывают щели, а сверху на скалах - трава зоны
		local cap = string.upper(string.sub(zone.id, 1, 1)) .. string.sub(zone.id, 2)
		local modules = math.max(1, math.round(length / MODULE_LENGTH))
		local step = length / modules
		for _, side in { -1, 1 } do
			local ledgeZ = side * (LANE_HALF + 1 + (LEDGE_WIDTH - 1) / 2)
			part(zoneFolder, {
				Name = "Ledge", Size = Vector3.new(length, LEDGE_HEIGHT, LEDGE_WIDTH - 1), Position = Vector3.new((x0 + x1) / 2, FLOOR + LEDGE_HEIGHT / 2, ledgeZ),
				Color = zone.wall, CanQuery = false,
			})
			local cliffZ0 = LANE_HALF + LEDGE_WIDTH + 1
			local cliffDepth = FAR - cliffZ0
			floorPart(zoneFolder, "Cliff", Vector3.new(length, TOP_Y - FLOOR, cliffDepth), Vector3.new((x0 + x1) / 2, (FLOOR + TOP_Y) / 2, side * (cliffZ0 + cliffDepth / 2)),
				look.ground, 44, zone.wall, { CanQuery = false })
			-- лицом к полосе: справа (z > 0) смотрят к -Z, слева - к +Z
			local face = Vector3.new(0, 0, -side)
			for j = 0, modules - 1 do
				local xa = side > 0 and x0 + j * step or x0 + (j + 1) * step
				local v = (j + index) % 2 == 0 and "A" or "B"
				ToonKit.Wall(zoneFolder, "Ledge" .. cap .. v, Vector3.new(xa, FLOOR, side * LANE_HALF), face, step, MODULE_LENGTH)
				ToonKit.Wall(zoneFolder, "Cliff" .. cap .. (v == "A" and "B" or "A"), Vector3.new(xa, FLOOR + LEDGE_HEIGHT, side * (LANE_HALF + LEDGE_WIDTH)), face, step, MODULE_LENGTH)
			end
			-- камни на стыке полосы и уступа, чтобы край не был ровной линией
			for _ = 1, 9 do
				prop(zoneFolder, look.rock, rng:NextNumber(x0 + 4, x1 - 4), FLOOR, side * (LANE_HALF - 0.8), rng:NextNumber(0, 6.28), rng:NextNumber(0.7, 1.2))
			end
			-- декор только на уступах и скалах: полоса чистая, там падает еда и стоит камера
			for _ = 1, math.floor(length / 14) do
				prop(zoneFolder, pick(look.list), rng:NextNumber(x0 + 4, x1 - 4), FLOOR + LEDGE_HEIGHT + 0.9,
					side * rng:NextNumber(LANE_HALF + 2.5, LANE_HALF + LEDGE_WIDTH - 2), rng:NextNumber(0, 6.28), rng:NextNumber(0.6, 0.9))
			end
			for _ = 1, math.floor(length / 9) do
				prop(zoneFolder, pick(look.list), rng:NextNumber(x0 + 4, x1 - 4), TOP_Y,
					side * rng:NextNumber(LANE_HALF + LEDGE_WIDTH + 6, LANE_HALF + LEDGE_WIDTH + 80), rng:NextNumber(0, 6.28), rng:NextNumber(0.9, 1.4))
			end
		end
	end

	-- море за последней зоной
	local fieldEnd = Game.FIELD_START + Formula.FIELD_LENGTH
	floorPart(field, "Sea", Vector3.new(1600, 1, 2400), Vector3.new(fieldEnd + 800, FLOOR - 0.8, 0), "water", 30, rgb(40, 130, 210),
		{ CanCollide = false, CanQuery = false })
end

-- три доски лидеров у левой скалы у зоны броска, лицом к базе; строки заполняет LeaderboardService.
-- Рамка и козырек - мульт-моделька Board на двух столбах, строки - на детали перед рамкой
local BOARD_ROWS = 8
local BOARD_X = 0.6 -- перед скалой: ее камни выступают до 3 студов, торец горы у помоста кончается на z = -40

local function buildBoards(map)
	local boardsFolder = folder(map, "Leaderboards")
	local list = {
		{ id = "animals", icon = "animals", title = "MOST ANIMALS", color = rgb(120, 220, 110) },
		{ id = "money", icon = "money", title = "TOP MONEY", color = rgb(255, 210, 70) },
		{ id = "luck", icon = "luck", title = "LUCKIEST CATCH", color = rgb(110, 200, 255) },
	}
	local boards = {}
	for i, info in list do
		-- смотрим на скалу вдоль +X, поэтому -Z слева: первая доска левая
		local z = -52 - (#list - i) * 17
		ToonKit.Place(boardsFolder, "Board", CFrame.new(BOARD_X, 0, z))
		for _, dz in { -7.9, 7.9 } do
			ToonKit.Place(boardsFolder, "FencePost", CFrame.new(BOARD_X + 0.3, 0, z + dz), 1, Vector3.new(1.2, 3.6, 1.2))
		end
		local board = part(boardsFolder, {
			Name = info.id, Size = Vector3.new(0.3, 12, 14), Position = Vector3.new(BOARD_X - 0.42, 8, z),
			Color = rgb(35, 30, 45), Material = Enum.Material.SmoothPlastic, CanCollide = false,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Left
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 25
		gui.Parent = board
		local header = Instance.new("Frame")
		header.Size = UDim2.fromScale(1, 0.16)
		header.BackgroundColor3 = info.color
		header.BorderSizePixel = 0
		header.Parent = gui
		iconLabel(header, info.icon, info.title, UDim2.fromScale(0.92, 0.8), UDim2.fromScale(0.04, 0.1), Color3.new(1, 1, 1), 0.13)
		local rows = {}
		for r = 1, BOARD_ROWS do
			local row = Instance.new("Frame")
			row.Size = UDim2.fromScale(0.94, 0.095)
			row.Position = UDim2.fromScale(0.03, 0.18 + (r - 1) * 0.102)
			row.BackgroundColor3 = r % 2 == 0 and rgb(55, 50, 70) or rgb(48, 43, 60)
			row.BorderSizePixel = 0
			row.Parent = gui
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.25, 0)
			corner.Parent = row
			local rankColor = r == 1 and rgb(255, 215, 60) or r == 2 and rgb(210, 215, 225) or r == 3 and rgb(225, 150, 80) or Color3.new(1, 1, 1)
			label(row, "#" .. r, UDim2.fromScale(0.14, 0.8), UDim2.fromScale(0.02, 0.1), rankColor)
			local name = label(row, "", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.17, 0.15))
			name.TextXAlignment = Enum.TextXAlignment.Left
			local value = label(row, "", UDim2.fromScale(0.3, 0.7), UDim2.fromScale(0.67, 0.15), info.color)
			value.TextXAlignment = Enum.TextXAlignment.Right
			rows[r] = { name = name, value = value }
		end
		boards[info.id] = rows
	end
	return boards
end

local TREES = { { "Tree1", 1 }, { "Tree2", 1 }, { "Tree3", 1 }, { "Pine1", 1 }, { "Pine2", 1 } }
local WALLS = { "WallA", "WallB", "WallC" }
local TOPS = { "TopA", "TopB", "TopC" }

-- скалы по краю базы слева и справа от зоны броска: каньон начинается прямо от полосы,
-- и вдоль обрыва не кажется, что туда можно пройти. Невидимые детали держат игрока
local function buildEdgeMountains(map)
	local mountains = folder(map, "EdgeMountains")
	local top = FLOOR + CLIFF_HEIGHT -- вровень со скалами каньона
	local x0, x1 = EDGE_WALL_X, 14
	local z0, z1 = Game.THROW_PAD.halfZ, BASE_HALF_Z -- дальше угол кольца гор
	for _, side in { -1, 1 } do
		local length = z1 - z0
		solid(mountains, "Mountain", Vector3.new(x1 - x0, top, length), CFrame.new((x0 + x1) / 2, top / 2, side * (z0 + length / 2)))
		-- лицом к базе (-X): модули идут вдоль -Z от угла
		for j = 0, 3 do
			local zStart = side > 0 and z0 + (j + 1) * 31 or -(z0 + j * 31)
			ToonKit.Wall(mountains, j % 2 == 0 and "EdgeA" or "EdgeB", Vector3.new(x0, 0, zStart), -Vector3.xAxis, 31, 31)
		end
		-- торец к помосту
		if side > 0 then
			ToonKit.Wall(mountains, "Side", Vector3.new(x0, 0, z0), -Vector3.zAxis, 10, 10)
		else
			ToonKit.Wall(mountains, "Side", Vector3.new(x1, 0, -z0), Vector3.zAxis, 10, 10)
		end
		-- деревья на гребне
		for z = z0 + 6, z1 - 4, 9 do
			if rng:NextNumber() < 0.6 then
				prop(mountains, pick(TREES), x0 + rng:NextNumber(3, 7), TOP_Y, side * z, rng:NextNumber(0, 6.28), rng:NextNumber(0.8, 1.15))
			end
		end
	end
end

-- Горы вокруг всей базы: за вольерами и по бокам, вровень со скалами каньона. Мульт-модули скал
-- лицом к базе, на них второй ярус глыб и деревья; вокруг плато с травой, на нем лес и холмы

local function buildMountainRing(map)
	local ring = folder(map, "MountainRing")
	local z = BASE_HALF_Z
	-- за вольерами: лицом к +X, модули идут вдоль +Z
	local count = math.round(z * 2 / 38)
	local step = z * 2 / count
	for j = 0, count - 1 do
		local zs = -z + j * step
		ToonKit.Wall(ring, WALLS[j % 3 + 1], Vector3.new(BASE_MIN_X, 0, zs), Vector3.xAxis, step, 38)
		local back = rng:NextNumber(7, 10)
		ToonKit.Wall(ring, TOPS[j % 3 + 1], Vector3.new(BASE_MIN_X - back, TOP_Y - 0.3, zs + 2), Vector3.xAxis, 17, 19, rng:NextNumber(0.8, 1.3))
		ToonKit.Wall(ring, TOPS[(j + 1) % 3 + 1], Vector3.new(BASE_MIN_X - back + 1, TOP_Y - 0.3, zs + 20), Vector3.xAxis, 16, 19, rng:NextNumber(0.6, 1.0))
		for _ = 1, 2 do
			prop(ring, pick(TREES), BASE_MIN_X - rng:NextNumber(2, back - 1.5), TOP_Y, zs + rng:NextNumber(3, step - 3), rng:NextNumber(0, 6.28), rng:NextNumber(0.8, 1.2))
		end
	end
	-- бока от задней стены до гор у зоны броска
	local sideLength = EDGE_WALL_X - BASE_MIN_X
	local sideCount = math.round(sideLength / 38)
	local sideStep = sideLength / sideCount
	for _, side in { -1, 1 } do
		for j = 0, sideCount - 1 do
			local xs = BASE_MIN_X + j * sideStep
			-- справа (z > 0) лицом к -Z, модуль идет вдоль +X; слева наоборот
			local cornerX = side > 0 and xs or xs + sideStep
			ToonKit.Wall(ring, WALLS[(j + 1) % 3 + 1], Vector3.new(cornerX, 0, side * z), Vector3.new(0, 0, -side), sideStep, 38)
			for _ = 1, 3 do
				prop(ring, pick(TREES), xs + rng:NextNumber(2, sideStep - 2), TOP_Y, side * (z + rng:NextNumber(2.5, 9)), rng:NextNumber(0, 6.28), rng:NextNumber(0.8, 1.2))
			end
		end
	end

	-- за модулями стен - сплошная земля до плато: на стыках модулей (особенно в задних углах)
	-- у самой земли оставались щели, и в них было видно небо
	-- Земля начинается в 3 студах за лицом стен (выступы камней ее закрывают) и уходит вниз
	-- под уровень базы: в щель смотрят сверху вниз, луч проходил под тонкой стенкой
	local BOTTOM, DEPTH = -12, 30
	local height = TOP_Y - 1 - BOTTOM
	part(ring, {
		Name = "Backstop", Size = Vector3.new(DEPTH, height, z * 2 + 2 * DEPTH), Position = Vector3.new(BASE_MIN_X - 3 - DEPTH / 2, BOTTOM + height / 2, 0),
		Color = DIRT, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
	})
	for _, side in { -1, 1 } do
		part(ring, {
			Name = "Backstop", Size = Vector3.new(sideLength + DEPTH, height, DEPTH), Position = Vector3.new(BASE_MIN_X + (sideLength - DEPTH) / 2, BOTTOM + height / 2, side * (z + 3 + DEPTH / 2)),
			Color = DIRT, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		})
	end

	-- плато за горами: сзади и по бокам базы (над каньоном его продолжают верхи скал зон)
	local backX0 = BASE_MIN_X - 1
	floorPart(ring, "Plateau", Vector3.new(FAR, 2, FAR * 2), Vector3.new(backX0 - FAR / 2, TOP_Y - 1, 0), GRASS, 44, Zones[1].wall, { CanQuery = false })
	for _, side in { -1, 1 } do
		local zIn = z + 1
		floorPart(ring, "Plateau", Vector3.new(13 - backX0, 2, FAR - zIn), Vector3.new((backX0 + 13) / 2, TOP_Y - 1, side * (zIn + (FAR - zIn) / 2)),
			GRASS, 44, Zones[1].wall, { CanQuery = false })
	end

	-- лес и холмы, чтобы горизонт не был пустым
	local forest = folder(ring, "Forest")
	for _ = 1, 90 do
		prop(forest, pick(TREES), rng:NextNumber(-260, BASE_MIN_X - 15), TOP_Y, rng:NextNumber(-330, 330), rng:NextNumber(0, 6.28), rng:NextNumber(1, 1.6))
	end
	for _, side in { -1, 1 } do
		for _ = 1, 45 do
			prop(forest, pick(TREES), rng:NextNumber(-260, 10), TOP_Y, side * rng:NextNumber(z + 16, 330), rng:NextNumber(0, 6.28), rng:NextNumber(1, 1.6))
		end
	end
	for j = 0, 8 do
		local h = ({ 1.0, 1.25, 0.8 })[j % 3 + 1]
		ToonKit.Wall(forest, j % 2 == 0 and "HillA" or "HillB", Vector3.new(-275 - (j % 2) * 25, TOP_Y - 0.9, -360 + j * 80), Vector3.xAxis, 80, 80, h)
	end
	for _, side in { -1, 1 } do
		for j = 0, 3 do
			local h = ({ 1.05, 0.8, 1.2 })[j % 3 + 1]
			local xs = -300 + j * 80
			ToonKit.Wall(forest, j % 2 == 0 and "HillB" or "HillA", Vector3.new(side > 0 and xs or xs + 80, TOP_Y - 0.9, side * 345), Vector3.new(0, 0, -side), 80, 80, h)
		end
	end
end

-- облака: мульт-облака высоко над картой
local function buildSky(map)
	local sky = folder(map, "Sky")
	for i = 1, 14 do
		prop(sky, "Cloud" .. (i % 3 + 1), rng:NextNumber(-500, 1500), rng:NextNumber(85, 160), (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(60, 600),
			rng:NextNumber(-0.3, 0.3), rng:NextNumber(1, 2))
	end
end

function MapService.Build()
	setupLighting(Looks[Game.LOOK] or Looks.juicy)
	-- в Studio цветокор можно переключать на лету: workspace:SetAttribute("Look", "golden")
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("Look"):Connect(function()
			local look = Looks[workspace:GetAttribute("Look")]
			if look then
				setupLighting(look)
			end
		end)
	end
	local map = folder(workspace, "Map")
	buildBase(map)
	buildMountainRing(map)
	buildHub(map)
	local plots = buildPlots(map)
	buildPaths(map)
	local boards = buildBoards(map)
	buildField(map)
	buildEdgeMountains(map)
	buildSky(map)
	return { plots = plots, boards = boards }
end

return MapService
