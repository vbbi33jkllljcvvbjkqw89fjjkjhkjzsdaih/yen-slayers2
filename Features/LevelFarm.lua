--/ Level Farm: takes the best kill quest you can take, bosses included, finishes it, then takes the next
--/ Delivery and pickup story quests are not automated, they are listed in docs/Quests.md

local Import = ...

return {
	Name = "Level Farm",
	Icon = "trending-up",
	Category = "Autofarms",

	Build = function(Feature)
		local Farm = Import.Load("Farm.lua")
		local State = Feature.State
		local Engine
		local Busy = false

		--/ Kill only combat quests have no task specs, boss quests among them. The one that pays the most exp goes first
		local function Best()
			local Quests = Farm.Quests()
			local Pick, PickExp = nil, -1

			for Name, Info in Quests and Quests.Holder or {} do
				if Info.Category == "Combat" and next(Info.TaskSpecs or {}) == nil and Farm.CanAccept(Name) then
					local Exp = Info.Rewards and Info.Rewards.Exp or 0

					if Exp > PickExp then
						Pick, PickExp = Name, Exp
					end
				end
			end

			return Pick
		end

		local function Tick()
			if not State.Enabled or Busy then
				return
			end

			local Name, Quest = Farm.Active()

			if not Name then
				local Wanted = Best()

				if Wanted then
					Busy = true

					Engine.Say("Taking: " .. Wanted)

					local Ok, Err = pcall(Engine.Accept, Wanted)

					Busy = false

					if not Ok then
						Import.Report("Feature Level Farm", Err)
					end

					return
				end

				Engine.Say("No quest to take, fighting nearby")
				Engine.Run(nil)

				return
			end

			Engine.Run(Farm.QuestFilter(Quest))
		end

		Feature.Toggle("Enabled", "Level Farm", State.Enabled or false, function(Value)
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

		Engine = Farm.new(Feature, {})

		Feature.Loop(1.5, Tick)
	end,
}
