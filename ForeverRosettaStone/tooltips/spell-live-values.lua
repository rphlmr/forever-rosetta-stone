local _, Addon = ...

-- Shared capture for spell, talent, aura and item-effect descriptions.
local LIMIT = 64
local function Readable(value, kind)
    return canaccessallvalues(value) and type(value) == kind
end

local function LiveText(raw)
    if raw~="$z" or type(GetBindLocation)~="function" then return end
    local ok,value=pcall(GetBindLocation)
    if ok and Readable(value,"string") and value~="" then return value end
end

local function Normalize(text, keepIcons)
    if not keepIcons then text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "") end
    return (text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("\\r\\n", " "):gsub("\\n", " ")
        :gsub("|n", " "):gsub("\194\160", " "):gsub("\226\128\175", " ")
        :gsub("[ \t\r\n]+", " "):gsub("^ +", ""):gsub(" +$", ""))
end

local function Escape(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function Balanced(text, start, open, close)
    if text:sub(start, start) ~= open then return end
    local depth = 0
    for index = start, #text do
        local char = text:sub(index, index)
        if char == open then depth = depth + 1 elseif char == close then depth = depth - 1 end
        if depth == 0 then return text:sub(start + 1, index - 1), index + 1 end
    end
end

local function Forms(text)
    local result = {}
    for form in (text .. ":"):gmatch("(.-):") do result[#result + 1] = form end
    return result
end

local function Plural(forms, number, locale)
    local index = number == 1 and 1 or 2
    if #forms >= 3 then
        if number ~= math.floor(number) then return end
        local last, lastTwo = number % 10, number % 100
        if locale == "ruRU" or locale == "ukUA" or locale == "hrHR" then
            index = last == 1 and lastTwo ~= 11 and 1
                or last >= 2 and last <= 4 and (lastTwo < 12 or lastTwo > 14) and 2 or 3
        elseif locale == "plPL" then
            index = number == 1 and 1 or last >= 2 and last <= 4 and (lastTwo < 12 or lastTwo > 14) and 2 or 3
        elseif locale == "csCZ" then index = number == 1 and 1 or number >= 2 and number <= 4 and 2 or 3
        else return end
    elseif locale == "frFR" or locale == "ptBR" then index = number == 0 and 1 or index end
    return forms[index]
end

local commaLocales = {frFR=true, deDE=true, esES=true, esMX=true, itIT=true, ptBR=true, ruRU=true,
    ukUA=true, plPL=true, csCZ=true, daDK=true, svSE=true, trTR=true, hrHR=true}
local spaceLocales = {frFR=true, ruRU=true, ukUA=true, plPL=true, csCZ=true, svSE=true}
local Formats
local function Separators(locale)
    local formats = Formats and Formats(locale) or {}
    local decimal = formats.DECIMAL_SEPERATOR or (commaLocales[locale] and "," or ".")
    local grouping = formats.LARGE_NUMBER_SEPERATOR
        or (spaceLocales[locale] and " " or decimal == "," and "." or ",")
    return decimal, grouping
end

local function Number(text, locale)
    text = Normalize(text)
    -- French can spell a unit quantity inside a numeric template slot. This is a
    -- grammatical number, not an entity name or a spell-specific effect value.
    if locale=="frFR" and (text=="un" or text=="une") then text="1" end
    local decimal, grouping = Separators(locale)
    grouping = grouping:gsub("\194\160", " "):gsub("\226\128\175", " ")
    local sign = text:match("^[+-]") or ""
    text = text:sub(#sign + 1)
    local integer, fraction = text:match("^(.-)" .. Escape(decimal) .. "(%d+)$")
    integer = integer or text
    -- An empty output separator is valid; native rows can still contain formatted grouping.
    if grouping == "" then grouping = spaceLocales[locale] and " " or decimal == "," and "." or "," end
    local grouped = grouping ~= "" and integer:find(grouping, 1, true) ~= nil
    if grouped then
        local chunks = {}
        for part in (integer .. grouping):gmatch("(.-)" .. Escape(grouping)) do chunks[#chunks + 1] = part end
        if not chunks[1]:match("^%d%d?%d?$") then return end
        for index = 2, #chunks do if not chunks[index]:match("^%d%d%d$") then return end end
        integer = table.concat(chunks)
    end
    if not integer:match("^%d+$") then return end
    local canonical = sign .. integer .. (fraction and "." .. fraction or "")
    local amount = tonumber(canonical)
    if not amount or amount ~= amount or math.abs(amount) == math.huge then return end
    return {canonical=canonical, integer=integer, fraction=fraction, sign=sign, grouped=grouped, amount=amount}
end

local function FormatNumber(value, locale)
    local decimal, grouping = Separators(locale)
    if locale == "frFR" then grouping = "\226\128\175" end
    local integer = value.integer
    if value.grouped then
        integer = integer:reverse():gsub("(%d%d%d)", "%1" .. grouping:reverse()):reverse()
        if integer:sub(1, #grouping) == grouping then integer = integer:sub(#grouping + 1) end
    end
    return value.sign .. integer .. (value.fraction and decimal .. value.fraction or "")
end

local formatCache = {}
Formats = function(locale)
    if formatCache[locale] then return formatCache[locale] end
    local fallback = Addon.tooltipFormatsByLocale and Addon.tooltipFormatsByLocale[locale] or {}
    local values = setmetatable({}, {__index = function(target, key)
        local value = Addon.GetClientLabel and Addon:GetClientLabel(key, locale) or fallback[key]
        if value ~= nil then rawset(target, key, value) end
        return value
    end})
    formatCache[locale] = values
    return values
end

local durationKeys = {"INT_SPELL_DURATION_SEC", "INT_SPELL_DURATION_MIN", "INT_SPELL_DURATION_HOURS", "INT_SPELL_DURATION_DAYS",
    "INT_GENERAL_DURATION_SEC", "INT_GENERAL_DURATION_MIN", "INT_GENERAL_DURATION_HOURS",
    "SECONDS_ABBR", "MINUTES_ABBR", "HOURS_ABBR", "DAYS_ABBR", "D_SECONDS", "D_MINUTES", "D_HOURS", "D_DAYS"}
local function FormatQuantity(template, value, locale)
    local failed
    local result = template:gsub("|4([^;]+);", function(forms)
        local word = Plural(Forms(forms), value.amount, locale)
        if not word then failed = true; return "" end
        return word
    end)
    local count
    result, count = result:gsub("%%[%d%.%$]*[dfsg]", function() return FormatNumber(value, locale) end)
    if failed or count ~= 1 then return end
    return result
end

local function CaptureQuantity(text, template, locale)
    local variants = {template}
    local first, last, forms = template:find("|4([^;]+);")
    if first then
        for _, word in ipairs(Forms(forms)) do
            variants[#variants + 1] = template:sub(1, first - 1) .. word .. template:sub(last + 1)
        end
    end
    for _, variant in ipairs(variants) do
        local pattern, count = variant:gsub("%%[%d%.%$]*[dfsg]", "\001")
        if count == 1 then
            pattern = Escape(Normalize(pattern)):gsub("\001", "(.-)")
            local captured = Normalize(text):match("^" .. pattern .. "$")
            local number = captured and Number(captured, locale)
            if number then return number end
        end
    end
end

local function MagnitudeNumber(text, locale)
    -- These two clients use the same magnitude thresholds. Other client locales may
    -- use different thresholds for the same UI key and remain unsupported here.
    if locale ~= "enUS" and locale ~= "frFR" then return end
    local magnitudes = {
        FIRST_NUMBER = {"thousand", 3}, SECOND_NUMBER = {"million", 6},
        THIRD_NUMBER = {"billion", 9}, FOURTH_NUMBER = {"trillion", 12},
    }
    if locale == "frFR" then text = text:gsub(" de$", "") end
    for key, magnitude in pairs(magnitudes) do
        local english, source = Formats("enUS")[key], Formats(locale)[key]
        if Readable(english,"string") and Normalize(english) == magnitude[1] and Readable(source,"string") then
            local units = {Normalize(source)}
            local forms = source:match("^|7([^;]+);$")
            for _, form in ipairs(forms and Forms(forms) or {}) do units[#units+1] = form end
            for _, unit in ipairs(units) do
                local quantity = text:match("^(.+) " .. Escape(unit) .. "$")
                local number = quantity and Number(quantity,locale)
                if number then
                    -- Shift the displayed decimal digits, without inferring the hidden,
                    -- unrounded client value or recalculating a character's spell values.
                    local digits = number.integer .. (number.fraction or "")
                    local point = #number.integer + magnitude[2]
                    if #digits < point then digits = digits .. string.rep("0",point-#digits) end
                    local integer = digits:sub(1,point):gsub("^0+","")
                    if integer == "" then integer = "0" end
                    local fraction = digits:sub(point+1)
                    local scaled = Number(number.sign .. integer .. (fraction ~= "" and "." .. fraction or ""),"enUS")
                    if scaled then scaled.grouped = #scaled.integer > 3; return scaled end
                end
            end
        end
    end
end

local function Value(text, duration, sourceLocale, targetLocale, rangeFormat)
    if duration then
        local source, target = Formats(sourceLocale), Formats(targetLocale)
        local unlimited = source.SPELL_DURATION_UNTIL_CANCELLED
        if Readable(unlimited, "string") and Normalize(text) == Normalize(unlimited)
            and Readable(target.SPELL_DURATION_UNTIL_CANCELLED, "string") then
            return {text=target.SPELL_DURATION_UNTIL_CANCELLED, canonical="SPELL_DURATION_UNTIL_CANCELLED"}
        end
        for _, key in ipairs(durationKeys) do
            local template, translated = source[key], target[key]
            if Readable(template, "string") and Readable(translated, "string") then
                local number = CaptureQuantity(text, template, sourceLocale)
                local output = number and FormatQuantity(translated, number, targetLocale)
                if output then return {text=output, canonical=key .. ":" .. number.canonical, amount=number.amount} end
            end
        end
        return
    end
    if rangeFormat then
        local prefix = Normalize(rangeFormat[1])
        if prefix ~= "" and text:sub(1, #prefix + 1) == prefix .. " " then
            text = text:sub(#prefix + 2)
        end
    end
    local number = Number(text, sourceLocale)
    if not number and rangeFormat and rangeFormat.dotLower and rangeFormat.dotUpper then
        number = Number(text, "enUS")
    end
    if number then return {text=FormatNumber(number,targetLocale),canonical=number.canonical,amount=number.amount} end
    local delimiters = {" à ", " to ", "–", " - ", "-"}
    -- The client owns localized scalar ranges too (for example German "bis").
    -- Reuse its numeric spread format rather than interpreting words as values.
    for _, key in ipairs({"SPELL_POINTS_SPREAD_TEMPLATE", "SPELL_POINTS_SPREAD_TEMPLATE_WITH_SYMBOL"}) do
        local spread = Formats(sourceLocale)[key]
        -- The symbol-bearing client format also accepts empty symbols.
        spread = Readable(spread, "string") and Normalize(spread):gsub("%%s", "")
        local join = spread and spread:match("^%%[%d%.%$]*[dfg](.-)%%[%d%.%$]*[dfg]$")
        if join and join ~= "" then table.insert(delimiters, 1, join) end
    end
    if rangeFormat then table.insert(delimiters, 1, Normalize(rangeFormat[2])) end
    for _, delimiter in ipairs(delimiters) do
        local first, last = text:find(delimiter, 1, true)
        if first and first > 1 then
            local lowText, highText = text:sub(1,first-1), text:sub(last+1)
            local lower, upper = Number(lowText,sourceLocale), Number(highText,sourceLocale)
            if rangeFormat then
                lower = lower or rangeFormat.dotLower and Number(lowText,"enUS")
                upper = upper or rangeFormat.dotUpper and Number(highText,"enUS")
            end
            if lower and upper then
                return {text=FormatNumber(lower,targetLocale) .. "-" .. FormatNumber(upper,targetLocale),
                    canonical=lower.canonical .. ":" .. upper.canonical,amount=upper.amount,lower=lower,upper=upper}
            end
        end
    end
    local magnitude = MagnitudeNumber(text,sourceLocale)
    if magnitude then
        return {text=FormatNumber(magnitude,targetLocale),canonical=magnitude.canonical,amount=magnitude.amount}
    end
end

local function Condition(text, start)
    local bracket = text:find("[", start, true)
    if not bracket then return end
    local predicate = text:sub(start, bracket-1)
    if predicate == "" then return end
    local yes, offset = Balanced(text,bracket,"[","]")
    if not yes then return end
    offset = offset + #(text:sub(offset):match("^[ \t\r\n]*") or "")
    if text:sub(offset,offset) == "?" then
        local nextBranches, finish, predicates = Condition(text,offset+1)
        if not nextBranches then return end
        table.insert(nextBranches,1,yes)
        return nextBranches,finish,predicate .. ";" .. predicates
    end
    local no, finish = Balanced(text,offset,"[","]")
    if no == nil then return end
    return {yes,no},finish,predicate
end

local contextValues = {PL=true, pl=true, AP=true, SPI=true, SPFI=true, SPH=true, SPA=true, SPS=true,
    SPFR=true, proccooldown=true, apm=true, rap=true, mcrit=true, bc=true, MW=true, mw=true,
    MWB=true, mwb=true, MWS=true, mws=true, ecim=true, RFR=true, RA=true, RF=true, RN=true, RS=true}

local function IsFormula(raw)
    if raw:sub(1,2)~="${" then return false end
    local _, ending=Balanced(raw,2,"{","}")
    if not ending then return false end
    local suffix=raw:sub(ending)
    return suffix=="" or suffix:match("^%.%d+$")~=nil
end

local function LevelBranch(predicates)
    if type(UnitLevel)~="function" then return end
    local ok,level=pcall(UnitLevel,"player")
    if not ok or not Readable(level,"number") or level<=0 then return end
    local selected,count
    count=0
    for predicate in (predicates .. ";"):gmatch("(.-);") do
        local operator,threshold=predicate:match("^%$[Pp][Ll]([<>=~!]+)(%d+)$")
        threshold=tonumber(threshold)
        if not operator or not threshold then return end
        local comparisons={ ["<"]=level<threshold, ["<="]=level<=threshold,
            [">"]=level>threshold, [">="]=level>=threshold, ["="]=level==threshold,
            ["=="]=level==threshold, ["!="]=level~=threshold, ["~="]=level~=threshold }
        if comparisons[operator]==nil then return end
        count=count+1
        if comparisons[operator] and not selected then selected=count end
    end
    return selected or count+1
end

local function ScaledAmountSlot(raw, owner)
    local operator, scale, reference, code, index = raw:match("^%$([*/])([%d%.]+);(%d*)([sSm])(%d*)$")
    if not operator then
        reference, code, index, operator, scale = raw:match("^%${%$(%d*)([sSm])(%d*)([*/])([+-]?[%d%.]+)}$")
    end
    scale = tonumber(scale)
    if not scale or scale == 0 then return end
    owner, index = tonumber(reference) or owner, tonumber(index) or 1
    local coefficient = operator == "/" and 1 / scale or scale
    local shape = code == "m" and "scaled-amount:" or "scaled-magnitude:"
    if code ~= "m" then
        -- $s and $S share magnitude semantics, including legacy scalar syntax.
        -- Equating them with signed $m additionally requires owned flat trait
        -- curves to prove the same sign at every rank. Never calculate a live value.
        local function TraitSign()
            local rules = ForeverRosettaStoneDB.GetSpellRules and ForeverRosettaStoneDB:GetSpellRules(owner)
            local sign
            for _, effect in ipairs(rules and rules.effects or {}) do
                if effect.index == index - 1 and effect.effectType == 6 and effect.auraType == 107
                    and effect.apCoefficient == 0 and effect.bonusCoefficient == 0 then
                    local modifier = effect.traitModifier
                    if modifier and modifier.operationType == 0 and type(modifier.curvePoints) == "table"
                        and #modifier.curvePoints > 0 then
                        if not Readable(effect.basePoints, "number") or effect.basePoints == 0 then return end
                        sign = effect.basePoints < 0 and -1 or 1
                        for _, point in ipairs(modifier.curvePoints) do
                            if not Readable(point.value, "number") or point.value == 0 then return end
                            local current = point.value < 0 and -1 or 1
                            if sign and sign ~= current then return end
                            sign = current
                        end
                    end
                end
            end
            return sign
        end
        local sign = TraitSign()
        if sign then
            coefficient, shape = coefficient * sign, "scaled-amount:"
        end
    end
    return {key=owner .. ":" .. raw,owner=owner,index=index,
        shape=shape .. string.format("%.17g", coefficient),raw=raw}
end

local function Slot(raw, owner)
    local reference, code, modifier, index = raw:match("^%$(%d*)([sSmMdDwWtTuUxXhniraAoObBeEfFvVqQpPHNRc])(~?)(%d*)$")
    if code then
        local shape = (code == "d" or code == "D") and "duration" or code == "M" and "maximum"
            or (code == "s" or code == "S" or code == "m" or code == "w" or code == "W") and "amount" or code
        if code == "M" then
            -- A nonnegative flat stat aura with explicit zero variance has one
            -- endpoint. Transfer the captured amount; do not evaluate its level scaling.
            local rules = ForeverRosettaStoneDB.GetSpellRules and ForeverRosettaStoneDB:GetSpellRules(tonumber(reference) or owner)
            for _, effect in ipairs(rules and rules.effects or {}) do
                if effect.index == (tonumber(index) or 1) - 1 and (effect.effectType == 6 or effect.effectType == 35)
                    and effect.auraType == 29 and effect.variance == 0 and effect.apCoefficient == 0
                    and effect.bonusCoefficient == 0 and effect.scalingClass == 0 and not effect.traitModifier
                    and Readable(effect.basePoints, "number") and effect.basePoints >= 0
                    and Readable(effect.perLevel, "number") and effect.perLevel >= 0 then shape = "amount" end
            end
        end
        return {key=owner .. ":" .. raw,owner=tonumber(reference) or owner,index=tonumber(index) or 1,
            shape=shape .. modifier,
            duration=code:lower()=="d",raw=raw}
    end
    if raw == "$z" then
        return {key=owner .. ":" .. raw,owner=owner,index=1,shape=raw,valueType="text",raw=raw}
    end
    if raw:match("^%$%d+$") or raw == "$rad" or raw == "$rad#" then
        return {key=owner .. ":" .. raw,owner=owner,index=1,
            shape=(raw=="$rad" or raw=="$rad#") and "radius" or raw,raw=raw}
    end
    local context = raw:match("^%$([A-Za-z][A-Za-z0-9_]*)$")
    if context and (contextValues[context] or context:match("^ec%d+$") or context:match("^skm?%d+$")
        or context:match("^signw%d+$")) then
        return {key=owner .. ":" .. raw,owner=owner,index=1,shape=raw,raw=raw}
    end
    local scaled = ScaledAmountSlot(raw, owner)
    if scaled then return scaled end
    if raw:match("^%$[*/][%d%.]+;%d*[A-Za-z]%d*$") or raw:match("^%$%d+[*/][%d%.]*;[A-Za-z]%d*$")
        or IsFormula(raw) or raw:match("^%$<[A-Za-z0-9_]+>$")
        or raw:match("^%$[Pp][Ll]$") or raw:match("^%$j%d+[A-Za-z]$") then
        return {key=owner .. ":" .. raw,owner=owner,index=tonumber(raw:match("[sSmM](%d+)")) or 1,
            shape=raw:gsub("([sSmM])%d+","%1#"),raw=raw}
    end
end

local function NumericRangeFormat(nodes)
    local count, layout, slots = 0, {"", "", ""}, {}
    for _, node in ipairs(nodes) do
        if node.literal then layout[count + 1] = layout[count + 1] .. node.literal
        elseif node.key and not node.valueType and not node.duration and count < 2 then
            count = count + 1; slots[count] = node
        else return end
    end
    if count ~= 2 or Normalize(layout[3]) ~= "" then return end
    -- Only paired minima/maxima of the same owned expression constitute a range.
    local upper, replacements = slots[1].raw:gsub("%$(%d*)m(%d*)", "$%1M%2", 1)
    if replacements ~= 1 or upper ~= slots[2].raw then return end
    local prefixes = { [""]=true, de=true, da=true, od=true, ["від"]=true }
    local joins = { to=true, ["à"]=true, ["-"]=true, ["–"]=true, a=true, y=true,
        bis=true, til=true, till=true, ["až"]=true, ["do"]=true, ila=true, ["至"]=true, ["до"]=true }
    if prefixes[Normalize(layout[1])] and joins[Normalize(layout[2])] then
        layout.dotLower = IsFormula(slots[1].raw) and slots[1].raw:match("%.%d+$") ~= nil
        layout.dotUpper = IsFormula(slots[2].raw) and slots[2].raw:match("%.%d+$") ~= nil
        return layout
    end
end

local function Compile(id, locale, field, unit, inlineTooltips, visibleReferences, variant)
    local parse, record
    local expansions={}
    parse = function(text, owner, depth)
        if depth > 12 then return end
        text = text:gsub("\\r\\n","\n"):gsub("\\n","\n")
        -- Wago exports nonbreaking spaces as literal hex escapes. Keep the owned source raw.
        text = text:gsub("\\[xX][aA]0", "\194\160")
        -- Client templates escape literal percent signs. Treat the escape as a
        -- single literal in both matching and rendering, including nested rows.
        text = text:gsub("%%%%", "%%")
        -- Some official templates omit only the leading sigil on a scalar
        -- arithmetic block. Its explicit variable/operator grammar still gives
        -- the same token identity; arbitrary braces and prose are untouched.
        text = text:gsub("()(%b{})", function(start, body)
            if text:sub(start - 1, start - 1) ~= "$"
                and body:match("^{%$%d*[sSmM]%d+[*/][+-]?%d+%.?%d*}$") then return "$" .. body end
            return body
        end)
        local nodes, offset = {}, 1
        while offset <= #text do
            local start = text:find("$",offset,true)
            if not start then nodes[#nodes+1]={literal=text:sub(offset)}; break end
            nodes[#nodes+1]={literal=text:sub(offset,start-1)}
            local rest, raw, node, finish = text:sub(start)
            local kind, reference = rest:match("^%$@([a-z]+)<(%d+)>")
            if not kind then kind,reference=rest:match("^%$@([a-z]+)(%d+)") end
            if kind then
                raw=rest:match("^%$@[a-z]+<%d+>") or rest:match("^%$@[a-z]+%d+")
                if kind == "spellname" then
                    local name=ForeverRosettaStoneDB:GetSpellName(tonumber(reference),locale)
                    if not Readable(name,"string") then return end
                    node={literal=name}
                elseif kind == "spelltooltip" and inlineTooltips and inlineTooltips[tonumber(reference)] then
                    -- A validated, separately rendered child block owns this reference.
                    node={literal=""}
                elseif kind == "spelldesc" or kind == "spelltooltip" or kind == "spellaura" then
                    -- Inline tooltip descriptions must still match the complete captured block.
                    -- Surfaces with additional headers or requirements remain unmatched.
                    local nested=record(tonumber(reference),kind=="spellaura" and "auraDescription" or "description",depth+1)
                    if not nested then return end
                    if visibleReferences and kind == "spelldesc" and depth == 0 then
                        -- Typed item-effect surfaces can omit a whole referenced
                        -- description. Match the complete remaining parent and
                        -- carry that reference's observed presence to the target.
                        node={choice=owner .. ":visible-spelldesc:" .. tonumber(reference),observedPresence=true,
                            branches={{{nested=nested}}, {}}}
                    else node={nested=nested} end
                elseif kind == "spellicon" then
                    node={key=owner .. ":" .. raw,owner=tonumber(reference),index=1,
                        shape="icon",valueType="icon",raw=raw}
                else return end
            elseif rest:sub(1,12)=="$@expandkey[" then
                local body, ending=Balanced(rest,12,"[","]")
                if not body then return end
                expansions[owner]=(expansions[owner] or 0)+1
                local key=owner .. ":expandkey:" .. expansions[owner]
                local nested=parse(body,owner,depth+1)
                if not nested then return end
                local hint={}
                local template=Formats(locale).TOOLTIP_EXPAND_HINT
                local before,after
                if Readable(template,"string") then before,after=template:match("^(.-)%%s(.-)$") end
                if before and not after:find("%%s") then
                    hint={{literal="\n" .. before},
                        {key=key .. ":modifier",owner=owner,index=1,shape="modifier",valueType="modifier"},
                        {literal=after}}
                end
                raw=rest:sub(1,ending-1)
                -- The client can append its owned hint inside the collapsed description.
                node={choice=key,branches={nested,hint,{}}}
            elseif rest:sub(1,2)=="${" then
                local body, ending=Balanced(rest,2,"{","}")
                if not body then return end
                local precision=rest:sub(ending):match("^%.%d+") or ""
                raw=rest:sub(1,ending-1) .. precision
                node=Slot(raw,owner)
            elseif rest:sub(1,2)=="$?" then
                local branches, ending, predicates=Condition(rest,3)
                if not branches then return end
                raw=rest:sub(1,ending-1)
                local selected=field~="auraDescription" and LevelBranch(predicates)
                local numeric, rangeFormat=true,nil
                for _, branch in ipairs(selected and {} or branches) do
                    local trimmed=Normalize(branch)
                    local slot=Slot(trimmed,owner)
                    if not Number(trimmed,locale) and not (slot and not slot.valueType) then
                        local nested = parse(branch,owner,depth+1)
                        local layout = nested and NumericRangeFormat(nested)
                        if not layout then numeric=false;break end
                        if rangeFormat and table.concat(rangeFormat,"\001") ~= table.concat(layout,"\001") then
                            numeric=false;break
                        end
                        rangeFormat=layout
                    end
                end
                if selected then
                    local nested=branches[selected] and parse(branches[selected],owner,depth+1)
                    if not nested then return end
                    node={nested=nested}
                elseif numeric then node={key=owner .. ":" .. raw,owner=owner,index=1,
                    shape="condition:" .. predicates,raw=raw,rangeFormat=rangeFormat}
                else
                    node={choice=owner .. ":" .. predicates,branches={}}
                    for _, branch in ipairs(branches) do
                        local nested=parse(branch,owner,depth+1)
                        if not nested then return end
                        node.branches[#node.branches+1]=nested
                    end
                end
            elseif rest:match("^%$[lLgG]") then
                local forms
                raw,forms=rest:match("^(%$[lLgG]([^;]*:[^;]*);)")
                if not raw then
                    -- With a missing plural terminator the client exposes the
                    -- remaining text literally, even without alternatives, and
                    -- removes only $l. Keep that literal as a template anchor.
                    local literal=rest:match("^%$[lL]([^$;]+)")
                    if not literal then return end
                    raw=rest:sub(1,2) .. literal
                    node={literal=literal}
                elseif rest:sub(2,2):lower()=="l" then
                    node={plural={}}
                    for _,form in ipairs(Forms(forms)) do
                        local nested=parse(form,owner,depth+1)
                        if not nested then return end
                        node.plural[#node.plural+1]=nested
                    end
                else
                    local ok,sex
                    if type(UnitSex)=="function" then ok,sex=pcall(UnitSex,unit or "player") end
                    if ok and Readable(sex,"number") and (sex==2 or sex==3) then
                        local nested=parse(Forms(forms)[sex-1],owner,depth+1)
                        if not nested then return end
                        node={nested=nested}
                    else
                        -- Visible grammar may identify the branch without a captured
                        -- UnitSex call. Ambiguous target outputs are still rejected.
                        node={choice="gender:" .. (unit or "player"),branches={}}
                        for _,form in ipairs(Forms(forms)) do
                            local nested=parse(form,owner,depth+1)
                            if not nested then return end
                            node.branches[#node.branches+1]=nested
                        end
                    end
                end
            else
                local context = rest:match("^%$([A-Za-z][A-Za-z0-9_]*)")
                local contextToken = context and Slot("$" .. context,owner)
                raw=rest:match("^%$[*/][%d%.]+;%d*[A-Za-z]%d*") or rest:match("^%$%d+[*/][%d%.]*;[A-Za-z]%d*")
                    or rest:match("^%$<[A-Za-z0-9_]+>") or rest:match("^%$[Pp][Ll]")
                    or rest:match("^%$rad#")
                    or rest:match("^%$%d*[sSmMdDwWtTuUxXhniraAoObBeEfFvVqQpPHNRc]~%d+")
                    or contextToken and "$" .. context
                    or rest:match("^%$j%d+[A-Za-z]")
                    or rest:match("^%$%d*[sSmMdDwWtTuUxXhniraAoObBeEfFvVqQpPHNRcz]~?%d*")
                    or rest:match("^%$%d+")
                if not raw then return end
                node=Slot(raw,owner)
            end
            if not raw or not node then return end
            if node.valueType=="text" then
                node.expected=LiveText(raw)
                node.captureOnly=raw=="$z" and type(GetBindLocation)~="function"
                if not node.expected and not node.captureOnly then return end
            end
            finish=start+#raw
            -- Duration codes have a scalar boundary even when client prose is
            -- adjacent (for example "$dlang"). Other bare names must not consume
            -- unknown identifiers. Matching still verifies the complete suffix.
            if not node.duration and raw:match("^%$%d*[%a]+$")
                and text:sub(finish,finish):match("[A-Za-z0-9_~]") then return end
            nodes[#nodes+1]=node
            offset=finish
        end
        return nodes
    end
    record=function(owner,which,depth)
        local details=ForeverRosettaStoneDB:GetSpellDetails(owner,locale)
        if not details then return end
        local text=details[which]
        if variant and depth==0 then
            local variants=details[which .. "Variants"]
            text=type(variants)=="table" and variants[variant] or nil
        end
        if not Readable(text,"string") then return end
        return parse(text,owner,depth)
    end
    return record(id,field,0)
end

local function Flatten(nodes, choices, result)
    result=result or {}
    for _, node in ipairs(nodes) do
        if node.nested then
            local ok,missing=Flatten(node.nested,choices,result)
            if not ok or missing then return ok,missing end
        elseif node.choice then
            local branch=choices[node.choice]
            if not branch then return result,{key=node.choice,count=#node.branches,observedPresence=node.observedPresence} end
            if not node.branches[branch] then return end
            local ok,missing=Flatten(node.branches[branch],choices,result)
            if not ok or missing then return ok,missing end
        elseif node.plural then
            local key=node
            if not choices[key] then return result,{key=key,count=#node.plural,forms=node.plural} end
            local marker={literal="",pluralForms=node.plural,selected=choices[key]}
            result[#result+1]=marker
            local ok,missing=Flatten(node.plural[choices[key]],choices,result)
            if not ok or missing then return ok,missing end
            marker.ending=#result
        else result[#result+1]=node end
    end
    return result
end

local function PrefixMatches(segments,native)
    local pattern={}
    local hasIcons=native:find("|T",1,true) or native:find("|A",1,true)
    for _,node in ipairs(segments) do
        if node.literal then pattern[#pattern+1]=Escape(node.literal)
        elseif node.valueType~="icon" or hasIcons then pattern[#pattern+1]=".-" end
    end
    -- Only reject impossible literal prefixes. Full matching still validates every value.
    return Normalize(native,true):find("^" .. Normalize(table.concat(pattern),true))~=nil
end

local function Match(segments,native,sourceLocale,targetLocale,valueLocale)
    valueLocale=valueLocale or sourceLocale
    local pattern,slots,literal,values,bindings,anchors={},{},"",{},{},{}
    local function Anchor(text)
        return Normalize("\001" .. text .. "\002",true):sub(2,-2)
    end
    -- Native requirement colors distinguish otherwise identical conditional branches.
    -- Only use an explicit leading color from both inputs; arbitrary inline styles remain cosmetic.
    local prefix=""
    for _,node in ipairs(segments) do
        if not node.literal then break end
        prefix=prefix .. node.literal
    end
    local expectedColor=prefix:match("^[ \t\r\n]*|[cC](%x%x%x%x%x%x%x%x)")
    local actualColor=native:match("^[ \t\r\n]*|[cC](%x%x%x%x%x%x%x%x)")
    if expectedColor and actualColor and expectedColor:lower()~=actualColor:lower() then return end
    local hasIcons=native:find("|T",1,true) or native:find("|A",1,true)
    for _, node in ipairs(segments) do
        if node.literal then literal=literal .. node.literal
        elseif node.valueType=="icon" and not hasIcons then
            bindings[#bindings+1]=node
            values[node.key]={text="",canonical=""}
        else
            if #slots>0 and literal=="" then return end
            pattern[#pattern+1]=Escape(literal)
            anchors[#anchors+1]=Anchor(literal)
            pattern[#pattern+1]="(.-)"
            literal=""; slots[#slots+1]=node;bindings[#bindings+1]=node
        end
    end
    pattern[#pattern+1]=Escape(literal)
    anchors[#anchors+1]=Anchor(literal)
    -- Match searches normalized whole input. Keep spaces between slots, but
    -- discard only outer whitespace, just as the complete pattern does.
    anchors[1]=anchors[1]:gsub("^ +", "")
    anchors[#anchors]=anchors[#anchors]:gsub(" +$", "")
    local normalized="^" .. Normalize(table.concat(pattern),true) .. "$"
    local captures={Normalize(native,true):match(normalized)}
    if #captures==0 then return end
    local function Decode(node,captured)
        local value
        if node.valueType=="text" then
            local location
            if node.expected and captured==Normalize(node.expected,true) then
                location=node.expected
            elseif node.captureOnly and captured~="" and not captured:find("<restricted>",1,true)
                and not captured:find("<nil>",1,true) and not captured:find("<function>",1,true) then
                location=captured
            end
            if location then
                local target = valueLocale == targetLocale and location
                    or ForeverRosettaStoneDB.TranslateLocationLabel
                        and ForeverRosettaStoneDB:TranslateLocationLabel(location, valueLocale, targetLocale)
                if target then value={text=target,canonical=captured,capturedText=not node.expected} end
            end
        elseif node.valueType=="icon" then
            if captured=="" or captured:match("^|T[^|]+|t$") or captured:match("^|A[^|]+|a$") then
                value={text=captured,canonical=captured}
            end
        elseif node.valueType=="modifier" then
            for _,key in ipairs({"SHIFT_KEY_TEXT","CTRL_KEY_TEXT","ALT_KEY_TEXT"}) do
                local source,target=Formats(valueLocale)[key],Formats(targetLocale)[key]
                if Readable(source,"string") and Readable(target,"string") and Normalize(source)==captured then
                    if value and value.canonical~=key then return end
                    value={text=target,canonical=key}
                end
            end
        else
            value=Value(captured,node.duration,valueLocale,targetLocale,node.rangeFormat)
            -- Explicit formula precision can use a dot even on a comma-decimal client.
            if not value and node.raw and IsFormula(node.raw) and node.raw:match("%.%d+$") then
                local number=Number(captured,"enUS")
                if number then value={text=FormatNumber(number,targetLocale),canonical=number.canonical,amount=number.amount} end
            end
            -- The client can expose an unresolved token, or echo a failed formula's
            -- body before that exact formula. Preserve this symbolic value verbatim;
            -- it must never acquire a numeric value or bind to a different token.
            if not value and node.raw then
                local echo
                if IsFormula(node.raw) then
                    local body=Balanced(node.raw,2,"{","}")
                    echo=body and body .. node.raw
                end
                if captured==Normalize(node.raw,true) or echo and captured==Normalize(echo,true) then
                    value={text=captured,canonical="unresolved:" .. node.raw,unresolved=node.raw}
                end
            end
        end
        return value
    end
    local initial={}
    for key,value in pairs(values) do initial[key]=value end
    local valid=true
    for index,node in ipairs(slots) do
        local value=Decode(node,captures[index])
        if not value or values[node.key] and values[node.key].canonical~=value.canonical then valid=false;break end
        values[node.key]=value
    end
    local adjacent
    for index=1,#slots-1 do
        if anchors[index+1]:match("^ +$") then adjacent=true;break end
    end
    if valid and not adjacent then return values,bindings end

    -- A duration followed by an amount can be separated only by whitespace
    -- (for example German "$d $o1"). Lua's first capture split need not be
    -- semantically valid. Explore literal boundaries with the real value parser,
    -- retaining a result only when every valid split gives the same bindings.
    local text=Normalize(native,true)
    if text:sub(1,#anchors[1])~=anchors[1] then return end
    local result,ambiguous,attempts,inspected=nil,false,0,0
    values=initial
    local function Search(index,offset)
        if ambiguous or attempts>LIMIT or inspected>512 then return end
        if index>#slots then
            if offset~=#text+1 then return end
            if result then
                for key,value in pairs(values) do
                    if not result[key] or result[key].canonical~=value.canonical then ambiguous=true;return end
                end
            else
                result={};for key,value in pairs(values) do result[key]=value end
            end
            return
        end
        local node,anchor=slots[index],anchors[index+1]
        local start,finish
        if anchor=="" then start,finish=#text+1,#text
        else start,finish=text:find(anchor,offset,true) end
        while start do
            inspected=inspected+1
            if inspected>512 then return end
            local value=Decode(node,text:sub(offset,start-1))
            local previous=values[node.key]
            if value and (not previous or previous.canonical==value.canonical) then
                attempts=attempts+1
                if attempts>LIMIT then return end
                values[node.key]=value
                Search(index+1,finish+1)
                values[node.key]=previous
            end
            if ambiguous or anchor=="" then break end
            start,finish=text:find(anchor,start+1,true)
        end
    end
    Search(1,#anchors[1]+1)
    if not ambiguous and attempts<=LIMIT and inspected<=512 then return result,bindings end
end

local function ValidPlurals(segments,values,locale,nativeInput,choices)
    local previous,rangeMinimum,symbolicCondition
    local minimums={}
    for index,node in ipairs(segments) do
        if node.pluralForms then
            local amount=previous
            -- A form can contain its quantity instead of following it.
            for nested=index+1,node.ending do
                local value=values[segments[nested].key]
                if value and value.amount then amount=value.amount;break end
            end
            if not amount then
                -- Some locales put the noun before its quantity. A single
                -- non-duration numeric token gives an unambiguous count; two
                -- possible quantities must remain unresolved.
                local unique
                for _, candidate in ipairs(segments) do
                    local value = candidate.key and not candidate.duration and values[candidate.key]
                    if value and value.amount then
                        if unique and unique ~= candidate.key then amount = nil; break end
                        unique, amount = candidate.key, value.amount
                    end
                end
            end
            -- A fully matched native non-singular condition can identify its
            -- wording even while the client exposes an unresolved counter.
            -- Carry only the observed condition; never infer a number or select
            -- an unobserved target plural form from it.
            local observed=nativeInput and symbolicCondition and choices and choices[symbolicCondition]==2
            if not amount and not observed then return end
            local selected=node.pluralForms[node.selected]
            if amount and Plural(node.pluralForms,amount,locale)~=selected
                and not (nativeInput and rangeMinimum~=nil and Plural(node.pluralForms,rangeMinimum,locale)==selected) then
                return
            end
        elseif node.key then
            local value=values[node.key]
            if value and (value.unresolved or value.capturedText) then
                previous,rangeMinimum=nil,nil
                symbolicCondition=value.unresolved and (node.owner .. ":" .. value.unresolved .. "=1") or nil
            elseif value and value.amount then
                symbolicCondition=nil
                previous,rangeMinimum=value.amount,value.lower and value.lower.amount
                local key=node.owner .. ":" .. node.index
                if node.raw and node.raw:match("^%$%d*m%d*$") then minimums[key]=value.amount end
                if node.raw and node.raw:match("^%$%d*M%d*$") then rangeMinimum=minimums[key] end
            end
        elseif node.literal then
            local amount=Normalize(node.literal):match("(%d+)[ \t\r\n]*$")
            if amount then previous=tonumber(amount);symbolicCondition=nil end
        end
    end
    return true
end

-- Some localized templates spell out a percentage that other locales expose
-- as a token. A single flat percentage is unambiguous only when every other
-- literal is free of numbers. Keep conditional/nested templates on the strict
-- path, and capture the visible quantity rather than the template's constant.
local function CaptureLiteralPercentage(nodes, owner)
    local result, count, synthetic = {}, 0, false
    for index, node in ipairs(nodes) do
        if node.literal then
            local before, amount, after = node.literal:match("^(.-)(%d+)([ \t]*%%.*)$")
            if amount then
                if before:find("%d") or after:find("%d") or before:match("[.,+%-]$") then return end
                count = count + 1
                synthetic = true
                result[#result+1] = {literal=before}
                result[#result+1] = {key=owner .. ":literal-percentage",owner=owner,index=1,shape="captured-percentage"}
                result[#result+1] = {literal=after}
            else
                if node.literal:find("%d") then return end
                result[#result+1] = node
            end
        elseif node.plural then
            -- Word-only inflections add no quantities or alternate bindings.
            for _, form in ipairs(node.plural) do
                for _, part in ipairs(form) do
                    if not part.literal or part.literal:find("%d") then return end
                end
            end
            result[#result+1] = node
        elseif node.key then
            local nextNode = nodes[index+1]
            if not node.valueType and not node.duration and nextNode and nextNode.literal
                and Normalize(nextNode.literal):match("^%%") then
                count = count + 1
                local slot = {}
                for key, value in pairs(node) do slot[key] = value end
                slot.shape = "captured-percentage"
                result[#result+1] = slot
            else result[#result+1] = node end
        else return end
    end
    if count ~= 1 then return end
    return result, synthetic
end

local function Bind(source,target,values)
    local unique,from,to={},{},{}
    for _,node in ipairs(source) do
        if node.key and not unique[node.key] then unique[node.key]=true;from[#from+1]=node end
    end
    unique={}
    for _,node in ipairs(target) do
        if node.key and not unique[node.key] then unique[node.key]=true;to[#to+1]=node end
    end
    if #from~=#to then return end
    local mapping,groups={},{ }
    for side,nodes in ipairs({from,to}) do
        for _,node in ipairs(nodes) do
            local key=node.owner .. ":" .. node.shape
            groups[key]=groups[key] or {{},{}}
            local group=groups[key][side]
            group[#group+1]=node
        end
    end
    for _,group in pairs(groups) do
        local left,right=group[1],group[2]
        if #left~=#right then return end
        local exact=true
        for _,node in ipairs(right) do if not values[node.key] then exact=false end end
        if exact then
            for _,node in ipairs(right) do mapping[node.key]=values[node.key] end
        else
            table.sort(left,function(a,b) return a.index<b.index end)
            table.sort(right,function(a,b) return a.index<b.index end)
            for index,node in ipairs(left) do
                local other=right[index]
                -- Align the whole group by rank, including partially overlapping index sets.
                if index>1 and (node.index==left[index-1].index or other.index==right[index-1].index) then return end
                mapping[other.key]=values[node.key]
            end
        end
    end
    return mapping
end

local function Translate(id,sourceLocale,targetLocale,native,field,unit,requireMatch,valueLocale,inlineTooltips,visibleReferences,literalPercentage,sourceVariant,targetVariant)
    if not Readable(native,"string") or not Readable(id,"number") then return end
    if sourceLocale==targetLocale and not requireMatch then return native end
    local source=Compile(id,sourceLocale,field,unit,inlineTooltips,visibleReferences,sourceVariant)
    local target=Compile(id,targetLocale,field,unit,inlineTooltips,visibleReferences,targetVariant)
    if not source or not target then return end
    if literalPercentage then
        local sourceSynthetic, targetSynthetic
        source, sourceSynthetic = CaptureLiteralPercentage(source,id)
        target, targetSynthetic = CaptureLiteralPercentage(target,id)
        if not source or not target or not (sourceSynthetic or targetSynthetic) then return end
    end
    local attempts,outputs=0,{}
    local function Try(choices)
        attempts=attempts+1
        if attempts>LIMIT then return end
        local segments,missing=Flatten(source,choices)
        if missing then
            if not segments or not PrefixMatches(segments,native) then return end
            for index=1,missing.count do choices[missing.key]=index;Try(choices) end
            choices[missing.key]=nil
            return
        end
        if not segments then return end
        local values,slots=Match(segments,native,sourceLocale,targetLocale,valueLocale)
        if not values or not ValidPlurals(segments,values,sourceLocale,true,choices) then return end
        local targets,targetMissing=Flatten(target,choices)
        if targetMissing then
            -- Only the matched source can decide that a reference was absent.
            if targetMissing.observedPresence then return end
            -- Exact token identities already carry the captured quantity. Choose
            -- its target plural directly instead of enumerating every combination
            -- (several Russian three-form lists otherwise exceed the branch limit).
            local amount
            if targetMissing.forms then
                for _, node in ipairs(targets) do
                    if node.key then
                        local value = values[node.key]
                        amount = value and value.amount or nil
                    elseif node.literal then
                        local literal = Normalize(node.literal):match("(%d+)[ \t\r\n]*$")
                        if literal then amount = tonumber(literal) end
                    end
                end
            end
            local selected = amount and Plural(targetMissing.forms, amount, targetLocale)
            if selected then
                for index, form in ipairs(targetMissing.forms) do
                    if form == selected then choices[targetMissing.key] = index; Try(choices); break end
                end
                choices[targetMissing.key] = nil
                return
            end
            for index=1,targetMissing.count do choices[targetMissing.key]=index;Try(choices) end
            choices[targetMissing.key]=nil
            return
        end
        if not targets then return end
        local mapping=Bind(slots,targets,values)
        if not mapping or not ValidPlurals(targets,mapping,targetLocale) then return end
        local output={}
        for _,node in ipairs(targets) do
            if node.literal then
                output[#output+1]=node.literal
            else
                local value=mapping[node.key]
                if not value then return end
                if value.unresolved and value.unresolved~=node.raw then return end
                if value.lower and node.rangeFormat then
                    output[#output+1]=node.rangeFormat[1] .. FormatNumber(value.lower,targetLocale)
                        .. node.rangeFormat[2] .. FormatNumber(value.upper,targetLocale) .. node.rangeFormat[3]
                else output[#output+1]=value.text end
            end
        end
        -- Keep target typography and captured decimal precision; normalization is only for matching.
        local rendered=(table.concat(output):gsub("\r\n","\n"):gsub("\r","\n")
            :gsub("[ \t]+"," "):gsub(" *\n *","\n"):gsub("^[ \t\r\n]+",""):gsub("[ \t\r\n]+$",""))
        outputs[rendered]=true
    end
    Try({})
    if attempts>LIMIT then return end
    local result, plain
    for output in pairs(outputs) do
        local uncolored = output:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        if plain and plain ~= uncolored then return end
        -- A client can omit inline colors while retaining the same words in both
        -- branches. Do not guess the condition's color; the renderer keeps native styling.
        if result and result ~= output then result = uncolored else result = output end
        plain = uncolored
    end
    return result
end

function Addon:TranslateLiveSpellDescription(id,locale,native,field,unit,inlineTooltips,visibleReferences)
    local ok,result=pcall(Translate,id,GetLocale(),locale,native,field or "description",unit,nil,nil,inlineTooltips,visibleReferences)
    if ok and result then return result end
    -- A localized client may return an English fallback for this owned field. Verify the
    -- same entity's English template, including its captured values, before accepting it.
    if GetLocale()~="enUS" then
        ok,result=pcall(Translate,id,"enUS",locale,native,field or "description",unit,true,GetLocale(),inlineTooltips,visibleReferences)
        if ok and result then return result end
    end
    -- Try the narrowly structured literal/token correspondence only after the
    -- original strict paths fail. Existing successful decodes stay unchanged.
    for _, sourceLocale in ipairs(GetLocale()=="enUS" and {"enUS"} or {GetLocale(),"enUS"}) do
        ok,result=pcall(Translate,id,sourceLocale,locale,native,field or "description",unit,true,GetLocale(),inlineTooltips,visibleReferences,true)
        if ok and result then return result end
    end
    -- Source-backed alternate wording may expose fewer/different quantities.
    -- Keep the primary native template and all strict slot checks. A fallback
    -- is accepted only when complete matching and binding yield one output.
    local function CountVariants(language)
        local details=ForeverRosettaStoneDB:GetSpellDetails(id,language)
        local variants=details and details[(field or "description") .. "Variants"]
        return type(variants)=="table" and math.min(#variants,4) or 0
    end
    local found
    for _, sourceLocale in ipairs(GetLocale()=="enUS" and {"enUS"} or {GetLocale(),"enUS"}) do
        for sourceIndex=0,CountVariants(sourceLocale) do
            for targetIndex=0,CountVariants(locale) do
                if sourceIndex~=0 or targetIndex~=0 then
                    ok,result=pcall(Translate,id,sourceLocale,locale,native,field or "description",unit,true,GetLocale(),
                        inlineTooltips,visibleReferences,nil,sourceIndex~=0 and sourceIndex or nil,targetIndex~=0 and targetIndex or nil)
                    if ok and result then
                        if found and found~=result then return end
                        found=result
                    end
                end
            end
        end
    end
    return found
end

function Addon:TranslateLiveTooltipValue(text, locale, duration)
    if not Readable(text, "string") then return end
    local ok, value = pcall(Value, text, duration, GetLocale(), locale)
    if ok and value then return value.text end
end

-- Client clocks join several quantities ("34 min 49 s"). Split them into the
-- shortest chain of single-unit quantities and translate each with its own format.
function Addon:TranslateLiveCompoundDuration(text, locale)
    if not Readable(text, "string") then return end
    local words = {}
    for word in Normalize(text):gmatch("%S+") do words[#words + 1] = word end
    if #words < 2 then return end
    local sourceLocale = GetLocale()
    local best = {}
    best[0] = {}
    for stop = 1, #words do
        for start = stop, 1, -1 do
            if best[start - 1] then
                local part = table.concat(words, " ", start, stop)
                local ok, value = pcall(Value, part, true, sourceLocale, locale)
                if ok and value then
                    local chain = {}
                    for index, translated in ipairs(best[start - 1]) do chain[index] = translated end
                    chain[#chain + 1] = value.text
                    if not best[stop] or #chain < #best[stop] then best[stop] = chain end
                end
            end
        end
    end
    local chain = best[#words]
    if chain and #chain > 1 then return table.concat(chain, " ") end
end

function Addon:TranslateLiveAuraTime(text, locale)
    if not Readable(text, "string") then return end
    local source, target = Formats(GetLocale()), Formats(locale)
    for _, key in ipairs({"SPELL_TIME_REMAINING_SEC", "SPELL_TIME_REMAINING_MIN",
        "SPELL_TIME_REMAINING_HOURS", "SPELL_TIME_REMAINING_DAYS"}) do
        if Readable(source[key], "string") and Readable(target[key], "string") then
            local value = CaptureQuantity(text, source[key], GetLocale())
            if value then return FormatQuantity(target[key], value, locale) end
        end
    end
end
