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

-- MODULE INDEX:
-- 1  Config              : thông số giao diện/animation
-- 2  Services            : Roblox services
-- 3  Global Cleanup      : dọn GUI và connection cũ
-- 4  Texture Loader      : tải/chuyển đổi ảnh nền
-- 5  ScreenGui Root      : container và lifecycle
-- 6  Main Frame          : pill chính và vị trí
-- 7  Border Rendering    : viền trắng + RGB beam
-- 8  Content Layout      : UIListLayout/UIPadding
-- 9  Text Factories      : tạo label dùng chung
-- 10 Watermark Content   : FPS/Time/Username/separator
-- 11 Separator RGB      : gradient cho dấu |
-- 12 Text RGB            : gradient liên tục cho Time/Username
-- 13 Animation Math      : lerp và ping-pong
-- 14 Frame Loop          : FPS và animation theo frame
-- 15 Game Time           : bộ đếm thời gian game
-- 16 Username Observer   : cập nhật username
-- 17 Drag Controller     : kéo bằng PC/mobile
-- 18 Initial Update      : khởi tạo gradient sau layout

-- ============================================================
-- MODULE 1: CONFIGURATION
-- Mục đích: tập trung toàn bộ thông số để chỉnh giao diện và tốc độ
-- mà không phải sửa logic bên dưới.
-- ============================================================
-- Tên duy nhất của ScreenGui.
-- Chức năng: dùng để tìm/xóa GUI cũ khi Auto-Execute lại.
-- Không nên đặt trùng với GUI khác trong CoreGui hoặc PlayerGui.
local GUI_NAME = "FPS_Username_Display"

-- Ảnh nền của pill.
-- Có thể dùng:
--   1. URL http/https: cần executor hỗ trợ HttpGet + getcustomasset.
--   2. Roblox Asset ID dạng số hoặc "rbxassetid://...".
--   3. Asset local do executor trả về.
local BACKGROUND_IMAGE = "https://cdn.discordapp.com/attachments/1410631576718676011/1527605586387144794/7a55130c51f61c865a364e7f0599f402.png?ex=6a84cc51&is=6a837ad1&hm=514a22ffbe18d70511cf5e1c28fdbad3680545bb9180dcd67e52d989dcd1ec17&"

-- Độ rõ của ảnh nền.
-- Giá trị hợp lệ: 0 đến 1.
--   0.00 = ảnh không nhìn thấy.
--   0.65 = ảnh mờ vừa.
--   1.00 = ảnh rõ nhất.
-- Giá trị này được chuyển thành ImageTransparency = 1 - BACKGROUND_OPACITY.
local BACKGROUND_OPACITY = 0.70

-- Chiều cao cố định của thanh watermark, tính bằng pixel.
-- Tăng giá trị này sẽ làm pill cao hơn và chữ nằm thoáng hơn.
-- Khoảng thường dùng: 24 đến 40.
local BAR_HEIGHT = 28

-- Kích thước chữ.
-- Roblox TextSize dùng số nguyên; không dùng 13.5 trực tiếp.
-- Tăng giá trị để chữ lớn hơn, nhưng username dài có thể làm pill rộng hơn.
local TEXT_SIZE = 14

-- Khoảng trống bên trái và bên phải nội dung.
-- Tăng giá trị này sẽ làm pill dài hơn và để lộ nhiều ảnh nền ở hai đầu.
local PADDING_SIDE = 26

-- Khoảng cách từ cạnh phải màn hình đến cạnh phải pill.
-- Giá trị càng lớn thì pill càng dịch sang trái.
local RIGHT_MARGIN = 10

-- Khoảng cách từ cạnh trên màn hình đến pill.
-- Giá trị càng lớn thì pill càng dịch xuống.
local TOP_MARGIN = 10

-- ============================================================
-- CẤU HÌNH RGB CHỮ
-- ============================================================

-- Tốc độ chạy của dải màu trên Time và Username.
-- Tăng lên 0.50 hoặc 1.00 để màu chạy nhanh hơn.
-- Giảm xuống 0.10 để chuyển màu chậm hơn.
local TEXT_RGB_SPEED = 0.30

-- Mật độ màu cầu vồng trên tổng chiều dài nội dung.
-- Giá trị nhỏ: dải màu dài, chuyển màu chậm và mượt.
-- Giá trị lớn: nhiều màu hơn trong đoạn chữ, chuyển màu nhanh hơn.
local TEXT_WAVE_DENSITY = 0.40

-- Tần suất cập nhật ColorSequence của chữ.
-- 1 / 30 nghĩa là cập nhật 30 lần mỗi giây.
-- Nếu máy yếu/mobile bị giật, thử 1 / 20 hoặc 1 / 15.
-- Không nên để quá cao vì ColorSequence được rebuild nhiều lần.
local TEXT_RGB_UPDATE_INTERVAL = 1 / 30

-- Số điểm màu trong mỗi ColorSequence.
-- Tăng lên: chuyển màu mượt hơn nhưng tốn tài nguyên hơn.
-- Giảm xuống: nhẹ hơn nhưng màu có thể ít mượt.
-- Giá trị cân bằng thường là 9 đến 17.
local TEXT_GRADIENT_STOPS = 13

-- ============================================================
-- CẤU HÌNH VIỀN TRẮNG
-- ============================================================

-- Độ dày viền trắng cố định quanh pill.
-- Giá trị tính bằng pixel; 1.0 đến 2.0 thường phù hợp.
local BORDER_WHITE_THICKNESS = 1.6

-- ============================================================
-- CẤU HÌNH RGB BEAM TRÊN VIỀN
-- ============================================================

-- Bật/tắt tia RGB chạy trên viền.
-- false: chỉ hiển thị viền trắng.
-- true: hiển thị thêm RGB beam ping-pong.
local BORDER_BEAM_ENABLED = true

-- Độ dày của RGB beam.
-- Nếu nhỏ hơn BORDER_WHITE_THICKNESS, beam có thể khó nhìn.
-- Nếu quá lớn, beam có thể che nhiều viền trắng.
local BORDER_BEAM_THICKNESS = 2.2

-- Thời gian RGB beam chạy một chiều.
-- Ví dụ 1.0 = chạy từ đầu này đến đầu kia trong 1 giây.
local BORDER_SWEEP_TIME = 1.0

-- Thời gian RGB beam đứng yên ở mỗi đầu.
-- Giá trị này được áp dụng ở cả đầu trái và đầu phải.
local BORDER_PAUSE_TIME = 1.0

-- Offset bắt đầu của beam.
-- Giá trị âm đẩy dải màu về phía trái.
-- Khoảng thường dùng: -0.70 đến -1.00.
local BORDER_BEAM_START_OFFSET = -0.85

-- Offset kết thúc của beam.
-- Giá trị dương đẩy dải màu về phía phải.
-- Độ chênh giữa START và END quyết định quãng đường beam di chuyển.
local BORDER_BEAM_END_OFFSET = 0.85

-- ============================================================
-- CẤU HÌNH RGB CHO DẤU |
-- ============================================================

-- Thời gian dấu | di chuyển từ vị trí trên xuống vị trí dưới.
local SEPARATOR_MOVE_TIME = 0.30

-- Thời gian dấu | dừng ở vị trí trên và dưới.
local SEPARATOR_PAUSE_TIME = 0.25

-- Offset vị trí phía trên của dải RGB.
-- Số âm tương ứng với phía trên.
local SEPARATOR_TOP_OFFSET = -0.5

-- Offset vị trí phía dưới của dải RGB.
-- Số dương tương ứng với phía dưới.
-- Tăng khoảng cách giữa TOP và BOTTOM để chuyển động rõ hơn.
local SEPARATOR_BOTTOM_OFFSET = 0.5

-- ============================================================
-- MODULE 2: ROBLOX SERVICES
-- Mục đích: lấy các dịch vụ dùng cho GUI, người chơi, animation và input.
-- ============================================================
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ============================================================
-- MODULE 3: GLOBAL CLEANUP / LIFECYCLE
-- Mục đích: xóa GUI cũ và ngắt connection cũ trước khi tạo GUI mới.
-- Nếu không có module này, mỗi lần execute sẽ tạo thêm RenderStepped,
-- làm watermark bị chồng và gây memory leak.
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
-- MODULE 4: BACKGROUND / TEXTURE LOADER
-- Mục đích: nhận URL, Roblox Asset ID hoặc asset local của executor,
-- sau đó trả về chuỗi texture phù hợp cho ImageLabel.Image.
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
-- MODULE 5: SCREEN GUI ROOT
-- Mục đích: tạo container gốc và đăng ký cleanup cho toàn bộ UI.
-- Mọi connection được lưu vào bảng connections để có thể ngắt sau này.
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
-- MODULE 6: MAIN WATERMARK FRAME
-- Mục đích: tạo pill chính, đặt ảnh nền, bo góc và neo góc phải màn hình.
-- AutomaticSize.X giúp chiều rộng tự giãn theo username.
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
-- MODULE 7: BORDER RENDERING
-- Mục đích: vẽ viền trắng cố định và một viền RGB chuyển động.
-- RGB beam chỉ thay đổi UIGradient.Offset nên nhẹ hơn việc tạo lại Stroke.
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
-- MODULE 8: CONTENT LAYOUT
-- Mục đích: xếp FPS, dấu |, Time và Username thành một hàng ngang.
-- UIPadding tạo khoảng trống ở hai đầu pill.
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
-- MODULE 9: TEXT FACTORIES
-- Mục đích: tạo TextLabel và áp dụng style chung, tránh lặp code.
-- Label số có chiều rộng cố định; username dùng AutomaticSize.X.
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
-- MODULE 10: WATERMARK CONTENT
-- Mục đích: tạo bốn nhóm nội dung: FPS, hai dấu phân cách, Time, Username.
-- ============================================================
local fpsLabel = createTextLabel("FPSLabel", "0 FPS", Color3.fromRGB(50, 255, 50), 50)
local sepBefore = createSeparator("SepBefore")
local timeLabel = createTextLabel("TimeLabel", "00:00", Color3.fromRGB(255, 255, 255), 38)
local sepAfter = createSeparator("SepAfter")
local userLabel = createTextLabel("UserLabel", LocalPlayer.Name, Color3.fromRGB(255, 255, 255), nil)

-- ============================================================
-- MODULE 11: SEPARATOR RGB
-- Mục đích: tạo gradient màu và vùng transparency cho hai dấu |.
-- Offset dọc của gradient sẽ được animation ở module 14.
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
-- MODULE 12: CONTINUOUS TEXT RGB
-- Mục đích: tính màu theo vị trí thật của Time và Username,
-- giúp hai đoạn chữ nhìn như một dải cầu vồng liên tục.
-- ColorSequence chỉ rebuild theo chu kỳ giới hạn, không phải mỗi frame.
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
-- MODULE 13: ANIMATION MATH
-- Mục đích: cung cấp lerp và chu kỳ ping-pong dùng chung cho beam/dấu |.
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
-- MODULE 14: FRAME LOOP
-- Mục đích: cập nhật FPS, RGB chữ, RGB viền và RGB dấu |.
-- Đây là connection RenderStepped chính của watermark.
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
-- MODULE 15: GAME TIME
-- Mục đích: hiển thị thời gian DistributedGameTime dạng phút:giây.
-- Chạy một task riêng mỗi một giây, không chiếm RenderStepped.
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
-- MODULE 16: USERNAME OBSERVER
-- Mục đích: đồng bộ TextLabel nếu thuộc tính Name của LocalPlayer thay đổi.
-- ============================================================
connect(LocalPlayer:GetPropertyChangedSignal("Name"), function()
    if not destroyed then
        userLabel.Text = LocalPlayer.Name
    end
end)

-- ============================================================
-- MODULE 17: DRAG CONTROLLER
-- Mục đích: kéo watermark bằng MouseButton1 hoặc Touch.
-- Cập nhật Position trực tiếp, không tạo Tween ở mỗi input.
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
-- MODULE 18: INITIAL LAYOUT UPDATE
-- Mục đích: chờ AbsoluteSize được Roblox tính xong rồi tạo RGB ban đầu.
-- ============================================================
task.wait(0.2)
if not destroyed and screenGui.Parent then
    updateContinuousTextRGB(0)
end

print("[" .. GUI_NAME .. "] Loaded successfully!")
