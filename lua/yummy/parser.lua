local M = {}

-- Split text into lines, preserving the contents of each line.
local function get_lines(text)
    local lines = {}

    for line in (text .. "\n"):gmatch("(.-)\n") do
        -- Remove a trailing carriage return for Windows files.
        line = line:gsub("\r$", "")
        table.insert(lines, line)
    end

    return lines
end

-- Parse a .yc character file.
function M.parse_characters(text)
    local characters = {}
    local character
    local tab

    local function finish_tab()
        if not tab then
            return
        end

        tab.content = table.concat(tab._lines, "\n")
            :gsub("^%s+", "")
            :gsub("%s+$", "")

        tab._lines = nil
        tab = nil
    end

    for _, line in ipairs(get_lines(text)) do
        -- A single # declares a character.
        local name = line:match("^#%s+(.+)%s*$")

        -- Two or more # characters are not character declarations.
        if line:match("^##") then
            name = nil
        end

        if name then
            finish_tab()

            character = {
                name = name,
                aliases = {},
                tabs = {},
            }

            table.insert(characters, character)
        else
            -- A ## heading starts a new character tab.
            local tab_name = line:match("^##%s+(.+)%s*$")

            if tab_name and character then
                finish_tab()

                tab = {
                    name = tab_name,
                    _lines = {},
                }

                table.insert(character.tabs, tab)
            elseif character and tab then
                table.insert(tab._lines, line)
            elseif character then
                -- Before the first ## heading, collect aliases.
                local alias = line:match("^%s*%-%s+(.+)%s*$")

                if alias then
                    table.insert(character.aliases, alias)
                end
            end
        end
    end

    finish_tab()

    return characters
end

-- Parse a .yo outline file.
function M.parse_outline(text)
    local chapters = {}
    local chapter

    local function finish_chapter()
        if not chapter then
            return
        end

        chapter.content = table.concat(chapter._lines, "\n")
            :gsub("^%s+", "")
            :gsub("%s+$", "")

        chapter._lines = nil
        chapter = nil
    end

    for _, line in ipairs(get_lines(text)) do
        -- Only a single # starts a chapter.
        local name = line:match("^#%s+(.+)%s*$")

        if line:match("^##") then
            name = nil
        end

        if name then
            finish_chapter()

            chapter = {
                name = name,
                content = "",
                _lines = {},
            }

            table.insert(chapters, chapter)
        elseif chapter then
            table.insert(chapter._lines, line)
        end
    end

    finish_chapter()

    return chapters
end

-- Parse a .ys manuscript into sections.
-- This preserves the heading hierarchy without interpreting prose.
function M.parse_manuscript(text)
    local sections = {}
    local section

    for _, line in ipairs(get_lines(text)) do
        local hashes, name = line:match("^(#+)%s+(.+)%s*$")

        if hashes then
            section = {
                level = #hashes,
                name = name,
                content = "",
                _lines = {},
            }

            table.insert(sections, section)
        elseif section then
            table.insert(section._lines, line)
        end
    end

    for _, item in ipairs(sections) do
        item.content = table.concat(item._lines, "\n")
            :gsub("^%s+", "")
            :gsub("%s+$", "")

        item._lines = nil
    end

    return sections
end

return M