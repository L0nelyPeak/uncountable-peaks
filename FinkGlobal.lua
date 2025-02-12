--[[ Global control script for Finks
2025-02-03 L0nelyPeak

workspace/NPC_Fink	- mobs in the world will be here
Folders WP_1 - WP_5 correspond to the WP navigation for each Fink, 1 in the basement and 2 on each floor
Determining the Fink's patrol zone based on the nearest WP

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
--local RunService = game:GetService("RunService")
--local HttpService = game:GetService("HttpService")
local remoteEvents = ReplicatedStorage.Remotes
local scrimmerEvent = remoteEvents.Scrimmer
-- scrimmerEvent:FireClient(player, 0, 1.5, 0.01, "Fink")
-- player, transparency, duration, fade time, name of the scrim image (usually matches the monster's name)
-- when scrim one, set transparency to 1; when scrim two, set transparency to 0

local config = require(ReplicatedStorage:WaitForChild("ConfigureNPC"))

-- global variables
local interact = workspace:WaitForChild("InteractInstances")
local shelfes = interact:WaitForChild("Shelfes"):GetChildren()		-- set of shelves
local tables = interact:WaitForChild("TableZones"):GetChildren()	-- set of tables

local npcFolder = workspace:WaitForChild("NPC_Fink")	-- where NPCs will be located
local waypoints = npcFolder:WaitForChild("WayPoints")	-- where the WPs are located
local allWP = waypoints:GetDescendants()				-- get ALL WPs
warn(allWP)

local path = PathfindingService:CreatePath({	-- preparation for path calculation
	AgentRadius = 3,			-- agent radius (character)
	AgentHeight =  5,			-- agent height
	AgentCanJump = false,		-- can the agent jump
	--AgentJumpHeight = 10,		-- jump height
	WaypointSpacing = 20,		-- distance between waypoints
	Costs = {
		DangerZone = math.huge,
	},
	-- return an approximate path result if the destination is unreachable
	PathSettings = {
		SupportPartialPath = true
	}
})

-- initialization with spawning
local logic = {}	-- table containing information about each NPC
for i = 1, 5 do
	logic[i] = {}
	logic[i].Title = "Fink_" .. tostring(i)
	logic[i].WP = npcFolder:WaitForChild("WayPoints"):WaitForChild( "WP_" .. tostring(i) ):GetChildren()		-- gathering its WPs
	logic[i].Model = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("NPC"):WaitForChild("Fink3"):Clone()	-- clone the base model
	local rnd = math.random(1, #logic[i].WP)-- random selection of WP
	local pos = logic[i].WP[rnd].CFrame		-- position of the given WP
	logic[i].Model:PivotTo(pos)				-- placement in space
	logic[i].Model.Parent = npcFolder		-- placement in the world
	logic[i].Model.Name = logic[i].Title	-- NPC name
	logic[i].Humanoid = logic[i].Model:FindFirstChild("Humanoid")
	logic[i].HRP = logic[i].Model:FindFirstChild("HumanoidRootPart")
	logic[i].HRP:SetNetworkOwner(nil)		-- physics controlled by the server
	logic[i].State = "патруль"				-- initial status
	logic[i].Bite = {}						-- record of bites during patrol
	logic[i].Target = nil					-- current target - player
	logic[i].LastPoint = nil				-- where it came from
	logic[i].NextPoint = nil				-- where it is going - part
	logic[i].Current = logic[i].HRP.Position-- current position
	logic[i].Timer = {}						-- time until the next iteration (for example in animations)
	logic[i].BrokenTime = 0					-- time of the last fixed position
	logic[i].BrokenPos = CFrame.new(Vector3.zero)	-- position at which it was fixed
	logic[i].Hands = {}						-- which player(s) have been waved at

	logic[i].Animator = logic[i].Humanoid:WaitForChild('Animator')	-- load animator
	logic[i].LastTrack = nil				-- last played track
	logic[i].LastSound = nil				-- last sound effect

	print("Кусака", logic[i].Title, "создан.")
end
print(logic)

-- list of animations
-- sounds with the same name should be placed in the mob's HRP
local anim = {
	idle = script.Idle,				-- waiting
	walk = script.Walk,				-- walking
	look = script.Look,				-- looking around
	shake = script.Shake,			-- shaking
	jump = script.Catchy,			-- jump
	wave = script.Wave,				-- wave hand
	-- in aggression mode
	open = script.Open,				-- open mouth - show teeth
	run = script.AggrRun,			-- run
	scream = script.Scream,			-- frenzy
	attack = script.AggrAttack,		-- attack	
}

-- start animation and accompany it with sound
-- proper stopping of track and sound
function StopLast(npc)	-- npc = logic[i]
	-- if timer is nil then
	--	timer = 0
	-- end

	-- and here's the ambush - while paused, all mobs are stopped
	-- task.wait(timer * 0.9)
	if npc.LastTrack ~= nil then
		npc.LastTrack:Stop()
	end
	if npc.LastSound ~= nil then
		npc.LastSound:Stop()
	end
end

-- launch animations and sound with tracking
function Animator(npc, animation, timer)	-- npc = logic[i]

	local array = npc.Animator:GetPlayingAnimationTracks()	-- currently playing animations 
	for i = 1, #array do
		if array[i].Name == animation.Name then	-- the requested animation is already playing
			return
		end
	end

	local animationTrack = npc.Animator:LoadAnimation(animation)

	--print(npc.Model, "current:", array )
	--print(npc.Model, "to play:", animation.Name)

	if timer == nil then				-- parameter not specified
		animationTrack.Looped = true	-- infinite playback
	else
		animationTrack.Looped = false
	end
	animationTrack:Play()

	-- if there is a sound with the same name - play it
	-- sounds are located in the mob's HRP
	local name = animation.Name
	local sound = npc.HRP:FindFirstChild(name)
	if sound then
		if timer == nil then
			sound.Looped = true
		else
			sound.Looped = false
		end
		sound:Play()
	end

	-- in global variables
	npc.LastTrack = animationTrack
	npc.LastSound = sound
	return
end

-- calculate the path distance for the given WPs
local function DistWP(wp)
	local rast = 0
	for i = 1, #wp - 1 do
		local delta = (wp[i].Position - wp[i+1].Position).Magnitude
		rast = rast + delta
	end
	return rast
end

-- find the nearest WP for this NPC
local function FindWP(npc:number)
	local target = nil	-- return the part to move towards

	local wp = logic[npc].WP
	local hrp = logic[npc].HRP

	local dist = math.huge	-- minimum distance	
	for _, part in pairs(logic[npc].WP) do
		if (hrp.Position - part.Position).Magnitude > dist then
			continue	-- skip if the direct distance is greater than the current minimum
		end
		local success, errorMessage = pcall(function()
			path:ComputeAsync(hrp.Position, part.Position)
		end)
		if success then	-- executed without error
			local wp = path:GetWaypoints()
			if #wp > 0 then
				local tmp = DistWP(wp)	-- calculated distance
				if tmp < dist then		-- smaller than the stored value
					dist = tmp			-- new minimum
					target = part		-- new WP
				end
			else
				warn("Кусака: нет WP - отключен параметр в Workspace?", part)
			end
		else
			warn("Кусака: пусть не рассчитан",part, hrp.Parent, errorMessage)
		end
	end

	return target
end

-- find cover on the map
local function FindCover(playerHRP:BasePart)
	local res = nil	-- return value

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = playerHRP.Parent:GetDescendants()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bounds = workspace:GetPartsInPart(playerHRP, params)
	-- debug 
	-- print("Части укрытия:", bounds )
	for i = 1, #bounds do
		print(i, bounds[i].Parent)
	end
	if #bounds > 0 then	-- to avoid errors with cover locations
		local target = bounds[1].Parent:FindFirstChild("SCREAM")
		if target then
			res = bounds[1].Parent	-- return the cover model
		else
			warn("Кусака: для укрытия", bounds[1].Parent, "не найден SCREAM")
		end
	else
		warn("Кусака: не найдены части укрытия!")
	end

	return res
end

-- set the movement direction
local function MoveToPart(npc, target)
	local res = nil

	local success, errorMessage = pcall(function()
		path:ComputeAsync(npc.HRP.Position, target.Position)
	end)
	if success then	-- executed without error
		local wp = path:GetWaypoints()
		if #wp > 0 then
			npc.Humanoid:MoveTo(wp[2].Position)	-- index 1 is our current position, index 2 is the next waypoint
			res = true
		else
			warn("Кусака: нет WP - отключен параметр в Workspace?", target)
		end
	else
		warn("Кусака: пусть не рассчитан",npc.Model, target, errorMessage)
	end

	return res	-- return true only in case of success
end

-- turn to face the player
local function RotateToPlayer(npc, target)
	--npc.HRP.CFrame = CFrame.lookAt(npc.HRP.Position + Vector3.new(0, 0.3, 0), target.Position)
	local cf = npc.HRP:GetPivot()	-- CFrame = Position * Orientation
	cf = CFrame.lookAt(cf.Position, target.Position)
	local cf1 = CFrame.new(cf.Position) * CFrame.Angles(0,cf.Rotation.Y,0)
	npc.HRP:PivotTo(cf1)
end


-- cache cover assignments to NPC routes
-- (reverse approach) change to iterate through all WP and find nearest cover
-- i.e. iterate through ALL WP ONCE and find nearest storage
-- Though, probably won't make difference
local route = {}    -- array mapping covers to routes
for _, model in pairs(shelfes) do    -- iterate through shelves
	local target = model:FindFirstChild("SCREAM")
	if target then
		local dist = math.huge    -- minimum distance
		local toWP = nil        -- target WP 
		for i, part in pairs(allWP) do
			if part:IsA("BasePart") then
				if (target.Position - part.Position).Magnitude > dist then
					continue    -- no need to calculate if straight-line distance is longer
				end
				local success, errorMessage = pcall(function()
					path:ComputeAsync(target.Position, part.Position)
				end)
				if success then    -- executed without error
					local wp = path:GetWaypoints()
					if #wp > 0 then
						local tmp = DistWP(wp)
						if tmp < dist then
							dist = tmp    -- new minimum
							toWP = part    -- new WP
						end
					else
						warn("Кусака: нет WP - отключен параметр в Workspace?", part)
					end
				else
					warn("Кусака: пусть не рассчитан",part.Parent, model, errorMessage)
				end
			end
		end
		if toWP then
			local str = toWP.Parent.Name
			local num = tonumber( string.sub(str, string.len(str), string.len(str)) )
			print(model, "принадлежит", num)
			route[model] = num
		else
			warn("Кусака: укрытие не доступно:", model)
		end
	else
		warn("Кусака: ошибка модели шкафа:", model)
	end
end
for _, model in pairs(tables) do    -- iterate through tables
	local target = model:FindFirstChild("SCREAM")
	if target then
		local dist = math.huge    -- minimum distance
		local toWP = nil        -- target WP 
		for i, part in pairs(allWP) do
			if part:IsA("BasePart") then
				if (target.Position - part.Position).Magnitude > dist then
					continue    -- no need to calculate if straight-line distance is longer
				end
				local success, errorMessage = pcall(function()
					path:ComputeAsync(target.Position, part.Position)
				end)
				if success then    -- executed without error
					local wp = path:GetWaypoints()
					if #wp > 0 then
						local tmp = DistWP(wp)
						if tmp < dist then
							dist = tmp    -- new minimum
							toWP = part    -- new WP
						end
					else
						warn("Кусака: нет WP - отключен параметр в Workspace?", part)
					end
				else
					warn("Кусака: пусть не рассчитан",part.Parent, model, errorMessage)
				end
			end
		end
		if toWP then
			local str = toWP.Parent.Name
			local num = tonumber( string.sub(str, string.len(str), string.len(str)) )
			print(model, "принадлежит", num)
			route[model] = num
		else
			warn("Кусака: укрытие не доступно:", model)
		end

	else
		warn("Кусака: ошибка модели шкафа:", model)
	end
end

-- infinity loop
while task.wait(config.FinkStep) do
	-- iterate over players with hidden status check
	for _, player in pairs(Players:GetChildren()) do
		local character = player.Character
		if character and character.Parent then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				if humanoid.Health > 0 then	-- alive
					-- check if hidden
					local hidden = humanoid:GetAttribute('isHiding')
					if hidden == true then
						-- check how long they have been hidden
						local timer = humanoid:GetAttribute("Fink")
						if timer == nil or timer == 0 then
							humanoid:SetAttribute( "Fink", tick() )	-- time when hidden
						else
							-- if hidden for too long, then find an NPC for them
							local delta = tick() - timer
							if delta > config.FinkHiddenTimer then	-- should already be attacked


								-- also check that they are not already being targeted!
								-- there is some lag here
								-- probably due to constant route calculations


								-- print("долго спрятавшийся", player)
								local npc = humanoid:GetAttribute("NPC")
								if npc == nil or npc == "" then		-- haven't run to them yet
									-- we will search for a suitable NPC
									local HRP = character:FindFirstChild("HumanoidRootPart")
									local model = FindCover(HRP)	-- search for cover model
									if model then
										local toWP = route[model]

										local target = model:FindFirstChild("SCREAM")
										--[[ -- this is the cause of the slowdown - solved using route[]
										local dist = math.huge	-- minimum distance
										local toWP = nil		-- which WP 
										for i, part in pairs(allWP) do
											if part:IsA("BasePart") then
												local success, errorMessage = pcall(function()
													path:ComputeAsync(target.Position, part.Position)
												end)
												if success then	-- executed without error
													local wp = path:GetWaypoints()
													if #wp > 0 then
														local tmp = DistWP(wp)
														if tmp < dist then
															dist = tmp	-- new minimum
															toWP = part	-- new WP
														end
													else
														warn("Кусака: нет WP - отключен параметр в Workspace?", part)
													end
												else
													warn("Кусака: пусть не рассчитан",part.Parent, HRP.Parent, errorMessage)
												end
											end
										end
										]]
										if toWP ~= nil then	-- a suitable WP exists
											--local str = toWP.Parent.Name
											--local num = tonumber( string.sub(str, string.len(str), string.len(str)) )
											local num = route[model]
											-- set NPC status to "enraged" if this NPC is patrolling
											if logic[num].State == "патруль" then
												logic[num].State = "бешенный" 
												logic[num].Target = player
												logic[num].NextPoint = target
												humanoid:SetAttribute("NPC", logic[num].Title)
												warn("Кусака: взбесился", logic[num].Model, player)
											end
										else
											warn("Кусака: не принадлежит маршрутам", model)
										end
									else
										warn("Кусака: Не определена модель укрытия!", player)
									end
								else
									warn("Кусака: за", player, "уже охота!")
								end
							end
						end
					else
						humanoid:SetAttribute("Fink",0)
					end
				end
			end
		end
	end

	-- iterate over NPCs and execute actions
	for i = 1, #logic do	-- iterate over all NPCs
		local npc = logic[i]
		-- patrol
		if npc.State == "патруль" then
			npc.Humanoid.WalkSpeed = config.FinkSpeedWalk
			Animator(npc, anim.walk)

			-- start/continue route
			if npc.NextPoint == nil then	-- return to route
				-- search for the nearest WP of its route
				local target = FindWP(i)
				if target then	-- there is somewhere to go
					npc.LastPoint = npc.NextPoint
					npc.NextPoint = target
					-- npc.Humanoid:MoveTo(target.Position)-- if it were like this, it would be great
					-- move to the given WP
					MoveToPart(npc, target)	-- setting off on the path
				else
					warn("Кусака: путь к WPs для", npc.Model, "не найден")
				end
			else	-- continue patrolling along the route
				local dist = (npc.HRP.Position - npc.NextPoint.Position).Magnitude
				if dist < config.FinkOffset then
					-- change destination point
					local objects = npc.NextPoint:GetChildren()
					if #objects == 0 then
						warn("Кусака: тупик - нет точек выхода у", npc.NextPoint)
						-- return to where we came from so as not to stop
						npc.NextPoint = npc.LastPoint
					else
						if #objects == 1 then	-- at the entrance to a room
							npc.State = "оглядеться"
							npc.LastPoint = npc.NextPoint
							npc.NextPoint = objects[1].Value
						else	-- choose direction
							local array = {}	-- rebuild the array
							for _, b in pairs(objects) do
								if b.Value ~= npc.LastPoint then
									table.insert(array, b)
								end
							end
							npc.LastPoint = npc.NextPoint
							local rnd = math.random(1, #array)
							npc.NextPoint = array[rnd].Value
							MoveToPart(npc, npc.NextPoint)	-- continue on the path
						end
					end

				else
					MoveToPart(npc, npc.NextPoint)	-- continue on the path
				end
			end

			-- control check 
			-- disable for all players that they are my target while I am on patrol
			for _, player in pairs(Players:GetChildren()) do
				local character = player.Character
				if character and character.Parent then
					local humanoid = character:FindFirstChild("Humanoid")
					if humanoid then
						if humanoid:GetAttribute("NPC") == npc.Title then
							humanoid:SetAttribute("NPC", "")
						end
					end
				end

				-- wave hand
				local playerHRP = character:FindFirstChild("HumanoidRootPart")
				local dist = (npc.HRP.Position - playerHRP.Position).Magnitude
				if dist <= config.FinkHandDist then	-- within waving distance
					local line = playerHRP.Position - npc.HRP.Position
					-- dot product of the direction vector and the look vector
					local fov = line.Unit:Dot(npc.HRP.CFrame.LookVector)

					if fov > config.FinkHandAggles then
						local playerHumanoid = character:FindFirstChild("Humanoid")
						if playerHumanoid then
							if playerHumanoid.Health > 0 then	-- player is alive
								local rnd = math.random()
								if rnd < config.FinkHandShans then
									local flag = false
									if npc.Hands[player] == nil then
										flag = true
										--warn("Ещё не встречались")
									else
										if npc.Hands[player] < tick() then
											flag = true
											--warn(player, npc.Hands[player], tick() )
											--warn("интервал прошёл")
										end
									end
									if flag == true then
										npc.Hands[player] = tick() + config.FinkHandInterval
										npc.State = "помахать"
									else
										--warn("Не давно махали")
									end
								end
							end
						end
					else
						-- warn("вне поля зрения -", fov)
					end
				else
					-- warn("Далеко")
				end

			end

			-- check for collisions with players during patrol
			local body = npc.Model:FindFirstChild("RedDoll_Body.001")
			if body then
				-- local array = workspace:GetPartsInPart(body)	-- or use collision with the model's volume
				local orientation, size = npc.Model:GetBoundingBox()
				local array = workspace:GetPartBoundsInBox(orientation, size)
				for _, part in array do
					if part:IsA("BasePart") then
						-- there is a piece of a player
						if Players:GetPlayerFromCharacter(part.Parent) ~= nil then
							npc.Target = Players:GetPlayerFromCharacter(part.Parent)
							npc.State = "кусаю"
							break	-- break on first collision
						end
					end
				end
			else
				warn("Кусака: RedDoll_Body не найден в NPC", npc.Model)
			end
		end

		-- look around and retreat
		if npc.State == "оглядеться" then
			-- several states / actions / animations
			local state = npc.State
			local stage = 0	-- current stage

			if npc.Timer[state] == nil then
				npc.Timer[state] = {}
				stage = 1
			else
				stage = npc.Timer[state].Stage
			end

			if stage == 1  then	-- first stage
				-- look around
				StopLast(npc)			-- stop immediately
				Animator(npc, anim.look, true)	-- one-time animation
				local timer = npc.LastTrack.Length
				npc.Timer[state].Stage = 2						-- next stage
				npc.Timer[state].Timer = tick() + timer * 0.9	-- set timer for continuation

			elseif stage == 2 and npc.Timer[state].Timer < tick() then
				StopLast(npc)

				-- continue patrolling
				-- MoveToPart(npc, npc.NextPoint)	-- set off on the path

				npc.Timer[state] = nil	-- stage complete
				npc.State = "патруль"	-- change state
			end
		end

		if npc.State == "помахать" then
			local state = npc.State
			local stage = 0	-- current stage

			if npc.Timer[state] == nil then
				npc.Timer[state] = {}
				stage = 1
			else
				stage = npc.Timer[state].Stage
			end

			if stage == 1  then	-- first stage
				warn("машем")
				-- stop
				npc.Humanoid:MoveTo(npc.HRP.Position)
				StopLast(npc)
				Animator(npc, anim.wave, true)	-- non-looping
				local timer = npc.LastTrack.Length
				npc.Timer[state].Stage = 2						-- next stage
				npc.Timer[state].Timer = tick() + timer * 0.9	-- set timer for continuation

			elseif stage == 2 and npc.Timer[state].Timer < tick() then
				StopLast(npc)
				npc.Timer[state] = nil	-- stage complete
				npc.State = "патруль"	-- change state
			end
		end

		-- enraged
		if npc.State == "бешенный" then
			npc.Humanoid.WalkSpeed = config.FinkSpeedRun

			local state = npc.State
			local stage = 0	-- current stage

			if npc.Timer[state] == nil then
				npc.Timer[state] = {}
				stage = 1
			else
				stage = npc.Timer[state].Stage
			end

			-- print("Target =", npc.Target)
			local character = npc.Target.Character
			local hrp = nil
			local humanoid = nil
			local hidden = nil
			if character and character.Parent then
				hrp = character:FindFirstChild("HumanoidRootPart")
				humanoid = character:FindFirstChild("Humanoid")
				if humanoid then
					hidden = humanoid:GetAttribute("isHiding")
				end
			end

			-- print(">>", stage, state, npc.Timer[state])
			if hidden ~= true then
				stage = 4	-- final stage
			end

			if stage == 1  then	-- first stage
				-- become enraged
				-- run to the target
				if hrp then
					local cover = FindCover(hrp)	-- where hiding
					if cover then
						npc.Timer[state].Cover = cover
						local scream = cover:FindFirstChild("SCREAM")
						-- if not reached
						if (scream.Position - npc.HRP.Position).Magnitude > config.FinkOffset then
							npc.NextPoint = scream
							Animator(npc, anim.run)
							MoveToPart(npc, scream)
							npc.Timer[state].Stage = 1
						else
							print("Добежал поорать")
							-- scream
							StopLast(npc)
							-- turn to the player
							RotateToPlayer(npc, hrp)
							Animator(npc, anim.scream)
							local timer = npc.LastTrack.Length
							npc.Timer[state].Stage = 2						-- next stage
							npc.Timer[state].Timer = tick() + timer * 0.9	-- set timer for continuation
						end
					end
				end

			elseif stage == 2 and npc.Timer[state].Timer < tick() then
				-- wait for the end of the animation
				StopLast(npc)
				-- run up to IN
				local partIn = npc.Timer[state].Cover:FindFirstChild("IN")
				if (partIn.Position - npc.HRP.Position).Magnitude > config.FinkOffset then
					npc.NextPoint = partIn
					Animator(npc, anim.run)
					MoveToPart(npc, partIn)
				else
					print("Добежал укусить")
					StopLast(npc)
					-- stop
					humanoid:MoveTo(hrp.Position)
					RotateToPlayer(npc, hrp)
					-- bite animation
					Animator(npc, anim.attack)
					local timer = npc.LastTrack.Length
					npc.Timer[state].Stage = 3						-- next stage
					npc.Timer[state].Timer = tick() + timer * 0.5	-- set timer for continuation
				end

			elseif stage == 3 and npc.Timer[state].Timer < tick() then
				-- bite
				humanoid.Health = humanoid.Health - config.FinkAttackDamage

				-- throw the player out of cover
				character:PivotTo(npc.Timer[state].Cover:FindFirstChild("OUT"):GetPivot())
				-- hrp.Position = hrp.Position + hrp.CFrame.LookVector * 1	-- shift
				npc.Timer[state].Stage = 4

			elseif stage == 4 then
				-- return to patrol
				if humanoid then
					humanoid:SetAttribute("NPC", "")	-- reset hunting
					humanoid:SetAttribute("Fink", 0)	-- reset post-bite time
				end
				StopLast(npc)			-- stop animations
				npc.Timer[state] = nil	-- stage complete
				npc.NextPoint = nil		-- reset to calculate return to route
				npc.State = "патруль"	-- change state
			end
		end

		-- bite upon collision with a player during patrol
		if npc.State == "кусаю" then
			local state = npc.State
			local stage = 0	-- current stage

			if npc.Timer[state] == nil then
				npc.Timer[state] = {}
				stage = 1
			else
				stage = npc.Timer[state].Stage
			end

			if stage == 1 then
				-- determine who was collided with
				local player = npc.Target	-- this is an example

				-- check that it hasn't bitten recently
				local bite = npc.Bite[player]
				if bite == nil then
					bite = 0
				end
				if bite < tick() then	-- time for a bite has come
					-- bite
					local character = player.Character
					if character and character.Parent then
						local humanoid = character:FindFirstChild("Humanoid")
						if humanoid then
							if humanoid.Health > 0 then
								-- stop
								npc.Humanoid:MoveTo(npc.HRP.Position)

								-- bite animation
								StopLast(npc)			-- stop immediately
								-- turn towards the player
								RotateToPlayer(npc, character.HumanoidRootPart)
								Animator(npc, anim.attack, true)	-- one-time animation
								local timer = npc.LastTrack.Length
								npc.Timer[state].Stage = 2						-- next stage
								npc.Timer[state].Timer = tick() + timer * 0.5	-- set timer for continuation
								humanoid.Health = humanoid.Health - config.FinkAttackDamage	-- (apply damage; consider moving this to state = 2)
							end
						end
					end
					-- set a new interval
					npc.Bite[player] = tick() + config.FinkBiteInterval
				else	-- bitten recently
					npc.Timer[state] = nil
					npc.State = "патруль"
				end
			elseif stage == 2 and npc.Timer[state].Timer < tick() then
				StopLast(npc)	-- stop after timer
				npc.Timer[state] = nil	-- stage complete
				-- continue patrolling
				npc.State = "патруль"
			end
		end

		-- check for getting stuck -----------------------------------
		-- + check for Run & Walk animations, i.e., we are moving
		local flag = false
		local array = npc.Animator:GetPlayingAnimationTracks()	-- currently playing animations
		for i = 1, #array do
			if array[i].Name == "Walk" or array[i].Name == "AggrRun" then	-- if the requested animation is playing
				flag = true
			end
		end
		if flag == true then
			-- time's up
			if npc.BrokenTime < tick() then	-- this means it's stuck
				-- distance is less than the specified threshold
				if (npc.BrokenPos.Position - npc.HRP.Position).Magnitude < config.FinkBrokenDist then
					warn(npc.Model, "- зафиксировано застревание!")
					print("Dist=", (npc.BrokenPos.Position - npc.HRP.Position).Magnitude )
					print("Dot :", npc.BrokenPos.LookVector:Dot(npc.HRP.CFrame.LookVector))
					-- find the nearest WP and teleport there
					local wp = FindWP(i)
					local cf = wp:GetPivot()
					npc.Model:PivotTo(cf)
				end
				npc.BrokenTime = tick() + config.FinkBroken
				npc.BrokenPos = npc.HRP.CFrame
			end
			-- distance covered
			if (npc.BrokenPos.Position - npc.HRP.Position).Magnitude >= config.FinkBrokenDist then 
				npc.BrokenTime = tick() + config.FinkBroken	-- if the required distance is covered,
				npc.BrokenPos = npc.HRP.CFrame			-- then update data
				-- print("прошли")
			end
			-- looking in a different direction (turned)
			if npc.BrokenPos.LookVector:Dot(npc.HRP.CFrame.LookVector) < 0.9 then
				npc.BrokenTime = tick() + config.FinkBroken
				npc.BrokenPos = npc.HRP.CFrame
				-- print("поворот")
			end
		else	-- if not in movement animations, then reset the counter
			npc.BrokenTime = tick() + config.FinkBroken	-- if the required distance is covered,
			npc.BrokenPos = npc.HRP.CFrame			-- then update data
		end

		--print(logic[i].Model, logic[i].State)	-- current status of each NPC
	end
end
