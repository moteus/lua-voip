local uv  = require "lluv"
local sip = require "voip.sip"
local log = require "log".new('trace',
  require "log.writer.stdout".new(),
  require "log.formatter.mix".new()
)

local config = {
  pnp_interface = "*";
  sua_interface = "192.168.1.25";
  url           = "http://fusionpbx.domain.local/fusionpbx/app/provision";
  vendor        = {
    grandstream = "${url}/cfg${mac}";
    escene      = "${url}/";
  };
}

local IS_WINDOWS = package.config:sub(1,1) == '\\'

local GROUP, PORT ="224.0.1.75", "5060"
local LOCAL, LOCAL_PORT

local function find_mac(req)
  local _, req_uri = req:getRequestLine()
  return    string.match(req_uri, '^sip:MAC%%%x%x([A-Fa-f0-9-]+)')
         or string.match(req_uri, '^sip:MAC:?([A-Fa-f0-9-]+)')
end

local function find_mac_self_test()
  assert('00135E874B49' == find_mac(sip.new_message'SUBSCRIBE sip:MAC:00135E874B49@intern.snom.de SIP/2.0'))
  assert('00135E874B49' == find_mac(sip.new_message'SUBSCRIBE sip:MAC00135E874B49@intern.snom.de SIP/2.0'))
  assert('00135E874B49' == find_mac(sip.new_message'SUBSCRIBE sip:MAC%3a00135E874B49@intern.snom.de SIP/2.0'))
end

local function apply_params(str, params)
  return (string.gsub(str, "(%$%b{})",function(key)
    key = key:sub(3,-2)
    return params[key] or ''
  end))
end

local function unquote(s)
  if s then
    if string.sub(s, 1, 1) == '"' then
      s = string.sub(s, 2, -2)
    end
    s = (string.gsub(s, "%%(%x%x)",function(ch)
      return (string.char(tonumber(ch, 16)))
    end))
  end
  return s
end

local cli = uv.udp():bind(config.sua_interface, config.local_port or 0, function(cli, err)
  if err then
    log.fatal('Can not create client socket: %s', tostring(err))
    return uv.stop()
  end

  LOCAL, LOCAL_PORT = cli:getsockname()

  cli:start_recv(function(_, err, msg, flags, host, port)
    if err then
      return log.fatal('server recv: %s', tostring(err))
    end
  end)
end)

local srv = uv.udp():bind(IS_WINDOWS and config.pnp_interface or GROUP, PORT, {'reuseaddr'}, function(srv, err, host, port)
  if err then
    log.fatal('Can not create server socket: %s', tostring(err))
    return uv.stop()
  end

  local ok, err = srv:set_membership(GROUP)
  if not ok then
    log.fatal('Can not add multicast membership: %s', tostring(err))
    return uv.stop()
  end

  log.info("Server started on: " .. host .. ':' .. port)
  log.info("SIP UA on : " .. LOCAL .. ':' .. LOCAL_PORT)
  log.info("Listen in membership: " .. GROUP)
  log.info("Provisioning URL: " .. config.url)

  srv:start_recv(function(_, err, msg, flags, host, port)
    if err then
      return log.fatal('server recv: %s', tostring(err))
    end

    log.trace("Recv from %s:%s\n%s", host, port, msg)

    local req = sip.new_message(msg)
    if (not req) or (req:getRequestLine() ~= 'SUBSCRIBE') then
      return
    end

    if false then
      local via = req:getHeader('Via')
      if not via then return end

      via = via:match('SIP/.-/.-%s+([^; ]+)')
      if not via then return end
      local resp_ip, resp_port = via:match("^(.-):(%d+)$")
      if not resp_ip then
        resp_ip, resp_port = via, "5060"
      end
    end

    local resp_ip, resp_port = host, port

    local params = {
      url     = config.url;
      mac     = find_mac(req);
      vendor  = unquote(req:getHeaderValueParameter('Event', 'vendor'));
      model   = unquote(req:getHeaderValueParameter('Event', 'model'));
      version = unquote(req:getHeaderValueParameter('Event', 'version'));
    }

    local vendor = params.vendor and string.lower(params.vendor)
    local url = vendor and config.vendor[vendor] or config.url
    url = apply_params(url, params)

    log.info(
      "Get request from %s:%s - mac: %s, vendor: %s, model: %s, version: %s",
      host, port,
      params.mac     or '----',
      params.vendor  or '----',
      params.model   or '----',
      params.version or '----'
    )

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

    resp = tostring(resp)
    log.trace("Send to %s:%s\n%s", resp_ip, resp_port, resp)

    cli:send(resp_ip, resp_port, resp, function(_, err, ...)
      if err then
        return log.error("Send 200/OK fail:%s", tostring(err))
      end
      log.debug("SEND 200/OK")
    end)

    local event = req:getHeader('Event') or "ua-profile"
    event = string.match(event, "^([^;]*)")

    local resp = sip.new_message{
      "NOTIFY "              .. req:getUri('Contact') .. " SIP/2.0";
      "Via: "                .. req:getHeader('Via');
      "Contact: "            .. '<sip:' .. LOCAL .. ':' .. LOCAL_PORT .. '>';
      "From: "               .. req:getHeader('From');
      "To: "                 .. req:getHeader('To');
      "Call-ID: "            .. req:getHeader('Call-ID');
      "CSeq: "               .. "3" .. " NOTIFY";
      "Event: "              .. event;
      "Subscription-State: " .. "terminated;reason=timeout";
      "Max-Forwards: "       .. "20";
      "Expires: "            .. "0";
      "Content-Length: "     .. "0";
    }
    resp:addHeaderUriParameter('Contact', 'transport', 'tcp')
    resp:addHeaderUriParameter('Contact', 'handler', 'dum')
    resp:setContentBody("application/url", url)

    log.info(
      "Send response to %s:%s - url: %s",
      resp_ip, resp_port, url
    )

    resp = tostring(resp)
    log.trace("Send to %s:%s\n%s", resp_ip, resp_port, resp)

    cli:send(resp_ip, resp_port, resp, function(_, err, ...)
      if err then
        return log.error("Send NOTIFY fail: %s", tostring(err))
      end
      log.debug("SEND NOTIFY")
    end)

  end)
end)

uv.run()
