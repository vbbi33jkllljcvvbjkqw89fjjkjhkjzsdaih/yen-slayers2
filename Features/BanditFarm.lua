--/ Bandit Farm: takes a bandit quest from Krue, kills the bandits (and Zuko), repeats

local Import = ...

local Quests = {
	["3 bandits"] = "Ill take 3 bandits",
	["Bandit boss (Lv 7)"] = "Ill take the bandit boss(Lv 7)",
}

return {
	Name = "Bandit Farm",
	Icon = "swords",
	Category = "Autofarms",

	Build = function(Feature)
		local Farm = Import.Load("Farm.lua")
		local State = Feature.State
		local Engine
		local Busy = false

		State.Quest = State.Quest or "3 bandits"

		if State.Collect == nil then
			State.Collect = true
		end

		local function Bandits(Model)
			return Model.Name == "Bandit" or Model.Name == "Zuko"
		end

		local function Tick()
			if not State.Enabled or Busy then
				return
			end

			local Name = Farm.Active()
			local Wanted = Quests[State.Quest]

			if not Name and State.Collect and Wanted and Farm.CanAccept(Wanted) then
				Busy = true

				Engine.Say("Taking quest")

				local Ok, Err = pcall(Engine.Accept, Wanted)

				Busy = false

				if not Ok then
					Import.Report("Feature Bandit Farm", Err)
				end

				return
			end

			Engine.Run(Bandits)
		end

		Feature.Toggle("Enabled", "Bandit Farm", State.Enabled or false, function(Value)
			State.Enabled = Value

			if not Engine then
				return
			end

			if Value then
				Engine.Resume()
			else
				Engine.Stop()
			end
		end)

		Feature.Dropdown("Quest", "Quest", { "3 bandits", "Bandit boss (Lv 7)" }, State.Quest, function(Value)
			State.Quest = Value
		end)

		Feature.Toggle("Collect", "Take the quest", State.Collect, function(Value)
			State.Collect = Value
		end)

		Engine = Farm.new(Feature, {})

		Feature.Loop(1.5, Tick)
	end,
}
