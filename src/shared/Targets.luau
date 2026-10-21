--!strict

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local Targets = {}

export type VelocitySample = {
	time: number,
	position: Vector3,
}

function Targets.getPosition(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

function Targets.measureVelocity(
	estimate: Vector3,
	sample: VelocitySample?,
	position: Vector3,
	now: number
): (Vector3, VelocitySample?)
	if not sample then
		return estimate, { time = now, position = position }
	end
	local elapsed = now - sample.time
	if elapsed < Config.TargetVelocityWindow then
		return estimate, sample
	end
	local measured = (position - sample.position) / elapsed
	return estimate:Lerp(measured, 0.5), { time = now, position = position }
end

function Targets.getPhysicsVelocity(target: Instance): Vector3?
	local part: BasePart? = if target:IsA("BasePart")
		then target
		elseif target:IsA("Model") then target.PrimaryPart
		else nil
	if part and not part.Anchored then
		return part.AssemblyLinearVelocity
	end
	return nil
end

function Targets.isTarget(instance: Instance): boolean
	return CollectionService:HasTag(instance, Config.TargetTag) and instance:IsDescendantOf(workspace)
end

function Targets.fromPart(part: Instance): Instance?
	local current: Instance? = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, Config.TargetTag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

function Targets.all(): { Instance }
	local result = {}
	for _, instance in CollectionService:GetTagged(Config.TargetTag) do
		if instance:IsDescendantOf(workspace) then
			table.insert(result, instance)
		end
	end
	return result
end

return Targets
