local SipCreateMsg = require "voip.sip.message".new
local utils        = require "voip.sip.impl.utils"
local date         = require "date"

local format     = utils.format
local Generators = utils.generators
local SipDigest  = utils.SipDigest

----------------------------------------------
local SIP_US do

SIP_US = {}

function SIP_US:new(cnn)
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
    }
  },{__index=self})
  return t
end

function SIP_US:check_auth_response(req, user, pass)
  local auth  = req:getHeader("Authorization")
  if not auth then return false end

  local realm    = string.match(auth, 'realm[ ]*=[ ]*"([^"]+)"')
  local uri      = string.match(auth, 'uri[ ]*=[ ]*"([^"]+)"')
  local response = string.match(auth, 'response[ ]*=[ ]*"([^"]+)"')
  local realm    = string.match(auth, 'realm[ ]*=[ ]*"([^"]+)"')
  local nonce    = string.match(auth, 'nonce[ ]*=[ ]*"([^"]+)"')
  local algo     = string.match(auth, 'algorithm[ ]*=[ ]*([^, ]+)')
  if (not realm) or (not nonce) or (not algo) or (not uri) or (not response) or (not nonce) then
    return nil, "Unknown format auth header"
  end
  local DIGEST = SipDigest("REGISTER", algo, user or "anonymus", pass  or "", uri, realm, nonce);
  return DIGEST == response
end

end
----------------------------------------------

local _M = {}

_M.new = function(...) return SIP_US:new(...) end

return _M

