local _, Addon = ...

Addon.tooltipLocaleReplacements = Addon.tooltipLocaleReplacements or {}
Addon.tooltipLocaleReplacements.itIT = true

-- AI-authored translations; linguistic review is pending.
Addon.tooltipFormatsByLocale.itIT = {
    SPELL_TOTEMS = "Strumenti: ",
    ALCHEMY = "Alchimia", BLACKSMITHING = "Forgiatura", COOKING = "Cucina", ENCHANTING = "Incantamento",
    ENGINEERING = "Ingegneria", FIRST_AID = "Primo soccorso", FISHING = "Pesca", HERBALISM = "Erbalismo",
    LEATHERWORKING = "Conciatura", MINING = "Estrazione", SKINNING = "Scuoiatura", TAILORING = "Sartoria",
    AMMO_DAMAGE_TEMPLATE = "Aggiunge %s danni al secondo", ARMOR_TEMPLATE = "Armatura: %s",
    CONTAINER_SLOTS = "%d scomparti: %s", COOLDOWN_REMAINING = "Tempo di recupero rimanente:",
    DAMAGE_PER_SECOND = "Danni al secondo", DAMAGE_SCHOOL2 = "Sacro", DAMAGE_SCHOOL3 = "Fuoco",
    DAMAGE_SCHOOL4 = "Natura", DAMAGE_SCHOOL5 = "Gelo", DAMAGE_SCHOOL6 = "Ombra", DAMAGE_SCHOOL7 = "Arcano",
    DAMAGE_TEMPLATE = "Danni: %s–%s", DAMAGE_TEMPLATE_WITH_SCHOOL = "Danni: %s–%s (%s)",
    DPS_TEMPLATE = "(%s danni al secondo)", DURABILITY_TEMPLATE = "Integrità %d / %d",
    ENERGY_COST = "Energia: %s", ENERGY_COST_PER_TIME = "Energia: %s, più %s al secondo",
    ENERGY_COST_PER_TIME_NO_BASE = "Energia: %s al secondo",
    INVTYPE_2HWEAPON = "Due mani", INVTYPE_AMMO = "Munizioni", INVTYPE_BAG = "Borsa", INVTYPE_BODY = "Camicia",
    INVTYPE_CHEST = "Torso", INVTYPE_CLOAK = "Schiena", INVTYPE_FEET = "Piedi", INVTYPE_FINGER = "Dito",
    INVTYPE_HAND = "Mani", INVTYPE_HEAD = "Testa", INVTYPE_HOLDABLE = "Mano secondaria", INVTYPE_LEGS = "Gambe",
    INVTYPE_NECK = "Collo", INVTYPE_NON_EQUIP = "Non equipaggiabile", INVTYPE_NON_EQUIP_IGNORE = "",
    INVTYPE_PROFESSION_GEAR = "Equipaggiamento professionale", INVTYPE_PROFESSION_TOOL = "Strumento professionale",
    INVTYPE_QUIVER = "Faretra", INVTYPE_RANGED = "A distanza", INVTYPE_RANGEDRIGHT = "A distanza",
    INVTYPE_RELIC = "Reliquia", INVTYPE_ROBE = "Torso", INVTYPE_SHIELD = "Mano secondaria",
    INVTYPE_SHOULDER = "Spalle", INVTYPE_TABARD = "Tabarda", INVTYPE_THROWN = "Da lancio",
    INVTYPE_TRINKET = "Monile", INVTYPE_WAIST = "Vita", INVTYPE_WEAPON = "Una mano",
    INVTYPE_WEAPONMAINHAND = "Mano primaria", INVTYPE_WEAPONMAINHAND_PET = "Attacco principale",
    INVTYPE_WEAPONOFFHAND = "Mano secondaria", INVTYPE_WRIST = "Polsi",
    ITEM_BIND_ON_EQUIP = "Si vincola quando equipaggiato", ITEM_BIND_ON_PICKUP = "Si vincola quando raccolto",
    ITEM_BIND_ON_USE = "Si vincola quando usato", ITEM_BIND_QUEST = "Oggetto di missione",
    ITEM_BIND_TO_ACCOUNT = "Si vincola all'account", ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP = "Vincolato all'account fino all'equipaggiamento",
    ITEM_BIND_TO_BNETACCOUNT = "Si vincola all'account", ITEM_CLASSES_ALLOWED = "Classi: %s",
    ITEM_COOLDOWN_TIME = "Tempo di recupero rimanente: %s", ITEM_COOLDOWN_TIME_MIN = "Tempo di recupero rimanente: %d min",
    ITEM_COOLDOWN_TIME_SEC = "Tempo di recupero rimanente: %d s", ITEM_COOLDOWN_TOTAL = "(Recupero: %s)",
    ITEM_COOLDOWN_TOTAL_MIN = "(Recupero: %d min)", ITEM_COOLDOWN_TOTAL_SEC = "(Recupero: %d s)",
    ITEM_MIN_LEVEL = "Richiede livello %d", ITEM_MIN_SKILL = "Richiede %s (%d)",
    ITEM_SET_BONUS = "Completo: %s", ITEM_SET_BONUS_GRAY = "(%d) Completo: %s", ITEM_SET_NAME = "%s (%d/%d)",
    ITEM_SOULBOUND = "Vincolato all'anima", ITEM_SPELL_CHARGES_NONE = "Nessuna carica", ITEM_SPELL_EFFECT = "Effetto: %s",
    ITEM_SPELL_KNOWN = "Già conosciuto", ITEM_SPELL_TRIGGER_ONEQUIP = "Equipaggiamento:",
    ITEM_SPELL_TRIGGER_ONPROC = "Probabilità al colpo:", ITEM_SPELL_TRIGGER_ONUSE = "Uso:",
    ITEM_UNIQUE = "Unico", ITEM_UNIQUE_EQUIPPABLE = "Unico equipaggiabile", ITEM_UNIQUE_MULTIPLE = "Unico (%d)",
    MANA_COST = "Mana: %s", MANA_COST_LARGE = "Mana: %s", MELEE_RANGE = "Portata da mischia",
    RANK = "Grado", SPEED = "Velocità", SPELL_PASSIVE = "Passivo", SPELL_PASSIVE_EFFECT = "Passivo",
    SPELL_PASSIVE_SECOND = "Passivo", SPELL_CAST_CHANNELED = "Canalizzato", SPELL_CAST_TIME_INSTANT = "Istantaneo",
    SPELL_CAST_TIME_INSTANT_NO_MANA = "Istantaneo", SPELL_RANGE = "Portata: %s yd",
    SPELL_RANGE_UNLIMITED = "Portata illimitata", SPELL_REAGENTS = "Reagenti: |n",
    TALENT_BUTTON_TOOLTIP_RANK_FORMAT = "Grado %s/%s", TALENT_BUTTON_TOOLTIP_RANK_NO_MAX_FORMAT = "Grado %s",
    TOOLTIP_TALENT_RANK = "Grado %d/%d", TOOLTIP_TALENT_RANK_CURRENT_ONLY = "Grado %d", WEAPON_SPEED = "Velocità d'attacco",
    ITEM_REQ_ALLIANCE = "Solo Alleanza", ITEM_REQ_HORDE = "Solo Orda",
    ITEM_REQ_PURCHASE_ACHIEVEMENT = "Richiede impresa: %s", ITEM_REQ_PURCHASE_GUILD = "Richiede una gilda",
    ITEM_REQ_PURCHASE_GUILD_LEVEL = "Richiede livello di gilda %d", ITEM_REQ_REPUTATION = "Richiede %s – %s",
    ITEM_REQ_SKILL = "Richiede %s", ITEM_REQ_SPECIALIZATION = "Richiede: %s",
    ITEM_REQ_ARENA_RATING = "Richiede indice personale in arena %d", ITEM_SPELL_MAX_USABLE_LEVEL = " (Richiede livello %d o inferiore)",
    PLUS_DAMAGE_TEMPLATE = "+ %s–%s danni", PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s–%s danni (%s)",
    PLUS_SINGLE_DAMAGE_TEMPLATE = "+ %s danni", PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s danni (%s)",
    PROFESSIONS_MODIFIED_CRAFTING_REAGENT_BASIC = "Reagente di creazione",
    PROFESSIONS_MODIFIED_CRAFTING_REAGENT_MODIFYING_REQUIRED = "Reagente di creazione",
    PROFESSIONS_USED_IN_COOKING = "Reagente di creazione", RACIAL_ABILITIES = "Abilità razziali",
    QUEST_TOOLTIP_ACTIVE = "Hai già questa missione", QUEST_TOOLTIP_REQUIREMENTS = "Requisiti:",
    RAGE_COST = "Rabbia: %s", RAGE_COST_PER_TIME = "Rabbia: %s, più %s al secondo",
    RAGE_COST_PER_TIME_NO_BASE = "Rabbia: %s al secondo", RESISTANCE0_NAME = "Armatura",
    RESISTANCE1_NAME = "Resistenza al sacro", RESISTANCE2_NAME = "Resistenza al fuoco",
    RESISTANCE3_NAME = "Resistenza alla natura", RESISTANCE4_NAME = "Resistenza al gelo",
    RESISTANCE5_NAME = "Resistenza all'ombra", RESISTANCE6_NAME = "Resistenza all'arcano",
    RESISTANCE_EXCELLENT = "Eccellente", RESISTANCE_FAIR = "Discreta", RESISTANCE_GOOD = "Buona",
    RESISTANCE_LABEL = "Resistenza", RESISTANCE_NONE = "Nessuna", RESISTANCE_POOR = "Scarsa",
    RESISTANCE_TEMPLATE = "%d %s", RESISTANCE_VERYGOOD = "Molto buona", RESISTANCE_TYPE0 = "armatura",
    RESISTANCE_TYPE1 = "sacro", RESISTANCE_TYPE2 = "fuoco", RESISTANCE_TYPE3 = "natura",
    RESISTANCE_TYPE4 = "gelo", RESISTANCE_TYPE5 = "ombra", RESISTANCE_TYPE6 = "arcano",
    SHIELD_BLOCK_TEMPLATE = "Blocco: %s", SINGLE_DAMAGE_TEMPLATE = "Danni: %s",
    SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "Danni: %s (%s)", SPELL_RANGE_AREA = "Area attorno all'incantatore",
    SPELL_RANGE_DUAL = "%1$s: portata %2$s yd", SPELL_ON_NEXT_RANGED = "Velocità d'attacco",
    SPELL_ON_NEXT_SWING = "Prossimo attacco in mischia", SPELL_CAST_TIME_MIN = "Lancio: %.2g min",
    SPELL_CAST_TIME_SEC = "Lancio: %.2g s", SPELL_CAST_TIME_RANGED = "Velocità d'attacco +%.2g s",
    SELL_PRICE = "Prezzo di vendita", SPELL_DURATION_UNTIL_CANCELLED = "fino all'annullamento",
    ITEM_ACCOUNTBOUND = "Vincolato all'account", ITEM_BNETACCOUNTBOUND = "Vincolato all'account",
    ITEM_ACCOUNTBOUND_UNTIL_EQUIP = "Vincolato all'account fino all'equipaggiamento",
    INVTYPE_EQUIPABLESPELL_DEFENSIVE = "Incantesimo equipaggiabile – difensivo",
    INVTYPE_EQUIPABLESPELL_OFFENSIVE = "Incantesimo equipaggiabile – offensivo",
    INVTYPE_EQUIPABLESPELL_UTILITY = "Incantesimo equipaggiabile – utilità",
    INVTYPE_EQUIPABLESPELL_WEAPON = "Incantesimo equipaggiabile – arma",
    ITEM_MOD_AGILITY_OR_INTELLECT_SHORT = "Agilità o intelletto", ITEM_MOD_AGILITY_OR_STRENGTH_SHORT = "Agilità o forza",
    ITEM_MOD_AGILITY_OR_STRENGTH_OR_INTELLECT_SHORT = "Agilità, forza o intelletto", ITEM_MOD_STRENGTH_OR_INTELLECT_SHORT = "Forza o intelletto",
    ITEM_MOD_CORRUPTION = "Corruzione", ITEM_MOD_CORRUPTION_RESISTANCE = "Resistenza alla corruzione",
    ITEM_MOD_CRAFTING_SPEED_SHORT = "Velocità di creazione", ITEM_MOD_CR_AVOIDANCE_SHORT = "Elusione",
    ITEM_MOD_CR_LIFESTEAL_SHORT = "Assorbimento vitale", ITEM_MOD_CR_MULTISTRIKE_SHORT = "Colpo multiplo",
    ITEM_MOD_CR_SPEED_SHORT = "Velocità", ITEM_MOD_CR_STURDINESS_SHORT = "Indistruttibile",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "danni al secondo", ITEM_MOD_DEFENSE_SKILL_RATING = "Aumenta la difesa di %s.",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Difesa", ITEM_MOD_EXTRA_ARMOR = "Aumenta l'armatura di %s.",
    ITEM_MOD_EXTRA_ARMOR_SHORT = "Armatura bonus", ITEM_MOD_HEALTH_REGEN = "Ripristina %s salute ogni 5 s.",
    ITEM_MOD_HEALTH_REGENERATION = "Ripristina %s salute ogni 5 s.", ITEM_MOD_HEALTH_REGENERATION_SHORT = "Rigenerazione salute",
    ITEM_MOD_HEALTH_REGEN_SHORT = "Salute ogni 5 s", ITEM_MOD_MANA_REGENERATION = "Ripristina %s mana ogni 5 s.",
    ITEM_MOD_MANA_REGENERATION_SHORT = "Rigenerazione mana ogni 5 s", ITEM_MOD_MASTERY_RATING_SPELL = "(%s)",
    ITEM_MOD_MASTERY_RATING_TWO_SPELLS = "(%s/%s)", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "Potenza d'attacco in mischia",
    ITEM_MOD_PVP_PRIMARY_STAT_SHORT = "Potenza PvP", ITEM_MOD_MODIFIED_CRAFTING_STAT_1 = "Statistica casuale 1",
    ITEM_MOD_MODIFIED_CRAFTING_STAT_2 = "Statistica casuale 2", ITEM_MOD_MULTICRAFT_SHORT = "Creazione multipla",
    ITEM_MOD_PERCEPTION_SHORT = "Percezione", ITEM_MOD_RESOURCEFULNESS_SHORT = "Intraprendenza", ITEM_MOD_VERSATILITY = "Versatilità",
    ITEM_MOD_SPELL_DAMAGE_DONE = "Aumenta i danni inflitti da incantesimi ed effetti magici fino a %s.",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Danni magici", ITEM_MOD_SPELL_HEALING_DONE = "Aumenta le cure di incantesimi ed effetti magici fino a %s.",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Cure magiche",
    DAYS_ABBR = "%d |4giorno:giorni;", DAY_ONELETTER_ABBR = "%d g", HOURS_ABBR = "%d |4ora:ore;",
    HOUR_ONELETTER_ABBR = "%d h", MINUTES_ABBR = "%d |4min:min;", MINUTE_ONELETTER_ABBR = "%d min",
    SECONDS_ABBR = "%d |4s:s;", SECOND_ONELETTER_ABBR = "%d s",
    ITEM_COOLDOWN_TIME_DAYS = "Tempo di recupero rimanente: %d |4giorno:giorni;",
    ITEM_COOLDOWN_TIME_HOURS = "Tempo di recupero rimanente: %d |4ora:ore;",
    ITEM_COOLDOWN_TOTAL_DAYS = "(Recupero: %d |4giorno:giorni;)", ITEM_COOLDOWN_TOTAL_HOURS = "(Recupero: %d |4ora:ore;)",
    ITEM_SPELL_CHARGES = "%d |4carica:cariche;", MANA_COST_LARGE_PER_TIME = "Mana: %s, più %s al secondo",
    MANA_COST_LARGE_PER_TIME_NO_BASE = "Mana: %s al secondo", MANA_COST_PER_TIME = "Mana: %s, più %s al secondo",
    MANA_COST_PER_TIME_NO_BASE = "Mana: %s al secondo", RUNIC_POWER_COST = "Potenza runica: %s",
    RUNIC_POWER_COST_PER_TIME = "Potenza runica: %s, più %s al secondo", RUNIC_POWER_COST_PER_TIME_NO_BASE = "Potenza runica: %s al secondo",
    SPELL_RECAST_TIME_CHARGES_DAYS = "Ricarica: %.2g g", SPELL_RECAST_TIME_CHARGES_HOURS = "Ricarica: %.2g h",
    SPELL_RECAST_TIME_CHARGES_INSTANT = "Ricarica istantanea", SPELL_RECAST_TIME_CHARGES_MIN = "Ricarica: %.2g min",
    SPELL_RECAST_TIME_CHARGES_SEC = "Ricarica: %.2g s", SPELL_RECAST_TIME_CHARGEUP_DAYS = "Richiede %.2g |4giorno:giorni;",
    SPELL_RECAST_TIME_CHARGEUP_HOURS = "Richiede %.2g |4ora:ore;", SPELL_RECAST_TIME_CHARGEUP_INSTANT = "Istantaneo",
    SPELL_RECAST_TIME_CHARGEUP_MIN = "Richiede %.2g min", SPELL_RECAST_TIME_CHARGEUP_SEC = "Richiede %.2g s",
    SPELL_RECAST_TIME_DAYS = "Recupero: %.2g g", SPELL_RECAST_TIME_HOURS = "Recupero: %.2g h",
    SPELL_RECAST_TIME_INSTANT = "Recupero istantaneo", SPELL_RECAST_TIME_MIN = "Recupero: %.2g min",
    SPELL_RECAST_TIME_SEC = "Recupero: %.2g s", ITEM_MOD_DEFTNESS_SHORT = "Destrezza", ITEM_MOD_FINESSE_SHORT = "Finezza",
    ITEM_MOD_INGENUITY_SHORT = "Ingegno", ITEM_MOD_INSPIRATION_SHORT = "Ispirazione",
    ITEM_MOD_FERAL_ATTACK_POWER = "Aumenta la potenza d'attacco di %s solo nelle forme di gatto, orso, orso feroce e lunagufo.",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "Potenza d'attacco nelle forme",
    ITEM_MOD_CR_UNUSED_1_SHORT = "Colpo multiplo", ITEM_MOD_CR_UNUSED_3_SHORT = "Velocità",
    ITEM_MOD_CR_UNUSED_4_SHORT = "Assorbimento vitale", ITEM_MOD_CR_UNUSED_5_SHORT = "Elusione",
    ITEM_MOD_CR_UNUSED_6_SHORT = "Indistruttibile", ITEM_MOD_CR_UNUSED_7_SHORT = "Non utilizzato 7",
    ITEM_MOD_CR_UNUSED_9_SHORT = "Versatilità", ITEM_MOD_CR_UNUSED_10_SHORT = "Non utilizzato 10",
    ITEM_MOD_CR_UNUSED_11_SHORT = "Non utilizzato 11", ITEM_MOD_CR_UNUSED_12_SHORT = "Non utilizzato 12",
    ITEM_REQ_AMOUNT_EARNED = "Richiede di ottenere un totale di %1$d\n%2$s nella stagione.",
    ITEM_REQ_ARENA_RATING_3V3 = "Richiede indice personale in arena %d|nnella categoria 3v3.",
    ITEM_REQ_ARENA_RATING_3V3_BG = "Richiede indice nei campi di battaglia %d o|nindice personale in arena %d|nnella categoria 3v3.",
    ITEM_REQ_ARENA_RATING_5V5 = "Richiede indice personale in arena %d|nnella categoria 5v5",
    ITEM_REQ_ARENA_RATING_BG = "Richiede indice nei campi di battaglia %d o|nindice personale in arena %d",
}

local skills = {
    ALCHEMY = "alchimia", AXES = "asce", BLACKSMITHING = "forgiatura", BOWS = "archi", COOKING = "cucina",
    CROSSBOWS = "balestre", DAGGERS = "pugnali", DUAL_WIELD = "combattimento con due armi",
    ENCHANTING = "incantamento", ENGINEERING = "ingegneria", FIRST_AID = "primo soccorso", FISHING = "pesca",
    FIST_WEAPONS = "armi da pugno", GUNS = "armi da fuoco", HERBALISM = "erbalismo", JEWELCRAFTING = "oreficeria",
    LEATHERWORKING = "conciatura", MACES = "mazze", MINING = "estrazione", POLEARMS = "armi inastate",
    SKINNING = "scuoiatura", STAVES = "bastoni", SWORDS = "spade", TAILORING = "sartoria", THROWN = "armi da lancio",
    TWOHANDED_AXES = "asce a due mani", TWOHANDED_MACES = "mazze a due mani", TWOHANDED_SWORDS = "spade a due mani",
    WANDS = "bacchette",
}
for key, name in pairs(skills) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key] = "Aumenta l'abilità di " .. name .. " di %s."
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_SHORT"] = "Abilità: " .. name
end

local stats = {
    ATTACK_POWER = "potenza d'attacco", BLOCK_RATING = "blocco con scudo", BLOCK_VALUE = "valore di blocco dello scudo",
    CRIT_RATING = "probabilità di critico", DODGE_RATING = "schivata", EXPERTISE_RATING = "maestria nelle armi",
    HASTE_RATING = "celerità", HIT_RATING = "probabilità di colpire", MASTERY_RATING = "maestria", PARRY_RATING = "parata",
    SPELL_POWER = "potenza magica", SPELL_PENETRATION = "penetrazione magica", ARMOR_PENETRATION_RATING = "penetrazione armatura",
    RANGED_ATTACK_POWER = "potenza d'attacco a distanza", RESILIENCE_RATING = "resilienza PvP", PVP_POWER = "potenza PvP",
    SPELL_RESISTANCE_ALL_SCHOOLS = "resistenza magica",
}
for key, name in pairs(stats) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key] = "Aumenta " .. name .. " di %s."
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_SHORT"] = name
end
local attributes = {AGILITY = "Agilità", HEALTH = "Salute", INTELLECT = "Intelletto", MANA = "Mana",
    SPIRIT = "Spirito", STAMINA = "Tempra", STRENGTH = "Forza"}
for key, name in pairs(attributes) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key] = "%c%s " .. name
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_SHORT"] = name
end
local damageTypes = {ARCANE = "arcani", FIRE = "da fuoco", FROST = "da gelo", HOLY = "sacri",
    NATURE = "da natura", PHYSICAL = "fisici", SHADOW = "da ombra"}
for key, name in pairs(damageTypes) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_DAMAGE_DONE"] = "Aumenta i danni " .. name .. " inflitti fino a %s."
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_DAMAGE_DONE_SHORT"] = "Danni " .. name
end
local piercing = {ARCANE = "arcana", FIRE = "del fuoco", FROST = "del gelo", NATURE = "della natura", SHADOW = "dell'ombra"}
for key, name in pairs(piercing) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_PENETRATION"] = "Aumenta la penetrazione " .. name .. " di %s."
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_PENETRATION_SHORT"] = "Penetrazione " .. name
end
local combatStats = {
    CRIT_MELEE_RATING = "critico in mischia", CRIT_RANGED_RATING = "critico a distanza", CRIT_SPELL_RATING = "critico magico",
    CRIT_TAKEN_RATING = "evitamento dei critici", CRIT_TAKEN_MELEE_RATING = "evitamento dei critici in mischia",
    CRIT_TAKEN_RANGED_RATING = "evitamento dei critici a distanza", CRIT_TAKEN_SPELL_RATING = "evitamento dei critici magici",
    HIT_MELEE_RATING = "colpo in mischia", HIT_RANGED_RATING = "colpo a distanza", HIT_SPELL_RATING = "colpo magico",
    HIT_TAKEN_RATING = "evitamento dei colpi", HIT_TAKEN_MELEE_RATING = "evitamento dei colpi in mischia",
    HIT_TAKEN_RANGED_RATING = "evitamento dei colpi a distanza", HIT_TAKEN_SPELL_RATING = "evitamento dei colpi magici",
}
for key, name in pairs(combatStats) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key] = "Migliora " .. name .. " di %s."
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_" .. key .. "_SHORT"] = name
end
local enemies = {BEAST = "bestie", DEMON = "demoni", DRAGONKIN = "draghi", ELEMENTAL = "elementali",
    GIANT = "giganti", HUMANOID = "umanoidi", MECHANICAL = "esseri meccanici", UNDEAD = "non morti"}
for key, name in pairs(enemies) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_ATTACK_POWER_VS_" .. key .. "_SHORT"] = "Potenza d'attacco contro " .. name
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_SPELL_DAMAGE_VS_" .. key .. "_SHORT"] = "Danni magici contro " .. name
end
local schools = {{"fisico", "Fisico"}, {"sacro", "Sacro"}, {"fuoco", "Fuoco"}, {"natura", "Natura"},
    {"gelo", "Gelo"}, {"ombra", "Ombra"}, {"arcano", "Arcano"}}
for index, names in ipairs(schools) do
    Addon.tooltipFormatsByLocale.itIT["SPELL_SCHOOL" .. (index - 1) .. "_NAME"] = names[1]
    Addon.tooltipFormatsByLocale.itIT["SPELL_SCHOOL" .. (index - 1) .. "_CAP"] = names[2]
end
local resources = {"Mana", "Rabbia", "Concentrazione", "Energia", "Felicità", "Rune", "Potenza runica"}
for index, name in ipairs(resources) do
    Addon.tooltipFormatsByLocale.itIT["ITEM_MOD_POWER_REGEN" .. (index - 1) .. "_SHORT"] = name .. " ogni 5 s"
end

local subclassNames = {
    Alchemy = "Alchimia", Arrow = "Freccia", Axe = "Ascia", Bag = "Borsa", Bandages = "Bende",
    Blacksmithing = "Forgiatura", Book = "Libro", Bow = "Arco", Bullet = "Proiettile", Cloth = "Stoffa",
    Cooking = "Cucina", Crossbow = "Balestra", Dagger = "Pugnale", Device = "Dispositivo",
    Elemental = "Elementale", Elixirs = "Elisir", Enchanting = "Incantamento", Engineering = "Ingegneria",
    Explosives = "Esplosivi", Fishing = "Pesca", Flasks = "Fiasche", Gun = "Fucile", Herb = "Erba",
    Idol = "Idolo", Junk = "Cianfrusaglie", Key = "Chiave", Leather = "Cuoio", Leatherworking = "Conciatura",
    Libram = "Libram", Lockpick = "Grimaldello", Mace = "Mazza", Mail = "Maglia", Miscellaneous = "Varie",
    Mount = "Cavalcatura", Other = "Altro", Parts = "Componenti", Permanent = "Permanente", Pet = "Mascotte",
    Plate = "Piastre", Polearm = "Arma inastata", Potions = "Pozioni", Quest = "Missione", Quiver = "Faretra",
    Reagent = "Reagente", Scrolls = "Pergamene", Shield = "Scudo", Spear = "Lancia", Staff = "Bastone",
    Sword = "Spada", Tailoring = "Sartoria", Temporary = "Temporaneo", Thrown = "Da lancio", Totem = "Totem",
    Wand = "Bacchetta", ["Ammo Pouch"] = "Portamunizioni", ["Cooking Bag"] = "Borsa da cucina",
    ["Enchanting Bag"] = "Borsa da incantatore", ["Engineering Bag"] = "Borsa da ingegnere",
    ["Herb Bag"] = "Borsa per erbe", ["Leatherworking Bag"] = "Borsa da conciatore", ["Mining Bag"] = "Borsa da minatore",
    ["Reagent Bag"] = "Borsa per reagenti", ["Soul Bag"] = "Borsa delle anime", ["Tackle Box"] = "Cassetta da pesca",
    ["Trinket Bag"] = "Borsa per monili", ["Food & Drink"] = "Cibo e bevande", ["First Aid"] = "Primo soccorso",
    ["Fishing Pole"] = "Canna da pesca", ["Fist Weapon"] = "Arma da pugno", ["Metal & Stone"] = "Metallo e pietra",
    Cosmetic = "Cosmetico", Draught = "Bevanda", Exotic = "Esotico", Holiday = "Festivo", NewItem = "Nuovo oggetto",
    Warglaives = "Lame da guerra", ["Bolt(OBSOLETE)"] = "Dardo (obsoleto)", ["Devices (OBSOLETE)"] = "Dispositivi (obsoleto)",
    ["Explosives (OBSOLETE)"] = "Esplosivi (obsoleto)", ["Generic(OBSOLETE)"] = "Generico (obsoleto)",
    ["Jewelry(OBSOLETE)"] = "Gioielli (obsoleto)", ["Money(OBSOLETE)"] = "Denaro (obsoleto)",
    ["Quiver(OBSOLETE)"] = "Faretra (obsoleto)", ["Thrown(OBSOLETE)"] = "Da lancio (obsoleto)",
    ["Trade Goods (OBSOLETE)"] = "Merci (obsoleto)", ["Wand(OBSOLETE)"] = "Bacchetta (obsoleto)",
}
local subclasses = {}
for classID, entries in pairs(Addon.itemSubclassesByLocale.enUS) do
    for subclassID, english in pairs(entries) do
        local translated = subclassNames[english]
        if translated then
            subclasses[classID] = subclasses[classID] or {}
            subclasses[classID][subclassID] = translated
        end
    end
end
Addon.itemSubclassesByLocale.itIT = subclasses
