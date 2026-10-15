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
local CoreGui          = game:GetService("CoreGui")
local HttpService      = game:GetService("HttpService")
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
    Mode = "MouseLock",
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

local WalkSpeed = { Enabled = false, Value = 16, Default = 16 }
local JumpPower = { Enabled = false, Value = 50, Default = 50 }
local SilentAim = { Enabled=false, Fov=100, DrawFOV=true, UseFOV=true, Prediction=0 }
local GunNoclip = { Enabled=false, Delay=0.05, Active=false }

-- ============================================================
-- ESP CONFIG
-- ============================================================
local Config = {
    Enabled = false,
    ShowOnSelf = false,
    MaxDistance = 0,
    Box = {
        Enable = true,
        Type   = "Full",
        Font   = "ProggyClean",
        Color  = Color3.fromRGB(255, 255, 255),
        Filled = {
            Enable = false,
            Gradient = {
                Enable       = true,
                Color        = { Start = Color3.fromRGB(255,255,255), End = Color3.fromRGB(0,0,0) },
                Rotation     = { Enable = true, Auto = true },
                Transparency = 0.3,
            },
        },
    },
    Text = {
        Enable = true,
        Name  = { Enable = true,  Type = "Display", Teamcheck = true, Color = Color3.fromRGB(255,255,255) },
        Studs = { Enable = true,  Color = Color3.fromRGB(255,255,255) },
        Tool  = { Enable = true,  Color = Color3.fromRGB(255,255,255) },
    },
    Bars = {
        Enable = true,
        Health = {
            Enable = true, Lerp = true,
            Color1 = Color3.fromRGB(0,255,0),
            Color2 = Color3.fromRGB(255,255,0),
            Color3 = Color3.fromRGB(255,0,0),
            Position = "Left",
            LastHealth = nil,
        },
        Armor = {
            Enable = true,
            Lerp   = true,
            Color1 = Color3.fromRGB(0, 100, 255),
            Color2 = Color3.fromRGB(80, 160, 255),
            Color3 = Color3.fromRGB(150, 200, 255),
            LastArmor = nil,
        },
    },
}

local ARMOR_MAX = 200
local function getArmorValue(char, player)
    local playersFolder = workspace:FindFirstChild("Players")
    if playersFolder then
        local model = playersFolder:FindFirstChild(char.Name)
        if model then
            local be = model:FindFirstChild("BodyEffects")
            local armor = be and be:FindFirstChild("Armor")
            if armor then return armor.Value end
        end
    end
    local be = char:FindFirstChild("BodyEffects")
    local armor = be and be:FindFirstChild("Armor")
    if armor then return armor.Value end
    return 0
end

-- SHARED STATE
local CurrentTarget  = nil
local Whitelisted, AimViewTarget, SpectateTarget = {}, nil, nil
local hookColorAmmo, clearColorConnections

local forceESPreFresh
local updateBarGradients

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

task.spawn(function()
    local cachedLabel = nil
    local function looksLikeTitleLabel(d)
        if not d:IsA("TextLabel") then return false end
        local t = d.Text
        if type(t) ~= "string" then return false end
        return t:find("Elytra", 1, true) ~= nil and t:find("Closet", 1, true) ~= nil
    end
    local function scanForTitleLabel()
        if cachedLabel and cachedLabel.Parent then return cachedLabel end
        local ok, result = pcall(function()
            for _, d in ipairs(CoreGui:GetDescendants()) do
                if looksLikeTitleLabel(d) then return d end
            end
        end)
        if ok and result then cachedLabel = result; return result end
        local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            local ok2, result2 = pcall(function()
                for _, d in ipairs(pg:GetDescendants()) do
                    if looksLikeTitleLabel(d) then return d end
                end
            end)
            if ok2 and result2 then cachedLabel = result2; return result2 end
        end
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

local GunNoclipSection= MiscPage:Section({Name = "Gun Noclip",     Side = 1})
local AutoEatSection  = MiscPage:Section({Name = "Auto Eat",       Side = 2})
local MovementSection = MiscPage:Section({Name = "Movement",       Side = 1})
local MacroSection    = MiscPage:Section({Name = "Gun Macro",      Side = 2})
local AmmoRedSection  = MiscPage:Section({Name = "Ammo Reduction", Side = 1})
local LaySection      = MiscPage:Section({Name = "Lay Macro",      Side = 2})
local MiscellaneousSection = MiscPage:Section({Name = "Miscellaneous", Side = 1})

local PlayerListSec   = PlayersPage:Section({Name = "Players",     Side = 1})

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
AimbotSection:Dropdown({
    Name = "Mode", Flag = "aim_mode",
    Items = {"MouseLock", "CamLock"},
    Default = "MouseLock",
    Callback = function(v) MouseLock.Mode = v or "MouseLock"; CurrentTarget = nil end,
})
AimbotSection:Slider({ Name="FOV", Flag="aim_fov", Min=0, Max=1000, Default=180, Decimals=1, Callback=function(v) MouseLock.FOV=v end })
AimbotSection:Slider({ Name="Smoothness", Flag="aim_smooth", Min=1, Max=100, Default=20, Decimals=1, Callback=function(v) MouseLock.Smoothness=v/100 end })
AimbotSection:Slider({ Name="Prediction", Flag="aim_prediction", Min=0, Max=50, Default=0, Decimals=1, Callback=function(v) MouseLock.Prediction=v/100 end })
AimbotSection:Slider({ Name="Deadzone", Flag="aim_deadzone", Min=0, Max=50, Default=3, Decimals=1, Callback=function(v) MouseLock.Deadzone=v end })
AimbotSection:Dropdown({
    Name = "Aim Part", Flag = "aim_part",
    Items = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso"},
    Default = "Head",
    Callback = function(v) MouseLock.AimPart = v end,
})
AimbotSection:Toggle({ Name="Visible FOV", Flag="aim_visible_fov", Default=false, Callback=function(v) MouseLock.VisibleFOV=v end })
AimbotSection:Toggle({ Name="Sticky", Flag="aim_sticky", Default=true, Callback=function(v) MouseLock.Sticky=v end })

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
SilentAimSection:Slider({ Name="FOV", Flag="sa_fov", Min=0, Max=1000, Default=100, Decimals=1, Callback=function(v) SilentAim.Fov=v end })
SilentAimSection:Toggle({ Name="Draw FOV", Flag="sa_drawfov", Default=true, Callback=function(v) SilentAim.DrawFOV=v and true or false end })
SilentAimSection:Toggle({ Name="Use FOV", Flag="sa_usefov", Default=true, Callback=function(v) SilentAim.UseFOV=v and true or false end })
SilentAimSection:Slider({ Name="Prediction", Flag="sa_prediction", Min=0, Max=50, Default=0, Decimals=1, Callback=function(v) SilentAim.Prediction=v/100 end })

-- ============================================================
-- HOST DETECTION helpers
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
-- TRIGGERBOT UI
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
TriggerSection:Slider({ Name="Delay", Flag="trig_delay", Min=0, Max=1000, Default=0, Decimals=1, Suffix="ms", Callback=function(v) Triggerbot.Delay=v/1000 end })
TriggerSection:Slider({ Name="Release", Flag="trig_release", Min=0, Max=1000, Default=0, Decimals=1, Suffix="ms", Callback=function(v) Triggerbot.Release=v/1000 end })

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
MacroSection:Slider({ Name="Delay", Flag="macro_delay", Min=0, Max=500, Default=5, Decimals=1, Suffix="ms", Callback=function(v) GunMacro.Delay=v/1000 end })
MacroSection:Slider({ Name="Click Hold", Flag="macro_click_hold", Min=1, Max=200, Default=8, Decimals=1, Suffix="ms", Callback=function(v) GunMacro.ClickHold=v/1000 end })

-- ============================================================
-- LAY MACRO
-- ============================================================
local LayMacro = { Enabled=false, KnifeName="[Knife]", KnifeDelay=50, LayDelay=0 }
local layMasterOn = false
local laySeqToken = 0

local function getMainRemoteEvent()
    local RS = game:GetService("ReplicatedStorage")
    local mainRemotes = RS:FindFirstChild("MainRemotes")
    return mainRemotes and mainRemotes:FindFirstChild("MainRemoteEvent")
end

local function pressLeftShift()
    if VIM then
        pcall(function()
            VIM:SendKeyEvent(true,  Enum.KeyCode.LeftShift, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)
    else
        pcall(function()
            keypress(Enum.KeyCode.LeftShift); task.wait(0.05); keyrelease(Enum.KeyCode.LeftShift)
        end)
    end
end

local function equipLayKnife()
    local char = LocalPlayer.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local held = char:FindFirstChild(LayMacro.KnifeName)
    if held and held:IsA("Tool") then return end
    local bp = LocalPlayer:FindFirstChild("Backpack"); if not bp then return end
    local knife = bp:FindFirstChild(LayMacro.KnifeName)
    if knife and knife:IsA("Tool") then pcall(function() hum:EquipTool(knife) end) end
end

local function runLayMacro()
    laySeqToken = laySeqToken + 1
    local myToken = laySeqToken
    task.spawn(function()
        if LayMacro.LayDelay > 0 then
            task.wait(LayMacro.LayDelay / 1000)
            if myToken ~= laySeqToken or not LayMacro.Enabled then return end
        end
        local ev = getMainRemoteEvent()
        if ev then pcall(function() ev:FireServer("AnimationPack", "Lay") end) end
        if LayMacro.KnifeDelay > 0 then
            task.wait(LayMacro.KnifeDelay / 1000)
            if myToken ~= laySeqToken or not LayMacro.Enabled then return end
        end
        equipLayKnife()
        if myToken ~= laySeqToken or not LayMacro.Enabled then return end
        pressLeftShift()
    end)
end

LaySection:Toggle({
    Name = "Enabled", Flag = "lay_enabled", Default = false,
    Callback = function(state)
        layMasterOn = state and true or false
        LayMacro.Enabled = state and true or false
        if LayMacro.Enabled then runLayMacro() end
    end,
}):Keybind({
    Flag = "lay_key", Default = Enum.KeyCode.X, Mode = "Toggle",
    Callback = function(v)
        if not layMasterOn then return end
        if type(v) == "boolean" then
            LayMacro.Enabled = v
            if v then runLayMacro() end
        end
    end,
})
LaySection:Slider({ Name="Lay Delay",   Flag="lay_laydelay",   Min=0, Max=1000, Default=0,  Decimals=1, Suffix="ms", Callback=function(v) LayMacro.LayDelay=v end })
LaySection:Slider({ Name="Knife Delay", Flag="lay_knifedelay", Min=0, Max=1000, Default=50, Decimals=1, Suffix="ms", Callback=function(v) LayMacro.KnifeDelay=v end })

-- ============================================================
-- AMMO REDUCTION
-- ============================================================
local AmmoReduction = { Enabled=false, Times=2, ToolName="[Double-Barrel SG]" }
local ammoRedMasterOn = false

local function getAmmoReduceRemote()
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChild(AmmoReduction.ToolName)
        if tool and tool:IsA("Tool") then
            local ev = tool:FindFirstChild("RemoteEvent")
            if ev and ev:IsA("RemoteEvent") then return ev end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        local tool = bp:FindFirstChild(AmmoReduction.ToolName)
        if tool and tool:IsA("Tool") then
            local ev = tool:FindFirstChild("RemoteEvent")
            if ev and ev:IsA("RemoteEvent") then return ev end
        end
    end
end

local function runAmmoReduction()
    local ev = getAmmoReduceRemote(); if not ev then return end
    local n = math.clamp(math.floor(AmmoReduction.Times), 1, 2)
    for i = 1, n do
        pcall(function() ev:FireServer("Reduce") end)
        if i < n then task.wait() end
    end
end

AmmoRedSection:Toggle({
    Name = "Enabled", Flag = "ammored_enabled", Default = false,
    Callback = function(state)
        ammoRedMasterOn = state and true or false
        AmmoReduction.Enabled = state and true or false
        if AmmoReduction.Enabled then runAmmoReduction() end
    end,
}):Keybind({
    Flag = "ammored_key", Default = Enum.KeyCode.G, Mode = "Toggle",
    Callback = function(v)
        if not ammoRedMasterOn then return end
        if type(v) == "boolean" then
            AmmoReduction.Enabled = v
            if v then runAmmoReduction() end
        end
    end,
})
AmmoRedSection:Slider({ Name="Times", Flag="ammored_times", Min=1, Max=2, Default=2, Decimals=1, Callback=function(v) AmmoReduction.Times=math.clamp(math.floor(v+0.5),1,2) end })

-- ============================================================
-- ESP UI
-- ============================================================

-- ------------------------------------------------------------
-- TOGGLES
-- ------------------------------------------------------------
ESPSection:Toggle({
    Name = "Enabled", Flag = "esp_enabled", Default = false,
    Callback = function(v) Config.Enabled = v and true or false end,
})

ESPSection:Toggle({
    Name = "Show On Self", Flag = "esp_self", Default = false,
    Callback = function(v) Config.ShowOnSelf = v and true or false end,
})

-- ---- BOX (single colorpicker) ----
ESPSection:Toggle({
    Name = "Box", Flag = "esp_box", Default = false,
    Callback = function(v) Config.Box.Enable = v and true or false end,
}):Colorpicker({
    Flag = "esp_box_color", Default = Config.Box.Color,
    Callback = function(c) Config.Box.Color = c end,
})

-- ---- FILLED BOX (2 colorpickers -> use variable) ----
local filledBoxToggle = ESPSection:Toggle({
    Name = "Filled Box", Flag = "esp_filled", Default = false,
    Callback = function(v) Config.Box.Filled.Enable = v and true or false end,
})
filledBoxToggle:Colorpicker({
    Flag = "esp_filled_color1", Default = Config.Box.Filled.Gradient.Color.Start,
    Callback = function(c) Config.Box.Filled.Gradient.Color.Start = c end,
})
filledBoxToggle:Colorpicker({
    Flag = "esp_filled_color2", Default = Config.Box.Filled.Gradient.Color.End,
    Callback = function(c) Config.Box.Filled.Gradient.Color.End = c end,
})

-- ---- HEALTH BAR (toggle only) ----
ESPSection:Toggle({
    Name = "Health Bar", Flag = "esp_hp", Default = false,
    Callback = function(v) Config.Bars.Health.Enable = v and true or false end,
})

-- ---- ARMOR BAR (toggle only) ----
ESPSection:Toggle({
    Name = "Armor Bar", Flag = "esp_ar", Default = false,
    Callback = function(v) Config.Bars.Armor.Enable = v and true or false end,
})

-- ---- TEXT MASTER ----
ESPSection:Toggle({
    Name = "Text Enabled", Flag = "esp_text_master", Default = false,
    Callback = function(v) Config.Text.Enable = v and true or false end,
})

-- ---- NAME (single colorpicker) ----
ESPSection:Toggle({
    Name = "Name", Flag = "esp_text_name", Default = false,
    Callback = function(v) Config.Text.Name.Enable = v and true or false end,
}):Colorpicker({
    Flag = "esp_text_name_color", Default = Config.Text.Name.Color,
    Callback = function(c) Config.Text.Name.Color = c end,
})

-- ---- DISTANCE (single colorpicker) ----
ESPSection:Toggle({
    Name = "Distance", Flag = "esp_text_dist", Default = false,
    Callback = function(v) Config.Text.Studs.Enable = v and true or false end,
}):Colorpicker({
    Flag = "esp_text_dist_color", Default = Config.Text.Studs.Color,
    Callback = function(c) Config.Text.Studs.Color = c end,
})

-- ---- EQUIPPED TOOL (single colorpicker) ----
ESPSection:Toggle({
    Name = "Equipped Tool", Flag = "esp_text_tool", Default = false,
    Callback = function(v) Config.Text.Tool.Enable = v and true or false end,
}):Colorpicker({
    Flag = "esp_text_tool_color", Default = Config.Text.Tool.Color,
    Callback = function(c) Config.Text.Tool.Color = c end,
})

-- ------------------------------------------------------------
-- DROPDOWNS
-- ------------------------------------------------------------
ESPSection:Dropdown({
    Name = "Bar Position", Flag = "esp_bar_pos",
    Items = {"Left", "Right", "Top", "Bottom"},
    Default = "Left",
    Callback = function(v) Config.Bars.Health.Position = v end,
})

ESPSection:Dropdown({
    Name = "Name Type", Flag = "esp_text_nametype",
    Items = {"Display", "Username", "Both"},
    Default = "Display",
    Callback = function(v) Config.Text.Name.Type = v end,
})

-- ------------------------------------------------------------
-- SLIDERS
-- ------------------------------------------------------------
ESPSection:Slider({
    Name = "Max Distance", Flag = "esp_maxdist",
    Min = 0, Max = 10000, Default = 0, Decimals = 1, Suffix = " studs",
    Callback = function(v) Config.MaxDistance = v end,
})

-- ============================================================
-- ESP PREVIEW (Side 2 - next to ESP)
-- ============================================================
local ESPPreviewSection = VisualsPage:Section({Name = "ESP Preview", Side = 2})

local ESPPreview = {
    Enabled = true,
    SelectedImage = "Tung Tung Sahur",
    Images = {
        ["Tung Tung Sahur"] = {
            Url = "https://files.catbox.moe/quo16r.png",
            Width = 95, Height = 155, Zoom = 1.35, OffsetY = 0,
            DisplayName = "Tung Tung Sahur", Username = "TungTungSahur",
        },
        ["Local Player"] = {
            Url = "LOCAL_PLAYER_AVATAR",
            Width = 95, Height = 160, Zoom = 1.45, OffsetY = -2,
            DisplayName = nil, Username = nil,
        },
        ["Kawaii Anime Girl"] = {
            Url = "https://files.catbox.moe/bthscb.png",
            Width = 95, Height = 160, Zoom = 1.35, OffsetY = 0,
            DisplayName = "Kawaii Anime Girl", Username = "KawaiiAnimeGirl",
        },
    },
}

local previewContent = ESPPreviewSection.Items["Content"].Instance

local previewMain = Instance.new("Frame")
previewMain.Name = "ESPPreviewMain"
previewMain.Size = UDim2.new(1, -6, 0, 265)
previewMain.BackgroundColor3 = Color3.fromRGB(11, 12, 16)
previewMain.BackgroundTransparency = 1
previewMain.BorderSizePixel = 0
previewMain.ClipsDescendants = true
previewMain.Parent = previewContent
Instance.new("UICorner", previewMain).CornerRadius = UDim.new(0, 8)
local previewStroke = Instance.new("UIStroke", previewMain)
previewStroke.Color = Color3.fromRGB(48, 48, 56)
previewStroke.Thickness = 1
previewStroke.Transparency = 0.5

local centerHolder = Instance.new("Frame")
centerHolder.Name = "CenterHolder"
centerHolder.Size = UDim2.fromOffset(95, 155)
centerHolder.AnchorPoint = Vector2.new(0.5, 0.5)
centerHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
centerHolder.BackgroundTransparency = 1
centerHolder.Parent = previewMain

local imageMask = Instance.new("Frame")
imageMask.Name = "ImageMask"
imageMask.Size = UDim2.fromScale(1, 1)
imageMask.BackgroundTransparency = 1
imageMask.ClipsDescendants = true
imageMask.Parent = centerHolder

local previewImage = Instance.new("ImageLabel")
previewImage.Name = "PreviewImage"
previewImage.AnchorPoint = Vector2.new(0.5, 0.5)
previewImage.Position = UDim2.new(0.5, 0, 0.5, 0)
previewImage.Size = UDim2.fromScale(1.35, 1.35)
previewImage.BackgroundTransparency = 1
previewImage.ImageTransparency = 0
previewImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
previewImage.ScaleType = Enum.ScaleType.Fit
previewImage.Parent = imageMask

-- FILLED BOX (created before outlines so it sits behind them)
local bFilled = Instance.new("Frame")
bFilled.Name = "BoxFilled"
bFilled.Size = UDim2.fromScale(1, 1)
bFilled.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
bFilled.BackgroundTransparency = 0.3
bFilled.BorderSizePixel = 0
bFilled.Visible = false
bFilled.ZIndex = 1
bFilled.Parent = centerHolder
local bFilledGrad = Instance.new("UIGradient", bFilled)
bFilledGrad.Rotation = 0
bFilledGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Config.Box.Filled.Gradient.Color.Start),
    ColorSequenceKeypoint.new(1, Config.Box.Filled.Gradient.Color.End),
})

local bOutline = Instance.new("Frame")
bOutline.Name = "BoxOutline"
bOutline.Size = UDim2.new(1, 2, 1, 2)
bOutline.Position = UDim2.fromOffset(-1, -1)
bOutline.BackgroundTransparency = 1
bOutline.BorderSizePixel = 0
bOutline.ZIndex = 2
bOutline.Parent = centerHolder
local bOutStroke = Instance.new("UIStroke", bOutline)
bOutStroke.Color = Color3.fromRGB(0, 0, 0)
bOutStroke.Thickness = 1

local bMain = Instance.new("Frame")
bMain.Name = "BoxMain"
bMain.Size = UDim2.fromScale(1, 1)
bMain.BackgroundTransparency = 1
bMain.BorderSizePixel = 0
bMain.ZIndex = 3
bMain.Parent = centerHolder
local bMainStroke = Instance.new("UIStroke", bMain)
bMainStroke.Thickness = 1
bMainStroke.Color = Color3.fromRGB(255, 255, 255)

local bIn = Instance.new("Frame")
bIn.Name = "BoxInline"
bIn.Size = UDim2.new(1, -2, 1, -2)
bIn.Position = UDim2.fromOffset(1, 1)
bIn.BackgroundTransparency = 1
bIn.BorderSizePixel = 0
bIn.ZIndex = 4
bIn.Parent = centerHolder
local bInStroke = Instance.new("UIStroke", bIn)
bInStroke.Color = Color3.fromRGB(0, 0, 0)
bInStroke.Thickness = 1

local function makePreviewLabel()
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextStrokeTransparency = 0.15
    l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    l.TextSize = 11
    l.Font = Enum.Font.GothamBold
    l.TextColor3 = Color3.fromRGB(255, 255, 255)
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.ZIndex = 26
    l.Visible = false
    l.Parent = centerHolder
    return l
end

local lblName  = makePreviewLabel()
lblName.Size = UDim2.new(3, 0, 0, 14)
lblName.AnchorPoint = Vector2.new(0.5, 1)
lblName.Position = UDim2.new(0.5, 0, 0, -5)

local lblStuds = makePreviewLabel()
lblStuds.Size = UDim2.new(2, 0, 0, 14)
lblStuds.AnchorPoint = Vector2.new(0.5, 0)
lblStuds.Position = UDim2.new(0.5, 0, 1, 4)

local lblTool  = makePreviewLabel()
lblTool.Size = UDim2.new(2, 0, 0, 14)
lblTool.AnchorPoint = Vector2.new(0.5, 0)
lblTool.Position = UDim2.new(0.5, 0, 1, 17)

local function makePreviewBar(z)
    local outline = Instance.new("Frame")
    outline.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    outline.BorderSizePixel = 0
    outline.ZIndex = z
    outline.Visible = false
    outline.Parent = centerHolder
    local fill = Instance.new("Frame", outline)
    fill.BorderSizePixel = 0
    fill.Position = UDim2.fromOffset(1, 1)
    fill.Size = UDim2.new(1, -2, 1, -2)
    fill.ZIndex = z + 1
    local grad = Instance.new("UIGradient", fill)
    grad.Rotation = 90
    return outline, fill, grad
end

local hpOutline,  hpFill,  hpGrad  = makePreviewBar(35)
local armOutline, armFill, armGrad = makePreviewBar(25)

local function loadPreviewImage(url)
    if url == "LOCAL_PLAYER_AVATAR" then
        local lp = LocalPlayer
        if lp then
            local ok, thumb = pcall(function()
                return Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
            end)
            if ok and thumb then previewImage.Image = thumb end
        end
        return
    end

    if not isfolder("NLAssets") then makefolder("NLAssets") end
    local fname = url:gsub("[^%w]", "") .. ".png"
    local path  = "NLAssets/" .. fname

    if not isfile(path) then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and body then pcall(function() writefile(path, body) end) end
    end

    if isfile(path) then
        local ok, asset = pcall(function() return getcustomasset(path) end)
        if ok and asset then previewImage.Image = asset end
    end
end

local function applySelectedPreview()
    local cfg = ESPPreview.Images[ESPPreview.SelectedImage]
    if not cfg then return end
    centerHolder.Size   = UDim2.fromOffset(cfg.Width, cfg.Height)
    previewImage.Size   = UDim2.fromScale(cfg.Zoom, cfg.Zoom)
    previewImage.Position = UDim2.new(0.5, 0, 0.5, cfg.OffsetY or 0)
    loadPreviewImage(cfg.Url)
end

ESPPreviewSection:Dropdown({
    Name = "Preview Image", Flag = "esp_preview_image",
    Items = { "Tung Tung Sahur", "Local Player", "Kawaii Anime Girl" },
    Default = "Tung Tung Sahur",
    Callback = function(v)
        ESPPreview.SelectedImage = v
        applySelectedPreview()
    end,
})

applySelectedPreview()

RunService.RenderStepped:Connect(function()
    if not previewMain or not previewMain.Parent then return end
    previewMain.Visible = true

    local cfg = ESPPreview.Images[ESPPreview.SelectedImage]
    local boxW = (cfg and cfg.Width)  or 95
    local boxH = (cfg and cfg.Height) or 155

    -- ---- Box outline ----
    if Config.Box.Enable then
        bOutline.Visible  = true
        bMain.Visible     = true
        bIn.Visible       = true
        bMainStroke.Color = Config.Box.Color
    else
        bOutline.Visible = false
        bMain.Visible    = false
        bIn.Visible      = false
    end

    -- ---- Filled box ----
    if Config.Box.Enable and Config.Box.Filled.Enable then
        bFilled.Visible = true
        bFilled.BackgroundTransparency = Config.Box.Filled.Gradient.Transparency or 0.3
        if Config.Box.Filled.Gradient.Enable then
            bFilledGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Config.Box.Filled.Gradient.Color.Start),
                ColorSequenceKeypoint.new(1, Config.Box.Filled.Gradient.Color.End),
            })
            bFilledGrad.Rotation = math.sin(tick() * 2) * 180
        else
            bFilledGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Config.Box.Filled.Gradient.Color.Start),
                ColorSequenceKeypoint.new(1, Config.Box.Filled.Gradient.Color.End),
            })
            bFilledGrad.Rotation = 0
        end
    else
        bFilled.Visible = false
    end

    -- ---- Name text (respects Name Type: Display / Username / Both) ----
    if Config.Text.Enable and Config.Text.Name.Enable then
        lblName.Visible    = true
        lblName.TextColor3 = Config.Text.Name.Color

        local sel = ESPPreview.SelectedImage
        local displayName, username
        if sel == "Local Player" then
            displayName = LocalPlayer.DisplayName
            username    = LocalPlayer.Name
        else
            local c = ESPPreview.Images[sel]
            displayName = (c and c.DisplayName) or sel
            username    = (c and c.Username)    or sel
        end

        local t = Config.Text.Name.Type
        if t == "Display" then
            lblName.Text = displayName
        elseif t == "Username" then
            lblName.Text = username
        else
            lblName.Text = displayName .. " (@" .. username .. ")"
        end
    else
        lblName.Visible = false
    end

    -- ---- Distance text ----
    if Config.Text.Enable and Config.Text.Studs.Enable then
        lblStuds.Visible    = true
        lblStuds.TextColor3 = Config.Text.Studs.Color
        lblStuds.Text       = "[15m]"
    else
        lblStuds.Visible = false
    end

    -- ---- Equipped tool text ----
    if Config.Text.Enable and Config.Text.Tool.Enable then
        lblTool.Visible    = true
        lblTool.TextColor3 = Config.Text.Tool.Color
        lblTool.Text       = "[Revolver]"
    else
        lblTool.Visible = false
    end

    -- ---- Bar position (Left / Right / Top / Bottom) ----
    local pos = Config.Bars.Health.Position or "Left"

    -- Health bar
    if Config.Bars.Health.Enable then
        hpOutline.Visible = true
        hpGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Config.Bars.Health.Color1),
            ColorSequenceKeypoint.new(0.5, Config.Bars.Health.Color2),
            ColorSequenceKeypoint.new(1,   Config.Bars.Health.Color3),
        })

        if pos == "Left" then
            hpOutline.Size     = UDim2.new(0, 5, 1, 4)
            hpOutline.Position = UDim2.fromOffset(-8, -2)
        elseif pos == "Right" then
            hpOutline.Size     = UDim2.new(0, 5, 1, 4)
            hpOutline.Position = UDim2.fromOffset(boxW + 3, -2)
        elseif pos == "Top" then
            hpOutline.Size     = UDim2.new(1, 4, 0, 5)
            hpOutline.Position = UDim2.fromOffset(-2, -8)
        elseif pos == "Bottom" then
            hpOutline.Size     = UDim2.new(1, 4, 0, 5)
            hpOutline.Position = UDim2.fromOffset(-2, boxH + 3)
        end
    else
        hpOutline.Visible = false
    end

    -- Armor bar
    if Config.Bars.Armor.Enable then
        armOutline.Visible = true
        armGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Config.Bars.Armor.Color1),
            ColorSequenceKeypoint.new(0.5, Config.Bars.Armor.Color2),
            ColorSequenceKeypoint.new(1,   Config.Bars.Armor.Color3),
        })

        if pos == "Left" then
            armOutline.Size     = UDim2.new(0, 5, 1, 4)
            armOutline.Position = UDim2.fromOffset(-14, -2)
        elseif pos == "Right" then
            armOutline.Size     = UDim2.new(0, 5, 1, 4)
            armOutline.Position = UDim2.fromOffset(boxW + 10, -2)
        elseif pos == "Top" then
            armOutline.Size     = UDim2.new(1, 4, 0, 5)
            armOutline.Position = UDim2.fromOffset(-2, -14)
        elseif pos == "Bottom" then
            armOutline.Size     = UDim2.new(1, 4, 0, 5)
            armOutline.Position = UDim2.fromOffset(-2, boxH + 10)
        end
    else
        armOutline.Visible = false
    end
end)

-- ============================================================
-- AIMVIEW BEAM SYSTEM
-- ============================================================
local AIMVIEW_WEAPONS = { ["[Revolver]"]=true, ["[Double-Barrel SG]"]=true, ["[TacticalShotgun]"]=true }
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
    destroyAimViewBeam(); if not tool then return end
    local origin = getMuzzleAttachment(tool); if not origin then return end
    local terrain = workspace:FindFirstChildOfClass("Terrain"); if not terrain then return end
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
    local bodyEffects = char:FindFirstChild("BodyEffects"); if not bodyEffects then return end
    local mousePos = bodyEffects:FindFirstChild("MousePos"); if not mousePos then return end
    if aimViewBeam.Attachment1 then aimViewBeam.Attachment1.WorldPosition = mousePos.Value end
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
    searchText.Focused:Connect(function() tween(shStroke, 0.15, { Color = THEME.White, Transparency = 0.3 }) end)
    searchText.FocusLost:Connect(function() tween(shStroke, 0.15, { Color = THEME.Border, Transparency = 0.4 }) end)

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
        st.Color = THEME.BorderSoft; st.Transparency = 0.5
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
            if ui and ui.chip then styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, true, false) end
        end
        if forceESPreFresh then forceESPreFresh() end
        Library:Notification("Whitelisted " .. c .. " player(s).", 2)
    end)
    mkTopBtn("Unwhitelist All", function()
        local c = 0
        for plr, ui in pairs(PlayerRows) do
            if Whitelisted[plr] then Whitelisted[plr] = nil; c = c + 1 end
            if ui and ui.chip then styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, false, false) end
        end
        if forceESPreFresh then forceESPreFresh() end
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
    lfStroke.Color = THEME.Border; lfStroke.Transparency = 0.4

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
            local total, wl = 0, 0
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
    if hum then Camera.CameraType = Enum.CameraType.Custom; Camera.CameraSubject = hum end
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
    st.Color = THEME.BorderSoft; st.Transparency = 0.5
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
            if ui.nameLabel and ui.nameLabel.Text ~= p.DisplayName then ui.nameLabel.Text = p.DisplayName end
            styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, isWL, false)
        end
        local isSpec = (SpectateTarget == p)
        if ui.btnSpec then ui.btnSpec.Text = isSpec and "Stop" or "Spectate"; setRowBtnActive(ui.btnSpec, ui.specStroke, isSpec) end
        local isAim = (AimViewTarget == p)
        if ui.btnAim then ui.btnAim.Text = isAim and "Stop" or "AimView"; setRowBtnActive(ui.btnAim, ui.aimStroke, isAim) end
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
    chipStroke.Color = THEME.Border; chipStroke.Transparency = 0.6

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

    chip.MouseEnter:Connect(function() styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, true) end)
    chip.MouseLeave:Connect(function() styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, false) end)
    chip.MouseButton1Click:Connect(function()
        if Whitelisted[plr] then Whitelisted[plr] = nil else Whitelisted[plr] = true end
        styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, true)
        if forceESPreFresh then forceESPreFresh(plr) end
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
        row = row, chip = chip, nameLabel = nameLabel, track = track, knob = knob,
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
    local char = SpectateTarget.Character; if not char then return end
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
    local character = LocalPlayer.Character; if not character then return false end
    local held = character:FindFirstChild(toolName)
    if held and held:IsA("Tool") then return true end
    local humanoid = character:FindFirstChildOfClass("Humanoid"); if not humanoid then return false end
    local backpack = LocalPlayer:FindFirstChild("Backpack"); if not backpack then return false end
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
        local t = (p - lo):Dot(ld); if t < 0 then t = 0 end
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
-- GUN MACRO LOOP
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
-- TRIGGERBOT LOOP
-- ============================================================
task.spawn(function()
    while true do
        task.wait()
        if not Triggerbot.Enabled then continue end
        if hostDetectEnabled and not hostReady then continue end
        local target = Mouse.Target
        if not target or not isValidTarget(target) then continue end
        local character = LocalPlayer.Character; if not character then continue end
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
                if type(newVal) == "number" and type(prev) == "number" and newVal < prev then hostReady = true end
                prev = newVal
            end)
        end)
        if not ok or not conn then
            conn = val.Changed:Connect(function(newVal)
                if type(newVal) == "number" and type(prev) == "number" and newVal < prev then hostReady = true end
                prev = newVal
            end)
        end
        table.insert(colorConns, conn)
    end
    local function scanTool(tool)
        if not tool or tool.Name ~= HostDetection.ToolName then return end
        local ammo = tool:FindFirstChild(HostDetection.WatchAmmoName)
        if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then watchAmmo(ammo) end
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("IntValue") or d:IsA("NumberValue")) and d.Name == HostDetection.WatchAmmoName then watchAmmo(d) end
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
            if child:IsA("Tool") then task.wait(0.05); scanTool(child) end
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
task.spawn(function() for _ = 1, 6 do task.wait(0.5); refreshColorTargetList() end end)
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
-- AIMBOT LOOP
-- ============================================================
local function IsAlive(player)
    local char = player.Character; if not char then return false end
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
                if d <= MouseLock.FOV and d < shortest then shortest, closest = d, player end
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
    local aimPart = CurrentTarget.Character and CurrentTarget.Character:FindFirstChild(MouseLock.AimPart)
    if not aimPart then CurrentTarget = nil; return end
    local predicted = aimPart.Position + (aimPart.AssemblyLinearVelocity * MouseLock.Prediction)
    if MouseLock.Mode == "MouseLock" then
        local sp = Camera:WorldToScreenPoint(predicted)
        local dx = sp.X - Mouse.X
        local dy = sp.Y - Mouse.Y
        if math.sqrt(dx*dx + dy*dy) < MouseLock.Deadzone then return end
        mousemoverel(dx * MouseLock.Smoothness, dy * MouseLock.Smoothness)
    else
        local camPos = Camera.CFrame.Position
        local desired = CFrame.new(camPos, predicted)
        local alpha = math.clamp(MouseLock.Smoothness, 0.01, 1)
        local sp = Camera:WorldToScreenPoint(predicted)
        local dx = sp.X - Mouse.X
        local dy = sp.Y - Mouse.Y
        if math.sqrt(dx*dx + dy*dy) < MouseLock.Deadzone then return end
        if alpha >= 0.99 then Camera.CFrame = desired
        else Camera.CFrame = Camera.CFrame:Lerp(desired, alpha) end
    end
end)

-- ============================================================
-- ESP ENGINE
-- ============================================================
local ESPCache = {}

local function make_text(parent)
    local lbl = Instance.new("TextLabel")
    lbl.Parent = parent
    lbl.Size = UDim2.new(0, 260, 0, 14)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3 = Color3.new(0,0,0)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextYAlignment = Enum.TextYAlignment.Center
    lbl.AnchorPoint = Vector2.new(0.5, 0)
    lbl.ZIndex = 3
    return lbl
end

local function new_screengui(name)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.Parent = CoreGui
    return g
end

local function render(player)
    if not player then return end
    if ESPCache[player] then return end
    ESPCache[player] = { Box = {}, Bars = {}, Text = {}, Gui = {} }

    ESPCache[player].Box.Full = {
        Square  = Drawing.new("Square"),
        Inline  = Drawing.new("Square"),
        Outline = Drawing.new("Square"),
    }

    local gui = new_screengui("ESP_"..player.Name)
    ESPCache[player].Gui.Main = gui

    local filled = Instance.new("Frame")
    filled.Name = "Filled"
    filled.BackgroundTransparency = 1
    filled.BorderSizePixel = 0
    filled.Visible = false
    filled.ZIndex = 1
    filled.Parent = gui
    ESPCache[player].Box.Filled = filled

    ESPCache[player].Text.Name  = make_text(gui)
    ESPCache[player].Text.Studs = make_text(gui)
    ESPCache[player].Text.Tool  = make_text(gui)

    local hOutline = Instance.new("Frame")
    hOutline.Name = "HealthOutline"
    hOutline.BackgroundColor3 = Color3.new(0,0,0)
    hOutline.BorderSizePixel = 0
    hOutline.Visible = false
    hOutline.ZIndex = 2
    hOutline.Parent = gui
    local hFill = Instance.new("Frame")
    hFill.Name = "Fill"
    hFill.BorderSizePixel = 0
    hFill.Parent = hOutline
    local hGrad = Instance.new("UIGradient", hFill)
    hGrad.Rotation = 90
    hGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Config.Bars.Health.Color1),
        ColorSequenceKeypoint.new(0.5, Config.Bars.Health.Color2),
        ColorSequenceKeypoint.new(1,   Config.Bars.Health.Color3),
    })
    ESPCache[player].Bars.Health = { Outline = hOutline, Frame = hFill, Gradient = hGrad }

    local aOutline = Instance.new("Frame")
    aOutline.Name = "ArmorOutline"
    aOutline.BackgroundColor3 = Color3.new(0,0,0)
    aOutline.BorderSizePixel = 0
    aOutline.Visible = false
    aOutline.ZIndex = 2
    aOutline.Parent = gui
    local aFill = Instance.new("Frame")
    aFill.Name = "Fill"
    aFill.BorderSizePixel = 0
    aFill.Parent = aOutline
    local aGrad = Instance.new("UIGradient", aFill)
    aGrad.Rotation = 90
    aGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Config.Bars.Armor.Color1),
        ColorSequenceKeypoint.new(0.5, Config.Bars.Armor.Color2),
        ColorSequenceKeypoint.new(1,   Config.Bars.Armor.Color3),
    })
    ESPCache[player].Bars.Armor = { Outline = aOutline, Frame = aFill, Gradient = aGrad }
end

local function clear_esp(player)
    local c = ESPCache[player]
    if not c then return end
    if c.Box and c.Box.Full then
        pcall(function() c.Box.Full.Square.Visible  = false end)
        pcall(function() c.Box.Full.Outline.Visible = false end)
        pcall(function() c.Box.Full.Inline.Visible  = false end)
    end
    if c.Box and c.Box.Filled then pcall(function() c.Box.Filled.Visible = false end) end
    if c.Text then
        if c.Text.Name  then pcall(function() c.Text.Name.Visible  = false end) end
        if c.Text.Studs then pcall(function() c.Text.Studs.Visible = false end) end
        if c.Text.Tool  then pcall(function() c.Text.Tool.Visible  = false end) end
    end
    if c.Bars then
        if c.Bars.Health then
            pcall(function() c.Bars.Health.Frame.Visible   = false end)
            pcall(function() c.Bars.Health.Outline.Visible = false end)
        end
        if c.Bars.Armor then
            pcall(function() c.Bars.Armor.Frame.Visible   = false end)
            pcall(function() c.Bars.Armor.Outline.Visible = false end)
        end
    end
end

local function destroy_esp(player)
    local c = ESPCache[player]
    if not c then return end
    if c.Box and c.Box.Full then
        for _, dr in pairs(c.Box.Full) do
            pcall(function() dr.Visible = false end)
            pcall(function() dr:Remove() end)
        end
        c.Box.Full = nil
    end
    if c.Gui and c.Gui.Main then
        pcall(function() c.Gui.Main:Destroy() end)
    end
    ESPCache[player] = nil
end

local function update(player)
    local c = ESPCache[player]
    if not c then return end

    if player == LocalPlayer and not Config.ShowOnSelf then return clear_esp(player) end
    if Whitelisted[player] then return clear_esp(player) end
    if player.Parent == nil then return clear_esp(player) end

    local boxOn, textOn = Config.Box.Enable, Config.Text.Enable
    local hpOn,  arOn   = Config.Bars.Health.Enable, Config.Bars.Armor.Enable
    if not (boxOn or textOn or hpOn or arOn) then return clear_esp(player) end

    local char  = player.Character
    local lchar = LocalPlayer.Character
    if not char or not lchar then return clear_esp(player) end
    if not char.Parent then return clear_esp(player) end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if not hrp or not hum then return clear_esp(player) end

    local myRoot = lchar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return clear_esp(player) end
    local worldDist = (hrp.Position - myRoot.Position).Magnitude
    if Config.MaxDistance and Config.MaxDistance > 0 and worldDist > Config.MaxDistance then
        return clear_esp(player)
    end

    local tlx, tly, brx, bry = math.huge, math.huge, -math.huge, -math.huge
    local found = false
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local cf, s = part.CFrame, part.Size * 0.5
            local corners = {
                cf * Vector3.new( s.X,  s.Y,  s.Z), cf * Vector3.new( s.X,  s.Y, -s.Z),
                cf * Vector3.new( s.X, -s.Y,  s.Z), cf * Vector3.new( s.X, -s.Y, -s.Z),
                cf * Vector3.new(-s.X,  s.Y,  s.Z), cf * Vector3.new(-s.X,  s.Y, -s.Z),
                cf * Vector3.new(-s.X, -s.Y,  s.Z), cf * Vector3.new(-s.X, -s.Y, -s.Z),
            }
            for _, p in ipairs(corners) do
                local sp, on = Camera:WorldToViewportPoint(p)
                if on then
                    found = true
                    tlx = math.min(tlx, sp.X); tly = math.min(tly, sp.Y)
                    brx = math.max(brx, sp.X); bry = math.max(bry, sp.Y)
                end
            end
        end
    end
    if not found or tlx == math.huge then return clear_esp(player) end

    local boxPos  = Vector2.new(math.floor(tlx - 2), math.floor(tly - 2))
    local boxSize = Vector2.new(math.floor(brx - tlx + 4), math.floor(bry - tly + 4))
    local boxLeft, boxTop = boxPos.X, boxPos.Y
    local boxRight, boxBot = boxPos.X + boxSize.X, boxPos.Y + boxSize.Y
    local centerX = boxLeft + boxSize.X / 2

    if boxOn and Config.Box.Type == "Full" then
        local f = c.Box.Full
        f.Square.Visible   = true
        f.Square.Position  = boxPos
        f.Square.Size      = boxSize
        f.Square.Color     = Config.Box.Color
        f.Square.Thickness = 2
        f.Square.Filled    = false
        f.Square.ZIndex    = 9000000000

        f.Outline.Visible   = true
        f.Outline.Position  = boxPos - Vector2.new(1,1)
        f.Outline.Size      = boxSize + Vector2.new(2,2)
        f.Outline.Color     = Color3.new(0,0,0)
        f.Outline.Thickness = 1
        f.Outline.Filled    = false

        f.Inline.Visible   = true
        f.Inline.Position  = boxPos + Vector2.new(1,1)
        f.Inline.Size      = boxSize - Vector2.new(2,2)
        f.Inline.Color     = Color3.new(0,0,0)
        f.Inline.Thickness = 1
        f.Inline.Filled    = false

        if Config.Box.Filled.Enable then
            local filled = c.Box.Filled
            filled.Position = UDim2.new(0, boxPos.X, 0, boxPos.Y)
            filled.Size     = UDim2.new(0, boxSize.X, 0, boxSize.Y)
            filled.BackgroundTransparency = Config.Box.Filled.Gradient.Transparency or 0.3
            filled.BackgroundColor3 = Color3.fromRGB(255,255,255)
            filled.Visible = true
            filled.ZIndex  = 1
            if Config.Box.Filled.Gradient.Enable then
                local g = filled:FindFirstChild("Gradient") or Instance.new("UIGradient")
                g.Name = "Gradient"
                g.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Config.Box.Filled.Gradient.Color.Start),
                    ColorSequenceKeypoint.new(1, Config.Box.Filled.Gradient.Color.End),
                })
                g.Rotation = math.sin(tick()*2) * 180
                if not g.Parent then g.Parent = filled end
            end
        else
            c.Box.Filled.Visible = false
        end
    else
        local f = c.Box.Full
        f.Square.Visible  = false
        f.Outline.Visible = false
        f.Inline.Visible  = false
        c.Box.Filled.Visible = false
    end

    if hpOn then
        local hp = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        local prev = c.Bars.Health.LastHealth or hp
        local smooth = prev + (hp - prev) * 0.05
        c.Bars.Health.LastHealth = smooth

        local o, f = c.Bars.Health.Outline, c.Bars.Health.Frame
        local pos = Config.Bars.Health.Position
        o.Visible = true
        o.BackgroundTransparency = 0.2
        o.ZIndex = 2
        f.Visible = true
        f.ZIndex = 3

        if pos == "Left" then
            o.Position = UDim2.new(0, boxLeft - 7, 0, boxTop)
            o.Size     = UDim2.new(0, 5, 0, boxSize.Y + 2)
            f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1)
            f.Size     = UDim2.new(0, 3, 0, smooth * boxSize.Y)
        elseif pos == "Right" then
            o.Position = UDim2.new(0, boxRight + 3, 0, boxTop)
            o.Size     = UDim2.new(0, 5, 0, boxSize.Y + 2)
            f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1)
            f.Size     = UDim2.new(0, 3, 0, smooth * boxSize.Y)
        elseif pos == "Top" then
            o.Position = UDim2.new(0, boxLeft - 1, 0, boxTop - 7)
            o.Size     = UDim2.new(0, boxSize.X + 2, 0, 5)
            f.Position = UDim2.new(0, 1, 0, 1)
            f.Size     = UDim2.new(0, smooth * boxSize.X, 0, 3)
        elseif pos == "Bottom" then
            o.Position = UDim2.new(0, boxLeft - 1, 0, boxBot + 3)
            o.Size     = UDim2.new(0, boxSize.X + 2, 0, 5)
            f.Position = UDim2.new(0, 1, 0, 1)
            f.Size     = UDim2.new(0, smooth * boxSize.X, 0, 3)
        end
    else
        c.Bars.Health.Frame.Visible   = false
        c.Bars.Health.Outline.Visible = false
    end

    if arOn then
        local armorVal = getArmorValue(char, player)
        local armor = math.clamp(armorVal / ARMOR_MAX, 0, 1)
        local prev = c.Bars.Armor.LastArmor or armor
        local smooth = prev + (armor - prev) * 0.05
        c.Bars.Armor.LastArmor = smooth

        local o, f = c.Bars.Armor.Outline, c.Bars.Armor.Frame
        local pos = Config.Bars.Health.Position
        o.Visible = true
        o.BackgroundTransparency = 0.2
        o.ZIndex = 2
        f.Visible = true
        f.ZIndex = 3

        if pos == "Left" then
            o.Position = UDim2.new(0, boxLeft - 14, 0, boxTop)
            o.Size     = UDim2.new(0, 5, 0, boxSize.Y + 2)
            f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1)
            f.Size     = UDim2.new(0, 3, 0, smooth * boxSize.Y)
        elseif pos == "Right" then
            o.Position = UDim2.new(0, boxRight + 10, 0, boxTop)
            o.Size     = UDim2.new(0, 5, 0, boxSize.Y + 2)
            f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1)
            f.Size     = UDim2.new(0, 3, 0, smooth * boxSize.Y)
        elseif pos == "Top" then
            o.Position = UDim2.new(0, boxLeft - 1, 0, boxTop - 14)
            o.Size     = UDim2.new(0, boxSize.X + 2, 0, 5)
            f.Position = UDim2.new(0, 1, 0, 1)
            f.Size     = UDim2.new(0, smooth * boxSize.X, 0, 3)
        elseif pos == "Bottom" then
            o.Position = UDim2.new(0, boxLeft - 1, 0, boxBot + 10)
            o.Size     = UDim2.new(0, boxSize.X + 2, 0, 5)
            f.Position = UDim2.new(0, 1, 0, 1)
            f.Size     = UDim2.new(0, smooth * boxSize.X, 0, 3)
        end
    else
        c.Bars.Armor.Frame.Visible   = false
        c.Bars.Armor.Outline.Visible = false
    end

    if textOn then
        local nL, sL, tL = c.Text.Name, c.Text.Studs, c.Text.Tool

        if Config.Text.Name.Enable then
            nL.Visible = true
            nL.TextColor3 = Config.Text.Name.Color
            local t = Config.Text.Name.Type
            if t == "Display" then nL.Text = player.DisplayName
            elseif t == "Username" then nL.Text = player.Name
            else nL.Text = player.DisplayName.." (@"..player.Name..")" end
            nL.Position = UDim2.new(0, centerX, 0, boxTop - 18)
        else nL.Visible = false end

        local yCursor = boxBot + 4

        if Config.Text.Studs.Enable then
            sL.Visible = true
            sL.TextColor3 = Config.Text.Studs.Color
            sL.Text = string.format("[%.0fm]", worldDist * 0.28)
            sL.Position = UDim2.new(0, centerX, 0, yCursor)
            yCursor = yCursor + 14
        else sL.Visible = false end

        if Config.Text.Tool.Enable then
            tL.Visible = true
            tL.TextColor3 = Config.Text.Tool.Color
            local tool = char:FindFirstChildOfClass("Tool")
            tL.Text = tool and tool.Name or "none"
            tL.Position = UDim2.new(0, centerX, 0, yCursor)
        else tL.Visible = false end
    else
        c.Text.Name.Visible  = false
        c.Text.Studs.Visible = false
        c.Text.Tool.Visible  = false
    end
end

updateBarGradients = function()
    for _, c in pairs(ESPCache) do
        if c.Bars then
            if c.Bars.Health and c.Bars.Health.Gradient then
                c.Bars.Health.Gradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0,   Config.Bars.Health.Color1),
                    ColorSequenceKeypoint.new(0.5, Config.Bars.Health.Color2),
                    ColorSequenceKeypoint.new(1,   Config.Bars.Health.Color3),
                })
            end
            if c.Bars.Armor and c.Bars.Armor.Gradient then
                c.Bars.Armor.Gradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0,   Config.Bars.Armor.Color1),
                    ColorSequenceKeypoint.new(0.5, Config.Bars.Armor.Color2),
                    ColorSequenceKeypoint.new(1,   Config.Bars.Armor.Color3),
                })
            end
        end
    end
end

forceESPreFresh = function(plr)
    if plr then
        if ESPCache[plr] then
            if Config.Enabled and not Whitelisted[plr] then
                update(plr)
            else
                clear_esp(plr)
            end
        end
    else
        for p in pairs(ESPCache) do
            if Config.Enabled and not Whitelisted[p] then
                update(p)
            else
                clear_esp(p)
            end
        end
    end
end

local function attachCharRemoving(plr)
    if not plr then return end
    plr.CharacterRemoving:Connect(function()
        if ESPCache[plr] then clear_esp(plr) end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    render(p)
    attachCharRemoving(p)
end

Players.PlayerAdded:Connect(function(p)
    render(p)
    attachCharRemoving(p)
end)

Players.PlayerRemoving:Connect(function(p)
    destroy_esp(p)
end)

RunService.Heartbeat:Connect(function()
    if not Config.Enabled then
        for p in pairs(ESPCache) do clear_esp(p) end
        return
    end
    for p in pairs(ESPCache) do
        if p.Parent == nil then
            destroy_esp(p)
        else
            update(p)
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
        if WalkSpeed.Enabled and hum.WalkSpeed ~= WalkSpeed.Value then hum.WalkSpeed = WalkSpeed.Value end
    end)
end
local function setWalkSpeedState(state)
    local prev = WalkSpeed.Enabled
    WalkSpeed.Enabled = state and true or false
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if WalkSpeed.Enabled then if hum then hookWalkSpeedSignal(hum) end
    elseif prev and hum then hum.WalkSpeed = WalkSpeed.Default end
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
    local char = LocalPlayer.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
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
        else task.wait(0.1) end
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
    Callback = function(state) wsMasterOn = state and true or false; setWalkSpeedState(state) end,
}):Keybind({
    Flag = "ws_key", Default = Enum.KeyCode.H, Mode = "Toggle",
    Callback = function(v)
        if not wsMasterOn then return end
        if type(v) == "boolean" then setWalkSpeedState(v) end
    end,
})
MovementSection:Slider({ Name="Speed", Flag="ws_value", Min=16, Max=500, Default=16, Decimals=1, Callback=function(v) WalkSpeed.Value=v end })

local jpMasterOn = false
MovementSection:Toggle({
    Name = "JumpPower", Flag = "jp_enabled", Default = false,
    Callback = function(state) jpMasterOn = state and true or false; setJumpPowerState(state) end,
}):Keybind({
    Flag = "jp_key", Default = Enum.KeyCode.J, Mode = "Toggle",
    Callback = function(v)
        if not jpMasterOn then return end
        if type(v) == "boolean" then setJumpPowerState(v) end
    end,
})
MovementSection:Slider({ Name="Power", Flag="jp_value", Min=50, Max=500, Default=50, Decimals=1, Callback=function(v) JumpPower.Value=v end })

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
        if type(v) == "boolean" then GunNoclip.Enabled = v; GunNoclip.Active = v end
    end,
})
GunNoclipSection:Slider({ Name="Delay", Flag="gn_delay", Min=0, Max=1000, Default=50, Decimals=1, Suffix="ms", Callback=function(v) GunNoclip.Delay=v/1000 end })

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
        else task.wait(0.05) end
    end
end)

-- ============================================================
-- AUTO EAT
-- ============================================================
local AutoEatCfg = {
    Enabled = false, Delay = 0.5, ArmorMax = 200,
    FoodList = {"[Donut]","[Hamburger]","[HotDog]","[Pizza]","[Popcorn]","[Taco]"},
}
local function getArmorValueSelf()
    local wp = workspace:FindFirstChild("Players"); if not wp then return nil end
    local me = wp:FindFirstChild(LocalPlayer.Name); if not me then return nil end
    local be = me:FindFirstChild("BodyEffects"); if not be then return nil end
    local ar = be:FindFirstChild("Armor"); if not ar then return nil end
    return tonumber(ar.Value)
end
local aeMasterOn = false
AutoEatSection:Toggle({
    Name = "Enabled", Flag = "ae_enabled", Default = false,
    Callback = function(state) aeMasterOn = state and true or false; AutoEatCfg.Enabled = state and true or false end,
}):Keybind({
    Flag = "ae_key", Default = Enum.KeyCode.R, Mode = "Hold",
    Callback = function(v)
        if not aeMasterOn then return end
        if type(v) == "boolean" then AutoEatCfg.Enabled = v end
    end,
})
AutoEatSection:Slider({ Name="Delay", Flag="ae_delay", Min=0, Max=1000, Default=500, Decimals=1, Suffix="ms", Callback=function(v) AutoEatCfg.Delay=v/1000 end })

local function eatClickMouse1()
    if mouse1click then pcall(mouse1click); return end
    if mouse1down and mouse1up then pcall(function() mouse1down(); task.wait(0.03); mouse1up() end); return end
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
    local char = LocalPlayer.Character; if not char then return nil end
    for _, name in ipairs(AutoEatCfg.FoodList) do
        local t = char:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end
end
local function getBackpackFood()
    local bp = LocalPlayer:FindFirstChild("Backpack"); if not bp then return nil end
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
        local armor = getArmorValueSelf()
        if armor and armor >= AutoEatCfg.ArmorMax then task.wait(0.2); continue end
        local equipped = getEquippedFood()
        if equipped then
            eatClickMouse1()
            local delay = AutoEatCfg.Delay
            if delay > 0 then task.wait(delay) else task.wait() end
        else
            local food = getBackpackFood()
            if food then pcall(function() hum:EquipTool(food) end); task.wait(0.1)
            else task.wait(0.2) end
        end
    end
end)

-- ============================================================
-- AUTO ARMOR
-- ============================================================
local AutoArmor = {
    Enabled = false,
    ClickWait = 0.12,
    Clicks = 3,
    ArmorMax = 200,
    TargetPos = CFrame.new(-938, -29, 566),
    ShopIndex = 42,
}
local function getArmorShopClickDetector()
    local ignored = workspace:FindFirstChild("Ignored"); if not ignored then return nil end
    local shop = ignored:FindFirstChild("Shop"); if not shop then return nil end
    local children = shop:GetChildren()
    local model = children[AutoArmor.ShopIndex]; if not model then return nil end
    return model:FindFirstChildWhichIsA("ClickDetector", true)
end

local function runAutoArmor()
    if not AutoArmor.Enabled then return end

    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local armor = getArmorValueSelf()
    if armor and armor >= AutoArmor.ArmorMax then return end

    local cd = getArmorShopClickDetector()
    if not cd then return end

    local startCFrame = hrp.CFrame

    pcall(function()
        hrp.CFrame = AutoArmor.TargetPos
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)

    task.wait(0.15)

    for i = 1, AutoArmor.Clicks do
        if not AutoArmor.Enabled then break end

        char = LocalPlayer.Character
        if not char then break end
        hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then break end

        if not cd or not cd.Parent then
            cd = getArmorShopClickDetector()
            if not cd then break end
        end

        pcall(function() fireclickdetector(cd) end)
        task.wait(AutoArmor.ClickWait)
    end

    char = LocalPlayer.Character
    if char then
        local newHrp = char:FindFirstChild("HumanoidRootPart")
        if newHrp then
            pcall(function()
                newHrp.CFrame = startCFrame
                newHrp.AssemblyLinearVelocity  = Vector3.zero
                newHrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

local aaMasterOn = false
MiscellaneousSection:Toggle({
    Name = "Auto Armor", Flag = "aa_enabled", Default = false,
    Callback = function(state) aaMasterOn = state and true or false; AutoArmor.Enabled = state and true or false end,
}):Keybind({
    Flag = "aa_key", Default = Enum.KeyCode.B, Mode = "Toggle",
    Callback = function(v)
        if not aaMasterOn then return end
        if type(v) == "boolean" then AutoArmor.Enabled = v end
    end,
})

task.spawn(function()
    while true do
        if not AutoArmor.Enabled then task.wait(0.2); continue end
        pcall(runAutoArmor)
        task.wait(1)
    end
end)

-- ============================================================
-- HEADLESS / KORBLOX (Phantom Shell Method)
-- ============================================================
local Headless = { Enabled = false }
local Korblox  = { Enabled = false }

local function applyHeadlessToCharacter(char)
    if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    head.Transparency = 1
    pcall(function() head.LocalTransparencyModifier = 1 end)
    for _, d in ipairs(head:GetChildren()) do
        if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
    end
end

local function removeHeadlessFromCharacter(char)
    if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    head.Transparency = 0
    pcall(function() head.LocalTransparencyModifier = 0 end)
    for _, d in ipairs(head:GetChildren()) do
        if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 0 end
    end
end

local function setHeadlessState(state)
    Headless.Enabled = state and true or false
    local char = LocalPlayer.Character
    if Headless.Enabled then applyHeadlessToCharacter(char) else removeHeadlessFromCharacter(char) end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    if Headless.Enabled then task.wait(0.25); applyHeadlessToCharacter(char) end
end)

-- ---- PHANTOM LEG (Korblox) - FIXED ----
local function applyKorbloxToCharacter(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if hum.RigType == Enum.HumanoidRigType.R15 then
        local limbs = {
            {"RightLowerLeg", 902942093, true},
            {"RightUpperLeg", 902942096, false, 902843398},
            {"RightFoot",     902942089, true}
        }

        for _, info in ipairs(limbs) do
            local p = char:FindFirstChild(info[1])
            if p then
                if not p:GetAttribute("OriginalMeshId") then
                    p:SetAttribute("OriginalMeshId", p.MeshId)
                    p:SetAttribute("OriginalTextureId", p.TextureID)
                    p:SetAttribute("OriginalTransparency", p.Transparency)
                end

                p.MeshId = "http://www.roblox.com/asset/?id=" .. info[2]
                if info[3] then p.Transparency = 1 end
                if info[4] then
                    p.TextureID = "http://roblox.com/asset/?id=" .. info[4]
                end
            end
        end
    else
        local base = char:FindFirstChild("Right Leg")
        if not base then return end

        if not base:GetAttribute("OriginalTransparency") then
            base:SetAttribute("OriginalTransparency", base.Transparency)
        end

        base.Transparency = 1

        local shell = char:FindFirstChild("PhantomShell")
        if shell then shell:Destroy() end

        shell = Instance.new("Part")
        shell.Name = "PhantomShell"
        shell.Size = Vector3.new(1, 2, 1)
        shell.CanCollide = false
        shell.Massless = true
        shell.CFrame = base.CFrame * CFrame.new(0, 0.75, 0)
        shell.Parent = char

        local lock = Instance.new("WeldConstraint")
        lock.Part0 = shell
        lock.Part1 = base
        lock.Parent = shell

        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = "http://www.roblox.com/asset/?id=902942093"
        mesh.TextureId = "http://roblox.com/asset/?id=902843398"
        mesh.Scale = Vector3.new(0.85, 1.25, 0.85)
        mesh.Parent = shell
    end
end

local function removeKorbloxFromCharacter(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if hum.RigType == Enum.HumanoidRigType.R15 then
        local limbs = {"RightLowerLeg", "RightUpperLeg", "RightFoot"}
        for _, name in ipairs(limbs) do
            local p = char:FindFirstChild(name)
            if p then
                local origMesh = p:GetAttribute("OriginalMeshId")
                local origTex = p:GetAttribute("OriginalTextureId")
                local origTrans = p:GetAttribute("OriginalTransparency")

                if origMesh then p.MeshId = origMesh end
                if origTex then p.TextureID = origTex end
                if origTrans then p.Transparency = origTrans end

                p:SetAttribute("OriginalMeshId", nil)
                p:SetAttribute("OriginalTextureId", nil)
                p:SetAttribute("OriginalTransparency", nil)
            end
        end
    else
        local base = char:FindFirstChild("Right Leg")
        if base then
            local origTrans = base:GetAttribute("OriginalTransparency")
            if origTrans then base.Transparency = origTrans end
            base:SetAttribute("OriginalTransparency", nil)
        end

        local shell = char:FindFirstChild("PhantomShell")
        if shell then shell:Destroy() end
    end
end

local function setKorbloxState(state)
    Korblox.Enabled = state and true or false
    local char = LocalPlayer.Character
    if char then
        if Korblox.Enabled then applyKorbloxToCharacter(char) else removeKorbloxFromCharacter(char) end
    end
end

task.spawn(function()
    while task.wait(0.1) do
        if Korblox.Enabled then
            local char = LocalPlayer.Character
            if char then
                pcall(applyKorbloxToCharacter, char)
            end
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    if Korblox.Enabled then applyKorbloxToCharacter(char) end
end)

MiscellaneousSection:Toggle({ Name="Headless", Flag="misc_headless", Default=false, Callback=function(state) setHeadlessState(state) end })
MiscellaneousSection:Toggle({ Name="Korblox",  Flag="misc_korblox",  Default=false, Callback=function(state) setKorbloxState(state)  end })

-- ============================================================
-- NOTIFICATION / SAFETY
-- ============================================================
Library:Notification("Elytra | Closet loaded.", 5)

pcall(function()
    local RS = game:GetService("ReplicatedStorage")
    local mainRemotes = RS:FindFirstChild("MainRemotes")
    local gunEvent    = mainRemotes and mainRemotes:FindFirstChild("MainRemoteEvent")
    if gunEvent then gunEvent:FireServer("ChangeSettings", "GunSystem", "New") end
end)
