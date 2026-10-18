-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local CharactersFolder = Workspace:WaitForChild("Characters")

-- Configuration
local AIM_ASSIST_ENABLED = false
local ESP_ENABLED = false
local AUTO_SPRINT_ENABLED = false
local SNIPER_MODE_ENABLED = false     -- Sniper Mode Toggle State
local AIM_PRO_ENABLED = false         -- Aim Pro Toggle State (Controller Pro Curve + Movement Demon Prediction)
local PC_CROSSHAIR_ENABLED = false    -- PC Crosshair Mode Toggle State (X: 683, Y: 292)
local JUMP_POWER_LOOP_ENABLED = false -- Jump Power Loop Toggle State
local JUMP_POWER_VALUE = 39.50        -- Target loop jump power (adjustable via slider)
local DEFAULT_JUMP_POWER = 36         -- Base normal jump power
local GAME_MODE = "TDM" -- Options: "TDM" or "FFA"
local SMOOTHNESS = 14 -- Natural, smooth tracking strength
local TARGET_PART_NAME = "Head" -- Locked on headshots

-- // Active Misc Suite Configurations
local MISC_MENU_OPEN = false
local FAST_WEAPON_SWAP_ENABLED = true
local BHOP_ASSIST_ENABLED = true
local INFECTION_MODE_ENABLED = false  -- Infection Mode Toggle State (Defaults to OFF)

-- Controller Aim & Fire Buttons (ADS / Hipfire trigger)
local TARGET_BUTTONS = {
	[Enum.KeyCode.ButtonL2] = true,
	[Enum.KeyCode.ButtonR2] = true
}

-- ESP & State Caching (Garbage Collection Optimization)
local espCache = {}
local hasSnappedThisPress = false
local hueTimer = 0
local isCurrentlySprinting = false
local lockedTargetModel = nil -- Strictly locks onto the specific target being shot
local lockLossFrames = 0      -- Grace buffer counter to prevent raycast flicker switching
local MAX_LOSS_FRAMES = 10    -- Persistence threshold before switching off an occluded target

-- Macro Auto-Reset Tracking
local currentResetThread = nil

-- Connection References for Kill Script Cleanup
local renderConnection = nil
local steppedConnection = nil

-- Create GUI (High ZIndex to ensure it sits above everything)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AimAssistGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- Diamond Crosshair Indicator (Defaults to Mobile X: 407, Y: 158)
local CrosshairDiamond = Instance.new("Frame")
CrosshairDiamond.Name = "RainbowDiamond"
CrosshairDiamond.Size = UDim2.new(0, 16, 0, 16)
CrosshairDiamond.Position = UDim2.new(0, 407, 0, 158)
CrosshairDiamond.AnchorPoint = Vector2.new(0.5, 0.5)
CrosshairDiamond.Rotation = 45
CrosshairDiamond.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
CrosshairDiamond.BackgroundTransparency = 0.5
CrosshairDiamond.Visible = true
CrosshairDiamond.ZIndex = 10
CrosshairDiamond.Parent = ScreenGui

local DiamondCorner = Instance.new("UICorner")
DiamondCorner.CornerRadius = UDim.new(0, 3)
DiamondCorner.Parent = CrosshairDiamond

local DiamondStroke = Instance.new("UIStroke")
DiamondStroke.Thickness = 1.5
DiamondStroke.Color = Color3.fromRGB(255, 255, 255)
DiamondStroke.Parent = CrosshairDiamond

-- Draggable Bubble Button
local BubbleButton = Instance.new("TextButton")
BubbleButton.Name = "BubbleButton"
BubbleButton.Size = UDim2.new(0, 50, 0, 50)
BubbleButton.Position = UDim2.new(0.05, 0, 0.75, 0)
BubbleButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
BubbleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
BubbleButton.TextSize = 14
BubbleButton.Font = Enum.Font.GothamBold
BubbleButton.Text = "AIM"
BubbleButton.ZIndex = 10
BubbleButton.Parent = ScreenGui

local BubbleCorner = Instance.new("UICorner")
BubbleCorner.CornerRadius = UDim.new(1, 0)
BubbleCorner.Parent = BubbleButton

local BubbleStroke = Instance.new("UIStroke")
BubbleStroke.Color = Color3.fromRGB(0, 170, 127)
BubbleStroke.Thickness = 2
BubbleStroke.Parent = BubbleButton

-- Control Container
local ControlContainer = Instance.new("Frame")
ControlContainer.Name = "ControlContainer"
ControlContainer.Size = UDim2.new(0, 160, 0, 395)
ControlContainer.Position = UDim2.new(0, 60, 0, 0)
ControlContainer.BackgroundTransparency = 1
ControlContainer.Visible = false
ControlContainer.ZIndex = 10
ControlContainer.Parent = BubbleButton

-- // Helper Function to Create Styled Buttons
local function createButton(name, yPos, color)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 160, 0, 34)
	btn.Position = UDim2.new(0, 0, 0, yPos)
	btn.BackgroundColor3 = color or Color3.fromRGB(45, 45, 45)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.ZIndex = 11
	btn.Parent = ControlContainer
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	
	return btn
end

-- // Misc Menu Button (Placed at top)
local MiscMenuButton = createButton("MiscMenuButton", 0, Color3.fromRGB(80, 80, 80))
MiscMenuButton.Text = "Misc Options >"

-- // Side-Popping Misc Sub-Container
local MiscSubContainer = Instance.new("Frame")
MiscSubContainer.Name = "MiscSubContainer"
MiscSubContainer.Size = UDim2.new(0, 160, 0, 122)
MiscSubContainer.Position = UDim2.new(1, 10, 0, 0)
MiscSubContainer.BackgroundTransparency = 1
MiscSubContainer.Visible = false
MiscSubContainer.ZIndex = 15
MiscSubContainer.Parent = MiscMenuButton

local function createMiscSubToggle(name, yPos, initialState, configKey)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 160, 0, 34)
	btn.Position = UDim2.new(0, 0, 0, yPos)
	btn.BackgroundColor3 = initialState and Color3.fromRGB(0, 170, 127) or Color3.fromRGB(50, 50, 50)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 11
	btn.Font = Enum.Font.GothamBold
	btn.ZIndex = 16
	btn.Text = name .. ": " .. (initialState and "ON" or "OFF")
	btn.Parent = MiscSubContainer
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	
	btn.MouseButton1Click:Connect(function()
		if configKey == "FastSwap" then
			FAST_WEAPON_SWAP_ENABLED = not FAST_WEAPON_SWAP_ENABLED
			btn.BackgroundColor3 = FAST_WEAPON_SWAP_ENABLED and Color3.fromRGB(0, 170, 127) or Color3.fromRGB(50, 50, 50)
			btn.Text = name .. ": " .. (FAST_WEAPON_SWAP_ENABLED and "ON" or "OFF")
		elseif configKey == "BHop" then
			BHOP_ASSIST_ENABLED = not BHOP_ASSIST_ENABLED
			btn.BackgroundColor3 = BHOP_ASSIST_ENABLED and Color3.fromRGB(0, 170, 127) or Color3.fromRGB(50, 50, 50)
			btn.Text = name .. ": " .. (BHOP_ASSIST_ENABLED and "ON" or "OFF")
		elseif configKey == "Infection" then
			INFECTION_MODE_ENABLED = not INFECTION_MODE_ENABLED
			btn.BackgroundColor3 = INFECTION_MODE_ENABLED and Color3.fromRGB(0, 170, 127) or Color3.fromRGB(50, 50, 50)
			btn.Text = name .. ": " .. (INFECTION_MODE_ENABLED and "ON" or "OFF")
		end
	end)
end

createMiscSubToggle("Fast Controller Swap", 0, true, "FastSwap")
createMiscSubToggle("Frame-Perfect B-Hop", 42, true, "BHop")
createMiscSubToggle("Infection Mode", 84, false, "Infection")

MiscMenuButton.MouseButton1Click:Connect(function()
	MISC_MENU_OPEN = not MISC_MENU_OPEN
	MiscSubContainer.Visible = MISC_MENU_OPEN
	MiscMenuButton.Text = MISC_MENU_OPEN and "Misc Options <" or "Misc Options >"
end)

-- Main Menu Buttons
local ModeButton = createButton("ModeButton", 42, Color3.fromRGB(0, 110, 255))
ModeButton.Text = "Mode: TDM"

local EspButton = createButton("EspButton", 80, Color3.fromRGB(45, 45, 45))
EspButton.Text = "ESP: OFF"

local SprintButton = createButton("SprintButton", 118, Color3.fromRGB(45, 45, 45))
SprintButton.Text = "Auto Sprint: OFF"

local JumpLoopButton = createButton("JumpLoopButton", 156, Color3.fromRGB(45, 45, 45))
JumpLoopButton.Text = "Jump Loop: OFF"

-- Jump Power Slider UI Container
local SliderContainer = Instance.new("Frame")
SliderContainer.Name = "SliderContainer"
SliderContainer.Size = UDim2.new(0, 160, 0, 42)
SliderContainer.Position = UDim2.new(0, 0, 0, 194)
SliderContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
SliderContainer.ZIndex = 11
SliderContainer.Parent = ControlContainer

local SliderCorner = Instance.new("UICorner")
SliderCorner.CornerRadius = UDim.new(0, 6)
SliderCorner.Parent = SliderContainer

local SliderLabel = Instance.new("TextLabel")
SliderLabel.Size = UDim2.new(1, 0, 0, 18)
SliderLabel.Position = UDim2.new(0, 0, 0, 2)
SliderLabel.BackgroundTransparency = 1
SliderLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
SliderLabel.TextSize = 11
SliderLabel.Font = Enum.Font.GothamBold
SliderLabel.ZIndex = 12
SliderLabel.Text = "Jump Power: 39.5"
SliderLabel.Parent = SliderContainer

local SliderBar = Instance.new("Frame")
SliderBar.Size = UDim2.new(1, -16, 0, 8)
SliderBar.Position = UDim2.new(0, 8, 0, 24)
SliderBar.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
SliderBar.BorderSizePixel = 0
SliderBar.ZIndex = 12
SliderBar.Parent = SliderContainer

local SliderBarCorner = Instance.new("UICorner")
SliderBarCorner.CornerRadius = UDim.new(1, 0)
SliderBarCorner.Parent = SliderBar

local initialPercent = (39.50 - 10) / 90

local SliderFill = Instance.new("Frame")
SliderFill.Size = UDim2.new(initialPercent, 0, 1, 0)
SliderFill.BackgroundColor3 = Color3.fromRGB(0, 170, 127)
SliderFill.BorderSizePixel = 0
SliderFill.ZIndex = 13
SliderFill.Parent = SliderBar

local SliderFillCorner = Instance.new("UICorner")
SliderFillCorner.CornerRadius = UDim.new(1, 0)
SliderFillCorner.Parent = SliderFill

local SliderKnob = Instance.new("TextButton")
SliderKnob.Size = UDim2.new(0, 14, 0, 14)
SliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
SliderKnob.Position = UDim2.new(initialPercent, 0, 0.5, 0)
SliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SliderKnob.Text = ""
SliderKnob.ZIndex = 14
SliderKnob.Parent = SliderBar

local KnobCorner = Instance.new("UICorner")
KnobCorner.CornerRadius = UDim.new(1, 0)
KnobCorner.Parent = SliderKnob

local ToggleButton = createButton("ToggleButton", 240, Color3.fromRGB(45, 45, 45))
ToggleButton.Text = "Aim Assist: OFF"

local SniperButton = createButton("SniperButton", 278, Color3.fromRGB(45, 45, 45))
SniperButton.Text = "Sniper Mode: OFF"

local AimProButton = createButton("AimProButton", 316, Color3.fromRGB(45, 45, 45))
AimProButton.Text = "Aim Pro: OFF"

local PCCrosshairButton = createButton("PCCrosshairButton", 354, Color3.fromRGB(45, 45, 45))
PCCrosshairButton.Text = "PC Crosshair: OFF"

local KillScriptButton = createButton("KillScriptButton", 392, Color3.fromRGB(200, 30, 30))
KillScriptButton.Text = "Kill Script"

-- Mode Switcher Logic
ModeButton.MouseButton1Click:Connect(function()
	if GAME_MODE == "TDM" then
		GAME_MODE = "FFA"
		ModeButton.Text = "Mode: FFA"
		ModeButton.BackgroundColor3 = Color3.fromRGB(255, 120, 0)
	else
		GAME_MODE = "TDM"
		ModeButton.Text = "Mode: TDM"
		ModeButton.BackgroundColor3 = Color3.fromRGB(0, 110, 255)
	end
end)

-- ESP Toggle Logic
EspButton.MouseButton1Click:Connect(function()
	ESP_ENABLED = not ESP_ENABLED
	if ESP_ENABLED then
		EspButton.Text = "ESP: ON"
		EspButton.BackgroundColor3 = Color3.fromRGB(140, 0, 255)
	else
		EspButton.Text = "ESP: OFF"
		EspButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		for targetKey, folder in pairs(espCache) do
			if folder then folder:Destroy() end
			espCache[targetKey] = nil
		end
	end
end)

-- Auto Sprint Toggle Logic
SprintButton.MouseButton1Click:Connect(function()
	AUTO_SPRINT_ENABLED = not AUTO_SPRINT_ENABLED
	if AUTO_SPRINT_ENABLED then
		SprintButton.Text = "Auto Sprint: ON"
		SprintButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	else
		SprintButton.Text = "Auto Sprint: OFF"
		SprintButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		if isCurrentlySprinting then
			pcall(function()
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.ButtonL3, false, game)
			end)
			isCurrentlySprinting = false
		end
	end
end)

-- Jump Loop Helper (Instantaneous Zero-Frame Trigger + 0.80s Timed Reset)
local function disableJumpLoop()
	JUMP_POWER_LOOP_ENABLED = false
	JumpLoopButton.Text = "Jump Loop: OFF"
	JumpLoopButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	pcall(function()
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.JumpPower = DEFAULT_JUMP_POWER
			end
		end
	end)
end

local function triggerMacroJump()
	if currentResetThread then
		task.cancel(currentResetThread)
		currentResetThread = nil
	end

	JUMP_POWER_LOOP_ENABLED = true
	JumpLoopButton.Text = "Jump Loop: ON"
	JumpLoopButton.BackgroundColor3 = Color3.fromRGB(255, 165, 0)
	
	pcall(function()
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum.JumpPower = JUMP_POWER_VALUE end
		end
	end)

	currentResetThread = task.delay(0.80, function()
		disableJumpLoop()
		currentResetThread = nil
	end)
end

JumpLoopButton.MouseButton1Click:Connect(triggerMacroJump)

-- // Controller ButtonY (Triangle) Listener for Instantaneous Timed Macro Jump
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.ButtonY then
		triggerMacroJump()
	end
end)

-- // Controller Fast Weapon-Swap Interception Hook
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not FAST_WEAPON_SWAP_ENABLED then return end
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1 then
		local char = LocalPlayer.Character
		local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		if char and backpack then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			local currentTool = char:FindFirstChildOfClass("Tool")
			if humanoid and currentTool then
				local tools = {}
				for _, item in ipairs(backpack:GetChildren()) do
					if item:IsA("Tool") then table.insert(tools, item) end
				end
				table.insert(tools, currentTool)
				if #tools > 1 then
					for i, tool in ipairs(tools) do
						if tool == currentTool then
							local nextIndex = (i % #tools) + 1
							humanoid:EquipTool(tools[nextIndex])
							break
						end
					end
				end
			end
		end
	end
end)

-- Slider Dragging Logic (10 to 100 range)
local minJP, maxJP = 10, 100
local sliding = false

local function updateSlider(inputX)
	local absPos = SliderBar.AbsolutePosition.X
	local absSize = SliderBar.AbsoluteSize.X
	local relativeX = math.clamp(inputX - absPos, 0, absSize)
	local percentage = relativeX / absSize
	
	local calculatedVal = minJP + (maxJP - minJP) * percentage
	calculatedVal = math.floor(calculatedVal * 10 + 0.5) / 10
	
	JUMP_POWER_VALUE = calculatedVal
	SliderFill.Size = UDim2.new(percentage, 0, 1, 0)
	SliderKnob.Position = UDim2.new(percentage, 0, 0.5, 0)
	SliderLabel.Text = string.format("Jump Power: %.1f", JUMP_POWER_VALUE)
end

SliderBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliding = true
		updateSlider(input.Position.X)
	end
end)

SliderKnob.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliding = true
		updateSlider(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		updateSlider(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliding = false
	end
end)

-- Aim Assist Toggle Logic
ToggleButton.MouseButton1Click:Connect(function()
	AIM_ASSIST_ENABLED = not AIM_ASSIST_ENABLED
	if AIM_ASSIST_ENABLED then
		ToggleButton.Text = "Aim Assist: ON"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 170, 127)
	else
		ToggleButton.Text = "Aim Assist: OFF"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		hasSnappedThisPress = false
		lockedTargetModel = nil
		lockLossFrames = 0
	end
end)

-- Sniper Mode Toggle Logic
SniperButton.MouseButton1Click:Connect(function()
	SNIPER_MODE_ENABLED = not SNIPER_MODE_ENABLED
	if SNIPER_MODE_ENABLED then
		AIM_PRO_ENABLED = false
		AimProButton.Text = "Aim Pro: OFF"
		AimProButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		SniperButton.Text = "Sniper Mode: ON"
		SniperButton.BackgroundColor3 = Color3.fromRGB(255, 69, 0)
	else
		SniperButton.Text = "Sniper Mode: OFF"
		SniperButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	end
end)

-- Aim Pro Toggle Logic
AimProButton.MouseButton1Click:Connect(function()
	AIM_PRO_ENABLED = not AIM_PRO_ENABLED
	if AIM_PRO_ENABLED then
		SNIPER_MODE_ENABLED = false
		SniperButton.Text = "Sniper Mode: OFF"
		SniperButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		AimProButton.Text = "Aim Pro: ON"
		AimProButton.BackgroundColor3 = Color3.fromRGB(50, 205, 50)
	else
		AimProButton.Text = "Aim Pro: OFF"
		AimProButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	end
end)

-- PC Crosshair Toggle Logic
PCCrosshairButton.MouseButton1Click:Connect(function()
	PC_CROSSHAIR_ENABLED = not PC_CROSSHAIR_ENABLED
	if PC_CROSSHAIR_ENABLED then
		PCCrosshairButton.Text = "PC Crosshair: ON"
		PCCrosshairButton.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		CrosshairDiamond.Position = UDim2.new(0, 683, 0, 292)
	else
		PCCrosshairButton.Text = "PC Crosshair: OFF"
		PCCrosshairButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		CrosshairDiamond.Position = UDim2.new(0, 407, 0, 158)
	end
end)

-- // Kill Script Nuke Logic
KillScriptButton.MouseButton1Click:Connect(function()
	pcall(function()
		if renderConnection then renderConnection:Disconnect() end
		if steppedConnection then steppedConnection:Disconnect() end
		
		for _, folder in pairs(espCache) do
			if folder then folder:Destroy() end
		end
        espCache = {}
		
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.JumpPower = DEFAULT_JUMP_POWER
			end
		end
		
		if isCurrentlySprinting then
			pcall(function()
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.ButtonL3, false, game)
			end)
		end
		
		ScreenGui:Destroy()
	end)
end)

-- // Draggable Bubble Click Handler
BubbleButton.MouseButton1Click:Connect(function()
	ControlContainer.Visible = not ControlContainer.Visible
end)

local isDragging = false
local dragStartPos = Vector2.new(0, 0)
local startGuiPos = UDim2.new(0, 0, 0, 0)

BubbleButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType ==Enum.UserInputType.Touch then
		isDragging = true
		dragStartPos = input.Position
		startGuiPos = BubbleButton.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStartPos
		BubbleButton.Position = UDim2.new(
			startGuiPos.X.Scale, 
			startGuiPos.X.Offset + delta.X, 
			startGuiPos.Y.Scale, 
			startGuiPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = false
	end
end)

-- Helper: Checks if a character model belongs to a real human player
local function isRealPlayer(model)
	return Players:GetPlayerFromCharacter(model) ~= nil
end

-- // Target Validation (Checks Workspace.Characters folder with Infection Mode Filter)
local function isValidTargetModel(model)
	if not model or not model:IsA("Model") then return false end
	if model == LocalPlayer.Character then return false end
	
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local targetPart = model:FindFirstChild(TARGET_PART_NAME)
	
	if not humanoid or humanoid.Health <= 0 or not targetPart then
		return false
	end

	-- Infection Mode: Only target models wearing the Red enemy highlight (the opposing team / infected)
	if INFECTION_MODE_ENABLED then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("Highlight") then
				local outline = child.OutlineColor or child.FillColor
				if outline.R > 0.8 and outline.B < 0.3 then
					return true
				end
			end
		end
		return false
	end

	if GAME_MODE == "FFA" then
		return true
	end

	-- Check if the character model has a Red enemy highlight (R > 0.8 and low Blue)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Highlight") then
			local outline = child.OutlineColor or child.FillColor
			if outline.R > 0.8 and outline.B < 0.3 then
				return true
			end
		end
	end
	
	return false
end

local function isVisible(targetPart)
	local adjustedTargetPos = targetPart.Position + Vector3.new(0, 0.2, 0)
	local origin = Camera.CFrame.Position
	local direction = adjustedTargetPos - origin
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, targetPart.Parent}
	raycastParams.IgnoreWater = true
	
	local result = Workspace:Raycast(origin, direction, raycastParams)
	if result then return false end
	return true
end

-- // Sticky Target Selection with Raycast Buffer & Infection Closest-Target Priority
local function getClosestTarget(buttonHeld)
	if buttonHeld and lockedTargetModel then
		if isValidTargetModel(lockedTargetModel) then
			local targetPart = lockedTargetModel:FindFirstChild(TARGET_PART_NAME)
			if targetPart and isVisible(targetPart) then
				lockLossFrames = 0
				return targetPart
			else
				lockLossFrames = lockLossFrames + 1
				if lockLossFrames < MAX_LOSS_FRAMES and targetPart then
					return targetPart
				end
			end
		end
		lockedTargetModel = nil
		lockLossFrames = 0
	end

	local screenCenter = PC_CROSSHAIR_ENABLED and Vector2.new(683, 292) or Vector2.new(407, 158)
	
	local closestTargetPart = nil
	local closestTargetModel = nil
	local shortestDist = math.huge

	-- In Infection Mode, target whoever is closest among the valid red-highlighted enemies (Players & Bots)
	if INFECTION_MODE_ENABLED then
		for _, model in ipairs(CharactersFolder:GetChildren()) do
			if model:IsA("Model") and isValidTargetModel(model) then
				local targetPart = model:FindFirstChild(TARGET_PART_NAME)
				if targetPart and isVisible(targetPart) then
					local screenPoint, onScreen = Camera:WorldToScreenPoint(targetPart.Position)
					if onScreen then
						local distance = (Vector2.new(screenPoint.X, screenPoint.Y) - screenCenter).Magnitude
						if distance < shortestDist then
							shortestDist = distance
							closestTargetPart = targetPart
							closestTargetModel = model
						end
					end
				end
			end
		end
		
		if closestTargetPart then
			if buttonHeld then
				lockedTargetModel = closestTargetModel
				lockLossFrames = 0
			end
			return closestTargetPart
		end
		return nil
	end

	-- Standard TDM / FFA Mode (Real Player Priority)
	local closestPlayerTarget = nil
	local closestPlayerModel = nil
	local shortestPlayerDist = math.huge

	local closestBotTarget = nil
	local closestBotModel = nil
	local shortestBotDist = math.huge

	for _, model in ipairs(CharactersFolder:GetChildren()) do
		if model:IsA("Model") and isValidTargetModel(model) then
			local targetPart = model:FindFirstChild(TARGET_PART_NAME)
			
			if targetPart and isVisible(targetPart) then
				local screenPoint, onScreen = Camera:WorldToScreenPoint(targetPart.Position)
				
				if onScreen then
					local distance = (Vector2.new(screenPoint.X, screenPoint.Y) - screenCenter).Magnitude
					
					if isRealPlayer(model) then
						if distance < shortestPlayerDist then
							shortestPlayerDist = distance
							closestPlayerTarget = targetPart
							closestPlayerModel = model
						end
					else
						if distance < shortestBotDist then
							shortestBotDist = distance
							closestBotTarget = targetPart
							closestBotModel = model
						end
					end
				end
			end
		end
	end

	if closestPlayerTarget then
		if buttonHeld then 
			lockedTargetModel = closestPlayerModel 
			lockLossFrames = 0
		end
		return closestPlayerTarget
	elseif closestBotTarget then
		if buttonHeld then 
			lockedTargetModel = closestBotModel 
			lockLossFrames = 0
		end
		return closestBotTarget
	end

	return nil
end

local function isAimButtonHeld()
	for code, _ in pairs(TARGET_BUTTONS) do
		if UserInputService:IsKeyDown(code) then return true end
	end
	for _, input in ipairs(UserInputService:GetMouseButtonsPressed()) do
		if TARGET_BUTTONS[input.KeyCode] then return true end
	end
	for _, gamepad in ipairs(UserInputService:GetConnectedGamepads()) do
		for code, _ in pairs(TARGET_BUTTONS) do
			if UserInputService:IsGamepadButtonDown(gamepad, code) then return true end
		end
	end
	return false
end

local function isGamepadConnected()
	return #UserInputService:GetConnectedGamepads() > 0 or true
end

steppedConnection = RunService.Stepped:Connect(function()
	if JUMP_POWER_LOOP_ENABLED then
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.JumpPower ~= JUMP_POWER_VALUE then
				hum.JumpPower = JUMP_POWER_VALUE
			end
		end
	end
end)

renderConnection = RunService.RenderStepped:Connect(function(dt)
	local buttonHeld = isAimButtonHeld()
	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")

	-- Frame-Perfect B-Hop Assist Logic
	if BHOP_ASSIST_ENABLED and humanoid and rootPart then
		local isSpaceHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space)
		for _, gamepad in ipairs(UserInputService:GetConnectedGamepads()) do
			if UserInputService:IsGamepadButtonDown(gamepad, Enum.KeyCode.ButtonA) then isSpaceHeld = true end
		end
		if humanoid.FloorMaterial ~= Enum.Material.Air and isSpaceHeld then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end

	-- Persistent Auto-Sprint Hold Logic
	if AUTO_SPRINT_ENABLED then
		if not buttonHeld then
			if not isCurrentlySprinting then
				pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.ButtonL3, false, game) end)
				isCurrentlySprinting = true
			end
		else
			if isCurrentlySprinting then
				pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.ButtonL3, false, game) end)
				isCurrentlySprinting = false
			end
		end
	elseif isCurrentlySprinting then
		pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.ButtonL3, false, game) end)
		isCurrentlySprinting = false
	end

	-- ESP Update Logic (Applies to Players, and Bots when Infection Mode is Active)
	for _, player in ipairs(Players:GetPlayers()) do
		local pChar = player.Character
		local shouldShowEsp = ESP_ENABLED and pChar and isValidTargetModel(pChar)
		
		if shouldShowEsp then
			local head = pChar:FindFirstChild("Head") or pChar:FindFirstChild("HumanoidRootPart")
			
			if head then
				local cacheData = espCache[player]
				if not cacheData then
					if cacheData and cacheData.Folder then
						cacheData.Folder:Destroy()
					end
					
					local folder = Instance.new("Folder")
					folder.Name = "CustomESP"
					folder.Parent = pChar
					
					local hl = Instance.new("Highlight")
					hl.Adornee = pChar
					hl.FillColor = Color3.fromRGB(255, 50, 50)
					hl.OutlineColor = Color3.fromRGB(255, 255, 255)
					hl.FillTransparency = 0.5
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Parent = folder
					
					local bb = Instance.new("BillboardGui")
					bb.Name = "NameTag"
					bb.Adornee = head
					bb.Size = UDim2.new(0, 120, 0, 40)
					bb.StudsOffset = Vector3.new(0, 2.5, 0)
					bb.AlwaysOnTop = true
					bb.Parent = folder
					
					local txt = Instance.new("TextLabel")
					txt.Size = UDim2.new(1, 0, 1, 0)
					txt.BackgroundTransparency = 1
					txt.Text = player.Name
					txt.TextColor3 = Color3.fromRGB(255, 255, 255)
					txt.TextSize = 13
					txt.Font = Enum.Font.GothamBold
					txt.TextStrokeTransparency = 0.3
					txt.Parent = bb
					
					espCache[player] = folder
				end
			end
		else
			if espCache[player] then
				espCache[player]:Destroy()
				espCache[player] = nil
			end
		end
	end

	-- Additional ESP handling for enemy bots in Infection Mode
	if ESP_ENABLED and INFECTION_MODE_ENABLED then
		for _, model in ipairs(CharactersFolder:GetChildren()) do
			if model:IsA("Model") and not isRealPlayer(model) and isValidTargetModel(model) then
				local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
				if head then
					local cacheData = espCache[model]
					if not cacheData then
						local folder = Instance.new("Folder")
						folder.Name = "CustomBotESP"
						folder.Parent = model
						
						local hl = Instance.new("Highlight")
						hl.Adornee = model
						hl.FillColor = Color3.fromRGB(255, 50, 50)
						hl.OutlineColor = Color3.fromRGB(255, 255, 255)
						hl.FillTransparency = 0.5
						hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
						hl.Parent = folder
						
						espCache[model] = folder
					end
				end
			else
				if espCache[model] and not isRealPlayer(model) then
					espCache[model]:Destroy()
					espCache[model] = nil
				end
			end
		end
	end

	-- Aim Assist & Rainbow Indicator Logic
	local target = getClosestTarget(buttonHeld)

	if not buttonHeld then
		hasSnappedThisPress = false
		lockedTargetModel = nil
		lockLossFrames = 0
	end
	
	if AIM_ASSIST_ENABLED and isGamepadConnected() and buttonHeld and target then
		local currentCamCFrame = Camera.CFrame
		
		local adjustedTargetPos = target.Position
		if AIM_PRO_ENABLED and target.Parent then
			local targetRoot = target.Parent:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				adjustedTargetPos = target.Position + (targetRoot.AssemblyLinearVelocity * 0.11)
			end
		end
		
		local targetCFrame = CFrame.new(currentCamCFrame.Position, adjustedTargetPos)
		
		hueTimer = (hueTimer + dt * 0.8) % 1
		local rainbowColor = Color3.fromHSV(hueTimer, 1, 1)
		
		if AIM_PRO_ENABLED then
			local currentPos = currentCamCFrame.Position
			local direction = (adjustedTargetPos - currentPos).Unit
			
			local controllerCurveSpeed = 13.5
			local step = math.clamp(dt * controllerCurveSpeed, 0, 1)
			
			local newLookVector = currentCamCFrame.LookVector:Lerp(direction, step)
			Camera.CFrame = CFrame.new(currentPos, currentPos + newLookVector)
			hasSnappedThisPress = true
		else
			local currentSmoothness = SNIPER_MODE_ENABLED and 999 or SMOOTHNESS
			
			if not hasSnappedThisPress or SNIPER_MODE_ENABLED then
				Camera.CFrame = targetCFrame
				hasSnappedThisPress = true
			else
				Camera.CFrame = currentCamCFrame:Lerp(targetCFrame, math.clamp(dt * currentSmoothness, 0, 1))
			end
		end
		
		CrosshairDiamond.BackgroundColor3 = rainbowColor
		DiamondStroke.Color = rainbowColor
		CrosshairDiamond.BackgroundTransparency = 0.1
	else
		CrosshairDiamond.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		DiamondStroke.Color = Color3.fromRGB(255, 255, 255)
		CrosshairDiamond.BackgroundTransparency = 0.6
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if espCache[player] then
		espCache[player]:Destroy()
		espCache[player] = nil
	end
end)
