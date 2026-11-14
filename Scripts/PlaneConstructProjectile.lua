-- Plane Construct projectile runtime.
-- The flight model follows Cannons Pack's CPProjectile: a client-side
-- raycast/integration loop with server-side impact and explosion handling.

if PCProjectile then return end

PCProjectile = class(GLOBAL_SCRIPT)
PCProjectile.projectiles = {}
PCProjectile.proj_queue = {}
PCProjectile.next_id = 0
PCProjectile.m_ref_count = 0
PCProjectile.sv_last_update = 0
PCProjectile.cl_last_update = 0

function PCProjectile.server_sendProjectile(self, shapeScript, data, projectileSettingsId)
    PCProjectile.next_id = PCProjectile.next_id + 1
    data.pcProjectileId = PCProjectile.next_id

    local dataToSend = _cpProj_ClearNetworkData(data, projectileSettingsId)
    _tableInsert(PCProjectile.proj_queue, { projectileSettingsId, shapeScript.shape, dataToSend })
end

function PCProjectile.client_loadProjectile(self, data)
    local projectileSettingsId, shape, networkData = unpack(data)
    local settings = _cpProj_CombineProjectileData(networkData, projectileSettingsId)

    local position = settings[ProjSettingEnum.position]
    local velocity = settings[ProjSettingEnum.velocity]

    if settings[ProjSettingEnum.localPosition] then
        if not _cpExists(shape) then return end
        position = shape.worldPosition + shape.worldRotation * position
    end

    if settings[ProjSettingEnum.localVelocity] then
        if not _cpExists(shape) then return end
        velocity = shape.worldRotation * velocity
    end

    local effectName = CP_ProjShellEffectEnumStrings[settings[ProjSettingEnum.shellEffect]]
    local ok, projectileEffect = pcall(_createEffect, effectName)
    if not ok then
        ok, projectileEffect = pcall(_createEffect, "NumberLogicCannon - Shell")
    end
    if not ok then return end

    projectileEffect:setPosition(position)
    projectileEffect:start()

    -- The default Smart Cannon shell effect is visual-only in Cannons Pack.
    -- Add a separate moving audio effect so every selected flight effect has
    -- an audible Doppler/thruster component, including Smart Cannon and EMP.
    local soundEffect
    local soundOk, createdSound = pcall(_createEffect, "PlaneCannon - Doppler")
    if soundOk and createdSound then
        soundEffect = createdSound
        soundEffect:setPosition(position)
        local speed = math.min(200, math.max(1, velocity:length()))
        soundEffect:setParameter("velocity", speed)
        soundEffect:setParameter("power", speed)
        soundEffect:start()
    end

    local projectile = {
        owner = self,
        id = networkData.pcProjectileId,
        effect = projectileEffect,
        sound = soundEffect,
        pos = position,
        dir = velocity,
        alive = settings[ProjSettingEnum.lifetime],
        grav = settings[ProjSettingEnum.gravity],
        friction = settings[ProjSettingEnum.friction],
        syncEffect = settings[ProjSettingEnum.syncEffect],
        keepEffect = CP_ProjShouldKeepEffect[settings[ProjSettingEnum.shellEffect]],
        hit = nil,
        hitSent = false
    }

    PCProjectile.projectiles[#PCProjectile.projectiles + 1] = projectile
end

local pcXAxis = _newVec(1, 0, 0)

local function pcUpdateEffect(projectile)
    if projectile.syncEffect then
        projectile.effect:setPosition(projectile.pos)
    end

    if projectile.dir:length() > 0.0001 then
        projectile.effect:setRotation(_getVec3Rotation(pcXAxis, projectile.dir))
    end

    if projectile.sound and _cpExists(projectile.sound) then
        projectile.sound:setPosition(projectile.pos)
        local speed = math.min(200, math.max(1, projectile.dir:length()))
        projectile.sound:setParameter("velocity", speed)
        projectile.sound:setParameter("power", speed)
    end
end

local function pcFinishEffect(projectile)
    if projectile.effect and _cpExists(projectile.effect) then
        if projectile.keepEffect then
            projectile.effect:stop()
            projectile.effect:setPosition(_newVec(0, 0, 10000))
        else
            projectile.effect:stopImmediate()
            projectile.effect:destroy()
        end
    end

    if projectile.sound and _cpExists(projectile.sound) then
        projectile.sound:stopImmediate()
        projectile.sound:destroy()
    end
end

function PCProjectile.client_onScriptUpdate(self, dt)
    for index, projectile in pairs(PCProjectile.projectiles) do
        if projectile then
            if projectile.hit then
                if not projectile.hitSent and _cpExists(projectile.owner) then
                    projectile.hitSent = true
                    projectile.owner.network:sendToServer("server_projectileHit", {
                        id = projectile.id,
                        position = projectile.hit
                    })
                end
                PCProjectile.projectiles[index] = nil
            else
                projectile.alive = projectile.alive - dt
                projectile.dir = projectile.dir * (1 - projectile.friction) - _newVec(0, 0, projectile.grav * dt)

                local nextPosition = projectile.pos + projectile.dir * dt * 1.2
                local hit, result = _physRaycast(projectile.pos, nextPosition)

                if hit then
                    projectile.hit = result.pointWorld
                elseif projectile.alive <= 0 then
                    projectile.hit = projectile.pos + projectile.dir * dt
                else
                    projectile.pos = projectile.pos + projectile.dir * dt
                    pcUpdateEffect(projectile)
                end

                if projectile.hit then
                    pcFinishEffect(projectile)
                end
            end
        end
    end
end

function PCProjectile.server_onScriptUpdate(self, _)
    for index, data in pairs(PCProjectile.proj_queue) do
        self.network:sendToClients("client_loadProjectile", data)
        PCProjectile.proj_queue[index] = nil
    end
end

function PCProjectile.client_onScriptDestroy(self)
    for _, projectile in pairs(PCProjectile.projectiles) do
        if projectile and projectile.effect and _cpExists(projectile.effect) then
            projectile.effect:stopImmediate()
            projectile.effect:destroy()
        end
        if projectile and projectile.sound and _cpExists(projectile.sound) then
            projectile.sound:stopImmediate()
            projectile.sound:destroy()
        end
    end
    PCProjectile.projectiles = {}
    PCProjectile.proj_queue = {}
end

_CP_gScript.PCProjectile = PCProjectile
