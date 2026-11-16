"""Compare client tooltip formats with the build-matched GlobalStrings snapshots.

The independent inventory is the TOOLTIP_ITEM_STAT_* family. GlobalStrings
does not establish which entries this client actually emits in a tooltip.
"""

import json
import re
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/fixtures/tooltip-client-strings.json"


def render_format(template):
    template = re.sub(r"\|4([^:;]+):[^;]+;", r"\1", template)
    template = re.sub(r"%(?:\d+\$)?[\d.]*c", "+", template)
    template = re.sub(r"%(?:\d+\$)?[\d.]*[dscfg]", "1", template)
    return template.replace("%%", "%")


def get_arguments(template):
    arguments = re.findall(r"%(?:(\d+)\$)?[\d.]*([dscfg])", template)
    return sorted((int(position or index), kind) for index, (position, kind) in enumerate(arguments, 1))


def render_case(template, key, locale):
    if key == "RESISTANCE_TEMPLATE":
        resistance = fixture["strings"]["RESISTANCE2_NAME"][locale]
        template = re.sub(r"%(?:\d+\$)?[\d.]*s", lambda _: resistance, template)

    return render_format(template)


fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
english = {key: values["enUS"] for key, values in fixture["strings"].items()}
french = {key: values["frFR"] for key, values in fixture["strings"].items()}
lua = LuaRuntime(encoding=None)
lua.execute(b'''
canaccessallvalues = function(...) return true end
sourceLocale = "frFR"
GetLocale = function() return sourceLocale end
Enum = { TooltipDataLineType = {} }
ForeverRosettaStoneDB = { GetItemDetails = function() return nil end, GetSpellDetails = function() return nil end }
assert(loadfile("tests/fixtures/tooltip-source-api.lua"))()(ForeverRosettaStoneDB)
local addon = {}
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/database/item-data.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/localized-tooltip-formats.lua"))("ForeverRosettaStone", addon)
for _, locale in ipairs({ "ukUA", "csCZ", "daDK", "hrHR", "plPL", "svSE", "trTR" }) do
    addon.tooltipFormatsByLocale[locale] = {}
end
assert(loadfile("ForeverRosettaStone/tooltips/appearance-tooltip-formats.lua"))("ForeverRosettaStone", addon)
TestAddon = addon
''')
addon = lua.globals().TestAddon
formats = {key.decode(): value.decode() for key, value in addon.englishTooltipFormats.items()}
labels = {key.decode(): value.decode() for key, value in addon.itemTooltipLabels.items()}
inventory = {key for key in english if key.startswith("TOOLTIP_ITEM_STAT_")}
missing = sorted(inventory - formats.keys())
print(f"Client stat formats absent from shipped map: {len(missing)} of {len(inventory)}; applicability unverified")

results = {"passed": [], "context or unsupported": [], "missing client source": [], "different English": []}
for key in sorted(formats.keys() | labels.keys()):
    if key not in english or key not in french:
        results["missing client source"].append(key)
        continue

    target = formats.get(key, labels.get(key))
    if target != english[key]:
        results["different English"].append(key)
        continue

    if not french[key] or not target:
        results["context or unsupported"].append(key)
        continue

    lua.globals()[key.encode()] = french[key].encode()
    actual = addon.TranslateLiveTooltipLine(addon, render_format(french[key]).encode())
    lua.globals()[key.encode()] = None
    expected = render_format(target).encode()
    results["passed" if actual == expected else "context or unsupported"].append(key)

for category, keys in results.items():
    print(f"{category}: {len(keys)}" + (f" ({', '.join(keys)})" if category != "passed" and keys else ""))

assert len(inventory) == 160, f"Unexpected client stat inventory size: {len(inventory)}"
assert results["context or unsupported"] == ["INVTYPE_NON_EQUIP_IGNORE"], results["context or unsupported"]
assert not results["missing client source"], results["missing client source"]
assert not results["different English"], results["different English"]
print(f"PASS: inventoried {len(formats)} formats, {len(labels)} item labels, and {len(inventory)} client stat formats")

extra_keys = {
    "SELL_PRICE", "SECONDS_ABBR", "MINUTES_ABBR", "HOURS_ABBR", "DAYS_ABBR",
    "SPELL_DURATION_UNTIL_CANCELLED", "SECOND_ONELETTER_ABBR", "MINUTE_ONELETTER_ABBR",
    "HOUR_ONELETTER_ABBR", "DAY_ONELETTER_ABBR",
}
for locale in fixture["locales"]:
    reference = {
        key: values[locale]
        for key, values in fixture["strings"].items()
    }
    target = addon.tooltipFormatsByLocale[locale.encode()]
    for key in formats.keys() | labels.keys() | extra_keys:
        expected = reference[key]
        actual = target[key.encode()]
        if not expected:
            assert actual is None or actual == b"", (locale, key, actual)
            continue

        override = fixture["targetOverrides"]["locales"].get(locale, {}).get(key)
        assert actual == (override or expected).encode(), (locale, key, actual, expected)
        assert get_arguments(expected) == get_arguments(english[key]), (locale, key)

print("PASS: official target format snapshots")

matrix_passed = 0
matrix_empty = 0
matrix_failures = []
for source_locale in fixture["locales"]:
    lua.globals().sourceLocale = source_locale.encode()
    for target_locale in fixture["locales"]:
        counts = {"passed": 0, "untranslated or mismatched": 0, "empty": 0}
        mismatched = []
        for key in sorted(formats.keys() | labels.keys() | extra_keys):
            source = fixture["strings"][key][source_locale]
            target = fixture["strings"][key][target_locale]
            if target_locale == "itIT" and key.startswith("TRANSMOGRIFY_TOOLTIP_"):
                target = fixture["targetOverrides"]["locales"]["itIT"][key]
            if not source or not target:
                counts["empty"] += 1
                continue

            lua.globals()[key.encode()] = source.encode()
            if key == "RESISTANCE_TEMPLATE":
                lua.globals().RESISTANCE2_NAME = fixture["strings"]["RESISTANCE2_NAME"][source_locale].encode()
            line = lua.table_from({b"leftText": render_case(source, key, source_locale).encode()})
            result = addon.GetLocalizedTooltipLine(addon, line, b"item", 0, target_locale.encode())
            actual = result[0] if isinstance(result, tuple) else result
            lua.globals()[key.encode()] = None
            if key == "RESISTANCE_TEMPLATE":
                lua.globals().RESISTANCE2_NAME = None
            target_format = addon.tooltipFormatsByLocale[target_locale.encode()][key.encode()].decode()
            expected = render_case(target_format, key, target_locale).encode()
            outcome = "passed" if actual == expected else "untranslated or mismatched"
            counts[outcome] += 1
            if outcome != "passed":
                mismatched.append(f"{key}={actual!r} expected {expected!r}")

        matrix_passed += counts["passed"]
        matrix_empty += counts["empty"]
        if mismatched:
            matrix_failures.append(f"{source_locale} to {target_locale}: {', '.join(mismatched)}")

print(f"Matrix: {matrix_passed} passed, {matrix_empty} empty, {len(matrix_failures)} locale pairs with failures")
assert not matrix_failures, "\n".join(matrix_failures)
print("PASS: shared item labels translate across official client languages")
appearance_keys = [key for key in formats if key.startswith("TRANSMOGRIFY_TOOLTIP_")]
assert len(appearance_keys) == 7, appearance_keys
for locale in ("ukUA", "csCZ", "daDK", "hrHR", "plPL", "svSE", "trTR", "itIT"):
    for key in appearance_keys:
        actual = addon.tooltipFormatsByLocale[locale.encode()][key.encode()]
        expected = fixture["targetOverrides"]["locales"][locale][key]
        assert actual == expected.encode(), (locale, key, actual, expected)

lua.globals().RESISTANCE2_NAME = None
lua.globals().sourceLocale = b"frFR"
appearance = "TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN"
lua.globals()[appearance.encode()] = french[appearance].encode()
assert addon.TranslateLiveTooltipLine(addon, french[appearance].encode()) == english[appearance].encode()
lua.globals()[appearance.encode()] = None

for key in ("DAMAGE_TEMPLATE_WITH_SCHOOL", "DAMAGE_SCHOOL3", "ITEM_MIN_SKILL"):
    lua.globals()[key.encode()] = french[key].encode()

assert addon.TranslateLiveTooltipLine(addon, "Dégâts (Feu) : 10 - 20".encode()) == b"10 - 20 Fire Damage"
profession_keys = (
    "ALCHEMY", "BLACKSMITHING", "COOKING", "ENCHANTING", "ENGINEERING", "FIRST_AID",
    "FISHING", "HERBALISM", "LEATHERWORKING", "MINING", "SKINNING", "TAILORING",
)
for key in profession_keys:
    lua.globals()[key.encode()] = french[key].encode()
    native = french["ITEM_MIN_SKILL"].replace("%s", french[key]).replace("%d", "150")
    expected = english["ITEM_MIN_SKILL"].replace("%s", english[key]).replace("%d", "150")
    skill_result = addon.TranslateLiveTooltipLine(addon, native.encode())
    assert skill_result == expected.encode(), (key, skill_result, expected)
    lua.globals()[key.encode()] = None

print("PASS: nested French school and profession names")
