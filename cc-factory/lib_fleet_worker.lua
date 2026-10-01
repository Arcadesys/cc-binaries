-- Trusted local catalog + correlated lease client. No received source is executed.
local M={}
local function copy(v)
    if type(v)~='table' then return v end
    local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function integer(v) return type(v)=='number' and v%1==0 and v>=0 and v<2^53 end
local function sameBay(a,b) return type(a)=='table' and type(b)=='table' and a.x==b.x and a.y==b.y and a.z==b.z end
local function validHome(p)
    if type(p)~='table' then return false end
    for _,k in ipairs({'x','y','z'}) do if type(p[k])~='number' or p[k]%1~=0 then return false end end
    return p.facing=='north' or p.facing=='east' or p.facing=='south' or p.facing=='west'
end
function M.new(config,deps)
    deps=deps or {};config=copy(config)
    if type(config)~='table' or type(config.fleet)~='string' or config.fleet=='' or not integer(config.coordinatorId) or not integer(config.workerId) or not validHome(config.home) or type(config.dimension)~='string' or config.dimension=='' or type(config.jobs)~='table' then return nil,'Invalid trusted worker configuration' end
    if config.protocol~=nil and config.protocol~='cc-safe-mining-fleet-v1' then return nil,'Unsupported fleet protocol' end
    local eligible={}
    for job,c in pairs(config.jobs) do
        if type(job)=='string' and type(c)=='table' and c.job==job and validHome(c.home) and sameBay(c.home,config.home) and c.dimension==config.dimension then eligible[#eligible+1]=job end
    end
    table.sort(eligible)
    if #eligible==0 then return nil,'No locally authorized job at this home and dimension' end
    if type(deps.clock)~='function' or type(deps.transport)~='table' or type(deps.transport.exchange)~='function' then return nil,'Clock and trusted transport required' end
    local lastClock
    local function clock()
        local value=deps.clock()
        if type(value)~='number' or value~=value or math.abs(value)==math.huge or value<0 or (lastClock and value<lastClock) then error('Invalid or regressed fleet clock') end
        lastClock=value;return value
    end
    local initialOK,initialTime=pcall(clock)
    if not initialOK then return nil,tostring(initialTime) end
    if config.timeout~=nil and (type(config.timeout)~='number' or config.timeout~=config.timeout or config.timeout<=0 or config.timeout>30) then return nil,'Transport timeout must be 0..30 seconds' end
    if config.pollSeconds~=nil and (type(config.pollSeconds)~='number' or config.pollSeconds~=config.pollSeconds or config.pollSeconds<=0 or config.pollSeconds>10) then return nil,'Polling interval must be 0..10 seconds' end
    local w={config=config,clock=clock,transport=deps.transport,miner=deps.miner or require('lib_safe_miner'),status='AWAITING_PREFLIGHT',eligibleJobs=eligible,knownHome=copy(config.home),journal=deps.journal or require('lib_mining_checkpoint'),sequence=config.requestIdSeed or math.floor(initialTime*1000)}
    if not integer(w.sequence) then return nil,'Invalid request sequence seed' end
    local positionConfig={job='fleet-position-'..config.workerId,checkpointPath=config.positionCheckpoint or ('fleet-'..config.fleet..'-worker-'..config.workerId..'.position'),fleet=config.fleet,workerId=config.workerId,coordinatorId=config.coordinatorId,dimension=config.dimension,home=copy(config.home)}
    function w:saveHome()
        local record={config=positionConfig,origin=copy(self.config.home),pose=copy(self.knownHome),path={copy(self.knownHome)},phase='HOME',miningPolicy={knownAir={},placedTorches={}}}
        return self.journal.save(record)
    end
    function w:state() return {status=self.status,reason=self.reason,job=self.job,phase=self.ctx and self.ctx.phase,pose=self.ctx and copy(self.ctx.pose),home=copy(self.knownHome),leaseUntil=self.leaseUntil} end
    function w:receive(sender,message) return false,'Unsolicited messages do not authorize actions' end
    function w:loadHome()
        local record,err=self.journal.load({config=positionConfig})
        if record==nil then self.status='NEEDS_HELP';self.reason=err;return false,err end
        if record then
            if not equal(record.config,positionConfig) or not validHome(record.pose) or not sameBay(record.pose,self.config.home) then self.status='NEEDS_HELP';self.reason='Invalid saved home identity/pose';return false,self.reason end
            self.knownHome=copy(record.pose)
        end
        return true
    end
    function w:confirmHome(confirmed)
        if self.status~='AWAITING_PREFLIGHT' or confirmed~=true then return false,'Local preflight confirmation required' end
        local ok,err=self:loadHome();if not ok then return false,err end
        ok,err=self:saveHome()
        if not ok then self.status='NEEDS_HELP';self.reason=err;return false,err end
        self.confirmed=true;self.status='READY';return true
    end
    function w:exchange(kind,extra)
        self.sequence=self.sequence+1
        local message={fleet=self.config.fleet,type=kind,workerId=self.config.workerId,requestId=self.sequence,session=self.session,job=self.job,token=self.token,generation=self.generation}
        for k,v in pairs(extra or {}) do message[k]=copy(v) end
        local sent=self.clock()
        local ok,sender,reply=pcall(self.transport.exchange,self.config.coordinatorId,message,self.config.timeout or 3)
        if not ok or sender~=self.config.coordinatorId or type(reply)~='table' or reply.fleet~=self.config.fleet or reply.requestId~=message.requestId then return nil,'No trusted correlated coordinator reply' end
        if kind~='register' and reply.session~=self.session then return nil,'Coordinator session mismatch' end
        return reply,nil,sent
    end
    function w:acceptLease(reply,sent)
        if type(reply.token)~='string' or reply.token=='' or not integer(reply.generation) or reply.generation<1 or type(reply.leaseSeconds)~='number' or reply.leaseSeconds~=reply.leaseSeconds or reply.leaseSeconds<=0 or reply.leaseSeconds>3600 then return false,'Invalid lease grant' end
        if reply.session~=self.session or reply.job~=self.job then return false,'Lease job/session mismatch' end
        if self.token and (reply.token~=self.token or reply.generation~=self.generation) then return false,'Lease token/generation mismatch' end
        local deadline=sent+reply.leaseSeconds
        if self.clock()>=deadline then return false,'Lease reply arrived after its deadline' end
        self.token,self.generation=reply.token,reply.generation
        self.leaseUntil=deadline;self.renewAt=sent+reply.leaseSeconds/2
        return true
    end
    function w:renew()
        if not self.job or not self.leaseUntil or self.clock()>=self.leaseUntil then return false,'Lease expired; area must remain quarantined' end
        local reply,err,sent=self:exchange('heartbeat',{result={phase=self.ctx and self.ctx.phase or 'READY',pose=self.ctx and copy(self.ctx.pose) or copy(self.config.home)}})
        if not reply or reply.type~='RENEWED' then return false,err or 'Coordinator refused lease renewal' end
        return self:acceptLease(reply,sent)
    end
    function w:authorizeAction(action,ctx)
        if not self.confirmed or self.status~='RUNNING' or not self.job then return false,'Worker is not authorized to run' end
        if not self.leaseUntil or self.clock()>=self.leaseUntil then self.leaseLost=true;return false,'Lease expired' end
        if self.clock()>=self.renewAt then
            local ok,err=self:renew();if not ok then self.leaseLost=true;self.reason=err;return false,err end
        end
        if self.clock()>=self.leaseUntil then self.leaseLost=true;return false,'Lease expired before action' end
        return true
    end
    function w:report()
        local phase=self.ctx and self.ctx.phase or 'NEEDS_HELP'
        local done=phase=='DONE' and equal(self.ctx.pose,self.config.jobs[self.job].home) and not self.ctx.intent
        if done then for slot=1,16 do if turtle.getItemCount(slot)~=0 then done=false;break end end end
        if phase=='DONE' and not done then phase='NEEDS_HELP';self.reason='Completion lacks verified home and empty inventory' end
        local reply,err=self:exchange(done and 'complete' or 'stop',{result={phase=phase,pose=self.ctx and copy(self.ctx.pose),unloaded=done,reason=self.reason or (self.ctx and self.ctx.lastError)}})
        if done and reply and reply.type=='COMPLETED' and reply.job==self.job and reply.token==self.token and reply.generation==self.generation then
            self.knownHome=copy(self.ctx.pose)
            local saved,why=self:saveHome();if not saved then self.status='NEEDS_HELP';self.reason=why;return false,why end
            self.ctx=nil;self.job=nil;self.token=nil;self.generation=nil;self.leaseUntil=nil;self.status='READY';return true
        end
        self.status=phase=='STOPPED' and 'STOPPED' or 'NEEDS_HELP'
        self.reason=self.reason or err or (reply and reply.reason) or (self.ctx and self.ctx.lastError) or 'Assignment remains quarantined'
        return false,self.reason
    end
    function w:stop()
        if self.ctx and not self.ctx.intent then self.miner.requestStop(self.ctx) end
        self.reason='Local stop requested';return self:report()
    end
    function w:tick()
        local clockOK,why=pcall(self.clock)
        if not clockOK then self.status='NEEDS_HELP';self.reason=tostring(why);return false,self.reason end
        if not self.confirmed then return false,'Local preflight confirmation required' end
        if self.status=='NEEDS_HELP' or self.status=='STOPPED' then return false,self.reason end
        if not self.session then
            local reply,err=self:exchange('register',{home=self.config.home,dimension=self.config.dimension})
            if not reply or reply.type~='REGISTERED' or type(reply.session)~='string' or reply.session=='' then self.status='NEEDS_HELP';self.reason=err or 'Registration refused';return false,self.reason end
            self.session=reply.session;return true
        end
        if not self.job then
            local reply,err,sent=self:exchange('request',{home=self.config.home,dimension=self.config.dimension,eligibleJobs=self.eligibleJobs})
            if reply and reply.type=='WAIT' then self.status='WAIT';return true end
            if not reply or reply.type~='ASSIGNED' or type(reply.job)~='string' or type(reply.config)~='table' or type(self.config.jobs[reply.job])~='table' or not equal(reply.config,self.config.jobs[reply.job]) or not sameBay(reply.config.home,self.config.home) or reply.config.dimension~=self.config.dimension then
                self.status='NEEDS_HELP';self.reason=err or 'Grant is outside the local job authorization';return false,self.reason
            end
            self.job=reply.job
            local ok;ok,err=self:acceptLease(reply,sent)
            if not ok then self.status='NEEDS_HELP';self.reason=err;return false,err end
            self.ctx={config=copy(self.config.jobs[self.job]),authorizeAction=function(action,ctx) return self:authorizeAction(action,ctx) end}
            self.status='RUNNING'
            self.targetHome=copy(reply.config.home)
            if self.knownHome.facing~=self.targetHome.facing then self.orienting=true;return true end
            local ran,state=pcall(self.miner.initialize,self.ctx)
            if not ran or state=='ERROR' then self.reason=ran and self.ctx.lastError or tostring(state);return self:report() end
            if self.ctx.phase=='DONE' then return self:report() end
            return true
        end
        local ok,err=self:authorizeAction('step',self.ctx)
        if not ok then
            self.reason=err
            if not self.ctx.intent then self.miner.requestStop(self.ctx) end
            return self:report()
        end
        if self.orienting then
            local orientation={config=positionConfig,origin=copy(self.config.home),pose=copy(self.knownHome),path={copy(self.knownHome)},pointer=1,phase='ORIENTING',miningPolicy={knownAir={},placedTorches={}},authorizeAction=self.ctx.authorizeAction}
            local order={north=0,east=1,south=2,west=3}
            local delta=(order[self.targetHome.facing]-order[self.knownHome.facing])%4
            local ran,moved,reason=pcall(self.miner.turnAtHome,orientation,delta==3 and 'left' or 'right')
            if not ran or not moved then self.reason=ran and reason or tostring(moved);self.ctx.phase='NEEDS_HELP';return self:report() end
            self.knownHome=copy(orientation.pose)
            local saved,why=self:saveHome();if not saved then self.reason=why;self.ctx.phase='NEEDS_HELP';return self:report() end
            if self.knownHome.facing==self.targetHome.facing then
                self.orienting=nil
                local initialized,state=pcall(self.miner.initialize,self.ctx)
                if not initialized or state=='ERROR' then self.reason=initialized and self.ctx.lastError or tostring(state);return self:report() end
            end
            return true
        end
        local ran,state=pcall(self.miner.step,self.ctx)
        if not ran then self.reason=tostring(state);self.ctx.phase='NEEDS_HELP';return self:report() end
        if state=='ERROR' or state=='EXIT' or self.leaseLost then return self:report() end
        return true
    end
    local loaded,err=w:loadHome();if not loaded then return nil,err end
    return w
end
return M
