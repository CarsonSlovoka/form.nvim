vim.api.nvim_create_user_command('LocationForm', function()
  require('form').open({
    title = 'location',
    fields = {
      { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
      { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
      { name = 'description', label = '描述', required = true },
    },
    on_submit = function(data)
      -- vim.print(data)
      -- Or persist with a synchronous function that raises/returns false on failure.

      local path = vim.fn.stdpath('data') .. '/location.json'

      local result = vim.fn.writefile({
        vim.json.encode(data),
      }, path)

      if result ~= 0 then
        return false, 'Failed to write file'
      else
        print("✅ save to :" .. path)
      end
    end,
  })
end, {})
