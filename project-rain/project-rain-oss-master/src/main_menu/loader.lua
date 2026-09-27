--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream it bootstrapped the script's main-menu (PlaceId 4111023553) support:
	a small window on the deepwoken start screen with rejoin / server hop /
	server snipe actions.

	Community reimplementation: standalone ScreenGui driving
	`utility/deepwoken/servers` (the original hop/rejoin/custom primitives).
]]

-- the servers module touches the global local_player; the full player-data
-- module only loads in game places, so provide the minimal shape here
if not getgenv().local_player then
	getgenv().local_player = {
		instance = services.Players.LocalPlayer,
	};
end;

local servers = require("@src/utility/deepwoken/servers");

local ACCENT = Color3.fromRGB(125, 196, 228);
local BG = Color3.fromRGB(16, 20, 25);
local BG_LIGHT = Color3.fromRGB(28, 34, 42);
local TEXT = Color3.fromRGB(220, 228, 236);

local gui = Instance.new("ScreenGui");
gui.Name = "ProjectRainMenu";
gui.ResetOnSpawn = false;
gui.IgnoreGuiInset = true;
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
gui.Parent = (gethui and gethui()) or services.CoreGui;

local frame = Instance.new("Frame");
frame.Name = "Window";
frame.Size = UDim2.fromOffset(272, 252);
frame.Position = UDim2.new(0.5, -136, 0.08, 0);
frame.BackgroundColor3 = BG;
frame.BorderSizePixel = 0;
frame.Parent = gui;

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6);

local stroke = Instance.new("UIStroke", frame);
stroke.Color = ACCENT;
stroke.Transparency = 0.55;
stroke.Thickness = 1;

local title = Instance.new("TextLabel");
title.Name = "Title";
title.Size = UDim2.new(1, 0, 0, 30);
title.BackgroundTransparency = 1;
title.Text = "  project rain  |  menu";
title.TextColor3 = ACCENT;
title.Font = Enum.Font.GothamBold;
title.TextSize = 14;
title.TextXAlignment = Enum.TextXAlignment.Left;
title.Parent = frame;

-- drag handling ----------------------------------------------------------------
do
	local dragging = false;
	local drag_start;
	local frame_start;

	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true;
			drag_start = input.Position;
			frame_start = frame.Position;
		end;
	end);

	title.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false;
		end;
	end);

	services.UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - drag_start;
			frame.Position = UDim2.new(frame_start.X.Scale, frame_start.X.Offset + delta.X, frame_start.Y.Scale, frame_start.Y.Offset + delta.Y);
		end;
	end);
end;

local function make_label(text, y)
	local label = Instance.new("TextLabel");
	label.Size = UDim2.new(1, -24, 0, 18);
	label.Position = UDim2.fromOffset(12, y);
	label.BackgroundTransparency = 1;
	label.Text = text;
	label.TextColor3 = TEXT;
	label.Font = Enum.Font.Gotham;
	label.TextSize = 12;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.Parent = frame;
	return label;
end;

local function make_button(text, y, accent)
	local button = Instance.new("TextButton");
	button.Size = UDim2.new(1, -24, 0, 30);
	button.Position = UDim2.fromOffset(12, y);
	button.BackgroundColor3 = accent and ACCENT or BG_LIGHT;
	button.Text = text;
	button.TextColor3 = accent and Color3.fromRGB(10, 14, 18) or TEXT;
	button.Font = Enum.Font.GothamBold;
	button.TextSize = 13;
	button.AutoButtonColor = true;
	button.Parent = frame;
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5);
	return button;
end;

-- slot picker -------------------------------------------------------------------
make_label("character slot:", 34);

local selected_slot = "A";
local slot_buttons = {};
for index, slot in ipairs({ "A", "B", "C" }) do
	local button = Instance.new("TextButton");
	button.Size = UDim2.fromOffset(76, 24);
	button.Position = UDim2.fromOffset(12 + (index - 1) * 84, 52);
	button.BackgroundColor3 = BG_LIGHT;
	button.Text = slot;
	button.TextColor3 = TEXT;
	button.Font = Enum.Font.GothamBold;
	button.TextSize = 13;
	button.Parent = frame;
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5);

	button.MouseButton1Click:Connect(function()
		selected_slot = slot;
		for other_slot, other_button in pairs(slot_buttons) do
			other_button.BackgroundColor3 = (other_slot == slot) and ACCENT or BG_LIGHT;
			other_button.TextColor3 = (other_slot == slot) and Color3.fromRGB(10, 14, 18) or TEXT;
		end;
	end);

	slot_buttons[slot] = button;
end;
slot_buttons.A.BackgroundColor3 = ACCENT;
slot_buttons.A.TextColor3 = Color3.fromRGB(10, 14, 18);

-- actions -----------------------------------------------------------------------
local rejoin_button = make_button("rejoin", 86, true);
local hop_button = make_button("server hop", 122);

make_label("server snipe (paste job id):", 160);

local job_box = Instance.new("TextBox");
job_box.Size = UDim2.new(1, -24, 0, 26);
job_box.Position = UDim2.fromOffset(12, 180);
job_box.BackgroundColor3 = BG_LIGHT;
job_box.PlaceholderText = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
job_box.PlaceholderColor3 = Color3.fromRGB(110, 120, 130);
job_box.Text = "";
job_box.TextColor3 = TEXT;
job_box.Font = Enum.Font.Gotham;
job_box.TextSize = 12;
job_box.ClearTextOnFocus = false;
job_box.Parent = frame;
Instance.new("UICorner", job_box).CornerRadius = UDim.new(0, 5);

local snipe_button = make_button("server snipe", 212);
snipe_button.Size = UDim2.new(0.5, -16, 0, 30);

local copy_button = make_button("copy job", 212);
copy_button.Size = UDim2.new(0.5, -16, 0, 30);
copy_button.Position = UDim2.new(0.5, 4, 0, 212);

rejoin_button.MouseButton1Click:Connect(function()
	xpcall(servers.rejoin, warn, servers, selected_slot);
end);

hop_button.MouseButton1Click:Connect(function()
	xpcall(servers.hop, warn, servers, selected_slot);
end);

snipe_button.MouseButton1Click:Connect(function()
	local id = string.gsub(job_box.Text, "%s+", "");
	if #id == 0 then
		job_box.PlaceholderText = "paste a job id first!";
		return;
	end;
	xpcall(servers.custom, warn, servers, selected_slot, id);
end);

copy_button.MouseButton1Click:Connect(function()
	local job_id = game.JobId;
	if job_id == "" then
		job_id = "(no job id - studio/solo)";
	end;
	if setclipboard then
		setclipboard(job_id);
	end;
	job_box.Text = job_id;
end);

xpcall(function()
	Logger.log_for_devs("[main menu] oss loader ready: rejoin / hop / snipe");
end, warn);

return true;
