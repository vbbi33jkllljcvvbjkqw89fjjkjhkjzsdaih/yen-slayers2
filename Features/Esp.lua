--/ Light ESP. One small text label per target, only the nearest few inside the range, refreshed a few times a second
--/ No boxes, tracers or per frame work, so it stays cheap on low end computers

return {
	Name = "ESP",
	Icon = "eye",
	Category = "ESP",

	Build = function(Feature)
		local Players = game:GetService("Players")

		local Player = Players.LocalPlayer
		local State = Feature.State

		State.Range = State.Range or 300
		State.Limit = State.Limit or 25

		local Colors = {
			Players = Color3.fromRGB(90, 170, 255),
			Enemies = Color3.fromRGB(255, 90, 90),
			NPCs = Color3.fromRGB(120, 230, 140),
			Items = Color3.fromRGB(255, 215, 90),
		}

		local Holder = Instance.new("Folder")

		Holder.Name = "YenEsp"
		Holder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

		local Labels = {}
		local Candidates = {}
		local ScannedAt = 0

		local function Root(Model)
			if Model:IsA("BasePart") then
				return Model
			end

			return Model.PrimaryPart or Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChildWhichIsA("BasePart", true)
		end

		--/ Rebuilt every 1.5 seconds. Humanoid models are Players, Enemies (IsMob) or NPCs, loot and chests are Items
		local function Scan()
			Candidates = {}

			local Folder = workspace:FindFirstChild("Humanoids")

			for _, Item in Folder and Folder:GetDescendants() or {} do
				if Item:IsA("Humanoid") and Item.Parent:IsA("Model") and Item.Parent ~= Player.Character then
					local Model = Item.Parent
					local Kind = Players:GetPlayerFromCharacter(Model) and "Players" or Model:GetAttribute("IsMob") == true and "Enemies" or "NPCs"

					if State[Kind] then
						table.insert(Candidates, { Model = Model, Kind = Kind, Humanoid = Item })
					end
				end
			end

			if State.Items then
				for _, Tag in { "Chest", "LootDrop" } do
					for _, Child in game:GetService("CollectionService"):GetTagged(Tag) do
						if Child:IsDescendantOf(workspace) then
							table.insert(Candidates, { Model = Child, Kind = "Items" })
						end
					end
				end
			end
		end

		local function Hide(Index)
			local Label = Labels[Index]

			if Label then
				Label.Enabled = false
			end
		end

		local function Label(Index)
			local Existing = Labels[Index]

			if Existing then
				return Existing
			end

			local Gui = Instance.new("BillboardGui")

			Gui.Size = UDim2.fromOffset(160, 18)
			Gui.StudsOffset = Vector3.new(0, 3, 0)
			Gui.AlwaysOnTop = true
			Gui.ResetOnSpawn = false
			Gui.Parent = Holder

			local Text = Instance.new("TextLabel")

			Text.Name = "Text"
			Text.Size = UDim2.fromScale(1, 1)
			Text.BackgroundTransparency = 1
			Text.Font = Enum.Font.GothamMedium
			Text.TextSize = 12
			Text.TextStrokeTransparency = 0.4
			Text.Parent = Gui

			Labels[Index] = Gui

			return Gui
		end

		local function Refresh()
			local Character = Player.Character
			local Origin = Character and Character:FindFirstChild("HumanoidRootPart")

			if not Origin then
				for Index in Labels do
					Hide(Index)
				end

				return
			end

			if os.clock() - ScannedAt > 1.5 then
				ScannedAt = os.clock()

				Scan()
			end

			local Shown = {}

			for _, Entry in Candidates do
				local Part = Entry.Model.Parent and Root(Entry.Model)

				if Part and (not Entry.Humanoid or Entry.Humanoid.Health > 0) then
					local Distance = (Part.Position - Origin.Position).Magnitude

					if Distance <= State.Range then
						table.insert(Shown, { Entry = Entry, Part = Part, Distance = Distance })
					end
				end
			end

			table.sort(Shown, function(A, B)
				return A.Distance < B.Distance
			end)

			for Index = 1, math.max(#Shown, #Labels) do
				local Item = Shown[Index]

				if Item and Index <= State.Limit then
					local Gui = Label(Index)
					local Text = Gui.Text

					Gui.Adornee = Item.Part
					Gui.Enabled = true
					Text.TextColor3 = Colors[Item.Entry.Kind]
					Text.Text = Item.Entry.Model.Name .. " [" .. math.floor(Item.Distance) .. "]"
				else
					Hide(Index)
				end
			end
		end

		local Stop = nil

		local function Clear()
			if Stop then
				Stop()
				Stop = nil
			end

			for Index in Labels do
				Hide(Index)
			end
		end

		local function Update()
			local Any = State.Players or State.Enemies or State.NPCs or State.Items

			if Any and not Stop then
				ScannedAt = 0
				Stop = Feature.Loop(0.4, Refresh)
			elseif not Any then
				Clear()
			end

			ScannedAt = 0
		end

		Feature.OnUnload(function()
			Clear()
			Holder:Destroy()
		end)

		for _, Kind in { "Players", "Enemies", "NPCs", "Items" } do
			Feature.Toggle(Kind, Kind, State[Kind] or false, function(Value)
				State[Kind] = Value

				Update()
			end)
		end

		local Advanced = {
			Feature.Slider("Range", "Range", 50, 1000, State.Range, function(Value)
				State.Range = Value
			end, 10),

			Feature.Slider("Limit", "Labels shown", 5, 60, State.Limit, function(Value)
				State.Limit = Value
			end),
		}

		local function ShowAdvanced(Value)
			for _, Control in Advanced do
				Control.SetVisible(Value)
			end
		end

		Feature.Toggle("Advanced", "Advanced", State.Advanced or false, function(Value)
			State.Advanced = Value

			ShowAdvanced(Value)
		end)

		ShowAdvanced(State.Advanced or false)
		Update()
	end,
}
