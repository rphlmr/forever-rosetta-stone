local _, Probe = ...

-- Explicit calibration inventory, not runtime translation exceptions.
Probe.cases = {
    spells = {
        {code = "D01", id = 598},
        {code = "D02", id = 8102},
        {code = "S01", id = 2054},
        {code = "P01", id = 970},
        {code = "P02", id = 6074},
    },
    items = {
        {code = "O01", id = 1205},
        {code = "O02", id = 2683},
        {code = "O03", id = 20744},
    },
    auraSpells = {6074, 970},
    traitNodes = {105830},
    -- `/frsverify api`: data APIs replayed by tests/lua/support/client-api-fixture.lua.
    -- Each call is a dotted API path, optionally with a format applied to the ID argument.
    api = {
        calls = {
            spell = {"C_Spell.GetSpellInfo", "C_Spell.GetSpellName", "C_Spell.GetSpellDescription",
                "C_Spell.GetSpellSubtext", "C_Spell.GetSpellPowerCost", "C_Spell.IsSpellDataCached",
                {api = "C_TradeSkillUI.GetRecipeSchematic", suffix = {false}},
                "C_TooltipInfo.GetSpellByID"},
            item = {"C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemNameByID",
                "C_Item.IsItemDataCachedByID", "C_TooltipInfo.GetItemByID",
                {api = "C_Item.GetItemStats", format = "item:%d"},
                {api = "C_TooltipInfo.GetHyperlink", format = "item:%d"}},
            quest = {"C_QuestLog.GetTitleForQuestID", {api = "C_TooltipInfo.GetHyperlink", format = "quest:%d"}},
            map = {"C_Map.GetMapInfo"},
            area = {"C_Map.GetAreaInfo"},
            faction = {"C_Reputation.GetFactionDataByID"},
            currency = {"C_CurrencyInfo.GetCurrencyInfo"},
            none = {"GetBuildInfo", "GetLocale"},
        },
        ids = {
            spell = {598, 8102, 2054, 970, 6074, 16757, 433, 439, 17783, 7418},
            item = {1205, 2683, 20744, 118, 5861, 5626, 5627, 15397, 10940},
            quest = {95317},
            map = {},
            area = {},
            faction = {},
            currency = {},
        },
        -- GlobalStrings whose client values Lua tests otherwise type by hand.
        globals = {
            "ARMOR", "ARMOR_TEMPLATE", "CANCEL", "CHESTSLOT", "CONTAINER_SLOTS", "CORPSE",
            "DAMAGE", "DAMAGE_SCHOOL5", "DECIMAL_SEPERATOR", "DEFAULTS", "DURABILITY_TEMPLATE",
            "ENABLE", "EQUIPPED", "EXPERIENCE_COLON", "FRAME_ACTION_CLOSE", "HEALTH", "HOURS_ABBR",
            "IF_EQUIPPED_TOGETHER", "INVTYPE_2HWEAPON", "ITEM_BIND_ON_PICKUP",
            "ITEM_COOLDOWN_TIME", "ITEM_DELTA_DESCRIPTION",
            "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION", "ITEM_MIN_LEVEL", "ITEM_RESIST_ALL",
            "ITEM_RESIST_SINGLE", "ITEM_SOULBOUND", "ITEM_SPELL_CHARGES",
            "ITEM_SPELL_TRIGGER_ONEQUIP", "ITEM_SPELL_TRIGGER_ONUSE", "ITEM_UNIQUE",
            "ITEM_UNIQUE_EQUIPPABLE", "ITEM_UNIQUE_MULTIPLE", "LARGE_NUMBER_SEPERATOR",
            "MANA_COST", "MINUTES_ABBR", "PROFESSIONS_USED_IN_COOKING", "QUEST_OBJECTIVES",
            "QUEST_TOOLTIP_REQUIREMENTS", "RESISTANCE_TOOLTIP_SUBTEXT", "RESISTANCE_TYPE4",
            "REWARD_ITEMS_ONLY", "REWARD_SPELL", "SECONDS_ABBR", "SHIELD_BLOCK_TEMPLATE",
            "SPELL_CAST_TIME_INSTANT", "SPELL_ON_NEXT_SWING", "SPELL_PASSIVE", "SPELL_RANGE",
            "SPELL_RANGE_DUAL", "SPELL_REAGENTS", "SPELL_RECAST_TIME_MIN", "SPELL_RECAST_TIME_SEC",
            "SPELL_SCHOOL2_CAP", "SPELL_SCHOOL3_CAP", "SPELL_TOTEMS", "STAT_FORMAT",
            "STAT_HEALTH_TOOLTIP", "UNITNAME_SUMMON_TITLE27", "UNITNAME_SUMMON_TITLE4",
            "UNITNAME_SUMMON_TITLE7", "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_MINION",
            "UNITNAME_TITLE_PET"},
        loadTimeout = 10,
    },
}
