local SipCreateMsg = require "voip.sip.message".new
local utils        = require "voip.sip.impl.utils"
local date         = require "date"

local format     = utils.format
local Generators = utils.generators
local SipDigest  = utils.SipDigest

----------------------------------------------
local SIP_UA do

SIP_UA = {
  sip_patterns = {
    reg = SipCreateMsg{
      'REGISTER sip:%{DOMAIN}:%{DOMAIN_PORT} SIP/2.0',
      'Via: SIP/2.0/UDP %{HOST}:%{PORT};branch=z9hG4bK%{BRANCH}',
      'To: <sip:%{ANI}@%{DOMAIN}:%{DOMAIN_PORT}>',
      'From: <sip:%{ANI}@%{DOMAIN}:%{DOMAIN_PORT}>;tag=%{TAG}',
      'Contact: <sip:%{ANI}@%{HOST}:%{PORT}>;expires=60',
      'Call-ID: %{CALLID}@%{HOST}',
      'CSeq: %{CSEQ} REGISTER',
      'Date: %{DATE}',
      'User-Agent: RegGen',
      'Expires: 60',
      'Max-Forwards: 70',
      'Content-Length: 0',
      ''
    };
  }
}

function SIP_UA:new(cnn)
  local t = setmetatable({
    private_ = {
      gen = {
        branch = Generators.random(11);
        tag    = Generators.random(10);
        nonce  = Generators.random(32);
        callid = Generators.uuid();
        cseq   = Generators.sequence(0);
      };
      cnn = assert(cnn);
      timeout = 5;
    }
  },{__index=self})
  return t
end

function SIP_UA:connection()
  return self.private_.cnn
end

function SIP_UA:timeout() return self.private_.timeout end

function SIP_UA:set_timeout(value) self.private_.timeout = value end

function SIP_UA:init_param()
  return {
    HOST   = self.private_.cnn:local_host();
    PORT   = self.private_.cnn:local_port();

    CALLID = self.private_.gen.callid();
    BRANCH = self.private_.gen.branch();
    TAG    = self.private_.gen.tag();
    CSEQ   = self.private_.gen.cseq();
    DATE   = date():fmt('${rfc1123}');
  }
end

function SIP_UA:reg_impl(do_auth, host, port, ani, user, pass)
  local cnn = self.private_.cnn
  if cnn:is_closed() then return nil, 'closed' end

  local ok,err = cnn:connect(host, port)
  if not ok then return nil, err end

  local PARAM       = self:init_param()
  PARAM.DOMAIN      = host;
  PARAM.DOMAIN_PORT = port or 5060;
  PARAM.ANI         = ani or "anonymus";

  local req = self.sip_patterns.reg:clone()
  req:applyParams(PARAM)
  local resp, msg
  resp, err, msg = cnn:send_recv_T1(req)
  if not resp then return nil, err, msg end

  if do_auth then
    if resp:isResponse1xx() then 
      resp, err, msg = cnn:recv_not_1xx(self.private_.timeout)
      if not resp then
        return nil, resp, msg
      end
    end

    resp, err = self:authorize(req, resp, user, pass)
    if not resp then
      return nil,err
    end
  end

  return resp:getResponseCode()
end

function SIP_UA:authorize(req, resp, user, pass)
  if resp:getResponseCode() ~= 401 then
    return resp
  end

  local auth  = resp:getHeader("www-authenticate") or resp:getHeader("proxy-authenticate")
  if not auth then
    return nil, "No auth header in response"
  end

  local realm = string.match(auth, 'realm[ ]*=[ ]*"([^"]+)"')
  local nonce = string.match(auth, 'nonce[ ]*=[ ]*"([^"]+)"')
  local algo  = string.match(auth, 'algorithm[ ]*=[ ]*([^, ]+)')
  if (not realm) or (not nonce) or (not algo) then
    return nil, "Unknown format auth header: " .. auth
  end

  local method, ruri, ver = req:getRequestLine()
  local auth_header = format([[Digest username="%{USER}",realm="%{REALM}",uri="%{RURI}",response="%{DIGEST}",nonce="%{NONCE}",algorithm=%{ALGO}]], {
    REALM  = realm;
    NONCE  = nonce;
    USER   = user or "anonymus";
    PWD    = pass or "";
    RURI   = ruri;
    ALGO   = algo or "MD5";
    -- @fixme use appropriate method INVITE/REGISTER
    DIGEST = SipDigest("REGISTER", algo, user or "anonymus", pass  or "", ruri, realm, nonce);
  })

  req:modifyHeader("CSeq", self.private_.gen.cseq() .. " " .. method)
  req:addHeader("Authorization", auth_header)

  return self.private_.cnn:send_recv_T1_not_1xx(self.private_.timeout, req)
end

function SIP_UA:ping(host, port, ani)
  return self:reg_impl(false, host, port, ani)
end

function SIP_UA:reg(host, port, ani, user, pass)
  return self:reg_impl(true,host,port,ani,user,pass)
end

end
----------------------------------------------

local _M = {}

_M.new = function(...) return SIP_UA:new(...) end

return _M
