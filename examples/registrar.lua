---
-- Very basic SIP registrar server
-- it supports only one login/password

local sip         = require "voip.sip"

local cnn = sip.connection(function()end)
cnn:set_timeout(0.01)

local ok,err = cnn:bind("*", 5060)
if not ok then
  print("can not bind:", err)
  return
end

local us = sip.US(cnn)

local AUTH, PASS, REALM = "1000", "1234", "LoacalRealm"

local function Make200OK(req)
  local resp = sip.new_message{
    "SIP/2.0 200 OK";
    "Via: "     .. req:getHeader('Via');
    "From: "    .. req:getHeader('From');
    "To: "      .. req:getHeader('To');
    "Call-ID: " .. req:getHeader('Call-ID');
    "CSeq: "    .. req:getHeader('CSeq');
    "Expires: " .. req:getHeader('Expires');
    "Content-Length: 0";
  }
  return resp
end

local function Make401Unauthorized(req)
  local resp = sip.new_message{
    "SIP/2.0 401 Unauthorized";
    "Via: "      .. req:getHeader('Via');
    "From: "     .. req:getHeader('From');
    "To: "       .. req:getHeader('To');
    "Call-ID: "  .. req:getHeader('Call-ID');
    "CSeq: "     .. req:getHeader('CSeq');
    'WWW-Authenticate: Digest realm="' .. REALM .. '",nonce="' .. us.private_.gen.nonce() .. '",algorithm=MD5';
    "Content-Length: 0";
  }
  resp:addHeaderValueParameter("To",'tag', us.private_.gen.tag())
  return resp
end

local function Make403Forbidden(req)
  local resp = sip.new_message{
    "SIP/2.0 403 Forbidden";
    "Via: "      .. req:getHeader('Via');
    "From: "     .. req:getHeader('From');
    "To: "       .. req:getHeader('To');
    "Call-ID: "  .. req:getHeader('Call-ID');
    "CSeq: "     .. req:getHeader('CSeq');
    'WWW-Authenticate: Digest realm="' .. REALM .. '",nonce="' .. us.private_.gen.nonce() .. '",algorithm=MD5';
    "Content-Length: 0";
  }
  resp:addHeaderValueParameter("To",'tag', us.private_.gen.tag())
  return resp
end

local WORKING = true
while WORKING do repeat
  local req, host, port = cnn:recvfrom()

  if not req then
    if err ~= "timeout" then
      print("error", host)
      WORKING = false
    end
    break
  end

  if req:isPing() then
    print("PING", host, port) -- @todo sent back 
    cnn:sendto(nil, msg, host, port)
    break
  end

  print(req)

  if req:getRequestLine() ~= "REGISTER" then
    print("Unsupported request:", req:getRequestLine())
    
    -- @fixme set ACK
    
    local resp = Make403Forbidden(req)
    cnn:sendto(nil, resp, host, port)
    break
  end

  if req:getHeaderValueParameter("Via", "rport") then
    -- rfc 3581
    -- @todo reg-id and +sip.instance
    -- @todo set rport parameter in VIA for response
  else
    -- @fixme do we need use last VIA
    local uri  = req:getUri('contact')
    if uri then
      host = uri:match('sip:[^@]*@([^:]*)')
      port = uri:match('sip:[^@]*@[^:]*:([0-9]+)$') or '5060'
    end
  end

  if req:getHeader("Authorization") then
    --@fixme check that it valid nonce

    auth = us:check_auth_response(req, AUTH, PASS)
    print('CHECK AUTH:', auth)
    local resp = (auth and Make200OK or Make401Unauthorized)(req)
    cnn:sendto(nil, resp, host , port)
    break
  end

  if req:getHeader("Expires") == "0" then -- unregister
    local resp = Make200OK(req)
    cnn:sendto(nil, resp, host , port)
    break
  end

  local resp = Make401Unauthorized(req)
  cnn:sendto(nil, resp, host , port)
  break

until true end

cnn:close()
