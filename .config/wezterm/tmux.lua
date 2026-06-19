local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- Shared helper: within each band of panes that share `group_key` (e.g.
-- every pane in the same row shares "top"), walk the boundaries between
-- members (ordered by `sort_key`) and nudge each one via AdjustPaneSize
-- along `size_key`/`grow_dir`/`shrink_dir` toward whatever
-- `compute_target(members, i)` returns for members[i]. Geometry is
-- re-read before every single boundary move so earlier moves don't throw
-- off later ones. Works well for simple row/column splits; deeply nested
-- or irregular layouts may not end up exactly as requested.
local function adjust_pane_boundaries(window, tab, group_key, size_key, grow_dir, shrink_dir, sort_key, compute_target)
	local groups = {}
	for _, info in ipairs(tab:panes_with_info()) do
		local k = info[group_key]
		groups[k] = groups[k] or {}
		table.insert(groups[k], info.pane:pane_id())
	end
	for _, ids in pairs(groups) do
		for i = 1, #ids - 1 do
			local current = {}
			for _, info in ipairs(tab:panes_with_info()) do
				current[info.pane:pane_id()] = info
			end
			local members = {}
			for _, id in ipairs(ids) do
				table.insert(members, current[id])
			end
			table.sort(members, function(a, b)
				return a[sort_key] < b[sort_key]
			end)
			local target = compute_target(members, i)
			local m = members[i]
			local diff = target - m[size_key]
			if diff > 0 then
				window:perform_action(act.AdjustPaneSize({ grow_dir, diff }), m.pane)
			elseif diff < 0 then
				window:perform_action(act.AdjustPaneSize({ shrink_dir, -diff }), m.pane)
			end
		end
	end
end

-- Per-tab toggle state for expand_column/expand_row, keyed by tab id:
-- { axis = "column"|"row", pane_id = <id of the pane that was expanded> }
local expand_state = {}

local function unzoom_all(window, tab)
	for _, info in ipairs(tab:panes_with_info()) do
		if info.is_zoomed then
			window:perform_action(act.TogglePaneZoomState, info.pane)
		end
	end
end

local function equal_target(members, size_key)
	local total = 0
	for _, m in ipairs(members) do
		total = total + m[size_key]
	end
	return math.floor(total / #members)
end

local function restore_balance(window, tab)
	adjust_pane_boundaries(window, tab, "top", "width", "Right", "Left", "left", function(members)
		return equal_target(members, "width")
	end)
	adjust_pane_boundaries(window, tab, "left", "height", "Down", "Up", "top", function(members)
		return equal_target(members, "height")
	end)
end

-- Balance all panes in the current tab to roughly equal sizes.
-- WezTerm has no built-in equivalent of tmux's "select-layout tiled".
local function balance_panes(window, pane)
	local tab = window:active_tab()
	if not tab then
		return
	end
	unzoom_all(window, tab)
	restore_balance(window, tab)
	expand_state[tab:tab_id()] = nil
end

-- Toggle: expand every pane sharing the active pane's `match_key` (e.g.
-- "left" for a column) to fill the tab, shrinking the other column(s)/
-- row(s) to a minimum. Pressing the same expand key again on the same
-- pane restores the balanced layout instead of expanding further; state
-- is tracked per tab so switching tabs doesn't confuse the toggle.
local function toggle_expand(window, pane, axis, group_key, size_key, grow_dir, shrink_dir, sort_key, match_key)
	local tab = window:active_tab()
	if not tab then
		return
	end
	local tab_id = tab:tab_id()
	local active_id = pane:pane_id()

	local state = expand_state[tab_id]
	if state and state.axis == axis and state.pane_id == active_id then
		unzoom_all(window, tab)
		restore_balance(window, tab)
		expand_state[tab_id] = nil
		return
	end

	unzoom_all(window, tab)

	local active_match
	for _, info in ipairs(tab:panes_with_info()) do
		if info.pane:pane_id() == active_id then
			active_match = info[match_key]
		end
	end
	if active_match == nil then
		return
	end

	adjust_pane_boundaries(window, tab, group_key, size_key, grow_dir, shrink_dir, sort_key, function(members, i)
		local total = 0
		local other_count = 0
		for _, m in ipairs(members) do
			total = total + m[size_key]
			if m[match_key] ~= active_match then
				other_count = other_count + 1
			end
		end
		local min_other = 1
		local active_target = math.floor((total - other_count * min_other) / (#members - other_count))
		local m = members[i]
		return m[match_key] == active_match and active_target or min_other
	end)

	expand_state[tab_id] = { axis = axis, pane_id = active_id }
end

-- leader+| : expand/restore the active pane's column (same "left")
local function expand_column(window, pane)
	toggle_expand(window, pane, "column", "top", "width", "Right", "Left", "left", "left")
end

-- leader+- : expand/restore the active pane's row (same "top")
local function expand_row(window, pane)
	toggle_expand(window, pane, "row", "left", "height", "Down", "Up", "top", "top")
end

function M.apply_to_config(config)
	-- Leader key (Ctrl+a, like tmux default prefix but use 'a' instead of 'b')
	config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }

	config.keys = {
		-- Pane splitting
		-- leader + " = split top/bottom (horizontal divider)
		{ key = '"', mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
		-- leader + % = split left/right (vertical divider)
		{ key = "%", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

		-- Pane navigation (vim-style)
		{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
		{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
		{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
		{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

		-- Pane navigation (arrow keys)
		{ key = "LeftArrow", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
		{ key = "DownArrow", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
		{ key = "UpArrow", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
		{ key = "RightArrow", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

		-- Pane resizing (leader + Shift + vim keys)
		{ key = "H", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
		{ key = "J", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
		{ key = "K", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
		{ key = "L", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },

		-- Pane management
		{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
		{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
		-- Expand the active pane's column/row to fill the tab; siblings within
		-- that column/row keep their own split, other columns/rows shrink down
		{ key = "|", mods = "LEADER", action = wezterm.action_callback(expand_column) },
		{ key = "-", mods = "LEADER", action = wezterm.action_callback(expand_row) },
		-- Balance all panes back to roughly equal sizes
		{ key = "=", mods = "LEADER", action = wezterm.action_callback(balance_panes) },

		-- Scroll / copy mode (like tmux prefix + [)
		-- In copy mode: hjkl/arrows to move, v to select, y to copy, q to quit
		{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },

		-- Search (like tmux prefix + /)
		-- After opening: type to search, Enter/n to go to next, N for previous, Esc to close
		{ key = "/", mods = "LEADER", action = act.Search("CurrentSelectionOrEmptyString") },

		-- Quick scroll without entering copy mode
		{ key = "PageUp", mods = "SHIFT", action = act.ScrollByPage(-1) },
		{ key = "PageDown", mods = "SHIFT", action = act.ScrollByPage(1) },
		{ key = "UpArrow", mods = "SHIFT", action = act.ScrollByLine(-3) },
		{ key = "DownArrow", mods = "SHIFT", action = act.ScrollByLine(3) },
	}
end

return M
