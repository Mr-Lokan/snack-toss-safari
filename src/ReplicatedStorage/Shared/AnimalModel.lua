local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local Animals = require(Config:WaitForChild("Animals"))
local Mutations = require(Config:WaitForChild("Mutations"))

-- Животные собираются из блоков по параметрам из Config.Animals.
-- Ноги стоят на y = 0, морда смотрит в -Z (как LookVector), пивот модели в (0, 0, 0).
local AnimalModel = {}

local EYE_COLOR = Color3.fromRGB(25, 25, 30)
local BEAK_COLOR = Color3.fromRGB(255, 170, 40)
local SIDES = { -1, 1 }

local function block(model, size, cframe, color, shape)
	local part = Instance.new("Part")
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

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

local function eyes(model, size, x, y, z)
	for _, side in SIDES do
		local eye = block(model, Vector3.new(size, size, size * 0.4), at(side * x, y, z), EYE_COLOR)
		eye.Name = "Eye"
		eye:SetAttribute("Eye", true)
	end
end

-- уши, рога и прочее на голове; head - размер головы, (hy, hz) - центр
local function headDetails(model, p, s, head, hy, hz)
	local c = p.color
	local top = hy + head * 0.425

	if p.ears == "pointy" then
		for _, side in SIDES do
			block(model, Vector3.new(head * 0.22, head * 0.4, head * 0.12),
				at(side * head * 0.3, top + head * 0.18, hz + head * 0.1) * CFrame.Angles(0, 0, -side * 0.2), c)
		end
	elseif p.ears == "long" then
		for _, side in SIDES do
			block(model, Vector3.new(head * 0.2, head * 0.95, head * 0.12),
				at(side * head * 0.2, top + head * 0.45, hz + head * 0.15) * CFrame.Angles(0.15, 0, -side * 0.1), c)
		end
	elseif p.ears == "round" then
		for _, side in SIDES do
			block(model, Vector3.new(head * 0.3, head * 0.3, head * 0.12), at(side * head * 0.42, top + head * 0.05, hz + head * 0.1), c)
		end
	elseif p.ears == "big" then
		for _, side in SIDES do
			block(model, Vector3.new(head * 0.1, head * 0.95, head * 0.8), at(side * head * 0.56, hy, hz + head * 0.25), c)
		end
	end

	if p.horns == "antlers" then
		local color = p.glow and p.color2 or Color3.fromRGB(215, 195, 160)
		for _, side in SIDES do
			local x = side * head * 0.28
			block(model, Vector3.new(0.12 * s, head * 0.9, 0.12 * s), at(x, top + head * 0.4, hz + head * 0.1) * CFrame.Angles(0, 0, -side * 0.35), color)
			block(model, Vector3.new(0.1 * s, head * 0.45, 0.1 * s), at(x + side * head * 0.35, top + head * 0.75, hz + head * 0.1) * CFrame.Angles(0, 0, -side * 1.1), color)
			block(model, Vector3.new(0.1 * s, head * 0.4, 0.1 * s), at(x + side * head * 0.15, top + head * 0.75, hz - head * 0.15) * CFrame.Angles(-0.6, 0, 0), color)
		end
	elseif p.horns == "horns" then
		for _, side in SIDES do
			block(model, Vector3.new(0.14 * s, head * 0.4, 0.14 * s), at(side * head * 0.25, top + head * 0.15, hz) * CFrame.Angles(0.3, 0, -side * 0.3), Color3.fromRGB(80, 60, 50))
		end
	end
end

local function buildQuad(model, p, s)
	local c = p.color
	local body = (p.body or Vector3.new(1, 0.9, 1.5)) * s
	local legH = (p.legs or 0.6) * s
	local head = (p.head or 0.8) * s
	local neck = (p.neck or 0) * s
	local bodyY = legH + body.Y / 2

	local main = block(model, body, at(0, bodyY, 0), c)
	main.Name = "Body"

	-- ноги по диагонали шагают в одной фазе
	local legW = math.max(0.2 * s, math.min(body.X, body.Z) * 0.22)
	for _, sx in SIDES do
		for _, sz in SIDES do
			local leg = block(model, Vector3.new(legW, legH + body.Y * 0.2, legW),
				at(sx * (body.X / 2 - legW / 2), (legH + body.Y * 0.2) / 2, sz * (body.Z / 2 - legW * 0.6)), c)
			leg:SetAttribute("Leg", sx * sz > 0 and 0 or math.pi)
		end
	end

	-- голова, с шеей - над передом тела
	local hy = legH + body.Y * 0.85 + neck
	local hz = -body.Z / 2 - head * 0.25
	if neck > 0 then
		hz = -body.Z / 2 + head * 0.2
		block(model, Vector3.new(head * 0.45, neck + body.Y * 0.4, head * 0.45), at(0, legH + body.Y * 0.7 + neck / 2, hz + head * 0.1), c)
	end
	if p.mane then
		block(model, Vector3.new(head * 1.5, head * 1.45, head * 0.7), at(0, hy - head * 0.05, hz + head * 0.35), p.mane)
	end
	local headPart = block(model, Vector3.new(head, head * 0.85, head), at(0, hy, hz), p.headColor or c)
	headPart.Name = "Head"
	local front = hz - head / 2

	if p.snout then
		local len = p.snout * s
		block(model, Vector3.new(head * 0.55, head * 0.42, len), at(0, hy - head * 0.18, front - len / 2 + 0.02), c)
		block(model, Vector3.new(head * 0.2, head * 0.14, head * 0.08), at(0, hy - head * 0.05, front - len), EYE_COLOR)
		if p.horns == "horn" then
			block(model, Vector3.new(0.2 * s, head * 0.55, 0.2 * s), at(0, hy + head * 0.12, front - len * 0.7) * CFrame.Angles(0.35, 0, 0), Color3.fromRGB(215, 205, 190))
		end
	end
	if p.trunk then
		block(model, Vector3.new(head * 0.28, head * 1.1, head * 0.28), at(0, hy - head * 0.6, front - head * 0.12), c)
	end
	if p.tusks then
		for _, side in SIDES do
			block(model, Vector3.new(0.1 * s, 0.1 * s, head * 0.45), at(side * head * 0.22, hy - head * 0.35, front - head * 0.15) * CFrame.Angles(0.5, 0, 0), Color3.fromRGB(250, 245, 230))
		end
	end
	eyes(model, head * 0.16, head * 0.25, hy + head * 0.12, front - head * 0.03)
	headDetails(model, p, s, head, hy, hz)

	-- грудь вторым цветом
	if p.color2 and not p.wings then
		block(model, Vector3.new(body.X * 0.6, body.Y * 0.6, 0.06 * s), at(0, bodyY - body.Y * 0.1, -body.Z / 2 - 0.02), p.color2)
	end

	-- хвост
	local back = body.Z / 2
	local tailY = legH + body.Y * 0.7
	if p.tail == "thin" then
		block(model, Vector3.new(0.12 * s, 0.12 * s, body.Z * 0.4), at(0, tailY - body.Z * 0.08, back + body.Z * 0.16) * CFrame.Angles(0.6, 0, 0), c):SetAttribute("Tail", "z")
	elseif p.tail == "fluffy" then
		local k = p.tailSize or 1
		block(model, Vector3.new(body.X * 0.45 * k, body.Y * 0.7 * k, body.Y * 0.45 * k), at(0, tailY + body.Y * 0.2 * k, back + body.Y * 0.2 * k) * CFrame.Angles(-0.4, 0, 0), c):SetAttribute("Tail", "y")
	elseif p.tail == "long" then
		block(model, Vector3.new(0.2 * s, 0.2 * s, body.Z * 0.9), at(0, tailY - 0.1 * s, back + body.Z * 0.42) * CFrame.Angles(0.25, 0, 0), c):SetAttribute("Tail", "z")
	elseif p.tail == "short" then
		block(model, Vector3.new(0.25 * s, 0.25 * s, 0.25 * s), at(0, tailY, back + 0.1 * s), p.color2 or c)
	end

	-- пятна и полосы
	if p.spots then
		local topY = legH + body.Y + 0.01
		block(model, Vector3.new(body.X * 0.3, 0.05 * s, body.Z * 0.2), at(body.X * 0.15, topY, -body.Z * 0.2), p.spots)
		block(model, Vector3.new(body.X * 0.25, 0.05 * s, body.Z * 0.18), at(-body.X * 0.2, topY, body.Z * 0.22), p.spots)
		for _, side in SIDES do
			block(model, Vector3.new(0.05 * s, body.Y * 0.3, body.Z * 0.2), at(side * (body.X / 2 + 0.01), bodyY + body.Y * 0.1, side * body.Z * 0.15), p.spots)
		end
	end
	if p.stripes then
		for i = 1, 3 do
			block(model, Vector3.new(body.X + 0.04 * s, body.Y + 0.04 * s, body.Z * 0.08), at(0, bodyY, -body.Z / 2 + body.Z * (0.05 + 0.25 * i)), p.stripes)
		end
	end
	if p.hump then
		for i = 1, p.hump do
			local z = p.hump == 1 and 0 or (i == 1 and -body.Z * 0.2 or body.Z * 0.2)
			block(model, Vector3.new(body.X * 0.6, body.Y * 0.55, body.Z * 0.3), at(0, legH + body.Y * 1.15, z), c)
		end
	end
	if p.shell then
		block(model, Vector3.new(body.X * 1.15, body.Y * 0.75, body.Z * 1.1), at(0, bodyY + body.Y * 0.3, 0), p.shell)
		block(model, Vector3.new(body.X * 0.8, body.Y * 0.4, body.Z * 0.75), at(0, bodyY + body.Y * 0.75, 0), p.shell)
	end
	if p.wings then
		for _, side in SIDES do
			block(model, Vector3.new(body.Z * 0.9, 0.08 * s, body.Z * 0.6),
				at(side * (body.X / 2 + body.Z * 0.4), legH + body.Y + 0.2 * s, 0) * CFrame.Angles(0, 0, side * 0.35), p.color2 or c)
		end
	end
	return main
end

local function buildBird(model, p, s)
	local c = p.color
	local body = (p.body or Vector3.new(1, 1, 1.2)) * s
	local legH = (p.legs or 0.35) * s
	local head = (p.head or 0.7) * s
	local neck = (p.neck or 0) * s
	local beak = p.beakColor or BEAK_COLOR

	local main = block(model, body, at(0, legH + body.Y / 2, 0), c)
	main.Name = "Body"

	for _, side in SIDES do
		local leg = block(model, Vector3.new(0.12 * s, legH + 0.1 * s, 0.12 * s), at(side * body.X * 0.22, legH / 2 + 0.05 * s, 0), beak)
		leg:SetAttribute("Leg", side < 0 and 0 or math.pi)
		block(model, Vector3.new(0.3 * s, 0.06 * s, 0.35 * s), at(side * body.X * 0.22, 0.03 * s, -0.1 * s), beak)
		block(model, Vector3.new(0.12 * s, body.Y * 0.7, body.Z * 0.75), at(side * (body.X / 2 + 0.05 * s), legH + body.Y * 0.55, 0.05 * s), p.color2 or c)
	end

	local hz = -body.Z * 0.25
	local hy = legH + body.Y + head * 0.3 + neck
	if neck > 0 then
		block(model, Vector3.new(head * 0.35, neck + head * 0.3, head * 0.35), at(0, legH + body.Y + neck / 2, hz), p.headColor or c)
	end
	local headPart = block(model, Vector3.new(head, head * 0.9, head), at(0, hy, hz), p.headColor or c)
	headPart.Name = "Head"
	local front = hz - head / 2
	block(model, Vector3.new(head * 0.3, head * 0.22, head * 0.45), at(0, hy - head * 0.1, front - head * 0.2), beak)
	eyes(model, head * 0.17, head * 0.25, hy + head * 0.12, front - head * 0.03)
	headDetails(model, p, s, head, hy, hz)

	if p.color2 then
		block(model, Vector3.new(body.X * 0.7, body.Y * 0.7, 0.06 * s), at(0, legH + body.Y * 0.45, -body.Z / 2 - 0.02), p.color2)
	end
	block(model, Vector3.new(body.X * 0.6, 0.1 * s, body.Z * 0.4), at(0, legH + body.Y * 0.35, body.Z / 2 + body.Z * 0.15) * CFrame.Angles(-0.4, 0, 0), p.color2 or c):SetAttribute("Tail", "z")
	return main
end

local function buildCrab(model, p, s)
	local c = p.color
	local body = (p.body or Vector3.new(1.6, 0.6, 1.1)) * s
	local bodyY = 0.45 * s + body.Y / 2

	local main = block(model, body, at(0, bodyY, 0), c)
	main.Name = "Body"

	for _, side in SIDES do
		for i = 1, 3 do
			block(model, Vector3.new(0.7 * s, 0.12 * s, 0.12 * s),
				at(side * (body.X / 2 + 0.2 * s), 0.3 * s, (i - 2) * body.Z * 0.32) * CFrame.Angles(0, 0, -side * 0.6), c)
		end
		block(model, Vector3.new(0.2 * s, 0.2 * s, 0.6 * s), at(side * body.X * 0.35, bodyY, -body.Z / 2 - 0.25 * s), c)
		block(model, Vector3.new(0.45 * s, 0.35 * s, 0.45 * s), at(side * body.X * 0.38, bodyY + 0.05 * s, -body.Z / 2 - 0.65 * s), c)
		block(model, Vector3.new(0.08 * s, 0.35 * s, 0.08 * s), at(side * 0.2 * s, bodyY + body.Y / 2 + 0.15 * s, -body.Z / 2 + 0.15 * s), c)
	end
	eyes(model, 0.17 * s, 0.2 * s, bodyY + body.Y / 2 + 0.38 * s, -body.Z / 2 + 0.15 * s)

	if p.tail == "stinger" then
		local points = { Vector3.new(0, 0.1, 0.65), Vector3.new(0, 0.45, 0.95), Vector3.new(0, 0.85, 1.05), Vector3.new(0, 1.15, 0.85) }
		for _, point in points do
			block(model, Vector3.new(0.28, 0.28, 0.28) * s, at(0, bodyY + point.Y * s, body.Z / 2 - 0.3 * s + point.Z * s), c)
		end
		block(model, Vector3.new(0.14, 0.35, 0.14) * s, at(0, bodyY + 1.05 * s, body.Z / 2 + 0.25 * s) * CFrame.Angles(-0.8, 0, 0), Color3.fromRGB(200, 40, 40))
	end
	if p.long then
		for i = 1, 3 do
			block(model, Vector3.new(body.X * (0.7 - i * 0.12), body.Y * 0.8, 0.42 * s), at(0, bodyY - i * 0.04 * s, body.Z / 2 + 0.2 * s + (i - 1) * 0.4 * s), c)
		end
		block(model, Vector3.new(body.X * 0.6, 0.1 * s, 0.4 * s), at(0, bodyY - 0.15 * s, body.Z / 2 + 1.35 * s), c)
	end
	return main
end

local function buildBlob(model, p, s)
	local c = p.color
	local r = 1.4 * s
	local cy = 0.7 * s + r / 2

	local main = block(model, Vector3.new(r, r, r), at(0, cy, 0), c, Enum.PartType.Ball)
	main.Name = "Body"
	block(model, Vector3.new(r * 0.8, 0.5 * s, r * 0.8), at(0, 0.6 * s, 0), c)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		block(model, Vector3.new(0.24 * s, 0.18 * s, 1 * s),
			CFrame.new(0, 0.25 * s, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.65 * s) * CFrame.Angles(-0.15, 0, 0), c)
	end
	for _, side in SIDES do
		block(model, Vector3.new(r * 0.24, r * 0.24, 0.1 * s), at(side * r * 0.2, cy + r * 0.08, -r * 0.45), Color3.new(1, 1, 1))
	end
	eyes(model, r * 0.12, r * 0.2, cy + r * 0.08, -r * 0.5)
	return main
end

local function buildFin(model, p, s)
	local c = p.color
	local body = (p.body or Vector3.new(1.1, 1, 3)) * s
	local bodyY = body.Y / 2 + 0.1 * s

	local main = block(model, body, at(0, bodyY, 0), c)
	main.Name = "Body"
	block(model, Vector3.new(body.X * 0.7, body.Y * 0.7, body.Z * 0.2), at(0, bodyY - body.Y * 0.05, -body.Z / 2 - body.Z * 0.1), c)
	if p.color2 then
		block(model, Vector3.new(body.X * 0.85, body.Y * 0.3, body.Z * 0.95), at(0, bodyY - body.Y * 0.38, 0), p.color2)
	end

	block(model, Vector3.new(body.X * 0.4, body.Y * 0.4, body.Z * 0.3), at(0, bodyY + body.Y * 0.05, body.Z / 2 + body.Z * 0.12), c)
	if p.fin == "whale" then
		block(model, Vector3.new(body.X * 1.8, 0.15 * s, body.Z * 0.25), at(0, bodyY + 0.1 * s, body.Z / 2 + body.Z * 0.32), c)
	else
		block(model, Vector3.new(0.15 * s, body.Y * 1.1, body.Z * 0.22), at(0, bodyY + body.Y * 0.2, body.Z / 2 + body.Z * 0.28) * CFrame.Angles(0.3, 0, 0), c)
		block(model, Vector3.new(0.15 * s, body.Y * 0.75, body.Z * 0.22), at(0, bodyY + body.Y * 0.7, -body.Z * 0.05) * CFrame.Angles(0.35, 0, 0), c)
	end
	for _, side in SIDES do
		block(model, Vector3.new(body.X * 0.7, 0.1 * s, body.Z * 0.18),
			at(side * (body.X / 2 + body.X * 0.3), bodyY - body.Y * 0.25, -body.Z * 0.15) * CFrame.Angles(0, 0, side * 0.3), c)
		local eye = block(model, Vector3.new(0.06 * s, 0.2 * s, 0.2 * s), at(side * (body.X / 2 + 0.02), bodyY + body.Y * 0.1, -body.Z * 0.35), EYE_COLOR)
		eye.Name = "Eye"
		eye:SetAttribute("Eye", true)
	end
	return main
end

local function buildSnake(model, p, s)
	local seg = 0.55 * s
	local main
	for i = 7, 1, -1 do
		local k = 1 - i * 0.06
		local x = math.sin(i * 0.9) * seg * 0.5
		local part = block(model, Vector3.new(seg * k, seg * 0.8 * k, seg * 1.1), at(x, seg * 0.4 * k, (i - 3) * seg), i % 2 == 0 and (p.color2 or p.color) or p.color)
		if i == 3 then
			main = part
			part.Name = "Body"
		end
	end
	local hz = -3 * seg - seg * 0.3
	local head = block(model, Vector3.new(seg * 1.3, seg * 0.9, seg * 1.3), at(0, seg * 0.5, hz), p.color)
	head.Name = "Head"
	block(model, Vector3.new(seg * 0.12, seg * 0.05, seg * 0.5), at(0, seg * 0.3, hz - seg * 0.8), Color3.fromRGB(220, 40, 60))
	eyes(model, seg * 0.22, seg * 0.35, seg * 0.7, hz - seg * 0.66)
	return main
end

-- половина размера детали по осям мира (рамка повёрнутой детали)
local function halfExtents(part)
	local cf, s = part.CFrame, part.Size / 2
	local function axis(c)
		return math.abs(cf.XVector[c]) * s.X + math.abs(cf.YVector[c]) * s.Y + math.abs(cf.ZVector[c]) * s.Z
	end
	return Vector3.new(axis("X"), axis("Y"), axis("Z"))
end

-- мульт-модели из Blender (ReplicatedStorage.ToonAnimals, импорт через Import 3D):
-- Body - меш с текстурой, Outline - вывернутая раздутая копия, которая видна только по краю (контур);
-- оба привязаны к костям (Bone) внутри невидимой RootPart, кости двигает AnimalModel.Pose
local function buildToon(model, p)
	local folder = ReplicatedStorage:FindFirstChild("ToonAnimals")
	local template = folder and folder:FindFirstChild(p.mesh)
	local templateBody = template and template:FindFirstChild("Body", true)
	if not templateBody then
		return nil
	end
	local copy = template:Clone()
	local body = copy:FindFirstChild("Body", true)
	copy:ScaleTo(p.height / (halfExtents(body).Y * 2))
	-- низ тела на y = 0, центр по x и z в нуле; мордой модель уже смотрит в -Z
	local half = halfExtents(body)
	local shift = Vector3.new(body.Position.X, body.Position.Y - half.Y, body.Position.Z)
	for _, part in copy:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame -= shift
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Parent = model
		end
	end
	copy:Destroy()
	local outline = model:FindFirstChild("Outline")
	if outline then
		outline:SetAttribute("Outline", true)
		if p.outline then
			outline.Color = p.outline
		end
	end
	model:SetAttribute("Toon", true)
	return model:FindFirstChild("Body")
end

-- ---------------------------------------------------------------- анимация костей мульт-моделей
-- Движения задаются в осях модели (X вправо, Y вверх, Z назад; морда к -Z) и переводятся в оси кости
-- по её положению в покое, поэтому не важно, как импорт развернул кости. Какая кость как двигается -
-- по имени (см. animal_concepts/styles/rigs.py): Body, Neck, Head, Ear*/Tuft*, Tail1..N,
-- LegFL/FR/BL/BR (четвероногие), Arm* (передние лапы сидящих), Hand* (держат еду), Foot*, Wing*.
local rigCache = setmetatable({}, { __mode = "k" })

local function rigOf(model)
	local rig = rigCache[model]
	if rig == nil then
		rig = false
		local root = model:FindFirstChild("RootPart")
		if root and model:GetAttribute("Toon") then
			local bones = {}
			for _, bone in root:GetDescendants() do
				if bone:IsA("Bone") then
					bone.Transform = CFrame.identity
				end
			end
			local pivot = model:GetPivot():Inverse()
			for _, bone in root:GetDescendants() do
				if bone:IsA("Bone") then
					local rest = pivot * bone.WorldCFrame
					local name = bone.Name
					local kind = string.match(name, "^(%a-)[LR%d]*$") or name
					if string.match(name, "^Leg") then
						kind = "Leg"
					end
					table.insert(bones, {
						bone = bone,
						kind = kind,
						rot = rest.Rotation,
						side = rest.Position.X >= 0 and 1 or -1,
						front = string.sub(name, 4, 4) == "F",
						index = tonumber(string.match(name, "%d+$")) or 1,
					})
				end
			end
			rig = { bones = bones }
		end
		rigCache[model] = rig
	end
	return rig or nil
end

local X, Y, Z = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis

-- поворот кости вокруг осей модели (радианы) и сдвиг в осях модели
local function setBone(e, ax, ay, az, offset)
	local r = e.rot
	local cf = CFrame.identity
	if ax ~= 0 then
		cf *= CFrame.fromAxisAngle(r:VectorToObjectSpace(X), ax)
	end
	if ay ~= 0 then
		cf *= CFrame.fromAxisAngle(r:VectorToObjectSpace(Y), ay)
	end
	if az ~= 0 then
		cf *= CFrame.fromAxisAngle(r:VectorToObjectSpace(Z), az)
	end
	if offset then
		cf = CFrame.new(r:VectorToObjectSpace(offset)) * cf
	end
	e.bone.Transform = cf
end

-- step - фаза шага (идет), mode - "eat" (ест, кивает головой), "happy" (радуется) или nil (покой)
local function animateRig(rig, step, t, mode)
	local walking = step ~= nil
	local s = step or 0
	local eat, happy = mode == "eat", mode == "happy"
	local chew = math.abs(math.sin(t * 11))
	-- иногда животное поворачивает голову и дергает ухом
	local look = math.sin(t * 0.55) * 0.35 + math.sin(t * 1.3) * 0.08
	local twitch = math.max(0, math.sin(t * 0.9) - 0.93) * 6
	for _, e in rig.bones do
		local ax, ay, az, offset = 0, 0, 0, nil
		local kind = e.kind
		if kind == "Body" then
			if walking then
				ax, az = math.sin(s * 2) * 0.04, math.sin(s) * 0.07
			elseif eat then
				ax = -0.14 - chew * 0.04
			elseif happy then
				az = math.sin(t * 9) * 0.09
			else
				ax = math.sin(t * 2.2) * 0.025 -- дыхание
			end
		elseif kind == "Neck" then
			if eat then
				ax = -0.55 - chew * 0.12
			elseif walking then
				ax = math.sin(s * 2) * 0.06
			elseif happy then
				ax = 0.15
			else
				ax = math.sin(t * 0.8) * 0.05
			end
		elseif kind == "Head" then
			if eat then
				ax = -0.3 - chew * 0.22
			elseif happy then
				ax, az = 0.12, math.sin(t * 9 + 1) * 0.18
			elseif walking then
				ax, az = -math.sin(s * 2) * 0.06, -math.sin(s) * 0.06
			else
				ay, az = look, math.sin(t * 0.45) * 0.08
			end
		elseif kind == "Ear" or kind == "Tuft" then
			if walking then
				ax = 0.12 + math.abs(math.sin(s)) * 0.3
			elseif happy then
				ax = -0.2 + math.sin(t * 9) * 0.1
			elseif eat then
				ax = 0.25
			else
				ax = math.sin(t * 1.7 + e.side) * 0.05 + twitch * 0.4
			end
			az = -e.side * (walking and math.abs(math.sin(s)) * 0.1 or 0)
		elseif kind == "Tail" then
			local speed = walking and 8 or happy and 15 or 2.4
			local amp = walking and 0.32 or happy and 0.5 or 0.16
			ay = math.sin(t * speed - e.index * 0.7) * amp
			ax = happy and -0.12 or 0
		elseif kind == "Leg" then
			local phase = ((e.front and e.side > 0) or (not e.front and e.side < 0)) and 0 or math.pi
			if walking then
				ax = math.sin(s + phase) * 0.6
			elseif happy then
				ax = math.sin(t * 9 + phase) * 0.25
			elseif eat and e.front then
				ax = 0.08
			end
		elseif kind == "Arm" then
			local phase = e.side > 0 and 0 or math.pi
			if walking then
				ax = math.sin(s + phase) * 0.55
			elseif happy then
				ax = 0.6 + math.sin(t * 9 + phase) * 0.35
			elseif eat then
				ax = 0.35 + chew * 0.1
			end
		elseif kind == "Hand" then
			if walking then
				ax = math.sin(s * 2) * 0.2
			elseif happy then
				ax = 0.45 + math.sin(t * 9) * 0.25
			elseif eat then
				ax = 0.55 + chew * 0.2
			else
				ax = math.sin(t * 2.2) * 0.05
			end
		elseif kind == "Foot" then
			local phase = e.side > 0 and math.pi or 0
			if walking then
				ax = math.sin(s + phase) * 0.45
			elseif happy then
				ax = math.sin(t * 9 + phase) * 0.2
			end
		elseif kind == "Wing" then
			local flap
			if walking then
				flap = 0.15 + math.abs(math.sin(s * 2)) * 0.3
			elseif happy then
				flap = 0.5 + math.sin(t * 18) * 0.45
			else
				flap = math.sin(t * 2.2) * 0.04
			end
			az = e.side * flap
		end
		setBone(e, ax, ay, az, offset)
	end
end

-- есть ли у модели кости (мульт-модель со скелетом)
function AnimalModel.IsRigged(model)
	return rigOf(model) ~= nil
end

local BUILDERS = {
	quad = buildQuad,
	bird = buildBird,
	crab = buildCrab,
	blob = buildBlob,
	fin = buildFin,
	snake = buildSnake,
}

local function forEachPart(model, callback)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part:GetAttribute("Eye") and not part:GetAttribute("Outline") then
			callback(part)
		end
	end
end

-- раскраска радужных животных, клиент вызывает это каждый кадр
function AnimalModel.PaintRainbow(model, t)
	local i = 0
	forEachPart(model, function(part)
		i += 1
		part.Color = Color3.fromHSV((t * 0.3 + i * 0.07) % 1, 0.65, 1)
	end)
end

-- animal = { id, m, g } как в данных игрока
function AnimalModel.Build(animal)
	local species = Animals.ById[animal.id]
	local p = species.model
	local s = p.size or 1

	local model = Instance.new("Model")
	model.Name = species.name
	-- мульт-меш, если он есть в плейсе; иначе обычная модель из блоков
	local main = p.mesh and buildToon(model, p)
	if not main then
		main = BUILDERS[p.kind](model, p, s)
	end
	model.PrimaryPart = main
	-- у меша окрас в текстуре: золото и радуга красят деталь целиком, текстуру убираем
	if model:GetAttribute("Toon") and (animal.m == "Gold" or animal.m == "Rainbow") then
		forEachPart(model, function(part)
			if part:IsA("MeshPart") then
				part.TextureID = ""
			end
		end)
	end

	if p.ghost then
		forEachPart(model, function(part)
			part.Transparency = 0.35
			part.Material = Enum.Material.Glass
		end)
	end
	if p.glow then
		local light = Instance.new("PointLight")
		light.Color = p.color2 or p.color
		light.Brightness = 2
		light.Range = 8 + 4 * s
		light.Parent = main
		for _, part in model:GetDescendants() do
			if part:GetAttribute("Eye") then
				part.Color = Color3.fromRGB(120, 230, 255)
				part.Material = Enum.Material.Neon
			end
		end
		-- у мульт-модели вокруг летают искорки
		if model:GetAttribute("Toon") then
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkles.Color = ColorSequence.new(p.color2 or p.color, Color3.new(1, 1, 1))
			sparkles.LightEmission = 1
			sparkles.Rate = 7
			sparkles.Lifetime = NumberRange.new(1, 1.8)
			sparkles.Speed = NumberRange.new(0.3, 0.8)
			sparkles.SpreadAngle = Vector2.new(180, 180)
			sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
			sparkles.Parent = main
		end
	end

	if animal.m == "Gold" then
		forEachPart(model, function(part)
			part.Color = Mutations.Gold.color
			part.Material = Enum.Material.Foil
		end)
	elseif animal.m == "Rainbow" then
		model:SetAttribute("Rainbow", true)
		AnimalModel.PaintRainbow(model, 0)
	end

	-- при заданном PrimaryPart WorldPivot игнорируется, поэтому пивот (точка под ногами)
	-- задается через PivotOffset главной детали, иначе модель стоит по пояс в земле
	main.PivotOffset = main.CFrame:Inverse()
	if animal.g then
		model:ScaleTo(Mutations.Giant.scale)
	end
	return model
end

local legCache = setmetatable({}, { __mode = "k" })

-- положение ног и хвоста в покое относительно пивота, считается один раз на модель.
-- Хвост качается вокруг конца, которым крепится к телу (по атрибуту Tail: ось z или y)
local function legsOf(model)
	local cached = legCache[model]
	if not cached then
		local legs, tails = {}, {}
		local pivot = model:GetPivot()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local phase = part:GetAttribute("Leg")
				local tailAxis = part:GetAttribute("Tail")
				if phase then
					local length = part.Size.Y
					table.insert(legs, {
						part = part,
						phase = phase,
						length = length,
						hip = pivot:ToObjectSpace(part.CFrame) * CFrame.new(0, length / 2, 0),
					})
				elseif tailAxis then
					local offset = tailAxis == "y" and CFrame.new(0, -part.Size.Y / 2, 0) or CFrame.new(0, 0, -part.Size.Z / 2)
					table.insert(tails, {
						part = part,
						hinge = pivot:ToObjectSpace(part.CFrame * offset),
						rest = offset:Inverse(),
					})
				end
			end
		end
		cached = { legs, tails }
		legCache[model] = cached
	end
	return cached[1], cached[2]
end

-- поставить животное в cframe; step - фаза шага, nil - стоит на месте
-- t - время для виляния хвостом и покоя (nil - хвост не трогаем)
-- mode - для мульт-моделей со скелетом: "eat" (ест), "happy" (радуется), nil (идет или стоит)
function AnimalModel.Pose(model, cframe, step, t, mode)
	local rig = rigOf(model)
	if rig then
		model:PivotTo(cframe)
		animateRig(rig, step, t or os.clock(), mode)
		return
	end
	local legs, tails = legsOf(model)
	-- у мульт-меша без костей нет отдельных ног: на ходу он подпрыгивает и переваливается
	if step and model:GetAttribute("Toon") then
		cframe *= CFrame.new(0, math.abs(math.sin(step)) * 0.12, 0) * CFrame.Angles(0, 0, math.sin(step) * 0.09)
	end
	model:PivotTo(cframe)
	for _, leg in legs do
		local swing = step and math.sin(step + leg.phase) * 0.55 or 0
		leg.part.CFrame = cframe * leg.hip * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -leg.length / 2, 0)
	end
	if t then
		local wag = math.sin(t * (step and 14 or 6)) * 0.4
		for _, tail in tails do
			tail.part.CFrame = cframe * tail.hinge * CFrame.Angles(0, wag, 0) * tail.rest
		end
	end
end

-- примерный рост модели, чтобы вешать над ней табличку
function AnimalModel.Height(model)
	local _, size = model:GetBoundingBox()
	return size.Y
end

return AnimalModel
