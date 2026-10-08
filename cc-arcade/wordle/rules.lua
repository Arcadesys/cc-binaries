-- Daily Wordle rules: which word is today's, which guesses count, and how a guess scores.
local M={}
M.LENGTH=5
M.TRIES=6
M.words=require('wordle.words')
local DAY=86400000
-- Days since 1970-01-01 for a 'YYYY-MM-DD' date (civil-from-days, run backwards).
local function dayOf(date)
 local y,m,d=date:match('^(%d+)-(%d+)-(%d+)$')
 y,m,d=tonumber(y),tonumber(m),tonumber(d)
 if m<=2 then y=y-1 end
 local era=math.floor(y/400)
 local yoe=y-era*400
 local doy=math.floor((153*((m+9)%12)+2)/5)+d-1
 local doe=yoe*365+math.floor(yoe/4)-math.floor(yoe/100)+doy
 return era*146097+doe-719468
end
M.dayOf=dayOf
-- Today's puzzle for a UTC time in milliseconds: {number, date, word}. Puzzle 1 is the
-- first date in the list; past the last date the list wraps around.
function M.daily(ms)
 local list=M.words
 local first=dayOf(list[1][1])
 local today=math.floor(ms/DAY)
 local n=today-first
 local k=n%#list+1
 return {number=n+1,date=os.date('!%Y-%m-%d',today*86400),word=list[k][2]}
end
local accepted
-- Is word (upper case) something the game takes as a guess?
function M.valid(word)
 if not accepted then
  accepted={}
  for w in require('wordle.guesses'):gmatch('%u%u%u%u%u') do accepted[w]=true end
  for _,e in ipairs(M.words) do accepted[e[2]]=true end
 end
 return accepted[word]==true
end
-- Marks for each letter of guess: 'hit' (right place), 'near' (in the word, elsewhere) or
-- 'miss'. A letter guessed more often than the answer holds it is marked only that many
-- times, hits first, so LLAMA against PLANK marks the second L a hit and the first a miss.
function M.score(guess,answer)
 local marks,spare={},{}
 for i=1,#answer do
  local g,a=guess:sub(i,i),answer:sub(i,i)
  if g==a then marks[i]='hit' else spare[a]=(spare[a] or 0)+1 end
 end
 for i=1,#answer do
  if not marks[i] then
   local g=guess:sub(i,i)
   if (spare[g] or 0)>0 then marks[i]='near'; spare[g]=spare[g]-1 else marks[i]='miss' end
  end
 end
 return marks
end
-- Best mark seen so far for each letter, for colouring the keyboard.
local RANK={miss=1,near=2,hit=3}
function M.keyboard(rows)
 local best={}
 for _,r in ipairs(rows) do
  for i=1,#r.word do
   local c,m=r.word:sub(i,i),r.marks[i]
   if not best[c] or RANK[m]>RANK[best[c]] then best[c]=m end
  end
 end
 return best
end
return M
