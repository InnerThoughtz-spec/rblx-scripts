-- BL Auto Green // Matcha external (Infinity Sports Basketball Legends)
-- Mouse via game.Players.LocalPlayer:GetMouse() · ping via GetPingValue()
-- Load: loadstring(game:HttpGet("https://raw.githubusercontent.com/InnerThoughtz-spec/rblx-scripts/refs/heads/main/bl-autogreen.lua"))()

-- ─── Config ─────────────────────────────────────────────────────────
local CONFIG = {
    fpsPresets = {
        { name = "30 FPS",  buckets = { 0.328, 0.330, 0.332, 0.336 } },
        { name = "60 FPS",  buckets = { 0.343, 0.343, 0.342, 0.344 } },
        { name = "240 FPS", buckets = { 0.354, 0.354, 0.3545, 0.355 } },
        { name = "Custom",  buckets = { 0.350, 0.350, 0.350, 0.350 } },
    },
    customPresetIdx = 4,
    defaultFpsIdx = 1,
    defaultCustomMs = 350,

    pingBuckets = {
        { maxPing = 30,   label = "LOW"   },
        { maxPing = 60,   label = "MID"   },
        { maxPing = 100,  label = "HIGH"  },
        { maxPing = 9999, label = "SPIKE" },
    },

    pingWindowSize   = 5,
    pingIntervalFast = 0.10,
    pingIntervalSlow = 1.00,
    hudRepaintRate   = 0.05,
    pingURL          = "https://www.gstatic.com/generate_204",

    shootKey       = 0x45, manualKey = 0x56, toggleKey = 0x54,
    cyclePingKey   = 0x50, cycleFpsKey = 0xDC,
    tuneUpKey      = 0xDD, tuneDownKey = 0xDB,
    minimizeKey    = 0x70, restoreKey  = 0x71,
    tuneStep       = 0.001, autoOnShoot = true,

    hudW = 340, hudHCollapsed = 188, hudHExpanded = 236,
}

-- ─── State ──────────────────────────────────────────────────────────
local state = {
    enabled = true, busy = false, currentPing = 0,
    currentBucket = CONFIG.pingBuckets[1],
    durationOffset = 0, pingSource = "init",
    manualBucketIdx = nil,
    fpsIdx = CONFIG.defaultFpsIdx,
    customMs = CONFIG.defaultCustomMs,
    sliderDragging = false,
    hudX = 20, hudY = 20,
    closed = false, minimized = false,
    sliderVisible = false,
    hudDragging = false, hudDragOffX = 0, hudDragOffY = 0,
}
local pingHistory = {}

-- ─── Helpers ────────────────────────────────────────────────────────
local function now()
    if tick then return tick() end
    if os and os.clock then return os.clock() end
    return os.time()
end
local function setCorner(d, r) pcall(function() d.Corner = r end) end

-- Mouse: Matcha proxies the real DataModel; LocalPlayer:GetMouse() works
local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local mouse = LP:GetMouse()

local function getMousePos()
    return mouse.X, mouse.Y
end

local function externalHttpGet(url)
    if httpget then return pcall(function() return httpget(url) end) end
    return false
end

local function safeNotify(msg, title, dur)
    if notify then pcall(function() notify(msg, title, dur) end) end
end

-- ─── Drawing registry ───────────────────────────────────────────────
local allDrawings = {}
local drawingRel = {}
local sliderSet = {}

local function regDrawing(kind)
    local d = Drawing.new(kind)
    table.insert(allDrawings, d)
    return d
end
local function place(d, dx, dy)
    drawingRel[d] = { dx = dx, dy = dy }
    d.Position = Vector2.new(state.hudX + dx, state.hudY + dy)
end
local function placeLine(d, fromDx, fromDy, toDx, toDy)
    drawingRel[d] = { isLine = true, fromDx = fromDx, fromDy = fromDy, toDx = toDx, toDy = toDy }
    d.From = Vector2.new(state.hudX + fromDx, state.hudY + fromDy)
    d.To   = Vector2.new(state.hudX + toDx,   state.hudY + toDy)
end
local function applyAllPositions()
    for d, r in pairs(drawingRel) do
        if r.isLine then
            d.From = Vector2.new(state.hudX + r.fromDx, state.hudY + r.fromDy)
            d.To   = Vector2.new(state.hudX + r.toDx,   state.hudY + r.toDy)
        else
            d.Position = Vector2.new(state.hudX + r.dx, state.hudY + r.dy)
        end
    end
end

-- ─── Layout constants ───────────────────────────────────────────────
local PAD = 14
local CLOSE_W, MIN_W, BTN_H_TITLE = 24, 24, 22
local CLOSE_DX = CONFIG.hudW - PAD - CLOSE_W
local MIN_DX   = CLOSE_DX - 6 - MIN_W
local TITLE_BTN_DY = 8

local BTN_H = 32
local BTN_TEXT_SZ = 13
local BTN_PAD = 6
local BTN_DY = 96
local BTN_AREA_W = CONFIG.hudW - PAD * 2
local BTN_W = math.floor((BTN_AREA_W - BTN_PAD * 3) / 4)

local SLIDER_DX = PAD
local SLIDER_DY = 158
local SLIDER_W  = CONFIG.hudW - PAD * 2
local SLIDER_H  = 10
local THUMB_W   = 14
local THUMB_H   = 18

-- ─── Build UI ───────────────────────────────────────────────────────
local bg = regDrawing("Square")
bg.Color = Color3.fromRGB(18, 20, 26); bg.Filled = true
bg.Transparency = 0.88; bg.ZIndex = 10; bg.Visible = true
setCorner(bg, 14); place(bg, 0, 0)

local accent = regDrawing("Square")
accent.Color = Color3.fromRGB(110, 230, 130); accent.Filled = true
accent.Transparency = 1; accent.ZIndex = 11; accent.Visible = true
setCorner(accent, 4); place(accent, 0, 0)

local title = regDrawing("Text")
title.Color = Color3.fromRGB(235, 240, 245)
title.Text = "BL Auto Green · matcha"
title.Size = 16; title.Font = Drawing.Fonts.SystemBold
title.ZIndex = 12; title.Visible = true
place(title, PAD, 10)

local minBtnBg = regDrawing("Square")
minBtnBg.Size = Vector2.new(MIN_W, BTN_H_TITLE)
minBtnBg.Color = Color3.fromRGB(58, 62, 72); minBtnBg.Filled = true
minBtnBg.Transparency = 0.9; minBtnBg.ZIndex = 12; minBtnBg.Visible = true
setCorner(minBtnBg, 5); place(minBtnBg, MIN_DX, TITLE_BTN_DY)

local MIN_CY = TITLE_BTN_DY + BTN_H_TITLE / 2
local MIN_LINE_PAD = 6
local minLine = regDrawing("Line")
minLine.Color = Color3.fromRGB(230, 230, 230)
minLine.Thickness = 2; minLine.Transparency = 1
minLine.ZIndex = 14; minLine.Visible = true
placeLine(minLine, MIN_DX + MIN_LINE_PAD, MIN_CY, MIN_DX + MIN_W - MIN_LINE_PAD, MIN_CY)

local closeBtnBg = regDrawing("Square")
closeBtnBg.Size = Vector2.new(CLOSE_W, BTN_H_TITLE)
closeBtnBg.Color = Color3.fromRGB(165, 60, 60); closeBtnBg.Filled = true
closeBtnBg.Transparency = 0.92; closeBtnBg.ZIndex = 12; closeBtnBg.Visible = true
setCorner(closeBtnBg, 5); place(closeBtnBg, CLOSE_DX, TITLE_BTN_DY)

local CLOSE_LINE_PAD_X = 7
local CLOSE_LINE_PAD_Y = 6
local closeLineA = regDrawing("Line")
closeLineA.Color = Color3.fromRGB(255, 240, 240)
closeLineA.Thickness = 2; closeLineA.Transparency = 1
closeLineA.ZIndex = 14; closeLineA.Visible = true
placeLine(closeLineA,
    CLOSE_DX + CLOSE_LINE_PAD_X, TITLE_BTN_DY + CLOSE_LINE_PAD_Y,
    CLOSE_DX + CLOSE_W - CLOSE_LINE_PAD_X, TITLE_BTN_DY + BTN_H_TITLE - CLOSE_LINE_PAD_Y)

local closeLineB = regDrawing("Line")
closeLineB.Color = Color3.fromRGB(255, 240, 240)
closeLineB.Thickness = 2; closeLineB.Transparency = 1
closeLineB.ZIndex = 14; closeLineB.Visible = true
placeLine(closeLineB,
    CLOSE_DX + CLOSE_LINE_PAD_X, TITLE_BTN_DY + BTN_H_TITLE - CLOSE_LINE_PAD_Y,
    CLOSE_DX + CLOSE_W - CLOSE_LINE_PAD_X, TITLE_BTN_DY + CLOSE_LINE_PAD_Y)

local statusTxt = regDrawing("Text")
statusTxt.Size = 14; statusTxt.Font = Drawing.Fonts.System
statusTxt.ZIndex = 12; statusTxt.Visible = true
place(statusTxt, PAD, 34)

local pingTxt = regDrawing("Text")
pingTxt.Size = 13; pingTxt.Font = Drawing.Fonts.Monospace
pingTxt.ZIndex = 12; pingTxt.Visible = true
place(pingTxt, PAD, 54)

local durTxt = regDrawing("Text")
durTxt.Color = Color3.fromRGB(180, 210, 195)
durTxt.Size = 13; durTxt.Font = Drawing.Fonts.Monospace
durTxt.ZIndex = 12; durTxt.Visible = true
place(durTxt, PAD, 72)

local fpsButtons = {}
for i, preset in ipairs(CONFIG.fpsPresets) do
    local dx = PAD + (i - 1) * (BTN_W + BTN_PAD)
    local box = regDrawing("Square")
    box.Filled = true; box.Transparency = 0.95
    box.ZIndex = 12; box.Visible = true
    box.Size = Vector2.new(BTN_W, BTN_H)
    setCorner(box, 8); place(box, dx, BTN_DY)

    local lbl = regDrawing("Text")
    lbl.Size = BTN_TEXT_SZ
    lbl.Center = true; lbl.Outline = true
    lbl.Font = Drawing.Fonts.SystemBold
    lbl.ZIndex = 13; lbl.Visible = true
    lbl.Text = preset.name
    place(lbl, dx + BTN_W / 2, BTN_DY + 12)

    fpsButtons[i] = { dx = dx, w = BTN_W, h = BTN_H, box = box, lbl = lbl }
end

local sliderLbl = regDrawing("Text")
sliderLbl.Size = 12; sliderLbl.Font = Drawing.Fonts.Monospace
sliderLbl.ZIndex = 12; sliderLbl.Visible = false
place(sliderLbl, PAD, 138); sliderSet[sliderLbl] = true

local sliderTrack = regDrawing("Square")
sliderTrack.Size = Vector2.new(SLIDER_W, SLIDER_H)
sliderTrack.Color = Color3.fromRGB(36, 40, 48)
sliderTrack.Filled = true; sliderTrack.Transparency = 1
sliderTrack.ZIndex = 12; sliderTrack.Visible = false
setCorner(sliderTrack, 5)
place(sliderTrack, SLIDER_DX, SLIDER_DY + (THUMB_H - SLIDER_H) / 2)
sliderSet[sliderTrack] = true

local sliderFill = regDrawing("Square")
sliderFill.Size = Vector2.new(0, SLIDER_H)
sliderFill.Color = Color3.fromRGB(70, 165, 95)
sliderFill.Filled = true; sliderFill.Transparency = 1
sliderFill.ZIndex = 13; sliderFill.Visible = false
setCorner(sliderFill, 5)
place(sliderFill, SLIDER_DX, SLIDER_DY + (THUMB_H - SLIDER_H) / 2)
sliderSet[sliderFill] = true

local sliderThumb = regDrawing("Square")
sliderThumb.Size = Vector2.new(THUMB_W, THUMB_H)
sliderThumb.Color = Color3.fromRGB(230, 235, 240)
sliderThumb.Filled = true; sliderThumb.Transparency = 1
sliderThumb.ZIndex = 14; sliderThumb.Visible = false
setCorner(sliderThumb, 5)
place(sliderThumb, SLIDER_DX, SLIDER_DY)
sliderSet[sliderThumb] = true

local hintTxt = regDrawing("Text")
hintTxt.Color = Color3.fromRGB(130, 140, 150)
hintTxt.Size = 11; hintTxt.Font = Drawing.Fonts.System
hintTxt.ZIndex = 12; hintTxt.Visible = true
hintTxt.Text = "E=auto V=shot T=toggle P=ping \\=FPS [ ]=tune"
place(hintTxt, PAD, 144)

local hintTxt2 = regDrawing("Text")
hintTxt2.Color = Color3.fromRGB(130, 140, 150)
hintTxt2.Size = 11; hintTxt2.Font = Drawing.Fonts.System
hintTxt2.ZIndex = 12; hintTxt2.Visible = true
hintTxt2.Text = "F1=minimize F2=restore X=close · drag title to move"
place(hintTxt2, PAD, 162)

local minBadgeBg = regDrawing("Square")
minBadgeBg.Color = Color3.fromRGB(70, 165, 95)
minBadgeBg.Filled = true; minBadgeBg.Transparency = 0.95
minBadgeBg.Size = Vector2.new(74, 24)
minBadgeBg.ZIndex = 15; minBadgeBg.Visible = false
setCorner(minBadgeBg, 6); place(minBadgeBg, 0, 0)

local minBadgeLbl = regDrawing("Text")
minBadgeLbl.Text = "BL ● F2"
minBadgeLbl.Size = 12; minBadgeLbl.Center = true
minBadgeLbl.Color = Color3.fromRGB(255, 255, 255)
minBadgeLbl.Font = Drawing.Fonts.SystemBold
minBadgeLbl.ZIndex = 16; minBadgeLbl.Visible = false
place(minBadgeLbl, 37, 8)

-- ─── Visibility / layout ────────────────────────────────────────────
local function refreshVisibility()
    if state.closed then return end
    if state.minimized then
        for _, d in ipairs(allDrawings) do d.Visible = false end
        minBadgeBg.Visible = true; minBadgeLbl.Visible = true
        return
    end
    for _, d in ipairs(allDrawings) do d.Visible = true end
    minBadgeBg.Visible = false; minBadgeLbl.Visible = false
    if not state.sliderVisible then
        for d in pairs(sliderSet) do d.Visible = false end
    end
end

local function rebuildLayout()
    if state.closed then return end
    local h = state.sliderVisible and CONFIG.hudHExpanded or CONFIG.hudHCollapsed
    bg.Size = Vector2.new(CONFIG.hudW, h)
    accent.Size = Vector2.new(4, h)
    if state.sliderVisible then
        place(hintTxt,  PAD, 200)
        place(hintTxt2, PAD, 218)
    else
        place(hintTxt,  PAD, 144)
        place(hintTxt2, PAD, 162)
    end
    refreshVisibility()
end

-- ─── Preset / slider ────────────────────────────────────────────────
local function applyFpsPreset(idx)
    state.fpsIdx = idx
    local p = CONFIG.fpsPresets[idx]
    for i = 1, 4 do CONFIG.pingBuckets[i].duration = p.buckets[i] end
    state.sliderVisible = (idx == CONFIG.customPresetIdx)
    rebuildLayout()
end
local function applyCustomMs()
    local sec = state.customMs / 1000
    for i = 1, 4 do
        CONFIG.fpsPresets[CONFIG.customPresetIdx].buckets[i] = sec
        if state.fpsIdx == CONFIG.customPresetIdx then
            CONFIG.pingBuckets[i].duration = sec
        end
    end
end
applyFpsPreset(state.fpsIdx); applyCustomMs()

-- ─── Move / min / close ─────────────────────────────────────────────
local function moveHud(nx, ny)
    state.hudX = nx; state.hudY = ny
    applyAllPositions()
end
local function setMinimized(v) state.minimized = v; refreshVisibility() end
local function closeScript()
    state.closed = true
    for _, d in ipairs(allDrawings) do
        pcall(function() d.Visible = false end)
        pcall(function() d:Remove() end)
    end
    safeNotify("BL Auto Green closed", "matcha", 3)
    print("[BL] closed.")
end

-- ─── Paint ──────────────────────────────────────────────────────────
local function activeDuration()
    return state.currentBucket.duration + state.durationOffset
end
local function paintSlider()
    local pct = state.customMs / 1000
    local thumbDx = SLIDER_DX + (SLIDER_W - THUMB_W) * pct
    place(sliderThumb, thumbDx, SLIDER_DY)
    local fillW = thumbDx + THUMB_W / 2 - SLIDER_DX
    if fillW < 0 then fillW = 0 end
    sliderFill.Size = Vector2.new(fillW, SLIDER_H)
    sliderLbl.Text  = string.format("Custom slider: %d ms", state.customMs)
    sliderLbl.Color = Color3.fromRGB(110, 230, 130)
end
local function paint()
    if state.closed or state.minimized then return end

    if state.busy then
        statusTxt.Text  = "Status: RELEASING"
        statusTxt.Color = Color3.fromRGB(255, 200, 80)
        accent.Color    = Color3.fromRGB(255, 200, 80)
    elseif state.enabled then
        statusTxt.Text  = "Status: ARMED  ·  " .. state.currentBucket.label
        statusTxt.Color = Color3.fromRGB(110, 230, 130)
        accent.Color    = Color3.fromRGB(110, 230, 130)
    else
        statusTxt.Text  = "Status: OFF"
        statusTxt.Color = Color3.fromRGB(255, 110, 110)
        accent.Color    = Color3.fromRGB(255, 110, 110)
    end

    local pc
    if     state.currentPing <= 30  then pc = Color3.fromRGB(110, 230, 130)
    elseif state.currentPing <= 60  then pc = Color3.fromRGB(220, 220, 120)
    elseif state.currentPing <= 100 then pc = Color3.fromRGB(255, 170, 80)
    else                                 pc = Color3.fromRGB(255, 110, 110) end
    pingTxt.Color = pc
    pingTxt.Text  = string.format("Ping: %d ms  (%s)",
        math.floor(state.currentPing + 0.5), state.pingSource)

    local d = activeDuration()
    durTxt.Text = string.format("Duration: %.1f ms   offset: %+d ms",
        d * 1000, math.floor(state.durationOffset * 1000 + 0.5))

    for i, btn in ipairs(fpsButtons) do
        if i == state.fpsIdx then
            btn.box.Color = Color3.fromRGB(70, 165, 95)
            btn.lbl.Color = Color3.fromRGB(255, 255, 255)
        else
            btn.box.Color = Color3.fromRGB(40, 44, 52)
            btn.lbl.Color = Color3.fromRGB(190, 200, 210)
        end
    end

    if state.sliderVisible then paintSlider() end
end

-- ─── Ping ladder ────────────────────────────────────────────────────
local function tryRobloxPing()
    if not GetPingValue then return nil end
    local ok, p = pcall(GetPingValue)
    if ok and type(p) == "number" and p > 0 and p < 10000 then return p end
    return nil
end

local function tryHttpPing()
    local t0 = now()
    if not externalHttpGet(CONFIG.pingURL) then return nil end
    local elapsed = (now() - t0) * 1000
    if elapsed < 0 or elapsed > 10000 then return nil end
    return elapsed
end

local rblxAvailable = tryRobloxPing() ~= nil
state.pingSource = rblxAvailable and "rblx" or "http"

local function freshPing()
    if rblxAvailable then
        local p = tryRobloxPing()
        if p then return p end
        rblxAvailable = false
        state.pingSource = "http"
    end
    return tryHttpPing()
end
local function pushPing(p)
    table.insert(pingHistory, 1, p)
    while #pingHistory > CONFIG.pingWindowSize do table.remove(pingHistory) end
end
local function rollingMaxPing()
    local m = 0
    for _, p in ipairs(pingHistory) do if p > m then m = p end end
    return m
end
local function bucketFor(ping)
    for _, b in ipairs(CONFIG.pingBuckets) do
        if ping <= b.maxPing then return b end
    end
    return CONFIG.pingBuckets[#CONFIG.pingBuckets]
end
local function refreshAtShotTime()
    if state.manualBucketIdx then return end
    if not rblxAvailable then return end
    local p = tryRobloxPing()
    if not p then return end
    pushPing(p)
    local eff = rollingMaxPing()
    state.currentPing = eff
    state.currentBucket = bucketFor(eff)
end

-- ─── Shot routines ──────────────────────────────────────────────────
local function perfectShot()
    if state.busy or not state.enabled then return end
    refreshAtShotTime()
    state.busy = true; paint()
    keypress(CONFIG.shootKey)
    wait(activeDuration())
    keyrelease(CONFIG.shootKey)
    wait(0.08); state.busy = false; paint()
end
local function releaseOnly()
    if state.busy or not state.enabled then return end
    refreshAtShotTime()
    state.busy = true; paint()
    wait(activeDuration())
    keyrelease(CONFIG.shootKey)
    wait(0.08); state.busy = false; paint()
end

-- ─── Mouse handler ──────────────────────────────────────────────────
local function inRect(mx, my, dx, dy, w, h)
    local x = state.hudX + dx
    local y = state.hudY + dy
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end
local function setSliderFromMouseX(mx)
    local pct = (mx - (state.hudX + SLIDER_DX)) / SLIDER_W
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    state.customMs = math.floor(pct * 1000 + 0.5)
    applyCustomMs()
end

spawn(function()
    local wasDown = false
    while not state.closed do
        local isDown = ismouse1pressed()
        local mx, my = getMousePos()

        if isDown and not wasDown and mx and my then
            local handled = false

            if state.minimized then
                if inRect(mx, my, 0, 0, 74, 24) then
                    setMinimized(false); handled = true
                end
            else
                if not handled and inRect(mx, my, CLOSE_DX, TITLE_BTN_DY, CLOSE_W, BTN_H_TITLE) then
                    closeScript(); return
                end
                if not handled and inRect(mx, my, MIN_DX, TITLE_BTN_DY, MIN_W, BTN_H_TITLE) then
                    setMinimized(true); handled = true
                end
                if not handled and state.sliderVisible then
                    if inRect(mx, my, SLIDER_DX, SLIDER_DY - 4, SLIDER_W, THUMB_H + 8) then
                        state.sliderDragging = true
                        setSliderFromMouseX(mx); paint()
                        handled = true
                    end
                end
                if not handled then
                    for i, btn in ipairs(fpsButtons) do
                        if inRect(mx, my, btn.dx, BTN_DY, btn.w, btn.h) then
                            applyFpsPreset(i)
                            if i == CONFIG.customPresetIdx then applyCustomMs() end
                            paint()
                            safeNotify("Preset: " .. CONFIG.fpsPresets[i].name, "matcha", 2)
                            handled = true
                            break
                        end
                    end
                end
                if not handled then
                    if my >= state.hudY and my <= state.hudY + 30
                    and mx >= state.hudX and mx <= state.hudX + CONFIG.hudW then
                        state.hudDragging = true
                        state.hudDragOffX = mx - state.hudX
                        state.hudDragOffY = my - state.hudY
                        handled = true
                    end
                end
            end
        end

        if isDown and state.sliderDragging and mx then
            setSliderFromMouseX(mx); paint()
        elseif isDown and state.hudDragging and mx and my then
            moveHud(mx - state.hudDragOffX, my - state.hudDragOffY)
        end

        if not isDown then
            state.sliderDragging = false
            state.hudDragging = false
        end

        wasDown = isDown
        wait(0.012)
    end
end)

-- ─── Hotkey loop ────────────────────────────────────────────────────
local function cycleFps()
    state.fpsIdx = (state.fpsIdx % #CONFIG.fpsPresets) + 1
    applyFpsPreset(state.fpsIdx)
    if state.fpsIdx == CONFIG.customPresetIdx then applyCustomMs() end
    paint()
    safeNotify("Preset: " .. CONFIG.fpsPresets[state.fpsIdx].name, "matcha", 2)
end

spawn(function()
    local prev = {}
    local function edge(k, name)
        if k == 0 then return false end
        local d = iskeypressed(k)
        local was = prev[name]; prev[name] = d
        return d and not was
    end

    while not state.closed do
        if CONFIG.manualKey ~= 0 and edge(CONFIG.manualKey, "manual") then
            spawn(perfectShot)
        end
        if edge(CONFIG.toggleKey, "toggle") then
            state.enabled = not state.enabled; paint()
        end
        if edge(CONFIG.tuneUpKey, "up") then
            state.durationOffset = state.durationOffset + CONFIG.tuneStep; paint()
        end
        if edge(CONFIG.tuneDownKey, "down") then
            state.durationOffset = state.durationOffset - CONFIG.tuneStep; paint()
        end
        if edge(CONFIG.cyclePingKey, "cycle") then
            if state.manualBucketIdx == nil then
                state.manualBucketIdx = 1
            else
                state.manualBucketIdx = state.manualBucketIdx + 1
                if state.manualBucketIdx > #CONFIG.pingBuckets then
                    state.manualBucketIdx = nil
                end
            end
            if state.manualBucketIdx then
                state.currentBucket = CONFIG.pingBuckets[state.manualBucketIdx]
                state.pingSource    = "manual"
                state.currentPing   = state.currentBucket.maxPing
            else
                state.pingSource = rblxAvailable and "rblx" or "http"
            end
            paint()
        end
        if edge(CONFIG.cycleFpsKey, "fps") then cycleFps() end
        if edge(CONFIG.minimizeKey, "min") then setMinimized(true) end
        if edge(CONFIG.restoreKey,  "rest") then setMinimized(false) end

        wait(0.008)
    end
end)

-- ─── Auto-release on E press ────────────────────────────────────────
if CONFIG.autoOnShoot then
    spawn(function()
        local wasDown = false
        while not state.closed do
            if state.enabled and not state.busy then
                local down = iskeypressed(CONFIG.shootKey)
                if down and not wasDown then spawn(releaseOnly) end
                wasDown = down
            else
                wasDown = iskeypressed(CONFIG.shootKey)
            end
            wait(0.002)
        end
    end)
end

-- ─── Background ping watcher ────────────────────────────────────────
spawn(function()
    while not state.closed do
        if state.manualBucketIdx == nil then
            local p = freshPing()
            if p then
                pushPing(p)
                local eff = rollingMaxPing()
                state.currentPing  = eff
                state.currentBucket = bucketFor(eff)
            end
        end
        wait(rblxAvailable and CONFIG.pingIntervalFast or CONFIG.pingIntervalSlow)
    end
end)

-- ─── Live repaint ──────────────────────────────────────────────────
spawn(function()
    while not state.closed do
        paint(); wait(CONFIG.hudRepaintRate)
    end
end)

rebuildLayout(); paint()
safeNotify(string.format("BL Auto Green ready. FPS=%s · ping=%s",
    CONFIG.fpsPresets[state.fpsIdx].name, state.pingSource), "matcha", 4)
print("[BL] armed. mouse=LP:GetMouse() · ping=" .. state.pingSource)
