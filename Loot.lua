--/ Auto Loot: picks up the chest and loot a boss drops. Only loot that dropped from the boss you killed, unless that is switched off
--/ Chests and drops are tagged objects with a proximity prompt. Other players can take them too, so it reacts fast

local Import = ...

return {
	Name = "Auto Loot",
	Icon = "package",
	Category = "Misc",

	Build = function(Feature)
		local Farm = Import.Load("Farm.lua")
		local CollectionService = game:GetService("CollectionService")
		local Players = game:GetService("Players")
		local RunService = game:GetService("RunService")
		local State = Feature.State
		local Body = Farm.Body()
		local Tries = {}
		local Kill = nil

		State.Range = State.Range or 500
		State.Speed = State.Speed or 50
		State.Reach = State.Reach or 120

		if State.Mine == nil then
			State.Mine = true
		end

		local Status = Feature.Label("Idle")
		local Message, Shown = "Idle", "Idle"

		--/ Text is queued and written from the frame loop, the same as the farms
		Feature.Connect(RunService.Heartbeat, function()
			if Shown ~= Message then
				Shown = Message

				Status:SetText(Shown)
			end
		end)

		--/ Remembers where the last boss died near you. Anything with 200 or more health counts as a boss
		local Regions = Farm.Regions()

		if Regions then
			Feature.Connect(Regions.DescendantRemoving, function(Item)
				if not Item:IsA("Model") or Item:GetAttribute("IsMob") ~= true then
					return
				end

				local Root = Item.PrimaryPart or Item:FindFirstChild("HumanoidRootPart")
				local Mine = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

				if Root and Mine and (Root.Position - Mine.Position).Magnitude < 250 and (Item:GetAttribute("MaxHealth") or 0) >= 200 then
					Kill = { Name = Item.Name, Position = Root.Position, At = os.clock() }
				end
			end)
		end

		local function Part(Item)
			if Item:IsA("BasePart") then
				return Item
			end

			return Item:IsA("Model") and (Item.PrimaryPart or Item:FindFirstChildWhichIsA("BasePart", true)) or nil
		end

		local Gone = { Locked = true, Opening = true, Opened = true, Despawned = true }

		--/ The nearest chest or drop that has a prompt and is still free. With Mine on it must lie near the last boss you killed
		local function Next(Root)
			local Best, BestPrompt, BestDistance = nil, nil, State.Range

			if State.Mine and (not Kill or os.clock() - Kill.At > 120) then
				return
			end

			for _, Tag in { "Chest", "LootDrop" } do
				for _, Item in CollectionService:GetTagged(Tag) do
					local Target = Item:IsDescendantOf(workspace) and Part(Item)
					local Prompt = Target and Item:FindFirstChildWhichIsA("ProximityPrompt", true)

					if Prompt and (Tries[Item] or 0) < 3 and not Gone[Item:GetAttribute("ChestState")] and (not State.Mine or (Target.Position - Kill.Position).Magnitude <= State.Reach) then
						local Distance = (Target.Position - Root.Position).Magnitude

						if Distance < BestDistance then
							Best, BestPrompt, BestDistance = Item, Prompt, Distance
						end
					end
				end
			end

			return Best, BestPrompt
		end

		local function Collect()
			local Model, Root, Humanoid = Farm.Character()
			local Common = Farm.Shared()

			if not Model or Common.Busy then
				return
			end

			local Item, Prompt = Next(Root)

			if not Item then
				Message = State.Mine and Kill and "Waiting for the drop" or "Nothing to collect"

				return
			end

			local Target = Part(Item)

			Common.Busy = true
			Message = "Collecting " .. Item.Name

			local Started = os.clock()
			local Last, Checked = Root.Position, os.clock()

			--/ Fire the prompt as soon as we are within its reach, no need to land right on top of it
			local Reach = math.max((Prompt.MaxActivationDistance or 10) - 2, 5)

			while State.Enabled and Item.Parent and Farm.Character() and os.clock() - Started < 40 do
				local Left, Resting, Snapped = Body.Travel(Root, Target.Position + Vector3.new(0, 2, 0), State.Speed)

				if Snapped then
					--/ Wait out the rubber band and keep collecting when Resume is on, otherwise stop
					if Farm.Settings().Resume then
						Body.Release()
						Message = "Rubber band, waiting it out"
						task.wait(Farm.Settings().ResumeDelay)
					else
						Message = "Server snapped you back, stopped"
						State.Enabled = false

						break
					end
				end

				if Left < Reach then
					break
				end

				Body.Hold(Model, Humanoid)

				--/ Stops if the character is held in place instead of pushing against it, a rest does not count
				if not Resting and os.clock() - Checked > 3 then
					if (Root.Position - Last).Magnitude < 1.5 then
						Message = "Movement blocked, stopped"
						State.Enabled = false

						break
					end

					Last, Checked = Root.Position, os.clock()
				end

				RunService.Heartbeat:Wait()
			end

			Body.Move(Root, Root.Position, 0)

			if State.Enabled and Item.Parent and Prompt.Parent then
				Tries[Item] = (Tries[Item] or 0) + 1

				pcall(fireproximityprompt, Prompt)
				task.wait(0.6)
			end

			Body.Release()

			Common.Busy = false
		end

		Feature.OnUnload(function()
			Body.Release()

			Farm.Shared().Busy = false
		end)

		Feature.Toggle("Enabled", "Auto Loot", State.Enabled or false, function(Value)
			State.Enabled = Value

			if not Value then
				Body.Release()

				Farm.Shared().Busy = false
				Message = "Idle"
			end
		end)

		Feature.Toggle("Mine", "Only my boss", State.Mine, function(Value)
			State.Mine = Value
		end)

		local Advanced = {
			Feature.Slider("Range", "Range", 50, 1000, State.Range, function(Value)
				State.Range = Value
			end, 10),

			Feature.Slider("Reach", "Distance from the boss", 20, 300, State.Reach, function(Value)
				State.Reach = Value
			end, 10),

			Feature.Slider("Speed", "Travel speed", 10, 50, State.Speed, function(Value)
				State.Speed = Value
			end),
		}

		local function Show(Value)
			for _, Control in Advanced do
				Control.SetVisible(Value)
			end
		end

		Feature.Toggle("Advanced", "Advanced", State.Advanced or false, function(Value)
			State.Advanced = Value

			Show(Value)
		end)

		Show(State.Advanced or false)

		Feature.Loop(0.25, function()
			if State.Enabled then
				Collect()
			end
		end)
	end,
}
