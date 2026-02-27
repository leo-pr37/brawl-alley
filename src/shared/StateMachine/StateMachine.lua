-- ReplicatedStorage/StateMachine/StateMachine.lua
-- Handles transitions and updates for a single entity
local AnimationLibrary = require(game.ReplicatedStorage.Shared.StateMachine.AnimationLibrary)

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(entity, config)
	local self = setmetatable({}, StateMachine)
	self.entity = entity
	self.config = config
	self.state = "Idle"
	self.stateTimer = 0
	self.cooldowns = {}
	return self
end

function StateMachine:changeState(newState)
	if self.state == newState then return end

	local oldState = self.state
	local oldConfig = self.config[oldState]
	local newConfig = self.config[newState]

	if oldConfig and oldConfig.Exit then
		oldConfig.Exit(self.entity)
	end

	self.state = newState
	self.stateTimer = 0

	print("[StateMachine]", self.entity.Name, "changed from", oldState, "→", newState)

	if newConfig and newConfig.Enter then
		newConfig.Enter(self.entity)
	end


	-- Play animation automatically
	self:_playAnimation(newState)
end


function StateMachine:update(dt)
	self.stateTimer += dt
	local currentConfig = self.config[self.state]
	if currentConfig and currentConfig.Update then
		currentConfig.Update(self.entity, dt)
	end
end

function StateMachine:tickCooldowns(dt)
	for key, time in pairs(self.cooldowns) do
		self.cooldowns[key] = math.max(0, time - dt)
	end
end


-- Helper: get or create Animator
function StateMachine:_getAnimator()
	local humanoid = self.entity:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator
end

-- Helper: play animation by state
function StateMachine:_playAnimation(stateName)
	local animator = self:_getAnimator()
	if not animator then return end

	-- Determine entity type (assume "NPC" for NPCs; can extend for Players)
	local entityType = self.entity:FindFirstChildOfClass("Humanoid") and "NPC" or "Player"
	local animId = AnimationLibrary[entityType] and AnimationLibrary[entityType][stateName]
	if not animId then return end


	-- Load and play the animation
	if not self.animCache then self.animCache = {} end
	if not self.animCache[stateName] then
		local anim = Instance.new("Animation")
		anim.AnimationId = animId.id
		self.animCache[stateName] = animator:LoadAnimation(anim)
	end

	local track = self.animCache[stateName]
	if track then
		track:Play()
	end
end


return StateMachine