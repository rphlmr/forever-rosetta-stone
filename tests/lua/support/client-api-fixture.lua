-- Replay client API returns captured in game with `/frsverify api`.
--
--   local Fixture = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
--   local capture = Fixture.Load("tests/fixtures/client-api/1.60.1.70938-frFR.lua")
--   Fixture.Install(capture)                      -- into _G
--   Fixture.Install(capture, {target = env})      -- into a sandbox table
--
-- Every installed function returns fresh copies with the captured nil slots and return
-- count. Calls with arguments that were not captured raise unless `strict = false`, which
-- returns nothing. Behavioural mocks (frames, fonts, focus, combat) stay hand-written.
local Fixture = {}

-- Must stay identical to ArgumentKey in tools/source-scan/rosetta-tooltip-check/probe.lua.
function Fixture.Key(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" then parts[index] = string.format("%q", value)
        elseif type(value) == "number" and value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            parts[index] = string.format("%d", value)
        elseif type(value) == "number" then parts[index] = string.format("%.17g", value)
        else parts[index] = tostring(value) end
    end
    return table.concat(parts, ", ")
end

local function Restore(value)
    if value == "<nil>" then return nil end
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Restore(child) end
    return copy
end

function Fixture.Load(path)
    local chunk = assert(loadfile(path))
    local env = {}
    setfenv(chunk, env)
    chunk()
    local capture = env.RosettaClientApiFixture
    assert(type(capture) == "table" and capture.schemaVersion == 1, "Not a client API fixture: " .. path)
    return capture
end

local function Replay(path, responses, strict)
    return function(...)
        local key = Fixture.Key(...)
        local response = responses[key]
        if not response then
            if strict then error("No captured " .. path .. "(" .. key .. ")", 2) end
            return
        end
        if response.status == "error" then error(response.error, 2) end
        local values = {}
        for index = 1, response.returnCount or 0 do values[index] = Restore(response.values[index]) end
        return unpack(values, 1, response.returnCount or 0)
    end
end

local function Available(responses)
    for _, response in pairs(responses) do
        if response.status ~= "missing API" then return true end
    end
    return false
end

function Fixture.Install(capture, options)
    options = options or {}
    local target = options.target or _G
    local strict = options.strict ~= false
    for path, responses in pairs(capture.calls) do
        if Available(responses) then
            local owner, name = target, nil
            for part in path:gmatch("[^%.]+") do
                if name then
                    owner[name] = type(owner[name]) == "table" and owner[name] or {}
                    owner = owner[name]
                end
                name = part
            end
            owner[name] = Replay(path, responses, strict)
        end
    end
    return target
end

-- Minimal JSON reader for catalog records (objects, arrays, strings, numbers, literals).
local function DecodeJson(text)
    local index = 1
    local function Skip() index = text:find("[^ \t\r\n]", index) or #text + 1 end
    local function Utf8(code)
        if code < 0x80 then return string.char(code) end
        if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
        if code < 0x10000 then
            return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
        end
        return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    local escapes = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
    local Value
    local function String()
        local parts = {}
        index = index + 1
        while true do
            local char = text:sub(index, index)
            if char == "" then error("Unterminated JSON string") end
            if char == '"' then index = index + 1; return table.concat(parts) end
            if char == "\\" then
                local kind = text:sub(index + 1, index + 1)
                if kind == "u" then
                    local code = tonumber(text:sub(index + 2, index + 5), 16)
                    index = index + 6
                    if code >= 0xD800 and code < 0xDC00 and text:sub(index, index + 1) == "\\u" then
                        local low = tonumber(text:sub(index + 2, index + 5), 16)
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        index = index + 6
                    end
                    parts[#parts + 1] = Utf8(code)
                else
                    parts[#parts + 1] = escapes[kind] or kind
                    index = index + 2
                end
            else
                local stop = text:find('["\\]', index) or #text + 1
                parts[#parts + 1] = text:sub(index, stop - 1)
                index = stop
            end
        end
    end
    function Value()
        Skip()
        local char = text:sub(index, index)
        if char == "{" or char == "[" then
            local result, object = {}, char == "{"
            index = index + 1
            Skip()
            if text:sub(index, index) == (object and "}" or "]") then index = index + 1; return result end
            while true do
                if object then
                    Skip()
                    local key = String()
                    Skip()
                    index = index + 1 -- ':'
                    result[key] = Value()
                else
                    result[#result + 1] = Value()
                end
                Skip()
                local separator = text:sub(index, index)
                index = index + 1
                if separator ~= "," then return result end
            end
        end
        if char == '"' then return String() end
        for literal, value in pairs({ ["true"] = true, ["false"] = false, ["null"] = false }) do
            if text:sub(index, index + #literal - 1) == literal then
                index = index + #literal
                if literal == "null" then return nil end
                return value
            end
        end
        local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", index)
        index = index + #number
        return tonumber(number)
    end
    return Value()
end

local globalStringIndex = "tests.lua.support.client-api-fixture.globalstrings"
-- Owned GlobalStrings by key, read from catalogs/globalstrings (the source of the data packs).
local function CatalogGlobalStrings()
    local catalogGlobals = package.loaded[globalStringIndex]
    if catalogGlobals then return catalogGlobals end
    catalogGlobals = {}
    -- Python lists the files once so Lua never probes gaps in the catalog IDs.
    local ids = assert(FRS_TestGlobalStringIDs, "Python test runner must install catalog GlobalStrings IDs")
    for _, id in ipairs(ids) do
        local file = assert(io.open("catalogs/globalstrings/" .. id .. ".json", "rb"))
        local text = file:read("*a")
        file:close()
        local key = text:match('"key"%s*:%s*"([^"]+)"')
        if key then catalogGlobals[key] = text end
    end
    -- Reuse the index even when independent test scripts load this helper again.
    package.loaded[globalStringIndex] = catalogGlobals
    return catalogGlobals
end

function Fixture.CatalogGlobalCount()
    local count = 0
    for _ in pairs(CatalogGlobalStrings()) do count = count + 1 end
    return count
end

-- Owned GlobalStrings keep the export's Lua escapes (`\32`, `\"`, `\\`); the client decodes them.
local luaEscapes = { n = "\n", r = "\r", t = "\t" }
function Fixture.DecodeExportEscapes(value)
    local parts, index = {}, 1
    while index <= #value do
        local slash = value:find("\\", index, true)
        if not slash or slash == #value then parts[#parts + 1] = value:sub(index); break end
        parts[#parts + 1] = value:sub(index, slash - 1)
        local digits = value:match("^%d%d?%d?", slash + 1)
        if digits then
            parts[#parts + 1] = string.char(tonumber(digits))
            index = slash + 1 + #digits
        else
            local char = value:sub(slash + 1, slash + 1)
            parts[#parts + 1] = luaEscapes[char] or char
            index = slash + 2
        end
    end
    return table.concat(parts)
end

-- The client value of an owned GlobalString, as the client shows it.
function Fixture.CatalogGlobal(key, locale)
    local raw = CatalogGlobalStrings()[key]
    local record = raw and DecodeJson(raw)
    local entry = record and record.locales and record.locales[locale]
    local value = entry and entry.name
    return value and Fixture.DecodeExportEscapes(value)
end

-- Install the named GlobalStrings for a client locale from the catalog. A key without an owned
-- value is an error: add it to the catalog instead of typing a value in a test.
function Fixture.InstallGlobals(locale, keys, target)
    target = target or _G
    for _, key in ipairs(keys) do
        local value = Fixture.CatalogGlobal(key, locale)
        assert(value ~= nil, "GlobalString " .. key .. " has no " .. locale .. " catalog value")
        target[key] = value
    end
    return target
end

local loaded = {}
-- The newest retained capture for a client locale.
function Fixture.Client(locale)
    if not loaded[locale] then
        loaded[locale] = Fixture.Load("tests/fixtures/client-api/1.60.1.70938-" .. locale .. ".lua")
    end
    return loaded[locale]
end

return Fixture
