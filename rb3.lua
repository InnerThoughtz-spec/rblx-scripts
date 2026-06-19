-- RB5 World 5 Auto Green // Matcha external
-- METER-POLL mechanic: hold F → wait until ShotMeter ≥ target → release F.
-- No need to find or fire any RemoteEvent — the game's own input handling
-- starts the shot on press and ends it on release.
--
-- ShotMeter scale (from RBW4 reference / RB5 framework):
--   < 0.85  → early / miss
--   ≥ 0.85  → basket (counts but not perfect)
--   ≥ 0.93  → GREEN zone (perfect)
--   > 1.20  → overcharge / brick
--
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/refs/heads/main/rb5w5-autogreen.lua"))()

local CONFIG = {
    target            = 0.85,   -- ShotMeter DELTA to release at (basket=0.85, tune up for green)
    overchargeCeiling = 1.20,

    shootKey          = 0x45,   -- E  (RB5 W5 shoot bind)
    toggleKey         = 0x54,   -- T
    tuneUpKey         = 0xDD,   -- ]  → target +0.001
    tuneDownKey       = 0xDB,   -- [  → target -0.001
    tuneCoarseUp      = 0xBB,   -- =  → target +0.01
    tuneCoarseDown    = 0xBD,   -- -  → target -0.01
    closeKey          = 0x71,   -- F2
    diagKey           = 0x70,   -- F1

    -- if true, ALSO fire ClientAction("Shoot", true/false) on the discovered
    -- RemoteEvent. Some games gate the shot on this rather than the key.
    -- Leave false unless keypress-only doesn't work for you.
    fireRemote        = false,

    hudX = 20, hudY = 260, hudW = 360, hudH = 184,
}

local state = {
    enabled       = true,
    closed        = false,
    busy          = false,
    lastShotMeter = 0,
    lastResult    = "—",
    shootEvent    = nil,
    shootEventPath= "(not found · keypress only)",
    shootActionArg= nil,
    meterAttrName = "ShotMeter",
    meterSource   = nil,        -- { get = function() return number end }
    meterSourceLabel = "",
    lastDetectAt  = 0,
}

local function readMeter()
    -- Priority 1: the hard-coded RB5 W5 path
    local sm = findShotMeterValue()
    if sm and type(sm.Value) == "number" then return sm.Value end
    -- Priority 2: whatever F3 locked in
    if state.meterSource then
        local ok, v = pcall(state.meterSource.get)
        if ok and type(v) == "number" then return v end
    end
    -- Priority 3: char attr fallback
    local char = nil
    pcall(function() char = (Players.LocalPlayer or LP).Character end)
    if char then
        local v = char:GetAttribute(state.meterAttrName)
        if type(v) == "number" then return v end
    end
    return 0
end

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

local function safeNotify(m, t, d)
    if notify then pcall(function() notify(m, t, d) end) end
end

-- ─── Direct meter lookup — RB5 W5 confirmed path ────────────────────
-- Discovered via wide autodetect: ShotMeter is a NumberValue at
--   workspace[YourName].Properties.ShotMeter
-- This re-resolves every read in case the character respawns.
local function findShotMeterValue()
    local lp = Players.LocalPlayer
    if not lp then return nil end
    local char = workspace:FindFirstChild(lp.Name)
    if not char then return nil end
    local props = char:FindFirstChild("Properties")
    if not props then return nil end
    local sm = props:FindFirstChild("ShotMeter")
    if not sm then return nil end
    return sm
end

-- Matcha external: LP.Character can return nil even when the character
-- exists in workspace. Try every path before giving up.
local function getChar()
    -- 1. fresh re-fetch of LocalPlayer (cached `LP` can be stale)
    local lp = Players.LocalPlayer or LP
    if lp then
        local c = lp.Character
        if c and c.Parent then return c end
    end
    -- 2. workspace lookup by player name
    if lp and lp.Name then
        local m = workspace:FindFirstChild(lp.Name)
        if m then return m end
    end
    -- 3. scan workspace for any Model with a Humanoid + the LP's Name in it
    if lp and lp.Name then
        for _, d in ipairs(workspace:GetChildren()) do
            if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid")
               and d.Name == lp.Name then
                return d
            end
        end
    end
    return nil
end

-- ─── Discover the shoot event (best-effort — used only if fireRemote=true) ─
local function findShootEvent()
    local candidates = {
        -- RB5 W5 (from LO's diagnostic)
        { path = "Game.Properties.CharacterAction", actionArg = "Shoot" },
        { path = "MainEvent",                        actionArg = "Shoot" },
        { path = "GameData.ClientEvent",             actionArg = "Shoot" },
        { path = "Game.Properties.ClientEvent",      actionArg = "Shoot" },
        -- RBW4 legacy
        { path = "GameEvents.ClientAction",          actionArg = "Shoot" },
        { path = "Events.ClientAction",              actionArg = "Shoot" },
        { path = "Remotes.ClientAction",             actionArg = "Shoot" },
        { path = "GameEvents.Shoot",                 actionArg = nil    },
        { path = "Shoot",                            actionArg = nil    },
    }
    for _, c in ipairs(candidates) do
        local node = ReplicatedStorage
        for part in c.path:gmatch("[^%.]+") do
            if node then node = node:FindFirstChild(part) end
        end
        if node and node:IsA("RemoteEvent") then
            state.shootEvent     = node
            state.shootEventPath = "RS." .. c.path
            state.shootActionArg = c.actionArg
            return
        end
    end
end

local function probeMeterAttr()
    local char = getChar()
    if not char then return end
    local candidates = {
        "ShotMeter", "ShotBar", "Meter", "Charge", "ChargeBar", "ShootMeter",
        "ShotProgress", "ReleaseTime", "Release", "Power", "ShotPower",
        "ChargeLevel", "ChargePercent", "ShotCharge", "ChargeAmount",
        "ShotPercent", "MeterValue", "Progress", "FillAmount",
    }
    for _, name in ipairs(candidates) do
        if char:GetAttribute(name) ~= nil then
            state.meterAttrName = name
            return
        end
    end
end

-- ─── HUD ───────────────────────────────────────────────────────────
local allDrawings = {}
local function newDraw(k)
    local d = Drawing.new(k)
    table.insert(allDrawings, d)
    return d
end

local hud = {}
hud.bg = newDraw("Square")
hud.bg.Color = Color3.fromRGB(12, 14, 18); hud.bg.Filled = true
hud.bg.Transparency = 0.92; hud.bg.ZIndex = 998; hud.bg.Visible = true
hud.bg.Size = Vector2.new(CONFIG.hudW, CONFIG.hudH)
hud.bg.Position = Vector2.new(CONFIG.hudX, CONFIG.hudY)
pcall(function() hud.bg.Corner = 10 end)

hud.accent = newDraw("Square")
hud.accent.Color = Color3.fromRGB(110, 230, 130); hud.accent.Filled = true
hud.accent.Transparency = 1; hud.accent.ZIndex = 999; hud.accent.Visible = true
hud.accent.Size = Vector2.new(4, CONFIG.hudH)
hud.accent.Position = Vector2.new(CONFIG.hudX, CONFIG.hudY)

hud.title = newDraw("Text")
hud.title.Text = "RB5 W5 Auto Green · matcha"
hud.title.Size = 15; hud.title.Font = Drawing.Fonts.SystemBold
hud.title.Color = Color3.fromRGB(240, 240, 245); hud.title.Outline = true
hud.title.ZIndex = 1000; hud.title.Visible = true
hud.title.Position = Vector2.new(CONFIG.hudX + 14, CONFIG.hudY + 8)

local function mkLine(dy)
    local t = newDraw("Text")
    t.Size = 12; t.Font = Drawing.Fonts.Monospace
    t.Color = Color3.fromRGB(210, 215, 220); t.Outline = true
    t.ZIndex = 1000; t.Visible = true
    t.Position = Vector2.new(CONFIG.hudX + 14, CONFIG.hudY + dy)
    return t
end
hud.lineStatus = mkLine(34)
hud.lineTarget = mkLine(52)
hud.lineMeter  = mkLine(70)
hud.lineAttr   = mkLine(88)
hud.lineEvent  = mkLine(106)
hud.lineLast   = mkLine(124)
hud.lineMode   = mkLine(142)
hud.lineHint   = mkLine(162)
hud.lineHint.Color = Color3.fromRGB(140, 150, 160)
hud.lineHint.Size = 10
hud.lineHint.Text = "E=shoot T=toggle [ ]=±.001 F1=diag F3=autodetect F2=close"

local function paintHud()
    if state.closed then return end
    hud.lineStatus.Text = "Status:    " .. (state.enabled and "ARMED" or "OFF") ..
        (state.busy and "  ·  RELEASING" or "")
    hud.lineStatus.Color = state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)

    hud.lineTarget.Text = string.format("Target:    %.3f  (basket≥0.85 · GREEN≥0.93 · brick>1.20)",
        CONFIG.target)
    hud.lineTarget.Color = Color3.fromRGB(255, 200, 80)

    -- meter shows delta during shot, OR raw value at rest (baseline+0)
    local sm = findShotMeterValue()
    local rawNow = sm and type(sm.Value) == "number" and sm.Value or 0
    hud.lineMeter.Text  = string.format("Meter:     raw=%.3f  shot-delta=%.3f", rawNow, state.lastShotMeter)
    hud.lineAttr.Text   = "Meter src: " ..
        (state.meterSourceLabel ~= "" and state.meterSourceLabel or ("char@" .. state.meterAttrName))
    hud.lineEvent.Text  = "RemEvent:  " .. state.shootEventPath
    hud.lineLast.Text   = "Last shot: " .. state.lastResult
    hud.lineMode.Text   = "Mode:      " .. (CONFIG.fireRemote and "keypress + RemoteEvent fire" or "keypress only")

    hud.accent.Color    = state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)
end

local function closeScript()
    state.closed = true
    -- safety: release the key if we're somehow still holding
    pcall(function() keyrelease(CONFIG.shootKey) end)
    for _, d in ipairs(allDrawings) do
        pcall(function() d.Visible = false end)
        pcall(function() d:Remove() end)
    end
    safeNotify("RB5 W5 Auto Green closed", "matcha", 3)
    print("[RB5] closed.")
end

-- ─── Shoot logic ────────────────────────────────────────────────────
-- 1. press F (game opens the shot, ball goes up, meter starts filling)
-- 2. poll character:GetAttribute(state.meterAttrName) every Heartbeat
-- 3. when meter ≥ target, release F (game releases the shot)
-- 4. classify result
local function fireRemoteShot(isStart)
    if not (CONFIG.fireRemote and state.shootEvent) then return end
    pcall(function()
        if state.shootActionArg then
            state.shootEvent:FireServer(state.shootActionArg, isStart)
        else
            state.shootEvent:FireServer(isStart)
        end
    end)
end

local function autoGreenShot()
    if state.busy or not state.enabled then return end
    state.busy = true

    -- IMPORTANT: tap E briefly — DO NOT keep holding it. The script holds
    -- the key for you. If you hold it physically, the OS overrides our
    -- keyrelease and the shot overshoots.
    -- BASELINE: snapshot the meter BEFORE pressing E so we can compute
    -- the *delta* (since ShotMeter retains its prior-shot residual value).
    local baseline = readMeter()
    pcall(function() keypress(CONFIG.shootKey) end)
    fireRemoteShot(true)
    local startedAt = tick()
    local releaseMeter = 0
    local lastNonZero = 0

    while true do
        local rawM = readMeter()
        local m = rawM - baseline   -- delta = how much we've filled this shot
        if m < 0 then m = 0 end     -- meter reset on fresh shot, that's fine
        state.lastShotMeter = m
        if m > 0 then lastNonZero = m end

        -- Release once delta passes target while still in legal band
        if m >= CONFIG.target and m <= CONFIG.overchargeCeiling then
            -- Hammer the release multiple times in case user is also still
            -- holding the physical key — at least one of these should win
            for _ = 1, 3 do
                pcall(function() keyrelease(CONFIG.shootKey) end)
            end
            fireRemoteShot(false)
            releaseMeter = m
            break
        end

        -- Detect "meter peaked and is now falling" — RB5 may auto-decay
        -- past 1.0 back to 0 if you hold too long. Release at the peak.
        if lastNonZero > 0.5 and m < lastNonZero * 0.5 then
            for _ = 1, 3 do
                pcall(function() keyrelease(CONFIG.shootKey) end)
            end
            fireRemoteShot(false)
            releaseMeter = lastNonZero
            break
        end

        if tick() - startedAt > 3 then
            for _ = 1, 3 do
                pcall(function() keyrelease(CONFIG.shootKey) end)
            end
            fireRemoteShot(false)
            releaseMeter = lastNonZero > 0 and lastNonZero or m
            break
        end
        wait(0)
    end

    -- classify
    if releaseMeter >= 0.93 and releaseMeter <= 1.0 then
        state.lastResult = string.format("%.3f  · GREEN", releaseMeter)
    elseif releaseMeter >= 0.85 then
        state.lastResult = string.format("%.3f  · basket", releaseMeter)
    elseif releaseMeter > 1.0 then
        state.lastResult = string.format("%.3f  · OVERCHARGE", releaseMeter)
    elseif releaseMeter == 0 then
        state.lastResult = "0.000 · no meter (hold ball + try again)"
    else
        state.lastResult = string.format("%.3f  · early/miss", releaseMeter)
    end

    wait(0.1)
    state.busy = false
end

-- ─── Diagnostic dump ────────────────────────────────────────────────
local function diagDump()
    print("=== RB5 Auto Green diagnostic ===")
    print("Shoot event candidate:  " .. state.shootEventPath)
    print("Meter attribute name:   " .. state.meterAttrName)
    print("Mode:                   " .. (CONFIG.fireRemote and "keypress + remote" or "keypress only"))
    local char = getChar()
    if char then
        print("--- ALL character attributes ---")
        local n = 0
        for k, v in pairs(char:GetAttributes()) do
            n = n + 1
            print(string.format("  @%s = %s  (%s)", tostring(k), tostring(v), type(v)))
        end
        if n == 0 then print("  (none — hold a ball / get in a match first)") end
    else
        print("getChar() returned nil — spawn into a match first")
    end
    print("--- ReplicatedStorage RemoteEvents (filtered) ---")
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            local n = string.lower(d.Name)
            if n:find("shoot") or n:find("action") or n:find("ball") or n:find("event") or n:find("main") then
                print("  " .. d:GetFullName())
            end
        end
    end
    print("=== end ===")
    safeNotify("Diagnostic dumped to console", "matcha", 3)
end

-- ─── F3: Auto-detect meter ─────────────────────────────────────────
-- Wide scan: snapshots every numeric value across char attrs, char
-- descendants (NumberValue/IntValue/Attributes), PlayerGui descendants
-- (UI Size scales count too!), ball model, and a few RS hotspots.
-- Then taps E and watches which value climbs the most. Whatever wins
-- gets locked in as the meter source.

local function _addSrc(t, label, getter)
    local ok, v = pcall(getter)
    if ok and type(v) == "number" then t[label] = { val = v, get = getter } end
end

local function collectNumericSources()
    local sources = {}
    local char = getChar()
    if char then
        -- char attributes
        for k, _ in pairs(char:GetAttributes()) do
            _addSrc(sources, "char@"..k, function() return char:GetAttribute(k) end)
        end
        -- char descendants
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("NumberValue") or d:IsA("IntValue") then
                _addSrc(sources, "char/"..d:GetFullName():gsub("^.-Character%.",""), function() return d.Value end)
            end
            local ok, attrs = pcall(function() return d:GetAttributes() end)
            if ok and attrs then
                for k, _ in pairs(attrs) do
                    _addSrc(sources, "char#"..d.Name.."@"..k, function() return d:GetAttribute(k) end)
                end
            end
        end
    end
    -- PlayerGui (UI elements may have NumberValue children OR UI sizes that animate)
    local lp = Players.LocalPlayer
    local gui = lp and lp:FindFirstChild("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("NumberValue") or d:IsA("IntValue") then
                _addSrc(sources, "gui/"..d.Name, function() return d.Value end)
            end
            if d:IsA("Frame") or d:IsA("ImageLabel") or d:IsA("TextLabel") or d:IsA("CanvasGroup") then
                -- UI size scale changes during meter animation
                _addSrc(sources, "gui#"..d.Name..".SizeX", function() return d.Size.X.Scale end)
                _addSrc(sources, "gui#"..d.Name..".SizeY", function() return d.Size.Y.Scale end)
            end
        end
    end
    return sources
end

local function autoDetectMeter()
    safeNotify("AutoDetect: scanning + tapping E for 2s — watch console", "matcha", 4)
    print("[RB5] === AUTODETECT METER (wide scan) ===")

    local sources = collectNumericSources()
    local snapCount = 0; for _ in pairs(sources) do snapCount = snapCount + 1 end
    print(string.format("[RB5] snapshot: %d numeric sources tracked", snapCount))
    if snapCount == 0 then
        print("[RB5] NOTHING numeric found at all. Try holding the ball first.")
        return
    end

    -- snapshot
    local before = {}
    for label, src in pairs(sources) do before[label] = src.val end

    -- press E and watch
    pcall(function() keypress(CONFIG.shootKey) end)
    local started = tick()
    local peak = {}
    while tick() - started < 2.0 do
        for label, src in pairs(sources) do
            local ok, cur = pcall(src.get)
            if ok and type(cur) == "number" then
                local delta = cur - (before[label] or 0)
                if delta > (peak[label] or -math.huge) then peak[label] = delta end
            end
        end
        wait(0)
    end
    -- release E (hammer)
    for _ = 1, 3 do
        pcall(function() keyrelease(CONFIG.shootKey) end)
    end

    -- rank by largest positive delta
    -- collect into sortable list
    local ranked = {}
    for k, d in pairs(peak) do
        if d > 0.01 then table.insert(ranked, { label = k, delta = d, from = before[k] }) end
    end
    table.sort(ranked, function(a, b) return a.delta > b.delta end)

    print(string.format("[RB5] top sources that climbed (showing up to 15 of %d):", #ranked))
    for i = 1, math.min(15, #ranked) do
        local r = ranked[i]
        print(string.format("        %s   delta=%+.4f   from=%s",
            r.label, r.delta, tostring(r.from)))
    end

    local best = ranked[1]
    if best then
        state.meterSource = sources[best.label]
        state.meterSourceLabel = best.label
        print(string.format("[RB5] METER LOCKED IN: %s  (rose by %.3f)", best.label, best.delta))
        safeNotify("Meter locked: " .. best.label, "matcha", 5)
    else
        print("[RB5] nothing climbed during keypress(E).")
        print("[RB5] Likely either: keypress not reaching game, OR meter is in a")
        print("[RB5] location we still haven't scanned (try holding ball + retry).")
        safeNotify("AutoDetect found nothing — paste console output", "matcha", 5)
    end
    print("[RB5] === end autodetect ===")
end

-- ─── Hotkeys ────────────────────────────────────────────────────────
spawn(function()
    local prev = {}
    while not state.closed do
        local function edge(k)
            local d = iskeypressed(k)
            local was = prev[k]; prev[k] = d
            return d and not was
        end

        if edge(CONFIG.shootKey) then spawn(autoGreenShot) end
        if edge(CONFIG.toggleKey) then
            state.enabled = not state.enabled
            safeNotify("Auto-green " .. (state.enabled and "ON" or "OFF"), "matcha", 1.5)
        end
        if edge(CONFIG.tuneUpKey)      then CONFIG.target = math.min(1.20, CONFIG.target + 0.001) end
        if edge(CONFIG.tuneDownKey)    then CONFIG.target = math.max(0.50, CONFIG.target - 0.001) end
        if edge(CONFIG.tuneCoarseUp)   then CONFIG.target = math.min(1.20, CONFIG.target + 0.01) end
        if edge(CONFIG.tuneCoarseDown) then CONFIG.target = math.max(0.50, CONFIG.target - 0.01) end
        if edge(CONFIG.diagKey)        then diagDump() end
        if edge(0x72) and (tick() - state.lastDetectAt) > 3 then         -- F3 = autodetect (3s debounce)
            state.lastDetectAt = tick()
            spawn(autoDetectMeter)
        end
        if edge(CONFIG.closeKey)       then closeScript(); return end

        wait(0.008)
    end
end)

-- ─── Live meter readout for HUD ─────────────────────────────────────
spawn(function()
    while not state.closed do
        if not state.busy then
            state.lastShotMeter = readMeter()
        end
        paintHud()
        wait(0.05)
    end
end)

-- ─── Init ───────────────────────────────────────────────────────────
findShootEvent()
probeMeterAttr()

-- Safe CharacterAdded re-probe (Matcha may not expose this signal)
pcall(function()
    LP.CharacterAdded:Connect(function()
        wait(0.5)
        probeMeterAttr()
    end)
end)

-- Periodic re-probe of meter attr in case it only appears mid-shot.
-- ALSO: when the character first appears, dump every attribute it has so
-- we can see what RB5 W5 actually names the meter.
local _dumpedAttrs = false
spawn(function()
    while not state.closed do
        probeMeterAttr()
        local char = getChar()
        if char and not _dumpedAttrs then
            local count = 0
            for k, v in pairs(char:GetAttributes()) do
                if not _dumpedAttrs then
                    print("[RB5] character attribute discovered:")
                    _dumpedAttrs = true
                end
                count = count + 1
                print(string.format("        @%s = %s  (%s)", tostring(k), tostring(v), type(v)))
            end
            if _dumpedAttrs then
                print(string.format("[RB5] %d attributes total — meter probe matched: %s", count, state.meterAttrName))
            end
        end
        wait(2)
    end
end)

safeNotify(string.format("RB5 W5 armed · target=%.3f", CONFIG.target), "matcha", 4)
print(string.format("[RB5] armed. target=%.3f  event=%s  attr=%s",
    CONFIG.target, state.shootEventPath, state.meterAttrName))
print("[RB5] E=shoot · T=toggle · [ ]=±.001 · - +=±.01 · F1=diag · F2=close")
