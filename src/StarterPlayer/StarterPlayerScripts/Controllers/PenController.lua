local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local State = require(script.Parent.State)
local ThrowController = require(script.Parent.ThrowController)
local UI = require(script.Parent.UI)

local placeCarry = Net.Event("PlaceCarry")

-- Пойманное животное в руках: курсором выбираешь место в своем вольере
-- (под курсором круг на земле) и кликаешь. Никаких кнопок.
local PenController = {}

local PEN_MARGIN = 2.5
local RAY_LENGTH = 400

local marker
local target -- точка в вольере под курсором

local function myPen()
	local index = player:GetAttribute("Plot")
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	return index and plots and plots:FindFirstChild("Plot" .. index)
end

-- точка пола своего вольера по лучу из камеры
local function penPoint(ray)
	local pen = myPen()
	-- пол лежит в папке Pen и пересоздается, когда вольер растет
	local floor = pen and pen:FindFirstChild("Floor", true)
	if not floor then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { floor }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	if not hit then
		return nil
	end
	-- клик у самого забора: ставим чуть внутрь, а не молча ничего не делаем
	local center, half = pen:GetAttribute("Center"), pen:GetAttribute("Half")
	local offset = hit.Position - center
	local limit = half - PEN_MARGIN
	return Vector3.new(center.X + math.clamp(offset.X, -limit, limit), hit.Position.Y, center.Z + math.clamp(offset.Z, -limit, limit))
end

local function makeMarker()
	local part = Instance.new("Part")
	part.Name = "PlaceMarker"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.12, 5, 5)
	part.Color = Color3.fromRGB(255, 232, 180)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0.25
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local hintAt = -math.huge

local function place(point)
	if not State.data.Carry or ThrowController.Following() then
		return
	end
	if point then
		placeCarry:FireServer(point)
	elseif os.clock() - hintAt > 2 then
		-- кликнули мимо вольера: подсказываем, куда кликать
		hintAt = os.clock()
		UI.Notify("Click on the grass inside your pen", "info", "animals")
	end
end

-- после поимки сервер переносит игрока к вольеру лицом ко входу,
-- ставим камеру за спину, чтобы вольер был впереди
local function faceThePen()
	local started = os.clock()
	while ThrowController.Following() and os.clock() - started < 6 do
		task.wait(0.05)
	end
	local view = ThrowController.PenView()
	if view then
		camera.CameraType = Enum.CameraType.Custom
		camera.CFrame = view
	end
end

function PenController.Init()
	marker = makeMarker()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not State.data.Carry then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			place(target)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			-- на телефоне ставим туда, куда тапнули
			local position = input.Position
			place(penPoint(camera:ScreenPointToRay(position.X, position.Y)))
		end
	end)

	local hadCarry = false
	State.OnChanged(function(payload)
		if payload.Carry == nil then
			return
		end
		local has = payload.Carry and true or false
		-- только после поимки (камера еще показывает животное)
		if has and not hadCarry and ThrowController.ThrewRecently() then
			task.spawn(faceThePen)
		end
		hadCarry = has
	end)

	RunService.RenderStepped:Connect(function()
		target = nil
		if State.data.Carry then
			local mouse = UserInputService:GetMouseLocation()
			target = penPoint(camera:ViewportPointToRay(mouse.X, mouse.Y))
		end
		if target then
			marker.CFrame = CFrame.new(target + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			marker.Parent = workspace
		else
			marker.Parent = nil
		end
	end)
end

return PenController
