local UserInputService = game:GetService("UserInputService")
local ScreenGui = Instance.new("ScreenGui")
local Frame = Instance.new("Frame")
local TextLabel = Instance.new("TextLabel")
local UIPadding = Instance.new("UIPadding")
local number = Instance.new("TextBox")
local UICorner = Instance.new("UICorner")
local down = Instance.new("TextButton")
local UIPadding_2 = Instance.new("UIPadding")
local up = Instance.new("TextButton")
local UIPadding_3 = Instance.new("UIPadding")
local timer = 0.85

ScreenGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")

Frame.Parent = ScreenGui
Frame.BackgroundColor3 = Color3.fromRGB(56, 56, 56)
Frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
Frame.BorderSizePixel = 0
Frame.Position = UDim2.new(0.0383914597, 0, 0.0925069377, 0)
Frame.Size = UDim2.new(0, 219, 0, 118)

TextLabel.Parent = Frame
TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TextLabel.BackgroundTransparency = 1.000
TextLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
TextLabel.BorderSizePixel = 0
TextLabel.Position = UDim2.new(-0.00160858152, 0, -0.0042672432, 0)
TextLabel.Size = UDim2.new(1, 0, 0.5, 0)
TextLabel.Font = Enum.Font.SourceSansBold
TextLabel.Text = "timer (turn down if late, opposite for early)"
TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TextLabel.TextScaled = true
TextLabel.TextSize = 14.000
TextLabel.TextWrapped = true

UIPadding.Parent = TextLabel
UIPadding.PaddingLeft = UDim.new(0.100000001, 0)
UIPadding.PaddingRight = UDim.new(0.100000001, 0)

number.Name = "number"
number.Parent = Frame
number.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
number.BorderColor3 = Color3.fromRGB(56, 161, 0)
number.BorderSizePixel = 2
number.Position = UDim2.new(0.030867625, 0, 0.494305104, 0)
number.Size = UDim2.new(0.672602713, 0, 0.449999988, 0)
number.Font = Enum.Font.SourceSansBold
number.Text = "0.85"
number.TextColor3 = Color3.fromRGB(255, 255, 255)
number.TextScaled = true
number.TextSize = 14.000
number.TextWrapped = true

UICorner.CornerRadius = UDim.new(0, 4)
UICorner.Parent = Frame

down.Name = "down"
down.Parent = Frame
down.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
down.BorderColor3 = Color3.fromRGB(56, 161, 0)
down.BorderSizePixel = 2
down.Position = UDim2.new(0.734000027, 0, 0.72299999, 0)
down.Size = UDim2.new(0.233999997, 0, 0.221000001, 0)
down.Font = Enum.Font.SourceSansBold
down.Text = "▼"
down.TextColor3 = Color3.fromRGB(255, 255, 255)
down.TextScaled = true
down.TextSize = 14.000
down.TextWrapped = true

UIPadding_2.Parent = down
UIPadding_2.PaddingBottom = UDim.new(0.100000001, 0)
UIPadding_2.PaddingLeft = UDim.new(0.100000001, 0)
UIPadding_2.PaddingRight = UDim.new(0.100000001, 0)
UIPadding_2.PaddingTop = UDim.new(0.100000001, 0)

up.Name = "up"
up.Parent = Frame
up.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
up.BorderColor3 = Color3.fromRGB(56, 161, 0)
up.BorderSizePixel = 2
up.Position = UDim2.new(0.734000027, 0, 0.493999988, 0)
up.Size = UDim2.new(0.233999997, 0, 0.221000001, 0)
up.Font = Enum.Font.SourceSansBold
up.Text = "▲"
up.TextColor3 = Color3.fromRGB(255, 255, 255)
up.TextScaled = true
up.TextSize = 14.000
up.TextWrapped = true

UIPadding_3.Parent = up
UIPadding_3.PaddingBottom = UDim.new(0.100000001, 0)
UIPadding_3.PaddingLeft = UDim.new(0.100000001, 0)
UIPadding_3.PaddingRight = UDim.new(0.100000001, 0)
UIPadding_3.PaddingTop = UDim.new(0.100000001, 0)

local function EIBRF_fake_script()
	local script = Instance.new('LocalScript', Frame)
	
	local gui = script.Parent
	
	local dragging
	local dragInput
	local dragStart
	local startPos
	
	local function update(input)
		local delta = input.Position - dragStart
		gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	
	gui.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = gui.Position
			
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	
	gui.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			update(input)
		end
	end)
	
	gui.number.FocusLost:Connect(function()
		gui.number.Text = string.gsub(gui.number.Text, "[^%d.]", "")
	end)
	
	gui.number:GetPropertyChangedSignal("Text"):Connect(function()
		gui.number.Text = string.gsub(gui.number.Text, "[^%d.]", "")
		if gui.number.Text ~= "" then
			timer = tonumber(gui.number.Text)
		end
	end)
	
	gui.up.MouseButton1Click:Connect(function()
		gui.number.Text = string.format("%.2f", tonumber(gui.number.Text) + 0.01)
	end)
	
	gui.down.MouseButton1Click:Connect(function()
		gui.number.Text = string.format("%.2f", tonumber(gui.number.Text) - 0.01)
	end)
end

coroutine.wrap(EIBRF_fake_script)()

local function shoot()
    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()

    game:GetService("ReplicatedStorage").GameEvents.ClientAction:FireServer("Shoot", true)

    while true do
        wait()
        local shotMeter = character:GetAttribute("ShotMeter")
        if shotMeter >= timer and shotMeter <= 1.2 then
            game:GetService("ReplicatedStorage").GameEvents.ClientAction:FireServer("Shoot", false)
            break
        end
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if not gameProcessedEvent then
        if input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonL2 then
            shoot()
        elseif input.KeyCode == Enum.KeyCode.F then
            shoot()
        end
    end
end)
