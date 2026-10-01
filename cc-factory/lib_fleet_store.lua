-- Fleet state replacement fails closed on any leftover staged write.
local M = {}
function M.new(path)
    assert(type(path)=='string' and path~='', 'Fleet store path required')
    local store={}
    function store.load()
        if not (fs and fs.exists and fs.open and textutils) then return nil,'Persistent filesystem unavailable' end
        if fs.exists(path..'.next') then return nil,'Interrupted fleet checkpoint; reconciliation required' end
        if not fs.exists(path) then return false end
        local ok,value=pcall(function()
            local file=assert(fs.open(path,'r'));local data=file.readAll();file.close()
            return textutils.unserialize(data)
        end)
        if not ok or type(value)~='table' then return nil,'Corrupt fleet checkpoint' end
        return value
    end
    function store.save(value)
        if not (fs and fs.exists and fs.open and fs.move and fs.delete and textutils) then return false,'Persistent filesystem unavailable' end
        local stage=path..'.next'
        if fs.exists(stage) then return false,'Pending fleet write requires reconciliation' end
        local ok,err=pcall(function()
            local data=textutils.serialize(value)
            local file=assert(fs.open(stage,'w'));file.write(data);file.close()
            local verify=assert(fs.open(stage,'r'));local actual=verify.readAll();verify.close()
            assert(data==actual,'Fleet checkpoint readback mismatch')
            if fs.exists(path) then fs.delete(path) end
            fs.move(stage,path)
        end)
        return ok,ok and nil or tostring(err)
    end
    return store
end
return M
