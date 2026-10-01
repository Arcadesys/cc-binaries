local net=require('tables.net')
local M={}
function M.run(args)
 local command=args[1]
 if command=='setup' then return net.setup({table.unpack(args,2)}) end
 local c=net.read()
 if not c then
  print('Table network is not configured.')
  print('Table: tables setup table <wired-modem> <seat-ids...>')
  print('Seat:  tables setup seat <wired-modem> <table-id>')
  return
 end
 command=command or c.role
 assert(command==c.role,'This computer is configured as a '..c.role)
 local t=term.current()
 local ok,err=pcall(function()
  if command=='table' then require('tables.host').run(c) else require('tables.seat').run(c) end
 end)
 term.redirect(t); t.setBackgroundColor(colors.black); t.setTextColor(colors.white); t.clear(); t.setCursorPos(1,1)
 if not ok then error(err,0) end
end
return M
