--/ Boss Autofarm: claims the boss hunt you pick, flies to the boss and kills it

local Import = ...

return {
	Name = "Boss Autofarm",
	Icon = "skull",
	Category = "Autofarms",

	Build = function(Feature)
		local Farm = Import.Load("Farm.lua")
		local State = Feature.State
		local Engine
		local ClaimedAt = 0

		State.Boss = State.Boss or "Any"

		if State.Claim == nil then
			State.Claim = true
		end

		--/ Every boss the game has a hunt for, read from the quest list
		local Bosses = {}
		local Quests = Farm.Quests()

		for Name, Info in Quests and Quests.Holder or {} do
			local Boss = Info.Category == "BossHunt" and string.match(Name, "^Eliminate (.+)$")

			if Boss then
				table.insert(Bosses, Boss)
			end
		end

		table.sort(Bosses)
		table.insert(Bosses, 1, "Any")

		local function BossName(Quest)
			return string.match(Quest or "", "^Eliminate (.+)$")
		end

		local function Exists(Boss)
			local Regions = Farm.Regions()

			for _, Item in Regions and Regions:GetDescendants() or {} do
				if Item:IsA("Humanoid") and Item.Health > 0 and Item.Parent.Name == Boss and Item.Parent:GetAttribute("IsMob") == true then
					return true
				end
			end

			return false
		end

		--/ Takes the first open hunt that matches the pick, that this character may take and whose boss is standing in the world
		local function Claim()
			if os.clock() - ClaimedAt < 5 then
				return
			end

			ClaimedAt = os.clock()

			local Hunts = game:GetService("ReplicatedStorage"):FindFirstChild("BossHunts")

			for _, Hunt in Hunts and Hunts:GetChildren() or {} do
				local Quest = Hunt:GetAttribute("Quest")
				local Boss = Hunt:GetAttribute("Boss")

				if Quest and Boss and (State.Boss == "Any" or State.Boss == Boss) and (Hunt:GetAttribute("ExpiresAt") or 0) > os.time() and Farm.CanAccept(Quest) and Exists(Boss) then
					Farm.Send("BossHuntsRequest", { action = "Claim", id = Hunt.Name })

					return
				end
			end
		end

		local function Tick()
			if not State.Enabled and not State.Claim then
				return
			end

			local Name = Farm.Active()

			if not Name and State.Claim then
				Claim()
			end

			if not State.Enabled then
				return
			end

			local Boss = BossName(Name)

			--/ Without a hunt, a boss you picked is still fought where it stands
			if not Boss and State.Boss ~= "Any" then
				Boss = State.Boss
			end

			if Boss then
				Engine.Run(function(Model)
					return Model.Name == Boss
				end)
			else
				Engine.Stop()
				Engine.Say("Waiting for a hunt")
			end
		end

		Feature.Toggle("Enabled", "Boss Autofarm", State.Enabled or false, function(Value)
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

		Feature.Dropdown("Boss", "Boss", Bosses, State.Boss, function(Value)
			State.Boss = Value
		end)

		Feature.Toggle("Claim", "Claim hunts", State.Claim, function(Value)
			State.Claim = Value
		end)

		Engine = Farm.new(Feature, {})

		Feature.Loop(1.5, Tick)
	end,
}
