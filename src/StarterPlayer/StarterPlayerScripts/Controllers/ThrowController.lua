local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Formula = require(Shared:WaitForChild("Formula"))
local Format = require(Shared:WaitForChild("Format"))
local AnimalModel = require(Shared:WaitForChild("AnimalModel"))
local FoodModel = require(Shared:WaitForChild("FoodModel"))
local Game = require(Config:WaitForChild("Game"))
local Foods = require(Config:WaitForChild("Foods"))
local Animals = require(Config:WaitForChild("Animals"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Rig = require(script.Parent.Rig)

local throwRemote = Net.Event("Throw")
local resultRemote = Net.Event("ThrowResult")

local METER_HALF_PERIOD = 0.75 -- бегунок идет от края до края за это время
local RUN_TIME = 1.8
local EAT_TIME = 1.2
-- камера в полете: позади еды и чуть выше, смотрит вперед вдоль каньона
local FLIGHT_CAMERA = Vector3.new(-11, 5, 0)
local FLIGHT_LOOK = Vector3.new(10, -2, 0)
-- бросок: камера на три четверти сзади, персонаж в кадре целиком, облетает его вместе
-- с разворотом (в осях тела, Z - назад)
local SPIN_CAMERA = CFrame.new(3.2, 2.4, 8.5)
local SPIN_LOOK = Vector3.new(0, 0.2, -4)
local EDGE_X = Game.THROW_PAD.x + Game.THROW_PAD.halfX + 2 -- до этого X под камерой земля базы, дальше каньон
local THROW_WATCH = 0.12 -- после броска камера еще миг за спиной, потом летит за едой
local ZONE_CAMERA = Vector3.new(-10, 4.5, 3.5) -- от персонажа в зоне броска
local ZONE_CAMERA_TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local PAD_TOP = 0.08 -- верх плиток зоны броска (они вровень с полом)

local ThrowController = {}

-- шкала включается сама, когда игрок стоит в зоне броска и может кидать;
-- бегунок ходит туда-сюда, клик бросает с текущим значением
local armed = false
local armedSince = 0
local busyUntil = 0
local onPad = false
local followTarget
local cameraOffset = FLIGHT_CAMERA
local lookOffset = Vector3.zero
local followSharpness = 5 -- как быстро камера догоняет цель
local followCFrame -- камера целиком (позиция и взгляд), например за спиной крутящегося персонажа
local flightSway = false -- легкое покачивание камеры, пока еда летит
local fxFolder
local throwSign
local locked -- игрок стоит в центре зоны и не может ходить: { humanoid, walkSpeed }
local zoneCamera -- твин камеры на ракурс броска
local defaultFov = camera.FieldOfView
local lastThrowAt = -math.huge
local povCFrame -- камера "из глаз" животного, пока оно бежит и ест
local throwToken = 0 -- номер броска: отложенные шаги старого броска не трогают новый
local resultPending = false -- бросок отправлен, ответа сервера еще нет
local myPose -- своя поза броска: запускается сразу по клику, еда вылетает из руки, когда придет ответ сервера

local function meterValue()
	local phase = ((os.clock() - armedSince) / METER_HALF_PERIOD) % 2
	return phase < 1 and phase or 2 - phase
end

-- пока идет показ броска или в руках пойманное животное, кидать нельзя
local function canThrow()
	return onPad and not State.training and State.Ready() and not followTarget and not State.data.Carry and os.clock() >= busyUntil
end

-- ---------- поза броска: замах с едой в руке, рывок вперед, возврат в стойку

-- Бросок как в оригинале: пауза после клика, быстрый разворот спиной к полю, замах в глубоком
-- выпаде с едой в отведенной руке, хлесткий доворот обратно к полю - рука проходит сбоку,
-- над головой и выстреливает вперед, шаг, доводка. Присед и наклон делает сустав корпуса Root.
-- Разворот - поворот самого HumanoidRootPart: суставом больше полуоборота физика срывает тело
-- на 180 градусов. Свой персонаж крутит этот клиент, чужих - их клиенты (поворот реплицируется)
local SPIN_START = 0.62 -- камера начинает облет персонажа
local THROW_RELEASE = 1.56 -- еда вылетает из руки
local TRAIL_FROM, TRAIL_TO = 1.08, 1.66 -- белый след за рукой на развороте
local THROW_JOINTS = {
	"Root", "Waist", "RightShoulder", "RightElbow", "LeftShoulder", "LeftElbow",
	"RightHip", "RightKnee", "LeftHip", "LeftKnee",
}

local PI = math.pi
local function A(x, y, z)
	return CFrame.Angles(x, y or 0, z or 0)
end

-- Ключевые позы. Суставы - повороты в осях сустава (X - вперед/назад, Y - поворот, Z - в стороны),
-- между позами смешиваются целиком. Корпус задан числами: drop - присед, yaw - разворот всего
-- тела (больше полуоборота, поэтому отдельно), lean - наклон (минус - вперед).
-- ease: как идет переход к этой позе - smooth, in (разгон), out (резко и затухая)
local THROW_KEYS = {
	{ time = 0, drop = 0, yaw = 0, lean = 0, joints = {} },
	{ time = 0.45, drop = -0.12, yaw = 0, lean = 0, joints = {
		RightShoulder = A(0.1, 0, 0.25), RightElbow = A(0.4), LeftShoulder = A(0.1, 0, -0.25), LeftElbow = A(0.4),
		Waist = A(-0.05), RightHip = A(0.2), RightKnee = A(-0.4), LeftHip = A(0.2), LeftKnee = A(-0.4),
	} },
	-- развернулся спиной к полю: выпад, левая нога впереди, рука с едой опущена и отведена назад
	{ time = 0.8, drop = -0.32, yaw = PI, lean = -0.25, joints = {
		RightShoulder = A(-0.9, 0, 0.35), RightElbow = A(0.3), LeftShoulder = A(0.9, 0, -0.6), LeftElbow = A(0.5),
		Waist = A(-0.15, -0.5), RightHip = A(-0.5), RightKnee = A(-0.4), LeftHip = A(0.9), LeftKnee = A(-0.9),
	} },
	-- замах: чуть докрутился назад, еще ниже
	{ time = 1.08, drop = -0.36, yaw = PI - 0.25, lean = -0.3, joints = {
		RightShoulder = A(-1.1, 0, 0.45), RightElbow = A(0.35), LeftShoulder = A(1.0, 0, -0.5), LeftElbow = A(0.6),
		Waist = A(-0.2, -0.65), RightHip = A(-0.5), RightKnee = A(-0.4), LeftHip = A(0.9), LeftKnee = A(-0.9),
	} },
	-- разворот к полю с разгоном: рука вытянута в сторону и тянется за телом, плечи отстают от бедер
	{ time = 1.34, ease = "in", drop = -0.3, yaw = 1.45 * PI, lean = -0.2, joints = {
		RightShoulder = A(0, -0.4, 1.5), RightElbow = A(0.15), LeftShoulder = A(0.3, 0, -1.2), LeftElbow = A(0.3),
		Waist = A(-0.2, -0.6), RightHip = A(-0.25), RightKnee = A(-0.5), LeftHip = A(0.55), LeftKnee = A(-0.65),
	} },
	-- рука взведена над головой, левая смотрит на цель
	{ time = 1.48, drop = -0.34, yaw = 1.85 * PI, lean = -0.05, joints = {
		RightShoulder = A(-2.5, 0, 0.35), RightElbow = A(1.2), LeftShoulder = A(1.3, 0, -0.3), LeftElbow = A(0.2),
		Waist = A(0.1, -0.45), RightHip = A(-0.45), RightKnee = A(-0.35), LeftHip = A(0.8), LeftKnee = A(-0.8),
	} },
	-- бросок: рука хлестом вперед, плечи обгоняют бедра, глубокий выпад
	{ time = 1.6, ease = "out", drop = -0.4, yaw = 2 * PI, lean = -0.25, joints = {
		RightShoulder = A(1.45, 0, 0.15), RightElbow = A(0.05), LeftShoulder = A(-0.4, 0, -0.5), LeftElbow = A(0.6),
		Waist = A(-0.45, 0.55), RightHip = A(-0.6), RightKnee = A(-0.3), LeftHip = A(1.0), LeftKnee = A(-1.0),
	} },
	-- доводка: рука уходит вниз через корпус, задняя нога подлетает
	{ time = 1.88, drop = -0.38, yaw = 2 * PI, lean = -0.3, joints = {
		RightShoulder = A(1.1, 0.5, -0.1), RightElbow = A(0.35), LeftShoulder = A(-0.6, 0, -0.6), LeftElbow = A(0.5),
		Waist = A(-0.5, 0.75), RightHip = A(-0.9), RightKnee = A(-0.9), LeftHip = A(0.9), LeftKnee = A(-0.9),
	} },
	{ time = 2.35, drop = 0, yaw = 2 * PI, lean = 0, joints = {} },
}
local THROW_POSE_TIME = THROW_KEYS[#THROW_KEYS].time

local function smooth(k)
	return k * k * (3 - 2 * k)
end

local EASES = {
	smooth = smooth,
	["in"] = function(k)
		return k * k
	end,
	out = function(k)
		return 1 - (1 - k) ^ 3
	end,
}

-- поза в момент t: суставы (CFrame) и корпус
local function throwFrame(t)
	for i = 1, #THROW_KEYS - 1 do
		local a, b = THROW_KEYS[i], THROW_KEYS[i + 1]
		if t <= b.time then
			local k = EASES[b.ease or "smooth"]((t - a.time) / (b.time - a.time))
			local joints = {}
			for _, name in THROW_JOINTS do
				local from = a.joints[name] or CFrame.identity
				local to = b.joints[name] or CFrame.identity
				joints[name] = from:Lerp(to, k)
			end
			return joints, a.drop + (b.drop - a.drop) * k, a.yaw + (b.yaw - a.yaw) * k, a.lean + (b.lean - a.lean) * k
		end
	end
	local last = THROW_KEYS[#THROW_KEYS]
	return {}, last.drop, last.yaw, last.lean
end

-- белый след за рукой, пока персонаж крутится
local function handTrail(hand)
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.35, 0)
	top.Parent = hand
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.35, 0)
	bottom.Parent = hand
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Lifetime = 0.35
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = hand
	return trail, { top, bottom, trail }
end

-- Поза поверх обычных анимаций персонажа, еда в правой руке до момента броска.
-- spinRoot - крутить корень самому (только свой персонаж).
-- Возвращает { releaseAt, yaw, base, release() }: yaw - текущий разворот тела от base (для камеры),
-- release убирает еду из руки и отдает точку, откуда она полетит
local function throwPose(character, foodId, spinRoot)
	local hand = character and character:FindFirstChild("RightHand")
	if not hand then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local base = root and root.CFrame
	if not spinRoot then
		root = nil
	end
	local joints = Rig.Joints(character, THROW_JOINTS)
	local mute = Rig.MuteAnimations(character)
	local trail, trailParts = handTrail(hand)
	local grip = hand:FindFirstChild("RightGripAttachment")
	local held = FoodModel.Build(foodId)
	held:ScaleTo(0.7)
	held.Parent = fxFolder
	local function gripPosition()
		return grip and grip.WorldPosition or hand.Position
	end

	-- для разбора анимации в Studio: workspace:SetAttribute("ThrowSlowmo", 0.25) замедляет позу в 4 раза
	local speed = RunService:IsStudio() and workspace:GetAttribute("ThrowSlowmo") or 1
	local started = os.clock()
	local pose = { releaseAt = started + THROW_RELEASE / speed, yaw = 0, base = base }
	function pose.release()
		local position = gripPosition()
		if held then
			held:Destroy()
			held = nil
		end
		return position
	end
	task.spawn(function()
		while hand.Parent do
			local t = (os.clock() - started) * speed
			if t >= THROW_POSE_TIME then
				break
			end
			mute.update()
			local frame, drop, yaw, lean = throwFrame(t)
			pose.yaw = yaw
			Rig.Set(joints, "Root", CFrame.new(0, drop, 0) * CFrame.Angles(lean, 0, 0))
			if root then
				root.CFrame = base * CFrame.Angles(0, yaw, 0)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			for name, rotation in frame do
				if name ~= "Root" then
					Rig.Set(joints, name, rotation)
				end
			end
			trail.Enabled = t > TRAIL_FROM and t < TRAIL_TO
			if held then
				held:PivotTo(CFrame.new(gripPosition()) * CFrame.Angles(t * 4, 0, 0))
			end
			RunService.RenderStepped:Wait()
		end
		pose.yaw = 0
		Rig.Reset(joints)
		mute.restore()
		if root and root.Parent then
			root.CFrame = base
		end
		for _, item in trailParts do
			item:Destroy()
		end
		-- сервер не принял бросок: еда так и не вылетела
		if held then
			held:Destroy()
		end
	end)
	return pose
end

-- ---------- фиксация в зоне броска: вошел - стоишь в центре лицом к полю, пока не кинешь

-- камера плавно уходит за плечо: персонаж слева, шкала справа, впереди поле
local function tweenToZone(position)
	camera.CameraType = Enum.CameraType.Scriptable
	zoneCamera = TweenService:Create(camera, ZONE_CAMERA_TWEEN, {
		CFrame = CFrame.lookAt(position + ZONE_CAMERA, position + Vector3.new(30, 1, 0)),
	})
	zoneCamera:Play()
end

-- На сервере до 5 игроков, у каждого своя точка на полосе (по номеру вольера, слева направо),
-- чтобы не стоять друг в друге. Крайние точки не у самых гор: камера облета броска туда не влезает
local LANE_STEP = 9

local function laneZ(root)
	local plot = player:GetAttribute("Plot")
	if type(plot) == "number" then
		return math.clamp(plot - 3, -2, 2) * LANE_STEP
	end
	return math.clamp(root.Position.Z, -2 * LANE_STEP, 2 * LANE_STEP)
end

local function lockInZone(character, root, humanoid)
	local pad = Game.THROW_PAD
	local height = humanoid.HipHeight + root.Size.Y / 2 + PAD_TOP
	local z = laneZ(root)
	character:PivotTo(CFrame.lookAt(Vector3.new(pad.x, height, z), Vector3.new(pad.x + 10, height, z)))
	root.AssemblyLinearVelocity = Vector3.zero
	locked = {
		humanoid = humanoid,
		walkSpeed = humanoid.WalkSpeed,
	}
	humanoid.WalkSpeed = 0
	-- силу прыжка не обнуляем: тогда Roblox прячет кнопку прыжка на телефоне, а ей выходят из зоны.
	-- Сам прыжок выключен, нажатие ловит JumpRequest (ниже)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.AutoRotate = false

	if not followTarget then
		tweenToZone(root.Position)
	end
end

-- stepOut: вывести игрока за край зоны, чтобы его сразу не поставило обратно
local function unlock(stepOut)
	if not locked then
		return
	end
	local humanoid = locked.humanoid
	if humanoid.Parent then
		humanoid.WalkSpeed = locked.walkSpeed
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		humanoid.AutoRotate = true
		local root = humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if stepOut and root then
			local pad = Game.THROW_PAD
			local position = Vector3.new(pad.x - pad.halfX - 4, root.Position.Y, root.Position.Z)
			humanoid.Parent:PivotTo(CFrame.lookAt(position, position - Vector3.xAxis))
		end
	end
	locked = nil
	if zoneCamera then
		zoneCamera:Cancel()
		zoneCamera = nil
	end
	if not followTarget then
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- ---------- камера за едой

-- offset и look - от цели в мировых осях (игрок в зоне всегда смотрит вдоль +X)
local function startFollow(getTarget, offset, look, sharpness)
	if zoneCamera then
		zoneCamera:Cancel()
		zoneCamera = nil
	end
	followTarget = getTarget
	followCFrame = nil
	cameraOffset = offset or FLIGHT_CAMERA
	lookOffset = look or FLIGHT_LOOK
	followSharpness = sharpness or 5
	camera.CameraType = Enum.CameraType.Scriptable
end

-- после показа улова игрок все еще в зоне: камера возвращается на ракурс броска
-- камера по функции, которая отдает ее CFrame целиком
local function startOrbit(getCFrame, sharpness)
	if zoneCamera then
		zoneCamera:Cancel()
		zoneCamera = nil
	end
	followCFrame = getCFrame
	followTarget = function()
		return getCFrame().Position
	end
	followSharpness = sharpness
	camera.CameraType = Enum.CameraType.Scriptable
end

-- вид на свой вольер (после поимки): камера со стороны базы и выше арки входа, смотрит
-- через персонажа в вольер. Направление берем на центр вольера, а не по взгляду персонажа:
-- он мог стоять как угодно, и камера оказывалась в вольере за листьями арки
local function penView()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. tostring(player:GetAttribute("Plot")))
	local center = plot and plot:GetAttribute("Center")
	if not root or typeof(center) ~= "Vector3" then
		return nil
	end
	local flat = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
	local dir = flat.Magnitude > 0.1 and flat.Unit or -Vector3.xAxis
	local eye = root.Position - dir * 15 + Vector3.new(0, 13, 0)
	return CFrame.lookAt(eye, root.Position + dir * 10 - Vector3.new(0, 2, 0))
end
ThrowController.PenView = penView

local function stopFollow()
	followTarget = nil
	followCFrame = nil
	povCFrame = nil
	lookOffset = Vector3.zero
	local character = locked and locked.humanoid.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		tweenToZone(root.Position)
		busyUntil = math.max(busyUntil, os.clock() + 0.6)
	else
		-- сразу на вольер: иначе обычная камера кадр-другой стояла со старым углом из каньона
		-- (один раз так показало карту снизу)
		camera.CameraType = Enum.CameraType.Custom
		local view = State.data.Carry and penView()
		if view then
			camera.CFrame = view
		end
	end
end

function ThrowController.Following()
	return followTarget ~= nil
end

-- кидал ли игрок недавно: животное в руках после поимки
function ThrowController.ThrewRecently()
	return os.clock() - lastThrowAt < 20
end

local function cameraStep(dt)
	if povCFrame then
		camera.CFrame = povCFrame
		return
	end
	if not followTarget then
		return
	end
	local desired
	if followCFrame then
		desired = followCFrame()
	else
		local target = followTarget()
		local position = target + cameraOffset
		-- еда уже над каньоном, а камера позади нее еще над базой: не уходим под землю у обрыва
		if position.X < EDGE_X then
			position = Vector3.new(position.X, math.max(position.Y, 2.5), position.Z)
		end
		desired = CFrame.lookAt(position, target + lookOffset)
	end
	if flightSway then
		desired *= CFrame.Angles(0, 0, math.sin(os.clock() * 4) * 0.03)
	end
	camera.CFrame = camera.CFrame:Lerp(desired, math.min(1, dt * followSharpness))
end

-- ---------- бросок с разворотом, как в оригинале: клик - бегунок замирает, внизу оценка,
-- полосы кино; через полсекунды разворот, камера за спиной крутится вместе с персонажем;
-- на выходе из оборота еда вылетает, камера летит за ней (это уже в playThrow)

local function startThrowSequence(character, timing, pose)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	throwToken += 1
	local token = throwToken
	UI.FreezeThrow(timing)
	UI.SetLetterbox(true)
	task.delay(SPIN_START, function()
		if throwToken ~= token then
			return
		end
		UI.ReleaseThrowUI()
		UI.SetCinematic(true)
		if root and root.Parent then
			TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { FieldOfView = defaultFov - 4 }):Play()
			-- камера догоняет разворот тела по дуге вокруг персонажа, а не напрямую сквозь него
			local cameraYaw, last = 0, os.clock()
			startOrbit(function()
				local now = os.clock()
				local target = pose and pose.yaw or 0
				cameraYaw += (target - cameraYaw) * math.min(1, (now - last) * 9)
				last = now
				local facing = (pose and pose.base or root.CFrame) * CFrame.Angles(0, cameraYaw, 0)
				return CFrame.lookAt((facing * SPIN_CAMERA).Position, facing:PointToWorldSpace(SPIN_LOOK))
			end, 12)
		end
	end)
	-- сервер не принял бросок: после разворота возвращаем обычный вид
	task.delay(THROW_POSE_TIME + 0.3, function()
		if throwToken == token and resultPending then
			resultPending = false
			UI.SetCinematic(false)
			TweenService:Create(camera, TweenInfo.new(0.3), { FieldOfView = defaultFov }):Play()
			stopFollow()
		end
	end)
end

local function throw()
	if not armed then
		return
	end
	local p = meterValue()
	local timing = Formula.Timing(p)
	armed = false
	busyUntil = os.clock() + THROW_POSE_TIME + 1 -- пока не пришел ответ сервера
	UI.ShowPowerPopup(Format.Number(State.data.Power * timing.mult))
	lastThrowAt = os.clock()
	resultPending = true
	throwRemote:FireServer(p)
	myPose = throwPose(player.Character, State.data.Food, true)
	startThrowSequence(player.Character, timing, myPose)
end


-- ---------- полет еды и появление животного

-- еда - модель из FoodModel, след висит на отдельной невидимой детали, чтобы не перекручивался
local function makeFood(food, position)
	local model = FoodModel.Build(food.id)
	model:PivotTo(CFrame.new(position))
	model.Parent = fxFolder

	local carrier = Instance.new("Part")
	carrier.Transparency = 1
	carrier.Size = Vector3.new(0.2, 0.2, 0.2)
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.Position = position
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = carrier
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), food.color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = 0.5
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = carrier
	carrier.Parent = fxFolder
	return model, carrier, trail
end

local function effectHolder(position)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	holder.Parent = fxFolder
	return holder
end

local function sparkle(position, color)
	local holder = effectHolder(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(1.2, 0)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(30)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

-- приземление: кольцо по земле и облачко пыли
local function dust(position, color)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 2, 2)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = Color3.new(1, 1, 1)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(0.15, 16, 16), Transparency = 1 }):Play()

	local holder = effectHolder(position + Vector3.new(0, 0.5, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4))
	emitter.Size = NumberSequence.new(1.6, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(26)
	task.delay(1.2, function()
		ring:Destroy()
		holder:Destroy()
	end)
end

local function animate(duration, step)
	local start = os.clock()
	while true do
		local k = math.min((os.clock() - start) / duration, 1)
		step(k)
		if k >= 1 then
			return
		end
		RunService.RenderStepped:Wait()
	end
end

-- спрятать модель только у себя (камера внутри головы животного)
local function setHidden(model, hidden)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

-- "S _ A _ _ _ S E" - буквы имени открываются по одной
local function suspenseText(name, shown)
	local parts = {}
	for i = 1, #name do
		local char = string.sub(name, i, i)
		table.insert(parts, char == " " and " " or (shown[i] and char or "_"))
	end
	return table.concat(parts, " ")
end

local function zoneAt(x)
	local distance = x - Game.FIELD_START
	for i = #Zones, 1, -1 do
		if distance >= Zones[i].start then
			return i
		end
	end
	return 1
end

local function serverLuck()
	return (workspace:GetAttribute("LuckUntil") or 0) > workspace:GetServerTimeNow() and 2 or 1
end

-- о редкой находке пишет баннер всем на сервере
local function rareBanner(info)
	local species = Animals.ById[info.animal.id]
	if species and species.rarity >= 5 then
		local rarity = Rarities[species.rarity]
		local who = info.player and info.player.DisplayName or "Someone"
		UI.Banner(who .. " found a " .. string.upper(rarity.id) .. " " .. Formula.AnimalName(info.animal) .. "!", rarity.color)
	end
end

local function playThrow(info, mine, isNew)
	-- чужой бросок не рисуем: в зоне броска игроки пропадают друг для друга (WorldFx),
	-- каждый видит только свою еду и свое животное. Другим - только баннер о редкой находке,
	-- когда животное поймано
	if not mine then
		task.wait(THROW_RELEASE + info.time + RUN_TIME + EAT_TIME)
		rareBanner(info)
		return
	end
	local food = Foods.ById[info.food] or Foods[1]
	-- замах начался по клику, еда вылетает из руки в момент броска
	local pose = myPose
	myPose = nil
	local from, to = info.from, info.to
	if pose then
		local left = pose.releaseAt - os.clock()
		if left > 0 then
			task.wait(left)
		end
		from = pose.release()
	end
	local foodModel, carrier, trail = makeFood(food, from)
	-- полет низкий и ровный, камера идет следом вдоль каньона
	local height = math.clamp((to - from).Magnitude * 0.08, 5, 40)
	local landing = to + Vector3.new(0, 0.8, 0)
	local animal = info.animal
	local species = Animals.ById[animal.id]
	local rarity = Rarities[species.rarity]

	if mine then
		UI.PlaySound("throw")
		UI.SetCinematic(true)
		UI.ShowFlight(food.luck * serverLuck())
		-- камера еще мгновение показывает бросок и доводку, потом срывается за едой:
		-- обзор шире, покачивание, линии скорости
		task.delay(THROW_WATCH, function()
			TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { FieldOfView = defaultFov + 18 }):Play()
			flightSway = true
			UI.SetSpeedLines(true)
			startFollow(function()
				return carrier.Position
			end, FLIGHT_CAMERA, FLIGHT_LOOK, 4)
		end)
	end

	-- полет: дуга, еда крутится, удача растет с дальностью, на границах зон баннер
	local currentZone = 0
	local baseLuck = food.luck * serverLuck()
	animate(info.time, function(k)
		local position = from:Lerp(landing, k) + Vector3.new(0, 4 * height * k * (1 - k), 0)
		carrier.Position = position
		foodModel:PivotTo(CFrame.new(position) * CFrame.Angles(k * 14, k * 9, 0))
		if mine then
			UI.SetFlightLuck(baseLuck * Formula.DistanceLuck(position.X - Game.FIELD_START))
		end
		if mine and position.X > Game.FIELD_START then
			local zone = zoneAt(position.X)
			if zone ~= currentZone then
				currentZone = zone
				UI.ZoneBanner(Zones[zone])
			end
		end
	end)
	trail.Enabled = false
	if mine then
		-- итог совпадает с удачей, с которой сервер выбирал животное
		UI.SetFlightLuck(info.luck or baseLuck * Formula.DistanceLuck(to.X - Game.FIELD_START))
		UI.SetVignette(0.6, Color3.new(0, 0, 0))
		flightSway = false
		UI.SetSpeedLines(false)
		TweenService:Create(camera, TweenInfo.new(0.5), { FieldOfView = defaultFov + 8 }):Play()
	end
	foodModel:PivotTo(CFrame.new(landing) * CFrame.Angles(0, math.random() * 6, 0))
	dust(to, Zones[info.zone] and Zones[info.zone].ground or food.color)

	-- животное выбегает спереди и бежит к еде
	local model = AnimalModel.Build(animal)
	model.Parent = fxFolder

	-- животное бежит из глубины каньона навстречу броску
	local startPos = to + Vector3.new(math.random(26, 38), 0, math.random(-5, 5))
	local direction = (to - startPos).Unit
	local size = model:GetExtentsSize()
	local stopPos = to - direction * (size.Z / 2 + 0.6)
	local hop = 0.1 + size.Y * 0.04
	local rainbow = model:GetAttribute("Rainbow")

	-- имя открывается по буквам в случайном порядке, последняя - в самом конце еды
	local name = string.upper(species.name)
	local shown, hidden = {}, {}
	for i = 1, #name do
		if string.sub(name, i, i) ~= " " then
			table.insert(hidden, i)
		end
	end
	local letterCount = #hidden
	local suspenseTime = RUN_TIME + EAT_TIME
	local function revealUpTo(elapsed)
		local due = math.min(letterCount, math.floor(letterCount * elapsed / suspenseTime + 0.5))
		local changed = false
		while letterCount - #hidden < due do
			shown[table.remove(hidden, math.random(1, #hidden))] = true
			changed = true
		end
		if changed then
			UI.SetSuspense(suspenseText(name, shown))
		end
	end

	-- интрига: свое животное не видно, камера - его глаза (морда смотрит вдоль LookVector).
	-- back - насколько отвести взгляд назад и вверх, чтобы еда вблизи не заслоняла весь кадр
	local function eyes(cf, lookAt, roll, back)
		back = back or 0
		local eye = cf.Position + Vector3.new(0, size.Y * 0.8 + back * 0.5, 0) + cf.LookVector * (size.Z * 0.5 - back)
		return CFrame.lookAt(eye, lookAt) * CFrame.Angles(0, 0, roll or 0)
	end
	local eatBack = 2 + size.Z * 0.3
	if mine then
		setHidden(model, true)
		followTarget = function()
			return model:GetPivot().Position + Vector3.new(0, size.Y / 2, 0)
		end
		UI.SetSuspense(suspenseText(name, shown))
		UI.SetVignette(0.8, Color3.new(0, 0, 0))
	end

	animate(RUN_TIME, function(k)
		local position = startPos:Lerp(stopPos, k)
		local step = k * math.pi * 10
		local cf = CFrame.lookAt(position, position + direction) + Vector3.new(0, math.abs(math.sin(step)) * hop, 0)
		AnimalModel.Pose(model, cf, step, os.clock())
		if rainbow then
			AnimalModel.PaintRainbow(model, os.clock())
		end
		if mine then
			povCFrame = eyes(cf, landing, math.sin(step) * 0.04)
			revealUpTo(k * RUN_TIME)
		end
	end)

	local eatCFrame = CFrame.lookAt(stopPos, stopPos + direction)
	AnimalModel.Pose(model, eatCFrame) -- ноги в покой
	-- у модели со скелетом ест голова (кивает к еде), у блочной - наклоняется все тело
	local rigged = AnimalModel.IsRigged(model)
	animate(EAT_TIME, function(k)
		local chew = eatCFrame
		if rigged then
			AnimalModel.Pose(model, eatCFrame, nil, os.clock(), "eat")
		else
			chew = eatCFrame * CFrame.Angles(-math.abs(math.sin(k * math.pi * 4)) * 0.18, 0, 0)
			model:PivotTo(chew)
		end
		foodModel:ScaleTo(math.max(0.05, 1 - k))
		if rainbow then
			AnimalModel.PaintRainbow(model, os.clock())
		end
		if mine then
			povCFrame = eyes(chew, landing, 0, eatBack * math.min(1, k * 4))
			revealUpTo(RUN_TIME + k * EAT_TIME)
		end
	end)
	if mine then
		-- все буквы открыты: имя целиком, и только потом показываем само животное
		revealUpTo(suspenseTime)
		task.wait(0.35)
		povCFrame = nil
		setHidden(model, false)
	end
	foodModel:Destroy()
	carrier:Destroy()

	rareBanner(info)

	if mine then
		-- крупный план спереди и карточка, пока не кликнут
		UI.SetSuspense(nil)
		UI.PlaySound(species.rarity >= 5 and "legendary" or "catch")
		sparkle(stopPos + Vector3.new(0, size.Y / 2, 0), rarity.color)
		-- камера близко перед мордой (животное смотрит вдоль direction) и чуть ниже него,
		-- чтобы животное было в верхней части кадра, над надписями
		local distance = 3.5 + size.Magnitude * 0.9
		cameraOffset = direction * distance + Vector3.new(0, 1 + size.Y * 0.4, 0)
		lookOffset = Vector3.new(0, -0.35 * distance, 0)
		local showing = true
		task.spawn(function()
			while showing do
				local t = os.clock()
				AnimalModel.Pose(model, eatCFrame + Vector3.new(0, math.abs(math.sin(t * 5)) * 0.3, 0), nil, t, "happy")
				if rainbow then
					AnimalModel.PaintRainbow(model, t)
				end
				RunService.RenderStepped:Wait()
			end
		end)
		UI.ShowReveal(animal, isNew)
		showing = false
	end

	-- прыжок и исчезновение
	animate(0.45, function(k)
		model:PivotTo(eatCFrame * CFrame.new(0, k * 4, 0) * CFrame.Angles(0, k * math.pi * 2, 0))
	end)
	sparkle(model:GetPivot().Position + Vector3.new(0, 1, 0), rarity.color)
	model:Destroy()

	if mine then
		UI.SetCinematic(false)
		TweenService:Create(camera, TweenInfo.new(0.4), { FieldOfView = defaultFov }):Play()
		stopFollow()
	end
end

local function makeWelcomeMarker()
	local beacon = Instance.new("Part")
	beacon.Name = "ThrowHere"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(26, 3.2, 3.2)
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(255, 220, 110)
	beacon.Transparency = 0.65
	beacon.CastShadow = false
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 64)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffsetWorldSpace = Vector3.new(14, 0, 0) -- над верхом столба (ось цилиндра - X)
	gui.Parent = beacon
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "THROW HERE!"
	label.TextColor3 = Color3.fromRGB(255, 230, 120)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(12, 12, 20)
	stroke.Parent = label
	return beacon, gui
end

function ThrowController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ThrowFx"
	fxFolder.Parent = workspace

	task.spawn(function()
		local beacon, gui = makeWelcomeMarker()
		while true do
			local data = State.data
			local plot = player:GetAttribute("Plot")
			local show = State.Ready() and (data.Throws or 0) == 0 and not data.Carry and not locked and type(plot) == "number"
			if show then
				local z = math.clamp(plot - 3, -2, 2) * LANE_STEP
				beacon.CFrame = CFrame.new(Game.THROW_PAD.x, 13, z) * CFrame.Angles(0, 0, math.pi / 2)
				gui.StudsOffsetWorldSpace = Vector3.new(0, 14 + math.sin(os.clock() * 4) * 0.6, 0)
				beacon.Parent = fxFolder
			else
				beacon.Parent = nil
			end
			RunService.RenderStepped:Wait()
		end
	end)

	-- надпись над зоной броска мешает, когда стоишь в ней
	task.spawn(function()
		local base = workspace:WaitForChild("Map"):WaitForChild("Base")
		repeat
			throwSign = base:FindFirstChild("ThrowSign", true)
			task.wait(0.5)
		until throwSign
	end)

	-- кидаем кликом или тапом в любом месте экрана
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonR2 then
			throw()
		end
	end)

	-- выйти из зоны без броска: прыжок
	UserInputService.JumpRequest:Connect(function()
		if locked and not followTarget and os.clock() >= busyUntil then
			unlock(true)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		onPad = root ~= nil and Formula.IsOnThrowPad(root.Position)

		-- пока несешь животное или висишь на турнике, зона не держит
		local mayLock = onPad and humanoid and humanoid.Health > 0 and State.Ready()
			and not State.training and not State.data.Carry
		if mayLock and not locked then
			lockInZone(character, root, humanoid)
		elseif locked and (not onPad or State.data.Carry or not locked.humanoid.Parent) then
			unlock(false)
		end
		UI.SetZoneHud(locked ~= nil)

		local ready = canThrow()
		if ready and not armed then
			armed = true
			armedSince = os.clock()
		elseif not ready then
			armed = false
		end
		UI.SetThrowState(onPad and not State.training and not followTarget and not State.data.Carry, ready)
		UI.ShowMeter(armed)
		if throwSign then
			throwSign.Enabled = not onPad
		end
		if armed then
			local p = meterValue()
			UI.SetMeter(p, Formula.Timing(p).color)
		end
		cameraStep(dt)
	end)

	resultRemote.OnClientEvent:Connect(function(info)
		local mine = info.player == player
		local isNew = false
		if mine then
			local index = State.data.Index
			isNew = not (index and index[info.animal.id])
			busyUntil = os.clock() + THROW_RELEASE + info.time + RUN_TIME + EAT_TIME + 0.9
			resultPending = false -- ответ пришел, заставка продолжится полетом
		end
		task.spawn(playThrow, info, mine, isNew)
	end)

	-- если персонаж умер во время полета камеры
	player.CharacterAdded:Connect(function()
		if followTarget then
			flightSway = false
			UI.SetSpeedLines(false)
			stopFollow()
		end
	end)
end

return ThrowController
