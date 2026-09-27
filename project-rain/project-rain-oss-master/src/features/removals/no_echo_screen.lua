-- [nzl studio] Requests/GetScore is deepwoken-only; bounded lookups so
-- require time never blocks outside the game
local requests = services.ReplicatedStorage:FindFirstChild("Requests");
if not requests and aztup and aztup.is_deepwoken then
    requests = services.ReplicatedStorage:WaitForChild("Requests", 15);
end;
local get_score = requests
    and (requests:FindFirstChild("GetScore") or (aztup and aztup.is_deepwoken and requests:WaitForChild("GetScore", 15) or nil));

local feature = Feature:new("no_echo_screen", is_depths and get_score and get_score.OnClientEvent or nil, function()
	if not get_score then return end;
	get_score:FireServer();

	local echo_score_screen = local_player.instance:FindFirstChild("EchoScoreScreen", true);
	echo_score_screen.Enabled = false;
end);

return feature  