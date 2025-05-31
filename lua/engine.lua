-- This code is from https://nachtimwald.com/2014/08/06/using-lua-as-a-templating-engine/
-- Code from John Schember's blog is licensed under MIT: https://nachtimwald.com/legal/
local M = {}

-- Append text or code to the builder.
local function appender(builder, text, code)
    if code then
        builder[#builder + 1] = code
    else
        -- [[ has a \n immediately after it. Lua will strip
        -- the first \n so we add one knowing it will be
        -- removed to ensure that if text starts with a \n
        -- it won't be lost.
        builder[#builder + 1] = "_ret[#_ret+1] = [[\n" .. text .. "]]"
    end
end

--- Takes a string and determines what kind of block it
-- is and takes the appropriate action.
--
-- The text should be something like:
-- "{{ ... }}"
--
-- If the block is supported the begin and end tags will
-- be stripped and the associated action will be taken.
-- If the tag isn't supported the block will be output
-- as is.
local function run_block(builder, text)
    local func
    local tag

    tag = text:sub(1, 2)

    if tag == "{{" then
        func = function(code)
            return ('_ret[#_ret+1] = %s'):format(code)
        end
    elseif tag == "{%" then
        func = function(code)
            return code
        end
    end
    if func then
        appender(builder, nil, func(text:sub(3, #text - 3)))
    else
        appender(builder, text)
    end
end

--- Compile a Lua template into a string.
--
-- @param      tmpl The template.
-- @param[opt] env  Environment table to use for sandboxing.
--
-- return Compiled template.
function M.compile(tmpl, env)
    -- Turn the template into a string that can be run though
    -- Lua. Builder will be used to efficiently build the string
    -- we'll run. The string will use it's own builder (_ret). Each
    -- part that comprises _ret will be the various pieces of the
    -- template. Strings, variables that should be printed and
    -- functions that should be run.
    local builder = { "_ret = {}\n" }
    local pos     = 1
    local b
    local func
    local err

    if type(env) ~= "table" then
        env = {}
    end

    env["include"] = function (tmpl_path, data)
        -- read_template is provided by Odin as a C function
        local content = M.read_template(tmpl_path)
        local new_data = {}

        for k, v in pairs(env) do
            new_data[k] = v
        end

        if type(data) == "table" then
            for k, v in pairs(data) do
                new_data[k] = v
            end
        end

        return M.compile(content, new_data)
    end

    if #tmpl == 0 then
        return ""
    end

    while pos < #tmpl do
        -- Look for start of a Lua block.
        b = tmpl:find("{", pos)
        if not b then
            break
        end

        -- Check if this is a block or escaped {.
        if tmpl:sub(b - 1, b - 1) == "\\" then
            appender(builder, tmpl:sub(pos, b - 2))
            appender(builder, "{")
            pos = b + 1
        else
            -- Add all text up until this block.
            appender(builder, tmpl:sub(pos, b - 1))
            -- Find the end of the block.
            pos = tmpl:find("}}", b)
            if not pos then
                error("End tag ('}}') missing")
                break
            end
            run_block(builder, tmpl:sub(b, pos + 2))
            -- Skip back the }} (pos points to the start of }}).
            pos = pos + 2
        end
    end
    -- Add any text after the last block. Or all of it if there
    -- are no blocks.
    if pos then
        appender(builder, tmpl:sub(pos, #tmpl))
    end

    builder[#builder + 1] = "return table.concat(_ret)"
    -- Run the Lua code we built though Lua and get the result.
    func, err = load(table.concat(builder, "\n"), "template", "t", env)
    if not func then
        return err
    end
    return func()
end

return M
