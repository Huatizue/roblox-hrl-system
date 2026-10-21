--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HomingMissile")
local Config = require(Shared.Config)
local Targets = require(Shared.Targets)

local Warhead = {}

local function damageAt(distance: number): number
	local fraction = math.clamp(distance / Config.BlastRadius, 0, 1)
	local scale = 1 + (Config.MinDamageFraction - 1) * fraction
	return Config.MaxDamage * scale
end

local function isOccluded(from: Vector3, part: BasePart, victim: Instance): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { victim }
	return workspace:Raycast(from, part.Position - from, params) ~= nil
end

local function tagCreator(humanoid: Humanoid, owner: Player)
	local existing = humanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = owner
	tag.Parent = humanoid
	game:GetService("Debris"):AddItem(tag, 2)
end

function Warhead.detonate(position: Vector3, owner: Player)
	local closest: { [Instance]: { part: BasePart, distance: number } } = {}

	for _, part in workspace:GetPartBoundsInRadius(position, Config.BlastRadius) do
		local victim: Instance? = Targets.fromPart(part)
		if not victim then
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				victim = model
			end
		end
		if victim then
			local distance = (part.Position - position).Magnitude
			local best = closest[victim]
			if not best or distance < best.distance then
				closest[victim] = { part = part, distance = distance }
			end
		end
	end

	for victim, info in closest do
		if isOccluded(position, info.part, victim) then
			continue
		end
		local damage = damageAt(info.distance)

		local humanoid = victim:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local victimPlayer = game:GetService("Players"):GetPlayerFromCharacter(victim)
			if victimPlayer ~= owner or Config.DamageOwner then
				tagCreator(humanoid, owner)
				humanoid:TakeDamage(damage)
			end
		end

		local health = victim:GetAttribute("Health")
		if typeof(health) == "number" then
			local remaining = if victim:GetAttribute("DestroyOnHit") then 0 else math.max(health - damage, 0)
			victim:SetAttribute("LastHitBy", owner.UserId)
			victim:SetAttribute("LastHitPosition", position)
			victim:SetAttribute("Health", remaining)
		end
	end
end

return Warhead
