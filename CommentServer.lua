	--== Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local DataStoreService = game:GetService('DataStoreService')
local RunService = game:GetService('RunService')
local MessagingService = game:GetService('MessagingService')
	--== Configurations
local config = require( ReplicatedStorage:WaitForChild('Configure') )
local requestCooldown = config.PublishCooldDown 			-- cooldown beetwen requests
local liveRequestTime = config.LiveRequestShowTime  		-- duration of live request
local attemptsToGetKeys = config.MaxAttemptsToGetKeyList	-- max attempts to get key list
local attemptsToLoadData = config.MaxAttemptsToLoadDate		-- max attempts to load data
local attemptsToSaveData = config.MaxAttemptsToSaveData		-- max attempts to save data
local keyInterval = config.IntervalBeetwenAttemptsToGetKeyList		-- time beetwen unsuccessful attempts to get keys
local loadDataInterval = config.IntervalBeetwenAttemptsToLoadData 	-- time beetwen unsuccessful attempts to load data
local saveDataInterval = config.IntervalBeetwenAttemptsToSaveData	-- time beetwen unsuccessful attempts to save data
local minVotes = config.MinimumNumberOfVotes				-- if likes/disleks less than this number, request will be deleted
local minExistTime = config.MinimumRequestDuration			-- if request older than this number we delete it (in days)
	--== Remote Events
local remotesEvent = ReplicatedStorage:WaitForChild('RemoteEvents')	-- folder w remotes events
local sendRequestEvent = remotesEvent:FindFirstChild('SendRequest')	-- new request remote event
local voteEvent = remotesEvent:FindFirstChild('VoteEvent')			-- new vote remote event
	--== Folders
local assets = ReplicatedStorage:WaitForChild('Assets')		-- assets folder
local uiPresets = assets:WaitForChild('UIPresets')			-- ui templates folder
	--== Databases
local playerDatabase = DataStoreService:GetDataStore("PlayerData")		-- coolddown database
local topDatabase = DataStoreService:GetDataStore("TopRequest")			-- top requests database
	--== Cache
local sessionData = {}			-- players cooldowns cache
local topRequestsCache = {}		-- top requests cache
	--== Variables
local topRequestsKeys = nil		-- top requests keys
local requestTemplate = uiPresets:FindFirstChild('RequestTemplate')		-- request template
local TopBoard = workspace.GlobalTopBoard:FindFirstChildOfClass('SurfaceGui'):FindFirstChildOfClass('ScrollingFrame')	-- top requests board
local LiveBoard = workspace.GlobalLiveBoard:FindFirstChildOfClass('SurfaceGui'):FindFirstChildOfClass('ScrollingFrame')	-- live requests board

	--==Functions
-- request author's avatar from roblox web site
local function getAuthorAvatar(authorId: number)
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(authorId)
	end)
	
	if not success or not name then
		name = 'UnknownPlayer'
	end
	
	local success, image = pcall(function()
		return Players:GetUserThumbnailAsync(authorId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	
	if not success or not image then
		image = 'rbxasset://textures/ui/GuiImagePlaceholder.png'
	end
	
	return name, image
end
	
-- show top reqeuests
local function showRequest(data: {}, key, board)	
	local name, icon = getAuthorAvatar(data.id)
	local votes = data.likes - data.dislikes
	
	local requestGui = requestTemplate:Clone()
	requestGui.Name = key
	requestGui.Message.Message.Text.Text = data.message
	requestGui.Message.Date.Date.Text = data.time
	requestGui.Message.PlayerName.Username.Text = name
	requestGui.Message.PlayerIcon.Icon.Image = icon
	requestGui.Votes.Value.Text = votes
	requestGui.LayoutOrder = -votes
	
	requestGui.Parent = board
	
	if board == LiveBoard then
		task.delay(liveRequestTime, function()
			requestGui.Parent = TopBoard
		end)
	end
end
	
-- creates request
local function createRequest(player: Player, key, data: {})
	if sessionData[player.UserId].Cooldown < tick() then
		if data and key then
			local cooldoown = tick() + requestCooldown
			sessionData[player.UserId].Cooldown = cooldoown
			player:SetAttribute('Cooldown', cooldoown)
			
			showRequest(data, key, LiveBoard)

			topRequestsCache[key] = data
			saveData(key, data, topDatabase)

			local topic = "TopRequest"
			local message = {}
			message.data = data
			message.key = key
			message.server = game.JobId

			publish(topic, message)
		end
	end
end

-- loading player's data from db, and saving in cache
local function playerAdded(player: Player)
	local data, success = loadData(playerDatabase, player.UserId)
	
	if success == true then
		if data == nil then
			data = {				-- new player
				["Voted"] = {},		-- table of voted requests
				["Cooldown"] = 0	-- request creating cooldown
			}
		end
		
		player:SetAttribute('Cooldown', data.Cooldown)
		sessionData[player.UserId] = data
	elseif success == false then
		player:Kick("Unable to load your data. Try again later.")
	end
end

-- saving session data in db
local function playerLeaving(player: Player)
	if sessionData[player.UserId] then
		saveData(player.UserId, sessionData[player.UserId], playerDatabase)
	end
end

-- server shutdown, we need to save all data
local function serverShudown()
	if RunService:IsStudio() then
		return
	end
	
	for i, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			playerLeaving(player)
		end)
	end
end

-- getting all keys of database
local function getKeyList(db)
	local  success = nil
	local keypages = nil
	local attempt = 0
	
	repeat
		success, keypages = pcall(function()
			return db:ListKeysAsync()
		end)
		
		attempt = attempt + 1
		if not success then
			task.wait(keyInterval)
		end
	until success or attempt == attemptsToGetKeys
	
	return keypages
end

-- accepting new top request from different server
local function newTopRequest(message)
	if message then
		if message.Data then
			local server = message.Data.server
			local key = message.Data.key
			local data = message.Data.data
			if server and key and data then
				if server ~= game.JobId then
					showRequest(message.data, message.key, LiveBoard)
					topRequestsCache[message.key] = message.data
				end
			end
		end
	end
end

local function vote(player: Players, key, vote: boolean, board)
	if table.find(sessionData[player.UserId].Voted, key) then
		return
	end
	table.insert(sessionData[player.UserId].Voted, key)
	local action = nil
	local newValue = nil
	
	if vote == true then
		action = "likes"
	elseif vote == false then
		action = "dislikes"
	end
	
	local success, err = pcall(function()
		topDatabase:UpdateAsync(key, function(oldValue)
			oldValue[action] = oldValue[action] + 1
			newValue = oldValue
			return oldValue
		end)
	end)
	
	if success then
		topRequestsCache[key] = newValue
		
		local request = board:FindFirstChild(key)
		if request then
			local votes = newValue.likes - newValue.dislikes
			request.Votes.Value.Text = votes
			request.LayoutOrder = -votes
		else
			showRequest(newValue, key, board)
		end
	end
end

-- publish messages
function publish(topic, data)
	MessagingService:PublishAsync(topic, data)
end

-- saving data to database
function saveData(key, data, db)
	local success = nil
	local errorMsg = nil
	local attempt = 0
	
	repeat
		success, errorMsg = pcall(function()
			return db:SetAsync(key, data)
		end)
		
		attempt = attempt + 1
		if not success then
			task.wait(saveDataInterval)
		end
	until success or attempt == attemptsToSaveData
end

-- loading data
function loadData(db, key)
	local  success = nil
	local data = nil
	local attempt = 0

	repeat
		success, data = pcall(function()
			return db:GetAsync(key)
		end)

		attempt = attempt + 1
		if not success then
			task.wait(loadDataInterval)
		end
	until success or attempt == attemptsToLoadData

	-- saving loaded data in cache
	if success then
		if db == topDatabase then
			topRequestsCache[key] = data
		end
	end
	
	return data, success
end
	--== Connections
-- got new top request from another server
MessagingService:SubscribeAsync("TopRequest", newTopRequest)
-- new request event
sendRequestEvent.OnServerEvent:Connect(createRequest)
-- new vote event
voteEvent.OnServerEvent:Connect(vote)
-- player joined to the game
Players.PlayerAdded:Connect(playerAdded)
-- player leaving the game
Players.PlayerRemoving:Connect(playerLeaving)
-- server shuttin down [we have 30 sec]
game:BindToClose(serverShudown)

	--== Main
--load all top requests, and delete old, not popular requests
while task.wait() do
	if topRequestsKeys == nil then
		topRequestsKeys = getKeyList(topDatabase)
	end
	
	for _, key in pairs(topRequestsKeys:GetCurrentPage()) do
		--topDatabase:RemoveAsync(key.KeyName) [clear database]
		
		local data = loadData(topDatabase, key.KeyName)
		
		if data ~= nil then
				
			local creationDate = string.gsub(data.time, "/", "")
			local currentDate = string.gsub(os.date("%x"), "/", "")
			local isOld = tostring(currentDate) - tostring(creationDate) > minExistTime * 100

			if isOld == true and data.dislikes <= minVotes and data.likes <= minVotes then
				local succuss, errorMsg = pcall(function()
					return topDatabase:RemoveAsync(key.KeyName)
				end)
			else
				showRequest(data, key.KeyName, TopBoard)
			end
				
		end
		
		task.wait()
	end
	-- loaded all requestes
	if topRequestsKeys.IsFinished then
		break 
	end
	topRequestsKeys:AdvanceToNextPageAsync()
end