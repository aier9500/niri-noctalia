-- Segment-based parser/serializer for niri's windowrules.kdl.
-- parse() splits the file into ordered segments (rule / opaque / comment),
-- each holding its original raw text. serialize() re-emits untouched
-- segments byte-verbatim and only regenerates segments edited through the
-- model API (set_field, set_match, ...). Written in plain Lua 5.1 syntax
-- (no `//` floor division, no `continue`, no Luau-only sugar) so it runs
-- under both a bare Lua interpreter and Noctalia's Luau runtime.

local M = {}

-- ============================================================
-- Low-level character scanner: strings, raw strings, comments.
-- Every skip_* function returns (endIndex, true) on success, where
-- endIndex is the index one past the consumed construct, or
-- (nil, false) on an unterminated construct.
-- ============================================================

local function skip_string(text, i)
  local n = #text
  local j = i + 1
  while j <= n do
    local c = text:sub(j, j)
    if c == "\\" then
      j = j + 2
    elseif c == '"' then
      return j + 1, true
    else
      j = j + 1
    end
  end
  return nil, false
end

local function is_raw_string_start(text, i)
  if text:sub(i, i) ~= "r" then
    return false
  end
  local j = i + 1
  while text:sub(j, j) == "#" do
    j = j + 1
  end
  return text:sub(j, j) == '"'
end

local function skip_raw_string(text, i)
  local n = #text
  local j = i + 1
  local hashes = 0
  while text:sub(j, j) == "#" do
    hashes = hashes + 1
    j = j + 1
  end
  if text:sub(j, j) ~= '"' then
    return nil, false
  end
  j = j + 1
  local closer = '"' .. string.rep("#", hashes)
  local closerLen = #closer
  while j <= n do
    if text:sub(j, j + closerLen - 1) == closer then
      return j + closerLen, true
    end
    j = j + 1
  end
  return nil, false
end

local function skip_block_comment(text, i)
  local n = #text
  local depth = 1
  local j = i + 2
  while j <= n do
    local two = text:sub(j, j + 1)
    if two == "/*" then
      depth = depth + 1
      j = j + 2
    elseif two == "*/" then
      depth = depth - 1
      j = j + 2
      if depth == 0 then
        return j, true
      end
    else
      j = j + 1
    end
  end
  return nil, false
end

-- Only handles the escapes KDL strings actually need here: \\ \" \n \t \r
-- \b \f. Any other escape sequence returns nil (caller marks unsupported).
local function unescape_kdl_string(inner)
  local out = {}
  local i = 1
  local n = #inner
  while i <= n do
    local c = inner:sub(i, i)
    if c == "\\" then
      local nc = inner:sub(i + 1, i + 1)
      local mapped = ({ ["\\"] = "\\", ['"'] = '"', n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[nc]
      if not mapped then
        return nil
      end
      table.insert(out, mapped)
      i = i + 2
    else
      table.insert(out, c)
      i = i + 1
    end
  end
  return table.concat(out)
end

local function quote_kdl_string(s)
  local escaped = s:gsub("\\", "\\\\")
  escaped = escaped:gsub('"', '\\"')
  return '"' .. escaped .. '"'
end

local function is_ws(c)
  return c == " " or c == "\t" or c == "\r"
end

local function is_stop_char(c)
  return c == "" or c == " " or c == "\t" or c == "\n" or c == "\r" or c == "{" or c == "}" or c == ";" or c == "="
end

-- ============================================================
-- Node parser. A "node list" is a KDL sibling sequence (top level of
-- the document, or the body of a { } block) -- both share one grammar,
-- so parse_node_list/parse_one_node recurse into each other for nested
-- blocks (window-rule's children, default-column-width's { fixed N; }).
-- ============================================================

local parse_node_list, parse_one_node

-- Reads one bare token (identifier/number/keyword) starting at i.
-- Stops before whitespace, {, }, ;, =, or a comment opener.
local function read_bare(text, i)
  local j = i
  local n = #text
  while j <= n do
    local c = text:sub(j, j)
    if is_stop_char(c) then
      break
    end
    local two = text:sub(j, j + 1)
    if two == "//" or two == "/*" then
      break
    end
    j = j + 1
  end
  return text:sub(i, j - 1), j
end

-- Parses one value (quoted string, raw string, or bare true/false/number)
-- starting at i. Returns {value=, kind="string"|"bool"|"number"|"raw"|"unknown"}.
-- kind "raw" and "unknown" both set unsupported=true via the returned flag.
local function read_value(text, i)
  local c = text:sub(i, i)
  if c == '"' then
    local stop, ok = skip_string(text, i)
    if not ok then
      return nil, nil, false, "unterminated string"
    end
    local inner = text:sub(i + 1, stop - 2)
    local uv = unescape_kdl_string(inner)
    return { value = uv, kind = "string", unsupported = uv == nil }, stop, true
  elseif c == "r" and is_raw_string_start(text, i) then
    local stop, ok = skip_raw_string(text, i)
    if not ok then
      return nil, nil, false, "unterminated raw string"
    end
    return { value = text:sub(i, stop - 1), kind = "raw", unsupported = true }, stop, true
  else
    local bare, j = read_bare(text, i)
    if bare == "" then
      return nil, nil, false, "unexpected character"
    end
    if bare == "true" then
      return { value = true, kind = "bool" }, j, true
    elseif bare == "false" then
      return { value = false, kind = "bool" }, j, true
    else
      local num = tonumber(bare)
      if num then
        return { value = num, kind = "number" }, j, true
      end
      return { value = bare, kind = "unknown", unsupported = true }, j, true
    end
  end
end

-- One node: name, then args/props up to `{` (children), `;`, newline,
-- the enclosing `}`, or EOF. `unsupported` marks a value this module's
-- managed model can't represent (raw string, unparsable bare token).
parse_one_node = function(text, i)
  local start = i
  local n = #text
  local isSlashdash = false
  if text:sub(i, i + 1) == "/-" then
    isSlashdash = true
    i = i + 2
  end

  -- name: quoted or bare
  local nameStart = i
  if text:sub(i, i) == '"' then
    local stop, ok = skip_string(text, i)
    if not ok then
      return nil, nil, false, "unterminated string in node name"
    end
    i = stop
  else
    local _, j = read_bare(text, i)
    i = j
  end
  local name = text:sub(nameStart, i - 1)

  local args = {}
  local props = {}
  local unsupported = false
  local children = nil

  while true do
    if i > n then
      break
    end
    local c = text:sub(i, i)
    if is_ws(c) then
      i = i + 1
    elseif c == "\n" then
      break
    elseif text:sub(i, i + 1) == "//" then
      -- comment on the node's own line, outside any string: this module
      -- can't preserve it through a regenerate, so the node is unsupported
      unsupported = true
      local nl = text:find("\n", i, true)
      i = nl and (nl + 1) or (n + 1)
      break
    elseif text:sub(i, i + 1) == "/*" then
      unsupported = true
      local ni, ok = skip_block_comment(text, i)
      if not ok then
        return nil, nil, false, "unterminated block comment"
      end
      i = ni
    elseif c == "{" then
      local elems, ni, ok, err = parse_node_list(text, i + 1, true)
      if not ok then
        return nil, nil, false, err
      end
      children = elems
      i = ni
      break
    elseif c == ";" then
      i = i + 1
      break
    elseif c == "}" then
      break -- belongs to the enclosing block
    elseif c == '"' or (c == "r" and is_raw_string_start(text, i)) then
      -- quoted or raw string is always a positional arg in this grammar
      local val, j, ok, err = read_value(text, i)
      if not ok then
        return nil, nil, false, err
      end
      i = j
      if val.unsupported then
        unsupported = true
      end
      table.insert(args, { value = val.value, kind = val.kind })
    else
      local bare, j = read_bare(text, i)
      if bare == "" then
        return nil, nil, false, "unexpected character"
      end
      i = j
      if text:sub(i, i) == "=" then
        -- bare token directly followed by '=' -> property key (any identifier)
        local key = bare
        i = i + 1
        local val, j2, ok, err = read_value(text, i)
        if not ok then
          return nil, nil, false, err
        end
        i = j2
        if val.unsupported then
          unsupported = true
        end
        props[key] = { value = val.value, kind = val.kind }
      elseif bare == "true" then
        table.insert(args, { value = true, kind = "bool" })
      elseif bare == "false" then
        table.insert(args, { value = false, kind = "bool" })
      else
        local num = tonumber(bare)
        if num then
          table.insert(args, { value = num, kind = "number" })
        else
          unsupported = true
          table.insert(args, { value = bare, kind = "unknown" })
        end
      end
    end
  end

  local node = {
    name = name,
    is_slashdash = isSlashdash,
    raw = text:sub(start, i - 1),
    args = args,
    props = props,
    unsupported = unsupported,
    children = children,
  }
  return node, i, true
end

-- Sibling sequence: gaps (whitespace/comments, kept verbatim) interleaved
-- with nodes. stopAtBrace=true consumes a trailing top-level `}` (for a
-- node's children block); stopAtBrace=false scans to EOF (top level).
parse_node_list = function(text, i, stopAtBrace)
  local elements = {}
  local gapStart = i
  local n = #text
  while true do
    if i > n then
      if stopAtBrace then
        return nil, nil, false, "unexpected end of file, expected }"
      end
      if i > gapStart then
        table.insert(elements, { kind = "gap", text = text:sub(gapStart, i - 1) })
      end
      return elements, i, true
    end
    local c = text:sub(i, i)
    if is_ws(c) or c == "\n" then
      i = i + 1
    elseif text:sub(i, i + 1) == "//" then
      local nl = text:find("\n", i, true)
      i = nl and (nl + 1) or (n + 1)
    elseif text:sub(i, i + 1) == "/*" then
      local ni, ok = skip_block_comment(text, i)
      if not ok then
        return nil, nil, false, "unterminated block comment"
      end
      i = ni
    elseif stopAtBrace and c == "}" then
      if i > gapStart then
        table.insert(elements, { kind = "gap", text = text:sub(gapStart, i - 1) })
      end
      return elements, i + 1, true
    else
      if i > gapStart then
        table.insert(elements, { kind = "gap", text = text:sub(gapStart, i - 1) })
      end
      local node, ni, ok, err = parse_one_node(text, i)
      if not ok then
        return nil, nil, false, err
      end
      table.insert(elements, { kind = "node", node = node })
      i = ni
      gapStart = i
    end
  end
end

-- ============================================================
-- Managed-set classifier: builds a rule model from a window-rule node's
-- children, or returns nil if anything falls outside the v1 managed set
-- (caller then keeps the node opaque).
-- ============================================================

local function has_comment_marker(gapText)
  return gapText:find("//", 1, true) ~= nil or gapText:find("/*", 1, true) ~= nil
end

local BOOL_FIELDS = {
  ["open-floating"] = "openFloating",
  ["open-maximized"] = "openMaximized",
  ["open-fullscreen"] = "openFullscreen",
  ["open-focused"] = "openFocused",
}

local STRING_FIELDS = {
  ["open-on-workspace"] = "openOnWorkspace",
  ["open-on-output"] = "openOnOutput",
  ["block-out-from"] = "blockOutFrom",
}

local SIZE_FIELDS = {
  ["default-column-width"] = "defaultColumnWidth",
  ["default-window-height"] = "defaultWindowHeight",
}

local function try_build_size_model(children)
  local found = nil
  for _, el in ipairs(children) do
    if el.kind == "gap" then
      if has_comment_marker(el.text) then
        return nil
      end
    else
      if found then
        return nil -- more than one child node
      end
      local child = el.node
      if child.is_slashdash then
        return nil
      end
      if child.name ~= "fixed" and child.name ~= "proportion" then
        return nil
      end
      if child.unsupported or child.children ~= nil then
        return nil
      end
      if #child.args ~= 1 or child.args[1].kind ~= "number" then
        return nil
      end
      if next(child.props) ~= nil then
        return nil
      end
      found = { kind = child.name, value = child.args[1].value }
    end
  end
  return found
end

local function try_build_rule_model(node)
  if node.unsupported or #node.args > 0 or next(node.props) ~= nil then
    return nil -- window-rule itself takes no args/props in v1
  end
  if not node.children then
    return nil
  end

  local model = {}
  local matchSeen = false

  for _, el in ipairs(node.children) do
    if el.kind == "gap" then
      if has_comment_marker(el.text) then
        return nil
      end
    else
      local child = el.node
      if child.is_slashdash then
        return nil
      end

      if child.name == "match" then
        if matchSeen or child.unsupported or child.children ~= nil or #child.args > 0 then
          return nil
        end
        matchSeen = true
        local m = {}
        for k, v in pairs(child.props) do
          if k == "app-id" and v.kind == "string" then
            m.appId = v.value
          elseif k == "title" and v.kind == "string" then
            m.title = v.value
          else
            return nil -- tri-state matcher prop, or unsupported value
          end
        end
        model.match = m
      elseif child.name == "exclude" then
        return nil
      elseif BOOL_FIELDS[child.name] then
        local field = BOOL_FIELDS[child.name]
        if child.unsupported or child.children ~= nil or next(child.props) ~= nil then
          return nil
        end
        if #child.args ~= 1 or child.args[1].kind ~= "bool" or model[field] ~= nil then
          return nil
        end
        model[field] = child.args[1].value
      elseif STRING_FIELDS[child.name] then
        local field = STRING_FIELDS[child.name]
        if child.unsupported or child.children ~= nil or next(child.props) ~= nil then
          return nil
        end
        if #child.args ~= 1 or child.args[1].kind ~= "string" or model[field] ~= nil then
          return nil
        end
        model[field] = child.args[1].value
      elseif child.name == "opacity" then
        if child.unsupported or child.children ~= nil or next(child.props) ~= nil then
          return nil
        end
        if #child.args ~= 1 or child.args[1].kind ~= "number" or model.opacity ~= nil then
          return nil
        end
        model.opacity = child.args[1].value
      elseif SIZE_FIELDS[child.name] then
        local field = SIZE_FIELDS[child.name]
        if child.unsupported or not child.children or model[field] ~= nil then
          return nil
        end
        local sizeModel = try_build_size_model(child.children)
        if not sizeModel then
          return nil
        end
        model[field] = sizeModel
      else
        return nil -- unmanaged property (shadow, border, ...)
      end
    end
  end

  if not matchSeen then
    return nil
  end
  return model
end

-- ============================================================
-- Formatter: model -> DMS-shaped KDL text (4-space indent, one property
-- per line, field order fixed by the v1 spec).
-- ============================================================

local function format_number(v)
  if v == math.floor(v) then
    return string.format("%d", v)
  end
  local s = string.format("%.10f", v)
  s = s:gsub("0+$", "")
  s = s:gsub("%.$", "")
  return s
end

local function format_size_property(name, size)
  return string.format("    %s { %s %s; }", name, size.kind, format_number(size.value))
end

local function format_rule(seg)
  local model = seg.model
  local lines = {}
  if seg.name and seg.name ~= "" then
    table.insert(lines, "// @name=" .. seg.name)
  end
  table.insert(lines, "window-rule {")

  local matchParts = {}
  local match = model.match or {}
  if match.appId then
    table.insert(matchParts, "app-id=" .. quote_kdl_string(match.appId))
  end
  if match.title then
    table.insert(matchParts, "title=" .. quote_kdl_string(match.title))
  end
  if #matchParts > 0 then
    table.insert(lines, "    match " .. table.concat(matchParts, " "))
  end

  local function emitBool(name, val)
    if val ~= nil then
      table.insert(lines, string.format("    %s %s", name, tostring(val)))
    end
  end
  emitBool("open-floating", model.openFloating)
  emitBool("open-maximized", model.openMaximized)
  emitBool("open-fullscreen", model.openFullscreen)
  emitBool("open-focused", model.openFocused)

  if model.openOnWorkspace then
    table.insert(lines, "    open-on-workspace " .. quote_kdl_string(model.openOnWorkspace))
  end
  if model.openOnOutput then
    table.insert(lines, "    open-on-output " .. quote_kdl_string(model.openOnOutput))
  end
  if model.opacity ~= nil then
    table.insert(lines, string.format("    opacity %.2f", model.opacity))
  end
  if model.defaultColumnWidth then
    table.insert(lines, format_size_property("default-column-width", model.defaultColumnWidth))
  end
  if model.defaultWindowHeight then
    table.insert(lines, format_size_property("default-window-height", model.defaultWindowHeight))
  end
  if model.blockOutFrom then
    table.insert(lines, "    block-out-from " .. quote_kdl_string(model.blockOutFrom))
  end

  table.insert(lines, "}")
  return table.concat(lines, "\n")
end

-- ============================================================
-- Segment assembly (top-level document only).
-- ============================================================

-- A `// @name=X` or DMS-style `// @id=X @name=Y` line directly above a
-- window-rule (no blank line between) belongs to that rule, not the
-- preceding comment segment. Returns (remainingGapText, name_or_nil,
-- commentLineToPrepend_or_nil).
local function extract_trailing_name_comment(gapText)
  if gapText == "" or gapText:sub(-1) ~= "\n" then
    return gapText, nil
  end
  local body = gapText:sub(1, -2)
  local lastNl = nil
  for pos in body:gmatch("()\n") do
    lastNl = pos
  end
  local lastLine = lastNl and body:sub(lastNl + 1) or body
  local rest = lastNl and gapText:sub(1, lastNl) or ""

  local name = lastLine:match("^//%s*@name=(.*)$")
  if not name then
    local _, nm = lastLine:match("^//%s*@id=(%S*)%s*@name=(.*)$")
    name = nm
  end
  if not name then
    return gapText, nil
  end
  name = name:match("^%s*(.-)%s*$")
  return rest, name, lastLine .. "\n"
end

local function build_node_segment(node, commentPrefix, name)
  local prefix = commentPrefix or ""
  if node.is_slashdash or node.name ~= "window-rule" then
    return { kind = "opaque", raw = prefix .. node.raw }
  end
  local model = try_build_rule_model(node)
  if not model then
    return { kind = "opaque", raw = prefix .. node.raw }
  end
  return { kind = "rule", raw = prefix .. node.raw, model = model, name = name, dirty = false }
end

--- Splits KDL text into ordered segments. On success: {readonly=false,
--- segments={...}}. On anything the scanner can't confidently classify
--- (unterminated string/comment, stray token): {readonly=true, reason=}
--- and the caller should show the file read-only rather than guess.
function M.parse(text)
  local elements, _, ok, err = parse_node_list(text, 1, false)
  if not ok then
    return { readonly = true, reason = err, segments = {} }
  end

  local segments = {}
  local i = 1
  local n = #elements
  while i <= n do
    local el = elements[i]
    if el.kind == "node" then
      table.insert(segments, build_node_segment(el.node, nil, nil))
      i = i + 1
    else
      local nextEl = elements[i + 1]
      local folded = false
      if nextEl and nextEl.kind == "node" and nextEl.node.name == "window-rule" then
        local restGap, name, commentLine = extract_trailing_name_comment(el.text)
        if name then
          if restGap ~= "" then
            table.insert(segments, { kind = "comment", raw = restGap })
          end
          table.insert(segments, build_node_segment(nextEl.node, commentLine, name))
          i = i + 2
          folded = true
        end
      end
      if not folded then
        if el.text ~= "" then
          table.insert(segments, { kind = "comment", raw = el.text })
        end
        i = i + 1
      end
    end
  end

  return { readonly = false, segments = segments }
end

--- Re-emits segments: untouched ones byte-verbatim, dirty rules
--- reformatted. parse(text) then serialize(segments) with no edits
--- reproduces text exactly.
function M.serialize(segments)
  local parts = {}
  for _, seg in ipairs(segments) do
    if seg.kind == "rule" and seg.dirty then
      table.insert(parts, format_rule(seg))
    else
      table.insert(parts, seg.raw)
    end
  end
  return table.concat(parts)
end

--- Candidate file text for the write pipeline; currently just serialize.
function M.plan_save(segments)
  return M.serialize(segments)
end

-- ============================================================
-- Model API. Segments returned by parse() with kind=="rule" are mutated
-- in place; every setter marks the segment dirty so serialize()
-- regenerates it instead of reusing the stored raw text.
-- ============================================================

--- New empty managed rule segment (dirty, no raw text yet).
function M.new_rule()
  return { kind = "rule", dirty = true, name = nil, model = {} }
end

function M.set_match(segment, appId, title)
  assert(segment.kind == "rule", "set_match: not a rule segment")
  segment.model.match = { appId = appId, title = title }
  segment.dirty = true
end

--- Sets one of: openFloating, openMaximized, openFullscreen, openFocused
--- (bool or nil), openOnWorkspace, openOnOutput, blockOutFrom (string or
--- nil), opacity (number or nil).
function M.set_field(segment, field, value)
  assert(segment.kind == "rule", "set_field: not a rule segment")
  segment.model[field] = value
  segment.dirty = true
end

--- field is "defaultColumnWidth" or "defaultWindowHeight"; kind is
--- "fixed"|"proportion", or pass kind=nil to clear the field.
function M.set_size(segment, field, kind, value)
  assert(segment.kind == "rule", "set_size: not a rule segment")
  if kind == nil then
    segment.model[field] = nil
  else
    segment.model[field] = { kind = kind, value = value }
  end
  segment.dirty = true
end

function M.set_name(segment, name)
  assert(segment.kind == "rule", "set_name: not a rule segment")
  segment.name = (name and name ~= "") and name or nil
  segment.dirty = true
end

-- ============================================================
-- Staleness hash: cheap length + rolling checksum, not cryptographic.
-- ============================================================

local HASH_MOD = 4294967291 -- largest prime below 2^32

--- Returns a "<len>:<checksum>" string; unequal on any content change
--- for the purpose of a save-time staleness check (not tamper-proof).
function M.hash(text)
  local checksum = 0
  for idx = 1, #text do
    checksum = (checksum * 131 + text:byte(idx)) % HASH_MOD
  end
  return #text .. ":" .. checksum
end

-- ============================================================
-- Write pipeline (pure helpers, testable without noctalia.*).
-- ============================================================

function M.candidate_paths(pluginDataDir)
  local dir = pluginDataDir .. "/candidate"
  return { dir = dir, kdl = dir .. "/windowrules.kdl", config = dir .. "/config.kdl" }
end

function M.backup_path(pluginDataDir, nowMs)
  return pluginDataDir .. "/backups/windowrules-" .. tostring(nowMs) .. ".kdl"
end

-- ============================================================
-- Runtime wrapper: noctalia.* calls isolated here, behind the `noctalia`
-- global that only exists inside the Noctalia shell. Absent under a bare
-- Lua interpreter, so this whole block is skipped in tests.
-- ============================================================

if noctalia then
  --- Writes the candidate, validates it via `niri validate` (async), stale-
  --- checks, backs up, then writes realPath. Calls callback with {ok=true}
  --- or {ok=false, stderr=} / {ok=false, stale=true} (real file changed
  --- since previousHash); any failure -- candidate write, validate, stale,
  --- backup, or real write -- leaves realPath untouched, and a backup
  --- failure aborts before realPath is touched.
  function M.save(pluginDataDir, realPath, segments, previousHash, callback)
    local candidate = M.plan_save(segments)
    local paths = M.candidate_paths(pluginDataDir)

    local function fail(stderr)
      callback({ ok = false, stderr = stderr })
    end

    local dirOk, dirErr = noctalia.mkdirAll(paths.dir)
    if not dirOk then
      return fail(dirErr or "candidate directory create failed")
    end
    local kdlOk, kdlErr = noctalia.writeFile(paths.kdl, candidate)
    if not kdlOk then
      return fail(kdlErr or "candidate write failed")
    end
    local cfgOk, cfgErr = noctalia.writeFile(paths.config, 'include "windowrules.kdl"\n')
    if not cfgOk then
      return fail(cfgErr or "candidate config write failed")
    end

    noctalia.runAsync("niri validate -c " .. paths.config, function(result)
      if result.exitCode ~= 0 then
        return fail(result.stderr)
      end

      local current = noctalia.readFile(realPath) or ""
      if M.hash(current) ~= previousHash then
        return callback({ ok = false, stale = true })
      end

      local nowMs = (noctalia.nowMs and noctalia.nowMs()) or (os.time() * 1000)
      local backupDirOk, backupDirErr = noctalia.mkdirAll(pluginDataDir .. "/backups")
      if not backupDirOk then
        return fail(backupDirErr or "backup write failed")
      end
      local backupOk = noctalia.writeFile(M.backup_path(pluginDataDir, nowMs), current)
      if not backupOk then
        return fail("backup write failed")
      end

      local realOk, realErr = noctalia.writeFile(realPath, candidate)
      if not realOk then
        return fail(realErr or "write failed")
      end
      callback({ ok = true })
    end)
  end
end

return M
