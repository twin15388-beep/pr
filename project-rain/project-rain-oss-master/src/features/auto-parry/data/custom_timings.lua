--[[
	[nzl studio]

	This data module was stripped from the public release.
	Upstream it managed user-made auto-parry timing definitions (produced by the
	timing builder) and fed them into the animator-handler's lookup chain.

	This is a community reimplementation:

	API (used by handlers/animator-handler.lua):
	  custom_timings:sync()          -> iterator over loaded timing names
	  custom_timings:lookup(id)      -> (timing_table, name) or (nil, nil)
	                                     where timing.ids contains `id`

	Timing files live in `rw_timings` (builder output, per upstream) or
	`NZL Studio/Timings`. Each file may be:
	  * .json  -> { "name": "...", "ids": ["rbxassetid://123", ...], ... }
	  * .lua   -> chunk returning the same table
	Extra fields are passed straight through to the auto-parry, which consumes
	the same shape as its built-in timing entries.
]]

local HttpService = game:GetService("HttpService");

local FOLDERS = {
	"rw_timings",
	"NZL Studio/Timings",
};

local RESCAN_INTERVAL = 2; -- seconds

local custom_timings = {
	timings = {}, -- [name] = timing_table
	names = {},   -- sorted array of names
	last_scan = 0,
};

local function parse_timing_source(src)
	if typeof(src) ~= "string" or #src == 0 then
		return nil;
	end;

	-- json first (builder output), then lua
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, src);
	if ok and typeof(decoded) == "table" then
		return decoded;
	end;

	local fn = select(1, loadstring(src));
	if fn then
		local ran, result = pcall(fn);
		if ran and typeof(result) == "table" then
			return result;
		end;
	end;

	return nil;
end;

local function file_name_to_timing_name(path)
	local name = path:gsub("\\", "/"):match("([^/]+)$") or path;
	name = name:gsub("%.json$", ""):gsub("%.lua$", "");
	return name;
end;

function custom_timings:rescan()
	local now = tick();
	if now - self.last_scan < RESCAN_INTERVAL then
		return;
	end;
	self.last_scan = now;

	local seen = {};

	for _, folder in ipairs(FOLDERS) do
		local is_folder = pcall(isfolder, folder);
		if not is_folder then
			continue;
		end;

		local ok, files = pcall(listfiles, folder);
		if not ok or typeof(files) ~= "table" then
			continue;
		end;

		for _, file in ipairs(files) do
			local is_file = pcall(isfile, file);
			if not is_file then
				continue;
			end;

			local read_ok, src = pcall(readfile, file);
			if not read_ok then
				continue;
			end;

			local timing = parse_timing_source(src);
			if not timing then
				continue;
			end;

			local name = timing.name or file_name_to_timing_name(file);
			if typeof(timing.ids) ~= "table" and typeof(timing.id) == "string" then
				timing.ids = { timing.id };
			end;

			seen[name] = timing;
		end;
	end;

	local names = {};
	for name in pairs(seen) do
		table.insert(names, name);
	end;
	table.sort(names);

	self.timings = seen;
	self.names = names;
end;

function custom_timings:sync()
	self:rescan();

	local index = 0;
	local names = self.names;
	return function()
		index = index + 1;
		return names[index];
	end;
end;

function custom_timings:lookup(id)
	if not id then
		return nil, nil;
	end;

	self:rescan();

	id = tostring(id);
	for name, timing in pairs(self.timings) do
		local ids = timing.ids;
		if typeof(ids) == "table" and (ids[id] or table.find(ids, id)) then
			return timing, name;
		end;
	end;

	return nil, nil;
end;

return custom_timings;
