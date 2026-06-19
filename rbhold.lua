-- RB5 World 5 Auto Green // Matcha external · bulletproof rewrite
-- Meter source: workspace[YourName].Properties.ShotMeter (NumberValue)
-- Mechanic: tap E once, script taps E for you, polls meter delta,
-- releases when delta >= target.
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/main/rb4.lua?v=1"))()

local OK, ERR = pcall(function()

local CONFIG = {
    target            = 0.920,   -- calibrated: 0.909 = basket/green boundary, 0.92+ should hit green
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

local function readMeter()
    local sm = findShotMeter()
    if not sm then return 0 end
    local v = 0
    pcall(function() v = sm.Value end)
    if type(v) ~= "number" then v = 0 end
    return v
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
hud.lineHint   = mkLine(140, "TAP E (script holds for you) · T=toggle [ ]=tune `=rec M=diag N=close")
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

-- ─── Shoot logic ────────────────────────────────────────────────────
local function autoGreenShot()
    if state.busy or not state.enabled then return end
    state.busy = true

    -- KEY-HOLD OVERRIDE: spawn a tight loop that hammers keypress(E) at
    -- ~100Hz so even if the user lifts their finger, the game still sees
    -- E held continuously. We control when the shot ends — not the user.
    local stopHoldLoop = false
    spawn(function()
        while not stopHoldLoop and not state.closed do
            pcall(function() keypress(CONFIG.shootKey) end)
            wait(0.01)
        end
    end)

    -- TRUE peak detection via multi-frame plateau confirmation.
    -- We require: meter has risen significantly, THEN stayed flat for many
    -- consecutive frames (not just one tick gap), THEN release.
    -- Also release on actual decrease (peak passed).

    local startedAt    = tick()
    local releaseAt    = 0
    local sawReset     = false
    local peakSeen     = 0
    local lastRaw      = readMeter()
    local risingFrames = 0
    local plateauFrames = 0
    local everRoseBy   = 0   -- total cumulative rise — must exceed a threshold

    while not state.closed do
        local raw = readMeter()
        state.rawNow = raw
        state.lastShotMeter = raw

        if raw > peakSeen then peakSeen = raw end

        if raw < 0.3 then
            sawReset = true
            risingFrames = 0
            plateauFrames = 0
            everRoseBy = 0
            peakSeen = raw
        end

        if sawReset then
            local delta = raw - lastRaw

            if delta > 0.003 then
                risingFrames = risingFrames + 1
                plateauFrames = 0
                everRoseBy = everRoseBy + delta
            elseif delta < -0.015 then
                -- meter clearly going DOWN — peak passed, release at peakSeen
                stopHoldLoop = true
                -- give the hold loop one tick to exit, then release
                for _ = 1, 10 do pcall(function() keyrelease(CONFIG.shootKey) end) end
                releaseAt = peakSeen
                break
            else
                -- meter ~flat
                plateauFrames = plateauFrames + 1
            end

            -- Confirmed plateau release: must have meaningfully risen
            -- AND stayed flat for many consecutive frames AND be at a real high
            if everRoseBy > 0.5
               and risingFrames > 6
               and plateauFrames > 6
               and raw > peakSeen * 0.97 then
                stopHoldLoop = true
                -- give the hold loop one tick to exit, then release
                for _ = 1, 10 do pcall(function() keyrelease(CONFIG.shootKey) end) end
                releaseAt = raw
                break
            end
        end

        lastRaw = raw

        if tick() - startedAt > 3 then
            for _ = 1, 6 do pcall(function() keyrelease(CONFIG.shootKey) end) end
            releaseAt = peakSeen > 0 and peakSeen or raw
            break
        end

        wait(0)
    end

    -- Classification calibrated against LO's 0.909 = basket/green boundary
    if releaseAt >= 0.91 and releaseAt <= 1.05 then
        state.lastResult = string.format("%.3f · GREEN", releaseAt)
    elseif releaseAt >= 0.85 then
        state.lastResult = string.format("%.3f · basket", releaseAt)
    elseif releaseAt > 1.05 then
        state.lastResult = string.format("%.3f · OVERCHARGE", releaseAt)
    elseif releaseAt == 0 then
        state.lastResult = "0.000 · no meter (hold ball + try)"
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
