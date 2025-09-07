-- Rayfield version of Super Ring Parts by lukas — integrated live values & collision control
-- Requires exploit environment (e.g. sethiddenproperty) — safely wrapped in pcall.

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Play sound helper
local function playSound(soundId)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. tostring(soundId)
    s.Parent = SoundService
    s:Play()
    s.Ended:Connect(function()
        pcall(function() s:Destroy() end)
    end)
end

pcall(function() playSound("2865227271") end)

-- Config and state
local config = { radius = 50, height = 100, rotationSpeed = 10, attractionStrength = 1000 }
local ringEnabled = false

-- Load Rayfield UI
pcall(function() getgenv().SecureMode = true end)
local ok, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Rayfield/main/source'))()
end)
if not ok or not Rayfield then
    warn("Rayfield failed to load. UI disabled.")
end

-- Setup Rayfield window if available
local Window, TabMain, SectionRing, SectionExtras
if Rayfield then
    Window = Rayfield:CreateWindow({
        Name = "Super Ring Parts V6 by lukas",
        LoadingTitle = "Super Ring Parts",
        LoadingSubtitle = "powered by Rayfield",
        ConfigurationSaving = { Enabled = true, FileName = "SuperRingPartsConfig" },
        Discord = { Enabled = false },
    })
    TabMain = Window:CreateTab("Main Controls", 4483362458)
    SectionRing = TabMain:CreateSection("Ring Settings")
    SectionExtras = TabMain:CreateSection("Extras")
end

-- Create ghost part for alignment
local folder = Instance.new("Folder", Workspace); folder.Name = "SRPFolder"
local ghost = Instance.new("Part", folder)
ghost.Name = "GhostPart"
ghost.Anchored = true; ghost.CanCollide = false; ghost.Transparency = 1
local ghostAttach = Instance.new("Attachment", ghost)

-- Network and collision tracking
if not getgenv().Network then getgenv().Network = { BaseParts = {}, Velocity = Vector3.new(14.46,14.46,14.46) } end
local origCollision = setmetatable({}, { __mode = "k" })

local function retainPart(p)
    if not p or not p:IsA("BasePart") then return end
    if origCollision[p] == nil then origCollision[p] = p.CanCollide end
    p.CanCollide = false
    p.CustomPhysicalProperties = PhysicalProperties.new(0,0,0,0,0)
    table.insert(getgenv().Network.BaseParts, p)
end

local function releasePart(p)
    local idx = table.find(getgenv().Network.BaseParts, p)
    if idx then table.remove(getgenv().Network.BaseParts, idx) end
    if origCollision[p] ~= nil then p.CanCollide = origCollision[p]; origCollision[p] = nil
    else p.CanCollide = true end
    -- cleanup attachments/torque (best effort)
    for _, c in pairs(p:GetChildren()) do
        if c:IsA("AlignPosition") or c:IsA("Torque") or c:IsA("Attachment") then
            pcall(function() c:Destroy() end)
        end
    end
end

-- Manage parts list for tornado
local parts = {}
local function addCandidate(p) if p:IsA("BasePart") and not p:IsDescendantOf(LocalPlayer.Character) then table.insert(parts, p) end end
local function remCandidate(p) releasePart(p); parts = table.filter(parts, function(x) return x ~= p end) end

workspace.DescendantAdded:Connect(addCandidate)
workspace.DescendantRemoving:Connect(remCandidate)
for _, p in pairs(workspace:GetDescendants()) do addCandidate(p) end

-- Apply tornado effect
RunService.Heartbeat:Connect(function()
    if not ringEnabled then return end
    local hrp = (LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()):FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local center = hrp.Position
    for _, p in ipairs(parts) do
        if p.Parent and not p.Anchored then
            local pos = p.Position
            local dist = (Vector3.new(pos.X, center.Y, pos.Z) - center).Magnitude
            local angle = math.atan2(pos.Z - center.Z, pos.X - center.X)
            local newAngle = angle + math.rad(config.rotationSpeed)
            local r = math.min(config.radius, dist)
            local yOff = config.height * math.abs(math.sin((pos.Y - center.Y) / math.max(1, config.height)))
            local target = Vector3.new(center.X + r * math.cos(newAngle), center.Y + yOff, center.Z + r * math.sin(newAngle))
            local dir = (target - pos).Unit
            p.Velocity = dir * config.attractionStrength
        end
    end

    -- enforce Align/Torque for retained parts
    for _, p in ipairs(getgenv().Network.BaseParts) do
        pcall(function()
            if not p:FindFirstChildOfClass("Torque") then
                local t = Instance.new("Torque", p); t.Torque = Vector3.new(1e5,1e5,1e5)
                local a = Instance.new("Attachment", p)
                local ap = Instance.new("AlignPosition", p)
                ap.Attachment0 = a; ap.Attachment1 = ghostAttach
                ap.MaxForce = 1e30; ap.MaxVelocity = math.huge; ap.Responsiveness = 200
            end
            if p.CanCollide ~= false then p.CanCollide = false end
        end)
    end
end)

-- Live values label in Rayfield UI
local liveLabel
if Rayfield then
    liveLabel = SectionRing:CreateLabel("Live Values")
    RunService.Heartbeat:Connect(function()
        local held = #getgenv().Network.BaseParts
        local txt = string.format("Ring: %s | Held: %d\nRadius: %.1f | Height: %.1f\nSpeed: %.1f° | Attract: %.1f",
            ringEnabled and "On" or "Off", held,
            config.radius, config.height, config.rotationSpeed, config.attractionStrength
        )
        liveLabel:Set(txt)
    end)
end

-- Rayfield controls
if Rayfield then
    SectionRing:CreateToggle({
        Name = "Tornado On/Off", CurrentValue = ringEnabled, Flag = "RingToggle",
        Callback = function(v) ringEnabled = v; playSound("12221967") end
    })
    SectionRing:CreateSlider({
        Name = "Radius", Range = {0,2000}, Increment = 1, Suffix = "studs", CurrentValue = config.radius, Flag = "RadiusSlider",
        Callback = function(v) config.radius = v end
    })
    SectionRing:CreateSlider({
        Name = "Height", Range = {0,1000}, Increment = 1, Suffix = "studs", CurrentValue = config.height, Flag = "HeightSlider",
        Callback = function(v) config.height = v end
    })
    SectionRing:CreateSlider({
        Name = "Rotation Speed", Range = {0,360}, Increment = 1, Suffix = "°", CurrentValue = config.rotationSpeed, Flag = "SpeedSlider",
        Callback = function(v) config.rotationSpeed = v end
    })
    SectionRing:CreateSlider({
        Name = "Attraction Strength", Range = {0,50000}, Increment = 10, CurrentValue = config.attractionStrength, Flag = "AttractSlider",
        Callback = function(v) config.attractionStrength = v end
    })
    SectionRing:CreateButton({
        Name = "Retain All Parts",
        Callback = function()
            local count = 0
            for _, p in pairs(workspace:GetDescendants()) do
                if p:IsA("BasePart") and not p:IsDescendantOf(LocalPlayer.Character) then
                    retainPart(p); count = count + 1
                end
            end
            Rayfield:Notify({Title = "Retained", Content = count.." parts", Duration = 4})
            playSound("12221967")
        end
    })
    SectionExtras:CreateButton({
        Name = "Release All Parts",
        Callback = function()
            local cnt = #getgenv().Network.BaseParts
            for _, p in ipairs({table.unpack(getgenv().Network.BaseParts)}) do releasePart(p) end
            Rayfield:Notify({Title = "Released", Content = cnt.." parts", Duration = 4})
        end
    })
    -- Extras: Fly, InfJump, etc.
    SectionExtras:CreateButton({ Name = "Fly GUI", Callback = function() pcall(function() loadstring(game:HttpGet('https://pastebin.com/raw/YSL3xKYU'))() end) end })
    SectionExtras:CreateToggle({
        Name = "Infinite Jump", CurrentValue = false, Flag = "InfJump",
        Callback = function(v) _G.InfJump = v end
    })
    UserInputService.JumpRequest:Connect(function() if _G.InfJump then local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid"); if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end end end)
    SectionExtras:CreateToggle({
        Name = "Noclip", CurrentValue = false, Flag = "NoclipToggle",
        Callback = function(v)
            if v then
                noclipConn = RunService.Stepped:Connect(function()
                    local chr = LocalPlayer.Character
                    if chr then
                        for _, part in pairs(chr:GetDescendants()) do
                            if part:IsA("BasePart") then pcall(function() part.CanCollide = false end) end
                        end
                    end
                end)
                Rayfield:Notify({Title = "Noclip", Content = "Enabled", Duration = 3})
            else
                if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
                Rayfield:Notify({Title = "Noclip", Content = "Disabled", Duration = 3})
            end
        end
    })
    SectionExtras:CreateButton({ Name = "Infinite Yield", Callback = function() pcall(function() loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))() end) end })
    SectionExtras:CreateButton({ Name = "Nameless Admin", Callback = function() pcall(function() loadstring(game:HttpGet("https://scriptblox.com/raw/Universal-Script-Nameless-Admin-FE-11243"))() end) end })
    SectionExtras:CreateButton({ Name = "FPS Script", Callback = function() pcall(function() loadstring(game:HttpGet("https://pastebin.com/raw/ySHJdZpb",true))() end) end })
    pcall(function() Rayfield:LoadConfiguration() end)
end

-- Notifications
StarterGui:SetCore("SendNotification", {Title = "Hey", Text = "Enjoy the Script!", Duration = 5})
StarterGui:SetCore("SendNotification", {Title = "TIPS", Text = "Use sliders/toggles to control ring", Duration = 5})
StarterGui:SetCore("SendNotification", {Title = "Credits", Text = "On scriptblox!", Duration = 5})

print("[SuperRingParts] Rayfield UI ready with live values and collision control.")
