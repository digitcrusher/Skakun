local utils = {}

function utils.lock_globals()
  setmetatable(_G, {
    __newindex = function(table, key, value)
      error('cannot create new global variable: ' .. key)
    end,
    __index = function(table, key, value)
      error('undefined variable: ' .. key)
    end,
  })
end

function utils.unlock_globals()
  setmetatable(_G, nil)
end

function utils.hex_encode(string)
  local hex = ''
  for i = 1, #string do
    hex = hex .. string.format('%02x', string:byte(i, i))
  end
  return hex
end

function utils.hex_decode(hex)
  local string = ''
  for i = 1, #hex, 2 do
    string = string .. string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return string
end

return utils
