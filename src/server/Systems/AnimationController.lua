--// AnimationController.lua
local AnimationController = {}
local AnimationLibrary = require(game.ReplicatedStorage.Shared.StateMachine.AnimationLibrary)

-- [entity] = { [animationName] = AnimationTrack }
local loadedAnimations = {}

function AnimationController.loadAnimations(entity, entityType)
	if not entity or not entity:FindFirstChildOfClass("Humanoid") then return end
	local humanoid = entity:FindFirstChildOfClass("Humanoid")

	local library = AnimationLibrary[entityType]
	if not library then
		warn("[AnimationController] No animation set for entity type:", entityType)
		return
	end

	loadedAnimations[entity] = {}

	for stateName, assetId in pairs(library) do
		local anim = Instance.new("Animation")
		anim.AnimationId = assetId.id

		local track = humanoid:LoadAnimation(anim)
		loadedAnimations[entity][stateName] = track
	end
end

function AnimationController.play(entity, stateName)
	local anims = loadedAnimations[entity]
	if anims and anims[stateName] then
		anims[stateName]:Play()
	end
end

function AnimationController.stop(entity, stateName)
	local anims = loadedAnimations[entity]
	if anims and anims[stateName] then
		anims[stateName]:Stop()
	end
end

function AnimationController.stopAll(entity)
	local anims = loadedAnimations[entity]
	if anims then
		for _, track in pairs(anims) do
			track:Stop()
		end
	end
end

function AnimationController.cleanup(entity)
	loadedAnimations[entity] = nil
end

return AnimationController
