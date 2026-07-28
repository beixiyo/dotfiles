# Telescope spec 维护说明

本文记录本目录自定义 picker 的共同边界，尤其是 ANSI 输出通过 terminal buffer 渲染时的 buffer 生命周期

## ANSI terminal preview

使用 `previewers.new_buffer_previewer()` 时，Telescope 会为每次 preview 创建 buffer，写入 `self.state.bufnr`，并通过 scheduled 回调把同一个局部 `bufnr` 设置到 preview window

因此 `define_preview` 必须直接使用 Telescope 创建的 `self.state.bufnr`：

```lua
opts.previewer = previewers.new_buffer_previewer({
  define_preview = function(self, entry)
    local bufnr = self.state.bufnr
    local chan = vim.api.nvim_open_term(bufnr, {})

    vim.system(command(entry), { text = true }, function(result)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        vim.api.nvim_chan_send(chan, result.stdout or '')
      end)
    end)
  end,
})
```

不要在 `define_preview` 中另建 buffer，也不要改写 `self.state.bufnr`：

- Telescope scheduled 回调捕获的是它创建的局部 `bufnr`
- 自己设置 preview window 会随后被 Telescope 覆盖
- 删除 Telescope 的 buffer 会让它的有效性检查失败，并可能保留旧 preview

## 异步边界

- 回调写入前检查 `nvim_buf_is_valid(bufnr)`
- 新请求开始时终止或忽略旧任务，避免过期输出覆盖当前 entry
- terminal channel 只对应创建它的 buffer
- stdout/stderr 和退出码策略由具体 picker 决定
- window、滚动和焦点行为必须在完整 Telescope UI 中手动验证，headless 只能验证 Lua/API 错误
