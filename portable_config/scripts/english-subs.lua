-- english-subs.lua
-- English-learning side panel for mpv.
-- Displays: previous 2 cues + current cue + next 2 cues.
-- Designed for a 60% video / 40% subtitle layout.

local mp = require "mp"
local utils = require "mp.utils"
local options = require "mp.options"

local o = {
    panel_ratio = 0.40,
    prev_count = 2,
    next_count = 2,
    font_size = 27,
    current_font_size = 32,
    max_chars = 43,
    line_gap = 14,
    block_gap = 22,
    margin_x = 28,
    current_marker = "▶ ",
}
options.read_options(o, "english-subs")

local overlay = mp.create_osd_overlay("ass-events")
local cues = {}
local subtitle_path = nil
local enabled = true
local active_index = nil
local last_render_key = ""

local function ass_escape(s)
    if not s then return "" end
    local ok, escaped = pcall(mp.command_native, {"escape-ass", s})
    if ok and escaped then return escaped end
    -- Fallback for older mpv builds.
    s = s:gsub("\\", "\\\\")
    s = s:gsub("{", "\\{")
    s = s:gsub("}", "\\}")
    return s
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function basename_no_ext(path)
    if not path then return nil end
    local name = path:gsub("\\", "/"):match("([^/]+)$") or path
    return name:gsub("%.[^%.]+$", "")
end

local function dirname(path)
    if not path then return nil end
    local normalized = path:gsub("\\", "/")
    local d = normalized:match("^(.*)/[^/]*$")
    if not d or d == "" then return "." end
    return d
end

local function parse_time(t)
    local h, m, s, ms = t:match("(%d+):(%d+):(%d+)[,.](%d+)")
    if not h then
        h, m, s = t:match("(%d+):(%d+):(%d+)")
        ms = "0"
    end
    if not h then return nil end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms or 0) / (10 ^ #(ms or "0"))
end

local function clean_text(s)
    -- Remove common subtitle markup while keeping readable text.
    s = s:gsub("<br%s*/?>", "\n")
    s = s:gsub("<[^>]->", "")
    s = s:gsub("{\\[^}]-}", "")
    s = s:gsub("\r", "")
    s = s:gsub("\n%s*\n+", "\n")
    return trim(s)
end

local function parse_srt(path)
    local f = io.open(path, "rb")
    if not f then
        mp.msg.warn("english-subs: could not open subtitle: " .. tostring(path))
        return {}
    end
    local data = f:read("*all")
    f:close()

    -- UTF-8 BOM
    data = data:gsub("^\239\187\191", "")
    data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
    data = data .. "\n\n"

    local result = {}
    for block in data:gmatch("(.-)\n\n+") do
        local lines = {}
        for line in block:gmatch("[^\n]+") do
            table.insert(lines, line)
        end

        local time_line_idx = nil
        for i, line in ipairs(lines) do
            if line:find("%-%->") then
                time_line_idx = i
                break
            end
        end

        if time_line_idx then
            local left, right = lines[time_line_idx]:match("^%s*(.-)%s+%-%->%s+(.-)%s*$")
            if left and right then
                right = right:match("^([^%s]+)") or right
                local start_t = parse_time(left)
                local end_t = parse_time(right)
                if start_t and end_t then
                    local text_parts = {}
                    for i = time_line_idx + 1, #lines do
                        table.insert(text_parts, lines[i])
                    end
                    local text = clean_text(table.concat(text_parts, "\n"))
                    if text ~= "" then
                        table.insert(result, {
                            start = start_t,
                            finish = end_t,
                            text = text,
                        })
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.start < b.start end)
    return result
end

local function choose_external_srt_from_tracks()
    local tracks = mp.get_property_native("track-list") or {}
    local selected = nil
    local fallback = nil

    for _, tr in ipairs(tracks) do
        if tr.type == "sub" and tr.external and tr["external-filename"] then
            local p = tr["external-filename"]
            if p:lower():match("%.srt$") then
                if tr.selected then selected = p end
                fallback = fallback or p
            end
        end
    end
    return selected or fallback
end

local function choose_matching_srt()
    local media_path = mp.get_property("path")
    if not media_path or media_path:match("^%a+://") then return nil end

    local media_base = basename_no_ext(media_path)
    local dir = dirname(media_path)
    if not media_base or not dir then return nil end

    local files = utils.readdir(dir, "files") or {}
    local base_lower = media_base:lower()
    local candidates = {}

    for _, name in ipairs(files) do
        local lower = name:lower()
        if lower:match("%.srt$") then
            local stem = name:gsub("%.[^%.]+$", "")
            local stem_lower = stem:lower()
            -- Accept exact names and names with notes appended after the video base name.
            if stem_lower == base_lower or stem_lower:sub(1, #base_lower) == base_lower then
                table.insert(candidates, name)
            end
        end
    end

    table.sort(candidates, function(a, b)
        if #a == #b then return a:lower() < b:lower() end
        return #a < #b
    end)

    if #candidates == 0 then return nil end

    local sep = package.config:sub(1,1)
    local real_dir = dir:gsub("/", sep)
    return real_dir .. sep .. candidates[1]
end

local function wrap_line(line, max_chars)
    line = trim(line)
    if line == "" then return {""} end
    if #line <= max_chars then return {line} end

    local out, current = {}, ""
    for word in line:gmatch("%S+") do
        if current == "" then
            current = word
        elseif #current + 1 + #word <= max_chars then
            current = current .. " " .. word
        else
            table.insert(out, current)
            current = word
        end
    end
    if current ~= "" then table.insert(out, current) end
    return out
end

local function wrap_text(text, max_chars)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local wrapped = wrap_line(line, max_chars)
        for _, w in ipairs(wrapped) do table.insert(out, w) end
    end
    return out
end

local function find_active_index(t)
    if #cues == 0 then return nil end

    -- Active cue first.
    for i, cue in ipairs(cues) do
        if t >= cue.start and t <= cue.finish then return i end
        if cue.start > t then
            -- During gaps, treat the upcoming cue as current so that five useful lines remain visible.
            return i
        end
    end
    return #cues
end

local function render()
    if not enabled or #cues == 0 then
        overlay.data = ""
        overlay:update()
        return
    end

    local w, h = mp.get_osd_size()
    if not w or not h or w <= 0 or h <= 0 then return end

    local t = mp.get_property_number("time-pos", 0)
    local idx = find_active_index(t)
    if not idx then return end
    active_index = idx

    local first = math.max(1, idx - o.prev_count)
    local last = math.min(#cues, idx + o.next_count)

    local render_key = tostring(idx) .. ":" .. tostring(w) .. ":" .. tostring(h) .. ":" .. tostring(enabled)
    if render_key == last_render_key then return end
    last_render_key = render_key

    overlay.res_x = w
    overlay.res_y = h

    local panel_left = math.floor(w * (1 - o.panel_ratio))
    local x = panel_left + o.margin_x
    local panel_width = w - panel_left - o.margin_x * 2
    local chars = math.max(24, math.floor(o.max_chars * (panel_width / math.max(420, panel_width))))

    -- Estimate vertical height, then center all five cue blocks.
    local blocks = {}
    local total_h = 0

    for i = first, last do
        local is_current = (i == idx)
        local marker = is_current and o.current_marker or ""
        local lines = wrap_text(marker .. cues[i].text, chars)
        local fs = is_current and o.current_font_size or o.font_size
        local line_h = fs + o.line_gap
        local block_h = #lines * line_h + o.block_gap
        table.insert(blocks, {index=i, lines=lines, fs=fs, h=block_h, current=is_current})
        total_h = total_h + block_h
    end

    local y = math.max(35, math.floor((h - total_h) / 2))
    local ass = {}

    -- Left align within the right-side panel.
    for _, block in ipairs(blocks) do
        local text = {}
        for _, line in ipairs(block.lines) do
            table.insert(text, ass_escape(line))
        end
        local joined = table.concat(text, "\\N")

        if block.current then
            -- Current subtitle: larger + bold + highlighted.
            table.insert(ass,
                string.format("{\\an7\\pos(%d,%d)\\fs%d\\b1\\c&H80FFFF&\\bord1.5\\shad0}%s",
                    x, y, block.fs, joined))
        else
            -- Context subtitles: slightly dimmer.
            table.insert(ass,
                string.format("{\\an7\\pos(%d,%d)\\fs%d\\b0\\c&HC8C8C8&\\bord1\\shad0}%s",
                    x, y, block.fs, joined))
        end
        y = y + block.h
    end

    overlay.data = table.concat(ass, "\n")
    overlay:update()
end

local function load_subtitles()
    cues = {}
    subtitle_path = choose_external_srt_from_tracks() or choose_matching_srt()
    active_index = nil
    last_render_key = ""

    if not subtitle_path then
        mp.msg.warn("english-subs: matching SRT not found")
        mp.osd_message("English subtitles: matching SRT not found", 3)
        render()
        return
    end

    cues = parse_srt(subtitle_path)
    if #cues == 0 then
        mp.msg.warn("english-subs: no SRT cues parsed from " .. subtitle_path)
        mp.osd_message("English subtitles: SRT could not be parsed", 3)
    else
        mp.msg.info(string.format("english-subs: loaded %d cues from %s", #cues, subtitle_path))
        mp.osd_message("English subtitles loaded: " .. (basename_no_ext(subtitle_path) or subtitle_path), 2)
    end
    render()
end

local function jump_to(index)
    if #cues == 0 then return end
    index = math.max(1, math.min(#cues, index))
    mp.commandv("seek", tostring(cues[index].start), "absolute+exact")
    last_render_key = ""
    render()
end

local function prev_sub()
    local t = mp.get_property_number("time-pos", 0)
    local idx = find_active_index(t) or 1
    -- If already a little way into the current cue, replay it first.
    if cues[idx] and t - cues[idx].start > 0.7 then
        jump_to(idx)
    else
        jump_to(idx - 1)
    end
end

local function next_sub()
    local t = mp.get_property_number("time-pos", 0)
    local idx = find_active_index(t) or 1
    jump_to(idx + 1)
end

local function replay_sub()
    local t = mp.get_property_number("time-pos", 0)
    local idx = find_active_index(t) or 1
    jump_to(idx)
end

local function toggle()
    enabled = not enabled
    last_render_key = ""
    mp.osd_message(enabled and "English subtitle panel: ON" or "English subtitle panel: OFF", 1.5)
    render()
end

mp.register_event("file-loaded", function()
    -- Give mpv a moment to populate external track metadata.
    mp.add_timeout(0.20, load_subtitles)
end)

mp.observe_property("time-pos", "number", function()
    local old = active_index
    local t = mp.get_property_number("time-pos", 0)
    local idx = find_active_index(t)
    if idx ~= old then
        last_render_key = ""
        render()
    end
end)

mp.observe_property("osd-width", "number", function()
    last_render_key = ""
    render()
end)

mp.observe_property("osd-height", "number", function()
    last_render_key = ""
    render()
end)

mp.register_script_message("english-subs-prev", prev_sub)
mp.register_script_message("english-subs-next", next_sub)
mp.register_script_message("english-subs-replay", replay_sub)
mp.register_script_message("english-subs-toggle", toggle)

mp.register_event("end-file", function()
    cues = {}
    active_index = nil
    last_render_key = ""
    overlay.data = ""
    overlay:update()
end)
