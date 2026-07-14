local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

return {
	entry = function()
		local _cwd = get_cwd()
		local cmd = string.format(
			'source "$HOME/.zsh/env.zsh"; source "$HOME/.zsh/functions/utils/index.zsh"; source "$HOME/.zsh/functions/fzf.zsh"; ff "%s"',
			_cwd
		)

		local permit = ui.hide()
		local child = Command("zsh")
			:arg("-c")
			:arg(cmd)
			:stdin(Command.INHERIT)
			:stdout(Command.PIPED)
			:stderr(Command.INHERIT)
			:spawn()

		if not child then
			permit:drop()
			ya.notify { title = "Fzf", content = "Failed to start zsh/fzf", level = "error" }
			return ya.err("Failed to start fzf")
		end

		local output = child:wait_with_output()
		permit:drop()

		if output and output.status.success then
			local target = output.stdout:gsub("^%s*(.-)%s*$", "%1")
			if target ~= "" then
				ya.emit("reveal", { target })
			end
		end
	end,
}
