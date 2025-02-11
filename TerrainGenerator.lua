local Players = game:GetService("Players") -- player service
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- resource replication service

local folder = ReplicatedStorage:WaitForChild("Resource") -- folder with resources
local config = { -- configuration 
	Tree = {
		Shans = 0.015, -- spawn chance (from 0 to 1)
		SizeMin = 0.3, -- minimum size
		SizeMax = 3.0, -- maximum size
		RessMin = 100, -- minimum resources
		RessMax = 300, -- maximum resources
	},
	Rock = {
		Shans = 0.01, -- spawn chance (from 0 to 1)
		SizeMin = 1, -- minimum size
		SizeMax = 3, -- maximum size
		RessMin = 50, -- minimum resources
		RessMax = 400, -- maximum resources
	},
	Flowers = {
		Shans = 0.1, -- spawn chance (from 0 to 1)
		SizeMin = 0.5, -- minimum size
		SizeMax = 1, -- maximum size
		RessMin = 10, -- minimum resources
		RessMax = 20, -- maximum resources
	},
}

math.randomseed( tick() ) -- set initial seed
local resourceFolder = workspace:WaitForChild("Resource") -- resource placement location

local SIZE = 20 -- initial size
-- maximum height
local HEIGHT = 50 
-- vertical offset
local BASE = -HEIGHT 
-- initial seed
local SEED = math.random() 
-- how many points per unit (x/z)
local SCALE = 15 
-- grid accuracy (default 4x4x4)
local GRID = 4 

local timer = workspace:GetServerTimeNow()
-- coordinates of the generated world
local chunk = {} 
-- player position
local position = {}

-- fill the array of available resources
-- indexed array of available resources
local resource = {}
-- take only described resources
for name, res in pairs(config) do 
	local find = folder:FindFirstChild(name)
	-- found in resources
	if find:IsA("Folder") then 
		local tmp = find:GetChildren()
		-- resources are present
		if #tmp > 0 then 
			for a, b in pairs(tmp) do
				-- check if it's a resource
				if b:IsA("Model") then
					-- has an attachment point
					if b.PrimaryPart ~= nil then 
						-- store a new resource element
						local element = {} 
						-- copy data into the element
						element = table.clone(res) 
						-- add name
						element.name = name 
						-- add reference to the model
						element.model = b 

						-- finally add the element to the list of available resources
						table.insert(resource, element)
					else
						warn("No PrimaryPart:", b)
					end
				else
					warn("Not a model:", b)
				end			
			end
		end
	end
end
print(resource)

-- create a resource on the map at given coordinates
function CreateResource(x, y, z, material)
	-- get a value from 0 to 1
	local shans = math.random() 
	-- random resource
	local num = math.random(1, #resource) 
	-- chance for placement triggered
	if shans <= resource[num].Shans then 
		-- clone the model
		local object = resource[num].model:Clone() 
		object:PivotTo(CFrame.new(x * GRID, y + GRID*2, z * GRID))
		object.Name = resource[num].name

		-- change size
		local sizer = math.random(resource[num].SizeMin * 100, resource[num].SizeMax * 100)
		-- prevent too small sizes
		if sizer < 1 then 
			sizer = 1
		end
		object:ScaleTo(sizer/100)

		-- rotate on Y
		local rotation = CFrame.Angles(0, math.rad(math.random(360)), 0)
		object:PivotTo(object:GetPivot() * rotation)

		-- check for intersection with other objects
		local part = Instance.new("Part")
		-- get position and size
		local orient, size = object:GetBoundingBox() 
		part.Size = size
		part.CFrame = orient
		-- returns nil or an array of intersections 
		local check = workspace:GetPartsInPart(part) 
		if check[1] ~= nil then
			-- remove as it failed the check
			object:Destroy()
		else
			-- place in the world
			object.Parent = resourceFolder
		end
		part:Destroy()
	end
end

function CreateChunk(x, z)
	-- get coordinate
	local y = math.noise(SEED, x/SCALE, z/SCALE) 
	local material = Enum.Material.Ground
	if y > 0.5 then
		material = Enum.Material.Glacier
	elseif y > 0.4 then
		material = Enum.Material.Snow
	elseif y > 0.2 then
		material = Enum.Material.LeafyGrass
	elseif y > 0 then
		material = Enum.Material.Grass
	elseif y < -0.2 then
		material = Enum.Material.Mud
	end
	-- get coordinate
	y = BASE + HEIGHT * y
	-- create terrain
	workspace.Terrain:FillBlock(
		-- placement location
		CFrame.new(x*GRID, y, z*GRID),
		-- size
		Vector3.new(GRID,GRID*2,GRID), 
		-- material type
		material
	)
	-- prevent freezing (60 FPS)
	if workspace:GetServerTimeNow() - timer > 5/60 then
		timer = workspace:GetServerTimeNow()
		task.wait()
	end

	-- generate resources
	CreateResource(x, y, z, material)
end

function CheckChunk(newPos)
	-- take only whole coordinates
	local posX = math.floor( newPos.X /4 )
	local posZ = math.floor( newPos.Z /4 )
	for x = posX - SIZE, posX + SIZE do
		for z = posZ - SIZE, posZ + SIZE do		
			if chunk[x] == nil then
				chunk[x] = {}
			end
			if chunk[x][z] == nil then
				chunk[x][z] = true
				CreateChunk(x, z)
			end
		end
	end 
end

-- infinite world rendering loop
while true do 
	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character.Parent then
			local pos = character:GetPivot()
			-- only for new positions
			if position[character] ~= pos then 
				position[character] = pos
				CheckChunk( pos.Position )
			end
		end
	end
	task.wait(1)
end