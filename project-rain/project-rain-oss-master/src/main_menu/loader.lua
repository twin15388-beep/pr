--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream it bootstrapped the script's main-menu (PlaceId 4111023553) support.

	Community reimplementation (rebuilt from the user's description):
	  * NO standalone window: everything is pinned into the game's own menu gui
	  * server snipe box docked ABOVE the "Characters" entry - resolves a target
	    PLAYER NAME through the public Roblox presence api and joins their exact
	    server via the game's own PickSlot + PickServer remotes
	  * a PURPLE SKULL cloned onto every character card next to the game's own
	    red skull; two clicks -> Requests.WipeSlot:InvokeServer(<that card slot>)
]]

local requests = services.ReplicatedStorage:WaitForChild("Requests", 30);
local start_menu = requests and requests:WaitForChild("StartMenu", 30);

local ACCENT = Color3.fromRGB(125, 196, 228);
local PURPLE = Color3.fromRGB(150, 80, 220);
local BG = Color3.fromRGB(14, 16, 14);
local TEXT = Color3.fromRGB(232, 224, 204);

local player = services.Players.LocalPlayer;
local player_gui = player:WaitForChild("PlayerGui", 30);

--#region helpers ------------------------------------------------------------------

local function status(line)
	print("[pr menu] " .. line);
end;

local function join_server(job_id, slot)
	if not start_menu then
		status("StartMenu remotes missing");
		return;
	end;

	status("joining " .. string.sub(job_id, 1, 8) .. "... (slot " .. slot .. ")");

	task.spawn(function()
		local pick_slot = start_menu:WaitForChild("PickSlot", 15);
		local pick_server = start_menu:WaitForChild("PickServer", 15);
		if not pick_slot or not pick_server then
			status("PickSlot/PickServer missing");
			return;
		end;

		local deadline = tick() + 45;
		while tick() < deadline and task.wait() do
			pcall(function()
				pick_slot:FireServer(slot, { PrivateTest = false });
			end);
			task.wait(0.4);
			pcall(function()
				pick_server:FireServer(job_id);
			end);
		end;
	end);
end;

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

--#region snipe box above "Characters" -----------------------------------------------

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
		panel.Size = UDim2.new(characters_label.Size.X.Scale, characters_label.Size.X.Offset, 0, 74);
		panel.BackgroundColor3 = BG;
		panel.BackgroundTransparency = 0.25;
		panel.BorderSizePixel = 0;

		local uses_layout = host:FindFirstChildOfClass("UIListLayout") ~= nil;
		if uses_layout then
			panel.LayoutOrder = (characters_label.LayoutOrder or 0) - 1;
		else
			panel.Position = UDim2.new(
				characters_label.Position.X.Scale,
				characters_label.Position.X.Offset,
				characters_label.Position.Y.Scale,
				characters_label.Position.Y.Offset - 82
			);
		end;

		panel.Parent = host;
		Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 4);

		local stroke = Instance.new("UIStroke", panel);
		stroke.Color = Color3.fromRGB(200, 190, 160);
		stroke.Transparency = 0.65;
		stroke.Thickness = 1;

		local box = Instance.new("TextBox");
		box.Size = UDim2.new(1, -12, 0, 22);
		box.Position = UDim2.fromOffset(6, 6);
		box.BackgroundColor3 = Color3.fromRGB(30, 33, 28);
		box.BackgroundTransparency = 0.1;
		box.PlaceholderText = "server snipe (player name)...";
		box.PlaceholderColor3 = Color3.fromRGB(140, 136, 118);
		box.Text = "";
		box.TextColor3 = TEXT;
		box.Font = Enum.Font.Gotham;
		box.TextSize = 11;
		box.ClearTextOnFocus = false;
		box.Parent = panel;
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4);

		local button = Instance.new("TextButton");
		button.Size = UDim2.new(1, -12, 0, 22);
		button.Position = UDim2.fromOffset(6, 32);
		button.BackgroundColor3 = ACCENT;
		button.BackgroundTransparency = 0.05;
		button.Text = "snipe player";
		button.TextColor3 = Color3.fromRGB(8, 12, 14);
		button.Font = Enum.Font.GothamBold;
		button.TextSize = 11;
		button.Parent = panel;
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 4);

		local status_line = Instance.new("TextLabel");
		status_line.Size = UDim2.new(1, -12, 0, 12);
		status_line.Position = UDim2.fromOffset(6, 58);
		status_line.BackgroundTransparency = 1;
		status_line.Text = "";
		status_line.TextColor3 = Color3.fromRGB(170, 215, 170);
		status_line.Font = Enum.Font.Gotham;
		status_line.TextSize = 9;
		status_line.TextXAlignment = Enum.TextXAlignment.Left;
		status_line.Parent = panel;

		button.MouseButton1Click:Connect(function()
			local name = string.gsub(box.Text, "^%s*(.-)%s*$", "%1");
			if #name == 0 then
				status_line.Text = "enter a player name or job id";
				status_line.TextColor3 = Color3.fromRGB(220, 170, 90);
				return;
			end;

			status_line.Text = "resolving '" .. name .. "'...";
			status_line.TextColor3 = Color3.fromRGB(170, 215, 170);

			resolve_player_server(name, function(job_id, err)
				if not job_id then
					status_line.Text = err or "failed";
					status_line.TextColor3 = Color3.fromRGB(220, 120, 120);
					return;
				end;

				status_line.Text = "joining...";
				status_line.TextColor3 = Color3.fromRGB(170, 215, 170);
				join_server(job_id, "A");
			end);
		end);
	end;
end;

--#endregion

--#region purple skull on character cards --------------------------------------------

-- locate the card by content (slot letter + character name), then the red skull
-- as the LOWEST small square icon in the card's left icon strip - no reliance
-- on asset names/ids, which is why the previous name-matching never fired
local function count_card_markers(frame)
	local has_letter = false;
	local has_name = false;

	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local text = string.match(descendant.Text or "", "^%s*(.-)%s*$");
			if #text == 1 and string.match(text, "^[ABC]$") then
				has_letter = true;
			elseif #text > 3 and not has_name then
				has_name = descendant.Text;
			end;
		end;
	end;

	return has_letter, has_name;
end;

local function looks_like_card(frame)
	if not frame:IsA("GuiObject") then
		return false;
	end;

	local has_letter, has_name = count_card_markers(frame);
	local size = frame.AbsoluteSize;
	if not (has_letter and has_name) or size.X < 180 or size.Y < 50 then
		return false;
	end;

	-- reject parent containers that hold whole cards (only innermost = real card)
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant ~= frame then
			local dl, dn = count_card_markers(descendant);
			if dl and dn then
				return false;
			end;
		end;
	end;

	return true;
end;

local function find_strip_skull(card)
	local best;
	local best_y = -math.huge;
	local card_x = card.AbsolutePosition.X;
	local card_w = card.AbsoluteSize.X;

	for _, descendant in ipairs(card:GetDescendants()) do
		if (descendant:IsA("ImageLabel") or descendant:IsA("ImageButton")) and descendant.Name ~= "PRPurpleSkull" then
			local size = descendant.AbsoluteSize;
			local pos = descendant.AbsolutePosition;
			if size.X >= 10 and size.X <= 40 and math.abs(size.X - size.Y) <= 10
				and (pos.X - card_x) < card_w * 0.22
				and descendant.Image ~= "" then
				if pos.Y > best_y then
					best, best_y = descendant, pos.Y;
				end;
			end;
		end;
	end;

	return best;
end;

local function find_card_slot_letter(card)
	for _, descendant in ipairs(card:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local text = string.match(descendant.Text or "", "^%s*(.-)%s*$");
			if text == "A" or text == "B" or text == "C" then
				return text;
			end;
		end;
	end;
	return nil;
end;

local function attach_purple_skull(card, red_skull)
	if red_skull.Parent:FindFirstChild("PRPurpleSkull") then
		return;
	end;

	local card_slot = find_card_slot_letter(card) or "A";

	-- grab the card's character name (for status lines); the wipe remote itself
	-- only needs the slot letter (same call hopper.lua's obliteration makes)
	local card_name = "?";
	for _, descendant in ipairs(card:GetDescendants()) do
		if descendant:IsA("TextLabel") and #string.gsub(descendant.Text or "", "%s+", "") > 3
			and not string.find(descendant.Text, "Lv%.") and descendant.TextSize >= 12 then
			card_name = descendant.Text;
			break;
		end;
	end;

	local purple = Instance.new("ImageButton");
	purple.Name = "PRPurpleSkull";
	purple.Size = red_skull.Size;
	purple.Position = red_skull.Position
		+ UDim2.new(0, 0, red_skull.Size.Y.Scale, red_skull.Size.Y.Offset + 2);
	purple.BackgroundTransparency = 1;
	purple.Image = red_skull.Image;
	purple.ImageColor3 = PURPLE;
	purple.ZIndex = (red_skull.ZIndex or 1) + 2;
	purple.Visible = red_skull.Visible;
	purple.Parent = red_skull.Parent;

	-- keep it glued if the card layout shifts
	red_skull:GetPropertyChangedSignal("Position"):Connect(function()
		purple.Position = red_skull.Position
			+ UDim2.new(0, 0, red_skull.Size.Y.Scale, red_skull.Size.Y.Offset + 2);
	end);
	red_skull:GetPropertyChangedSignal("Visible"):Connect(function()
		purple.Visible = red_skull.Visible;
	end);

	-- two clicks = insta wipe (confirm flash, second click fires immediately)
	local armed_until = 0;
	purple.MouseButton1Click:Connect(function()
		if tick() < armed_until then
			armed_until = 0;
			purple.ImageColor3 = PURPLE;
			status("wiping " .. card_name .. " (slot " .. card_slot .. ")...");
			task.spawn(wipe_slot, card_slot);
			return;
		end;

		armed_until = tick() + 4;
		purple.ImageColor3 = Color3.fromRGB(255, 90, 255);
		task.delay(4.2, function()
			if tick() >= armed_until then
				purple.ImageColor3 = PURPLE;
			end;
		end);
	end);

	status("purple skull attached: " .. card_name .. " (slot " .. card_slot .. ")");
end;

task.spawn(function()
	while true do
		local ok = pcall(function()
			for _, descendant in ipairs(player_gui:GetDescendants()) do
				if looks_like_card(descendant) then
					local red_skull = find_strip_skull(descendant);
					if red_skull then
						attach_purple_skull(descendant, red_skull);
					end;
				end;
			end;
		end);

		if not ok then
			-- next pass retries
		end;

		task.wait(1);
	end;
end);

--#endregion

xpcall(function()
	Logger.log_for_devs("[main menu] oss loader ready: snipe box above Characters + purple skull per card");
end, warn);

return true;
