local _, Addon = ...

Addon:RegisterNameTooltipComponent({
    kind = "minimapLocation",
    defaultContext = "zoneHeader",
    alwaysFull = true,
    GetName = function(name, locale)
        local location = ForeverRosettaStoneDB:GetPlayerLocation(locale)
        if not location then return end
        -- Either native line can trigger the update; one unresolved line must not hide the other.
        if location.zone.nativeName == name then return location.zone.name or location.subzone.name end
        if location.subzone.nativeName == name then return location.subzone.name or location.zone.name end
    end,
    FillTooltip = function(tip, source)
        local location = ForeverRosettaStoneDB:GetPlayerLocation(Addon:GetTargetLocale())
        if not location then return end
        local count = 0
        for index, area in ipairs({ location.zone, location.subzone }) do
            if area.nativeName ~= "" and (index == 1 or area.nativeName ~= location.zone.nativeName) then
                local translated = area.name
                if translated then
                    local original = source:GetLeftLine(index)
                    local r, g, b = 1, 1, 1
                    if original then r, g, b = original:GetTextColor() end
                    count = count + 1
                    if count == 1 then
                        Addon:SetCompanionTooltipTitle(tip, translated, r, g, b)
                    else
                        tip:AddLine(translated, r, g, b)
                    end
                    local line = tip:GetLeftLine(count)
                    Addon:CopyQuestTextStyle(line, original)
                    if line and original then line:SetTextScale(original:GetTextScale()) end
                end
            end
        end
    end,
    Install = function()
        hooksecurefunc(GameTooltip, "AddLine", function(source, text)
            if Addon.lifecycle ~= "ready" or source:IsForbidden()
                or Addon.tooltipRendering == source
                or not MinimapCluster or source:GetOwner() ~= MinimapCluster.ZoneTextButton then return end

            local nativeLine = source:NumLines()
            local zone, subzone = GetZoneText(), GetSubZoneText()
            local isZone = nativeLine == 1 and text == zone
            local isSubzone = nativeLine == 2 and subzone ~= "" and subzone ~= zone and text == subzone
            if not isZone and not isSubzone then return end

            Addon:Run("translate minimap location line", Addon.UpdateNameTooltip, Addon,
                source, "minimapLocation", text, nil, Addon:GetTooltipPresentation(GameTooltip) ~= "separate")
        end)
    end,
})
