local M = {}

local parser = require("yummy.parser")
local project_module = require("yummy.project")

local function read_file(path)
    local lines = vim.fn.readfile(path)

    if vim.v.shell_error ~= 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

local function normalize_name(name)
    return vim.trim(name)
end

local function add_lookup(index, name, item)
    local key = normalize_name(name)

    if key == "" then
        return
    end

    index[key] = index[key] or {}
    table.insert(index[key], item)
end

-- Load and index every character from every .yc file in a project.
function M.load(project)
    if type(project) == "string" then
        project = project_module.load(project)
    elseif not project then
        project = project_module.get()
    end

    if not project then
        return nil
    end

    local result = {
        root = project.root,
        characters = {},
        by_name = {},
    }

    for _, path in ipairs(project.files.characters) do
        local text = read_file(path)

        if text then
            local characters = parser.parse_characters(text)

            for _, character in ipairs(characters) do
                character.source = path
                table.insert(result.characters, character)

                -- Index the character's canonical name.
                add_lookup(result.by_name, character.name, character)

                -- Index each alias to the same character object.
                for _, alias in ipairs(character.aliases) do
                    add_lookup(result.by_name, alias, character)
                end
            end
        else
            vim.notify(
                "Yummy: Could not read character file: " .. path,
                vim.log.levels.WARN
            )
        end
    end

    return result
end

-- Return every character matching a name or alias, case-insensitively.
function M.find(data, name)
    if not data or not name then
        return {}
    end

    return data.by_name[normalize_name(name)] or {}
end

-- Return the first match, or nil if there isn't one.
function M.get(data, name)
    return M.find(data, name)[1]
end

return M