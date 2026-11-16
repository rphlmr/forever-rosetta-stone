-- Adapt miniature tooltip fixtures to the provider's native-source API.
return function(database)
    database.GetQuestSource = database.GetQuest
    database.GetSourceSpellName = database.GetSpellName

    local function SourceDetails(method, id, locale)
        local original = method(database, id, "enUS")
        if not original then return end
        local details = {}
        for key, value in pairs(original) do details[key] = value end
        if locale ~= "enUS" then
            details.description = original.sourceDescriptions and original.sourceDescriptions[locale]
            details.rank = original.sourceRanks and original.sourceRanks[locale]
            details.nameDescription = original.sourceNameDescriptions and original.sourceNameDescriptions[locale]
        end
        return details
    end

    function database:GetSpellSourceDetails(id, locale)
        return SourceDetails(self.GetSpellDetails, id, locale)
    end

    function database:GetItemSourceDetails(id, locale)
        return SourceDetails(self.GetItemDetails, id, locale)
    end
end
