--!nonstrict
-- Character picker launcher provider: Unicode symbols + all noctalia emoji.
-- /char lists everything; text after the prefix searches names/keywords; a hex
-- query (2192, u+2192, 0x2192) resolves the codepoint directly. Enter copies
-- to the clipboard (launcher auto-paste setting applies, same as /emo).

local RESULT_LIMIT = 4000 -- above database size: unfiltered list never truncates
local SEARCH_LIMIT = 400

-- Lazily loaded array of launcher-ready entries from generate_db.py:
-- c=char, n=search haystack (name + keywords + u+hex), t=display name,
-- x="U+XXXX" or "".
local db = nil

local function loadDatabase()
  if db ~= nil then
    return db
  end
  local raw = noctalia.readFile("database.json")
  if not raw then
    return nil
  end
  local parsed = noctalia.json.decode(raw)
  if type(parsed) ~= "table" then
    return nil
  end
  db = parsed
  return db
end

local function row(e)
  return {
    id = "c:" .. e.c,
    title = e.t,
    subtitle = if e.x ~= "" then e.x else nil,
    badge = e.c, -- the character itself as the leading visual, like built-in /emo
  }
end

-- "2192" (must contain a digit), "u+2192" or "0x2192" -> codepoint, else nil.
local function hexCodepoint(text)
  local hx = text:match("^u%+?(%x+)$") or text:match("^0x(%x+)$")
  if not hx and text:match("^%x+$") and text:match("%d") then
    hx = text
  end
  if not hx or #hx > 6 then
    return nil
  end
  local cp = tonumber(hx, 16)
  if not cp or cp < 0x20 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
    return nil
  end
  return cp
end

function onQuery(query)
  local d = loadDatabase()
  if not d then
    launcher.setResults(query, {
      { id = "", title = "Database unavailable", subtitle = "Could not load database.json", glyph = "alert-triangle" },
    })
    return
  end

  local text = noctalia.string.trim(query):lower()
  local rows = {}

  if text == "" then
    for _, e in d do
      if #rows >= RESULT_LIMIT then
        break
      end
      table.insert(rows, row(e))
    end
    launcher.setResults(query, rows)
    return
  end

  local cp = hexCodepoint(text)
  if cp then
    local ch = utf8.char(cp)
    table.insert(rows, {
      id = "c:" .. ch,
      title = string.format("U+%04X", cp),
      badge = ch,
    })
  end

  local words = {}
  for w in text:gmatch("%S+") do
    table.insert(words, w)
  end

  local matches = {}
  for i, e in d do
    local ok = true
    for _, w in words do
      if not e.n:find(w, 1, true) then
        ok = false
        break
      end
    end
    if ok then
      table.insert(matches, { e = e, s = noctalia.fuzzyScore(text, e.t) or 0, i = i })
      if #matches >= SEARCH_LIMIT then
        break
      end
    end
  end
  table.sort(matches, function(a, b)
    if a.s ~= b.s then
      return a.s > b.s
    end
    return a.i < b.i
  end)
  for _, m in matches do
    table.insert(rows, row(m.e))
  end

  if #rows == 0 then
    rows[1] = { id = "", title = "No matches", subtitle = "Search by name, keyword or hex codepoint", glyph = "mood-empty" }
  end
  launcher.setResults(query, rows)
end

function onActivate(id)
  if id:sub(1, 2) ~= "c:" then
    return
  end
  local ch = id:sub(3)
  if ch ~= "" then
    noctalia.copyToClipboard(ch, "text/plain")
  end
end
