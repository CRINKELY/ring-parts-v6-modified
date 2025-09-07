-- Rayfield port of "Super Ring Parts V6 by lukas"
-- Added: live values overlay and collision bookkeeping for parts held by the network.
-- NOTE: Uses exploit-only calls in pcall (sethiddenproperty, getgenv), loadstring http requests. Guarded.

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Play sound helper
local function playSound(soundId)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(soundId)
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function()
        pcall(function() sound:Destroy() end)
    end)
end

pcall(function() playSound("2865227271") end)

----------------------------------------------------------------
-- Config & runtime state
----------------------------------------------------------------
local config = {
    radius = 50,
    height = 100,
    rotationSpeed = 10,
    attractionStrength = 1000,
}

local ringPartsEnabled = false

----------------------------------------------------------------
-- Rayfield setup (graceful fallback if Rayfield fails)
----------------------------------------------------------------
pcall(function() getgenv().SecureMode = true end)
local successRay, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Rayfield/main/source'))()
end)

local Window, MainTab, RingSection, ExtrasSection
if successRay and Rayfield then
    Window = Rayfield:CreateWindow({
        Name = "Super Ring Parts V6 by lukas",
        LoadingTitle = "Super Ring Parts V6",
        LoadingSubtitle = "Rayfield UI",
        ConfigurationSaving = { Enabled = true, FileName = "SuperRingPartsConfig" },
        Discord = { Enabled = false },
    })

    MainTab = Window:CreateTab("Main Controls", 4483362458)
    RingSection = MainTab:CreateSection("Ring Settings")
    ExtrasSection = MainTab:CreateSection("Extras")
else
    warn("Rayfield failed to load — GUI unavailable. Script will still run.")
end

----------------------------------------------------------------
-- Folder, ghost part, and central attachment for AlignPosition
----------------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name = "SuperRingPartsFolder"
folder.Parent = Workspace

local ghostPart = Instance.new("Part")
ghostPart.Name = "__SuperRingGhost"
ghostPart.Parent = folder
ghostPart.Anchored = true
ghostPart.CanCollide = false
ghostPart.Transparency = 1
ghostPart.Size = Vector3.new(1,1,1)

local attachmentCenter = Instance.new("Attachment")
attachmentCenter.Parent = ghostPart

----------------------------------------------------------------
-- Network table (kept in getgenv to be re-usable)
-- Also maintain originalCanCollide bookkeeping table to restore collision on release.
----------------------------------------------------------------
if not getgenv().Network then
    getgenv().Network = { BaseParts = {}, Velocity = Vector3.new(14.46262424, 14.46262424, 14.46262424) }
end

-- weak-key table for storing original CanCollide values (so parts can be GC'd)
local originalCanCollide = setmetatable({}, { __mode = "k" })

-- Helper to check if a part is already in the network list
local function networkContains(part)
    for i, p in ipairs(getgenv().Network.BaseParts) do
        if p == part then return i end
    end
    return nil
end

-- RetainPart: add to network, record original CanCollide, set CanCollide = false
getgenv().Network.RetainPart = function(Part)
    if typeof(Part) ~= "Instance" or not Part:IsA("BasePart") or not Part:IsDescendantOf(Workspace) then
        return
    end

    if Part.Parent == LocalPlayer.Character or Part:IsDescendantOf(LocalPlayer.Character) then
        return
    end

    if networkContains(Part) then
        return
    end

    -- store original CanCollide
    if originalCanCollide[Part] == nil then
        originalCanCollide[Part] = Part.CanCollide
    end

    -- set CanCollide false as requested
    pcall(function() Part.CanCollide = false end)

    -- set some safe physics
    pcall(function() Part.CustomPhysicalProperties = PhysicalProperties.new(0,0,0,0,0) end)

    table.insert(getgenv().Network.BaseParts, Part)
end

-- ReleasePart: restore CanCollide to original and remove from network list
local function ReleasePart(part)
    if not part or typeof(part) ~= "Instance" then return end

    -- remove from Network.BaseParts
    local idx = networkContains(part)
    if idx then
        table.remove(getgenv().Network.BaseParts, idx)
    end

    -- restore original CanCollide if recorded
    local orig = originalCanCollide[part]
    if orig ~= nil then
        pcall(function() part.CanCollide = orig end)
        originalCanCollide[part] = nil
    else
        -- fallback: enable collision if we don't know original
        pcall(function() part.CanCollide = true end)
    end

    -- attempt to clean up Align/Attachments/Torque we added earlier (best-effort)
    pcall(function()
        if part:FindFirstChildOfClass("AlignPosition") then part:FindFirstChildOfClass("AlignPosition"):Destroy() end
        for _, child in pairs(part:GetChildren()) do
            if child:IsA("Attachment") and child ~= attachmentCenter then
                -- if it's our attachment, destroy
                -- (we used to create a unique attachment; we attempt safe cleanup)
                child:Destroy()
            end
            if child:IsA("Torque") then child:Destroy() end
        end
    end)
end

-- A safe housekeeping function to release parts that are gone or no longer desirable in the network
local function CleanNetworkList()
    for i = #getgenv().Network.BaseParts, 1, -1 do
        local p = getgenv().Network.BaseParts[i]
        if not p or not p:IsDescendantOf(game) then
            -- attempt restore (if possible)
            if p then ReleasePart(p) end
            table.remove(getgenv().Network.BaseParts, i)
        end
    end
end

----------------------------------------------------------------
-- Retain/Release helpers used by workspace hooks and UI
----------------------------------------------------------------
local function RetainPartPublic(part)
    pcall(function() getgenv().Network.RetainPart(part) end)
end

local function removePartPublic(part)
    -- if part is in our parts table or network list, release it
    pcall(function() ReleasePart(part) end)
end

----------------------------------------------------------------
-- add/remove tracking lists and workspace hooks (search existing parts)
----------------------------------------------------------------
local parts = {}

local function addPartToList(part)
    -- maintain the "parts" collection (candidates for tornado)
    if not part or typeof(part) ~= "Instance" then return end
    if not part:IsA("BasePart") then return end
    if part:IsDescendantOf(LocalPlayer.Character) then return end

    if not table.find(parts, part) then
        table.insert(parts, part)
    end
end

local function removePartFromList(part)
    if not part then return end
    local idx = table.find(parts, part)
    if idx then
        table.remove(parts, idx)
    end
    -- also release if network held it
    pcall(function() ReleasePart(part) end)
end

-- seed current descendants
for _, p in pairs(Workspace:GetDescendants()) do
    pcall(function() addPartToList(p) end)
end

Workspace.DescendantAdded:Connect(function(d)
    pcall(function() addPartToList(d) end)
end)
Workspace.DescendantRemoving:Connect(function(d)
    pcall(function() removePartFromList(d) end)
end)

----------------------------------------------------------------
-- ForcePart: apply Align/Torque/etc. (keeps previous behavior but avoids enabling collision)
----------------------------------------------------------------
local function ForcePart(v)
    if not v or not v:IsA("Part") then return end
    if not v:IsDescendantOf(Workspace) or v.Anchored then return end
    if v.Parent:FindFirstChild("Humanoid") or v.Parent:FindFirstChild("Head") then return end
    if v.Name == "Handle" then return end

    -- destroy physics objects we don't want
    for _, x in next, v:GetChildren() do
        if x:IsA("BodyAngularVelocity") or x:IsA("BodyForce") or x:IsA("BodyGyro") or x:IsA("BodyPosition")
        or x:IsA("BodyThrust") or x:IsA("BodyVelocity") or x:IsA("RocketPropulsion") then
            pcall(function() x:Destroy() end)
        end
    end

    -- don't automatically change CanCollide here — that will be handled by Network.RetainPart
    pcall(function()
        if v:FindFirstChild("Attachment") then v:FindFirstChild("Attachment"):Destroy() end
        if v:FindFirstChild("AlignPosition") then v:FindFirstChild("AlignPosition"):Destroy() end
        if v:FindFirstChild("Torque") then v:FindFirstChild("Torque"):Destroy() end
    end)

    -- create torque + attachment + align position
    pcall(function()
        local torque = Instance.new("Torque")
        torque.Parent = v
        torque.Torque = Vector3.new(100000, 100000, 100000)

        local attach = Instance.new("Attachment")
        attach.Parent = v

        local align = Instance.new("AlignPosition")
        align.Parent = v
        align.MaxForce = 1e30
        align.MaxVelocity = math.huge
        align.Responsiveness = 200
        align.Attachment0 = attach
        align.Attachment1 = attachmentCenter
    end)
end

----------------------------------------------------------------
-- Heartbeat: main tornado logic and periodic cleaning
----------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    -- cleaning
    CleanNetworkList()

    if not ringPartsEnabled then return end
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    local tornadoCenter = humanoidRootPart.Position

    -- iterate over the candidate list
    for _, part in pairs(parts) do
        if part and part.Parent and not part.Anchored then
            -- compute positions
            local pos = part.Position
            local horizontalDistance = (Vector3.new(pos.X, tornadoCenter.Y, pos.Z) - tornadoCenter).Magnitude
            local angle = math.atan2(pos.Z - tornadoCenter.Z, pos.X - tornadoCenter.X)
            local newAngle = angle + math.rad(config.rotationSpeed)
            local clampedRadius = math.min(config.radius, horizontalDistance)
            local verticalOffset = config.height * (math.abs(math.sin((pos.Y - tornadoCenter.Y) / math.max(1, config.height))))
            local targetPos = Vector3.new(
                tornadoCenter.X + math.cos(newAngle) * clampedRadius,
                tornadoCenter.Y + verticalOffset,
                tornadoCenter.Z + math.sin(newAngle) * clampedRadius
            )

            local dir = targetPos - part.Position
            local mag = dir.Magnitude
            if mag > 0 then
                dir = dir / mag
                -- attraction velocity
                pcall(function()
                    part.Velocity = dir * config.attractionStrength
                end)
            end
        end
    end

    -- also try to apply Align/Torque to all network parts (if you used "Force Retain" button)
    for _, p in pairs(getgenv().Network.BaseParts) do
        pcall(function() ForcePart(p) end)
    end
end)

----------------------------------------------------------------
-- Rayfield GUI controls + Live Values overlay
----------------------------------------------------------------
-- Live values overlay (ScreenGui + TextLabel) — always created (even if Rayfield missing) so user sees live values
local liveGui = Instance.new("ScreenGui")
liveGui.Name = "SuperRingParts_LiveValues"
liveGui.ResetOnSpawn = false
liveGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local liveLabel = Instance.new("TextLabel")
liveLabel.Size = UDim2.new(0, 300, 0, 120)
liveLabel.Position = UDim2.new(0, 10, 0, 10)
liveLabel.BackgroundTransparency = 0.35
liveLabel.BackgroundColor3 = Color3.fromRGB(0,0,0)
liveLabel.TextColor3 = Color3.fromRGB(255,255,255)
liveLabel.TextWrapped = true
liveLabel.TextXAlignment = Enum.TextXAlignment.Left
liveLabel.TextYAlignment = Enum.TextYAlignment.Top
liveLabel.Font = Enum.Font.SourceSans
liveLabel.TextSize = 14
liveLabel.BorderSizePixel = 0
liveLabel.Parent = liveGui

-- update liveLabel every heartbeat (lightweight)
RunService.Heartbeat:Connect(function()
    local heldCount = 0
    for _, p in pairs(getgenv().Network.BaseParts) do
        if p and p:IsDescendantOf(game) then heldCount = heldCount + 1 end
    end
    local s = ("Ring: %s\nRadius: %.1f\nHeight: %.1f\nRotation: %.1f\nAttraction: %.1f\nHeldParts: %d")
    liveLabel.Text = string.format(s,
        tostring(ringPartsEnabled and "On" or "Off"),
        config.radius,
        config.height,
        config.rotationSpeed,
        config.attractionStrength,
        heldCount
    )
end)

-- Rayfield controls (if available)
if successRay and Rayfield and RingSection and ExtrasSection then
    -- Tornado toggle
    RingSection:CreateToggle({
        Name = "Tornado (Ring) On/Off",
        CurrentValue = ringPartsEnabled,
        Flag = "TornadoEnabled",
        Callback = function(value)
            ringPartsEnabled = value
            playSound("12221967")
        end,
    })

    -- Sliders for config values
    RingSection:CreateSlider({
        Name = "Radius",
        Range = {0, 2000},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = config.radius,
        Flag = "RadiusValue",
        Callback = function(v) config.radius = v end,
    })

    RingSection:CreateSlider({
        Name = "Height",
        Range = {0, 1000},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = config.height,
        Flag = "HeightValue",
        Callback = function(v) config.height = v end,
    })

    RingSection:CreateSlider({
        Name = "Rotation Speed",
        Range = {0, 360},
        Increment = 1,
        Suffix = "°",
        CurrentValue = config.rotationSpeed,
        Flag = "RotationSpeedValue",
        Callback = function(v) config.rotationSpeed = v end,
    })

    RingSection:CreateSlider({
        Name = "Attraction Strength",
        Range = {0, 50000},
        Increment = 10,
        Suffix = "",
        CurrentValue = config.attractionStrength,
        Flag = "AttractionStrengthValue",
        Callback = function(v) config.attractionStrength = v end,
    })

    -- Button to retain all visible parts (retains and sets CanCollide = false)
    RingSection:CreateButton({
        Name = "Retain Current Workspace Parts",
        Callback = function()
            local count = 0
            for _, p in pairs(Workspace:GetDescendants()) do
                pcall(function()
                    if p and p:IsA("BasePart") and not p:IsDescendantOf(LocalPlayer.Character) then
                        getgenv().Network.RetainPart(p)
                        count = count + 1
                    end
                end)
            end
            Rayfield:Notify({Title = "Retain", Content = "Retained "..tostring(count).." parts.", Duration = 4})
            playSound("12221967")
        end,
    })

    -- Force/Align all networked parts button
    ExtrasSection:CreateButton({
        Name = "Force Retain All and Align",
        Callback = function()
            local c = 0
            for _, p in pairs(Workspace:GetDescendants()) do
                pcall(function()
                    if p and p:IsA("BasePart") and not p:IsDescendantOf(LocalPlayer.Character) then
                        getgenv().Network.RetainPart(p)
                        ForcePart(p)
                        c = c + 1
                    end
                end)
            end
            Rayfield:Notify({Title = "Force Retain", Content = "Processed "..tostring(c).." parts.", Duration = 4})
        end,
    })

    -- Release all currently held parts (restore collisions)
    ExtrasSection:CreateButton({
        Name = "Release All Network Parts",
        Callback = function()
            local cnt = 0
            for i = #getgenv().Network.BaseParts, 1, -1 do
                local p = getgenv().Network.BaseParts[i]
                if p then
                    ReleasePart(p)
                    cnt = cnt + 1
                end
            end
            Rayfield:Notify({Title = "Release", Content = "Released "..tostring(cnt).." parts.", Duration = 4})
        end,
    })

    -- Extras: loads (kept from original), wrapped in pcall
    ExtrasSection:CreateButton({ Name = "Fly GUI", Callback = function() pcall(function() loadstring(game:HttpGet('https://pastebin.com/raw/YSL3xKYU'))() end) end })
    ExtrasSection:CreateButton({ Name = "Infinite Yield", Callback = function() pcall(function() loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))() end) end })
    ExtrasSection:CreateButton({ Name = "Nameless Admin", Callback = function() pcall(function() loadstring(game:HttpGet("https://scriptblox.com/raw/Universal-Script-Nameless-Admin-FE-11243"))() end) end })
    ExtrasSection:CreateButton({ Name = "FPS", Callback = function() pcall(function() loadstring(game:HttpGet("https://pastebin.com/raw/ySHJdZpb",true))() end) end })

    -- No fall damage (best-effort)
    ExtrasSection:CreateButton({
        Name = "No Fall Damage",
        Callback = function()
            pcall(function()
                local lp = Players.LocalPlayer
                local function applyNoFall(chr)
                    local root = chr:FindFirstChild("HumanoidRootPart")
                    if not root then return end
                    local con
                    con = RunService.Heartbeat:Connect(function()
                        if not root.Parent then con:Disconnect() return end
                        local oldvel = root.AssemblyLinearVelocity
                        root.AssemblyLinearVelocity = Vector3.new(0,0,0)
                        RunService.RenderStepped:Wait()
                        pcall(function() root.AssemblyLinearVelocity = oldvel end)
                    end)
                end
                if lp.Character then applyNoFall(lp.Character) end
                lp.CharacterAdded:Connect(applyNoFall)
            end)
            Rayfield:Notify({Title = "No Fall Damage", Content = "Applied no-fall-damage filter.", Duration = 4})
        end,
    })

    -- Noclip toggle
    local noclipConn
    ExtrasSection:CreateToggle({
        Name = "Noclip",
        CurrentValue = false,
        Flag = "NoclipToggle",
        Callback = function(v)
            if v then
                noclipConn = RunService.Stepped:Connect(function()
                    local chr = LocalPlayer.Character
                    if not chr then return end
                    for _, part in pairs(chr:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            pcall(function() part.CanCollide = false end)
                        end
                    end
                end)
                Rayfield:Notify({Title = "Noclip", Content = "Noclip enabled.", Duration = 3})
            else
                if noclipConn then noclipConn:Disconnect() noclipConn = nil end
                Rayfield:Notify({Title = "Noclip", Content = "Noclip disabled.", Duration = 3})
            end
        end,
    })

    -- Infinite Jump toggle
    local infiniteJump = false
    ExtrasSection:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = infiniteJump,
        Flag = "InfJumpToggle",
        Callback = function(v)
            infiniteJump = v
            Rayfield:Notify({Title = "Infinite Jump", Content = infiniteJump and "Enabled" or "Disabled", Duration = 3})
        end,
    })

    UserInputService.JumpRequest:Connect(function()
        if infiniteJump then
            local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end) end
        end
    end)

    -- try load saved config on start
    pcall(function() Rayfield:LoadConfiguration() end)
end

----------------------------------------------------------------
-- DescendantRemoving hook: if we lose a part from workspace, ensure release & cleanup
----------------------------------------------------------------
Workspace.DescendantRemoving:Connect(function(desc)
    pcall(function()
        -- if part was in our network list, release and restore
        ReleasePart(desc)
        -- also remove from our parts list
        removePartFromList(desc)
    end)
end)

----------------------------------------------------------------
-- Periodic housekeeping (smaller interval) to ensure released parts restored if manually removed from network
----------------------------------------------------------------
task.spawn(function()
    while true do
        -- iterate network list and ensure any part not owned remains updated
        for i = #getgenv().Network.BaseParts, 1, -1 do
            local p = getgenv().Network.BaseParts[i]
            if not p or not p:IsDescendantOf(game) then
                if p then ReleasePart(p) end
                table.remove(getgenv().Network.BaseParts, i)
            else
                -- ensure parts held by network keep CanCollide false
                if p and p.CanCollide ~= false then
                    pcall(function() p.CanCollide = false end)
                end
            end
        end
        task.wait(2)
    end
end)

----------------------------------------------------------------
-- StarterGui notifications like original
----------------------------------------------------------------
StarterGui:SetCore("SendNotification", { Title = "Hey", Text = "Enjoy the Script!", Duration = 5 })
StarterGui:SetCore("SendNotification", { Title = "TIPS", Text = "Adjust sliders to change ring behavior", Duration = 5 })
StarterGui:SetCore("SendNotification", { Title = "Credits", Text = "On scriptblox!", Duration = 5 })

print("[SuperRingParts] Rayfield UI initialized with live values and collision bookkeeping.")
