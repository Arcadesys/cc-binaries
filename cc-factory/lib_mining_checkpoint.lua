-- Durable mining journal. A staging file is deliberately a recovery blocker:
-- an interrupted replacement may contain an action intent newer than the main file.
local M = {}
local fields = { 'config', 'origin', 'pose', 'path', 'workPath', 'workPose', 'pointer',
    'phase', 'travelIndex', 'returnReason', 'intent', 'lastError', 'stoppedPhase', 'knownAir', 'placedTorches', 'identity', 'failedPhase' }
M.fields = fields
function M.path(ctx)
    return ctx.config.checkpointPath or ('mining-' .. ctx.config.job .. '.checkpoint')
end
function M.save(ctx)
    if not (fs and fs.open and fs.exists and fs.move and fs.delete and textutils) then
        return false, 'Persistent filesystem unavailable'
    end
    local record = { version = 1 }
    for _, key in ipairs(fields) do record[key] = ctx[key] end
    if ctx.miningPolicy then record.knownAir = ctx.miningPolicy.knownAir; record.placedTorches = ctx.miningPolicy.placedTorches end
    local path, stage = M.path(ctx), M.path(ctx) .. '.next'
    if fs.exists(stage) then return false, 'Pending checkpoint write requires manual reconciliation' end
    local ok, err = pcall(function()
        local data = textutils.serialize(record)
        local file = assert(fs.open(stage, 'w'), 'Checkpoint cannot be opened')
        file.write(data); file.close()
        local verify = assert(fs.open(stage, 'r'), 'Checkpoint cannot be verified')
        local stored = verify.readAll(); verify.close()
        assert(stored == data, 'Checkpoint readback mismatch')
        if fs.exists(path) then fs.delete(path) end
        fs.move(stage, path)
    end)
    return ok, ok and nil or tostring(err)
end
function M.load(ctx)
    if not (fs and fs.exists and fs.open and textutils) then return nil, 'Persistent filesystem unavailable' end
    local path = M.path(ctx)
    if fs.exists(path .. '.next') then return nil, 'Interrupted checkpoint write; manual reconciliation required' end
    if not fs.exists(path) then return false end
    local ok, record = pcall(function()
        local file = assert(fs.open(path, 'r'))
        local contents = file.readAll(); file.close()
        return textutils.unserialize(contents)
    end)
    if not ok or type(record) ~= 'table' or record.version ~= 1 then return nil, 'Invalid mining checkpoint' end
    if record.intent then return nil, 'Interrupted action; pose or inventory uncertain. Reconcile manually; no automatic movement.' end
    return record
end
return M
