--[[
	[project rain oss]

	This module was stripped from the public release.
	Rebuilt from the user's description of upstream behavior:

	  * server snipe box docked ABOVE the game's "Characters" entry, styled like
	    the main NZL Studio (linoria) ui - dark panel, thin outline, accent rule
	  * a purple skull emoji button glued UNDER the red skull of every character
	    card (overlay at absolute coords); two clicks = insta wipe of that slot
	    (Requests.WipeSlot - the same remote hopper.lua's obliteration fires)
	  * joins a named player's server via the public presence api, or a pasted
	    JobId directly, through the game's own PickSlot + PickServer remotes
]]

local requests = services.ReplicatedStorage:WaitForChild("Requests", 30);
local start_menu = requests and requests:WaitForChild("StartMenu", 30);

local ACCENT = Color3.fromRGB(125, 196, 228);
local PURPLE = Color3.fromRGB(170, 100, 255);
local MAIN = Color3.fromRGB(28, 28, 28);
local BG_INNER = Color3.fromRGB(19, 19, 19);
local OUTLINE = Color3.fromRGB(55, 55, 60);
local TEXT = Color3.fromRGB(230, 230, 230);

local player = services.Players.LocalPlayer;
local player_gui = player:WaitForChild("PlayerGui", 30);

local function status(line)
	print("[pr menu] " .. line);
end;

--#region join / resolve / wipe --------------------------------------------------------

local function join_server(job_id, slot, status_setter)
	if not start_menu then
		if status_setter then status_setter("StartMenu remotes missing", true); end;
		return;
	end;

	if status_setter then status_setter("joining " .. string.sub(job_id, 1, 8) .. "...", false); end;

	task.spawn(function()
		local pick_slot_remote = start_menu:WaitForChild("PickSlot", 15);
		local pick_server_remote = start_menu:WaitForChild("PickServer", 15);
		if not pick_slot_remote or not pick_server_remote then
			if status_setter then status_setter("PickSlot/PickServer missing", true); end;
			return;
		end;

		local deadline = tick() + 45;
		while tick() < deadline and task.wait() do
			pcall(function()
				pick_slot_remote:FireServer(slot, { PrivateTest = false });
			end);
			task.wait(0.4);
			pcall(function()
				pick_server_remote:FireServer(job_id);
			end);
		end;
	end);
end;

local http_request = getgenv().request
	or getgenv().http_request
	or (getgenv().syn and getgenv().syn.request)
	or (getgenv().http and getgenv().http.request);

local function resolve_player_server(name, callback)
	if string.match(name, "^%x+%-%x+%-%x+%-%x+%-%x+$") then
		callback(name, nil);
		return;
	end;

	local ok, user_id = pcall(services.Players.GetUserIdFromNameAsync, services.Players, name);
	if not ok or not user_id then
		callback(nil, "no such player");
		return;
	end;

	if not http_request then
		callback(nil, "no http fn");
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
		callback(nil, "not in game / presence hidden");
		return;
	end;

	callback(presence.gameId, nil);
end;

local function wipe_slot(slot)
	if not requests then
		return;
	end;

	task.spawn(function()
		local wipe_remote = requests:WaitForChild("WipeSlot", 15);
		if not wipe_remote then
			status("WipeSlot remote missing");
			return;
		end;

		local ok, err = pcall(wipe_remote.InvokeServer, wipe_remote, slot);
		status(ok and ("slot " .. slot .. " wiped") or ("wipe failed: " .. tostring(err)));
	end);
end;

--#endregion

--#region linoria-styled snipe box above "Characters" ------------------------------------

do
	local characters_label;
	for _, descendant in ipairs(player_gui:GetDescendants()) do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
			and string.match(descendant.Text or "", "^%s*(.-)%s*$") == "Characters" then
			characters_label = descendant;
			break;
		end;
	end;

	if characters_label and characters_label.Parent then
		local host = characters_label.Parent;

		local panel = Instance.new("Frame");
		panel.Name = "PRServerSnipe";
		panel.Size = UDim2.new(characters_label.Size.X.Scale, characters_label.Size.X.Offset, 0, 88);
		panel.BackgroundColor3 = MAIN;
		panel.BorderColor3 = OUTLINE;
		panel.BorderSizePixel = 1;

		local uses_layout = host:FindFirstChildOfClass("UIListLayout") ~= nil;
		if uses_layout then
			panel.LayoutOrder = (characters_label.LayoutOrder or 0) - 1;
		else
			panel.Position = UDim2.new(
				characters_label.Position.X.Scale,
				characters_label.Position.X.Offset,
				characters_label.Position.Y.Scale,
				characters_label.Position.Y.Offset - 96
			);
		end;
		panel.Parent = host;

		-- header strip with accent rule, mimicking a groupbox title
		local header = Instance.new("TextLabel");
		header.Size = UDim2.new(1, -10, 0, 16);
		header.Position = UDim2.fromOffset(8, 4);
		header.BackgroundTransparency = 1;
		header.Text = "server snipe";
		header.TextColor3 = TEXT;
		header.Font = Enum.Font.GothamBold;
		header.TextSize = 12;
		header.TextXAlignment = Enum.TextXAlignment.Left;
		header.Parent = panel;

		local rule = Instance.new("Frame");
		rule.Size = UDim2.new(1, -10, 0, 1);
		rule.Position = UDim2.fromOffset(5, 22);
		rule.BackgroundColor3 = ACCENT;
		rule.BorderSizePixel = 0;
		rule.Parent = panel;

		local box = Instance.new("TextBox");
		box.Size = UDim2.new(1, -12, 0, 22);
		box.Position = UDim2.fromOffset(6, 28);
		box.BackgroundColor3 = BG_INNER;
		box.BorderColor3 = OUTLINE;
		box.BorderSizePixel = 1;
		box.PlaceholderText = "player name or job id...";
		box.PlaceholderColor3 = Color3.fromRGB(140, 140, 140);
		box.Text = "";
		box.TextColor3 = TEXT;
		box.Font = Enum.Font.Gotham;
		box.TextSize = 11;
		box.ClearTextOnFocus = false;
		box.Parent = panel;

		local button = Instance.new("TextButton");
		button.Size = UDim2.new(1, -12, 0, 22);
		button.Position = UDim2.fromOffset(6, 54);
		button.BackgroundColor3 = ACCENT;
		button.BorderColor3 = Color3.fromRGB(0, 0, 0);
		button.Text = "snipe player";
		button.TextColor3 = Color3.fromRGB(10, 12, 14);
		button.Font = Enum.Font.GothamBold;
		button.TextSize = 11;
		button.Parent = panel;

		local status_line = Instance.new("TextLabel");
		status_line.Size = UDim2.new(1, -12, 0, 10);
		status_line.Position = UDim2.fromOffset(8, 78);
		status_line.BackgroundTransparency = 1;
		status_line.Text = "";
		status_line.TextColor3 = Color3.fromRGB(170, 215, 170);
		status_line.Font = Enum.Font.Gotham;
		status_line.TextSize = 9;
		status_line.TextXAlignment = Enum.TextXAlignment.Left;
		status_line.Parent = panel;

		local function set_line(text, is_error)
			status_line.Text = text;
			status_line.TextColor3 = is_error and Color3.fromRGB(220, 120, 120) or Color3.fromRGB(170, 215, 170);
		end;

		button.MouseButton1Click:Connect(function()
			local name = string.gsub(box.Text, "^%s*(.-)%s*$", "%1");
			if #name == 0 then
				set_line("enter a player name or job id", true);
				return;
			end;

			set_line("resolving '" .. name .. "'...", false);
			resolve_player_server(name, function(job_id, err)
				if not job_id then
					set_line(err or "failed", true);
					return;
				end;
				join_server(job_id, "A", set_line);
			end);
		end);
	end;
end;

--#endregion

--#region purple skull buttons under every card's red skull -------------------------------

local overlay = Instance.new("ScreenGui");
overlay.Name = "PRMenuOverlay";
overlay.IgnoreGuiInset = true;
overlay.ResetOnSpawn = false;
overlay.ZIndexBehavior = Enum.ZIndexBehavior.Global;
overlay.DisplayOrder = 50;
overlay.Parent = (gethui and gethui()) or services.CoreGui;

local function frame_card_data(frame)
	local letter;
	local letter_x;
	local letter_y;
	local name;
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local text = string.match(descendant.Text or "", "^%s*(.-)%s*$");
			if not letter and string.match(text, "^[ABC]$") then
				letter = text;
				letter_x = descendant.AbsolutePosition.X;
				letter_y = descendant.AbsolutePosition.Y;
			elseif not name and #text > 3 then
				name = text;
			end;
		end;
	end;
	return letter, name, letter_x, letter_y;
end;

-- gather small square images (the icon strip: coat / sword / bell / skull)
local tiny_icons = {};
local function refresh_icons()
	table.clear(tiny_icons);

	local ok = pcall(function()
		for _, descendant in ipairs(player_gui:GetDescendants()) do
			if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				local size = descendant.AbsoluteSize;
				if descendant.Image ~= "" and size.X >= 6 and size.X <= 64 and math.abs(size.X - size.Y) <= 18 then
					table.insert(tiny_icons, descendant);
				end;
			end;
		end;
	end);

	if not ok then
		table.clear(tiny_icons);
	end;
end;

local purples = {}; -- card frame -> purple badge

task.spawn(function()
	local last_debug = 0;

	while true do
		local diag_frames = 0;
		local diag_candidates = 0;
		local diag_icons = 0;

		local scan_ok = pcall(function()
			refresh_icons();
			diag_icons = #tiny_icons;

			local seen_cards = {};

			for _, frame in ipairs(player_gui:GetDescendants()) do
				if not frame:IsA("GuiObject") then
					continue;
				end;

				diag_frames += 1;

				local fsize = frame.AbsoluteSize;
				if fsize.X < 180 or fsize.Y < 50 then
					continue;
				end;

				local letter, name, letter_x, letter_y = frame_card_data(frame);
				if not letter or not name then
					continue;
				end;

				diag_candidates += 1;

				local pos = frame.AbsolutePosition;

				-- a real character card has its slot letter on the left edge; the
				-- news/hotfixes panels fail this test (no more stray skulls)
				if not letter_x or letter_x - pos.X > 60 then
					continue;
				end;

				seen_cards[frame] = true;

				-- collect strip icons inside the card's left quarter
				local card_icons = {};
				local skull;
				local skull_y = -math.huge;
				for _, icon in ipairs(tiny_icons) do
					local ipos = icon.AbsolutePosition;
					local isize = icon.AbsoluteSize;
					local cx = ipos.X + isize.X * 0.5;
					local cy = ipos.Y + isize.Y * 0.5;
					if cx >= pos.X and cx <= pos.X + fsize.X * 0.25
						and cy >= pos.Y and cy <= pos.Y + fsize.Y then
						table.insert(card_icons, icon);
						if cy > skull_y then
							skull, skull_y = icon, cy;
						end;
					end;
				end

				-- badge centered on the strip column, 6px under the red skull;
				-- if the game's icons can't be picked up, fall back to the
				-- estimated strip column derived from the slot letter position
				local badge_x;
				local badge_y;
				local anchor_icon;

				if skull then
					anchor_icon = skull;
					badge_x = skull.AbsolutePosition.X + skull.AbsoluteSize.X * 0.5 - 15;
					badge_y = skull.AbsolutePosition.Y + skull.AbsoluteSize.Y + 6;
				elseif letter_x then
					badge_x = letter_x + 2;
					badge_y = (letter_y or pos.Y + 20) + 84;
				else
					continue;
				end;

				local purple = purples[frame];
				if not purple then
					-- tidy clickable badge under the strip: dark rounded pad with
					-- the purple-tinted icon inside; centered on the strip column
					local badge = Instance.new("TextButton");
					badge.Name = "PRPurpleSkull";
					badge.Size = UDim2.fromOffset(30, 26);
					badge.BackgroundColor3 = BG;
					badge.BackgroundTransparency = 0.15;
					badge.Text = "";
					badge.AutoButtonColor = false;
					badge.ZIndex = 20;
					badge.Parent = overlay;

					Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5);

					local badge_stroke = Instance.new("UIStroke", badge);
					badge_stroke.Color = Color3.fromRGB(200, 190, 160);
					badge_stroke.Transparency = 0.55;
					badge_stroke.Thickness = 1;

					local badge_icon = Instance.new("ImageLabel", badge);
					badge_icon.Size = UDim2.fromOffset(18, 18);
					badge_icon.Position = UDim2.fromOffset(6, 4);
					badge_icon.BackgroundTransparency = 1;
					badge_icon.Image = anchor_icon and anchor_icon.Image or "";
					badge_icon.ImageColor3 = PURPLE;
					badge_icon.ZIndex = 21;

					purple = badge;

					local card_letter = letter;
					local card_name = name;
					local armed_until = 0;

					badge.MouseButton1Click:Connect(function()
						if tick() < armed_until then
							armed_until = 0;
							badge_icon.ImageColor3 = PURPLE;
							badge_stroke.Transparency = 0.55;
							status("wiping " .. tostring(card_name) .. " (slot " .. card_letter .. ")...");
							task.spawn(wipe_slot, card_letter);
							return;
						end;

						armed_until = tick() + 4;
						badge_icon.ImageColor3 = Color3.fromRGB(255, 120, 255);
						badge_stroke.Color = Color3.fromRGB(255, 120, 255);
						badge_stroke.Transparency = 0.1;
						task.delay(4.2, function()
							if tick() >= armed_until then
								badge_icon.ImageColor3 = PURPLE;
								badge_stroke.Color = Color3.fromRGB(200, 190, 160);
								badge_stroke.Transparency = 0.55;
							end;
						end);
					end);

					purples[frame] = badge;
					status("purple skull attached: " .. tostring(name) .. " (slot " .. letter .. ")" .. (anchor_icon and "" or " [letter fallback]"));
				end;

				purple.Position = UDim2.fromOffset(badge_x, badge_y);

				local viewport = services.Workspace.CurrentCamera and services.Workspace.CurrentCamera.ViewportSize or Vector2.new(1e9, 1e9);
				purple.Visible = frame.Visible and badge_x > -40 and badge_y > -40 and badge_x < viewport.X and badge_y < viewport.Y;
			end;

			-- drop badges whose card is gone
			local badge_count = 0;
			for frame, purple in pairs(purples) do
				if not seen_cards[frame] or not frame.Parent then
					purple:Destroy();
					purples[frame] = nil;
				else
					badge_count += 1;
				end;
			end;

			if tick() - last_debug > 5 then
				last_debug = tick();
				local debug_line = string.format(
					"[pr menu] scan: frames=%d candidates=%d icons=%d badges=%d",
					diag_frames, diag_candidates, diag_icons, badge_count
				);
				status(debug_line:sub(11));
				pcall(writefile, "Project Rain/menu_debug.txt", debug_line);
			end;
		end);

		if not scan_ok then
			-- retry next pass
		end;

		task.wait(0.35);
	end;
end);

--#endregion

xpcall(function()
	Logger.log_for_devs("[main menu] oss loader ready: snipe box (linoria style) + purple skulls");
end, warn);

return true;
