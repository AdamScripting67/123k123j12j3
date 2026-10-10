for _, v in pairs(getgc(true)) do
    if type(v) == "table" and pcall(function() return rawget(v, "indexInstance") end) then
        local index_inst = rawget(v, "indexInstance")
        if type(index_inst) == "table" and #index_inst >= 2 and type(index_inst[2]) == "function" then
            local name = index_inst[1]
            if type(name) == "string" and name == "kick" then
                hookfunction(index_inst[2], function(...) return false end)
            end
        end
    end
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/AdamScripting67/cb/refs/heads/main/Colorbot%20Panel.lua"))()

Library.Folders = {
    Directory = "Elytra",
    Configs   = "Elytra/Configs",
    Assets    = "Elytrahub/Assets",
}
for _, Value in pairs(Library.Folders) do
    if not isfolder(Value) then makefolder(Value) end
end

-- ============================================================
-- Services & shared state
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera
local Mouse            = LocalPlayer:GetMouse()

local VIM = pcall(game.GetService, game, "VirtualInputManager")
    and game:FindService("VirtualInputManager") or nil

local function tween(obj, time, props)
    if not obj or not obj.Parent then return end
    TweenService:Create(obj,
        TweenInfo.new(time or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props):Play()
end

local MouseLock = {
    Enabled = false, Prediction = 0,
    AimPart = "Head", Smoothness = 0.2, Deadzone = 3,
    FOV = 180, VisibleFOV = false, Sticky = true,
    CircleColor = Color3.fromRGB(255, 255, 255),
}
local Triggerbot = {
    Enabled = false, Delay = 0, Release = 0,
    Blacklist = {"knife"},
    DefaultRange = math.huge,
    GunRanges = {
        ["[Revolver]"]         = 245,
        ["[Double-Barrel SG]"] = 49,
        ["[TacticalShotgun]"]  = 49,
    },
}
local GunMacro = {
    Enabled = false, Delay = 0.005, ClickHold = 0.008, Active = false,
    Tools = {"[Double-Barrel SG]", "[TacticalShotgun]"},
    MaxRange = 49,
}
local HostDetection = {
    Enabled = false,
    DelayMs = 50,
    TargetPlayer = nil,
    ToolName = "[Double-Barrel SG]",
    WatchAmmoName = "Ammo",
}
local hostReady = false

local ESP = {
    Enabled = false, Name_ESP = true, Box_ESP = true,
    Health_ESP = true, Armor_ESP = true, Distance_ESP = true,
    VisibleCheck = false, Distance = 1000,
    Font = "Tahoma",
    NameSize = 14, DistanceSize = 14, HealthSize = 12, ArmorSize = 12,
    NameColor     = Color3.fromRGB(255, 255, 255),
    BoxColor      = Color3.fromRGB(255, 255, 255),
    HealthColor   = Color3.fromRGB(0, 255, 0),
    ArmorColor    = Color3.fromRGB(0, 150, 255),
    DistanceColor = Color3.fromRGB(255, 255, 255),
    VisibleColor  = Color3.fromRGB(0, 255, 0),
    HiddenColor   = Color3.fromRGB(255, 0, 0),
}
local WalkSpeed = { Enabled = false, Value = 16, Default = 16 }
local JumpPower = { Enabled = false, Value = 50, Default = 50 }
local SilentAim = { Enabled=false, Fov=100, DrawFOV=true, UseFOV=true, Prediction=0 }
local GunNoclip = { Enabled=false, Delay=0.05, Active=false }

-- FONT MAPPING
local function safeFont(name)
    local ok, f = pcall(function() return Enum.Font[name] end)
    return ok and f or Enum.Font.SourceSans
end
local FONT_MAP = {
    ["Tahoma"]      = { enum = safeFont("SourceSans"),      drawing = 0 },
    ["Arial"]       = { enum = safeFont("Arial"),           drawing = 1 },
    ["Verdana"]     = { enum = safeFont("SourceSans"),      drawing = 0 },
    ["Segoe UI"]    = { enum = safeFont("Gotham"),          drawing = 0 },
    ["Roboto"]      = { enum = safeFont("Roboto"),          drawing = 0 },
    ["Consolas"]    = { enum = safeFont("Code"),            drawing = 3 },
    ["Courier New"] = { enum = safeFont("Code"),            drawing = 3 },
    ["Small Fonts"] = { enum = safeFont("SourceSansLight"), drawing = 0 },
    ["Calibri"]     = { enum = safeFont("SourceSans"),      drawing = 0 },
    ["Inter"]       = { enum = safeFont("Gotham"),          drawing = 0 },
    ["ProggyClean"] = { enum = safeFont("Code"),            drawing = 3 },
    ["Pixel"]       = { enum = safeFont("Arcade"),          drawing = 0 },
}
local FONT_OPTIONS = {"Tahoma","Arial","Verdana","Segoe UI","Roboto","Consolas","Courier New","Small Fonts","Calibri","Inter","ProggyClean","Pixel"}
local function getFontPair()
    local m = FONT_MAP[ESP.Font] or FONT_MAP["Tahoma"]
    return m.enum, m.drawing
end

-- SHARED STATE
local CurrentTarget  = nil
local Whitelisted, AimViewTarget, SpectateTarget = {}, nil, nil
local namePool, boxPool, hpPool, armorPool, distPool = {}, {}, {}, {}, {}
local armorRef, charCache = {}, {}
local playerList, playerSet, playerCount = {}, {}, 0
local hookColorAmmo, clearColorConnections

local FOVCircle
pcall(function()
    local c = Drawing.new("Circle")
    if c then
        FOVCircle = c
        c.Thickness, c.NumSides, c.Radius = 1, 64, MouseLock.FOV
        c.Filled, c.Visible, c.Color, c.Transparency = false, false, MouseLock.CircleColor, 1
        c.Position = Vector2.new(0, 0)
    end
end)

local SA_FOVCircle
pcall(function()
    local c = Drawing.new("Circle")
    if c then
        SA_FOVCircle = c
        c.Thickness, c.NumSides, c.Radius = 1, 64, SilentAim.Fov
        c.Filled, c.Visible, c.Color, c.Transparency = false, false, Color3.fromRGB(255,255,255), 0.8
        c.Position = Vector2.new(0, 0)
    end
end)

local GameName = "Unknown Game"
pcall(function()
    GameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
end)

local function buildWindowTitle()
    return string.format("Elytra | Closet | %s | %s", GameName, os.date("%b %d %Y | %H:%M"))
end

local Window = Library:Window({
    Name = buildWindowTitle(),
    Logo = "90363697817722"
})
local Watermark = Library:Watermark("Elytra")
local KeybindList  = Library:KeybindList()

-- Auto-update the window title's time every 15 seconds
task.spawn(function()
    local CoreGui = game:GetService("CoreGui")
    local cachedLabel = nil

    local function looksLikeTitleLabel(d)
        if not d:IsA("TextLabel") then return false end
        local t = d.Text
        if type(t) ~= "string" then return false end
        return t:find("Elytra", 1, true) ~= nil and t:find("Closet", 1, true) ~= nil
    end

    local function scanForTitleLabel()
        if cachedLabel and cachedLabel.Parent then
            return cachedLabel
        end
        local ok, result = pcall(function()
            for _, d in ipairs(CoreGui:GetDescendants()) do
                if looksLikeTitleLabel(d) then return d end
            end
            return nil
        end)
        if ok and result then
            cachedLabel = result
            return result
        end
        local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            local ok2, result2 = pcall(function()
                for _, d in ipairs(pg:GetDescendants()) do
                    if looksLikeTitleLabel(d) then return d end
                end
                return nil
            end)
            if ok2 and result2 then
                cachedLabel = result2
                return result2
            end
        end
        return nil
    end

    task.wait(1)
    while true do
        local label = scanForTitleLabel()
        if label then
            local ok = pcall(function() label.Text = buildWindowTitle() end)
            if not ok then cachedLabel = nil end
        end
        task.wait(15)
    end
end)

local CombatPage   = Window:Page({Name = "Combat",  Columns = 2})
local VisualsPage  = Window:Page({Name = "Visuals", Columns = 2})
local MiscPage     = Window:Page({Name = "Misc",    Columns = 2})
local PlayersPage  = Window:Page({Name = "Players", Columns = 2})
local SettingsPage = Library:CreateSettingsPage(Window, KeybindList, Watermark)

local AimbotSection   = CombatPage:Section({Name = "Aimbot",       Side = 1})
local SilentAimSection= CombatPage:Section({Name = "Silent Aim",   Side = 2})
local TriggerSection  = CombatPage:Section({Name = "Triggerbot",   Side = 2})

local ESPSection      = VisualsPage:Section({Name = "ESP",         Side = 1})
local TextSection     = VisualsPage:Section({Name = "ESP Text",    Side = 2})

local GunNoclipSection= MiscPage:Section({Name = "Gun Noclip",     Side = 1})
local AutoEatSection  = MiscPage:Section({Name = "Auto Eat",       Side = 2})
local MovementSection = MiscPage:Section({Name = "Movement",       Side = 1})
local MacroSection    = MiscPage:Section({Name = "Gun Macro",      Side = 2})

local PlayerListSec   = PlayersPage:Section({Name = "Players",     Side = 1})

-- HELPERS
local function normalizeKey(v)
    if type(v) == "string" then return v end
    if type(v) == "userdata" and typeof(v) == "EnumItem" then
        return v.Name or tostring(v):match("(%w+)$")
    end
    return tostring(v)
end

local function setAimbotState(v)
    MouseLock.Enabled = v and true or false
    if not MouseLock.Enabled then CurrentTarget = nil end
end

-- ============================================================
-- AIMBOT UI
-- ============================================================
local aimMasterOn = false
AimbotSection:Toggle({
    Name = "Enabled", Flag = "aim_enabled", Default = false,
    Callback = function(state)
        aimMasterOn = state and true or false
        setAimbotState(state)
    end,
}):Keybind({
    Flag = "aim_key", Default = Enum.KeyCode.E, Mode = "Toggle",
    Callback = function(v)
        if not aimMasterOn then return end
        if type(v) == "boolean" then setAimbotState(v) end
    end,
})
AimbotSection:Slider({
    Name = "FOV", Flag = "aim_fov", Min = 0, Max = 1000, Default = 180, Decimals = 1,
    Callback = function(v) MouseLock.FOV = v end,
})
AimbotSection:Slider({
    Name = "Smoothness", Flag = "aim_smooth", Min = 1, Max = 100, Default = 20, Decimals = 1,
    Callback = function(v) MouseLock.Smoothness = v / 100 end,
})
AimbotSection:Slider({
    Name = "Prediction", Flag = "aim_prediction", Min = 0, Max = 50, Default = 0, Decimals = 1,
    Callback = function(v) MouseLock.Prediction = v / 100 end,
})
AimbotSection:Slider({
    Name = "Deadzone", Flag = "aim_deadzone", Min = 0, Max = 50, Default = 3, Decimals = 1,
    Callback = function(v) MouseLock.Deadzone = v end,
})
AimbotSection:Dropdown({
    Name = "Aim Part", Flag = "aim_part",
    Items = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso"},
    Default = "Head",
    Callback = function(v) MouseLock.AimPart = v end,
})
AimbotSection:Toggle({
    Name = "Visible FOV", Flag = "aim_visible_fov", Default = false,
    Callback = function(v) MouseLock.VisibleFOV = v end,
})
AimbotSection:Toggle({
    Name = "Sticky", Flag = "aim_sticky", Default = true,
    Callback = function(v) MouseLock.Sticky = v end,
})

-- ============================================================
-- SILENT AIM UI
-- ============================================================
SilentAimSection:Toggle({
    Name = "Enabled", Flag = "sa_enabled", Default = false,
    Callback = function(v)
        local RS = game:GetService("ReplicatedStorage")
        local mainRemotes = RS:FindFirstChild("MainRemotes")
        local gunEvent    = mainRemotes and mainRemotes:FindFirstChild("MainRemoteEvent")
        if gunEvent then
            if v then gunEvent:FireServer("ChangeSettings", "GunSystem", "Old")
            else        gunEvent:FireServer("ChangeSettings", "GunSystem", "New") end
        end
        SilentAim.Enabled = v and true or false
    end,
})
SilentAimSection:Slider({
    Name = "FOV", Flag = "sa_fov", Min = 0, Max = 1000, Default = 100, Decimals = 1,
    Callback = function(v) SilentAim.Fov = v end,
})
SilentAimSection:Toggle({
    Name = "Draw FOV", Flag = "sa_drawfov", Default = true,
    Callback = function(v) SilentAim.DrawFOV = v and true or false end,
})
SilentAimSection:Toggle({
    Name = "Use FOV", Flag = "sa_usefov", Default = true,
    Callback = function(v) SilentAim.UseFOV = v and true or false end,
})
SilentAimSection:Slider({
    Name = "Prediction", Flag = "sa_prediction", Min = 0, Max = 50, Default = 0, Decimals = 1,
    Callback = function(v) SilentAim.Prediction = v / 100 end,
})

-- ============================================================
-- HOST DETECTION — helpers
-- ============================================================
local function buildColorTargetOptions()
    local names = {"None"}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(names, p.Name) end
    end
    table.sort(names, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a < b
    end)
    return names
end

-- ============================================================
-- TRIGGERBOT UI (with integrated Host Detection)
-- ============================================================
local trigMasterOn = false
TriggerSection:Toggle({
    Name = "Enabled", Flag = "trig_enabled", Default = false,
    Callback = function(state)
        trigMasterOn = state and true or false
        Triggerbot.Enabled = state and true or false
        if not state then hostReady = false end
    end,
}):Keybind({
    Flag = "trig_key", Default = Enum.KeyCode.Z, Mode = "Hold",
    Callback = function(v)
        if not trigMasterOn then return end
        if type(v) == "boolean" then
            Triggerbot.Enabled = v
            if not v then hostReady = false end
        end
    end,
})
TriggerSection:Slider({
    Name = "Delay", Flag = "trig_delay", Min = 0, Max = 1000, Default = 0, Decimals = 1, Suffix = "ms",
    Callback = function(v) Triggerbot.Delay = v / 1000 end,
})
TriggerSection:Slider({
    Name = "Release", Flag = "trig_release", Min = 0, Max = 1000, Default = 0, Decimals = 1, Suffix = "ms",
    Callback = function(v) Triggerbot.Release = v / 1000 end,
})

local hostDetectEnabled = false
local HostPlayerDropdown
local HostDelaySlider

local function setElVisible(el, v)
    if not el then return end
    pcall(function() if el.Visible ~= nil then el.Visible = v end end)
    pcall(function() if el.Container and el.Container.Visible ~= nil then el.Container.Visible = v end end)
    pcall(function() if el.Frame and el.Frame.Visible ~= nil then el.Frame.Visible = v end end)
    pcall(function() if el.Object and el.Object.Visible ~= nil then el.Object.Visible = v end end)
    pcall(function() if el.Instance and el.Instance.Visible ~= nil then el.Instance.Visible = v end end)
    pcall(function() if el.Holder and el.Holder.Visible ~= nil then el.Holder.Visible = v end end)
    pcall(function() if el.Main and el.Main.Visible ~= nil then el.Main.Visible = v end end)
end

TriggerSection:Toggle({
    Name = "Host Detection", Flag = "trig_hostdetect", Default = false,
    Callback = function(state)
        hostDetectEnabled = state and true or false
        HostDetection.Enabled = hostDetectEnabled
        hostReady = false
        if hostDetectEnabled then
            if HostDetection.TargetPlayer then hookColorAmmo(HostDetection.TargetPlayer) end
        else
            clearColorConnections()
        end
        setElVisible(HostPlayerDropdown, hostDetectEnabled)
        setElVisible(HostDelaySlider,    hostDetectEnabled)
    end,
})

HostPlayerDropdown = TriggerSection:Dropdown({
    Name = "Host Player", Flag = "trig_host",
    Items = buildColorTargetOptions(), Default = "None",
    Callback = function(v)
        if v == nil or v == "" or v == "None" then
            HostDetection.TargetPlayer = nil
            clearColorConnections()
        else
            HostDetection.TargetPlayer = Players:FindFirstChild(v)
            if hostDetectEnabled and HostDetection.TargetPlayer then
                hookColorAmmo(HostDetection.TargetPlayer)
            end
        end
    end,
})

HostDelaySlider = TriggerSection:Slider({
    Name = "Host Delay", Flag = "trig_hostdelay",
    Min = 0, Max = 1000, Default = 50, Decimals = 1, Suffix = "ms",
    Callback = function(v) HostDetection.DelayMs = v end,
})

task.defer(function()
    task.wait(0.2)
    setElVisible(HostPlayerDropdown, false)
    setElVisible(HostDelaySlider,    false)
end)

-- ============================================================
-- GUN MACRO UI
-- ============================================================
local macroMasterOn = false
MacroSection:Toggle({
    Name = "Enabled", Flag = "macro_enabled", Default = false,
    Callback = function(state)
        macroMasterOn = state and true or false
        GunMacro.Enabled = state and true or false
        if not state then GunMacro.Active = false end
    end,
}):Keybind({
    Flag = "macro_key", Default = Enum.KeyCode.F, Mode = "Hold",
    Callback = function(v)
        if not macroMasterOn then return end
        if type(v) == "boolean" then
            GunMacro.Enabled = v
            if not v then GunMacro.Active = false end
        end
    end,
})
MacroSection:Slider({
    Name = "Delay", Flag = "macro_delay", Min = 0, Max = 500, Default = 5, Decimals = 1, Suffix = "ms",
    Callback = function(v) GunMacro.Delay = v / 1000 end,
})
MacroSection:Slider({
    Name = "Click Hold", Flag = "macro_click_hold", Min = 1, Max = 200, Default = 8, Decimals = 1, Suffix = "ms",
    Callback = function(v) GunMacro.ClickHold = v / 1000 end,
})

-- ============================================================
-- ESP UI
-- ============================================================
ESPSection:Toggle({
    Name = "Enabled", Flag = "esp_enabled", Default = false,
    Callback = function(v) ESP.Enabled = v end,
})
ESPSection:Toggle({
    Name = "Name", Flag = "esp_name", Default = true,
    Callback = function(v) ESP.Name_ESP = v end,
}):Colorpicker({
    Flag = "esp_name_color", Default = Color3.fromRGB(255, 255, 255),
    Callback = function(c) ESP.NameColor = c end,
})
ESPSection:Toggle({
    Name = "Box", Flag = "esp_box", Default = true,
    Callback = function(v) ESP.Box_ESP = v end,
}):Colorpicker({
    Flag = "esp_box_color", Default = Color3.fromRGB(255, 255, 255),
    Callback = function(c) ESP.BoxColor = c end,
})
ESPSection:Toggle({
    Name = "Health", Flag = "esp_health", Default = true,
    Callback = function(v) ESP.Health_ESP = v end,
}):Colorpicker({
    Flag = "esp_hp_color", Default = Color3.fromRGB(0, 255, 0),
    Callback = function(c) ESP.HealthColor = c end,
})
ESPSection:Toggle({
    Name = "Armor", Flag = "esp_armor", Default = true,
    Callback = function(v) ESP.Armor_ESP = v end,
}):Colorpicker({
    Flag = "esp_ar_color", Default = Color3.fromRGB(0, 150, 255),
    Callback = function(c) ESP.ArmorColor = c end,
})
ESPSection:Toggle({
    Name = "Distance", Flag = "esp_distance", Default = true,
    Callback = function(v) ESP.Distance_ESP = v end,
}):Colorpicker({
    Flag = "esp_dist_color", Default = Color3.fromRGB(255, 255, 255),
    Callback = function(c) ESP.DistanceColor = c end,
})
ESPSection:Toggle({
    Name = "Visible Check", Flag = "esp_visible", Default = false,
    Callback = function(v) ESP.VisibleCheck = v end,
})
ESPSection:Slider({
    Name = "Max Distance", Flag = "esp_max_dist", Min = 0, Max = 5000, Default = 1000, Decimals = 1, Suffix = " studs",
    Callback = function(v) ESP.Distance = v end,
})

-- ============================================================
-- ESP TEXT UI
-- ============================================================
TextSection:Dropdown({
    Name = "Font", Flag = "esp_font",
    Items = FONT_OPTIONS, Default = "Tahoma",
    Callback = function(v) ESP.Font = v end,
})
TextSection:Slider({ Name="Name Font Size",     Flag="esp_name_size", Min=8, Max=32, Default=14, Decimals=1, Callback=function(v) ESP.NameSize = v end })
TextSection:Slider({ Name="Distance Font Size", Flag="esp_dist_size", Min=8, Max=32, Default=14, Decimals=1, Callback=function(v) ESP.DistanceSize = v end })
TextSection:Slider({ Name="Health Font Size",   Flag="esp_hp_size",   Min=8, Max=32, Default=12, Decimals=1, Callback=function(v) ESP.HealthSize = v end })
TextSection:Slider({ Name="Armor Font Size",    Flag="esp_ar_size",   Min=8, Max=32, Default=12, Decimals=1, Callback=function(v) ESP.ArmorSize = v end })

-- ============================================================
-- AIMVIEW BEAM SYSTEM
-- ============================================================
local AIMVIEW_WEAPONS = {
    ["[Revolver]"] = true, ["[Double-Barrel SG]"] = true, ["[TacticalShotgun]"] = true,
}
local aimViewBeam, aimViewBeamTool = nil, nil

local function destroyAimViewBeam()
    if aimViewBeam then
        pcall(function()
            local origin = aimViewBeam.Attachment0
            if origin and origin.Name == "FacilityAimViewMuzzle" then origin:Destroy() end
            local target = aimViewBeam.Attachment1
            if target then target:Destroy() end
            aimViewBeam:Destroy()
        end)
        aimViewBeam, aimViewBeamTool = nil, nil
    end
end
local function getEquippedAimViewTool(char)
    if not char then return nil end
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("Tool") and AIMVIEW_WEAPONS[c.Name] then return c end
    end
end
local function getMuzzleAttachment(tool)
    if not tool then return nil end
    local attNames = {"Muzzle","FirePoint","Nozzle","MuzzleAttachment","BarrelAttachment","FireAttachment","GunTip","Tip"}
    for _, name in ipairs(attNames) do
        for _, d in ipairs(tool:GetDescendants()) do
            if d.Name == name and d:IsA("Attachment") then return d end
        end
    end
    local partNames = {"Muzzle","Barrel","FirePoint","Nozzle","Tip","GunTip"}
    for _, name in ipairs(partNames) do
        for _, d in ipairs(tool:GetDescendants()) do
            if d.Name == name and d:IsA("BasePart") then
                local existing = d:FindFirstChildOfClass("Attachment")
                if existing then return existing end
                local att = Instance.new("Attachment", d)
                att.Name = "FacilityAimViewMuzzle"
                att.Position = Vector3.new(0, 0, -d.Size.Z * 0.5)
                return att
            end
        end
    end
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        local att = Instance.new("Attachment", handle)
        att.Name = "FacilityAimViewMuzzle"
        att.Position = Vector3.new(0, 0, -handle.Size.Z * 0.6)
        return att
    end
end
local function rebuildAimViewBeam(tool)
    destroyAimViewBeam()
    if not tool then return end
    local origin = getMuzzleAttachment(tool)
    if not origin then return end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if not terrain then return end
    local attach1 = Instance.new("Attachment", terrain)
    attach1.WorldPosition = origin.WorldPosition
    local beam = Instance.new("Beam")
    beam.Attachment0, beam.Attachment1 = origin, attach1
    beam.Width0, beam.Width1 = 0.1, 0.1
    beam.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
    beam.FaceCamera, beam.Enabled = true, true
    beam.Parent = tool
    aimViewBeam, aimViewBeamTool = beam, tool
end
RunService.Heartbeat:Connect(function()
    if not AimViewTarget then
        if aimViewBeam then destroyAimViewBeam() end
        return
    end
    local char = AimViewTarget.Character
    if not char or not char.Parent then destroyAimViewBeam(); return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then destroyAimViewBeam(); return end
    local tool = getEquippedAimViewTool(char)
    if not tool then
        if aimViewBeam then destroyAimViewBeam() end
        return
    end
    if aimViewBeamTool ~= tool or not aimViewBeam or not aimViewBeam.Attachment0 or not aimViewBeam.Attachment0.Parent then
        rebuildAimViewBeam(tool)
        if not aimViewBeam then return end
    end
    local bodyEffects = char:FindFirstChild("BodyEffects")
    if not bodyEffects then return end
    local mousePos = bodyEffects:FindFirstChild("MousePos")
    if not mousePos then return end
    if aimViewBeam.Attachment1 then
        aimViewBeam.Attachment1.WorldPosition = mousePos.Value
    end
end)

-- ============================================================
-- PLAYER LIST
-- ============================================================
local PlayerRows = {}
local searchQuery = ""
local autoWhitelistEnabled = true

local THEME = {
    Inline       = Color3.fromRGB(20, 20, 24),
    Element      = Color3.fromRGB(32, 32, 38),
    ElementHover = Color3.fromRGB(42, 42, 50),
    ElementPress = Color3.fromRGB(52, 52, 62),
    Border       = Color3.fromRGB(48, 48, 56),
    BorderSoft   = Color3.fromRGB(58, 58, 68),
    Text         = Color3.fromRGB(240, 240, 245),
    TextOn       = Color3.fromRGB(20, 20, 24),
    TextDim      = Color3.fromRGB(150, 150, 160),
    TextOff      = Color3.fromRGB(105, 105, 115),
    White        = Color3.fromRGB(240, 240, 245),
    WhiteHover   = Color3.fromRGB(255, 255, 255),
    TrackOn      = Color3.fromRGB(240, 240, 245),
    TrackOff     = Color3.fromRGB(52, 52, 60),
    KnobOn       = Color3.fromRGB(28, 28, 34),
    KnobOff      = Color3.fromRGB(130, 130, 140),
    WLText       = Color3.fromRGB(240, 240, 245),
    WLTextOff    = Color3.fromRGB(130, 130, 140),
    SpecActive   = Color3.fromRGB(240, 240, 245),
    AimActive    = Color3.fromRGB(240, 240, 245),
    GotoActive   = Color3.fromRGB(240, 240, 245),
}

local function styleChip(chip, nameLabel, track, knob, isWL, hovered)
    if isWL then
        tween(chip, 0.14, { BackgroundColor3 = hovered and THEME.ElementHover or THEME.Element })
        if chip:FindFirstChildOfClass("UIStroke") then
            tween(chip:FindFirstChildOfClass("UIStroke"), 0.14, { Color = THEME.White, Transparency = hovered and 0.45 or 0.65 })
        end
        tween(nameLabel, 0.14, { TextColor3 = THEME.Text })
        tween(track, 0.14, { BackgroundColor3 = THEME.TrackOn })
        tween(knob, 0.14, { Position = UDim2.new(1, -12, 0.5, 0), BackgroundColor3 = THEME.KnobOn })
    else
        tween(chip, 0.14, { BackgroundColor3 = hovered and THEME.ElementHover or THEME.Element })
        if chip:FindFirstChildOfClass("UIStroke") then
            tween(chip:FindFirstChildOfClass("UIStroke"), 0.14, { Color = THEME.Border, Transparency = hovered and 0.4 or 0.6 })
        end
        tween(nameLabel, 0.14, { TextColor3 = THEME.TextOff })
        tween(track, 0.14, { BackgroundColor3 = THEME.TrackOff })
        tween(knob, 0.14, { Position = UDim2.new(0, 2, 0.5, 0), BackgroundColor3 = THEME.KnobOff })
    end
end

local function applySearchFilter()
    local q = searchQuery:lower()
    for plr, ui in pairs(PlayerRows) do
        if ui.row then
            local display = (plr.DisplayName or ""):lower()
            local name    = (plr.Name or ""):lower()
            ui.row.Visible = (q == "" or display:find(q,1,true) or name:find(q,1,true))
        end
    end
end
local function resortRows()
    local arr = {}
    for plr, ui in pairs(PlayerRows) do
        if ui.row then table.insert(arr, {plr = plr, ui = ui}) end
    end
    table.sort(arr, function(a, b)
        local an = (a.plr.DisplayName or a.plr.Name or ""):lower()
        local bn = (b.plr.DisplayName or b.plr.Name or ""):lower()
        if an == bn then return (a.plr.Name or "") < (b.plr.Name or "") end
        return an < bn
    end)
    for i, item in ipairs(arr) do item.ui.row.LayoutOrder = i end
end

local PListRowsHolder
do
    local content = PlayerListSec.Items["Content"].Instance

    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "CountLabel"
    countLabel.Size = UDim2.new(1, 0, 0, 16)
    countLabel.BackgroundTransparency = 1
    countLabel.Font = Enum.Font.GothamMedium
    countLabel.TextSize = 12
    countLabel.TextColor3 = THEME.TextDim
    countLabel.TextXAlignment = Enum.TextXAlignment.Left
    countLabel.Text = "0 players"
    countLabel.Parent = content

    local searchHolder = Instance.new("Frame")
    searchHolder.Size = UDim2.new(1, 0, 0, 28)
    searchHolder.BackgroundColor3 = THEME.Element
    searchHolder.BorderSizePixel = 0
    searchHolder.Parent = content
    Instance.new("UICorner", searchHolder).CornerRadius = UDim.new(0, 6)
    local shStroke = Instance.new("UIStroke", searchHolder)
    shStroke.Color = THEME.Border
    shStroke.Transparency = 0.4

    local searchText = Instance.new("TextBox")
    searchText.Name = "SearchBox"
    searchText.Size = UDim2.fromScale(1, 1)
    searchText.BackgroundTransparency = 1
    searchText.Font = Enum.Font.Gotham
    searchText.TextSize = 13
    searchText.TextColor3 = THEME.Text
    searchText.Text = ""
    searchText.PlaceholderText = "Search Players..."
    searchText.PlaceholderColor3 = THEME.TextDim
    searchText.TextXAlignment = Enum.TextXAlignment.Left
    searchText.ClearTextOnFocus = false
    searchText.RichText = false
    searchText.MultiLine = false
    searchText.Parent = searchHolder
    Instance.new("UIPadding", searchText).PaddingLeft = UDim.new(0, 10)

    searchText:GetPropertyChangedSignal("Text"):Connect(function()
        searchQuery = searchText.Text or ""
        applySearchFilter()
    end)
    searchText.Focused:Connect(function()
        tween(shStroke, 0.15, { Color = THEME.White, Transparency = 0.3 })
    end)
    searchText.FocusLost:Connect(function()
        tween(shStroke, 0.15, { Color = THEME.Border, Transparency = 0.4 })
    end)

    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, 0, 0, 26)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = content
    local btnLayout = Instance.new("UIListLayout", btnRow)
    btnLayout.FillDirection = Enum.FillDirection.Horizontal
    btnLayout.Padding = UDim.new(0, 6)
    btnLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local function mkTopBtn(text, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -3, 1, 0)
        b.BackgroundColor3 = THEME.Element
        b.TextColor3 = THEME.Text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Text = text
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.Parent = btnRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local st = Instance.new("UIStroke", b)
        st.Color = THEME.BorderSoft
        st.Transparency = 0.5
        b.MouseEnter:Connect(function()
            tween(b, 0.14, { BackgroundColor3 = THEME.ElementHover })
            tween(st, 0.14, { Color = THEME.White, Transparency = 0.5 })
        end)
        b.MouseLeave:Connect(function()
            tween(b, 0.14, { BackgroundColor3 = THEME.Element })
            tween(st, 0.14, { Color = THEME.BorderSoft, Transparency = 0.5 })
        end)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    mkTopBtn("Whitelist All", function()
        local c = 0
        for plr, ui in pairs(PlayerRows) do
            if not Whitelisted[plr] then Whitelisted[plr] = true; c = c + 1 end
            if ui and ui.chip then
                styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, true, false)
            end
        end
        Library:Notification("Whitelisted " .. c .. " player(s).", 2)
    end)

    mkTopBtn("Unwhitelist All", function()
        local c = 0
        for plr, ui in pairs(PlayerRows) do
            if Whitelisted[plr] then Whitelisted[plr] = nil; c = c + 1 end
            if ui and ui.chip then
                styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, false, false)
            end
        end
        Library:Notification("Unwhitelisted " .. c .. " player(s).", 2)
    end)

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Name = "PlayerListFrame"
    listFrame.Size = UDim2.new(1, 0, 0, 420)
    listFrame.BackgroundColor3 = THEME.Inline
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 4
    listFrame.ScrollBarImageColor3 = THEME.BorderSoft
    listFrame.ScrollBarImageTransparency = 0.25
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.Parent = content
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)
    local lfStroke = Instance.new("UIStroke", listFrame)
    lfStroke.Color = THEME.Border
    lfStroke.Transparency = 0.4

    local listPadding = Instance.new("UIPadding", listFrame)
    listPadding.PaddingTop    = UDim.new(0, 6)
    listPadding.PaddingBottom = UDim.new(0, 6)
    listPadding.PaddingLeft   = UDim.new(0, 6)
    listPadding.PaddingRight  = UDim.new(0, 6)

    local listLayout = Instance.new("UIListLayout", listFrame)
    listLayout.Padding = UDim.new(0, 5)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    PListRowsHolder = listFrame

    task.spawn(function()
        while task.wait(0.5) do
            local total = 0
            local wl = 0
            for plr in pairs(PlayerRows) do
                total = total + 1
                if Whitelisted[plr] then wl = wl + 1 end
            end
            if countLabel and countLabel.Parent then
                countLabel.Text = string.format("%d player(s)  •  %d whitelisted", total, wl)
            end
        end
    end)
end

local function resetCameraToLocal()
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        Camera.CameraType    = Enum.CameraType.Custom
        Camera.CameraSubject = hum
    end
end
local function clearSpectate() SpectateTarget = nil; resetCameraToLocal() end
local function clearAimView()  AimViewTarget = nil; destroyAimViewBeam() end
local function teleportToPlayer(targetPlr)
    if not targetPlr or targetPlr == LocalPlayer then return end
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local targetChar = targetPlr.Character
    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if myRoot and targetRoot then myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3) end
end

local function mkRowButton(parent, size, text, onClick)
    local b = Instance.new("TextButton")
    b.Size = size
    b.BackgroundColor3 = THEME.Element
    b.TextColor3 = THEME.Text
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.Text = text
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local st = Instance.new("UIStroke", b)
    st.Color = THEME.BorderSoft
    st.Transparency = 0.5

    b:SetAttribute("IsActive", false)

    b.MouseEnter:Connect(function()
        if b:GetAttribute("IsActive") then return end
        tween(b, 0.14, { BackgroundColor3 = THEME.ElementHover })
        tween(st, 0.14, { Color = THEME.White, Transparency = 0.5 })
    end)
    b.MouseLeave:Connect(function()
        if b:GetAttribute("IsActive") then return end
        tween(b, 0.14, { BackgroundColor3 = THEME.Element })
        tween(st, 0.14, { Color = THEME.BorderSoft, Transparency = 0.5 })
    end)
    b.MouseButton1Click:Connect(onClick)
    return b, st
end

local function setRowBtnActive(btn, stroke, active)
    if not btn then return end
    btn:SetAttribute("IsActive", active and true or false)
    if active then
        tween(btn, 0.14, { BackgroundColor3 = THEME.White })
        tween(btn, 0.14, { TextColor3 = THEME.TextOn })
        if stroke then tween(stroke, 0.14, { Color = THEME.White, Transparency = 0.2 }) end
    else
        tween(btn, 0.14, { BackgroundColor3 = THEME.Element })
        tween(btn, 0.14, { TextColor3 = THEME.Text })
        if stroke then tween(stroke, 0.14, { Color = THEME.BorderSoft, Transparency = 0.5 }) end
    end
end

local function updateAllPlayerUI()
    for p, ui in pairs(PlayerRows) do
        if ui.chip then
            local isWL = Whitelisted[p] and true or false
            if ui.nameLabel and ui.nameLabel.Text ~= p.DisplayName then
                ui.nameLabel.Text = p.DisplayName
            end
            styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, isWL, false)
        end
        local isSpec = (SpectateTarget == p)
        if ui.btnSpec then
            ui.btnSpec.Text = isSpec and "Stop" or "Spectate"
            setRowBtnActive(ui.btnSpec, ui.specStroke, isSpec)
        end
        local isAim = (AimViewTarget == p)
        if ui.btnAim then
            ui.btnAim.Text = isAim and "Stop" or "AimView"
            setRowBtnActive(ui.btnAim, ui.aimStroke, isAim)
        end
    end
end

local function createPlayerRow(plr)
    if plr == LocalPlayer then return end
    if PlayerRows[plr] then return end
    if autoWhitelistEnabled then Whitelisted[plr] = true end

    local row = Instance.new("Frame")
    row.Name = plr.Name .. "_Row"
    row.Size = UDim2.new(1, -8, 0, 30)
    row.BackgroundTransparency = 1
    row.Parent = PListRowsHolder
    local rowLayout = Instance.new("UIListLayout", row)
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.Padding = UDim.new(0, 5)
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local chip = Instance.new("TextButton")
    chip.Name = "NameChip"
    chip.Size = UDim2.new(0.41, -3, 1, 0)
    chip.BackgroundColor3 = THEME.Element
    chip.Text = ""
    chip.AutoButtonColor = false
    chip.BorderSizePixel = 0
    chip.Parent = row
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
    local chipStroke = Instance.new("UIStroke", chip)
    chipStroke.Color = THEME.Border
    chipStroke.Transparency = 0.6

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -44, 1, 0)
    nameLabel.Position = UDim2.new(0, 12, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 12
    nameLabel.TextColor3 = THEME.Text
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Text = plr.DisplayName
    nameLabel.Parent = chip

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.AnchorPoint = Vector2.new(1, 0.5)
    track.Size = UDim2.new(0, 22, 0, 12)
    track.Position = UDim2.new(1, -8, 0.5, 0)
    track.BackgroundColor3 = THEME.TrackOff
    track.BorderSizePixel = 0
    track.Parent = chip
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Size = UDim2.new(0, 8, 0, 8)
    knob.Position = UDim2.new(0, 2, 0.5, 0)
    knob.BackgroundColor3 = THEME.KnobOff
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, false)

    chip.MouseEnter:Connect(function()
        styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, true)
    end)
    chip.MouseLeave:Connect(function()
        styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, false)
    end)
    chip.MouseButton1Click:Connect(function()
        if Whitelisted[plr] then Whitelisted[plr] = nil else Whitelisted[plr] = true end
        styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, true)
    end)

    local btnSpec, specStroke = mkRowButton(row, UDim2.new(0.20, -2, 1, 0), "Spectate", function()
        if SpectateTarget == plr then clearSpectate()
        else
            SpectateTarget = plr
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then Camera.CameraType = Enum.CameraType.Custom; Camera.CameraSubject = hum end
        end
        updateAllPlayerUI()
    end)

    local btnAim, aimStroke = mkRowButton(row, UDim2.new(0.20, -2, 1, 0), "AimView", function()
        if AimViewTarget == plr then clearAimView() else AimViewTarget = plr end
        updateAllPlayerUI()
    end)

    local btnGoto, gotoStroke = mkRowButton(row, UDim2.new(0.19, -2, 1, 0), "Goto", function()
        teleportToPlayer(plr)
    end)

    PlayerRows[plr] = {
        row = row,
        chip = chip,
        nameLabel = nameLabel,
        track = track,
        knob = knob,
        btnSpec = btnSpec, specStroke = specStroke,
        btnAim = btnAim,   aimStroke = aimStroke,
        btnGoto = btnGoto, gotoStroke = gotoStroke,
    }
    updateAllPlayerUI(); resortRows(); applySearchFilter()
end

local function removePlayerRow(plr)
    local ui = PlayerRows[plr]
    if ui and ui.row then ui.row:Destroy() end
    PlayerRows[plr] = nil
    if Whitelisted[plr] then Whitelisted[plr] = nil end
    if AimViewTarget == plr then clearAimView() end
    if SpectateTarget == plr then clearSpectate() end
    resortRows(); applySearchFilter()
end

Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then
        if autoWhitelistEnabled then Whitelisted[plr] = true end
        createPlayerRow(plr)
    end
end)
Players.PlayerRemoving:Connect(removePlayerRow)
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
        if autoWhitelistEnabled then Whitelisted[plr] = true end
        createPlayerRow(plr)
    end
end

RunService.RenderStepped:Connect(function()
    if not SpectateTarget then return end
    local char = SpectateTarget.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    Camera.CameraType    = Enum.CameraType.Custom
    Camera.CameraSubject = hum
end)

-- ============================================================
-- CORE HELPERS
-- ============================================================
local isValidTarget
local function clickMouse1()
    if not VIM then return end
    local m = UserInputService:GetMouseLocation()
    pcall(function()
        VIM:SendMouseButtonEvent(m.X, m.Y, 0, true,  game, 1)
        task.wait(GunMacro.ClickHold)
        VIM:SendMouseButtonEvent(m.X, m.Y, 0, false, game, 1)
    end)
end
local function equip(toolName)
    local character = LocalPlayer.Character
    if not character then return false end
    local held = character:FindFirstChild(toolName)
    if held and held:IsA("Tool") then return true end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end
    local tool = backpack:FindFirstChild(toolName)
    if tool then humanoid:EquipTool(tool); return true end
    return false
end

function isValidTarget(target)
    if not target then return false end
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and
           (target == player.Character or target:IsDescendantOf(player.Character)) then
            if Whitelisted[player] and not hostDetectEnabled then return false end
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health <= 0 then return false end
            local effects = player.Character:FindFirstChild("BodyEffects")
            if effects then
                local ko = effects:FindFirstChild("K.O") or effects:FindFirstChild("KO")
                if ko and ko.Value then return false end
            end
            return true
        end
    end
    return false
end
local function getTargetCharacter(target)
    if not target then return nil end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            if target == p.Character or target:IsDescendantOf(p.Character) then return p.Character end
        end
    end
end
local function getTargetDistance(target)
    local character = LocalPlayer.Character
    local myRoot = character and character:FindFirstChild("HumanoidRootPart")
    local targetChar = getTargetCharacter(target)
    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not myRoot or not targetRoot then return nil end
    return (targetRoot.Position - myRoot.Position).Magnitude
end
local function canFireAt(target)
    if not isValidTarget(target) then return false end
    local distance = getTargetDistance(target)
    if distance and GunMacro.MaxRange > 0 and distance > GunMacro.MaxRange then return false end
    return true
end
local function isToolBlacklisted(tool)
    local n = tool.Name:lower()
    for _, name in ipairs(Triggerbot.Blacklist) do
        if n:find(name:lower(), 1, true) then return true end
    end
    return false
end
local function getMaxRange(tool)
    if Triggerbot.GunRanges[tool.Name] then return Triggerbot.GunRanges[tool.Name] end
    local n = tool.Name:lower()
    for gunName, range in pairs(Triggerbot.GunRanges) do
        if n:find(gunName:lower(), 1, true) then return range end
    end
    return Triggerbot.DefaultRange
end

-- ============================================================
-- SILENT AIM LOGIC
-- ============================================================
local SA_oldIndex = nil
local SA_currentPart, SA_currentPoint = nil, nil
local function SA_WorldToScreen(worldPos)
    local sp, onScreen = Camera:WorldToViewportPoint(worldPos)
    return Vector2.new(sp.X, sp.Y), onScreen
end
local function SA_ClosestPointOnPartToRay(part, rayOrigin, rayDirection, worldOffset)
    local cf, size = part.CFrame, part.Size
    if worldOffset then cf = cf + worldOffset end
    local half = size / 2
    local lo = cf:PointToObjectSpace(rayOrigin)
    local ld = cf:VectorToObjectSpace(rayDirection)
    local p = Vector3.new(
        math.clamp(lo.X, -half.X, half.X),
        math.clamp(lo.Y, -half.Y, half.Y),
        math.clamp(lo.Z, -half.Z, half.Z))
    for _ = 1, 8 do
        local t = (p - lo):Dot(ld)
        if t < 0 then t = 0 end
        local q = lo + ld * t
        p = Vector3.new(
            math.clamp(q.X, -half.X, half.X),
            math.clamp(q.Y, -half.Y, half.Y),
            math.clamp(q.Z, -half.Z, half.Z))
    end
    return cf:PointToWorldSpace(p)
end
local function SA_IsValidPart(part)
    if not part:IsA("BasePart") then return false end
    if part.Transparency >= 1 then return false end
    if part.Name == "HumanoidRootPart" then return false end
    local a = part.Parent
    while a and not a:IsA("Model") do
        if a:IsA("Accessory") or a:IsA("Tool") then return false end
        a = a.Parent
    end
    return true
end
local function SA_IsVisible(point, targetChar)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, Camera, targetChar }
    local origin = Camera.CFrame.Position
    local dir    = point - origin
    local result = workspace:Raycast(origin, dir, params)
    return result == nil or (result.Position - origin).Magnitude >= dir.Magnitude - 1
end
local function SA_GetBestTarget()
    local mousePos = UserInputService:GetMouseLocation()
    local ray      = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local bestPart, bestPoint, bestDist = nil, nil, math.huge
    local fovLimit = SilentAim.UseFOV and SilentAim.Fov or math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not Whitelisted[player] then
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local be = char:FindFirstChild("BodyEffects")
                    local ko = be and (be:FindFirstChild("K.O") or be:FindFirstChild("KO"))
                    if not (ko and ko.Value) then
                        for _, part in ipairs(char:GetDescendants()) do
                            if SA_IsValidPart(part) then
                                local offset = SilentAim.Prediction > 0
                                    and (part.AssemblyLinearVelocity * SilentAim.Prediction) or nil
                                local point = SA_ClosestPointOnPartToRay(part, ray.Origin, ray.Direction, offset)
                                if SA_IsVisible(point, char) then
                                    local screenPos, onScreen = SA_WorldToScreen(point)
                                    if onScreen then
                                        local dist = (screenPos - mousePos).Magnitude
                                        if dist <= fovLimit and dist < bestDist then
                                            bestDist, bestPart, bestPoint = dist, part, point
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPart, bestPoint
end
local function SA_ApplyHook()
    if SA_oldIndex then return end
    local mt = getrawmetatable(game)
    SA_oldIndex = mt.__index
    setreadonly(mt, false)
    mt.__index = newcclosure(function(self, key)
        if self == Mouse and SilentAim.Enabled and SA_currentPart and SA_currentPoint then
            if key == "Target" then return SA_currentPart
            elseif key == "Hit" then return CFrame.new(SA_currentPoint) end
        end
        return SA_oldIndex(self, key)
    end)
    setreadonly(mt, true)
end
local function SA_RemoveHook()
    if not SA_oldIndex then return end
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    mt.__index = SA_oldIndex
    setreadonly(mt, true)
    SA_oldIndex = nil
end
RunService.RenderStepped:Connect(function()
    if not SilentAim.Enabled then
        SA_currentPart, SA_currentPoint = nil, nil
        SA_RemoveHook()
        return
    end
    SA_ApplyHook()
    SA_currentPart, SA_currentPoint = SA_GetBestTarget()
end)
RunService.RenderStepped:Connect(function()
    if SA_FOVCircle then
        if SilentAim.Enabled and SilentAim.DrawFOV then
            SA_FOVCircle.Visible  = true
            SA_FOVCircle.Position = UserInputService:GetMouseLocation()
            SA_FOVCircle.Radius   = SilentAim.UseFOV and SilentAim.Fov or 0
        else
            SA_FOVCircle.Visible = false
        end
    end
end)

-- ============================================================
-- GUN MACRO
-- ============================================================
task.spawn(function()
    while true do
        GunMacro.Active = GunMacro.Enabled
        if GunMacro.Active and canFireAt(Mouse.Target) then
            if equip(GunMacro.Tools[1]) then clickMouse1() end
            task.wait(GunMacro.Delay)
            if GunMacro.Tools[2] and canFireAt(Mouse.Target) then
                if equip(GunMacro.Tools[2]) then clickMouse1() end
            end
            task.wait(GunMacro.Delay)
        else
            task.wait(0.05)
        end
    end
end)

-- ============================================================
-- TRIGGERBOT (with host gate when Host Detection is on)
-- ============================================================
task.spawn(function()
    while true do
        task.wait()
        if not Triggerbot.Enabled then continue end
        if hostDetectEnabled and not hostReady then continue end

        local target = Mouse.Target
        if not target or not isValidTarget(target) then continue end
        local character = LocalPlayer.Character
        if not character then continue end
        local tool = character:FindFirstChildWhichIsA("Tool")
        if not tool or isToolBlacklisted(tool) then continue end
        local myRoot = character:FindFirstChild("HumanoidRootPart")
        local targetChar = getTargetCharacter(target)
        local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if myRoot and targetRoot then
            local maxRange = getMaxRange(tool)
            if (targetRoot.Position - myRoot.Position).Magnitude > maxRange then continue end
        end

        local useDelay = hostDetectEnabled and (HostDetection.DelayMs / 1000) or Triggerbot.Delay
        if useDelay > 0 then task.wait(useDelay) end
        if not Triggerbot.Enabled then continue end
        if hostDetectEnabled and not hostReady then continue end

        tool:Activate()
        if Triggerbot.Release > 0 then task.wait(Triggerbot.Release) end
    end
end)

-- ============================================================
-- HOST DETECTION
-- ============================================================
local colorConns = {}

clearColorConnections = function()
    for _, c in ipairs(colorConns) do pcall(function() c:Disconnect() end) end
    colorConns = {}
end

hookColorAmmo = function(targetPlayer)
    clearColorConnections()
    if not targetPlayer or not targetPlayer.Parent then return end

    local watched = {}

    local function watchAmmo(val)
        if watched[val] then return end
        watched[val] = true
        local prev = val.Value
        local conn
        local ok = pcall(function()
            conn = val:GetPropertyChangedSignal("Value"):Connect(function()
                local newVal = val.Value
                if type(newVal) == "number" and type(prev) == "number" and newVal < prev then
                    hostReady = true
                end
                prev = newVal
            end)
        end)
        if not ok or not conn then
            conn = val.Changed:Connect(function(newVal)
                if type(newVal) == "number" and type(prev) == "number" and newVal < prev then
                    hostReady = true
                end
                prev = newVal
            end)
        end
        table.insert(colorConns, conn)
    end

    local function scanTool(tool)
        if not tool or tool.Name ~= HostDetection.ToolName then return end
        local ammo = tool:FindFirstChild(HostDetection.WatchAmmoName)
        if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then
            watchAmmo(ammo)
        end
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("IntValue") or d:IsA("NumberValue")) and d.Name == HostDetection.WatchAmmoName then
                watchAmmo(d)
            end
        end
    end

    local function scanContainer(container)
        if not container then return end
        for _, c in ipairs(container:GetChildren()) do
            if c:IsA("Tool") then scanTool(c) end
        end
    end

    local function attachContainer(container)
        if not container then return end
        table.insert(colorConns, container.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                task.wait(0.05)
                scanTool(child)
            end
        end))
    end

    scanContainer(targetPlayer.Character)
    scanContainer(targetPlayer:FindFirstChild("Backpack"))
    attachContainer(targetPlayer.Character)
    attachContainer(targetPlayer:FindFirstChild("Backpack"))

    table.insert(colorConns, targetPlayer.CharacterAdded:Connect(function(newChar)
        task.wait(1)
        if not targetPlayer.Parent then return end
        scanContainer(newChar)
        scanContainer(targetPlayer:FindFirstChild("Backpack"))
        attachContainer(newChar)
        attachContainer(targetPlayer:FindFirstChild("Backpack"))
    end))
end

-- ============================================================
-- HOST PLAYER DROPDOWN REFRESH
-- ============================================================
local function refreshColorTargetList()
    local names = buildColorTargetOptions()
    if not HostPlayerDropdown then return end
    local methods = {"Refresh", "Update", "SetItems", "SetOptions", "SetValues", "UpdateItems"}
    for _, m in ipairs(methods) do
        if type(HostPlayerDropdown[m]) == "function" then
            local ok = pcall(function() HostPlayerDropdown[m](HostPlayerDropdown, names) end)
            if ok then return end
        end
    end
    pcall(function()
        if HostPlayerDropdown.Items then HostPlayerDropdown.Items = names
        elseif HostPlayerDropdown.Options then HostPlayerDropdown.Options = names end
    end)
end

Players.PlayerAdded:Connect(function(p) if p ~= LocalPlayer then task.wait(0.1); refreshColorTargetList() end end)
Players.PlayerRemoving:Connect(function(p)
    refreshColorTargetList()
    if HostDetection.TargetPlayer and HostDetection.TargetPlayer.Name == p.Name then
        HostDetection.TargetPlayer = nil
        pcall(function() HostPlayerDropdown:SetValue("None") end)
        clearColorConnections()
    end
end)
task.spawn(function()
    for _ = 1, 6 do task.wait(0.5); refreshColorTargetList() end
end)
task.spawn(function()
    while task.wait(5) do
        local current = buildColorTargetOptions()
        local needsRefresh = false
        if HostPlayerDropdown and type(HostPlayerDropdown.Values) == "table" then
            local count = 0
            for _ in pairs(HostPlayerDropdown.Values) do count = count + 1 end
            if count ~= #current then needsRefresh = true end
        end
        if needsRefresh then refreshColorTargetList() end
        if HostDetection.TargetPlayer and not Players:FindFirstChild(HostDetection.TargetPlayer.Name) then
            HostDetection.TargetPlayer = nil
            pcall(function() HostPlayerDropdown:SetValue("None") end)
            clearColorConnections()
        end
    end
end)

-- ============================================================
-- AIMBOT
-- ============================================================
local function IsAlive(player)
    local char = player.Character
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local root     = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return false end
    local be = char:FindFirstChild("BodyEffects")
    if be and be:FindFirstChild("K.O") and be["K.O"].Value == true then return false end
    return true
end
local function GetClosestPlayerInFOV()
    local closest, shortest = nil, math.huge
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsAlive(player) and not Whitelisted[player] then
            local root = player.Character.HumanoidRootPart
            local sp, onScreen = Camera:WorldToViewportPoint(root.Position)
            if onScreen then
                local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                if d <= MouseLock.FOV and d < shortest then
                    shortest, closest = d, player
                end
            end
        end
    end
    return closest
end
RunService.RenderStepped:Connect(function()
    if FOVCircle then
        FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
        FOVCircle.Radius   = MouseLock.FOV
        FOVCircle.Visible  = MouseLock.VisibleFOV
        FOVCircle.Color    = MouseLock.CircleColor
    end
    if not MouseLock.Enabled then return end
    if MouseLock.Sticky then
        if not (CurrentTarget and IsAlive(CurrentTarget)) then
            CurrentTarget = GetClosestPlayerInFOV()
            if not CurrentTarget then return end
        end
    else
        CurrentTarget = GetClosestPlayerInFOV()
        if not CurrentTarget then return end
    end
    if CurrentTarget and Whitelisted[CurrentTarget] then CurrentTarget = nil; return end
    local aimPart = CurrentTarget.Character:FindFirstChild(MouseLock.AimPart)
    if not aimPart then CurrentTarget = nil; return end
    local predicted = aimPart.Position + (aimPart.AssemblyLinearVelocity * MouseLock.Prediction)
    local sp = Camera:WorldToScreenPoint(predicted)
    local dx = sp.X - Mouse.X
    local dy = sp.Y - Mouse.Y
    if math.sqrt(dx*dx + dy*dy) < MouseLock.Deadzone then return end
    mousemoverel(dx * MouseLock.Smoothness, dy * MouseLock.Smoothness)
end)

-- ============================================================
-- ESP
-- ============================================================
local ARMOR_MAX = 200
local floor, sqrt, abs, clamp = math.floor, math.sqrt, math.abs, math.clamp
local Dnew
pcall(function() Dnew = Drawing.new end)
local LP = Players.LocalPlayer
while not LP do task.wait(0.1); LP = Players.LocalPlayer end
local COLOR_BLACK = Color3.new(0, 0, 0)
if not Dnew then
    ESP.Box_ESP, ESP.Health_ESP, ESP.Armor_ESP, ESP.Distance_ESP = false, false, false, false
    warn("[ESP] Drawing unavailable — only Name_ESP active.")
end
for _, plr in ipairs(Players:GetPlayers()) do
    local char = plr.Character
    if char then
        for _, d in ipairs(char:GetDescendants()) do
            if d.Name == "NameESP" and d:IsA("BillboardGui") then d:Destroy() end
        end
    end
end
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        for _, d in ipairs(char:GetDescendants()) do
            if d.Name == "NameESP" and d:IsA("BillboardGui") then d:Destroy() end
        end
    end)
end)

local function addPlayer(plr)
    if playerSet[plr] then return end
    playerSet[plr] = true; playerCount = playerCount + 1
    playerList[playerCount] = plr
end
local function removePlayer(plr)
    if not playerSet[plr] then return end
    playerSet[plr] = nil
    for i = 1, playerCount do
        if playerList[i] == plr then
            playerList[i] = playerList[playerCount]
            playerList[playerCount] = nil
            playerCount = playerCount - 1
            return
        end
    end
end
local function getParts(plr)
    local c = charCache[plr]
    if c and c.char == plr.Character and c.hrp.Parent == c.char and c.hum.Parent == c.char then
        return c.hrp, c.hum, c.char
    end
    local char = plr.Character
    if not char then charCache[plr] = nil; return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then charCache[plr] = nil; return nil end
    local hum = char:FindFirstChildOfClass("Humanoid");    if not hum then charCache[plr] = nil; return nil end
    charCache[plr] = {hrp = hrp, hum = hum, char = char}
    return hrp, hum, char
end
local rayParams = RaycastParams.new()
pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Blacklist end)

local function dropName(plr)
    local x = namePool[plr]
    if x then pcall(function() if x.gui then x.gui:Destroy() end end); namePool[plr] = nil end
end
local function dropBox(plr)  local x=boxPool[plr];  if x then for i=1,4 do pcall(function() x[i]:Remove() end) end; boxPool[plr]=nil end end
local function dropHealth(plr) local x=hpPool[plr]; if not x then return end
    pcall(function() x.bg:Remove() end); pcall(function() x.fill:Remove() end); pcall(function() x.text:Remove() end)
    hpPool[plr]=nil end
local function dropArmor(plr) local x=armorPool[plr]; if not x then return end
    pcall(function() x.bg:Remove() end); pcall(function() x.fill:Remove() end)
    if x.text then pcall(function() x.text:Remove() end) end
    armorPool[plr]=nil end
local function dropDist(plr) local x=distPool[plr]; if x then pcall(function() x:Remove() end); distPool[plr]=nil end end
local function wipe(plr)
    dropName(plr); dropBox(plr); dropHealth(plr); dropArmor(plr); dropDist(plr)
    charCache[plr], armorRef[plr] = nil, nil
end
local function isValidNameESP(plr, char)
    local n = namePool[plr]
    if not n or not n.gui or not n.gui.Parent then return false end
    if not n.label or not n.label.Parent then return false end
    if n.char ~= char then return false end
    return true
end
local function hookPlayer(plr)
    if plr == LP then return end
    addPlayer(plr)
    plr.CharacterAdded:Connect(function() wipe(plr) end)
end
Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(plr) removePlayer(plr); wipe(plr) end)
for _, plr in next, Players:GetPlayers() do hookPlayer(plr) end
Players:GetPropertyChangedSignal("LocalPlayer"):Connect(function()
    if Players.LocalPlayer then LP = Players.LocalPlayer end
end)
if LP then
    LP.CharacterAdded:Connect(function() charCache[LP] = nil; armorRef[LP] = nil end)
end
local function hidePlayer(ng, box, hp, ar, dst)
    if ng and ng.gui and ng.gui.Enabled then ng.gui.Enabled = false end
    if box and box[1].Visible then
        box[1].Visible=false; box[2].Visible=false; box[3].Visible=false; box[4].Visible=false
    end
    if hp and hp.bg.Visible then hp.bg.Visible=false; hp.fill.Visible=false; hp.text.Visible=false end
    if ar and ar.bg.Visible then
        ar.bg.Visible=false; ar.fill.Visible=false
        if ar.text then ar.text.Visible = false end
    end
    if dst and dst.Visible then dst.Visible = false end
end
local lastDistSet, maxDistSq = -1, 0
local espPrevEnabled = false
local lastFont = nil
local cachedEnumFont, cachedDrawFont = getFontPair()

RunService.Heartbeat:Connect(function()
    if not ESP.Enabled then
        if espPrevEnabled then
            for i = 1, playerCount do
                local plr = playerList[i]
                if plr then
                    local ng, box = namePool[plr], boxPool[plr]
                    local hp, ar  = hpPool[plr],   armorPool[plr]
                    local dst     = distPool[plr]
                    if ng and ng.gui then ng.gui.Enabled = false end
                    if box then for bi=1,4 do if box[bi] then box[bi].Visible = false end end end
                    if hp then hp.bg.Visible, hp.fill.Visible, hp.text.Visible = false, false, false end
                    if ar then
                        ar.bg.Visible, ar.fill.Visible = false, false
                        if ar.text then ar.text.Visible = false end
                    end
                    if dst then dst.Visible = false end
                end
            end
            espPrevEnabled = false
        end
        return
    end
    espPrevEnabled = true
    if lastFont ~= ESP.Font then
        lastFont = ESP.Font
        cachedEnumFont, cachedDrawFont = getFontPair()
    end
    local enumFont, drawFont = cachedEnumFont, cachedDrawFont
    if not LP.Parent then LP = Players.LocalPlayer; if not LP then return end end
    local doName, doBox     = ESP.Name_ESP, ESP.Box_ESP
    local doHealth, doArmor = ESP.Health_ESP, ESP.Armor_ESP
    local doDist, doVis     = ESP.Distance_ESP, ESP.VisibleCheck
    local anyDraw           = doBox or doHealth or doArmor or doDist
    local dSet = ESP.Distance
    if dSet ~= lastDistSet then lastDistSet, maxDistSq = dSet, dSet * dSet end
    local myChar = LP.Character
    local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHum  = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local meDead = not myHrp or not myHum or myHum.Health <= 0
    local myPos  = myHrp and myHrp.Position
    local camCF  = Camera.CFrame
    local camPos = camCF.Position
    local lookVec = camCF.LookVector
    local nameMaxDist = dSet > 0 and dSet or 5000
    for i = 1, playerCount do
        local plr = playerList[i]
        if plr and plr ~= LP then
            if Whitelisted[plr] then
                hidePlayer(namePool[plr], boxPool[plr], hpPool[plr], armorPool[plr], distPool[plr])
                continue
            end
            local ng, box = namePool[plr], boxPool[plr]
            local hp, ar  = hpPool[plr],   armorPool[plr]
            local dst     = distPool[plr]
            local hrp, hum, char = getParts(plr)
            if meDead or not hrp or not hum or hum.Health <= 0 then
                hidePlayer(ng, box, hp, ar, dst); continue
            end
            local hrpPos = hrp.Position
            local dx, dy, dz = hrpPos.X - myPos.X, hrpPos.Y - myPos.Y, hrpPos.Z - myPos.Z
            local distSq = dx*dx + dy*dy + dz*dz
            if maxDistSq > 0 and distSq > maxDistSq then hidePlayer(ng, box, hp, ar, dst); continue end
            local tdx, tdy, tdz = hrpPos.X - camPos.X, hrpPos.Y - camPos.Y, hrpPos.Z - camPos.Z
            if tdx*lookVec.X + tdy*lookVec.Y + tdz*lookVec.Z <= 0 then hidePlayer(ng, box, hp, ar, dst); continue end
            local dist = sqrt(distSq)
            local targetColor = ESP.BoxColor
            if doVis then
                rayParams.FilterDescendantsInstances = {char, myChar}
                local hit = workspace:Raycast(camPos, hrpPos - camPos, rayParams)
                targetColor = hit and ESP.HiddenColor or ESP.VisibleColor
            end
            if doName then
                if not isValidNameESP(plr, char) then
                    if namePool[plr] then dropName(plr) end
                    ng = nil
                end
                if not ng then
                    local head = char:FindFirstChild("Head")
                    if head then
                        local gui = Instance.new("BillboardGui")
                        gui.Name = "NameESP"
                        gui.Size = UDim2.fromOffset(160, 24)
                        gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
                        gui.AlwaysOnTop = true
                        gui.MaxDistance = nameMaxDist
                        gui.Adornee = head
                        gui.ResetOnSpawn = false
                        local label = Instance.new("TextLabel")
                        label.Name = "NameLabel"
                        label.Size = UDim2.fromScale(1, 1)
                        label.BackgroundTransparency = 1
                        label.TextColor3 = ESP.NameColor
                        label.TextStrokeColor3 = COLOR_BLACK
                        label.TextStrokeTransparency = 0.4
                        label.TextSize = ESP.NameSize
                        label.Font = enumFont
                        label.Text = plr.Name
                        label.TextScaled = false
                        label.Parent = gui
                        gui.Parent = head
                        ng = {gui = gui, label = label, char = char}
                        namePool[plr] = ng
                    end
                else
                    if ng.label.TextSize ~= ESP.NameSize then ng.label.TextSize = ESP.NameSize end
                    if ng.label.TextColor3 ~= ESP.NameColor then ng.label.TextColor3 = ESP.NameColor end
                    if ng.label.Font ~= enumFont then ng.label.Font = enumFont end
                    if ng.label.Text ~= plr.Name then ng.label.Text = plr.Name end
                    if ng.gui.MaxDistance ~= nameMaxDist then ng.gui.MaxDistance = nameMaxDist end
                    if not ng.gui.Enabled then ng.gui.Enabled = true end
                end
            elseif ng and ng.gui and ng.gui.Enabled then ng.gui.Enabled = false end

            if anyDraw and Dnew then
                local top = Camera:WorldToViewportPoint(hrpPos + Vector3.new(0, 3, 0))
                if top.Z > 0 then
                    local bottom = Camera:WorldToViewportPoint(hrpPos - Vector3.new(0, 3, 0))
                    local h  = abs(bottom.Y - top.Y)
                    local w  = h * 0.5
                    local x1, y1 = top.X - w * 0.5, top.Y
                    local x2, y2 = x1 + w, y1 + h

                    if doBox then
                        if not box then
                            box = {Dnew("Line"), Dnew("Line"), Dnew("Line"), Dnew("Line")}
                            for bi = 1, 4 do
                                box[bi].Thickness, box[bi].Transparency = 1, 1
                                box[bi].Color, box[bi].Visible = targetColor, false
                            end
                            boxPool[plr] = box
                        end
                        local l1,l2,l3,l4 = box[1],box[2],box[3],box[4]
                        if l1.Color ~= targetColor then
                            l1.Color,l2.Color,l3.Color,l4.Color = targetColor,targetColor,targetColor,targetColor
                        end
                        l1.From=Vector2.new(x1,y1); l1.To=Vector2.new(x2,y1)
                        l2.From=Vector2.new(x2,y1); l2.To=Vector2.new(x2,y2)
                        l3.From=Vector2.new(x2,y2); l3.To=Vector2.new(x1,y2)
                        l4.From=Vector2.new(x1,y2); l4.To=Vector2.new(x1,y1)
                        l1.Visible,l2.Visible,l3.Visible,l4.Visible = true,true,true,true
                    elseif box and box[1].Visible then
                        box[1].Visible,box[2].Visible,box[3].Visible,box[4].Visible = false,false,false,false
                    end

                    if doHealth then
                        local barX = x1 - 6
                        if not hp then
                            hp = {bg = Dnew("Line"), fill = Dnew("Line"), text = Dnew("Text")}
                            hp.bg.Thickness, hp.bg.Color, hp.bg.Transparency = 1, COLOR_BLACK, 0.5
                            hp.fill.Thickness = 2
                            hp.text.Center, hp.text.Outline = true, true
                            hpPool[plr] = hp
                        end
                        local pct = clamp(hum.Health / hum.MaxHealth, 0, 1)
                        local col = ESP.HealthColor
                        hp.bg.From = Vector2.new(barX, y1); hp.bg.To = Vector2.new(barX, y2)
                        hp.fill.Color = col
                        hp.fill.From = Vector2.new(barX, y2); hp.fill.To = Vector2.new(barX, y2 - h * pct)
                        if hp.text.Size ~= ESP.HealthSize then hp.text.Size = ESP.HealthSize end
                        if hp.text.Font ~= drawFont then hp.text.Font = drawFont end
                        hp.text.Color = col
                        hp.text.Text = tostring(floor(hum.Health))
                        hp.text.Position = Vector2.new(barX, y1 - ESP.HealthSize * 0.6)
                        hp.bg.Visible, hp.fill.Visible, hp.text.Visible = true, true, true
                    elseif hp and hp.bg.Visible then
                        hp.bg.Visible, hp.fill.Visible, hp.text.Visible = false, false, false
                    end

                    if doArmor then
                        local av = armorRef[plr]
                        if not av or not av.Parent then
                            av = nil
                            local bfx = char:FindFirstChild("BodyEffects")
                            if bfx then av = bfx:FindFirstChild("Armor"); if av then armorRef[plr] = av end end
                        end
                        if av and tonumber(av.Value) then
                            local barX = x2 + 4
                            if not ar then
                                ar = {bg = Dnew("Line"), fill = Dnew("Line"), text = Dnew("Text")}
                                ar.bg.Thickness, ar.bg.Color, ar.bg.Transparency = 1, COLOR_BLACK, 0.5
                                ar.fill.Thickness, ar.fill.Color = 2, ESP.ArmorColor
                                ar.text.Center, ar.text.Outline = true, true
                                armorPool[plr] = ar
                            end
                            local pct = clamp(tonumber(av.Value) / ARMOR_MAX, 0, 1)
                            ar.bg.From = Vector2.new(barX, y1); ar.bg.To = Vector2.new(barX, y2)
                            ar.fill.Color = ESP.ArmorColor
                            ar.fill.From = Vector2.new(barX, y2); ar.fill.To = Vector2.new(barX, y2 - h * pct)
                            if ar.text.Size ~= ESP.ArmorSize then ar.text.Size = ESP.ArmorSize end
                            if ar.text.Font ~= drawFont then ar.text.Font = drawFont end
                            ar.text.Color = ESP.ArmorColor
                            ar.text.Text = tostring(floor(tonumber(av.Value)))
                            ar.text.Position = Vector2.new(barX, y1 - ESP.ArmorSize * 0.6)
                            ar.bg.Visible, ar.fill.Visible, ar.text.Visible = true, true, true
                        elseif ar and ar.bg.Visible then
                            ar.bg.Visible, ar.fill.Visible = false, false
                            if ar.text then ar.text.Visible = false end
                        end
                    elseif ar and ar.bg.Visible then
                        ar.bg.Visible, ar.fill.Visible = false, false
                        if ar.text then ar.text.Visible = false end
                    end

                    if doDist then
                        if not dst then
                            dst = Dnew("Text")
                            dst.Center, dst.Outline = true, false
                            dst.Color = ESP.DistanceColor
                            distPool[plr] = dst
                        end
                        if dst.Size ~= ESP.DistanceSize then dst.Size = ESP.DistanceSize end
                        if dst.Font ~= drawFont then dst.Font = drawFont end
                        dst.Color = ESP.DistanceColor
                        dst.Position = Vector2.new((x1 + x2) * 0.5, y2 + 4)
                        dst.Text = floor(dist + 0.5) .. " studs"
                        dst.Visible = true
                    elseif dst and dst.Visible then
                        dst.Visible = false
                    end
                else
                    if box and box[1].Visible then box[1].Visible,box[2].Visible,box[3].Visible,box[4].Visible = false,false,false,false end
                    if hp and hp.bg.Visible then hp.bg.Visible,hp.fill.Visible,hp.text.Visible = false,false,false end
                    if ar and ar.bg.Visible then
                        ar.bg.Visible,ar.fill.Visible = false,false
                        if ar.text then ar.text.Visible = false end
                    end
                    if dst and dst.Visible then dst.Visible = false end
                end
            end
        end
    end
end)

-- ============================================================
-- MOVEMENT
-- ============================================================
local wsSignalConn = nil
local function hookWalkSpeedSignal(hum)
    if wsSignalConn then pcall(function() wsSignalConn:Disconnect() end); wsSignalConn = nil end
    if not hum then return end
    wsSignalConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if WalkSpeed.Enabled and hum.WalkSpeed ~= WalkSpeed.Value then
            hum.WalkSpeed = WalkSpeed.Value
        end
    end)
end

local function setWalkSpeedState(state)
    local prev = WalkSpeed.Enabled
    WalkSpeed.Enabled = state and true or false
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if WalkSpeed.Enabled then
        if hum then hookWalkSpeedSignal(hum) end
    elseif prev and hum then
        hum.WalkSpeed = WalkSpeed.Default
    end
end

local function setJumpPowerState(state)
    local prev = JumpPower.Enabled
    JumpPower.Enabled = state and true or false
    if prev and not JumpPower.Enabled then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.UseJumpPower = true; hum.JumpPower = JumpPower.Default end
    end
end

local function enforceMovement()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if not wsSignalConn then hookWalkSpeedSignal(hum) end
    if WalkSpeed.Enabled and hum.WalkSpeed ~= WalkSpeed.Value then hum.WalkSpeed = WalkSpeed.Value end
    if JumpPower.Enabled then
        if not hum.UseJumpPower then hum.UseJumpPower = true end
        if hum.JumpPower ~= JumpPower.Value then hum.JumpPower = JumpPower.Value end
    end
end
RunService.RenderStepped:Connect(enforceMovement)
RunService.Stepped:Connect(enforceMovement)
RunService.Heartbeat:Connect(enforceMovement)
pcall(function() RunService.PreSimulation:Connect(enforceMovement) end)
pcall(function() RunService.PostSimulation:Connect(enforceMovement) end)
task.spawn(function()
    while true do
        if WalkSpeed.Enabled then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= WalkSpeed.Value then hum.WalkSpeed = WalkSpeed.Value end
            RunService.Heartbeat:Wait()
        else
            task.wait(0.1)
        end
    end
end)
LocalPlayer.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then hookWalkSpeedSignal(hum) end
end)
if LocalPlayer.Character then
    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hookWalkSpeedSignal(hum) end
end

local wsMasterOn = false
MovementSection:Toggle({
    Name = "WalkSpeed", Flag = "ws_enabled", Default = false,
    Callback = function(state)
        wsMasterOn = state and true or false
        setWalkSpeedState(state)
    end,
}):Keybind({
    Flag = "ws_key", Default = Enum.KeyCode.H, Mode = "Toggle",
    Callback = function(v)
        if not wsMasterOn then return end
        if type(v) == "boolean" then setWalkSpeedState(v) end
    end,
})
MovementSection:Slider({
    Name = "Speed", Flag = "ws_value", Min = 16, Max = 500, Default = 16, Decimals = 1,
    Callback = function(v) WalkSpeed.Value = v end,
})
local jpMasterOn = false
MovementSection:Toggle({
    Name = "JumpPower", Flag = "jp_enabled", Default = false,
    Callback = function(state)
        jpMasterOn = state and true or false
        setJumpPowerState(state)
    end,
}):Keybind({
    Flag = "jp_key", Default = Enum.KeyCode.J, Mode = "Toggle",
    Callback = function(v)
        if not jpMasterOn then return end
        if type(v) == "boolean" then setJumpPowerState(v) end
    end,
})
MovementSection:Slider({
    Name = "Power", Flag = "jp_value", Min = 50, Max = 500, Default = 50, Decimals = 1,
    Callback = function(v) JumpPower.Value = v end,
})

-- ============================================================
-- GUN NOCLIP
-- ============================================================
local gnMasterOn = false
GunNoclipSection:Toggle({
    Name = "Enabled", Flag = "gn_enabled", Default = false,
    Callback = function(state)
        gnMasterOn = state and true or false
        GunNoclip.Enabled = state and true or false
        GunNoclip.Active = state and true or false
    end,
}):Keybind({
    Flag = "gn_key", Default = Enum.KeyCode.V, Mode = "Toggle",
    Callback = function(v)
        if not gnMasterOn then return end
        if type(v) == "boolean" then
            GunNoclip.Enabled = v
            GunNoclip.Active = v
        end
    end,
})
GunNoclipSection:Slider({
    Name = "Delay", Flag = "gn_delay", Min = 0, Max = 1000, Default = 50, Decimals = 1, Suffix = "ms",
    Callback = function(v) GunNoclip.Delay = v / 1000 end,
})

local function getBackpackTool(name)
    local char = LocalPlayer.Character
    if char then
        local t = char:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        local t = bp:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end
end
task.spawn(function()
    local swap = false
    while true do
        GunNoclip.Active = GunNoclip.Enabled
        if GunNoclip.Active then
            local char = LocalPlayer.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                local name = swap and "[TacticalShotgun]" or "[Double-Barrel SG]"
                local tool = getBackpackTool(name)
                if tool then pcall(function() hum:EquipTool(tool) end) end
                swap = not swap
            end
            if GunNoclip.Delay > 0 then task.wait(GunNoclip.Delay) else task.wait() end
        else
            task.wait(0.05)
        end
    end
end)

-- ============================================================
-- AUTO EAT
-- ============================================================
local AutoEatCfg = {
    Enabled = false, Delay = 0.5, ArmorMax = 200,
    FoodList = {"[Donut]","[Hamburger]","[HotDog]","[Pizza]","[Popcorn]","[Taco]"},
}
local function getArmorValue()
    local wp = workspace:FindFirstChild("Players")
    if not wp then return nil end
    local me = wp:FindFirstChild(LocalPlayer.Name)
    if not me then return nil end
    local be = me:FindFirstChild("BodyEffects")
    if not be then return nil end
    local ar = be:FindFirstChild("Armor")
    if not ar then return nil end
    return tonumber(ar.Value)
end

local aeMasterOn = false
AutoEatSection:Toggle({
    Name = "Enabled", Flag = "ae_enabled", Default = false,
    Callback = function(state)
        aeMasterOn = state and true or false
        AutoEatCfg.Enabled = state and true or false
    end,
}):Keybind({
    Flag = "ae_key", Default = Enum.KeyCode.R, Mode = "Hold",
    Callback = function(v)
        if not aeMasterOn then return end
        if type(v) == "boolean" then AutoEatCfg.Enabled = v end
    end,
})
AutoEatSection:Slider({
    Name = "Delay", Flag = "ae_delay", Min = 0, Max = 1000, Default = 500, Decimals = 1, Suffix = "ms",
    Callback = function(v) AutoEatCfg.Delay = v / 1000 end,
})

local function eatClickMouse1()
    if mouse1click then pcall(mouse1click); return end
    if mouse1down and mouse1up then
        pcall(function() mouse1down(); task.wait(0.03); mouse1up() end)
        return
    end
    if VIM then
        local m = UserInputService:GetMouseLocation()
        pcall(function()
            VIM:SendMouseButtonEvent(m.X, m.Y, 0, true,  game, 1)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(m.X, m.Y, 0, false, game, 1)
        end)
    end
end
local function getEquippedFood()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, name in ipairs(AutoEatCfg.FoodList) do
        local t = char:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end
end
local function getBackpackFood()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return nil end
    for _, name in ipairs(AutoEatCfg.FoodList) do
        local t = bp:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end
end
task.spawn(function()
    while true do
        if not AutoEatCfg.Enabled then task.wait(0.1); continue end
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then task.wait(0.1); continue end
        local armor = getArmorValue()
        if armor and armor >= AutoEatCfg.ArmorMax then task.wait(0.2); continue end
        local equipped = getEquippedFood()
        if equipped then
            eatClickMouse1()
            local delay = AutoEatCfg.Delay
            if delay > 0 then task.wait(delay) else task.wait() end
        else
            local food = getBackpackFood()
            if food then
                pcall(function() hum:EquipTool(food) end)
                task.wait(0.1)
            else
                task.wait(0.2)
            end
        end
    end
end)

-- ============================================================
-- NOTIFICATION / SAFETY
-- ============================================================
Library:Notification("Elytra | Der Hood | Closet loaded. Press RightShift to toggle.", 5)

pcall(function()
    local RS = game:GetService("ReplicatedStorage")
    local mainRemotes = RS:FindFirstChild("MainRemotes")
    local gunEvent    = mainRemotes and mainRemotes:FindFirstChild("MainRemoteEvent")
    if gunEvent then gunEvent:FireServer("ChangeSettings", "GunSystem", "New") end
end)
