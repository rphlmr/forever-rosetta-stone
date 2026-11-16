local _, Addon = ...

-- AI translation; human review is still needed.
Addon.tooltipFormatsByLocale.svSE = {
    SPELL_TOTEMS = "Verktyg: ",
    SELL_PRICE = "Försäljningspris",
    SECONDS_ABBR = "%d sek", MINUTES_ABBR = "%d min", HOURS_ABBR = "%d tim",
    DAYS_ABBR = "%d |4dag:dagar;", SPELL_DURATION_UNTIL_CANCELLED = "tills den avbryts",
    SECOND_ONELETTER_ABBR = "%d s", MINUTE_ONELETTER_ABBR = "%d m",
    HOUR_ONELETTER_ABBR = "%d h", DAY_ONELETTER_ABBR = "%d d",
    ARMOR_TEMPLATE = "%s rustning", SHIELD_BLOCK_TEMPLATE = "%s blockering",
    DURABILITY_TEMPLATE = "Hållbarhet %d / %d", DAMAGE_PER_SECOND = "Skada per sekund",
    DAMAGE_TEMPLATE = "%s - %s skada", DAMAGE_TEMPLATE_WITH_SCHOOL = "%s - %s %s skada",
    SINGLE_DAMAGE_TEMPLATE = "%s skada", SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "%s %s skada",
    PLUS_DAMAGE_TEMPLATE = "+ %s - %s skada", PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s - %s %s skada",
    PLUS_SINGLE_DAMAGE_TEMPLATE = "+ %s skada", PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s %s skada",
    DPS_TEMPLATE = "(%s skada per sekund)", AMMO_DAMAGE_TEMPLATE = "Lägger till %s skada per sekund",
    CONTAINER_SLOTS = "%d platser: %s", COOLDOWN_REMAINING = "Återstående nedkylning:",
    ITEM_BIND_ON_EQUIP = "Binds när den utrustas", ITEM_BIND_ON_PICKUP = "Binds när den plockas upp",
    ITEM_BIND_ON_USE = "Binds när den används", ITEM_BIND_QUEST = "Uppdragsföremål",
    ITEM_BIND_TO_ACCOUNT = "Kontobundet", ITEM_BIND_TO_BNETACCOUNT = "Kontobundet",
    ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP = "Kontobundet tills det utrustas", ITEM_SOULBOUND = "Själsbundet",
    ITEM_UNIQUE = "Unik", ITEM_UNIQUE_EQUIPPABLE = "Unik vid utrustning", ITEM_UNIQUE_MULTIPLE = "Unik (%d)",
    ITEM_MIN_LEVEL = "Kräver nivå %d", ITEM_MIN_SKILL = "Kräver %s (%d)", ITEM_REQ_SKILL = "Kräver %s",
    ITEM_CLASSES_ALLOWED = "Klasser: %s", ITEM_REQ_REPUTATION = "Kräver %s - %s",
    ITEM_SET_BONUS = "Set: %s", ITEM_SET_BONUS_GRAY = "(%d) Set: %s", ITEM_SET_NAME = "%s (%d/%d)",
    ITEM_SPELL_TRIGGER_ONUSE = "Använd:", ITEM_SPELL_TRIGGER_ONEQUIP = "Utrustad:",
    ITEM_SPELL_TRIGGER_ONPROC = "Chans vid träff:", ITEM_SPELL_EFFECT = "Effekt: %s",
    ITEM_SPELL_CHARGES = "%d |4laddning:laddningar;", ITEM_SPELL_CHARGES_NONE = "Inga laddningar",
    ITEM_SPELL_KNOWN = "Redan känd", ITEM_SPELL_MAX_USABLE_LEVEL = " (Kräver högst nivå %d)",
    ITEM_MOD_AGILITY = "%c%s smidighet", ITEM_MOD_AGILITY_SHORT = "Smidighet",
    ITEM_MOD_STRENGTH = "%c%s styrka", ITEM_MOD_STRENGTH_SHORT = "Styrka",
    ITEM_MOD_STAMINA = "%c%s uthållighet", ITEM_MOD_STAMINA_SHORT = "Uthållighet",
    ITEM_MOD_INTELLECT = "%c%s intelligens", ITEM_MOD_INTELLECT_SHORT = "Intelligens",
    ITEM_MOD_SPIRIT = "%c%s ande", ITEM_MOD_SPIRIT_SHORT = "Ande",
    ITEM_MOD_HEALTH = "%c%s hälsa", ITEM_MOD_HEALTH_SHORT = "Hälsa",
    ITEM_MOD_MANA = "%c%s mana", ITEM_MOD_MANA_SHORT = "Mana",
    MANA_COST = "%s mana", MANA_COST_LARGE = "%s mana", ENERGY_COST = "%s energi", RAGE_COST = "%s vrede",
    SPELL_CAST_TIME_INSTANT = "Omedelbar", SPELL_CAST_TIME_INSTANT_NO_MANA = "Omedelbar",
    SPELL_CAST_TIME_SEC = "%.2g sek kasttid", SPELL_CAST_TIME_MIN = "%.2g min kasttid",
    SPELL_CAST_CHANNELED = "Kanaliserad", SPELL_PASSIVE = "Passiv", SPELL_PASSIVE_EFFECT = "Passiv",
    SPELL_PASSIVE_SECOND = "Passiv", SPELL_RANGE = "%s yards räckvidd", MELEE_RANGE = "Närstridsräckvidd",
    SPELL_RANGE_DUAL = "%1$s: %2$s yards räckvidd", SPELL_RANGE_UNLIMITED = "Obegränsad räckvidd",
    SPELL_RECAST_TIME_SEC = "%.2g sek nedkylning", SPELL_RECAST_TIME_MIN = "%.2g min nedkylning",
    SPELL_RECAST_TIME_HOURS = "%.2g tim nedkylning", SPELL_RECAST_TIME_DAYS = "%.2g dagar nedkylning",
    SPELL_RECAST_TIME_INSTANT = "Omedelbar nedkylning", RANK = "Rang",
    TOOLTIP_TALENT_RANK = "Rang %d/%d", TOOLTIP_TALENT_RANK_CURRENT_ONLY = "Rang %d",
    TALENT_BUTTON_TOOLTIP_RANK_FORMAT = "Rang %s/%s", TALENT_BUTTON_TOOLTIP_RANK_NO_MAX_FORMAT = "Rang %s",
    QUEST_TOOLTIP_ACTIVE = "Du har detta uppdrag", QUEST_TOOLTIP_REQUIREMENTS = "Krav:",
    WEAPON_SPEED = "Attackhastighet", SPEED = "Hastighet", SPELL_REAGENTS = "Reagenser: |n",
    INVTYPE_HEAD = "Huvud", INVTYPE_NECK = "Hals", INVTYPE_BODY = "Skjorta", INVTYPE_CHEST = "Bröst",
    INVTYPE_ROBE = "Bröst", INVTYPE_LEGS = "Ben", INVTYPE_FEET = "Fötter", INVTYPE_WRIST = "Handleder",
    INVTYPE_HAND = "Händer", INVTYPE_FINGER = "Finger", INVTYPE_WEAPON = "Enhandsvapen",
    INVTYPE_WEAPONMAINHAND = "Huvudhand", INVTYPE_WEAPONOFFHAND = "Andra handen", INVTYPE_SHIELD = "Andra handen",
    INVTYPE_RANGED = "Avståndsvapen", INVTYPE_RANGEDRIGHT = "Avståndsvapen", INVTYPE_CLOAK = "Rygg",
    INVTYPE_2HWEAPON = "Tvåhandsvapen", INVTYPE_BAG = "Väska", INVTYPE_HOLDABLE = "Hålls i andra handen",
    INVTYPE_TABARD = "Tabard", INVTYPE_SHOULDER = "Axlar", INVTYPE_TRINKET = "Smycke", INVTYPE_WAIST = "Midja",
    INVTYPE_RELIC = "Relik", INVTYPE_AMMO = "Ammunition", INVTYPE_THROWN = "Kastvapen", INVTYPE_QUIVER = "Koger",
    INVTYPE_NON_EQUIP = "Kan inte utrustas", INVTYPE_PROFESSION_TOOL = "Yrkesverktyg",
    INVTYPE_PROFESSION_GEAR = "Yrkesutrustning", INVTYPE_WEAPONMAINHAND_PET = "Huvudattack",
    ALCHEMY = "Alkemi", BLACKSMITHING = "Smide", COOKING = "Matlagning", ENCHANTING = "Förtrollning",
    ENGINEERING = "Ingenjörskonst", FIRST_AID = "Första hjälpen", FISHING = "Fiske", HERBALISM = "Örtlära",
    LEATHERWORKING = "Läderarbete", MINING = "Gruvdrift", SKINNING = "Flåning", TAILORING = "Sömnad",
    DAMAGE_SCHOOL2 = "Helig", DAMAGE_SCHOOL3 = "Eld", DAMAGE_SCHOOL4 = "Natur", DAMAGE_SCHOOL5 = "Frost",
    DAMAGE_SCHOOL6 = "Skugga", DAMAGE_SCHOOL7 = "Arkan", RESISTANCE0_NAME = "Rustning",
    RESISTANCE1_NAME = "Heligt motstånd", RESISTANCE2_NAME = "Eldmotstånd", RESISTANCE3_NAME = "Naturmotstånd",
    RESISTANCE4_NAME = "Frostmotstånd", RESISTANCE5_NAME = "Skuggmotstånd", RESISTANCE6_NAME = "Arkant motstånd",
    RESISTANCE_LABEL = "Motstånd", RESISTANCE_NONE = "Inget", RESISTANCE_POOR = "Dåligt",
    RESISTANCE_FAIR = "Acceptabelt", RESISTANCE_GOOD = "Bra", RESISTANCE_VERYGOOD = "Mycket bra",
    RESISTANCE_EXCELLENT = "Utmärkt", RESISTANCE_TEMPLATE = "%d %s",
    ITEM_REQ_ALLIANCE = "Endast Alliansen", ITEM_REQ_HORDE = "Endast Horden", ITEM_REQ_PURCHASE_GUILD = "Kräver ett gille",
    ITEM_REQ_PURCHASE_GUILD_LEVEL = "Kräver gillesnivå %d", ITEM_REQ_PURCHASE_ACHIEVEMENT = "Kräver prestation: %s",
    ITEM_REQ_SPECIALIZATION = "Kräver: %s", RACIAL_ABILITIES = "Rasförmågor",
    PROFESSIONS_USED_IN_COOKING = "Hantverksreagens", PROFESSIONS_MODIFIED_CRAFTING_REAGENT_BASIC = "Hantverksreagens",
    PROFESSIONS_MODIFIED_CRAFTING_REAGENT_MODIFYING_REQUIRED = "Hantverksreagens",
    ITEM_COOLDOWN_TIME = "Återstående nedkylning: %s", ITEM_COOLDOWN_TIME_DAYS = "Återstående nedkylning: %d |4dag:dagar;",
    ITEM_COOLDOWN_TIME_HOURS = "Återstående nedkylning: %d |4timme:timmar;",
    ITEM_COOLDOWN_TIME_MIN = "Återstående nedkylning: %d min", ITEM_COOLDOWN_TIME_SEC = "Återstående nedkylning: %d sek",
    ITEM_COOLDOWN_TOTAL = "(%s nedkylning)", ITEM_COOLDOWN_TOTAL_DAYS = "(%d |4dag:dagar; nedkylning)",
    ITEM_COOLDOWN_TOTAL_HOURS = "(%d |4timme:timmar; nedkylning)", ITEM_COOLDOWN_TOTAL_MIN = "(%d min nedkylning)",
    ITEM_COOLDOWN_TOTAL_SEC = "(%d sek nedkylning)", SPELL_ON_NEXT_RANGED = "Attackhastighet",
    SPELL_ON_NEXT_SWING = "Nästa närstridsattack", SPELL_RANGE_AREA = "Området runt kastaren",
    SPELL_CAST_TIME_RANGED = "Attackhastighet +%.2g sek", SPELL_RECAST_TIME_CHARGES_DAYS = "%.2g dagars uppladdning",
    SPELL_RECAST_TIME_CHARGES_HOURS = "%.2g timmars uppladdning", SPELL_RECAST_TIME_CHARGES_MIN = "%.2g min uppladdning",
    SPELL_RECAST_TIME_CHARGES_SEC = "%.2g sek uppladdning", SPELL_RECAST_TIME_CHARGES_INSTANT = "Omedelbar uppladdning",
    SPELL_RECAST_TIME_CHARGEUP_DAYS = "Kräver %.2g |4dag:dagar;", SPELL_RECAST_TIME_CHARGEUP_HOURS = "Kräver %.2g |4timme:timmar;",
    SPELL_RECAST_TIME_CHARGEUP_MIN = "Kräver %.2g min", SPELL_RECAST_TIME_CHARGEUP_SEC = "Kräver %.2g sek",
    SPELL_RECAST_TIME_CHARGEUP_INSTANT = "Omedelbar", ITEM_ACCOUNTBOUND = "Kontobundet",
    ITEM_ACCOUNTBOUND_UNTIL_EQUIP = "Kontobundet tills det utrustas", ITEM_BNETACCOUNTBOUND = "Kontobundet",
}

local statNames = {
    ATTACK_POWER = "attackkraft", ARMOR_PENETRATION_RATING = "rustningspenetration", BLOCK_RATING = "blockering",
    BLOCK_VALUE = "blockeringsvärde", CRIT_RATING = "kritisk träff", CRIT_MELEE_RATING = "kritisk träff i närstrid",
    CRIT_RANGED_RATING = "kritisk träff på avstånd", CRIT_SPELL_RATING = "kritisk besvärjelseträff",
    DODGE_RATING = "undanmanöver", PARRY_RATING = "parering", DEFENSE_SKILL_RATING = "försvar",
    EXPERTISE_RATING = "expertis", EXTRA_ARMOR = "bonusrustning", HASTE_RATING = "snabbhet", HIT_RATING = "träffsäkerhet",
    HIT_MELEE_RATING = "träffsäkerhet i närstrid", HIT_RANGED_RATING = "träffsäkerhet på avstånd",
    HIT_SPELL_RATING = "träffsäkerhet med besvärjelser", MASTERY_RATING = "mästerskap", PVP_POWER = "PvP-kraft",
    RANGED_ATTACK_POWER = "attackkraft på avstånd", RESILIENCE_RATING = "PvP-motståndskraft",
    SPELL_POWER = "besvärjelsekraft", SPELL_PENETRATION = "besvärjelsepenetration",
    SPELL_RESISTANCE_ALL_SCHOOLS = "besvärjelsemotstånd", SPELL_DAMAGE_DONE = "besvärjelseskada",
    SPELL_HEALING_DONE = "besvärjelseläkning", FIRE_DAMAGE_DONE = "eldskada", FROST_DAMAGE_DONE = "frostskada",
    NATURE_DAMAGE_DONE = "naturskada", SHADOW_DAMAGE_DONE = "skuggskada", HOLY_DAMAGE_DONE = "helig skada",
    ARCANE_DAMAGE_DONE = "arkanskada", PHYSICAL_DAMAGE_DONE = "fysisk skada", FIRE_PENETRATION = "eldpenetration",
    FROST_PENETRATION = "frostpenetration", NATURE_PENETRATION = "naturpenetration",
    SHADOW_PENETRATION = "skuggpenetration", ARCANE_PENETRATION = "arkanpenetration",
    ALCHEMY = "alkemifärdighet", BLACKSMITHING = "smidesfärdighet", COOKING = "matlagningsfärdighet",
    ENCHANTING = "förtrollningsfärdighet", ENGINEERING = "ingenjörsfärdighet", FIRST_AID = "första hjälpen",
    FISHING = "fiskefärdighet", HERBALISM = "örtfärdighet", LEATHERWORKING = "läderarbetsfärdighet",
    MINING = "gruvfärdighet", SKINNING = "flåningsfärdighet", TAILORING = "sömnadsfärdighet",
    AXES = "yxfärdighet", BOWS = "bågfärdighet", CROSSBOWS = "armborstfärdighet", DAGGERS = "dolkfärdighet",
    GUNS = "gevärsfärdighet", MACES = "klubbfärdighet", POLEARMS = "stångvapenfärdighet", STAVES = "stavfärdighet",
    SWORDS = "svärdfärdighet", THROWN = "kastvapenfärdighet", WANDS = "trollstavsfärdighet",
    FIST_WEAPONS = "knytnävsvapenfärdighet", DUAL_WIELD = "färdighet med två vapen",
    TWOHANDED_AXES = "färdighet med tvåhandsyxor", TWOHANDED_MACES = "färdighet med tvåhandsklubbor",
    TWOHANDED_SWORDS = "färdighet med tvåhandssvärd", JEWELCRAFTING = "juvelerarfärdighet",
}
for suffix, name in pairs(statNames) do
    local key = "ITEM_MOD_" .. suffix
    if Addon.englishTooltipFormats[key .. "_SHORT"] then Addon.tooltipFormatsByLocale.svSE[key .. "_SHORT"] = name end
    local english = Addon.englishTooltipFormats[key]
    if english and english:match("^Increases .- by %%s%.$") then
        Addon.tooltipFormatsByLocale.svSE[key] = "Ökar " .. name .. " med %s."
    elseif english and english:match("^Improves .- by %%s%.$") then
        Addon.tooltipFormatsByLocale.svSE[key] = "Förbättrar " .. name .. " med %s."
    elseif english and english:match("^Increases .- by up to %%s%.$") then
        Addon.tooltipFormatsByLocale.svSE[key] = "Ökar " .. name .. " med upp till %s."
    end
end

local additional = {
    ENERGY_COST_PER_TIME = "%s energi, plus %s per sek", ENERGY_COST_PER_TIME_NO_BASE = "%s energi per sek",
    MANA_COST_PER_TIME = "%s mana, plus %s per sek", MANA_COST_PER_TIME_NO_BASE = "%s mana per sek",
    MANA_COST_LARGE_PER_TIME = "%s mana, plus %s per sek", MANA_COST_LARGE_PER_TIME_NO_BASE = "%s mana per sek",
    RAGE_COST_PER_TIME = "%s vrede, plus %s per sek", RAGE_COST_PER_TIME_NO_BASE = "%s vrede per sek",
    RUNIC_POWER_COST = "%s runkraft", RUNIC_POWER_COST_PER_TIME = "%s runkraft, plus %s per sek",
    RUNIC_POWER_COST_PER_TIME_NO_BASE = "%s runkraft per sek", INVTYPE_NON_EQUIP_IGNORE = "",
    INVTYPE_EQUIPABLESPELL_DEFENSIVE = "Utrustningsbar besvärjelse - defensiv",
    INVTYPE_EQUIPABLESPELL_OFFENSIVE = "Utrustningsbar besvärjelse - offensiv",
    INVTYPE_EQUIPABLESPELL_UTILITY = "Utrustningsbar besvärjelse - nytta", INVTYPE_EQUIPABLESPELL_WEAPON = "Utrustningsbar besvärjelse - vapen",
    ITEM_MOD_AGILITY_OR_INTELLECT_SHORT = "Smidighet eller intelligens", ITEM_MOD_AGILITY_OR_STRENGTH_SHORT = "Smidighet eller styrka",
    ITEM_MOD_STRENGTH_OR_INTELLECT_SHORT = "Styrka eller intelligens",
    ITEM_MOD_AGILITY_OR_STRENGTH_OR_INTELLECT_SHORT = "Smidighet, styrka eller intelligens",
    ITEM_MOD_CORRUPTION = "Korruption", ITEM_MOD_CORRUPTION_RESISTANCE = "Korruptionsmotstånd",
    ITEM_MOD_CRAFTING_SPEED_SHORT = "Tillverkningshastighet", ITEM_MOD_CR_AVOIDANCE_SHORT = "Undvikande",
    ITEM_MOD_CR_LIFESTEAL_SHORT = "Livsstöld", ITEM_MOD_CR_MULTISTRIKE_SHORT = "Multiträff",
    ITEM_MOD_CR_SPEED_SHORT = "Hastighet", ITEM_MOD_CR_STURDINESS_SHORT = "Oförstörbar",
    ITEM_MOD_CR_UNUSED_10_SHORT = "Oanvänd 10", ITEM_MOD_CR_UNUSED_11_SHORT = "Oanvänd 11",
    ITEM_MOD_CR_UNUSED_12_SHORT = "Oanvänd 12", ITEM_MOD_CR_UNUSED_1_SHORT = "Multiträff",
    ITEM_MOD_CR_UNUSED_3_SHORT = "Hastighet", ITEM_MOD_CR_UNUSED_4_SHORT = "Livsstöld",
    ITEM_MOD_CR_UNUSED_5_SHORT = "Undvikande", ITEM_MOD_CR_UNUSED_6_SHORT = "Oförstörbar",
    ITEM_MOD_CR_UNUSED_7_SHORT = "Oanvänd 7", ITEM_MOD_CR_UNUSED_9_SHORT = "Mångsidighet",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "skada per sekund", ITEM_MOD_DEFTNESS_SHORT = "Skicklighet",
    ITEM_MOD_FINESSE_SHORT = "Finess", ITEM_MOD_INGENUITY_SHORT = "Uppfinningsrikedom",
    ITEM_MOD_INSPIRATION_SHORT = "Inspiration", ITEM_MOD_MULTICRAFT_SHORT = "Flerproduktion",
    ITEM_MOD_PERCEPTION_SHORT = "Uppfattning", ITEM_MOD_RESOURCEFULNESS_SHORT = "Resursfullhet",
    ITEM_MOD_VERSATILITY = "Mångsidighet", ITEM_MOD_PVP_PRIMARY_STAT_SHORT = "PvP-kraft",
    ITEM_MOD_HEALTH_REGEN = "Återställer %s hälsa per 5 sek.", ITEM_MOD_HEALTH_REGENERATION = "Återställer %s hälsa per 5 sek.",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "Hälsoregenerering", ITEM_MOD_HEALTH_REGEN_SHORT = "Hälsa per 5 sek",
    ITEM_MOD_MANA_REGENERATION = "Återställer %s mana per 5 sek.", ITEM_MOD_MANA_REGENERATION_SHORT = "Manaregenerering per 5 sek",
    ITEM_MOD_MASTERY_RATING_SPELL = "(%s)", ITEM_MOD_MASTERY_RATING_TWO_SPELLS = "(%s/%s)",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "Attackkraft i närstrid", ITEM_MOD_MODIFIED_CRAFTING_STAT_1 = "Slumpmässig egenskap 1",
    ITEM_MOD_MODIFIED_CRAFTING_STAT_2 = "Slumpmässig egenskap 2", ITEM_MOD_POWER_REGEN0_SHORT = "Mana per 5 sek",
    ITEM_MOD_POWER_REGEN1_SHORT = "Vrede per 5 sek", ITEM_MOD_POWER_REGEN2_SHORT = "Fokus per 5 sek",
    ITEM_MOD_POWER_REGEN3_SHORT = "Energi per 5 sek", ITEM_MOD_POWER_REGEN4_SHORT = "Lycka per 5 sek",
    ITEM_MOD_POWER_REGEN5_SHORT = "Runor per 5 sek", ITEM_MOD_POWER_REGEN6_SHORT = "Runkraft per 5 sek",
    ITEM_MOD_FERAL_ATTACK_POWER = "Ökar attackkraften med %s endast i katt-, björn-, ursinnesbjörn- och månskensform.",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "Attackkraft i former",
    ITEM_REQ_AMOUNT_EARNED = "Kräver totalt intjänat %1$d\n%2$s under säsongen.",
    ITEM_REQ_ARENA_RATING = "Kräver personligt arenabetyg %d", ITEM_REQ_ARENA_RATING_3V3 = "Kräver personligt arenabetyg %d|ni 3v3-gruppen.",
    ITEM_REQ_ARENA_RATING_5V5 = "Kräver personligt arenabetyg %d|ni 5v5-gruppen",
    ITEM_REQ_ARENA_RATING_BG = "Kräver slagfältsbetyg %d eller|npersonligt arenabetyg %d",
    ITEM_REQ_ARENA_RATING_3V3_BG = "Kräver slagfältsbetyg %d eller|npersonligt arenabetyg %d|ni 3v3-gruppen.",
}
for key, value in pairs(additional) do Addon.tooltipFormatsByLocale.svSE[key] = value end
local labels = Addon.tooltipFormatsByLocale.svSE
local schools = { "fysisk", "helig", "eld", "natur", "frost", "skugga", "arkan" }
for index = 0, 6 do
    labels["RESISTANCE_TYPE" .. index] = index == 0 and "rustning" or schools[index + 1]
    labels["SPELL_SCHOOL" .. index .. "_NAME"] = schools[index + 1]
    labels["SPELL_SCHOOL" .. index .. "_CAP"] = schools[index + 1]:gsub("^%l", string.upper)
end
local targets = { BEAST = "vilddjur", DEMON = "demoner", DRAGONKIN = "drakvarelser", ELEMENTAL = "elementarer",
    GIANT = "jättar", HUMANOID = "humanoider", MECHANICAL = "mekaniska varelser", UNDEAD = "odöda" }
for key, name in pairs(targets) do
    labels["ITEM_MOD_ATTACK_POWER_VS_" .. key .. "_SHORT"] = "Attackkraft mot " .. name
    labels["ITEM_MOD_SPELL_DAMAGE_VS_" .. key .. "_SHORT"] = "Besvärjelseskada mot " .. name
end
local avoidance = { [""] = "undvikande av träffar", MELEE_ = "undvikande av närstridsträffar",
    RANGED_ = "undvikande av avståndsträffar", SPELL_ = "undvikande av besvärjelseträffar" }
for suffix, name in pairs(avoidance) do
    for _, prefix in ipairs({ "HIT_TAKEN_", "CRIT_TAKEN_" }) do
        local key = "ITEM_MOD_" .. prefix .. suffix .. "RATING"
        local text = prefix == "CRIT_TAKEN_" and "kritiskt " .. name or name
        labels[key], labels[key .. "_SHORT"] = "Förbättrar " .. text .. " med %s.", text
    end
end

Addon.itemSubclassesByLocale.svSE = {
    [0] = { [0] = "Sprängämnen", [1] = "Drycker", [2] = "Elixir", [3] = "Flaskor", [4] = "Skriftrullar",
        [5] = "Mat och dryck", [6] = "Permanent", [7] = "Bandage", [8] = "Övrigt", [13] = "Dryck",
        [14] = "Anordning", [15] = "Tillfällig", [-1] = "Nytt föremål" },
    [1] = { [0] = "Väska", [1] = "Själsväska", [2] = "Örtväska", [3] = "Förtrollningsväska",
        [4] = "Ingenjörsväska", [6] = "Gruvväska", [7] = "Läderarbetarväska", [9] = "Fiskelåda",
        [10] = "Matlagningsväska", [11] = "Reagensväska", [12] = "Smyckesväska" },
    [2] = { [0] = "Yxa", [1] = "Yxa", [2] = "Båge", [3] = "Gevär", [4] = "Stridsklubba", [5] = "Stridsklubba",
        [6] = "Stångvapen", [7] = "Svärd", [8] = "Svärd", [9] = "Krigsglaiver", [10] = "Stav", [11] = "Exotiskt",
        [12] = "Exotiskt", [13] = "Knytnävsvapen", [14] = "Övrigt", [15] = "Dolk", [16] = "Kastvapen",
        [17] = "Spjut", [18] = "Armborst", [19] = "Trollstav", [20] = "Fiskespö" },
    [3] = { [0] = "Smycken (föråldrat)" },
    [4] = { [0] = "Övrigt", [1] = "Tyg", [2] = "Läder", [3] = "Ringbrynja", [4] = "Plåt", [5] = "Kosmetiskt",
        [6] = "Sköld", [7] = "Libram", [8] = "Idol", [9] = "Totem" },
    [5] = { [0] = "Reagens" }, [6] = { [0] = "Trollstav (föråldrat)", [1] = "Skäkta (föråldrat)",
        [2] = "Pil", [3] = "Kula", [4] = "Kastvapen (föråldrat)" },
    [7] = { [0] = "Handelsvaror (föråldrat)", [1] = "Delar", [2] = "Sprängämnen (föråldrat)",
        [3] = "Anordningar (föråldrat)", [5] = "Tyg", [6] = "Läder", [7] = "Metall och sten", [8] = "Matlagning",
        [9] = "Ört", [10] = "Elementärt", [11] = "Övrigt", [12] = "Förtrollning" },
    [8] = { [0] = "Allmänt (föråldrat)" }, [9] = { [0] = "Bok", [1] = "Läderarbete", [2] = "Sömnad",
        [3] = "Ingenjörskonst", [4] = "Smide", [5] = "Matlagning", [6] = "Alkemi", [7] = "Första hjälpen",
        [8] = "Förtrollning", [9] = "Fiske" }, [10] = { [0] = "Pengar (föråldrat)" },
    [11] = { [0] = "Koger (föråldrat)", [1] = "Koger (föråldrat)", [2] = "Koger", [3] = "Ammunitionsväska" },
    [12] = { [0] = "Uppdrag" }, [13] = { [0] = "Nyckel", [1] = "Dyrk" }, [14] = { [0] = "Permanent" },
    [15] = { [0] = "Skräp", [1] = "Reagens", [2] = "Husdjur", [3] = "Högtid", [4] = "Övrigt", [5] = "Riddjur" },
}
