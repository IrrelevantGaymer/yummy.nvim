local M = {}

local extensions = {
    ys = "manuscripts",
    yc = "characters",
    yo = "outlines",
}

-- Find the nearest ancestor directory containing a .yummy marker.
function M.find_root(path)
    path = path or vim.api.nvim_buf_get_name(0)

    if path == "" then
        path = vim.fn.getcwd()
    end

    path = vim.fn.fnamemodify(path, ":p")

    -- If path is a file, start from its containing directory.
    if vim.fn.isdirectory(path) == 0 then
        path = vim.fn.fnamemodify(path, ":h")
    end

    local marker = vim.fs.find(".yummy", {
        path = path,
        upward = true,
        type = "file",
    })[1]

    if not marker then
        return nil
    end

    return vim.fs.dirname(marker)
end

-- Discover all Yummy files inside a project.
function M.get_files(root)
    local files = {
        manuscripts = {},
        characters = {},
        outlines = {},
    }

    for extension, category in pairs(extensions) do
        local matches = vim.fs.find(function(name)
            return name:match("%." .. extension .. "$") ~= nil
        end, {
            path = root,
            type = "file",
            limit = math.huge,
        })

        files[category] = matches
    end

    -- Keep file lists deterministic.
    for _, category in pairs(files) do
        table.sort(category)
    end

    return files
end

-- Build a project object from a root directory.
function M.load(root)
    root = root or M.find_root()

    if not root then
        return nil
    end

    return {
        root = root,
        files = M.get_files(root),
    }
end

-- Find and load the project containing a buffer.
function M.get(bufnr)
    bufnr = bufnr or 0

    local path = vim.api.nvim_buf_get_name(bufnr)

    if path == "" then
        return nil
    end

    local root = M.find_root(path)

    if not root then
        return nil
    end

    return M.load(root)
end

return M