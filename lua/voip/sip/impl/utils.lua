local uuid = require "uuid"
local md5  = require "md5"

local ALGO = {
  md5 = assert(md5.digest or md5.sumhexa);
}

local function format(s, tab)
  -- %{name:format}
  s =  s:gsub('%%%{([%w_][%w_]*)%:([-0-9%.]*[cdeEfgGiouxXsq])%}',
            function(k, fmt)
              if tonumber(k) then 
                if tab[tonumber(k)] then
                  k = tonumber(k);
                end
              end
              if tab[k] then 
                return ("%"..fmt):format(tab[k])
              end
            end
  )
  return (
    -- %{name}
    s:gsub('%%%{([%w_][%w_]*)%}',
            function(k)
              if tonumber(k) then 
                if tab[tonumber(k)] then
                  k = tonumber(k);
                end
              end
              return tab[k]
            end
    )
  )
end;

local GreateUuidGenerator do
  if uuid.getUUID then 
    GreateUuidGenerator = function()
      return function()
        return uuid.getUUID()
      end
    end
  else
    GreateUuidGenerator = function()
      return function()
        return uuid.new("default")
      end
    end
  end
end

local function GreateSeqGenerator(n)
  n = n or 0
  return function()
    n = n + 1
    if n >= 2^31 then n = 1 end
    return n
  end
end

local new_rand do
  local ok, random = pcall(require, "random")
  if ok then
    new_rand = random.new
  else
    new_rand = function(seed)
      return math.random
    end
  end
end

local function GreateRandGenerator(len)
  local gen = new_rand(os.time())
  local function make_rand_sym()
    local i = gen(0,9)
    if i < 5  then
      return string.char(gen(string.byte('0'),string.byte('9')))
    end
    return string.char(gen(string.byte('a'),string.byte('z')))
  end

  return function()
    local res = ""
    for i = 1, len do
      res = res .. make_rand_sym()
    end
    return res
  end
end

local function SipDigest(method, algo, user, password, uri, realm, nonce)
  algo = string.lower(algo or "md5")
  local digest = assert(ALGO[algo])
  local A1 = digest(user .. ":" .. realm .. ":" .. password)
  local A2 = digest(method .. ":" .. uri)
  return digest(A1 .. ":" .. nonce .. ":" .. A2)
end

return {
  format = format;
  generators = {
    sequence = GreateSeqGenerator;
    random   = GreateRandGenerator;
    uuid     = GreateUuidGenerator;
  };
  SipDigest  = SipDigest;
}
