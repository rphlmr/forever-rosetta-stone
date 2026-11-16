local Addon = {}
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-state.lua"))("ForeverRosettaStone", Addon)
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local primary, comparison = {}, {}
local visible = { [primary] = true, [comparison] = false }
local state = Addon:CreateTooltipLifecycle(primary, visible)
local function send(kind, source, fields)
    local event = fields or {}
    event.type, event.source, event.visible = kind, source, visible
    local nextState, effects = Addon:TransitionTooltipLifecycle(state, event)
    state = nextState
    return effects
end

local effects = send("native.clear", primary)
equal(state.value, "building", "a native refresh enters building")
equal(effects[1].type, "clear.source", "clearing only discards the old embedded content")
equal(#send("layout.now"), 0, "a half-built visible source cannot render")
effects = send("native.data", primary, { data = { id = 2973 } })
equal(effects[1].type, "resolve.data", "data resolves without rendering unfinished native geometry")
effects = send("native.shown", primary)
equal(state.value, "scheduled", "native Show schedules the completed tooltip")
equal(effects[1].type, "resolve.owner", "native identity is resolved before rendering")
equal(effects[2].type, "schedule", "the machine owns scheduling")
local firstTicket = effects[2].ticket
equal(#send("layout.request"), 0, "repeated layout events share the pending layout")
effects = send("layout.tick", nil, { ticket = firstTicket })
equal(state.value, "rendering", "the current ticket starts rendering")
equal(effects[1].type, "render", "rendering is an accepted transition effect")
for _, event in ipairs({ "native.clear", "native.data", "native.shown", "native.hidden", "layout.now", "layout.request" }) do
    equal(#send(event, primary), 0, "renderer callbacks cannot reenter the lifecycle: " .. event)
    equal(state.value, "rendering", "renderer callbacks cannot change its state: " .. event)
end
send("layout.complete")
equal(state.value, "visible", "render completion releases ownership")
effects = send("layout.request")
local secondTicket = effects[1].ticket
equal(#send("layout.tick", nil, { ticket = firstTicket }), 0, "an old ticket cannot consume a newer pending layout")
equal(state.value, "scheduled", "a stale callback preserves the newer scheduled state")
send("layout.now")
send("layout.complete")
equal(#send("layout.tick", nil, { ticket = secondTicket }), 0, "an immediate layout invalidates its old scheduled callback")

visible[comparison] = true
send("native.clear", comparison)
equal(#send("layout.now"), 0, "an unfinished comparison blocks premature interleaving")
send("native.shown", comparison)
effects = send("layout.now")
equal(effects[1].type, "render", "comparison readiness permits the complete group")
send("layout.complete")
visible[primary] = false
effects = send("native.hidden", primary)
equal(state.value, "cleaning", "hiding the primary owns group cleanup")
equal(effects[1].type, "cleanup", "primary hide releases all translated tooltips")
equal(effects[1].clearIdentity, true, "primary hide discards stale entity identities")
equal(#send("native.shown", comparison), 0, "cleanup callbacks cannot resurrect the group")
equal(#send("reset"), 0, "cleanup cannot recursively restart itself")
send("cleanup.complete")
equal(state.value, "hidden", "cleanup settles into hidden")
equal(state.sources[comparison], "hidden", "hidden groups retain no ready comparison state")
effects = send("reset")
equal(effects[1].clearIdentity, false, "settings cleanup retains identities for immediate refresh")
send("cleanup.complete")
equal(#send("unknown", primary), 0, "unknown events have no effects")
print("PASS: " .. checks .. " tooltip lifecycle assertions")
