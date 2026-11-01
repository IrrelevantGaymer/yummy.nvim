local M = {}

local ns = vim.api.nvim_create_namespace("yummy_highlight")
local center_ns = vim.api.nvim_create_namespace("yummy_center")

-- Linked with `default` so a colorscheme or your init.lua can override them.
local groups = {
    YummyQuote             = "String",
    YummyName              = "Identifier",
    YummyNameQuoted        = "Special",
    YummyChapter           = "Title",
    YummyCharacterHeader   = "Type",
    YummyCharacterAlias    = "Type",
    YummyTabHeader         = "Function",
    YummyBlockquote        = "Comment",
    YummySongName          = "Constant",
    YummySongArtist        = "Number",
    YummyTodo              = "Todo",
    YummyComment           = "Comment",
    YummySeparator         = "Comment",
    YummyPunctuation       = "Delimiter",
    YummyPunctuationQuoted = "Operator",
}

function M.define()
    for name, link in pairs(groups) do
        vim.api.nvim_set_hl(0, name, { link = link, default = true })
    end
end

local function is_yummy(ft)
    return ft == "ys" or ft == "yc" or ft == "yo"
end

-- Every character name and alias, longest first so "Aaron Ulysses Birch"
-- wins over "Aaron".
function M.names_for_root(root)
    local data = root and require("yummy.data").get(root)
    local names, seen = {}, {}

    if data and data.characters then
        for _, c in ipairs(data.characters.characters) do
            local list = { c.name }
            vim.list_extend(list, c.aliases or {})
            for _, n in ipairs(list) do
                n = vim.trim(n)
                if n ~= "" and not seen[n] then
                    seen[n] = true
                    table.insert(names, n)
                end
            end
        end
    end

    table.sort(names, function(a, b) return #a > #b end)
    return names
end

local function collect_names(bufnr)
    local root = require("yummy.project").find_root(vim.api.nvim_buf_get_name(bufnr))
    return M.names_for_root(root)
end

-- Center `* * *` scene-break lines in manuscripts.
function M.center(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, center_ns, 0, -1)

    local ft = vim.bo[bufnr].filetype
    if not (ft == "ys" or ft == "yc" or ft == "yo" or ft:match("^yummy%-")) then
        return
    end

    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then
        return
    end

    local info = vim.fn.getwininfo(win)[1]
    local width = info.width - info.textoff

    for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        if line:match("^%s*%* %* %*%s*$") then
            local pad = math.max(math.floor((width - 5) / 2), 0)
            local text = string.rep(" ", pad) .. "* * *"

            -- Cover any extra characters in the real line (stray spaces).
            text = text .. string.rep(" ", math.max(#line - #text, 0))

            vim.api.nvim_buf_set_extmark(bufnr, center_ns, i - 1, 0, {
                virt_text = { { text, "YummySeparator" } },
                virt_text_pos = "overlay",
                virt_text_win_col = 0,
            })
        end
    end
end

-- Find <!-- ... --> spans on a line. `state.open` carries multi-line comments.
-- Returns { {start, end}, ... } as byte positions (1-based, inclusive).
local function comment_spans(line, state)
    local spans, pos = {}, 1
    local start = state.open and 1 or nil

    while pos <= #line do
        if state.open then
            local _, e = line:find("-->", pos, true)
            if not e then
                table.insert(spans, { start, #line })
                return spans
            end
            table.insert(spans, { start, e })
            state.open = false
            pos = e + 1
        else
            local s = line:find("<!--", pos, true)
            if not s then
                break
            end
            state.open = true
            start = s
            pos = s + 4
        end
    end

    if state.open and start and #spans == 0 or (state.open and start and spans[#spans] and spans[#spans][2] < start) then
        table.insert(spans, { start, #line })
    end

    return spans
end

function M.apply(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local ft = vim.bo[bufnr].filetype
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    if not is_yummy(ft) then
        return
    end

    local names = collect_names(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local function mark(row, s, e, hl, prio)
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, s - 1, {
            end_col = e,
            hl_group = hl,
            priority = prio,
        })
    end

    local pattern_cache = {}

    -- Turn "Steven" into "S[Ss]*t+e+v+e+n+" so stretched letters still match.
    -- Only ASCII letters stretch; spaces, punctuation, and multibyte characters stay literal.
    local function name_pattern(name)
        if pattern_cache[name] then
            return pattern_cache[name]
        end

        local out = {}
        local prev_letter = false

        for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            local is_letter = #ch == 1 and ch:match("%a") ~= nil

            if is_letter then
                if not prev_letter and ch:match("%u") then
                    -- Capital at the start of a word: it must be uppercase,
                    -- but its stretched copies may be either case (Ssss).
                    table.insert(out, ch .. "[" .. ch .. ch:lower() .. "]*")
                else
                    table.insert(out, ch .. "+")
                end
            elseif #ch == 1 and ch:match("%p") then
                table.insert(out, "%" .. ch)
            else
                table.insert(out, ch)
            end

            prev_letter = is_letter
        end

        pattern_cache[name] = table.concat(out)
        return pattern_cache[name]
    end

    -- Length of a possessive suffix right after position `e`, or 0.
    local function possessive_len(line, e, name)
        local function ok(suffix)
            return line:sub(e + 1, e + #suffix) == suffix
                and not line:sub(e + #suffix + 1, e + #suffix + 1):match("[%w_]")
        end

        for _, suffix in ipairs({ "'s", "’s" }) do
            if ok(suffix) then return #suffix end
        end

        -- Names ending in "s" can take a bare apostrophe: James'
        if name:sub(-1) == "s" then
            for _, suffix in ipairs({ "'", "’" }) do
                if ok(suffix) then return #suffix end
            end
        end

        return 0
    end

    -- Find every name occurrence in a line. Returns { {start, end}, ... }.
    -- Names are case-sensitive, may be stretched (Steeeven), and may be possessive (Steven's).
    function M.find_names(line, names)
        local found, taken = {}, {}

        for _, name in ipairs(names) do
            local pat = name_pattern(name)
            local start = 1

            while true do
                local s, e = line:find(pat, start)
                if not s then break end
                start = s + 1

                local before = s > 1 and line:sub(s - 1, s - 1) or ""

                if not before:match("[%w_]") then
                    local extra = possessive_len(line, e, name)

                    if extra == 0 and line:sub(e + 1, e + 1):match("[%w_]") then
                        goto continue
                    end

                    e = e + extra

                    for _, t in ipairs(taken) do
                        if s <= t[2] and e >= t[1] then
                            goto continue
                        end
                    end

                    table.insert(taken, { s, e })
                    table.insert(found, { s, e })
                end

                ::continue::
            end
        end

        return found
    end

    -- Color quotes and character names on one line, in any buffer/namespace.
    function M.mark_text(bufnr, target_ns, row, line, names)
        local function mark(s, e, hl, prio)
            vim.api.nvim_buf_set_extmark(bufnr, target_ns, row, s - 1, {
                end_col = e,
                hl_group = hl,
                priority = prio,
            })
        end

        local quotes, open = {}, nil
        for pos in line:gmatch('()"') do
            if open then
                table.insert(quotes, { open, pos })
                mark(open, pos, "YummyQuote", 110)
                open = nil
            else
                open = pos
            end
        end

        -- Punctuation: one color outside quotes, another inside.
        local function punct(s, e)
            local hl = "YummyPunctuation"
            for _, q in ipairs(quotes) do
                if s > q[1] and e < q[2] then
                    hl = "YummyPunctuationQuoted"
                    break
                end
            end
            mark(s, e, hl, 115)
        end

        -- ASCII punctuation: ' - ( ) . , ; : ! ? and so on (not the quote mark).
        for pos in line:gmatch("()%p") do
            if line:sub(pos, pos) ~= '"' then
                punct(pos, pos)
            end
        end

        -- Multibyte punctuation: dashes, curly apostrophes, ellipsis.
        for _, ch in ipairs({ "—", "–" }) do
            local start = 1
            while true do
                local s, e = line:find(ch, start, true)
                if not s then break end
                punct(s, e)
                start = e + 1
            end
        end

        for _, m in ipairs(M.find_names(line, names)) do
            local hl = "YummyName"
            for _, q in ipairs(quotes) do
                if m[1] >= q[1] and m[2] <= q[2] then
                    hl = "YummyNameQuoted"
                    break
                end
            end
            mark(m[1], m[2], hl, 120)
        end
    end

    local function process(row, line)
        -- Headers
        local hashes = line:match("^(#+)%s")
        if hashes then
            local hl = "YummyChapter"
            if ft == "yc" then
                hl = #hashes == 1 and "YummyCharacterHeader" or "YummyTabHeader"
            end
            mark(row, 1, #line, hl, 100)
            return
        end

        -- Blockquotes (manuscripts only); `> song - artist` gets split colors.
        if ft == "ys" and line:match("^>") then
            mark(row, 1, #line, "YummyBlockquote", 100)

            local ns_, name, ne_, as_, artist, ae_ =
                line:match("^>%s*()(.*)()%s+%-%s+()(.-)()%s*$")

            if name and name ~= "" and artist ~= "" then
                mark(row, ns_, ne_ - 1, "YummySongName", 110)
                mark(row, as_, ae_ - 1, "YummySongArtist", 110)
            end
            return
        end

        -- Aliases (character files only)
        if ft == "yc" and line:match("^%s*%-%s+%S") then
            mark(row, 1, #line, "YummyCharacterAlias", 100)
            return
        end

        M.mark_text(bufnr, ns, row, line, names)
    end

        local in_todo = false
    local comment = { open = false }

    for i, line in ipairs(lines) do
        local row = i - 1

        if in_todo then
            if #line > 0 then
                mark(row, 1, #line, "YummyTodo", 140)
            end
            if line:find("-->", 1, true) then
                in_todo = false
            end
        elseif not comment.open and line:match("^%s*<!%-%-%s*TODO") then
            mark(row, 1, #line, "YummyTodo", 140)
            if not line:find("-->", 1, true) then
                in_todo = true
            end
        else
            local was_open = comment.open
            local spans = comment_spans(line, comment)

            if #spans == 0 then
                process(row, line)
            else
                for _, sp in ipairs(spans) do
                    mark(row, sp[1], sp[2], "YummyComment", 140)
                end

                -- Process only the text outside the comments, so names and
                -- quotes inside a comment aren't colored as prose.
                if not was_open then
                    local outside = line
                    for k = #spans, 1, -1 do
                        local sp = spans[k]
                        outside = outside:sub(1, sp[1] - 1)
                            .. string.rep(" ", sp[2] - sp[1] + 1)
                            .. outside:sub(sp[2] + 1)
                    end
                    process(row, outside)
                end
            end
        end
    end

    M.center(bufnr)
end

-- Re-highlight every loaded Yummy buffer (after the index changes).
function M.refresh_all()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and is_yummy(vim.bo[buf].filetype) then
            M.apply(buf)
        end
    end
end

return M