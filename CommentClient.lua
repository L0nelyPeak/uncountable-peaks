	--== Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local HttpService = game:GetService('HttpService')

	--== Configurations
local config = require( ReplicatedStorage:WaitForChild('Configure') )
local maxLength = config.MaxLength	-- max lenght of request message
local minLength = config.MinLength 	-- min lenght of request message
local requestCooldown = config.PublishCooldDown		-- cooldown beetwen request creations
local notificationTime = config.NotificationTime	-- time that notification is visible
	--== Remote Events
local remotesEvent = ReplicatedStorage:WaitForChild('RemoteEvents')	-- folder w remotes events
local sendRequestEvent = remotesEvent:WaitForChild('SendRequest')	-- new request remote event
local voteEvent = remotesEvent:WaitForChild('VoteEvent')			-- vote remote event

	--== Gui
local gui = script.Parent		-- main gui
local sendRequestFrame = gui:WaitForChild("SendRequest")				-- main frame of send request gui
local requestMessageInput = sendRequestFrame:WaitForChild("Message"):WaitForChild('MessageText')	-- request text input
local sendRequestButton = sendRequestFrame:WaitForChild('SendMessage'):WaitForChild('Send')			-- request send button
local LockedGui = sendRequestFrame:WaitForChild('Locked')				-- locked gui
local notificationGui = sendRequestFrame:WaitForChild('TypeMessage')	-- notification gui	
	
	--== Variables
local player = Players.LocalPlayer		-- player
local TopBoard = workspace:WaitForChild('GlobalTopBoard'):WaitForChild('SurfaceGui'):WaitForChild('ScrollingFrame')	 -- top request holder
local LiveBoard = workspace:WaitForChild('GlobalLiveBoard'):WaitForChild('SurfaceGui'):WaitForChild('ScrollingFrame') -- live request holder
local voted = {}	-- request that already was voted
local cooldown = player:GetAttribute("Cooldown")	-- cooldown duration
local onCooldown = false	-- playing is on cooldown

	--== Functions
-- notify a player
local function showNotification(text)
	notificationGui.Visible = true
	notificationGui.Text = text

	task.delay(notificationTime, function()
		notificationGui.Visible = false
		notificationGui.Text = ""
	end)
end

-- check if on cooldown
local function checkCooldown()
	if cooldown < tick() then
		onCooldown = false
		return
	else
		onCooldown =  true
		
		while cooldown >= tick() do
			local timer = math.floor(cooldown - tick())
			
			requestMessageInput.Visible = false
			requestMessageInput.Text = ""
			LockedGui.Visible = true
			LockedGui.Timer.Text = "Cooldown: " .. timer
			
			task.wait(1)
		end
		
		onCooldown = false
		requestMessageInput.Visible = true
		LockedGui.Visible = false
		LockedGui.Timer.Text = ""
	end
end
	
-- check message
local function checkMessage(text)
	if text then
		if typeof(text) == "string" then
			local length = #text
			if length >= minLength and length <= maxLength then
				return true
			end
		end
	end
	
	return false
end
	
-- send request to the server
local function sendRequest(enterPressed)
	if enterPressed == false then
		return
	end
	if onCooldown == true then
		showNotification("On Cooldown!")
		requestMessageInput.Text = ""
		return
	end
	
	local message = requestMessageInput.Text
	
	
	if checkMessage(message) == true then
		
		local uniqueKey = HttpService:GenerateGUID(false)
		
		local data = {}
		data.id = player.UserId
		data.message = message
		data.time = os.date("%x")
		data.likes = 0
		data.dislikes = 0
		
		sendRequestEvent:FireServer(uniqueKey, data)
	else
		showNotification("request does not meet the condition!")
	end
	requestMessageInput.Text = ""
	
end

-- voting system
local function vote(request:Instance, action:boolean, board)
	if table.find(voted, request.Name) then	-- already voted
		return
	end
	table.insert(voted, request.Name)
	
	voteEvent:FireServer(request.Name, action, board)
end
	--== Connections
-- player start editing request
requestMessageInput.Focused:Connect(checkCooldown)
-- player stop editig request
requestMessageInput.FocusLost:Connect(sendRequest)
-- player pressed "send request" button
sendRequestButton.Activated:Connect(sendRequest)
-- connecting to like and dislike buttons of each top request
TopBoard.ChildAdded:Connect(function(child)
	child.Message.UpVote.Button.Activated:Connect(function()
		vote(child, true, TopBoard)
	end)
	
	child.Message.DownVote.Button.Activated:Connect(function()
		vote(child, false, TopBoard)
	end)
end)
-- connecting to like and dislike buttons of each live request
LiveBoard.ChildAdded:Connect(function(child)
	child.Message.UpVote.Button.Activated:Connect(function()
		vote(child, true, LiveBoard)
	end)

	child.Message.DownVote.Button.Activated:Connect(function()
		vote(child, false, LiveBoard)
	end)
end)
-- connecting to cooldown
player:GetAttributeChangedSignal("Cooldown"):Connect(function()
	local value = player:GetAttribute("Cooldown")
	cooldown = value
end)
