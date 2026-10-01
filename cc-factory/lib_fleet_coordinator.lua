-- Finite durable scheduler. Network sender checks are not cryptographic identity.
local stores=require('lib_fleet_store')
local strategy=require('lib_strategy_branchmine')
local miningPolicy=require('lib_mine_policy')
local M={}
local function copy(t)
    if type(t)~='table' then return t end
    local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r
end
local function plainData(value,depth,seen,budget)
    depth=depth or 0;seen=seen or {};budget=budget or {n=0}
    local kind=type(value)
    if kind=='string' then return #value<=4096 end
    if kind=='number' then return value==value and math.abs(value)~=math.huge end
    if kind=='boolean' or kind=='nil' then return true end
    if kind~='table' or depth>8 or seen[value] or getmetatable(value) then return false end
    seen[value]=true
    for k,v in pairs(value) do
        budget.n=budget.n+1
        if budget.n>4096 or not plainData(k,depth+1,seen,budget) or not plainData(v,depth+1,seen,budget) then return false end
    end
    seen[value]=nil;return true
end
local function callStore(store,method,...)
    local ok,value,err=pcall(store[method],...)
    if not ok then return nil,tostring(value) end
    return value,err
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function canonical(t)
    if type(t)~='table' then return type(t)..':'..tostring(t) end
    local keys={};for k in pairs(t) do keys[#keys+1]=k end
    table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b) end)
    local parts={};for _,k in ipairs(keys) do parts[#parts+1]=canonical(k)..'='..canonical(t[k]) end
    return '{'..table.concat(parts,';')..'}'
end
local function integer(n) return type(n)=='number' and n==n and n%1==0 and math.abs(n)<1e15 end
local function box(b)
    if type(b)~='table' or type(b.min)~='table' or type(b.max)~='table' then return false end
    for _,axis in ipairs({'x','y','z'}) do if not integer(b.min[axis]) or not integer(b.max[axis]) or b.min[axis]>b.max[axis] then return false end end
    return true
end
local function contains(b,p)
    for _,axis in ipairs({'x','y','z'}) do if not integer(p[axis]) or p[axis]<b.min[axis] or p[axis]>b.max[axis] then return false end end
    return true
end
local function samePosition(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
local function intersects(a,b) for key in pairs(a) do if b[key] then return true end end;return false end
local function includes(a,b) return contains(a,b.min) and contains(a,b.max) end
local function overlaps(a,b)
    for _,axis in ipairs({'x','y','z'}) do if a.max[axis]<b.min[axis] or b.max[axis]<a.min[axis] then return false end end
    return true
end
M.overlaps=overlaps
local facing={north=true,east=true,south=true,west=true}
local vectors={north={0,-1},east={1,0},south={0,1},west={-1,0}}
local function home(p)
    return type(p)=='table' and integer(p.x) and integer(p.y) and integer(p.z) and facing[p.facing]
end
local function sorted(t)
    local r={};for key in pairs(t) do r[#r+1]=key end;table.sort(r);return r
end
local function normalize(config)
    local c=copy(config)
    if type(c)~='table' or type(c.fleet)~='string' or (#c.fleet>64 or not c.fleet:match('^[%w_-]+$')) then return nil,'Named fleet required' end
    if type(c.workers)~='table' or type(c.jobs)~='table' then return nil,'Finite worker and job catalogs required' end
    c.leaseSeconds=c.leaseSeconds or 30
    if not integer(c.leaseSeconds) or c.leaseSeconds<2 or c.leaseSeconds>300 then return nil,'Lease must be 2..300 seconds' end
    local workers={};local count=0
    for id,profile in pairs(c.workers) do
        local numeric=tonumber(id)
        if not integer(numeric) or numeric<0 or workers[tostring(numeric)] then return nil,'Unique numeric worker IDs required' end
        if type(profile)~='table' or not home(profile.home) or type(profile.dimension)~='string' or profile.dimension=='' or not box(profile.bayBounds) or not contains(profile.bayBounds,profile.home) then return nil,'Worker requires dimension, home heading and explicit bay bounds' end
        workers[tostring(numeric)]=profile;count=count+1
    end
    if count<1 or count>64 then return nil,'Authorize 1..64 workers' end
    c.workers=workers
    for _,profile in pairs(workers) do profile.bayCells={[miningPolicy.key(profile.home)]=true} end
    count=0
    for name,job in pairs(c.jobs) do
        if type(name)~='string' or (#name>64 or not name:match('^[%w_-]+$')) or type(job)~='table' or type(job.config)~='table' then return nil,'Named finite job configs required' end
        local jc=job.config
        if jc.job~=name or jc.mode~='mine' or not home(jc.home) or type(jc.dimension)~='string' or not box(jc.bounds) or not box(job.footprint) or not includes(job.footprint,jc.bounds) then return nil,'Job footprint must contain exact miner bounds' end
        if jc.resume then return nil,'Fleet job cannot auto-resume a local checkpoint' end
        if not integer(jc.length) or jc.length<1 or jc.length>256 or not integer(jc.branchInterval) or jc.branchInterval<1 or not integer(jc.branchLength) or jc.branchLength<1 or jc.branchLength>64 or not integer(jc.torchInterval) or jc.torchInterval<1 then return nil,'Job geometry must be explicit and bounded' end
        local ok,plan=pcall(strategy.generate,jc.length,jc.branchInterval,jc.branchLength,jc.torchInterval)
        if not ok then return nil,'Invalid job plan' end
        local p,err=miningPolicy.create(jc.home,plan,jc)
        if not p then return nil,'Job bounds rejected: '..tostring(err) end
        local owners={}
        for id,profile in pairs(workers) do
            if (job.workerId==nil or tostring(job.workerId)==id) and samePosition(profile.home,jc.home) and profile.dimension==jc.dimension then
                if not includes(job.footprint,profile.bayBounds) then return nil,'Job footprint omits owner bay' end
                local sideMethods={front=true,up=true,down=true}
                if not sideMethods[jc.outputSide] or not sideMethods[jc.supplySide] or jc.outputSide==jc.supplySide then return nil,'Job requires separate explicit inventory sides' end
                for _,side in ipairs({jc.outputSide,jc.supplySide}) do
                    local point=copy(jc.home)
                    if side=='up' then point.y=point.y+1 elseif side=='down' then point.y=point.y-1 else local v=vectors[point.facing];point.x=point.x+v[1];point.z=point.z+v[2] end
                    if not contains(profile.bayBounds,point) then return nil,'Bay bounds omit storage position' end
                    profile.bayCells[miningPolicy.key(point)]=true
                end
                owners[id]=true
            end
        end
        if next(owners)==nil then return nil,'Job has no compatible registered home and dimension' end
        job.owners=owners;job.workCells=copy(p.allowed)
        count=count+1
    end
    if count<1 or count>256 then return nil,'Authorize 1..256 finite jobs' end
    local ids=sorted(workers)
    for i,id in ipairs(ids) do for j=i+1,#ids do
        local a,b=workers[id],workers[ids[j]]
        if a.dimension==b.dimension and intersects(a.bayCells,b.bayCells) then return nil,'Registered home/storage cells overlap' end
    end end
    for _,job in pairs(c.jobs) do
        for _,profile in pairs(workers) do
            if profile.dimension==job.config.dimension and intersects(job.workCells,profile.bayCells) then return nil,'Job work crosses a home/storage cell' end
        end
    end
    local names=sorted(c.jobs)
    for i,name in ipairs(names) do for j=i+1,#names do
        local a,b=c.jobs[name],c.jobs[names[j]]
        if a.config.dimension==b.config.dimension and intersects(a.workCells,b.workCells) then return nil,'Preapproved work cells overlap' end
    end end
    return c
end
function M.new(config,options)
    options=options or {}
    local ok,c,err=pcall(normalize,config)
    if not ok or not c then return nil,err or tostring(c) end
    local clock=options.clock or function() return os.clock() end
    local store=options.store or stores.new(c.storePath or ('fleet-'..c.fleet..'.checkpoint'))
    local identity=options.coordinatorId or (os.getComputerID and os.getComputerID()) or 'unavailable'
    local fingerprint=canonical(c)
    local loaded,loadErr=callStore(store,'load')
    if loaded==nil then return nil,loadErr end
    local state
    if loaded==false then
        state={version=1,config=fingerprint,coordinatorId=identity,epoch=0,counter=0,jobs={},workers={}}
        for name in pairs(c.jobs) do state.jobs[name]={status='AVAILABLE',generation=0} end
        for id in pairs(c.workers) do state.workers[id]={highWater=0} end
    else
        if type(loaded)~='table' then return nil,'Invalid fleet checkpoint data' end
        state=copy(loaded)
        if state.version~=1 or state.config~=fingerprint or state.coordinatorId~=identity or not integer(state.epoch) or state.epoch<1 or not integer(state.counter) or state.counter<0 or type(state.jobs)~='table' or type(state.workers)~='table' then return nil,'Fleet checkpoint/config/identity mismatch' end
        local statuses={AVAILABLE=true,ASSIGNED=true,QUARANTINED=true,RETIRED=true}
        for name in pairs(state.jobs) do if not c.jobs[name] then return nil,'Unknown saved job' end end
        for name in pairs(c.jobs) do
            local saved=state.jobs[name]
            if type(saved)~='table' or not statuses[saved.status] or not integer(saved.generation) or saved.generation<0 then return nil,'Corrupt saved job reservation' end
            if saved.status~='AVAILABLE' and (not c.jobs[name].owners[saved.worker] or type(saved.token)~='string' or not integer(saved.epoch) or saved.epoch<1 or type(saved.deadline)~='number' or saved.deadline~=saved.deadline or math.abs(saved.deadline)==math.huge) then return nil,'Corrupt saved assignment' end
        end
        for id in pairs(state.workers) do if not c.workers[id] then return nil,'Unknown saved worker' end end
        for id in pairs(c.workers) do
            local saved=state.workers[id]
            if type(saved)~='table' or not integer(saved.highWater) or saved.highWater<0 then return nil,'Corrupt saved worker sequence' end
            if saved.job and (not state.jobs[saved.job] or state.jobs[saved.job].worker~=id) then return nil,'Corrupt worker assignment link' end
        end
    end
    state.epoch=state.epoch+1
    for _,job in pairs(state.jobs) do
        if job.status=='ASSIGNED' then job.status='QUARANTINED';job.reason='Coordinator restarted; occupied area requires reconciliation' end
    end
    for _,worker in pairs(state.workers) do worker.session=nil;worker.last=nil end
    local saved,saveErr=callStore(store,'save',state)
    if not saved then return nil,'Cannot persist coordinator epoch: '..tostring(saveErr) end
    local self={config=c,state=state,disabled=false,lastClock=nil}
    local function persist()
        local success,why=callStore(store,'save',state)
        if not success then self.disabled=true;self.error='Fleet persistence failed: '..tostring(why) end
        return success,why
    end
    local function reply(msg,kind,extra)
        local r={fleet=c.fleet,type=kind,requestId=msg.requestId,epoch=state.epoch}
        for k,v in pairs(extra or {}) do r[k]=copy(v) end
        return r
    end
    local function reject(msg,reason) return reply(msg,'REJECTED',{reason=reason}) end
    function self:tick()
        if self.disabled then return false,self.error end
        local now=clock();if type(now)~='number' or now~=now or math.abs(now)==math.huge or (self.lastClock and now<self.lastClock) then self.disabled=true;self.error='Invalid or regressed coordinator clock';return false,self.error end
        self.lastClock=now
        local changed=false
        for _,job in pairs(state.jobs) do
            if job.status=='ASSIGNED' and now>=job.deadline then job.status='QUARANTINED';job.reason='Worker lease expired; area may be occupied';changed=true end
        end
        if changed then return persist() end
        return true
    end
    function self:handle(sender,msg)
        if type(msg)~='table' or not plainData(msg) then return {fleet=c.fleet,type='REJECTED',reason='Invalid message'} end
        if self.disabled then return reject(msg,self.error or 'Coordinator stopped') end
        if msg.fleet~=c.fleet or not integer(sender) or msg.workerId~=sender or not c.workers[tostring(sender)] then return reject(msg,'Fleet or registered sender mismatch') end
        if not integer(msg.requestId) or msg.requestId<1 then return reject(msg,'Positive integer request ID required') end
        local id=tostring(sender);local worker=state.workers[id]
        local tickOK,tickErr=self:tick();if not tickOK then return reject(msg,tickErr) end
        local body=canonical(msg)
        if msg.requestId<=worker.highWater then
            if worker.last and worker.last.id==msg.requestId and worker.last.body==body then
                local old=worker.last.reply
                local assigned=old.job and state.jobs[old.job]
                if old.epoch~=state.epoch then return reject(msg,'Stale coordinator epoch') end
                if assigned and (old.type=='ASSIGNED' or old.type=='RENEWED') and assigned.status~='ASSIGNED' then return reply(msg,'QUARANTINED',{job=old.job,reason=assigned.reason or 'Assignment no longer active'}) end
                local replay=copy(old)
                if assigned and (old.type=='ASSIGNED' or old.type=='RENEWED') then replay.leaseSeconds=math.max(0,math.min(assigned.deadline,worker.last.deadline or assigned.deadline)-clock()) end
                return replay
            end
            return reject(msg,'Stale or reused request ID')
        end
        local response
        if msg.type=='register' then
            if worker.job and state.jobs[worker.job].status~='RETIRED' then
                response=reply(msg,'QUARANTINED',{job=worker.job,reason='Existing area reservation requires reconciliation'})
            else
                state.counter=state.counter+1
                worker.session=c.fleet..':'..state.epoch..':'..id..':'..state.counter
                worker.job=nil
                response=reply(msg,'REGISTERED',{session=worker.session,leaseSeconds=c.leaseSeconds})
            end
        elseif not worker.session or msg.session~=worker.session then response=reject(msg,'Stale or missing worker session')
        elseif msg.type=='request' then
            if worker.job then
                local existing=state.jobs[worker.job]
                if existing.status=='ASSIGNED' then response=reply(msg,'ASSIGNED',{session=worker.session,job=worker.job,token=existing.token,generation=existing.generation,leaseSeconds=math.max(0,existing.deadline-clock()),config=c.jobs[worker.job].config,footprint=c.jobs[worker.job].footprint})
                else response=reply(msg,'QUARANTINED',{job=worker.job,reason=existing.reason}) end
            else
                local eligible={}
                if type(msg.eligibleJobs)=='table' then for _,name in ipairs(msg.eligibleJobs) do if type(name)=='string' and c.jobs[name] then eligible[name]=true end end end
                for _,name in ipairs(sorted(c.jobs)) do
                    local job,authorization=state.jobs[name],c.jobs[name]
                    if job.status=='AVAILABLE' and authorization.owners[id] and eligible[name] then
                        local blocked=false
                        for otherName,other in pairs(state.jobs) do
                            if otherName~=name and other.status~='AVAILABLE' and c.jobs[otherName].config.dimension==authorization.config.dimension and intersects(c.jobs[otherName].workCells,authorization.workCells) then blocked=true end
                        end
                        if not blocked then
                            state.counter=state.counter+1;job.generation=job.generation+1
                            job.status='ASSIGNED';job.worker=id;job.epoch=state.epoch;job.token=c.fleet..':'..state.epoch..':'..name..':'..state.counter
                            job.deadline=clock()+c.leaseSeconds;worker.job=name
                            response=reply(msg,'ASSIGNED',{session=worker.session,job=name,token=job.token,generation=job.generation,leaseSeconds=c.leaseSeconds,config=authorization.config,footprint=authorization.footprint});break
                        end
                    end
                end
                response=response or reply(msg,'WAIT',{session=worker.session,reason='No compatible unreserved authorized work'})
            end
        elseif msg.type=='heartbeat' or msg.type=='complete' or msg.type=='stop' then
            local job=type(msg.job)=='string' and state.jobs[msg.job]
            if not job or worker.job~=msg.job or job.worker~=id or msg.token~=job.token or msg.generation~=job.generation or job.epoch~=state.epoch then response=reject(msg,'Assignment token or generation mismatch')
            elseif job.status~='ASSIGNED' then response=reply(msg,'QUARANTINED',{job=msg.job,reason=job.reason or 'Area is not active'})
            elseif msg.type=='heartbeat' then
                job.deadline=clock()+c.leaseSeconds
                response=reply(msg,'RENEWED',{session=worker.session,job=msg.job,token=job.token,generation=job.generation,leaseSeconds=c.leaseSeconds})
            elseif msg.type=='stop' then
                job.status='QUARANTINED';job.reason='Worker stopped; area requires reconciliation'
                response=reply(msg,'STOPPED',{session=worker.session,job=msg.job,reason=job.reason})
            else
                local result=msg.result
                if type(result)~='table' or result.phase~='DONE' or result.unloaded~=true or not home(result.pose) or not samePosition(result.pose,c.workers[id].home) or result.pose.facing~=c.jobs[msg.job].config.home.facing then response=reject(msg,'Completion requires verified home heading and unloading')
                else job.status='RETIRED';job.reason='Completed excavation permanently retired';worker.job=nil;response=reply(msg,'COMPLETED',{session=worker.session,job=msg.job,token=job.token,generation=job.generation}) end
            end
        else response=reject(msg,'Unknown protocol operation') end
        worker.highWater=msg.requestId;worker.last={id=msg.requestId,body=body,reply=copy(response),deadline=response.job and state.jobs[response.job].deadline or nil}
        local durable,why=persist()
        if not durable then return reject(msg,'No grant: durable write failed: '..tostring(why)) end
        return response
    end
    function self:snapshot() return copy(state) end
    return self
end
return M
