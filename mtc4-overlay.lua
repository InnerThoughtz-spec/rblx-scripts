-- MTC4 Property Patcher // Matcha external
-- Inf-pen, no-ricochet, flat-trajectory, infinite-shell-speed
-- Same scan/overwrite trick the obfuscated tank cheat uses, applied
-- against MTC4's ReplicatedStorage.TankInfo + workspace vehicle paths.
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/refs/heads/main/mtc4-overlay.lua"))()

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer
local mouse             = LP:GetMouse()

-- ────────────────────────────────────────────────────────────────────
-- PATCH_TARGETS — values get scanned + overwritten every refresh tick
-- ────────────────────────────────────────────────────────────────────
local PATCH_TARGETS = {
    Penetration = {
        target      = 9999,
        active      = true,
        patched     = {}, origPatched = {},
        names       = { "Penetration", "Penetrate", "Pen" },
    },
    Ricochet = {
        target      = 9999,
        active      = true,
        patched     = {}, origPatched = {},
        names       = { "RicochetAngle", "Ricochet", "RicoAngle" },
    },
    BulletGravity = {
        target      = 0,
        active      = true,
        patched     = {}, origPatched = {},
        names       = { "BulletGravity", "Gravity", "ShellGravity" },
    },
    ShellSpeed = {
        target      = 9999,
        active      = true,
        patched     = {}, origPatched = {},
        names       = { "ShellSpeed", "MuzzleVelocity", "Velocity", "ShellVel" },
    },
    -- bonus: also smash any obvious damage / reload values we encounter
    Damage = {
        target      = 9999,
        active      = false,
        patched     = {}, origPatched = {},
        names       = { "Damage", "BaseDamage", "Dmg" },
    },
    Reload = {
        target      = 0.1,
        active      = false,
        patched     = {}, origPatched = {},
        names       = { "ReloadTime", "Reload" },
    },
}

local state = {
    closed = false, minimized = false,
    refreshInterval = 1.0,
    lastScanCount = 0,
    lastApplyTick = 0,
    scanRoots = {},      -- live list of Instances to scan each pass
}

-- ────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────
local function safeNotify(msg, title, dur)
    if notify then pcall(function() notify(msg, title, dur) end) end
end
local function setCorner(d, r) pcall(function() d.Corner = r end) end

local function isPatchableValue(inst)
    return inst:IsA("NumberValue") or inst:IsA("IntValue")
        or inst:IsA("NumberConstrainedValue")
end

-- Also let us flip numeric Attributes (MTC4 may store stats as attributes)
local function flipAttribute(inst, attrName, target)
    local v = inst:GetAttribute(attrName)
    if type(v) == "number" then
        local key = inst:GetFullName() .. ":" .. attrName
        return v, function() pcall(function() inst:SetAttribute(attrName, target) end) end, key
    end
    return nil
end

-- ────────────────────────────────────────────────────────────────────
-- Scan roots — where the cheat looks for values to patch
-- ────────────────────────────────────────────────────────────────────
local function buildScanRoots()
    local roots = {}
    -- 1. ReplicatedStorage.TankInfo (your earlier intel)
    local ti = ReplicatedStorage:FindFirstChild("TankInfo")
    if ti then table.insert(roots, ti) end

    -- 2. Any other ReplicatedStorage children with shell/projectile-ish names
    for _, child in ipairs(ReplicatedStorage:GetChildren()) do
        local n = string.lower(child.Name)
        if n:find("shell") or n:find("ammo") or n:find("projectile")
           or n:find("weapon") or n:find("gun") then
            table.insert(roots, child)
        end
    end

    -- 3. LP's own vehicle in workspace, if reachable
    local vehFolder = workspace:FindFirstChild("Vehicles")
                   or workspace:FindFirstChild("Tanks")
                   or workspace:FindFirstChild("Vehicle")
    if vehFolder then
        for _, m in ipairs(vehFolder:GetChildren()) do
            -- match by player name OR by anything seated by LP
            if m.Name == LP.Name then
                table.insert(roots, m)
            else
                -- recursive seat check
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("VehicleSeat") and d.Occupant
                       and d.Occupant.Parent == LP.Character then
                        table.insert(roots, m)
                        break
                    end
                end
            end
        end
    end

    -- 4. Any tank model in workspace whose name appears in TankInfo
    if ti then
        local tankNames = {}
        for _, t in ipairs(ti:GetChildren()) do tankNames[t.Name] = true end
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and tankNames[d.Name] then
                table.insert(roots, d)
            end
        end
    end

    state.scanRoots = roots
end

-- ────────────────────────────────────────────────────────────────────
-- The patcher: walk each root, find matching values, overwrite them,
-- cache originals for restore on cleanup.
-- ────────────────────────────────────────────────────────────────────
local function applyPatches()
    local count = 0
    for _, root in ipairs(state.scanRoots) do
        if root and root.Parent then
            for _, target in pairs(PATCH_TARGETS) do
                if target.active then
                    local nameSet = {}
                    for _, n in ipairs(target.names) do
                        nameSet[n] = true
                        nameSet[string.lower(n)] = true
                    end

                    for _, inst in ipairs(root:GetDescendants()) do
                        -- value-instance match (NumberValue / IntValue)
                        if nameSet[inst.Name] and isPatchableValue(inst) then
                            if target.origPatched[inst] == nil then
                                target.origPatched[inst] = inst.Value
                            end
                            pcall(function() inst.Value = target.target end)
                            target.patched[inst] = true
                            count = count + 1
                        end
                        -- attribute match (any instance can have numeric attributes)
                        for _, name in ipairs(target.names) do
                            local av = inst:GetAttribute(name)
                            if type(av) == "number" then
                                local key = "attr:" .. tostring(inst) .. ":" .. name
                                if target.origPatched[key] == nil then
                                    target.origPatched[key] = av
                                end
                                pcall(function() inst:SetAttribute(name, target.target) end)
                                target.patched[key] = { inst = inst, attr = name }
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end
    state.lastScanCount = count
end

local function restoreAll()
    for _, target in pairs(PATCH_TARGETS) do
        for k, v in pairs(target.patched) do
            if type(k) == "string" and type(v) == "table" then
                -- attribute restore
                local orig = target.origPatched[k]
                if orig ~= nil and v.inst and v.inst.Parent then
                    pcall(function() v.inst:SetAttribute(v.attr, orig) end)
                end
            else
                -- value-instance restore
                local inst = k
                local orig = target.origPatched[inst]
                if orig ~= nil and inst and inst.Parent then
                    pcall(function() inst.Value = orig end)
                end
            end
        end
        target.patched     = {}
        target.origPatched = {}
    end
end

-- ────────────────────────────────────────────────────────────────────
-- Minimal HUD — status panel + hotkeys to toggle each target
-- ────────────────────────────────────────────────────────────────────
local hud, allDrawings = {}, {}
local function newDraw(kind)
    local d = Drawing.new(kind)
    table.insert(allDrawings, d)
    return d
end

local HUD_X, HUD_Y, HUD_W = 20, 20, 280

hud.bg = newDraw("Square")
hud.bg.Color = Color3.fromRGB(12, 14, 18); hud.bg.Filled = true
hud.bg.Transparency = 0.86; hud.bg.ZIndex = 10; hud.bg.Visible = true
hud.bg.Size = Vector2.new(HUD_W, 168)
hud.bg.Position = Vector2.new(HUD_X, HUD_Y)
setCorner(hud.bg, 10)

hud.accent = newDraw("Square")
hud.accent.Color = Color3.fromRGB(110, 230, 130); hud.accent.Filled = true
hud.accent.Transparency = 1; hud.accent.ZIndex = 11; hud.accent.Visible = true
hud.accent.Size = Vector2.new(4, 168)
hud.accent.Position = Vector2.new(HUD_X, HUD_Y)

hud.title = newDraw("Text")
hud.title.Text = "MTC4 PATCHER · matcha"
hud.title.Size = 15; hud.title.Font = Drawing.Fonts.SystemBold
hud.title.Color = Color3.fromRGB(240, 240, 245)
hud.title.ZIndex = 12; hud.title.Visible = true
hud.title.Position = Vector2.new(HUD_X + 14, HUD_Y + 8)

local function mkLine(dy, init)
    local t = newDraw("Text")
    t.Size = 12; t.Font = Drawing.Fonts.Monospace
    t.Color = Color3.fromRGB(210, 215, 220)
    t.ZIndex = 12; t.Visible = true
    t.Position = Vector2.new(HUD_X + 14, HUD_Y + dy)
    t.Text = init or ""
    return t
end

hud.linePen  = mkLine(32, "")
hud.lineRic  = mkLine(48, "")
hud.lineGrav = mkLine(64, "")
hud.lineSpd  = mkLine(80, "")
hud.lineDmg  = mkLine(96, "")
hud.lineRld  = mkLine(112, "")
hud.lineStat = mkLine(132, "")
hud.lineHint = mkLine(150, "1/2/3/4 toggle · 5/6 dmg/reload · R refresh · X close")
hud.lineHint.Color = Color3.fromRGB(130, 140, 150)
hud.lineHint.Size = 10

local function paintHud()
    if state.closed then return end
    local function lineFor(name, ln, label)
        local t = PATCH_TARGETS[name]
        if t.active then
            ln.Text = string.format("%-13s ON  → %s", label, tostring(t.target))
            ln.Color = Color3.fromRGB(110, 230, 130)
        else
            ln.Text = string.format("%-13s OFF", label)
            ln.Color = Color3.fromRGB(180, 110, 110)
        end
    end
    lineFor("Penetration",   hud.linePen,  "1 PEN")
    lineFor("Ricochet",      hud.lineRic,  "2 RICO")
    lineFor("BulletGravity", hud.lineGrav, "3 GRAV")
    lineFor("ShellSpeed",    hud.lineSpd,  "4 SPD")
    lineFor("Damage",        hud.lineDmg,  "5 DMG")
    lineFor("Reload",        hud.lineRld,  "6 RLD")
    hud.lineStat.Text = string.format("PATCHED: %d values  · roots: %d",
        state.lastScanCount, #state.scanRoots)
    hud.lineStat.Color = Color3.fromRGB(180, 220, 255)
end

local function closeScript()
    state.closed = true
    restoreAll()
    for _, d in ipairs(allDrawings) do
        pcall(function() d.Visible = false end)
        pcall(function() d:Remove() end)
    end
    safeNotify("MTC4 patcher closed (values restored)", "matcha", 3)
    print("[MTC4P] closed.")
end

-- ────────────────────────────────────────────────────────────────────
-- Hotkeys
-- ────────────────────────────────────────────────────────────────────
local KEYS = {
    [0x31] = "Penetration",   [0x32] = "Ricochet",
    [0x33] = "BulletGravity", [0x34] = "ShellSpeed",
    [0x35] = "Damage",        [0x36] = "Reload",
}

spawn(function()
    local prev = {}
    while not state.closed do
        for k, name in pairs(KEYS) do
            local d = iskeypressed(k)
            if d and not prev[k] then
                PATCH_TARGETS[name].active = not PATCH_TARGETS[name].active
                if not PATCH_TARGETS[name].active then
                    -- restore JUST this target's snapshots
                    for inst, _ in pairs(PATCH_TARGETS[name].patched) do
                        local orig = PATCH_TARGETS[name].origPatched[inst]
                        if type(inst) ~= "string" and orig ~= nil and inst.Parent then
                            pcall(function() inst.Value = orig end)
                        end
                    end
                    PATCH_TARGETS[name].patched = {}
                    PATCH_TARGETS[name].origPatched = {}
                end
                safeNotify(name .. " " .. (PATCH_TARGETS[name].active and "ON" or "OFF"), "matcha", 1.5)
            end
            prev[k] = d
        end
        -- R = force refresh
        local r = iskeypressed(0x52)
        if r and not prev[0x52] then
            buildScanRoots()
            applyPatches()
            safeNotify(string.format("Manual refresh · %d values", state.lastScanCount), "matcha", 2)
        end
        prev[0x52] = r
        -- X = close
        local x = iskeypressed(0x58)
        if x and not prev[0x58] then closeScript(); return end
        prev[0x58] = x
        wait(0.05)
    end
end)

-- ────────────────────────────────────────────────────────────────────
-- Main patcher loop — re-scans roots every refreshInterval seconds,
-- re-applies patches (in case the game's networking resets a value
-- after respawn / round-start / shell-fire).
-- ────────────────────────────────────────────────────────────────────
spawn(function()
    buildScanRoots()
    applyPatches()
    while not state.closed do
        local t = tick()
        if t - state.lastApplyTick > state.refreshInterval then
            buildScanRoots()
            applyPatches()
            state.lastApplyTick = t
        end
        paintHud()
        wait(0.1)
    end
end)

-- Restore originals if LP leaves / character resets
LP.CharacterRemoving:Connect(function() restoreAll() end)

safeNotify("MTC4 patcher armed · 1/2/3/4 toggle · R force refresh · X close", "matcha", 5)
print("[MTC4P] armed. PATCH_TARGETS hot — scanning ReplicatedStorage.TankInfo + LP vehicle.")
