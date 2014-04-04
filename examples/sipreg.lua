local SIP = require "voip.sip"

local arg = {...}

local LOCAL_HOST = arg[1] or "*"
local LOCAL_PORT = arg[2] or "5080"

local HOST       = arg[3] or "127.0.0.1"
local PORT       = arg[4] or "5060"
local ANI        = arg[5] or "1000"
local LOGIN      = arg[6] or "1000"
local PASS       = arg[7] or "1234"

local counter = 0
local cnn = SIP.connection(function() counter = counter + 1 end)
cnn:set_timeout(0.01) -- 100ms

local ok,err = cnn:bind(LOCAL_HOST, LOCAL_PORT)
if not ok then 
  print("can not bind:", err)
  return
end
local sip = SIP.UA(cnn)

local status, msg = sip:reg(HOST, PORT, ANI, LOGIN, PASS)
cnn:close()

print("REG ON " .. HOST .. " :", status, msg)
print("COUNTER:", counter)

if status == 200 then
  print("PASSED!")
  os.exit(0)
end
print("FAIL!")
os.exit(-1)
