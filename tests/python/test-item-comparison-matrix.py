"""Check comparison delta labels across native and target locales."""

import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

FIXTURE = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())
KEYS = (['DAMAGE_PER_SECOND'] + [f'RESISTANCE{index}_NAME' for index in range(1, 7)]
        + ['ITEM_MOD_DAMAGE_PER_SECOND_SHORT'])
CUSTOM_LABELS = {
    'csCZ': 'Poškození za sekundu|Odolnost vůči svatému|Odolnost vůči ohni|Odolnost vůči přírodě|Odolnost vůči mrazu|Odolnost vůči stínu|Odolnost vůči arkáně',
    'daDK': 'Skade pr. sekund|Hellig modstand|Ildmodstand|Naturmodstand|Frostmodstand|Skyggemodstand|Arkan modstand',
    'hrHR': 'Šteta u sekundi|Otpornost na sveto|Otpornost na vatru|Otpornost na prirodu|Otpornost na mraz|Otpornost na sjenu|Otpornost na tajanstveno',
    'itIT': "Danni al secondo|Resistenza al sacro|Resistenza al fuoco|Resistenza alla natura|Resistenza al gelo|Resistenza all'ombra|Resistenza all'arcano",
    'plPL': 'Obrażenia na sekundę|Odporność na świętość|Odporność na ogień|Odporność na naturę|Odporność na mróz|Odporność na cień|Odporność na Arkana',
    'svSE': 'Skada per sekund|Heligt motstånd|Eldmotstånd|Naturmotstånd|Frostmotstånd|Skuggmotstånd|Arkant motstånd',
    'trTR': 'Saniye Başına Hasar|Kutsal Direnci|Ateş Direnci|Doğa Direnci|Don Direnci|Gölge Direnci|Gizem Direnci',
    'ukUA': 'Шкода за секунду|Опір світлу|Опір вогню|Опір природі|Опір кризі|Опір тіні|Опір тайній магії',
}
SHORT_DPS = {
    'csCZ': 'poškození za sekundu', 'daDK': 'skade pr. sekund', 'hrHR': 'šteta u sekundi',
    'itIT': 'danni al secondo', 'plPL': 'obrażeń na sekundę', 'svSE': 'skada per sekund',
    'trTR': 'saniye başına hasar', 'ukUA': 'шкода за секунду',
}
STAT_KEYS = ['ARMOR', 'ITEM_MOD_STRENGTH_SHORT', 'ITEM_MOD_AGILITY_SHORT', 'ITEM_MOD_STAMINA_SHORT',
             'ITEM_MOD_INTELLECT_SHORT', 'ITEM_MOD_SPIRIT_SHORT', 'HEALTH', 'MANA',
             'ITEM_MOD_ATTACK_POWER_SHORT', 'ITEM_MOD_SPELL_POWER_SHORT', 'ITEM_MOD_CRIT_RATING_SHORT',
             'ITEM_MOD_HASTE_RATING_SHORT', 'ITEM_MOD_HIT_RATING_SHORT', 'ITEM_MOD_DODGE_RATING_SHORT',
             'ITEM_MOD_PARRY_RATING_SHORT', 'ITEM_MOD_BLOCK_RATING_SHORT', 'DEFENSE']
STAT_LABELS = {
    'enUS': 'Armor|Strength|Agility|Stamina|Intellect|Spirit|Health|Mana|Attack Power|Spell Power|Critical Strike|Haste|Hit|Dodge|Parry|Block|Defense',
    'frFR': 'Armure|Force|Agilité|Endurance|Intelligence|Esprit|Vie|Mana|Puissance d’attaque|Puissance des sorts|Coup critique|Hâte|Toucher|Esquive|Parade|Blocage|Défense',
    'deDE': 'Rüstung|Stärke|Beweglichkeit|Ausdauer|Intelligenz|Willenskraft|Gesundheit|Mana|Angriffskraft|Zaubermacht|Kritischer Trefferwert|Tempo|Trefferwert|Ausweichen|Parieren|Blocken|Verteidigung',
    'esES': 'Armadura|Fuerza|Agilidad|Aguante|Intelecto|Espíritu|Salud|Maná|Poder de ataque|Poder con hechizos|Golpe crítico|Celeridad|Golpe|Esquivar|Parar|Bloquear|Defensa',
    'itIT': "Armatura|Forza|Agilità|Tempra|Intelletto|Spirito|Salute|Mana|Potenza d'attacco|Potenza magica|Colpo critico|Celerità|Impatto|Schivata|Parata|Blocco|Difesa",
    'ptBR': 'Armadura|Força|Agilidade|Vigor|Intelecto|Espírito|Vida|Mana|Poder de Ataque|Poder Mágico|Acerto Crítico|Aceleração|Acerto|Esquiva|Aparo|Bloqueio|Defesa',
    'ruRU': 'Броня|Сила|Ловкость|Выносливость|Интеллект|Дух|Здоровье|Мана|Сила атаки|Сила заклинаний|Критический удар|Скорость|Меткость|Уклонение|Парирование|Блокирование|Защита',
    'ukUA': 'Броня|Сила|Спритність|Витривалість|Інтелект|Дух|Здоров’я|Мана|Сила атаки|Сила заклять|Критичний удар|Швидкість|Влучність|Ухилення|Парирування|Блокування|Захист',
    'plPL': 'Pancerz|Siła|Zręczność|Wytrzymałość|Intelekt|Duch|Zdrowie|Mana|Siła ataku|Moc zaklęć|Trafienie krytyczne|Pośpiech|Trafienie|Unik|Parowanie|Blok|Obrona',
    'csCZ': 'Zbroj|Síla|Obratnost|Výdrž|Intelekt|Duch|Zdraví|Mana|Síla útoku|Síla kouzel|Kritický zásah|Zrychlení|Zásah|Úhyb|Odražení|Blokování|Obrana',
    'daDK': 'Rustning|Styrke|Smidighed|Udholdenhed|Intellekt|Ånd|Helbred|Mana|Angrebskraft|Tryllekraft|Kritisk træffer|Hastighed|Træffer|Undvigelse|Parering|Blokering|Forsvar',
    'svSE': 'Rustning|Styrka|Smidighet|Uthållighet|Intellekt|Ande|Hälsa|Mana|Attackkraft|Trollformelskraft|Kritisk träff|Snabbhet|Träff|Undvikande|Parering|Blockering|Försvar',
    'hrHR': 'Oklop|Snaga|Okretnost|Izdržljivost|Intelekt|Duh|Zdravlje|Mana|Snaga napada|Moć čarolija|Kritični pogodak|Brzina|Pogodak|Izmicanje|Pariranje|Blokiranje|Obrana',
    'trTR': 'Zırh|Güç|Çeviklik|Dayanıklılık|Zekâ|Ruh|Sağlık|Mana|Saldırı Gücü|Büyü Gücü|Kritik Vuruş|Hız|İsabet|Sıyrılma|Savuşturma|Blok|Savunma',
    'koKR': '방어도|힘|민첩성|체력|지능|정신력|생명력|마나|전투력|주문력|치명타|가속|적중|회피|무기 막기|방패 막기|방어 숙련',
    'zhCN': '护甲|力量|敏捷|耐力|智力|精神|生命值|法力值|攻击强度|法术强度|爆击|急速|命中|躲闪|招架|格挡|防御',
    'zhTW': '護甲|力量|敏捷|耐力|智力|精神|生命力|法力|攻擊強度|法術能量|致命一擊|加速|命中|閃躲|招架|格擋|防禦',
}
STAT_LABELS['esMX'] = STAT_LABELS['esES']


class ComparisonMatrix(unittest.TestCase):
    def test_delta_labels(self):
        document = load_catalog(ROOT, 'quests', ids=[])
        targets = document['locales']
        sources = [locale for locale in targets if locale not in document['rosettaLocales']]
        lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        lua.execute(b"""
            canaccessallvalues = function() return true end
            function GetLocale() return sourceLocale end
            addon = {}
            function addon:GetTargetLocale() return targetLocale end
            assert(loadfile('ForeverRosettaStone/database/item-data.lua'))('addon', addon)
            assert(loadfile('ForeverRosettaStone/tooltips/english-tooltip-formats.lua'))('addon', addon)
            assert(loadfile('ForeverRosettaStone/tooltips/localized-tooltip-formats.lua'))('addon', addon)
            assert(loadfile('ForeverRosettaStone/database/localized-item-data.lua'))('addon', addon)
        """)
        addon = lua.globals()[b'addon']
        for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
            lua.execute(path.read_bytes(), b'addon', addon)
        lua.execute((ROOT / 'ForeverRosettaStone/tooltips/tooltip-comparisons.lua').read_bytes(), b'addon', addon)
        globals_ = lua.globals()
        translate = addon[b'TranslateComparisonText']
        failures = []
        cases = 0
        for source in sources:
            globals_[b'sourceLocale'] = source.encode()
            for target in targets:
                globals_[b'targetLocale'] = target.encode()
                for index, key in enumerate(KEYS + STAT_KEYS):
                    source_values = FIXTURE['strings'].get(key, {})
                    native = source_values.get(source) or f'client_{source}_{key}'
                    globals_[key.encode()] = native.encode()
                    if key in KEYS:
                        override = FIXTURE['targetOverrides']['locales'].get(target, {}).get(key)
                        if target in CUSTOM_LABELS:
                            expected_label = (SHORT_DPS[target] if key == 'ITEM_MOD_DAMAGE_PER_SECOND_SHORT'
                                              else CUSTOM_LABELS[target].split('|')[index])
                        else:
                            expected_label = override or FIXTURE['strings'][key].get(target)
                    else:
                        expected_label = STAT_LABELS[target].split('|')[index - len(KEYS)]
                    for number in ('+12', '-1.75'):
                        prefix = f'|cff00ff00{number}|r '
                        original = prefix + native
                        result = translate(addon, original.encode())
                        actual = result.decode() if result is not None else None
                        expected = prefix + expected_label
                        cases += 1
                        if actual != expected:
                            failures.append((source, target, key, original, expected, actual))
                    globals_[key.encode()] = None
                unknown = b'|cffff0000-2|r Mystery stat'
                result = translate(addon, unknown)
                expected = unknown if source == target else None
                self.assertEqual(result, expected, (source, target, 'unrecognized'))
        print(f'Comparison matrix: {len(sources)} sources x {len(targets)} targets, {cases} cases')
        self.assertFalse(failures, f'Failures (first 10): {failures[:10]!r}; total {len(failures)}')


if __name__ == '__main__':
    unittest.main()
