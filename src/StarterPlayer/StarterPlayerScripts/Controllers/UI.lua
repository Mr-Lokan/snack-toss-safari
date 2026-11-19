local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Formula = require(Shared:WaitForChild("Formula"))
local Game = require(Config:WaitForChild("Game"))
local Foods = require(Config:WaitForChild("Foods"))
local Animals = require(Config:WaitForChild("Animals"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local Products = require(Config:WaitForChild("Products"))
local IconAtlas = require(Shared:WaitForChild("IconAtlas"))
local State = require(script.Parent.State)
local Icons = require(script.Parent.Icons)

-- весь интерфейс создается кодом
local UI = {}

local rgb = Color3.fromRGB
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local THROW_TEXT = TOUCH and "TAP TO THROW!" or "CLICK TO THROW!"

local C = {
	panel = rgb(22, 24, 34),
	row = rgb(36, 38, 52),
	stroke = rgb(12, 12, 20),
	green = rgb(70, 200, 90),
	red = rgb(225, 65, 65),
	blue = rgb(65, 145, 255),
	orange = rgb(255, 150, 40),
	gold = rgb(255, 200, 40),
	gray = rgb(95, 95, 108),
	cash = rgb(120, 255, 120),
	power = rgb(90, 190, 255),
	luck = rgb(120, 255, 160),
	soft = rgb(200, 200, 225),
}
local KIND_COLORS = { good = C.green, bad = C.red, info = C.blue, luck = C.luck }
local MUTATION_COLORS = { Gold = rgb(255, 205, 50), Rainbow = rgb(255, 120, 220) }

-- стандартные звуки клиента, заменить на свои ассеты
local SOUNDS = {
	throw = "rbxasset://sounds/swordlunge.wav",
	catch = "rbxasset://sounds/electronicpingshort.wav",
	legendary = "rbxasset://sounds/victory.wav",
	click = "rbxasset://sounds/button.wav",
}

local remotes = {
	buyFood = Net.Event("BuyFood"),
	equipFood = Net.Event("EquipFood"),
	sell = Net.Event("SellAnimals"),
	sellBackpack = Net.Event("SellBackpack"),
	pickUp = Net.Event("PickUp"),
	goThrow = Net.Event("GoThrow"),
	equip = Net.Event("EquipBackpack"),
	equipBest = Net.Event("EquipBest"),
	purchase = Net.Event("Purchase"),
}

local screen, cinema
local scales = {}
local panels = {}
local openPanel
local hud = {}
local controls = {}
local reveal = {}
local flight = {}
local toastList, banner, blur
local cinematicOn, inZone = false, false
local sounds = {}
local bannerToken, bonusToken, zoneToken = 0, 0, 0

local function new(className, props, children)
	local object = Instance.new(className)
	local parent = props and props.Parent
	for key, value in props or {} do
		if key ~= "Parent" then
			object[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = object
	end
	object.Parent = parent
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function round()
	return new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

local function stroke(thickness, color)
	return new("UIStroke", {
		Thickness = thickness or 2.5,
		Color = color or C.stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- затенение сверху вниз: UIGradient умножается на цвет фона, поэтому от белого к серому
local SHADE = ColorSequence.new(WHITE, rgb(180, 180, 180))

local function gradient(_, rotation)
	return new("UIGradient", { Color = SHADE, Rotation = rotation or 90 })
end

local function tween(object, time, goal, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- текст с толстой обводкой
local function text(props)
	local max = props.max or 32
	local outline = props.outline
	props.max, props.outline = nil, nil
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = FONT
	props.TextScaled = true
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextStrokeTransparency = 1
	local label = new("TextLabel", props, { new("UITextSizeConstraint", { MaxTextSize = max }) })
	new("UIStroke", { Thickness = outline or 2.5, Color = C.stroke, Parent = label })
	return label
end

-- значок и надпись в одну строку (значки вместо смайликов): текст своей длины, вместе по центру
-- или слева. props: Position, Size (высота строки - Size.Y.Offset), AnchorPoint, key - значок,
-- Text, TextColor3, max - размер текста, outline, align = "left", LayoutOrder, ZIndex, Parent.
-- Возвращает надпись, значок и рамку
local function iconLine(props)
	local h = props.Size.Y.Offset
	local holder = new("Frame", {
		AnchorPoint = props.AnchorPoint or Vector2.zero, Position = props.Position or UDim2.new(), Size = props.Size,
		BackgroundTransparency = 1, LayoutOrder = props.LayoutOrder or 0, ZIndex = props.ZIndex or 1, Parent = props.Parent,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = props.align == "left" and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, math.floor(h * 0.15)), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local icon = IconAtlas.New(props.key, {
		Size = UDim2.fromOffset(math.floor(h * 1.3), math.floor(h * 1.3)), LayoutOrder = 1, ZIndex = props.ZIndex or 1, Parent = holder,
	})
	local label = new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), BackgroundTransparency = 1, Font = FONT,
		TextSize = props.max or math.floor(h * 0.85), Text = props.Text or "", TextColor3 = props.TextColor3 or WHITE,
		TextXAlignment = LEFT, LayoutOrder = 2, ZIndex = props.ZIndex or 1, Parent = holder,
	})
	new("UIStroke", { Thickness = props.outline or 2.5, Color = C.stroke, Parent = label })
	return label, icon, holder
end

function UI.PlaySound(name)
	local sound = sounds[name]
	if not sound then
		sound = new("Sound", { SoundId = SOUNDS[name], Volume = 0.5, Parent = SoundService })
		sounds[name] = sound
	end
	SoundService:PlayLocalSound(sound)
end

-- кнопка: градиент, обводка, пружинит при наведении и нажатии
local function button(props, onClick)
	local color = props.color or C.blue
	local max = props.max or 30
	props.color, props.max = nil, nil
	props.BackgroundColor3 = color
	props.AutoButtonColor = false
	props.Font = FONT
	props.TextScaled = true
	props.TextColor3 = WHITE
	props.TextStrokeTransparency = 0
	local b = new("TextButton", props, {
		corner(12),
		stroke(3),
		gradient(),
		new("UITextSizeConstraint", { MaxTextSize = max }),
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		}),
	})
	local scale = new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		tween(scale, 0.1, { Scale = 1.06 })
	end)
	b.MouseLeave:Connect(function()
		tween(scale, 0.1, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = 0.9 })
	end)
	b.MouseButton1Up:Connect(function()
		tween(scale, 0.25, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		b.Activated:Connect(function()
			UI.PlaySound("click")
			onClick()
		end)
	end
	return b
end

-- квадратная кнопка меню: большая иконка и подпись снизу
local function iconButton(parent, icon, caption, color, order, onClick)
	local b = button({ Size = UDim2.fromOffset(108, 108), Text = "", color = color, LayoutOrder = order, Parent = parent }, onClick)
	IconAtlas.New(icon, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(80, 80), Parent = b })
	text({ Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 32), Text = caption, max = 28, outline = 3, Parent = b })
	return b
end

-- общий масштаб интерфейса под размер экрана
local function scaled(frame)
	table.insert(scales, new("UIScale", { Parent = frame }))
	return frame
end

local function updateScale()
	local size = workspace.CurrentCamera.ViewportSize
	local value = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.5, 1.2)
	for _, s in scales do
		s.Scale = value
	end
	-- на телефоне плашка удачи под цифрами силы и денег, их высота зависит от масштаба
	if TOUCH and hud.luck then
		hud.luck.Position = UDim2.new(1, -16, 0, 8 + 156 * value)
	end
end

local function clear(container)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function countKeys(t)
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

-- короткое "подпрыгивание" надписи
local function bump(label)
	local scale = label:FindFirstChild("Bump") or new("UIScale", { Name = "Bump", Parent = label })
	scale.Scale = 1.15
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- ---------- HUD

-- подсказка: значок и текст
local function goalText(data)
	if State.training then
		return "strength", (TOUCH and "Tap" or "Click") .. " the circles for x2 power!"
	end
	if data.Carry then
		return "animals", "Click inside your pen to put your animal there"
	end
	if (data.Throws or 0) == 0 then
		return "throw", "Step into the glowing zone to throw food"
	end
	if not data.Foods.apple then
		return "food", "Buy an Apple at the Food Shop (" .. Format.Money(Foods.ById.apple.price) .. ")"
	end
	if data.Power < 40 then
		return "strength", "Step into the circle at your pull-up bar"
	end
	local nextZone = Zones[Formula.ReachZone(data.Power) + 1]
	if nextZone then
		local need = math.ceil(nextZone.power / Formula.TIMING[1].mult)
		return IconAtlas.Zone(nextZone), nextZone.name .. ": " .. Format.Number(data.Power) .. " / " .. Format.Number(need) .. " power"
	end
	return "trophy", "You reached the last zone!"
end

local lastShown = {}
local function updateHud()
	local data = State.data
	if not State.Ready() then
		return
	end
	if lastShown.cash and data.Cash > lastShown.cash then
		bump(hud.cash)
	end
	if lastShown.power and data.Power > lastShown.power then
		bump(hud.power)
	end
	lastShown.cash, lastShown.power = data.Cash, data.Power
	hud.power.Text = Format.Number(data.Power)
	hud.cash.Text = Format.Money(data.Cash)
	hud.income.Text = "+" .. Format.Money(player:GetAttribute("Income") or 0) .. "/s"
	local goalIcon, goalLine = goalText(data)
	hud.goal.Text = goalLine
	IconAtlas.Apply(hud.goalIcon, goalIcon)
end

local function buildHud()
	-- подсказка, что делать дальше
	local goal = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(470, 42),
		BackgroundColor3 = rgb(70, 50, 15), BackgroundTransparency = 0.1, Parent = screen,
	}, { corner(12), stroke(2.5, C.orange) }))
	hud.goal, hud.goalIcon = iconLine({ Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 36), key = "throw", max = 20, outline = 2, Parent = goal })

	-- сила и деньги, большие цифры с иконками: на компьютере внизу слева, на телефоне справа сверху
	-- (внизу слева на телефоне появляется джойстик и закрывал их)
	local stats = scaled(new("Frame", {
		AnchorPoint = TOUCH and Vector2.new(1, 0) or Vector2.new(0, 1),
		Position = TOUCH and UDim2.new(1, -16, 0, 8) or UDim2.new(0, 16, 1, -12),
		Size = UDim2.fromOffset(380, 150), BackgroundTransparency = 1, Parent = screen,
	}))
	-- на телефоне значки справа, цифры прижаты к ним справа
	local iconX = TOUCH and 380 - 68 or -4
	local textX = TOUCH and 0 or 72
	local align = TOUCH and RIGHT or LEFT
	IconAtlas.New("strength", { Position = UDim2.fromOffset(iconX, -4), Size = UDim2.fromOffset(72, 72), Parent = stats })
	hud.power = text({ Position = UDim2.fromOffset(textX, 2), Size = UDim2.new(1, -72, 0, 60), TextXAlignment = align, TextColor3 = C.power, max = 58, outline = 4, Parent = stats })
	IconAtlas.New("money", { Position = UDim2.fromOffset(iconX, 62), Size = UDim2.fromOffset(72, 72), Parent = stats })
	hud.cash = text({ Position = UDim2.fromOffset(textX, 68), Size = UDim2.new(1, -72, 0, 60), TextXAlignment = align, TextColor3 = C.cash, max = 58, outline = 4, Parent = stats })
	hud.income = text({ Position = UDim2.fromOffset(TOUCH and 0 or 76, 126), Size = UDim2.new(1, -76, 0, 24), TextXAlignment = align, max = 22, Parent = stats })

	-- меню: слева Index и Shop, справа Animals
	local left = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, -30), Size = UDim2.fromOffset(108, 352),
		BackgroundTransparency = 1, Parent = screen,
	}, { new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }) }))
	iconButton(left, "index", "Index", C.blue, 1, function()
		UI.OpenPanel("Index")
	end)
	iconButton(left, "shop", "Shop", C.red, 2, function()
		UI.OpenPanel("Store")
	end)
	-- к своему месту в зоне броска: от дальних вольеров идти втрое дольше, чем от среднего
	iconButton(left, "throw", "Throw", C.green, 3, function()
		if State.data.Carry then
			UI.Notify("Put your animal in your pen first", "bad", "animals")
			return
		end
		UI.ClosePanel()
		remotes.goThrow:FireServer()
	end)
	local right = scaled(new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, -50), Size = UDim2.fromOffset(108, 108),
		BackgroundTransparency = 1, Parent = screen,
	}))
	iconButton(right, "animals", "Animals", C.orange, 1, function()
		UI.OpenPanel("Animals")
	end)

	local luck = scaled(new("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, TOUCH and 112 or 56), Size = UDim2.fromOffset(260, 46),
		BackgroundColor3 = rgb(40, 150, 80), Visible = false, Parent = screen,
	}, { corner(12), stroke(3), gradient(rgb(40, 150, 80)) }))
	hud.luck = luck
	hud.luckText = iconLine({ Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 34), key = "luck", max = 22, Parent = luck })

	-- во время броска прячем все лишнее, в зоне броска - меню
	hud.groups = { goal = goal, stats = stats, left = left, right = right }
end

local function refreshGroups()
	local groups = hud.groups
	groups.goal.Visible = not cinematicOn
	groups.stats.Visible = not cinematicOn
	groups.left.Visible = not cinematicOn and not inZone
	groups.right.Visible = not cinematicOn and not inZone
	controls.root.Visible = not cinematicOn
end

-- полосы кино сверху и снизу; при броске выезжают раньше, чем прячется интерфейс
function UI.SetLetterbox(on)
	local height = on and 0.1 or 0
	tween(cinema.top, 0.35, { Size = UDim2.fromScale(1, height) })
	tween(cinema.bottom, 0.35, { Size = UDim2.fromScale(1, height) })
end

function UI.SetCinematic(on)
	cinematicOn = on
	refreshGroups()
	UI.SetLetterbox(on)
	if not on then
		flight.luck.Visible = false
		UI.SetSuspense(nil)
		UI.SetVignette(0)
	end
end

function UI.SetZoneHud(on)
	if inZone ~= on then
		inZone = on
		refreshGroups()
	end
end

-- ---------- бросок, тренировка, ношение животного

local function buildControls()
	local root = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(620, 170),
		BackgroundTransparency = 1, Parent = screen,
	}))
	controls.root = root

	-- зона броска: надпись внизу и вертикальная шкала справа от персонажа
	controls.throwText = text({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(560, 66),
		Text = THROW_TEXT, Visible = false, max = 62, outline = 5, Parent = root,
	})
	controls.leaveHint = text({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(300, 22),
		Text = TOUCH and "Tap jump to leave" or "Jump to leave", TextColor3 = C.soft, Visible = false, max = 20, Parent = root,
	})

	local meter = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 150, 0.5, -20), Size = UDim2.fromOffset(74, 330),
		BackgroundTransparency = 1, Visible = false, Parent = screen,
	}))
	local bar = new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.panel, Parent = meter }, { round() })
	local upper = 1
	for _, timing in ipairs(Formula.TIMING) do
		new("Frame", {
			Position = UDim2.fromScale(0, 1 - upper), Size = UDim2.fromScale(1, upper - timing.from),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = bar,
		}, { new("UIGradient", { Color = ColorSequence.new(timing.color:Lerp(WHITE, 0.35), timing.color) }) })
		if timing.from > 0 then
			new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 1 - timing.from), Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = C.stroke, BorderSizePixel = 0, ZIndex = 2, Parent = bar,
			})
		end
		upper = timing.from
	end
	-- блик слева
	new("Frame", {
		Position = UDim2.fromScale(0.16, 0.05), Size = UDim2.new(0, 8, 0.9, 0), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6, ZIndex = 3, Parent = bar,
	}, { round() })
	-- обводка отдельной рамкой: CanvasGroup обрезал бы ее по краю
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = meter }, {
		round(),
		new("UIStroke", { Thickness = 5, Color = C.stroke }),
	})
	controls.slider = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1.4, 0, 0, 26),
		BackgroundColor3 = WHITE, ZIndex = 3, Parent = meter,
	}, { round(), stroke(4) })
	-- число рядом с бегунком: где он сейчас, от 0 внизу до 20 наверху
	controls.meterValue = text({
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 20, 1, 0), Size = UDim2.fromOffset(90, 58),
		TextXAlignment = LEFT, max = 56, outline = 4, Parent = meter,
	})
	controls.meter = meter

	-- турник: STOP и шкала уровня
	controls.stop = button({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -64), Size = UDim2.fromOffset(230, 64),
		Text = "STOP", color = C.red, max = 44, Visible = false, Parent = root,
	})
	local xp = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(600, 52),
		BackgroundColor3 = rgb(25, 55, 35), ClipsDescendants = true, Visible = false, Parent = root,
	}, { corner(14), stroke(4) })
	controls.xpFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = xp }, {
		corner(14),
		new("UIGradient", { Color = ColorSequence.new(rgb(120, 180, 255), rgb(40, 100, 240)), Rotation = 90 }),
	})
	controls.xpLevel = text({ Position = UDim2.fromOffset(16, 6), Size = UDim2.new(0.5, -16, 1, -12), TextXAlignment = LEFT, ZIndex = 2, max = 34, outline = 3, Parent = xp })
	controls.xpCount = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 6), Size = UDim2.new(0.5, -16, 1, -12), TextXAlignment = RIGHT, ZIndex = 2, max = 32, outline = 3, Parent = xp })
	controls.xp = xp
	-- x2 за пойманный кружок: значок зелья и таймер; прячется и показывается вся строка
	local bonusText, _, bonusLine = iconLine({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -134), Size = UDim2.fromOffset(320, 42),
		key = "boost", TextColor3 = rgb(255, 215, 0), max = 36, outline = 3, Parent = root,
	})
	bonusLine.Visible = false
	controls.bonus, controls.bonusText = bonusLine, bonusText

	-- платформа улучшения турника
	-- как вкладки: кожаная обложка, крафт-бумага, чернила
	local upgrade = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(470, 150),
		BackgroundColor3 = rgb(122, 82, 52), Visible = false, Parent = root,
	}, { corner(16), stroke(4) })
	local sheet = new("ImageLabel", {
		Position = UDim2.fromOffset(9, 9), Size = UDim2.new(1, -18, 1, -18), BackgroundColor3 = rgb(238, 218, 176),
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(256, 256), Parent = upgrade,
	}, { corner(10) })
	task.spawn(function()
		local plate = ReplicatedStorage:WaitForChild("ToonWorld"):WaitForChild("Textures"):WaitForChild("ui_paper", 10)
		sheet.Image = plate and plate.TextureID or ""
	end)
	controls.upgrade = {
		frame = upgrade,
		title = (iconLine({ Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 32), key = "upgrade", Text = "Upgrade your bar", TextColor3 = rgb(70, 46, 30), align = "left", max = 28, outline = 0, ZIndex = 2, Parent = upgrade })),
		info = text({ Position = UDim2.fromOffset(22, 46), Size = UDim2.new(1, -44, 0, 36), TextXAlignment = LEFT, TextColor3 = rgb(128, 98, 68), max = 18, outline = 0, ZIndex = 2, Parent = upgrade }),
		button = button({ Position = UDim2.new(0, 20, 1, -58), Size = UDim2.new(1, -40, 0, 44), color = C.green, max = 26, ZIndex = 2, Parent = upgrade }),
	}
end

function UI.Controls()
	return controls
end

-- frozen: после клика шкала замирает на месте броска, пока не начнется разворот
local throwState = {}

function UI.ShowMeter(visible)
	if not throwState.frozen then
		controls.meter.Visible = visible
	end
end

local METER_MAX = 20

-- p от 0 (низ) до 1 (верх); color - цвет сегмента, на котором бегунок
function UI.SetMeter(p, color)
	controls.slider.Position = UDim2.fromScale(0.5, 1 - p)
	controls.meterValue.Position = UDim2.new(1, 20, 1 - p, 0)
	controls.meterValue.Text = tostring(math.floor(p * METER_MAX + 0.5))
	controls.meterValue.TextColor3 = color or WHITE
end

-- клик: бегунок замирает и подсвечивается, вместо "CLICK TO THROW!" - оценка броска
function UI.FreezeThrow(timing)
	throwState.frozen = true
	controls.meter.Visible = true
	local slider = controls.slider:FindFirstChildOfClass("UIStroke")
	slider.Color = timing.color
	slider.Thickness = 6
	local label = controls.throwText
	label.Text = string.upper(timing.label)
	label.TextColor3 = timing.color
	label.Visible = true
	controls.leaveHint.Visible = false
	bump(label)
end

-- начался разворот: шкала и оценка уходят, дальше кино
function UI.ReleaseThrowUI()
	throwState.frozen = false
	throwState.visible, throwState.ready = nil, nil
	controls.meter.Visible = false
	local slider = controls.slider:FindFirstChildOfClass("UIStroke")
	slider.Color = C.stroke
	slider.Thickness = 4
	controls.throwText.Text = THROW_TEXT
	controls.throwText.TextColor3 = WHITE
	controls.throwText.Visible = false
end

-- "+19 POWER" рядом со шкалой в момент броска
function UI.ShowPowerPopup(value)
	local label = text({
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 210, 0.5, 0), Size = UDim2.fromOffset(340, 64),
		Text = "+" .. value .. " POWER", TextXAlignment = LEFT, TextColor3 = C.cash, max = 60, outline = 5, Parent = screen,
	})
	local scale = new("UIScale", { Scale = 0.5, Parent = label })
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.7, function()
		tween(label, 0.5, { Position = label.Position - UDim2.fromOffset(0, 60), TextTransparency = 1 })
		task.wait(0.5)
		label:Destroy()
	end)
end

function UI.SetThrowState(visible, ready)
	if throwState.frozen or throwState.visible == visible and throwState.ready == ready then
		return
	end
	throwState.visible, throwState.ready = visible, ready
	controls.throwText.Visible = visible and ready
	controls.leaveHint.Visible = visible and ready
	if not visible then
		controls.meter.Visible = false
	end
end

function UI.SetTrainingMode(training)
	updateHud()
	controls.stop.Visible = training
	controls.xp.Visible = training
	if training then
		UI.SetThrowState(false, false)
	else
		bonusToken += 1
		controls.bonus.Visible = false
	end
end

function UI.SetXP(level, xp, need)
	controls.xpLevel.Text = "Level " .. level
	controls.xpCount.Text = Format.Number(xp) .. " / " .. Format.Number(need)
	tween(controls.xpFill, 0.25, { Size = UDim2.fromScale(math.clamp(xp / need, 0, 1), 1) })
end

-- всплывающий опыт возле персонажа
function UI.ShowGain(gain, boosted)
	local label = text({
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.random(-90, -30), 0.5, math.random(-40, 20)),
		Size = UDim2.fromOffset(240, 54), Text = "+" .. Format.Number(gain) .. " XP",
		TextColor3 = boosted and rgb(255, 215, 0) or rgb(150, 230, 255), max = boosted and 50 or 42, outline = 3, Parent = screen,
	})
	tween(label, 0.9, { Position = label.Position - UDim2.fromOffset(0, 90), TextTransparency = 1 })
	task.delay(0.9, function()
		label:Destroy()
	end)
end

-- "LEVEL UP! Throw Power +N" над головой, всплывает и улетает вверх
function UI.ShowLevelUp(character, gain)
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = new("BillboardGui", {
		Adornee = head, Size = UDim2.fromOffset(320, 100), StudsOffset = Vector3.new(0, 1.5, 0),
		AlwaysOnTop = true, LightInfluence = 0, ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui"),
	})
	local holder = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local scale = new("UIScale", { Scale = 0.3, Parent = holder })
	text({ Size = UDim2.fromScale(1, 0.56), Text = "LEVEL UP!", TextColor3 = rgb(255, 220, 60), max = 64, outline = 5, Parent = holder })
	text({ Position = UDim2.fromScale(0, 0.56), Size = UDim2.fromScale(1, 0.4), Text = "Throw Power +" .. Format.Number(gain), TextColor3 = C.cash, max = 42, outline = 4, Parent = holder })
	tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(gui, 2, { StudsOffset = Vector3.new(0, 3.5, 0) }, Enum.EasingStyle.Sine)
	task.delay(1.6, function()
		tween(scale, 0.3, { Scale = 0 })
		task.wait(0.3)
		gui:Destroy()
	end)
end

-- кружок с бонусом x2 возле персонажа, сжимается за duration секунд
function UI.ShowBonusCircle(duration, onClick)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(110, 110), BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.58 + math.random() * 0.1, 0.45 + math.random() * 0.15), ZIndex = 10, Parent = screen,
	})
	local ring = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(2, 2),
		BackgroundTransparency = 1, ZIndex = 10, Parent = holder,
	}, { round(), new("UIStroke", { Thickness = 5, Color = rgb(230, 170, 255) }) })
	local circle = new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(170, 70, 230), AutoButtonColor = false,
		Text = TOUCH and "TAP!" or "CLICK!", Font = FONT, TextScaled = true, TextColor3 = WHITE, ZIndex = 11, Parent = holder,
	}, {
		round(),
		gradient(rgb(170, 70, 230)),
		new("UIStroke", { Thickness = 4, Color = rgb(240, 200, 255), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		new("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0) }),
	})
	text({
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 18, 1, 10), Size = UDim2.fromOffset(70, 46),
		Text = "x2", ZIndex = 12, max = 44, outline = 4, Parent = holder,
	})
	local pulse = new("UIScale", { Parent = holder })
	pulse.Scale = 0.3
	tween(pulse, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(ring, duration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	circle.Activated:Connect(function()
		UI.PlaySound("catch")
		onClick()
		holder:Destroy()
	end)
	task.delay(duration, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

function UI.ShowBonusActive(seconds)
	bonusToken += 1
	local token = bonusToken
	local label = controls.bonusText
	controls.bonus.Visible = true
	task.spawn(function()
		local endAt = os.clock() + seconds
		while token == bonusToken and os.clock() < endAt do
			label.Text = string.format("x2 XP  %.1fs", endAt - os.clock())
			task.wait(0.1)
		end
		if token == bonusToken then
			controls.bonus.Visible = false
		end
	end)
end

-- info = { current, next, canBuy } или nil, если игрок не на платформе
function UI.SetUpgradePad(info)
	local panel = controls.upgrade
	panel.frame.Visible = info ~= nil
	if not info then
		return
	end
	local current, nextBar = info.current, info.next
	local line = current.name .. " · +" .. Format.Number(current.power) .. " XP per pull-up"
	if nextBar then
		panel.info.Text = line .. "\n→ " .. nextBar.name .. " · +" .. Format.Number(nextBar.power) .. " XP per pull-up"
		panel.button.Text = "UPGRADE " .. Format.Money(nextBar.price)
		panel.button.BackgroundColor3 = info.canBuy and C.green or C.gray
	else
		panel.info.Text = line .. "\nYour bar is maxed out!"
		panel.button.Text = "MAX LEVEL"
		panel.button.BackgroundColor3 = C.gray
	end
end

function UI.UpgradeButton()
	return controls.upgrade.button
end

-- ---------- кино при броске: удача, зоны, имя по буквам, показ улова

local function buildCinema()
	cinema = {}
	local gui = new("ScreenGui", {
		Name = "Cinema", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
	})
	cinema.gui = gui
	-- затемнение по краям: при приземлении черное, при показе улова - цветом редкости.
	-- Радиального градиента нет, поэтому четыре полосы с линейным
	cinema.vignette = {}
	for _, edge in {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.32), 90 },
		{ UDim2.fromScale(0, 0.68), UDim2.fromScale(1, 0.32), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.26, 1), 0 },
		{ UDim2.fromScale(0.74, 0), UDim2.fromScale(0.26, 1), 180 },
	} do
		table.insert(cinema.vignette, new("Frame", {
			Position = edge[1], Size = edge[2], BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = gui,
		}, { new("UIGradient", { Rotation = edge[3], Transparency = NumberSequence.new(0, 1) }) }))
	end
	cinema.top = new("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor3 = BLACK, BorderSizePixel = 0, Parent = gui })
	cinema.bottom = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = BLACK, BorderSizePixel = 0, Parent = gui })

	local layer = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, Parent = gui,
	}))

	-- удача сверху во время полета
	flight.luck = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.11), Size = UDim2.fromOffset(420, 130), BackgroundTransparency = 1, Visible = false, Parent = layer })
	flight.luckValue = text({ Size = UDim2.new(1, 0, 0, 92), TextColor3 = rgb(120, 110, 255), max = 90, outline = 6, Parent = flight.luck })
	text({ Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 40), Text = "LUCK", max = 38, outline = 4, Parent = flight.luck })

	-- полоса с названием зоны
	flight.zone = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.new(1, 0, 0, 80),
		BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, Visible = false, Parent = layer,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0),
				NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	flight.zoneText, flight.zoneIcon = iconLine({ Size = UDim2.new(1, 0, 0, 80), key = "z_forest", max = 64, outline = 5, Parent = flight.zone })

	-- имя животного по буквам, пока оно бежит к еде
	flight.suspense = text({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.86, 0), Size = UDim2.fromOffset(900, 100),
		Visible = false, max = 96, outline = 6, Parent = layer,
	})

	-- показ пойманного животного
	reveal.frame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = layer })
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.92, 0), Size = UDim2.fromOffset(900, 290), BackgroundTransparency = 1, Parent = reveal.frame })
	reveal.box = box
	reveal.pop = new("UIScale", { Parent = box })
	reveal.tag = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(500, 50), max = 46, outline = 4, Parent = box })
	reveal.name = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.fromOffset(880, 110), max = 104, outline = 7, Parent = box })
	reveal.income = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160), Size = UDim2.fromOffset(500, 66), TextColor3 = C.cash, max = 62, outline = 5, Parent = box })
	reveal.hint = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 236), Size = UDim2.fromOffset(400, 36), Text = TOUCH and "tap to continue" or "click to continue", max = 32, outline = 3, Parent = box })
	reveal.new = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 330, 0, 80), Size = UDim2.fromOffset(200, 80),
		BackgroundColor3 = C.orange, Rotation = -12, Parent = box,
	}, { corner(16), stroke(5), gradient(C.orange) })
	text({ Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -12), Text = "NEW!", max = 64, outline = 5, Parent = reveal.new })
end

function UI.ShowFlight(luck)
	flight.luck.Visible = true
	flight.shownLuck = nil
	UI.SetFlightLuck(luck)
end

-- удача растет, пока еда летит дальше
function UI.SetFlightLuck(luck)
	flight.luckValue.Text = string.format("%.2fX", luck)
	local step = math.floor(luck * 2)
	if flight.shownLuck and step > flight.shownLuck then
		bump(flight.luckValue)
	end
	flight.shownLuck = step
end

-- strength от 0 до 1
function UI.SetVignette(strength, color)
	for _, edge in cinema.vignette do
		if color then
			edge.BackgroundColor3 = color
		end
		tween(edge, 0.4, { BackgroundTransparency = 1 - strength * 0.85 })
	end
end

-- линии скорости: тонкие штрихи летят от центра к краям, пока еда в полете
local speedToken = 0

function UI.SetSpeedLines(on)
	speedToken += 1
	if not on then
		return
	end
	local token = speedToken
	task.spawn(function()
		while token == speedToken do
			local angle = math.random() * math.pi * 2
			local direction = Vector2.new(math.cos(angle), math.sin(angle))
			local line = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(math.random(90, 170), 3),
				Position = UDim2.fromScale(0.5 + direction.X * 0.3, 0.5 + direction.Y * 0.3), Rotation = math.deg(angle),
				BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 0, Parent = cinema.gui,
			})
			tween(line, 0.3, { Position = UDim2.fromScale(0.5 + direction.X * 0.75, 0.5 + direction.Y * 0.75), BackgroundTransparency = 1 })
			task.delay(0.3, function()
				line:Destroy()
			end)
			task.wait(0.04)
		end
	end)
end

-- кольцо, которое разлетается от центра экрана
local function burstRing(color, delay)
	task.delay(delay or 0, function()
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(80, 80),
			BackgroundTransparency = 1, Parent = cinema.gui,
		}, { round() })
		local ringStroke = new("UIStroke", { Thickness = 14, Color = color, Parent = ring })
		tween(ring, 0.8, { Size = UDim2.fromOffset(1100, 1100) }, Enum.EasingStyle.Quart)
		tween(ringStroke, 0.8, { Transparency = 1, Thickness = 3 })
		task.wait(0.8)
		ring:Destroy()
	end)
end

function UI.ZoneBanner(zone)
	zoneToken += 1
	local token = zoneToken
	flight.zoneText.Text = zone.name
	IconAtlas.Apply(flight.zoneIcon, IconAtlas.Zone(zone))
	flight.zoneText.TextColor3 = zone.ground:Lerp(WHITE, 0.35)
	flight.zone.Visible = true
	flight.zone.Size = UDim2.new(0.3, 0, 0, 80)
	tween(flight.zone, 0.3, { Size = UDim2.new(1, 0, 0, 80) }, Enum.EasingStyle.Back)
	task.delay(1.6, function()
		if token == zoneToken then
			flight.zone.Visible = false
		end
	end)
end

function UI.SetSuspense(value)
	flight.suspense.Visible = value ~= nil
	if value then
		flight.suspense.Text = value
	end
end

-- показывает животное крупно и ждет клика (или пару секунд)
function UI.ShowReveal(animal, isNew)
	local species = Animals.ById[animal.id]
	local rarity = Rarities[species.rarity]
	local tags = {}
	if animal.m then
		table.insert(tags, string.upper(animal.m))
	end
	if animal.g then
		table.insert(tags, "BIG")
	end
	reveal.tag.Text = table.concat(tags, " · ")
	reveal.tag.TextColor3 = animal.m and MUTATION_COLORS[animal.m] or WHITE
	reveal.name.Text = string.upper(species.name)
	reveal.name.TextColor3 = rarity.color
	reveal.income.Text = Format.Money(Formula.Income(animal)) .. "/s"
	reveal.new.Visible = isNew
	reveal.frame.Visible = true
	UI.SetVignette(species.rarity >= 3 and 0.75 or 0.5, rarity.color)
	burstRing(rarity.color)
	burstRing(WHITE, 0.15)
	reveal.pop.Scale = 0.3
	tween(reveal.pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	if isNew then
		reveal.new.Rotation = -40
		tween(reveal.new, 0.5, { Rotation = -12 }, Enum.EasingStyle.Elastic)
	end

	local done = false
	local connection = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space then
			done = true
		end
	end)
	local started = os.clock()
	task.wait(0.4) -- чтобы случайный клик не закрыл сразу
	done = false
	while not done and os.clock() - started < 3.5 do
		task.wait()
	end
	connection:Disconnect()
	tween(reveal.pop, 0.2, { Scale = 0 })
	task.wait(0.2)
	reveal.frame.Visible = false
end

-- ---------- уведомления и баннер

-- icon - значок слева (ключ из IconAtlas), можно без него
function UI.Notify(message, kind, icon)
	local color = KIND_COLORS[kind] or C.blue
	local toast = new("Frame", {
		Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.panel, BackgroundTransparency = 0.05, Parent = toastList,
	}, { corner(12), stroke(3, color) })
	local textX = 10
	if type(icon) == "string" then
		IconAtlas.New(icon, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(50, 50), Parent = toast })
		textX = 54
	end
	text({ Position = UDim2.fromOffset(textX, 5), Size = UDim2.new(1, -textX - 10, 1, -10), Text = message, max = 22, Parent = toast })
	local scale = new("UIScale", { Scale = 0.6, Parent = toast })
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local frames = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames > 4 then
		frames[1]:Destroy()
	end
	task.delay(3.5, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

function UI.Banner(message, color)
	bannerToken += 1
	local token = bannerToken
	banner.Text = message
	banner.TextColor3 = color or WHITE
	banner.Visible = true
	local scale = banner:FindFirstChildOfClass("UIScale")
	scale.Scale = 0.6
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(4, function()
		if token == bannerToken then
			banner.Visible = false
		end
	end)
end

local function buildPopups()
	-- уведомления на своем экране поверх вкладок: раньше «Bought Apple!» пряталось под Food Shop
	local toastScreen = new("ScreenGui", {
		Name = "Toasts", ResetOnSpawn = false, DisplayOrder = 2, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	toastList = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(400, 220),
		BackgroundTransparency = 1, Parent = toastScreen,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}))

	local bannerHolder = scaled(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(820, 64),
		BackgroundTransparency = 1, Parent = screen,
	}))
	banner = text({ Size = UDim2.fromScale(1, 1), Visible = false, max = 48, outline = 5, Parent = bannerHolder })
	new("UIScale", { Parent = banner })
end

-- ---------- панели

-- ---------- Вкладки в стиле «Сафари-блокнот» (выбран вариант C): крафт-бумага на кольцах, заголовок
-- на скотче, животные и еда - полароиды на булавках, доход и отметки - печати, цены - ценники.
-- Картинки бумаги, скотча, кольца, ценника и булавки лежат в ReplicatedStorage.ToonWorld.Textures (ui_*)

local INK = rgb(70, 46, 30)
local INK_SOFT = rgb(128, 98, 68)
local COVER = rgb(122, 82, 52)
local STITCH = rgb(176, 136, 92)
local RULE = rgb(226, 203, 158)
local PHOTO = rgb(253, 250, 242)
local STAMP_GREEN = rgb(50, 150, 70)

local uiImages = {}
local function uiImage(name)
	if uiImages[name] == nil then
		local world = ReplicatedStorage:WaitForChild("ToonWorld")
		local plate = world:WaitForChild("Textures"):WaitForChild(name, 10)
		uiImages[name] = plate and plate.TextureID or ""
	end
	return uiImages[name]
end

-- полоска скотча цвета color
local function tape(parent, props)
	return new("ImageLabel", {
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5), Position = props.Position, Size = props.Size,
		Rotation = props.Rotation or 0, Image = uiImage("ui_tape"), ImageColor3 = props.color or rgb(255, 236, 150),
		BackgroundTransparency = 1, ZIndex = props.ZIndex or 3, Parent = parent,
	})
end

-- печать: рамка и надпись цветом чернил, чуть повернута. Возвращает надпись и рамку
local function stamp(parent, props)
	local color = props.color or STAMP_GREEN
	local z = props.ZIndex or 6
	local frame = new("Frame", {
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5), Position = props.Position, Size = props.Size,
		Rotation = props.Rotation or -8, BackgroundColor3 = rgb(250, 244, 228), BackgroundTransparency = 0.2, ZIndex = z,
		LayoutOrder = props.LayoutOrder or 0, Parent = parent,
	}, { corner(10), new("UIStroke", { Thickness = 3, Color = color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	local label = text({
		Position = UDim2.fromOffset(5, 3), Size = UDim2.new(1, -10, 1, -6), Text = props.Text or "", TextColor3 = color,
		max = props.max or 28, outline = 0, ZIndex = z + 1, Parent = frame,
	})
	return label, frame
end

-- ценник-кнопка: белая картинка с острым концом и дыркой, крашеная в color. Возвращает кнопку и надпись
local function priceTag(parent, props, onClick)
	local height = props.Size.Y.Offset
	local b = new("ImageButton", {
		AnchorPoint = props.AnchorPoint or Vector2.zero, Position = props.Position, Size = props.Size,
		Image = uiImage("ui_tag"), ImageColor3 = props.color or C.green, ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(70, 24, 296, 72), SliceScale = height / 96, BackgroundTransparency = 1,
		AutoButtonColor = false, LayoutOrder = props.LayoutOrder or 0, ZIndex = props.ZIndex or 2, Parent = parent,
	})
	local label = text({
		Position = UDim2.new(0, height * 0.62, 0, height * 0.12), Size = UDim2.new(1, -height * 0.8, 1, -height * 0.3),
		Text = props.Text or "", max = props.max or 28, outline = 3, ZIndex = (props.ZIndex or 2) + 1, Parent = b,
	})
	local scale = new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		tween(scale, 0.1, { Scale = 1.05 })
	end)
	b.MouseLeave:Connect(function()
		tween(scale, 0.1, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		tween(scale, 0.25, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		b.Activated:Connect(function()
			UI.PlaySound("click")
			onClick()
		end)
	end
	return b, label
end

-- полароид: тень, белая рамка, фото цвета color (вернется - туда кладут 3D-модельку), подпись снизу
local function polaroid(parent, props)
	local w, h = props.w, props.h
	local position = props.Position or UDim2.new(0.5, 0, 0, 10)
	local anchor = props.AnchorPoint or Vector2.new(0.5, 0)
	new("Frame", {
		AnchorPoint = anchor, Position = position + UDim2.fromOffset(4, 6), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = BLACK, BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 1, Parent = parent,
	})
	local frame = new("Frame", {
		AnchorPoint = anchor, Position = position, Size = UDim2.fromOffset(w, h), BackgroundColor3 = PHOTO,
		BorderSizePixel = 0, ZIndex = 2, Parent = parent,
	}, { stroke(3) })
	local photo = new("Frame", {
		Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -42), BackgroundColor3 = props.color or rgb(205, 200, 190),
		BorderSizePixel = 0, ZIndex = 2, Parent = frame,
	})
	local caption = text({
		Position = UDim2.new(0, 6, 1, -32), Size = UDim2.new(1, -12, 0, 26), Text = props.Text or "", TextColor3 = INK,
		max = props.max or 22, outline = 0, ZIndex = 3, Parent = frame,
	})
	return frame, photo, caption
end

-- пунктирная строчка по ширине родителя
local function stitchLine(parent, position, order)
	local line = new("Frame", {
		Position = position or UDim2.new(), Size = UDim2.new(1, 0, 0, 3), BackgroundTransparency = 1, ClipsDescendants = true,
		LayoutOrder = order or 0, Parent = parent,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 9) }) })
	for _ = 1, 60 do
		new("Frame", { Size = UDim2.fromOffset(12, 3), BackgroundColor3 = STITCH, BorderSizePixel = 0, Parent = line })
	end
	return line
end

local function makePanel(name, def)
	local w, h = def.size.X, def.size.Y
	local holder = scaled(new("Frame", {
		Name = name, AnchorPoint = def.anchor or Vector2.new(0.5, 0.5), Position = def.position or UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, Visible = false, Parent = screen,
	}))
	local frame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = holder })
	local pop = new("UIScale", { Parent = frame })
	-- тень, кожаная обложка и бумага
	new("Frame", { Position = UDim2.fromOffset(8, 12), Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.55, Parent = frame }, { corner(22) })
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = COVER, Parent = frame }, { corner(22), stroke(5) })
	local paper = new("ImageLabel", {
		Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28), Image = uiImage("ui_paper"),
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(256, 256), BackgroundColor3 = rgb(238, 218, 176), Parent = frame,
	}, { corner(14) })
	-- линейки и строчка по краю бумаги
	for y = 108, h - 70, 36 do
		new("Frame", { Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 2), BackgroundColor3 = RULE, BorderSizePixel = 0, Parent = paper })
	end
	stitchLine(paper, UDim2.fromOffset(18, 10)).Size = UDim2.new(1, -36, 0, 3)
	stitchLine(paper, UDim2.new(0, 18, 1, -14)).Size = UDim2.new(1, -36, 0, 3)
	-- кольца блокнота над верхним краем
	for x = 54, w - 54, 64 do
		new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, -26), Size = UDim2.fromOffset(28, 42),
			Image = uiImage("ui_ring"), BackgroundTransparency = 1, ZIndex = 3, Parent = frame,
		})
	end
	-- заголовок на скотче
	local tapeWidth = math.min(w - 180, 480)
	tape(frame, { Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(tapeWidth, 78), Rotation = 1.5, color = def.tape, ZIndex = 2 })
	iconLine({
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(tapeWidth - 24, 48),
		key = def.icon or "star", Text = def.title, TextColor3 = INK, max = 42, outline = 0, ZIndex = 4, Parent = frame,
	})
	-- закрыть: красная печать
	local close = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -24, 0, 22), Size = UDim2.fromOffset(58, 58),
		BackgroundColor3 = rgb(214, 64, 56), Text = "X", Font = FONT, TextScaled = true, TextColor3 = WHITE,
		AutoButtonColor = false, ZIndex = 5, Parent = frame,
	}, {
		round(), stroke(4),
		new("UITextSizeConstraint", { MaxTextSize = 30 }),
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }),
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1, ZIndex = 5, Parent = close,
	}, { round(), new("UIStroke", { Thickness = 2, Color = rgb(255, 190, 180) }) })
	local closeScale = new("UIScale", { Parent = close })
	close.MouseEnter:Connect(function()
		tween(closeScale, 0.1, { Scale = 1.1 })
	end)
	close.MouseLeave:Connect(function()
		tween(closeScale, 0.1, { Scale = 1 })
	end)
	close.Activated:Connect(function()
		UI.PlaySound("click")
		UI.ClosePanel()
	end)
	local body = new("Frame", {
		Position = UDim2.fromOffset(30, 102), Size = UDim2.new(1, -60, 1, -130), BackgroundTransparency = 1, ZIndex = 2, Parent = frame,
	})
	local panel = { holder = holder, frame = frame, pop = pop, header = frame, body = body, render = def.render, state = {} }
	panels[name] = panel
	return panel
end

local function scrollList(parent, position, size, layout)
	local scroll = new("ScrollingFrame", {
		Position = position, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 8, ScrollBarImageColor3 = STITCH, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = parent,
	}, { new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12) }) })
	layout.Parent = scroll
	return scroll
end

local function list(parent, top, bottom)
	return scrollList(parent, UDim2.fromOffset(0, top), UDim2.new(1, 0, 1, -top - (bottom or 0)),
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }))
end

-- сетка полароидов внутри списка (растет по высоте сама)
local function photoGrid(parent, order, cell)
	return new("Frame", {
		Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Parent = parent,
	}, {
		new("UIGridLayout", {
			CellSize = cell, CellPadding = UDim2.fromOffset(12, 16), SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
end

-- Food Shop: еда на полароидах, сверху скотч с редкостью, удача печатью, цена ценником
local function renderFood(panel)
	local data = State.data
	clear(panel.list)
	for i, food in ipairs(Foods) do
		local rarity = Rarities[food.rarity] or Rarities[1]
		local equipped = data.Food == food.id
		local card = new("Frame", { Size = UDim2.fromOffset(222, 360), BackgroundTransparency = 1, LayoutOrder = i, Parent = panel.list })
		local _, photo = polaroid(card, { w = 200, h = 236, Position = UDim2.new(0.5, 0, 0, 16), color = rarity.color:Lerp(WHITE, 0.55), Text = food.name, max = 24 })
		Icons.Food(photo, food.id)
		tape(card, { Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(150, 40), Rotation = (i % 2 == 0) and 3 or -3, color = rarity.color:Lerp(WHITE, 0.25), ZIndex = 4 })
		text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(130, 26), Text = string.upper(rarity.id), TextColor3 = WHITE, max = 20, outline = 2, ZIndex = 5, Parent = card })
		-- в правом нижнем углу фото, над подписью (раньше налезала на название)
		stamp(card, { Position = UDim2.new(1, -44, 0, 178), Size = UDim2.fromOffset(104, 36), Text = "Luck x" .. tostring(food.luck), max = 18, Rotation = 8, color = rgb(70, 110, 200) })
		if equipped then
			stamp(card, { Position = UDim2.new(0.5, 0, 1, -36), Size = UDim2.fromOffset(170, 50), Text = "EQUIPPED", max = 26, Rotation = -6 })
		elseif data.Foods[food.id] then
			button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(170, 50), Text = "EQUIP", color = C.green, max = 28, Parent = card }, function()
				remotes.equipFood:FireServer(food.id)
			end)
		else
			priceTag(card, {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(196, 58),
				Text = Format.Money(food.price), color = data.Cash >= food.price and C.green or C.red,
			}, function()
				remotes.buyFood:FireServer(food.id)
			end)
		end
	end
end

local function sortedAnimals(data)
	local result = {}
	for uid, animal in data.Animals do
		table.insert(result, { uid = uid, animal = animal, income = Formula.Income(animal) })
	end
	table.sort(result, function(a, b)
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.uid < b.uid
	end)
	return result
end

local function mutationLine(animal)
	local tags = {}
	if animal.m then
		table.insert(tags, string.upper(animal.m))
	end
	if animal.g then
		table.insert(tags, "BIG")
	end
	return table.concat(tags, " · ")
end

local CARD = UDim2.fromOffset(196, 252) -- клетка сетки с карточкой животного

-- карточка животного: полароид на булавке, доход печатью, мутация сверху; кнопки добавляет cardActions
local function animalCard(grid, animal, order)
	local species = Animals.ById[animal.id]
	local rarity = Rarities[species.rarity]
	local cell = new("Frame", { BackgroundTransparency = 1, LayoutOrder = order, Parent = grid })
	local _, photo = polaroid(cell, { w = 160, h = 186, Position = UDim2.new(0.5, 0, 0, 12), color = rarity.color:Lerp(WHITE, 0.5), Text = species.name })
	Icons.Animal(photo, animal, false)
	new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(28, 28),
		Image = uiImage("ui_pin"), BackgroundTransparency = 1, ZIndex = 7, Parent = cell,
	})
	stamp(cell, { Position = UDim2.new(1, -30, 0, 40), Size = UDim2.fromOffset(92, 34), Text = Format.Money(Formula.Income(animal)) .. "/s", max = 19, Rotation = 9 })
	local tags = mutationLine(animal)
	if tags ~= "" then
		text({
			Position = UDim2.fromOffset(6, 18), Size = UDim2.fromOffset(90, 22), Text = tags, Rotation = -6,
			TextColor3 = animal.m and MUTATION_COLORS[animal.m] or WHITE, max = 18, outline = 3, ZIndex = 7, Parent = cell,
		})
	end
	return cell
end

local function sectionTitle(parent, key, label, order)
	return iconLine({ Size = UDim2.new(1, -12, 0, 34), key = key, Text = label, TextColor3 = INK, align = "left", max = 25, outline = 0, LayoutOrder = order, Parent = parent })
end

local function emptyLine(parent, label, order)
	return text({ Size = UDim2.new(1, 0, 0, 56), Text = label, TextColor3 = INK_SOFT, max = 22, outline = 0, LayoutOrder = order, Parent = parent })
end

-- кнопки под карточкой: действие (или цена) и SELL. После SELL - "Sell for $X?" и YES/NO
local function cardActions(panel, cell, key, animal, action, onSell, rerender)
	local price = Formula.SellPrice(animal)
	local top = 206
	if panel.state.confirm == key then
		text({ Position = UDim2.fromOffset(0, top - 6), Size = UDim2.new(1, 0, 0, 20), Text = "Sell for " .. Format.Money(price) .. "?", TextColor3 = INK, max = 18, outline = 0, ZIndex = 3, Parent = cell })
		button({ Position = UDim2.fromOffset(6, top + 14), Size = UDim2.new(0.5, -10, 0, 32), Text = "YES", color = C.green, max = 20, Parent = cell }, function()
			panel.state.confirm = nil
			onSell()
		end)
		button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, top + 14), Size = UDim2.new(0.5, -10, 0, 32), Text = "NO", color = C.gray, max = 20, Parent = cell }, function()
			panel.state.confirm = nil
			rerender(panel)
		end)
		return
	end
	if action then
		button({ Position = UDim2.fromOffset(4, top + 6), Size = UDim2.new(0.5, -8, 0, 38), Text = action.label, color = action.color, max = 19, Parent = cell }, action.run)
	else
		text({ Position = UDim2.fromOffset(2, top + 8), Size = UDim2.new(0.5, -6, 0, 34), Text = Format.Money(price), TextColor3 = C.cash, max = 22, outline = 3, Parent = cell })
	end
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, top + 6), Size = UDim2.new(0.5, -8, 0, 38), Text = "SELL", color = C.red, max = 19, Parent = cell }, function()
		panel.state.confirm = key
		rerender(panel)
	end)
end

-- My Animals: справа, два раздела - вольер (PICK UP / SELL) и рюкзак (EQUIP / SELL)
local function renderAnimals(panel)
	local data = State.data
	local count = countKeys(data.Animals)
	panel.badge.Text = count .. "/" .. data.Slots
	clear(panel.list)

	sectionTitle(panel.list, "animals", "IN YOUR PEN  " .. count .. "/" .. data.Slots, 0)
	local pen = photoGrid(panel.list, 1, CARD)
	for i, entry in sortedAnimals(data) do
		local uid = entry.uid
		cardActions(panel, animalCard(pen, entry.animal, i), uid, entry.animal, {
			label = "PICK UP", color = C.blue, run = function()
				remotes.pickUp:FireServer(uid)
			end,
		}, function()
			remotes.sell:FireServer({ uid })
		end, renderAnimals)
	end
	if count == 0 then
		emptyLine(panel.list, "Your pen is empty", 2)
	end

	stitchLine(panel.list, nil, 999).Size = UDim2.new(1, -24, 0, 3)
	sectionTitle(panel.list, "backpack", "BACKPACK (for selling)  " .. #data.Backpack .. "/" .. Game.BACKPACK_SIZE, 1000)
	local bag = photoGrid(panel.list, 1001, CARD)
	for i, animal in data.Backpack do
		cardActions(panel, animalCard(bag, animal, i), "b" .. i, animal, {
			label = "EQUIP", color = C.green, run = function()
				remotes.equip:FireServer(i)
			end,
		}, function()
			remotes.sellBackpack:FireServer(i)
		end, renderAnimals)
	end
	if #data.Backpack == 0 then
		emptyLine(panel.list, "PICK UP animals here to sell them", 1002)
	end
	panel.equipBest.BackgroundColor3 = count + #data.Backpack > 0 and C.gold or C.gray
end

-- что можно продать: животное в руках и рюкзак. key - что отправить серверу
local function forSale(data)
	local list, total = {}, 0
	if data.Carry then
		table.insert(list, { animal = data.Carry, key = "carry" })
	end
	for i, animal in data.Backpack do
		table.insert(list, { animal = animal, key = i })
	end
	for _, entry in list do
		total += Formula.SellPrice(entry.animal)
	end
	return list, total
end

-- магазин продажи: рюкзак (животные, вынесенные из вольера) и то, что в руках
local function renderSell(panel)
	local data = State.data
	local list, total = forSale(data)
	panel.value.Text = Format.Money(total)
	panel.sellAllText.Text = "SELL ALL (" .. #list .. ")"
	panel.sellAll.ImageColor3 = #list > 0 and C.green or C.gray
	panel.count.Text = "BACKPACK  " .. #data.Backpack .. "/" .. Game.BACKPACK_SIZE
	panel.confirm.Visible = false
	clear(panel.list)
	local grid = photoGrid(panel.list, 1, CARD)
	for i, entry in list do
		local key = entry.key
		cardActions(panel, animalCard(grid, entry.animal, i), key, entry.animal, nil, function()
			remotes.sellBackpack:FireServer(key)
		end, renderSell)
	end
	if #list == 0 then
		emptyLine(panel.list, "Nothing to sell.\nPick up animals from your pen in My Animals", 2)
	end
end

-- Index: по зонам - открытка зоны и полароиды животных на скотче, ненайденные - силуэты
local function renderIndex(panel)
	local data = State.data
	clear(panel.list)
	local total, found = 0, 0
	for zoneIndex, zone in ipairs(Zones) do
		local section = new("Frame", { Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = zoneIndex, Parent = panel.list })
		local _, photo = polaroid(section, { w = 186, h = 276, AnchorPoint = Vector2.zero, Position = UDim2.fromOffset(10, 22), color = zone.ground:Lerp(WHITE, 0.15), Text = zone.name, max = 22 })
		IconAtlas.New(IconAtlas.Zone(zone), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(140, 140), ZIndex = 3, Parent = photo })
		tape(section, { Position = UDim2.fromOffset(103, 22), Size = UDim2.fromOffset(100, 30), Rotation = 4, ZIndex = 4 })
		local zoneStamp = stamp(section, { Position = UDim2.fromOffset(103, 330), Size = UDim2.fromOffset(110, 46), Text = "", max = 26, Rotation = 6 })

		local grid = new("Frame", { Position = UDim2.fromOffset(222, 0), Size = UDim2.new(1, -222, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = section }, {
			new("UIGridLayout", { CellSize = UDim2.fromOffset(152, 200), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local zoneFound = 0
		for rarityIndex = 1, #Rarities do
			local species = Animals.ByZone[zoneIndex][rarityIndex]
			if species then
				total += 1
				local isFound = data.Index[species.id] == true
				if isFound then
					zoneFound += 1
					found += 1
				end
				local rarity = Rarities[species.rarity]
				local cell = new("Frame", { BackgroundTransparency = 1, LayoutOrder = rarityIndex, Parent = grid })
				local _, pic = polaroid(cell, {
					w = 134, h = 172, Position = UDim2.new(0.5, 0, 0, 16), Text = isFound and species.name or "???", max = 20,
					color = isFound and rarity.color:Lerp(WHITE, 0.5) or rgb(205, 200, 190),
				})
				Icons.Animal(pic, { id = species.id }, not isFound)
				tape(cell, { Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(74, 24), Rotation = (rarityIndex % 2 == 0) and 6 or -5, color = isFound and rgb(255, 236, 150) or rgb(222, 222, 222), ZIndex = 4 })
			end
		end
		zoneStamp.Text = zoneFound .. " / 7"
	end
	panel.total.Text = "Unlocked: " .. found .. "/" .. total
	panel.totalFill.Size = UDim2.fromScale(math.clamp(found / math.max(total, 1), 0, 1), 1)
end

-- Shop: наклейки товаров, цена ценником, купленное - печать OWNED
local function renderStore(panel)
	clear(panel.list)
	for i, item in ipairs(Products) do
		local row = new("Frame", { Size = UDim2.new(1, -12, 0, 112), BackgroundTransparency = 1, LayoutOrder = i * 2, Parent = panel.list })
		new("Frame", { Position = UDim2.fromOffset(6, 8), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = WHITE, Parent = row }, { round(), stroke(3) })
		IconAtlas.New(item.icon or "star", { Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(84, 84), Parent = row })
		text({ Position = UDim2.fromOffset(118, 12), Size = UDim2.new(1, -340, 0, 40), Text = item.name, TextXAlignment = LEFT, TextColor3 = INK, max = 32, outline = 0, Parent = row })
		local desc = text({
			Position = UDim2.fromOffset(118, 54), Size = UDim2.new(1, -340, 0, 46), Text = item.desc, TextXAlignment = LEFT,
			TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = INK_SOFT, max = 19, outline = 0, Parent = row,
		})
		desc.TextWrapped = true
		local owned = item.kind == "pass" and player:GetAttribute("Pass_" .. item.key)
		if owned then
			stamp(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30, 0.5, 0), Size = UDim2.fromOffset(170, 58), Text = "OWNED", max = 32, Rotation = -8 })
		else
			priceTag(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(196, 64), Text = "R$ " .. item.price, color = C.green, max = 30 }, function()
				remotes.purchase:FireServer(item.key)
			end)
		end
		if i < #Products then
			stitchLine(panel.list, nil, i * 2 + 1).Size = UDim2.new(1, -24, 0, 3)
		end
	end
end

local function buildPanels()
	local food = makePanel("Food", { title = "Food Shop", icon = "food", tape = rgb(190, 230, 140), size = Vector2.new(1000, 520), render = renderFood })
	food.list = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8, ScrollBarImageColor3 = STITCH,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, Parent = food.body,
	}, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
	})

	local animals = makePanel("Animals", {
		title = "My Animals", icon = "animals", tape = rgb(190, 230, 140), size = Vector2.new(520, 610),
		anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -140, 0.5, 14), render = renderAnimals,
	})
	-- сколько животных в вольере: печать в углу
	animals.badge = stamp(animals.frame, { Position = UDim2.new(1, -86, 0, 96), Size = UDim2.fromOffset(96, 40), Text = "", max = 24, Rotation = 6 })
	animals.list = list(animals.body, 0, 78)
	-- лучшие по доходу встают в вольер, остальные уходят в рюкзак
	animals.equipBest = button({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 64),
		Text = "EQUIP BEST", color = C.gold, max = 34, Parent = animals.body,
	}, function()
		remotes.equipBest:FireServer()
	end)
	IconAtlas.New("trophy", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(60, 60), Parent = animals.equipBest })

	local sell = makePanel("Sell", { title = "Sell Animals", icon = "sell", tape = rgb(255, 190, 150), size = Vector2.new(720, 580), render = renderSell })
	local summary = new("Frame", { Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1, Parent = sell.body })
	text({ Position = UDim2.fromOffset(6, 4), Size = UDim2.new(0.5, 0, 0, 30), Text = "BACKPACK VALUE", TextXAlignment = LEFT, TextColor3 = INK_SOFT, max = 24, outline = 0, Parent = summary })
	sell.value = text({ Position = UDim2.fromOffset(6, 38), Size = UDim2.new(0.45, 0, 0, 58), TextXAlignment = LEFT, TextColor3 = C.cash, max = 54, outline = 4, Parent = summary })
	sell.count = iconLine({ Position = UDim2.fromOffset(2, 112), Size = UDim2.new(1, 0, 0, 34), key = "backpack", TextColor3 = INK, align = "left", max = 26, outline = 0, Parent = sell.body })
	stitchLine(sell.body, UDim2.fromOffset(0, 152)).Size = UDim2.new(1, 0, 0, 3)
	sell.list = list(sell.body, 160)

	-- SELL ALL спрашивает подтверждение поверх страницы: записка с красной рамкой
	local confirm = new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.4, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 10, Parent = sell.frame,
	}, { corner(22) })
	local dialog = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(540, 250), Rotation = -1.5,
		Image = uiImage("ui_paper"), ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(256, 256), ZIndex = 11, Parent = confirm,
	}, { corner(12), stroke(5, C.red) })
	tape(dialog, { Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(160, 40), Rotation = -4, ZIndex = 12 })
	sell.confirmText = text({ Position = UDim2.fromOffset(20, 30), Size = UDim2.new(1, -40, 0, 56), TextColor3 = INK, max = 38, outline = 0, ZIndex = 12, Parent = dialog })
	text({ Position = UDim2.fromOffset(20, 90), Size = UDim2.new(1, -40, 0, 28), Text = "Animals in your pen are kept", TextColor3 = INK_SOFT, max = 22, outline = 0, ZIndex = 12, Parent = dialog })
	button({ Position = UDim2.new(0, 24, 1, -86), Size = UDim2.new(0.5, -34, 0, 62), Text = "YES", color = C.green, max = 38, ZIndex = 12, Parent = dialog }, function()
		confirm.Visible = false
		remotes.sellBackpack:FireServer("all")
	end)
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 1, -86), Size = UDim2.new(0.5, -34, 0, 62), Text = "NO", color = C.gray, max = 38, ZIndex = 12, Parent = dialog }, function()
		confirm.Visible = false
	end)
	sell.confirm = confirm
	sell.sellAll, sell.sellAllText = priceTag(summary, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(300, 78), color = C.green, max = 34,
	}, function()
		local list, total = forSale(State.data)
		if #list > 0 then
			local plural = #list == 1 and " animal" or " animals"
			sell.confirmText.Text = "Sell " .. #list .. plural .. " for " .. Format.Money(total) .. "?"
			confirm.Visible = true
		end
	end)

	local index = makePanel("Index", { title = "Animal Index", icon = "index", tape = rgb(170, 215, 255), size = Vector2.new(1000, 610), render = renderIndex })
	index.list = list(index.body, 0, 70)
	local totalBar = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = COVER,
		ClipsDescendants = true, Parent = index.body,
	}, { corner(12), stroke(4) })
	index.totalFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green, BorderSizePixel = 0, Parent = totalBar }, { corner(12), gradient(C.green) })
	index.total = iconLine({ Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 44), key = "index", max = 36, outline = 4, ZIndex = 2, Parent = totalBar })

	local store = makePanel("Store", { title = "Shop", icon = "shop", tape = rgb(255, 205, 150), size = Vector2.new(800, 520), render = renderStore })
	store.list = list(store.body, 0)
end

function UI.OpenPanel(name)
	if openPanel == name then
		UI.ClosePanel()
		return
	end
	UI.ClosePanel()
	local panel = panels[name]
	if not panel or not State.Ready() then
		return
	end
	openPanel = name
	panel.state = {}
	panel.render(panel)
	panel.holder.Visible = true
	panel.pop.Scale = 0.8
	tween(panel.pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(blur, 0.3, { Size = 14 })
end

function UI.OpenedPanel()
	return openPanel
end

function UI.ClosePanel()
	if openPanel then
		panels[openPanel].holder.Visible = false
		openPanel = nil
		tween(blur, 0.2, { Size = 0 })
	end
end

function UI.Init()
	screen = new("ScreenGui", {
		Name = "GameUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	blur = new("BlurEffect", { Size = 0, Parent = workspace.CurrentCamera })
	buildHud()
	buildControls()
	buildPopups()
	buildCinema()
	buildPanels()

	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	State.OnChanged(function(payload)
		updateHud()
		if payload.TrainXP or payload.TrainLevel then
			local data = State.data
			UI.SetXP(data.TrainLevel, data.TrainXP, Formula.XPNeed(data.TrainLevel))
		end
		local panel = openPanel and panels[openPanel]
		if not panel then
			return
		end
		if openPanel == "Food" and (payload.Foods or payload.Food or payload.Cash) then
			renderFood(panel)
		elseif openPanel == "Animals" and (payload.Animals or payload.Slots or payload.Backpack) then
			-- номера в рюкзаке сдвигаются, старое подтверждение продажи уже не про то животное
			if payload.Backpack then
				panel.state.confirm = nil
			end
			renderAnimals(panel)
		elseif openPanel == "Sell" and (payload.Backpack or payload.Carry ~= nil) then
			panel.state.confirm = nil
			renderSell(panel)
		elseif openPanel == "Index" and payload.Index then
			renderIndex(panel)
		end
	end)
	player:GetAttributeChangedSignal("Income"):Connect(updateHud)
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Pass_" and openPanel == "Store" then
			renderStore(panels.Store)
		end
	end)

	Net.Event("Notify").OnClientEvent:Connect(UI.Notify)

	-- таймер удачи сервера
	task.spawn(function()
		while true do
			local left = (workspace:GetAttribute("LuckUntil") or 0) - workspace:GetServerTimeNow()
			hud.luck.Visible = left > 0
			if left > 0 then
				hud.luckText.Text = "Server Luck x2  ·  " .. Format.Time(left)
			end
			task.wait(0.5)
		end
	end)
end

return UI
