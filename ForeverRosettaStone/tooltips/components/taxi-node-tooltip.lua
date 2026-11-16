local _, Addon = ...

local function ResolveTaxiNode(source)
    if source ~= GameTooltip or not TaxiFrame or not TaxiFrame:IsShown()
        or not C_TaxiMap or not C_TaxiMap.GetAllTaxiNodes or not GetTaxiMapID then return end
    local owner = source:GetOwner()
    if not owner or owner:IsForbidden() or not owner.GetID then return end
    local slot = owner:GetID()
    -- Taxi buttons carry a session-local slot, not a TaxiNodes table ID.
    if not Addon:IsReadableEntityID(slot) or _G["TaxiButton" .. slot] ~= owner then return end
    local parent = owner
    while parent and parent ~= TaxiFrame do
        if parent:IsForbidden() then return end
        parent = parent:GetParent()
    end
    if not parent then return end
    local mapID = GetTaxiMapID()
    if not Addon:IsReadableEntityID(mapID) then return end
    local nodes = C_TaxiMap.GetAllTaxiNodes(mapID)
    if not canaccessallvalues(nodes) or type(nodes) ~= "table" then return end
    local id
    for _, node in ipairs(nodes) do
        if canaccessallvalues(node) and type(node) == "table"
            and canaccessallvalues(node.slotIndex) and node.slotIndex == slot then
            if not Addon:IsReadableEntityID(node.nodeID) or id then return end
            id = node.nodeID
        end
    end
    return id
end

Addon:RegisterNameTooltipComponent({
    kind = "taxiNode",
    defaultContext = "flightMap",
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetTaxiNodeName(id, locale) end,
    ResolveOwner = ResolveTaxiNode,
    FillTooltip = function(tip, source, name, red, green, blue)
        Addon:SetCompanionTooltipTitle(tip, name, red, green, blue)
        local owner = source:GetOwner()
        if Addon.preferences.tooltipCoverage == "full" and owner and TaxiNodeGetType
            and TaxiNodeGetType(owner:GetID()) == "CURRENT" then
            local label = Addon:GetClientLabel("TAXINODEYOUAREHERE", Addon:GetTargetLocale())
            if label then tip:AddLine(label, 1, 1, 1) end
        end
    end,
})
