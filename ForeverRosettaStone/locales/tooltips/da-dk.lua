local _, Addon = ...

-- AI translation; human review is still needed.
Addon.tooltipFormatsByLocale.daDK = {
    SPELL_TOTEMS = "Værktøjer: ",
    SELL_PRICE = "Salgspris",
    SECONDS_ABBR = "%d sek", MINUTES_ABBR = "%d min", HOURS_ABBR = "%d t",
    DAYS_ABBR = "%d |4dag:dage;", SPELL_DURATION_UNTIL_CANCELLED = "indtil den afbrydes",
    SECOND_ONELETTER_ABBR = "%d s", MINUTE_ONELETTER_ABBR = "%d m",
    HOUR_ONELETTER_ABBR = "%d t", DAY_ONELETTER_ABBR = "%d d",
    ARMOR_TEMPLATE = "%s rustning", SHIELD_BLOCK_TEMPLATE = "%s blokering",
    DURABILITY_TEMPLATE = "Holdbarhed %d / %d", DAMAGE_PER_SECOND = "Skade pr. sekund",
    DAMAGE_TEMPLATE = "%s - %s skade", DAMAGE_TEMPLATE_WITH_SCHOOL = "%s - %s %s skade",
    SINGLE_DAMAGE_TEMPLATE = "%s skade", SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "%s %s skade",
    PLUS_DAMAGE_TEMPLATE = "+ %s - %s skade", PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s - %s %s skade",
    PLUS_SINGLE_DAMAGE_TEMPLATE = "+ %s skade", PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s %s skade",
    DPS_TEMPLATE = "(%s skade pr. sekund)", AMMO_DAMAGE_TEMPLATE = "Tilføjer %s skade pr. sekund",
    CONTAINER_SLOTS = "%d pladser: %s", COOLDOWN_REMAINING = "Resterende nedkøling:",
    ITEM_BIND_ON_EQUIP = "Bindes ved udstyring", ITEM_BIND_ON_PICKUP = "Bindes ved opsamling",
    ITEM_BIND_ON_USE = "Bindes ved brug", ITEM_BIND_QUEST = "Opgavegenstand",
    ITEM_BIND_TO_ACCOUNT = "Kontobundet", ITEM_BIND_TO_BNETACCOUNT = "Kontobundet",
    ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP = "Kontobundet indtil udstyring", ITEM_SOULBOUND = "Sjælebundet",
    ITEM_UNIQUE = "Unik", ITEM_UNIQUE_EQUIPPABLE = "Unik ved udstyring", ITEM_UNIQUE_MULTIPLE = "Unik (%d)",
    ITEM_MIN_LEVEL = "Kræver niveau %d", ITEM_MIN_SKILL = "Kræver %s (%d)", ITEM_REQ_SKILL = "Kræver %s",
    ITEM_CLASSES_ALLOWED = "Klasser: %s", ITEM_REQ_REPUTATION = "Kræver %s - %s",
    ITEM_SET_BONUS = "Sæt: %s", ITEM_SET_BONUS_GRAY = "(%d) Sæt: %s", ITEM_SET_NAME = "%s (%d/%d)",
    ITEM_SPELL_TRIGGER_ONUSE = "Brug:", ITEM_SPELL_TRIGGER_ONEQUIP = "Udstyret:",
    ITEM_SPELL_TRIGGER_ONPROC = "Chance ved træf:", ITEM_SPELL_EFFECT = "Effekt: %s",
    ITEM_SPELL_CHARGES = "%d |4ladning:ladninger;", ITEM_SPELL_CHARGES_NONE = "Ingen ladninger",
    ITEM_SPELL_KNOWN = "Allerede kendt", ITEM_SPELL_MAX_USABLE_LEVEL = " (Kræver højst niveau %d)",
    ITEM_MOD_AGILITY = "%c%s smidighed", ITEM_MOD_AGILITY_SHORT = "Smidighed",
    ITEM_MOD_STRENGTH = "%c%s styrke", ITEM_MOD_STRENGTH_SHORT = "Styrke",
    ITEM_MOD_STAMINA = "%c%s udholdenhed", ITEM_MOD_STAMINA_SHORT = "Udholdenhed",
    ITEM_MOD_INTELLECT = "%c%s intellekt", ITEM_MOD_INTELLECT_SHORT = "Intellekt",
    ITEM_MOD_SPIRIT = "%c%s ånd", ITEM_MOD_SPIRIT_SHORT = "Ånd",
    ITEM_MOD_HEALTH = "%c%s helbred", ITEM_MOD_HEALTH_SHORT = "Helbred",
    ITEM_MOD_MANA = "%c%s mana", ITEM_MOD_MANA_SHORT = "Mana",
    MANA_COST = "%s mana", MANA_COST_LARGE = "%s mana", ENERGY_COST = "%s energi", RAGE_COST = "%s raseri",
    SPELL_CAST_TIME_INSTANT = "Øjeblikkelig", SPELL_CAST_TIME_INSTANT_NO_MANA = "Øjeblikkelig",
    SPELL_CAST_TIME_SEC = "%.2g sek kastetid", SPELL_CAST_TIME_MIN = "%.2g min kastetid",
    SPELL_CAST_CHANNELED = "Kanaliseret", SPELL_PASSIVE = "Passiv", SPELL_PASSIVE_EFFECT = "Passiv",
    SPELL_PASSIVE_SECOND = "Passiv", SPELL_RANGE = "%s yards rækkevidde", MELEE_RANGE = "Nærkampsrækkevidde",
    SPELL_RANGE_DUAL = "%1$s: %2$s yards rækkevidde", SPELL_RANGE_UNLIMITED = "Ubegrænset rækkevidde",
    SPELL_RECAST_TIME_SEC = "%.2g sek nedkøling", SPELL_RECAST_TIME_MIN = "%.2g min nedkøling",
    SPELL_RECAST_TIME_HOURS = "%.2g t nedkøling", SPELL_RECAST_TIME_DAYS = "%.2g dage nedkøling",
    SPELL_RECAST_TIME_INSTANT = "Øjeblikkelig nedkøling", RANK = "Rang",
    TOOLTIP_TALENT_RANK = "Rang %d/%d", TOOLTIP_TALENT_RANK_CURRENT_ONLY = "Rang %d",
    TALENT_BUTTON_TOOLTIP_RANK_FORMAT = "Rang %s/%s", TALENT_BUTTON_TOOLTIP_RANK_NO_MAX_FORMAT = "Rang %s",
    QUEST_TOOLTIP_ACTIVE = "Du har denne opgave", QUEST_TOOLTIP_REQUIREMENTS = "Krav:",
    WEAPON_SPEED = "Angrebshastighed", SPEED = "Hastighed", SPELL_REAGENTS = "Reagenser: |n",
    INVTYPE_HEAD = "Hoved", INVTYPE_NECK = "Hals", INVTYPE_BODY = "Skjorte", INVTYPE_CHEST = "Bryst",
    INVTYPE_ROBE = "Bryst", INVTYPE_LEGS = "Ben", INVTYPE_FEET = "Fødder", INVTYPE_WRIST = "Håndled",
    INVTYPE_HAND = "Hænder", INVTYPE_FINGER = "Finger", INVTYPE_WEAPON = "Enhåndsvåben",
    INVTYPE_WEAPONMAINHAND = "Hovedhånd", INVTYPE_WEAPONOFFHAND = "Anden hånd", INVTYPE_SHIELD = "Anden hånd",
    INVTYPE_RANGED = "Afstandsvåben", INVTYPE_RANGEDRIGHT = "Afstandsvåben", INVTYPE_CLOAK = "Ryg",
    INVTYPE_2HWEAPON = "Tohåndsvåben", INVTYPE_BAG = "Taske", INVTYPE_HOLDABLE = "Holdes i anden hånd",
    INVTYPE_TABARD = "Våbenkjortel", INVTYPE_SHOULDER = "Skuldre", INVTYPE_TRINKET = "Smykke", INVTYPE_WAIST = "Talje",
    INVTYPE_RELIC = "Relikvie", INVTYPE_AMMO = "Ammunition", INVTYPE_THROWN = "Kastevåben", INVTYPE_QUIVER = "Kogger",
    INVTYPE_NON_EQUIP = "Kan ikke udstyres", INVTYPE_PROFESSION_TOOL = "Fagværktøj",
    INVTYPE_PROFESSION_GEAR = "Fagudstyr", INVTYPE_WEAPONMAINHAND_PET = "Hovedangreb",
    ALCHEMY = "Alkymi", BLACKSMITHING = "Smedning", COOKING = "Madlavning", ENCHANTING = "Fortryllelse",
    ENGINEERING = "Ingeniørkunst", FIRST_AID = "Førstehjælp", FISHING = "Fiskeri", HERBALISM = "Urtekunst",
    LEATHERWORKING = "Læderarbejde", MINING = "Minedrift", SKINNING = "Flåning", TAILORING = "Skrædderi",
    DAMAGE_SCHOOL2 = "Hellig", DAMAGE_SCHOOL3 = "Ild", DAMAGE_SCHOOL4 = "Natur", DAMAGE_SCHOOL5 = "Frost",
    DAMAGE_SCHOOL6 = "Skygge", DAMAGE_SCHOOL7 = "Arkan", RESISTANCE0_NAME = "Rustning",
    RESISTANCE1_NAME = "Hellig modstand", RESISTANCE2_NAME = "Ildmodstand", RESISTANCE3_NAME = "Naturmodstand",
    RESISTANCE4_NAME = "Frostmodstand", RESISTANCE5_NAME = "Skyggemodstand", RESISTANCE6_NAME = "Arkan modstand",
    RESISTANCE_LABEL = "Modstand", RESISTANCE_NONE = "Ingen", RESISTANCE_POOR = "Dårlig",
    RESISTANCE_FAIR = "Rimelig", RESISTANCE_GOOD = "God", RESISTANCE_VERYGOOD = "Meget god",
    RESISTANCE_EXCELLENT = "Fremragende", RESISTANCE_TEMPLATE = "%d %s",
    ITEM_REQ_ALLIANCE = "Kun Alliancen", ITEM_REQ_HORDE = "Kun Horden", ITEM_REQ_PURCHASE_GUILD = "Kræver en guild",
    ITEM_REQ_PURCHASE_GUILD_LEVEL = "Kræver guildniveau %d", ITEM_REQ_PURCHASE_ACHIEVEMENT = "Kræver præstation: %s",
    ITEM_REQ_SPECIALIZATION = "Kræver: %s", RACIAL_ABILITIES = "Raceevner",
    PROFESSIONS_USED_IN_COOKING = "Fremstillingsreagens", PROFESSIONS_MODIFIED_CRAFTING_REAGENT_BASIC = "Fremstillingsreagens",
    PROFESSIONS_MODIFIED_CRAFTING_REAGENT_MODIFYING_REQUIRED = "Fremstillingsreagens",
    ITEM_COOLDOWN_TIME = "Resterende nedkøling: %s", ITEM_COOLDOWN_TIME_DAYS = "Resterende nedkøling: %d |4dag:dage;",
    ITEM_COOLDOWN_TIME_HOURS = "Resterende nedkøling: %d |4time:timer;",
    ITEM_COOLDOWN_TIME_MIN = "Resterende nedkøling: %d min", ITEM_COOLDOWN_TIME_SEC = "Resterende nedkøling: %d sek",
    ITEM_COOLDOWN_TOTAL = "(%s nedkøling)", ITEM_COOLDOWN_TOTAL_DAYS = "(%d |4dag:dage; nedkøling)",
    ITEM_COOLDOWN_TOTAL_HOURS = "(%d |4time:timer; nedkøling)", ITEM_COOLDOWN_TOTAL_MIN = "(%d min nedkøling)",
    ITEM_COOLDOWN_TOTAL_SEC = "(%d sek nedkøling)", SPELL_ON_NEXT_RANGED = "Angrebshastighed",
    SPELL_ON_NEXT_SWING = "Næste nærkampsangreb", SPELL_RANGE_AREA = "Området omkring kasteren",
    SPELL_CAST_TIME_RANGED = "Angrebshastighed +%.2g sek", SPELL_RECAST_TIME_CHARGES_DAYS = "%.2g dages genopladning",
    SPELL_RECAST_TIME_CHARGES_HOURS = "%.2g timers genopladning", SPELL_RECAST_TIME_CHARGES_MIN = "%.2g min genopladning",
    SPELL_RECAST_TIME_CHARGES_SEC = "%.2g sek genopladning", SPELL_RECAST_TIME_CHARGES_INSTANT = "Øjeblikkelig genopladning",
    SPELL_RECAST_TIME_CHARGEUP_DAYS = "Kræver %.2g |4dag:dage;", SPELL_RECAST_TIME_CHARGEUP_HOURS = "Kræver %.2g |4time:timer;",
    SPELL_RECAST_TIME_CHARGEUP_MIN = "Kræver %.2g min", SPELL_RECAST_TIME_CHARGEUP_SEC = "Kræver %.2g sek",
    SPELL_RECAST_TIME_CHARGEUP_INSTANT = "Øjeblikkelig", ITEM_ACCOUNTBOUND = "Kontobundet",
    ITEM_ACCOUNTBOUND_UNTIL_EQUIP = "Kontobundet indtil udstyring", ITEM_BNETACCOUNTBOUND = "Kontobundet",
}

local statNames = {
    ATTACK_POWER = "angrebskraft", ARMOR_PENETRATION_RATING = "rustningsgennemtrængning", BLOCK_RATING = "blokering",
    BLOCK_VALUE = "blokeringsværdi", CRIT_RATING = "kritisk træf", CRIT_MELEE_RATING = "kritisk nærkampstræf",
    CRIT_RANGED_RATING = "kritisk afstandstræf", CRIT_SPELL_RATING = "kritisk magitræf",
    DODGE_RATING = "undvigelse", PARRY_RATING = "parering", DEFENSE_SKILL_RATING = "forsvar",
    EXPERTISE_RATING = "ekspertise", EXTRA_ARMOR = "bonusrustning", HASTE_RATING = "hastighed", HIT_RATING = "træfsikkerhed",
    HIT_MELEE_RATING = "træfsikkerhed i nærkamp", HIT_RANGED_RATING = "træfsikkerhed på afstand",
    HIT_SPELL_RATING = "træfsikkerhed med magi", MASTERY_RATING = "mesterskab", PVP_POWER = "PvP-kraft",
    RANGED_ATTACK_POWER = "angrebskraft på afstand", RESILIENCE_RATING = "PvP-modstandsdygtighed",
    SPELL_POWER = "magikraft", SPELL_PENETRATION = "magigennemtrængning",
    SPELL_RESISTANCE_ALL_SCHOOLS = "magimodstand", SPELL_DAMAGE_DONE = "magiskade",
    SPELL_HEALING_DONE = "magihelbredelse", FIRE_DAMAGE_DONE = "ildskade", FROST_DAMAGE_DONE = "frostskade",
    NATURE_DAMAGE_DONE = "naturskade", SHADOW_DAMAGE_DONE = "skyggeskade", HOLY_DAMAGE_DONE = "hellig skade",
    ARCANE_DAMAGE_DONE = "arkanskade", PHYSICAL_DAMAGE_DONE = "fysisk skade", FIRE_PENETRATION = "ildgennemtrængning",
    FROST_PENETRATION = "frostgennemtrængning", NATURE_PENETRATION = "naturgennemtrængning",
    SHADOW_PENETRATION = "skyggegennemtrængning", ARCANE_PENETRATION = "arkangennemtrængning",
    ALCHEMY = "alkymifærdighed", BLACKSMITHING = "smedefærdighed", COOKING = "madlavningsfærdighed",
    ENCHANTING = "fortryllelsesfærdighed", ENGINEERING = "ingeniørfærdighed", FIRST_AID = "førstehjælpsfærdighed",
    FISHING = "fiskefærdighed", HERBALISM = "urtefærdighed", LEATHERWORKING = "læderarbejdsfærdighed",
    MINING = "minefærdighed", SKINNING = "flåningsfærdighed", TAILORING = "skrædderfærdighed",
    AXES = "øksefærdighed", BOWS = "buefærdighed", CROSSBOWS = "armbrøstfærdighed", DAGGERS = "dolkfærdighed",
    GUNS = "geværfærdighed", MACES = "køllefærdighed", POLEARMS = "stangvåbenfærdighed", STAVES = "stavfærdighed",
    SWORDS = "sværdfærdighed", THROWN = "kastevåbenfærdighed", WANDS = "tryllestavsfærdighed",
    FIST_WEAPONS = "nævevåbenfærdighed", DUAL_WIELD = "færdighed med to våben",
    TWOHANDED_AXES = "færdighed med tohåndsøkser", TWOHANDED_MACES = "færdighed med tohåndskøller",
    TWOHANDED_SWORDS = "færdighed med tohåndssværd", JEWELCRAFTING = "juvelerfærdighed",
}
for suffix, name in pairs(statNames) do
    local key = "ITEM_MOD_" .. suffix
    if Addon.englishTooltipFormats[key .. "_SHORT"] then Addon.tooltipFormatsByLocale.daDK[key .. "_SHORT"] = name end
    local english = Addon.englishTooltipFormats[key]
    if english and english:match("^Increases .- by %%s%.$") then
        Addon.tooltipFormatsByLocale.daDK[key] = "Øger " .. name .. " med %s."
    elseif english and english:match("^Improves .- by %%s%.$") then
        Addon.tooltipFormatsByLocale.daDK[key] = "Forbedrer " .. name .. " med %s."
    elseif english and english:match("^Increases .- by up to %%s%.$") then
        Addon.tooltipFormatsByLocale.daDK[key] = "Øger " .. name .. " med op til %s."
    end
end

local additional = {
    ENERGY_COST_PER_TIME = "%s energi, plus %s pr. sek", ENERGY_COST_PER_TIME_NO_BASE = "%s energi pr. sek",
    MANA_COST_PER_TIME = "%s mana, plus %s pr. sek", MANA_COST_PER_TIME_NO_BASE = "%s mana pr. sek",
    MANA_COST_LARGE_PER_TIME = "%s mana, plus %s pr. sek", MANA_COST_LARGE_PER_TIME_NO_BASE = "%s mana pr. sek",
    RAGE_COST_PER_TIME = "%s raseri, plus %s pr. sek", RAGE_COST_PER_TIME_NO_BASE = "%s raseri pr. sek",
    RUNIC_POWER_COST = "%s runekraft", RUNIC_POWER_COST_PER_TIME = "%s runekraft, plus %s pr. sek",
    RUNIC_POWER_COST_PER_TIME_NO_BASE = "%s runekraft pr. sek", INVTYPE_NON_EQUIP_IGNORE = "",
    INVTYPE_EQUIPABLESPELL_DEFENSIVE = "Udstyrbar besværgelse - defensiv",
    INVTYPE_EQUIPABLESPELL_OFFENSIVE = "Udstyrbar besværgelse - offensiv",
    INVTYPE_EQUIPABLESPELL_UTILITY = "Udstyrbar besværgelse - nytte", INVTYPE_EQUIPABLESPELL_WEAPON = "Udstyrbar besværgelse - våben",
    ITEM_MOD_AGILITY_OR_INTELLECT_SHORT = "Smidighed eller intellekt", ITEM_MOD_AGILITY_OR_STRENGTH_SHORT = "Smidighed eller styrke",
    ITEM_MOD_STRENGTH_OR_INTELLECT_SHORT = "Styrke eller intellekt",
    ITEM_MOD_AGILITY_OR_STRENGTH_OR_INTELLECT_SHORT = "Smidighed, styrke eller intellekt",
    ITEM_MOD_CORRUPTION = "Korruption", ITEM_MOD_CORRUPTION_RESISTANCE = "Korruptionsmodstand",
    ITEM_MOD_CRAFTING_SPEED_SHORT = "Fremstillingshastighed", ITEM_MOD_CR_AVOIDANCE_SHORT = "Undvigelse",
    ITEM_MOD_CR_LIFESTEAL_SHORT = "Livstyveri", ITEM_MOD_CR_MULTISTRIKE_SHORT = "Multitræf",
    ITEM_MOD_CR_SPEED_SHORT = "Hastighed", ITEM_MOD_CR_STURDINESS_SHORT = "Uforgængelig",
    ITEM_MOD_CR_UNUSED_10_SHORT = "Ubrugt 10", ITEM_MOD_CR_UNUSED_11_SHORT = "Ubrugt 11",
    ITEM_MOD_CR_UNUSED_12_SHORT = "Ubrugt 12", ITEM_MOD_CR_UNUSED_1_SHORT = "Multitræf",
    ITEM_MOD_CR_UNUSED_3_SHORT = "Hastighed", ITEM_MOD_CR_UNUSED_4_SHORT = "Livstyveri",
    ITEM_MOD_CR_UNUSED_5_SHORT = "Undvigelse", ITEM_MOD_CR_UNUSED_6_SHORT = "Uforgængelig",
    ITEM_MOD_CR_UNUSED_7_SHORT = "Ubrugt 7", ITEM_MOD_CR_UNUSED_9_SHORT = "Alsidighed",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "skade pr. sekund", ITEM_MOD_DEFTNESS_SHORT = "Behændighed",
    ITEM_MOD_FINESSE_SHORT = "Finesse", ITEM_MOD_INGENUITY_SHORT = "Opfindsomhed",
    ITEM_MOD_INSPIRATION_SHORT = "Inspiration", ITEM_MOD_MULTICRAFT_SHORT = "Flerproduktion",
    ITEM_MOD_PERCEPTION_SHORT = "Opfattelse", ITEM_MOD_RESOURCEFULNESS_SHORT = "Ressourcefuldhed",
    ITEM_MOD_VERSATILITY = "Alsidighed", ITEM_MOD_PVP_PRIMARY_STAT_SHORT = "PvP-kraft",
    ITEM_MOD_HEALTH_REGEN = "Gendanner %s helbred pr. 5 sek.", ITEM_MOD_HEALTH_REGENERATION = "Gendanner %s helbred pr. 5 sek.",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "Helbredsregenerering", ITEM_MOD_HEALTH_REGEN_SHORT = "Helbred pr. 5 sek",
    ITEM_MOD_MANA_REGENERATION = "Gendanner %s mana pr. 5 sek.", ITEM_MOD_MANA_REGENERATION_SHORT = "Manaregenerering pr. 5 sek",
    ITEM_MOD_MASTERY_RATING_SPELL = "(%s)", ITEM_MOD_MASTERY_RATING_TWO_SPELLS = "(%s/%s)",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "Angrebskraft i nærkamp", ITEM_MOD_MODIFIED_CRAFTING_STAT_1 = "Tilfældig egenskab 1",
    ITEM_MOD_MODIFIED_CRAFTING_STAT_2 = "Tilfældig egenskab 2", ITEM_MOD_POWER_REGEN0_SHORT = "Mana pr. 5 sek",
    ITEM_MOD_POWER_REGEN1_SHORT = "Raseri pr. 5 sek", ITEM_MOD_POWER_REGEN2_SHORT = "Fokus pr. 5 sek",
    ITEM_MOD_POWER_REGEN3_SHORT = "Energi pr. 5 sek", ITEM_MOD_POWER_REGEN4_SHORT = "Lykke pr. 5 sek",
    ITEM_MOD_POWER_REGEN5_SHORT = "Runer pr. 5 sek", ITEM_MOD_POWER_REGEN6_SHORT = "Runekraft pr. 5 sek",
    ITEM_MOD_FERAL_ATTACK_POWER = "Øger angrebskraft med %s kun i katte-, bjørne-, kampbjørne- og måneugleform.",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "Angrebskraft i former",
    ITEM_REQ_AMOUNT_EARNED = "Kræver i alt optjent %1$d\n%2$s i sæsonen.",
    ITEM_REQ_ARENA_RATING = "Kræver personlig arenavurdering %d", ITEM_REQ_ARENA_RATING_3V3 = "Kræver personlig arenavurdering %d|ni 3v3-gruppen.",
    ITEM_REQ_ARENA_RATING_5V5 = "Kræver personlig arenavurdering %d|ni 5v5-gruppen",
    ITEM_REQ_ARENA_RATING_BG = "Kræver slagmarksvurdering %d eller|npersonlig arenavurdering %d",
    ITEM_REQ_ARENA_RATING_3V3_BG = "Kræver slagmarksvurdering %d eller|npersonlig arenavurdering %d|ni 3v3-gruppen.",
}
for key, value in pairs(additional) do Addon.tooltipFormatsByLocale.daDK[key] = value end
local labels = Addon.tooltipFormatsByLocale.daDK
local schools = { "fysisk", "hellig", "ild", "natur", "frost", "skygge", "arkan" }
for index = 0, 6 do
    labels["RESISTANCE_TYPE" .. index] = index == 0 and "rustning" or schools[index + 1]
    labels["SPELL_SCHOOL" .. index .. "_NAME"] = schools[index + 1]
    labels["SPELL_SCHOOL" .. index .. "_CAP"] = schools[index + 1]:gsub("^%l", string.upper)
end
local targets = { BEAST = "vilddyr", DEMON = "dæmoner", DRAGONKIN = "dragevæsner", ELEMENTAL = "elementarer",
    GIANT = "jætter", HUMANOID = "humanoider", MECHANICAL = "mekaniske væsner", UNDEAD = "udøde" }
for key, name in pairs(targets) do
    labels["ITEM_MOD_ATTACK_POWER_VS_" .. key .. "_SHORT"] = "Angrebskraft mod " .. name
    labels["ITEM_MOD_SPELL_DAMAGE_VS_" .. key .. "_SHORT"] = "Magiskade mod " .. name
end
local avoidance = { [""] = "undgåelse af træf", MELEE_ = "undgåelse af nærkampstræf",
    RANGED_ = "undgåelse af afstandstræf", SPELL_ = "undgåelse af magitræf" }
for suffix, name in pairs(avoidance) do
    for _, prefix in ipairs({ "HIT_TAKEN_", "CRIT_TAKEN_" }) do
        local key = "ITEM_MOD_" .. prefix .. suffix .. "RATING"
        local text = prefix == "CRIT_TAKEN_" and "kritisk " .. name or name
        labels[key], labels[key .. "_SHORT"] = "Forbedrer " .. text .. " med %s.", text
    end
end

Addon.itemSubclassesByLocale.daDK = {
    [0] = { [0] = "Sprængstoffer", [1] = "Trylledrikke", [2] = "Eliksirer", [3] = "Kolber", [4] = "Skriftruller",
        [5] = "Mad og drikke", [6] = "Permanent", [7] = "Forbindinger", [8] = "Andet", [13] = "Drik",
        [14] = "Anordning", [15] = "Midlertidig", [-1] = "Ny genstand" },
    [1] = { [0] = "Taske", [1] = "Sjæletaske", [2] = "Urtetaske", [3] = "Fortryllelsestaske",
        [4] = "Ingeniørtaske", [6] = "Minetaske", [7] = "Læderarbejdertaske", [9] = "Fiskegrejskasse",
        [10] = "Madlavningstaske", [11] = "Reagenstaske", [12] = "Smykketaske" },
    [2] = { [0] = "Økse", [1] = "Økse", [2] = "Bue", [3] = "Gevær", [4] = "Stridskølle", [5] = "Stridskølle",
        [6] = "Stangvåben", [7] = "Sværd", [8] = "Sværd", [9] = "Krigsglaiver", [10] = "Stav", [11] = "Eksotisk",
        [12] = "Eksotisk", [13] = "Nævevåben", [14] = "Diverse", [15] = "Dolk", [16] = "Kastevåben",
        [17] = "Spyd", [18] = "Armbrøst", [19] = "Tryllestav", [20] = "Fiskestang" },
    [3] = { [0] = "Smykker (forældet)" },
    [4] = { [0] = "Diverse", [1] = "Stof", [2] = "Læder", [3] = "Ringbrynje", [4] = "Plade", [5] = "Kosmetisk",
        [6] = "Skjold", [7] = "Libram", [8] = "Idol", [9] = "Totem" },
    [5] = { [0] = "Reagens" }, [6] = { [0] = "Tryllestav (forældet)", [1] = "Bolt (forældet)",
        [2] = "Pil", [3] = "Kugle", [4] = "Kastevåben (forældet)" },
    [7] = { [0] = "Handelsvarer (forældet)", [1] = "Dele", [2] = "Sprængstoffer (forældet)",
        [3] = "Anordninger (forældet)", [5] = "Stof", [6] = "Læder", [7] = "Metal og sten", [8] = "Madlavning",
        [9] = "Urt", [10] = "Elementært", [11] = "Andet", [12] = "Fortryllelse" },
    [8] = { [0] = "Generisk (forældet)" }, [9] = { [0] = "Bog", [1] = "Læderarbejde", [2] = "Skrædderi",
        [3] = "Ingeniørkunst", [4] = "Smedning", [5] = "Madlavning", [6] = "Alkymi", [7] = "Førstehjælp",
        [8] = "Fortryllelse", [9] = "Fiskeri" }, [10] = { [0] = "Penge (forældet)" },
    [11] = { [0] = "Kogger (forældet)", [1] = "Kogger (forældet)", [2] = "Kogger", [3] = "Ammunitionstaske" },
    [12] = { [0] = "Opgave" }, [13] = { [0] = "Nøgle", [1] = "Dirk" }, [14] = { [0] = "Permanent" },
    [15] = { [0] = "Skrammel", [1] = "Reagens", [2] = "Kæledyr", [3] = "Højtid", [4] = "Andet", [5] = "Ridedyr" },
}
