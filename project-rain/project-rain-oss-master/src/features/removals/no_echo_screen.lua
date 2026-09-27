-- [project rain oss] Requests/GetScore is deepwoken-only; bounded lookups so
-- require time never blocks outside the game
local requests = services.ReplicatedStorage:FindFirstChild("Requests")
    or services.ReplicatedStorage:WaitForChild("Requests", 15);
local get_score = requests and (requests:FindFirstChild("GetScore") or requests:WaitForChild("GetScore", 15));

local feature = Feature:new("no_echo_screen", is_depths and get_score and get_score.OnClientEvent or nil, function()
	if not get_score then return end;
	get_score:FireServer();

	local echo_score_screen = local_player.instance:FindFirstChild("EchoScoreScreen", true);
	echo_score_screen.Enabled = false;
end);

return feature  