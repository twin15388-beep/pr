--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream it registered the Luarmor script for auto-execution on teleport.

	OSS reimplementation: queue a re-execution of this exact build through the
	executor's `queue_on_teleport` (deepwoken teleports a lot - start menu,
	depths, layers, server hops - so the script must re-arm itself each time).
]]

local queue = getgenv().queue_on_teleport;
if not queue then
	warn("[auto load] executor does not expose queue_on_teleport - auto load unavailable");
	return false;
end;

queue(
	'loadstring(game:HttpGet("https://raw.githubusercontent.com/twin15388-beep/pr/arena/01a0e209-pr/project-rain/project-rain-oss-master/project-rain.luau"))()'
);

xpcall(function()
	Logger.log_for_devs("[auto load] queued re-execution for teleports");
end, warn);

return true;
