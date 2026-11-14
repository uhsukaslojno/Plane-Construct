dofile("$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua")

HornFoamExtinguisher = class()

HornFoamExtinguisher.maxParentCount = 1
HornFoamExtinguisher.maxChildCount = 0
HornFoamExtinguisher.connectionInput = sm.interactable.connectionType.logic
HornFoamExtinguisher.connectionOutput = sm.interactable.connectionType.none
HornFoamExtinguisher.colorNormal = sm.color.new(0x6238f7ff)
HornFoamExtinguisher.colorHighlight = sm.color.new(0x8d6cffff)

local FIXED_TICKS_PER_SECOND = 40.0
local SHOTS_PER_SECOND = 20.0
local FIRE_VELOCITY = 30.0
local MUZZLE_POSITION = sm.vec3.new(0.0, 0.0, 0.125)
local FORWARD = sm.vec3.new(0.0, 0.0, 1.0)
local FIRST_SHOT_SPREAD = 0.25
local SUSTAINED_SPREAD = 24.0

function HornFoamExtinguisher.server_onCreate(self)
    self:sv_reset()
end

function HornFoamExtinguisher.server_onRefresh(self)
    self:sv_reset()
end

function HornFoamExtinguisher.sv_reset(self)
    self.sv = {
        shotProgress = 1.0,
        wasActive = false
    }
end

function HornFoamExtinguisher.server_onFixedUpdate(self, _)
    local parent = self.interactable:getSingleParent()
    local active = parent ~= nil and parent:isActive()

    if active then
        self.sv.shotProgress = self.sv.shotProgress + SHOTS_PER_SECOND / FIXED_TICKS_PER_SECOND
    else
        self.sv.shotProgress = 1.0
    end

    if active and self.sv.shotProgress >= 1.0 then
        local spread = self.sv.wasActive and SUSTAINED_SPREAD or FIRST_SHOT_SPREAD
        local direction = sm.noise.gunSpread(FORWARD, spread)

        sm.projectile.shapeFire(
            self.shape,
            projectile_foam,
            MUZZLE_POSITION,
            direction * FIRE_VELOCITY,
            0
        )

        self.sv.shotProgress = self.sv.shotProgress - 1.0
    end

    if active ~= self.sv.wasActive then
        self.network:sendToClients("cl_setActive", active)
    end

    self.sv.wasActive = active
end

function HornFoamExtinguisher.client_onCreate(self)
    self.cl = {
        active = false,
        sprayEffect = sm.effect.createEffect("Foamgun - Muzzlesplash", self.interactable),
        sprayAudio = nil
    }
    self.cl.sprayEffect:setOffsetPosition(MUZZLE_POSITION)
end

function HornFoamExtinguisher.client_onDestroy(self)
    if self.cl and self.cl.sprayEffect then
        self.cl.sprayEffect:destroy()
    end
    if self.cl and self.cl.sprayAudio then
        self.cl.sprayAudio:destroy()
    end
end

function HornFoamExtinguisher.cl_startSprayAudio(self)
    if self.cl.sprayAudio then
        self.cl.sprayAudio:destroy()
    end

    self.cl.sprayAudio = sm.effect.createEffect("Foamgun - Muzzlesplash_audio", self.interactable)
    self.cl.sprayAudio:setOffsetPosition(MUZZLE_POSITION)
    self.cl.sprayAudio:start()
end

function HornFoamExtinguisher.cl_setActive(self, active)
    self.cl.active = active

    if active then
        if not self.cl.sprayEffect:isPlaying() then
            self.cl.sprayEffect:start()
        end
        self:cl_startSprayAudio()
    elseif self.cl.sprayEffect:isPlaying() then
        self.cl.sprayEffect:stop()
    end

    if not active and self.cl.sprayAudio then
        self.cl.sprayAudio:stopBreakSustain()
    end
end
