--/ Template for a premium feature. Files in this folder only go into the premium file, list them under Premium in Games.lua

return {
	Name = "PremiumExample",

	Build = function(Feature)
		local State = Feature.State

		Feature.Label("Premium tier unlocked")

		Feature.Toggle("Boost", "Boost", State.Boost or false, function(Value)
			State.Boost = Value
		end)

		Feature.Button("Say hello", function()
			Feature.Toast("Hello from a premium feature")
		end)
	end,
}