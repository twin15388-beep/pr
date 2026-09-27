--[[
	[nzl studio]

	This module was stripped from the public release.
	Upstream it was the visual timing-builder GUI used by the auto-parry
	("Timing Builder" section of the Combat tab).

	This is a community reimplementation with the same public interface:
	  * combat tab:  timing_builder:set_visible(v) / timing_builder.on_close = fn
	  * timing logger: getgenv().timing_builder:load_track(track, entity)

	How it works:
	  1. enable "Timing Logger" in the Combat tab and get an enemy to attack you
	  2. click the logged animation (or press its keybind slot) to load it here
	  3. click on the timeline / use the + buttons to place parry/dodge actions
	  4. press Save -> writes rw_timings/<name>.json and hot-reloads timings

	Saved timings use exactly the format the animator handler consumes:
	  { name, ids = {...}, action_type?, actions = { {type=..., when=...}, ... } }
]]

local Players = game:GetService("Players");
local MarketplaceService = game:GetService("MarketplaceService");
local HttpService = game:GetService("HttpService");
local UserInputService = game:GetService("UserInputService");

local ASSET_TYPES = { "M1", "Critical", "Spell", "Bell", "Untagged" };
local ACTION_TYPES = { "Parry", "Dodge", "Forced Full Dodge", "Start Block", "Crouch", "Jump" };
local ADD_BUTTONS = { "Parry", "Dodge", "Forced Full Dodge", "Start Block" };

local ACTION_COLORS = {
	Parry = Color3.fromRGB(102, 153, 204),
	Dodge = Color3.fromRGB(235, 185, 75),
	["Forced Full Dodge"] = Color3.fromRGB(222, 120, 60),
	["Start Block"] = Color3.fromRGB(120, 190, 120),
	Crouch = Color3.fromRGB(160, 120, 200),
	Jump = Color3.fromRGB(190, 190, 110),
};

local COLORS = {
	background = Color3.fromRGB(16, 16, 20),
	panel = Color3.fromRGB(24, 24, 30),
	panel_light = Color3.fromRGB(32, 32, 40),
	stroke = Color3.fromRGB(45, 45, 55),
	text = Color3.fromRGB(225, 225, 235),
	text_dim = Color3.fromRGB(140, 140, 155),
};

local builder = {
	visible = false,
	on_close = nil, -- set by the combat tab

	current = nil, -- { id = string, name = string, length = number, entity = string }
	ids = {},      -- string list of animation ids in this timing
	actions = {},  -- { {type=string, when=number}, ... }
	action_type_index = 0, -- 0 = none
	name = "",
};

getgenv().timing_builder = builder;

local info_name_cache = {};
local function anim_display_name(id)
	if info_name_cache[id] then
		return info_name_cache[id];
	end;

	local name = id;
	pcall(function()
		name = MarketplaceService:GetProductInfo(tonumber(id) or 0).Name or id;
	end);
	info_name_cache[id] = name;
	return name;
end;

local function round3(n)
	return math.floor(n * 1000 + 0.5) / 1000;
end

local function sanitize_file_name(name)
	name = tostring(name or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "");
	if #name == 0 then
		return nil;
	end;
	return name;
end

-- ============================================================================
-- gui
-- ============================================================================

local gui;
local widgets = {};

local function new(class_name, props, parent)
	local inst = Instance.new(class_name);
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value;
		end;
	end;
	inst.Parent = parent or props.Parent;
	return inst;
end

local function with_corner(inst, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 4) }, inst);
	return inst;
end

local function with_stroke(inst, color, thickness)
	new("UIStroke", { Color = color or COLORS.stroke, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inst);
	return inst;
end

local function make_label(props, parent)
	props.BackgroundTransparency = 1;
	props.TextColor3 = props.TextColor3 or COLORS.text;
	props.Font = props.Font or Enum.Font.Gotham;
	props.TextSize = props.TextSize or 12;
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left;
	return new("TextLabel", props, parent);
end

local function make_button(text, parent)
	local button = with_corner(with_stroke(new("TextButton", {
		BackgroundColor3 = COLORS.panel_light,
		TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		Text = text,
		AutoButtonColor = true,
	}, parent)));
	return button;
end

local function accent_color()
	local ok, result = pcall(function()
		return Library and Library.AccentColor;
	end);
	if ok and typeof(result) == "Color3" then
		return result;
	end;
	return Color3.fromRGB(102, 153, 204);
end

local function build_gui()
	if gui then
		return gui;
	end

	local parent;
	pcall(function()
		parent = (gethui and gethui()) or game:GetService("CoreGui");
	end);
	parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui");

	gui = new("ScreenGui", {
		Name = "PRTimingBuilder",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
		Enabled = false,
	}, parent);

	local main = with_corner(with_stroke(new("Frame", {
		Name = "Main",
		Size = UDim2.new(0, 500, 0, 380),
		Position = UDim2.new(0.5, -250, 0.5, -190),
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Active = true,
	}, gui)));
	widgets.main = main;

	-- title bar -------------------------------------------------------------
	local title_bar = with_corner(new("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
	}, main));
	widgets.title_bar = title_bar;

	make_label({
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		Font = Enum.Font.GothamBold,
		Text = "pr // timing builder [oss]",
	}, title_bar);

	local close_button = make_button("X", title_bar);
	close_button.Size = UDim2.new(0, 22, 0, 18);
	close_button.Position = UDim2.new(1, -26, 0.5, -9);
	close_button.TextColor3 = Color3.fromRGB(230, 110, 110);

	-- window dragging
	do
		local dragging = false;
		local drag_start;
		local frame_start;

		title_bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true;
				drag_start = input.Position;
				frame_start = main.Position;
			end;
		end);

		UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - drag_start;
				main.Position = UDim2.new(frame_start.X.Scale, frame_start.X.Offset + delta.X, frame_start.Y.Scale, frame_start.Y.Offset + delta.Y);
			end;
		end);

		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false;
			end;
		end);
	end

	-- track info ------------------------------------------------------------
	widgets.track_label = make_label({
		Position = UDim2.new(0, 8, 0, 32),
		Size = UDim2.new(1, -16, 0, 16),
		TextColor3 = COLORS.text_dim,
		Text = "no track loaded - click an animation in the Timing Logger",
	}, main);

	widgets.id_label = make_label({
		Position = UDim2.new(0, 8, 0, 48),
		Size = UDim2.new(1, -16, 0, 14),
		TextSize = 11,
		TextColor3 = COLORS.text_dim,
		Text = "",
	}, main);

	-- timeline --------------------------------------------------------------
	local timeline = with_corner(with_stroke(new("Frame", {
		Position = UDim2.new(0, 8, 0, 68),
		Size = UDim2.new(1, -16, 0, 54),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Active = true,
	}, main)));
	widgets.timeline = timeline;

	make_label({
		Size = UDim2.new(0, 60, 0, 12),
		Position = UDim2.new(0, 2, 0, 0),
		TextSize = 10,
		TextColor3 = COLORS.text_dim,
		Text = "0.00s",
	}, timeline);

	widgets.end_label = make_label({
		Size = UDim2.new(0, 60, 0, 12),
		Position = UDim2.new(1, -62, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 10,
		TextColor3 = COLORS.text_dim,
		Text = "",
	}, timeline);

	widgets.marker_holder = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -14),
		Position = UDim2.new(0, 0, 0, 14),
	}, timeline);

	timeline.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return;
		end;
		builder:add_action_at("Parry", builder:timeline_x_to_when(input.Position.X));
	end);

	-- add / type buttons ----------------------------------------------------
	local button_y = 128;
	for index, action_type in ipairs(ADD_BUTTONS) do
		local button = make_button("+ " .. action_type, main);
		button.Size = UDim2.new(0, 115, 0, 22);
		button.Position = UDim2.new(0, 8 + (index - 1) * 122, 0, button_y);
		button.TextColor3 = ACTION_COLORS[action_type] or COLORS.text;
		button.MouseButton1Click:Connect(function()
			builder:add_action(action_type);
		end);
	end

	button_y = button_y + 28;
	widgets.asset_button = make_button("action group: none", main);
	widgets.asset_button.Size = UDim2.new(0, 158, 0, 20);
	widgets.asset_button.Position = UDim2.new(0, 8, 0, button_y);
	widgets.asset_button.MouseButton1Click:Connect(function()
		builder:cycle_action_type();
	end);

	local add_id_button = make_button("add current id to ids", main);
	add_id_button.Size = UDim2.new(0, 158, 0, 20);
	add_id_button.Position = UDim2.new(0, 174, 0, button_y);
	add_id_button.MouseButton1Click:Connect(function()
		builder:add_current_id();
	end);

	local clear_button = make_button("clear actions", main);
	clear_button.Size = UDim2.new(0, 154, 0, 20);
	clear_button.Position = UDim2.new(0, 340, 0, button_y);
	clear_button.TextColor3 = Color3.fromRGB(230, 110, 110);
	clear_button.MouseButton1Click:Connect(function()
		builder:clear();
	end);

	-- action list -----------------------------------------------------------
	local list = with_corner(with_stroke(new("ScrollingFrame", {
		Position = UDim2.new(0, 8, 0, 188),
		Size = UDim2.new(1, -16, 0, 128),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, main)));
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, list);
	widgets.list = list;

	-- name + save row -------------------------------------------------------
	local name_box = with_corner(with_stroke(new("TextBox", {
		Position = UDim2.new(0, 8, 1, -30),
		Size = UDim2.new(0, 240, 0, 22),
		BackgroundColor3 = COLORS.panel_light,
		TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		PlaceholderText = "timing name...",
		Text = "",
	}, main)));
	new("UIPadding", { PaddingLeft = UDim.new(0, 6) }, name_box);
	name_box:GetPropertyChangedSignal("Text"):Connect(function()
		builder.name = name_box.Text;
	end);
	widgets.name_box = name_box;

	local save_button = make_button("save", main);
	save_button.Size = UDim2.new(0, 116, 0, 22);
	save_button.Position = UDim2.new(0, 256, 1, -30);
	save_button.TextColor3 = Color3.fromRGB(120, 190, 120);
	save_button.MouseButton1Click:Connect(function()
		builder:save();
	end);

	local delete_button = make_button("delete", main);
	delete_button.Size = UDim2.new(0, 116, 0, 22);
	delete_button.Position = UDim2.new(0, 378, 1, -30);
	delete_button.TextColor3 = Color3.fromRGB(230, 110, 110);
	delete_button.MouseButton1Click:Connect(function()
		builder:delete_file();
	end);

	-- status ----------------------------------------------------------------
	widgets.status = make_label({
		Position = UDim2.new(0, 8, 1, -52),
		Size = UDim2.new(1, -16, 0, 18),
		TextSize = 11,
		TextColor3 = COLORS.text_dim,
		Text = "",
	}, main);

	close_button.MouseButton1Click:Connect(function()
		builder:hide(true);
	end);

	builder:apply_accent();
	return gui;
end

function builder:apply_accent()
	if not widgets.track_label then
		return;
	end;
	local accent = accent_color();
	if widgets.main then
		local stroke = widgets.main:FindFirstChildOfClass("UIStroke");
		if stroke then
			stroke.Color = accent;
		end;
	end;
end

-- ============================================================================
-- timeline helpers
-- ============================================================================

function builder:timeline_length()
	if self.current and self.current.length and self.current.length > 0.05 then
		return self.current.length;
	end;

	local longest = 1;
	for _, action in ipairs(self.actions) do
		if action.when + 0.5 > longest then
			longest = action.when + 0.5;
		end;
	end;
	return math.max(2, longest);
end

function builder:timeline_x_to_when(absolute_x)
	local timeline = widgets.timeline;
	if not timeline then
		return 0;
	end;

	local relative = math.clamp((absolute_x - timeline.AbsolutePosition.X) / math.max(1, timeline.AbsoluteSize.X), 0, 1);
	return round3(relative * self:timeline_length());
end

-- ============================================================================
-- editing
-- ============================================================================

function builder:set_status(text)
	if widgets.status then
		widgets.status.Text = tostring(text);
	end;
end

function builder:add_action(action_type)
	local when = 0;
	if #self.actions > 0 then
		when = round3(self.actions[#self.actions].when + 0.25);
	end;

	if self.current and not table.find(self.ids, self.current.id) then
		table.insert(self.ids, self.current.id);
	end;

	table.insert(self.actions, { type = action_type, when = when });
	self:sort_actions();
	self:render();
	self:set_status(string.format("added %s @ %.2fs", action_type, when));
end

function builder:add_action_at(action_type, when)
	table.insert(self.actions, { type = action_type, when = round3(when) });
	self:sort_actions();
	self:render();
	self:set_status(string.format("added %s @ %.2fs", action_type, when));
end

function builder:sort_actions()
	table.sort(self.actions, function(a, b)
		return (a.when or 0) < (b.when or 0);
	end);
end

function builder:cycle_action(index)
	local action = self.actions[index];
	if not action then
		return;
	end;

	local current = 0;
	for type_index, action_type in ipairs(ACTION_TYPES) do
		if action_type == action.type then
			current = type_index;
			break;
		end;
	end;

	action.type = ACTION_TYPES[(current % #ACTION_TYPES) + 1];
	self:render();
end

function builder:nudge(index, delta)
	local action = self.actions[index];
	if not action then
		return;
	end;

	action.when = round3(math.max(0, (action.when or 0) + delta));
	self:sort_actions();
	self:render();
end

function builder:remove_action(index)
	table.remove(self.actions, index);
	self:render();
end

function builder:clear()
	table.clear(self.actions);
	self:render();
	self:set_status("cleared actions");
end

function builder:cycle_action_type()
	self.action_type_index = (self.action_type_index % (#ASSET_TYPES + 1)) + 1;

	local label = "none";
	if self.action_type_index <= #ASSET_TYPES then
		label = ASSET_TYPES[self.action_type_index];
	end;

	widgets.asset_button.Text = "action group: " .. label;
end

function builder:add_current_id()
	if not self.current then
		return self:set_status("no track loaded");
	end;

	if not table.find(self.ids, self.current.id) then
		table.insert(self.ids, self.current.id);
	end;

	self:render_ids();
	self:set_status("ids: " .. table.concat(self.ids, ", "));
end

-- ============================================================================
-- rendering
-- ============================================================================

function builder:render_ids()
	if widgets.id_label then
		widgets.id_label.Text = (#self.ids > 0) and ("ids: " .. table.concat(self.ids, ", ")) or "";
	end;
end

function builder:render()
	-- markers
	local holder = widgets.marker_holder;
	if holder then
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy();
			end;
		end;

		local length = self:timeline_length();
		for index, action in ipairs(self.actions) do
			local alpha = math.clamp((action.when or 0) / length, 0, 1);
			local marker = new("Frame", {
				Size = UDim2.new(0, 10, 1, 0),
				Position = UDim2.new(alpha, -5, 0, 0),
				BackgroundColor3 = ACTION_COLORS[action.type] or COLORS.text,
				BorderSizePixel = 0,
			}, holder);
			with_corner(marker, 2);
			new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Text = tostring(index),
				TextColor3 = Color3.fromRGB(10, 10, 12),
				Font = Enum.Font.GothamBold,
				TextSize = 10,
			}, marker);
		end;

		widgets.end_label.Text = string.format("%.2fs", length);
	end;

	-- rows
	local list = widgets.list;
	if list then
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy();
			end;
		end;

		for index, action in ipairs(self.actions) do
			local row = with_corner(new("Frame", {
				Size = UDim2.new(1, -6, 0, 22),
				BackgroundColor3 = COLORS.panel_light,
				BorderSizePixel = 0,
				LayoutOrder = index,
			}, list));

			make_label({
				Position = UDim2.new(0, 6, 0, 0),
				Size = UDim2.new(0, 228, 1, 0),
				Text = string.format("#%d  %s  @ %.2fs", index, action.type, action.when or 0),
				TextColor3 = ACTION_COLORS[action.type] or COLORS.text,
				TextSize = 11,
			}, row);

			local type_button = make_button("type", row);
			type_button.Size = UDim2.new(0, 44, 0, 16);
			type_button.Position = UDim2.new(1, -190, 0.5, -8);
			type_button.TextSize = 10;
			type_button.MouseButton1Click:Connect(function()
				builder:cycle_action(index);
			end);

			local minus_button = make_button("-", row);
			minus_button.Size = UDim2.new(0, 24, 0, 16);
			minus_button.Position = UDim2.new(1, -140, 0.5, -8);
			minus_button.MouseButton1Click:Connect(function()
				builder:nudge(index, -0.01);
			end);

			local plus_button = make_button("+", row);
			plus_button.Size = UDim2.new(0, 24, 0, 16);
			plus_button.Position = UDim2.new(1, -110, 0.5, -8);
			plus_button.MouseButton1Click:Connect(function()
				builder:nudge(index, 0.01);
			end);

			local nudge_big = make_button("++", row);
			nudge_big.Size = UDim2.new(0, 24, 0, 16);
			nudge_big.Position = UDim2.new(1, -80, 0.5, -8);
			nudge_big.MouseButton1Click:Connect(function()
				builder:nudge(index, 0.1);
			end);

			local delete_button = make_button("x", row);
			delete_button.Size = UDim2.new(0, 24, 0, 16);
			delete_button.Position = UDim2.new(1, -40, 0.5, -8);
			delete_button.TextColor3 = Color3.fromRGB(230, 110, 110);
			delete_button.MouseButton1Click:Connect(function()
				builder:remove_action(index);
			end);
		end;
	end;

	self:render_ids();
end

-- ============================================================================
-- track loading (timing logger integration)
-- ============================================================================

function builder:load_track(track, entity)
	local ok, err = pcall(function()
		if not (track and track.Animation) then
			return;
		end;

		local id = tostring(track.Animation.AnimationId:match("%d+") or "");
		if #id == 0 then
			return;
		end;

		local entity_name = (entity and entity.Name) or "?";
		local name = anim_display_name(id);

		self.current = {
			id = id,
			name = name,
			entity = entity_name,
			length = 0,
		};

		if not table.find(self.ids, id) then
			table.insert(self.ids, id);
		end;

		if #self.name == 0 and widgets.name_box then
			local clean = (entity_name .. " " .. name):gsub("[^%w%-_ ]", "");
			widgets.name_box.Text = clean;
			self.name = clean;
		end;

		if widgets.track_label then
			widgets.track_label.Text = string.format("%s  (%s)  [%s]", name, entity_name, id);
		end;

		-- track.Length is replicated lazily; poll briefly then refresh the timeline
		task.spawn(function()
			for _ = 1, 20 do
				if track.Length and track.Length > 0 then
					if self.current and self.current.id == id then
						self.current.length = track.Length;
						if self.visible then
							self:render();
						end;
					end;
					return;
				end;
				task.wait(0.1);
			end;
		end);

		self:set_status(string.format("loaded %s from %s", name, entity_name));
		self:set_visible(true);
		self:render();
	end);

	if not ok then
		self:set_status("load_track failed: " .. tostring(err));
	end;
end

-- ============================================================================
-- persistence
-- ============================================================================

function builder:build_timing_table()
	local timing = {
		name = self.name,
		ids = self.ids,
		actions = {},
	};

	if self.action_type_index >= 1 and self.action_type_index <= #ASSET_TYPES then
		timing.action_type = ASSET_TYPES[self.action_type_index];
	end;

	for _, action in ipairs(self.actions) do
		table.insert(timing.actions, {
			type = action.type,
			when = round3(action.when or 0),
		});
	end;

	return timing;
end

function builder:file_path()
	local name = sanitize_file_name(self.name);
	if not name then
		if self.current then
			name = "timing_" .. self.current.id;
		else
			return nil;
		end;
	end;
	return "rw_timings/" .. name .. ".json", name;
end

function builder:save()
	if #self.ids == 0 then
		return self:set_status("nothing to save: no ids loaded (click an anim in the Timing Logger / 'add current id')");
	end;

	if #self.actions == 0 then
		return self:set_status("nothing to save: place at least one action");
	end

	local path, name = self:file_path();
	if not path then
		return self:set_status("set a timing name first");
	end;

	self:sort_actions();

	local ok, err = pcall(function()
		pcall(makefolder, "rw_timings");

		local timing = self:build_timing_table();
		timing.name = name;
		writefile(path, HttpService:JSONEncode(timing));

		if getgenv().load_timings then
			xpcall(getgenv().load_timings, warn);
		end;
	end);

	if ok then
		self:set_status("saved -> " .. path .. " (hot-reloaded)");
		if Library and Library.Notify then
			Library:Notify("saved timing '" .. name .. "'", 3);
		end;
	else
		self:set_status("save failed: " .. tostring(err));
	end;
end

function builder:delete_file()
	local path = self:file_path();
	if not path then
		return self:set_status("no file to delete");
	end;

	pcall(function()
		if isfile(path) then
			delfile(path);
			if getgenv().load_timings then
				xpcall(getgenv().load_timings, warn);
			end;
		end;
	end);

	self:set_status("deleted " .. tostring(path) .. " (if it existed)");
end

-- ============================================================================
-- visibility
-- ============================================================================

function builder:hide(from_close_button)
	self.visible = false;
	if gui then
		gui.Enabled = false;
	end;

	if from_close_button and self.on_close then
		task.spawn(pcall, self.on_close);
	end;
end

function builder:set_visible(visible)
	if visible then
		build_gui();
		gui.Enabled = true;
		self.visible = true;
		self:render();
	else
		self:hide(false);
	end;
end

function builder:is_visible()
	return self.visible;
end

return builder;
