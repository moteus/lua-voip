local async_socket = require "async_socket"
local timer        = require "async_socket.timer"
local SipCreateMsg = require "voip.sip.message".new

----------------------------------------------
local SIP_TRANSPORT = {} do

local cnn_method = {
  "bind","connect","close","idle","is_async",
  "send","sendto","recv","recvfrom","set_timeout",
  "timeout","local_host","local_port","remote_host",
  "remote_port", "is_closed", "is_connected"
}

for _, method_name in pairs(cnn_method) do
  SIP_TRANSPORT[method_name] = function(self, ...)
    return self.private_.cnn[method_name](self.private_.cnn, ...)
  end
end

function SIP_TRANSPORT:new(idle_hook)
  local cnn, err = async_socket.udp_client(idle_hook);
  if not cnn then return nil, err end
  local t = setmetatable({
    private_ = {
      timers = {
        T1 = 0.5;
        T2 = 64;
      };
      cnn = cnn;
      trace = function() end;
    }
  },{__index=self})
  return t
end

function SIP_TRANSPORT:trace(...)
  self.private_.trace(...)
end

function SIP_TRANSPORT:recv(timeout)
  local msg, err = self.private_.cnn:recv(timeout)
  self:trace("RECV")
  if not msg then
    self:trace("RECV ERROR:", msg, err)
    return nil, err
  end
  self:trace("RECV DONE:", msg)
  return SipCreateMsg(msg)
end

function SIP_TRANSPORT:recvfrom(timeout)
  local msg, err, port = self.private_.cnn:recvfrom(timeout)
  self:trace("RECVFROM")
  if not msg then
    self:trace("RECV ERROR:", msg, err)
    return nil, err
  end
  self:trace("RECV DONE:", msg, err, port)
  return SipCreateMsg(msg), err, port
end

local function is_resp_match(req,resp)
  local req_cseq = assert(req:getCSeq())
  local req_cid  = assert(req:getHeader('Call-ID'))

  local resp_cseq = resp:getCSeq()
  if type(resp_cseq) ~= 'number' then
    return nil, 'wrong cseq'
  end
  if resp_cseq < req_cseq then -- old response
    return nil, 'old cseq'
  end
  if resp:getHeader('Call-ID') ~= req_cid then
    return nil, 'wrong call-id'
  end
  return true
end

function SIP_TRANSPORT:recv_response(timeout, req)
  local rtimer
  if timeout then
    rtimer = timer:new()
    rtimer:set_interval(timeout * 1000)
    rtimer:start()
  end

  while true do
    local resp, err = self:recv(timeout)
    if not resp then return nil, err end

    if not resp:getResponseLine() then
      self:trace("INVALID SIP MESSAGE:", resp)
      return nil, "bad_sip_response", resp
    end

    if not req then
      return resp
    end

    local ok, err = is_resp_match(req, resp)
    if ok then return resp end
    self:trace("WRONG RESPONSE:", resp)

    if timeout then 
      if rtimer:rest() == 0 then
        return nil, 'timeout'
      end
      timeout = rtimer:rest() / 1000
    end
  end
end 

-- timeout используется для ожидания каждого очередного
-- сообщения. Общеее время может превышать timeout
function SIP_TRANSPORT:recv_not_1xx(timeout, req)
  local resp,err,msg
  while true do
    resp,err,msg  = self:recv_response(timeout, req)
    if not resp then return nil,err,msg end
    if not resp:isResponse1xx() then return resp end
  end
end

function SIP_TRANSPORT:send(timeout, msg)
  self:trace("SEND: ", msg)
  local ok, err = self.private_.cnn:send(timeout, tostring(msg))
  self:trace("SEND RESULT:", ok, err)
  return ok, err
end

function SIP_TRANSPORT:sendto(timeout, msg, host, port)
  self:trace("SEND: ", msg)
  local ok, err = self.private_.cnn:sendto(timeout, tostring(msg), host, port)
  self:trace("SEND RESULT:", ok, err)
  return ok, err
end

---
-- @return 
function SIP_TRANSPORT:send_recv_T1(msg)
  local TimerA=self.private_.timers.T1
  local TimerB=self.private_.timers.T2

  while true do
    local ok, err = self:send(nil, msg) -- infinity
    if not ok then return nil, err end

    local resp, raw_msg
    resp, err, raw_msg = self:recv_response(TimerA, msg)
    if resp then return resp
    elseif err ~= 'timeout' then 
      return nil, err, raw_msg
    end

    TimerA = TimerA * 2
    if TimerA > TimerB then return nil, 'timeout' end
  end
end

-- timeout - для ожидания окончательного ответа после предварительного
--    если был предварительный ответ
function SIP_TRANSPORT:send_recv_T1_not_1xx(timeout, msg)
  local resp, err, msg = self:send_recv_T1(msg)
  if not resp then
    return nil, err, msg
  end
  if not resp:isResponse1xx() then 
    return resp
  end
  return self:recv_not_1xx(timeout, msg)
end

end
----------------------------------------------

local _M = {}

_M.new = function(...) return SIP_TRANSPORT:new(...) end

return _M
