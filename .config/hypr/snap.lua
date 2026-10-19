-- Window floating + snapping for HyDE (Hyprland Lua config).
-- Loaded from hyprland.lua with require("snap").
--   SUPER + F            toggle floating
--   SUPER + Left/Right   snap to left/right half (keeps top/bottom if already a quarter)
--   SUPER + Up/Down      snap to top/bottom half, or a quarter if already on a side;
--                        pressing the opposite key goes back to full height
-- The usable area excludes Waybar (read from the monitor's reserved space).
-- Windows with a minimum size larger than the target zone (e.g. some apps) are
-- anchored to the zone's outer edge instead of being centred over the bar.

local GAP = 10 -- px between windows and screen edges
local TOL = 6  -- px tolerance when detecting the current zone
local SETTLE_MS = 60 -- wait for the compositor to apply min-size limits

local MOD = hyde.config.modifiers.main

local function near(a, b)
    return math.abs(a - b) <= TOL
end

local function geometry(mon)
    local inv = 1 / (mon.scale or 1)
    local r = mon.reserved or {}
    local rl, rt = (r.left or 0) * inv, (r.top or 0) * inv
    local rr, rb = (r.right or 0) * inv, (r.bottom or 0) * inv
    return {
        x = mon.x + rl + GAP,
        y = mon.y + rt + GAP,
        w = mon.width * inv - rl - rr - 2 * GAP,
        h = mon.height * inv - rt - rb - 2 * GAP,
    }
end

-- HyDE's monocle layout keeps tiled windows in a maximized state, which makes
-- Hyprland refuse to move or resize them even once floating. Leave it first.
local function release(win)
    if (tonumber(win.fullscreen) or 0) ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen_state({internal = 0, client = 0, window = win}))
    end
end

-- SUPER + F: tiled -> floating (a screen-filling window comes out at 70%, centred
-- so the change is visible); floating -> tiled.
local function toggle_float()
    local win = hl.get_active_window()
    if not win then
        return
    end
    if win.floating then
        hl.dispatch(hl.dsp.window.float({action = "toggle"}))
        return
    end
    local mon = win.monitor or hl.get_active_monitor()
    local u = mon and geometry(mon)
    local fills = u and win.size.x >= u.w - TOL and win.size.y >= u.h - TOL
    release(win)
    hl.dispatch(hl.dsp.window.float({action = "toggle"}))
    if fills then
        local w, h = math.floor(u.w * 0.7), math.floor(u.h * 0.7)
        hl.dispatch(hl.dsp.window.resize({window = win, x = w, y = h, exact = true}))
        hl.dispatch(hl.dsp.window.move({
            window = win,
            x = math.floor(u.x + (u.w - w) / 2),
            y = math.floor(u.y + (u.h - h) / 2),
            exact = true,
        }))
    end
end

local function snap(dir)
    local win = hl.get_active_window()
    if not win then
        return
    end
    local mon = win.monitor or hl.get_active_monitor()
    if not mon then
        return
    end

    local u = geometry(mon)
    local hw = math.floor((u.w - GAP) / 2)
    local hh = math.floor((u.h - GAP) / 2)

    -- which zone is the window in right now? (from where it is anchored)
    local hz, vt -- hz: "L"/"R"/nil, vt: "T"/"B"/nil
    if win.floating then
        local ax, ay = win.at.x, win.at.y
        local w, h = win.size.x, win.size.y
        if w < u.w - TOL then
            if near(ax, u.x) then
                hz = "L"
            elseif near(ax + w, u.x + u.w) then
                hz = "R"
            end
        end
        if h < u.h - TOL then
            if near(ay, u.y) then
                vt = "T"
            elseif near(ay + h, u.y + u.h) then
                vt = "B"
            end
        end
    end

    if dir == "left" then
        hz = "L"
    elseif dir == "right" then
        hz = "R"
    elseif dir == "up" then
        if vt == "B" then vt = nil else vt = "T" end
    elseif dir == "down" then
        if vt == "T" then vt = nil else vt = "B" end
    end

    local x, w = u.x, u.w
    if hz == "L" then
        w = hw
    elseif hz == "R" then
        x, w = u.x + hw + GAP, hw
    end
    local y, h = u.y, u.h
    if vt == "T" then
        h = hh
    elseif vt == "B" then
        y, h = u.y + hh + GAP, hh
    end
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)

    release(win)
    if not win.floating then
        hl.dispatch(hl.dsp.window.float({action = "toggle"}))
    end
    hl.dispatch(hl.dsp.window.resize({window = win, x = w, y = h, exact = true}))
    hl.dispatch(hl.dsp.window.move({window = win, x = x, y = y, exact = true}))

    -- Some windows refuse to get as small as asked and the compositor then
    -- re-centres them on the requested box, which can push them over the bar.
    -- Once the real size is known, re-anchor to the zone's outer edges.
    hl.timer(function()
        local aw, ah = win.size.x, win.size.y
        local fx, fy = x, y
        if hz == "R" then fx = math.floor(u.x + u.w - aw) end
        if vt == "B" then fy = math.floor(u.y + u.h - ah) end
        fx = math.max(fx, math.floor(u.x))
        fy = math.max(fy, math.floor(u.y))
        if fx ~= win.at.x or fy ~= win.at.y then
            hl.dispatch(hl.dsp.window.move({window = win, x = fx, y = fy, exact = true}))
        end
    end, {timeout = SETTLE_MS, type = "oneshot"})
end

hl.bind(MOD .. " + F", toggle_float, {
    description = "[Window Management] toggle floating",
})

local keys = {Left = "left", Right = "right", Up = "up", Down = "down"}
for key, dir in pairs(keys) do
    hl.bind(MOD .. " + " .. key, function() snap(dir) end, {
        description = "[Window Management|Snap] snap " .. dir,
    })
end

