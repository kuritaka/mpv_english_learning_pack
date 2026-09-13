-- mpv version
-- English/Japanese-aware wrapping

local mp = require "mp"
local utils = require "mp.utils"

local o = {
    panel_ratio = 0.50,
    prev_count = 2,
    next_count = 2,
    font_size = 27,
    current_font_size = 27,
    line_gap = 14,
    block_gap = 22,
    margin_x = 28,
    current_marker = "",
    -- Increase if wrapping happens too early; decrease if text goes too far right.
    wrap_width_scale = 1.08,
}

local overlay = mp.create_osd_overlay("ass-events")
local cues = {}
local enabled = true
local active_index = nil
local last_render_key = ""

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ass_escape(s)
    if not s then return "" end
    local ok, escaped = pcall(mp.command_native, {"escape-ass", s})
    if ok and escaped then return escaped end
    return s:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}")
end

local function basename_no_ext(path)
    if not path then return nil end
    local name = path:gsub("\\", "/"):match("([^/]+)$") or path
    return name:gsub("%.[^%.]+$", "")
end

local function dirname(path)
    if not path then return nil end
    local d = path:gsub("\\", "/"):match("^(.*)/[^/]*$")
    return (d and d ~= "") and d or "."
end

local function parse_time(t)
    local h,m,s,ms = t:match("(%d+):(%d+):(%d+)[,.](%d+)")
    if not h then
        h,m,s = t:match("(%d+):(%d+):(%d+)")
        ms = "0"
    end
    if not h then return nil end
    return tonumber(h)*3600 + tonumber(m)*60 + tonumber(s) + tonumber(ms)/(10^#ms)
end

local function line_kind(s)
    for i = 1, #s do
        local b = s:byte(i)
        if b and b >= 0x80 then return "cjk" end
    end
    return "latin"
end

local function clean_text(s)
    s = s:gsub("<br%s*/?>", "\n")
         :gsub("<[^>]->", "")
         :gsub("{\\[^}]-}", "")
         :gsub("\r", "")

    local src = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        line = trim(line)
        if line ~= "" then
            table.insert(src, {text=line, kind=line_kind(line)})
        end
    end
    if #src == 0 then return "" end

    local groups, kind, current = {}, nil, ""
    for _, item in ipairs(src) do
        if not kind then
            kind, current = item.kind, item.text
        elseif item.kind == kind then
            if kind == "latin" then
                current = current .. " " .. item.text
            else
                current = current .. item.text
            end
        else
            table.insert(groups, trim(current))
            kind, current = item.kind, item.text
        end
    end
    if current ~= "" then table.insert(groups, trim(current)) end

    -- Keep English and Japanese groups on separate lines.
    return table.concat(groups, "\n")
end

local function parse_srt(path)
    local f = io.open(path, "rb")
    if not f then return {} end
    local data = f:read("*all")
    f:close()

    data = data:gsub("^\239\187\191", "")
               :gsub("\r\n", "\n")
               :gsub("\r", "\n") .. "\n\n"

    local result = {}
    for block in data:gmatch("(.-)\n\n+") do
        local lines = {}
        for line in block:gmatch("[^\n]+") do table.insert(lines, line) end

        local ti
        for i,line in ipairs(lines) do
            if line:find("%-%->") then ti = i break end
        end

        if ti then
            local left,right = lines[ti]:match("^%s*(.-)%s+%-%->%s+(.-)%s*$")
            if left and right then
                right = right:match("^([^%s]+)") or right
                local st, et = parse_time(left), parse_time(right)
                if st and et then
                    local parts = {}
                    for i=ti+1,#lines do table.insert(parts, lines[i]) end
                    local text = clean_text(table.concat(parts, "\n"))
                    if text ~= "" then
                        table.insert(result, {start=st, finish=et, text=text})
                    end
                end
            end
        end
    end

    table.sort(result, function(a,b) return a.start < b.start end)
    return result
end

local function choose_external_srt()
    local tracks = mp.get_property_native("track-list") or {}
    local selected, fallback
    for _,tr in ipairs(tracks) do
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

    local base, dir = basename_no_ext(media_path), dirname(media_path)
    if not base or not dir then return nil end

    local base_lower, candidates = base:lower(), {}
    for _,name in ipairs(utils.readdir(dir, "files") or {}) do
        if name:lower():match("%.srt$") then
            local stem = name:gsub("%.[^%.]+$", "")
            local sl = stem:lower()
            if sl == base_lower or sl:sub(1,#base_lower) == base_lower then
                table.insert(candidates, name)
            end
        end
    end

    table.sort(candidates, function(a,b)
        if #a == #b then return a:lower() < b:lower() end
        return #a < #b
    end)

    if #candidates == 0 then return nil end
    local sep = package.config:sub(1,1)
    return dir:gsub("/", sep) .. sep .. candidates[1]
end

local function utf8_next(s, i)
    local b = s:byte(i)
    if not b then return nil, i end
    local len
    if b < 0x80 then len = 1
    elseif b < 0xE0 then len = 2
    elseif b < 0xF0 then len = 3
    else len = 4 end
    return s:sub(i, i+len-1), i+len
end

local function char_width_px(ch, fs)
    local b = ch:byte(1)
    if not b then return 0 end
    if b >= 0x80 then return fs * 0.82 end
    if ch == " " then return fs * 0.28 end
    if ch:match("[ilI%.,'`:;!|]") then return fs * 0.24 end
    if ch:match("[MW@%%&QO]") then return fs * 0.66 end
    if ch:match("[mw]") then return fs * 0.60 end
    if ch:match("[A-Z0-9]") then return fs * 0.48 end
    return fs * 0.46
end

local function text_width_px(s, fs)
    local width, i = 0, 1
    while i <= #s do
        local ch
        ch, i = utf8_next(s, i)
        if ch then width = width + char_width_px(ch, fs) end
    end
    return width
end

local function tokenize_line(s)
    local tokens, word, i = {}, "", 1

    local function flush()
        if word ~= "" then
            table.insert(tokens, word)
            word = ""
        end
    end

    while i <= #s do
        local ch
        ch, i = utf8_next(s, i)
        if not ch then break end
        local b = ch:byte(1)

        if b and b >= 0x80 then
            flush()
            table.insert(tokens, ch)
        elseif ch == " " then
            flush()
            table.insert(tokens, " ")
        else
            word = word .. ch
        end
    end
    flush()
    return tokens
end

local function split_long_token(token, fs, max_width)
    local out, current, width, i = {}, "", 0, 1
    while i <= #token do
        local ch
        ch, i = utf8_next(token, i)
        local cw = char_width_px(ch, fs)
        if current ~= "" and width + cw > max_width then
            table.insert(out, current)
            current, width = ch, cw
        else
            current = current .. ch
            width = width + cw
        end
    end
    if current ~= "" then table.insert(out, current) end
    return out
end

local function wrap_logical_line(line, fs, max_width)
    line = trim(line)
    if line == "" then return {""} end

    local result, current, width = {}, "", 0

    local function flush()
        local out = trim(current)
        if out ~= "" then table.insert(result, out) end
        current, width = "", 0
    end

    for _,token in ipairs(tokenize_line(line)) do
        local tw = text_width_px(token, fs)

        if token == " " then
            if current ~= "" then
                current = current .. " "
                width = width + tw
            end
        elseif tw > max_width then
            flush()
            local pieces = split_long_token(token, fs, max_width)
            for i=1,#pieces-1 do table.insert(result, pieces[i]) end
            current = pieces[#pieces] or ""
            width = text_width_px(current, fs)
        elseif current ~= "" and width + tw > max_width then
            flush()
            current, width = token, tw
        else
            current = current .. token
            width = width + tw
        end
    end

    flush()
    return (#result > 0) and result or {""}
end

local function wrap_text(text, fs, max_width)
    local result = {}
    for logical_line in (text .. "\n"):gmatch("(.-)\n") do
        for _,line in ipairs(wrap_logical_line(logical_line, fs, max_width)) do
            table.insert(result, line)
        end
    end
    return result
end

local function find_active_index(t)
    if #cues == 0 then return nil end
    for i,c in ipairs(cues) do
        if t >= c.start and t <= c.finish then return i end
        if c.start > t then return i end
    end
    return #cues
end

local function render()
    if not enabled or #cues == 0 then
        overlay.data = ""
        overlay:update()
        return
    end

    local w,h = mp.get_osd_size()
    if not w or not h or w <= 0 or h <= 0 then return end

    local idx = find_active_index(mp.get_property_number("time-pos", 0))
    if not idx then return end
    active_index = idx

    local key = table.concat({idx,w,h,tostring(enabled)}, ":")
    if key == last_render_key then return end
    last_render_key = key

    overlay.res_x, overlay.res_y = w,h

    local panel_left = math.floor(w * (1 - o.panel_ratio))
    local panel_width = w - panel_left
    local x = panel_left + o.margin_x
    local usable_width = math.max(1, panel_width - o.margin_x*2)
    local max_text_width = usable_width * o.wrap_width_scale

    local first = math.max(1, idx-o.prev_count)
    local last = math.min(#cues, idx+o.next_count)
    local blocks, total_h = {}, 0

    for i=first,last do
        local current = (i == idx)
        local fs = current and o.current_font_size or o.font_size
        local marker = current and o.current_marker or ""
        local lines = wrap_text(marker .. cues[i].text, fs, max_text_width)
        local bh = #lines * (fs + o.line_gap) + o.block_gap
        table.insert(blocks, {lines=lines,fs=fs,h=bh,current=current})
        total_h = total_h + bh
    end

    local y = math.max(35, math.floor((h-total_h)/2))
    local ass = {}

    for _,b in ipairs(blocks) do
        local parts = {}
        for _,line in ipairs(b.lines) do table.insert(parts, ass_escape(line)) end
        local joined = table.concat(parts, "\\N")

        local style
        if b.current then
            style = string.format(
                "{\\an7\\q2\\pos(%d,%d)\\fs%d\\b0\\c&H80FFFF&\\bord1.5\\shad0}",
                x,y,b.fs
            )
        else
            style = string.format(
                "{\\an7\\q2\\pos(%d,%d)\\fs%d\\b0\\c&HC8C8C8&\\bord1\\shad0}",
                x,y,b.fs
            )
        end

        table.insert(ass, style .. joined)
        y = y + b.h
    end

    overlay.data = table.concat(ass, "\n")
    overlay:update()
end

local function load_subtitles()
    cues, active_index, last_render_key = {}, nil, ""

    local path = choose_external_srt() or choose_matching_srt()
    if not path then
        mp.osd_message("English subtitles: matching SRT not found", 3)
        return
    end

    cues = parse_srt(path)
    if #cues == 0 then
        mp.osd_message("English subtitles: SRT could not be parsed", 3)
        return
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
    local t = mp.get_property_number("time-pos",0)
    local idx = find_active_index(t) or 1
    if cues[idx] and t-cues[idx].start > 0.7 then jump_to(idx)
    else jump_to(idx-1) end
end

local function next_sub()
    jump_to((find_active_index(mp.get_property_number("time-pos",0)) or 1)+1)
end

local function replay_sub()
    jump_to(find_active_index(mp.get_property_number("time-pos",0)) or 1)
end

local function toggle()
    enabled = not enabled
    last_render_key = ""
    render()
end

mp.register_event("file-loaded", function() mp.add_timeout(0.20, load_subtitles) end)
mp.observe_property("time-pos","number",function()
    local idx = find_active_index(mp.get_property_number("time-pos",0))
    if idx ~= active_index then last_render_key=""; render() end
end)
mp.observe_property("osd-width","number",function() last_render_key=""; render() end)
mp.observe_property("osd-height","number",function() last_render_key=""; render() end)

mp.register_script_message("english-subs-prev",prev_sub)
mp.register_script_message("english-subs-next",next_sub)
mp.register_script_message("english-subs-replay",replay_sub)
mp.register_script_message("english-subs-toggle",toggle)

mp.register_event("end-file",function()
    cues = {}
    active_index = nil
    last_render_key = ""
    overlay.data = ""
    overlay:update()
end)
