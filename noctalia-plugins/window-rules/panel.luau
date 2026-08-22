--!nonstrict
-- Window Rules [[panel]].
--
-- List + edit screens over rules.luau's segment model for niri's
-- windowrules.kdl. All writes go through M.save (validate, backup, write);
-- edits stay in a local `draft` table and only touch a segment at Save.

local M = require("./rules.luau")

local REAL_PATH = "~/.config/niri/user/windowrules.kdl"

-- ── State ──────────────────────────────────────────────────────────────────

local isOpen = false
local render -- forward-declared: assigned near the bottom, called from
             -- every handler defined above it

local pluginDataDir = ""
local realPath = ""
local segments = {}
local fileHash = nil
local banner = nil -- {kind="readonly"|"stale"|"error", text=...}

local view = "list" -- "list" | "edit"
local busy = false -- guards every M.save call; also flips the Save label
local pendingDeleteIndex = nil -- segments index awaiting the confirm tap

local generation = 0 -- bumped on open/close/screen-switch; async callbacks
                      -- (save, focused-window fetch) capture it at dispatch
                      -- and skip touching UI state if it has since moved on

local editMode = "new" -- "new" | "existing"
local editIndex = nil -- segments index when editMode == "existing"
local editSession = 0 -- bumped per edit-screen entry; folded into every
                       -- field's key so a fresh rule never inherits a prior
                       -- rule's typed-but-unseeded input state
local appIdRev = 0 -- bumped only when the app-id input is reseeded by the
                    -- picker, since ui.input's `value` is seed-only
local draft = nil
local editError = nil
local appIdOptions = {}

-- ── Small helpers ──────────────────────────────────────────────────────────

local function blankToNil(s)
  if s == nil or s == "" then return nil end
  return s
end

-- ui.toggle/ui.select callbacks have been observed passing "true"/"false"
-- as strings (see onHover elsewhere in this codebase), so accept both.
local function toBool(v)
  return v == true or v == "true"
end

-- Escapes regex metacharacters so "^<id>$" matches the id literally.
local function regexEscape(s)
  return (s:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$|{}\\]", "\\%0"))
end

local function blankDraft()
  return {
    name = "", appId = "", title = "",
    openFloating = nil, openMaximized = nil, openFullscreen = nil, openFocused = nil,
    openOnWorkspace = "", openOnOutput = "",
    opacitySet = false, opacityPercent = 90,
    blockOutFrom = nil,
    columnWidthKind = nil, columnWidthValue = "",
    windowHeightKind = nil, windowHeightValue = "",
  }
end

local function seedDraftFromSegment(seg)
  local model = seg.model or {}
  local match = model.match or {}
  local cw = model.defaultColumnWidth
  local wh = model.defaultWindowHeight
  return {
    name = seg.name or "",
    appId = match.appId or "",
    title = match.title or "",
    openFloating = model.openFloating,
    openMaximized = model.openMaximized,
    openFullscreen = model.openFullscreen,
    openFocused = model.openFocused,
    openOnWorkspace = model.openOnWorkspace or "",
    openOnOutput = model.openOnOutput or "",
    opacitySet = model.opacity ~= nil,
    opacityPercent = model.opacity ~= nil and math.floor(model.opacity * 100 + 0.5) or 90,
    blockOutFrom = model.blockOutFrom,
    columnWidthKind = cw and cw.kind or nil,
    columnWidthValue = cw and tostring(cw.value) or "",
    windowHeightKind = wh and wh.kind or nil,
    windowHeightValue = wh and tostring(wh.value) or "",
  }
end

local function ruleTitle(seg)
  if seg.name and seg.name ~= "" then return seg.name end
  local match = seg.model.match or {}
  if match.appId and match.appId ~= "" then return match.appId end
  if match.title and match.title ~= "" then return match.title end
  return "Unnamed"
end

local function matchSummary(model)
  local match = model.match or {}
  if match.appId and match.title then
    return "app-id " .. match.appId .. "  ·  title " .. match.title
  elseif match.appId then
    return "app-id " .. match.appId
  elseif match.title then
    return "title " .. match.title
  end
  return "(no match set)"
end

-- Only fields the user has actually set get a chip -- tri-state false is
-- meaningful (niri applies it) so it shows just like true.
local function ruleChips(model)
  local chips = {}
  if model.openFloating ~= nil then table.insert(chips, "Float: " .. tostring(model.openFloating)) end
  if model.openMaximized ~= nil then table.insert(chips, "Maximized: " .. tostring(model.openMaximized)) end
  if model.openFullscreen ~= nil then table.insert(chips, "Fullscreen: " .. tostring(model.openFullscreen)) end
  if model.openFocused ~= nil then table.insert(chips, "Focused: " .. tostring(model.openFocused)) end
  if model.openOnWorkspace then table.insert(chips, "Workspace " .. model.openOnWorkspace) end
  if model.openOnOutput then table.insert(chips, "Output " .. model.openOnOutput) end
  if model.opacity ~= nil then
    table.insert(chips, "Opacity " .. tostring(math.floor(model.opacity * 100 + 0.5)) .. "%")
  end
  if model.blockOutFrom then table.insert(chips, "Block-out " .. model.blockOutFrom) end
  if model.defaultColumnWidth then
    table.insert(chips, "Width " .. model.defaultColumnWidth.kind .. " " .. tostring(model.defaultColumnWidth.value))
  end
  if model.defaultWindowHeight then
    table.insert(chips, "Height " .. model.defaultWindowHeight.kind .. " " .. tostring(model.defaultWindowHeight.value))
  end
  return chips
end

local function chipPill(text, key)
  return ui.column({ key = key, paddingV = 3, paddingH = 8, radius = 8, fill = "surface_variant" }, {
    ui.label({ text = text, fontSize = 10, color = "on_surface_variant" }),
  })
end

local function chipRows(chips)
  if #chips == 0 then return nil end
  local rows = {}
  local row = {}
  for i, text in ipairs(chips) do
    table.insert(row, chipPill(text, "chip-" .. i))
    if #row == 3 then
      table.insert(rows, ui.row({ key = "chiprow-" .. #rows, gap = 4 }, row))
      row = {}
    end
  end
  if #row > 0 then
    table.insert(rows, ui.row({ key = "chiprow-" .. #rows, gap = 4 }, row))
  end
  return ui.column({ gap = 4 }, rows)
end

-- ── Disk I/O ───────────────────────────────────────────────────────────────

local function loadFromDisk()
  local text = noctalia.readFile(realPath) or ""
  fileHash = M.hash(text)
  local result = M.parse(text)
  segments = result.segments
  if result.readonly then
    banner = { kind = "readonly", text = "File could not be parsed (" .. tostring(result.reason) .. "). Editing disabled." }
  else
    banner = nil
  end
end

-- Writes candidateSegments through M.save (async). `segments`/`fileHash`
-- change only on a successful reload, so a failed write leaves the
-- in-memory list (and any card still on screen) exactly as it was. If the
-- panel closed or the screen changed before the callback lands, `busy` is
-- still cleared but nothing else is touched -- the response no longer
-- belongs to whatever's on screen.
local function commitSegments(candidateSegments, onOk)
  if busy then return end
  busy = true
  render()
  local myGeneration = generation
  M.save(pluginDataDir, realPath, candidateSegments, fileHash, function(result)
    busy = false
    if myGeneration ~= generation then return end
    if result.ok then
      loadFromDisk()
      if onOk then onOk() end
    elseif result.stale then
      banner = { kind = "stale", text = "File changed on disk since this was loaded." }
    else
      banner = { kind = "error", text = result.stderr or "Save failed." }
      noctalia.notifyError(banner.text)
    end
    render()
  end)
end

-- ── List-screen actions ────────────────────────────────────────────────────

local function findAdjacentBlockIndex(idx, dir)
  local i = idx + dir
  local n = #segments
  while i >= 1 and i <= n do
    if segments[i].kind == "rule" or segments[i].kind == "opaque" then
      return i
    end
    i = i + dir
  end
  return nil
end

-- Moves a rule/opaque block past its nearest rule/opaque neighbor by
-- swapping the two array slots; every comment segment keeps its own slot
-- (and so its position in the file), simplest-correct per the plan.
local function onMoveClicked(idx, dir)
  pendingDeleteIndex = nil
  local other = findAdjacentBlockIndex(idx, dir)
  if not other then return end
  local candidate = {}
  for i, s in ipairs(segments) do candidate[i] = s end
  candidate[idx], candidate[other] = candidate[other], candidate[idx]
  commitSegments(candidate)
end

local function onDeleteConfirmed(idx)
  pendingDeleteIndex = nil
  local candidate = {}
  for i, s in ipairs(segments) do
    if i ~= idx then table.insert(candidate, s) end
  end
  commitSegments(candidate)
end

local function onDeleteClicked(idx)
  if pendingDeleteIndex == idx then
    onDeleteConfirmed(idx)
  else
    pendingDeleteIndex = idx
    render()
  end
end

-- ── Edit-screen model glue ─────────────────────────────────────────────────

local function cloneRuleSegment(seg)
  local modelCopy = {}
  for k, v in pairs(seg.model) do
    if type(v) == "table" then
      local vc = {}
      for k2, v2 in pairs(v) do vc[k2] = v2 end
      modelCopy[k] = vc
    else
      modelCopy[k] = v
    end
  end
  return { kind = "rule", raw = seg.raw, dirty = seg.dirty, name = seg.name, model = modelCopy }
end

local function applyDraftToSegment(seg, d)
  M.set_name(seg, d.name)
  M.set_match(seg, blankToNil(d.appId), blankToNil(d.title))
  M.set_field(seg, "openFloating", d.openFloating)
  M.set_field(seg, "openMaximized", d.openMaximized)
  M.set_field(seg, "openFullscreen", d.openFullscreen)
  M.set_field(seg, "openFocused", d.openFocused)
  M.set_field(seg, "openOnWorkspace", blankToNil(d.openOnWorkspace))
  M.set_field(seg, "openOnOutput", blankToNil(d.openOnOutput))
  M.set_field(seg, "blockOutFrom", d.blockOutFrom)
  M.set_field(seg, "opacity", d.opacitySet and (d.opacityPercent / 100) or nil)
  M.set_size(seg, "defaultColumnWidth", d.columnWidthKind, d.columnWidthKind and tonumber(d.columnWidthValue) or nil)
  M.set_size(seg, "defaultWindowHeight", d.windowHeightKind, d.windowHeightKind and tonumber(d.windowHeightValue) or nil)
end

-- Proportion is a fraction above 0 up to 1 (matching the raw KDL value niri
-- stores), not a percent; the input's hint text spells this out.
local FIXED_SIZE_MAX = 2147483647 -- 2^31 - 1: string.format("%d") wraps past this

local function validateDraft(d)
  local errors = {}
  if not (blankToNil(d.appId) or blankToNil(d.title)) then
    table.insert(errors, "Match: set an App ID or Title, or this rule matches nothing.")
  end
  local function checkSize(label, kind, valueStr)
    if kind == "fixed" then
      local n = tonumber(valueStr)
      if not n or n <= 0 or n ~= math.floor(n) or n > FIXED_SIZE_MAX then
        table.insert(errors, label .. ": fixed needs a whole pixel count from 1 to " .. FIXED_SIZE_MAX .. ".")
      end
    elseif kind == "proportion" then
      local n = tonumber(valueStr)
      if not n or n <= 0 or n > 1 then
        table.insert(errors, label .. ": proportion needs a number greater than 0, up to 1.")
      end
    end
  end
  checkSize("Column width", d.columnWidthKind, d.columnWidthValue)
  checkSize("Window height", d.windowHeightKind, d.windowHeightValue)
  return errors
end

local function loadAppIdOptions()
  noctalia.runAsync("niri msg -j windows", function(res)
    if res.exitCode ~= 0 then return end -- picker degrades silently to free text
    local decoded = noctalia.json.decode(res.stdout or "")
    if type(decoded) ~= "table" then return end
    local seen = {}
    local list = {}
    for _, w in ipairs(decoded) do
      if type(w) == "table" and type(w.app_id) == "string" and w.app_id ~= "" and not seen[w.app_id] then
        seen[w.app_id] = true
        table.insert(list, w.app_id)
      end
    end
    table.sort(list)
    appIdOptions = list
    if isOpen and view == "edit" then render() end
  end)
end

local function enterEdit(mode, idx, seed)
  pendingDeleteIndex = nil
  generation = generation + 1
  editMode = mode
  editIndex = idx
  draft = seed
  editError = nil
  editSession = editSession + 1
  appIdRev = 0
  view = "edit"
  loadAppIdOptions()
  render()
end

local function onEditClicked(idx)
  pendingDeleteIndex = nil
  enterEdit("existing", idx, seedDraftFromSegment(segments[idx]))
end

-- ── List-screen render ─────────────────────────────────────────────────────

local function opaqueCard(seg, idx)
  local firstLine = seg.raw:match("^[^\n]*") or seg.raw
  local buttons = {}
  local up = findAdjacentBlockIndex(idx, -1)
  local down = findAdjacentBlockIndex(idx, 1)
  if up then
    table.insert(buttons, ui.button({
      key = "up-" .. idx, glyph = "chevron-up", variant = "ghost", controlSize = "sm",
      tooltip = "Move up", onClick = function() onMoveClicked(idx, -1) end,
    }))
  end
  if down then
    table.insert(buttons, ui.button({
      key = "down-" .. idx, glyph = "chevron-down", variant = "ghost", controlSize = "sm",
      tooltip = "Move down", onClick = function() onMoveClicked(idx, 1) end,
    }))
  end
  return ui.column({ key = "card-" .. idx, gap = 4, padding = 8, radius = 10, fill = "surface_variant" }, {
    ui.row({ align = "center", gap = 6 }, {
      ui.label({ text = firstLine, flexGrow = 1, fontSize = 12, color = "on_surface", maxLines = 1 }),
      ui.label({ text = "read-only", fontSize = 10, color = "on_surface_variant" }),
    }),
    ui.row({ gap = 4 }, buttons),
  })
end

local function ruleCard(seg, idx)
  local model = seg.model or {}
  local isPendingDelete = pendingDeleteIndex == idx
  local buttonRow = {
    ui.button({
      key = "edit-" .. idx, glyph = "pencil", text = "Edit", variant = "ghost", controlSize = "sm",
      onClick = function() onEditClicked(idx) end,
    }),
    ui.button({
      key = "delete-" .. idx,
      text = isPendingDelete and "Confirm?" or nil,
      glyph = isPendingDelete and nil or "trash",
      variant = isPendingDelete and "destructive" or "ghost",
      controlSize = "sm",
      onClick = function() onDeleteClicked(idx) end,
    }),
  }
  local up = findAdjacentBlockIndex(idx, -1)
  local down = findAdjacentBlockIndex(idx, 1)
  if up then
    table.insert(buttonRow, ui.button({
      key = "up-" .. idx, glyph = "chevron-up", variant = "ghost", controlSize = "sm",
      tooltip = "Move up", onClick = function() onMoveClicked(idx, -1) end,
    }))
  end
  if down then
    table.insert(buttonRow, ui.button({
      key = "down-" .. idx, glyph = "chevron-down", variant = "ghost", controlSize = "sm",
      tooltip = "Move down", onClick = function() onMoveClicked(idx, 1) end,
    }))
  end

  local children = {
    ui.label({ text = ruleTitle(seg), fontSize = 13, fontWeight = "bold", color = "on_surface" }),
    ui.label({ text = matchSummary(model), fontSize = 11, color = "on_surface_variant" }),
  }
  local chips = chipRows(ruleChips(model))
  if chips then table.insert(children, chips) end
  table.insert(children, ui.row({ gap = 4 }, buttonRow))

  return ui.column({ key = "card-" .. idx, gap = 4, padding = 8, radius = 10, fill = "surface_variant" }, children)
end

local function bannerRow()
  if not banner then return nil end
  local children = { ui.label({ text = banner.text, flexGrow = 1, fontSize = 11, color = "error" }) }
  if banner.kind == "stale" or banner.kind == "readonly" then
    table.insert(children, ui.button({
      key = "banner-reload", text = "Reload", variant = "ghost", controlSize = "sm", onClick = "onReloadClicked",
    }))
  else
    table.insert(children, ui.button({
      key = "banner-dismiss", glyph = "x", variant = "ghost", controlSize = "sm", onClick = "onBannerDismiss",
    }))
  end
  return ui.row({ align = "center", gap = 6, padding = 6, radius = 8, fill = "surface_variant" }, children)
end

local function listHeader()
  local row = { ui.label({ text = "Window Rules", flexGrow = 1, fontSize = 16, fontWeight = "bold", color = "on_surface" }) }
  if not (banner and banner.kind == "readonly") then
    table.insert(row, ui.button({
      key = "hdr-focused", glyph = "target", variant = "ghost",
      tooltip = "Rule for focused window", onClick = "onFocusedRuleClicked",
    }))
    table.insert(row, ui.button({
      key = "hdr-add", glyph = "plus", variant = "primary", tooltip = "Add rule", onClick = "onAddClicked",
    }))
  end
  table.insert(row, ui.button({ key = "hdr-close", glyph = "close", variant = "ghost", onClick = "onCloseClicked" }))
  return ui.row({ align = "center", gap = 4 }, row)
end

local function listBody()
  local cards = {}
  for i, seg in ipairs(segments) do
    if seg.kind == "rule" then
      table.insert(cards, ruleCard(seg, i))
    elseif seg.kind == "opaque" then
      table.insert(cards, opaqueCard(seg, i))
    end
  end
  if #cards == 0 and not banner then
    table.insert(cards, ui.label({ text = "No window rules yet.", color = "on_surface_variant", textAlign = "center" }))
  end
  return ui.scroll({ flexGrow = 1, gap = 8 }, cards)
end

-- ── Edit-screen render ─────────────────────────────────────────────────────

local function sectionLabel(text)
  return ui.label({ text = text, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" })
end

local TRI_OPTIONS = { "Unset", "Yes", "No" }

local function triStateIndex(v)
  if v == true then return 1 elseif v == false then return 2 end
  return 0
end

local function triStateFromIndex(i)
  if i == 1 then return true elseif i == 2 then return false end
  return nil
end

local function triStateRow(label, field, key)
  return ui.row({ key = key, align = "center", gap = 6 }, {
    ui.label({ text = label, flexGrow = 1, fontSize = 12, color = "on_surface" }),
    ui.select({
      key = key .. "-sel",
      options = TRI_OPTIONS,
      selectedIndex = triStateIndex(draft[field]),
      onChange = function(value)
        draft[field] = triStateFromIndex(tonumber(value) or 0)
        render()
      end,
    }),
  })
end

local SIZE_KIND_OPTIONS = { "Unset", "Fixed", "Proportion" }

local function sizeKindIndex(k)
  if k == "fixed" then return 1 elseif k == "proportion" then return 2 end
  return 0
end

local function sizeKindFromIndex(i)
  if i == 1 then return "fixed" elseif i == 2 then return "proportion" end
  return nil
end

local function sizeRow(label, kindField, valueField, key)
  local kind = draft[kindField]
  local row = ui.row({ key = key, align = "center", gap = 6 }, {
    ui.label({ text = label, flexGrow = 1, fontSize = 12, color = "on_surface" }),
    ui.select({
      key = key .. "-kind",
      options = SIZE_KIND_OPTIONS,
      selectedIndex = sizeKindIndex(kind),
      onChange = function(value)
        draft[kindField] = sizeKindFromIndex(tonumber(value) or 0)
        render()
      end,
    }),
  })
  if not kind then return ui.column({ gap = 2 }, { row }) end
  local hint = kind == "fixed" and "pixels, e.g. 800" or "fraction above 0 up to 1, e.g. 0.5"
  local input = ui.input({
    key = key .. "-value-" .. editSession,
    value = draft[valueField],
    placeholder = hint,
    onChange = function(v) draft[valueField] = v; render() end,
  })
  return ui.column({ gap = 2 }, { row, input, ui.label({ text = hint, fontSize = 10, color = "on_surface_variant" }) })
end

local BLOCK_OUT_OPTIONS = { "Unset", "screencast", "screen-capture" }

local function blockOutIndex(v)
  if v == "screencast" then return 1 elseif v == "screen-capture" then return 2 end
  return 0
end

local function blockOutFromIndex(i)
  if i == 1 then return "screencast" elseif i == 2 then return "screen-capture" end
  return nil
end

local function nameSection()
  return ui.column({ gap = 6 }, {
    sectionLabel("Name"),
    ui.input({
      key = "name-" .. editSession,
      value = draft.name,
      placeholder = "Rule name (optional)",
      focus = true,
      onChange = function(v) draft.name = v; render() end,
    }),
  })
end

local function matchSection()
  local children = { sectionLabel("Match") }
  if #appIdOptions > 0 then
    local options = { "Pick from running windows…" }
    for _, id in ipairs(appIdOptions) do table.insert(options, id) end
    table.insert(children, ui.select({
      key = "appid-picker-" .. editSession,
      options = options,
      selectedIndex = 0,
      onChange = function(value)
        local idx = tonumber(value) or 0
        local appId = idx > 0 and appIdOptions[idx] or nil
        if appId then
          draft.appId = "^" .. regexEscape(appId) .. "$"
          appIdRev = appIdRev + 1
          render()
        end
      end,
    }))
  end
  table.insert(children, ui.input({
    key = "appid-" .. editSession .. "-" .. appIdRev,
    value = draft.appId,
    placeholder = "^org.example.App$",
    onChange = function(v) draft.appId = v; render() end,
  }))
  table.insert(children, ui.input({
    key = "title-" .. editSession,
    value = draft.title,
    placeholder = "Window title regex (optional)",
    onChange = function(v) draft.title = v; render() end,
  }))
  return ui.column({ gap = 6 }, children)
end

local function windowOpeningSection()
  return ui.column({ gap = 6 }, {
    sectionLabel("Window opening"),
    triStateRow("Open floating", "openFloating", "row-floating-" .. editSession),
    triStateRow("Open maximized", "openMaximized", "row-maximized-" .. editSession),
    triStateRow("Open fullscreen", "openFullscreen", "row-fullscreen-" .. editSession),
    triStateRow("Open focused", "openFocused", "row-focused-" .. editSession),
    ui.input({
      key = "workspace-" .. editSession,
      value = draft.openOnWorkspace,
      placeholder = "Workspace (optional)",
      onChange = function(v) draft.openOnWorkspace = v; render() end,
    }),
    ui.input({
      key = "output-" .. editSession,
      value = draft.openOnOutput,
      placeholder = "Output (optional)",
      onChange = function(v) draft.openOnOutput = v; render() end,
    }),
  })
end

local function dynamicsSection()
  local children = {
    sectionLabel("Dynamics"),
    ui.row({ align = "center", gap = 6 }, {
      ui.label({ text = "Opacity", flexGrow = 1, fontSize = 12, color = "on_surface" }),
      ui.toggle({
        key = "opacity-toggle-" .. editSession,
        checked = draft.opacitySet,
        onChange = function(v) draft.opacitySet = toBool(v); render() end,
      }),
    }),
  }
  if draft.opacitySet then
    table.insert(children, ui.row({ align = "center", gap = 8 }, {
      ui.slider({
        key = "opacity-slider-" .. editSession,
        min = 10, max = 100, step = 1,
        value = draft.opacityPercent,
        onChange = function(v)
          local n = tonumber(v)
          if n then draft.opacityPercent = math.floor(n + 0.5) end
          render()
        end,
      }),
      ui.label({ text = tostring(draft.opacityPercent) .. "%", fontSize = 12, color = "primary" }),
    }))
  end
  table.insert(children, ui.row({ align = "center", gap = 6 }, {
    ui.label({ text = "Block out from", flexGrow = 1, fontSize = 12, color = "on_surface" }),
    ui.select({
      key = "blockout-" .. editSession,
      options = BLOCK_OUT_OPTIONS,
      selectedIndex = blockOutIndex(draft.blockOutFrom),
      onChange = function(v)
        draft.blockOutFrom = blockOutFromIndex(tonumber(v) or 0)
        render()
      end,
    }),
  }))
  table.insert(children, sizeRow("Column width", "columnWidthKind", "columnWidthValue", "colwidth-" .. editSession))
  table.insert(children, sizeRow("Window height", "windowHeightKind", "windowHeightValue", "winheight-" .. editSession))
  return ui.column({ gap = 8 }, children)
end

local function editHeader()
  local title = editMode == "existing" and "Edit rule" or "New rule"
  return ui.row({ align = "center", gap = 6 }, {
    ui.button({ key = "edit-back", glyph = "arrow-left", variant = "ghost", onClick = "onCancelClicked" }),
    ui.label({ text = title, flexGrow = 1, fontSize = 16, fontWeight = "bold", color = "on_surface" }),
    ui.button({ key = "edit-close", glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
  })
end

local function editBody()
  return ui.scroll({ flexGrow = 1, gap = 10 }, {
    nameSection(), matchSection(), windowOpeningSection(), dynamicsSection(),
  })
end

local function editFooter()
  local children = {}
  if editError then
    table.insert(children, ui.label({ text = editError, color = "error", fontSize = 11 }))
  end
  table.insert(children, ui.row({ gap = 6 }, {
    ui.button({ key = "edit-cancel", text = "Cancel", variant = "ghost", flexGrow = 1, onClick = "onCancelClicked" }),
    ui.button({
      key = "edit-save", text = busy and "Saving…" or "Save", variant = "primary", flexGrow = 1,
      onClick = "onSaveClicked",
    }),
  }))
  return ui.column({ gap = 6 }, children)
end

-- ── Main render ────────────────────────────────────────────────────────────

render = function()
  if not isOpen then return end
  local children = {}
  if view == "edit" then
    table.insert(children, editHeader())
    local b = bannerRow(); if b then table.insert(children, b) end
    table.insert(children, editBody())
    table.insert(children, editFooter())
  else
    table.insert(children, listHeader())
    local b = bannerRow(); if b then table.insert(children, b) end
    table.insert(children, listBody())
  end
  panel.render(ui.column({ flexGrow = 1, gap = 10, padding = 12 }, children))
end

-- ── Global handlers (referenced by name from onClick strings) ──────────────

function onCloseClicked()
  panel.close()
end

function onAddClicked()
  enterEdit("new", nil, blankDraft())
end

function onFocusedRuleClicked()
  if banner and banner.kind == "readonly" then return end
  local myGeneration = generation
  noctalia.runAsync("niri msg -j focused-window", function(res)
    if myGeneration ~= generation then return end -- user already navigated elsewhere
    local appId = nil
    if res.exitCode == 0 then
      local decoded = noctalia.json.decode(res.stdout or "")
      if type(decoded) == "table" and type(decoded.app_id) == "string" and decoded.app_id ~= "" then
        appId = decoded.app_id
      end
    end
    local seed = blankDraft()
    if appId then
      seed.appId = "^" .. regexEscape(appId) .. "$"
      seed.name = appId
    end
    enterEdit("new", nil, seed) -- falls back to a blank rule when niri msg fails
  end)
end

function onCancelClicked()
  generation = generation + 1
  view = "list"
  draft = nil
  editError = nil
  render()
end

function onSaveClicked()
  if busy or not draft then return end
  local errors = validateDraft(draft)
  if #errors > 0 then
    editError = table.concat(errors, " ")
    render()
    return
  end
  editError = nil
  local segForSave = editMode == "existing" and cloneRuleSegment(segments[editIndex]) or M.new_rule()
  applyDraftToSegment(segForSave, draft)
  local candidate = {}
  for i, s in ipairs(segments) do candidate[i] = s end
  if editMode == "existing" then
    candidate[editIndex] = segForSave
  else
    table.insert(candidate, segForSave) -- new rules land last (highest niri precedence)
  end
  commitSegments(candidate, function()
    view = "list"
    editError = nil
    draft = nil
  end)
end

function onReloadClicked()
  generation = generation + 1
  loadFromDisk()
  view = "list"
  draft = nil
  editError = nil
  pendingDeleteIndex = nil
  render()
end

function onBannerDismiss()
  banner = nil
  render()
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function onOpen(_context)
  isOpen = true
  generation = generation + 1
  view = "list"
  pendingDeleteIndex = nil
  busy = false
  pluginDataDir = noctalia.pluginDataDir()
  realPath = noctalia.expandPath(REAL_PATH)
  loadFromDisk()
  render()
end

function onClose()
  isOpen = false
  generation = generation + 1
end
