--[[
	[project rain oss]

	This data module was stripped from the public release.
	Upstream it was a map of Deepwoken staff member userIds -> staff role, e.g.:
		return {
			[123456789] = "Moderator",
			[987654321] = "Developer",
		};

	The mod detector (`mod_detector.lua`) indexes it as moderator_map[user_id].
	Fill it in yourself if you want detection beyond the public group-role check;
	an empty table simply means "no known staff detected by id list".
]]

return {};
