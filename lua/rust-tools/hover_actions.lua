-- ?? helps with all the warnings spam
local vim = vim
local util = vim.lsp.util
local config = require('rust-tools.config')

local M = {}

local function get_params() return vim.lsp.util.make_position_params() end

M._state = {winnr = nil, commands = nil, ttype = nil}

-- run the command under the cursor, if the thing under the cursor is not the
-- command then do nothing
function M._run_command()
    local line = vim.api.nvim_win_get_cursor(M._state.winnr)[1]

    if line > #M._state.commands then return end

    M._close_hover()
    if M._state.ttype == "rust-analyzer.gotoLocation" then
        vim.lsp.util.jump_to_location(M._state.commands[line].arguments[1])
    else
        if M._state.ttype == "rust-analyzer.showReferences" then
            vim.lsp.buf.implementation()
        end
    end
end

function M._close_hover()
    if M._state.winnr ~= nil then
        vim.api.nvim_win_close(M._state.winnr, true)
    end
end

local function parse_commands()
    local prompt = {}

    for i, value in ipairs(M._state.commands) do
        if value.command == "rust-analyzer.gotoLocation" then
            table.insert(prompt, string.format("%d. Go to %s (%s)", i,
                                               value.title, value.tooltip))
        else
            table.insert(prompt,
                         string.format("%d. %s", i, "Go to " .. value.title))
        end
    end
    table.insert(prompt, "")

    return prompt
end

function M.handler(_, _, result, _, _, _)
    if not (result and result.contents) then
        -- return { 'No information available' }
        return
    end

    local markdown_lines = util.convert_input_to_markdown_lines(result.contents)
    markdown_lines = util.trim_empty_lines(markdown_lines)

    if vim.tbl_isempty(markdown_lines) then
        -- return { 'No information available' }
        return
    end

    local bufnr, winnr = util.open_floating_preview(markdown_lines, "markdown",
                                                    {
        border = config.options.tools.hover_actions.border,
        focusable = true,
        focus_id = "rust-tools-hover-actions",
        close_events = {"CursorMoved", "BufHidden", "InsertCharPre"}
    })

    if config.options.tools.hover_actions.auto_focus then
        vim.api.nvim_set_current_win(winnr)
    end

    if M._state.winnr ~= nil then return end

    -- update the window number here so that we can map escape to close even
    -- when there are no actions, update the rest of the state later
    M._state.winnr = winnr
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<Esc>",
                                ":lua require'rust-tools.hover_actions'._close_hover()<CR>",
                                {})

    vim.api.nvim_buf_attach(bufnr, false,
                            {on_detach = function() M._state.winnr = nil end})

    --- stop here if there are no possible actions
    if result.actions == nil then return end

    -- syntax highlighting
    vim.api.nvim_buf_set_option(bufnr, "filetype", "rust")

    -- update the state
    M._state.commands = result.actions[1].commands
    M._state.ttype = M._state.commands[1].command

    local prompt = parse_commands()

    -- get the maximum length of all the possible commands
    local max_len = 0
    for _, line in ipairs(prompt) do
        if #line > max_len then max_len = #line end
    end

    --- update the height to compensate for the commands being added
    local old_height = vim.api.nvim_win_get_height(winnr)
    vim.api.nvim_win_set_height(winnr, old_height + #prompt)

    --- update the width to compensate for the commands being added
    local old_width = vim.api.nvim_win_get_width(winnr)
    if max_len > old_width then vim.api.nvim_win_set_width(winnr, max_len) end

    -- make it modifiable so that the commands text can be added
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    -- makes more sense in a dropdown-ish ui
    vim.api.nvim_win_set_option(winnr, 'cursorline', true)
    -- write to the buffer containing the hover text
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, prompt)
    -- no need now since we have written all we want
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    -- move cursor to the start since its at the place before we added the
    -- commands text
    vim.api.nvim_win_set_cursor(winnr, {1, 0})
    -- run the command under the cursor
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>",
                                ":lua require'rust-tools.hover_actions'._run_command()<CR>",
                                {})
    -- muscle memory
    vim.api.nvim_buf_set_keymap(bufnr, "n", "gd",
                                ":lua require'rust-tools.hover_actions'._run_command()<CR>",
                                {})
    -- close on escape
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<Esc>",
                                ":lua require'rust-tools.hover_actions'._close_hover()<CR>",
                                {})
end

-- Sends the request to rust-analyzer to get hover actions and handle it
function M.hover_actions()
    vim.lsp.buf_request(0, "textDocument/hover", get_params(), M.handler)
end

return M
