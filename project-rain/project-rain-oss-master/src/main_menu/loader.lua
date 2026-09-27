--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream it bootstrapped the script's main-menu (PlaceId 4111023553) support:
	server snipe box above the character list and the purple-skull wipe action.

	Community reimplementation (rebuilt from user description):
	  * server snipe BY PLAYER NAME - resolves the target's presence through the
	    public Roblox API and joins their exact server (PickSlot + PickServer)
	  * purple wipe button (two-step confirm) -> Requests.WipeSlot:InvokeServer,
	    plus a best-effort purple skull cloned onto the game's own character card
	  * rejoin + copy current JobId as utilities
	  (server hop lives in-game: Main tab > Other > Serverhop - it queues the
	    hopper and picks the slot itself)
]]

-- the servers module touches the global local_player; the full player-data
-- module only loads in game places, so provide the minimal shape here
if not getgenv().local_player then
	getgenv().local_player = {
		instance = services.Players.LocalPlayer,
	};
end;

local requests = services.ReplicatedStorage:WaitForChild("Requests", 30);
local start_menu = requests and requests:WaitForChild("StartMenu", 30);

local ACCENT = Color3.fromRGB(125, 196, 228);
local PURPLE = Color3.fromRGB(150, 80, 220);
local BG = Color3.fromRGB(14, 16, 14);
local BG_LIGHT = Color3.fromRGB(30, 33, 28);
local TEXT = Color3.fromRGB(232, 224, 204);

local gui_parent = (gethui and gethui()) or services.CoreGui;

local gui = Instance.new("ScreenGui");
gui.Name = "ProjectRainMenu";
gui.ResetOnSpawn = false;
gui.IgnoreGuiInset = true;
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
gui.Parent = gui_parent;

local frame = Instance.new("Frame");
frame.Name = "Window";
frame.Size = UDim2.fromOffset(260, 236);
frame.Position = UDim2.new(0, 130, 0.5, -118);
frame.BackgroundColor3 = BG;
frame.BackgroundTransparency = 0.15;
frame.BorderSizePixel = 0;
frame.Parent = gui;

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4);

local stroke = Instance.new("UIStroke", frame);
stroke.Color = Color3.fromRGB(200, 190, 160);
stroke.Transparency = 0.6;
stroke.Thickness = 1;

local title = Instance.new("TextLabel");
title.Size = UDim2.new(1, 0, 0, 26);
title.BackgroundTransparency = 1;
title.Text = "  project rain";
title.TextColor3 = ACCENT;
title.Font = Enum.Font.GothamBold;
title.TextSize = 13;
title.TextXAlignment = Enum.TextXAlignment.Left;
title.Parent = frame;

-- drag handling -----------------------------------------------------------------
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

local function make_row_label(text, y)
	local label = Instance.new("TextLabel");
	label.Size = UDim2.new(1, -20, 0, 16);
	label.Position = UDim2.fromOffset(10, y);
	label.BackgroundTransparency = 1;
	label.Text = text;
	label.TextColor3 = TEXT;
	label.Font = Enum.Font.Gotham;
	label.TextSize = 11;
	label.TextXAlignment = Enum.TextXAlignment.Left;
	label.Parent = frame;
	return label;
end;

local status_label = make_row_label("", 214);
status_label.TextColor3 = Color3.fromRGB(170, 215, 170);
status_label.TextSize = 10;

local selected_slot = "A";
local wipe_button; -- assigned below; slot picker keeps its label in sync
-- slot picker -------------------------------------------------------------------
do
	local slot_buttons = {};
	for index, slot in ipairs({ "A", "B", "C" }) do
		local button = Instance.new("TextButton");
		button.Size = UDim2.fromOffset(72, 20);
		button.Position = UDim2.fromOffset(10 + (index - 1) * 78, 30);
		button.BackgroundColor3 = BG_LIGHT;
		button.BackgroundTransparency = 0.1;
		button.Text = slot;
		button.TextColor3 = TEXT;
		button.Font = Enum.Font.GothamBold;
		button.TextSize = 12;
		button.Parent = frame;
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 4);

		button.MouseButton1Click:Connect(function()
			selected_slot = slot;
			for other_slot, other_button in pairs(slot_buttons) do
				local active = (other_slot == slot);
				other_button.BackgroundColor3 = active and ACCENT or BG_LIGHT;
				other_button.TextColor3 = active and Color3.fromRGB(8, 12, 14) or TEXT;
			end;

			if wipe_button then
				wipe_button.Text = "\u{1F480} wipe slot " .. slot;
			end;
		end);

		slot_buttons[slot] = button;
	end;
	slot_buttons.A.BackgroundColor3 = ACCENT;
	slot_buttons.A.TextColor3 = Color3.fromRGB(8, 12, 14);
end;

local function make_button(text, x, y, w, color, text_color)
	local button = Instance.new("TextButton");
	button.Size = UDim2.fromOffset(w, 24);
	button.Position = UDim2.fromOffset(x, y);
	button.BackgroundColor3 = color or BG_LIGHT;
	button.BackgroundTransparency = 0.1;
	button.Text = text;
	button.TextColor3 = text_color or TEXT;
	button.Font = Enum.Font.GothamBold;
	button.TextSize = 12;
	button.Parent = frame;
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 4);
	return button;
end;

local function set_status(text, color)
	status_label.Text = text;
	status_label.TextColor3 = color or status_label.TextColor3;
end;

-- join loop ----------------------------------------------------------------------
local function join_server(job_id)
	if not start_menu then
		set_status("StartMenu remotes missing", Color3.fromRGB(220, 120, 120));
		return;
	end;

	set_status("joining " .. string.sub(job_id, 1, 8) .. "...");

	task.spawn(function()
		local pick_slot = start_menu:WaitForChild("PickSlot", 15);
		local pick_server = start_menu:WaitForChild("PickServer", 15);
		if not pick_slot or not pick_server then
			set_status("PickSlot/PickServer missing", Color3.fromRGB(220, 120, 120));
			return;
		end;

		local deadline = tick() + 45;
		while tick() < deadline and task.wait() do
			pcall(function()
				pick_slot:FireServer(selected_slot, { PrivateTest = false });
			end);
			task.wait(0.4);
			pcall(function()
				pick_server:FireServer(job_id);
			end);
		end;
	end);
end;

-- player-name -> server resolution ------------------------------------------------
local http_request = getgenv().request
	or getgenv().http_request
	or (getgenv().syn and getgenv().syn.request)
	or (getgenv().http and getgenv().http.request);

local function resolve_player_server(name, callback)
	-- direct JobId paste works too
	if string.match(name, "^%x+%-%x+%-%x+%-%x+%-%x+$") then
		callback(name, nil);
		return;
	end;

	local ok, user_id = pcall(services.Players.GetUserIdFromNameAsync, services.Players, name);
	if not ok or not user_id then
		callback(nil, "no such player '" .. name .. "'");
		return;
	end;

	if not http_request then
		callback(nil, "executor has no http request fn");
		return;
	end;

	local req_ok, response = pcall(http_request, {
		Url = "https://presence.roproxy.com/presence/users",
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = services.HttpService:JSONEncode({ userIds = { user_id } }),
	});

	if not req_ok or not response or not response.Body then
		callback(nil, "presence lookup failed");
		return;
	end;

	local decode_ok, payload = pcall(services.HttpService.JSONDecode, services.HttpService, response.Body);
	local presence = decode_ok and payload and payload.userPresences and payload.userPresences[1];

	if not presence or presence.userPresenceType ~= 2 or not presence.gameId then
		callback(nil, name .. " is not in game (or presence hidden)");
		return;
	end;

	callback(presence.gameId, nil);
end;

-- widgets ------------------------------------------------------------------------
make_row_label("server snipe (player name or job id):", 58);

local name_box = Instance.new("TextBox");
name_box.Size = UDim2.fromOffset(240, 24);
name_box.Position = UDim2.fromOffset(10, 76);
name_box.BackgroundColor3 = BG_LIGHT;
name_box.BackgroundTransparency = 0.1;
name_box.PlaceholderText = "player name...";
name_box.PlaceholderColor3 = Color3.fromRGB(140, 136, 118);
name_box.Text = "";
name_box.TextColor3 = TEXT;
name_box.Font = Enum.Font.Gotham;
name_box.TextSize = 12;
name_box.ClearTextOnFocus = false;
name_box.Parent = frame;
Instance.new("UICorner", name_box).CornerRadius = UDim.new(0, 4);

local snipe_button = make_button("snipe player", 10, 106, 240, ACCENT, Color3.fromRGB(8, 12, 14));
snipe_button.MouseButton1Click:Connect(function()
	local name = string.gsub(name_box.Text, "^%s*(.-)%s*$", "%1");
	if #name == 0 then
		set_status("enter a player name (or job id)", Color3.fromRGB(220, 170, 90));
		return;
	end;

	set_status("resolving '" .. name .. "'...");
	resolve_player_server(name, function(job_id, err)
		if not job_id then
			set_status(err or "failed", Color3.fromRGB(220, 120, 120));
			return;
		end;
		join_server(job_id);
	end);
end);

-- utilities ----------------------------------------------------------------------
local rejoin_button = make_button("rejoin", 10, 138, 116);
rejoin_button.MouseButton1Click:Connect(function()
	if game.JobId == "" then
		set_status("no previous server known", Color3.fromRGB(220, 170, 90));
		return;
	end;
	join_server(game.JobId);
end);

local copy_button = make_button("copy job", 134, 138, 116);
copy_button.MouseButton1Click:Connect(function()
	local job_id = game.JobId;
	if job_id ~= "" and setclipboard then
		setclipboard(job_id);
	end;
	name_box.Text = job_id ~= "" and job_id or name_box.Text;
	set_status("job id in the box");
end);

-- purple wipe (two-step confirm) --------------------------------------------------
local function wipe_slot(slot)
	if not requests then
		set_status("Requests missing", Color3.fromRGB(220, 120, 120));
		return;
	end;

	set_status("wiping slot " .. slot .. "...", PURPLE);
	task.spawn(function()
		local wipe_slot_remote = requests:WaitForChild("WipeSlot", 15);
		if not wipe_slot_remote then
			set_status("WipeSlot remote missing", Color3.fromRGB(220, 120, 120));
			return;
		end;
		local ok, err = pcall(wipe_slot_remote.InvokeServer, wipe_slot_remote, slot);
		set_status(ok and ("slot " .. slot .. " wiped") or ("wipe failed: " .. tostring(err)), ok and PURPLE or Color3.fromRGB(220, 120, 120));
	end);
end;

wipe_button = make_button("\u{1F480} wipe slot A", 10, 170, 240, PURPLE, Color3.fromRGB(245, 240, 250));
local wipe_armed_until = 0;

wipe_button.MouseButton1Click:Connect(function()
	if tick() < wipe_armed_until then
		wipe_button.Text = "\u{1F480} wipe slot A";
		wipe_armed_until = 0;
		task.spawn(wipe_slot, selected_slot);
		return;
	end;

	wipe_armed_until = tick() + 4;
	wipe_button.Text = "sure? click again to WIPE " .. selected_slot;
	task.delay(4.2, function()
		if tick() >= wipe_armed_until then
			wipe_button.Text = "\u{1F480} wipe slot A";
		end;
	end);
end);

make_row_label("server hop lives in-game: main tab > other > serverhop", 190);

-- best-effort purple skull on the game's own slot card ---------------------------
task.spawn(function()
	task.wait(4); -- let the game's menu build its cards

	local ok = pcall(function()
		local player_gui = services.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui");
		if not player_gui then
			return;
		end;

		for _, descendant in ipairs(player_gui:GetDescendants()) do
			if not descendant:IsA("ImageButton") and not descendant:IsA("ImageLabel") then
				continue;
			end;

			local name = string.lower(descendant.Name);
			local image = string.lower(descendant.Image or "");
			if not (string.find(name, "skull") or string.find(image, "skull")) then
				continue;
			end;

			local skull = Instance.new("ImageButton");
			skull.Size = descendant.Size;
			skull.Position = descendant.Position + UDim2.fromOffset(0, 22);
			skull.BackgroundTransparency = 1;
			skull.Image = descendant.Image;
			skull.ImageColor3 = PURPLE;
			skull.ZIndex = (descendant.ZIndex or 1) + 1;
			skull.Parent = descendant.Parent;

			local armed_until = 0;
			skull.MouseButton1Click:Connect(function()
				if tick() < armed_until then
					armed_until = 0;
					task.spawn(wipe_slot, selected_slot);
					return;
				end;
				armed_until = tick() + 4;
				skull.ImageColor3 = Color3.fromRGB(255, 90, 255);
				task.delay(4.2, function()
					if tick() >= armed_until then
						skull.ImageColor3 = PURPLE;
					end;
				end);
			end);

			break; -- one card clone is enough
		end;
	end);

	if not ok then
		-- the in-window wipe button above remains as the fallback
	end;
end);

xpcall(function()
	Logger.log_for_devs("[main menu] oss loader ready: snipe (player name) / wipe (purple) / rejoin");
end, warn);

return true;
