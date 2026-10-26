--/ Template feature. Copy this file, rename it and list the name in Games.lua
--/ Everything on Feature is protected: errors go to Diagnostics, nothing prints, and loops, connections and threads stop when the hub unloads
--/ Feature.State survives switching interface, so a running feature can start itself again after the rebuild

return {
	Name = "Example",
	Category = "Misc",

	Build = function(Feature)
		local State = Feature.State

		State.Ticks = State.Ticks or 0
		State.Speed = State.Speed or 1
		State.Mode = State.Mode or "Count up"

		local Status = Feature.Label("Ticks: " .. State.Ticks)
		local Stop = nil

		local function Refresh()
			Status:SetText("Ticks: " .. State.Ticks .. " (" .. State.Mode .. ")")
		end

		local function Start()
			if Stop then
				Stop()
			end

			Stop = Feature.Loop(1 / State.Speed, function()
				State.Ticks += State.Mode == "Count up" and 1 or -1

				Refresh()
			end)
		end

		Feature.Toggle("Counter", "Counter", State.Enabled or false, function(Value)
			State.Enabled = Value

			if Value then
				Start()
			elseif Stop then
				Stop()
				Stop = nil
			end
		end)

		Feature.Slider("Speed", "Speed", 1, 10, State.Speed, function(Value)
			State.Speed = Value

			if State.Enabled then
				Start()
			end
		end)

		Feature.Dropdown("Mode", "Mode", { "Count up", "Count down" }, State.Mode, function(Value)
			State.Mode = Value

			Refresh()
		end)

		Feature.Input("Note", "Note", State.Note or "", function(Value)
			State.Note = Value
		end)

		Feature.Keybind("Reset", "Reset key", "R", function()
			State.Ticks = 0

			Refresh()
		end)

		Feature.Button("Reset now", function()
			State.Ticks = 0

			Refresh()
		end)

		if State.Enabled then
			Start()
		end
	end,
}