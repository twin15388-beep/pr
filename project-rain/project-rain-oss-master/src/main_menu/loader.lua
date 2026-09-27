--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream it bootstrapped the script's main-menu (PlaceId 4111023553) support.

	This is a community reimplementation stub: it keeps init.lua's control flow
	intact and just tells you nothing main-menu specific is available.
]]

task.spawn(xpcall, function()
	if Logger and Logger.long_notify then
		Logger:long_notify("project rain (oss): main-menu features are not included in the open source release.");
	end;
end, warn);

return true;
