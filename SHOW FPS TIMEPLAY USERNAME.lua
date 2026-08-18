repeat task.wait() until game:IsLoaded()

-- ============================================================
-- FPS / USERNAME WATERMARK - BẢN ĐÃ SỬA VÀ TỐI ƯU
-- ============================================================
-- Các điểm đã sửa:
--   • Dọn cả connection cũ khi Auto-Execute nhiều lần.
--   • Neo đúng góc trên bên phải bằng AnchorPoint.
--   • Không tạo Tween mới ở mỗi lần kéo chuột.
--   • Không rebuild ColorSequence ở mọi RenderStepped.
--   • Thêm RGB beam chạy ping-pong trên viền nhưng vẫn giữ viền trắng.
--   • Giữ chiều cao cố định, tránh layout bị giật theo username/FPS.

-- ============================================================
-- 1. CONFIG
-- ============================================================
local GUI_NAME = "FPS_Username_Display"

local BACKGROUND_IMAGE = "https://cdn.discordapp.com/attachments/1413006808959815720/1539162634694295552/image.png?ex=6a855068&is=6a83fee8&hm=feb6524dfdf47312886dda9792f224879288715091f6fcc0d65dc9c78f7adc66&"

-- Độ đậm của ảnh nền: 0 = trong suốt, 1 = rõ hoàn toàn.
local BACKGROUND_OPACITY = 0.8

-- Kích thước pill.
local BAR_HEIGHT = 28
-- TextSize của Roblox là số nguyên, nên 13.5 được làm tròn thành 14.
local TEXT_SIZE = 14
local PADDING_SIDE = 26
local RIGHT_MARGIN = 10
local TOP_MARGIN = 10

-- RGB chữ.
local TEXT_RGB_SPEED = 0.30
local TEXT_WAVE_DENSITY = 0.40
local TEXT_RGB_UPDATE_INTERVAL = 1 / 30
local TEXT_GRADIENT_STOPS = 13

-- Viền trắng cố định.
local BORDER_WHITE_THICKNESS = 1.6

-- RGB beam ngắn chạy qua viền: đi -> nghỉ -> về -> nghỉ.
local BORDER_BEAM_ENABLED = true
local BORDER_BEAM_THICKNESS = 2.2
local BORDER_SWEEP_TIME = 1.0
local BORDER_PAUSE_TIME = 1.0
local BORDER_BEAM_START_OFFSET = -0.85
local BORDER_BEAM_END_OFFSET = 0.85

-- Dấu | : xuống -> nghỉ đáy -> lên -> nghỉ đỉnh.
local SEPARATOR_MOVE_TIME = 0.30
local SEPARATOR_PAUSE_TIME = 0.25
local SEPARATOR_TOP_OFFSET = -0.5
local SEPARATOR_BOTTOM_OFFSET = 0.5

-- ============================================================
-- 2. SERVICES
-- ============================================================
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ============================================================
-- 3. GLOBAL CLEANUP - CHỐNG LEAK KHI AUTO-EXECUTE LẠI
-- ============================================================
local function getRuntimeEnvironment()
    local environment = _G

    if type(getgenv) == "function" then
        local success, result = pcall(getgenv)
        if success and type(result) == "table" then
            environment = result
        end
    end

    return environment
end

local runtimeEnvironment = getRuntimeEnvironment()
local cleanupKey = "__FPS_Username_Display_Cleanup"

local previousCleanup = runtimeEnvironment[cleanupKey]
if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end

local function destroyNamedGui(parent)
    if not parent then
        return
    end

    local success, children = pcall(function()
        return parent:GetChildren()
    end)

    if not success then
        return
    end

    for _, child in ipairs(children) do
        if child:IsA("ScreenGui") and child.Name == GUI_NAME then
            pcall(function()
                child:Destroy()
            end)
        end
    end
end

-- Dọn GUI cũ ở những nơi thường được executor sử dụng.
destroyNamedGui(CoreGui)

do
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    destroyNamedGui(playerGui)
end

local guiParent = CoreGui

-- Một số executor có gethui(); dùng nó để GUI không bị Roblox reset.
if type(gethui) == "function" then
    local success, hiddenUi = pcall(gethui)
    if success and hiddenUi then
        guiParent = hiddenUi
        destroyNamedGui(guiParent)
    end
end

-- ============================================================
-- 4. BACKGROUND HELPER
-- ============================================================
local function getTexture(input)
    if type(input) ~= "string" or input == "" then
        return ""
    end

    if string.match(input, "^https?://") then
        -- Direct URL không phải executor nào cũng hỗ trợ.
        -- Nếu có file API, tải một lần rồi dùng getcustomasset.
        if type(isfile) == "function"
            and type(getcustomasset) == "function"
            and type(writefile) == "function" then

            local safeName = string.gsub(input, "[^%w]", "_")
            if #safeName > 64 then
                safeName = string.sub(safeName, #safeName - 63)
            end

            local fileName = "custom_bg_" .. safeName .. ".png"
            local exists = false

            pcall(function()
                exists = isfile(fileName)
            end)

            if not exists then
                local success, response = pcall(function()
                    return game:HttpGet(input)
                end)

                if success and type(response) == "string" and #response > 0 then
                    pcall(function()
                        writefile(fileName, response)
                    end)
                end
            end

            local assetSuccess, asset = pcall(function()
                return getcustomasset(fileName)
            end)

            if assetSuccess and type(asset) == "string" and asset ~= "" then
                return asset
            end
        end

        -- Giữ fallback cho môi trường có hỗ trợ URL trực tiếp.
        return input
    end

    local numericId = tonumber(input)
    if numericId then
        return "rbxassetid://" .. numericId
    end

    return input
end

-- ============================================================
-- 5. SCREEN GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999999

-- Đăng ký cleanup trước khi parent để có thể dọn nếu parent lỗi.
local connections = {}
local destroyed = false

local function disconnectAll()
    for _, connection in ipairs(connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(connections)
end

local function cleanup()
    if destroyed then
        return
    end

    destroyed = true
    disconnectAll()

    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end

    if runtimeEnvironment[cleanupKey] == cleanup then
        runtimeEnvironment[cleanupKey] = nil
    end
end

runtimeEnvironment[cleanupKey] = cleanup

local parentSuccess = pcall(function()
    screenGui.Parent = guiParent
end)

-- CoreGui có thể bị khóa trong LocalScript thông thường; fallback sang PlayerGui.
if not parentSuccess then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
    screenGui.Parent = guiParent
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

-- Nếu người dùng tự xóa ScreenGui, ngắt các connection còn lại.
connect(screenGui.Destroying, function()
    if destroyed then
        return
    end

    destroyed = true
    disconnectAll()

    if runtimeEnvironment[cleanupKey] == cleanup then
        runtimeEnvironment[cleanupKey] = nil
    end
end)

-- ============================================================
-- 6. MAIN FRAME
-- ============================================================
local mainFrame = Instance.new("ImageLabel")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(1, 0)
mainFrame.Size = UDim2.new(0, 0, 0, BAR_HEIGHT)
mainFrame.Position = UDim2.new(1, -RIGHT_MARGIN, 0, TOP_MARGIN)
mainFrame.AutomaticSize = Enum.AutomaticSize.X
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mainFrame.BackgroundTransparency = 0.35
mainFrame.Image = getTexture(BACKGROUND_IMAGE)
mainFrame.ImageTransparency = 1 - math.clamp(BACKGROUND_OPACITY, 0, 1)
mainFrame.ScaleType = Enum.ScaleType.Crop
mainFrame.ClipsDescendants = true
mainFrame.Active = true
mainFrame.ZIndex = 1
mainFrame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.Name = "CapsuleCorner"
uiCorner.CornerRadius = UDim.new(1, 0)
uiCorner.Parent = mainFrame

-- ============================================================
-- 7. WHITE BORDER + SHOOTING RGB BEAM
-- ============================================================
local whiteStroke = Instance.new("UIStroke")
whiteStroke.Name = "WhiteSolidBorder"
whiteStroke.Thickness = BORDER_WHITE_THICKNESS
whiteStroke.Color = Color3.fromRGB(255, 255, 255)
whiteStroke.Transparency = 0
whiteStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
whiteStroke.Parent = mainFrame

local beamGradient

if BORDER_BEAM_ENABLED then
    local beamStroke = Instance.new("UIStroke")
    beamStroke.Name = "RGBBeamBorder"
    beamStroke.Thickness = BORDER_BEAM_THICKNESS
    beamStroke.Color = Color3.fromRGB(255, 255, 255)
    beamStroke.Transparency = 0
    beamStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    beamStroke.Parent = mainFrame

    beamGradient = Instance.new("UIGradient")
    beamGradient.Name = "RGBBeamGradient"
    beamGradient.Rotation = 0
    beamGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 0, 50)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 220, 0)),
        ColorSequenceKeypoint.new(0.58, Color3.fromRGB(0, 255, 100)),
        ColorSequenceKeypoint.new(0.66, Color3.fromRGB(120, 0, 255)),
        ColorSequenceKeypoint.new(0.74, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 255, 255)),
    })
    beamGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 1),
        NumberSequenceKeypoint.new(0.34, 1),
        NumberSequenceKeypoint.new(0.42, 0),
        NumberSequenceKeypoint.new(0.66, 0),
        NumberSequenceKeypoint.new(0.74, 1),
        NumberSequenceKeypoint.new(1.00, 1),
    })
    beamGradient.Parent = beamStroke
end

-- ============================================================
-- 8. LIST LAYOUT & PADDING
-- ============================================================
local uiListLayout = Instance.new("UIListLayout")
uiListLayout.Name = "ContentLayout"
uiListLayout.FillDirection = Enum.FillDirection.Horizontal
uiListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
uiListLayout.Padding = UDim.new(0, 3)
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Parent = mainFrame

local uiPadding = Instance.new("UIPadding")
uiPadding.Name = "SidePadding"
uiPadding.PaddingLeft = UDim.new(0, PADDING_SIDE)
uiPadding.PaddingRight = UDim.new(0, PADDING_SIDE)
uiPadding.Parent = mainFrame

-- ============================================================
-- 9. TEXT HELPERS
-- ============================================================
local function addTextStroke(parent, thickness, transparency)
    local textStroke = Instance.new("UIStroke")
    textStroke.Name = "TextOutline"
    textStroke.Thickness = thickness
    textStroke.Color = Color3.fromRGB(0, 0, 0)
    textStroke.Transparency = transparency
    textStroke.Parent = parent
end

local function createTextLabel(name, defaultText, color, fixedWidth)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Text = defaultText
    label.Font = Enum.Font.GothamBold
    label.TextSize = TEXT_SIZE
    label.TextColor3 = color
    label.TextTransparency = 0
    label.TextWrapped = false
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Size = UDim2.new(0, fixedWidth or 0, 0, BAR_HEIGHT)
    label.AutomaticSize = fixedWidth and Enum.AutomaticSize.None or Enum.AutomaticSize.X
    label.ZIndex = 3
    label.Parent = mainFrame

    addTextStroke(label, 1.0, 0.4)
    return label
end

local function createSeparator(name)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Text = "|"
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextTransparency = 0
    label.TextWrapped = false
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0, 7, 0, BAR_HEIGHT)
    label.AutomaticSize = Enum.AutomaticSize.None
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 3
    label.Parent = mainFrame

    addTextStroke(label, 0.9, 0.4)
    return label
end

-- ============================================================
-- 10. UI ELEMENTS
-- ============================================================
local fpsLabel = createTextLabel("FPSLabel", "0 FPS", Color3.fromRGB(50, 255, 50), 50)
local sepBefore = createSeparator("SepBefore")
local timeLabel = createTextLabel("TimeLabel", "00:00", Color3.fromRGB(255, 255, 255), 38)
local sepAfter = createSeparator("SepAfter")
local userLabel = createTextLabel("UserLabel", LocalPlayer.Name, Color3.fromRGB(255, 255, 255), nil)

-- ============================================================
-- 11. SEPARATOR GRADIENT
-- ============================================================
local separatorColor = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 50)),
    ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 220, 0)),
    ColorSequenceKeypoint.new(0.40, Color3.fromRGB(0, 255, 100)),
    ColorSequenceKeypoint.new(0.60, Color3.fromRGB(0, 240, 255)),
    ColorSequenceKeypoint.new(0.80, Color3.fromRGB(120, 0, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 150)),
})

local separatorTransparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1),
    NumberSequenceKeypoint.new(0.20, 1),
    NumberSequenceKeypoint.new(0.38, 0),
    NumberSequenceKeypoint.new(0.62, 0),
    NumberSequenceKeypoint.new(0.80, 1),
    NumberSequenceKeypoint.new(1.00, 1),
})

local sepGradientBefore = Instance.new("UIGradient")
sepGradientBefore.Name = "SeparatorRainbow"
sepGradientBefore.Color = separatorColor
sepGradientBefore.Transparency = separatorTransparency
sepGradientBefore.Rotation = 90
sepGradientBefore.Parent = sepBefore

local sepGradientAfter = Instance.new("UIGradient")
sepGradientAfter.Name = "SeparatorRainbow"
sepGradientAfter.Color = separatorColor
sepGradientAfter.Transparency = separatorTransparency
sepGradientAfter.Rotation = 90
sepGradientAfter.Parent = sepAfter

-- ============================================================
-- 12. CONTINUOUS RGB TEXT
-- ============================================================
local function getRainbowColor(position)
    position = position % 1
    return Color3.fromHSV(position, 1, 1)
end

local timeGradient = Instance.new("UIGradient")
timeGradient.Name = "ContinuousRGB"
timeGradient.Rotation = 0
timeGradient.Parent = timeLabel

local userGradient = Instance.new("UIGradient")
userGradient.Name = "ContinuousRGB"
userGradient.Rotation = 0
userGradient.Parent = userLabel

local lastMetrics

local function updateContinuousTextRGB(phase)
    local timeWidth = timeLabel.AbsoluteSize.X
    local userWidth = userLabel.AbsoluteSize.X
    local fpsWidth = fpsLabel.AbsoluteSize.X
    local separatorWidth = sepBefore.AbsoluteSize.X
    local separatorAfterWidth = sepAfter.AbsoluteSize.X
    local gap = uiListLayout.Padding.Offset

    if timeWidth <= 0 or userWidth <= 0 then
        return
    end

    -- Tính theo vị trí thật trong toàn bộ content, kể cả 2 dấu | và khoảng cách.
    local timeStart = fpsWidth + gap + separatorWidth + gap
    local userStart = timeStart + timeWidth + gap + separatorAfterWidth + gap
    local combinedWidth = userStart + userWidth

    if combinedWidth <= 0 then
        return
    end

    local metricsKey = string.format(
        "%.2f|%.2f|%.2f|%.2f|%.2f",
        timeWidth,
        userWidth,
        fpsWidth,
        separatorWidth,
        separatorAfterWidth
    )

    -- Không cần làm gì nếu kích thước chưa thay đổi và phase chưa được yêu cầu?
    -- ColorSequence vẫn cập nhật theo phase; metricsKey chỉ dùng để ghi nhận layout.
    lastMetrics = metricsKey

    local timeSequence = {}
    local userSequence = {}
    local lastIndex = TEXT_GRADIENT_STOPS - 1

    for i = 0, lastIndex do
        local p = i / lastIndex

        local timeGlobalX = timeStart + p * timeWidth
        local timeNormalized = timeGlobalX / combinedWidth
        local timeColor = getRainbowColor(timeNormalized * TEXT_WAVE_DENSITY + phase)
        table.insert(timeSequence, ColorSequenceKeypoint.new(p, timeColor))

        local userGlobalX = userStart + p * userWidth
        local userNormalized = userGlobalX / combinedWidth
        local userColor = getRainbowColor(userNormalized * TEXT_WAVE_DENSITY + phase)
        table.insert(userSequence, ColorSequenceKeypoint.new(p, userColor))
    end

    timeGradient.Color = ColorSequence.new(timeSequence)
    userGradient.Color = ColorSequence.new(userSequence)
end

-- ============================================================
-- 13. ANIMATION HELPERS
-- ============================================================
local function lerpNumber(a, b, alpha)
    return a + (b - a) * alpha
end

local function getPingPongValue(elapsed, moveTime, pauseTime, startValue, endValue)
    local cycleTime = 2 * (moveTime + pauseTime)
    local t = elapsed % cycleTime

    if t < moveTime then
        return lerpNumber(startValue, endValue, t / moveTime)
    elseif t < moveTime + pauseTime then
        return endValue
    elseif t < (2 * moveTime) + pauseTime then
        local reverseT = t - moveTime - pauseTime
        return lerpNumber(endValue, startValue, reverseT / moveTime)
    else
        return startValue
    end
end

-- ============================================================
-- 14. FPS + ANIMATIONS
-- ============================================================
local frameCount = 0
local fpsElapsed = 0
local animationElapsed = 0
local textUpdateElapsed = 999

local function updateFpsColor(fps)
    if fps >= 60 then
        fpsLabel.TextColor3 = Color3.fromRGB(50, 255, 50)
    elseif fps >= 30 then
        fpsLabel.TextColor3 = Color3.fromRGB(255, 210, 0)
    else
        fpsLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
    end
end

connect(RunService.RenderStepped, function(deltaTime)
    if destroyed or not screenGui.Parent then
        return
    end

    -- FPS counter: dùng deltaTime thay vì os.clock để tránh sai số khi máy lag.
    frameCount += 1
    fpsElapsed += deltaTime

    if fpsElapsed >= 1 then
        local fps = math.floor((frameCount / fpsElapsed) + 0.5)
        frameCount = 0
        fpsElapsed = 0
        fpsLabel.Text = tostring(fps) .. " FPS"
        updateFpsColor(fps)
    end

    animationElapsed += deltaTime

    -- RGB chữ: cập nhật 30 lần/giây, không rebuild ở toàn bộ 60/144 RenderStepped.
    textUpdateElapsed += deltaTime
    if textUpdateElapsed >= TEXT_RGB_UPDATE_INTERVAL then
        textUpdateElapsed = 0
        updateContinuousTextRGB(animationElapsed * TEXT_RGB_SPEED)
    end

    -- RGB beam viền.
    if beamGradient then
        local beamOffset = getPingPongValue(
            animationElapsed,
            BORDER_SWEEP_TIME,
            BORDER_PAUSE_TIME,
            BORDER_BEAM_START_OFFSET,
            BORDER_BEAM_END_OFFSET
        )
        beamGradient.Offset = Vector2.new(beamOffset, 0)
    end

    -- RGB dấu |.
    local separatorOffset = getPingPongValue(
        animationElapsed,
        SEPARATOR_MOVE_TIME,
        SEPARATOR_PAUSE_TIME,
        SEPARATOR_TOP_OFFSET,
        SEPARATOR_BOTTOM_OFFSET
    )

    sepGradientBefore.Offset = Vector2.new(0, separatorOffset)
    sepGradientAfter.Offset = Vector2.new(0, separatorOffset)
end)

-- ============================================================
-- 15. TIME COUNTER
-- ============================================================
local function updateTime()
    if destroyed or not screenGui.Parent then
        return
    end

    local totalSeconds = math.max(0, math.floor(workspace.DistributedGameTime))
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    timeLabel.Text = string.format("%02d:%02d", minutes, seconds)
end

updateTime()

task.spawn(function()
    while not destroyed and screenGui.Parent do
        task.wait(1)
        updateTime()
    end
end)

-- ============================================================
-- 16. UPDATE USERNAME
-- ============================================================
connect(LocalPlayer:GetPropertyChangedSignal("Name"), function()
    if not destroyed then
        userLabel.Text = LocalPlayer.Name
    end
end)

-- ============================================================
-- 17. DRAG SYSTEM - PC + MOBILE
-- ============================================================
local dragging = false
local dragInput
local dragStart
local startPosition

local function updateDrag(input)
    if not dragging or not dragStart or not startPosition then
        return
    end

    local delta = input.Position - dragStart
    mainFrame.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end

connect(mainFrame.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPosition = mainFrame.Position
    end
end)

connect(mainFrame.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then

        dragInput = input
    end
end)

connect(UserInputService.InputChanged, function(input)
    if input == dragInput and dragging then
        updateDrag(input)
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = false
        dragInput = nil
        dragStart = nil
        startPosition = nil
    end
end)

-- ============================================================
-- 18. INITIAL UPDATE
-- ============================================================
task.wait(0.2)
if not destroyed and screenGui.Parent then
    updateContinuousTextRGB(0)
end

print("[" .. GUI_NAME .. "] Loaded successfully!")
