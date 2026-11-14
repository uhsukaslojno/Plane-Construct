----------------------------------------------------
-- 操作编辑器：跨部件状态管理
-- Copyright (c) 2026 APxiaosong & Nyako. All rights reserved.
-- SM 的不同部件脚本之间没有直接调用通道，只能借共享的 _G 通信。
-- 这里把所有跨部件状态收进单一所有者，对外只暴露语义化接口，实现编辑器与座椅的解耦：
--   编辑器只写自己的回放区、只读自己的录制信箱，座椅只读回放区、只写录制信箱。
-- 服务端与客户端是相互独立的 Lua 环境，各自持有一份根表，互不可见。
----------------------------------------------------

local M = {}

local SERVER_ROOT = "AE_SERVER"
local CLIENT_ROOT = "AE_CLIENT"

local function serverRoot()
    local root = _G[SERVER_ROOT]
    if not root then
        root = {}
        _G[SERVER_ROOT] = root
    end
    -- 各分区统一在此补齐：新建与热重载沿用旧版根表走同一条路径，新增分区不会在旧会话中空缺。
    root.playback = root.playback or {}
    root.inbox = root.inbox or {}
    root.recording = root.recording or {}
    root.seats = root.seats or {}
    return root
end

-- 服务端当前帧。引擎极早期可能取不到，返回 nil 由调用方自行回退；录制帧戳与合成松键共用这一时钟。
function M.currentTick()
    if sm.game and sm.game.getCurrentTick then
        local ok, tick = pcall( sm.game.getCurrentTick )
        if ok then return tick end
    end
    return nil
end

-- ---------- 座椅能力注册：适配座椅创建时登记，销毁和卸载时注销 ----------
-- 录制和回放都依赖座椅脚本主动调用 AESeat 的接口；未适配的座椅（原版或其他模组）能通过连接检查，
-- 但既不会生产录制输入也不会消费回放通道，功能会静默失效。编辑器在启动录制或回放前据此在入口拒绝。

function M.registerSeat( seatId )
    if seatId then serverRoot().seats[seatId] = true end
end

function M.unregisterSeat( seatId )
    if seatId then serverRoot().seats[seatId] = nil end
end

function M.isSeatSupported( seatId )
    return seatId ~= nil and serverRoot().seats[seatId] == true
end

local function clientRoot()
    local root = _G[CLIENT_ROOT]
    if not root then
        root = {}
        _G[CLIENT_ROOT] = root
    end
    -- 与 serverRoot 同一口径：分区统一在此补齐，热重载沿用旧版根表时不会索引到空缺字段。
    root.playingSeats = root.playingSeats or {}
    return root
end

-- ---------- 回放通道：编辑器服务端发布，座椅服务端拉取 ----------

-- channels 形如 { steering = {forward=bool,...}, item = {[0]=bool,...}, logic = {space=bool,...} }
function M.publishPlayback( seatId, editorId, channels )
    if not seatId then return end
    serverRoot().playback[seatId] = {
        editorId = editorId,
        steering = channels.steering,
        item = channels.item,
        logic = channels.logic
    }
end

function M.getPlayback( seatId )
    if not seatId then return nil end
    return serverRoot().playback[seatId]
end

function M.getPlaybackOwner( seatId )
    local current = M.getPlayback( seatId )
    return current and current.editorId or nil
end

function M.clearPlayback( seatId, editorId )
    if not seatId then return end
    local playback = serverRoot().playback
    local current = playback[seatId]
    -- 只有当前持有者本人能撤下回放，避免后来者误清正在进行的回放。
    if current and ( editorId == nil or current.editorId == editorId ) then
        playback[seatId] = nil
    end
end

-- ---------- 录制占用：编辑器服务端在录制期间登记，与回放占用互为对称的互斥 ----------
-- 回放会向座椅写入通道，若与录制并存，录出的时间线混入回放输入后无法复现；
-- 录制启动前查询回放占用，回放启动前查询录制占用，两个方向都拒绝并存。

-- 申请录制占用：空闲或已属于本编辑器时登记并返回 true，被其他编辑器占用时返回 false。
-- 查询与登记必须在同一个函数内完成：分成两次调用会让第二个编辑器直接覆盖第一个的登记，
-- 占用者停止时清空登记，先占用者却仍在录制，互斥就名存实亡了。服务端脚本单线程执行，同函数内不会被穿插。
function M.claimRecording( seatId, editorId )
    if not seatId or not editorId then return false end
    local recording = serverRoot().recording
    if recording[seatId] and recording[seatId] ~= editorId then return false end
    recording[seatId] = editorId
    return true
end

function M.getRecordingOwner( seatId )
    if not seatId then return nil end
    return serverRoot().recording[seatId]
end

function M.clearRecording( seatId, editorId )
    if not seatId then return end
    local recording = serverRoot().recording
    -- 只有当前持有者本人能撤下登记，与 clearPlayback 的口径一致。
    if recording[seatId] and ( editorId == nil or recording[seatId] == editorId ) then
        recording[seatId] = nil
    end
end

-- ---------- 录制信箱：座椅服务端投递玩家输入，编辑器服务端取走 ----------

function M.pushInput( editorId, record )
    if not editorId or not record then return end
    local inbox = serverRoot().inbox
    local queue = inbox[editorId]
    if not queue then
        queue = {}
        inbox[editorId] = queue
    end
    queue[#queue + 1] = record
end

function M.drainInput( editorId )
    if not editorId then return nil end
    local inbox = serverRoot().inbox
    local queue = inbox[editorId]
    inbox[editorId] = nil
    return queue
end

function M.clearInput( editorId )
    if not editorId then return end
    serverRoot().inbox[editorId] = nil
end

-- ---------- 连接查询 ----------

-- 编辑器以 seated 连接挂在座椅下，且 maxParentCount 为 1，所以唯一的父级就是目标座椅。
-- 通过 getSeatCharacter 方法是否存在来区分座椅和其它部件。
function M.getConnectedSeat( editor )
    if not editor or not editor.interactable then return nil end
    local parent = editor.interactable:getSingleParent()
    if parent and parent.getSeatCharacter then
        return parent
    end
    return nil
end

-- 判断某个 interactable 所在的形状是否停在千斤顶上（回放和录制要据此避让）。
-- 取 shape 和取 onLift 各包一层 pcall：这些访问在对象异常时会抛错，把错误限制在本函数内，不向外扩散。
-- pcall 以“函数加接收者”的形式直接调用：本函数处于每秒 40 帧的服务端热路径，包成闭包会让每次调用都分配两个对象。
-- 编辑器与座椅两侧共用这一函数，避免各写一份判定逻辑、各自分叉。
function M.isInteractableOnLift( interactable )
    if not interactable or not sm.exists( interactable ) then return false end
    local okShape, shape = pcall( interactable.getShape, interactable )
    if not okShape or not shape or not shape.body then return false end
    local okLift, onLift = pcall( shape.body.isOnLift, shape.body )
    return okLift and onLift == true
end

-- ---------- 客户端回放标记：编辑器客户端写，座椅客户端读 ----------
-- 座椅客户端据此判断“回放中按 Use 应放行给游戏”，让玩家仍能离座。
-- 标记按持有者（编辑器编号）登记：同一座椅在两个编辑器之间快速交接回放时，
-- 旧编辑器迟到的清理只能撤掉自己的登记，不会把新编辑器刚设置的标记一并清掉。

function M.setClientPlaying( seatId, editorId )
    if not seatId or not editorId then return end
    clientRoot().playingSeats[seatId] = editorId
end

function M.releaseClientPlaying( seatId, editorId )
    if not seatId then return end
    local playingSeats = clientRoot().playingSeats
    if playingSeats[seatId] == editorId then
        playingSeats[seatId] = nil
    end
end

function M.isClientPlaying( seatId )
    if not seatId then return false end
    return clientRoot().playingSeats[seatId] ~= nil
end

AEManager = M
