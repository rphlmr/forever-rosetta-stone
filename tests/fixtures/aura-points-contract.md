# Active aura amount contract

This is source-backed implementation guidance, not an in-game capture of build 70938.

## Source evidence

- The [Forever UI export, build 1.60.1.70658](https://github.com/reckhou/WoWBlzCode/blob/main/Forever/BlizzardInterfaceCode/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua)
  implements `AuraUtil.UnpackAuraData` by unpacking `auraData.points` in order.
  The UI export exposes the values but does not document the engine's internal mapping.
- The [TrinityCore aura update implementation](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/game/Spells/Auras/SpellAuras.cpp)
  writes each amount at its original zero-based effect index using
  `EnsureWritableVectorIndex(auraData.Points, effect->GetEffIndex())`.
  Missing earlier effects are not removed from the index space. This is an independent
  protocol implementation, not the source of Blizzard's Forever engine.
- Owned SpellEffect records identify each effect with a zero-based `index`, an
  `effectType`, and an `auraType`. The template token `$sN` already selects effect `N - 1`.

Together these sources support the effect-slot mapping implemented here. A live Forever
check remains necessary to confirm which amounts each aura actually exposes on build 70938.

## Renderer boundary

For an owned apply-aura effect (`effectType = 6`, positive `auraType`) belonging to the
displayed aura, `$sN`, `$mN`, and `$MN` read `points[N]`. The active amount is a single
value, not a base range. Explicit references to the same spell may use it; other spells
and their nested descriptions must not inherit these points. `$wN` retains its existing
explicit live-point behavior. Missing, restricted, or nonfinite required amounts retain
native text. No recipient spell power, level scaling, or trait scaling is applied to a
live amount already supplied by the aura.

The regression values are controlled synthetic inputs. They test mapping, sparse slots,
zero, signs, changing instances, other casters, expressions and source isolation; they
are not presented as observations of real priest aura ticks.
