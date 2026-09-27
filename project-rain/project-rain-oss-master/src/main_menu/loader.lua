--[[
	[nzl studio]

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

-- the game's own menu builds asynchronously; retry until the anchor exists
task.spawn(function()
	local characters_label;
	while not characters_label do
		for _, descendant in ipairs(player_gui:GetDescendants()) do
			if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
				and string.match(descendant.Text or "", "^%s*(.-)%s*$") == "Characters" then
				characters_label = descendant;
				break;
			end;
		end;

		if not characters_label then
			task.wait(1);
		end;
	end;

	if characters_label and characters_label.Parent then
		local host = characters_label.Parent;

		local panel = Instance.new("Frame");
		panel.Name = "PRServerSnipe";
		panel.Size = UDim2.new(characters_label.Size.X.Scale, characters_label.Size.X.Offset, 0, 84);
		panel.BackgroundColor3 = Color3.fromRGB(24, 26, 18);
		panel.BackgroundTransparency = 0.28;
		panel.BorderSizePixel = 0;

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

		Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6);

		local panel_stroke = Instance.new("UIStroke", panel);
		panel_stroke.Color = Color3.fromRGB(200, 190, 160);
		panel_stroke.Transparency = 0.65;
		panel_stroke.Thickness = 1;

		-- subtle header: beige text + thin beige divider, like the game's panels
		local header = Instance.new("TextLabel");
		header.Size = UDim2.new(1, -10, 0, 15);
		header.Position = UDim2.fromOffset(10, 4);
		header.BackgroundTransparency = 1;
		header.Text = "server snipe";
		header.TextColor3 = Color3.fromRGB(232, 224, 204);
		header.Font = Enum.Font.Gotham;
		header.TextSize = 12;
		header.TextXAlignment = Enum.TextXAlignment.Left;
		header.Parent = panel;

		local rule = Instance.new("Frame");
		rule.Size = UDim2.new(1, -12, 0, 1);
		rule.Position = UDim2.fromOffset(6, 21);
		rule.BackgroundColor3 = Color3.fromRGB(200, 190, 160);
		rule.BackgroundTransparency = 0.7;
		rule.BorderSizePixel = 0;
		rule.Parent = panel;

		local box = Instance.new("TextBox");
		box.Size = UDim2.new(1, -12, 0, 21);
		box.Position = UDim2.fromOffset(6, 26);
		box.BackgroundColor3 = Color3.fromRGB(30, 33, 28);
		box.BackgroundTransparency = 0.15;
		box.BorderSizePixel = 0;
		box.PlaceholderText = "player name or job id...";
		box.PlaceholderColor3 = Color3.fromRGB(140, 140, 140);
		box.Text = "";
		box.TextColor3 = TEXT;
		box.Font = Enum.Font.Gotham;
		box.TextSize = 11;
		box.ClearTextOnFocus = false;
		box.Parent = panel;
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5);

		local button = Instance.new("TextButton");
		button.Size = UDim2.new(1, -12, 0, 22);
		button.Position = UDim2.fromOffset(6, 51);
		button.BackgroundColor3 = Color3.fromRGB(125, 196, 228);
		button.BackgroundTransparency = 0.05;
		button.BorderSizePixel = 0;
		button.Text = "snipe player";
		button.TextColor3 = Color3.fromRGB(10, 12, 14);
		button.Font = Enum.Font.GothamBold;
		button.TextSize = 11;
		button.Parent = panel;
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5);

		local status_line = Instance.new("TextLabel");
		status_line.Size = UDim2.new(1, -12, 0, 9);
		status_line.Position = UDim2.fromOffset(10, 75);
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
end);

--#endregion

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

--#region purple wipe badge embedded into each character card ---------------------------

-- parented INTO the game's card frame itself (renders as a first-class child),
-- positioned relative to the card using the slot letter's absolute position;
-- if the red skull strip icon can be picked up, the badge snaps exactly under it

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

				-- real character names contain letters (filters "200" etc.)
				if not string.find(name, "%a") then
					continue;
				end;

				diag_candidates += 1;

				local pos = frame.AbsolutePosition;

				if not letter_x or letter_x - pos.X > 60 then
					continue;
				end;

				-- reject outer containers that hold whole cards inside;
				-- only the innermost marked frame is the actual card
				local holds_other_card = false;
				for _, other in ipairs(frame:GetDescendants()) do
					if other:IsA("GuiObject") then
						local o_letter, o_name = frame_card_data(other);
						if o_letter and o_name and string.find(o_name, "%a") then
							holds_other_card = true;
							break;
						end;
					end;
				end;
				if holds_other_card then
					continue;
				end;

				seen_cards[frame] = true;

				-- optional refinement: lowest strip icon inside the card's left quarter
				local skull;
				local skull_y = -math.huge;
				for _, icon in ipairs(tiny_icons) do
					local ipos = icon.AbsolutePosition;
					local isize = icon.AbsoluteSize;
					local cx = ipos.X + isize.X * 0.5;
					local cy = ipos.Y + isize.Y * 0.5;
					if cx >= pos.X and cx <= pos.X + fsize.X * 0.25
						and cy >= pos.Y and cy <= pos.Y + fsize.Y then
						if cy > skull_y then
							skull, skull_y = icon, cy;
						end;
					end;
				end

				-- card-relative badge offsets: by default under the slot letter's
				-- strip column; snapped under the red skull when it is visible
				local rel_x;
				local rel_y;
				if skull then
					rel_x = skull.AbsolutePosition.X + skull.AbsoluteSize.X * 0.5 - 15 - pos.X;
					rel_y = skull.AbsolutePosition.Y + skull.AbsoluteSize.Y + 6 - pos.Y;
				else
					rel_x = letter_x + 2 - pos.X;
					rel_y = (letter_y or pos.Y + 20) + 84 - pos.Y;
				end;

				local purple = purples[frame];
				if not purple then
					local badge = Instance.new("TextButton");
					badge.Name = "PRPurpleSkull";
					badge.Size = UDim2.fromOffset(30, 26);
					badge.Position = UDim2.fromOffset(rel_x, rel_y);
					badge.BackgroundColor3 = BG;
					badge.BackgroundTransparency = 0.15;
					badge.Text = "";
					badge.AutoButtonColor = false;
					badge.ZIndex = frame.ZIndex + 5;
					badge.Parent = frame;

					Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5);

					local badge_stroke = Instance.new("UIStroke", badge);
					badge_stroke.Color = Color3.fromRGB(200, 190, 160);
					badge_stroke.Transparency = 0.55;
					badge_stroke.Thickness = 1;

					local badge_icon;
					if skull and skull.Image ~= "" then
						badge_icon = Instance.new("ImageLabel", badge);
						badge_icon.Size = UDim2.fromOffset(18, 18);
						badge_icon.Position = UDim2.fromOffset(6, 4);
						badge_icon.BackgroundTransparency = 1;
						badge_icon.Image = skull.Image;
						badge_icon.ZIndex = badge.ZIndex + 1;
					else
						-- no template image available: bold purple cross so the
						-- badge always reads as a wipe button, never an empty box
						badge_icon = Instance.new("TextLabel", badge);
						badge_icon.Size = UDim2.new(1, 0, 1, 0);
						badge_icon.BackgroundTransparency = 1;
						badge_icon.Text = "\u{2716}";
						badge_icon.TextSize = 14;
						badge_icon.Font = Enum.Font.GothamBold;
						badge_icon.ZIndex = badge.ZIndex + 1;
					end;
					local set_icon_color = function(color)
						if badge_icon:IsA("ImageLabel") then
							badge_icon.ImageColor3 = color;
						else
							badge_icon.TextColor3 = color;
						end;
					end;
					set_icon_color(PURPLE);

					purple = badge;

					local card_letter = letter;
					local card_name = name;
					local armed_until = 0;

					badge.MouseButton1Click:Connect(function()
						if tick() < armed_until then
							armed_until = 0;
							set_icon_color(PURPLE);
							badge_stroke.Color = Color3.fromRGB(200, 190, 160);
							badge_stroke.Transparency = 0.55;
							status("wiping " .. tostring(card_name) .. " (slot " .. card_letter .. ")...");
							task.spawn(wipe_slot, card_letter);
							return;
						end;

						armed_until = tick() + 4;
						set_icon_color(Color3.fromRGB(255, 120, 255));
						badge_stroke.Color = Color3.fromRGB(255, 120, 255);
						badge_stroke.Transparency = 0.1;
						task.delay(4.2, function()
							if tick() >= armed_until then
								set_icon_color(PURPLE);
								badge_stroke.Color = Color3.fromRGB(200, 190, 160);
								badge_stroke.Transparency = 0.55;
							end;
						end);
					end);

					purples[frame] = badge;
				else
					purple.Position = UDim2.fromOffset(rel_x, rel_y);
					purple.Visible = frame.Visible;
				end;
			end;

			-- drop badges whose card is gone
			local badge_count = 0;
			for frame, purple in pairs(purples) do
				if not seen_cards[frame] or not frame.Parent then
					purples[frame] = nil; -- badge dies with the card (it is parented to it)
				else
					badge_count += 1;
				end;
			end;

			if tick() - last_debug > 5 then
				last_debug = tick();
				-- silent diagnostics: file only, no console spam
				pcall(writefile, "NZL Studio Deep/menu_debug.txt", string.format(
					"[pr menu] scan: frames=%d candidates=%d icons=%d badges=%d",
					diag_frames, diag_candidates, diag_icons, badge_count
				));
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
