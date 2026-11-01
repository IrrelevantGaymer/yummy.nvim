local M = {}

local project = require("yummy.project")
local data = require("yummy.data")
local highlight = require("yummy.highlight")
local ui = require("yummy.ui")

M.config = {
    center_width = 0.60
}

local function is_yummy_ft(ft)
    return ft == "ys" or ft == "yc" or ft == "yo"
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    require("yummy.commands").setup()

    local group = vim.api.nvim_create_augroup("Yummy", { clear = true })

    -- Initialize project data when a Yummy file is opened.
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "ys", "yc", "yo" },
        callback = function(args)
            local current_project = project.get(args.buf)

            if not current_project then
                vim.notify(
                    "Yummy: No project found (.yummy marker missing)",
                    vim.log.levels.WARN
                )
                return
            end

            vim.b[args.buf].yummy_root = current_project.root
            vim.wo.statusline = "%f %m%= %{v:lua.require'yummy'.statusline()}"
            data.refresh(current_project.root)
        end,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "ys", "yc", "yo" },
        callback = function(args)
            vim.wo.wrap = true
            vim.wo.linebreak = true
            vim.wo.breakindent = false

            vim.api.nvim_create_autocmd("TextChangedI", {
                group = group,
                buffer = args.buf,
                callback = function()
                    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
                    local before = vim.api.nvim_get_current_line():sub(1, col)

                    local triggers = {
                        { "\\--- ", "—" },
                        { "\\-- ", "–" },
                    }

                    for _, t in ipairs(triggers) do
                        local trigger, dash = t[1], t[2]

                        if before:sub(-#trigger) == trigger then
                            vim.api.nvim_buf_set_text(
                                0, row - 1, col - #trigger, row - 1, col, { dash }
                            )
                            vim.api.nvim_win_set_cursor(
                                0, { row, col - #trigger + #dash }
                            )
                            return
                        end
                    end
                end,
            })
        end,
    })

    -- Refresh indexes when a character or outline file is saved.
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = { "*.yc", "*.yo" },
        callback = function(args)
            data.refresh_for_buffer(args.buf)
            require("yummy.highlight").refresh_all()

            local st = ui.get_state()
            if ui.is_open() then
                -- Re-resolve the character and chapter from the fresh data.
                ui.update_context(vim.api.nvim_win_get_buf(st.main_win))
            end
        end,
    })

    -- Auto open / close the side panels.
    vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
        group = group,
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then
                    return
                end

                local win = vim.api.nvim_get_current_win()

                -- Ignore floating windows and the panels themselves.
                if vim.api.nvim_win_get_config(win).relative ~= "" then
                    return
                end

                local ft = vim.bo[args.buf].filetype
                if ft:match("^yummy%-") then
                    return
                end

                local st = ui.get_state()

                if is_yummy_ft(ft) then
                    if ui.is_open() then
                        return
                    end

                    ui.open(args.buf)
                elseif ui.is_open() and win == st.main_win then
                    -- Main window moved to a non-Yummy buffer.
                    ui.close()
                end
            end)
        end,
    })

    -- Close the panels if the main window is closed.
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            local st = ui.get_state()

            if st.main_win and tostring(st.main_win) == args.match then
                vim.schedule(function()
                    pcall(ui.close)
                end)
            end
        end,
    })

    -- Keep the panels in sync with the cursor.
    vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved" }, {
        group = group,
        callback = function(args)
            if ui.is_open()
                and vim.api.nvim_get_current_win() == ui.get_state().main_win
            then
                ui.update_context(args.buf)
            end
        end,
    })

    -- Re-balance panel widths on terminal resize.
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            ui.resize()
        end,
    })

    -- Manual drags / :vertical resize on any of the three windows.
    vim.api.nvim_create_autocmd("WinResized", {
        group = group,
        callback = function()
            ui.sync_ratio(vim.v.event.windows)
            ui.render()
        end,
    })

    vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
        group = group,
        callback = function()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                local ft = vim.bo[buf].filetype
                if ft == "ys" or ft == "yc" or ft == "yo" then
                    require("yummy.highlight").center(buf)
                end
            end
        end,
    })

    highlight.define()

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            highlight.define()
            highlight.refresh_all()
        end,
    })

    vim.api.nvim_create_autocmd(
        { "FileType", "BufEnter", "TextChanged", "TextChangedI" },
        {
            group = group,
            pattern = { "*.ys", "*.yc", "*.yo" },
            callback = function(args)
                highlight.apply(args.buf)
            end,
        }
    )
end

function M.get_project(bufnr)
    return project.get(bufnr)
end

function M.get_data(root)
    return data.get(root)
end

function M.statusline()
    return require("yummy.manuscript").statusline()
end

return M