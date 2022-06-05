local M = {}

M.default_config = {
  cmd_name = "IncRename",
  hl_group = "Substitute",
}

local state = {
  should_fetch_references = true,
  orig_lines = nil,
  lsp_positions = nil,
}

-- Called when the user is still typing the command or the command arguments
local function incremental_rename_preview(opts, preview_ns, preview_buf)
  -- Store the lines of the buffer at the first invocation
  if state.should_fetch_references then
    -- Get positions of LSP reference symbols
    local params = vim.lsp.util.make_position_params()
    params.context = { includeDeclaration = vim.F.if_nil(opts.include_declaration, true) }

    vim.lsp.buf_request(0, "textDocument/references", params, function(err, result, _, _)
      if err then
        vim.notify("Error while finding references: " .. err.message, vim.lsp.log_levels.ERROR)
        return
      end
      if not result or vim.tbl_isempty(result) then
        vim.notify("No results from textDocument/references", vim.lsp.log_levels.WARN)
        return
      end
      state.lsp_positions = vim.tbl_map(function(x)
        return x.range
      end, result)

      local buf = vim.api.nvim_get_current_buf()
      state.orig_lines = {}
      for _, position in ipairs(state.lsp_positions) do
        local line_nr = position.start.line
        local line = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
        local start_col, end_col = position.start.character, position["end"].character
        local line_item = { text = line, start_col = start_col, end_col = end_col }
        -- Same line was already seen, this case needs to be handled separately
        if state.orig_lines[line_nr] then
          table.insert(state.orig_lines[line_nr], line_item)
        else
          state.orig_lines[line_nr] = { line_item }
        end
      end
      state.should_fetch_references = false
    end)
    return
  end

  local new_name = opts.args
  -- Ignore whitespace-only name (abort highlighting)
  if new_name:match("^%s*$") then
    return
  end

  for line_nr, line_items in pairs(state.orig_lines) do
    local offset = 0
    local updated_line = line_items[1].text
    local highlight_positions = {}
    for _, item in ipairs(line_items) do
      updated_line = updated_line:sub(1, item.start_col + offset)
          .. new_name
          .. updated_line:sub(item.end_col + 1 + offset)
      table.insert(highlight_positions, {
        start_col = item.start_col + offset,
        end_col = item.start_col + #new_name + offset,
      })
      -- Offset by the length difference between the new and old names
      offset = offset + #new_name - (item.end_col - item.start_col)
    end
    vim.api.nvim_buf_set_lines(0, line_nr, line_nr + 1, false, { updated_line })
    if preview_buf then
      vim.api.nvim_buf_set_lines(preview_buf, line_nr, line_nr + 1, false, { updated_line })
    end
    for _, hl_pos in ipairs(highlight_positions) do
      vim.api.nvim_buf_add_highlight(0, preview_ns, M.config.hl_group, line_nr, hl_pos.start_col, hl_pos.end_col)
      if preview_buf then
        vim.api.nvim_buf_add_highlight(
          preview_buf,
          preview_ns,
          M.config.hl_group,
          line_nr,
          hl_pos.start_col,
          hl_pos.end_col
        )
      end
    end
  end
  return 2
end

-- Runs when the command is executed (user pressed enter)
local function incremental_rename_execute(opts)
  vim.lsp.buf.rename(opts.args)
  state.should_fetch_references = true
end

local create_user_command = function(cmd_name)
  -- Create the user command
  vim.api.nvim_create_user_command(
    cmd_name,
    incremental_rename_execute,
    { nargs = 1, addr = "lines", preview = incremental_rename_preview }
  )
end

M.setup = function(user_config)
  M.config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  create_user_command(M.config.cmd_name)
end

return M
