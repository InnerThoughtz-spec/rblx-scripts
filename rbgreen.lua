-- RB5 World 5 Auto Green // Matcha external · bulletproof rewrite
-- Meter source: workspace[YourName].Properties.ShotMeter (NumberValue)
-- Mechanic: tap E once, script taps E for you, polls meter delta,
-- releases when delta >= target.
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/main/rb4.lua?v=1"))()

local OK, ERR = pcall(function()

local CONFIG = {
    target            = 0.78,    -- release when bar normalized crosses this (tune with [ ])
    adaptiveTarget    = false,   -- distance math was wrong, dropped
    overchargeCeiling = 1.50,
    shootKey          = 0x45,    -- E
    -- Letter-key hotkeys only (no F-keys per your request)
    toggleKey         = 0x54,    -- T = on/off
    tuneUpKey         = 0xDD,    -- ] = +0.001
    tuneDownKey       = 0xDB,    -- [ = -0.001
    tuneCoarseUp      = 0xBB,    -- = = +0.01
    tuneCoarseDown    = 0xBD,    -- - = -0.01
    diagKey           = 0x4D,    -- M = diag dump
    closeKey          = 0x4E,    -- N = close
}

local state = {
    enabled       = true,
    closed        = false,
    busy          = false,
    lastShotMeter = 0,
    lastResult    = "—",
    rawNow        = 0,
}

local function safeNotify(m, t, d)
    pcall(function() if notify then notify(m, t, d) end end)
end

-- Get the Workspace service the safe way (matcha may not expose `workspace` global)
local function getWorkspace()
    local w
    pcall(function() w = game:GetService("Workspace") end)
    if w then return w end
    pcall(function() w = workspace end)
    return w
end

local function getLP()
    local p
    pcall(function() p = game:GetService("Players").LocalPlayer end)
    return p
end

-- Locate workspace[YourName].Properties.ShotMeter
local function findShotMeter()
    local lp = getLP()
    if not lp then return nil end
    local lpName
    pcall(function() lpName = lp.Name end)
    if not lpName then return nil end
    local ws = getWorkspace()
    if not ws then return nil end
    local char
    pcall(function() char = ws:FindFirstChild(lpName) end)
    if not char then return nil end
    local props
    pcall(function() props = char:FindFirstChild("Properties") end)
    if not props then return nil end
    local sm
    pcall(function() sm = props:FindFirstChild("ShotMeter") end)
    return sm
end

-- ─── UI BAR ────────────────────────────────────────────────────────
local barLocked = { frame = nil, axis = nil, minPx = 0, maxPx = 0 }

-- Hardcoded paths from your dump
local function findBarFrame()
    if barLocked.frame and barLocked.frame.Parent then return barLocked.frame end
    local lp = getLP()
    local gui = lp and lp:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local c = gui:FindFirstChild("ShotMeterUI_Vertical")
    if not c then return nil end
    c = c:FindFirstChild("Canvas")
    if not c then return nil end
    local m = c:FindFirstChild("Meter")
    if not m then return nil end
    return m:FindFirstChild("Bar")
end

local function findPerfectFrame()
    local lp = getLP()
    local gui = lp and lp:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local c = gui:FindFirstChild("ShotMeterUI_Vertical")
    if not c then return nil end
    c = c:FindFirstChild("Canvas")
    if not c then return nil end
    return c:FindFirstChild("Perfect")
end

local function readBarPx()
    local f = barLocked.frame or findBarFrame()
    if not f then return nil end
    local px
    pcall(function() px = f.AbsoluteSize.Y end)
    return type(px) == "number" and px or nil
end

local function readPerfectPx()
    local f = findPerfectFrame()
    if not f then return nil end
    local px
    pcall(function() px = f.AbsoluteSize.Y end)
    return type(px) == "number" and px or nil
end

local function readBarScale()
    local barPx = readBarPx()
    if not barPx then return nil end
    local range = barLocked.maxPx - barLocked.minPx
    if range <= 0 then
        -- Fallback: if no autodetect ran, assume bar maxes at 200 px
        range = 200
    end
    local minPx = barLocked.minPx > 0 and barLocked.minPx or 1
    local norm = (barPx - minPx) / range
    return math.max(0, math.min(1.2, norm))
end

local function readMeter()
    -- PRIORITY 1: locked UI bar (the visible yellow thing), normalized 0-1
    local bar = readBarScale()
    if bar then return bar end
    -- PRIORITY 2: fall back to ShotMeter NumberValue
    local sm = findShotMeter()
    if not sm then return 0 end
    local v = 0
    pcall(function() v = sm.Value end)
    if type(v) ~= "number" then v = 0 end
    return v
end

-- ─── Distance-to-basket → target value ─────────────────────────────
-- RB5 W5: shot timing varies by court position. Close = fast meter,
-- short hold (lower target). Three = slow meter, longer hold (higher
-- target). We find the nearest hoop, compute distance, interpolate.
local function findNearestHoop()
    local ws = getWorkspace()
    if not ws then return nil end
    local closest, closestDist = nil, math.huge
    local lp = getLP()
    if not lp or not lp.Character then return nil end
    local root
    pcall(function()
        root = lp.Character:FindFirstChild("HumanoidRootPart")
              or lp.Character.PrimaryPart
              or lp.Character:FindFirstChild("Hull")
    end)
    if not root then return nil end
    local myPos = root.Position

    for _, d in ipairs(ws:GetDescendants()) do
        local nm = string.lower(d.Name or "")
        if d:IsA("BasePart") and (nm:find("hoop") or nm:find("basket") or nm:find("rim") or nm:find("backboard")) then
            local dist = (d.Position - myPos).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = d
            end
        end
    end
    return closest, closestDist
end

local function computeTargetForDistance(dist)
    -- Calibration anchors (from LO's observed data + court scale heuristics):
    --   ~8 studs   (under-basket / layup zone) → target ≈ 0.85
    --   ~25 studs  (mid-range)                 → target ≈ 0.97
    --   ~45 studs  (three-point line area)     → target ≈ 1.10
    --   ~65+ studs (deep three / heave)        → target ≈ 1.25
    if dist <= 8  then return 0.85 end
    if dist <= 25 then return 0.85 + (dist - 8)  / 17 * 0.12 end
    if dist <= 45 then return 0.97 + (dist - 25) / 20 * 0.13 end
    if dist <= 65 then return 1.10 + (dist - 45) / 20 * 0.15 end
    return 1.25
end

local function getAdaptiveTarget()
    if not CONFIG.adaptiveTarget then return CONFIG.target, nil end
    local hoop, dist = findNearestHoop()
    if not hoop or not dist then return CONFIG.target, nil end
    local t = computeTargetForDistance(dist)
    return t, dist
end

-- ─── B: Bar autodetect — find the visible UI meter Frame ───────────
-- Walks PlayerGui, snapshots every Frame's Size.X.Scale and Size.Y.Scale,
-- watches 2.5s while user holds E, locks the Frame+axis whose Scale
-- climbed most.
local function barAutoDetect()
    print("[RB5] === BAR AUTODETECT === HOLD E NOW")
    safeNotify("BAR DETECT: HOLD E now", "matcha", 4)

    print("[RB5] step 1: getLP")
    local lp = getLP()
    print("[RB5]   lp = " .. tostring(lp))
    if not lp then print("[RB5] FAIL: no LocalPlayer"); return end

    print("[RB5] step 2: PlayerGui")
    local gui
    local okG = pcall(function() gui = lp:FindFirstChild("PlayerGui") end)
    print("[RB5]   ok=" .. tostring(okG) .. " gui=" .. tostring(gui))
    if not gui then print("[RB5] FAIL: no PlayerGui"); return end

    print("[RB5] step 3: GetDescendants")
    local descendants
    local okD = pcall(function() descendants = gui:GetDescendants() end)
    if not okD or not descendants then
        print("[RB5] FAIL: GetDescendants errored")
        return
    end
    print("[RB5]   " .. tostring(#descendants) .. " descendants")

    print("[RB5] step 4: probing Size access on one Frame...")
    local probed = false
    for _, d in ipairs(descendants) do
        if probed then break end
        local cls
        pcall(function() cls = d.ClassName end)
        if cls == "Frame" then
            local sz, ab, tof
            pcall(function() sz = tostring(d.Size) end)
            pcall(function() ab = tostring(d.AbsoluteSize) end)
            pcall(function() tof = typeof and typeof(d.Size) or type(d.Size) end)
            print("[RB5]   sample Frame: " .. d.Name)
            print("[RB5]     Size tostring: " .. tostring(sz))
            print("[RB5]     Size typeof:   " .. tostring(tof))
            print("[RB5]     AbsoluteSize:  " .. tostring(ab))
            local xs, ys
            pcall(function() xs = d.Size.X.Scale end)
            pcall(function() ys = d.Size.Y.Scale end)
            print("[RB5]     Size.X.Scale = " .. tostring(xs))
            print("[RB5]     Size.Y.Scale = " .. tostring(ys))
            local ax, ay
            pcall(function() ax = d.AbsoluteSize.X end)
            pcall(function() ay = d.AbsoluteSize.Y end)
            print("[RB5]     AbsoluteSize.X = " .. tostring(ax))
            print("[RB5]     AbsoluteSize.Y = " .. tostring(ay))
            probed = true
        end
    end

    print("[RB5] step 5: snapshot AbsoluteSize (pixels) of every UI instance")
    local snapshots = {}
    local seenInsts = 0
    for _, d in ipairs(descendants) do
        local cls
        pcall(function() cls = d.ClassName end)
        if cls == "Frame" or cls == "ImageLabel" or cls == "ImageButton"
           or cls == "CanvasGroup" or cls == "TextLabel" then
            seenInsts = seenInsts + 1
            local ax, ay
            pcall(function() ax = d.AbsoluteSize.X end)
            pcall(function() ay = d.AbsoluteSize.Y end)
            if type(ax) == "number" then
                table.insert(snapshots, { frame = d, axis = "X", min = ax, max = ax })
            end
            if type(ay) == "number" then
                table.insert(snapshots, { frame = d, axis = "Y", min = ay, max = ay })
            end
        end
    end
    print(string.format("[RB5]   %d UI instances, %d AbsoluteSize sources", seenInsts, #snapshots))

    if #snapshots == 0 then
        print("[RB5] FAIL: AbsoluteSize unreadable too")
        return
    end

    print("[RB5] step 6: watching for 2.5s — HOLD E NOW")
    local started = tick()
    local pollCount = 0
    while tick() - started < 2.5 do
        for _, snap in ipairs(snapshots) do
            local v
            if snap.axis == "X" then
                pcall(function() v = snap.frame.AbsoluteSize.X end)
            else
                pcall(function() v = snap.frame.AbsoluteSize.Y end)
            end
            if type(v) == "number" then
                if v > snap.max then snap.max = v end
                if v < snap.min then snap.min = v end
            end
        end
        pollCount = pollCount + 1
        wait(0)
    end
    print("[RB5]   " .. pollCount .. " polls completed")

    print("[RB5] step 7: ranking by pixel growth")
    -- AbsoluteSize is in pixels — need bigger threshold (a bar might grow by 200+ px)
    local ranked = {}
    for _, snap in ipairs(snapshots) do
        local amp = snap.max - snap.min
        -- compute relative growth (max-min)/max so bars of any pixel size rank fairly
        local rel = snap.max > 0 and (amp / snap.max) or 0
        if amp > 5 then  -- at least 5 pixels of movement
            table.insert(ranked, { snap = snap, amp = amp, rel = rel })
        end
    end
    -- rank by relative growth (a bar growing from 10→100 px should beat a window resize)
    table.sort(ranked, function(a, b) return a.rel > b.rel end)

    print(string.format("[RB5] %d UI sources moved during the shot:", #ranked))
    for i = 1, math.min(15, #ranked) do
        local r = ranked[i]
        local fn = "?"
        pcall(function() fn = r.snap.frame:GetFullName() end)
        print(string.format("  [%d] %s.AbsoluteSize.%s   %.1f -> %.1f px   rel=%.3f",
            i, fn, r.snap.axis, r.snap.min, r.snap.max, r.rel))
    end

    if ranked[1] and ranked[1].rel > 0.3 then
        barLocked.frame = ranked[1].snap.frame
        barLocked.axis  = ranked[1].snap.axis
        barLocked.minPx = ranked[1].snap.min
        barLocked.maxPx = ranked[1].snap.max
        local fn = "?"
        pcall(function() fn = ranked[1].snap.frame:GetFullName() end)
        print(string.format("[RB5] BAR LOCKED: %s.AbsoluteSize.%s  range=%.1f-%.1f px",
            fn, ranked[1].snap.axis, ranked[1].snap.min, ranked[1].snap.max))
        safeNotify("Bar locked!", "matcha", 5)
    else
        print("[RB5] no source climbed enough — hold E for the FULL 2.5s next time")
        safeNotify("Bar detect: nothing climbed", "matcha", 5)
    end
end

-- ─── Y: print live bar + perfect values (call right after a green) ──
local function dumpLive()
    local barPx = readBarPx()
    local perfectPx = readPerfectPx()
    local scale = readBarScale()
    print(string.format("[RB5] LIVE   barPx=%.2f  perfectPx=%.2f  norm=%.4f  target=%.3f",
        barPx or -1, perfectPx or -1, scale or -1, CONFIG.target))
    safeNotify(string.format("bar=%.0fpx scale=%.3f", barPx or 0, scale or 0), "matcha", 3)
end

-- ─── Drawing helpers (every Drawing.new wrapped) ────────────────────
local allDrawings = {}
local function newDraw(kind)
    local d
    local ok = pcall(function() d = Drawing.new(kind) end)
    if not ok or not d then return nil end
    table.insert(allDrawings, d)
    return d
end

local function setProp(d, key, val)
    if not d then return end
    pcall(function() d[key] = val end)
end

-- ─── HUD ────────────────────────────────────────────────────────────
local HUD_X, HUD_Y, HUD_W, HUD_H = 20, 260, 360, 170
local hud = {}

hud.bg = newDraw("Square")
setProp(hud.bg, "Color", Color3.fromRGB(12, 14, 18))
setProp(hud.bg, "Filled", true)
setProp(hud.bg, "Transparency", 0.92)
setProp(hud.bg, "ZIndex", 998)
setProp(hud.bg, "Visible", true)
setProp(hud.bg, "Size", Vector2.new(HUD_W, HUD_H))
setProp(hud.bg, "Position", Vector2.new(HUD_X, HUD_Y))

hud.accent = newDraw("Square")
setProp(hud.accent, "Color", Color3.fromRGB(110, 230, 130))
setProp(hud.accent, "Filled", true)
setProp(hud.accent, "Transparency", 1)
setProp(hud.accent, "ZIndex", 999)
setProp(hud.accent, "Visible", true)
setProp(hud.accent, "Size", Vector2.new(4, HUD_H))
setProp(hud.accent, "Position", Vector2.new(HUD_X, HUD_Y))

hud.title = newDraw("Text")
setProp(hud.title, "Text", "RB5 W5 Auto Green · matcha")
setProp(hud.title, "Size", 15)
setProp(hud.title, "Font", Drawing.Fonts.SystemBold)
setProp(hud.title, "Color", Color3.fromRGB(240, 240, 245))
setProp(hud.title, "Outline", true)
setProp(hud.title, "ZIndex", 1000)
setProp(hud.title, "Visible", true)
setProp(hud.title, "Position", Vector2.new(HUD_X + 14, HUD_Y + 8))

local function mkLine(dy, init)
    local t = newDraw("Text")
    setProp(t, "Size", 12)
    setProp(t, "Font", Drawing.Fonts.Monospace)
    setProp(t, "Color", Color3.fromRGB(210, 215, 220))
    setProp(t, "Outline", true)
    setProp(t, "ZIndex", 1000)
    setProp(t, "Visible", true)
    setProp(t, "Position", Vector2.new(HUD_X + 14, HUD_Y + dy))
    setProp(t, "Text", init or "")
    return t
end
hud.lineStatus = mkLine(34, "Status:    -")
hud.lineTarget = mkLine(52, "Target:    -")
hud.lineMeter  = mkLine(70, "Meter:     -")
hud.lineSrc    = mkLine(88, "Source:    -")
hud.lineLast   = mkLine(108, "Last shot: -")
hud.lineHint   = mkLine(140, "HOLD E · script releases at target · T=toggle [ ]=tune `=rec N=close")
setProp(hud.lineHint, "Color", Color3.fromRGB(140, 150, 160))
setProp(hud.lineHint, "Size", 10)

local function paintHud()
    pcall(function()
        local statusTxt = state.enabled and "ARMED" or "OFF"
        if state.busy then statusTxt = statusTxt .. "  ·  RELEASING" end
        setProp(hud.lineStatus, "Text", "Status:    " .. statusTxt)
        setProp(hud.lineStatus, "Color", state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110))

        setProp(hud.lineTarget, "Text", string.format("Target:    %.3f (basket=0.85 · GREEN=0.93+)", CONFIG.target))
        setProp(hud.lineTarget, "Color", Color3.fromRGB(255, 200, 80))

        setProp(hud.lineMeter, "Text", string.format("Meter:     raw=%.3f  shot-delta=%.3f", state.rawNow, state.lastShotMeter))

        local sm = findShotMeter()
        setProp(hud.lineSrc, "Text", "Source:    " .. (sm and "workspace[You].Properties.ShotMeter ✓" or "NOT FOUND — respawn?"))
        setProp(hud.lineSrc, "Color", sm and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110))

        setProp(hud.lineLast, "Text", "Last shot: " .. state.lastResult)

        setProp(hud.accent, "Color", state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110))
    end)
end

-- ─── Shoot logic — BL Auto Green pattern ───────────────────────────
-- User holds E themselves (natural hold). Script monitors the meter,
-- and at the exact moment meter crosses the target value going up,
-- fires keyrelease(E) — even though user is still holding E. The
-- release event reaches the game first → shot fires at target.
-- No keypress loop, no fighting the user.
local function autoGreenShot()
    if state.busy or not state.enabled then return end
    state.busy = true

    local startedAt = tick()
    local releaseAt = 0
    local sawReset  = false
    local resetAt   = nil

    while not state.closed do
        local raw = readMeter()
        state.rawNow = raw
        state.lastShotMeter = raw

        -- Wait for meter to reset (fresh shot started)
        if not sawReset and raw < 0.3 then
            sawReset = true
            resetAt  = tick()
        end

        if sawReset then
            local heldFor = tick() - resetAt
            if heldFor >= 0.15 then
                local activeTarget, distFromHoop = getAdaptiveTarget()
                state.activeTarget = activeTarget
                state.distFromHoop = distFromHoop
                if raw >= activeTarget then
                    for _ = 1, 10 do pcall(function() keyrelease(CONFIG.shootKey) end) end
                    releaseAt = raw
                    break
                end
            end
        end

        if tick() - startedAt > 3 then
            for _ = 1, 10 do pcall(function() keyrelease(CONFIG.shootKey) end) end
            releaseAt = raw
            break
        end

        wait(0)
    end

    -- Classification — calibrated to LO's data points (840=basket, 909=basket/green,
    -- 1.811 confirmed overcharge/miss)
    if releaseAt >= 0.93 and releaseAt <= 1.05 then
        state.lastResult = string.format("%.3f · GREEN", releaseAt)
    elseif releaseAt >= 0.85 then
        state.lastResult = string.format("%.3f · basket", releaseAt)
    elseif releaseAt > 1.05 then
        state.lastResult = string.format("%.3f · OVERCHARGE/miss", releaseAt)
    elseif releaseAt == 0 then
        state.lastResult = "0.000 · no shot detected"
    else
        state.lastResult = string.format("%.3f · early/miss", releaseAt)
    end

    pcall(function() wait(0.08) end)
    state.busy = false
end

-- ─── R: Record mode — trace the meter for 3 seconds ─────────────────
-- Press R THEN immediately tap E. The script prints the meter every
-- 50ms so we can see the exact curve and pick the green target.
local function recordMode()
    print("=== RB5 RECORD MODE === press E now and hold for the full shot")
    safeNotify("RECORD: press E for full shot now", "matcha", 3)
    local samples = {}
    local startedAt = tick()
    while tick() - startedAt < 3.0 do
        local raw = readMeter()
        table.insert(samples, { t = tick() - startedAt, v = raw })
        wait(0.05)
    end
    print("[RB5] meter trace (3 seconds):")
    for i, s in ipairs(samples) do
        if i % 2 == 1 then  -- every 100ms
            print(string.format("  %6.2fs   %.4f", s.t, s.v))
        end
    end
    -- pick the peak as candidate for "perfect green" target
    local peak = 0
    for _, s in ipairs(samples) do if s.v > peak then peak = s.v end end
    print(string.format("[RB5] PEAK during trace: %.4f", peak))
    safeNotify(string.format("Peak: %.3f — paste console", peak), "matcha", 5)
end

-- ─── Diagnostic ─────────────────────────────────────────────────────
local function diagDump()
    print("=== RB5 W5 diag ===")
    local sm = findShotMeter()
    print("Meter found:  " .. tostring(sm and sm:GetFullName() or "nil"))
    print("Meter value:  " .. tostring(readMeter()))
    print("Target:       " .. tostring(CONFIG.target))
    local lp = getLP()
    print("LP name:      " .. tostring(lp and lp.Name or "nil"))
    safeNotify("Diag dumped to console", "matcha", 3)
end

-- ─── Hotkeys ────────────────────────────────────────────────────────
spawn(function()
    pcall(function()
        local prev = {}
        local function edge(k)
            local d
            pcall(function() d = iskeypressed(k) end)
            local was = prev[k]; prev[k] = d
            return d and not was
        end

        while not state.closed do
            if edge(CONFIG.shootKey) then
                spawn(function() pcall(autoGreenShot) end)
            end
            if edge(CONFIG.toggleKey) then
                state.enabled = not state.enabled
                safeNotify("Auto-green " .. (state.enabled and "ON" or "OFF"), "matcha", 1.5)
            end
            if edge(CONFIG.tuneUpKey)      then CONFIG.target = math.min(1.50, CONFIG.target + 0.001) end
            if edge(CONFIG.tuneDownKey)    then CONFIG.target = math.max(0.10, CONFIG.target - 0.001) end
            if edge(CONFIG.tuneCoarseUp)   then CONFIG.target = math.min(1.50, CONFIG.target + 0.01) end
            if edge(CONFIG.tuneCoarseDown) then CONFIG.target = math.max(0.10, CONFIG.target - 0.01) end
            if edge(CONFIG.diagKey)        then spawn(function() pcall(diagDump) end) end
            if edge(0xC0)                  then spawn(function() pcall(recordMode) end) end  -- ` (backtick) = record
            if edge(0x42)                  then spawn(function() pcall(barAutoDetect) end) end  -- B = bar autodetect
            if edge(0x59)                  then spawn(function() pcall(dumpLive) end) end       -- Y = print live bar+perfect
            if edge(CONFIG.closeKey) then
                state.closed = true
                for _, d in ipairs(allDrawings) do
                    pcall(function() d.Visible = false end)
                    pcall(function() d:Remove() end)
                end
                safeNotify("RB5 closed", "matcha", 2)
                return
            end
            wait(0.008)
        end
    end)
end)

-- ─── Live meter readout + HUD paint ────────────────────────────────
spawn(function()
    while not state.closed do
        pcall(function()
            if not state.busy then state.rawNow = readMeter() end
            paintHud()
        end)
        wait(0.05)
    end
end)

safeNotify("RB5 W5 armed · tap E to shoot · target=" .. CONFIG.target, "matcha", 4)
print("[RB5] armed. target=" .. CONFIG.target)
print("[RB5] keys: E=shoot · T=toggle · [ ]=tune · M=diag · N=close")

end)  -- end of outer pcall

if not OK then
    pcall(function()
        if notify then notify("RB5 boot error: " .. tostring(ERR), "matcha", 8) end
    end)
    print("[RB5] BOOT ERROR: " .. tostring(ERR))
end
