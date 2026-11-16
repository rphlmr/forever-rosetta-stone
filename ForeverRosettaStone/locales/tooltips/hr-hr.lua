local _, Addon = ...

-- AI translation; human review is still needed.
Addon.tooltipFormatsByLocale.hrHR = {
    SPELL_TOTEMS = "Alati: ",
    SELL_PRICE = "Prodajna cijena",
    SECONDS_ABBR = "%d s", MINUTES_ABBR = "%d min", HOURS_ABBR = "%d h",
    DAYS_ABBR = "%d |4dan:dana:dana;", SPELL_DURATION_UNTIL_CANCELLED = "do prekida",
    SECOND_ONELETTER_ABBR = "%d s", MINUTE_ONELETTER_ABBR = "%d m",
    HOUR_ONELETTER_ABBR = "%d h", DAY_ONELETTER_ABBR = "%d d",
    ARMOR_TEMPLATE = "%s oklopa", SHIELD_BLOCK_TEMPLATE = "%s blokiranja",
    DURABILITY_TEMPLATE = "Trajnost %d / %d", DAMAGE_PER_SECOND = "Šteta u sekundi",
    DAMAGE_TEMPLATE = "%s - %s štete", DAMAGE_TEMPLATE_WITH_SCHOOL = "%s - %s %s štete",
    SINGLE_DAMAGE_TEMPLATE = "%s štete", SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "%s %s štete",
    PLUS_DAMAGE_TEMPLATE = "+ %s - %s štete", PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s - %s %s štete",
    PLUS_SINGLE_DAMAGE_TEMPLATE = "+ %s štete", PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s %s štete",
    DPS_TEMPLATE = "(%s štete u sekundi)", AMMO_DAMAGE_TEMPLATE = "Dodaje %s štete u sekundi",
    CONTAINER_SLOTS = "%d mjesta: %s", COOLDOWN_REMAINING = "Preostalo vrijeme oporavka:",
    ITEM_BIND_ON_EQUIP = "Veže se pri opremanju", ITEM_BIND_ON_PICKUP = "Veže se pri preuzimanju",
    ITEM_BIND_ON_USE = "Veže se pri uporabi", ITEM_BIND_QUEST = "Predmet zadatka",
    ITEM_BIND_TO_ACCOUNT = "Vezano za račun", ITEM_BIND_TO_BNETACCOUNT = "Vezano za račun",
    ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP = "Vezano za račun do opremanja", ITEM_SOULBOUND = "Vezano za dušu",
    ITEM_UNIQUE = "Jedinstveno", ITEM_UNIQUE_EQUIPPABLE = "Jedinstveno pri opremanju", ITEM_UNIQUE_MULTIPLE = "Jedinstveno (%d)",
    ITEM_MIN_LEVEL = "Zahtijeva razinu %d", ITEM_MIN_SKILL = "Zahtijeva %s (%d)", ITEM_REQ_SKILL = "Zahtijeva %s",
    ITEM_CLASSES_ALLOWED = "Klase: %s", ITEM_REQ_REPUTATION = "Zahtijeva %s - %s",
    ITEM_SET_BONUS = "Komplet: %s", ITEM_SET_BONUS_GRAY = "(%d) Komplet: %s", ITEM_SET_NAME = "%s (%d/%d)",
    ITEM_SPELL_TRIGGER_ONUSE = "Uporaba:", ITEM_SPELL_TRIGGER_ONEQUIP = "Opremljeno:",
    ITEM_SPELL_TRIGGER_ONPROC = "Mogućnost pri pogotku:", ITEM_SPELL_EFFECT = "Učinak: %s",
    ITEM_SPELL_CHARGES = "%d |4punjenje:punjenja:punjenja;", ITEM_SPELL_CHARGES_NONE = "Nema punjenja",
    ITEM_SPELL_KNOWN = "Već poznato", ITEM_SPELL_MAX_USABLE_LEVEL = " (Zahtijeva najviše razinu %d)",
    ITEM_MOD_AGILITY = "%c%s okretnosti", ITEM_MOD_AGILITY_SHORT = "Okretnost",
    ITEM_MOD_STRENGTH = "%c%s snage", ITEM_MOD_STRENGTH_SHORT = "Snaga",
    ITEM_MOD_STAMINA = "%c%s izdržljivosti", ITEM_MOD_STAMINA_SHORT = "Izdržljivost",
    ITEM_MOD_INTELLECT = "%c%s intelekta", ITEM_MOD_INTELLECT_SHORT = "Intelekt",
    ITEM_MOD_SPIRIT = "%c%s duha", ITEM_MOD_SPIRIT_SHORT = "Duh",
    ITEM_MOD_HEALTH = "%c%s zdravlja", ITEM_MOD_HEALTH_SHORT = "Zdravlje",
    ITEM_MOD_MANA = "%c%s mane", ITEM_MOD_MANA_SHORT = "Mana",
    MANA_COST = "%s mane", MANA_COST_LARGE = "%s mane", ENERGY_COST = "%s energije", RAGE_COST = "%s bijesa",
    SPELL_CAST_TIME_INSTANT = "Trenutačno", SPELL_CAST_TIME_INSTANT_NO_MANA = "Trenutačno",
    SPELL_CAST_TIME_SEC = "%.2g s bacanja", SPELL_CAST_TIME_MIN = "%.2g min bacanja",
    SPELL_CAST_CHANNELED = "Kanalizirano", SPELL_PASSIVE = "Pasivno", SPELL_PASSIVE_EFFECT = "Pasivno",
    SPELL_PASSIVE_SECOND = "Pasivno", SPELL_RANGE = "Domet %s jardi", MELEE_RANGE = "Domet bliske borbe",
    SPELL_RANGE_DUAL = "%1$s: domet %2$s jardi", SPELL_RANGE_UNLIMITED = "Neograničen domet",
    SPELL_RECAST_TIME_SEC = "%.2g s oporavka", SPELL_RECAST_TIME_MIN = "%.2g min oporavka",
    SPELL_RECAST_TIME_HOURS = "%.2g h oporavka", SPELL_RECAST_TIME_DAYS = "%.2g dana oporavka",
    SPELL_RECAST_TIME_INSTANT = "Trenutačan oporavak", RANK = "Rang",
    TOOLTIP_TALENT_RANK = "Rang %d/%d", TOOLTIP_TALENT_RANK_CURRENT_ONLY = "Rang %d",
    TALENT_BUTTON_TOOLTIP_RANK_FORMAT = "Rang %s/%s", TALENT_BUTTON_TOOLTIP_RANK_NO_MAX_FORMAT = "Rang %s",
    QUEST_TOOLTIP_ACTIVE = "Imate ovaj zadatak", QUEST_TOOLTIP_REQUIREMENTS = "Zahtjevi:",
    WEAPON_SPEED = "Brzina napada", SPEED = "Brzina", SPELL_REAGENTS = "Reagensi: |n",
    INVTYPE_HEAD = "Glava", INVTYPE_NECK = "Vrat", INVTYPE_BODY = "Košulja", INVTYPE_CHEST = "Prsa",
    INVTYPE_ROBE = "Prsa", INVTYPE_LEGS = "Noge", INVTYPE_FEET = "Stopala", INVTYPE_WRIST = "Zapešća",
    INVTYPE_HAND = "Šake", INVTYPE_FINGER = "Prst", INVTYPE_WEAPON = "Jednoručno oružje",
    INVTYPE_WEAPONMAINHAND = "Glavna ruka", INVTYPE_WEAPONOFFHAND = "Druga ruka", INVTYPE_SHIELD = "Druga ruka",
    INVTYPE_RANGED = "Dalekometno oružje", INVTYPE_RANGEDRIGHT = "Dalekometno oružje", INVTYPE_CLOAK = "Leđa",
    INVTYPE_2HWEAPON = "Dvoručno oružje", INVTYPE_BAG = "Torba", INVTYPE_HOLDABLE = "Drži se u drugoj ruci",
    INVTYPE_TABARD = "Tabard", INVTYPE_SHOULDER = "Ramena", INVTYPE_TRINKET = "Ukras", INVTYPE_WAIST = "Struk",
    INVTYPE_RELIC = "Relikvija", INVTYPE_AMMO = "Streljivo", INVTYPE_THROWN = "Bacačko oružje", INVTYPE_QUIVER = "Tobolac",
    INVTYPE_NON_EQUIP = "Ne može se opremiti", INVTYPE_PROFESSION_TOOL = "Alat za zanimanje",
    INVTYPE_PROFESSION_GEAR = "Oprema za zanimanje", INVTYPE_WEAPONMAINHAND_PET = "Glavni napad",
    ALCHEMY = "Alkemija", BLACKSMITHING = "Kovanje", COOKING = "Kuhanje", ENCHANTING = "Začaravanje",
    ENGINEERING = "Inženjerstvo", FIRST_AID = "Prva pomoć", FISHING = "Ribolov", HERBALISM = "Biljarstvo",
    LEATHERWORKING = "Obrada kože", MINING = "Rudarstvo", SKINNING = "Guljenje kože", TAILORING = "Krojenje",
    DAMAGE_SCHOOL2 = "Sveta", DAMAGE_SCHOOL3 = "Vatra", DAMAGE_SCHOOL4 = "Priroda", DAMAGE_SCHOOL5 = "Mraz",
    DAMAGE_SCHOOL6 = "Sjena", DAMAGE_SCHOOL7 = "Tajanstvena", RESISTANCE0_NAME = "Oklop",
    RESISTANCE1_NAME = "Otpornost na sveto", RESISTANCE2_NAME = "Otpornost na vatru", RESISTANCE3_NAME = "Otpornost na prirodu",
    RESISTANCE4_NAME = "Otpornost na mraz", RESISTANCE5_NAME = "Otpornost na sjenu", RESISTANCE6_NAME = "Otpornost na tajanstveno",
    RESISTANCE_LABEL = "Otpornost", RESISTANCE_NONE = "Nema", RESISTANCE_POOR = "Slaba",
    RESISTANCE_FAIR = "Umjerena", RESISTANCE_GOOD = "Dobra", RESISTANCE_VERYGOOD = "Vrlo dobra",
    RESISTANCE_EXCELLENT = "Izvrsna", RESISTANCE_TEMPLATE = "%d %s",
    ITEM_REQ_ALLIANCE = "Samo Savez", ITEM_REQ_HORDE = "Samo Horda", ITEM_REQ_PURCHASE_GUILD = "Zahtijeva ceh",
    ITEM_REQ_PURCHASE_GUILD_LEVEL = "Zahtijeva razinu ceha %d", ITEM_REQ_PURCHASE_ACHIEVEMENT = "Zahtijeva postignuće: %s",
    ITEM_REQ_SPECIALIZATION = "Zahtijeva: %s", RACIAL_ABILITIES = "Rasne sposobnosti",
    PROFESSIONS_USED_IN_COOKING = "Reagens za izradu", PROFESSIONS_MODIFIED_CRAFTING_REAGENT_BASIC = "Reagens za izradu",
    PROFESSIONS_MODIFIED_CRAFTING_REAGENT_MODIFYING_REQUIRED = "Reagens za izradu",
    ITEM_COOLDOWN_TIME = "Preostalo vrijeme oporavka: %s", ITEM_COOLDOWN_TIME_DAYS = "Preostalo vrijeme oporavka: %d |4dan:dana:dana;",
    ITEM_COOLDOWN_TIME_HOURS = "Preostalo vrijeme oporavka: %d |4sat:sata:sati;",
    ITEM_COOLDOWN_TIME_MIN = "Preostalo vrijeme oporavka: %d min", ITEM_COOLDOWN_TIME_SEC = "Preostalo vrijeme oporavka: %d s",
    ITEM_COOLDOWN_TOTAL = "(%s oporavka)", ITEM_COOLDOWN_TOTAL_DAYS = "(%d |4dan:dana:dana; oporavka)",
    ITEM_COOLDOWN_TOTAL_HOURS = "(%d |4sat:sata:sati; oporavka)", ITEM_COOLDOWN_TOTAL_MIN = "(%d min oporavka)",
    ITEM_COOLDOWN_TOTAL_SEC = "(%d s oporavka)", SPELL_ON_NEXT_RANGED = "Brzina napada",
    SPELL_ON_NEXT_SWING = "Sljedeći bliski napad", SPELL_RANGE_AREA = "Područje oko bacača",
    SPELL_CAST_TIME_RANGED = "Brzina napada +%.2g s", SPELL_RECAST_TIME_CHARGES_DAYS = "%.2g dana punjenja",
    SPELL_RECAST_TIME_CHARGES_HOURS = "%.2g sati punjenja", SPELL_RECAST_TIME_CHARGES_MIN = "%.2g min punjenja",
    SPELL_RECAST_TIME_CHARGES_SEC = "%.2g s punjenja", SPELL_RECAST_TIME_CHARGES_INSTANT = "Trenutačno punjenje",
    SPELL_RECAST_TIME_CHARGEUP_DAYS = "Zahtijeva %.2g |4dan:dana:dana;", SPELL_RECAST_TIME_CHARGEUP_HOURS = "Zahtijeva %.2g |4sat:sata:sati;",
    SPELL_RECAST_TIME_CHARGEUP_MIN = "Zahtijeva %.2g min", SPELL_RECAST_TIME_CHARGEUP_SEC = "Zahtijeva %.2g s",
    SPELL_RECAST_TIME_CHARGEUP_INSTANT = "Trenutačno", ITEM_ACCOUNTBOUND = "Vezano za račun",
    ITEM_ACCOUNTBOUND_UNTIL_EQUIP = "Vezano za račun do opremanja", ITEM_BNETACCOUNTBOUND = "Vezano za račun",
}

local statNames = {
    ATTACK_POWER = "snagu napada", ARMOR_PENETRATION_RATING = "probijanje oklopa", BLOCK_RATING = "blokiranje",
    BLOCK_VALUE = "vrijednost blokiranja", CRIT_RATING = "kritični pogodak", CRIT_MELEE_RATING = "kritični bliski pogodak",
    CRIT_RANGED_RATING = "kritični dalekometni pogodak", CRIT_SPELL_RATING = "kritični pogodak čarolijom",
    DODGE_RATING = "izbjegavanje", PARRY_RATING = "pariranje", DEFENSE_SKILL_RATING = "obranu",
    EXPERTISE_RATING = "stručnost", EXTRA_ARMOR = "dodatni oklop", HASTE_RATING = "ubrzanje", HIT_RATING = "preciznost",
    HIT_MELEE_RATING = "preciznost u bliskoj borbi", HIT_RANGED_RATING = "preciznost na daljinu",
    HIT_SPELL_RATING = "preciznost čarolija", MASTERY_RATING = "majstorstvo", PVP_POWER = "PvP snagu",
    RANGED_ATTACK_POWER = "snagu dalekometnog napada", RESILIENCE_RATING = "PvP otpornost",
    SPELL_POWER = "snagu čarolija", SPELL_PENETRATION = "probijanje čarolija",
    SPELL_RESISTANCE_ALL_SCHOOLS = "otpornost na čarolije", SPELL_DAMAGE_DONE = "štetu čarolija",
    SPELL_HEALING_DONE = "liječenje čarolijama", FIRE_DAMAGE_DONE = "vatrenu štetu", FROST_DAMAGE_DONE = "štetu mraza",
    NATURE_DAMAGE_DONE = "prirodnu štetu", SHADOW_DAMAGE_DONE = "štetu sjene", HOLY_DAMAGE_DONE = "svetu štetu",
    ARCANE_DAMAGE_DONE = "tajanstvenu štetu", PHYSICAL_DAMAGE_DONE = "fizičku štetu", FIRE_PENETRATION = "probijanje vatre",
    FROST_PENETRATION = "probijanje mraza", NATURE_PENETRATION = "probijanje prirode",
    SHADOW_PENETRATION = "probijanje sjene", ARCANE_PENETRATION = "tajanstveno probijanje",
    ALCHEMY = "vještinu alkemije", BLACKSMITHING = "vještinu kovanja", COOKING = "vještinu kuhanja",
    ENCHANTING = "vještinu začaravanja", ENGINEERING = "vještinu inženjerstva", FIRST_AID = "vještinu prve pomoći",
    FISHING = "vještinu ribolova", HERBALISM = "vještinu biljarstva", LEATHERWORKING = "vještinu obrade kože",
    MINING = "vještinu rudarstva", SKINNING = "vještinu guljenja kože", TAILORING = "vještinu krojenja",
    AXES = "vještinu sjekira", BOWS = "vještinu lukova", CROSSBOWS = "vještinu samostrela", DAGGERS = "vještinu bodeža",
    GUNS = "vještinu pušaka", MACES = "vještinu buzdovana", POLEARMS = "vještinu motkastog oružja", STAVES = "vještinu štapova",
    SWORDS = "vještinu mačeva", THROWN = "vještinu bacačkog oružja", WANDS = "vještinu čarobnih štapića",
    FIST_WEAPONS = "vještinu oružja za šaku", DUAL_WIELD = "vještinu borbe s dva oružja",
    TWOHANDED_AXES = "vještinu dvoručnih sjekira", TWOHANDED_MACES = "vještinu dvoručnih buzdovana",
    TWOHANDED_SWORDS = "vještinu dvoručnih mačeva", JEWELCRAFTING = "vještinu draguljarstva",
}
for suffix, name in pairs(statNames) do
    local key = "ITEM_MOD_" .. suffix
    if Addon.englishTooltipFormats[key .. "_SHORT"] then Addon.tooltipFormatsByLocale.hrHR[key .. "_SHORT"] = name end
    local english = Addon.englishTooltipFormats[key]
    if english and english:match("^Increases .- by %%s%.$") then
        Addon.tooltipFormatsByLocale.hrHR[key] = "Povećava " .. name .. " za %s."
    elseif english and english:match("^Improves .- by %%s%.$") then
        Addon.tooltipFormatsByLocale.hrHR[key] = "Poboljšava " .. name .. " za %s."
    elseif english and english:match("^Increases .- by up to %%s%.$") then
        Addon.tooltipFormatsByLocale.hrHR[key] = "Povećava " .. name .. " za najviše %s."
    end
end

local additional = {
    ENERGY_COST_PER_TIME = "%s energije, plus %s u sekundi", ENERGY_COST_PER_TIME_NO_BASE = "%s energije u sekundi",
    MANA_COST_PER_TIME = "%s mane, plus %s u sekundi", MANA_COST_PER_TIME_NO_BASE = "%s mane u sekundi",
    MANA_COST_LARGE_PER_TIME = "%s mane, plus %s u sekundi", MANA_COST_LARGE_PER_TIME_NO_BASE = "%s mane u sekundi",
    RAGE_COST_PER_TIME = "%s bijesa, plus %s u sekundi", RAGE_COST_PER_TIME_NO_BASE = "%s bijesa u sekundi",
    RUNIC_POWER_COST = "%s runske snage", RUNIC_POWER_COST_PER_TIME = "%s runske snage, plus %s u sekundi",
    RUNIC_POWER_COST_PER_TIME_NO_BASE = "%s runske snage u sekundi", INVTYPE_NON_EQUIP_IGNORE = "",
    INVTYPE_EQUIPABLESPELL_DEFENSIVE = "Čarolija za opremanje - obrambena",
    INVTYPE_EQUIPABLESPELL_OFFENSIVE = "Čarolija za opremanje - napadačka",
    INVTYPE_EQUIPABLESPELL_UTILITY = "Čarolija za opremanje - pomoćna", INVTYPE_EQUIPABLESPELL_WEAPON = "Čarolija za opremanje - oružje",
    ITEM_MOD_AGILITY_OR_INTELLECT_SHORT = "Okretnost ili intelekt", ITEM_MOD_AGILITY_OR_STRENGTH_SHORT = "Okretnost ili snaga",
    ITEM_MOD_STRENGTH_OR_INTELLECT_SHORT = "Snaga ili intelekt",
    ITEM_MOD_AGILITY_OR_STRENGTH_OR_INTELLECT_SHORT = "Okretnost, snaga ili intelekt",
    ITEM_MOD_CORRUPTION = "Iskvarenost", ITEM_MOD_CORRUPTION_RESISTANCE = "Otpornost na iskvarenost",
    ITEM_MOD_CRAFTING_SPEED_SHORT = "Brzina izrade", ITEM_MOD_CR_AVOIDANCE_SHORT = "Izbjegavanje",
    ITEM_MOD_CR_LIFESTEAL_SHORT = "Krađa života", ITEM_MOD_CR_MULTISTRIKE_SHORT = "Višestruki udarac",
    ITEM_MOD_CR_SPEED_SHORT = "Brzina", ITEM_MOD_CR_STURDINESS_SHORT = "Neuništivo",
    ITEM_MOD_CR_UNUSED_10_SHORT = "Neiskorišteno 10", ITEM_MOD_CR_UNUSED_11_SHORT = "Neiskorišteno 11",
    ITEM_MOD_CR_UNUSED_12_SHORT = "Neiskorišteno 12", ITEM_MOD_CR_UNUSED_1_SHORT = "Višestruki udarac",
    ITEM_MOD_CR_UNUSED_3_SHORT = "Brzina", ITEM_MOD_CR_UNUSED_4_SHORT = "Krađa života",
    ITEM_MOD_CR_UNUSED_5_SHORT = "Izbjegavanje", ITEM_MOD_CR_UNUSED_6_SHORT = "Neuništivo",
    ITEM_MOD_CR_UNUSED_7_SHORT = "Neiskorišteno 7", ITEM_MOD_CR_UNUSED_9_SHORT = "Svestranost",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "šteta u sekundi", ITEM_MOD_DEFTNESS_SHORT = "Spretnost",
    ITEM_MOD_FINESSE_SHORT = "Finesa", ITEM_MOD_INGENUITY_SHORT = "Domišljatost",
    ITEM_MOD_INSPIRATION_SHORT = "Nadahnuće", ITEM_MOD_MULTICRAFT_SHORT = "Višestruka izrada",
    ITEM_MOD_PERCEPTION_SHORT = "Opažanje", ITEM_MOD_RESOURCEFULNESS_SHORT = "Snalažljivost",
    ITEM_MOD_VERSATILITY = "Svestranost", ITEM_MOD_PVP_PRIMARY_STAT_SHORT = "PvP snaga",
    ITEM_MOD_HEALTH_REGEN = "Obnavlja %s zdravlja svakih 5 s.", ITEM_MOD_HEALTH_REGENERATION = "Obnavlja %s zdravlja svakih 5 s.",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "Obnova zdravlja", ITEM_MOD_HEALTH_REGEN_SHORT = "Zdravlje svakih 5 s",
    ITEM_MOD_MANA_REGENERATION = "Obnavlja %s mane svakih 5 s.", ITEM_MOD_MANA_REGENERATION_SHORT = "Obnova mane svakih 5 s",
    ITEM_MOD_MASTERY_RATING_SPELL = "(%s)", ITEM_MOD_MASTERY_RATING_TWO_SPELLS = "(%s/%s)",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "Snaga bliskog napada", ITEM_MOD_MODIFIED_CRAFTING_STAT_1 = "Nasumična osobina 1",
    ITEM_MOD_MODIFIED_CRAFTING_STAT_2 = "Nasumična osobina 2", ITEM_MOD_POWER_REGEN0_SHORT = "Mana svakih 5 s",
    ITEM_MOD_POWER_REGEN1_SHORT = "Bijes svakih 5 s", ITEM_MOD_POWER_REGEN2_SHORT = "Fokus svakih 5 s",
    ITEM_MOD_POWER_REGEN3_SHORT = "Energija svakih 5 s", ITEM_MOD_POWER_REGEN4_SHORT = "Sreća svakih 5 s",
    ITEM_MOD_POWER_REGEN5_SHORT = "Rune svakih 5 s", ITEM_MOD_POWER_REGEN6_SHORT = "Runska snaga svakih 5 s",
    ITEM_MOD_FERAL_ATTACK_POWER = "Povećava snagu napada za %s samo u obliku mačke, medvjeda, strašnog medvjeda i mjesečeve sove.",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "Snaga napada u oblicima",
    ITEM_REQ_AMOUNT_EARNED = "Zahtijeva ukupno zarađenih %1$d\n%2$s tijekom sezone.",
    ITEM_REQ_ARENA_RATING = "Zahtijeva osobni rejting arene %d", ITEM_REQ_ARENA_RATING_3V3 = "Zahtijeva osobni rejting arene %d|nu skupini 3v3.",
    ITEM_REQ_ARENA_RATING_5V5 = "Zahtijeva osobni rejting arene %d|nu skupini 5v5",
    ITEM_REQ_ARENA_RATING_BG = "Zahtijeva rejting bojišta %d ili|nosobni rejting arene %d",
    ITEM_REQ_ARENA_RATING_3V3_BG = "Zahtijeva rejting bojišta %d ili|nosobni rejting arene %d|nu skupini 3v3.",
}
for key, value in pairs(additional) do Addon.tooltipFormatsByLocale.hrHR[key] = value end
local labels = Addon.tooltipFormatsByLocale.hrHR
local schools = { "fizičko", "sveto", "vatra", "priroda", "mraz", "sjena", "tajanstveno" }
for index = 0, 6 do
    labels["RESISTANCE_TYPE" .. index] = index == 0 and "oklop" or schools[index + 1]
    labels["SPELL_SCHOOL" .. index .. "_NAME"] = schools[index + 1]
    labels["SPELL_SCHOOL" .. index .. "_CAP"] = schools[index + 1]:gsub("^%l", string.upper)
end
local targets = { BEAST = "zvijeri", DEMON = "demona", DRAGONKIN = "zmajskih stvorenja", ELEMENTAL = "elementala",
    GIANT = "divova", HUMANOID = "humanoida", MECHANICAL = "mehaničkih stvorenja", UNDEAD = "nemrtvih" }
for key, name in pairs(targets) do
    labels["ITEM_MOD_ATTACK_POWER_VS_" .. key .. "_SHORT"] = "Snaga napada protiv " .. name
    labels["ITEM_MOD_SPELL_DAMAGE_VS_" .. key .. "_SHORT"] = "Šteta čarolija protiv " .. name
end
local avoidance = { [""] = "izbjegavanje pogodaka", MELEE_ = "izbjegavanje bliskih pogodaka",
    RANGED_ = "izbjegavanje dalekometnih pogodaka", SPELL_ = "izbjegavanje pogodaka čarolijama" }
for suffix, name in pairs(avoidance) do
    for _, prefix in ipairs({ "HIT_TAKEN_", "CRIT_TAKEN_" }) do
        local key = "ITEM_MOD_" .. prefix .. suffix .. "RATING"
        local text = prefix == "CRIT_TAKEN_" and name:gsub("pogodaka", "kritičnih pogodaka") or name
        labels[key], labels[key .. "_SHORT"] = "Poboljšava " .. text .. " za %s.", text
    end
end

Addon.itemSubclassesByLocale.hrHR = {
    [0] = { [0] = "Eksplozivi", [1] = "Napitci", [2] = "Eliksiri", [3] = "Bočice", [4] = "Svici",
        [5] = "Hrana i piće", [6] = "Trajno", [7] = "Zavoji", [8] = "Ostalo", [13] = "Napitak",
        [14] = "Naprava", [15] = "Privremeno", [-1] = "Novi predmet" },
    [1] = { [0] = "Torba", [1] = "Torba za duše", [2] = "Torba za bilje", [3] = "Torba za začaravanje",
        [4] = "Inženjerska torba", [6] = "Rudarska torba", [7] = "Kožarska torba", [9] = "Kutija za ribolovni pribor",
        [10] = "Kuharska torba", [11] = "Torba za reagense", [12] = "Torba za ukrase" },
    [2] = { [0] = "Sjekira", [1] = "Sjekira", [2] = "Luk", [3] = "Puška", [4] = "Buzdovan", [5] = "Buzdovan",
        [6] = "Motkasto oružje", [7] = "Mač", [8] = "Mač", [9] = "Ratne oštrice", [10] = "Štap", [11] = "Egzotično",
        [12] = "Egzotično", [13] = "Oružje za šaku", [14] = "Razno", [15] = "Bodež", [16] = "Bacačko oružje",
        [17] = "Koplje", [18] = "Samostrel", [19] = "Čarobni štapić", [20] = "Ribolovni štap" },
    [3] = { [0] = "Nakit (zastarjelo)" },
    [4] = { [0] = "Razno", [1] = "Tkanina", [2] = "Koža", [3] = "Verižnjača", [4] = "Pločasti oklop", [5] = "Kozmetički",
        [6] = "Štit", [7] = "Libram", [8] = "Idol", [9] = "Totem" },
    [5] = { [0] = "Reagens" }, [6] = { [0] = "Čarobni štapić (zastarjelo)", [1] = "Strijela samostrela (zastarjelo)",
        [2] = "Strijela", [3] = "Metak", [4] = "Bacačko oružje (zastarjelo)" },
    [7] = { [0] = "Trgovačka roba (zastarjelo)", [1] = "Dijelovi", [2] = "Eksplozivi (zastarjelo)",
        [3] = "Naprave (zastarjelo)", [5] = "Tkanina", [6] = "Koža", [7] = "Metal i kamen", [8] = "Kuhanje",
        [9] = "Biljka", [10] = "Elementarno", [11] = "Ostalo", [12] = "Začaravanje" },
    [8] = { [0] = "Općenito (zastarjelo)" }, [9] = { [0] = "Knjiga", [1] = "Obrada kože", [2] = "Krojenje",
        [3] = "Inženjerstvo", [4] = "Kovanje", [5] = "Kuhanje", [6] = "Alkemija", [7] = "Prva pomoć",
        [8] = "Začaravanje", [9] = "Ribolov" }, [10] = { [0] = "Novac (zastarjelo)" },
    [11] = { [0] = "Tobolac (zastarjelo)", [1] = "Tobolac (zastarjelo)", [2] = "Tobolac", [3] = "Torba za streljivo" },
    [12] = { [0] = "Zadatak" }, [13] = { [0] = "Ključ", [1] = "Alat za obijanje" }, [14] = { [0] = "Trajno" },
    [15] = { [0] = "Smeće", [1] = "Reagens", [2] = "Ljubimac", [3] = "Blagdan", [4] = "Ostalo", [5] = "Jahaća životinja" },
}
