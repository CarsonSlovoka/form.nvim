vim.api.nvim_create_user_command('LocationForm', function()
  require('form').open({
    title = 'location',
    fields = {
      { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
      { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
      { name = 'description', label = '描述', multiline = true, required = true },
    },
    on_submit = function(data, ctx)
      -- vim.print(data)
      -- Or persist with a synchronous function that raises/returns false on failure.

      if ctx.path == nil then
        vim.notify("缺少保存的檔案名稱", vim.log.levels.ERROR)
        return false
      end

      local result = vim.fn.writefile({
        vim.json.encode(data),
      }, ctx.path)

      if result ~= 0 then
        return false, 'Failed to write file'
      else
        print("✅ save to: " .. ctx.path)
      end
    end,
  })
end, {})

vim.api.nvim_create_user_command('LocationForm2', function()
  require('form').open({
    title = 'location',
    fields = {
      { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
      { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
      { name = 'description', label = '描述', multiline = true, required = true },
      { name = 'price', label = '$', type = 'number', required = false },
      { name = 'note', label = '備註', multiline = true, required = false },
    },

    -- ❗ 使用format就不需要在定義on_submit, 可以直接用 `:w myfile` 就可以保存結果
    format = function(data, ctx)
      return string.format([[
經度: %s
緯度: %s
描述: %s

📝: %s
]], data.longitude, data.latitude, data.description, data.note or "")
    end,
  })
end, {})
