-- MTC4 Overlay // Matcha external (Multicrew Tank Combat 4)
-- ESP + aim assist + weak-point hint + range readout
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/refs/heads/main/mtc4-overlay.lua"))()

-- ─── Config ─────────────────────────────────────────────────────────
local CONFIG = {
    -- features
    espEnabled         = true,
    aimEnabled         = true,
    weakPointHint      = true,
    showHealthBars     = true,
    showDistance       = true,
    showLines          = false,    -- snap-line from screen-bottom to enemy
    skipTeammates      = true,     -- honor Team property
    maxDistance        = 6000,     -- studs · cull beyond this

    -- aim
    aimKey             = 0x02,     -- VK_RBUTTON · hold right-mouse to aim
    aimSmoothing       = 0.35,     -- 0 = instant, 1 = no movement
    aimFovRadius       = 220,      -- pixels · only consider targets within this radius of crosshair
    aimAtWeakPoint     = true,     -- aim turret ring / commander hatch when known, else HRP

    -- ESP colors
    enemyColor         = { r = 235, g = 70,  b = 70  },
    friendColor        = { r = 90,  g = 200, b = 110 },
    weakPointColor     = { r = 255, g = 200, b = 60  },

    -- hotkeys
    toggleEspKey       = 0x42, -- B
    toggleAimKey       = 0x51, -- Q
    toggleWeakKey      = 0x4A, -- J
    fovUpKey           = 0xDD, -- ]
    fovDownKey         = 0xDB, -- [
    closeKey           = 0x58, -- X
    minimizeKey        = 0x70, -- F1
    restoreKey         = 0x71, -- F2

    -- HUD
    hudX = 20, hudY = 20,
    hudW = 320, hudH = 168,
}

local state = {
    closed = false, minimized = false,
    enemiesSeen = 0,
    currentTarget = nil,
    fov = CONFIG.aimFovRadius,
    aimingNow = false,
}

-- ─── Helpers ────────────────────────────────────────────────────────
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local mouse = LP:GetMouse()
local Camera = workspace.CurrentCamera

-- ─── TankInfo loader ────────────────────────────────────────────────
-- Reads ReplicatedStorage.TankInfo, builds a lookup table:
--   tankData[tankName] = { armor = {hull, turret, side, rear}, weakPoints = {...} }
local tankData = {}
local tankInfoRoot = nil

local function readNumValue(parent, name)
    local v = parent:FindFirstChild(name)
    if v and v:IsA("NumberValue") then return v.Value end
    if v and v:IsA("IntValue") then return v.Value end
    -- attribute fallback
    local a = parent:GetAttribute(name)
    if type(a) == "number" then return a end
    return nil
end

local function readStringValue(parent, name)
    local v = parent:FindFirstChild(name)
    if v and v:IsA("StringValue") then return v.Value end
    local a = parent:GetAttribute(name)
    if type(a) == "string" then return a end
    return nil
end

local function extractTankEntry(node)
    local entry = { name = node.Name, raw = node, armor = {}, weakPoints = {}, weapons = {} }

    -- ModuleScript form: require() and inspect returned table
    if node:IsA("ModuleScript") then
        local ok, data = pcall(require, node)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                local lk = string.lower(tostring(k))
                if type(v) == "number" then
                    entry.armor[lk] = v
                elseif type(v) == "string" then
                    entry.armor[lk] = v
                elseif type(v) == "table" then
                    if lk:find("weak") or lk:find("crit") then
                        for _, partName in pairs(v) do
                            if type(partName) == "string" then
                                table.insert(entry.weakPoints, partName)
                            end
                        end
                    elseif lk:find("armor") or lk:find("plate") then
                        for kk, vv in pairs(v) do entry.armor[string.lower(tostring(kk))] = vv end
                    end
                end
            end
        end
        return entry
    end

    -- Folder / Configuration / Model form: enumerate children & attributes
    for _, c in ipairs(node:GetChildren()) do
        local cname = string.lower(c.Name)
        if c:IsA("NumberValue") or c:IsA("IntValue") then
            entry.armor[cname] = c.Value
        elseif c:IsA("StringValue") then
            entry.armor[cname] = c.Value
        elseif c:IsA("Folder") or c:IsA("Configuration") then
            if cname:find("weak") or cname:find("crit") then
                for _, wp in ipairs(c:GetChildren()) do
                    table.insert(entry.weakPoints, wp.Name)
                end
            elseif cname:find("armor") or cname:find("plate") then
                for _, av in ipairs(c:GetChildren()) do
                    if av:IsA("NumberValue") or av:IsA("IntValue") then
                        entry.armor[string.lower(av.Name)] = av.Value
                    end
                end
            elseif cname:find("weapon") or cname:find("gun") then
                for _, w in ipairs(c:GetChildren()) do
                    table.insert(entry.weapons, w.Name)
                end
            end
        end
    end

    -- attribute pass
    for k, v in pairs(node:GetAttributes()) do
        local lk = string.lower(k)
        if type(v) == "number" then entry.armor[lk] = v end
    end

    return entry
end

local function loadTankInfo()
    tankInfoRoot = ReplicatedStorage:FindFirstChild("TankInfo")
    if not tankInfoRoot then
        print("[MTC4] TankInfo not found in ReplicatedStorage")
        return
    end
    local count = 0
    for _, node in ipairs(tankInfoRoot:GetChildren()) do
        local ok, entry = pcall(extractTankEntry, node)
        if ok and entry then
            tankData[entry.name] = entry
            -- also key by lowercase + spaceless variants for flexible matching
            tankData[string.lower(entry.name)] = entry
            tankData[entry.name:gsub("%s+", "")] = entry
            count = count + 1
        end
    end
    print(string.format("[MTC4] TankInfo loaded · %d entries", count))
    if count > 0 then
        -- print first 3 entries as a sample so we know the shape is right
        local shown = 0
        for k, v in pairs(tankData) do
            if shown < 3 and k == v.name then
                local armorParts = {}
                for ak, av in pairs(v.armor) do
                    table.insert(armorParts, string.format("%s=%s", ak, tostring(av)))
                    if #armorParts >= 4 then break end
                end
                print(string.format("  [%s] armor:{%s}  weakpts:%d  weapons:%d",
                    k, table.concat(armorParts, " "), #v.weakPoints, #v.weapons))
                shown = shown + 1
            end
        end
    end
end
loadTankInfo()

-- Resolve which TankInfo entry an enemy is using
-- Strategy: check the vehicle model's name, then any string-value tags, then attributes
local function getTankEntry(vehicleModel)
    if not vehicleModel then return nil end
    local candidates = { vehicleModel.Name }
    -- common tag spots
    local tag = readStringValue(vehicleModel, "TankType")
            or readStringValue(vehicleModel, "Type")
            or readStringValue(vehicleModel, "Model")
            or vehicleModel:GetAttribute("TankType")
            or vehicleModel:GetAttribute("Tank")
            or vehicleModel:GetAttribute("Model")
    if type(tag) == "string" then table.insert(candidates, tag) end
    for _, c in ipairs(candidates) do
        if tankData[c] then return tankData[c] end
        if tankData[string.lower(c)] then return tankData[string.lower(c)] end
        if tankData[c:gsub("%s+", "")] then return tankData[c:gsub("%s+", "")] end
    end
    return nil
end

local function safeNotify(msg, title, dur)
    if notify then pcall(function() notify(msg, title, dur) end) end
end
local function setCorner(d, r) pcall(function() d.Corner = r end) end

-- WorldToScreen via Matcha global · returns (Vector2 screen, bool onScreen, number depth)
local function worldToScreen(pos)
    if WorldToScreen then
        local ok, s, on, depth = pcall(WorldToScreen, pos)
        if ok and s then
            return s, on, depth or 0
        end
    end
    -- fallback: use the Camera projection
    if Camera then
        local v, on = Camera:WorldToViewportPoint(pos)
        return Vector2.new(v.X, v.Y), on, v.Z
    end
    return nil, false, 0
end

-- ─── Drawing registry ───────────────────────────────────────────────
local allDrawings = {}
local espPool = {}
local function newDraw(kind)
    local d = Drawing.new(kind)
    table.insert(allDrawings, d)
    return d
end

-- ─── HUD ────────────────────────────────────────────────────────────
local hud = {}
hud.bg = newDraw("Square")
hud.bg.Color = Color3.fromRGB(15, 17, 22); hud.bg.Filled = true
hud.bg.Transparency = 0.86; hud.bg.ZIndex = 10; hud.bg.Visible = true
hud.bg.Size = Vector2.new(CONFIG.hudW, CONFIG.hudH)
setCorner(hud.bg, 12)
hud.bg.Position = Vector2.new(CONFIG.hudX, CONFIG.hudY)

hud.accent = newDraw("Square")
hud.accent.Color = Color3.fromRGB(235, 70, 70); hud.accent.Filled = true
hud.accent.Transparency = 1; hud.accent.ZIndex = 11; hud.accent.Visible = true
hud.accent.Size = Vector2.new(4, CONFIG.hudH)
setCorner(hud.accent, 4)
hud.accent.Position = Vector2.new(CONFIG.hudX, CONFIG.hudY)

hud.title = newDraw("Text")
hud.title.Color = Color3.fromRGB(235, 240, 245)
hud.title.Text = "MTC4 OVERLAY · matcha"
hud.title.Size = 15; hud.title.Font = Drawing.Fonts.SystemBold
hud.title.ZIndex = 12; hud.title.Visible = true
hud.title.Position = Vector2.new(CONFIG.hudX + 14, CONFIG.hudY + 10)

local function mkLine(dy, init)
    local t = newDraw("Text")
    t.Size = 13; t.Font = Drawing.Fonts.Monospace
    t.Color = Color3.fromRGB(210, 215, 220)
    t.ZIndex = 12; t.Visible = true
    t.Position = Vector2.new(CONFIG.hudX + 14, CONFIG.hudY + dy)
    t.Text = init or ""
    return t
end
hud.lineEsp  = mkLine(36,  "ESP:    -")
hud.lineAim  = mkLine(54,  "AIM:    -")
hud.lineWeak = mkLine(72,  "WEAK:   -")
hud.lineFov  = mkLine(90,  "FOV:    -")
hud.lineTgt  = mkLine(108, "TGT:    -")
hud.lineCnt  = mkLine(126, "ENEMY:  -")
hud.lineHint = mkLine(146, "B=ESP Q=AIM J=WEAK [ ]=FOV X=close F1/F2 min/restore")
hud.lineHint.Color = Color3.fromRGB(130, 140, 150)
hud.lineHint.Size = 10

-- minimized badge
hud.badge = newDraw("Square")
hud.badge.Color = Color3.fromRGB(235, 70, 70); hud.badge.Filled = true
hud.badge.Transparency = 0.95; hud.badge.ZIndex = 15; hud.badge.Visible = false
hud.badge.Size = Vector2.new(80, 22)
setCorner(hud.badge, 6)
hud.badge.Position = Vector2.new(CONFIG.hudX, CONFIG.hudY)

hud.badgeLbl = newDraw("Text")
hud.badgeLbl.Text = "MTC ● F2"; hud.badgeLbl.Size = 12
hud.badgeLbl.Color = Color3.fromRGB(255,255,255); hud.badgeLbl.Center = true
hud.badgeLbl.Font = Drawing.Fonts.SystemBold
hud.badgeLbl.ZIndex = 16; hud.badgeLbl.Visible = false
hud.badgeLbl.Position = Vector2.new(CONFIG.hudX + 40, CONFIG.hudY + 6)

local function refreshHudVisibility()
    if state.closed then return end
    local list = { hud.bg, hud.accent, hud.title, hud.lineEsp, hud.lineAim,
                   hud.lineWeak, hud.lineFov, hud.lineTgt, hud.lineCnt, hud.lineHint }
    for _, d in ipairs(list) do d.Visible = not state.minimized end
    hud.badge.Visible = state.minimized
    hud.badgeLbl.Visible = state.minimized
end

-- ─── ESP draw pool ──────────────────────────────────────────────────
-- one set of drawings per visible enemy, reused across frames
local function newEspEntry()
    local box     = newDraw("Square")
    box.Filled = false; box.Thickness = 1.5; box.ZIndex = 20; box.Visible = false
    local boxOut  = newDraw("Square")
    boxOut.Filled = false; boxOut.Thickness = 2.5; boxOut.Color = Color3.fromRGB(0,0,0)
    boxOut.Transparency = 0.6; boxOut.ZIndex = 19; boxOut.Visible = false
    local nameTxt = newDraw("Text")
    nameTxt.Size = 12; nameTxt.Font = Drawing.Fonts.SystemBold
    nameTxt.Center = true; nameTxt.Outline = true; nameTxt.ZIndex = 21; nameTxt.Visible = false
    local distTxt = newDraw("Text")
    distTxt.Size = 11; distTxt.Font = Drawing.Fonts.Monospace
    distTxt.Center = true; distTxt.Outline = true; distTxt.ZIndex = 21; distTxt.Visible = false
    local hpBarBg = newDraw("Square")
    hpBarBg.Filled = true; hpBarBg.Color = Color3.fromRGB(20,20,20)
    hpBarBg.Transparency = 0.85; hpBarBg.ZIndex = 20; hpBarBg.Visible = false
    local hpBar   = newDraw("Square")
    hpBar.Filled = true; hpBar.ZIndex = 21; hpBar.Visible = false
    local snapLine = newDraw("Line")
    snapLine.Thickness = 1.2; snapLine.Transparency = 0.7; snapLine.ZIndex = 18; snapLine.Visible = false
    local weakDot = newDraw("Circle")
    weakDot.Filled = true; weakDot.Radius = 4; weakDot.NumSides = 12
    weakDot.Color = Color3.fromRGB(255, 200, 60); weakDot.ZIndex = 22; weakDot.Visible = false
    local armorTxt = newDraw("Text")
    armorTxt.Size = 10; armorTxt.Font = Drawing.Fonts.Monospace
    armorTxt.Center = true; armorTxt.Outline = true; armorTxt.ZIndex = 21; armorTxt.Visible = false
    armorTxt.Color = Color3.fromRGB(180, 220, 255)
    local tankTxt = newDraw("Text")
    tankTxt.Size = 10; tankTxt.Font = Drawing.Fonts.Monospace
    tankTxt.Center = true; tankTxt.Outline = true; tankTxt.ZIndex = 21; tankTxt.Visible = false
    tankTxt.Color = Color3.fromRGB(255, 200, 60)

    return {
        box=box, boxOut=boxOut, name=nameTxt, dist=distTxt,
        hpBg=hpBarBg, hp=hpBar, line=snapLine, weakDot=weakDot,
        armor=armorTxt, tank=tankTxt
    }
end

local function getEspEntry(i)
    if not espPool[i] then espPool[i] = newEspEntry() end
    return espPool[i]
end

local function hideEspEntry(e)
    e.box.Visible = false
    e.boxOut.Visible = false
    e.name.Visible = false
    e.dist.Visible = false
    e.hpBg.Visible = false
    e.hp.Visible = false
    e.line.Visible = false
    e.weakDot.Visible = false
    e.armor.Visible = false
    e.tank.Visible = false
end

-- ─── Enemy enumeration ──────────────────────────────────────────────
-- Returns list of { player, name, hrp, hpModel, health, maxHealth, distance, vehicleModel }
local function gatherEnemies()
    local out = {}
    local lpChar = LP.Character
    local lpPos = nil
    if lpChar then
        local lpHrp = lpChar:FindFirstChild("HumanoidRootPart") or lpChar:FindFirstChild("Head")
        if lpHrp then lpPos = lpHrp.Position end
    end
    if not lpPos then return out end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local skip = false
            if CONFIG.skipTeammates and p.Team and LP.Team and p.Team == LP.Team then
                skip = true
            end
            if not skip and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Head")
                if hrp then
                    local d = (hrp.Position - lpPos).Magnitude
                    if d <= CONFIG.maxDistance then
                        local hum = p.Character:FindFirstChildOfClass("Humanoid")
                        local hp, maxhp = nil, nil
                        if hum then hp = hum.Health; maxhp = hum.MaxHealth end
                        -- vehicle detection: seated in a VehicleSeat
                        local vehicleModel = nil
                        if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
                            vehicleModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
                        end
                        table.insert(out, {
                            player = p, name = p.Name,
                            hrp = hrp,
                            health = hp, maxHealth = maxhp,
                            distance = d,
                            vehicle = vehicleModel,
                        })
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

-- Weak-point lookup. Priority:
--   1. TankInfo entry's weakPoints list (the real game data we just loaded)
--   2. Common tank-game part names as fallback
--   3. Turret roof estimate above HRP
local function findWeakPoint(enemy)
    if not enemy.vehicle then
        return enemy.hrp.Position + Vector3.new(0, 1.5, 0)
    end

    -- (1) TankInfo-driven weak points
    local entry = getTankEntry(enemy.vehicle)
    if entry and entry.weakPoints and #entry.weakPoints > 0 then
        for _, wpName in ipairs(entry.weakPoints) do
            local part = enemy.vehicle:FindFirstChild(wpName, true)
            if part and part:IsA("BasePart") then return part.Position end
        end
    end

    -- (2) heuristic part-name probe
    local candidates = {
        "TurretRing", "Turret_Ring", "Cupola", "CommanderHatch", "Hatch",
        "Commander", "EngineDeck", "Engine", "AmmoRack", "Crew",
        "DriverHatch", "GunMantlet", "MGPort", "PeriscopeLow",
    }
    for _, n in ipairs(candidates) do
        local part = enemy.vehicle:FindFirstChild(n, true)
        if part and part:IsA("BasePart") then return part.Position end
    end

    -- (3) fallback: turret roof estimate
    if enemy.vehicle.PrimaryPart then
        return enemy.vehicle.PrimaryPart.Position + Vector3.new(0, 2.5, 0)
    end
    return enemy.hrp.Position + Vector3.new(0, 2, 0)
end

-- Format an armor summary string from a TankInfo entry for ESP display
local function armorSummary(entry)
    if not entry or not entry.armor then return nil end
    local order = { "hull", "turret", "side", "rear", "hullarmor", "turretarmor", "sidearmor", "rearArmor" }
    local parts = {}
    for _, k in ipairs(order) do
        local v = entry.armor[k]
        if v and tonumber(v) then
            local short = k:gsub("armor", "")
            table.insert(parts, string.format("%s:%d", short:sub(1,1):upper()..short:sub(2), math.floor(v)))
        end
    end
    -- if none of the standard names matched, just grab the first few numeric armor values
    if #parts == 0 then
        for k, v in pairs(entry.armor) do
            if tonumber(v) and not k:find("price") and not k:find("speed") then
                table.insert(parts, string.format("%s:%s", k:sub(1,3):upper(), tostring(v)))
                if #parts >= 3 then break end
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- Bounding box of a model on screen (project min/max corners)
local function modelScreenBox(model)
    if not model then return nil end
    local cf, size
    if model.GetBoundingBox then
        local ok
        ok, cf, size = pcall(function() return model:GetBoundingBox() end)
        if not ok then return nil end
    end
    if not cf or not size then return nil end
    local hx, hy, hz = size.X/2, size.Y/2, size.Z/2
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for dx = -1, 1, 2 do for dy = -1, 1, 2 do for dz = -1, 1, 2 do
        local p = cf * CFrame.new(dx*hx, dy*hy, dz*hz)
        local s, on = worldToScreen(p.Position)
        if s then
            if s.X < minX then minX = s.X end
            if s.Y < minY then minY = s.Y end
            if s.X > maxX then maxX = s.X end
            if s.Y > maxY then maxY = s.Y end
        end
    end end end
    if minX == math.huge then return nil end
    return minX, minY, maxX, maxY
end

-- ─── ESP render ─────────────────────────────────────────────────────
local function colorOf(c) return Color3.fromRGB(c.r, c.g, c.b) end

local function renderESP(enemies)
    -- hide all first
    for _, e in pairs(espPool) do hideEspEntry(e) end
    if not CONFIG.espEnabled or state.minimized then return end

    local viewport = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local screenBottomCenter = Vector2.new(viewport.X / 2, viewport.Y)

    for i, en in ipairs(enemies) do
        local e = getEspEntry(i)
        local headPos = en.hrp.Position + Vector3.new(0, 2.5, 0)
        local footPos = en.hrp.Position - Vector3.new(0, 3, 0)
        local sHead, onH = worldToScreen(headPos)
        local sFoot, onF = worldToScreen(footPos)
        if sHead and onH then
            local x1, y1, x2, y2 = modelScreenBox(en.vehicle)
            local boxX, boxY, boxW, boxH
            if x1 and x2 and (x2 - x1) > 6 and (y2 - y1) > 6 then
                boxX, boxY = x1, y1
                boxW, boxH = x2 - x1, y2 - y1
            else
                -- fallback to head/foot height-based box
                local h = math.abs((sFoot and sFoot.Y or sHead.Y) - sHead.Y)
                if h < 20 then h = 20 end
                local w = h * 0.55
                boxX = sHead.X - w/2; boxY = sHead.Y
                boxW = w; boxH = h
            end

            local col = colorOf(CONFIG.enemyColor)

            e.boxOut.Position = Vector2.new(boxX-1, boxY-1)
            e.boxOut.Size     = Vector2.new(boxW+2, boxH+2)
            e.boxOut.Visible  = true
            e.box.Position = Vector2.new(boxX, boxY)
            e.box.Size     = Vector2.new(boxW, boxH)
            e.box.Color    = col
            e.box.Visible  = true

            e.name.Position = Vector2.new(boxX + boxW/2, boxY - 16)
            e.name.Text     = en.name
            e.name.Color    = col
            e.name.Visible  = true

            if CONFIG.showDistance then
                e.dist.Position = Vector2.new(boxX + boxW/2, boxY + boxH + 2)
                e.dist.Text     = string.format("%d m", math.floor(en.distance + 0.5))
                e.dist.Color    = Color3.fromRGB(220, 220, 220)
                e.dist.Visible  = true
            end

            -- TankInfo-driven labels: tank name + armor summary
            local entry = getTankEntry(en.vehicle)
            if entry then
                e.tank.Position = Vector2.new(boxX + boxW/2, boxY - 28)
                e.tank.Text     = entry.name
                e.tank.Visible  = true

                local armorStr = armorSummary(entry)
                if armorStr then
                    e.armor.Position = Vector2.new(boxX + boxW/2, boxY + boxH + 14)
                    e.armor.Text     = armorStr
                    e.armor.Visible  = true
                end
            end

            if CONFIG.showHealthBars and en.maxHealth and en.maxHealth > 0 then
                local hpRatio = math.clamp(en.health / en.maxHealth, 0, 1)
                local barW, barH = 3, boxH
                e.hpBg.Position = Vector2.new(boxX - barW - 3, boxY)
                e.hpBg.Size     = Vector2.new(barW, barH)
                e.hpBg.Visible  = true
                e.hp.Position   = Vector2.new(boxX - barW - 3, boxY + barH * (1 - hpRatio))
                e.hp.Size       = Vector2.new(barW, barH * hpRatio)
                e.hp.Color      = Color3.fromRGB(
                    math.floor(255 * (1 - hpRatio)),
                    math.floor(200 * hpRatio),
                    60)
                e.hp.Visible    = true
            end

            if CONFIG.showLines then
                e.line.From    = screenBottomCenter
                e.line.To      = Vector2.new(boxX + boxW/2, boxY + boxH/2)
                e.line.Color   = col
                e.line.Visible = true
            end

            if CONFIG.weakPointHint then
                local wp = findWeakPoint(en)
                local sw, onW = worldToScreen(wp)
                if sw and onW then
                    e.weakDot.Position = sw
                    e.weakDot.Visible  = true
                end
            end
        end
    end
end

-- ─── Aim assist ─────────────────────────────────────────────────────
local function getCrosshairPos()
    local v = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    return Vector2.new(v.X / 2, v.Y / 2)
end

local function pickAimTarget(enemies)
    if not enemies or #enemies == 0 then return nil end
    local crosshair = getCrosshairPos()
    local best, bestDist = nil, math.huge
    for _, en in ipairs(enemies) do
        local aimPos
        if CONFIG.aimAtWeakPoint then
            aimPos = findWeakPoint(en)
        else
            aimPos = en.hrp.Position
        end
        local s, on = worldToScreen(aimPos)
        if s and on then
            local dx = s.X - crosshair.X
            local dy = s.Y - crosshair.Y
            local r = math.sqrt(dx*dx + dy*dy)
            if r < state.fov and r < bestDist then
                bestDist = r; best = { enemy = en, screenPos = s }
            end
        end
    end
    return best
end

local function aimAt(target)
    if not target then return end
    local cx, cy
    local ok, mx, my = pcall(function() return mouse.X, mouse.Y end)
    if not ok then return end
    cx, cy = mx, my
    local tx, ty = target.screenPos.X, target.screenPos.Y
    local dx = (tx - cx) * (1 - CONFIG.aimSmoothing)
    local dy = (ty - cy) * (1 - CONFIG.aimSmoothing)
    if mousemoverel then
        pcall(mousemoverel, dx, dy)
    elseif mousemoveabs then
        pcall(mousemoveabs, cx + dx, cy + dy)
    end
end

-- ─── HUD repaint ────────────────────────────────────────────────────
local function paintHud()
    if state.closed or state.minimized then return end
    hud.lineEsp.Text = "ESP:    " .. (CONFIG.espEnabled and "ON" or "OFF")
    hud.lineEsp.Color = CONFIG.espEnabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)
    hud.lineAim.Text = "AIM:    " .. (CONFIG.aimEnabled and "ON" or "OFF") .. (state.aimingNow and "  [HOLDING]" or "")
    hud.lineAim.Color = CONFIG.aimEnabled and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(220, 110, 110)
    hud.lineWeak.Text = "WEAK:   " .. (CONFIG.weakPointHint and "ON" or "OFF")
    hud.lineFov.Text  = string.format("FOV:    %d px", state.fov)
    hud.lineCnt.Text  = string.format("ENEMY:  %d in range", state.enemiesSeen)
    if state.currentTarget then
        hud.lineTgt.Text = string.format("TGT:    %s @ %dm", state.currentTarget.enemy.name,
            math.floor(state.currentTarget.enemy.distance + 0.5))
        hud.lineTgt.Color = Color3.fromRGB(255, 200, 60)
    else
        hud.lineTgt.Text = "TGT:    -"
        hud.lineTgt.Color = Color3.fromRGB(180, 185, 190)
    end
end

-- ─── Main loop ──────────────────────────────────────────────────────
local function closeOverlay()
    state.closed = true
    for _, d in ipairs(allDrawings) do
        pcall(function() d.Visible = false end)
        pcall(function() d:Remove() end)
    end
    safeNotify("MTC4 overlay closed", "matcha", 3)
    print("[MTC4] closed.")
end

spawn(function()
    while not state.closed do
        local enemies = gatherEnemies()
        state.enemiesSeen = #enemies
        renderESP(enemies)

        if CONFIG.aimEnabled and iskeypressed(CONFIG.aimKey) then
            local tgt = pickAimTarget(enemies)
            state.currentTarget = tgt
            state.aimingNow = true
            if tgt then aimAt(tgt) end
        else
            state.currentTarget = nil
            state.aimingNow = false
        end

        paintHud()
        wait(0.012)
    end
end)

-- hotkeys
spawn(function()
    local prev = {}
    local function edge(k, name)
        if k == 0 then return false end
        local d = iskeypressed(k)
        local was = prev[name]; prev[name] = d
        return d and not was
    end
    while not state.closed do
        if edge(CONFIG.toggleEspKey, "esp") then
            CONFIG.espEnabled = not CONFIG.espEnabled
            safeNotify("ESP " .. (CONFIG.espEnabled and "ON" or "OFF"), "matcha", 1.5)
        end
        if edge(CONFIG.toggleAimKey, "aim") then
            CONFIG.aimEnabled = not CONFIG.aimEnabled
            safeNotify("AIM " .. (CONFIG.aimEnabled and "ON" or "OFF"), "matcha", 1.5)
        end
        if edge(CONFIG.toggleWeakKey, "weak") then
            CONFIG.weakPointHint = not CONFIG.weakPointHint
            CONFIG.aimAtWeakPoint = CONFIG.weakPointHint
            safeNotify("WEAK-POINT " .. (CONFIG.weakPointHint and "ON" or "OFF"), "matcha", 1.5)
        end
        if edge(CONFIG.fovUpKey,   "fovup")   then state.fov = math.min(800, state.fov + 20) end
        if edge(CONFIG.fovDownKey, "fovdown") then state.fov = math.max(20,  state.fov - 20) end
        if edge(CONFIG.closeKey, "close") then closeOverlay(); return end
        if edge(CONFIG.minimizeKey, "min") then state.minimized = true; refreshHudVisibility() end
        if edge(CONFIG.restoreKey,  "rest") then state.minimized = false; refreshHudVisibility() end
        wait(0.008)
    end
end)

refreshHudVisibility()
paintHud()
safeNotify("MTC4 overlay armed · B/Q/J toggle · RBUTTON to aim · X to close", "matcha", 5)
print("[MTC4] armed. ESP+AIM+WEAK ready.")
