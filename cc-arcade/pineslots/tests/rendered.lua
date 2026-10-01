-- Renders the cabinet at several states and sizes and dumps each screen for review.
local render=require('pineslots.render')
local dump=require('casino.tests.screen')
for _,size in ipairs({{51,19},{100,40}}) do
 local t=window.create(term.current(),1,1,size[1],size[2],false)
 local r=render.new(t)
 r:draw({positions={0,5,15},bet=3,credits=120,lines={true,true,true},lamps=function(i) return i%2==0 end,message='PULL THE ARM'})
 dump(t,'slots-'..size[1]..'-idle')
 r:draw({positions={0.5,9.3,15.8},bet=5,credits=117,lines={true,true,true,true,true},pressed={max=true},lamps=function() return true end,message='GOOD LUCK!'})
 dump(t,'slots-'..size[1]..'-spin')
 r:draw({positions={9,8,8},bet=5,credits=197,lines={true},lamps=function() return true end,message='WINNER! 80 CREDITS',highlight=true})
 dump(t,'slots-'..size[1]..'-win')
 local start=os.epoch('utc'); local frames=0
 for n=1,40 do r:draw({positions={n*.4,n*.35,n*.3},bet=5,credits=1,message='x'}); frames=frames+1 end
 local fps=frames/math.max(.001,(os.epoch('utc')-start)/1000)
 print(('Rendered %dx%d at %.1f fps'):format(size[1],size[2],fps))
 assert(fps>=10,'Render throughput under 10 fps')
end
print('PASS rendered cabinet')
