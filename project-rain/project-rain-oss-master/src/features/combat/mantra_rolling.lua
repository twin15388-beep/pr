
local feature = Feature:new("action_rolling");

-- [project rain oss] deepwoken's KeyBinds only - instant outside via is_deepwoken
local keybinds_instance = game:GetService("ReplicatedStorage"):FindFirstChild("KeyBinds");
if not keybinds_instance and aztup and aztup.is_deepwoken then
    keybinds_instance = game:GetService("ReplicatedStorage"):WaitForChild("KeyBinds", 15);
end;
local ok_keybinds, Keybinds = pcall(function()
    return keybinds_instance and base_require(keybinds_instance);
end);
if not ok_keybinds or not Keybinds then
    Keybinds = {
        IsActionHeld = function() return false; end,
        ForceActionDown = function() end,
        ForceActionUp = function() end,
    };
end;

function feature:enable()
	self.on_mantra_req = local_player.tracker.on_mantra_request.Event:Connect(function(mantra)
		local backpack = local_player.instance:FindFirstChild("Backpack");
		if not backpack then return nil end;

		local ether = local_player.character:FindFirstChild("Ether");
		if not ether or ether.Value <= mantra:GetAttribute("SpellCost") then
			return nil		
end

		if math.random() > aztup.flags.action_rolling_chance / 100 then
			return nil		
end

		if mantra and aztup_options.action_rolling_mantras.Value[mantra:GetAttribute("DefaultName")] then
			Keybinds.ForceActionDown("Dodge")
			Keybinds.ForceActionUp("Dodge")
			
			task.delay(0.15, function()
				local client_feint = EffectReplicator:CreateEffect("ClientFeint");
		
				if client_feint then
					client_feint:Debris(0.1);
				end;
			end)
		end

		return nil	
end)
end;

function feature:disable()
	if self.on_mantra_req then
		self.on_mantra_req:Disconnect();
	end;
end;

return feature