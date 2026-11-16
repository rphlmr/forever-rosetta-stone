# Spell tooltip source syntax with unverified client expansion

These examples are retained client templates from `catalogs/spells/<id>.json`. The
synthetic matrix does not claim to reproduce the client's output for these
forms. The family-first test prints the complete unexercised family list for
each source locale, including cases that may have no usable target template.
Numeric `$1`, `$$444681s2`, `$10/;s1`, and `$rad#` are captured as opaque
tokens when the client supplies their live values; this does not establish
how the game computes those values.

| Spell ID | Source excerpt | What remains unverified |
| --- | --- | --- |
| 1245130 | `every $p for $d ... within $rad# yds` | `$rad#` expansion and its live value |
| 1319309 | `$@spellaura24907` | Actual in-game rendering; aura text is covered by synthetic fixtures |
| 1238122 | `$@spelltooltip414924` | One frFR `C_Spell.GetSpellDescription` capture omits child text; embedded-widget behavior remains unverified |
| 348779 | `$@null` | Whether and how the client renders this marker |
| 27039 | `maximum health by $1%` | Meaning and live value of bare `$1` |
| 444682 | `by $$444681s2%` | Client interpretation of the doubled dollar sign |
| 446783 | `Restore $10/;s1 Rage` | Client interpretation of this transform syntax |
| 1245130 | frFR `$rad`, enUS `$rad#` | Whether the two token spellings identify the same client value |
| 447581 | `$@spelldesc998` | Spell 998 has no row in the pinned Spell or SpellName exports. The Forever tooltip endpoint returned 404 for 998 and no description or buff text for 447581 (Gloom). The reference stays intact. |

Source token family names normalize numeric IDs and indexes. This groups
instances for coverage selection, but generated values retain the original
token identity. An unexercised family is not by itself proof that runtime
handling is unsupported or that a template is valid.

The executable family-first scan prints the current unexercised families by
source locale. These are coverage gaps, not a count of distinct parser defects.

In the retained English and ten native source descriptions, lowercase `$pl`
appears 55 times as an operand inside `${...}` across three spells and 22 times
in a player-level predicate across two spells. It has no standalone occurrences
in those descriptions. For example, spell 1302309 contains both `$?$pl>=55`
and `${340+($pl-46)*12}`. The predicate is handled as a level condition and the
expression is captured as an opaque result; `$pl` is not an extra numeric slot.

Uppercase `$PL` also occurs as a standalone numeric token, for example in spell
1296663's `Level $PL target`. In the same source set it occurs 198 times
standalone across 18 spells, 891 times inside expressions, and 517 times in
level predicates. The source set counts enUS once and does not duplicate the
enGB alias.
