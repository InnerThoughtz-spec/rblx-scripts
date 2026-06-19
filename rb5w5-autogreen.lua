-- RB5 World 5 Auto Green // Matcha external
-- METER-BASED — polls the character's ShotMeter attribute and releases at
-- the configured target. This is the correct RB-series mechanic
-- (reverse-engineered from RBW4 reference: timer=0.85 means meter>=0.85).
--
-- 0.85   = basket (LO confirmed this hits but not perfect)
-- 0.93+  = perfect green (community-typical for RB5 W5)
-- 1.00   = top of bar (anything over 1.2 = overcharge / brick)
--
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/refs/heads/main/rb5w5-autogreen.lua"))()

local CONFIG = {
    target            = 0.96,   -- ShotMeter value to release at (the perfect-green zone)
    overchargeCeiling = 1.20,   -- anything past this = brick

    shootKey          = 0x46,   -- F (the RBW4 reference uses F; change to 0x45 for E)
    toggleKey         = 0x54,   -- T
    tuneUpKey         = 0xDD,   -- ]  → target +0.001
    tuneDownKey       = 0xDB,   -- [  → target -0.001
    tuneCoarseUp      = 0xBB,   -- =  → target +0.01
    tuneCoarseDown    = 0xBD,   -- -  → target -0.01
    closeKey          = 0x71,   -- F2
    diagKey           = 0x70,   -- F1 (dump found events / attributes)

    hudX = 20, hudY = 260, hudW = 340, hudH = 168,
}

local state = {
    enabled       = true,
    closed        = false,
    lastShotMeter = 0,
    lastFireOk    = false,
    lastResult    = "—",
    shootEvent    = nil,    -- discovered RemoteEvent for "Shoot"
    shootEventPath= "—",
    meterAttrName = "ShotMeter",
    busy          = false,
}

-- ─── Services ───────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

local function safeNotify(m, t, d)
    if notify then pcall(function() notify(m, t, d) end) end
end

-- ─── Find the Shoot remote event ────────────────────────────────────
-- RBW4 used ReplicatedStorage.GameEvents.ClientAction (RemoteEvent, args: "Shoot", bool)
-- RB5 may have moved/renamed it. Probe known paths first, then fall back to a scan.
local function findShootEvent()
    local candidates = {
        { path = "GameEvents.ClientAction", remote = "ClientAction", actionArg = "Shoot" },
        { path = "Events.ClientAction",     remote = "ClientAction", actionArg = "Shoot" },
        { path = "Remotes.ClientAction",    remote = "ClientAction", actionArg = "Shoot" },
        { path = "GameEvents.Shoot",        remote = "Shoot",         actionArg = nil    },
        { path = "Events.Shoot",            remote = "Shoot",         actionArg = nil    },
        { path = "Remotes.Shoot",           remote = "Shoot",         actionArg = nil    },
        { path = "Shoot",                   remote = "Shoot",         actionArg = nil    },
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

    -- Generic scan: any RemoteEvent named ClientAction / Shoot / BallAction
    local scanNames = { ClientAction = "Shoot", Shoot = nil, BallAction = "Shoot", ShootAction = nil }
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and scanNames[d.Name] ~= nil then
            state.shootEvent     = d
            state.shootEventPath = d:GetFullName()
            state.shootActionArg = scanNames[d.Name]
            return
        end
    end
end

-- ─── Find the ShotMeter attribute ───────────────────────────────────
-- RBW4 char attribute "ShotMeter". RB5 might rename.
local function probeMeterAttr()
    local char = LP.Character
    if not char then return end
    local candidates = { "ShotMeter", "ShotBar", "Meter", "Charge", "ChargeBar", "ShootMeter", "ShotProgress" }
    for _, name in ipairs(candidates) do
        if char:GetAttribute(name) ~= nil then
            state.meterAttrName = name
            return
        end
    end
end

-- ─── HUD ────────────────────────────────────────────────────────────
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
hud.lineEvent  = mkLine(88)
hud.lineAttr   = mkLine(106)
hud.lineLast   = mkLine(124)
hud.lineHint   = mkLine(146)
hud.lineHint.Color = Color3.fromRGB(140, 150, 160)
hud.lineHint.Size = 10
hud.lineHint.Text = "F=shoot T=toggle [ ]=±.001 -/+=±.01 F1=diag F2=close"

local function paintHud()
    if state.closed then return end
    hud.lineStatus.Text = "Status:    " .. (state.enabled and "ARMED" or "OFF") ..
        (state.busy and "  ·  RELEASING" or "")
    hud.lineStatus.Color = state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)

    hud.lineTarget.Text = string.format("Target:    %.3f  (basket≥0.85 · perfect≈0.93–0.99 · brick>1.20)",
        CONFIG.target)
    hud.lineTarget.Color = Color3.fromRGB(255, 200, 80)

    hud.lineMeter.Text  = string.format("Meter now: %.3f", state.lastShotMeter)
    hud.lineEvent.Text  = "Event:     " .. state.shootEventPath
    hud.lineAttr.Text   = "Attr:      char." .. state.meterAttrName
    hud.lineLast.Text   = "Last shot: " .. state.lastResult
    hud.accent.Color    = state.enabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)
end

local function closeScript()
    state.closed = true
    for _, d in ipairs(allDrawings) do
        pcall(function() d.Visible = false end)
        pcall(function() d:Remove() end)
    end
    safeNotify("RB5 W5 Auto Green closed", "matcha", 3)
    print("[RB5] closed.")
end

-- ─── Shoot mechanic ─────────────────────────────────────────────────
-- 1. fire ClientAction("Shoot", true)
-- 2. poll character:GetAttribute(state.meterAttrName) every RenderStep
-- 3. when meter >= target, fire ClientAction("Shoot", false)
-- 4. log the meter value at release as the result
local function fireShoot(isStart)
    if not state.shootEvent then return false end
    local ok
    if state.shootActionArg then
        ok = pcall(function() state.shootEvent:FireServer(state.shootActionArg, isStart) end)
    else
        ok = pcall(function() state.shootEvent:FireServer(isStart) end)
    end
    return ok
end

local function autoGreenShot()
    if state.busy or not state.enabled then return end
    if not state.shootEvent then
        safeNotify("Shoot event not found — press F1 for diag", "matcha", 3)
        return
    end
    state.busy = true

    local char = LP.Character
    if not char then state.busy = false; return end

    fireShoot(true)
    local startedAt = tick()
    local releaseMeter = 0
    while true do
        local m = char:GetAttribute(state.meterAttrName) or 0
        state.lastShotMeter = m
        if m >= CONFIG.target and m <= CONFIG.overchargeCeiling then
            fireShoot(false)
            releaseMeter = m
            break
        end
        if tick() - startedAt > 3 then
            -- safety: bail if meter never reaches target (e.g. shot got cancelled)
            fireShoot(false)
            releaseMeter = m
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
    else
        state.lastResult = string.format("%.3f  · early/miss", releaseMeter)
    end

    wait(0.08)
    state.busy = false
end

-- ─── Diagnostic dump ────────────────────────────────────────────────
local function diagDump()
    print("=== RB5 Auto Green diagnostic ===")
    print("Shoot event candidate:  " .. state.shootEventPath)
    print("Meter attribute name:   " .. state.meterAttrName)
    local char = LP.Character
    if char then
        print("--- Character attributes (numeric) ---")
        for k, v in pairs(char:GetAttributes()) do
            if type(v) == "number" then
                print(string.format("  @%s = %s", tostring(k), tostring(v)))
            end
        end
    end
    print("--- ReplicatedStorage top-level RemoteEvents ---")
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            local n = string.lower(d.Name)
            if n:find("shoot") or n:find("action") or n:find("ball") or n:find("event") then
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
        if edge(CONFIG.toggleKey) then state.enabled = not state.enabled end
        if edge(CONFIG.tuneUpKey)    then CONFIG.target = math.min(1.20, CONFIG.target + 0.001) end
        if edge(CONFIG.tuneDownKey)  then CONFIG.target = math.max(0.50, CONFIG.target - 0.001) end
        if edge(CONFIG.tuneCoarseUp) then CONFIG.target = math.min(1.20, CONFIG.target + 0.01) end
        if edge(CONFIG.tuneCoarseDown) then CONFIG.target = math.max(0.50, CONFIG.target - 0.01) end
        if edge(CONFIG.diagKey)   then diagDump() end
        if edge(CONFIG.closeKey)  then closeScript(); return end

        wait(0.008)
    end
end)

-- ─── Background meter readout (for live HUD) ────────────────────────
spawn(function()
    while not state.closed do
        local char = LP.Character
        if char and not state.busy then
            local m = char:GetAttribute(state.meterAttrName)
            if type(m) == "number" then state.lastShotMeter = m end
        end
        paintHud()
        wait(0.05)
    end
end)

-- ─── Init: rediscover event + attr on each respawn ──────────────────
findShootEvent()
probeMeterAttr()

LP.CharacterAdded:Connect(function()
    wait(0.5)
    probeMeterAttr()
end)

if not state.shootEvent then
    safeNotify("Shoot event not auto-found — press F1 for diagnostic", "matcha", 5)
    print("[RB5] WARN: no shoot RemoteEvent found. Press F1 to dump candidates.")
else
    safeNotify(string.format("RB5 W5 armed · target=%.3f · event=%s", CONFIG.target, state.shootEventPath), "matcha", 4)
end
print(string.format("[RB5] armed. target=%.3f  event=%s  attr=%s",
    CONFIG.target, state.shootEventPath, state.meterAttrName))
print("[RB5] F=shoot · T=toggle · [ ]=±.001 · - +=±.01 · F1=diag · F2=close")
