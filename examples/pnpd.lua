local uv  = require "lluv"
local sip = require "voip.sip"

local LOCAL, GROUP, PORT, LOCAL_PORT = "192.168.1.25", "224.0.1.75", "5060", "1036"
local URL = "http://fusionpbx.domain.local/fusionpbx/app/provision/"

local srv = uv.udp():bind(LOCAL, PORT, {'reuseaddr'}, function(srv, err, host, port)
  if err then return print("BIND", err) end

  srv:set_membership(GROUP)

  local cli = uv.udp():bind(LOCAL, LOCAL_PORT)

  srv:start_recv(function(_, err, msg, flags, host, port)
    if err then return print("RECV", err) end

    local req = sip.new_message(msg)
    if (not req) or (req:getRequestLine() ~= 'SUBSCRIBE') then
      return
    end

    local via = req:getHeader('Via')
    if not via then return end

    via = via:match('SIP/.-/.-%s+([^; ]+)')
    if not via then return end
    local resp_ip, resp_port = via:match("^(.-):(%d+)$")
    if not resp_ip then
      resp_ip, resp_port = via, "5060"
    end

    local resp = sip.new_message{
      "SIP/2.0 200 OK";
      "Via: "            .. req:getHeader('Via');
      "Contact: "        .. req:getHeader('Contact');
      "From: "           .. req:getHeader('From');
      "To: "             .. req:getHeader('To');
      "Call-ID: "        .. req:getHeader('Call-ID');
      "CSeq: "           .. req:getHeader('CSeq');
      "Expires: "        .. "0";
      "Content-Length: " .. "0";
    }
    resp:addHeaderUriParameter('Contact', 'transport', 'tcp')
    resp:addHeaderUriParameter('Contact', 'handler', 'dum')

    cli:send(resp_ip, resp_port, tostring(resp), function(_, err, ...)
      print("SEND 200/OK", err, ...)
    end)

    local resp = sip.new_message({
      "NOTIFY "              .. req:getUri('Contact') .. " SIP/2.0";
      "Via: "                .. req:getHeader('Via');
      "Contact: "            .. '<sip:' .. LOCAL .. ':' .. LOCAL_PORT .. '>';
      "From: "               .. req:getHeader('From');
      "To: "                 .. req:getHeader('To');
      "Call-ID: "            .. req:getHeader('Call-ID');
      "CSeq: "               .. "3" .. " NOTIFY";
      "Event: "              .. req:getHeader('Event');
      "Subscription-State: " .. "terminated;reason=timeout";
      "Max-Forwards: "       .. "20";
      "Expires: "            .. "0";
      "Content-Length: "     .. "0";
    })
    resp:addHeaderUriParameter('Contact', 'transport', 'tcp')
    resp:addHeaderUriParameter('Contact', 'handler', 'dum')
    resp:setContentBody("application/url", {URL})

    cli:send(resp_ip, resp_port, tostring(resp), function(_, err, ...)
      print("NOTIFY ", err, ...)
    end)

  end)
end)

uv.run()
