--!nonstrict
-- Power Control bar [[widget]].
--
-- Sole data owner: polls dGPU sysfs, battery sysfs, and `cardwire get`, then
-- publishes to the "gpu" / "cardwire" / "battery" state channels the panel
-- watches. The panel bumps the "poke" channel after an action to force an
-- immediate re-poll. Click toggles the panel.

local SHOW_WATTAGE = noctalia.getConfig("show_wattage") ~= false
local SHOW_GPU_STATE = noctalia.getConfig("show_gpu_state") ~= false
local POLL_MS = (tonumber(noctalia.getConfig("poll_seconds")) or 10) * 1000

local trim = noctalia.string.trim

local gpu = { available = false }
local cardwire = { available = false, modes = {} }
local battery = { present = false }

local function readSys(path)
  if not noctalia.fileExists(path) then return nil end
  local content = noctalia.readFile(path)
  if not content then return nil end
  return trim(content)
end

-- ── dGPU ───────────────────────────────────────────────────────────────────

-- Empty pci_address setting: first display-class PCI device that is not the
-- boot VGA (the iGPU carries boot_vga=1).
local pciAddr = nil
local function detectPci()
  local cfg = noctalia.getConfig("pci_address")
  if type(cfg) == "string" and cfg ~= "" then
    pciAddr = cfg:match("^%x+:") == nil and cfg or (cfg:find("^0000:") and cfg or "0000:" .. cfg)
    return
  end
  local entries = noctalia.listDir("/sys/bus/pci/devices")
  if not entries then return end
  for _, name in entries do
    local base = "/sys/bus/pci/devices/" .. name
    local class = readSys(base .. "/class")
    if class and class:sub(1, 5) == "0x030" then
      local boot = readSys(base .. "/boot_vga")
      if boot ~= "1" then
        pciAddr = name
        return
      end
    end
  end
end

local function pollGpu()
  if not pciAddr then detectPci() end
  if not pciAddr then
    gpu = { available = false }
    return
  end
  local base = "/sys/bus/pci/devices/" .. pciAddr
  local state = readSys(base .. "/power_state")
  if not state then
    -- device gone from the bus (e.g. mode switch removed it): re-detect next poll
    if noctalia.getConfig("pci_address") == "" then pciAddr = nil end
    gpu = { available = false }
    return
  end
  gpu = {
    available = true,
    addr = pciAddr,
    state = state,
    runtime = readSys(base .. "/power/runtime_status") or "?",
    asleep = state:sub(1, 2) == "D3",
  }
end

-- ── Battery ────────────────────────────────────────────────────────────────

local batDir = nil
local function detectBattery()
  local entries = noctalia.listDir("/sys/class/power_supply")
  if not entries then return end
  for _, name in entries do
    local base = "/sys/class/power_supply/" .. name
    if name:sub(1, 3) == "BAT" and noctalia.fileExists(base .. "/capacity") then
      batDir = base
      return
    end
  end
end

local function acOnline()
  local entries = noctalia.listDir("/sys/class/power_supply")
  if not entries then return false end
  for _, name in entries do
    local base = "/sys/class/power_supply/" .. name
    if readSys(base .. "/type") == "Mains" and readSys(base .. "/online") == "1" then
      return true
    end
  end
  return false
end

local function pollBattery()
  if not batDir then detectBattery() end
  if not batDir or not noctalia.fileExists(batDir .. "/capacity") then
    batDir = nil
    battery = { present = false }
    return
  end
  local watts = nil
  local uw = tonumber(readSys(batDir .. "/power_now"))
  if uw then
    watts = uw / 1e6
  else
    local ua = tonumber(readSys(batDir .. "/current_now"))
    local uv = tonumber(readSys(batDir .. "/voltage_now"))
    if ua and uv then watts = ua * uv / 1e12 end
  end
  local full = tonumber(readSys(batDir .. "/energy_full")) or tonumber(readSys(batDir .. "/charge_full"))
  local design = tonumber(readSys(batDir .. "/energy_full_design")) or tonumber(readSys(batDir .. "/charge_full_design"))
  battery = {
    present = true,
    percent = tonumber(readSys(batDir .. "/capacity")) or 0,
    status = readSys(batDir .. "/status") or "?",
    limit = tonumber(readSys(batDir .. "/charge_control_end_threshold")),
    watts = watts,
    health = (full and design and design > 0) and math.min(100, math.floor(full / design * 100 + 0.5)) or nil,
    ac = acOnline(),
  }
end

-- ── cardwire ───────────────────────────────────────────────────────────────

local cwRunning = false
local function pollCardwire(done)
  if not noctalia.commandExists("cardwire") then
    cardwire = { available = false, modes = {} }
    if done then done() end
    return
  end
  if cwRunning then return end
  cwRunning = true
  noctalia.runAsync("cardwire get", function(res)
    cwRunning = false
    local out = res.stdout or ""
    if res.exitCode ~= 0 then
      cardwire = { available = false, modes = {} }
    else
      local mode = out:match("[Cc]urrent [Mm]ode:%s*(%S+)")
      local avail = out:match("[Aa]vailable [Mm]odes?:%s*([^\r\n]+)")
      local modes = {}
      if avail then
        for m in avail:gmatch("[%w_-]+") do table.insert(modes, m:lower()) end
      end
      cardwire = {
        available = mode ~= nil,
        mode = mode and mode:lower() or "?",
        modes = #modes > 0 and modes or { "integrated", "hybrid" },
      }
    end
    if done then done() end
  end)
end

-- ── Publish + render ───────────────────────────────────────────────────────

local function publish()
  noctalia.state.set("gpu", gpu)
  noctalia.state.set("cardwire", cardwire)
  noctalia.state.set("battery", battery)
end

-- One glyph per power state: zzz asleep, bolt-filled awake on AC, bolt awake on battery.
local function gpuLook()
  if not gpu.available then return "cpu-2", "on_surface/0.4" end
  if gpu.asleep then return "zzz", "on_surface" end
  if battery.present and not battery.ac then return "bolt", "error" end
  return "bolt-filled", "error"
end

local function render()
  local container = barWidget.isVertical() and ui.column or ui.row
  local glyphName, stateColor = gpuLook()
  local children = { ui.glyph({ name = glyphName, size = 14, color = stateColor }) }
  local showState = SHOW_GPU_STATE and gpu.available
  local showWatts = SHOW_WATTAGE and battery.present and battery.watts and battery.status == "Discharging"
  if showState then
    table.insert(children, ui.label({ text = gpu.state, fontSize = 11, fontWeight = "bold", color = stateColor }))
  end
  if showState and showWatts then
    table.insert(children, ui.label({ text = "|", fontSize = 11, color = "on_surface/0.4" }))
  end
  if showWatts then
    table.insert(children, ui.label({ text = string.format("%.1fW", battery.watts), fontSize = 11, fontWeight = "bold" }))
  end
  barWidget.render(container({ gap = 4, align = "center" }, children))
end

local function pollAll()
  pollGpu()
  pollBattery()
  pollCardwire(function()
    publish()
    render()
  end)
  publish()
  render()
end

function update()
  noctalia.setUpdateInterval(POLL_MS)
  pollAll()
end

noctalia.state.watch("poke", function()
  pollAll()
end)

function onClick()
  noctalia.togglePanel("aier9500/power-control:panel")
end

pollAll()
