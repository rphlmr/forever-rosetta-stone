local _, Addon = ...

-- Blizzard's CJK faces are available separately from the client's active UI locale.
local fonts = {
    zhCN = { [[Fonts\ARKai_T.ttf]], [[Fonts\ARKai_C.ttf]] },
    zhTW = { [[Fonts\blei00d.TTF]], [[Fonts\bKAI00M.TTF]] },
    koKR = { [[Fonts\2002.TTF]], [[Fonts\K_Pagetext.TTF]] },
}

function Addon:UsesLocalizedFont(locale)
    return fonts[locale] ~= nil
end

function Addon:TryLocalizedFont(target, locale, size, flags)
    local candidates = fonts[locale]
    if not target or not candidates then return false end
    if not size then
        local font
        font, size, flags = target:GetFont()
        if not font or not size then return false end
    end
    for _, path in ipairs(candidates) do
        local ok, applied = pcall(target.SetFont, target, path, size, flags)
        if ok and applied then return true end
    end
    return false
end
