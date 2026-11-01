local M = {}

local ms = require("yummy.manuscript")
local ui = require("yummy.ui")

function M.setup()
    vim.api.nvim_create_user_command("YummyNextTab", function()
        ui.next_character_tab()
    end, {})

    vim.api.nvim_create_user_command("YummyPrevTab", function()
        ui.previous_character_tab()
    end, {})

    vim.api.nvim_create_user_command("YummyGotoChapter", function(opts)
        ms.goto_chapter(opts.args)
    end, {
        nargs = "*",
        complete = function(lead, cmdline)
            return ms.complete_chapter(lead, cmdline)
        end,
    })

    vim.api.nvim_create_user_command("YummyGotoTodo", function(opts)
        ms.goto_todo(opts.args)
    end, {
        nargs = "*",
        complete = function(lead, cmdline)
            return ms.complete_todo(lead, cmdline)
        end,
    })

    local relative = {
        YummyGotoPrevChapterStart = { "start", -1 },
        YummyGotoNextChapterStart = { "start", 1 },
        YummyGotoPrevChapterEnd   = { "end", -1 },
        YummyGotoNextChapterEnd   = { "end", 1 },
        YummyGotoPrevTodo         = { "todo", -1 },
        YummyGotoNextTodo         = { "todo", 1 },
    }

    for name, args in pairs(relative) do
        vim.api.nvim_create_user_command(name, function()
            ms.goto_relative(args[1], args[2])
        end, {})
    end
end

return M