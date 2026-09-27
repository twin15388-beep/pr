--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream the "Refresh" button sat on the Wipe button and respawned you in
	place ("Respawns you at your same spot, Not usable in combat, Breaks menus.")

	This is a community reimplementation: it kills your character (via the
	replicatesignal Kill path when available) and snaps you back to where you
	were standing once you respawn.
]]

return function()
	task.spawn(xpcall, function()
		local root_part = local_player and local_player.root_part;
		if not root_part then
			return Logger:short_notify("refresh: no character");
		end;

		local spot = root_part.CFrame;

		if replicatesignal then
			replicatesignal(local_player.instance.Kill);
		else
			local humanoid = local_player.character and local_player.character:FindFirstChildOfClass("Humanoid");
			if not humanoid then
				return;
			end;
			humanoid.Health = 0;
		end;

		local new_character = local_player.instance.CharacterAdded:Wait();
		local new_root = new_character:WaitForChild("HumanoidRootPart", 15);
		if not new_root then
			return;
		end;

		task.wait(0.35);
		new_root.CFrame = spot;
	end, warn);
end;
