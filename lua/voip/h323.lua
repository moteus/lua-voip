
local function prequire(...)
  local ok, mod = pcall(require, ...)
  if not ok then return nil, mod end
  return mod, ...
end

local function mrequire(...)
  for i = 1, select("#", ...) do
    local mod, name = prequire((select(i, ...)))
    if mod then return mod, name end
  end
  error("can not load modules", 1)
end

local socket = require "socket"
local bit    = mrequire("bit", "bit32")

local function make_callid()
  local t = {}
  for i = 1, 16 do
    table.insert(t, math.random(255)-1)
  end
  return t
end

local function byte_1(n)
  return bit.band(n,0xFF)
end

local function byte_2(n)
  return bit.band(bit.rshift(n,8),0xFF)
end

assert(byte_1(0xAABB) == 0xBB)
assert(byte_2(0xAABB) == 0xAA)

local function tappend(to,...)
  for _,from in ipairs{...}do
    if type(from) == 'table' then
      for i,d in ipairs(from)do
        table.insert(to,d)
      end
    elseif type(from) == 'number' then
      table.insert(to,from)
    else
      error("tappend number or table", 0)
    end
  end
  return to
end

local function tset_string(to, pos, from)
  assert((#to-pos+1) >= #from)
  for i = 1,#from do
    to[i + pos - 1] = string.byte(string.sub(from,i,i))
  end
  return to
end

local function tnew(n)
  local t = {}
  for i = 1, n do t[i]=0x00 end
  return t
end

local function ticlone(src)
  local t = {}
  for i = 1, #src do t[i] = src[i] end
  return t
end

local function tcmp(lhs,rhs)
  if #lhs ~= #rhs then
    return false
  end

  for i = 1, #lhs do
    if lhs[i] ~= rhs[i] then
      return false
    end
  end

  return true
end

local function unpack_b(src, dst)
  dst = dst or {}
  for i = 1, #src do
    dst[#dst + 1] = string.byte(src, i)
  end
  return dst
end

---------------------------------------------------------
--
---------------------------------------------------------
local REQ_MT = {} do
REQ_MT.__index = REQ_MT
REQ_MT.__tostring = function(t)
  local msg = ticlone(t.data)
  msg[3] = byte_2(#msg)
  msg[4] = byte_1(#msg)
  table.foreach(msg, function(i,d) msg[i] = string.char(d) end)
  return table.concat(msg)
end

function REQ_MT:new(t)
  return setmetatable({data=(t or {})},self)
end

function REQ_MT:append_(info)
   tappend(self.data, info)
end

function REQ_MT:AddQ931mess(id, info)
  local msg = self.data
  local len = assert(#info)

  msg[#msg + 1] = id

  if(id==0x7E)then msg[#msg + 1] = byte_2(len) end
  msg[#msg + 1] = byte_1(len)

  tappend(msg, info)
  return self
end

-- заполняет поле длинной len значениями
-- в качестве значений могут быть байты или строки
function REQ_MT:AddString(id, len, ...)
  local argv, argc = {...}, select('#', ...)
  local t   = tnew(len);
  local pos = 1
  for i = 1, argc do
    local v = argv[i]
    assert(type(v) == 'string')
    tset_string(t, pos, v)
    pos = pos + #v
  end
  return self:AddQ931mess(id, t);
end

function REQ_MT:AddAni(TON, value)
  return self:AddString(0x6C, 31, string.char(TON), value)
end

function REQ_MT:AddDnis(TON, value)
  return self:AddString(0x70, 31, string.char(TON), value)
end

function REQ_MT:AddDisplayInfo(value)
  return self:AddString(0x28, 79,  value)
end

function REQ_MT:AddBearerCap(value)
  return self:AddQ931mess(0x04, value);
end

function REQ_MT:AddSetup(value)
  return self:AddQ931mess(0x7E, value);
end

function REQ_MT:AddCause(value)
  return self:AddQ931mess(0x08, value);
end

end
---------------------------------------------------------

local function RecvQ931(sock)
  local header, err= assert(sock:receive(4))
  if not header then return nil, err end
  local b1, b2 = string.byte(header,4), string.byte(header,3)
  local len = b1 + bit.lshift(b2, 8)
  local data, err = sock:receive(len - 4)
  if not data then return nil, err end

  local t = unpack_b(header)
  return REQ_MT:new(unpack_b(data, t))
end

local function MakeSetupMsg(DNIS,ANI,DI)
  local TON = 0x81
  local Setup = REQ_MT:new{
    -- TPKT
    0x03,       -- version
    0x00,       -- reserved
    0x00, 0x00, -- length (set later)
    -----------------------------------
    0x08,       -- Descriminator
    0x02,       -- Call reference flag: Message sent from originating side
    0x00, 0x01, -- Call reference
    0x05,       -- Message type: SETUP
  }

  Setup:AddBearerCap{0x88, 0xc0, 0xa5}
  Setup:AddDnis(TON, DNIS)
  Setup:AddAni(TON,ANI)
  Setup:AddDisplayInfo(DI)

  Setup:AddSetup(
    tappend(
      {
        0x05, -- Descriminator
        0x00, 0x00, 0x06, 
        0x00, 0x08, 0x91, 0x4a, 0x00, 0x03, -- version
        --0x00, 0x00
      },
      {
         0x01, 0x40, 0x08, 0x00, 0x34, 0x00, 0x36, 0x00, 0x37, 0x00, 
         0x39, 0x00, 0x39, 0x00, 0x39, 0x00, 0x37, 0x00, 0x38, 0x00, 0x31
      },
      make_callid(), -- conference ID

      0x00
    )
  )

  return tostring(Setup)
end

local function MakeReleaseMsg()
  --                                                                        |------|  Call reference
  local Release = REQ_MT:new{0x03, 0x00, 0x00, 0x00, 0x08, 0x02, 0x00, 0x01, 0x5a};
  Release:AddCause{0x80, 0x90};
  Release:AddSetup{0x05, 0x05, 0x00, 0x06, 0x00, 0x08, 0x91, 0x4a, 0x00, 0x03};
  return tostring(Release)
end

local function SendSetupRelease(ip, port, dnis, ani, di)
  local s, err = socket.connect(ip, port)
  if not s then return nil, err end
  local ok
  ok, err = s:send(MakeSetupMsg(dnis,ani,di))
  if not ok then
    s:close()
    return nil, err
  end

  ok, err = RecvQ931(s)
  if ok then s:send(MakeReleaseMsg()) end

  s:close()

  if not ok then return nil,err end
  return ok
end

local _M = {}

_M.SendSetupRelease = SendSetupRelease

return _M
