-- Physical cabinet controls: a pull arm and three buttons, each wired to a redstone input.
-- An input is a computer side ("left") or a Redstone Relay side ("redstone_relay_0:left"),
-- for cabinets whose sides are taken by the monitor, drive and modem. Only rising edges
-- count, so a lever left on does not spin twice and holding a button does not repeat.
local M={names={'arm','bet','max','cash'},path='/pineslots-settings'}
M.labels={arm='PULL ARM',bet='BET ONE',max='MAX BET',cash='CASH OUT'}
M.defaults={arm='right',bet='left',max='top',cash='back'}
function M.load()
 settings.load(M.path)
 local c={}
 for _,n in ipairs(M.names) do c[n]=settings.get('pineslots.'..n,M.defaults[n]) end
 return c
end
function M.read(spec)
 if type(spec)~='string' or spec=='' or spec=='none' then return false end
 local device,side=spec:match('^(.+):(%a+)$')
 if device then
  local ok,on=pcall(peripheral.call,device,'getInput',side)
  return ok and on==true
 end
 local ok,on=pcall(redstone.getInput,spec)
 return ok and on==true
end
-- Keyboard and touch stand in for the cabinet on a desk or a bare monitor.
local KEYS={[keys.space]='arm',[keys.enter]='arm',[keys.one]='bet',[keys.b]='bet',[keys.two]='max',[keys.m]='max',[keys.three]='cash',[keys.c]='cash'}
function M.new(config,read)
 read=read or M.read
 local api={config=config,last={}}
 for _,n in ipairs(M.names) do api.last[n]=read(config[n]) end
 -- Controls that went from off to on since the last poll.
 function api:poll()
  local out={}
  for _,n in ipairs(M.names) do
   local on=read(config[n])
   if on and not self.last[n] then out[#out+1]=n end
   self.last[n]=on
  end
  return out
 end
 function api:key(code) return KEYS[code] end
 return api
end
-- Every input that could carry a control: computer sides and attached relays.
function M.candidates()
 local out={}
 for _,side in ipairs(redstone.getSides()) do out[#out+1]=side end
 for _,name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name,'redstone_relay') then
   for _,side in ipairs(redstone.getSides()) do out[#out+1]=name..':'..side end
  end
 end
 return out
end
-- Learn each control by having the operator use it.
function M.setup()
 print('PINE SLOTS CONTROL SETUP')
 print('Use each control when asked. Enter skips it (keyboard and touch still work).')
 local chosen={}; local used={}
 for _,n in ipairs(M.names) do
  local list=M.candidates(); local last={}
  for _,spec in ipairs(list) do last[spec]=M.read(spec) end
  write(M.labels[n]..': waiting... ')
  local found
  local timer=os.startTimer(.1)
  while not found do
   local e,a=os.pullEvent()
   if e=='key' and (a==keys.enter or a==keys.numPadEnter) then found='none'
   elseif e=='timer' and a==timer or e=='redstone' then
    for _,spec in ipairs(list) do
     local on=M.read(spec)
     if on and not last[spec] and not used[spec] then found=spec; break end
     last[spec]=on
    end
    if e=='timer' then timer=os.startTimer(.1) end
   end
  end
  print(found)
  chosen[n]=found; if found~='none' then used[found]=true end
 end
 for _,n in ipairs(M.names) do settings.set('pineslots.'..n,chosen[n]) end
 settings.save(M.path)
 print('Saved '..M.path..'. Run pineslots to play.')
 return chosen
end
return M
