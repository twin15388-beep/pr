--[[
	[project rain oss]

	This data module was stripped from the public release.
	Upstream it was a map of dropped-item mesh asset ids -> item names so the base
	ESP could label loot on the ground, e.g.:
		return {
			["12345678901"] = "Dormant Splinter",
			["10987654321"] = "Umbral Obsidian",
		};

	`base_esp.lua` indexes it as deepwoken_mesh_ids[tostring(mesh_id)] and falls
	back to "Dropped Item", so an empty table is safe — loot just shows generically.
	Collect ids from dropped item MeshParts (SpecialMesh.MeshId) to fill it in.
]]

return {};
