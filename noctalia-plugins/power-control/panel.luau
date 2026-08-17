--!nonstrict
-- Power Control [[panel]].
--
-- Thin client over the widget's "gpu" / "cardwire" / "battery" state channels.
-- Actions run cardwire/asusctl directly, then bump "poke" so the widget
-- re-polls at once instead of waiting out its interval.

local isOpen = false
local render

local function tr(key, subst)
  if subst then return noctalia.tr(key, subst) end
  return noctalia.tr(key)
end

local function poke()
  noctalia.state.set("poke", (tonumber(noctalia.state.get("poke")) or 0) + 1)
end

-- ── Actions ────────────────────────────────────────────────────────────────

local modeBusy = false
local function setMode(mode)
  local cw = noctalia.state.get("cardwire") or {}
  if modeBusy or mode == cw.mode then return end
  modeBusy = true
  noctalia.runAsync("cardwire set " .. mode, function(res)
    modeBusy = false
    if res.exitCode ~= 0 then
      noctalia.notifyError(tr("panel.mode_failed", { mode = mode }))
    end
    poke()
  end)
end

-- Sliders fire mid-drag: run one asusctl at a time, keep only the newest value.
local limitBusy, limitPending = false, nil
local function applyLimit(value)
  if limitBusy then
    limitPending = value
    return
  end
  limitBusy = true
  noctalia.runAsync("asusctl battery limit " .. tostring(value), function(res)
    limitBusy = false
    if res.exitCode ~= 0 then
      noctalia.notifyError(tr("panel.limit_failed"))
    end
    if limitPending then
      local queued = limitPending
      limitPending = nil
      applyLimit(queued)
    else
      poke()
    end
  end)
end

-- Panel-local override so the slider tracks the drag; cleared once sysfs
-- reports the applied value.
local draggedLimit = nil

function onLimitChange(value)
  local n = tonumber(value)
  if not n then return end
  n = math.floor(n + 0.5)
  draggedLimit = n
  applyLimit(n)
  render()
end

function onOneshot()
  noctalia.runAsync("asusctl battery oneshot", function(res)
    if res.exitCode ~= 0 then
      noctalia.notifyError(tr("panel.oneshot_failed"))
    else
      noctalia.notify(tr("panel.title"), tr("panel.oneshot_sent"))
    end
    poke()
  end)
end

function onCloseClicked()
  panel.close()
end

-- ── Sections ───────────────────────────────────────────────────────────────

local function header()
  return ui.row({ align = "center", gap = 6 }, {
    ui.glyph({ name = "cpu-2", size = 16, color = "primary" }),
    ui.label({ text = tr("panel.title"), flexGrow = 1, fontSize = 16, fontWeight = "bold", color = "on_surface" }),
    ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
  })
end

local function infoCard(labelText, valueText, valueColor)
  return ui.column({ flexGrow = 1, gap = 2, align = "center", paddingV = 8, radius = 10, fill = "surface_variant" }, {
    ui.label({ text = labelText, fontSize = 11, fontWeight = "bold", color = "primary" }),
    ui.label({ text = valueText, fontSize = 14, fontWeight = "bold", color = valueColor or "on_surface" }),
  })
end

local function gpuSection()
  local gpu = noctalia.state.get("gpu") or {}
  local cw = noctalia.state.get("cardwire") or {}
  local battery = noctalia.state.get("battery") or {}

  if not gpu.available and not cw.available then
    return ui.label({ text = tr("panel.no_gpu"), fontSize = 12, color = "on_surface_variant", textAlign = "center" })
  end

  local awakeColor = (battery.present and not battery.ac) and "error" or "on_surface"
  local stateColor = gpu.asleep and "primary" or awakeColor
  local children = {
    ui.label({ text = tr("panel.gpu_section"), fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }),
  }

  if gpu.available then
    table.insert(children, ui.row({ flexGrow = 1, gap = 8 }, {
      infoCard(tr("panel.gpu_state"), gpu.state .. " · " .. (gpu.asleep and tr("panel.gpu_idle") or tr("panel.gpu_active")), stateColor),
      infoCard(tr("panel.gpu_runtime"), gpu.runtime),
    }))
  end

  if cw.available then
    local buttons = {}
    for _, mode in ipairs(cw.modes or {}) do
      local active = mode == cw.mode
      table.insert(buttons, ui.button({
        key = "mode-" .. mode,
        text = mode,
        variant = active and "primary" or "ghost",
        flexGrow = 1,
        onClick = function() setMode(mode) end,
      }))
    end
    local rows = {}
    for i = 1, #buttons, 2 do
      local pair = { buttons[i] }
      if buttons[i + 1] then table.insert(pair, buttons[i + 1]) end
      table.insert(rows, ui.row({ flexGrow = 1, gap = 6 }, pair))
    end
    table.insert(children, ui.label({ text = tr("panel.cardwire_mode"), fontSize = 11, color = "on_surface_variant" }))
    table.insert(children, ui.column({ gap = 6 }, rows))
  else
    table.insert(children, ui.label({ text = tr("panel.no_cardwire"), fontSize = 11, color = "error" }))
  end

  return ui.column({ gap = 8 }, children)
end

local function batterySection()
  local battery = noctalia.state.get("battery") or {}
  if not battery.present then
    return ui.label({ text = tr("panel.no_battery"), fontSize = 12, color = "on_surface_variant", textAlign = "center" })
  end

  local statusKey = ({
    Charging = "panel.bat_charging",
    Discharging = "panel.bat_discharging",
    Full = "panel.bat_full",
    ["Not charging"] = "panel.bat_not_charging",
  })[battery.status]

  local children = {
    ui.label({ text = tr("panel.battery_section"), fontSize = 12, fontWeight = "bold", color = "on_surface_variant" }),
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "battery-charging", size = 18, color = battery.ac and "primary" or "on_surface" }),
      ui.label({ text = tostring(battery.percent) .. "%", fontSize = 18, fontWeight = "bold", color = "primary" }),
      ui.label({ text = statusKey and tr(statusKey) or battery.status, fontSize = 12, color = "on_surface_variant" }),
    }),
    ui.row({ flexGrow = 1, gap = 8 }, {
      infoCard(tr("panel.power"), battery.watts and string.format("%.1f W", battery.watts) or "—"),
      infoCard(tr("panel.health"), battery.health and (tostring(battery.health) .. "%") or "—",
        (battery.health and battery.health < 80) and "error" or "on_surface"),
    }),
  }

  local limit = draggedLimit or battery.limit
  if limit then
    if draggedLimit and battery.limit == draggedLimit then draggedLimit = nil end
    table.insert(children, ui.row({ align = "center", justify = "space_between" }, {
      ui.label({ text = tr("panel.charge_limit"), fontSize = 13, color = "on_surface" }),
      ui.label({ text = tostring(limit) .. "%", fontSize = 15, fontWeight = "bold", color = "primary" }),
    }))
    table.insert(children, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "20%", fontSize = 11, color = "on_surface_variant" }),
      ui.slider({ min = 20, max = 100, step = 5, value = limit, onChange = "onLimitChange" }),
      ui.label({ text = "100%", fontSize = 11, color = "on_surface_variant" }),
    }))
    table.insert(children, ui.button({
      text = tr("panel.oneshot"),
      glyph = "battery-charging",
      variant = "ghost",
      onClick = "onOneshot",
    }))
  else
    table.insert(children, ui.label({ text = tr("panel.no_limit"), fontSize = 11, color = "on_surface_variant" }))
  end

  return ui.column({ gap = 8 }, children)
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

render = function()
  if not isOpen then return end
  panel.render(ui.column({ gap = 12, padding = 12 }, {
    header(),
    gpuSection(),
    ui.separator({ thickness = 1, color = "outline/0.3", spacing = 4 }),
    batterySection(),
  }))
end

function onOpen(_context)
  isOpen = true
  poke()
  render()
end

function onClose()
  isOpen = false
  draggedLimit = nil
end

for _, channel in ipairs({ "gpu", "cardwire", "battery" }) do
  noctalia.state.watch(channel, function()
    if isOpen then render() end
  end)
end
