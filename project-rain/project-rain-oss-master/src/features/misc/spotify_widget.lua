--[[
	[nzl studio]

	This module was stripped from the public release.
	Upstream it was the draggable Spotify "now playing" widget; it talked to a
	NZL Studio desktop helper over localhost and exposed playback controls.

	This is a community reimplementation:
	  * real draggable widget frame; `aztup.spotify_widget` points at it so
	    SaveManager persists/restores `.Position` exactly like upstream
	  * visibility toggle + bridge url textbox live in the "Config" tab
	  * bridge contract: point the url at any local helper serving
	      GET  <base>/now-playing   -> {"title": "...", "artist": "...", "playing": true}
	      POST <base>/play-pause | <base>/next | <base>/previous
	    no helper running = widget just shows "not connected"
]]

local Players = game:GetService("Players");
local HttpService = game:GetService("HttpService");
local UserInputService = game:GetService("UserInputService");

local SPOTIFY_GREEN = Color3.fromRGB(30, 215, 96);
local COLORS = {
	background = Color3.fromRGB(18, 18, 20),
	panel = Color3.fromRGB(26, 26, 32),
	stroke = Color3.fromRGB(45, 45, 55),
	text = Color3.fromRGB(230, 230, 238),
	text_dim = Color3.fromRGB(140, 140, 155),
};

local widget = {
	bridge_url = nil,
	poll_task = nil,
	visible = false,
};

local gui;
local frame;
local track_label;
local artist_label;
local status_label;
local play_button;

local function new(class_name, props, parent)
	local inst = Instance.new(class_name);
	for key, value in pairs(props) do
		inst[key] = value;
	end;
	inst.Parent = parent;
	return inst;
end

local function with_corner(inst, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, inst);
	return inst;
end

local function http_request(opts)
	local req = (syn and syn.request) or (http and http.request) or request or fluxus and fluxus.request;
	if not req then
		return nil, "no request function";
	end;

	local ok, response = pcall(req, opts);
	if not ok then
		return nil, response;
	end;

	return response;
end

local function get_bridge_base()
	local raw = widget.bridge_url;
	if typeof(raw) ~= "string" or #raw == 0 then
		return nil;
	end;

	return raw:gsub("/+$", "");
end

local function bridge_post(path)
	local base = get_bridge_base();
	if not base then
		return;
	end;

	task.spawn(function()
		http_request({ Url = base .. path, Method = "POST" });
	end);
end

local function poll_bridge()
	local base = get_bridge_base();
	if not base then
		if status_label then
			status_label.Text = "not connected - set a bridge url in the Config tab";
		end;
		return;
	end;

	task.spawn(function()
		local response = http_request({ Url = base .. "/now-playing", Method = "GET" });

		if not (response and response.Body) then
			if status_label then
				status_label.Text = "bridge unreachable";
			end;
			return;
		end;

		local ok, data = pcall(HttpService.JSONDecode, HttpService, response.Body);
		if not (ok and typeof(data) == "table") then
			if status_label then
				status_label.Text = "bridge returned bad json";
			end;
			return;
		end;

		if track_label then
			track_label.Text = data.title or "unknown track";
		end;
		if artist_label then
			artist_label.Text = data.artist or "";
		end;
		if status_label then
			status_label.Text = data.playing and "playing" or "paused";
		end;
		if play_button then
			play_button.Text = data.playing and "||" or ">";
		end;
	end);
end

local function build_gui()
	if gui then
		return;
	end;

	local parent;
	pcall(function()
		parent = (gethui and gethui()) or game:GetService("CoreGui");
	end);
	parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui");

	gui = new("ScreenGui", {
		Name = "PRSpotifyWidget",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, parent);

	frame = with_corner(new("Frame", {
		Name = "SpotifyWidget",
		Size = UDim2.new(0, 240, 0, 74),
		Position = UDim2.new(0, 16, 0, 220),
		BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0,
		Active = true,
		Draggable = false,
	}, gui));
	new("UIStroke", { Color = COLORS.stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame);

	-- dragging (title strip)
	do
		local strip = new("Frame", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundColor3 = COLORS.panel,
			BorderSizePixel = 0,
		}, frame);
		with_corner(strip, 6);

		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 1, 0),
			Position = UDim2.new(0, 6, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = SPOTIFY_GREEN,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			Text = "spotify",
		}, strip);

		local dragging = false;
		local drag_start;
		local frame_start;

		strip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true;
				drag_start = input.Position;
				frame_start = frame.Position;
			end;
		end);

		UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - drag_start;
				frame.Position = UDim2.new(frame_start.X.Scale, frame_start.X.Offset + delta.X, frame_start.Y.Scale, frame_start.Y.Offset + delta.Y);
			end;
		end);

		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false;
			end;
		end);
	end

	track_label = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 20),
		Size = UDim2.new(1, -16, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLORS.text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "-",
	}, frame);

	artist_label = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 35),
		Size = UDim2.new(1, -16, 0, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLORS.text_dim,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "-",
	}, frame);

	status_label = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 52),
		Size = UDim2.new(0, 110, 0, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLORS.text_dim,
		Font = Enum.Font.Gotham,
		TextSize = 10,
		Text = "not connected - set a bridge url in the Config tab",
	}, frame);

	local function control(text, x_offset, on_click)
		local button = with_corner(new("TextButton", {
			Size = UDim2.new(0, 34, 0, 16),
			Position = UDim2.new(1, x_offset, 0, 50),
			BackgroundColor3 = COLORS.panel,
			TextColor3 = COLORS.text,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			Text = text,
			AutoButtonColor = true,
		}, frame));
		new("UIStroke", { Color = COLORS.stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button);
		button.MouseButton1Click:Connect(on_click);
		return button;
	end

	control("|<", -132, function()
		bridge_post("/previous");
		task.delay(0.4, poll_bridge);
	end);

	play_button = control(">", -92, function()
		bridge_post("/play-pause");
		task.delay(0.4, poll_bridge);
	end);

	control(">|", -52, function()
		bridge_post("/next");
		task.delay(0.4, poll_bridge);
	end);

	-- SaveManager expects this frame on aztup.spotify_widget
	aztup.spotify_widget = frame;
end

function widget:set_visible(visible)
	self.visible = visible == true;

	if self.visible then
		build_gui();
		gui.Enabled = true;
		poll_bridge();
	elseif gui then
		gui.Enabled = false;
	end;

	if self.poll_task then
		task.cancel(self.poll_task);
		self.poll_task = nil;
	end;

	if self.visible then
		self.poll_task = task.spawn(function()
			while widget.visible do
				task.wait(3);
				pcall(poll_bridge);
			end;
		end);
	end;
end;

function widget:set_bridge_url(url)
	self.bridge_url = url;
	if self.visible then
		poll_bridge();
	end;
end;

function widget:is_visible()
	return self.visible;
end

-- make sure aztup.spotify_widget exists even if the widget is never shown
task.defer(function()
	while not (getgenv().aztup) do
		task.wait();
	end;

	if not aztup.spotify_widget then
		local ok = pcall(build_gui);
		if not ok then
			aztup.spotify_widget = { Position = UDim2.new(0, 16, 0, 220) };
		end;
	end;
end);

return widget;
