-- Renders the cashier's cage at two sizes and dumps each screen for casino/tools/screens.py.
local cage=require('derby.cage')
local dump=require('casino.tests.screen')
for _,size in ipairs({{51,19},{100,40}}) do
 local t=window.create(term.current(),1,1,size[1],size[2],false)
 local r=cage.new(t)
 local v={balance=1280,count=20,info='house-0042  |  Balance: 1280',prompt='Amount: 20  [Left/Right]',status='Transferred 20 diamonds',hint='[N] New card  [R] Retry  [Q] Exit',options={'DEPOSIT','20','WITHDRAW'}}
 r:draw(v); dump(t,'cage-'..size[1]..'-idle')
 v.count=64; v.dx=3; v.balance=nil; v.prompt='WITHDRAW 64 DIAMONDS?'; v.options={'CONFIRM','','CANCEL'}
 r:draw(v); dump(t,'cage-'..size[1]..'-slide')
 local start=os.epoch('utc'); for _=1,30 do r:draw(v) end
 local fps=30/math.max(.001,(os.epoch('utc')-start)/1000)
 print(('Rendered %dx%d at %.1f fps'):format(size[1],size[2],fps)); assert(fps>=10,'Render under 10 fps')
end
print('PASS cashier cage')
