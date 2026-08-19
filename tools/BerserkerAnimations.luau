--!strict
--[[
	BerserkerAnimations — source of truth for the Berserker's keyframed swings.

	This file is NOT synced into the game. It builds KeyframeSequence instances
	that get uploaded as animation assets (CGS Student Development group); the
	uploaded ids live in AnimationConfig. To revise a swing: edit the poses
	here, preview via the command bar (RegisterKeyframeSequence gives a local
	id), re-upload, paste the new id.

	Conventions (match FXController's procedural poses, verified on live rigs):
	  Pose name = the PART the joint drives (RightUpperArm = shoulder,
	  UpperTorso = waist, LowerTorso = root).
	  Shoulder X: negative = wound back/up behind the head, positive = swung
	  down in front. Waist Y: positive = twist right.
]]

local D = math.rad

-- part -> parent part, R15.
local PARENT = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg",
}

local function keyframe(t: number, style: Enum.PoseEasingStyle, dir: Enum.PoseEasingDirection, cframes: { [string]: CFrame }): Keyframe
	local kf = Instance.new("Keyframe")
	kf.Time = t
	local poses: { [string]: Pose } = {}
	local function ensure(name: string): Pose
		local found = poses[name]
		if found then
			return found
		end
		local p = Instance.new("Pose")
		p.Name = name
		p.CFrame = cframes[name] or CFrame.identity
		p.EasingStyle = style
		p.EasingDirection = dir
		poses[name] = p
		if name ~= "HumanoidRootPart" then
			ensure(PARENT[name]):AddSubPose(p)
		else
			kf:AddPose(p)
		end
		return p
	end
	for name in pairs(cframes) do
		ensure(name)
	end
	ensure("HumanoidRootPart")
	return kf
end

local function sequence(name: string, frames: { Keyframe }): KeyframeSequence
	local ks = Instance.new("KeyframeSequence")
	ks.Name = name
	ks.Loop = false
	ks.Priority = Enum.AnimationPriority.Action
	for _, kf in ipairs(frames) do
		kf.Parent = ks
	end
	return ks
end

local Anims = {}

--[[
	Step 3: the GIF swing. Slow rise to a high wind-up behind the head, a
	beat of anticipation at the apex, then a violent full-body slam into a
	crouched follow-through, and a slow recover.
]]
function Anims.Crash(): KeyframeSequence
	return sequence("BerserkerCrash", {
		keyframe(0.00, Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.Out, {
			LowerTorso = CFrame.new(0, -0.05, 0) * CFrame.Angles(D(-3), 0, 0),
			UpperTorso = CFrame.Angles(D(-5), D(8), 0),
			RightUpperArm = CFrame.Angles(D(-25), 0, D(-8)),
			LeftUpperArm = CFrame.Angles(D(-10), 0, D(8)),
		}),
		-- wind-up apex
		keyframe(0.42, Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out, {
			LowerTorso = CFrame.new(0, -0.12, 0) * CFrame.Angles(D(8), D(6), 0),
			UpperTorso = CFrame.Angles(D(-18), D(28), D(-6)),
			Head = CFrame.Angles(D(12), D(-14), 0),
			RightUpperArm = CFrame.Angles(D(-140), 0, D(-18)),
			RightLowerArm = CFrame.Angles(D(-32), 0, 0),
			RightHand = CFrame.Angles(D(-30), 0, 0),
			LeftUpperArm = CFrame.Angles(D(-48), 0, D(28)),
			LeftLowerArm = CFrame.Angles(D(-20), 0, 0),
			RightUpperLeg = CFrame.Angles(D(-12), 0, 0),
			LeftUpperLeg = CFrame.Angles(D(9), 0, 0),
		}),
		-- anticipation beat: tiny extra rise so the slam has a still moment to leave from
		keyframe(0.56, Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.InOut, {
			LowerTorso = CFrame.new(0, -0.10, 0) * CFrame.Angles(D(9), D(7), 0),
			UpperTorso = CFrame.Angles(D(-20), D(31), D(-6)),
			Head = CFrame.Angles(D(13), D(-15), 0),
			RightUpperArm = CFrame.Angles(D(-146), 0, D(-19)),
			RightLowerArm = CFrame.Angles(D(-34), 0, 0),
			RightHand = CFrame.Angles(D(-34), 0, 0),
			LeftUpperArm = CFrame.Angles(D(-50), 0, D(29)),
			LeftLowerArm = CFrame.Angles(D(-21), 0, 0),
			RightUpperLeg = CFrame.Angles(D(-13), 0, 0),
			LeftUpperLeg = CFrame.Angles(D(10), 0, 0),
		}),
		-- SLAM
		keyframe(0.66, Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.In, {
			LowerTorso = CFrame.new(0, -0.55, 0) * CFrame.Angles(D(-12), D(-4), 0),
			UpperTorso = CFrame.Angles(D(48), D(-12), D(4)),
			Head = CFrame.Angles(D(-16), 0, 0),
			RightUpperArm = CFrame.Angles(D(55), 0, D(10)),
			RightLowerArm = CFrame.Angles(D(25), 0, 0),
			RightHand = CFrame.Angles(D(85), 0, 0),
			LeftUpperArm = CFrame.Angles(D(50), 0, D(-16)),
			LeftLowerArm = CFrame.Angles(D(20), 0, 0),
			RightUpperLeg = CFrame.Angles(D(-34), 0, 0),
			RightLowerLeg = CFrame.Angles(D(38), 0, 0),
			LeftUpperLeg = CFrame.Angles(D(-24), 0, 0),
			LeftLowerLeg = CFrame.Angles(D(30), 0, 0),
		}),
		-- follow-through settle
		keyframe(0.82, Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out, {
			LowerTorso = CFrame.new(0, -0.50, 0) * CFrame.Angles(D(-10), D(-5), 0),
			UpperTorso = CFrame.Angles(D(42), D(-14), D(3)),
			Head = CFrame.Angles(D(-12), 0, 0),
			RightUpperArm = CFrame.Angles(D(26), 0, D(9)),
			RightLowerArm = CFrame.Angles(D(20), 0, 0),
			RightHand = CFrame.Angles(D(75), 0, 0),
			LeftUpperArm = CFrame.Angles(D(42), 0, D(-14)),
			LeftLowerArm = CFrame.Angles(D(16), 0, 0),
			RightUpperLeg = CFrame.Angles(D(-30), 0, 0),
			RightLowerLeg = CFrame.Angles(D(34), 0, 0),
			LeftUpperLeg = CFrame.Angles(D(-20), 0, 0),
			LeftLowerLeg = CFrame.Angles(D(26), 0, 0),
		}),
		-- recover
		keyframe(1.10, Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.InOut, {
			LowerTorso = CFrame.new(0, -0.05, 0) * CFrame.Angles(D(-3), 0, 0),
			UpperTorso = CFrame.Angles(D(-5), D(8), 0),
			RightUpperArm = CFrame.Angles(D(-25), 0, D(-8)),
			LeftUpperArm = CFrame.Angles(D(-10), 0, D(8)),
		}),
	})
end

return Anims
