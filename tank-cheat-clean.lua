-- TANK CHEAT // fully deobfuscated source
-- Reconstructed from the XOR + control-flow-flattening obfuscation.
-- Same behavior, every identifier renamed to its role.

local Players = game:GetService("Players")

-- ────────────────────────────────────────────────────────────────────
-- PATCH_TARGETS — the heart of the cheat.
-- For each entry, the patcher walks every alive player's tank chassis
-- looking for instances (NumberValue / IntValue) whose Name appears in
-- `names`. When found, the original .Value is cached in `origPatched`
-- and the live value is overwritten with `target`. On cleanup the
-- originals are restored from `origPatched`.
-- ────────────────────────────────────────────────────────────────────
local PATCH_TARGETS = {
    Penetration = {
        target      = 9999,
        active      = true,                       -- DEFAULT ON
        patched     = {},                         -- [Instance] = true
        origPatched = {},                         -- [Instance] = origValue
        names       = { "Penetration", "Penetrate" },
    },
    Ricochet = {
        target      = 9999,
        active      = false,
        patched     = {},
        origPatched = {},
        names       = { "RicochetAngle" },
    },
    BulletGravity = {
        target      = 0,
        active      = false,
        patched     = {},
        origPatched = {},
        names       = { "BulletGravity" },
    },
    ShellSpeed = {
        target      = 9999,
        active      = false,
        patched     = {},
        origPatched = {},
        names       = { "ShellSpeed" },
    },
}

-- Per-player state: { esp = {Box, Bar, Text}, cache = {} }
local playerState = {}

-- ────────────────────────────────────────────────────────────────────
-- ESP DRAWING FACTORY
-- ────────────────────────────────────────────────────────────────────
local function CreateBoxes()
    local box = Drawing.new("Square")
    box.Visible   = false
    box.Thickness = 3
    box.Color     = Color3.fromRGB(0, 0, 0)
    box.Filled    = false

    local bar = Drawing.new("Square")
    bar.Visible   = false
    bar.Thickness = 1.5
    bar.Color     = Color3.fromRGB(255, 38, 38)
    bar.Filled    = false

    local txt = Drawing.new("Text")
    txt.Visible = false
    txt.Color   = Color3.fromRGB(255, 38, 38)
    txt.Outline = true

    return { Box = box, Bar = bar, Text = txt }
end

local function HideBoxes(e)
    if not e then return end
    pcall(function() e.Box.Visible  = false end)
    pcall(function() e.Bar.Visible  = false end)
    pcall(function() e.Text.Visible = false end)
end

local function DestroyBoxes(e)
    if not e then return end
    for _, d in pairs(e) do
        pcall(function()
            d.Visible = false
            d:Remove()
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────
-- TANK / PLAYER STATE
-- ────────────────────────────────────────────────────────────────────
local function IsAlive(player)
    local ok, char = pcall(function() return player.Character end)
    return ok and char ~= nil
end

local function GetVehiclesFolder()
    return workspace:FindFirstChild("Vehicles")
end

local function GetChassis(player)
    local v = GetVehiclesFolder()
    return v and v:FindFirstChild(player.Name)
end

local function GetTankModel(player)
    local c = GetChassis(player)
    return c and c:FindFirstChild("Tank")
end

local function GetTankHull(player)
    local t = GetTankModel(player)
    return t and t:FindFirstChild("Hull")
end

-- ────────────────────────────────────────────────────────────────────
-- PROPERTY PATCHER
-- For each active PATCH_TARGET, recurse the player's chassis looking
-- for NumberValue / IntValue instances whose Name matches any entry in
-- `names`. Snapshot the original value, then overwrite with `target`.
-- ────────────────────────────────────────────────────────────────────
local function isPatchableValue(inst)
    return inst:IsA("NumberValue") or inst:IsA("IntValue")
        or inst:IsA("NumberConstrainedValue")
end

local function RefreshCache(player)
    local chassis = GetChassis(player)
    if not chassis then return end

    for _, target in pairs(PATCH_TARGETS) do
        if target.active then
            -- name → true lookup for O(1) match
            local nameSet = {}
            for _, n in ipairs(target.names) do nameSet[n] = true end

            for _, inst in ipairs(chassis:GetDescendants()) do
                if nameSet[inst.Name] and isPatchableValue(inst) then
                    if target.origPatched[inst] == nil then
                        target.origPatched[inst] = inst.Value
                    end
                    pcall(function() inst.Value = target.target end)
                    target.patched[inst] = true
                end
            end
        end
    end
end

local function InvalidateCache()
    for _, target in pairs(PATCH_TARGETS) do
        for inst in pairs(target.patched) do
            if target.origPatched[inst] ~= nil then
                pcall(function() inst.Value = target.origPatched[inst] end)
            end
        end
        target.patched     = {}
        target.origPatched = {}
    end
end

local function CompleteClear(player)
    local s = playerState[player.UserId]
    if not s then return end
    DestroyBoxes(s.esp)
    playerState[player.UserId] = nil
end

-- ────────────────────────────────────────────────────────────────────
-- PER-PLAYER FRAME UPDATE — patch + ESP
-- ────────────────────────────────────────────────────────────────────
local function ProcessPlayer(player, esp, localPlayer)
    if not IsAlive(player) then HideBoxes(esp); return end

    -- the patcher runs for every player (including the LP) so any tank
    -- you control gets your shells patched, and every enemy's shells get
    -- the same numeric values
    RefreshCache(player)

    -- ESP only for non-self
    if player == localPlayer then HideBoxes(esp); return end

    local tank = GetTankModel(player)
    local hull = GetTankHull(player)
    if not (tank and hull) then HideBoxes(esp); return end

    local Camera = workspace.CurrentCamera
    local head   = hull.Position + Vector3.new(0, hull.Size.Y / 2, 0)
    local foot   = hull.Position - Vector3.new(0, hull.Size.Y,     0)
    local sH, vH = Camera:WorldToViewportPoint(head)
    local sF, vF = Camera:WorldToViewportPoint(foot)
    if not (vH or vF) then HideBoxes(esp); return end

    local h    = math.abs(sH.Y - sF.Y)
    local w    = h / 1.5
    local boxX = sH.X - w / 2
    local boxY = sH.Y - 20

    esp.Box.Position = Vector2.new(boxX, boxY)
    esp.Box.Size     = Vector2.new(w * 2, h)
    esp.Box.Visible  = true

    esp.Bar.Position = Vector2.new(boxX, boxY)
    esp.Bar.Size     = Vector2.new(w * 2, h)
    esp.Bar.Visible  = true

    local lpRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if lpRoot then
        -- the original divides by 3.571... which is studs→meters
        local distMeters = (head - lpRoot.Position).Magnitude / 3.5714285710000002
        esp.Text.Text     = player.Name .. "\n" .. string.format("%dm", distMeters)
        esp.Text.Position = Vector2.new(boxX + w, boxY - 20)
        esp.Text.Visible  = true
    end
end

local function ProcessPlayers()
    local lp = Players.LocalPlayer
    for _, p in pairs(Players:GetPlayers()) do
        local s = playerState[p.UserId]
        if not s then
            s = { esp = CreateBoxes(), cache = {} }
            playerState[p.UserId] = s
        end
        ProcessPlayer(p, s.esp, lp)
    end
end

local function CleanupDisconnectedPlayers()
    local active = {}
    for _, p in pairs(Players:GetPlayers()) do active[p.UserId] = true end
    for uid, s in pairs(playerState) do
        if not active[uid] then
            DestroyBoxes(s.esp)
            playerState[uid] = nil
        end
    end
end

local function HideAllEsp()
    for _, s in pairs(playerState) do HideBoxes(s.esp) end
end

-- ────────────────────────────────────────────────────────────────────
-- PLAYER REMOVING — disconnect cleanup
-- ────────────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(p) CompleteClear(p) end)

-- ────────────────────────────────────────────────────────────────────
-- MAIN LOOP — the bottom while-Vd block in the obfuscated source.
-- Runs every frame:
--   • Process all players (patch + draw ESP)
--   • Every 5s, cleanup disconnected players
--   • Every 10s, a full refresh pass (unused timer in original; kept)
-- ────────────────────────────────────────────────────────────────────
spawn(function()
    local lastSlow = 0
    local lastFast = 0
    while true do
        local now = tick()
        if not Players.LocalPlayer then
            HideAllEsp()
            wait()
        else
            ProcessPlayers()
            if now - lastFast > 5 then
                CleanupDisconnectedPlayers()
                lastFast = now
            end
            if now - lastSlow > 10 then
                lastSlow = now
            end
            wait()
        end
    end
end)
