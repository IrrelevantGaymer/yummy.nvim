local M = {}

local state = {
    main_win = nil,
    character_win = nil,
    outline_win = nil,

    character_buf = nil,
    outline_buf = nil,

    root = nil,
    active_character = nil,
    active_tab = 1,
    active_chapter = nil,
    mode = nil,
    words = nil,
}

local applying = false
local panel_ns = vim.api.nvim_create_namespace("yummy_panel")
local highlight = require("yummy.highlight")

local function valid_win(win)
    return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
    return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function create_panel(name, filetype)
    local full_name = "yummy://" .. name

    -- Remove any stale buffer left over with the same name.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b):sub(-#full_name) == full_name then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
    end

    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_name(buf, full_name)

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = filetype
    vim.bo[buf].modifiable = false

    return buf
end

-- A builder collects lines plus the highlights to apply to them.
local function new_builder()
    local b = { lines = {}, hls = {}, texts = {} }

    -- Whole line in one highlight group (or none).
    function b.add(line, group)
        table.insert(b.lines, line)
        if group and #line > 0 then
            table.insert(b.hls, { #b.lines - 1, 1, #line, group })
        end
    end

    -- Prose line: quotes and character names get colored.
    function b.add_text(line)
        table.insert(b.lines, line)
        table.insert(b.texts, { #b.lines - 1, line })
    end

    -- One line made of differently colored parts: { {text, group}, ... }
    function b.add_parts(parts)
        local line, pos = "", 0
        local row = #b.lines

        for _, p in ipairs(parts) do
            if p[2] and #p[1] > 0 then
                table.insert(b.hls, { row, pos + 1, pos + #p[1], p[2] })
            end
            line = line .. p[1]
            pos = pos + #p[1]
        end

        table.insert(b.lines, line)
    end

    return b
end

local function set_panel_content(buf, b, names)
    if not valid_buf(buf) then
        return
    end

    b = b or new_builder()

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(buf, panel_ns, 0, -1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, b.lines)
    vim.bo[buf].modifiable = false

    for _, h in ipairs(b.hls) do
        vim.api.nvim_buf_set_extmark(buf, panel_ns, h[1], h[2] - 1, {
            end_col = h[3],
            hl_group = h[4],
            priority = 100,
        })
    end

    for _, t in ipairs(b.texts) do
        highlight.mark_text(buf, panel_ns, t[1], t[2], names or {})
    end

    highlight.center(buf)
end

local function clear_panel(buf)
    set_panel_content(buf, nil, {})
end

local function configure_panel(win, label)
    vim.wo[win].statusline = " " .. label
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].breakindent = false
    vim.wo[win].cursorline = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].list = false
    vim.wo[win].winfixwidth = true
end

local function get_data(root)
    return require("yummy.data").get(root)
end

local function normalize(text)
    return vim.trim(text)
end

-- Find a character name or alias that contains the cursor position.
local function find_character_at_cursor(bufnr, data)
    if not data or not data.characters then
        return nil
    end

    local cursor = vim.api.nvim_win_get_cursor(state.main_win)
    local row = cursor[1]
    local col = cursor[2] + 1

    local line = vim.api.nvim_buf_get_lines(
        bufnr,
        row - 1,
        row,
        false
    )[1] or ""

    local check_line = line
    local best_character
    local best_length = math.huge

    for _, character in ipairs(data.characters.characters or {}) do
        local names = { character.name }

        for _, alias in ipairs(character.aliases or {}) do
            table.insert(names, alias)
        end

        for _, name in ipairs(names) do
            local search = normalize(name)

            if search ~= "" then
                for _, m in ipairs(highlight.find_names(line, { search })) do
                    local len = m[2] - m[1] + 1

                    if col >= m[1] and col <= m[2] and len < best_length then
                        best_character = character
                        best_length = len
                    end
                end
            end
        end
    end

    return best_character
end

-- Find the nearest preceding top-level heading in the active buffer.
local function find_current_chapter(bufnr)
    local cursor = vim.api.nvim_win_get_cursor(state.main_win)
    local lines = vim.api.nvim_buf_get_lines(
        bufnr,
        0,
        cursor[1],
        false
    )

    for i = #lines, 1, -1 do
        local line = lines[i]

        if not line:match("^##") then
            local heading = line:match("^#%s+(.+)%s*$")

            if heading then
                return vim.trim(heading)
            end
        end
    end

    return nil
end

local function render_character(character, tab_index, width)
    local b = new_builder()

    if not character then
        return b
    end

    b.add(character.name, "YummyCharacterHeader")

    for _, alias in ipairs(character.aliases or {}) do
        b.add("    a.k.a. " .. alias, "YummyCharacterAlias")
    end

    b.add("")
    b.add(string.rep("─", width))
    b.add("")

    local tabs = character.tabs or {}

    if #tabs == 0 then
        b.add("No sections defined.")
        return b
    end

    tab_index = math.max(1, math.min(tab_index, #tabs))

    for i, tab in ipairs(tabs) do
        if i == tab_index then
            b.add("> " .. tab.name, "YummyBlockquote")
        else
            b.add("  " .. tab.name, "YummyTabHeader")
        end
    end

    b.add("")
    b.add(string.rep("─", width))
    b.add("")

    for _, line in ipairs(vim.split(tabs[tab_index].content or "", "\n")) do
        b.add_text(line)
    end

    return b
end

local function render_chapter(chapter_name, data)
    local b = new_builder()

    if not chapter_name then
        return b
    end

    if state.words then
        b.add_parts({
            {chapter_name, "YummyChapter"}, 
            {string.format(" (%d words)", state.words.chapter)}
        })
    else
        b.add(chapter_name, "YummyChapter")
    end
    b.add("")

    if not data or not data.outlines then
        b.add("No outline data available.")
        return b
    end

    local chapter = (data.outlines.by_name[normalize(chapter_name)] or {})[1]

    if not chapter or (chapter.content or "") == "" then
        b.add("No chapter notes.")
    else
        for _, line in ipairs(vim.split(chapter.content, "\n")) do
            b.add_text(line)
        end
    end

    return b
end

function M.render()
    if not M.is_open() then
        return
    end

    if state.mode == "yc" or not state.root then
        clear_panel(state.character_buf)
        clear_panel(state.outline_buf)
        return
    end

    local data = get_data(state.root)
    local names = highlight.names_for_root(state.root)
    local width = vim.api.nvim_win_get_width(state.character_win)

    set_panel_content(
        state.character_buf,
        render_character(state.active_character, state.active_tab, width),
        names
    )

    if state.mode == "ys" then
        set_panel_content(
            state.outline_buf,
            render_chapter(state.active_chapter, data),
            names
        )
    else
        clear_panel(state.outline_buf)
    end
end

function M.resize()
    if not M.is_open() then
        return
    end

    local config = require("yummy").config
    local ratio = math.max(0.30, math.min(config.center_width or 0.60, 0.80))

    -- Two separators between three windows.
    local available = vim.o.columns - 2
    local side_width = math.max(12, math.floor(available * (1 - ratio) / 2))
    local main_width = available - side_width * 2

    applying = true
    pcall(vim.api.nvim_win_set_width, state.character_win, side_width)
    pcall(vim.api.nvim_win_set_width, state.outline_win, side_width)
    pcall(vim.api.nvim_win_set_width, state.main_win, main_width)

    M.render()

    -- WinResized fires on the next loop tick; clear the flag after it.
    vim.schedule(function()
        applying = false
    end)
end

-- Set the center ratio (0.30 - 0.80) and re-apply the layout.
function M.set_ratio(ratio)
    local config = require("yummy").config
    config.center_width = math.max(0.30, math.min(ratio, 0.80))
    M.resize()
end

-- After a manual drag, adopt the new center ratio and re-balance the sides.
function M.sync_ratio(changed_wins)
    if applying or not M.is_open() then
        return
    end

    local touched = false
    for _, w in ipairs(changed_wins or {}) do
        if w == state.character_win or w == state.outline_win or w == state.main_win then
            touched = true
        end
    end
    if not touched then
        return
    end

    local main = vim.api.nvim_win_get_width(state.main_win)
    local left = vim.api.nvim_win_get_width(state.character_win)
    local right = vim.api.nvim_win_get_width(state.outline_win)
    local ratio = main / (main + left + right)

    local config = require("yummy").config
    if math.abs(ratio - (config.center_width or 0.60)) < 0.02 then
        return
    end

    M.set_ratio(ratio)
end

function M.update_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not valid_win(state.main_win)
        or not valid_win(state.character_win)
        or not valid_win(state.outline_win)
    then
        return
    end

    local filetype = vim.bo[bufnr].filetype

    if filetype ~= "ys" and filetype ~= "yc" and filetype ~= "yo" then
        return
    end

    local path = vim.api.nvim_buf_get_name(bufnr)
    local root = require("yummy.project").find_root(path)

    if not root then
        clear_panel(state.character_buf)
        clear_panel(state.outline_buf)
        return
    end

    if vim.api.nvim_win_get_buf(state.main_win) ~= bufnr then
        vim.api.nvim_win_set_buf(state.main_win, bufnr)
    end

    state.root = root
    state.mode = filetype

    -- A character file leaves both contextual panels empty.
    if filetype == "yc" then
        state.active_character = nil
        state.active_tab = 1
        state.active_chapter = nil

        clear_panel(state.character_buf)
        clear_panel(state.outline_buf)
        return
    end

    local data = get_data(root)

    -- Select the character beneath the cursor for both .ys and .yo.
    local character = find_character_at_cursor(bufnr, data)

    if character ~= state.active_character then
        state.active_character = character
        state.active_tab = 1
    end

    -- Only manuscripts show the chapter notes panel.
    state.active_chapter = filetype == "ys" and find_current_chapter(bufnr) or nil

    state.words = nil
    if filetype == "ys" then
        local row = vim.api.nvim_win_get_cursor(state.main_win)[1]
        state.words = require("yummy.manuscript").words_at(bufnr, row)
    end

    M.render()
end

-- Move between the selected character's ## sections.
local function change_tab(direction)
    local character = state.active_character

    if not character or not character.tabs or #character.tabs == 0 then
        return
    end

    local count = #character.tabs

    state.active_tab = ((state.active_tab - 1 + direction) % count) + 1
    M.render()
end

function M.next_character_tab()
    change_tab(1)
end

function M.previous_character_tab()
    change_tab(-1)
end

function M.open(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local filetype = vim.bo[bufnr].filetype

    if filetype ~= "ys" and filetype ~= "yc" and filetype ~= "yo" then
        vim.notify(
            "Yummy: Open a .ys, .yc, or .yo file first",
            vim.log.levels.WARN
        )
        return false
    end

    if valid_win(state.main_win)
        and valid_win(state.character_win)
        and valid_win(state.outline_win)
    then
        M.update_context(bufnr)
        vim.api.nvim_set_current_win(state.main_win)
        return true
    end

    state.main_win = vim.api.nvim_get_current_win()
    state.character_buf = create_panel("characters", "yummy-characters")
    state.outline_buf = create_panel("outline", "yummy-outline")

    -- Right panel.
    vim.cmd("rightbelow vsplit")
    state.outline_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.outline_win, state.outline_buf)
    configure_panel(state.outline_win, "chapters ")

    -- Left panel.
    vim.api.nvim_set_current_win(state.main_win)
    vim.cmd("leftabove vsplit")
    state.character_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.character_win, state.character_buf)
    configure_panel(state.character_win, "characters ")

    M.resize()
    M.update_context(bufnr)

    vim.api.nvim_set_current_win(state.main_win)

    return true
end

function M.close()
    local main_win = state.main_win

    local quit_after = false

    for _, win in ipairs({
        state.character_win,
        state.outline_win,
    }) do
        if valid_win(win) then
            -- Neovim can't close the last window, so quit instead.
            if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
                quit_after = true
            else
                pcall(vim.api.nvim_win_close, win, true)
            end
        end
    end

    for _, buf in ipairs({ state.character_buf, state.outline_buf }) do
        if valid_buf(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end

    if valid_win(main_win) then
        vim.api.nvim_set_current_win(main_win)
    end

    state.main_win = nil
    state.character_win = nil
    state.outline_win = nil
    state.character_buf = nil
    state.outline_buf = nil
    state.root = nil
    state.active_character = nil
    state.active_tab = 1
    state.active_chapter = nil
    state.mode = nil

    if quit_after then
        -- Quitting is fine only if nothing is unsaved.
        local modified = vim.tbl_filter(function(b)
            return vim.bo[b].modified
        end, vim.api.nvim_list_bufs())

        if #modified == 0 then
            vim.cmd("quit")
        else
            vim.notify(
                "Yummy: unsaved changes, use :q! or :wq",
                vim.log.levels.WARN
            )
        end
    end

    return true
end

function M.is_open()
    return valid_win(state.main_win)
        and valid_win(state.character_win)
        and valid_win(state.outline_win)
end

function M.get_state()
    return state
end

return M