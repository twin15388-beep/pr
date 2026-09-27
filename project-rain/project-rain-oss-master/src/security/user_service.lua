--[[
	[nzl studio]

	This module was stripped from the public release.
	Upstream it authenticated the user against the NZL Studio backend and exposed
	the current user's identity/permissions to the rest of the script.

	This is a community reimplementation that keeps the same surface area so the
	rest of the codebase keeps working: everything is unlocked, nobody is staff.
]]

local local_player = game:GetService("Players").LocalPlayer;

local user_service = {
	loaded = true,
	oss = true,

	user = {
		id = 0,
		discord_id = "0",
		username = local_player and local_player.Name or "user",
		role = "user",
		roles = { "user" },
		permissions = { "*" },
	},
};

function user_service:get(key)
	return self.user[key];
end;

function user_service:get_username()
	return self.user.username;
end;

function user_service:get_role()
	return self.user.role;
end;

function user_service:get_roles()
	return self.user.roles;
end;

function user_service:has_role(_role)
	return false;
end;

function user_service:has_permission(_permission)
	-- oss build: nothing is gated
	return true;
end;

function user_service:is_admin()
	return false;
end;

function user_service:is_staff()
	return false;
end;

function user_service:is_premium()
	return true;
end;

return user_service;
