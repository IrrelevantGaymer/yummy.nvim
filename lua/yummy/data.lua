local M = {}

local project_module = require("yummy.project")
local characters = require("yummy.characters")
local outlines = require("yummy.outlines")

local cache = {}

local function key(root)
    return (vim.fn.fnamemodify(root, ":p"):gsub("[/\\]$", ""))
end

-- Load or reload all indexed data for a project.
function M.refresh(root)
    local project = project_module.load(root)

    if not project then
        return nil
    end

    local data = {
        root = project.root,
        project = project,
        characters = characters.load(project),
        outlines = outlines.load(project),
    }

    cache[key(project.root)] = data

    return data
end

-- Get cached data, loading it if necessary.
function M.get(root)
    root = root or project_module.find_root()

    if not root then
        return nil
    end

    root = key(root)

    if not cache[root] then
        return M.refresh(root)
    end

    return cache[root]
end

-- Refresh the project associated with a buffer.
function M.refresh_for_buffer(bufnr)
    local project = project_module.get(bufnr)

    if not project then
        return nil
    end

    return M.refresh(project.root)
end

-- Clear cached data for a project.
function M.clear(root)
    if root then
        cache[key(root)] = nil
    else
        cache = {}
    end
end

return M