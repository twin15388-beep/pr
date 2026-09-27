--[[
	[project rain oss]

	This file was stripped from the public release ("Omitted. Do this yourself. <3").
	Community reimplementation of the feature loader.

	Responsibilities (reverse engineered from ~120 feature modules + the ui wrapper):
	  1. expose the global `Feature` class. feature modules self-register with
	     `Feature:new(id, conn?, update?)` and are stored at `aztup.features[id]`.
	     the ui wrapper (utility/ui/wrapper.lua) drives `feature:enable()`,
	     `feature:disable()` and, when `feature.conn` + `feature.update` exist,
	     wires `conn:Connect(update)` while the toggle is on.
	  2. `initialize()` loads every self-registering feature module, one xpcall
	     each so a single broken module can't take the script down.
]]

local loader = {};

local Feature = {};
Feature.__index = Feature;

function Feature.new(id, conn, update)
	assert(typeof(id) == "string", "Feature.new: id must be a string");

	local self = setmetatable({
		id = id,
		conn = conn,     -- RBXScriptSignal the ui wrapper connects while enabled
		update = update, -- handler called with the signal's args
		enabled = false,
		current_connection = nil,
	}, Feature);

	if aztup and aztup.features then
		if aztup.features[id] then
			warn(string.format("[loader] duplicate feature id '%s' (overwriting)", id));
		end;

		aztup.features[id] = self;
	end;

	return self;
end;

-- sane defaults; feature modules override these on their instance
function Feature:enable() end;

function Feature:disable() end;

function Feature:is_enabled()
	return (aztup and aztup.flags and self.id and aztup.flags[self.id]) == true;
end;

do
	-- `Feature:new(...)` sugar + `Feature.new` access
	local feature_mt = {};

	feature_mt.__index = Feature;
	feature_mt.__call = function(_, ...)
		return Feature.new(...);
	end;

	getgenv().Feature = setmetatable({}, feature_mt);
end;

-- modules that must NOT be auto-loaded here:
--   * hard dependencies of init.lua (it requires them directly, in order)
--   * data tables / late-bound helpers pulled in by other modules with require
--   * button bodies (returned as functions, wired up by ui tabs)
--   * the loader itself
local SKIP = {
	["@src/features/loader"] = true,
	["@src/features/hooking"] = true,
	["@src/features/generic_feature"] = true, -- documentation template

	["@src/features/auto-builder/auto_builder"] = true,        -- init.lua
	["@src/features/visuals/player_esp"] = true,               -- init.lua
	["@src/features/visuals/base_esp"] = true,                 -- init.lua
	["@src/features/auto-parry/block-input-manager"] = true,   -- init.lua
	["@src/features/auto-parry/util/target-filter"] = true,    -- init.lua

	["@src/features/auto-parry/builder"] = true,               -- combat tab (stripped/stub)
	["@src/features/misc/mod_detector/group_members"] = true,  -- data table (stripped/stub)
	["@src/features/misc/spotify_widget"] = true,              -- config tab (stripped/stub)
	["@src/features/removals/mantra_revealer/mantras"] = true, -- data table (stripped/stub)
	["@src/features/buttons/refresh"] = true,                  -- button (stripped/stub)
};

-- modules nothing else requires that must be loaded exactly once, up front
-- (auto-parry hooks everything on load and sets global DefendActionManager/Latency)
local ENTRY_POINTS = {
	"@src/features/auto-parry/auto-parry",
};

-- directories with self-registering feature modules (`*` = one level deep)
local SEARCH = {
	"features/auto-parry/*",
	"features/automation/*",
	"features/combat/*",
	"features/exploits/*",
	"features/misc/*",
	"features/misc/mod_detector/*",
	"features/movement/*",
	"features/qol/*",
	"features/removals/*",
	"features/removals/mantra_revealer/*",
	"features/spoofing/*",
	"features/visuals/*",
	"features/auto-fight/*",
	"features/auto-loot/*",
};

function loader.load_module(path)
	local ok, result = xpcall(require, debug.traceback, path);

	if not ok then
		warn(string.format("[loader] failed to load %s:\n%s", path, tostring(result)));
	end;

	return ok;
end;

function loader.initialize()
	local loaded, failed = 0, 0;
	local seen = {};

	local function load(path)
		if seen[path] or SKIP[path] then
			return;
		end;
		seen[path] = true;

		if loader.load_module(path) then
			loaded = loaded + 1;
		else
			failed = failed + 1;
		end;
	end;

	for _, path in ipairs(ENTRY_POINTS) do
		load(path);
	end;

	for _, pattern in ipairs(SEARCH) do
		for _, module in ipairs(list_modules(pattern)) do
			load(module);
		end;
	end;

	local message = string.format("[loader] %d feature modules loaded, %d failed.", loaded, failed);

	if Logger and Logger.log then
		Logger.log(message);
	else
		print(message);
	end;
end;

return loader;
