----------------------------------------------------
-- 操作编辑器：座椅侧集成
-- Copyright (c) 2026 APxiaosong & Nyako. All rights reserved.
-- 座椅是座椅输入的唯一写入者。这里提供给座椅脚本显式调用的接口：
--   onSeatCreate       座椅创建时登记能力并清理陈旧共享状态
--   onClientInput      座椅客户端上报玩家输入变化（用于录制并维护玩家镜像）
--   serverReceiveInput 座椅服务端接收上报：更新玩家镜像并投递录制信箱
--   applyToSeat        座椅服务端每帧把玩家输入或回放输入合并后写回座椅
--   onSeatGone         座椅销毁或卸载时清理（两条路径需要完全相同的收尾）
--   shouldReleaseUse   回放中按 Use 时放行，让玩家仍能离座
-- 编辑器与座椅只通过 AEManager 通信，彼此不持有对方的脚本对象，也不做方法包装。
----------------------------------------------------

local M = {}

local EDITOR_UUID = "49524f50-0511-8000-0331-6b6167757961"
local EMPTY_CHANNEL = {}
local EMPTY_PLAYER = { steering = {}, logic = {} }

-- ---------- 编辑器识别与查找 ----------

local function isEditorPart( interactable )
    if not interactable or not sm.exists( interactable ) then return false end
    local ok, uuid = pcall( function() return tostring( interactable:getShape():getShapeUuid() ) end )
    return ok and uuid == EDITOR_UUID
end

local function findEditorIds( seat )
    local out = {}
    if not seat.interactable then return out end
    local children = seat.interactable:getChildren( sm.interactable.connectionType.seated )
    for _, child in ipairs( children or {} ) do
        if isEditorPart( child ) then
            out[#out + 1] = child.id
        end
    end
    return out
end

local function isOwnEditor( seat, editorId )
    for _, id in ipairs( findEditorIds( seat ) ) do
        if id == editorId then return true end
    end
    return false
end

-- ---------- 座椅输入上报（客户端 → 服务端） ----------

function M.onClientInput( seat, action, state, consumeAction )
    -- 座椅没有消费的输入不属于录制范围。
    if not consumeAction then return end
    local info = AEInput.classify( action )
    if not info then return end
    -- 逻辑键只有在座椅确实把它接成逻辑输出时才录制；否则空格只是站起之类的无关动作。
    if info.channel == AEInput.LOGIC then
        if info.key == "space" and not seat.spaceLogic then return end
        if info.key == "leftClick" and not seat.leftClickLogic then return end
        if info.key == "rightClick" and not seat.rightClickLogic then return end
    end

    -- onAction 是边沿触发（按下 / 松开各一次），无需在客户端去重；
    -- 直接上报每次状态变化，离座再坐下也不会因残留去重表而漏掉首次输入。
    for _, editorId in ipairs( findEditorIds( seat ) ) do
        seat.network:sendToServer( "sv_aeInput", {
            editorId = editorId,
            action = action,
            state = state == true
        } )
    end
end

function M.serverReceiveInput( seat, data, player )
    if type( data ) ~= "table" or not seat.interactable then return end
    local action = tonumber( data.action )
    local info = action and AEInput.classify( action ) or nil
    if not info then return end

    -- 只接受当前落座者的上报（按下与松开一视同仁），拦下非落座玩家伪造或迟到的输入：
    -- 伪造的按下会污染录制、让回放方向卡住；伪造的松键会压掉新乘员刚按下的状态、提前截断录制片段。
    -- 玩家按住键直接离座导致的松键缺失，由 applyToSeat 检测乘员变化时统一合成，不靠放行未鉴权的松键兜底。
    local rider = seat.interactable:getSeatCharacter()
    if not rider or rider:getPlayer() ~= player then return end

    local state = data.state == true

    -- 维护玩家输入镜像，供回放期间与回放通道的期望输入做“或”合并。快捷栏不进入镜像：玩家自身的快捷栏
    -- 由座椅原生逻辑在客户端直接触发，回放合并不使用它（见 applyItems），维护它只会留下不再被读取的状态。
    if info.channel ~= AEInput.ITEM then
        if not seat.aePlayer then
            seat.aePlayer = { steering = {}, logic = {} }
        end
        seat.aePlayer[info.channel][info.key] = state
    end

    -- 投递到录制信箱；是否真正写入，由编辑器服务端根据当前是否在录制来决定。附上 seatId 是为了让编辑器能校验来源，
    -- 附上当前帧是为了让录制的帧戳以到达座椅的时刻为准，不因编辑器下一拍才排空信箱而被压成同一帧。
    -- editorId 必须是本座椅下挂接的编辑器：伪造的 id 永远不会被任何编辑器取走，不拦截就会在信箱中无限堆积。
    if data.editorId and isOwnEditor( seat, data.editorId ) then
        AEManager.pushInput( data.editorId, {
            action = action,
            state = state,
            seatId = seat.interactable.id,
            t = AEManager.currentTick()
        } )
    end
end

-- ---------- 回放合并与写回（服务端） ----------

local function applySeatItem( seat, index, state )
    local interactables = seat.interactable:getSeatInteractables()
    -- getSeatInteractables 的下标从 1 开始，pressSeatInteractable 的下标从 0 开始：校验时取 index + 1，操作时传 index。
    local child = interactables and interactables[index + 1] or nil
    -- 槽位空缺，或者连接的是编辑器本身：没有可操作的对象，返回 nil 让上层收敛，不必每帧重试。
    if not child or not sm.exists( child ) or isEditorPart( child ) then return nil end

    -- 这个 API 在少数非预期目标上会抛错；把错误限制在单个槽位，避免整次回放崩溃。
    local ok, result
    if state then
        ok, result = pcall( function() return seat.interactable:pressSeatInteractable( index ) end )
    else
        ok, result = pcall( function() return seat.interactable:releaseSeatInteractable( index ) end )
    end
    return ok and result ~= false
end

-- 玩家乘坐回放座椅时，转向标志有两个写入者：本函数（服务端），以及玩家原生 client_onAction 里的
-- set / unsetSteeringFlag。如果使用差分缓存，当玩家松开某个回放也需要的方向时会清除标志，而缓存
-- 仍会认为该方向处于按住状态，导致回放方向无法恢复。set / unsetSteeringFlag 是幂等的电平操作，因此回放期间
-- 每帧都无条件重申期望；标志被玩家清除后，下一帧就会重新写入。
local function applySteering( seat, player, playback, onLift )
    local pb = playback and playback.steering or EMPTY_CHANNEL
    local pl = player.steering
    for _, key in ipairs( AEInput.STEERING_KEYS ) do
        if pl[key] == true or ( pb[key] == true and not onLift ) then
            seat.interactable:setSteeringFlag( AEInput.steeringFlag( key ) )
        else
            seat.interactable:unsetSteeringFlag( AEInput.steeringFlag( key ) )
        end
    end
end

-- 快捷栏是触发语义（pressSeatInteractable 不幂等，重复按会让开关反复切换），无法像转向那样每帧重申，
-- 只能采用差分。这里只把回放通道写回座椅，不合并玩家镜像：玩家自身的快捷栏由座椅原生逻辑在客户端
-- 直接触发，如果服务端按照镜像再执行一次，同一次拨动就会被执行两遍，开关型部件先被翻转、随即又被
-- 翻回，等于没有生效。差分的代价是：如果玩家按下又松开了回放正按住的同一个快捷栏，该槽位在本段回放
-- 剩余的时间里会失效。SM 不提供快捷栏状态的查询接口，这是该通道固有的限制。
-- 返回是否仍有未收敛的差异：回放结束后的清理帧据此决定能否丢弃差分缓存，释放失败的残留才有机会重试。
local function applyItems( seat, playback, onLift )
    local pb = playback and playback.item or EMPTY_CHANNEL
    local pending = false
    for index = 0, 9 do
        local want = pb[index] == true and not onLift
        -- 差分缓存里的 nil 是未知态：本系统从未按下过该槽位，视作与“未按”一致，
        -- 首帧才不会对时间线之外的槽位发起释放、打断玩家自己按住的部件。
        if ( seat.aeApplied.item[index] or false ) ~= want then
            local result = applySeatItem( seat, index, want )
            -- result 为 false：有目标但调用失败，无论按下还是松开都保留差异，留到下一帧重试，不把未完成的操作当作已达成；
            -- result 为 nil：暂时没有可操作目标；想按下就保留差异，等目标出现后再按；想松开的话本来就是松开态，直接收敛；
            -- result 为 true：操作成功，直接收敛。
            if result ~= false and not ( result == nil and want ) then
                seat.aeApplied.item[index] = want
            else
                pending = true
            end
        end
    end
    return pending
end

-- 逻辑键写入的是用座椅 id 拼接出来的全局标志，由 Seat Logic Breakout 部件消费。座椅原生的 sv_setGlobalFlag
-- 与本函数并行写同一个 _G 键；赋值是幂等的，因此回放期间每帧都无条件重申，避免玩家松键时把它清成低电平。
local function applyLogic( seat, player, playback, onLift )
    local pb = playback and playback.logic or EMPTY_CHANNEL
    local pl = player.logic
    local seatId = seat.interactable.id
    for _, key in ipairs( AEInput.LOGIC_KEYS ) do
        _G[seatId .. key] = pl[key] == true or ( pb[key] == true and not onLift )
    end
end

-- 乘坐者离开时替他补上仍按住的键的松键：离座瞬间客户端不再发送松键包，迟到的松键包又会被
-- 乘员鉴权拦下，录制里这些按住只能由服务端在此闭合，否则片段会一直延长到停止录制的时刻。
-- 只投给当前的录制占用者：没有录制在进行时，释放事件没有任何消费者。
local function releaseHeldInput( seat )
    local mirror = seat.aePlayer
    if not mirror then return end
    local editorId = AEManager.getRecordingOwner( seat.interactable.id )
    if not editorId then return end
    local t = AEManager.currentTick()
    for channel, keys in pairs( mirror ) do
        for key, held in pairs( keys ) do
            if held then
                AEManager.pushInput( editorId, {
                    action = AEInput.actionOf( channel, key ),
                    state = false,
                    seatId = seat.interactable.id,
                    t = t
                } )
            end
        end
    end
end

function M.applyToSeat( seat )
    if not seat.interactable then return end
    local seatId = seat.interactable.id

    -- 乘坐者变化（离座或换人）时闭合旧乘员的按住并清除玩家输入镜像。玩家异常离座（传送、断线、
    -- 按住键直接起身）不会送来松键事件，残留的按住状态会被合并进后续回放，导致方向永久卡住；
    -- 只有以当前乘坐者为准，才能可靠回收这些残留。输入鉴权保证镜像不会在无人时被迟到的包重建。
    local rider = seat.interactable:getSeatCharacter()
    if seat.aeRider ~= rider then
        releaseHeldInput( seat )
        seat.aeRider = rider
        seat.aePlayer = nil
    end

    local playback = AEManager.getPlayback( seatId )
    local active = playback ~= nil

    -- 既没有回放，也没有上一次回放留下的残留需要释放：此时不做干预，交还给座椅的原生逻辑。
    if not active and not seat.aeActive then return end

    if not seat.aeApplied then
        -- 只有快捷栏通道需要差分（它的状态由触发式 API 改变，无法每帧重申）；
        -- 转向和逻辑键采用每帧无条件重申的方式，不依赖缓存。
        seat.aeApplied = { item = {} }
    end
    local player = seat.aePlayer or EMPTY_PLAYER
    local onLift = AEManager.isInteractableOnLift( seat.interactable )

    applySteering( seat, player, playback, onLift )
    local pendingItems = applyItems( seat, playback, onLift )
    applyLogic( seat, player, playback, onLift )

    if active then
        -- 无人回放也要座椅处于激活状态，方向与动力输出才会生效。
        seat.interactable:setActive( true )
        seat.interactable:setPower( seat.interactable:getSteeringPower() )
        seat.aeActive = true
    elseif pendingItems then
        -- 残留释放失败（目标暂时异常）：保留差分缓存与激活标记，下一帧继续重试，
        -- 否则失败的槽位会永远停在按下状态，直到下一次回放才被纠正。
        seat.aeActive = true
    else
        -- 残留已释放完毕，丢弃差分缓存，下次回放时从初始状态重新建立。
        seat.aeActive = nil
        seat.aeApplied = nil
    end
end

-- 座椅创建：登记录制与回放能力，并清掉共享区里同编号的陈旧状态。共享区是会话级全局表，
-- 异常路径（旧版本脚本、崩溃残留）留下的冻结通道若不在此清除，重新加载的座椅会立刻消费它。
function M.onSeatCreate( seat )
    if not seat.interactable then return end
    local seatId = seat.interactable.id
    AEManager.registerSeat( seatId )
    AEManager.clearPlayback( seatId )
    AEManager.clearRecording( seatId )
end

-- 座椅销毁与卸载共用的收尾：建造物离开加载范围时脚本实例同样会消失，共享区里的占用、
-- 通道和能力登记都必须撤下，两条路径不允许有差别。
function M.onSeatGone( seat )
    seat.aePlayer = nil
    seat.aeApplied = nil
    seat.aeActive = nil
    seat.aeRider = nil
    if seat.interactable then
        local seatId = seat.interactable.id
        AEManager.clearPlayback( seatId )
        AEManager.clearRecording( seatId )
        AEManager.unregisterSeat( seatId )
    end
end

-- ---------- 客户端：回放中放行 Use ----------

function M.shouldReleaseUse( seat, action )
    if not seat.interactable then return false end
    if action ~= sm.interactable.actions.use then return false end
    -- 回放不应屏蔽玩家离座的意图；座椅原有逻辑处理后，仍把 Use 交还给游戏的默认行为。
    return AEManager.isClientPlaying( seat.interactable.id )
end

AESeat = M
