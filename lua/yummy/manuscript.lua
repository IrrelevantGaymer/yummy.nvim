local M = {}

local cache = {}

local function count_words(line)
    local n = 0
    for _ in line:gmatch("%S+") do
        n = n + 1
    end
    return n
end

-- Remove <!-- ... --> spans from a line. `state.open` carries multi-line comments.
local function strip_comments(line, state)
    local out, pos = {}, 1

    while pos <= #line do
        if state.open then
            local _, e = line:find("-->", pos, true)
            if not e then
                break
            end
            state.open = false
            pos = e + 1
        else
            local s = line:find("<!--", pos, true)
            if not s then
                table.insert(out, line:sub(pos))
                break
            end
            table.insert(out, line:sub(pos, s - 1))
            state.open = true
            pos = s + 4
        end
    end

    return table.concat(out)
end

-- Chapters (# headings), TODO lines, and word counts. Cached per buffer change.
function M.analyze(bufnr)
    bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local cached = cache[bufnr]
    if cached and cached.tick == tick then
        return cached
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local info = { tick = tick, chapters = {}, todos = {}, total = 0 }
    local current
    local in_todo = false
    local comment = { open = false }

    for i, line in ipairs(lines) do
        if in_todo then
            if line:find("-->", 1, true) then
                in_todo = false
            end
        elseif not comment.open and line:match("^%s*<!%-%-%s*TODO") then
            local name = line:match("TODO:?%s*(.-)%s*$") or ""
            name = name:gsub("%s*%-%->.*$", "")
            table.insert(info.todos, {
                line = i,
                text = name ~= "" and name or "(unnamed)",
            })
            if not line:find("-->", 1, true) then
                in_todo = true
            end
        else
            local was_open = comment.open
            local text = strip_comments(line, comment)
            local heading = not was_open and line:match("^#%s+(.+)$")

            if heading then
                if current then
                    current.end_line = i - 1
                end
                current = {
                    name = vim.trim(heading),
                    start_line = i,
                    end_line = #lines,
                    words = 0,
                }
                table.insert(info.chapters, current)
            elseif not text:match("^#+%s")          -- headings
                and not text:match("^>")            -- songs / blockquotes
                and not text:match("^%s*%* %* %*%s*$") -- separators
            then
                local n = count_words(text)
                info.total = info.total + n
                if current then
                    current.words = current.words + n
                end
            end
        end
    end

    for _, ch in ipairs(info.chapters) do
        while ch.end_line > ch.start_line and lines[ch.end_line]:match("^%s*$") do
            ch.end_line = ch.end_line - 1
        end
    end

    cache[bufnr] = info
    return info
end

function M.chapter_at(info, row)
    local found
    for _, ch in ipairs(info.chapters) do
        if ch.start_line <= row then
            found = ch
        else
            break
        end
    end
    return found
end

-- Current chapter and total word counts for a cursor row.
function M.words_at(bufnr, row)
    local info = M.analyze(bufnr)
    local ch = M.chapter_at(info, row)
    return { chapter = ch and ch.words or 0, total = info.total }
end

-- For your statusline.
function M.statusline()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].filetype ~= "ys" then
        return ""
    end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local w = M.words_at(bufnr, row)
    return string.format("Ch: %d words | Total: %d words", w.chapter, w.total)
end

local function jump(line, to_end)
    local col = 0
    if to_end then
        local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""
        col = math.max(#text - 1, 0)
    end
    vim.api.nvim_win_set_cursor(0, { line, col })
    vim.cmd("normal! zz")
end

-- Next line past `row` in direction `dir`, wrapping around the list.
local function find(list, row, dir)
    if #list == 0 then return nil end

    if dir > 0 then
        for _, l in ipairs(list) do
            if l > row then return l end
        end
        return list[1]
    else
        for i = #list, 1, -1 do
            if list[i] < row then return list[i] end
        end
        return list[#list]
    end
end

-- Build completion candidates that contain spaces without escaping.
-- Neovim replaces only the last word, so trim each match to start there.
local function complete_from(items, arglead, cmdline)
    local lead = cmdline:gsub("^%S+%s*", "")
    local offset = #lead - #arglead
    local out = {}
    
    for _, full in ipairs(items) do
        if full:sub(1, #lead) == lead then
            table.insert(out, full:sub(offset + 1))
        end
    end
    
    return out
end

local function format_chapter(ch)
    return string.format("%s (%d words)", ch.name, ch.words)
end

function M.complete_chapter(arglead, cmdline)
    local items = {}
    for _, ch in ipairs(M.analyze(0).chapters) do
        table.insert(items, format_chapter(ch))
    end
    return complete_from(items, arglead, cmdline)
end

local function format_todo(t)
    return string.format("(line %d) TODO: %s", t.line, t.text)
end

function M.complete_todo(arglead, cmdline)
    local items = {}
    for _, t in ipairs(M.analyze(0).todos) do
        table.insert(items, format_todo(t))
    end
    return complete_from(items, arglead, cmdline)
end

-- kind: "start" | "end" | "todo"
function M.goto_relative(kind, dir)
    local info = M.analyze(0)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local list = {}

    if kind == "todo" then
        for _, t in ipairs(info.todos) do table.insert(list, t.line) end
    else
        for _, ch in ipairs(info.chapters) do
            table.insert(list, kind == "start" and ch.start_line or ch.end_line)
        end
    end

    local target = find(list, row, dir)
    if target then
        jump(target, kind == "end")
    else
        vim.notify("Yummy: nothing to jump to")
    end
end

function M.goto_chapter(name)
    local info = M.analyze(0)

    local function go(ch)
        if ch then jump(ch.start_line) end
    end

    if name and name ~= "" then
        -- Undo completion escapes and strip the "(N words)" suffix.
        name = name:gsub("%s*%(%d+ words?%)$", "")
        for _, ch in ipairs(info.chapters) do
            if ch.name == name then
                return go(ch)
            end
        end
        vim.notify("Yummy: no chapter named " .. name, vim.log.levels.WARN)
        return
    end

    vim.ui.select(info.chapters, {
        prompt = "Chapter",
        format_item = function(ch)
            return string.format("%s (%d words)", ch.name, ch.words)
        end,
    }, go)
end

function M.goto_todo(arg)
    local info = M.analyze(0)

    if #info.todos == 0 then
        vim.notify("Yummy: no TODOs")
        return
    end

    if arg and arg ~= "" then
        -- Accept "(line #) TODO: name", "(line #)", or just the name.
        local num = arg:match("^%(line (%d+)%)")
        local name = arg:gsub("^%(line %d+%)%s*TODO:%s*", "")
        for _, t in ipairs(info.todos) do
            if (num and t.line == tonumber(num)) or t.text == name then
                return jump(t.line)
            end
        end
        vim.notify("Yummy: no TODO matching " .. arg, vim.log.levels.WARN)
        return
    end

    vim.ui.select(info.todos, {
        prompt = "TODO",
        format_item = format_todo,
    }, function(t)
        if t then jump(t.line) end
    end)
end

return M