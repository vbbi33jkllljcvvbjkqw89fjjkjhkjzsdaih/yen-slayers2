--/ Shared engine for the Slayers 2 farms. Movement, targeting, attacks, quest helpers and the settings every farm shares
--/ Found by reading the game: mobs sit under Workspace.Humanoids.Regions with an IsMob attribute, swings and quests go through SignalEvent.Event

local Import = ...

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

local Farm = {}

function Farm.Dig(Root, Path)
	local Node = Root

	for _, Name in Path do
		Node = Node and Node:FindFirstChild(Name)
	end

	return Node
end

local Dig = Farm.Dig

--/ One farm moves the character at a time. Busy is set by the loot collector while it flies, Owner is the engine in control
local function Shared()
	local Table = getgenv().YenFarm

	if not Table then
		Table = { Busy = false, Owner = nil }
		getgenv().YenFarm = Table
	end

	return Table
end

Farm.Shared = Shared

function Farm.Remote()
	return Dig(ReplicatedStorage, { "Communication", "ServerAndClient", "Signals", "SignalEvent", "Event" })
end

function Farm.Send(...)
	local Remote = Farm.Remote()

	if Remote then
		Remote:FireServer(...)

		return true
	end

	return false
end

local function Require(Path)
	local Module = Dig(ReplicatedStorage, Path)
	local Ok, Result = pcall(require, Module)

	return Ok and Result or nil
end

function Farm.Quests()
	return Require({ "CAM", "Global", "Subsets", "Gameplay", "Quests" })
end

function Farm.Regions()
	return Dig(workspace, { "Humanoids", "Regions" })
end

function Farm.Character()
	local Model = Player.Character

	if not Model then
		return
	end

	local Root = Model:FindFirstChild("HumanoidRootPart")
	local Humanoid = Model:FindFirstChildOfClass("Humanoid")

	if Root and Humanoid and Humanoid.Health > 0 then
		return Model, Root, Humanoid
	end
end

--/ The quest the player is on right now, nil when there is none
function Farm.Active()
	local Utility = Require({ "CAM", "Global", "Utility" })

	if not Utility then
		return
	end

	local Ok, Data = pcall(Utility.GetData, Player)
	local Holder = Ok and Data and Dig(Data, { "Quests", "Holder" })
	local First = Holder and Holder:GetChildren()[1]

	return First and First.Name, First
end

function Farm.CanAccept(Name)
	local Quests = Farm.Quests()

	if not Quests then
		return false
	end

	local Ok, Result = pcall(Quests.CanAddQuest, Player, Name)

	return Ok and Result == true
end

--/ The chat prompt of a quest giver, found by name under Workspace.Debree
local Prompts = {}

function Farm.NpcPrompt(Name)
	if type(Name) ~= "string" then
		return
	end

	local Known = Prompts[Name]

	if Known and Known.Parent then
		return Known, Known:FindFirstAncestorOfClass("Model") and Known:FindFirstAncestorOfClass("Model").PrimaryPart or Known.Parent
	end

	local Folder = workspace:FindFirstChild("Debree")

	for _, Item in Folder and Folder:GetDescendants() or {} do
		if Item:IsA("ProximityPrompt") then
			local Model = Item:FindFirstAncestorOfClass("Model")

			if Model and Model.Name == Name then
				Prompts[Name] = Item

				return Item, Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart")
			end
		end
	end
end

function Farm.CloseDialogue()
	local Utility = Require({ "CAM", "Client", "Components", "Client", "DialogueComponent", "DialogueUtility" })

	if Utility and Utility.Close then
		pcall(Utility.Close)
	end
end

function Farm.Info(Name)
	local Quests = Farm.Quests()

	return Quests and Quests.Holder and Quests.Holder[Name]
end

--/ Mobs the quest wants killed, read from its task codes. A code like KaruVillageBandit matches a mob called Bandit
--/ Lowercase and drop spaces and punctuation, so a quest code like "VillageSpy" matches a mob called "Village Spy"
local function Squash(Text)
	return (string.gsub(string.lower(tostring(Text)), "[^%a%d]", ""))
end

function Farm.QuestFilter(Quest)
	local Codes = {}
	local Tasks = Quest and Dig(Quest, { "Tasks" })

	for _, Task in Tasks and Tasks:GetChildren() or {} do
		local Code = Task:FindFirstChild("Code")
		local Value = Task:FindFirstChild("Value")
		local Max = Task:FindFirstChild("Max")

		if Code and Code.Value ~= "" and (not Value or not Max or Value.Value < Max.Value) then
			table.insert(Codes, Squash(Code.Value))
		end
	end

	if #Codes == 0 then
		return nil
	end

	return function(Model)
		--/ A disguised target is shown wrapped in asterisks, like *Civilian*, while the real civilians stay plain. Those are the quest's mobs
		if string.find(Model.Name, "^%*.+%*$") then
			return true
		end

		local Name = Squash(Model.Name)

		for _, Code in Codes do
			if Code ~= "" and Name ~= "" and (Code == Name or string.find(Code, Name, 1, true) or string.find(Name, Code, 1, true)) then
				return true
			end
		end

		return false
	end
end

--/ Holds the character in the air and moves it with physics forces, not CFrame teleports, so the server sees a normal moving character
--/ Movement is a BodyPosition pulling toward a moving waypoint at the chosen speed, with a BodyGyro for facing (the way most of these scripts move)
--/ Flying far in one go still gets pulled back, so Travel goes in short hops: every ~50 studs it drops a platform under the feet and stops for a moment
--/ A server snap back (a jump far bigger than the step we asked for) is treated as a detection and makes the farm halt, the same signal those scripts watch for
local HopDistance = 50
local HopRest = 0.25
local SnapMargin = 40

function Farm.Body()
	local Body = {}
	local Held = nil
	local Ghosted = {}
	local LastGhost = 0

	local Travelled = 0
	local LastHopPos = nil
	local RestUntil = 0
	local Platform = nil

	local Mover = nil
	local Gyro = nil
	local LastMove = nil
	local SnapPrev = nil
	local LastSet = nil

	local function ClearPlatform()
		if Platform then
			pcall(function()
				Platform:Destroy()
			end)

			Platform = nil
		end
	end

	local function ClearMover()
		for _, Instance in { Mover, Gyro } do
			if Instance then
				pcall(function()
					Instance:Destroy()
				end)
			end
		end

		Mover, Gyro = nil, nil
	end

	function Body.Release()
		if Held then
			pcall(function()
				Held.PlatformStand = false
			end)

			Held = nil
		end

		for Part in Ghosted do
			pcall(function()
				Part.CanCollide = true
			end)
		end

		table.clear(Ghosted)
		ClearPlatform()
		ClearMover()

		Travelled = 0
		LastHopPos = nil
		RestUntil = 0
		LastMove = nil
		SnapPrev = nil
		LastSet = nil
	end

	function Body.Hold(Model, Humanoid)
		if Held ~= Humanoid then
			Body.Release()
		end

		Held = Humanoid
		Humanoid.PlatformStand = true

		--/ The humanoid turns collisions back on by itself, so they are cleared again every quarter second
		if os.clock() - LastGhost > 0.25 then
			LastGhost = os.clock()

			for _, Part in Model:GetDescendants() do
				if Part:IsA("BasePart") and Part.CanCollide then
					Ghosted[Part] = true
					Part.CanCollide = false
				end
			end
		end
	end

	--/ Builds the force movers on the root, or rebuilds them if the character respawned and they were lost
	local function Ensure(Root)
		if Mover and Mover.Parent == Root and Gyro and Gyro.Parent == Root then
			return
		end

		ClearMover()

		local Position = Instance.new("BodyPosition")

		Position.Name = "YenMove"
		Position.MaxForce = Vector3.one * math.huge
		Position.P = 30000
		Position.D = 2000
		Position.Position = Root.Position
		Position.Parent = Root

		local Spin = Instance.new("BodyGyro")

		Spin.Name = "YenGyro"
		Spin.MaxTorque = Vector3.one * math.huge
		Spin.P = 30000
		Spin.D = 600
		Spin.CFrame = Root.CFrame
		Spin.Parent = Root

		Mover, Gyro = Position, Spin
	end

	--/ Instantly sets the root at Goal facing Face. Snap is detected by us arriving far from where we last put ourselves (the server pulled us)
	local function Teleport(Root, Goal, Face)
		ClearMover()

		local Snapped = LastSet ~= nil and (Root.Position - LastSet).Magnitude > 30

		if Face and (Vector3.new(Face.X, Goal.Y, Face.Z) - Goal).Magnitude > 0.1 then
			Root.CFrame = CFrame.lookAt(Goal, Vector3.new(Face.X, Goal.Y, Face.Z))
		else
			Root.CFrame = CFrame.new(Goal) * (Root.CFrame - Root.CFrame.Position)
		end

		Root.AssemblyLinearVelocity = Vector3.zero
		Root.AssemblyAngularVelocity = Vector3.zero

		LastSet = Goal

		return (Goal - Root.Position).Magnitude, Snapped
	end

	--/ Moves the root toward Goal, facing Face. Teleport sets it there at once, Fly pulls it with a BodyPosition. Returns distance left and whether the server snapped us
	function Body.Move(Root, Goal, Speed, Face)
		if Farm.Settings().Move == "Teleport" then
			return Teleport(Root, Goal, Face)
		end

		LastSet = nil

		Ensure(Root)

		local Now = os.clock()
		local Delta = LastMove and math.clamp(Now - LastMove, 0, 0.1) or 1 / 60

		LastMove = Now

		local Offset = Goal - Root.Position
		local Distance = Offset.Magnitude
		local Step = Speed * Delta

		--/ The waypoint sits one step ahead toward the goal, so the stiff BodyPosition tracks it at about Speed studs a second
		local Waypoint = (Distance <= Step or Distance < 0.3) and Goal or Root.Position + Offset.Unit * Step

		Mover.Position = Waypoint

		if Face then
			local Look = Face - Root.Position

			if Look.Magnitude > 0.1 then
				Gyro.CFrame = CFrame.lookAt(Root.Position, Vector3.new(Face.X, Root.Position.Y, Face.Z))
			end
		elseif Offset.Magnitude > 0.1 then
			Gyro.CFrame = CFrame.lookAt(Root.Position, Root.Position + Vector3.new(Offset.X, 0, Offset.Z))
		end

		local Snapped = false

		if SnapPrev then
			local Moved = (Root.Position - SnapPrev).Magnitude

			Snapped = Moved > Step + SnapMargin
		end

		SnapPrev = Root.Position

		return Distance, Snapped
	end

	--/ Like Move but hops: pauses on a dropped platform every HopDistance studs. Teleport needs no hops. Returns distance left, whether resting, whether snapped
	function Body.Travel(Root, Goal, Speed, Face)
		if Farm.Settings().Move == "Teleport" then
			local Distance, Snapped = Teleport(Root, Goal, Face)

			return Distance, false, Snapped
		end

		local Now = os.clock()
		local Distance = (Goal - Root.Position).Magnitude

		if RestUntil > Now then
			Ensure(Root)

			Mover.Position = Root.Position
			SnapPrev = Root.Position

			return Distance, true, false
		end

		if Platform then
			ClearPlatform()

			Travelled = 0
		end

		if LastHopPos then
			Travelled += (Root.Position - LastHopPos).Magnitude
		end

		LastHopPos = Root.Position

		--/ Close enough to the goal, no need to break the last stretch
		if Travelled >= HopDistance and Distance > HopDistance then
			local Pad = Instance.new("Part")

			Pad.Anchored = true
			Pad.CanCollide = true
			Pad.Transparency = 1
			Pad.Size = Vector3.new(12, 1, 12)
			Pad.CFrame = CFrame.new(Root.Position - Vector3.new(0, 3.5, 0))
			Pad.Parent = workspace

			Platform = Pad
			RestUntil = Now + HopRest

			Ensure(Root)
			Mover.Position = Root.Position

			return Distance, true, false
		end

		local _, Snapped = Body.Move(Root, Goal, Speed, Face)

		return Distance, false, Snapped
	end

	return Body
end

--/ One set of settings shared by every farm, shown once in the Farm Settings group. Weapon is the fighting style the swing packet carries
function Farm.Settings()
	local Settings = getgenv().YenFarmSettings

	if not Settings then
		Settings = {
			Move = "Teleport",
			Weapon = "Auto",
			Position = "Behind and up",
			Back = 6,
			Height = 4,
			Speed = 50,
			Rate = 0.25,
			Retreat = 25,
			Region = "All regions",
			Resume = true,
			ResumeDelay = 2.5,
			Advanced = false,
		}

		getgenv().YenFarmSettings = Settings
	end

	return Settings
end

function Farm.BuildSettings(Feature)
	local State = Farm.Settings()
	local Styles = { "Auto" }
	local Animations = Dig(ReplicatedStorage, { "Assets", "Animations" })

	for _, Item in Animations and Animations:GetChildren() or {} do
		local Name = string.match(Item.Name, "^(.+)_Combat_Anims$")

		if Name then
			table.insert(Styles, Name)
		end
	end

	table.sort(Styles, function(A, B)
		return A == "Auto" or (B ~= "Auto" and A < B)
	end)

	Feature.Dropdown("Move", "Movement", { "Teleport", "Fly" }, State.Move, function(Value)
		State.Move = Value
	end)

	Feature.Dropdown("Weapon", "Weapon", Styles, State.Weapon, function(Value)
		State.Weapon = Value
	end)

	Feature.Dropdown("Position", "Position", { "Behind and up", "Under" }, State.Position, function(Value)
		State.Position = Value
	end)

	--/ On a rubber band, wait it out and carry on instead of stopping for good
	Feature.Toggle("Resume", "Resume on rubber band", State.Resume, function(Value)
		State.Resume = Value
	end)

	local Names = { "All regions" }
	local Regions = Farm.Regions()

	for _, Item in Regions and Regions:GetChildren() or {} do
		table.insert(Names, Item.Name)
	end

	local Advanced = {
		Feature.Dropdown("Region", "Region", Names, State.Region, function(Value)
			State.Region = Value
		end),

		Feature.Slider("Height", "Height from enemy", 2, 20, State.Height, function(Value)
			State.Height = Value
		end),

		Feature.Slider("Back", "Distance behind enemy", 1, 15, State.Back, function(Value)
			State.Back = Value
		end),

		Feature.Slider("Speed", "Travel speed", 10, 50, State.Speed, function(Value)
			State.Speed = Value
		end),

		Feature.Slider("Rate", "Attack delay", 0.05, 1, State.Rate, function(Value)
			State.Rate = Value
		end, 0.05),

		Feature.Slider("Retreat", "Pause below health %", 0, 90, State.Retreat, function(Value)
			State.Retreat = Value
		end),

		Feature.Slider("ResumeDelay", "Rubber band wait (s)", 0.5, 8, State.ResumeDelay, function(Value)
			State.ResumeDelay = Value
		end, 0.5),
	}

	local function Show(Value)
		for _, Control in Advanced do
			Control.SetVisible(Value)
		end
	end

	Feature.Toggle("Advanced", "Advanced", State.Advanced, function(Value)
		State.Advanced = Value

		Show(Value)
	end)

	Show(State.Advanced)
end

function Farm.new(Feature, Options)
	Options = Options or {}

	local State = Farm.Settings()
	local Engine = { Mode = "Off", Filter = nil, Target = nil, Goal = nil, Arrived = false, PausedUntil = 0 }
	local Body = Farm.Body()

	local Cache = {}
	local CachedAt = 0
	local LastAttack = 0
	local Combo = 0

	local Status = Feature.Label("Idle")
	local Shown = "Idle"

	--/ Calling the game's quest code leaves the thread unable to touch the UI, so text is queued and written from the frame loop
	Engine.Message = "Idle"

	function Engine.Say(Text)
		Engine.Message = Text
	end

	local function Alive(Model)
		local Humanoid = Model and Model.Parent and Model:FindFirstChildOfClass("Humanoid")

		return Humanoid ~= nil and Humanoid.Health > 0
	end

	local function EnemyRoot(Model)
		return Model.PrimaryPart or Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChildWhichIsA("BasePart")
	end

	--/ Rebuilt at most every 1.5 seconds so a big map is not scanned every frame
	local function Enemies()
		if os.clock() - CachedAt < 1.5 then
			return Cache
		end

		CachedAt = os.clock()
		Cache = {}

		local Folder = Farm.Regions()

		if Folder and Options.Region and State.Region ~= "All regions" then
			Folder = Folder:FindFirstChild(State.Region)
		end

		for _, Item in Folder and Folder:GetDescendants() or {} do
			if Item:IsA("Humanoid") and Item.Health > 0 then
				local Model = Item.Parent

				if Model and Model:IsA("Model") and Model:GetAttribute("IsMob") == true and EnemyRoot(Model) and (not Engine.Filter or Engine.Filter(Model)) then
					table.insert(Cache, Model)
				end
			end
		end

		return Cache
	end

	local function Nearest(Root)
		local Best, BestDistance = nil, math.huge

		for _, Model in Enemies() do
			local Part = Alive(Model) and EnemyRoot(Model)

			if Part then
				local Distance = (Part.Position - Root.Position).Magnitude

				if Distance < BestDistance then
					Best, BestDistance = Model, Distance
				end
			end
		end

		return Best
	end

	local function HasStyle(Name)
		return Name ~= nil and Name ~= "" and Dig(ReplicatedStorage, { "Assets", "Animations", Name .. "_Combat_Anims" }) ~= nil
	end

	--/ Auto follows the tool you hold, then your power, then plain Combat
	local function Style(Model)
		if State.Weapon ~= "Auto" then
			return State.Weapon
		end

		for _, Item in Model:GetChildren() do
			if Item:IsA("Tool") and HasStyle(Item.Name) then
				return Item.Name
			end
		end

		local Power = Dig(ReplicatedStorage, { "CAM", "Client", "Controllers", "Skills_Provider", "CurPower" })

		for _, Name in Power and string.split(Power.Value, ",") or {} do
			if HasStyle(Name) then
				return Name
			end
		end

		return "Combat"
	end

	local function Attack(Model)
		if os.clock() - LastAttack < State.Rate then
			return
		end

		LastAttack = os.clock()
		Combo = Combo % 5 + 1

		Farm.Send("Combat_Service", Style(Model), Combo, false, 0, false)
	end

	--/ If the character is told to move but stays put, something is holding it. The farm stops instead of pushing against it
	local LastPos, LastCheck = nil, 0

	local function Blocked(Root, Distance)
		if os.clock() - LastCheck < 3 then
			return false
		end

		local Moved = LastPos and (Root.Position - LastPos).Magnitude or math.huge

		LastPos, LastCheck = Root.Position, os.clock()

		return Moved < 1.5 and Distance > 10
	end

	local function Halt(Reason)
		Engine.Stop()

		Engine.Halted = true
		LastPos = nil

		local Text = Reason or "Movement blocked, stopped"

		Engine.Say(Text)

		--/ A silent stop leaves the player thinking the farm is still going, so tell them on a card. Resume clears the halt
		pcall(Import.Notify, Text .. ". Turn the farm back on when you are ready.", "Yen")
	end

	--/ A rubber band. With Resume on, the farm waits out the pull back and carries on by itself instead of stopping for good
	local function Snap()
		if not State.Resume then
			return Halt("Server snapped you back, stopped")
		end

		Engine.PausedUntil = os.clock() + State.ResumeDelay
		Engine.Target = nil
		LastPos = nil

		Body.Release()
		Engine.Say("Rubber band, waiting it out")
	end

	local function Step()
		local Common = Shared()

		if Shown ~= Engine.Message then
			Shown = Engine.Message

			Status:SetText(Shown)
		end

		if Engine.Mode == "Off" or Common.Busy then
			return
		end

		if Common.Owner ~= Engine then
			return
		end

		local Model, Root, Humanoid = Farm.Character()

		if not Model then
			Body.Release()
			Engine.Target = nil

			return Engine.Say("Waiting for your character")
		end

		if Humanoid.Health / math.max(Humanoid.MaxHealth, 1) * 100 <= State.Retreat then
			Body.Release()
			Engine.Target = nil

			return Engine.Say("Health low, paused")
		end

		--/ Waiting out a rubber band, hold still until the pause is over
		if Engine.PausedUntil > os.clock() then
			Body.Release()

			return
		end

		if Engine.Mode == "Goto" then
			Body.Hold(Model, Humanoid)

			local Left, Resting, Snapped = Body.Travel(Root, Engine.Goal, State.Speed)

			if Snapped then
				Snap()
			elseif Left < 4 then
				Engine.Arrived = true
			elseif not Resting and Blocked(Root, Left) then
				Halt()
			end

			return
		end

		if not Alive(Engine.Target) then
			Engine.Target = Nearest(Root)
		end

		local Part = Engine.Target and EnemyRoot(Engine.Target)

		if not Part then
			Body.Release()

			return Engine.Say(Farm.Regions() and "No enemies found" or "Not in a world with enemies")
		end

		Body.Hold(Model, Humanoid)

		local Goal

		if State.Position == "Under" then
			Goal = Part.Position - Vector3.new(0, State.Height, 0)
		else
			Goal = Part.Position - Part.CFrame.LookVector * State.Back + Vector3.new(0, State.Height, 0)
		end

		local Distance, Resting, Snapped = Body.Travel(Root, Goal, State.Speed, Part.Position)

		if Snapped then
			return Snap()
		end

		if not Resting and Blocked(Root, Distance) then
			return Halt()
		end

		Engine.Say("Target: " .. Engine.Target.Name)

		if not Resting and Distance < 15 then
			Attack(Model)
		end
	end

	Feature.Connect(RunService.Heartbeat, Step)

	Feature.OnUnload(function()
		Body.Release()

		if Shared().Owner == Engine then
			Shared().Owner = nil
		end
	end)

	local function Claim()
		local Common = Shared()

		if Common.Owner ~= Engine then
			if Common.Owner then
				Common.Owner.Mode = "Off"
				Common.Owner.Say("Stopped, another farm started")
			end

			Common.Owner = Engine
		end
	end

	--/ Fights enemies that pass the filter, nil means any enemy
	function Engine.Resume()
		Engine.Halted = false
		LastPos = nil
	end

	function Engine.Run(Filter)
		if Engine.Halted then
			return
		end

		Claim()

		if Engine.Mode ~= "Fight" or Engine.Filter ~= Filter then
			Engine.Target = nil
			CachedAt = 0
		end

		Engine.Filter = Filter
		Engine.Mode = "Fight"
	end

	function Engine.Stop()
		Engine.Mode = "Off"
		Engine.Target = nil
		Engine.Filter = nil

		Body.Release()
		Engine.Say("Idle")

		if Shared().Owner == Engine then
			Shared().Owner = nil
		end
	end

	--/ Flies to a point and waits there. Call it from a loop or thread, it yields
	function Engine.Travel(Position, Timeout)
		if Engine.Halted then
			return false
		end

		Claim()

		Engine.Goal = Position
		Engine.Arrived = false
		Engine.Mode = "Goto"
		Engine.Say("Travelling")

		local Started = os.clock()
		local Limit = Timeout or 60

		while Engine.Mode == "Goto" and not Engine.Arrived and os.clock() - Started < Limit do
			task.wait(0.1)
		end

		return Engine.Arrived
	end

	--/ Goes to the quest giver, opens the chat the way a player does so the server knows who you are talking to, takes the quest
	--/ Returns true once the game lists it as active
	function Engine.Accept(Name)
		if Engine.Halted then
			return false
		end

		local Info = Farm.Info(Name)
		local Prompt, Part = Farm.NpcPrompt(Info and Info.OfferNpc)

		if Part then
			Engine.Travel(Part.Position + Vector3.new(0, 3, 0), 45)
		elseif Info and typeof(Info.Position) == "Vector3" then
			Engine.Travel(Info.Position + Vector3.new(0, 3, 0), 45)
		end

		Engine.Mode = "Off"
		Body.Release()

		if Prompt then
			pcall(fireproximityprompt, Prompt)
			task.wait(1.2)
		end

		Farm.Send("AddQuest", Name)

		local Taken = false

		for _ = 1, 20 do
			task.wait(0.2)

			if Farm.Active() == Name then
				Taken = true

				break
			end
		end

		Farm.CloseDialogue()

		return Taken
	end

	return Engine
end

return Farm
