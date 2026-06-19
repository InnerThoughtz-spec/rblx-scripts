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
    target            = 0.96,   -- ShotMeter value to release at
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
}

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

local function safeNotify(m, t, d)
    if notify then pcall(function() notify(m, t, d) end) end
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
    local char = LP.Character
    if not char then return end
    local candidates = { "ShotMeter", "ShotBar", "Meter", "Charge", "ChargeBar", "ShootMeter", "ShotProgress", "ReleaseTime" }
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
hud.lineHint.Text = "E=shoot T=toggle [ ]=±.001 -/+=±.01 F1=diag F2=close"

local function paintHud()
    if state.closed then return end
    hud.lineStatus.Text = "Status:    " .. (state.enabled and "ARMED" or "OFF") ..
        (state.busy and "  ·  RELEASING" or "")
    hud.lineStatus.Color = state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)

    hud.lineTarget.Text = string.format("Target:    %.3f  (basket≥0.85 · GREEN≥0.93 · brick>1.20)",
        CONFIG.target)
    hud.lineTarget.Color = Color3.fromRGB(255, 200, 80)

    hud.lineMeter.Text  = string.format("Meter now: %.3f", state.lastShotMeter)
    hud.lineAttr.Text   = "Attr:      char." .. state.meterAttrName
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

    local char = LP.Character
    if not char then state.busy = false; return end

    -- IMPORTANT: tap E briefly — DO NOT keep holding it. The script holds
    -- the key for you. If you hold it physically, the OS overrides our
    -- keyrelease and the shot overshoots.
    pcall(function() keypress(CONFIG.shootKey) end)
    fireRemoteShot(true)
    local startedAt = tick()
    local releaseMeter = 0
    local lastNonZero = 0

    while true do
        local m = char:GetAttribute(state.meterAttrName) or 0
        if type(m) ~= "number" then m = 0 end
        state.lastShotMeter = m
        if m > 0 then lastNonZero = m end

        -- Release once meter passes target while still in legal band
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
        RunService.Heartbeat:Wait()
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
    local char = LP.Character
    if char then
        print("--- ALL character attributes ---")
        local n = 0
        for k, v in pairs(char:GetAttributes()) do
            n = n + 1
            print(string.format("  @%s = %s  (%s)", tostring(k), tostring(v), type(v)))
        end
        if n == 0 then print("  (none — hold a ball / get in a match first)") end
    else
        print("LP.Character is nil — spawn into a match first")
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
        if edge(CONFIG.closeKey)       then closeScript(); return end

        wait(0.008)
    end
end)

-- ─── Live meter readout for HUD ─────────────────────────────────────
spawn(function()
    while not state.closed do
        local char = LP.Character
        if char and not state.busy then
            local m = char:GetAttribute(state.meterAttrName)
            if type(m) == "number" then state.lastShotMeter = m else state.lastShotMeter = 0 end
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
        local char = LP.Character
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
