-- Reel strips, paylines and paytable. Every stop is equally likely, so returns and the
-- largest possible win for each bet are computed exactly by visiting all 16^3 outcomes.
local M={}
M.size=16
M.strips={'CPBPRPCBPSBPRBCD','PCBPRCPBSPCRBPDC','BPCRPBCPSBPRCPDB'}
M.names={C='CHERRY',P='PLUM',B='BELL',R='BAR',S='SEVEN',D='DIAMOND'}
-- Three of a kind on a line, per credit on that line.
M.three={D=200,S=80,R=30,B=15,P=10,C=10}
-- Cherries reading from the left reel: one pays 1, two pay 3.
M.cherry={1,3}
-- Row offsets per reel (-1 top, 0 centre, 1 bottom). Each credit bet lights one more line.
M.lines={{0,0,0},{-1,-1,-1},{1,1,1},{-1,0,1},{1,0,-1}}
M.lineNames={'CENTER','TOP','BOTTOM','DIAGONAL','DIAGONAL'}
M.maxBet=#M.lines
function M.symbol(reel,stop)
 local i=stop%M.size+1
 return M.strips[reel]:sub(i,i)
end
function M.linePay(a,b,c)
 if a==b and b==c then return M.three[a] end
 if a=='C' then return b=='C' and M.cherry[2] or M.cherry[1] end
 return 0
end
function M.evaluate(stops,bet)
 local total,wins=0,{}
 for n=1,bet do
  local l=M.lines[n]; local s={}
  for r=1,3 do s[r]=M.symbol(r,stops[r]+l[r]) end
  local pay=M.linePay(s[1],s[2],s[3])
  if pay>0 then total=total+pay; wins[#wins+1]={line=n,pay=pay,symbols=s} end
 end
 return total,wins
end
function M.spin(random)
 random=random or math.random
 return {random(0,M.size-1),random(0,M.size-1),random(0,M.size-1)}
end
local cache
-- {maximum={per bet}, rtp=return per credit, hit=fraction of single-line spins that pay}
function M.stats()
 if cache then return cache end
 local maximum={}; for b=1,M.maxBet do maximum[b]=0 end
 local paid,hits,n=0,0,0
 for a=0,M.size-1 do for b=0,M.size-1 do for c=0,M.size-1 do
  local stops={a,b,c}; local running=0
  for bet=1,M.maxBet do
   local l=M.lines[bet]
   running=running+M.linePay(M.symbol(1,a+l[1]),M.symbol(2,b+l[2]),M.symbol(3,c+l[3]))
   if running>maximum[bet] then maximum[bet]=running end
   if bet==1 then paid=paid+running; if running>0 then hits=hits+1 end end
  end
  n=n+1
 end end end
 cache={maximum=maximum,rtp=paid/n,hit=hits/n}
 return cache
end
-- The house reservation for a spin: the most this bet can ever return.
function M.maxReturn(bet) return M.stats().maximum[bet] end
return M
