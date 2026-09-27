--[[
	[nzl studio]

	This data module was stripped from the public release.
	Upstream it mapped obfuscated/"mystery" mantra choice-card names to the real
	mantra names so the revealer/auto-builder could display them, e.g.:
		return {
			["???"] = "Fire Blade",
			["some_obfuscated_name"] = "Lightning Cloak",
		};

	Consumers fall back gracefully (`mantras[name] or card.MantraName or card.Name`),
	so an empty table is safe — unrevealed cards will show their raw names.
]]

return {};
