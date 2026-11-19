local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local AnimalModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimalModel"))
local Game = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Game"))
local Formula = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Formula"))
local UI = require(script.Parent.UI)
local Rig = require(script.Parent.Rig)

-- животные гуляют по вольерам, радуга, турники, пульсация зоны броска
local WorldFx = {}

local PAD_PULSE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local ANIMATE_DISTANCE = 150
local WALK_SPEED = 3
local PEN_MARGIN = 3
local PULL_HEIGHT = 1.8

local walkers = {} -- [model] = { pos, look, target, waitUntil, phase }

local function track(farm)
	local function add(object)
		if object:IsA("Model") and object.Parent and object.Parent.Parent == farm then
			walkers[object] = false -- состояние заведем, когда придут атрибуты
		end
	end
	farm.DescendantAdded:Connect(add)
	farm.DescendantRemoving:Connect(function(object)
		walkers[object] = nil
	end)
	for _, object in farm:GetDescendants() do
		add(object)
	end
end

-- каждое животное ходит к случайной точке вольера, стоит, идет дальше.
-- Это только на клиенте, сервер хранит лишь место, куда животное поставили
local function walk(dt)
	local t = os.clock()
	local cameraPosition = camera.CFrame.Position
	for model, s in walkers do
		if not s then
			local home = model:GetAttribute("Home")
			if not home then
				continue
			end
			s = { pos = home.Position, look = home.LookVector, waitUntil = t + math.random() * 3, phase = math.random() * 10 }
			walkers[model] = s
		end
		if (s.pos - cameraPosition).Magnitude > ANIMATE_DISTANCE then
			continue
		end

		local hop, step = 0, nil
		if s.target then
			local delta = s.target - s.pos
			local distance = delta.Magnitude
			if distance < 0.3 then
				s.target = nil
				s.waitUntil = t + 1.5 + math.random() * 3
				-- постояв, животное то просто смотрит по сторонам, то щиплет траву, то радостно прыгает
				local roll = math.random()
				s.mode = roll < 0.3 and "eat" or roll < 0.45 and "happy" or nil
			else
				s.mode = nil
				local direction = delta / distance
				s.pos += direction * math.min(distance, WALK_SPEED * dt)
				s.look = direction
				step = t * 9 + s.phase
				hop = math.abs(math.sin(step)) * 0.12
			end
		elseif t > s.waitUntil then
			local center = model:GetAttribute("PenCenter")
			local half = model:GetAttribute("PenHalf")
			if center and half then
				local r = half - PEN_MARGIN
				s.target = Vector3.new(center.X + (math.random() * 2 - 1) * r, s.pos.Y, center.Z + (math.random() * 2 - 1) * r)
			end
		end

		if s.mode == "happy" and not step then
			hop = math.abs(math.sin((t + s.phase) * 7)) * 0.35
		end
		AnimalModel.Pose(model, CFrame.lookAt(s.pos, s.pos + s.look) + Vector3.new(0, hop, 0), step, t + s.phase, s.mode)
		if model:GetAttribute("Rainbow") then
			AnimalModel.PaintRainbow(model, t)
		end
	end
end

-- игроки на турнике: сервер ставит атрибут Hang, а движение рисует каждый клиент сам,
-- так подтягивания плавные. Руки и ноги R15 гнет тоже клиент: в висе руки почти прямые,
-- при подъеме локти уходят в стороны, кисти остаются на перекладине, тело поднимается к ней
local hangs = setmetatable({}, { __mode = "k" }) -- [character] = поза: откуда начали, суставы, размеры

-- кисти на перекладине шире плеч, перекладина перед грудью: тело висит за ней и не проходит насквозь
local GRIP_OUT = 0.6 -- насколько каждая кисть дальше плеча в сторону: хват на ширине плеч, руки почти отвесно
local BAR_AHEAD = 0.8 -- насколько перекладина впереди плеч: тело висит под ней, но голова не задевает
local REST_STRAIGHT = 0.97 -- в висе рука почти прямая
local PULL_TOP = 0.2 -- в верхней точке кисти выше плеч на столько, подбородок над перекладиной
local GRIP_DROP = 0 -- середина кисти ровно на оси перекладины: кулак обхватывает трубу
local HANG_JOINTS = {
	"RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist",
	"RightHip", "LeftHip", "RightKnee", "LeftKnee",
}
local DOWN = Vector3.new(0, -1, 0)
local FORWARD = Vector3.new(0, 0, -1) -- вперед в осях корня и любой детали в покое
-- локоть при подъеме смотрит вниз, чуть в сторону и назад, как у человека на турнике
local ELBOW_POLE = Vector3.new(0.6, -1, 0.35)

-- часть вектора поперек оси (единичная) или nil, если вектор почти вдоль оси
local function across(v, axis)
	local flat = v - axis * v:Dot(axis)
	return flat.Magnitude > 1e-3 and flat.Unit or nil
end

-- угол поворота вокруг axis, который переводит from в to (оба поперек оси)
local function angleAround(from, to, axis)
	return math.atan2(axis:Dot(from:Cross(to)), from:Dot(to))
end

-- докрутить rotation вокруг оси axis так, чтобы вектор have (уже после rotation) смотрел как want
local function twistToward(rotation, have, want, axis)
	local a, b = across(have, axis), across(want, axis)
	if not (a and b) then
		return rotation
	end
	return CFrame.fromAxisAngle(axis, angleAround(a, b, axis)) * rotation
end

local function smooth(k)
	return k * k * (3 - 2 * k)
end

-- одно подтягивание: быстро вверх, короткая задержка у перекладины, плавно вниз
local function pullCurve(t)
	if t < 0.4 then
		return smooth(t / 0.4)
	elseif t < 0.5 then
		return 1
	end
	return 1 - smooth((t - 0.5) / 0.5)
end

-- Хват: середина кисти на оси трубы, ладонь вперед (хват сверху), труба вдоль костяшек проходит
-- через прорезь кулака. Вокруг трубы кисть поворачивается вслед за предплечьем, как у человека,
-- поэтому запястье прямое, без излома. Вбок кисть наклоняется за предплечьем только наполовину:
-- так она не ломается в запястье и труба не выходит из прорези
local WRIST_EXTEND = 0.1 -- пальцы чуть дальше предплечья через верх трубы
local LATERAL_FOLLOW = 0.5 -- какую долю бокового наклона предплечья повторяет кисть

-- поворот кисти в осях корня. В покое у кисти пальцы вниз (-Y), ладонь к бедру (-X у правой).
-- tilt - насколько пальцы наклонены вперед от вертикали, lean - наклон вбок (к +X)
local function handRotation(side, tilt, lean)
	local fingers = Vector3.new(0, math.cos(tilt), -math.sin(tilt))
	local palm = Vector3.new(0, -math.sin(tilt), -math.cos(tilt))
	local x, y = palm * -side, -fingers
	return CFrame.fromAxisAngle(palm, lean) * CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

-- кисть, которая продолжает предплечье (fore - от локтя к запястью, в осях корня)
local function handAlong(side, fore)
	local tilt = math.atan2(-fore.Z, fore.Y) + WRIST_EXTEND
	local lean = LATERAL_FOLLOW * math.asin(math.clamp(fore.X, -1, 1))
	return handRotation(side, tilt, lean)
end

-- Рука по настоящим точкам суставов персонажа: плечо-локоть (upper) и локоть-запястье (lower)
-- в осях своих суставов. В покое у аватаров эти отрезки не строго вертикальны (точки суставов
-- сдвинуты вбок и вперед), поэтому повороты считаются от них. Без суставов R15 руку не гнем
local function armRig(character, name)
	local shoulderBase, shoulderChild = Rig.Frames(character, name .. "Shoulder")
	local elbowBase, elbowChild = Rig.Frames(character, name .. "Elbow")
	local wristBase, wristChild = Rig.Frames(character, name .. "Wrist")
	if not (shoulderBase and elbowBase and wristBase) then
		return nil
	end
	local side = name == "Right" and 1 or -1
	return {
		side = side,
		restUpper = shoulderChild:VectorToObjectSpace(elbowBase.Position - shoulderChild.Position),
		restLower = elbowChild:VectorToObjectSpace(wristBase.Position - elbowChild.Position),
		shoulderBase = shoulderBase, shoulderChild = shoulderChild,
		elbowBase = elbowBase, elbowChild = elbowChild,
		wristBase = wristBase, wristChild = wristChild,
		-- перед плеча (бицепс): к нему сгибается локоть
		upperFront = shoulderChild:VectorToObjectSpace(FORWARD),
		-- сторона ладони у предплечья: предплечье докручивается вслед за кистью, запястье не ломается
		lowerPalm = elbowChild:VectorToObjectSpace(Vector3.new(-side, 0, 0)),
	}
end

-- верх туловища в осях корня по суставам Root и Waist в покое (анимации на это не влияют)
local function restTorso(character, root)
	local rootBase, rootChild = Rig.Frames(character, "Root")
	local waistBase, waistChild = Rig.Frames(character, "Waist")
	if rootBase and waistBase then
		return rootBase * rootChild:Inverse() * waistBase * waistChild:Inverse()
	end
	local torso = character:FindFirstChild("UpperTorso")
	return torso and root.CFrame:ToObjectSpace(torso.CFrame) or CFrame.new(0, 0.5, 0)
end

local function startPose(character, root)
	local pose = { from = root.CFrame, joints = Rig.Joints(character, HANG_JOINTS) }
	local torso = restTorso(character, root)
	pose.torso = torso.Rotation
	pose.arms = { Right = armRig(character, "Right"), Left = armRig(character, "Left") }
	local right, left = pose.arms.Right, pose.arms.Left
	-- точки плеч в осях корня (X - вправо, Y - вверх, Z - назад)
	pose.right = right and torso * right.shoulderBase.Position or Vector3.new(1, 1.4, 0)
	pose.left = left and torso * left.shoulderBase.Position or Vector3.new(-1, 1.4, 0)
	-- насколько середина кисти выше плеча в висе, когда рука от плеча до запястья почти прямая.
	-- Кисть продолжает прямую руку, а от нее зависит, где запястье, - уточняем несколько раз
	local full = right and (right.restUpper.Magnitude + right.restLower.Magnitude) * REST_STRAIGHT or 2
	pose.rise = math.sqrt(math.max(full ^ 2 - GRIP_OUT ^ 2 - BAR_AHEAD ^ 2, 0.5))
	if right then
		for _ = 1, 4 do
			local fore = Vector3.new(GRIP_OUT, pose.rise, -BAR_AHEAD).Unit
			local toWrist = handAlong(1, fore) * right.wristChild.Position
			local gx, gz = GRIP_OUT + toWrist.X, toWrist.Z - BAR_AHEAD
			pose.rise = math.sqrt(math.max(full ^ 2 - gx ^ 2 - gz ^ 2, 0.5)) - toWrist.Y
		end
	end
	return pose
end

-- локоть по двум длинам: смотрит вниз и чуть в сторону-назад. Возвращает локоть и куда дотянулась рука
local function placeElbow(arm, shoulder, wrist)
	local upper, lower = arm.restUpper.Magnitude, arm.restLower.Magnitude
	local toWrist = wrist - shoulder
	local distance = math.clamp(toWrist.Magnitude, math.abs(upper - lower) + 0.05, upper + lower - 0.01)
	local direction = toWrist.Unit
	local along = (upper ^ 2 - lower ^ 2 + distance ^ 2) / (2 * distance)
	local out = math.sqrt(math.max(upper ^ 2 - along ^ 2, 0))
	local pole = across(ELBOW_POLE * Vector3.new(arm.side, 1, 1), direction) or DOWN
	return shoulder + direction * along + pole * out, shoulder + direction * distance
end

-- Рука от плеча к запястью через локоть: локоть гнется как шарнир (к бицепсу), предплечье
-- докручивается за кистью, запястье ставит кисть в хват, продолжающий предплечье.
-- Точки в осях корня, hand - где середина кисти. Возвращает повороты суставов плеча, локтя и запястья
local function solveArm(pose, arm, shoulder, hand)
	-- поворот кисти зависит от предплечья, а предплечье - от того, где запястье при этом повороте:
	-- пара уточнений от прошлого кадра сходится
	local grip = arm.lastGrip or handAlong(arm.side, (hand - shoulder).Unit)
	for _ = 1, 2 do
		local elbow, reach = placeElbow(arm, shoulder, hand + grip * arm.wristChild.Position)
		grip = handAlong(arm.side, (reach - elbow).Unit)
	end
	arm.lastGrip = grip
	local elbow, reach = placeElbow(arm, shoulder, hand + grip * arm.wristChild.Position)

	-- плечо: отрезок плечо-локоть на нужное направление и докрутка вокруг него, чтобы локоть гнулся вперед
	local shoulderFrame = pose.torso * arm.shoulderBase.Rotation
	local upperDir = shoulderFrame:VectorToObjectSpace((elbow - shoulder).Unit)
	local foreInShoulder = shoulderFrame:VectorToObjectSpace((reach - elbow).Unit)
	local shoulderRotation = CFrame.fromRotationBetweenVectors(arm.restUpper.Unit, upperDir)
	shoulderRotation = twistToward(shoulderRotation, shoulderRotation:VectorToWorldSpace(arm.upperFront), foreInShoulder, upperDir)

	-- локоть: предплечье от локтя к запястью, докрутка вокруг него к ладони кисти
	local elbowFrame = shoulderFrame * shoulderRotation * arm.shoulderChild.Rotation:Inverse() * arm.elbowBase.Rotation
	local foreDir = elbowFrame:VectorToObjectSpace((reach - elbow).Unit)
	local elbowRotation = CFrame.fromRotationBetweenVectors(arm.restLower.Unit, foreDir)
	local palmWanted = elbowFrame:VectorToObjectSpace(grip * Vector3.new(-arm.side, 0, 0))
	elbowRotation = twistToward(elbowRotation, elbowRotation:VectorToWorldSpace(arm.lowerPalm), palmWanted, foreDir)

	-- запястье: кисть ровно в хват
	local wristFrame = elbowFrame * elbowRotation * arm.elbowChild.Rotation:Inverse() * arm.wristBase.Rotation
	local wristRotation = wristFrame:Inverse() * grip * arm.wristChild.Rotation
	return shoulderRotation, elbowRotation, wristRotation
end

-- raise 0..1 - руки от опущенных до хвата (заход на турник), lift - насколько тело поднялось,
-- pull 0..1 - фаза подтягивания (ноги чуть поджимаются)
local function poseLimbs(pose, raise, lift, pull)
	local joints = pose.joints
	-- ось перекладины в осях корня: тело поднялось на lift, значит перекладина ниже на столько же
	local barY = pose.right.Y + pose.rise - lift
	local barZ = pose.right.Z - BAR_AHEAD
	for name, arm in pose.arms do
		local shoulder = name == "Right" and pose.right or pose.left
		local hand = Vector3.new(shoulder.X + arm.side * GRIP_OUT, barY, barZ)
		local shoulderRotation, elbowRotation, wristRotation = solveArm(pose, arm, shoulder, hand)
		Rig.Set(joints, name .. "Shoulder", CFrame.identity:Lerp(shoulderRotation, raise))
		Rig.Set(joints, name .. "Elbow", CFrame.identity:Lerp(elbowRotation, raise))
		Rig.Set(joints, name .. "Wrist", CFrame.identity:Lerp(wristRotation, raise))
	end
	local hip = (0.25 + 0.2 * pull) * raise
	local knee = -(0.7 + 0.3 * pull) * raise
	Rig.Set(joints, "RightHip", CFrame.Angles(hip, 0, 0))
	Rig.Set(joints, "LeftHip", CFrame.Angles(hip * 0.7, 0, 0))
	Rig.Set(joints, "RightKnee", CFrame.Angles(knee, 0, 0))
	Rig.Set(joints, "LeftKnee", CFrame.Angles(knee * 1.2, 0, 0))
end

local function animateHangs()
	local now = workspace:GetServerTimeNow()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local hang = character and character:GetAttribute("Hang")
		local pose = character and hangs[character]
		if hang and root then
			if not pose then
				pose = startPose(character, root)
				hangs[character] = pose
			end
			-- корень ставим так, чтобы в висе ладони были на перекладине, а грудь - за ней
			local baseY = Game.BAR_Y - GRIP_DROP - pose.right.Y - pose.rise
			local hangCFrame = (hang.Rotation + Vector3.new(hang.X, baseY, hang.Z)) * CFrame.new(0, 0, BAR_AHEAD - pose.right.Z)
			local elapsed = now - (character:GetAttribute("HangSince") or now)
			if elapsed < Game.HANG_ENTER then
				local k = smooth(math.max(elapsed, 0) / Game.HANG_ENTER)
				root.CFrame = pose.from:Lerp(hangCFrame, k)
				poseLimbs(pose, k, 0, 0)
			else
				local t = ((elapsed - Game.HANG_ENTER) / Game.REP_TIME) % 1
				local pull = pullCurve(t)
				local lift = pull * math.min(PULL_HEIGHT, pose.rise - PULL_TOP)
				root.CFrame = hangCFrame + Vector3.new(0, lift, 0)
				poseLimbs(pose, 1, lift, pull)
			end
		elseif pose then
			Rig.Reset(pose.joints)
			hangs[character] = nil
		end
	end
end

-- круги у ларьков: встал - панель открылась, сошел - закрылась
local shopPads = {}
local standingOn

local function checkShopPads()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local current
	if root then
		for _, pad in shopPads do
			local offset = root.Position - pad.Position
			if Vector2.new(offset.X, offset.Z).Magnitude < pad:GetAttribute("Radius") and offset.Y < 8 then
				current = pad
				break
			end
		end
	end
	if current == standingOn then
		return
	end
	if standingOn and UI.OpenedPanel() == standingOn:GetAttribute("Opens") then
		UI.ClosePanel()
	end
	standingOn = current
	if current then
		UI.OpenPanel(current:GetAttribute("Opens"))
	end
end

local function isMine(plot)
	return plot.Name == "Plot" .. tostring(player:GetAttribute("Plot"))
end

-- Личное у вольера (свой Food Shop и круг улучшения турника, папка OwnerOnly) видно только хозяину:
-- у чужих вольеров детали прозрачные, надписи и свет выключены. Это только на этом клиенте
local hiddenTransparency = {} -- [деталь] = прозрачность, которая была до скрытия

local function showOwnerPart(object, visible)
	if object:IsA("BasePart") then
		if visible and hiddenTransparency[object] then
			object.Transparency = hiddenTransparency[object]
			hiddenTransparency[object] = nil
		elseif not visible and not hiddenTransparency[object] then
			hiddenTransparency[object] = object.Transparency
			object.Transparency = 1
		end
	elseif object:IsA("BillboardGui") or object:IsA("Light") or object:IsA("ParticleEmitter") then
		object.Enabled = visible
	end
end

local function ownerFolderOf(object)
	local ownerOnly = object:FindFirstAncestor("OwnerOnly")
	return ownerOnly, ownerOnly and ownerOnly.Parent
end

-- табличку расширения вольера может нажать только хозяин, круги магазинов работают только свои
local function updateOwnerStuff(map, plots)
	table.clear(shopPads)
	for _, object in map:WaitForChild("Hub"):GetDescendants() do
		if object:GetAttribute("Opens") then
			table.insert(shopPads, object)
		end
	end
	for _, plot in plots:GetChildren() do
		local mine = isMine(plot)
		for _, object in plot:GetDescendants() do
			if object:IsA("ProximityPrompt") then
				object.Enabled = mine
			end
		end
		local ownerOnly = plot:FindFirstChild("OwnerOnly")
		if ownerOnly then
			for _, object in ownerOnly:GetDescendants() do
				showOwnerPart(object, mine)
				if mine and object:GetAttribute("Opens") then
					table.insert(shopPads, object)
				end
			end
		end
	end
end

-- Игрок в зоне броска пропадает для остальных: в зоне каждый видит только себя и свой бросок.
-- Прячем только на этом клиенте (LocalTransparencyModifier) и убираем ник над головой;
-- вышел из зоны - снова виден
local hiddenThrowers = {} -- [персонаж] = { humanoid, display, added }

local function fade(object, hidden)
	if object:IsA("BasePart") or object:IsA("Decal") then
		object.LocalTransparencyModifier = hidden and 1 or 0
	end
end

local function showThrower(character, state)
	state.added:Disconnect()
	for _, object in character:GetDescendants() do
		fade(object, false)
	end
	if state.humanoid then
		state.humanoid.DisplayDistanceType = state.display
	end
	hiddenThrowers[character] = nil
end

local function hideThrower(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local state = { humanoid = humanoid, display = humanoid and humanoid.DisplayDistanceType }
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, object in character:GetDescendants() do
		fade(object, true)
	end
	-- аксессуары и прочее, что доедет к персонажу, пока он в зоне
	state.added = character.DescendantAdded:Connect(function(object)
		fade(object, true)
	end)
	hiddenThrowers[character] = state
end

local function updateThrowers()
	for _, other in Players:GetPlayers() do
		local character = other ~= player and other.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			local inZone = root ~= nil and Formula.IsOnThrowPad(root.Position)
			local state = hiddenThrowers[character]
			if inZone and not state then
				hideThrower(character)
			elseif state and not inZone then
				showThrower(character, state)
			end
		end
	end
	-- персонаж пропал (вышел из игры, возродился) - забываем
	for character, state in hiddenThrowers do
		if not character.Parent then
			state.added:Disconnect()
			hiddenThrowers[character] = nil
		end
	end
end

-- Подписи над животными (имя и доход): когда их много, они налезали друг на друга.
-- Раз в 0.15 с показываем только те, что не перекрывают уже показанные ближние к камере
local TAG_GAP = 4 -- запас в пикселях между подписями
local tagClock = 0

local function declutterTags(dt)
	tagClock += dt
	if tagClock < 0.15 then
		return
	end
	tagClock = 0
	local farm = workspace:FindFirstChild("Farm")
	if not farm then
		return
	end
	local camPos = camera.CFrame.Position
	local right, up = camera.CFrame.RightVector, camera.CFrame.UpVector
	local tags = {}
	for model in walkers do
		local tag = model.Parent and model:FindFirstChild("Tag")
		local adornee = tag and tag.Adornee
		if adornee then
			local center = adornee.Position + tag.StudsOffsetWorldSpace
			local p, onScreen = camera:WorldToViewportPoint(center)
			if onScreen and p.Z > 0 then
				-- размер подписи в пикселях: она задана в студах (7 x 2.2)
				local size = tag.Size
				local px = camera:WorldToViewportPoint(center + right * size.X.Scale / 2)
				local py = camera:WorldToViewportPoint(center + up * size.Y.Scale / 2)
				local hw, hh = math.abs(px.X - p.X), math.abs(py.Y - p.Y)
				table.insert(tags, { tag = tag, x = p.X, y = p.Y, hw = hw, hh = hh, d = (center - camPos).Magnitude })
			else
				tag.Enabled = true -- за экраном движок и так не рисует
			end
		end
	end
	table.sort(tags, function(a, b)
		return a.d < b.d
	end)
	local shown = {}
	for _, t in tags do
		local free = true
		for _, o in shown do
			if math.abs(t.x - o.x) < t.hw + o.hw + TAG_GAP and math.abs(t.y - o.y) < t.hh + o.hh + TAG_GAP then
				free = false
				break
			end
		end
		t.tag.Enabled = free
		if free then
			table.insert(shown, t)
		end
	end
end

function WorldFx.Init()
	task.spawn(function()
		track(workspace:WaitForChild("Farm"))
	end)
	RunService.Heartbeat:Connect(declutterTags)
	RunService.Heartbeat:Connect(updateThrowers)
	RunService.RenderStepped:Connect(walk)

	task.spawn(function()
		-- пунктир у зоны броска мягко дышит: каждый штрих тускнеет и снова разгорается
		local line = workspace:WaitForChild("Map"):WaitForChild("Base"):WaitForChild("ThrowLine")
		local function pulse(dash)
			if dash:IsA("BasePart") then
				TweenService:Create(dash, PAD_PULSE, { Transparency = math.min(dash.Transparency + 0.35, 1) }):Play()
			end
		end
		for _, dash in line:GetChildren() do
			pulse(dash)
		end
		line.ChildAdded:Connect(pulse)
	end)

	-- поза турника ставится до физики: суставы и кисти сходятся в том же кадре, без отставания и дрожи
	RunService.Stepped:Connect(animateHangs)

	-- надписи на табличках карты (TextScaled) иногда считаются до загрузки шрифта и остаются пустыми:
	-- через пару секунд после загрузки карты переставляем их текст, и размер пересчитывается
	task.spawn(function()
		local map = workspace:WaitForChild("Map")
		task.wait(3)
		local texts = {}
		for _, label in map:GetDescendants() do
			if label:IsA("TextLabel") and label.TextScaled and label.Text ~= "" then
				texts[label] = label.Text
				label.Text = ""
			end
		end
		task.wait()
		for label, text in texts do
			if label.Text == "" then
				label.Text = text
			end
		end
	end)

	task.spawn(function()
		local map = workspace:WaitForChild("Map")
		local plots = map:WaitForChild("Plots")
		updateOwnerStuff(map, plots)
		RunService.Heartbeat:Connect(checkShopPads)
		player:GetAttributeChangedSignal("Plot"):Connect(function()
			updateOwnerStuff(map, plots)
		end)
		-- детали карты могут доехать до клиента позже этого скрипта
		plots.DescendantAdded:Connect(function(object)
			local ownerOnly, plot = ownerFolderOf(object)
			if ownerOnly and plot then
				showOwnerPart(object, isMine(plot))
				if object:GetAttribute("Opens") and isMine(plot) then
					table.insert(shopPads, object)
				end
			end
		end)
	end)
end

return WorldFx
