--[[
    This extension captures the initially opened media (both its file name and full URI),
    loads all media files from that file's folder into VLC's playlist, and then jumps to the captured media.
    
    Navigation commands (next/previous) work relative to the current item, with wrap-around behavior,
    regardless of VLC's loop settings.


    Open any file in VLC and the rest of its folder is queued in alphabetical order.
    Install to: %APPDATA%\vlc\lua\intf\autoplay.lua  (see README)
--]]
local media_ext = {}
for e in ([[avi mkv mp4 wmv flv mpeg mpg mov rm vob asf divx m4v ogg ogm ogv qt
rmvb webm 3gp 3g2 drc f4v f4p f4a f4b gifv mng mts m2ts ts mxf nsv roq svi viv
mp3 wav flac aac wma alac ape ac3 opus aiff aif amr au mka dts m4a m4b m4p mpc
mpp oga spx tta voc ra mid midi]]):gmatch("%S+") do
    media_ext[e] = true
end

local last_key = nil

local function is_media(name)
    local ext = name:match("%.([^%.]+)$")
    return ext and media_ext[ext:lower()] or false
end

-- Natural, case-insensitive sort key ("file2" < "file10")
local function sort_key(name)
    return (name:lower():gsub("%d+", function(d)
        return string.rep("0", 12 - #d) .. d
    end))
end

local function uri_to_path(uri)
    local p = vlc.strings.decode_uri(uri)
    p = p:gsub("^file://", "")
    if p:match("^/%a:") then p = p:sub(2) end   -- Windows: /C:/... -> C:/...
    return p
end

local function path_to_uri(path)
    local enc = path:gsub("[^%w%-%._~/:]", function(c)
        return string.format("%%%02X", c:byte())
    end)
    if enc:match("^%a:") then return "file:///" .. enc end
    return "file://" .. enc
end

local function norm(p) return p:lower() end

local function wait_ms(ms)
    vlc.misc.mwait(vlc.misc.mdate() + ms * 1000)
end

-- Returns a map of path -> playlist id, and how many items the playlist has
local function playlist_info()
    local set, count = {}, 0
    local function walk(node)
        if node.path then
            set[norm(uri_to_path(node.path))] = node.id
            count = count + 1
        end
        if node.children then
            for _, c in ipairs(node.children) do walk(c) end
        end
    end
    local ok, pl = pcall(vlc.playlist.get, "normal")
    if ok and pl then walk(pl) end
    return set, count
end

-- Current input state: 3 = playing, 4 = paused (VLC 3.x)
local function input_state()
    local i = vlc.object.input()
    if not i then return nil end
    local ok, v = pcall(vlc.var.get, i, "state")
    if ok then return v end
    return nil
end

local function cur_time()
    local i = vlc.object.input()
    if i then
        local ok, v = pcall(vlc.var.get, i, "time")
        if ok and v then return v end
    end
    return 0
end

local function current_id()
    local ok, id = pcall(vlc.playlist.current)
    if ok then return id end
    return nil
end

-- Rebuild the playlist in order while paused and muted, so nothing is
-- seen or heard until everything is ready.
local function rebuild(folder, files, path, existing, count_before)
    local vol = vlc.volume.get()
    local was_paused = (vlc.playlist.status() == "paused")
    local t = cur_time()

    -- freeze immediately
    pcall(vlc.volume.set, 0)
    if not was_paused then pcall(vlc.playlist.pause) end

    -- give VLC time to apply any resume-position jump, then read the time
    wait_ms(300)
    local t2 = cur_time()
    if t2 > t then t = t2 end

    local function finish(target)
        if not was_paused then
            local st = vlc.playlist.status()
            if st == "paused" then
                pcall(vlc.playlist.pause)            -- toggles back to playing
            elseif st == "stopped" and target then
                pcall(vlc.playlist.goto, target)     -- never fall back to item 1
            end
        end
        if vol and vol > 0 then pcall(vlc.volume.set, vol) end
    end

    -- remember the id(s) of the item(s) currently in the playlist
    local old_ids = {}
    for _, id in pairs(existing) do old_ids[id] = true end

    local list = {}
    for _, f in ipairs(files) do
        table.insert(list, {path = path_to_uri(folder .. f), name = f})
    end
    vlc.playlist.enqueue(list)     -- full sorted folder, no clear()

    -- wait until VLC has actually registered every file (up to ~10 s)
    local expected = count_before + #list
    for _ = 1, 100 do
        wait_ms(100)
        local _, c = playlist_info()
        if c >= expected then break end
    end
    wait_ms(200)

    -- find the NEW entry for the opened file (its id is not an old one)
    local new_id
    local function walk(node)
        if node.path and node.id and not old_ids[node.id]
           and norm(uri_to_path(node.path)) == norm(path) then
            new_id = node.id
        end
        if node.children then
            for _, c in ipairs(node.children) do walk(c) end
        end
    end
    local okp, pl = pcall(vlc.playlist.get, "normal")
    if okp and pl then walk(pl) end
    if not new_id then finish(nil) return end

    -- jump to the new copy and wait until VLC confirms it is the current
    -- item AND it is really playing (videos need longer than audio)
    vlc.playlist.goto(new_id)
    local ready = false
    for _ = 1, 200 do                       -- up to ~10 s
        wait_ms(50)
        if current_id() == new_id and input_state() == 3 then
            ready = true
            break
        end
    end

    if ready then
        pcall(vlc.playlist.pause)           -- freeze the new copy
        wait_ms(150)
        local i2 = vlc.object.input()
        -- restore the position and verify it stuck (times are in microseconds)
        if i2 and t > 1000000 then
            for _ = 1, 20 do
                pcall(vlc.var.set, i2, "time", t)
                wait_ms(250)
                if math.abs(cur_time() - t) < 2000000 then break end
            end
        end
    end

    -- only remove the old copy once the new one is current
    if current_id() == new_id then
        for id in pairs(old_ids) do
            pcall(vlc.playlist.delete, id)
        end
        wait_ms(100)
    end

    finish(new_id)
end

local function populate()
    local item = vlc.input.item()
    if not item then return end
    local uri = item:uri()
    if not uri or not uri:match("^file:") then return end

    local path = uri_to_path(uri)
    local folder, current = path:match("^(.*/)([^/]+)$")
    if not folder then return end

    if last_key == norm(path) then return end   -- once per file
    last_key = norm(path)

    local ok, entries = pcall(vlc.io.readdir, folder)
    if not ok or not entries then return end

    local files = {}
    for _, f in ipairs(entries) do
        if f ~= "." and f ~= ".." and is_media(f) then
            table.insert(files, f)
        end
    end
    table.sort(files, function(a, b)
        local ka, kb = sort_key(a), sort_key(b)
        if ka == kb then return a < b end
        return ka < kb
    end)

    local existing, count = playlist_info()

    -- CASE 1: the playlist holds only the file that was just opened.
    if count <= 1 then
        rebuild(folder, files, path, existing, count)
        -- the swapped-in file is now the playing one; don't re-trigger on it
        last_key = norm(path)
        return
    end

    -- CASE 2: the playlist already has other items (your own queue).
    -- Don't touch it, only append missing files.
    existing[norm(path)] = true
    local to_add = {}
    for _, f in ipairs(files) do
        if not existing[norm(folder .. f)] then
            table.insert(to_add, {path = path_to_uri(folder .. f), name = f})
        end
    end
    if #to_add > 0 then vlc.playlist.enqueue(to_add) end
end

-- Main loop: check 5 times per second until VLC quits
while true do
    if vlc.volume.get() == -256 then break end   -- VLC is shutting down
    pcall(populate)
    wait_ms(200)
end
