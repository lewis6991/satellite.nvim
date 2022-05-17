local highlight = 'Normal'

---@type Handler
local handler = {
	name = 'marks',
}

function handler.init() end

function handler.update(bufnr)
	local marks = {}
	local buffer_marks = vim.fn.getmarklist(bufnr)
	for _, mark in ipairs(buffer_marks) do
		marks[#marks + 1] = {
			-- [bufnum, lnum, col, off]
			lnum = mark.pos[2] + 1,
			-- first char of mark name is a single quote
			symbol = string.sub(mark.mark, 2, 3),
			highlight = highlight,
		}
	end
	return marks
end

require('satellite.handlers').register(handler)
