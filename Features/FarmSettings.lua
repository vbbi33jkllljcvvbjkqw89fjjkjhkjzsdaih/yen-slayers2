--/ Farm Settings: weapon, position and the advanced sliders, shared by every farm

local Import = ...

return {
	Name = "Farm Settings",
	Icon = "sliders-horizontal",
	Category = "Autofarms",

	Build = function(Feature)
		Import.Load("Farm.lua").BuildSettings(Feature)
	end,
}
