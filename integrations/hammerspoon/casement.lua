-- Hammerspoon helper: push live activities to Casement.
-- Usage: local casement = dofile(os.getenv("HOME") .. "/.hammerspoon/casement.lua")
--        casement.notify("Wi-Fi changed", hs.wifi.currentNetwork() or "Disconnected")
local M = {}

local function discovery()
  local f = io.open(os.getenv("HOME") .. "/Library/Application Support/Casement/api.json")
  if not f then return nil end
  local d = hs.json.decode(f:read("*a")); f:close()
  return d
end

function M.post(path, body)
  local d = discovery()
  if not d then return end
  hs.http.asyncPost("http://127.0.0.1:" .. d.port .. path, hs.json.encode(body),
    { ["Authorization"] = "Bearer " .. d.token, ["Content-Type"] = "application/json" }, function() end)
end

function M.notify(title, subtitle, icon) M.post("/v1/notify", { title = title, subtitle = subtitle, icon = icon }) end
function M.set(id, fields) fields.id = id; M.post("/v1/activities", fields) end

-- Example: announce Wi-Fi network changes.
M.wifiWatcher = hs.wifi.watcher.new(function()
  M.notify("Wi-Fi", hs.wifi.currentNetwork() or "Disconnected", "sf:wifi")
end)

return M
