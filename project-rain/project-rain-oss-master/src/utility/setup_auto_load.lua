--[[
	[project rain oss]

	This module was stripped from the public release.
	Upstream it registered the Luarmor script for auto-execution on teleport.

	The OSS build has no remote loader to re-fetch, so this is a no-op stub.
	If you want auto-load, queue your own copy, e.g.:
		queue_on_teleport('loadstring(game:HttpGet("<your paste url>"))()')
]]

return true;
