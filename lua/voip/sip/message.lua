local utils  = require "voip.sip.impl.utils"
local split  = utils.split
local format = utils.format

-------------------------------------------------------------------------------
-- message class
-------------------------------------------------------------------------------
local SipCreateMsg do
local REQ_MT = {}
REQ_MT.__index = REQ_MT

SipCreateMsg = function(msg)
  local t
  if type(msg) == 'string' then
    t = split(msg, "\r\n")
  else
    t = {}
    for k,v in ipairs(msg)do
      t[#t+1] = v
    end
  end

  t = setmetatable(t, REQ_MT)

  local len = t:getHeader('Content-Length')
  if not len or len == '0' then
    while t[#t] == '' do
      t[#t] = nil
    end
  end

  return t
end

function REQ_MT:__tostring()
  if not self[1] then
    return '\r\n\r\n'
  end

  local str = table.concat(self,'\r\n')

  if str:find('\r\n\r\n', 1, true) then -- has message end
    return str
  end

  return  str .. '\r\n\r\n'
end

local escape_lua_pattern
do
  local matches = {
    ["^"]  = "%^";
    ["$"]  = "%$";
    ["("]  = "%(";
    [")"]  = "%)";
    ["%"]  = "%%";
    ["."]  = "%.";
    ["["]  = "%[";
    ["]"]  = "%]";
    ["*"]  = "%*";
    ["+"]  = "%+";
    ["-"]  = "%-";
    ["?"]  = "%?";
    ["\0"] = "%z";
  }

  escape_lua_pattern = function(s) return (s:gsub(".", matches)) end
end

local function match_param(str, name)
  local v = str:match("[%s,;]" .. name .. "=([^%s,;]*)") or str:match("^" .. name .. "=([^%s,;]*)")
  if v then
    return v
  end
  if 
    str:match("[%s,;]" .. name .. "[%s,;]") or 
    str:match("^"      .. name .. "[%s,;]") or 
    str:match("[%s,;]" .. name .. "$")      or
    str:match("^"      .. name .. "$")
  then
    return ""
  end
end

local function remove_param(str, name)
  name = escape_lua_pattern(name)
  return 
    (str
      :gsub("([%s,;])" .. name .. "=[^%s,;]*[%s,;]+",'%1')
      :gsub("^"        .. name .. "=[^%s,;]*[%s,;]+",''  )
      :gsub("([%s,;])" .. name .. "=[^%s,;]*$"      ,''  )
      :gsub("^"        .. name .. "=[^%s,;]*$"      ,''  )

      :gsub("([%s,;])" .. name .. "[%s,;]+"         ,'%1')
      :gsub("^"        .. name .. "[%s,;]+"         ,''  )
      :gsub("[%s,;]+"  .. name .. "$"               ,''  )
      :gsub("^"        .. name .. "$"               ,''  )
    )
end

local function match_uri(str)
  local pat_1 = [[(%w+):([A-Za-z0-9.+-:]*)]]
  local pat_2 = [[(%w+):([A-Za-z0-9.+-]*@[A-Za-z0-9.+-:]*)]]
  local pat_3 = "<" .. pat_2 ..">"
  local pat_4 = "<" .. pat_2 .."[,;%s]+([^>]+)>"
  local pat_5 = "<" .. pat_1 ..">"
  local pat_6 = "<" .. pat_1 .."[,;%s]+([^>]+)>"

  local scheme, uri, param

  scheme, uri, param = str:match(pat_6)
  if scheme then
    return scheme, uri, param
  end
  scheme, uri = str:match(pat_5)
  if scheme then
    return scheme, uri
  end
  scheme, uri, param = str:match(pat_4)
  if scheme then
    return scheme, uri, param
  end
  scheme, uri = str:match(pat_3)
  if scheme then
    return scheme, uri
  end
  scheme, uri = str:match(pat_2) 
  if scheme then
    return scheme, uri
  end
  return str:match(pat_1)
end

function REQ_MT:applyParams(PARAM)
  for k,v in ipairs(self)do
    self[k] = format(self[k], PARAM)
  end
end

function REQ_MT:clone()
  local t = {}
  for k,v in ipairs(self)do
    t[#t+1] = v
  end
  return setmetatable(t,REQ_MT)
end

function REQ_MT:getHeader_idx_(name, i)
  local res = {}
  i = i or 2
  while(self[i] and self[i] ~= "")do
    local h,v = self[i]:match("^([^:]+):%s*(.*)$")
    if(h:upper() == name:upper())then
      return i
    end
    i = i + 1
  end
end

function REQ_MT:getRequestLine()
  if self[1] then
    return self[1]:match("^([%S]+)%s+([%S]+)%s+([Ss][Ii][Pp]/[%d.]+)$")
  end
end

function REQ_MT:getRequestUriParameter(name)
  local _,ruri = self:getRequestLine()
  local param = ruri and ruri:match(name .."=([^%s;]+)")
  return param
end

function REQ_MT:setRequestUri(uri)
  local method, _, ver = self:getRequestLine()
  if method then
    self[1] = method .. ' ' .. uri .. ' ' .. ver
  end
end

function REQ_MT:getResponseLine()
  if self[1] then
    local version, status, reason = self[1]:match("^([Ss][Ii][Pp]/[%d.]+) ([%S]+)%s+(.+)$")
    return version, tonumber(status) or status, reason
  end
end

function REQ_MT:getResponseCode()
  local _, status, reason = self:getResponseLine()
  return status, reason
end

function REQ_MT:isResponse1xx()
  local _, code = self:getResponseLine()
  return (code>=100)and(code<200)
end

function REQ_MT:isResponse2xx()
  local _, code = self:getResponseLine()
  return (code>=200)and(code<300)
end

function REQ_MT:isResponse3xx()
  local _, code = self:getResponseLine()
  return (code>=300)and(code<400)
end

function REQ_MT:isResponse4xx()
  local _, code = self:getResponseLine()
  return (code>=400)and(code<500)
end

function REQ_MT:isResponse5xx()
  local _, code = self:getResponseLine()
  return (code>=500)and(code<600)
end

function REQ_MT:isResponse6xx()
  local _, code = self:getResponseLine()
  return (code>=600)and(code<700)
end

function REQ_MT:setResponseCode(status, reason)
  local version, _, _ = self:getResponseLine()
  if version then
    self[1] = version .. ' ' .. tostring(status) .. ' ' .. reason
  end
end

local function split_header(str)
  local h,v = str:match("^([^:]+):%s*(.*)$")
  return h,v
end

function REQ_MT:getHeader(name)
  local res = self:getHeaderValues(name)
  if res then
    return table.concat(res,',')
  end
end

function REQ_MT:getHeaderValues(name)
  local res = {}
  local i = 2
  while(self[i] and self[i] ~= "")do
    local h,v = split_header(self[i])
    i = i + 1
    if(h:upper() == name:upper())then
      res[#res+1] = v
    end
  end
  if res[1] then
    return res
  end
end

function REQ_MT:getHeaderValueParameter(header,tag)
  local h = self:getHeader(header)
  if h then
    return match_param(h, tag)
  end
end

function REQ_MT:getHeaderUri(header)
  local h = self:getHeader(header)
  if h then
    return match_uri(h)
  end
end

function REQ_MT:getHeaderUriParameter(header,tag)
  local _,_,param = self:getHeaderUri(header)
  return match_param(param,tag)
end

function REQ_MT:addHeader(name,value)
  local i = 2
  while self[i] and self[i] ~= '' do
    i = i + 1
  end 
  table.insert(self, i, name .. ": " .. value)
end

function REQ_MT:addHeaderValueParameter(header,tag,value)
  local i = self:getHeader_idx_(header)
  if i then
    self[i] = self[i] .. ";" .. tag
    if value ~= nil then
      self[i] = self[i] .. "=" .. tostring(value)
    end
  end
end

function REQ_MT:addHeaderUriParameter(header,tag,value)
  local i = self:getHeader_idx_(header)
  if not i then return end

  local _, hvalue = split_header(self[i])
  if not hvalue then return end

  local scheme,uri,param = match_uri(hvalue)

  if scheme then
    local pat = scheme .. ":" .. uri
    if param then
      pat = pat .. "[,;%s]+" .. param
    end
    pat = "<?(" .. pat .. ")>?"
    local rep = '<%1;' .. tag
    if value ~= nil then
      rep = rep .. '='..tostring(value)
    end
    rep = rep .. ">"
    self[i] = self[i]:gsub(pat, rep)
  end
end

function REQ_MT:modifyHeader(name,value)
  local i = self:getHeader_idx_(name)
  if not i then 
    return i
  end
  self[i] = name .. ": " .. value
end

function REQ_MT:removeHeader(name)
  local i = self:getHeader_idx_(name)
  if not i then 
    return i
  end
  table.remove(self,i)
end

function REQ_MT:removeHeaderValue(header,tag)
  local i = self:getHeader_idx_(header)
  if not i then 
    return i
  end
  local h,v = self[i]:match("^([^:]+):%s*(.*)$")
  local v = remove_param(v, tag)
  if v == '' then
    table.remove(self, i)
  else
    self[i] = h .. ': ' .. v
  end
end

function REQ_MT:getData_idx_()
  local i, res = 2, {}

  while self[i] and #self[i] > 0 do
    i = i + 1
  end

  if (self[i] == '') and (self[i+1]) then
    return i + 1
  end
end

function REQ_MT:getContentBody(content_type)
  local ctype = self:getHeader("Content-Type")
  if (not ctype) or (ctype:lower() ~= content_type:lower()) then
    return 
  end
  local i = self:getData_idx_()
  if not i then return end

  local clen = self:getHeader("Content-Length")
  if clen then clen = tonumber(clen) end
  local body = table.concat(self, '\r\n', i)
  return body, clen 
end

function REQ_MT:setContentBody(content_type, content_body)
  if type(content_body) == 'string' then
    content_body = split(content_body, "\r\n")
  end

  local i = self:getData_idx_()
  if not i then table.insert(self, "")
  else for k = i, #self do self[k] = nil end end

  local body_len = 0
  for i, k in ipairs(content_body) do 
    self[#self + 1] = k
    body_len = body_len + #k + 2
  end
  if body_len > 0 then body_len = body_len - 2 end

  if content_type == 'application/sdp' and self[#self] ~= '' then
    self[#self + 1] = ''
    body_len = body_len + 2
  end

  self:removeHeader("Content-Type")
  self:addHeader("Content-Type", content_type)
  self:removeHeader("Content-Length")
  self:addHeader("Content-Length", body_len)

  return body_len
end

--returns true if the message is a request, the method is INVITE, 
-- and there is no tag parameter in the To header. 
-- Otherwise, false is returned. 
function REQ_MT:isInitialInviteRequest()
  local method = self:getRequestLine()
  if (not method) or (method:upper() ~= 'INVITE') then
    return nil
  end

  local totag = self:getHeaderValueParameter("to", "tag")
  if totag and totag ~= '' then
    return false
  end
  return true
end

-- This method returns true if the message is a request, the method is INVITE, 
-- and there is a tag parameter in the To header. Otherwise, false is returned. 
function REQ_MT:isReInviteRequest() 
  return not self:isInitialInviteRequest()
end

-- from first header
function REQ_MT:getUri(header)
  local header = self:getHeader(header)
  if not header then 
    return
  end
  local scheme,uri,param = match_uri(header)
  if scheme then
    return scheme .. ":" .. uri
  end
end

function REQ_MT:getUri2(header)
  local header = self:getHeader(header)
  if not header then 
    return
  end
  local scheme,uri,param = match_uri(header)
  return scheme,uri,param
end

function REQ_MT:getCSeq()
  local header = self:getHeader('CSeq')
  if not header then 
    return
  end
  local no, method = header:match("^%s*(%d+)%s*(.-)%s*$")
  if no then no = tonumber(no) end
  if no then return no, method end
  return header
end

function REQ_MT:isPing()
  return (#self == 0) or
    ((#self == 1) and (self[1] == "")) or
    ((#self == 2) and (self[1] == "") and (self[2] == ""))
end

end --
-------------------------------------------------------------------------------

-- do return end
---
--
local function self_test()
  -- Optional EOL
  local msg1 = SipCreateMsg{
    "INVITE sip:12345678900@192.168.10.10 SIP/2.0";
    "";
  }
  local msg2 = SipCreateMsg{
    "INVITE sip:12345678900@192.168.10.10 SIP/2.0";
  }
  assert(tostring(msg1) == tostring(msg2))

  -- getRequestLine
  local msg = SipCreateMsg{"INVITE sip:1234@10.10.10.1 SIP/2.0"}
  local method, ruri, version = msg:getRequestLine()
  assert(method == "INVITE")
  assert(ruri == "sip:1234@10.10.10.1")
  assert(version == "SIP/2.0")

  -- end of message without body
  local msg = SipCreateMsg{"INVITE sip:1234@10.10.10.1 SIP/2.0"}
  assert(tostring(msg) == ("INVITE sip:1234@10.10.10.1 SIP/2.0" .. "\r\n\r\n"))

  local msg = SipCreateMsg{"INVITE sip:1234@10.10.10.1 SIP/2.0\r\n\r\n"}
  assert(tostring(msg) == ("INVITE sip:1234@10.10.10.1 SIP/2.0" .. "\r\n\r\n"))

  -- end of message with body
  local msg = SipCreateMsg{"INVITE sip:1234@10.10.10.1 SIP/2.0"}
  msg:setContentBody('text/plain', '0123456789')
  local content = "Content-Type: text/plain\r\nContent-Length: 10\r\n\r\n0123456789"
  assert(tostring(msg) == ("INVITE sip:1234@10.10.10.1 SIP/2.0" .. "\r\n" .. content))

  -- end of message with body
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0",
    "Content-Type: text/plain",
    "Content-Length: 10",
    "",
    "0123456789",
  }
  local content = "Content-Type: text/plain\r\nContent-Length: 10\r\n\r\n0123456789"
  assert(tostring(msg) == ("INVITE sip:1234@10.10.10.1 SIP/2.0" .. "\r\n" .. content))

  -- getRequestUriParameter
  local msg = SipCreateMsg{"INVITE sip:1234@10.10.10.1;user=phone SIP/2.0"}
  local userparam = msg:getRequestUriParameter("user")
  assert(userparam == 'phone')

  -- message with body with eol
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0",
    "Content-Type: text/plain",
    "Content-Length: 20",
    "",
    "\r\n\r\n0123\r\n456789\r\n\r\n",
  }
  local content = "Content-Type: text/plain\r\nContent-Length: 20\r\n\r\n" .. "\r\n\r\n0123\r\n456789\r\n\r\n"
  assert(tostring(msg) == ("INVITE sip:1234@10.10.10.1 SIP/2.0" .. "\r\n" .. content))
  
  -- message with body with eol
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0"
  }
  msg:setContentBody('text/plain', "\r\n\r\n0123\r\n456789\r\n\r\n")
  local content = "Content-Type: text/plain\r\nContent-Length: 20\r\n\r\n" .. "\r\n\r\n0123\r\n456789\r\n\r\n"
  assert(tostring(msg) == ("INVITE sip:1234@10.10.10.1 SIP/2.0" .. "\r\n" .. content))

  -- setRequestUri
  local msg = SipCreateMsg{"INVITE sip:1234@10.10.10.1 SIP/2.0"}
  msg:setRequestUri("tel:1234")
  assert(msg[1] == "INVITE tel:1234 SIP/2.0")

  -- getResponseLine
  local msg = SipCreateMsg{
    "SIP/2.0 200 Ok";
    "CSeq: 102 INVITE";
  }
  local version, status, reason = msg:getResponseLine()
  assert(version == "SIP/2.0")
  assert(status == 200)
  assert(reason == "Ok")

  -- setResponseCode
  local msg = SipCreateMsg{
    "SIP/2.0 404 Not Found";
    "CSeq: 102 INVITE";
  }
  msg:setResponseCode(604, "Does Not Exist Anywhere")
  assert(msg[1] == "SIP/2.0 604 Does Not Exist Anywhere")
  assert(msg[2] == "CSeq: 102 INVITE")

  -- getHeader
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "To: <sip:1234@10.10.10.1>;";
    "Allow: UPDATE";
    "Allow: Ack,Cancel,Bye,Invite";
  }
  local allow = msg:getHeader("Allow")
  assert(allow == "UPDATE,Ack,Cancel,Bye,Invite")

  -- getHeaderValues
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "To: <sip:1234@10.10.10.1>;";
    "History-Info: <sip:UserB@hostB?Reason=sip;cause=408>;index=1";
    "History-Info: <sip:UserC@hostC?Reason=sip;cause=302>;index=1.1";
    "History-Info: <sip:UserD@hostD>;index=1.1.1";
  }
  local history_info = msg:getHeaderValues("History-Info")
  assert(history_info[1] == "<sip:UserB@hostB?Reason=sip;cause=408>;index=1")
  assert(history_info[2] == "<sip:UserC@hostC?Reason=sip;cause=302>;index=1.1")
  assert(history_info[3] == "<sip:UserD@hostD>;index=1.1.1")

  -- getHeaderValueParameter
  local msg = SipCreateMsg{
    "SIP/2.0 180 Ringing";
    "To: <sip:1234@10.10.10.1>;tag=32355SIPpTag0114";
  }
  local totag = msg:getHeaderValueParameter("To", "tag")
  assert( totag == "32355SIPpTag0114")

  -- getHeaderUriParameter
  local msg = SipCreateMsg{
    "SIP/2.0 180 Ringing";
    "To: <sip:1234@10.10.10.1;user=phone>;tag=32355SIPpTag0114";
  }
  local userparam = msg:getHeaderUriParameter("To", "user")
  assert(userparam == "phone")

  -- addHeader
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "To: <sip:1234@10.10.10.1>;";
    "Allow: Ack,Cancel,Bye,Invite";
  }
  msg:addHeader("Allow", "INFO")
  assert(msg:getHeader("Allow") == "Ack,Cancel,Bye,Invite,INFO")

  -- addHeaderValueParameter
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "Contact: <sip:1234@10.10.10.2>";
  }
  msg:addHeaderValueParameter("Contact", "color", "blue")
  assert(msg[1] == "INVITE sip:1234@10.10.10.1 SIP/2.0")
  assert(msg[2] == "Contact: <sip:1234@10.10.10.2>;color=blue")

  -- addHeaderUriParameter
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "P-Asserted-Identity: <sip:1234@10.10.10.1>";
  }
  msg:addHeaderUriParameter("P-Asserted-Identity", "user", "phone")
  assert(msg[1] == "INVITE sip:1234@10.10.10.1 SIP/2.0")
  assert(msg[2] == "P-Asserted-Identity: <sip:1234@10.10.10.1;user=phone>")

  -- addHeaderUriParameter
  local msg = SipCreateMsg{
    "SIP/2.0 200 OK";
    "Contact: <sip:192.168.10.67:5060>";
  }
  msg:addHeaderUriParameter("Contact", "transport", "tcp")
  assert(msg[1] == "SIP/2.0 200 OK")
  assert(msg[2] == "Contact: <sip:192.168.10.67:5060;transport=tcp>")

  -- addHeaderUriParameter
  local msg = SipCreateMsg{
    "SIP/2.0 200 OK";
    "Contact: sip:192.168.10.67:5060";
  }
  msg:addHeaderUriParameter("Contact", "transport", "tcp")
  assert(msg[1] == "SIP/2.0 200 OK")
  assert(msg[2] == "Contact: <sip:192.168.10.67:5060;transport=tcp>")

  -- modifyHeader
  local msg = SipCreateMsg{
    'INVITE sip:1234@10.10.10.1 SIP/2.0';
    'P-Asserted-Identity: "1234" <1234@10.10.10.1>';
  }
  -- Remove the display name from the PAI heade
  local pai = msg:getHeader("P-Asserted-Identity")
  local uri = string.match(pai, "(<.+>)")
  msg:modifyHeader("P-Asserted-Identity", uri)
  assert(msg[1] == 'INVITE sip:1234@10.10.10.1 SIP/2.0')
  assert(msg[2] == 'P-Asserted-Identity: <1234@10.10.10.1>')
  
  --removeHeader
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    'P-Asserted-Identity: "1234" <1234@10.10.10.1>';
    "Cisco-Guid: 1234-4567-1234";
    "Session-Expires:  1800";
  }
  msg:removeHeader("Cisco-Guid")
  assert(msg[1] == "INVITE sip:1234@10.10.10.1 SIP/2.0");
  assert(msg[2] == 'P-Asserted-Identity: "1234" <1234@10.10.10.1>');
  assert(msg[3] == "Session-Expires:  1800")
  assert(msg[4] == nil)

  --  removeHeaderValue
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "Supported: timer, replaces, X-cisco-srtp-fallback";
  }
  msg:removeHeaderValue("Supported", "X-cisco-srtp-fallback")
  assert(msg[1] == "INVITE sip:1234@10.10.10.1 SIP/2.0")
  assert(msg[2] == "Supported: timer, replaces")

  -- isInitialInviteRequest / isReInviteRequest
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "To: <sip:1234@10.10.10.1>";
  }
  assert(msg:isInitialInviteRequest())
  assert(not msg:isReInviteRequest())
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "To: <sip:1234@10.10.10.1>;tag=1234";
  }
  assert(not msg:isInitialInviteRequest())
  assert(msg:isReInviteRequest())

  -- getContentBody
  local msg = SipCreateMsg{
    "INVITE sip:12345678900@192.168.10.10 SIP/2.0";
    "Via: SIP/2.0/UDP 172.16.10.121:5060;branch=z9hG4bK1f47c5601992968773f3b";
    'From: "98765432100" <sip:98765432100@192.168.10.10>;tag=524797280-9453-12046';
    "To: <sip:12345678900@192.168.10.10>";
    "User-Agent: SomeVoipServer/1.3.4";
    "Call-ID: 7D643027-011c6965-1f47c560-005a0e@172.16.10.121";
    "CSeq: 19929 INVITE";
    "Contact: <sip:98765432100@172.16.10.121>";
    "Content-Type: application/sdp";
    "Content-Length: 237";
    "Date: Thu, 19 Apr 2012 09:15:30 GMT";
    "Allow: INVITE, ACK, CANCEL, OPTIONS, INFO, BYE";
    "";
    "v=0";
    "o=172.16.10.121 1334826930 1334826930 IN IP4 172.16.10.121";
    "s=SomeVoipServer/1.3.4";
    "c=IN IP4 172.16.10.121";
    "t=0 0";
    "m=audio 19904 RTP/AVP 18 101";
    "a=ptime:20";
    "a=rtpmap:18 G729/8000";
    "a=rtpmap:101 telephone-event/8000";
    "a=fmtp:101 0-15";
    "";
  }
  local sdp, sdp_len = msg:getContentBody('application/sdp')
  assert(sdp and (#sdp == sdp_len))

  -- setContentBody
  local msg = SipCreateMsg{
    "INVITE sip:12345678900@192.168.10.10 SIP/2.0";
  }
  msg:setContentBody("application/sdp", {
    "v=0";
    "o=172.16.10.121 1334826930 1334826930 IN IP4 172.16.10.121";
    "s=SomeVoipServer/1.3.4";
    "c=IN IP4 172.16.10.121";
    "t=0 0";
    "m=audio 19904 RTP/AVP 18 101";
    "a=ptime:20";
    "a=rtpmap:18 G729/8000";
    "a=rtpmap:101 telephone-event/8000";
    "a=fmtp:101 0-15";
  })
  local len = msg:getHeader('Content-Length')
  assert(tonumber(len) == 237)
  local sdp, sdp_len = msg:getContentBody('application/sdp')
  assert(sdp and (#sdp == 237))
  
  -- setContentBody
  local msg = SipCreateMsg{
    "INVITE sip:12345678900@192.168.10.10 SIP/2.0";
    "Via: SIP/2.0/UDP 172.16.10.121:5060;branch=z9hG4bK1f47c5601992968773f3b";
    'From: "98765432100" <sip:98765432100@192.168.10.10>;tag=524797280-9453-12046';
    "To: <sip:12345678900@192.168.10.10>";
    "User-Agent: SomeVoipServer/1.3.4";
    "Call-ID: 7D643027-011c6965-1f47c560-005a0e@172.16.10.121";
    "CSeq: 19929 INVITE";
    "Contact: <sip:98765432100@172.16.10.121>";
    "Date: Thu, 19 Apr 2012 09:15:30 GMT";
    "Allow: INVITE, ACK, CANCEL, OPTIONS, INFO, BYE";
    "";
  }
  local body = {
    "v=0";
    "o=172.16.10.121 1334826930 1334826930 IN IP4 172.16.10.121";
    "s=SomeVoipServer/1.3.4";
    "c=IN IP4 172.16.10.121";
    "t=0 0";
    "m=audio 19904 RTP/AVP 18 101";
    "a=ptime:20";
    "a=rtpmap:18 G729/8000";
    "a=rtpmap:101 telephone-event/8000";
    "a=fmtp:101 0-15";
    "";
  }
  local sdp_len = msg:setContentBody('application/sdp', body)
  assert(sdp_len and sdp_len == #msg:getContentBody('application/sdp'))

  -- setContentBody
  local msg = SipCreateMsg{
    "NOTIFY sip:192.168.10.67:5060 SIP/2.0";
  }
  local body = {
    "http://fusionpbx.domain.local/app/provision/index.php?mac={mac}/OEM.htm";
  }
  local sdp_len = msg:setContentBody('application/url', body)
  assert(sdp_len == 71)
  assert(sdp_len and sdp_len == #msg:getContentBody('application/url'))

  -- getUri
  local msg = SipCreateMsg{
    "INVITE sip:1234@10.10.10.1 SIP/2.0";
    "P-Asserted-Identity: <sip:1234@10.10.10.1>";
  }
  local uri = msg:getUri("P-Asserted-Identity")
  assert(uri ==  "sip:1234@10.10.10.1")

  -- getCSeq
  local msg = SipCreateMsg{
    "SIP/2.0 404 Not Found";
    "CSeq: 102 INVITE";
  }
  local code, method = msg:getCSeq()
  assert(code == 102)
  assert(method == "INVITE")

  -- getCSeq
  local msg = SipCreateMsg{
    "SIP/2.0 404 Not Found";
    "CSeq: 20";
  }
  local code, method = msg:getCSeq()
  assert(code == 20)
  assert(method == "")

  -- Params
  local msg = SipCreateMsg{
    "SIP/2.0 404 Not Found";
    "CSeq: %{CODE}";
  }
  msg:applyParams{ CODE = 20 }
  local code, method = msg:getCSeq()
  assert(code == 20)
  assert(method == "")

  -- getCSeq
  local msg = SipCreateMsg(
    "SIP/2.0 404 Not Found" .. "\r\n".. 
    "CSeq: 20"
  )
  local code, method = msg:getCSeq()
  assert(code == 20)
  assert(method == "")

  -- SIP PING
  local PING = '\r\n\r\n'
  local msg = SipCreateMsg(PING)
  assert(tostring(msg) == PING)
  assert(msg:isPing())
  assert(nil == msg:getRequestLine())

end

self_test()

local _M = {}

_M.new       = function (...) return SipCreateMsg(...) end

_M.self_test = self_test

return _M
