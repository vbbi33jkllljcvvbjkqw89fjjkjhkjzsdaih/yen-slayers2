--/ Autofarm: flies to the nearest enemy, hovers behind and above it and swings with the game's own packet

local Import = ...

return {
	Name = "Autofarm",
	Icon = "swords",
	Category = "Autofarms",

	Build = function(Feature)
		local Farm = Import.Load("Farm.lua")
		local State = Feature.State
		local Engine

		Feature.Toggle("Enabled", "Autofarm", State.Enabled or false, function(Value)
			State.Enabled = Value

			if not Engine then
				return
			end

			if Value then
				Engine.Resume()
				Engine.Run(nil)
			else
				Engine.Stop()
			end
		end)

		Engine = Farm.new(Feature, { Region = true })

		if State.Enabled then
			Engine.Run(nil)
		end
	end,
}
