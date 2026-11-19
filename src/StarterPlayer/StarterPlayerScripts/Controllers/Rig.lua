-- Суставы R15 для поз, которые рисует клиент (турник, бросок).
-- Сустав бывает Motor6D (крутим C0) или AnimationConstraint (новые суставы аватара,
-- тогда крутим его Attachment0). Исходное значение запоминается, Reset возвращает его
local Rig = {}

-- имя сустава -> деталь персонажа, в которой он лежит
local PARTS = {
	RightShoulder = "RightUpperArm", LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm", LeftElbow = "LeftLowerArm",
	RightHip = "RightUpperLeg", LeftHip = "LeftUpperLeg",
	RightKnee = "RightLowerLeg", LeftKnee = "LeftLowerLeg",
	Waist = "UpperTorso",
	Root = "LowerTorso", -- корпус целиком относительно HumanoidRootPart: присед и разворот тела
	RightWrist = "RightHand", LeftWrist = "LeftHand",
}

local function findJoint(character, jointName)
	local part = character:FindFirstChild(PARTS[jointName])
	return part and part:FindFirstChild(jointName)
end

-- Рамки сустава: base - где сустав сидит в родительской детали (C0 или Attachment0),
-- child - где он сидит в своей детали (C1 или Attachment1). Читать до того, как сустав повернули
function Rig.Frames(character, jointName)
	local joint = findJoint(character, jointName)
	if joint and joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 and joint.Attachment1 then
		return joint.Attachment0.CFrame, joint.Attachment1.CFrame
	end
	return nil
end

local function handle(character, jointName)
	local joint = findJoint(character, jointName)
	if joint and joint:IsA("Motor6D") then
		local base = joint.C0
		return {
			set = function(rotation)
				joint.C0 = base * rotation
			end,
			reset = function()
				joint.C0 = base
			end,
		}
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		local attachment = joint.Attachment0
		local base = attachment.CFrame
		return {
			set = function(rotation)
				attachment.CFrame = base * rotation
			end,
			reset = function()
				attachment.CFrame = base
			end,
		}
	end
	return nil
end

-- { [имя] = сустав } для тех, что нашлись (у R6 их нет - поза просто не рисуется)
function Rig.Joints(character, names)
	local joints = {}
	for _, name in names do
		joints[name] = handle(character, name)
	end
	return joints
end

-- rotation в осях сустава: X - вперед/назад, Y - поворот, Z - в стороны
function Rig.Set(joints, name, rotation)
	local joint = joints[name]
	if joint then
		joint.set(rotation)
	end
end

function Rig.Reset(joints)
	for _, joint in joints do
		joint.reset()
	end
end

-- Обычные анимации персонажа (стойка) перебивают плечи новых суставов, поэтому на время позы
-- их вес почти обнуляется. update зовем каждый кадр (ловит дорожки, начатые во время позы),
-- restore возвращает прежний вес
function Rig.MuteAnimations(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local muted = {} -- [дорожка] = вес до позы
	local mute = {}
	function mute.update()
		if not animator then
			return
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			if muted[track] == nil then
				muted[track] = track.WeightTarget
				track:AdjustWeight(0.001, 0.05)
			end
		end
	end
	function mute.restore()
		for track, weight in muted do
			if track.IsPlaying then
				track:AdjustWeight(weight, 0.15)
			end
		end
		table.clear(muted)
	end
	return mute
end

return Rig
