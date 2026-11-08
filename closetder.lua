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

-- ============================================================
-- UNLOAD STATE & TRACKERS
-- ============================================================
local Alive           = true
local TrackedConns    = {}
local TrackedDrawings = {}
local TrackedGuis     = {}
local doUnload

local function trackConn(c) if c then table.insert(TrackedConns, c) end; return c end
local function trackDraw(d) if d then table.insert(TrackedDrawings, d) end; return d end
local function trackGui(g)  if g then table.insert(TrackedGuis, g)  end; return g end

-- ============================================================
-- SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")

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

-- ============================================================
-- SHARED STATE
-- ============================================================
local MouseLock = {
    Enabled = false, Prediction = 0,
    AimPart = "Head", Smoothness = 0, Deadzone = 0,
    FOV = 0, VisibleFOV = false, FillFOV = false, Sticky = false,
    VisibleCheck = false,
    CircleColor = Color3.fromRGB(255, 255, 255),
    FillFOVColor = Color3.fromRGB(255, 255, 255),
    FillFOVTransparency = 0,
    Mode = "MouseLock",
}
local Triggerbot = {
    Enabled = false, Delay = 0, Release = 0,
    Blacklist = {"knife"},
    DefaultRange = math.huge,
    GunRanges = {
        ["[Revolver]"]         = 238,
        ["[Double-Barrel SG]"] = 50.5,
        ["[TacticalShotgun]"]  = 50.5,
    },
}
local GunMacro = {
    Enabled = false, Delay = 0, Active = false,
    Tools = {"[Double-Barrel SG]", "[TacticalShotgun]"},
    MaxRange = 50.5,
}
local KnifeJump = {
    Enabled     = false,
    KnifeName   = "Knife",
    BoostJP     = 60,
    Busy        = false,
}
local NoJumpCD = {
    Enabled   = false,
    ToolName  = "[Knife]",
    JpDefault = 50,
    JpKnife   = 60,
    Conns     = {},
    StepName  = "NoJumpCD_Force_" .. tostring(math.random(1, 1e9)),
}
local HostDetection = {
    Enabled = false,
    DelayMs = 0,
    TargetPlayer = nil,
    ToolName = "[Double-Barrel SG]",
    WatchAmmoName = "Ammo",
}
local hostReady = false
local hostDetectEnabled = false

local function localHasCombatGun()
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChildWhichIsA("Tool")
    if not tool then return false end
    local n = tool.Name
    return n == "[Double-Barrel SG]" or n == "[Revolver]" or n == "[TacticalShotgun]"
end
local attachLocalReloadWatcher   -- forward declared; defined in CORE HELPERS block
local clearLocalAmmoConns        -- forward declared; defined in CORE HELPERS block

local WalkSpeed = { Enabled = false, Value = 16, Default = 16 }
local JumpPower = { Enabled = false, Value = 50, Default = 50 }
local GunNoclip = { Enabled=false, Delay=0.05, Active=false }
local gnMasterOn = true
local gnToggle
local gn_setEnabled
local layMasterOn = true
local layToggle
local LayMacroRef
local runLayMacro
local InfiniteAmmo = { Enabled=false, ReloadRunning=false, WrapperInstalled=false, OriginalCanShoot=nil }

-- ============================================================
-- KEYBIND GUARD: returns true when key is "None" / unset
-- ============================================================
local function isKeybindNone(kb)
    if kb == nil then return true end
    if kb == Enum.KeyCode.Unknown then return true end
    if tostring(kb) == "Enum.KeyCode.Unknown" then return true end
    if type(kb) == "string" and (kb == "" or kb:lower() == "none" or kb:lower() == "unknown") then return true end
    return false
end


-- Range Extender State (also drives Client Redirection)
local RangeExtender = {
    Enabled  = false,
    Distance = 42,     -- pull/push distance
    FOV      = 45,
    TargetRange = 238, -- static fallback used by Client Redirection
    Guns = {
        ["[Revolver]"]         = { Range = 238, Distance = 238 },
        ["[Double-Barrel SG]"] = { Range = 53  },
        ["[TacticalShotgun]"]  = { Range = 53  },
    },
}
local re_activeTarget = nil
local re_state = nil

-- Returns the active RE range for a tool (or tool name), or nil if RE
-- shouldn't apply to it (master off or that gun's toggle off).
local function getRangeExtenderRange(toolOrName)
    if not RangeExtender.Enabled then return nil end
    local name = type(toolOrName) == "string" and toolOrName
              or (toolOrName and toolOrName.Name)
    if not name then return nil end
    local cfg = RangeExtender.Guns[name]
    if not cfg then return nil end
    return cfg.Range
end

-- Returns the pull/push distance for the currently held gun.
local function getRangeExtenderDistance(toolOrName)
    local name = type(toolOrName) == "string" and toolOrName
              or (toolOrName and toolOrName.Name)
    if not name then return RangeExtender.Distance end
    local cfg = RangeExtender.Guns[name]
    if cfg and cfg.Distance then return cfg.Distance end
    return RangeExtender.Distance
end

-- ============================================================
-- ESP CONFIG (Elytra v6 style)
-- ============================================================
local Config = {
    Enabled = false, ShowOnSelf = false, MaxDistance = 0, TextSize = 11,
    KnockCheck = false,
    Font = Enum.Font.GothamBold,
    BoxStyle = "2D", DistanceUnit = "Metres",
    Box = { Enable = false, Color = Color3.fromRGB(255, 255, 255) },
    Skeleton = { Enable = false, Color = Color3.fromRGB(255, 255, 255) },
    HeadCircle = { Enable = false, Color = Color3.fromRGB(255, 255, 255) },
    Text = {
        Enable = true,
        Name   = { Enable = true,  Type = "Display", Teamcheck = true, Color = Color3.fromRGB(255,255,255) },
        Studs  = { Enable = true,  Color = Color3.fromRGB(255,255,255) },
        Tool   = { Enable = true,  Color = Color3.fromRGB(255,255,255) },
        Health = { Enable = false, Color = Color3.fromRGB(0, 255, 0) },
        Armor  = { Enable = false, Color = Color3.fromRGB(0, 150, 255) },
        Flags  = { Enable = false },
    },
    -- Normalized offsets (fraction of box size) from default positions — set by ESP Preview drag
    Layout = {
        Name       = { X = 0, Y = 0 },
        HealthText = { X = 0, Y = 0 },
        ArmorText  = { X = 0, Y = 0 },
        Flags      = { X = 0, Y = 0 },
        Studs      = { X = 0, Y = 0 },
        Tool       = { X = 0, Y = 0 },
        HealthBar  = { X = 0, Y = 0 },
        ArmorBar   = { X = 0, Y = 0 },
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
            Position = "Left",
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


local function hasForceField(char)
    if not char then return false end
    if char:FindFirstChildOfClass("ForceField") then return true end
    local be = char:FindFirstChild("BodyEffects")
    if be then
        local ff = be:FindFirstChild("ForceField") or be:FindFirstChild("FF") or be:FindFirstChild("Forcefield")
        if ff then
            if ff:IsA("BoolValue") then return ff.Value == true end
            return true
        end
    end
    return false
end

-- Spawn/respawn protection: ignore player for 0.8s after CharacterAdded
-- Used by Triggerbot / Gun Macro / HBE / Client Redirection (via isCombatImmune)
local SpawnProtectUntil = {} -- [Player] = tick() expiry
local SPAWN_PROTECT_SEC = 0.8

local function markSpawnProtect(plr)
    if not plr or plr == LocalPlayer then return end
    SpawnProtectUntil[plr] = tick() + SPAWN_PROTECT_SEC
end

local function isSpawnProtected(plr)
    if not plr then return false end
    local untilT = SpawnProtectUntil[plr]
    if not untilT then return false end
    if tick() >= untilT then
        SpawnProtectUntil[plr] = nil
        return false
    end
    return true
end

-- Read KO / Dead from a BodyEffects folder (workspace.Players or Character)
local function bodyEffectsIsDown(be)
    if not be then return false end
    local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
    if ko then
        local kv = ko.Value
        if type(kv) == "boolean" and kv then return true end
        if type(kv) == "number" and kv > 0 then return true end
        if type(kv) == "string" then
            local s = kv:lower()
            if s ~= "" and s ~= "false" and s ~= "0" then return true end
        end
        if kv == true then return true end
    end
    local dead = be:FindFirstChild("Dead")
    if dead then
        local dv = dead.Value
        if dv == true then return true end
        if type(dv) == "number" and dv > 0 then return true end
    end
    return false
end

-- True while player is knocked / fully dead (do not shoot until they get up or respawn)
local function isPlayerKnockedOrDead(plr)
    if not plr then return true end
    local char = plr.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
        if bodyEffectsIsDown(char:FindFirstChild("BodyEffects")) then return true end
    end
    local ok, down = pcall(function()
        local playersFolder = workspace:FindFirstChild("Players")
        if not playersFolder then return false end
        local pFolder = playersFolder:FindFirstChild(plr.Name)
        if not pFolder then return false end
        return bodyEffectsIsDown(pFolder:FindFirstChild("BodyEffects"))
    end)
    if ok and down then return true end
    return false
end

-- True if Gun Macro / Triggerbot must not shoot this player right now
local function isCombatImmune(plr)
    if not plr then return true end
    if isSpawnProtected(plr) then return true end
    if isPlayerKnockedOrDead(plr) then return true end
    local char = plr.Character
    if not char then return true end
    if hasForceField(char) then return true end
    return false
end

-- Hook CharacterAdded for all players (and future joiners)
local function hookPlayerSpawnProtect(plr)
    if not plr or plr == LocalPlayer then return end
    if plr.Character then markSpawnProtect(plr) end
    trackConn(plr.CharacterAdded:Connect(function()
        markSpawnProtect(plr)
    end))
end
for _, plr in ipairs(Players:GetPlayers()) do
    hookPlayerSpawnProtect(plr)
end
trackConn(Players.PlayerAdded:Connect(function(plr)
    hookPlayerSpawnProtect(plr)
end))
trackConn(Players.PlayerRemoving:Connect(function(plr)
    SpawnProtectUntil[plr] = nil
end))

-- FORWARD DECLARATIONS
local CurrentTarget  = nil
local Whitelisted, AimViewTarget, SpectateTarget = {}, nil, nil
local hookColorAmmo, clearColorConnections
local forceESPreFresh
local updateBarGradients
local destroyAimViewBeam
local cr_restore
local setHeadlessState
local setKorbloxState
local stopInfiniteAmmo
local hb_restore
local re_restore

-- Cross-system mutual exclusion (CR vs Hitbox Expander)
local ClientRedirectionState = nil
local HitboxExpanderState    = nil
local crToggleRef            = nil
local hbToggleRef            = nil

local HBE_State = { ActiveTarget = nil }
local CR_State  = { ActiveTarget = nil }

-- ============================================================
-- SNAPLINE STATE (shared by Aimbot & Client Redirection)
-- ============================================================
local SnaplineState = {
    Aim = { Enabled = false, Color = Color3.fromRGB(255, 255, 255), Thickness = 1.2 },
    CR  = { Enabled = false, Color = Color3.fromRGB(255, 255, 255), Thickness = 1.2 },
}

-- Drawing objects for snaplines (created lazily)
local _snaplineAim, _snaplineCR, _snaplineAimGlow, _snaplineCRGlow

local function ensureSnaplines()
    if not _snaplineAim then
        pcall(function()
            _snaplineAimGlow = trackDraw(Drawing.new("Line"))
            _snaplineAimGlow.Visible   = false
            _snaplineAimGlow.Thickness = 3
            _snaplineAimGlow.Transparency = 0.6
            _snaplineAimGlow.Color     = Color3.fromRGB(255, 255, 255)

            _snaplineAim = trackDraw(Drawing.new("Line"))
            _snaplineAim.Visible   = false
            _snaplineAim.Thickness = 1.2
            _snaplineAim.Transparency = 0
            _snaplineAim.Color     = Color3.fromRGB(255, 255, 255)
        end)
    end
    if not _snaplineCR then
        pcall(function()
            _snaplineCRGlow = trackDraw(Drawing.new("Line"))
            _snaplineCRGlow.Visible   = false
            _snaplineCRGlow.Thickness = 3
            _snaplineCRGlow.Transparency = 0.6
            _snaplineCRGlow.Color     = Color3.fromRGB(255, 255, 255)

            _snaplineCR = trackDraw(Drawing.new("Line"))
            _snaplineCR.Visible   = false
            _snaplineCR.Thickness = 1.2
            _snaplineCR.Transparency = 0
            _snaplineCR.Color     = Color3.fromRGB(255, 255, 255)
        end)
    end
end

local function updateSnapline(lineObj, glowObj, enabled, targetPart, color, thickness)
    if not lineObj then return end
    if not enabled or not targetPart or not targetPart.Parent then
        pcall(function() lineObj.Visible = false end)
        if glowObj then pcall(function() glowObj.Visible = false end) end
        return
    end
    local sp, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
    if not onScreen or sp.Z <= 0 then
        pcall(function() lineObj.Visible = false end)
        if glowObj then pcall(function() glowObj.Visible = false end) end
        return
    end
    local mousePos = UserInputService:GetMouseLocation()
    local origin = mousePos  -- from mouse cursor
    local target = Vector2.new(sp.X, sp.Y)
    -- Glow layer
    if glowObj then
        pcall(function()
            glowObj.From  = origin
            glowObj.To    = target
            glowObj.Color = color
            glowObj.Thickness = (thickness or 1.2) + 2
            glowObj.Transparency = 0.55
            glowObj.Visible = true
        end)
    end
    -- Main line
    pcall(function()
        lineObj.From  = origin
        lineObj.To    = target
        lineObj.Color = color
        lineObj.Thickness = thickness or 1.2
        lineObj.Transparency = 0
        lineObj.Visible = true
    end)
end


-- ============================================================
-- TARGET ESP STATE
-- ============================================================
local TargetESP = {
    Enabled = false,
    Color   = Color3.fromRGB(255, 255, 255),
}

local ESPCache = {}
local destroy_esp

local SKELETON_R15 = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}
local SKELETON_R6 = {
    {"Head","Torso"},
    {"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
}

-- ============================================================
-- LIBRARY & UI SETUP
-- ============================================================
local Library
do
    local raw = game:HttpGet("https://raw.githubusercontent.com/AdamScripting67/cb/refs/heads/main/Colorbot%20Panel.lua")
    -- Instant menu drag (no 0.35s lag tween)
    raw = raw:gsub(
        "self:Tween%(%s*TweenInfo%.new%(0%.35, Enum%.EasingStyle%.Quart, Enum%.EasingDirection%.Out%),%s*{ Position = UDim2New%(0, NewX, 0, NewY%)%s*}%s*%)",
        "Gui.Position = UDim2New(0, NewX, 0, NewY)"
    )
    -- Block window drag while ESP preview elements are being dragged
    raw = raw:gsub(
        "if Dragging then%s*Set%(Input%)",
        "if Dragging and not (getgenv and getgenv().ElytraPreviewDragging) then Set(Input)"
    )
    -- Faster default tweens (sliders / UI feel instant)
    raw = raw:gsub("Time = 0%.25,", "Time = 0.01,")
    raw = raw:gsub("FadeSpeed = 0%.2,", "FadeSpeed = 0.05,")
    -- Tighter element spacing
    raw = raw:gsub("Padding = UDimNew%(0, 6%),", "Padding = UDimNew(0, 2),")
    raw = raw:gsub("Padding = UDimNew%(0, 8%),", "Padding = UDimNew(0, 2),")
    raw = raw:gsub("Padding = UDimNew%(0, 4%),", "Padding = UDimNew(0, 2),")
    raw = raw:gsub("Padding = UDimNew%(0, 5%),", "Padding = UDimNew(0, 2),")
    -- Use exact open size matching the menu layout (625x644)
    raw = raw:gsub(
        "local DefaultSize = IsMobile and Vector2New%(375, 400%) or Vector2New%(621, 542%)",
        "local DefaultSize = (Data and Data.Size and Vector2New(Data.Size.X.Offset, Data.Size.Y.Offset)) or (IsMobile and Vector2New(375, 400) or Vector2New(625, 644))"
    )
    -- Fallback if Data.Size not in scope at that line: force desktop default
    raw = raw:gsub(
        "Vector2New%(621, 542%)",
        "Vector2New(625, 644)"
    )
    Library = loadstring(raw)()
end

pcall(function()
    if Library.Tween then
        Library.Tween.Time = 0
        Library.Tween.Style = Enum.EasingStyle.Linear
        Library.Tween.Direction = Enum.EasingDirection.Out
    end
    Library.FadeSpeed = 0
end)

Library.Folders = {
    Directory = "getelytra",
    Configs   = "getelytra/Configs",
    Assets    = "getelytra/Assets",
}
for _, Value in pairs(Library.Folders) do
    if not isfolder(Value) then makefolder(Value) end
end

local GameName = "Unknown Game"
pcall(function()
    GameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
end)

local function buildWindowTitle()
    return string.format("/getelytra | %s | %s", GameName, os.date("%b %d %Y | %H:%M"))
end

-- Exact size measured from the menu screenshot (full combat layout visible)
local MENU_SIZE = Vector2.new(625, 644)

local Window = Library:Window({
    Name = buildWindowTitle(),
    Logo = "90363697817722",
    Size = UDim2.fromOffset(MENU_SIZE.X, MENU_SIZE.Y),
})

-- Force MainFrame to exact size on open (library may ignore Size without the patch)
task.defer(function()
    for _ = 1, 20 do
        task.wait(0.05)
        local applied = false
        pcall(function()
            local mf = Library.MainFrame
            if mf and mf:IsA("GuiObject") then
                mf.Size = UDim2.fromOffset(MENU_SIZE.X, MENU_SIZE.Y)
                applied = true
            end
        end)
        if applied then break end
    end
end)
local Watermark = Library:Watermark("/getelytra")
local KeybindList  = Library:KeybindList()

-- Compact UI + responsive drag
task.defer(function()
    task.wait(0.3)
    local function tighten(gui)
        if not gui then return end
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("UIListLayout") then
                local pad = d.Padding
                if pad and pad.Offset > 4 then
                    d.Padding = UDim.new(0, 3)
                end
            elseif d:IsA("UIPadding") then
                if d.PaddingTop.Offset > 6 then d.PaddingTop = UDim.new(0, 6) end
                if d.PaddingBottom.Offset > 6 then d.PaddingBottom = UDim.new(0, 6) end
                if d.PaddingLeft.Offset > 8 then d.PaddingLeft = UDim.new(0, 8) end
                if d.PaddingRight.Offset > 8 then d.PaddingRight = UDim.new(0, 8) end
            end
        end
    end
    pcall(function()
        for _, g in ipairs(game:GetService("CoreGui"):GetChildren()) do
            if g:IsA("ScreenGui") then tighten(g) end
        end
        local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, g in ipairs(pg:GetChildren()) do
                if g:IsA("ScreenGui") then tighten(g) end
            end
        end
        if gethui then
            for _, g in ipairs(gethui():GetChildren()) do
                if g:IsA("ScreenGui") then tighten(g) end
            end
        end
    end)
end)

task.spawn(function()
    local cachedLabel = nil
    local function looksLikeTitleLabel(d)
        if not d:IsA("TextLabel") then return false end
        local t = d.Text
        if type(t) ~= "string" then return false end
        return t:find("/getelytra", 1, true) ~= nil or (t:find("getelytra", 1, true) ~= nil)
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
    while Alive do
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
local ClientRedirectionSection = CombatPage:Section({Name = "Client Redirection", Side = 2})
local TriggerSection  = CombatPage:Section({Name = "Triggerbot",   Side = 2})
local GunMacroSection = CombatPage:Section({Name = "Gun Macro", Side = 2})
local HitboxExpanderSection = CombatPage:Section({Name = "Hitbox Expander", Side = 1})

local ESPSection      = VisualsPage:Section({Name = "ESP",         Side = 1})

-- Misc page layout:
local MovementSection = MiscPage:Section({Name = "Movement", Side = 1})
local RangeExtenderSection = MiscPage:Section({Name = "Range Extender", Side = 1})
local MiscellaneousSection = MiscPage:Section({Name = "Misc", Side = 2})

local PlayerListSec   = PlayersPage:Section({Name = "Players",     Side = 1})

-- ============================================================
-- AIMBOT UI
-- ============================================================
do
    local aimMasterOn = true
    local aimToggle
    local function setAimbotState(v)
        MouseLock.Enabled = v and true or false
        if not MouseLock.Enabled then CurrentTarget = nil end
    end

    aimToggle = AimbotSection:Toggle({
        Name = "Enabled", Flag = "aim_enabled", Default = false,
        Callback = function(state)
            aimMasterOn = state and true or false
            setAimbotState(state)
        end,
    })
    aimToggle:Keybind({
        Flag = "aim_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not aimMasterOn then return end
            -- Do not activate if keybind is None/unset
            do
                local _kb = Library and Library.Flags and Library.Flags["aim_key"]
                if isKeybindNone(_kb) then return end
            end
            setAimbotState(v)
            if aimToggle and type(aimToggle.SetValue) == "function" then
                pcall(function() aimToggle:SetValue(v) end)
            end
        end,
    })

    AimbotSection:Dropdown({
        Name = "Mode", Flag = "aim_mode",
        Items = {"MouseLock", "CamLock"},
        Default = "MouseLock",
        Callback = function(v) MouseLock.Mode = v or "MouseLock"; CurrentTarget = nil end,
    })
    AimbotSection:Slider({ Name="FOV", Flag="aim_fov", Min=0, Max=1000, Default=0, Decimals=1, Callback=function(v) MouseLock.FOV=v end })
    AimbotSection:Slider({ Name="Smoothness", Flag="aim_smooth", Min=0, Max=100, Default=0, Decimals=1, Callback=function(v) MouseLock.Smoothness=v/100 end })
    AimbotSection:Slider({ Name="Prediction", Flag="aim_prediction", Min=0, Max=50, Default=0, Decimals=1, Callback=function(v) MouseLock.Prediction=v/100 end })
    AimbotSection:Slider({ Name="Deadzone", Flag="aim_deadzone", Min=0, Max=50, Default=0, Decimals=1, Callback=function(v) MouseLock.Deadzone=v end })
    AimbotSection:Dropdown({
        Name = "Aim Part", Flag = "aim_part",
        Items = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso"},
        Default = "Head",
        Callback = function(v) MouseLock.AimPart = v end,
    })
    local aimVisibleFOVToggle = AimbotSection:Toggle({ Name="Show FOV", Flag="aim_visible_fov", Default=false, Callback=function(v) MouseLock.VisibleFOV=v end })
    aimVisibleFOVToggle:Colorpicker({
        Flag = "aim_fov_circle_color", Default = MouseLock.CircleColor,
        Callback = function(c)
            MouseLock.CircleColor = c
        end,
    })
    local aimFillFOVToggle = AimbotSection:Toggle({ Name="Fill FOV", Flag="aim_fill_fov", Default=false, Callback=function(v) MouseLock.FillFOV=v end })
    aimFillFOVToggle:Colorpicker({
        Flag = "aim_fill_fov_color", Default = MouseLock.FillFOVColor,
        Callback = function(c) MouseLock.FillFOVColor = c end,
    })
    AimbotSection:Slider({
        Name = "Fill FOV Transparency", Flag = "aim_fill_fov_trans",
        Min = 0, Max = 100, Default = 0, Decimals = 1,
        Callback = function(v) MouseLock.FillFOVTransparency = v / 100 end,
    })
    AimbotSection:Toggle({ Name="Sticky", Flag="aim_sticky", Default=false, Callback=function(v) MouseLock.Sticky=v end })
    AimbotSection:Toggle({
        Name = "Visible Check", Flag = "aim_visible", Default = false,
        Callback = function(v) MouseLock.VisibleCheck = v and true or false end,
    })
    local aimSnapToggle = AimbotSection:Toggle({
        Name = "Snapline", Flag = "aim_snapline", Default = false,
        Callback = function(v)
            ensureSnaplines()
            SnaplineState.Aim.Enabled = v and true or false
        end,
    })
    aimSnapToggle:Colorpicker({
        Flag = "aim_snapline_color", Default = SnaplineState.Aim.Color,
        Callback = function(c)
            SnaplineState.Aim.Color = c
            if _snaplineAim then pcall(function() _snaplineAim.Color = c end) end
            if _snaplineAimGlow then pcall(function() _snaplineAimGlow.Color = c end) end
        end,
    })
end

-- ============================================================
-- CLIENT REDIRECTION
-- ============================================================
do
        local ClientRedirection = {
        Enabled            = false,
        VisibleCheck       = false,
        ShowFOV            = false,
        FillFOV            = false,
        FOV                = 0,
        FOVColor           = Color3.fromRGB(255, 255, 255),
        FillFOVColor       = Color3.fromRGB(255, 255, 255),
        FillFOVTransparency = 0,
    }
    ClientRedirectionState = ClientRedirection

    local REDIRECT_DISTANCE = 42

    local cr_activeTarget = nil
    local cr_state        = nil

        local cr_FOVCircle
    local cr_FOVCircleFill
    pcall(function()
        local c = Drawing.new("Circle")
        if c then
            cr_FOVCircle = trackDraw(c)
            c.Thickness, c.NumSides = 1, 64
            c.Filled, c.Visible     = false, false
            c.Color, c.Transparency = Color3.fromRGB(255, 255, 255), 0.8
            c.Position              = Vector2.new(0, 0)
            c.Radius                = ClientRedirection.FOV
        end
    end)
    pcall(function()
        local cf = Drawing.new("Circle")
        if cf then
            cr_FOVCircleFill = trackDraw(cf)
            cf.Thickness, cf.NumSides = 0, 64
            cf.Filled = true
            cf.Visible = false
            cf.Color = Color3.fromRGB(255, 255, 255)
            cf.Transparency = 0.5
            cf.Position = Vector2.new(0, 0)
            cf.Radius = ClientRedirection.FOV
        end
    end)

    local function cr_getHitbox(char)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local att = hrp:FindFirstChild("RootAttachment")
        if att then
            local hb = att:FindFirstChild("Hitbox")
            if hb then return hb end
        end
        for _, v in ipairs(char:GetDescendants()) do
            if v.Name == "Hitbox" then return v end
        end
        return nil
    end

    local function cr_isVisible(char)
        local ref = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not ref then return false end
        local origin = Camera.CFrame.Position
        local dir = ref.Position - origin
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { char }
        if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
        params.FilterDescendantsInstances = filter
        local hit = workspace:Raycast(origin, dir, params)
        if not hit or hit.Instance:IsDescendantOf(char) then return true end
        return false
    end

    local function cr_isKnocked(plr)
        if not plr then return false end
        local ok, knocked = pcall(function()
            local playersFolder = workspace:FindFirstChild("Players")
            if not playersFolder then return false end
            local pFolder = playersFolder:FindFirstChild(plr.Name)
            if not pFolder then return false end
            local bodyEffects = pFolder:FindFirstChild("BodyEffects")
            if not bodyEffects then return false end
            local ko = bodyEffects:FindFirstChild("K.O") or bodyEffects:FindFirstChild("KO")
            if not ko then return false end
            if ko:IsA("BoolValue") then return ko.Value
            elseif ko:IsA("IntValue") or ko:IsA("NumberValue") then return ko.Value > 0
            elseif ko:IsA("StringValue") then
                local v = ko.Value
                return v ~= "" and v ~= "false" and v ~= "0"
            end
            return ko.Value == true
        end)
        return ok and knocked == true
    end

    local function cr_getCursorWorldPoint(exclude)
        local unitRay = Mouse.UnitRay
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclude or {}
        local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, params)
        if hit then return hit.Position end
        return unitRay.Origin + unitRay.Direction * 5000
    end

    cr_restore = function()
        if cr_state then
            pcall(function()
                if cr_state.hitbox and cr_state.hitbox.Parent then
                    if cr_state.hitbox:IsA("BasePart") then
                        cr_state.hitbox.CFrame   = cr_state.origCFrame
                        cr_state.hitbox.Anchored = cr_state.origAnchored
                    elseif cr_state.hitbox:IsA("Attachment") then
                        cr_state.hitbox.WorldCFrame = cr_state.origCFrame
                    end
                    for _, j in ipairs(cr_state.brokenJoints) do
                        if j.joint and j.joint.Parent then
                            j.joint.Part0 = j.part0
                            j.joint.Part1 = j.part1
                        end
                    end
                end
            end)
        end
        cr_activeTarget = nil
        cr_state        = nil
        CR_State.ActiveTarget = nil
    end

    local function cr_setup(plr)
        if re_restore then pcall(re_restore) end
        cr_restore()
        if not plr then return end
        if cr_isKnocked(plr) then return end
        local char = plr.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local hitbox = cr_getHitbox(char)
        if not hitbox then return end

        local origAnchored = nil
        local brokenJoints = {}
        if hitbox:IsA("BasePart") then
            origAnchored = hitbox.Anchored
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("JointInstance") and (v.Part0 == hitbox or v.Part1 == hitbox) then
                    table.insert(brokenJoints, {joint = v, part0 = v.Part0, part1 = v.Part1})
                    v.Part0 = nil
                    v.Part1 = nil
                end
            end
            hitbox.Anchored = true
        end

        cr_state = {
            char = char,
            hrp = hrp,
            hitbox = hitbox,
            origCFrame = hitbox:IsA("BasePart") and hitbox.CFrame or hitbox.WorldCFrame,
            origAnchored = origAnchored,
            brokenJoints = brokenJoints,
        }
        cr_activeTarget = plr
        CR_State.ActiveTarget = plr
    end

    local function cr_getClosestToMouse()
        local myChar = LocalPlayer.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return nil end

        local mousePos = UserInputService:GetMouseLocation()
        local best, bestDist = nil, math.huge

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer or Whitelisted[plr] then continue end
            if isCombatImmune(plr) then continue end
            local char = plr.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            if not cr_getHitbox(char) then continue end
            if cr_isKnocked(plr) then continue end

            local distToPlayer = (myHrp.Position - hrp.Position).Magnitude
            local closestMax = RangeExtender.TargetRange
            if RangeExtender.Enabled then
                local tool = myChar:FindFirstChildWhichIsA("Tool")
                local reR = getRangeExtenderRange(tool)
                if reR then closestMax = reR end
            end
            if distToPlayer > closestMax then continue end
            if ClientRedirection.VisibleCheck and not cr_isVisible(char) then continue end

            local minDist = math.huge
            for _, pName in ipairs({"Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso"}) do
                local part = char:FindFirstChild(pName)
                if part and part:IsA("BasePart") then
                    local sp = Camera:WorldToScreenPoint(part.Position)
                    if sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                        if d < minDist then minDist = d end
                    end
                end
            end

            if minDist > ClientRedirection.FOV then continue end
            if minDist < bestDist then
                best, bestDist = plr, minDist
            end
        end
        return best
    end

    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive or not ClientRedirection.Enabled then
            if cr_state then cr_restore() end
            return
        end

        local closest = cr_getClosestToMouse()
        if closest ~= cr_activeTarget then cr_setup(closest) end
        if cr_activeTarget and cr_state and cr_activeTarget.Character ~= cr_state.char then
            cr_setup(cr_activeTarget)
        end

        if not cr_activeTarget or not cr_state then return end
        if not cr_state.hitbox or not cr_state.hitbox.Parent then cr_restore(); return end

        local myChar = LocalPlayer.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end

        -- Actual studs between local player and target (never pull closer than real distance)
        local distToTarget = (myHrp.Position - cr_state.hrp.Position).Magnitude

        -- Max allowed range: Range Extender gun range when RE is on, else TargetRange fallback
        local maxRange = RangeExtender.TargetRange
        if RangeExtender.Enabled then
            local crTool = myChar:FindFirstChildWhichIsA("Tool")
            local reRange = getRangeExtenderRange(crTool)
            if reRange then maxRange = reRange end
        end
        if distToTarget > maxRange then cr_restore(); return end

        local cursorWorld = cr_getCursorWorldPoint({ LocalPlayer.Character, cr_state.char })
        if not cursorWorld then return end

        local myPos = myHrp.Position
        local dir = cursorWorld - myPos
        if dir.Magnitude < 0.01 then dir = myHrp.CFrame.LookVector else dir = dir.Unit end

        -- Place hitbox at the target's REAL distance along the aim ray (exact studs)
        local redirectDist = distToTarget
        local displacedPos = myPos + dir * redirectDist
        local displacedCFrame = CFrame.new(displacedPos) * cr_state.hrp.CFrame.Rotation

        if cr_state.hitbox:IsA("BasePart") then
            cr_state.hitbox.CFrame = displacedCFrame
        elseif cr_state.hitbox:IsA("Attachment") then
            cr_state.hitbox.WorldCFrame = displacedCFrame
        end
    end))

        trackConn(RunService.RenderStepped:Connect(function()
        if not Alive then return end
        local crFovActive = ClientRedirection.ShowFOV
        if cr_FOVCircle then
            if crFovActive then
                cr_FOVCircle.Visible  = true
                cr_FOVCircle.Position = UserInputService:GetMouseLocation()
                cr_FOVCircle.Radius   = ClientRedirection.FOV
                cr_FOVCircle.Color    = ClientRedirection.FOVColor
            else
                cr_FOVCircle.Visible = false
            end
        end
        if cr_FOVCircleFill then
            if crFovActive and ClientRedirection.FillFOV then
                cr_FOVCircleFill.Visible      = true
                cr_FOVCircleFill.Position     = UserInputService:GetMouseLocation()
                cr_FOVCircleFill.Radius       = ClientRedirection.FOV
                cr_FOVCircleFill.Color        = ClientRedirection.FillFOVColor
                cr_FOVCircleFill.Transparency = ClientRedirection.FillFOVTransparency
            else
                cr_FOVCircleFill.Visible = false
            end
        end
    end))

    task.spawn(function()
        local CR_RESET_INTERVAL = 120
        while Alive do
            task.wait(CR_RESET_INTERVAL)
            if not Alive then break end
            if not ClientRedirection.Enabled then continue end
            local prevTarget = cr_activeTarget
            pcall(cr_restore)
            if ClientRedirection.Enabled and prevTarget and prevTarget.Parent then
                task.wait()
                if ClientRedirection.Enabled then
                    pcall(function() cr_setup(prevTarget) end)
                end
            end
        end
    end)

    local crMasterOn = true

    local function setCRState(state)
        ClientRedirection.Enabled = state and true or false
        if state then
            if HitboxExpanderState and HitboxExpanderState.Enabled then
                HitboxExpanderState.Enabled = false
                if hb_restore then pcall(hb_restore) end
                if hbToggleRef then pcall(function() hbToggleRef:SetValue(false) end) end
            end
        else
            cr_restore()
        end
    end

    crToggleRef = ClientRedirectionSection:Toggle({
        Name = "Enabled", Flag = "cr_enabled", Default = false,
        Callback = function(state)
            if state and HitboxExpanderState and HitboxExpanderState.Enabled then
                Library:Notification("Disable Hitbox Expander first.", 2)
                if crToggleRef and type(crToggleRef.SetValue) == "function" then
                    pcall(function() crToggleRef:SetValue(false) end)
                end
                return
            end
            crMasterOn = state and true or false
            setCRState(state)
        end,
    })
    
    crToggleRef:Keybind({
        Flag = "cr_key", Default = Enum.KeyCode.Unknown, Mode = "Hold",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not crMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["cr_key"]
                if isKeybindNone(_kb) then return end
            end
            if v and HitboxExpanderState and HitboxExpanderState.Enabled then
                Library:Notification("Disable Hitbox Expander first.", 2)
                return
            end
            setCRState(v)
        end,
    })

    ClientRedirectionSection:Slider({
        Name = "FOV", Flag = "cr_fov",
        Min = 0, Max = 500, Default = 0, Decimals = 1,
        Callback = function(v) ClientRedirection.FOV = v end,
    })

    local crShowFOVToggle = ClientRedirectionSection:Toggle({
        Name = "Show FOV", Flag = "cr_showfov", Default = false,
        Callback = function(v) ClientRedirection.ShowFOV = v and true or false end,
    })
    
    crShowFOVToggle:Colorpicker({
        Flag = "cr_fov_color", Default = ClientRedirection.FOVColor,
        Callback = function(c) ClientRedirection.FOVColor = c end,
    })
        local crFillFOVToggle = ClientRedirectionSection:Toggle({
        Name = "Fill FOV", Flag = "cr_fill_fov", Default = false,
        Callback = function(v) ClientRedirection.FillFOV = v and true or false end,
    })
    crFillFOVToggle:Colorpicker({
        Flag = "cr_fill_fov_color", Default = Color3.fromRGB(255,255,255),
        Callback = function(c) ClientRedirection.FillFOVColor = c end,
    })
    ClientRedirectionSection:Slider({
        Name = "Fill FOV Transparency", Flag = "cr_fill_fov_trans",
        Min = 0, Max = 100, Default = 0, Decimals = 1,
        Callback = function(v) ClientRedirection.FillFOVTransparency = v / 100 end,
    })
    
    ClientRedirectionSection:Toggle({
        Name = "Visible Check", Flag = "cr_visible", Default = false,
        Callback = function(v) ClientRedirection.VisibleCheck = v and true or false end,
    })
    local crSnapToggle = ClientRedirectionSection:Toggle({
        Name = "Snapline", Flag = "cr_snapline", Default = false,
        Callback = function(v)
            ensureSnaplines()
            SnaplineState.CR.Enabled = v and true or false
        end,
    })
    crSnapToggle:Colorpicker({
        Flag = "cr_snapline_color", Default = SnaplineState.CR.Color,
        Callback = function(c)
            SnaplineState.CR.Color = c
            if _snaplineCR then pcall(function() _snaplineCR.Color = c end) end
            if _snaplineCRGlow then pcall(function() _snaplineCRGlow.Color = c end) end
        end,
    })
end

-- ============================================================
-- TRIGGERBOT & HOST DETECTION
-- ============================================================
do
    local trigMasterOn = true
    local trigToggle
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

    trigToggle = TriggerSection:Toggle({
        Name = "Enabled", Flag = "trig_enabled", Default = false,
        Callback = function(state)
            trigMasterOn = state and true or false
            Triggerbot.Enabled = state and true or false
            hostReady = false
        end,
    })
    trigToggle:Keybind({
        Flag = "trig_key", Default = Enum.KeyCode.Unknown, Mode = "Hold",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not trigMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["trig_key"]
                if isKeybindNone(_kb) then return end
            end
            Triggerbot.Enabled = v
            -- Always clear cached host shot on keybind edge so a prior host shot
            -- cannot fire after the user starts holding the bind.
            hostReady = false
        end,
    })
    TriggerSection:Slider({ Name="Delay", Flag="trig_delay", Min=0, Max=1000, Default=0, Decimals=1, Suffix="ms", Callback=function(v) Triggerbot.Delay=v/1000 end })
    TriggerSection:Slider({ Name="Release", Flag="trig_release", Min=0, Max=1000, Default=0, Decimals=1, Suffix="ms", Callback=function(v) Triggerbot.Release=v/1000 end })

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

    TriggerSection:Toggle({
        Name = "Host Detection", Flag = "trig_hostdetect", Default = false,
        Callback = function(state)
            hostDetectEnabled = state and true or false
            HostDetection.Enabled = hostDetectEnabled
            hostReady = false
            if hostDetectEnabled then
                if HostDetection.TargetPlayer then hookColorAmmo(HostDetection.TargetPlayer) end
                if attachLocalReloadWatcher then pcall(attachLocalReloadWatcher) end
            else
                clearColorConnections()
                if clearLocalAmmoConns then pcall(clearLocalAmmoConns) end
            end
            setElVisible(HostPlayerDropdown, hostDetectEnabled)
            setElVisible(HostDelaySlider,    hostDetectEnabled)
        end,
    })

    -- Ammo Reduction (fixed to 2 times, moved from Misc)
    do
        local AmmoReduction = { Enabled = false, Times = 2, ToolName = "[Double-Barrel SG]" }
        local ammoRedMasterOn = true
        local ammoRedToggle

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
            local ev = getAmmoReduceRemote()
            if not ev then return end
            for i = 1, 2 do
                pcall(function() ev:FireServer("Reduce") end)
                if i < 2 then task.wait() end
            end
        end

        ammoRedToggle = TriggerSection:Toggle({
            Name = "Ammo Reduction", Flag = "ammored_enabled", Default = false,
            Callback = function(state)
                ammoRedMasterOn = state and true or false
                AmmoReduction.Enabled = state and true or false
                if AmmoReduction.Enabled then runAmmoReduction() end
            end,
        })
        ammoRedToggle:Keybind({
            Flag = "ammored_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
            Callback = function(v)
                if type(v) ~= "boolean" then return end
                if not ammoRedMasterOn then return end
                do
                    local _kb = Library and Library.Flags and Library.Flags["ammored_key"]
                    if isKeybindNone(_kb) then return end
                end
                AmmoReduction.Enabled = v
                if v then runAmmoReduction() end
                if ammoRedToggle and type(ammoRedToggle.SetValue) == "function" then
                    pcall(function() ammoRedToggle:SetValue(v) end)
                end
            end,
        })
    end

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
        Min = 0, Max = 1000, Default = 0, Decimals = 1, Suffix = "ms",
        Callback = function(v) HostDetection.DelayMs = v end,
    })

    task.defer(function()
        task.wait(0.2)
        setElVisible(HostPlayerDropdown, false)
        setElVisible(HostDelaySlider,    false)
    end)

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
                        -- Only cache the shot if local is holding a combat gun AND triggerbot keybind is already active.
                        -- Shots that happened before the keybind was held must not fire later.
                        if Triggerbot.Enabled and localHasCombatGun() then hostReady = true end
                    end
                    prev = newVal
                end)
            end)
            if not ok or not conn then
                conn = val.Changed:Connect(function(newVal)
                    if type(newVal) == "number" and type(prev) == "number" and newVal < prev then
                        -- Only cache the shot if local is holding a combat gun AND triggerbot keybind is already active.
                        if Triggerbot.Enabled and localHasCombatGun() then hostReady = true end
                    end
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

    trackConn(Players.PlayerAdded:Connect(function(p) if p ~= LocalPlayer then task.wait(0.1); refreshColorTargetList() end end))
    trackConn(Players.PlayerRemoving:Connect(function(p)
        refreshColorTargetList()
        if HostDetection.TargetPlayer and HostDetection.TargetPlayer.Name == p.Name then
            HostDetection.TargetPlayer = nil
            pcall(function() HostPlayerDropdown:SetValue("None") end)
            clearColorConnections()
        end
    end))
    task.spawn(function() for _ = 1, 6 do task.wait(0.5); if not Alive then return end; refreshColorTargetList() end end)
    task.spawn(function()
        while Alive and task.wait(5) do
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
end

-- ============================================================
-- HITBOX EXPANDER (Combat)
-- ============================================================
do
        local HitboxExpander = {
        Enabled          = false,
        TeleportDistance = 42,
        X = 0, Y = 0, Z = 0,
        VisibleCheck     = false,
    }
    HitboxExpanderState = HitboxExpander

    local hb_activeTarget = nil
    local hb_state        = nil

        local function hb_getMaxRange()
        local char = LocalPlayer.Character
        local tool = char and char:FindFirstChildWhichIsA("Tool")

        -- If not holding rev/db/tac (or no tool), cap HBE range to 238 studs
        local tn = tool and tool.Name
        local isRevTacDB = tn and (
            (tn == "[Revolver]") or (tn == "[TacticalShotgun]") or (tn == "[Double-Barrel SG]")
        )
        if not isRevTacDB then
            return 238
        end

        -- Holding a combat gun: use RE range if active, else natural gun range
        local reRange = getRangeExtenderRange(tool)
        if reRange then return reRange end

        local r = Triggerbot.GunRanges[tn]
        if not r then
            local n = tn:lower()
            for gunName, gr in pairs(Triggerbot.GunRanges) do
                if n:find(gunName:lower(), 1, true) then r = gr; break end
            end
        end
        return r or Triggerbot.DefaultRange
    end

    local function hb_getHitbox(char)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local att = hrp:FindFirstChild("RootAttachment")
        if att then
            local hb = att:FindFirstChild("Hitbox")
            if hb then return hb end
        end
        for _, v in ipairs(char:GetDescendants()) do
            if v.Name == "Hitbox" then return v end
        end
        return nil
    end

    local function hb_isKnocked(plr)
        if not plr then return false end
        local ok, knocked = pcall(function()
            local playersFolder = workspace:FindFirstChild("Players")
            if not playersFolder then return false end
            local pFolder = playersFolder:FindFirstChild(plr.Name)
            if not pFolder then return false end
            local bodyEffects = pFolder:FindFirstChild("BodyEffects")
            if not bodyEffects then return false end
            local ko = bodyEffects:FindFirstChild("K.O") or bodyEffects:FindFirstChild("KO")
            if not ko then return false end
            if ko:IsA("BoolValue") then
                return ko.Value
            elseif ko:IsA("IntValue") or ko:IsA("NumberValue") then
                return ko.Value > 0
            elseif ko:IsA("StringValue") then
                local v = ko.Value
                return v ~= "" and v ~= "false" and v ~= "0"
            end
            return ko.Value == true
        end)
        return ok and knocked == true
    end

    local function hb_rayAABB(origin, dir, center, half)
        local tmin, tmax = 0, math.huge
        local axes = {
            { origin.X, dir.X, center.X, half.X },
            { origin.Y, dir.Y, center.Y, half.Y },
            { origin.Z, dir.Z, center.Z, half.Z },
        }
        for i = 1, 3 do
            local o, d, c, h = axes[i][1], axes[i][2], axes[i][3], axes[i][4]
            local lo, hi = c - h, c + h
            if math.abs(d) < 1e-6 then
                if o < lo or o > hi then return nil end
            else
                local t1, t2 = (lo - o) / d, (hi - o) / d
                if t1 > t2 then t1, t2 = t2, t1 end
                if t1 > tmin then tmin = t1 end
                if t2 < tmax then tmax = t2 end
                if tmin > tmax then return nil end
            end
        end
        return tmin
    end

    local function hb_getMouseRay()
        -- Prefer UnitRay; fall back to ViewportPointToRay from camera.
        local ok, ray = pcall(function() return Mouse.UnitRay end)
        if ok and ray and ray.Origin and ray.Direction then
            return ray
        end
        local mousePos = UserInputService:GetMouseLocation()
        local ok2, camRay = pcall(function()
            return Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        end)
        if ok2 and camRay and camRay.Origin and camRay.Direction then
            return camRay
        end
        return nil
    end

    local function hb_getCursorWorldPoint(exclude)
        local unitRay = hb_getMouseRay()
        if not unitRay or not unitRay.Origin then return nil end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclude or {}
        local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, params)
        if hit then return hit.Position end
        return unitRay.Origin + unitRay.Direction * 5000
    end

    hb_restore = function()
        if hb_state then
            pcall(function()
                local char = hb_state.char
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hb_state.hitbox and hb_state.hitbox.Parent and hum and hum.Health > 0 then
                    if hb_state.hitbox:IsA("BasePart") then
                        hb_state.hitbox.CFrame   = hb_state.origCFrame
                        hb_state.hitbox.Anchored = hb_state.origAnchored
                    elseif hb_state.hitbox:IsA("Attachment") then
                        hb_state.hitbox.WorldCFrame = hb_state.origCFrame
                    end
                    for _, j in ipairs(hb_state.brokenJoints) do
                        if j.joint and j.joint.Parent then
                            j.joint.Part0 = j.part0
                            j.joint.Part1 = j.part1
                        end
                    end
                    for _, wc in ipairs(hb_state.brokenConstraints or {}) do
                        if wc and wc.Parent then pcall(function() wc.Enabled = true end) end
                    end
                end
            end)
        end
        hb_activeTarget = nil
        hb_state        = nil
        HBE_State.ActiveTarget = nil
    end

        local function hb_setup(plr)
        if re_restore then pcall(re_restore) end
        hb_restore()
        if not plr then return end
        if hb_isKnocked(plr) then return end
        local char = plr.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local hitbox = hb_getHitbox(char)
        if not hitbox then return end

        local origAnchored      = nil
        local brokenJoints      = {}
        local brokenConstraints = {}

        if hitbox:IsA("BasePart") then
            origAnchored = hitbox.Anchored
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("JointInstance") and (v.Part0 == hitbox or v.Part1 == hitbox) then
                    table.insert(brokenJoints, { joint = v, part0 = v.Part0, part1 = v.Part1 })
                    v.Part0 = nil
                    v.Part1 = nil
                end
                if v:IsA("WeldConstraint") and (v.Part0 == hitbox or v.Part1 == hitbox) then
                    v.Enabled = false
                    table.insert(brokenConstraints, v)
                end
                if (v:IsA("AlignPosition") or v:IsA("AlignOrientation")) then
                    local att0 = v.Attachment0
                    local att1 = v.Attachment1
                    if (att0 and att0.Parent == hitbox) or (att1 and att1.Parent == hitbox) then
                        v.Enabled = false
                        table.insert(brokenConstraints, v)
                    end
                end
            end
            hitbox.Anchored = true
        end

        hb_state = {
            char              = char,
            hrp               = hrp,
            hitbox            = hitbox,
            origCFrame        = hitbox:IsA("BasePart") and hitbox.CFrame or hitbox.WorldCFrame,
            origAnchored      = origAnchored,
            brokenJoints      = brokenJoints,
            brokenConstraints = brokenConstraints,
        }
        hb_activeTarget = plr
        HBE_State.ActiveTarget = plr
    end

    local function hb_isVisible(char)
        if not char then return false end
        local ref = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not ref then return false end
        local origin = Camera.CFrame.Position
        local dir = ref.Position - origin
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { char }
        if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
        params.FilterDescendantsInstances = filter
        local hit = workspace:Raycast(origin, dir, params)
        if not hit or hit.Instance:IsDescendantOf(char) then return true end
        return false
    end

    local function hb_holdingKnife()
        local char = LocalPlayer.Character
        if not char then return false end
        local tool = char:FindFirstChildWhichIsA("Tool")
        if not tool then return false end
        local n = tool.Name:lower()
        return n:find("knife", 1, true) ~= nil
    end

    local function hb_selectTarget(currentTarget)
        local myChar = LocalPlayer.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return nil end
        local myPos    = myHrp.Position
        local maxRange = hb_getMaxRange()
        local mousePos = UserInputService:GetMouseLocation()

        -- aiming near its expanded X/Y/Z volume (no sticky when looking away)
        if currentTarget and not Whitelisted[currentTarget] and not isCombatImmune(currentTarget) then
            local char = currentTarget.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0
               and hb_getHitbox(char) and not hb_isKnocked(currentTarget)
               and (hrp.Position - myPos).Magnitude <= maxRange
               and (not HitboxExpander.VisibleCheck or hb_isVisible(char)) then
                local half = hrp.Size * 0.5 + Vector3.new(HitboxExpander.X, HitboxExpander.Y, HitboxExpander.Z)
                local ray = hb_getMouseRay()
                if ray and hb_rayAABB(ray.Origin, ray.Direction, hrp.Position, half) ~= nil then
                    return currentTarget
                end
            end
        end

        local best, bestScore = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and not Whitelisted[plr] and not isCombatImmune(plr) then
                local char = plr.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0
                       and hb_getHitbox(char) and not hb_isKnocked(plr)
                       and (not HitboxExpander.VisibleCheck or hb_isVisible(char)) then
                        local d = (hrp.Position - myPos).Magnitude
                        if d <= maxRange then
                            local half = hrp.Size * 0.5 + Vector3.new(HitboxExpander.X, HitboxExpander.Y, HitboxExpander.Z)
                            local ray = hb_getMouseRay()
                            local t = ray and hb_rayAABB(ray.Origin, ray.Direction, hrp.Position, half) or nil
                            if t ~= nil then
                                if t < bestScore then
                                    bestScore = t
                                    best = plr
                                end
                            else
                                local sp, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                                if onScreen and sp.Z > 0 then
                                    local screenDist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                                    if screenDist < 120 and screenDist < bestScore then
                                        bestScore = screenDist
                                        best = plr
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    local function hb_stillOnCursor(target)
        if not target then return false end
        local char = target.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end

        local myChar = LocalPlayer.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return false end
        if (hrp.Position - myHrp.Position).Magnitude > hb_getMaxRange() then
            return false
        end

        local half = hrp.Size * 0.5 + Vector3.new(HitboxExpander.X, HitboxExpander.Y, HitboxExpander.Z)
        local ray  = hb_getMouseRay()
        if not ray then return false end
        return hb_rayAABB(ray.Origin, ray.Direction, hrp.Position, half) ~= nil
    end

    local hbLogicActive = false

        trackConn(RunService.RenderStepped:Connect(function()
        if not Alive or not hbLogicActive then
            if hb_state then hb_restore() end
            return
        end

        local myChar = LocalPlayer.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then
            if hb_state then hb_restore() end
            return
        end

        local closest = hb_selectTarget(hb_activeTarget)
        if closest ~= hb_activeTarget then
            if closest then
                hb_setup(closest)
            else
                hb_restore()
                return
            end
        end

        if not hb_activeTarget or not hb_state then return end

        local char = hb_activeTarget.Character
        if not char or char ~= hb_state.char then hb_restore(); return end
        if not hb_state.hitbox or not hb_state.hitbox.Parent then hb_restore(); return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then hb_restore(); return end
        if hb_isKnocked(hb_activeTarget) then hb_restore(); return end

        if not hb_stillOnCursor(hb_activeTarget) then
            hb_restore()
            return
        end

        local cursorWorld = hb_getCursorWorldPoint({ myChar, hb_state.char })
        if not cursorWorld then return end

        local myPos = myHrp.Position
        local dir = cursorWorld - myPos
        if dir.Magnitude < 0.01 then
            dir = myHrp.CFrame.LookVector
        else
            dir = dir.Unit
        end

                local teleDist
        local revTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
        if revTool and revTool.Name:lower():find("revolver", 1, true) then
            teleDist = 238
        else
            teleDist = HitboxExpander.TeleportDistance
        end
        local dist = math.min((cursorWorld - myPos).Magnitude, teleDist)
        local displacedPos = myPos + dir * dist
        local displacedCFrame = CFrame.new(displacedPos) * hb_state.hrp.CFrame.Rotation

        if hb_state.hitbox:IsA("BasePart") then
            hb_state.hitbox.CFrame = displacedCFrame
        elseif hb_state.hitbox:IsA("Attachment") then
            hb_state.hitbox.WorldCFrame = displacedCFrame
        end
    end))

    local hbMasterOn    = false
    -- hbKeybindHeld: true only while the physical keybind is held down
    local hbKeybindHeld = false

    -- displaced for too long without releasing it.
    task.spawn(function()
        local HBE_RESET_INTERVAL = 120  -- seconds between resets
        while Alive do
            task.wait(HBE_RESET_INTERVAL)
            if not Alive then break end
            if not hbLogicActive then continue end
            -- Snapshot current target before restore clears it
            local prevTarget = hb_activeTarget
            pcall(hb_restore)
            -- Only re-acquire if logic is still active and we had a target
            if hbLogicActive and prevTarget and prevTarget.Parent then
                task.wait()  -- yield one frame so physics settles
                if hbLogicActive then
                    pcall(function() hb_setup(prevTarget) end)
                end
            end
        end
    end)

    -- Central function that updates hbLogicActive and side-effects
    local function applyHBLogic()
        local shouldBeActive = hbMasterOn and hbKeybindHeld
        if shouldBeActive == hbLogicActive then return end  -- no change
        hbLogicActive = shouldBeActive
        if HitboxExpanderState then HitboxExpanderState.LogicActive = hbLogicActive end
        if hbLogicActive then
            -- Disable CR if it's running (mutually exclusive)
            if ClientRedirectionState and ClientRedirectionState.Enabled then
                ClientRedirectionState.Enabled = false
                if cr_restore then pcall(cr_restore) end
                if crToggleRef then pcall(function() crToggleRef:SetValue(false) end) end
            end
        else
            -- Keybind released or master turned off — restore hitbox immediately
            hb_restore()
        end
    end

            hbToggleRef = HitboxExpanderSection:Toggle({
        Name = "Enabled", Flag = "hitbox_enabled", Default = false,
        Callback = function(state)
            if state and ClientRedirectionState and ClientRedirectionState.Enabled then
                Library:Notification("Disable Client Redirection first.", 2)
                if hbToggleRef and type(hbToggleRef.SetValue) == "function" then
                    pcall(function() hbToggleRef:SetValue(false) end)
                end
                return
            end
            hbMasterOn = state and true or false
            HitboxExpander.Enabled = hbMasterOn
            if HitboxExpanderState then HitboxExpanderState.Enabled = hbMasterOn end
            applyHBLogic()
        end,
    })
    
        hbToggleRef:Keybind({
        Flag        = "hitbox_key",
        Default     = Enum.KeyCode.Unknown,
        Mode        = "Hold",
        Callback    = function(v)
            if type(v) ~= "boolean" then return end
            if v and ClientRedirectionState and ClientRedirectionState.Enabled then
                Library:Notification("Disable Client Redirection first.", 2)
                return
            end
            hbKeybindHeld = v
            applyHBLogic()
        end,
    })
    
    HitboxExpanderSection:Slider({
        Name = "X", Flag = "hitbox_x",
        Min = 0, Max = 100, Default = 0, Decimals = 1,
        Callback = function(v) HitboxExpander.X = v end,
    })
    HitboxExpanderSection:Slider({
        Name = "Y", Flag = "hitbox_y",
        Min = 0, Max = 100, Default = 0, Decimals = 1,
        Callback = function(v) HitboxExpander.Y = v end,
    })
    HitboxExpanderSection:Slider({
        Name = "Z", Flag = "hitbox_z",
        Min = 0, Max = 100, Default = 0, Decimals = 1,
        Callback = function(v) HitboxExpander.Z = v end,
    })
    HitboxExpanderSection:Toggle({
        Name = "Visible Check", Flag = "hitbox_visible", Default = false,
        Callback = function(v) HitboxExpander.VisibleCheck = v and true or false end,
    })
        -- HBE Visualizer
    local hbeVisEnabled = false
    local hbeVisColor = Color3.fromRGB(255, 255, 255)
    local hbeVisFillColor = Color3.fromRGB(255, 255, 255)
    local hbeVisFillTrans = 0.7
    local hbeVisPart = Instance.new("Part")
    hbeVisPart.Name = "_HBEVis"
    hbeVisPart.Anchored = true
    hbeVisPart.CanCollide = false
    hbeVisPart.CanTouch = false
    hbeVisPart.CanQuery = false
    hbeVisPart.CastShadow = false
    hbeVisPart.Massless = true
    hbeVisPart.Transparency = 1
    hbeVisPart.Size = Vector3.new(0.01, 0.01, 0.01)
    hbeVisPart.CFrame = CFrame.new(0, -10000, 0)
    -- Deliberately NOT parented — only parented to workspace while the
    -- visualizer is actively drawing on a live HBE target.
    local hbeSelBox = Instance.new("SelectionBox")
    hbeSelBox.LineThickness = 0.04
    hbeSelBox.Color3 = hbeVisColor
    hbeSelBox.SurfaceTransparency = hbeVisFillTrans
    hbeSelBox.SurfaceColor3 = hbeVisFillColor
    hbeSelBox.Adornee = nil
    hbeSelBox.Parent = workspace

    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive then return end
        local showVis = hbeVisEnabled and hbLogicActive and hb_activeTarget ~= nil
        if not showVis then
            hbeSelBox.Adornee = nil
            if hbeVisPart.Parent then hbeVisPart.Parent = nil end
            return
        end
        local char = hb_activeTarget and hb_activeTarget.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            hbeSelBox.Adornee = nil
            if hbeVisPart.Parent then hbeVisPart.Parent = nil end
            return
        end
        local expand = Vector3.new(HitboxExpander.X, HitboxExpander.Y, HitboxExpander.Z)
        hbeVisPart.Size   = hrp.Size + expand * 2
        hbeVisPart.CFrame = hrp.CFrame
        if hbeVisPart.Parent ~= workspace then hbeVisPart.Parent = workspace end
        hbeSelBox.Color3 = hbeVisColor
        hbeSelBox.SurfaceColor3 = hbeVisFillColor
        hbeSelBox.SurfaceTransparency = hbeVisFillTrans
        hbeSelBox.Adornee = hbeVisPart
    end))

    local hbeVisToggle = HitboxExpanderSection:Toggle({
        Name = "Show Visualizer", Flag = "hbe_vis", Default = false,
        Callback = function(v) hbeVisEnabled = v end,
    })
    hbeVisToggle:Colorpicker({
        Flag = "hbe_vis_color", Default = hbeVisColor,
        Callback = function(c) hbeVisColor = c end,
    })
    local hbeVisFillToggle = HitboxExpanderSection:Toggle({
        Name = "Fill Visualizer", Flag = "hbe_vis_fill", Default = false,
        Callback = function(v)
            hbeVisFillTrans = v and 0.7 or 1
            hbeSelBox.SurfaceTransparency = hbeVisFillTrans
        end,
    })
    hbeVisFillToggle:Colorpicker({
        Flag = "hbe_vis_fill_color", Default = hbeVisFillColor,
        Callback = function(c) hbeVisFillColor = c end,
    })
    HitboxExpanderSection:Slider({
        Name = "Fill Transparency", Flag = "hbe_vis_fill_trans",
        Min = 0, Max = 100, Default = 0, Decimals = 1,
        Callback = function(v) hbeVisFillTrans = v/100; hbeSelBox.SurfaceTransparency = hbeVisFillTrans end,
    })
end

-- ============================================================
-- GUN MACRO UI (under Triggerbot / Host Detection on Combat page)
-- ============================================================
do
    local macroMasterOn = true
    local macroToggle
    macroToggle = GunMacroSection:Toggle({
        Name = "Enabled", Flag = "macro_enabled", Default = false,
        Callback = function(state)
            macroMasterOn = state and true or false
            GunMacro.Enabled = state and true or false
            if not state then GunMacro.Active = false end
        end,
    })
    macroToggle:Keybind({
        Flag = "macro_key", Default = Enum.KeyCode.Unknown, Mode = "Hold",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not macroMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["macro_key"]
                if isKeybindNone(_kb) then return end
            end
            GunMacro.Enabled = v
            if not v then GunMacro.Active = false end
        end,
    })
    GunMacroSection:Slider({ Name="Delay", Flag="macro_delay", Min=0, Max=500, Default=0, Decimals=1, Suffix="ms", Callback=function(v) GunMacro.Delay=v/1000 end })
end


-- ============================================================
-- LAY MACRO
-- ============================================================
do
    local LayMacro = { Enabled=false, KnifeName="[Knife]", Delay=50 }
    LayMacroRef = LayMacro
    local laySeqToken = 0

    local function getMainRemoteEvent()
        local RS = game:GetService("ReplicatedStorage")
        local mainRemotes = RS:FindFirstChild("MainRemotes")
        return mainRemotes and mainRemotes:FindFirstChild("MainRemoteEvent")
    end

    -- Check if the game's shift-lock (mouse lock) is currently active
    local function isShiftLockActive()
        -- Check via PlayerModule / RootCamera if accessible
        local ok, result = pcall(function()
            local PlayerModule = LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
            if not PlayerModule then return false end
            local controls = require(PlayerModule):GetControls()
            -- If the camera module exposes shift lock state
            return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
        end)
        if ok then return result end
        -- Fallback: MouseBehavior lock center = shift lock active
        return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
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

    runLayMacro = function()
        laySeqToken = laySeqToken + 1
        local myToken = laySeqToken
        task.spawn(function()
            -- Detect and disable shift lock BEFORE sending lay animation
            local wasShiftLocked = isShiftLockActive()
            if wasShiftLocked then
                pressLeftShift()
                task.wait(0.08)
                if myToken ~= laySeqToken or not LayMacro.Enabled then return end
            end

            if LayMacro.Delay > 0 then
                task.wait(LayMacro.Delay / 1000)
                if myToken ~= laySeqToken or not LayMacro.Enabled then return end
            end
            local ev = getMainRemoteEvent()
            if ev then pcall(function() ev:FireServer("AnimationPack", "Lay") end) end
            if LayMacro.Delay > 0 then
                task.wait(LayMacro.Delay / 1000)
                if myToken ~= laySeqToken or not LayMacro.Enabled then return end
            end
            equipLayKnife()
            if myToken ~= laySeqToken or not LayMacro.Enabled then return end
            -- Always ensure shift lock is ON after lay macro
            if not isShiftLockActive() then
                pressLeftShift()
            end
        end)
    end

    -- Lay Macro toggle lives in Misc section only (no separate section / slider)
end


-- ============================================================
-- RANGE EXTENDER
-- ============================================================
do
    local function re_getCursorWorldPoint(exclude)
        local unitRay = Mouse.UnitRay
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclude or {}
        local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, params)
        if hit then return hit.Position end
        return unitRay.Origin + unitRay.Direction * 5000
    end

    local function re_getHitbox(char)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local att = hrp:FindFirstChild("RootAttachment")
        if att then
            local hb = att:FindFirstChild("Hitbox")
            if hb then return hb end
        end
        for _, v in ipairs(char:GetDescendants()) do
            if v.Name == "Hitbox" then return v end
        end
        return nil
    end

    local function re_isVisible(char)
        local ref = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not ref then return false end
        local origin = Camera.CFrame.Position
        local dir = (ref.Position - origin)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { LocalPlayer.Character, char }
        local hit = workspace:Raycast(origin, dir, params)
        if not hit or hit.Instance:IsDescendantOf(char) then return true end
        return false
    end

    re_restore = function()
        if re_state then
            pcall(function()
                if re_state.hitbox and re_state.hitbox.Parent then
                    if re_state.hitbox:IsA("BasePart") then
                        re_state.hitbox.CFrame = re_state.origCFrame
                        re_state.hitbox.Anchored = re_state.origAnchored
                    elseif re_state.hitbox:IsA("Attachment") then
                        re_state.hitbox.WorldCFrame = re_state.origCFrame
                    end
                    for _, j in ipairs(re_state.brokenJoints) do
                        if j.joint and j.joint.Parent then
                            j.joint.Part0 = j.part0
                            j.joint.Part1 = j.part1
                        end
                    end
                end
            end)
        end
        re_activeTarget = nil
        re_state = nil
    end

    local function re_setup(plr)
        re_restore()
        if not plr then return end
        local char = plr.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local hitbox = re_getHitbox(char)
        if not hitbox then return end

        local origAnchored = nil
        local brokenJoints = {}
        if hitbox:IsA("BasePart") then
            origAnchored = hitbox.Anchored
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("JointInstance") and (v.Part0 == hitbox or v.Part1 == hitbox) then
                    table.insert(brokenJoints, {joint = v, part0 = v.Part0, part1 = v.Part1})
                    v.Part0 = nil
                    v.Part1 = nil
                end
            end
            hitbox.Anchored = true
        end

        re_state = {
            char = char,
            hrp = hrp,
            hitbox = hitbox,
            origCFrame = hitbox:IsA("BasePart") and hitbox.CFrame or hitbox.WorldCFrame,
            origAnchored = origAnchored,
            brokenJoints = brokenJoints,
        }
        re_activeTarget = plr
    end

    local function re_getClosestToMouse(maxRange)
        local myChar = LocalPlayer.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return nil end
        local mousePos = UserInputService:GetMouseLocation()
        local best, bestDist = nil, math.huge

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer or Whitelisted[plr] then continue end
            local char = plr.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end

            local distToPlayer = (myHrp.Position - hrp.Position).Magnitude
            if distToPlayer > maxRange then continue end
            if not re_isVisible(char) then continue end

            local ref = char:FindFirstChild("Head") or hrp
            local screen, onScreen = Camera:WorldToViewportPoint(ref.Position)
            if not onScreen then continue end

            local dist = (Vector2.new(screen.X, screen.Y) - mousePos).Magnitude
            if dist > RangeExtender.FOV then continue end
            if dist < bestDist then
                best, bestDist = plr, dist
            end
        end
        return best
    end

    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive or not RangeExtender.Enabled then
            if re_state then re_restore() end
            return
        end

        local reChar = LocalPlayer.Character
        local reTool = reChar and reChar:FindFirstChildWhichIsA("Tool")
        if not reTool then
            if re_state then re_restore() end
            return
        end

        -- Per-gun gate: is RE enabled for *this* weapon?
        local reRange = getRangeExtenderRange(reTool)
        if not reRange then
            if re_state then re_restore() end
            return
        end

        if (ClientRedirectionState and ClientRedirectionState.Enabled)
            or (HBE_State.ActiveTarget ~= nil) then
            if re_state then re_restore() end
            return
        end

        local closest = re_getClosestToMouse(reRange)
        if closest ~= re_activeTarget then re_setup(closest) end
        if re_activeTarget and re_state and re_activeTarget.Character ~= re_state.char then
            re_setup(re_activeTarget)
        end

        if not re_activeTarget or not re_state then return end
        if not re_state.hitbox or not re_state.hitbox.Parent then re_restore() return end

        local myChar = LocalPlayer.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end

        local distToTarget = (myHrp.Position - re_state.hrp.Position).Magnitude
        if distToTarget > reRange then re_restore() return end

        local cursorWorld = re_getCursorWorldPoint({ LocalPlayer.Character, re_state.char })
        if not cursorWorld then return end

        local myPos = myHrp.Position
        local dir = cursorWorld - myPos
        if dir.Magnitude < 0.01 then dir = myHrp.CFrame.LookVector else dir = dir.Unit end

        local displacedPos = myPos + dir * (getRangeExtenderDistance(reTool) or RangeExtender.Distance)
        local displacedCFrame = CFrame.new(displacedPos) * re_state.hrp.CFrame.Rotation

        if re_state.hitbox:IsA("BasePart") then
            re_state.hitbox.CFrame = displacedCFrame
        elseif re_state.hitbox:IsA("Attachment") then
            re_state.hitbox.WorldCFrame = displacedCFrame
        end
    end))

    RangeExtenderSection:Toggle({
        Name = "Range Extender", Flag = "misc_range_extender", Default = false,
        Callback = function(state)
            RangeExtender.Enabled = state
            if not state then re_restore() end
        end
    })

    -- ── Per-gun range sliders (all guns active when Range Extender is on) ──

    -- Revolver
    RangeExtenderSection:Slider({
        Name = "Revolver Range", Flag = "re_gun_revolver_range",
        Min = 0, Max = 238, Default = 0, Decimals = 1, Suffix = " studs",
        Callback = function(v) RangeExtender.Guns["[Revolver]"].Range = v end,
    })

    -- Double-Barrel SG
    RangeExtenderSection:Slider({
        Name = "Double-Barrel SG Range", Flag = "re_gun_db_range",
        Min = 0, Max = 238, Default = 0, Decimals = 1, Suffix = " studs",
        Callback = function(v) RangeExtender.Guns["[Double-Barrel SG]"].Range = v end,
    })

    -- TacticalShotgun
    RangeExtenderSection:Slider({
        Name = "TacticalShotgun Range", Flag = "re_gun_tac_range",
        Min = 0, Max = 238, Default = 0, Decimals = 1, Suffix = " studs",
        Callback = function(v) RangeExtender.Guns["[TacticalShotgun]"].Range = v end,
    })
end

-- ============================================================
-- ESP UI
-- ============================================================
do
    local espMasterOn = true
    local espToggle
    local function applyESP(v)
        if type(v) ~= "boolean" then return end
        Config.Enabled = v
    end

    espToggle = ESPSection:Toggle({
        Name = "Enabled", Flag = "esp_enabled", Default = false,
        Callback = function(v)
            espMasterOn = v and true or false
            applyESP(v)
        end,
    })
    espToggle:Keybind({
        Flag = "esp_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not espMasterOn then return end
            applyESP(v)
            if espToggle and type(espToggle.SetValue) == "function" then
                pcall(function() espToggle:SetValue(v) end)
            end
        end,
    })
end

local boxToggle = ESPSection:Toggle({
    Name = "Box", Flag = "esp_box", Default = false,
    Callback = function(v) Config.Box.Enable = v and true or false end,
})
boxToggle:Colorpicker({
    Flag = "esp_box_color", Default = Config.Box.Color,
    Callback = function(c) Config.Box.Color = c end,
})
local skelToggle = ESPSection:Toggle({
    Name = "Skeleton", Flag = "esp_skeleton", Default = false,
    Callback = function(v) Config.Skeleton.Enable = v and true or false end,
})
skelToggle:Colorpicker({
    Flag = "esp_skeleton_color", Default = Config.Skeleton.Color,
    Callback = function(c) Config.Skeleton.Color = c end,
})

local headToggle = ESPSection:Toggle({
    Name = "Head Circle", Flag = "esp_headcircle", Default = false,
    Callback = function(v) Config.HeadCircle.Enable = v and true or false end,
})
headToggle:Colorpicker({
    Flag = "esp_headcircle_color", Default = Config.HeadCircle.Color,
    Callback = function(c) Config.HeadCircle.Color = c end,
})

ESPSection:Toggle({
    Name = "Health Bar", Flag = "esp_hp", Default = false,
    Callback = function(v) Config.Bars.Health.Enable = v and true or false end,
})
ESPSection:Toggle({
    Name = "Armor Bar", Flag = "esp_ar", Default = false,
    Callback = function(v) Config.Bars.Armor.Enable = v and true or false end,
})

local hpTextToggle = ESPSection:Toggle({
    Name = "Health Text", Flag = "esp_text_hp", Default = false,
    Callback = function(v) Config.Text.Health.Enable = v and true or false end,
})
hpTextToggle:Colorpicker({
    Flag = "esp_text_hp_color", Default = Config.Text.Health.Color,
    Callback = function(c) Config.Text.Health.Color = c end,
})

local arTextToggle = ESPSection:Toggle({
    Name = "Armor Text", Flag = "esp_text_ar", Default = false,
    Callback = function(v) Config.Text.Armor.Enable = v and true or false end,
})
arTextToggle:Colorpicker({
    Flag = "esp_text_ar_color", Default = Config.Text.Armor.Color,
    Callback = function(c) Config.Text.Armor.Color = c end,
})

local nameToggle = ESPSection:Toggle({
    Name = "Name", Flag = "esp_text_name", Default = false,
    Callback = function(v) Config.Text.Name.Enable = v and true or false end,
})
nameToggle:Colorpicker({
    Flag = "esp_text_name_color", Default = Config.Text.Name.Color,
    Callback = function(c) Config.Text.Name.Color = c end,
})

local distToggle = ESPSection:Toggle({
    Name = "Distance", Flag = "esp_text_dist", Default = false,
    Callback = function(v) Config.Text.Studs.Enable = v and true or false end,
})
distToggle:Colorpicker({
    Flag = "esp_text_dist_color", Default = Config.Text.Studs.Color,
    Callback = function(c) Config.Text.Studs.Color = c end,
})

local targetESPToggle = ESPSection:Toggle({
    Name = "Target", Flag = "esp_target", Default = false,
    Callback = function(v) TargetESP.Enabled = v and true or false end,
})
targetESPToggle:Colorpicker({
    Flag = "esp_target_color", Default = TargetESP.Color,
    Callback = function(c) TargetESP.Color = c end,
})

local toolToggle = ESPSection:Toggle({
    Name = "Tool", Flag = "esp_text_tool", Default = false,
    Callback = function(v) Config.Text.Tool.Enable = v and true or false end,
})
toolToggle:Colorpicker({
    Flag = "esp_text_tool_color", Default = Config.Text.Tool.Color,
    Callback = function(c) Config.Text.Tool.Color = c end,
})

ESPSection:Toggle({
    Name = "Flags", Flag = "esp_flags", Default = false,
    Callback = function(v) Config.Text.Flags.Enable = v and true or false end,
})

ESPSection:Toggle({
    Name = "Visual Self", Flag = "esp_self", Default = false,
    Callback = function(v) Config.ShowOnSelf = v and true or false end,
})

ESPSection:Toggle({
    Name = "Knock Check", Flag = "esp_knock_check", Default = false,
    Callback = function(v) Config.KnockCheck = v and true or false end,
})

-- Box Type dropdown sits below Flags
ESPSection:Dropdown({
    Name = "Box Type", Flag = "esp_box_style",
    Items = {"2D", "Corner", "3D"},
    Default = "2D",
    Callback = function(v) Config.BoxStyle = v or "2D" end,
})

ESPSection:Dropdown({
    Name = "Distance Unit", Flag = "esp_dist_unit",
    Items = {"Metres", "Studs"},
    Default = "Metres",
    Callback = function(v) Config.DistanceUnit = v or "Metres" end,
})
ESPSection:Dropdown({
    Name = "Bar Position", Flag = "esp_bar_pos",
    Items = {"Left", "Right", "Top", "Bottom"},
    Default = "Left",
    Callback = function(v)
        Config.Bars.Health.Position = v
        Config.Bars.Armor.Position = v
    end,
})
ESPSection:Dropdown({
    Name = "Name Type", Flag = "esp_text_nametype",
    Items = {"Display", "Username", "Both"},
    Default = "Display",
    Callback = function(v) Config.Text.Name.Type = v end,
})


-- ============================================================
-- ESP PREVIEW
-- ============================================================
local ESPPreviewSection = VisualsPage:Section({Name = "ESP Preview", Side = 2})
do
    local ESPPreview = {
        Enabled = true,
        SelectedImage = "Donald Trump",
        Images = {
            ["Donald Trump"] = {
                Url = "https://files.catbox.moe/0h2jen.png",
                Width = 140, Height = 200, Zoom = 1.0, OffsetY = 0,
                DisplayName = "Donald Trump", Username = "DonaldTrump",
            },
            ["Elon Musk"] = {
                Url = "https://files.catbox.moe/6ocfwv.png",
                Width = 140, Height = 200, Zoom = 1.0, OffsetY = 0,
                DisplayName = "Elon Musk", Username = "ElonMusk",
            },
        },
    }

    local previewContent = ESPPreviewSection.Items["Content"].Instance

    ESPPreviewSection:Dropdown({
        Name = "Font", Flag = "esp_font",
        Items = {
            "GothamBold", "Gotham", "GothamMedium", "GothamBlack",
            "SourceSans", "SourceSansBold", "SourceSansSemibold",
            "Roboto", "RobotoMono", "Ubuntu",
            "Arial", "ArialBold", "Code", "Legacy",
            "Highway", "SciFi", "Arcade", "Bodoni", "Garamond",
            "Fantasy", "Antique"
        },
        Default = "GothamBold",
        Callback = function(v)
            local ok, font = pcall(function() return Enum.Font[v] end)
            if ok and font then
                Config.Font = font
                -- refresh existing ESP labels
                for _, c in pairs(ESPCache or {}) do
                    if c.Text then
                        for _, lbl in pairs(c.Text) do
                            if lbl and lbl.Parent then
                                pcall(function() lbl.Font = font end)
                            end
                        end
                    end
                end
            end
        end,
    })
    ESPPreviewSection:Slider({
        Name = "Text Size", Flag = "esp_textsize",
        Min = 0, Max = 20, Default = 11, Decimals = 1,
        Callback = function(v)
            Config.TextSize = v
            -- Apply to all live ESP text labels immediately
            for _, c in pairs(ESPCache or {}) do
                if c.Text then
                    for _, lbl in pairs(c.Text) do
                        if lbl and lbl.Parent then
                            pcall(function()
                                lbl.TextSize = math.max(1, v)
                            end)
                        end
                    end
                end
            end
        end,
    })
    ESPPreviewSection:Slider({
        Name = "Distance 0=Inf", Flag = "esp_maxdist",
        Min = 0, Max = 10000, Default = 0, Decimals = 1, Suffix = " studs",
        Callback = function(v) Config.MaxDistance = v end,
    })

    local previewMain = Instance.new("Frame")
    previewMain.Name = "ESPPreviewMain"
    previewMain.Size = UDim2.new(1, -6, 0, 280)
    previewMain.BackgroundColor3 = Color3.fromRGB(11, 12, 16)
    previewMain.BackgroundTransparency = 1 -- fully transparent so only the photo shows
    previewMain.BorderSizePixel = 0
    previewMain.ClipsDescendants = false
    previewMain.Parent = previewContent
    Instance.new("UICorner", previewMain).CornerRadius = UDim.new(0, 8)
    local previewStroke = Instance.new("UIStroke", previewMain)
    previewStroke.Color = Color3.fromRGB(48, 48, 56)
    previewStroke.Thickness = 1
    previewStroke.Transparency = 1 -- hidden; photo sits flush on panel

    local centerHolder = Instance.new("Frame")
    centerHolder.Name = "CenterHolder"
    centerHolder.Size = UDim2.fromOffset(140, 200)
    centerHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    centerHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
    centerHolder.BackgroundTransparency = 1
    centerHolder.ClipsDescendants = false
    centerHolder.Parent = previewMain

    local imageMask = Instance.new("Frame")
    imageMask.Name = "ImageMask"
    imageMask.Size = UDim2.fromScale(1, 1)
    imageMask.BackgroundTransparency = 1
    imageMask.BackgroundColor3 = Color3.new(0, 0, 0)
    imageMask.ClipsDescendants = false
    imageMask.Parent = centerHolder

    local previewImage = Instance.new("ImageLabel")
    previewImage.Name = "PreviewImage"
    previewImage.AnchorPoint = Vector2.new(0.5, 0.5)
    previewImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    previewImage.Size = UDim2.fromScale(1, 1)
    previewImage.BackgroundTransparency = 1
    previewImage.BackgroundColor3 = Color3.new(0, 0, 0)
    previewImage.BorderSizePixel = 0
    previewImage.ImageTransparency = 0
    previewImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
    previewImage.ScaleType = Enum.ScaleType.Fit
    previewImage.Parent = imageMask

    local function makeEdge(z)
        local f = Instance.new("Frame", centerHolder)
        f.BorderSizePixel = 0
        f.BackgroundColor3 = Color3.new(1,1,1)
        f.Visible = false
        f.ZIndex = z
        return f
    end
    local bTopO, bBotO, bLeftO, bRightO = makeEdge(2), makeEdge(2), makeEdge(2), makeEdge(2)
    local bTop,  bBot,  bLeft,  bRight  = makeEdge(3), makeEdge(3), makeEdge(3), makeEdge(3)
    for _, o in ipairs({bTopO, bBotO, bLeftO, bRightO}) do o.BackgroundColor3 = Color3.new(0,0,0) end

    -- Skeleton base joints for a front-facing clasped-hands pose (ref 95x155)
    -- Scaled at runtime by sx/sy so it tracks every preview photo size
    local skelPairs = {
        -- spine: head -> mid torso -> hips
        {47.5, 20, 47.5, 48},
        {47.5, 48, 47.5, 84},
        -- left arm: shoulder -> elbow -> clasped hand
        {47.5, 48, 34, 58},
        {34, 58, 40, 74},
        -- right arm: shoulder -> elbow -> clasped hand
        {47.5, 48, 61, 58},
        {61, 58, 55, 74},
        -- left leg: hip -> knee -> ankle -> foot
        {47.5, 84, 40, 108},
        {40, 108, 38, 132},
        {38, 132, 36, 148},
        -- right leg
        {47.5, 84, 55, 108},
        {55, 108, 57, 132},
        {57, 132, 59, 148},
    }
    local skelLines = {}
    for i = 1, #skelPairs do
        local fr = Instance.new("Frame", centerHolder)
        fr.BorderSizePixel = 0
        fr.AnchorPoint = Vector2.new(0.5, 0.5)
        fr.BackgroundColor3 = Color3.new(1,1,1)
        fr.Visible = false
        fr.ZIndex = 20
        skelLines[i] = fr
    end

    local previewHead = Instance.new("Frame", centerHolder)
    previewHead.BackgroundTransparency = 1
    previewHead.BorderSizePixel = 0
    previewHead.Visible = false
    previewHead.ZIndex = 21
    local previewHeadStroke = Instance.new("UIStroke", previewHead)
    previewHeadStroke.Thickness = 1
    previewHeadStroke.Color = Color3.new(1,1,1)
    previewHeadStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    Instance.new("UICorner", previewHead).CornerRadius = UDim.new(1, 0)

    local function makePreviewLabel()
        local l = Instance.new("TextLabel", centerHolder)
        l.BackgroundTransparency = 1
        l.TextStrokeTransparency = 0
        l.TextStrokeColor3 = Color3.new(0,0,0)
        l.TextSize = 11
        l.Font = Enum.Font.GothamBold
        l.TextColor3 = Color3.new(1,1,1)
        l.ZIndex = 26
        l.Visible = false
        return l
    end

    local lblName   = makePreviewLabel()
    lblName.Size = UDim2.fromOffset(260, 14)
    lblName.AnchorPoint = Vector2.new(0.5, 1)
    lblName.Position = UDim2.fromOffset(0, -4)
    lblName.TextXAlignment = Enum.TextXAlignment.Center

    local lblStuds  = makePreviewLabel()
    lblStuds.Size = UDim2.fromOffset(120, 14)
    lblStuds.AnchorPoint = Vector2.new(0.5, 0)
    lblStuds.Position = UDim2.fromOffset(0, 0)
    lblStuds.TextXAlignment = Enum.TextXAlignment.Center

    local lblTool   = makePreviewLabel()
    lblTool.Size = UDim2.fromOffset(160, 14)
    lblTool.AnchorPoint = Vector2.new(0.5, 0)
    lblTool.Position = UDim2.fromOffset(0, 0)
    lblTool.TextXAlignment = Enum.TextXAlignment.Center

    local lblArmor  = makePreviewLabel()
    lblArmor.Size = UDim2.fromOffset(70, 13)
    lblArmor.AnchorPoint = Vector2.new(1, 0)
    lblArmor.Position = UDim2.fromOffset(-18, 2)
    lblArmor.TextXAlignment = Enum.TextXAlignment.Right
    lblArmor.TextSize = 10

    local lblHealth = makePreviewLabel()
    lblHealth.Size = UDim2.fromOffset(70, 13)
    lblHealth.AnchorPoint = Vector2.new(1, 0)
    lblHealth.Position = UDim2.fromOffset(-18, 16)
    lblHealth.TextXAlignment = Enum.TextXAlignment.Right
    lblHealth.TextSize = 10
    -- positions refreshed each frame with Config.Layout offsets

    local function makePreviewBar(z)
        local outline = Instance.new("Frame", centerHolder)
        outline.BackgroundColor3 = Color3.new(0, 0, 0)
        outline.BorderSizePixel = 0
        outline.ZIndex = z
        outline.Visible = false
        local fill = Instance.new("Frame", outline)
        fill.BackgroundColor3 = Color3.new(1, 1, 1) -- required for UIGradient to show
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

    -- Drag ESP elements in the preview → writes Config.Layout offsets used by live ESP.
    -- Uses getgenv().ElytraPreviewDragging so the UI library skips window drag (patched above).
    local _previewDrag = nil
    local function ensureLayout(key)
        if not Config.Layout then Config.Layout = {} end
        if not Config.Layout[key] then Config.Layout[key] = { X = 0, Y = 0 } end
        return Config.Layout[key]
    end
    -- Layout X/Y are fractions of the ESP box size. Convert to pixels for a given box.
    local function layoutPixels(key, boxW, boxH)
        local lay = Config.Layout and Config.Layout[key]
        if not lay then return 0, 0 end
        return (lay.X or 0) * boxW, (lay.Y or 0) * boxH
    end
    local function setPreviewDragging(v)
        pcall(function()
            if getgenv then getgenv().ElytraPreviewDragging = v and true or false end
        end)
    end
    setPreviewDragging(false)

    -- Base positions (without layout offset) used while dragging for live feedback
    local previewBase = {
        Name = function(off) return UDim2.new(0.5, off.X or 0, 0, -5 + (off.Y or 0)) end,
        Studs = function(off) return UDim2.new(0.5, off.X or 0, 1, 4 + (off.Y or 0)) end,
        Tool = function(off) return UDim2.new(0.5, off.X or 0, 1, 17 + (off.Y or 0)) end,
    }
    local function bindPreviewDrag(guiObj, layoutKey)
        if not guiObj then return end
        pcall(function()
            guiObj.Active = true
            guiObj.ZIndex = math.max(guiObj.ZIndex, 40)
            -- No visible highlight — fully transparent hit target
            if guiObj:IsA("TextLabel") or guiObj:IsA("TextButton") then
                guiObj.BackgroundTransparency = 1
            end
        end)
        trackConn(guiObj.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            local lay = ensureLayout(layoutKey)
            setPreviewDragging(true)
            _previewDrag = {
                key = layoutKey,
                obj = guiObj,
                startMouse = Vector2.new(input.Position.X, input.Position.Y),
                startX = lay.X or 0,
                startY = lay.Y or 0,
            }
        end))
    end
    -- Same placement math as live ESP: box origin top-left (0,0), size (bw,bh)
    local function applyOnePreviewPos(key, bw, bh)
        local ox, oy = layoutPixels(key, bw, bh)
        local barPos = Config.Bars.Health.Position or "Left"
        local hpOn = Config.Enabled and Config.Bars.Health.Enable
        local arOn = Config.Enabled and Config.Bars.Armor.Enable
        local barColW = 0
        if barPos == "Left" then
            if arOn and hpOn then barColW = 16
            elseif arOn or hpOn then barColW = 9 end
        end
        local leftEdge = -barColW - 4
        local yCursor = bh + 4
        if barPos == "Bottom" then
            if arOn then yCursor = bh + 17 elseif hpOn then yCursor = bh + 10 end
        end
        if key == "Name" then
            lblName.Position = UDim2.fromOffset(bw * 0.5 + ox, -4 + oy)
        elseif key == "Studs" then
            lblStuds.Position = UDim2.fromOffset(bw * 0.5 + ox, yCursor + oy)
        elseif key == "Tool" then
            if Config.Text.Studs.Enable then yCursor = yCursor + 14 end
            lblTool.Position = UDim2.fromOffset(bw * 0.5 + ox, yCursor + oy)
        elseif key == "ArmorText" then
            lblArmor.Position = UDim2.fromOffset(leftEdge + ox, -1 + oy)
        elseif key == "HealthText" then
            local healthY = Config.Text.Armor.Enable and 1 or -1
            lblHealth.Position = UDim2.fromOffset(leftEdge + ox, healthY + oy)
        end
    end
    trackConn(UserInputService.InputChanged:Connect(function(input)
        if not _previewDrag then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local dx = input.Position.X - _previewDrag.startMouse.X
        local dy = input.Position.Y - _previewDrag.startMouse.Y
        -- Always normalize against logical box size (matches cfg Width/Height used by refresh)
        local cfg = ESPPreview.Images[ESPPreview.SelectedImage]
        local bw = math.max(1, (cfg and cfg.Width) or centerHolder.AbsoluteSize.X)
        local bh = math.max(1, (cfg and cfg.Height) or centerHolder.AbsoluteSize.Y)
        local lay = ensureLayout(_previewDrag.key)
        lay.X = math.clamp(_previewDrag.startX + dx / bw, -1.5, 1.5)
        lay.Y = math.clamp(_previewDrag.startY + dy / bh, -1.5, 1.5)
        applyOnePreviewPos(_previewDrag.key, bw, bh)
    end))
    trackConn(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            _previewDrag = nil
            setPreviewDragging(false)
        end
    end))
    bindPreviewDrag(lblName, "Name")
    bindPreviewDrag(lblStuds, "Studs")
    bindPreviewDrag(lblTool, "Tool")
    bindPreviewDrag(lblHealth, "HealthText")
    bindPreviewDrag(lblArmor, "ArmorText")
    -- Bars are not draggable (fixed to box sides)

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
        centerHolder.Size   = UDim2.fromOffset(cfg.Width or 140, cfg.Height or 200)
        -- Always show the full image with transparent background
        previewImage.Size   = UDim2.fromScale(1, 1)
        previewImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        previewImage.BackgroundTransparency = 1
        previewImage.BorderSizePixel = 0
        imageMask.BackgroundTransparency = 1
        imageMask.BorderSizePixel = 0
        centerHolder.BackgroundTransparency = 1
        loadPreviewImage(cfg.Url)
    end

    ESPPreviewSection:Dropdown({
        Name = "Preview Image", Flag = "esp_preview_image",
        Items = { "Donald Trump", "Elon Musk" },
        Default = "Donald Trump",
        Callback = function(v)
            ESPPreview.SelectedImage = v
            applySelectedPreview()
        end,
    })

    ESPPreviewSection:Button({
        Name = "Reset ESP Layout",
        Callback = function()
            Config.Layout = {}
            pcall(function()
                if getgenv then getgenv().ElytraPreviewDragging = false end
            end)
        end,
    })

    applySelectedPreview()

    local previewFrame = 0
    local _lastPreviewHash = ""
    trackConn(RunService.Heartbeat:Connect(function()
        if not Alive then return end
        if not previewMain or not previewMain.Parent then return end
        previewFrame = previewFrame + 1
        -- ~10Hz is plenty for a static preview panel
        if previewFrame % 6 ~= 0 then return end
        previewMain.Visible = true

        local cfg = ESPPreview.Images[ESPPreview.SelectedImage]
        local bw = (cfg and cfg.Width)  or 95
        local bh = (cfg and cfg.Height) or 155

        local boxShow = Config.Enabled and Config.Box.Enable
        for _, edge in ipairs({bTop,bBot,bLeft,bRight,bTopO,bBotO,bLeftO,bRightO}) do edge.Visible = false end
        if boxShow then
            local t, o = 1, 1
            local boxColor = Config.Box.Color or Color3.new(1,1,1)
            bTopO.Visible=true; bTopO.Position=UDim2.fromOffset(-o, -o);           bTopO.Size=UDim2.fromOffset(bw + o*2, t + o*2)
            bBotO.Visible=true; bBotO.Position=UDim2.fromOffset(-o, bh - t - o);   bBotO.Size=UDim2.fromOffset(bw + o*2, t + o*2)
            bLeftO.Visible=true;bLeftO.Position=UDim2.fromOffset(-o, -o);          bLeftO.Size=UDim2.fromOffset(t + o*2, bh + o*2)
            bRightO.Visible=true;bRightO.Position=UDim2.fromOffset(bw - t - o, -o);bRightO.Size=UDim2.fromOffset(t + o*2, bh + o*2)
            bTop.Visible=true;bTop.BackgroundColor3=boxColor;bTop.Position=UDim2.fromOffset(0,0);bTop.Size=UDim2.fromOffset(bw,t)
            bBot.Visible=true;bBot.BackgroundColor3=boxColor;bBot.Position=UDim2.fromOffset(0,bh-t);bBot.Size=UDim2.fromOffset(bw,t)
            bLeft.Visible=true;bLeft.BackgroundColor3=boxColor;bLeft.Position=UDim2.fromOffset(0,0);bLeft.Size=UDim2.fromOffset(t,bh)
            bRight.Visible=true;bRight.BackgroundColor3=boxColor;bRight.Position=UDim2.fromOffset(bw-t,0);bRight.Size=UDim2.fromOffset(t,bh)
        end

        -- Skeleton / head scaled to current preview size so it matches the photo body
        local sx, sy = bw / 95, bh / 155
        local skelShow = Config.Enabled and Config.Skeleton.Enable
        local skelCol  = Config.Skeleton.Color or Color3.new(1,1,1)
        for i, line in ipairs(skelLines) do
            if skelShow then
                local p = skelPairs[i]
                local x1,y1 = p[1]*sx, p[2]*sy
                local x2,y2 = p[3]*sx, p[4]*sy
                local dx,dy = x2-x1, y2-y1
                local len = math.sqrt(dx*dx + dy*dy)
                line.Visible = true
                line.BackgroundColor3 = skelCol
                line.Size = UDim2.fromOffset(math.max(len,1), math.max(1, math.floor(1.2*sx)))
                line.Position = UDim2.fromOffset((x1+x2)/2, (y1+y2)/2)
                line.Rotation = math.deg(math.atan2(dy, dx))
            else
                line.Visible = false
            end
        end

        if Config.Enabled and Config.HeadCircle.Enable then
            -- Head joint at (47.5, 20) in base coords
            local hx, hy = 47.5 * sx, 20 * sy
            local hs = math.max(16, math.floor(22 * math.min(sx, sy)))
            previewHead.Visible = true
            previewHead.Size = UDim2.fromOffset(hs, hs)
            previewHead.Position = UDim2.fromOffset(hx - hs/2, hy - hs/2)
            previewHeadStroke.Color = Config.HeadCircle.Color or Color3.new(1,1,1)
            previewHeadStroke.Thickness = math.max(1, sx * 0.9)
        else
            previewHead.Visible = false
        end

        -- Preview font style can follow setting; size stays fixed so preview doesn't scale with Text Size slider
        local previewFont = Config.Font or Enum.Font.GothamBold
        local PREVIEW_TS = 11
        for _, lbl in ipairs({lblName, lblStuds, lblTool, lblArmor, lblHealth}) do
            if lbl then
                lbl.Font = previewFont
                lbl.TextSize = PREVIEW_TS
            end
        end

        -- Exact same placement rules as live ESP (box = centerHolder 0,0 → bw,bh)
        local barPos = Config.Bars.Health.Position or "Left"
        local hpOnPrev = Config.Enabled and Config.Bars.Health.Enable
        local arOnPrev = Config.Enabled and Config.Bars.Armor.Enable
        local barColW = 0
        if barPos == "Left" then
            if arOnPrev and hpOnPrev then barColW = 16
            elseif arOnPrev or hpOnPrev then barColW = 9 end
        end
        local leftEdge = -barColW - 4

        if Config.Enabled and Config.Text.Name.Enable then
            local ox, oy = layoutPixels("Name", bw, bh)
            lblName.Visible = true
            lblName.TextColor3 = Config.Text.Name.Color
            lblName.AnchorPoint = Vector2.new(0.5, 1)
            lblName.TextXAlignment = Enum.TextXAlignment.Center
            lblName.Size = UDim2.fromOffset(260, PREVIEW_TS + 3)
            -- live: (centerX + ox, boxTop - 4 + oy)
            lblName.Position = UDim2.fromOffset(bw * 0.5 + ox, -4 + oy)
            local sel = ESPPreview.SelectedImage
            local dn, un
            if sel == "Local Player" then
                dn, un = LocalPlayer.DisplayName, LocalPlayer.Name
            else
                local c = ESPPreview.Images[sel]
                dn = (c and c.DisplayName) or sel
                un = (c and c.Username)    or sel
            end
            local t = Config.Text.Name.Type
            if t == "Display" then lblName.Text = dn
            elseif t == "Username" then lblName.Text = un
            else lblName.Text = dn .. " (@" .. un .. ")" end
        else
            lblName.Visible = false
        end

        local yCursor = bh + 4
        if barPos == "Bottom" then
            if arOnPrev then yCursor = bh + 17 elseif hpOnPrev then yCursor = bh + 10 end
        end
        if Config.Enabled and Config.Text.Studs.Enable then
            local ox, oy = layoutPixels("Studs", bw, bh)
            lblStuds.Visible = true
            lblStuds.TextColor3 = Config.Text.Studs.Color
            lblStuds.Text = Config.DistanceUnit == "Studs" and "[54 studs]" or "[15m]"
            lblStuds.AnchorPoint = Vector2.new(0.5, 0)
            lblStuds.TextXAlignment = Enum.TextXAlignment.Center
            lblStuds.Size = UDim2.fromOffset(120, PREVIEW_TS + 3)
            -- live: (centerX + ox, yCursor + oy)
            lblStuds.Position = UDim2.fromOffset(bw * 0.5 + ox, yCursor + oy)
            yCursor = yCursor + 14
        else
            lblStuds.Visible = false
        end
        if Config.Enabled and Config.Text.Tool.Enable then
            local ox, oy = layoutPixels("Tool", bw, bh)
            lblTool.Visible = true
            lblTool.TextColor3 = Config.Text.Tool.Color
            lblTool.Text = "[Revolver]"
            lblTool.AnchorPoint = Vector2.new(0.5, 0)
            lblTool.TextXAlignment = Enum.TextXAlignment.Center
            lblTool.Size = UDim2.fromOffset(160, PREVIEW_TS + 3)
            -- live: (centerX + ox, yCursor + oy)
            lblTool.Position = UDim2.fromOffset(bw * 0.5 + ox, yCursor + oy)
        else
            lblTool.Visible = false
        end

        if Config.Enabled and Config.Text.Armor.Enable then
            local ox, oy = layoutPixels("ArmorText", bw, bh)
            lblArmor.Visible = true
            lblArmor.TextColor3 = Config.Text.Armor.Color or Color3.fromRGB(30, 110, 255)
            lblArmor.Text = "100 armor"
            lblArmor.AnchorPoint = Vector2.new(1, 1)
            lblArmor.TextXAlignment = Enum.TextXAlignment.Right
            lblArmor.Size = UDim2.fromOffset(120, PREVIEW_TS + 2)
            -- live: (leftEdge + ox, boxTop - 1 + oy)
            lblArmor.Position = UDim2.fromOffset(leftEdge + ox, -1 + oy)
        else
            lblArmor.Visible = false
        end
        if Config.Enabled and Config.Text.Health.Enable then
            local ox, oy = layoutPixels("HealthText", bw, bh)
            lblHealth.Visible = true
            lblHealth.TextColor3 = Config.Text.Health.Color or Color3.fromRGB(80, 220, 100)
            lblHealth.Text = "100 health"
            lblHealth.AnchorPoint = Vector2.new(1, 0)
            lblHealth.TextXAlignment = Enum.TextXAlignment.Right
            lblHealth.Size = UDim2.fromOffset(120, PREVIEW_TS + 2)
            local healthY = Config.Text.Armor.Enable and 1 or -1
            -- live: (leftEdge + ox, healthY + oy)
            lblHealth.Position = UDim2.fromOffset(leftEdge + ox, healthY + oy)
        else
            lblHealth.Visible = false
        end

        local pos = barPos
        if Config.Enabled and Config.Bars.Health.Enable then
            hpOutline.Visible = true
            hpOutline.BackgroundColor3 = Color3.new(0, 0, 0)
            hpOutline.BackgroundTransparency = 0
            hpOutline.ZIndex = 40
            hpFill.Visible = true
            hpFill.ZIndex = 41
            hpFill.BackgroundTransparency = 0
            -- Match live ESP green health bar
            hpFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
            pcall(function() hpGrad.Enabled = false end)
            if pos == "Left" then
                hpOutline.Size = UDim2.fromOffset(5, bh)
                hpOutline.Position = UDim2.fromOffset(-7, 0)
                hpFill.Size = UDim2.new(1, -2, 0.85, -2)
                hpFill.Position = UDim2.new(0, 1, 0.15, 1)
            elseif pos == "Right" then
                hpOutline.Size = UDim2.fromOffset(5, bh)
                hpOutline.Position = UDim2.fromOffset(bw + 3, 0)
                hpFill.Size = UDim2.new(1, -2, 0.85, -2)
                hpFill.Position = UDim2.new(0, 1, 0.15, 1)
            elseif pos == "Top" then
                hpOutline.Size = UDim2.fromOffset(bw, 5)
                hpOutline.Position = UDim2.fromOffset(0, -7)
                hpFill.Size = UDim2.new(0.85, -2, 1, -2)
                hpFill.Position = UDim2.fromOffset(1, 1)
            else
                hpOutline.Size = UDim2.fromOffset(bw, 5)
                hpOutline.Position = UDim2.fromOffset(0, bh + 3)
                hpFill.Size = UDim2.new(0.85, -2, 1, -2)
                hpFill.Position = UDim2.fromOffset(1, 1)
            end
        else
            hpOutline.Visible = false
        end

        if Config.Enabled and Config.Bars.Armor.Enable then
            armOutline.Visible = true
            armOutline.BackgroundColor3 = Color3.new(0, 0, 0)
            armOutline.BackgroundTransparency = 0
            armOutline.ZIndex = 40
            armFill.Visible = true
            armFill.ZIndex = 41
            armFill.BackgroundTransparency = 0
            -- Match live ESP cyan/blue armor bar
            armFill.BackgroundColor3 = Color3.fromRGB(50, 170, 255)
            pcall(function() armGrad.Enabled = false end)
            if pos == "Left" then
                armOutline.Size = UDim2.fromOffset(5, bh)
                armOutline.Position = UDim2.fromOffset(-13, 0)
                armFill.Size = UDim2.new(1, -2, 1, -2)
                armFill.Position = UDim2.fromOffset(1, 1)
            elseif pos == "Right" then
                armOutline.Size = UDim2.fromOffset(5, bh)
                armOutline.Position = UDim2.fromOffset(bw + 9, 0)
                armFill.Size = UDim2.new(1, -2, 1, -2)
                armFill.Position = UDim2.fromOffset(1, 1)
            elseif pos == "Top" then
                armOutline.Size = UDim2.fromOffset(bw, 5)
                armOutline.Position = UDim2.fromOffset(0, -13)
                armFill.Size = UDim2.new(1, -2, 1, -2)
                armFill.Position = UDim2.fromOffset(1, 1)
            else
                armOutline.Size = UDim2.fromOffset(bw, 5)
                armOutline.Position = UDim2.fromOffset(0, bh + 9)
                armFill.Size = UDim2.new(1, -2, 1, -2)
                armFill.Position = UDim2.fromOffset(1, 1)
            end
        else
            armOutline.Visible = false
        end
    end))
end

-- ============================================================
-- AIMVIEW BEAM SYSTEM
-- ============================================================
do
    local AIMVIEW_WEAPONS = { ["[Revolver]"]=true, ["[Double-Barrel SG]"]=true, ["[TacticalShotgun]"]=true }
    local aimViewBeam, aimViewBeamTool = nil, nil

    function destroyAimViewBeam()
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
    trackConn(RunService.Heartbeat:Connect(function()
        if not Alive then return end
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
    end))
end

-- ============================================================
-- PLAYER LIST
-- ============================================================
do
    local PlayerRows = {}
    local searchQuery = ""
    local autoWhitelistEnabled = true

    local THEME = {
        Inline       = Color3.fromRGB(18, 18, 20),
        Element      = Color3.fromRGB(28, 28, 32),
        ElementHover = Color3.fromRGB(38, 38, 44),
        ElementPress = Color3.fromRGB(48, 48, 56),
        Border       = Color3.fromRGB(55, 55, 62),
        BorderSoft   = Color3.fromRGB(45, 45, 52),
        Text         = Color3.fromRGB(230, 230, 235),
        TextOn       = Color3.fromRGB(18, 18, 20),
        TextDim      = Color3.fromRGB(140, 140, 150),
        TextOff      = Color3.fromRGB(100, 100, 110),
        White        = Color3.fromRGB(235, 235, 240),
        WhiteHover   = Color3.fromRGB(255, 255, 255),
        TrackOn      = Color3.fromRGB(90, 160, 255),
        TrackOff     = Color3.fromRGB(45, 45, 52),
        KnobOn       = Color3.fromRGB(255, 255, 255),
        KnobOff      = Color3.fromRGB(120, 120, 130),
        WLText       = Color3.fromRGB(230, 230, 235),
        WLTextOff    = Color3.fromRGB(120, 120, 130),
        SpecActive   = Color3.fromRGB(90, 160, 255),
        AimActive    = Color3.fromRGB(255, 120, 90),
        GotoActive   = Color3.fromRGB(100, 200, 130),
    }

    local function styleChip(chip, nameLabel, track, knob, isWL, hovered)
        local bg = hovered and THEME.ElementHover or THEME.Element
        chip.BackgroundColor3 = bg
        local stroke = chip:FindFirstChildOfClass("UIStroke")
        if isWL then
            if stroke then stroke.Color = THEME.TrackOn; stroke.Transparency = hovered and 0.25 or 0.4 end
            nameLabel.TextColor3 = THEME.Text
            track.BackgroundColor3 = THEME.TrackOn
            knob.Position = UDim2.new(1, -12, 0.5, 0)
            knob.BackgroundColor3 = THEME.KnobOn
        else
            if stroke then stroke.Color = THEME.BorderSoft; stroke.Transparency = hovered and 0.35 or 0.55 end
            nameLabel.TextColor3 = THEME.TextDim
            track.BackgroundColor3 = THEME.TrackOff
            knob.Position = UDim2.new(0, 2, 0.5, 0)
            knob.BackgroundColor3 = THEME.KnobOff
        end
    end

    local function applySearchFilter()
        local q = searchQuery:lower()
        for plr, ui in pairs(PlayerRows) do
            if ui.row then
                local display = (plr.DisplayName or ""):lower()
                local name    = (plr.Name or ""):lower()
                local visible
                if q == "" then
                    visible = true
                else
                    visible = display:sub(1, #q) == q or name:sub(1, #q) == q
                end
                ui.row.Visible = visible
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
        countLabel.Text = "0 online  ·  0 whitelisted"
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
        searchText.PlaceholderText = "Search players..."
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
            b.Size = UDim2.new(0.5, -3, 1, 0) -- half row
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
            Library:Notification("Whitelisted " .. c, 2)
        end)
        mkTopBtn("Blacklist All", function()
            local c = 0
            for plr, ui in pairs(PlayerRows) do
                if Whitelisted[plr] then Whitelisted[plr] = nil; c = c + 1 end
                if ui and ui.chip then styleChip(ui.chip, ui.nameLabel, ui.track, ui.knob, false, false) end
            end
            if forceESPreFresh then forceESPreFresh() end
            Library:Notification("Unwhitelisted " .. c, 2)
        end)

        local listFrame = Instance.new("ScrollingFrame")
        listFrame.Name = "PlayerListFrame"
        listFrame.Size = UDim2.new(1, 0, 0, 460)
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
            while Alive and task.wait(0.5) do
                local total, wl, bl = 0, 0, 0
                for plr in pairs(PlayerRows) do
                    total = total + 1
                    if Whitelisted[plr] then wl = wl + 1 else bl = bl + 1 end
                end
                if countLabel and countLabel.Parent then
                    countLabel.Text = string.format("%d online  ·  %d whitelisted  ·  %d blacklisted", total, wl, bl)
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

    local function setRowBtnActive(btn, stroke, active, activeColor)
        if not btn then return end
        btn:SetAttribute("IsActive", active and true or false)
        if active then
            local col = activeColor or THEME.White
            btn.BackgroundColor3 = col
            btn.TextColor3 = THEME.TextOn
            if stroke then stroke.Color = col; stroke.Transparency = 0.15 end
        else
            btn.BackgroundColor3 = THEME.Element
            btn.TextColor3 = THEME.Text
            if stroke then stroke.Color = THEME.BorderSoft; stroke.Transparency = 0.5 end
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
            if ui.btnSpec then ui.btnSpec.Text = isSpec and "Stop" or "Spec"; setRowBtnActive(ui.btnSpec, ui.specStroke, isSpec, THEME.SpecActive) end
            local isAim = (AimViewTarget == p)
            if ui.btnAim then ui.btnAim.Text = isAim and "Stop" or "Aim"; setRowBtnActive(ui.btnAim, ui.aimStroke, isAim, THEME.AimActive) end
        end
    end

    local function createPlayerRow(plr)
        if not Alive then return end
        if plr == LocalPlayer then return end
        if PlayerRows[plr] then return end
        if autoWhitelistEnabled then Whitelisted[plr] = true end

        local row = Instance.new("Frame")
        row.Name = plr.Name .. "_Row"
        row.Size = UDim2.new(1, -4, 0, 32)
        row.BackgroundTransparency = 1
        row.Parent = PListRowsHolder

        -- Absolute layout: chip stretches left, buttons fixed on the right (perfect columns)
        -- Chip gets most of the row so the full display name is readable
        local chip = Instance.new("TextButton")
        chip.Name = "NameChip"
        chip.Size = UDim2.new(1, -128, 1, 0)
        chip.Position = UDim2.fromOffset(0, 0)
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
        nameLabel.Size = UDim2.new(1, -40, 1, 0)
        nameLabel.Position = UDim2.new(0, 10, 0, 0)
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
            if Whitelisted[plr] then
                Whitelisted[plr] = nil
            else
                Whitelisted[plr] = true
                -- Drop any active combat locks on newly-whitelisted players
                if CurrentTarget == plr then CurrentTarget = nil end
                if CR_State and CR_State.ActiveTarget == plr then pcall(function() if cr_restore then cr_restore() end end) end
                if HBE_State and HBE_State.ActiveTarget == plr then pcall(function() if hb_restore then hb_restore() end end) end
                if re_activeTarget == plr then pcall(function() if re_restore then re_restore() end end) end
            end
            styleChip(chip, nameLabel, track, knob, Whitelisted[plr] and true or false, true)
            if forceESPreFresh then forceESPreFresh(plr) end
        end)

        local btnSpec, specStroke = mkRowButton(row, UDim2.fromOffset(40, 28), "Spec", function()
            if SpectateTarget == plr then clearSpectate()
            else
                SpectateTarget = plr
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then Camera.CameraType = Enum.CameraType.Custom; Camera.CameraSubject = hum end
            end
            updateAllPlayerUI()
        end)
        btnSpec.Position = UDim2.new(1, -124, 0.5, -14)
        btnSpec.TextSize = 11

        local btnAim, aimStroke = mkRowButton(row, UDim2.fromOffset(40, 28), "Aim", function()
            if AimViewTarget == plr then clearAimView() else AimViewTarget = plr end
            updateAllPlayerUI()
        end)
        btnAim.Position = UDim2.new(1, -82, 0.5, -14)
        btnAim.TextSize = 11

        local btnGoto, gotoStroke = mkRowButton(row, UDim2.fromOffset(40, 28), "Goto", function()
            teleportToPlayer(plr)
        end)
        btnGoto.Position = UDim2.new(1, -40, 0.5, -14)
        btnGoto.TextSize = 11

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

    trackConn(Players.PlayerAdded:Connect(function(plr)
        if plr ~= LocalPlayer then
            if autoWhitelistEnabled then Whitelisted[plr] = true end
            createPlayerRow(plr)
        end
    end))
    trackConn(Players.PlayerRemoving:Connect(removePlayerRow))
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if autoWhitelistEnabled then Whitelisted[plr] = true end
            createPlayerRow(plr)
        end
    end

    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive then return end
        if not SpectateTarget then return end
        local char = SpectateTarget.Character; if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        Camera.CameraType    = Enum.CameraType.Custom
        Camera.CameraSubject = hum
    end))
end

-- ============================================================
-- CORE HELPERS & LOOPS
-- ============================================================
do
    local function clickMouse1()
        if not VIM then return end
        local m = UserInputService:GetMouseLocation()
        pcall(function()
            VIM:SendMouseButtonEvent(m.X, m.Y, 0, true,  game, 1)
            task.wait(0.008)
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

    local function isValidTarget(target)
        if not target then return false end
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and
               (target == player.Character or target:IsDescendantOf(player.Character)) then
                if Whitelisted[player] and not hostDetectEnabled then return false end
                if isCombatImmune(player) then return false end
                return true
            end
        end
        return false
    end

    local function isLocalCrouching()
        -- Only Ctrl (common crouch bind). Do NOT treat C as crouch — it blocks shooting.
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
            return true
        end
        local char = LocalPlayer.Character
        if not char then return false end
        -- BodyEffects crouch/crawl flags (Da Hood style)
        local be = char:FindFirstChild("BodyEffects")
        if be then
            for _, name in ipairs({"Crouch", "Crouching", "Crawl", "Crawling", "Sneak"}) do
                local v = be:FindFirstChild(name)
                if v then
                    local val = v.Value
                    if val == true then return true end
                    if type(val) == "number" and val > 0 then return true end
                end
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
        local hbTarget = HBE_State.ActiveTarget
        if hbTarget and not Whitelisted[hbTarget] and hbTarget.Character then
            local hbHum = hbTarget.Character:FindFirstChildOfClass("Humanoid")
            if hbHum and hbHum.Health > 0 then
                return true
            end
        end
        local crTarget = CR_State.ActiveTarget
        if crTarget and not Whitelisted[crTarget] and crTarget.Character then
            local crHum = crTarget.Character:FindFirstChildOfClass("Humanoid")
            if crHum and crHum.Health > 0 then
                return true
            end
        end
        if not isValidTarget(target) then return false end
        local distance = getTargetDistance(target)
        if distance then
            local character = LocalPlayer.Character
            local tool = character and character:FindFirstChildWhichIsA("Tool")
            local maxRange
            local reRange = tool and getRangeExtenderRange(tool)
            if reRange then
                maxRange = reRange
            elseif tool and tool.Name:lower():find("revolver", 1, true) then
                maxRange = Triggerbot.GunRanges["[Revolver]"] or 238
            else
                maxRange = GunMacro.MaxRange
            end
            if maxRange > 0 and distance > maxRange then return false end
        end
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

    local function trig_rayAABB(origin, dir, center, half)
        local tmin, tmax = 0, math.huge
        local axes = {
            { origin.X, dir.X, center.X, half.X },
            { origin.Y, dir.Y, center.Y, half.Y },
            { origin.Z, dir.Z, center.Z, half.Z },
        }
        for i = 1, 3 do
            local o, d, c, h = axes[i][1], axes[i][2], axes[i][3], axes[i][4]
            local lo, hi = c - h, c + h
            if math.abs(d) < 1e-6 then
                if o < lo or o > hi then return nil end
            else
                local t1, t2 = (lo - o) / d, (hi - o) / d
                if t1 > t2 then t1, t2 = t2, t1 end
                if t1 > tmin then tmin = t1 end
                if t2 < tmax then tmax = t2 end
                if tmin > tmax then return nil end
            end
        end
        return tmin
    end

    local function trig_getMouseRay()
        local ok, ray = pcall(function() return Mouse.UnitRay end)
        if ok and ray and ray.Origin and ray.Direction then return ray end
        local mp = UserInputService:GetMouseLocation()
        local ok2, camRay = pcall(function() return Camera:ViewportPointToRay(mp.X, mp.Y) end)
        if ok2 and camRay and camRay.Origin and camRay.Direction then return camRay end
        return nil
    end

        local function getHBESizeTargetChar(currentTool)
        local myChar = LocalPlayer.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return nil end
        local ray = trig_getMouseRay()
        if not ray then return nil end

        local maxRange = getRangeExtenderRange(currentTool) or getMaxRange(currentTool)

        local myPos = myHrp.Position
        local expand = Vector3.new(
            HitboxExpanderState and HitboxExpanderState.X or 0,
            HitboxExpanderState and HitboxExpanderState.Y or 0,
            HitboxExpanderState and HitboxExpanderState.Z or 0
        )

        local best, bestScore = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and not Whitelisted[plr] then
                local char = plr.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        local knocked = false
                        local be = char:FindFirstChild("BodyEffects")
                        if be then
                            local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
                            if ko then
                                local kv = ko.Value
                                if type(kv) == "boolean" then knocked = kv
                                elseif type(kv) == "number" then knocked = kv > 0
                                elseif type(kv) == "string" then knocked = kv ~= "" and kv ~= "false" and kv ~= "0"
                                end
                            end
                        end
                        if not knocked then
                            local d = (hrp.Position - myPos).Magnitude
                            if d <= maxRange then
                                local half = hrp.Size * 0.5 + expand
                                local t = trig_rayAABB(ray.Origin, ray.Direction, hrp.Position, half)
                                if t and t < bestScore then
                                    bestScore = t
                                    best = char
                                end
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    -- ── Gun-macro validation helpers ──
    -- when using the new HBE-size / CR-FOV paths.

    local function gm_isKnocked(plr)
        if not plr then return false end
        local ok, knocked = pcall(function()
            local playersFolder = workspace:FindFirstChild("Players")
            if not playersFolder then return false end
            local pFolder = playersFolder:FindFirstChild(plr.Name)
            if not pFolder then return false end
            local bodyEffects = pFolder:FindFirstChild("BodyEffects")
            if not bodyEffects then return false end
            local ko = bodyEffects:FindFirstChild("K.O") or bodyEffects:FindFirstChild("KO")
            if not ko then return false end
            if ko:IsA("BoolValue") then return ko.Value
            elseif ko:IsA("IntValue") or ko:IsA("NumberValue") then return ko.Value > 0
            elseif ko:IsA("StringValue") then
                local v = ko.Value
                return v ~= "" and v ~= "false" and v ~= "0"
            end
            return ko.Value == true
        end)
        return ok and knocked == true
    end

        local function gunMacroHBECheck(curTool)
        local myChar = LocalPlayer.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return false end
        local ray = trig_getMouseRay()
        if not ray then return false end

        local myPos = myHrp.Position
        local maxRange = getRangeExtenderRange(curTool) or getMaxRange(curTool)

        -- Uses your actual HBE slider size
        local expand = Vector3.new(
            HitboxExpanderState and HitboxExpanderState.X or 0,
            HitboxExpanderState and HitboxExpanderState.Y or 0,
            HitboxExpanderState and HitboxExpanderState.Z or 0
        )

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and not Whitelisted[plr] and not gm_isKnocked(plr) and not isCombatImmune(plr) then
                local pchar = plr.Character
                local phrp  = pchar and pchar:FindFirstChild("HumanoidRootPart")
                local phum  = pchar and pchar:FindFirstChildOfClass("Humanoid")
                if phrp and phum and phum.Health > 0 then
                    local d = (phrp.Position - myPos).Magnitude
                    if d <= maxRange then
                        local bodyHalf = phrp.Size * 0.5 + expand
                        local t = trig_rayAABB(ray.Origin, ray.Direction, phrp.Position, bodyHalf)
                        if t then return true end
                    end
                end
            end
        end
        return false
    end

    -- ── Gun macro loop (single instance) ──
        -- ── Gun macro loop (single instance) ──
    task.spawn(function()
        while Alive do
            GunMacro.Active = GunMacro.Enabled
            if not GunMacro.Active then task.wait(0.05) continue end

            -- [UseCRFOV] fire only when a target is inside the CR FOV circle.
            if false then -- UseCRFOV removed
                local ok = false

                local crTarget = CR_State.ActiveTarget
                if crTarget and crTarget.Character then
                    local crHum = crTarget.Character:FindFirstChildOfClass("Humanoid")
                    if crHum and crHum.Health > 0 then ok = true end
                end

                if not ok then
                    local mouseLoc = UserInputService:GetMouseLocation()
                    local fovRadius = (ClientRedirectionState and ClientRedirectionState.FOV) or 100
                    local needVis   = ClientRedirectionState and ClientRedirectionState.VisibleCheck
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer and not Whitelisted[plr] and not gm_isKnocked(plr) and not isCombatImmune(plr) then
                            local pchar = plr.Character
                            local phrp  = pchar and pchar:FindFirstChild("HumanoidRootPart")
                            local phum  = pchar and pchar:FindFirstChildOfClass("Humanoid")
                            if phrp and phum and phum.Health > 0 then
                                if not needVis or gm_isVisible(pchar) then
                                    local sp, onScreen = Camera:WorldToViewportPoint(phrp.Position)
                                    if onScreen and sp.Z > 0 then
                                        local dd = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                                        if dd <= fovRadius then ok = true; break end
                                    end
                                end
                            end
                        end
                    end
                end

                if not ok then task.wait(0.05) continue end
            end

            -- Detect whether HBE or CR already owns a target (respect spawn FF / protect)
            local usingExpander = false
            local hbTarget = HBE_State.ActiveTarget
            if hbTarget and not Whitelisted[hbTarget] and not isCombatImmune(hbTarget) and hbTarget.Character then
                local hbHum = hbTarget.Character:FindFirstChildOfClass("Humanoid")
                if hbHum and hbHum.Health > 0 then usingExpander = true end
            end
            if not usingExpander then
                local crTarget = CR_State.ActiveTarget
                if crTarget and not Whitelisted[crTarget] and not isCombatImmune(crTarget) and crTarget.Character then
                    local crHum = crTarget.Character:FindFirstChildOfClass("Humanoid")
                    if crHum and crHum.Health > 0 then usingExpander = true end
                end
            end

                        -- Pre-check: is there actually something to shoot?
            -- Prevents pulling DB/TSG out when there is no target.
            local hasTarget = false
            if usingExpander then
                hasTarget = true
            else
                -- Range we'd have with the tool we're about to equip
                local targetToolName = GunMacro.Tools[1]
                local preCheckRange  = getRangeExtenderRange(targetToolName)
                if not preCheckRange then
                    local r = Triggerbot.GunRanges[targetToolName]
                    if not r then
                        local n = targetToolName:lower()
                        for gunName, gr in pairs(Triggerbot.GunRanges) do
                            if n:find(gunName:lower(), 1, true) then r = gr; break end
                        end
                    end
                    preCheckRange = r or GunMacro.MaxRange
                end

                -- Check 1: mouse over a valid target within that range
                local mt = Mouse.Target
                if mt and isValidTarget(mt) then
                    local dist = getTargetDistance(mt)
                    if dist and (preCheckRange <= 0 or dist <= preCheckRange) then
                        hasTarget = true
                    end
                end

                -- Check 2 (UseHBESize path): target inside expanded AABB within range
                if false then -- UseHBESize removed
                    local myChar = LocalPlayer.Character
                    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    local ray = myHrp and trig_getMouseRay()
                    if myHrp and ray then
                        local expand = Vector3.new(
                            HitboxExpanderState and HitboxExpanderState.X or 0,
                            HitboxExpanderState and HitboxExpanderState.Y or 0,
                            HitboxExpanderState and HitboxExpanderState.Z or 0
                        )
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer and not Whitelisted[plr] and not gm_isKnocked(plr) and not isCombatImmune(plr) then
                                local pchar = plr.Character
                                local phrp = pchar and pchar:FindFirstChild("HumanoidRootPart")
                                local phum = pchar and pchar:FindFirstChildOfClass("Humanoid")
                                if phrp and phum and phum.Health > 0
                                   and (preCheckRange <= 0 or (phrp.Position - myHrp.Position).Magnitude <= preCheckRange) then
                                    local bodyHalf = phrp.Size * 0.5 + expand
                                    if trig_rayAABB(ray.Origin, ray.Direction, phrp.Position, bodyHalf) then
                                        hasTarget = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if not hasTarget then task.wait(0.05) continue end

            if not equip(GunMacro.Tools[1]) then task.wait(0.05) continue end

            local function canShootNow()
                if usingExpander then
                    return true 
                end
                
                -- If UseHBESize is on, run the fixed virtual AABB check
                if false then -- UseHBESize removed
                    local curTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Tool")
                    return curTool and gunMacroHBECheck(curTool) or false
                end
                
                -- Default macro validation
                return canFireAt(Mouse.Target)
            end

            if canShootNow() then
                clickMouse1()
                task.wait(GunMacro.Delay)
                if GunMacro.Tools[2] and equip(GunMacro.Tools[2]) and canShootNow() then
                    clickMouse1()
                end
                task.wait(GunMacro.Delay)
            else
                task.wait(0.05)
            end
        end
    end)

    -- ── Host Detection ammo guard ──
    local hd_localOutOfAmmo   = false
    local hd_sessionActive    = false
    local hd_localHasReloaded = false

    local hd_localAmmoConns = {}
    clearLocalAmmoConns = function()
        for _, c in ipairs(hd_localAmmoConns) do pcall(function() c:Disconnect() end) end
        hd_localAmmoConns = {}
    end

    attachLocalReloadWatcher = function()
        clearLocalAmmoConns()
        if not hostDetectEnabled then return end

        local char = LocalPlayer.Character
        if not char then return end

        local function watchAmmoValue(ammoVal)
            local prevAmmo = ammoVal.Value
            local conn
            local ok = pcall(function()
                conn = ammoVal:GetPropertyChangedSignal("Value"):Connect(function()
                    local newAmmo = ammoVal.Value
                    if type(newAmmo) ~= "number" or type(prevAmmo) ~= "number" then
                        prevAmmo = newAmmo; return
                    end
                    if newAmmo <= 0 and prevAmmo > 0 then
                        hd_localOutOfAmmo   = true
                        hd_sessionActive    = false
                        hd_localHasReloaded = false
                    elseif newAmmo > 0 and hd_localOutOfAmmo then
                        hd_localOutOfAmmo   = false
                        hd_localHasReloaded = true
                    end
                    prevAmmo = newAmmo
                end)
            end)
            if not ok or not conn then
                conn = ammoVal.Changed:Connect(function(newAmmo)
                    if type(newAmmo) ~= "number" then return end
                    if newAmmo <= 0 and prevAmmo > 0 then
                        hd_localOutOfAmmo   = true
                        hd_sessionActive    = false
                        hd_localHasReloaded = false
                    elseif newAmmo > 0 and hd_localOutOfAmmo then
                        hd_localOutOfAmmo   = false
                        hd_localHasReloaded = true
                    end
                    prevAmmo = newAmmo
                end)
            end
            table.insert(hd_localAmmoConns, conn)
        end

        local function scanToolForAmmo(tool)
            if not tool or tool.Name ~= HostDetection.ToolName then return end
            local ammo = tool:FindFirstChild(HostDetection.WatchAmmoName)
            if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then
                watchAmmoValue(ammo)
            end
            for _, d in ipairs(tool:GetDescendants()) do
                if (d:IsA("IntValue") or d:IsA("NumberValue")) and d.Name == HostDetection.WatchAmmoName then
                    watchAmmoValue(d)
                end
            end
        end

        local function scanContainer(container)
            if not container then return end
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then scanToolForAmmo(child) end
            end
        end

        scanContainer(char)
        scanContainer(LocalPlayer:FindFirstChild("Backpack"))

        local conn1 = char.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then task.wait(0.05); scanToolForAmmo(child) end
        end)
        table.insert(hd_localAmmoConns, conn1)
    end

    trackConn(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        hd_localOutOfAmmo   = false
        hd_sessionActive    = false
        hd_localHasReloaded = false
        if Alive and hostDetectEnabled then attachLocalReloadWatcher() end
    end))

    task.spawn(function()
        while Alive do
            task.wait(2)
            if hostDetectEnabled then pcall(attachLocalReloadWatcher) end
        end
    end)

    -- ── Triggerbot loop ──
        task.spawn(function()
        while Alive do
            task.wait()
            if not Alive then break end
            if not Triggerbot.Enabled then continue end

            -- Host-detection gate (unchanged)
            if hostDetectEnabled then
                if not hd_sessionActive then
                    if not hostReady then continue end
                    if hd_localOutOfAmmo then continue end
                    hd_sessionActive = true
                    hostReady = false
                end
            end

            local character = LocalPlayer.Character
            if not character then continue end
            -- Never shoot while local player is crouched / holding crouch
            if isLocalCrouching() then continue end
            local tool = character:FindFirstChildWhichIsA("Tool")
            if not tool or isToolBlacklisted(tool) then continue end

            -- Does HBE or CR currently own a live target?
            local usingExpander   = false
            local expanderTarget  = nil
            local hbTarget = HBE_State.ActiveTarget
            if hbTarget and not Whitelisted[hbTarget] and not isCombatImmune(hbTarget) and hbTarget.Character then
                local hbHum = hbTarget.Character:FindFirstChildOfClass("Humanoid")
                if hbHum and hbHum.Health > 0 then
                    usingExpander  = true
                    expanderTarget = hbTarget.Character
                end
            end
            if not usingExpander then
                local crTarget = CR_State.ActiveTarget
                if crTarget and not Whitelisted[crTarget] and not isCombatImmune(crTarget) and crTarget.Character then
                    local crHum = crTarget.Character:FindFirstChildOfClass("Humanoid")
                    if crHum and crHum.Health > 0 then
                        usingExpander  = true
                        expanderTarget = crTarget.Character
                    end
                end
            end

            -- Determine target.
            -- The UseCRFOV / UseHBESize toggles are now NON-FATAL: if the
            -- condition they gate on isn't met (CR has no lock, HBE AABB misses),
            -- we fall through to Mouse.Target instead of skipping every frame.
            local targetChar = nil

            if usingExpander then
                targetChar = expanderTarget
            end

            if false then -- UseCRFOV removed
                local crTarget = CR_State.ActiveTarget
                if crTarget and crTarget.Character then
                    local crHum = crTarget.Character:FindFirstChildOfClass("Humanoid")
                    if crHum and crHum.Health > 0 then targetChar = crTarget.Character end
                end
            end

            if false then -- UseHBESize removed
                local hbeChar = getHBESizeTargetChar(tool)
                if hbeChar then targetChar = hbeChar end
            end

            if not targetChar then
                local mt = Mouse.Target
                if mt and isValidTarget(mt) then
                    targetChar = getTargetCharacter(mt)
                end
            end

            if not targetChar then continue end

            -- Range check (per-gun RE range if enabled, else natural gun range)
            if not usingExpander then
                local myRoot     = character:FindFirstChild("HumanoidRootPart")
                local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
                if myRoot and targetRoot then
                    local maxRange = getRangeExtenderRange(tool) or getMaxRange(tool)
                    if maxRange > 0 and (targetRoot.Position - myRoot.Position).Magnitude > maxRange then
                        continue
                    end
                end
            end

            -- Delay + release
            local useDelay = hostDetectEnabled and (HostDetection.DelayMs / 1000) or Triggerbot.Delay
            if useDelay > 0 then task.wait(useDelay) end
            if not Triggerbot.Enabled then continue end
            if hostDetectEnabled and not hd_sessionActive then continue end
            if isLocalCrouching() then continue end
            -- Re-validate target is still not knocked after delay
            if targetChar then
                local tp = Players:GetPlayerFromCharacter(targetChar)
                if tp and isCombatImmune(tp) then continue end
            end

            tool:Activate()
            if Triggerbot.Release > 0 then task.wait(Triggerbot.Release) end
        end
    end)
end

-- ============================================================
-- AIMBOT LOOP
-- ============================================================
do
    local FOVCircle
    local FOVCircleFill
    pcall(function()
        local c = Drawing.new("Circle")
        if c then
            FOVCircle = trackDraw(c)
            c.Thickness, c.NumSides, c.Radius = 1, 64, MouseLock.FOV
            c.Filled, c.Visible, c.Color, c.Transparency = false, false, MouseLock.CircleColor, 1
            c.Position = Vector2.new(0, 0)
        end
    end)
    pcall(function()
        local cf = Drawing.new("Circle")
        if cf then
            FOVCircleFill = trackDraw(cf)
            cf.Thickness, cf.NumSides = 0, 64
            cf.Filled = true
            cf.Visible = false
            cf.Color = MouseLock.FillFOVColor
            cf.Transparency = 0.5
            cf.Radius = MouseLock.FOV
            cf.Position = Vector2.new(0, 0)
        end
    end)

    local function IsAlive(player)
        local char = player.Character; if not char then return false end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local root     = char:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health <= 0 or not root then return false end
        local be = char:FindFirstChild("BodyEffects")
        if be and be:FindFirstChild("K.O") and be["K.O"].Value == true then return false end
        return true
    end
    local function aim_isVisible(char)
        if not char then return false end
        local ref = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not ref then return false end
        local origin = Camera.CFrame.Position
        local dir = ref.Position - origin
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { char }
        if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
        params.FilterDescendantsInstances = filter
        local hit = workspace:Raycast(origin, dir, params)
        if not hit or hit.Instance:IsDescendantOf(char) then return true end
        return false
    end
    local function GetClosestPlayerInFOV()
        local closest, shortest = nil, math.huge
        local mousePos = UserInputService:GetMouseLocation()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and IsAlive(player) and not Whitelisted[player] then
                local char = player.Character
                if MouseLock.VisibleCheck and not aim_isVisible(char) then continue end
                local root = char:FindFirstChild("HumanoidRootPart")
                if not root then continue end
                local sp, onScreen = Camera:WorldToViewportPoint(root.Position)
                if onScreen then
                    local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                    if d <= MouseLock.FOV and d < shortest then shortest, closest = d, player end
                end
            end
        end
        return closest
    end

    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive then return end
        local mousePos = UserInputService:GetMouseLocation()
        if FOVCircle then
            FOVCircle.Position = mousePos
            FOVCircle.Radius   = MouseLock.FOV
            FOVCircle.Visible  = MouseLock.VisibleFOV
            FOVCircle.Color    = MouseLock.CircleColor
        end
        if FOVCircleFill then
            FOVCircleFill.Position     = mousePos
            FOVCircleFill.Radius       = MouseLock.FOV
            FOVCircleFill.Visible      = MouseLock.VisibleFOV and MouseLock.FillFOV
            FOVCircleFill.Color        = MouseLock.FillFOVColor
            FOVCircleFill.Transparency = MouseLock.FillFOVTransparency
        end
        if not MouseLock.Enabled then return end
        if MouseLock.Sticky then
            if not (CurrentTarget and IsAlive(CurrentTarget) and not Whitelisted[CurrentTarget]) then
                CurrentTarget = GetClosestPlayerInFOV()
                if not CurrentTarget then return end
            elseif MouseLock.VisibleCheck and CurrentTarget.Character and not aim_isVisible(CurrentTarget.Character) then
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
            local sp = Camera:WorldToViewportPoint(predicted)
            local mouseLoc = UserInputService:GetMouseLocation()
            local dx = sp.X - mouseLoc.X
            local dy = sp.Y - mouseLoc.Y
            if math.sqrt(dx*dx + dy*dy) < MouseLock.Deadzone then return end
            mousemoverel(dx * MouseLock.Smoothness, dy * MouseLock.Smoothness)
        else
            local camPos = Camera.CFrame.Position
            local desired = CFrame.new(camPos, predicted)
            local alpha = math.clamp(MouseLock.Smoothness, 0.01, 1)
            local sp = Camera:WorldToViewportPoint(predicted)
            local mouseLoc = UserInputService:GetMouseLocation()
            local dx = sp.X - mouseLoc.X
            local dy = sp.Y - mouseLoc.Y
            if math.sqrt(dx*dx + dy*dy) < MouseLock.Deadzone then return end
            if alpha >= 0.99 then Camera.CFrame = desired
            else Camera.CFrame = Camera.CFrame:Lerp(desired, alpha) end
        end
    end))
end

-- ============================================================
-- ============================================================
-- ESP ENGINE
-- ============================================================
local function esp_isKnocked(plr)
    if not plr then return false end
    local ok, knocked = pcall(function()
        local playersFolder = workspace:FindFirstChild("Players")
        if not playersFolder then return false end
        local pFolder = playersFolder:FindFirstChild(plr.Name)
        if not pFolder then return false end
        local bodyEffects = pFolder:FindFirstChild("BodyEffects")
        if not bodyEffects then return false end
        local ko = bodyEffects:FindFirstChild("K.O") or bodyEffects:FindFirstChild("KO")
        if not ko then return false end
        if ko:IsA("BoolValue") then
            return ko.Value
        elseif ko:IsA("IntValue") or ko:IsA("NumberValue") then
            return ko.Value > 0
        elseif ko:IsA("StringValue") then
            local v = ko.Value
            return v ~= "" and v ~= "false" and v ~= "0"
        end
        return ko.Value == true
    end)
    return ok and knocked == true
end

local function InitESP()
    local function getArmorValueESP(char)
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

    local function make_text(parent)
        local lbl = Instance.new("TextLabel", parent)
        lbl.Size = UDim2.new(0, 260, 0, 14); lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.new(1,1,1); lbl.TextStrokeTransparency = 0
        lbl.TextStrokeColor3 = Color3.new(0,0,0)
        lbl.TextSize = Config.TextSize or 11; lbl.Font = Config.Font or Enum.Font.GothamBold
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.AnchorPoint = Vector2.new(0.5, 0); lbl.ZIndex = 3
        return lbl
    end

    local function new_screengui(name)
        local g = Instance.new("ScreenGui")
        g.Name = name; g.ResetOnSpawn = false; g.IgnoreGuiInset = true
        g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; g.Parent = CoreGui
        trackGui(g); return g
    end

    local function make_box_side(parent, name)
        local f = Instance.new("Frame", parent)
        f.Name = name; f.BorderSizePixel = 0
        f.BackgroundColor3 = Color3.fromRGB(255,255,255)
        f.Visible = false; f.ZIndex = 5
        return f
    end

    local function render(player)
        if not Alive then return end
        if not player or ESPCache[player] then return end
        ESPCache[player] = { Box = {}, Bars = {}, Text = {}, Gui = {}, Skeleton = {}, HeadCircle = nil, Parts = nil, LastChar = nil }

        local gui = new_screengui("ESP_"..player.Name)
        ESPCache[player].Gui.Main = gui

        local boxHolder = Instance.new("Frame", gui)
        boxHolder.Name = "BoxHolder"; boxHolder.BackgroundTransparency = 1
        boxHolder.BorderSizePixel = 0; boxHolder.Visible = false; boxHolder.ZIndex = 4
        ESPCache[player].Box.Holder = boxHolder
        ESPCache[player].Box.Top     = make_box_side(boxHolder, "Top")
        ESPCache[player].Box.Bottom  = make_box_side(boxHolder, "Bottom")
        ESPCache[player].Box.Left    = make_box_side(boxHolder, "Left")
        ESPCache[player].Box.Right   = make_box_side(boxHolder, "Right")
        ESPCache[player].Box.TopO    = make_box_side(boxHolder, "TopO")
        ESPCache[player].Box.BottomO = make_box_side(boxHolder, "BottomO")
        ESPCache[player].Box.LeftO   = make_box_side(boxHolder, "LeftO")
        ESPCache[player].Box.RightO  = make_box_side(boxHolder, "RightO")
        for _, side in ipairs({"TopO","BottomO","LeftO","RightO"}) do
            ESPCache[player].Box[side].BackgroundColor3 = Color3.new(0, 0, 0)
            ESPCache[player].Box[side].ZIndex = 4
        end
        -- 3D depth faces (back plane + 4 corner connectors)
        for _, dKey in ipairs({"D_Top","D_Bot","D_Left","D_Right","D_TL","D_TR","D_BL","D_BR"}) do
            local df = Instance.new("Frame", gui)
            df.Name = dKey; df.BorderSizePixel = 0
            df.BackgroundColor3 = Color3.fromRGB(255,255,255)
            df.BackgroundTransparency = 0.5
            df.AnchorPoint = Vector2.new(0, 0.5)
            df.Visible = false; df.ZIndex = 3
            ESPCache[player].Box[dKey] = df
        end
        for _, cKey in ipairs({
            "C_TRH","C_TRV","C_BLH","C_BLV","C_BRH","C_BRV",
            "C_TRH_O","C_TRV_O","C_BLH_O","C_BLV_O","C_BRH_O","C_BRV_O"
        }) do
            local cf = Instance.new("Frame", gui)
            cf.Name = cKey; cf.BorderSizePixel = 0
            cf.BackgroundColor3 = cKey:find("_O$") and Color3.new(0,0,0) or Color3.fromRGB(255,255,255)
            cf.BackgroundTransparency = 0
            cf.Visible = false; cf.ZIndex = cKey:find("_O$") and 4 or 5
            ESPCache[player].Box[cKey] = cf
        end

        local skelLines = {}
        for i = 1, 14 do
            local fr = Instance.new("Frame", gui)
            fr.Name = "Skel"..i; fr.BorderSizePixel = 0
            fr.AnchorPoint = Vector2.new(0.5, 0.5)
            fr.BackgroundColor3 = Color3.fromRGB(255,255,255)
            fr.Visible = false; fr.ZIndex = 6
            skelLines[i] = { kind = "frame", obj = fr }
        end
        ESPCache[player].Skeleton = skelLines

        local ring = Instance.new("Frame", gui)
        ring.Name = "HeadCircle"; ring.BackgroundTransparency = 1
        ring.BorderSizePixel = 0; ring.Visible = false; ring.ZIndex = 6
        local stroke = Instance.new("UIStroke", ring)
        stroke.Thickness = 1; stroke.Color = Color3.fromRGB(255,255,255)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        local corner = Instance.new("UICorner", ring)
        corner.CornerRadius = UDim.new(1, 0)
        ESPCache[player].HeadCircle = { kind = "frame", obj = ring, stroke = stroke }

        ESPCache[player].Text.Name   = make_text(gui)
        ESPCache[player].Text.Studs  = make_text(gui)
        ESPCache[player].Text.Tool   = make_text(gui)
        ESPCache[player].Text.Health = make_text(gui)
        ESPCache[player].Text.Armor  = make_text(gui)
        ESPCache[player].Text.Flags  = make_text(gui)

        local hOutline = Instance.new("Frame", gui)
        hOutline.Name = "HealthOutline"; hOutline.BackgroundColor3 = Color3.new(0,0,0)
        hOutline.BorderSizePixel = 0; hOutline.Visible = false; hOutline.ZIndex = 2
        local hFill = Instance.new("Frame", hOutline)
        hFill.Name = "Fill"; hFill.BorderSizePixel = 0
        local hGrad = Instance.new("UIGradient", hFill); hGrad.Rotation = 90
        ESPCache[player].Bars.Health = { Outline = hOutline, Frame = hFill, Gradient = hGrad, LastHealth = nil }

        local aOutline = Instance.new("Frame", gui)
        aOutline.Name = "ArmorOutline"; aOutline.BackgroundColor3 = Color3.new(0,0,0)
        aOutline.BorderSizePixel = 0; aOutline.Visible = false; aOutline.ZIndex = 2
        local aFill = Instance.new("Frame", aOutline)
        aFill.Name = "Fill"; aFill.BorderSizePixel = 0
        local aGrad = Instance.new("UIGradient", aFill); aGrad.Rotation = 90
        ESPCache[player].Bars.Armor = { Outline = aOutline, Frame = aFill, Gradient = aGrad, LastArmor = nil }
    end

    local function hide_skeleton(c)
        if not c or not c.Skeleton then return end
        for _, line in ipairs(c.Skeleton) do
            pcall(function() line.obj.Visible = false end)
        end
    end
    local function hide_head_circle(c)
        if not c or not c.HeadCircle then return end
        pcall(function() c.HeadCircle.obj.Visible = false end)
    end

    local function clear_esp(player)
        local c = ESPCache[player]; if not c then return end
        if c.Box then
            if c.Box.Holder then c.Box.Holder.Visible = false end
            -- direct hide of known box pieces (no ipairs + pcall)
            local b = c.Box
            if b.Top then b.Top.Visible=false end; if b.Bottom then b.Bottom.Visible=false end
            if b.Left then b.Left.Visible=false end; if b.Right then b.Right.Visible=false end
            if b.TopO then b.TopO.Visible=false end; if b.BottomO then b.BottomO.Visible=false end
            if b.LeftO then b.LeftO.Visible=false end; if b.RightO then b.RightO.Visible=false end
            if b.D_Top then b.D_Top.Visible=false end; if b.D_Bot then b.D_Bot.Visible=false end
            if b.D_Left then b.D_Left.Visible=false end; if b.D_Right then b.D_Right.Visible=false end
            if b.D_TL then b.D_TL.Visible=false end; if b.D_TR then b.D_TR.Visible=false end
            if b.D_BL then b.D_BL.Visible=false end; if b.D_BR then b.D_BR.Visible=false end
            if b.C_TRH then b.C_TRH.Visible=false end; if b.C_TRV then b.C_TRV.Visible=false end
            if b.C_BLH then b.C_BLH.Visible=false end; if b.C_BLV then b.C_BLV.Visible=false end
            if b.C_BRH then b.C_BRH.Visible=false end; if b.C_BRV then b.C_BRV.Visible=false end
            if b.C_TRH_O then b.C_TRH_O.Visible=false end; if b.C_TRV_O then b.C_TRV_O.Visible=false end
            if b.C_BLH_O then b.C_BLH_O.Visible=false end; if b.C_BLV_O then b.C_BLV_O.Visible=false end
            if b.C_BRH_O then b.C_BRH_O.Visible=false end; if b.C_BRV_O then b.C_BRV_O.Visible=false end
        end
        hide_skeleton(c); hide_head_circle(c)
        if c.Text then
            if c.Text.Name then c.Text.Name.Visible=false end
            if c.Text.Studs then c.Text.Studs.Visible=false end
            if c.Text.Tool then c.Text.Tool.Visible=false end
            if c.Text.Health then c.Text.Health.Visible=false end
            if c.Text.Armor then c.Text.Armor.Visible=false end
            if c.Text.Flags then c.Text.Flags.Visible=false end
        end
        if c.Bars then
            if c.Bars.Health then
                if c.Bars.Health.Frame then c.Bars.Health.Frame.Visible=false end
                if c.Bars.Health.Outline then c.Bars.Health.Outline.Visible=false end
            end
            if c.Bars.Armor then
                if c.Bars.Armor.Frame then c.Bars.Armor.Frame.Visible=false end
                if c.Bars.Armor.Outline then c.Bars.Armor.Outline.Visible=false end
            end
        end
    end

    destroy_esp = function(player)
        local c = ESPCache[player]; if not c then return end
        if c.Skeleton then
            for _, line in ipairs(c.Skeleton) do
                pcall(function() line.obj.Visible = false end)
            end
        end
        if c.HeadCircle then pcall(function() c.HeadCircle.obj.Visible = false end) end
        if c.Gui and c.Gui.Main then pcall(function() c.Gui.Main:Destroy() end) end
        ESPCache[player] = nil
    end

    -- Prebuilt sequences so we don't allocate ColorSequence every tick
    local _hpGreenSeq = ColorSequence.new(Color3.fromRGB(80, 220, 100))
    local _hpRedSeq   = ColorSequence.new(Color3.fromRGB(255, 40, 40))
    local _armorSeq   = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Config.Bars.Armor.Color1),
        ColorSequenceKeypoint.new(0.5, Config.Bars.Armor.Color2),
        ColorSequenceKeypoint.new(1,   Config.Bars.Armor.Color3),
    })
    local function updateBarGradientsLocal()
        for player, c in pairs(ESPCache) do
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if c.Bars then
                if c.Bars.Health and c.Bars.Health.Gradient then
                    local rawHp = hum and hum.Health or 0
                    local isGod = hum and ((rawHp > 200) or (rawHp ~= rawHp) or (rawHp == math.huge) or (rawHp == -math.huge))
                    c.Bars.Health.Gradient.Color = isGod and _hpRedSeq or _hpGreenSeq
                end
                if c.Bars.Armor and c.Bars.Armor.Gradient then
                    c.Bars.Armor.Gradient.Color = _armorSeq
                end
            end
        end
    end

    local function update(player)
        local c = ESPCache[player]; if not c then return end
        if player == LocalPlayer and not Config.ShowOnSelf then return clear_esp(player) end
        -- Hide ESP for whitelisted players (friends / ignored)
        if Whitelisted[player] then return clear_esp(player) end
        if not Config.Enabled then return clear_esp(player) end
        if player.Parent == nil then return clear_esp(player) end

        local boxOn, skelOn, headOn = Config.Box.Enable, Config.Skeleton.Enable, Config.HeadCircle.Enable
        local hpOn, arOn = Config.Bars.Health.Enable, Config.Bars.Armor.Enable
        local flagsOn = Config.Text.Flags and Config.Text.Flags.Enable
        local textOn = Config.Text.Name.Enable or Config.Text.Studs.Enable
            or Config.Text.Tool.Enable or Config.Text.Health.Enable or Config.Text.Armor.Enable
            or flagsOn
        if not (boxOn or textOn or hpOn or arOn or skelOn or headOn) then return clear_esp(player) end

        local char, lchar = player.Character, LocalPlayer.Character
        if not lchar then return clear_esp(player) end

        local _now = os.clock()
        -- Cache KO check ~8Hz (still reacts fast; cuts BodyEffects lookups)
        local knockedNow = c._knockedCached
        if not c._knockedAt or (_now - c._knockedAt) > 0.12 then
            c._knockedAt = _now
            knockedNow = false
            pcall(function() knockedNow = esp_isKnocked(player) end)
            c._knockedCached = knockedNow
        end
        if not char or not char.Parent then
            return clear_esp(player)
        end

        -- Part cache: every frame while knocked so the box follows the crawling body
        local refreshEvery = knockedNow and 0 or 0.25
        if c.LastChar ~= char or not c.Parts or not c._partsAt or (_now - c._partsAt) > refreshEvery then
            c.LastChar = char
            c._partsAt = _now
            local p = c.Parts or {}
            local function gp(n)
                local v = char:FindFirstChild(n)
                if v then return v end
                -- Deep search only for critical roots when knocked models nest parts
                if n == "HumanoidRootPart" or n == "Head" or n == "Torso" or n == "UpperTorso" then
                    return char:FindFirstChild(n, true)
                end
                return nil
            end
            p.HRP  = gp("HumanoidRootPart")
            p.Hum  = char:FindFirstChildWhichIsA("Humanoid") or char:FindFirstChildWhichIsA("Humanoid", true)
            p.Head = gp("Head")
            p.UT   = gp("UpperTorso") or gp("Torso")
            p.LT   = gp("LowerTorso")
            p.LUA  = gp("LeftUpperArm") or gp("Left Arm")
            p.RUA  = gp("RightUpperArm") or gp("Right Arm")
            p.LF   = gp("LeftFoot") or gp("Left Leg")
            p.RF   = gp("RightFoot") or gp("Right Leg")
            p["Head"] = p.Head
            p["HumanoidRootPart"] = p.HRP
            p["UpperTorso"] = gp("UpperTorso")
            p["LowerTorso"] = p.LT
            p["Torso"] = gp("Torso")
            p["LeftUpperArm"] = gp("LeftUpperArm"); p["LeftLowerArm"] = gp("LeftLowerArm"); p["LeftHand"] = gp("LeftHand")
            p["RightUpperArm"] = gp("RightUpperArm"); p["RightLowerArm"] = gp("RightLowerArm"); p["RightHand"] = gp("RightHand")
            p["LeftUpperLeg"] = gp("LeftUpperLeg"); p["LeftLowerLeg"] = gp("LeftLowerLeg"); p["LeftFoot"] = gp("LeftFoot")
            p["RightUpperLeg"] = gp("RightUpperLeg"); p["RightLowerLeg"] = gp("RightLowerLeg"); p["RightFoot"] = gp("RightFoot")
            p["Left Arm"] = gp("Left Arm"); p["Right Arm"] = gp("Right Arm")
            p["Left Leg"] = gp("Left Leg"); p["Right Leg"] = gp("Right Leg")
            c.Parts = p
        end
        local parts = c.Parts or {}
        c.Parts = parts
        -- Real HRP only (using Head as root glitched box/skeleton)
        local hrp = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp then
            parts.HRP = hrp
            parts["HumanoidRootPart"] = hrp
        end
        parts.Hum = hum
        if not hrp or not hrp.Parent then
            return clear_esp(player)
        end
        local myRoot = lchar:FindFirstChild("HumanoidRootPart")
        if not myRoot then return clear_esp(player) end
        local worldDist = (hrp.Position - myRoot.Position).Magnitude
        -- Distance cull skipped while knocked so crawl never drops ESP
        if not knockedNow and Config.MaxDistance and Config.MaxDistance > 0 and worldDist > Config.MaxDistance then
            return clear_esp(player)
        end

        if Config.KnockCheck and knockedNow then return clear_esp(player) end
        c._lastGoodAt = _now
        c._lastHrpPos = hrp.Position

        local _isTargetPlayer = TargetESP.Enabled and (
            (CurrentTarget and CurrentTarget == player) or
            (CR_State.ActiveTarget and CR_State.ActiveTarget == player)
        )

        -- Behind camera / invalid → hide (prevents ESP stuck on screen center)
        local hrpSP, hrpOnScreen = Camera:WorldToViewportPoint(hrp.Position)
        if hrpSP.Z <= 0 then
            return clear_esp(player)
        end

        local posOffset = Vector3.zero  -- no smoothing offset; all visuals use raw positions

        -- Bounds from body parts (parts refreshed every frame while knocked)
        local tlx, tly, brx, bry = math.huge, math.huge, -math.huge, -math.huge
        local found = false
        local keyParts = { parts.Head, parts.UT, parts.LT or hrp, parts.LUA, parts.RUA, parts.LF, parts.RF }
        for i = 1, #keyParts do
            local part = keyParts[i]
            if part and part.Parent and part:IsA("BasePart") then
                local cf, half = part.CFrame, part.Size * 0.5
                -- Shift corners by the smoothed-position offset
                local p1 = cf * Vector3.new(-half.X,  half.Y, -half.Z)
                local p2 = cf * Vector3.new( half.X, -half.Y,  half.Z)
                local sp1, on1 = Camera:WorldToViewportPoint(p1)
                local sp2, on2 = Camera:WorldToViewportPoint(p2)
                if on1 or sp1.Z > 0 then
                    found = true
                    if sp1.X < tlx then tlx = sp1.X end
                    if sp1.Y < tly then tly = sp1.Y end
                    if sp1.X > brx then brx = sp1.X end
                    if sp1.Y > bry then bry = sp1.Y end
                end
                if on2 or sp2.Z > 0 then
                    found = true
                    if sp2.X < tlx then tlx = sp2.X end
                    if sp2.Y < tly then tly = sp2.Y end
                    if sp2.X > brx then brx = sp2.X end
                    if sp2.Y > bry then bry = sp2.Y end
                end
            end
        end
        -- Knocked/ragdoll: fall back to root-centered box so ESP follows the body
        if not found or tlx == math.huge then
            local sp = Camera:WorldToViewportPoint(hrp.Position)
            if sp.Z <= 0 then
                return clear_esp(player)
            end
            local s = knockedNow and 34 or 28
            tlx, tly, brx, bry = sp.X - s, sp.Y - s * 1.6, sp.X + s, sp.Y + s * 0.4
            found = true
        end

        local boxPos  = Vector2.new(math.floor(tlx - 2), math.floor(tly - 2))
        local boxSize = Vector2.new(math.floor(brx - tlx + 4), math.floor(bry - tly + 4))
        local boxLeft, boxTop = boxPos.X, boxPos.Y
        local boxRight, boxBot = boxPos.X + boxSize.X, boxPos.Y + boxSize.Y
        local centerX = boxLeft + boxSize.X / 2

        if boxOn and c.Box and c.Box.Holder then
            local col = (_isTargetPlayer and TargetESP.Color) or Config.Box.Color or Color3.fromRGB(255,255,255)
            local t, o = 1, 1
            local style = Config.BoxStyle or "2D"
            -- Hide all first, redraw per style
            for _, k in ipairs({
                "Top","Bottom","Left","Right","TopO","BottomO","LeftO","RightO",
                "D_Top","D_Bot","D_Left","D_Right","D_TL","D_TR","D_BL","D_BR",
                "C_TRH","C_TRV","C_BLH","C_BLV","C_BRH","C_BRV",
                "C_TRH_O","C_TRV_O","C_BLH_O","C_BLV_O","C_BRH_O","C_BRV_O",
            }) do
                if c.Box[k] then c.Box[k].Visible = false end
            end
            c.Box.Holder.Visible = true

            if style == "Corner" then
                -- Corner box: proper L-shaped ticks at all 4 corners
                local cw = math.max(5, math.floor(boxSize.X * 0.22))  -- horizontal tick length
                local ch = math.max(5, math.floor(boxSize.Y * 0.22))  -- vertical tick length
                local bk = Color3.new(0,0,0)

                -- ── TOP-LEFT (uses existing boxHolder frames) ──
                c.Box.TopO.Visible=true; c.Box.TopO.BackgroundColor3=bk
                c.Box.TopO.Position=UDim2.fromOffset(boxLeft-o,boxTop-o); c.Box.TopO.Size=UDim2.fromOffset(cw+o*2,t+o*2)
                c.Box.LeftO.Visible=true; c.Box.LeftO.BackgroundColor3=bk
                c.Box.LeftO.Position=UDim2.fromOffset(boxLeft-o,boxTop-o); c.Box.LeftO.Size=UDim2.fromOffset(t+o*2,ch+o*2)
                c.Box.Top.Visible=true; c.Box.Top.BackgroundColor3=col
                c.Box.Top.Position=UDim2.fromOffset(boxLeft,boxTop); c.Box.Top.Size=UDim2.fromOffset(cw,t)
                c.Box.Left.Visible=true; c.Box.Left.BackgroundColor3=col
                c.Box.Left.Position=UDim2.fromOffset(boxLeft,boxTop); c.Box.Left.Size=UDim2.fromOffset(t,ch)

                -- ── TOP-RIGHT ──
                if c.Box.C_TRH_O then c.Box.C_TRH_O.Visible=true; c.Box.C_TRH_O.BackgroundColor3=bk
                    c.Box.C_TRH_O.Position=UDim2.fromOffset(boxRight-cw-o,boxTop-o); c.Box.C_TRH_O.Size=UDim2.fromOffset(cw+o*2,t+o*2) end
                if c.Box.C_TRV_O then c.Box.C_TRV_O.Visible=true; c.Box.C_TRV_O.BackgroundColor3=bk
                    c.Box.C_TRV_O.Position=UDim2.fromOffset(boxRight-t-o,boxTop-o); c.Box.C_TRV_O.Size=UDim2.fromOffset(t+o*2,ch+o*2) end
                if c.Box.C_TRH then c.Box.C_TRH.Visible=true; c.Box.C_TRH.BackgroundColor3=col
                    c.Box.C_TRH.Position=UDim2.fromOffset(boxRight-cw,boxTop); c.Box.C_TRH.Size=UDim2.fromOffset(cw,t) end
                if c.Box.C_TRV then c.Box.C_TRV.Visible=true; c.Box.C_TRV.BackgroundColor3=col
                    c.Box.C_TRV.Position=UDim2.fromOffset(boxRight-t,boxTop); c.Box.C_TRV.Size=UDim2.fromOffset(t,ch) end

                -- ── BOTTOM-LEFT ──
                if c.Box.C_BLH_O then c.Box.C_BLH_O.Visible=true; c.Box.C_BLH_O.BackgroundColor3=bk
                    c.Box.C_BLH_O.Position=UDim2.fromOffset(boxLeft-o,boxBot-t-o); c.Box.C_BLH_O.Size=UDim2.fromOffset(cw+o*2,t+o*2) end
                if c.Box.C_BLV_O then c.Box.C_BLV_O.Visible=true; c.Box.C_BLV_O.BackgroundColor3=bk
                    c.Box.C_BLV_O.Position=UDim2.fromOffset(boxLeft-o,boxBot-ch-o); c.Box.C_BLV_O.Size=UDim2.fromOffset(t+o*2,ch+o*2) end
                if c.Box.C_BLH then c.Box.C_BLH.Visible=true; c.Box.C_BLH.BackgroundColor3=col
                    c.Box.C_BLH.Position=UDim2.fromOffset(boxLeft,boxBot-t); c.Box.C_BLH.Size=UDim2.fromOffset(cw,t) end
                if c.Box.C_BLV then c.Box.C_BLV.Visible=true; c.Box.C_BLV.BackgroundColor3=col
                    c.Box.C_BLV.Position=UDim2.fromOffset(boxLeft,boxBot-ch); c.Box.C_BLV.Size=UDim2.fromOffset(t,ch) end

                -- ── BOTTOM-RIGHT ──
                c.Box.BottomO.Visible=true; c.Box.BottomO.BackgroundColor3=bk
                c.Box.BottomO.Position=UDim2.fromOffset(boxRight-cw-o,boxBot-t-o); c.Box.BottomO.Size=UDim2.fromOffset(cw+o*2,t+o*2)
                c.Box.RightO.Visible=true; c.Box.RightO.BackgroundColor3=bk
                c.Box.RightO.Position=UDim2.fromOffset(boxRight-t-o,boxBot-ch-o); c.Box.RightO.Size=UDim2.fromOffset(t+o*2,ch+o*2)
                c.Box.Bottom.Visible=true; c.Box.Bottom.BackgroundColor3=col
                c.Box.Bottom.Position=UDim2.fromOffset(boxRight-cw,boxBot-t); c.Box.Bottom.Size=UDim2.fromOffset(cw,t)
                c.Box.Right.Visible=true; c.Box.Right.BackgroundColor3=col
                c.Box.Right.Position=UDim2.fromOffset(boxRight-t,boxBot-ch); c.Box.Right.Size=UDim2.fromOffset(t,ch)
            elseif style == "3D" then
                -- Perspective-ish 3D wireframe: front box + back box offset + 4 connectors
                local depth = math.max(6, math.floor(math.min(boxSize.X, boxSize.Y) * 0.18))
                local ox, oy = depth, -depth  -- back face offset (up-right)
                local bTrans = 0.40
                local cTrans = 0.25
                local bk = Color3.new(0,0,0)
                -- Front face outlines
                c.Box.TopO.Visible=true; c.Box.TopO.BackgroundColor3=bk
                c.Box.TopO.Position=UDim2.fromOffset(boxLeft-o,boxTop-o); c.Box.TopO.Size=UDim2.fromOffset(boxSize.X+o*2,t+o*2)
                c.Box.BottomO.Visible=true; c.Box.BottomO.BackgroundColor3=bk
                c.Box.BottomO.Position=UDim2.fromOffset(boxLeft-o,boxBot-t-o); c.Box.BottomO.Size=UDim2.fromOffset(boxSize.X+o*2,t+o*2)
                c.Box.LeftO.Visible=true; c.Box.LeftO.BackgroundColor3=bk
                c.Box.LeftO.Position=UDim2.fromOffset(boxLeft-o,boxTop-o); c.Box.LeftO.Size=UDim2.fromOffset(t+o*2,boxSize.Y+o*2)
                c.Box.RightO.Visible=true; c.Box.RightO.BackgroundColor3=bk
                c.Box.RightO.Position=UDim2.fromOffset(boxRight-t-o,boxTop-o); c.Box.RightO.Size=UDim2.fromOffset(t+o*2,boxSize.Y+o*2)
                c.Box.Top.Visible=true; c.Box.Top.BackgroundColor3=col; c.Box.Top.BackgroundTransparency=0
                c.Box.Top.Position=UDim2.fromOffset(boxLeft,boxTop); c.Box.Top.Size=UDim2.fromOffset(boxSize.X,t)
                c.Box.Bottom.Visible=true; c.Box.Bottom.BackgroundColor3=col; c.Box.Bottom.BackgroundTransparency=0
                c.Box.Bottom.Position=UDim2.fromOffset(boxLeft,boxBot-t); c.Box.Bottom.Size=UDim2.fromOffset(boxSize.X,t)
                c.Box.Left.Visible=true; c.Box.Left.BackgroundColor3=col; c.Box.Left.BackgroundTransparency=0
                c.Box.Left.Position=UDim2.fromOffset(boxLeft,boxTop); c.Box.Left.Size=UDim2.fromOffset(t,boxSize.Y)
                c.Box.Right.Visible=true; c.Box.Right.BackgroundColor3=col; c.Box.Right.BackgroundTransparency=0
                c.Box.Right.Position=UDim2.fromOffset(boxRight-t,boxTop); c.Box.Right.Size=UDim2.fromOffset(t,boxSize.Y)
                -- Back face (offset)
                local bl, bt, br, bb = boxLeft+ox, boxTop+oy, boxRight+ox, boxBot+oy
                if c.Box.D_Top then
                    c.Box.D_Top.Visible=true; c.Box.D_Top.BackgroundColor3=col; c.Box.D_Top.BackgroundTransparency=bTrans
                    c.Box.D_Top.AnchorPoint=Vector2.new(0,0); c.Box.D_Top.Rotation=0
                    c.Box.D_Top.Position=UDim2.fromOffset(bl, bt); c.Box.D_Top.Size=UDim2.fromOffset(boxSize.X, t)
                end
                if c.Box.D_Bot then
                    c.Box.D_Bot.Visible=true; c.Box.D_Bot.BackgroundColor3=col; c.Box.D_Bot.BackgroundTransparency=bTrans
                    c.Box.D_Bot.AnchorPoint=Vector2.new(0,0); c.Box.D_Bot.Rotation=0
                    c.Box.D_Bot.Position=UDim2.fromOffset(bl, bb-t); c.Box.D_Bot.Size=UDim2.fromOffset(boxSize.X, t)
                end
                if c.Box.D_Left then
                    c.Box.D_Left.Visible=true; c.Box.D_Left.BackgroundColor3=col; c.Box.D_Left.BackgroundTransparency=bTrans
                    c.Box.D_Left.AnchorPoint=Vector2.new(0,0); c.Box.D_Left.Rotation=0
                    c.Box.D_Left.Position=UDim2.fromOffset(bl, bt); c.Box.D_Left.Size=UDim2.fromOffset(t, boxSize.Y)
                end
                if c.Box.D_Right then
                    c.Box.D_Right.Visible=true; c.Box.D_Right.BackgroundColor3=col; c.Box.D_Right.BackgroundTransparency=bTrans
                    c.Box.D_Right.AnchorPoint=Vector2.new(0,0); c.Box.D_Right.Rotation=0
                    c.Box.D_Right.Position=UDim2.fromOffset(br-t, bt); c.Box.D_Right.Size=UDim2.fromOffset(t, boxSize.Y)
                end
                -- Corner connectors (angle from front corner -> back corner)
                local function setConn(frame, fx, fy, bx, by)
                    if not frame then return end
                    local dx, dy = bx - fx, by - fy
                    local len = math.sqrt(dx*dx + dy*dy)
                    local ang = math.deg(math.atan2(dy, dx))
                    frame.Visible = true
                    frame.BackgroundColor3 = col
                    frame.BackgroundTransparency = cTrans
                    frame.AnchorPoint = Vector2.new(0, 0.5)
                    frame.Position = UDim2.fromOffset(fx, fy)
                    frame.Size = UDim2.fromOffset(math.max(1, math.floor(len + 0.5)), t)
                    frame.Rotation = ang
                end
                setConn(c.Box.D_TL, boxLeft,  boxTop, bl, bt)
                setConn(c.Box.D_TR, boxRight, boxTop, br, bt)
                setConn(c.Box.D_BL, boxLeft,  boxBot, bl, bb)
                setConn(c.Box.D_BR, boxRight, boxBot, br, bb)
            else
                -- Default full 2D box
                c.Box.TopO.Visible=true; c.Box.TopO.BackgroundColor3=Color3.new(0,0,0)
                c.Box.TopO.Position=UDim2.fromOffset(boxLeft-o,boxTop-o); c.Box.TopO.Size=UDim2.fromOffset(boxSize.X+o*2,t+o*2)
                c.Box.BottomO.Visible=true; c.Box.BottomO.BackgroundColor3=Color3.new(0,0,0)
                c.Box.BottomO.Position=UDim2.fromOffset(boxLeft-o,boxBot-t-o); c.Box.BottomO.Size=UDim2.fromOffset(boxSize.X+o*2,t+o*2)
                c.Box.LeftO.Visible=true; c.Box.LeftO.BackgroundColor3=Color3.new(0,0,0)
                c.Box.LeftO.Position=UDim2.fromOffset(boxLeft-o,boxTop-o); c.Box.LeftO.Size=UDim2.fromOffset(t+o*2,boxSize.Y+o*2)
                c.Box.RightO.Visible=true; c.Box.RightO.BackgroundColor3=Color3.new(0,0,0)
                c.Box.RightO.Position=UDim2.fromOffset(boxRight-t-o,boxTop-o); c.Box.RightO.Size=UDim2.fromOffset(t+o*2,boxSize.Y+o*2)
                c.Box.Top.Visible=true; c.Box.Top.BackgroundColor3=col
                c.Box.Top.Position=UDim2.fromOffset(boxLeft,boxTop); c.Box.Top.Size=UDim2.fromOffset(boxSize.X,t)
                c.Box.Bottom.Visible=true; c.Box.Bottom.BackgroundColor3=col
                c.Box.Bottom.Position=UDim2.fromOffset(boxLeft,boxBot-t); c.Box.Bottom.Size=UDim2.fromOffset(boxSize.X,t)
                c.Box.Left.Visible=true; c.Box.Left.BackgroundColor3=col
                c.Box.Left.Position=UDim2.fromOffset(boxLeft,boxTop); c.Box.Left.Size=UDim2.fromOffset(t,boxSize.Y)
                c.Box.Right.Visible=true; c.Box.Right.BackgroundColor3=col
                c.Box.Right.Position=UDim2.fromOffset(boxRight-t,boxTop); c.Box.Right.Size=UDim2.fromOffset(t,boxSize.Y)
            end
        elseif c.Box and c.Box.Holder then
            c.Box.Holder.Visible = false
            for _, k in ipairs({
                "Top","Bottom","Left","Right","TopO","BottomO","LeftO","RightO",
                "D_Top","D_Bot","D_Left","D_Right","D_TL","D_TR","D_BL","D_BR",
                "C_TRH","C_TRV","C_BLH","C_BLV","C_BRH","C_BRV",
                "C_TRH_O","C_TRV_O","C_BLH_O","C_BLV_O","C_BRH_O","C_BRV_O",
            }) do
                if c.Box[k] then c.Box[k].Visible = false end
            end
        end

        if skelOn and c.Skeleton then
            local pairs_ = (parts.UT and parts.UT.Name == "UpperTorso") and SKELETON_R15 or SKELETON_R6
            local skelCol = (_isTargetPlayer and TargetESP.Color) or Config.Skeleton.Color or Color3.fromRGB(255,255,255)
            for i, pair in ipairs(pairs_) do
                local line = c.Skeleton[i]
                local a = parts[pair[1]] or char:FindFirstChild(pair[1])
                local b = parts[pair[2]] or char:FindFirstChild(pair[2])
                if line and a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                    local sa, ona = Camera:WorldToViewportPoint(a.Position)
                    local sb, onb = Camera:WorldToViewportPoint(b.Position)
                    if ona and onb and sa.Z > 0 and sb.Z > 0 then
                        local dx, dy = sb.X - sa.X, sb.Y - sa.Y
                        local len = math.sqrt(dx*dx + dy*dy)
                        local ang = math.atan2(dy, dx)
                        line.obj.Visible = true
                        line.obj.BackgroundColor3 = skelCol
                        line.obj.Size = UDim2.fromOffset(math.max(len, 1), 1)
                        line.obj.Position = UDim2.fromOffset((sa.X + sb.X)/2, (sa.Y + sb.Y)/2)
                        line.obj.Rotation = math.deg(ang)
                    else
                        pcall(function() line.obj.Visible = false end)
                    end
                elseif line then
                    pcall(function() line.obj.Visible = false end)
                end
            end
            for i = #pairs_ + 1, #c.Skeleton do
                local line = c.Skeleton[i]
                if line then pcall(function() line.obj.Visible = false end) end
            end
        else
            hide_skeleton(c)
        end

        if headOn and c.HeadCircle then
            local head = parts.Head
            if head and head.Parent and head:IsA("BasePart") then
                local sp, on = Camera:WorldToViewportPoint(head.Position)
                if on and sp.Z > 0 then
                    local bottom = Camera:WorldToViewportPoint(head.Position - Vector3.new(0, head.Size.Y * 0.55, 0))
                    local radius = math.clamp(math.abs(sp.Y - bottom.Y), 3, 48)
                    local hCol = Config.HeadCircle.Color or Color3.fromRGB(255,255,255)
                    local d = radius * 2
                    c.HeadCircle.obj.Visible = true
                    c.HeadCircle.obj.Size = UDim2.fromOffset(d, d)
                    c.HeadCircle.obj.Position = UDim2.fromOffset(sp.X - radius, sp.Y - radius)
                    if c.HeadCircle.stroke then
                        c.HeadCircle.stroke.Color = hCol
                        c.HeadCircle.stroke.Thickness = 1
                    end
                else
                    hide_head_circle(c)
                end
            else
                hide_head_circle(c)
            end
        else
            hide_head_circle(c)
        end

        if hpOn then
            local rawHp = hum and hum.Health or 0
            local maxHp = (hum and hum.MaxHealth) or 100
            local isGod = (rawHp > 200) or (rawHp ~= rawHp) or (rawHp == math.huge) or (rawHp == -math.huge)
            local hp = isGod and 1 or math.clamp(rawHp / math.max(maxHp, 1), 0, 1)
            local prev = c.Bars.Health.LastHealth or hp
            local smooth = prev + (hp - prev) * 0.05
            c.Bars.Health.LastHealth = smooth
            local o, f = c.Bars.Health.Outline, c.Bars.Health.Frame
            local pos = Config.Bars.Health.Position
            o.Visible = true; o.BackgroundTransparency = 0.2; o.ZIndex = 2
            f.Visible = true; f.ZIndex = 3
            local barColor = isGod and Color3.fromRGB(255,40,40) or Color3.fromRGB(80,220,100)
            f.BackgroundColor3 = barColor
            if c.Bars.Health.Gradient then c.Bars.Health.Gradient.Color = isGod and _hpRedSeq or _hpGreenSeq end
            local ox, oy = 0, 0 -- bars locked to box (not draggable)
            if pos == "Left" then
                o.Position = UDim2.new(0, boxLeft - 7 + ox, 0, boxTop + oy); o.Size = UDim2.new(0, 5, 0, boxSize.Y + 2)
                f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1); f.Size = UDim2.new(0, 3, 0, smooth * boxSize.Y)
            elseif pos == "Right" then
                o.Position = UDim2.new(0, boxRight + 3 + ox, 0, boxTop + oy); o.Size = UDim2.new(0, 5, 0, boxSize.Y + 2)
                f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1); f.Size = UDim2.new(0, 3, 0, smooth * boxSize.Y)
            elseif pos == "Top" then
                o.Position = UDim2.new(0, boxLeft - 1 + ox, 0, boxTop - 7 + oy); o.Size = UDim2.new(0, boxSize.X + 2, 0, 5)
                f.Position = UDim2.new(0, 1, 0, 1); f.Size = UDim2.new(0, smooth * boxSize.X, 0, 3)
            elseif pos == "Bottom" then
                o.Position = UDim2.new(0, boxLeft - 1 + ox, 0, boxBot + 3 + oy); o.Size = UDim2.new(0, boxSize.X + 2, 0, 5)
                f.Position = UDim2.new(0, 1, 0, 1); f.Size = UDim2.new(0, smooth * boxSize.X, 0, 3)
            end
        else
            c.Bars.Health.Frame.Visible = false; c.Bars.Health.Outline.Visible = false
        end

        if arOn then
            local armorVal = getArmorValueESP(char)
            local armor = math.clamp(armorVal / 200, 0, 1)
            local prev = c.Bars.Armor.LastArmor or armor
            local smooth = prev + (armor - prev) * 0.05
            c.Bars.Armor.LastArmor = smooth
            local o, f = c.Bars.Armor.Outline, c.Bars.Armor.Frame
            local pos = Config.Bars.Health.Position
            o.Visible = true; o.BackgroundTransparency = 0.2; o.ZIndex = 2
            f.Visible = true; f.ZIndex = 3
            local ax, ay = 0, 0 -- bars locked to box (not draggable)
            if pos == "Left" then
                o.Position = UDim2.new(0, boxLeft - 14 + ax, 0, boxTop + ay); o.Size = UDim2.new(0, 5, 0, boxSize.Y + 2)
                f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1); f.Size = UDim2.new(0, 3, 0, smooth * boxSize.Y)
            elseif pos == "Right" then
                o.Position = UDim2.new(0, boxRight + 10 + ax, 0, boxTop + ay); o.Size = UDim2.new(0, 5, 0, boxSize.Y + 2)
                f.Position = UDim2.new(0, 1, 0, (1 - smooth) * boxSize.Y + 1); f.Size = UDim2.new(0, 3, 0, smooth * boxSize.Y)
            elseif pos == "Top" then
                o.Position = UDim2.new(0, boxLeft - 1 + ax, 0, boxTop - 14 + ay); o.Size = UDim2.new(0, boxSize.X + 2, 0, 5)
                f.Position = UDim2.new(0, 1, 0, 1); f.Size = UDim2.new(0, smooth * boxSize.X, 0, 3)
            elseif pos == "Bottom" then
                o.Position = UDim2.new(0, boxLeft - 1 + ax, 0, boxBot + 10 + ay); o.Size = UDim2.new(0, boxSize.X + 2, 0, 5)
                f.Position = UDim2.new(0, 1, 0, 1); f.Size = UDim2.new(0, smooth * boxSize.X, 0, 3)
            end
        else
            c.Bars.Armor.Frame.Visible = false; c.Bars.Armor.Outline.Visible = false
        end

        if textOn then
            local nL, sL, tL, hL, aL = c.Text.Name, c.Text.Studs, c.Text.Tool, c.Text.Health, c.Text.Armor
            local barPos = Config.Bars.Health.Position

            if Config.Text.Name.Enable then
                local ox = ((Config.Layout and Config.Layout.Name and Config.Layout.Name.X) or 0) * boxSize.X
                local oy = ((Config.Layout and Config.Layout.Name and Config.Layout.Name.Y) or 0) * boxSize.Y
                nL.Visible = true
                nL.TextColor3 = (_isTargetPlayer and TargetESP.Color) or Config.Text.Name.Color
                nL.TextXAlignment = Enum.TextXAlignment.Center
                nL.AnchorPoint = Vector2.new(0.5, 1)
                nL.TextSize = math.max(1, Config.TextSize)
                nL.Size = UDim2.fromOffset(260, math.max(1, Config.TextSize) + 3)
                local t = Config.Text.Name.Type
                if t == "Display" then nL.Text = player.DisplayName
                elseif t == "Username" then nL.Text = player.Name
                else nL.Text = player.DisplayName.." (@"..player.Name..")" end
                nL.Position = UDim2.fromOffset(centerX + ox, boxTop - 4 + oy)
            else nL.Visible = false end

            local barColW = 0
            if barPos == "Left" then
                if arOn and hpOn then barColW = 16
                elseif arOn or hpOn then barColW = 9 end
            end
            local leftEdge = boxLeft - barColW - 4

            if Config.Text.Armor.Enable then
                local arm = math.floor((tonumber(getArmorValueESP(char)) or 0) + 0.5)
                aL.Visible = true
                aL.TextColor3 = Config.Text.Armor.Color
                aL.Text = arm .. " armor"
                aL.TextXAlignment = Enum.TextXAlignment.Right
                aL.AnchorPoint = Vector2.new(1, 1)
                aL.Font = Config.Font or Enum.Font.GothamBold
                aL.TextSize = math.max(1, Config.TextSize or 11)
                aL.Size = UDim2.new(0, 120, 0, math.max(1, Config.TextSize or 11) + 2)
                local ox = ((Config.Layout and Config.Layout.ArmorText and Config.Layout.ArmorText.X) or 0) * boxSize.X
                local oy = ((Config.Layout and Config.Layout.ArmorText and Config.Layout.ArmorText.Y) or 0) * boxSize.Y
                aL.Position = UDim2.fromOffset(leftEdge + ox, boxTop - 1 + oy)
            else aL.Visible = false end

            if Config.Text.Health.Enable then
                local rawHp = hum and hum.Health or 0
                local isGod = (rawHp > 200) or (rawHp ~= rawHp) or (rawHp == math.huge) or (rawHp == -math.huge)
                hL.Visible = true
                hL.TextXAlignment = Enum.TextXAlignment.Right
                hL.AnchorPoint = Vector2.new(1, 0)
                hL.Font = Config.Font or Enum.Font.GothamBold
                hL.TextSize = math.max(1, Config.TextSize or 11)
                hL.Size = UDim2.new(0, 120, 0, math.max(1, Config.TextSize or 11) + 2)
                if isGod then
                    hL.Text = "god mode"
                    hL.TextColor3 = Color3.fromRGB(255, 60, 60)
                else
                    hL.Text = math.floor(rawHp + 0.5) .. " health"
                    hL.TextColor3 = Config.Text.Health.Color
                end
                local healthY = Config.Text.Armor.Enable and (boxTop + 1) or (boxTop - 1)
                local ox = ((Config.Layout and Config.Layout.HealthText and Config.Layout.HealthText.X) or 0) * boxSize.X
                local oy = ((Config.Layout and Config.Layout.HealthText and Config.Layout.HealthText.Y) or 0) * boxSize.Y
                hL.Position = UDim2.fromOffset(leftEdge + ox, healthY + oy)
            else hL.Visible = false end

            -- Flags (right side, opposite health/armor)
            -- Dead = bright red | Reloading = yellow | Healing = green (only while HP is rising)
            local fL = c.Text.Flags
            if fL then
                if flagsOn then
                    local flagText, flagCol = nil, nil
                    local be = nil
                    pcall(function()
                        local pf2 = workspace:FindFirstChild("Players")
                        local pm = pf2 and pf2:FindFirstChild(player.Name)
                        be = (pm and pm:FindFirstChild("BodyEffects")) or (char and char:FindFirstChild("BodyEffects"))
                    end)
                    local function beFlag(name)
                        if not be then return false end
                        local v = be:FindFirstChild(name)
                        if not v then return false end
                        local val = v.Value
                        if val == true then return true end
                        if type(val) == "number" and val > 0 then return true end
                        if type(val) == "string" then
                            local s = val:lower()
                            return s ~= "" and s ~= "false" and s ~= "0"
                        end
                        return false
                    end
                    -- Healing only while holding a food tool (not guns / other tools)
                    local holdingFood = false
                    local tool = char and char:FindFirstChildOfClass("Tool")
                    if tool then
                        local tn = tool.Name:lower()
                        if tn:find("donut", 1, true) or tn:find("pizza", 1, true)
                            or tn:find("taco", 1, true) or tn:find("hamburger", 1, true)
                            or tn:find("hotdog", 1, true) or tn:find("chicken", 1, true)
                            or tn:find("popcorn", 1, true) or tn:find("latte", 1, true)
                            or tn:find("cranberry", 1, true) or tn:find("cookie", 1, true)
                            or tn:find("meat", 1, true) or tn:find("milk", 1, true) then
                            holdingFood = true
                        end
                    end
                    if knockedNow or (hum and hum.Health <= 0) or beFlag("K.O") or beFlag("KO") or beFlag("Dead") then
                        flagText, flagCol = "Dead", Color3.fromRGB(255, 35, 35)
                    elseif beFlag("Reload") or beFlag("Reloading") then
                        flagText, flagCol = "Reloading", Color3.fromRGB(255, 220, 40)
                    elseif holdingFood then
                        flagText, flagCol = "Healing", Color3.fromRGB(70, 255, 110)
                    end
                    if flagText then
                        local lay = (Config.Layout and Config.Layout.Flags) or {X=0,Y=0}
                        fL.Visible = true
                        fL.Text = flagText
                        fL.TextColor3 = flagCol
                        fL.TextXAlignment = Enum.TextXAlignment.Left
                        fL.AnchorPoint = Vector2.new(0, 0)
                        fL.Font = Config.Font or Enum.Font.GothamBold
                        fL.TextSize = math.max(1, Config.TextSize or 11)
                        fL.Size = UDim2.new(0, 120, 0, math.max(1, Config.TextSize or 11) + 2)
                        local rightEdge = boxRight + 6
                        if barPos == "Right" then
                            if arOn and hpOn then rightEdge = boxRight + 18
                            elseif arOn or hpOn then rightEdge = boxRight + 11 end
                        end
                        local ox = (lay.X or 0) * boxSize.X
                        local oy = (lay.Y or 0) * boxSize.Y
                        fL.Position = UDim2.fromOffset(rightEdge + ox, boxTop - 1 + oy)
                    else
                        fL.Visible = false
                    end
                else
                    fL.Visible = false
                end
            end

            local yCursor = boxBot + 4
            if barPos == "Bottom" then
                if arOn then yCursor = boxBot + 17 elseif hpOn then yCursor = boxBot + 10 end
            end

            if Config.Text.Studs.Enable then
                sL.Visible = true
                sL.TextColor3 = (_isTargetPlayer and TargetESP.Color) or Config.Text.Studs.Color
                if Config.DistanceUnit == "Studs" then
                    sL.Text = string.format("[%.0f studs]", worldDist)
                else
                    sL.Text = string.format("[%.0fm]", worldDist * 0.28)
                end
                sL.TextXAlignment = Enum.TextXAlignment.Center
                sL.TextSize = math.max(1, Config.TextSize)
                sL.AnchorPoint = Vector2.new(0.5, 0)
                sL.Size = UDim2.new(0, 120, 0, math.max(1, Config.TextSize) + 3)
                local ox = ((Config.Layout and Config.Layout.Studs and Config.Layout.Studs.X) or 0) * boxSize.X
                local oy = ((Config.Layout and Config.Layout.Studs and Config.Layout.Studs.Y) or 0) * boxSize.Y
                sL.Position = UDim2.fromOffset(centerX + ox, yCursor + oy)
                yCursor = yCursor + 14
            else sL.Visible = false end

            if Config.Text.Tool.Enable then
                local layT = (Config.Layout and Config.Layout.Tool) or {X=0,Y=0}
                tL.Visible = true
                tL.TextColor3 = (_isTargetPlayer and TargetESP.Color) or Config.Text.Tool.Color
                local tool = char:FindFirstChildOfClass("Tool")
                tL.Text = tool and tool.Name or "none"
                tL.TextXAlignment = Enum.TextXAlignment.Center
                tL.TextSize = math.max(1, Config.TextSize)
                tL.AnchorPoint = Vector2.new(0.5, 0)
                tL.Size = UDim2.new(0, 160, 0, math.max(1, Config.TextSize) + 3)
                local ox = ((Config.Layout and Config.Layout.Tool and Config.Layout.Tool.X) or 0) * boxSize.X
                local oy = ((Config.Layout and Config.Layout.Tool and Config.Layout.Tool.Y) or 0) * boxSize.Y
                tL.Position = UDim2.fromOffset(centerX + ox, yCursor + oy)
            else tL.Visible = false end
        else
            c.Text.Name.Visible = false; c.Text.Studs.Visible = false; c.Text.Tool.Visible = false
            c.Text.Health.Visible = false; c.Text.Armor.Visible = false
            if c.Text.Flags then c.Text.Flags.Visible = false end
        end
    end

    local function hookEspRespawn(plr)
        if not plr or plr == LocalPlayer then return end
        trackConn(plr.CharacterAdded:Connect(function()
            -- Full redraw after respawn (knocked body is gone)
            pcall(function() destroy_esp(plr) end)
            task.defer(function()
                if not Alive or not Config.Enabled then return end
                if plr.Parent then pcall(render, plr) end
            end)
        end))
    end
    for _, p in ipairs(Players:GetPlayers()) do
        render(p)
        hookEspRespawn(p)
    end
    trackConn(Players.PlayerAdded:Connect(function(p)
        render(p)
        hookEspRespawn(p)
    end))
    trackConn(Players.PlayerRemoving:Connect(destroy_esp))

    local espWasEnabled = false
    local espFrame = 0
    local _toDestroy = {}
    -- Reuse player list buffer to avoid per-frame allocations
    local _espPlayers = {}

    -- Use RenderStepped for per-frame ESP so boxes never lag behind fast-moving players
    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive then return end
        if not Config.Enabled then
            if espWasEnabled then
                for p in pairs(ESPCache) do clear_esp(p) end
                espWasEnabled = false
            end
            return
        end
        espWasEnabled = true
        espFrame = espFrame + 1
        local doGrad  = espFrame % 12 == 0
        local doClean = espFrame % 90 == 0
        if doGrad then updateBarGradientsLocal() end

        local n = 0
        for p in pairs(ESPCache) do
            n = n + 1
            _espPlayers[n] = p
        end
        for i = 1, n do
            local p = _espPlayers[i]
            _espPlayers[i] = nil
            if p.Parent == nil then
                if doClean then _toDestroy[#_toDestroy + 1] = p end
            else
                -- update() is already pcall-safe internally for most paths
                local ok = pcall(update, p)
                if not ok then
                    pcall(clear_esp, p)
                end
            end
        end

        if doClean and #_toDestroy > 0 then
            for i = 1, #_toDestroy do destroy_esp(_toDestroy[i]) end
            table.clear(_toDestroy)
        end
    end))

    -- Refresh ESP after whitelist/blacklist changes so visuals never desync
    forceESPreFresh = function(specificPlayer)
        if specificPlayer then
            pcall(function()
                if Whitelisted[specificPlayer] then
                    clear_esp(specificPlayer)
                else
                    update(specificPlayer)
                end
            end)
            return
        end
        for p in pairs(ESPCache) do
            pcall(function()
                if Whitelisted[p] then
                    clear_esp(p)
                else
                    update(p)
                end
            end)
        end
        -- Ensure non-cached non-whitelisted players get ESP when enabled
        if Config.Enabled then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and not Whitelisted[p] and not ESPCache[p] then
                    pcall(render, p)
                end
            end
        end
    end
end
InitESP()

-- ============================================================
-- MOVEMENT
-- ============================================================
do
    local wsSignalConn    = nil
    local jpSignalConn    = nil
    local jpUseSignalConn = nil

    local function hookWalkSpeedSignal(hum)
        if wsSignalConn then pcall(function() wsSignalConn:Disconnect() end); wsSignalConn = nil end
        if not hum then return end
        wsSignalConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if WalkSpeed.Enabled and hum.WalkSpeed ~= WalkSpeed.Value then
                hum.WalkSpeed = WalkSpeed.Value
            end
        end)
    end

    local function hookJumpPowerSignal(hum)
        if jpSignalConn    then pcall(function() jpSignalConn:Disconnect()    end); jpSignalConn    = nil end
        if jpUseSignalConn then pcall(function() jpUseSignalConn:Disconnect() end); jpUseSignalConn = nil end
        if not hum then return end

        jpSignalConn = hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
            if JumpPower.Enabled and hum.JumpPower ~= JumpPower.Value then
                hum.JumpPower = JumpPower.Value
            end
        end)

        jpUseSignalConn = hum:GetPropertyChangedSignal("UseJumpPower"):Connect(function()
            if JumpPower.Enabled and not hum.UseJumpPower then
                hum.UseJumpPower = true
                hum.JumpPower = JumpPower.Value
            end
        end)
    end

    local function setWalkSpeedState(state)
        local prev = WalkSpeed.Enabled
        WalkSpeed.Enabled = state and true or false
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if WalkSpeed.Enabled then
            if hum then
                hookWalkSpeedSignal(hum)
                hum.WalkSpeed = WalkSpeed.Value
            end
        elseif prev and hum then
            if wsSignalConn then pcall(function() wsSignalConn:Disconnect() end); wsSignalConn = nil end
            hum.WalkSpeed = WalkSpeed.Default
        end
    end

    local function setJumpPowerState(state)
        local prev = JumpPower.Enabled
        JumpPower.Enabled = state and true or false
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if JumpPower.Enabled then
            if hum then
                hookJumpPowerSignal(hum)
                if not hum.UseJumpPower then hum.UseJumpPower = true end
                hum.JumpPower = JumpPower.Value
            end
        elseif prev and hum then
            if jpSignalConn    then pcall(function() jpSignalConn:Disconnect()    end); jpSignalConn    = nil end
            if jpUseSignalConn then pcall(function() jpUseSignalConn:Disconnect() end); jpUseSignalConn = nil end
            hum.UseJumpPower = true
            hum.JumpPower = JumpPower.Default
        end
    end

    local function enforceMovement()
        if not Alive then return end
        if not WalkSpeed.Enabled and not JumpPower.Enabled then return end
        local char = LocalPlayer.Character; if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        if WalkSpeed.Enabled then
            if not wsSignalConn then hookWalkSpeedSignal(hum) end
            if hum.WalkSpeed ~= WalkSpeed.Value then hum.WalkSpeed = WalkSpeed.Value end
        end
        if JumpPower.Enabled then
            if not jpSignalConn then hookJumpPowerSignal(hum) end
            pcall(function()
                if not hum.UseJumpPower then hum.UseJumpPower = true end
                if hum.JumpPower ~= JumpPower.Value then hum.JumpPower = JumpPower.Value end
                -- R15 / hybrid maps often key off JumpHeight; keep both in sync
                local jh = JumpPower.Value / 50 * 7.2
                if hum.JumpHeight ~= nil and math.abs((hum.JumpHeight or 0) - jh) > 0.05 then
                    hum.JumpHeight = jh
                end
            end)
        end
    end

    -- Single Heartbeat connection only when needed
    trackConn(RunService.Heartbeat:Connect(enforceMovement))

    trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if not hum then return end
        -- Drop stale hooks that may still reference the old humanoid
        if wsSignalConn    then pcall(function() wsSignalConn:Disconnect()    end); wsSignalConn    = nil end
        if jpSignalConn    then pcall(function() jpSignalConn:Disconnect()    end); jpSignalConn    = nil end
        if jpUseSignalConn then pcall(function() jpUseSignalConn:Disconnect() end); jpUseSignalConn = nil end
        if WalkSpeed.Enabled then hookWalkSpeedSignal(hum) end
        if JumpPower.Enabled then hookJumpPowerSignal(hum) end
    end))

    -- Hook the current humanoid if we already have a character
    if LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hookWalkSpeedSignal(hum)
            hookJumpPowerSignal(hum)
        end
    end

    local wsMasterOn = true
    local wsToggle
    wsToggle = MovementSection:Toggle({
        Name = "WalkSpeed", Flag = "ws_enabled", Default = false,
        Callback = function(state) wsMasterOn = state and true or false; setWalkSpeedState(state) end,
    })
    wsToggle:Keybind({
        Flag = "ws_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not wsMasterOn then return end
            setWalkSpeedState(v)
            if wsToggle and type(wsToggle.SetValue) == "function" then
                pcall(function() wsToggle:SetValue(v) end)
            end
        end,
    })
    MovementSection:Slider({
        Name="Speed", Flag="ws_value", Min=16, Max=500, Default=16, Decimals=1,
        Callback = function(v)
            WalkSpeed.Value = v
            if WalkSpeed.Enabled then
                local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = v end
            end
        end
    })

    local jpMasterOn = true
    local jpToggle
    jpToggle = MovementSection:Toggle({
        Name = "JumpPower", Flag = "jp_enabled", Default = false,
        Callback = function(state) jpMasterOn = state and true or false; setJumpPowerState(state) end,
    })
    jpToggle:Keybind({
        Flag = "jp_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not jpMasterOn then return end
            setJumpPowerState(v)
            if jpToggle and type(jpToggle.SetValue) == "function" then
                pcall(function() jpToggle:SetValue(v) end)
            end
        end,
    })
    MovementSection:Slider({
        Name="Power", Flag="jp_value", Min=50, Max=500, Default=50, Decimals=1,
        Callback = function(v)
            JumpPower.Value = v
            if JumpPower.Enabled then
                local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then
                    if not hum.UseJumpPower then hum.UseJumpPower = true end
                    hum.JumpPower = v
                end
            end
        end
    })
end

-- ============================================================
-- GUN NOCLIP (CanCollide noclip + tool-swap spam)
-- ============================================================
do
    local gnNoclipConn  = nil
    local gnOrigCanCollide = {}
    local gnLoopRunning = false
    local gnToolIdx     = 1

    -- Defensive: guarantee Tools exists even if the state-table edit was skipped
    if type(GunNoclip.Tools) ~= "table" or #GunNoclip.Tools == 0 then
        GunNoclip.Tools = { "[Double-Barrel SG]", "[TacticalShotgun]" }
    end
    if type(GunNoclip.Delay) ~= "number" then
        GunNoclip.Delay = 0
    end

    -- ── CanCollide noclip ──
    local function gn_applyNoclip(char)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if gnOrigCanCollide[part] == nil then
                    gnOrigCanCollide[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end
    end

    local function gn_restoreNoclip()
        for part, orig in pairs(gnOrigCanCollide) do
            if part and part.Parent then
                pcall(function() part.CanCollide = orig end)
            end
        end
        gnOrigCanCollide = {}
    end

    -- ── Tool-swap spam ──
    -- Only looks in Backpack. The alternation guarantees we're always equipping
    -- the tool that is NOT currently held, so every tick is a real swap event.
    local function gn_equipByName(name)
        local char = LocalPlayer.Character
        if not char then return false end
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if not bp then return false end

        local tool = bp:FindFirstChild(name)
        if not tool or not tool:IsA("Tool") then return false end

        pcall(function() hum:EquipTool(tool) end)
        return true
    end

    local function gn_startLoop()
        if gnLoopRunning then return end
        gnLoopRunning = true
        task.spawn(function()
            while Alive and GunNoclip.Enabled do
                pcall(function()
                    local char = LocalPlayer.Character
                    if char then
                        gn_applyNoclip(char)
                        local tools = GunNoclip.Tools
                        if tools and #tools > 0 then
                            local name = tools[gnToolIdx]
                            gn_equipByName(name)
                            gnToolIdx = (gnToolIdx % #tools) + 1
                        end
                    end
                end)
                local d = GunNoclip.Delay or 0
                if d > 0 then task.wait(d) else task.wait() end
            end
            gnLoopRunning = false
        end)
    end

    gn_setEnabled = function(state)
        GunNoclip.Enabled = state and true or false
        GunNoclip.Active  = GunNoclip.Enabled
        if GunNoclip.Enabled then
            local char = LocalPlayer.Character
            if char then gn_applyNoclip(char) end
            if not gnNoclipConn then
                gnNoclipConn = trackConn(RunService.Stepped:Connect(function()
                    if not Alive or not GunNoclip.Enabled then return end
                    local c = LocalPlayer.Character
                    if c then gn_applyNoclip(c) end
                end))
            end
            gn_startLoop()
        else
            gn_restoreNoclip()
        end
    end

    trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.1)
        if GunNoclip.Enabled and Alive then
            gnOrigCanCollide = {}
            gn_applyNoclip(char)
        end
    end))
end


-- ============================================================
-- KNIFE JUMP & NO JUMP CD
-- ============================================================
do
    local function kj_findKnife()
        local char = LocalPlayer.Character
        if not char then return nil end
        local bp = LocalPlayer:FindFirstChild("Backpack")

        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and t.Name:lower():find(KnifeJump.KnifeName:lower(), 1, true) then
                    return t
                end
            end
        end
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and t.Name:lower():find(KnifeJump.KnifeName:lower(), 1, true) then
                return t
            end
        end
    end

    local function kj_doJumpBoost()
        if not KnifeJump.Enabled or KnifeJump.Busy then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        local knife = kj_findKnife()
        if not knife then return end

        local prev = char:FindFirstChildOfClass("Tool")
        if prev == knife then return end

        KnifeJump.Busy = true
        hum.JumpPower = KnifeJump.BoostJP
        if prev then prev.Parent = LocalPlayer.Backpack end
        knife.Parent = char

        task.spawn(function()
            RunService.Heartbeat:Wait()
            if not Alive then return end
            if knife.Parent == char then knife.Parent = LocalPlayer.Backpack end
            if prev and prev.Parent == LocalPlayer.Backpack then prev.Parent = char end
            KnifeJump.Busy = false
        end)
    end

    trackConn(UserInputService.InputBegan:Connect(function(input, gpe)
        if not Alive then return end
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
            kj_doJumpBoost()
        end
    end))

    local function kj_bindJumping(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            trackConn(hum.Jumping:Connect(function()
                if not Alive then return end
                if not KnifeJump.Busy then kj_doJumpBoost() end
            end))
        end
    end
    trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then kj_bindJumping(char) end
    end))
    if LocalPlayer.Character then kj_bindJumping(LocalPlayer.Character) end

    MiscellaneousSection:Toggle({
        Name = "Knife Jump", Flag = "misc_knifejump", Default = false,
        Callback = function(state)
            KnifeJump.Enabled = state and true or false
            KnifeJump.Busy = false
        end,
    })
end

do
    local function njcd_enforce()
        if not Alive then return end
        if not NoJumpCD.Enabled then return end
        -- JumpPower master takes priority when enabled
        if JumpPower.Enabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end

        if not hum.UseJumpPower then hum.UseJumpPower = true end

        local holding = char:FindFirstChild(NoJumpCD.ToolName) ~= nil
        local target  = holding and NoJumpCD.JpKnife or NoJumpCD.JpDefault
        if hum.JumpPower ~= target then hum.JumpPower = target end
    end

    local function njcd_start()
        if #NoJumpCD.Conns > 0 then return end

        table.insert(NoJumpCD.Conns, RunService.Heartbeat:Connect(njcd_enforce))
        table.insert(NoJumpCD.Conns, RunService.Stepped:Connect(njcd_enforce))

        pcall(function()
            RunService:BindToRenderStep(
                NoJumpCD.StepName,
                Enum.RenderPriority.Camera.Value + 1,
                njcd_enforce
            )
        end)
    end

    local function njcd_stop()
        pcall(function() RunService:UnbindFromRenderStep(NoJumpCD.StepName) end)
        for _, c in ipairs(NoJumpCD.Conns) do
            pcall(function() c:Disconnect() end)
        end
        NoJumpCD.Conns = {}

        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                if not hum.UseJumpPower then hum.UseJumpPower = true end
                hum.JumpPower = NoJumpCD.JpDefault
            end)
        end
    end

    MiscellaneousSection:Toggle({
        Name = "No Jump CD", Flag = "misc_nojumpcd", Default = false,
        Callback = function(state)
            NoJumpCD.Enabled = state and true or false
            if NoJumpCD.Enabled then njcd_start() else njcd_stop() end
        end,
    })
end

-- ============================================================
-- INFINITE AMMO
-- ============================================================
do
    local RELOAD_TOOLS = {
        "[Double-Barrel SG]",
        "[Revolver]",
        "[TacticalShotgun]",
    }

    local function getMainEvent()
        local RS = game:GetService("ReplicatedStorage")
        local mainRemotes = RS:FindFirstChild("MainRemotes")
        return mainRemotes and mainRemotes:FindFirstChild("MainRemoteEvent")
    end

    local function getGunHandler()
        local RS = game:GetService("ReplicatedStorage")
        local modules = RS:FindFirstChild("Modules")
        if not modules then return nil end
        local mod = modules:FindFirstChild("GunHandler")
        if not mod then return nil end
        local ok, handler = pcall(require, mod)
        if ok then return handler end
        return nil
    end

    local function installWrapper()
        if InfiniteAmmo.WrapperInstalled then return end
        local GunHandler = getGunHandler()
        if not GunHandler or type(GunHandler.getCanShoot) ~= "function" then return end
        InfiniteAmmo.OriginalCanShoot = GunHandler.getCanShoot
        GunHandler.getCanShoot = function(...)
            if InfiniteAmmo.Enabled then return true end
            return InfiniteAmmo.OriginalCanShoot(...)
        end
        InfiniteAmmo.WrapperInstalled = true
    end

    local function uninstallWrapper()
        if not InfiniteAmmo.WrapperInstalled then return end
        local GunHandler = getGunHandler()
        if GunHandler and InfiniteAmmo.OriginalCanShoot then
            pcall(function()
                GunHandler.getCanShoot = InfiniteAmmo.OriginalCanShoot
            end)
        end
        InfiniteAmmo.WrapperInstalled = false
        InfiniteAmmo.OriginalCanShoot   = nil
    end
    InfiniteAmmo.UninstallWrapper = uninstallWrapper

    local function startInfiniteAmmo()
        if InfiniteAmmo.Enabled then return end
        InfiniteAmmo.Enabled = true
        pcall(installWrapper)

        if not InfiniteAmmo.ReloadRunning then
            InfiniteAmmo.ReloadRunning = true
            task.spawn(function()
                while Alive and InfiniteAmmo.Enabled do
                    local char = LocalPlayer.Character
                    local backpack = LocalPlayer:FindFirstChild("Backpack")
                    local ev = getMainEvent()
                    if ev then
                        for _, name in ipairs(RELOAD_TOOLS) do
                            if not InfiniteAmmo.Enabled then break end
                            local tool = (backpack and backpack:FindFirstChild(name))
                                      or (char and char:FindFirstChild(name))
                            if tool then
                                pcall(function() ev:FireServer("Reload", tool) end)
                            end
                        end
                    end
                    task.wait(0.05)
                end
                InfiniteAmmo.ReloadRunning = false
            end)
        end
    end

    function stopInfiniteAmmo()
        if not InfiniteAmmo then return end
        InfiniteAmmo.Enabled = false

        task.spawn(function()
            local char = LocalPlayer.Character
            if char then
                local be = char:FindFirstChild("BodyEffects")
                if be then
                    local reload = be:FindFirstChild("Reload")
                    if reload and reload.Value == true then
                        reload.Value = false
                    end
                end
            end
        end)
    end

    trackConn(RunService.Heartbeat:Connect(function()
        if not Alive or not InfiniteAmmo.Enabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        local be = char:FindFirstChild("BodyEffects")
        if be then
            local reload = be:FindFirstChild("Reload")
            if reload and reload.Value == true then
                reload.Value = false
            end
        end
        local tool = char:FindFirstChildWhichIsA("Tool")
        if tool and not tool.Enabled then
            tool.Enabled = true
        end
    end))

    MiscellaneousSection:Toggle({
        Name = "Infinite Ammo", Flag = "misc_infiniteammo", Default = false,
        Callback = function(state)
            if state then startInfiniteAmmo() else stopInfiniteAmmo() end
        end,
    })
end

-- ============================================================
-- HEADLESS / KORBLOX
-- ============================================================
do
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

    function setHeadlessState(state)
        Headless.Enabled = state and true or false
        local char = LocalPlayer.Character
        if Headless.Enabled then applyHeadlessToCharacter(char) else removeHeadlessFromCharacter(char) end
    end

    trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
        if Headless.Enabled then task.wait(0.25); if Alive then applyHeadlessToCharacter(char) end end
    end))

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

    function setKorbloxState(state)
        Korblox.Enabled = state and true or false
        local char = LocalPlayer.Character
        if char then
            if Korblox.Enabled then applyKorbloxToCharacter(char) else removeKorbloxFromCharacter(char) end
        end
    end

    task.spawn(function()
        while Alive and task.wait(0.5) do
            if Korblox.Enabled then
                local char = LocalPlayer.Character
                if char then
                    pcall(applyKorbloxToCharacter, char)
                end
            end
        end
    end)

    trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if not Alive then return end
        if Korblox.Enabled then applyKorbloxToCharacter(char) end
    end))

    MiscellaneousSection:Toggle({ Name="Headless", Flag="misc_headless", Default=false, Callback=function(state) setHeadlessState(state) end })
    MiscellaneousSection:Toggle({ Name="Korblox",  Flag="misc_korblox",  Default=false, Callback=function(state) setKorbloxState(state)  end })
end


-- ============================================================
-- MISC (RIGHT) — Auto Door + Hover Buy
-- ============================================================
do
    -- ── Auto Door ──
    local AutoDoor = { Enabled = false, Range = 10 }
    local AD_PATHS = {
        'workspace.MAP.Indestructible.Military:GetChildren()[26].Model.Door:GetChildren()[11].ClickDetector',
        'workspace.MAP.Indestructible.Military:GetChildren()[4].Model.Door:GetChildren()[23].ClickDetector',
        'workspace.MAP.Indestructible.MilitaryDestruction.Model.Model.Door:GetChildren()[12].ClickDetector',
        'workspace.MAP.Indestructible.MilitaryDestruction:GetChildren()[3].Model.Door:GetChildren()[13].ClickDetector',
        'workspace.MAP.Map.Apartment:GetChildren()[33].Door:GetChildren()[7].ClickDetector',
        'workspace.MAP.Map.Apartment.Door:GetChildren()[16].ClickDetector',
        'workspace.MAP.Map.Apartment:GetChildren()[41].Door:GetChildren()[11].ClickDetector',
        'workspace.MAP.Map.Apartment:GetChildren()[49].Door:GetChildren()[8].ClickDetector',
        'workspace.MAP.Map.Apartment:GetChildren()[32].Door:GetChildren()[15].ClickDetector',
        'workspace.MAP.Indestructible:GetChildren()[3]:GetChildren()[2]:GetChildren()[20]:GetChildren()[19].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[10].Perm.Door:GetChildren()[22].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[11].Perm:GetChildren()[6]:GetChildren()[20].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[12].Perm.Door.Part.ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[10].Perm:GetChildren()[6]:GetChildren()[15].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[12].Perm:GetChildren()[6]:GetChildren()[7].ClickDetector',
        'workspace.MAP.Map["Ubi\'s Resturant"].Door:GetChildren()[20].ClickDetector',
        'workspace.MAP.Map.WarehouseExpansion.Door:GetChildren()[24].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[4].Perm:GetChildren()[6]:GetChildren()[10].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[4].Perm.Door:GetChildren()[7].ClickDetector',
        'workspace.MAP.Map.AbandonedBuilding_Addition.Abandoned_House:GetChildren()[8].Part.ClickDetector',
        'workspace.MAP.Map.AbandonedBuilding_Addition.Abandoned_House.Door:GetChildren()[27].ClickDetector',
        'workspace.MAP.Map["Game-Houses"].Apartment.Perm.Door:GetChildren()[21].ClickDetector',
        'workspace.MAP.Map["Game-Houses"].Apartment.Perm:GetChildren()[6]:GetChildren()[14].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[15].Perm.Door:GetChildren()[9].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[15].Perm:GetChildren()[6]:GetChildren()[7].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[14].Perm.Door:GetChildren()[19].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[14].Perm:GetChildren()[6]:GetChildren()[21].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[6].Perm.Door:GetChildren()[13].ClickDetector',
        'workspace.MAP.Map["Game-Houses"]:GetChildren()[6].Perm:GetChildren()[6]:GetChildren()[26].ClickDetector',
    }

    local function ad_resolve(expr)
        local node = workspace
        local i, n = 1, #expr
        while i <= n and node do
            local ch = expr:sub(i, i)
            if ch == "." then
                local j = i + 1
                while j <= n and not expr:sub(j, j):match("[%.:%[]") do j = j + 1 end
                node = node:FindFirstChild(expr:sub(i + 1, j - 1))
                i = j
            elseif ch == "[" then
                local close = expr:find("]", i, true)
                if not close then return nil end
                local inner = expr:sub(i + 1, close - 1)
                local quoted = inner:match('^"(.*)"$') or inner:match("^'(.*)'$")
                if quoted then node = node:FindFirstChild(quoted)
                else
                    local idx = tonumber(inner)
                    node = idx and node:GetChildren()[idx] or nil
                end
                i = close + 1
            elseif ch == ":" then
                local close = expr:find("]", i, true)
                if not close then return nil end
                local idx = expr:sub(i, close):match("%[(%d+)%]")
                node = (idx and node) and node:GetChildren()[tonumber(idx)] or nil
                i = close + 1
            else i = i + 1 end
        end
        return node
    end

    local ad_tracked, ad_seen = {}, {}
    local function ad_findCD(obj)
        if not obj then return nil end
        if obj:IsA("ClickDetector") then return obj end
        local cd = obj:FindFirstChildOfClass("ClickDetector")
            or obj:FindFirstChild("ClickDetector")
            or obj:FindFirstChild("Clickdetector")
        if cd then return cd end
        return obj:FindFirstChildWhichIsA("ClickDetector", true)
    end
    local function ad_rebuild()
        ad_tracked, ad_seen = {}, {}
        for _, expr in ipairs(AD_PATHS) do
            local obj = ad_resolve(expr)
            local cd = ad_findCD(obj)
            -- If path ended on parent (ClickDetector missing), try parent of last resolved
            if not cd and obj and obj.Parent then
                cd = ad_findCD(obj.Parent)
            end
            if cd and not ad_seen[cd] then
                ad_seen[cd] = true
                table.insert(ad_tracked, {cd = cd})
            end
        end
    end
    ad_rebuild()
    -- Refresh paths periodically (map streaming)
    task.spawn(function()
        while Alive do
            task.wait(3)
            if AutoDoor.Enabled then pcall(ad_rebuild) end
        end
    end)

    -- Only real Lock instances (NOT "Block" / parts that merely contain "lock")
    local function ad_isLock(cd)
        local p = cd and cd.Parent
        local depth = 0
        while p and depth < 6 do
            local n = tostring(p.Name or "")
            if n == "Lock" or n == "lock" or n == "LOCKED" then
                return true
            end
            p = p.Parent
            depth = depth + 1
        end
        return false
    end

    local function ad_fire(cd)
        if not cd or not cd.Parent then return end
        if ad_isLock(cd) then return end
        pcall(function() cd.MaxActivationDistance = 64 end)
        pcall(function()
            if fireclickdetector then
                fireclickdetector(cd)
                fireclickdetector(cd, 0)
                fireclickdetector(cd, 10)
            end
        end)
        pcall(function()
            if firesignal then firesignal(cd.MouseClick) end
        end)
        pcall(function()
            if getconnections then
                for _, conn in ipairs(getconnections(cd.MouseClick)) do
                    pcall(function()
                        if conn.Fire then conn:Fire()
                        elseif conn.Function then conn.Function()
                        end
                    end)
                end
            end
        end)
    end

    -- Part attached to the ClickDetector (used for position)
    local function ad_part(cd)
        if not cd then return nil end
        local parent = cd.Parent
        if not parent then return nil end
        if parent:IsA("BasePart") then return parent end
        local p = parent:FindFirstChildWhichIsA("BasePart", true)
        return p
    end

    local function ad_pos(cd)
        local part = ad_part(cd)
        if part then return part.Position end
        local parent = cd and cd.Parent
        if not parent then return nil end
        local ok, pivot = pcall(function() return parent:GetPivot().Position end)
        if ok then return pivot end
        return nil
    end

    -- Closed = any related door part still has CanCollide on. Open = all off → don't fire.
    local function ad_isClosed(cd)
        if not cd then return false end
        local parent = cd.Parent
        if not parent then return false end

        local function hasCollide(inst, depth)
            if not inst or depth > 5 then return false end
            if inst:IsA("BasePart") and inst.CanCollide == true then
                return true
            end
            for _, ch in ipairs(inst:GetChildren()) do
                if hasCollide(ch, depth + 1) then return true end
            end
            return false
        end

        if hasCollide(parent, 0) then return true end
        -- Door model is often one level up from the ClickDetector parent
        if parent.Parent and hasCollide(parent.Parent, 0) then return true end
        if parent.Parent and parent.Parent.Parent and parent.Parent.Name:lower():find("door", 1, true) then
            if hasCollide(parent.Parent.Parent, 0) then return true end
        end
        return false
    end

    -- Fire every nearby closed door (not locks). Fast scan + fire.
    local ad_lastScan = 0
    local AD_FIRE_INTERVAL = 0.05
    local ad_fireAt = {} -- [cd] = last fire clock
    trackConn(RunService.Heartbeat:Connect(function()
        if not Alive or not AutoDoor.Enabled then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or (hum and hum.Health <= 0) then return end
        local myPos = hrp.Position
        local range = AutoDoor.Range or 10
        local now = os.clock()

        if #ad_tracked == 0 or (now - ad_lastScan) > 1.5 then
            ad_lastScan = now
            pcall(ad_rebuild)
            pcall(function()
                local map = workspace:FindFirstChild("MAP")
                if not map then return end
                for _, inst in ipairs(map:GetDescendants()) do
                    if inst:IsA("ClickDetector") and not ad_seen[inst] then
                        if not ad_isLock(inst) then
                            ad_seen[inst] = true
                            table.insert(ad_tracked, {cd = inst})
                        end
                    end
                end
            end)
        end

        for _, entry in ipairs(ad_tracked) do
            local cd = entry.cd
            if cd and cd.Parent and not ad_isLock(cd) then
                local last = ad_fireAt[cd] or 0
                if (now - last) >= AD_FIRE_INTERVAL then
                    local pos = ad_pos(cd)
                    if pos and (myPos - pos).Magnitude <= range then
                        -- Only closed doors (CanCollide still on)
                        if ad_isClosed(cd) then
                            ad_fireAt[cd] = now
                            ad_fire(cd)
                        end
                    end
                end
            end
        end
    end))

    MiscellaneousSection:Toggle({
        Name = "Auto Door", Flag = "util_autodoor", Default = false,
        Callback = function(state)
            AutoDoor.Enabled = state and true or false
            if state then
                ad_rebuild()
            end
        end,
    })



    -- ── Hover Buy ──
    -- Spams nearby shop ClickDetectors.
    -- Food items: buy until you own 2 copies.
    -- Everything else (armor etc.): keep spamming while in range.
    local HoverBuy = {
        Enabled    = false,
        Range      = 18,
        ClickDelay = 0.04,
        FoodTarget = 2,   -- how many of each food to own
    }
    local hb_tracked = {}

    -- Hard ignore list (paths / names that must never be clicked)
    local HB_IGNORE_INDEX = { [32]=true, [51]=true }
    local HB_IGNORE_NAME = {
        ["[Silencer] - $400"] = true,
        ["[Flintlock] - $3000"] = true,
        ["[LockPicker] - $106"] = true,
        ["[PepperSpray] - $159"] = true,
    }

    local FOOD_NAMES = {
        ["[Donut]"] = true, ["[Hamburger]"] = true, ["[HotDog]"] = true,
        ["[Pizza]"] = true, ["[Popcorn]"] = true, ["[Taco]"] = true,
        ["[Starblox Latte]"] = true, ["[Chicken]"] = true, ["[Cranberry]"] = true,
        ["Donut"] = true, ["Hamburger"] = true, ["HotDog"] = true,
        ["Pizza"] = true, ["Popcorn"] = true, ["Taco"] = true,
        ["Starblox Latte"] = true, ["Chicken"] = true, ["Cranberry"] = true,
    }

    local function hb_isFood(item)
        if not item then return false end
        local n = item.Name or ""
        if FOOD_NAMES[n] then return true end
        local lower = n:lower()
        for food in pairs(FOOD_NAMES) do
            if lower:find(food:lower():gsub("[%[%]]", ""), 1, true) then return true end
        end
        -- armor keywords = not food
        if lower:find("armor", 1, true) or lower:find("vest", 1, true) then return false end
        return false
    end

    local function hb_countOwned(itemName)
        local count = 0
        local function scan(container)
            if not container then return end
            for _, t in ipairs(container:GetChildren()) do
                if t:IsA("Tool") and t.Name == itemName then
                    count = count + 1
                end
            end
        end
        local char = LocalPlayer.Character
        scan(char)
        scan(LocalPlayer:FindFirstChild("Backpack"))
        return count
    end

    local function hb_toolNameFromItem(item)
        if not item then return nil end
        -- Prefer exact tool-style name if present
        local n = item.Name
        if n and n:match("^%[.+%]$") then return n end
        -- Try child tool
        local tool = item:FindFirstChildWhichIsA("Tool", true)
        if tool then return tool.Name end
        return n
    end

    local function hb_isArmor(item)
        if not item then return false end
        local n = (item.Name or ""):lower()
        return n:find("armor", 1, true) ~= nil or n:find("vest", 1, true) ~= nil
    end

    local function hb_shouldIgnore(item, shopChildrenIndex)
        if not item then return true end
        if HB_IGNORE_NAME[item.Name] then return true end
        if shopChildrenIndex and HB_IGNORE_INDEX[shopChildrenIndex] then return true end
        return false
    end

    local function hb_scan()
        hb_tracked = {}
        local shop = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
        if not shop then return end
        local children = shop:GetChildren()
        for idx, item in ipairs(children) do
            if hb_shouldIgnore(item, idx) then continue end
            local cd = item:IsA("ClickDetector") and item or item:FindFirstChildWhichIsA("ClickDetector", true)
            if cd then
                local part = item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart", true)
                local isFood = hb_isFood(item)
                local isArmor = hb_isArmor(item)
                local toolName = hb_toolNameFromItem(item)
                table.insert(hb_tracked, {
                    cd = cd,
                    item = item,
                    part = part,
                    isFood = isFood,
                    isArmor = isArmor,
                    toolName = toolName,
                    shopIndex = idx,
                    lastClick = 0,
                })
            end
        end
    end
    hb_scan()
    task.spawn(function()
        while Alive do
            task.wait(4)
            hb_scan()
        end
    end)

    trackConn(RunService.Heartbeat:Connect(function()
        if not Alive or not HoverBuy.Enabled then return end
        if #hb_tracked == 0 then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or (hum and hum.Health <= 0) then return end

        local now = os.clock()
        local myPos = hrp.Position
        local range = HoverBuy.Range

        local ARMOR_CD_INDICES = { [24]=true, [41]=true, [16]=true, [34]=true, [31]=true, [43]=true, [44]=true }
        local ARMOR_CD_NAMES   = { ["[Full Armor] - $3639"] = true }
        local ARMOR_CD_RANGE   = 10  -- armor CDs only fire within 10 studs

        -- Reads ArmorSave from DataFolder (persistent save value, not live BodyEffects)
        local function hb_getArmorSave()
            local ok, val = pcall(function()
                return LocalPlayer.DataFolder.Information.ArmorSave.Value
            end)
            return ok and tonumber(val) or nil
        end

        for _, entry in ipairs(hb_tracked) do
            local cd = entry.cd
            if not cd or not cd.Parent then
                cd = entry.item and (entry.item:IsA("ClickDetector") and entry.item or entry.item:FindFirstChildWhichIsA("ClickDetector", true))
                entry.cd = cd
            end
            if not cd then continue end

            -- Identify armor CD early so we can apply its own range threshold
            local isArmorCD = ARMOR_CD_INDICES[entry.shopIndex] or ARMOR_CD_NAMES[entry.item and entry.item.Name]

            -- Get position for range check: prefer stored part, fall back to cd.Parent
            local part = entry.part
            if not part or not part.Parent then
                part = entry.item and (entry.item:IsA("BasePart") and entry.item or entry.item:FindFirstChildWhichIsA("BasePart", true))
                if not part then
                    part = cd.Parent and cd.Parent:IsA("BasePart") and cd.Parent or nil
                end
                entry.part = part
            end
            if not part then continue end

            -- Armor CDs use a strict 10-stud range; everything else uses the configured range
            local effectiveRange = isArmorCD and ARMOR_CD_RANGE or range
            if (part.Position - myPos).Magnitude > effectiveRange then continue end
            if (now - entry.lastClick) < HoverBuy.ClickDelay then continue end

            -- Armor CD gate: read DataFolder.Information.ArmorSave
            -- Spam when ArmorSave < 199; block entirely at 199+
            if isArmorCD then
                local armorSave = hb_getArmorSave()
                if armorSave == nil or armorSave >= 199 then
                    continue
                end
            end

            -- Food: stop at target copies; after first buy, hold food out then spam CD again
            if entry.isFood and entry.toolName then
                local owned = hb_countOwned(entry.toolName)
                if owned >= HoverBuy.FoodTarget then
                    continue
                end
                -- ensure any purchased copy is held so the next click registers a second
                if owned >= 1 then
                    local char = LocalPlayer.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local bp = LocalPlayer:FindFirstChild("Backpack")
                    if hum then
                        local held = char and char:FindFirstChild(entry.toolName)
                        if not (held and held:IsA("Tool")) and bp then
                            local t = bp:FindFirstChild(entry.toolName)
                            if t and t:IsA("Tool") then
                                pcall(function() hum:EquipTool(t) end)
                            end
                        end
                    end
                end
            end

            pcall(function()
                if fireclickdetector then
                    fireclickdetector(cd)
                elseif firesignal then
                    firesignal(cd.MouseClick)
                end
            end)
            entry.lastClick = now

            -- After a food click: if we just crossed 1 owned, equip and keep spamming for the 2nd
            if entry.isFood and entry.toolName then
                local ownedAfter = hb_countOwned(entry.toolName)
                if ownedAfter >= 1 and ownedAfter < HoverBuy.FoodTarget then
                    local char = LocalPlayer.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local bp = LocalPlayer:FindFirstChild("Backpack")
                    if hum and bp then
                        local t = bp:FindFirstChild(entry.toolName) or (char and char:FindFirstChild(entry.toolName))
                        if t and t:IsA("Tool") and t.Parent ~= char then
                            pcall(function() hum:EquipTool(t) end)
                        end
                    end
                    -- allow faster re-fire for second copy
                    entry.lastClick = now - (HoverBuy.ClickDelay * 0.5)
                end
            end
        end
    end))

    MiscellaneousSection:Toggle({
        Name = "Hover Buy", Flag = "util_hoverbuy", Default = false,
        Callback = function(state)
            HoverBuy.Enabled = state and true or false
            if state then
                for _, e in ipairs(hb_tracked) do e.lastClick = 0 end
                hb_scan()
            end
        end,
    })

    -- Anti AFK: press W every 15 minutes to avoid idle kick
    do
        local AntiAFK = { Enabled = false }
        local function afkPressW()
            pcall(function()
                if VIM then
                    VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                    task.wait(0.08)
                    VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                elseif keypress and keyrelease then
                    keypress(Enum.KeyCode.W)
                    task.wait(0.08)
                    keyrelease(Enum.KeyCode.W)
                end
            end)
        end
        task.spawn(function()
            while Alive do
                for _ = 1, 900 do
                    if not Alive then return end
                    task.wait(1)
                    if not AntiAFK.Enabled then break end
                end
                if not Alive then return end
                if AntiAFK.Enabled then
                    afkPressW()
                end
            end
        end)
        MiscellaneousSection:Toggle({
            Name = "Anti AFK", Flag = "util_antiafk", Default = false,
            Callback = function(state)
                AntiAFK.Enabled = state and true or false
            end,
        })
    end

    -- Chat Spy: toggle TextChatService chat window
    do
        local function setChatSpy(state)
            pcall(function()
                local TextChatService = game:GetService("TextChatService")
                local cfg = TextChatService.ChatWindowConfiguration
                if cfg then
                    cfg.Enabled = state and true or false
                end
            end)
        end
        MiscellaneousSection:Toggle({
            Name = "Chat Spy", Flag = "util_chatspy", Default = false,
            Callback = function(state)
                setChatSpy(state and true or false)
            end,
        })
    end

-- ============================================================
-- AUTO EAT & AUTO ARMOR
-- ============================================================
do
    local AutoEatCfg = {
        Enabled = false, Delay = 0, ArmorMax = 200,
        FoodList = {
            "[Donut]","[Hamburger]","[HotDog]","[Pizza]","[Popcorn]","[Taco]",
            "[Starblox Latte]","[Chicken]","[Cranberry]",
            "Donut","Hamburger","HotDog","Pizza","Popcorn","Taco",
            "Starblox Latte","Chicken","Cranberry","Cookie","[Cookie]",
        },
    }
    local function getArmorValueSelf()
        local wp = workspace:FindFirstChild("Players"); if not wp then return nil end
        local me = wp:FindFirstChild(LocalPlayer.Name); if not me then return nil end
        local be = me:FindFirstChild("BodyEffects"); if not be then return nil end
        local ar = be:FindFirstChild("Armor"); if not ar then return nil end
        return tonumber(ar.Value)
    end
    local aeMasterOn = true
    local aeToggle

    local function isFoodTool(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local n = tool.Name
        for _, name in ipairs(AutoEatCfg.FoodList) do
            if n == name then return true end
        end
        local lower = n:lower()
        for _, name in ipairs(AutoEatCfg.FoodList) do
            if lower:find(name:lower():gsub("[%[%]]", ""), 1, true) then return true end
        end
        return false
    end

    local function eatClickMouse1()
        -- Prefer tool Activate so the held food is actually consumed
        local char = LocalPlayer.Character
        local tool = char and char:FindFirstChildWhichIsA("Tool")
        if tool and isFoodTool(tool) then
            pcall(function() tool:Activate() end)
        end
        if mouse1click then pcall(mouse1click) end
        if mouse1press and mouse1release then
            pcall(function() mouse1press(); task.wait(0.02); mouse1release() end)
        elseif mouse1down and mouse1up then
            pcall(function() mouse1down(); task.wait(0.02); mouse1up() end)
        end
        if VIM then
            local m = UserInputService:GetMouseLocation()
            pcall(function()
                VIM:SendMouseButtonEvent(m.X, m.Y, 0, true,  game, 1)
                task.wait(0.02)
                VIM:SendMouseButtonEvent(m.X, m.Y, 0, false, game, 1)
            end)
        end
    end

    local function getEquippedFood()
        local char = LocalPlayer.Character; if not char then return nil end
        for _, t in ipairs(char:GetChildren()) do
            if isFoodTool(t) then return t end
        end
        return nil
    end

    local function getBackpackFood()
        local bp = LocalPlayer:FindFirstChild("Backpack"); if not bp then return nil end
        for _, t in ipairs(bp:GetChildren()) do
            if isFoodTool(t) then return t end
        end
        return nil
    end

    local function isChickenOrCookie(tool)
        if not tool then return false end
        local n = (tool.Name or ""):lower()
        return n:find("chicken", 1, true) ~= nil or n:find("cookie", 1, true) ~= nil
    end

    task.spawn(function()
        while Alive do
            if not AutoEatCfg.Enabled then task.wait(0.1); continue end
            local char = LocalPlayer.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then task.wait(0.1); continue end

            -- Armor above 199: never eat any food
            local armor = getArmorValueSelf()
            if armor and armor > 199 then task.wait(0.2); continue end

            local health = hum.Health

            local function foodAllowed(tool)
                if not tool then return false end
                -- Health over 99: do not eat chicken or cookie
                if health > 99 and isChickenOrCookie(tool) then return false end
                return true
            end

            local equipped = getEquippedFood()
            if equipped and not foodAllowed(equipped) then
                -- Unequip blocked food so we can pick something else
                pcall(function() equipped.Parent = LocalPlayer:FindFirstChild("Backpack") end)
                equipped = nil
                task.wait(0.05)
            end

            if not equipped then
                local bp = LocalPlayer:FindFirstChild("Backpack")
                if bp then
                    for _, t in ipairs(bp:GetChildren()) do
                        if isFoodTool(t) and foodAllowed(t) then
                            pcall(function() hum:EquipTool(t) end)
                            task.wait(0.08)
                            equipped = getEquippedFood() or t
                            break
                        end
                    end
                end
            end

            if equipped and foodAllowed(equipped) then
                if equipped.Parent ~= char then
                    pcall(function() hum:EquipTool(equipped) end)
                    task.wait(0.05)
                end
                eatClickMouse1()
                local delay = AutoEatCfg.Delay or 0
                if delay > 0 then task.wait(delay) else task.wait() end
            else
                task.wait(0.15)
            end
        end
    end)

    -- ============================================================
    -- PURCHASE — Auto Armor (Instant + Invis/God mode)
    -- (wrapped in its own do block to stay under Lua's 200-local limit)
    -- ============================================================
    -- Isolated function scope (Luau 200 local-register limit)
    local function runAutoArmorScope()
    local AutoArmor = {
        Enabled   = false,
        Method    = "Instant",  -- "Instant" or "Invis"
        UseSpoof  = true,
        GodMode   = true,       -- Invis method uses God mode (FakePos ON -> D x2 -> TP -> buy -> back -> FakePos OFF)
        ClickWait = 0.008,      -- fastest click spacing
        Clicks    = 8,          -- more clicks per burst
        ArmorMax  = 199,        -- treat armor > 199 as done
        TargetPos = CFrame.new(-938, -29, 566),
        ShopIndex = 41,         -- workspace.Ignored.Shop:GetChildren()[41].ClickDetector
        BuyWindow = 6,
    }
    AutoArmorRef = AutoArmor
    local aaSetHiddenProp = sethiddenproperty or sethiddenprop or set_hidden_property
    local aaLastCharAddedAt = 0
    local aaFakePosEnabled, aaFakePosBusy, aaFakePosCooldown = false, false, 0
    local aaFakePosServerPos = nil
    local aaBusy = false

    local function aaGetHRP()
        local char = LocalPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end
    local function aaSetPhysicsRep(root, value)
        if type(aaSetHiddenProp) == "function" and root then
            pcall(aaSetHiddenProp, root, "PhysicsRepRootPart", value)
        end
    end
    local function aaStartFakePos()
        aaFakePosEnabled = true
        local root = aaGetHRP()
        if root then aaFakePosServerPos = root.Position end
    end
    local function aaStopFakePos()
        local root = aaGetHRP()
        if root then
            local keep = root.CFrame
            aaFakePosEnabled = false
            aaFakePosServerPos, aaFakePosBusy, aaFakePosCooldown = nil, false, 0
            root.CFrame = keep
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            aaSetPhysicsRep(root, root)
            return
        end
        aaFakePosEnabled = false
        aaFakePosServerPos, aaFakePosBusy, aaFakePosCooldown = nil, false, 0
    end

    -- FakePos heartbeat loop for Auto Armor
    trackConn(RunService.Heartbeat:Connect(function()
        if not Alive or not aaFakePosEnabled or type(aaSetHiddenProp) ~= "function" then return end
        local root = aaGetHRP()
        if not root or aaFakePosBusy then return end
        if aaFakePosCooldown <= 0 then
            aaFakePosBusy = true
            local before = root.Position
            aaSetPhysicsRep(root, nil)
            task.wait(0.1)
            local after = root.Position
            aaSetPhysicsRep(root, root)
            if (after - before).Magnitude > 10 then aaFakePosServerPos = after end
            aaFakePosBusy = false
            aaFakePosCooldown = 20
        else
            aaFakePosCooldown -= 1
            aaSetPhysicsRep(root, root)
        end
    end))

    trackConn(LocalPlayer.CharacterAdded:Connect(function()
        aaLastCharAddedAt = tick()
        task.wait(0.35)
        if aaFakePosEnabled then aaStartFakePos() end
    end))
    aaLastCharAddedAt = tick()

    local function aaIsDownOrDead()
        local char = LocalPlayer.Character
        if not char then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return true end
        if hum:GetState() == Enum.HumanoidStateType.Dead then return true end
        local be = char:FindFirstChild("BodyEffects")
        if be then
            local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
            if ko and ko.Value == true then return true end
            local dead = be:FindFirstChild("Dead")
            if dead and dead.Value == true then return true end
        end
        return false
    end

    -- ============================================================
    -- EXPENSIVE ARMOR GATE
    -- These shop child indices (and the named item) only fire when
    -- armor < 200. Index 41 is excluded — that is the auto armor CD.
    -- ============================================================
    local EXPENSIVE_ARMOR_INDICES = { [24]=true, [16]=true, [34]=true, [31]=true, [43]=true, [44]=true }
    local EXPENSIVE_ARMOR_NAMES   = { ["[Full Armor] - $3639"] = true }

    -- Set of actual CD instances to gate. Rebuilt at startup and every 5s.
    local expensiveArmorCDSet = {}
    local function rebuildExpensiveArmorCDSet()
        expensiveArmorCDSet = {}
        local ignored = workspace:FindFirstChild("Ignored"); if not ignored then return end
        local shop = ignored:FindFirstChild("Shop"); if not shop then return end
        local children = shop:GetChildren()
        for idx, child in ipairs(children) do
            if EXPENSIVE_ARMOR_INDICES[idx] or EXPENSIVE_ARMOR_NAMES[child.Name] then
                if child:IsA("ClickDetector") then
                    expensiveArmorCDSet[child] = true
                end
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("ClickDetector") then
                        expensiveArmorCDSet[desc] = true
                    end
                end
            end
        end
    end
    rebuildExpensiveArmorCDSet()
    task.spawn(function()
        while Alive do task.wait(5); rebuildExpensiveArmorCDSet() end
    end)

    -- Returns true = skip this click (armor is full OR this is a gated CD at full armor)
    local function expensiveArmorBlocked(cd)
        if not cd then return false end
        if not expensiveArmorCDSet[cd] then return false end
        local armor = getArmorValueSelf()
        return armor ~= nil and armor >= 200
    end

    local aaCachedCD = nil
    local function getArmorShopClickDetector()
        if aaCachedCD and aaCachedCD.Parent then return aaCachedCD end
        local ignored = workspace:FindFirstChild("Ignored"); if not ignored then return nil end
        local shop = ignored:FindFirstChild("Shop"); if not shop then return nil end
        local children = shop:GetChildren()
        local model = children[AutoArmor.ShopIndex]
        if model then
            local cd = model:FindFirstChildWhichIsA("ClickDetector", true)
            if cd then aaCachedCD = cd; return cd end
        end
        -- No fallback scan — only ever use the exact ShopIndex CD
        return nil
    end

    local function aaStartCamSpoof(cam, frozenCam)
        if not cam or not frozenCam then return nil, nil end
        cam.CameraType = Enum.CameraType.Scriptable
        local look = frozenCam.LookVector
        local camPitch = math.asin(math.clamp(look.Y, -1, 1))
        local camYaw = math.atan2(-look.X, -look.Z)
        local camPos = frozenCam.Position
        local accum = Vector2.zero
        local camSens = 0.006
        local camDeltaConn = UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                accum = accum + Vector2.new(input.Delta.X, input.Delta.Y)
            end
        end)
        local camConn = RunService.RenderStepped:Connect(function()
            if accum.X ~= 0 or accum.Y ~= 0 then
                camYaw = camYaw - accum.X * camSens
                camPitch = math.clamp(camPitch - accum.Y * camSens, -math.pi/2+0.05, math.pi/2-0.05)
                accum = Vector2.zero
            end
            cam.CFrame = CFrame.new(camPos) * CFrame.fromEulerAnglesYXZ(camPitch, camYaw, 0)
        end)
        return camConn, camDeltaConn
    end

    local function aaRestoreCamera(cam, camType, subject)
        if not cam then return end
        local c = LocalPlayer.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        cam.CameraType = (camType and camType ~= Enum.CameraType.Scriptable) and camType or Enum.CameraType.Custom
        if h then cam.CameraSubject = h
        elseif subject then cam.CameraSubject = subject end
    end

    local function aaIsShiftLockActive()
        local ok, result = pcall(function()
            return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
        end)
        if ok then return result end
        return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
    end

    local function aaEnsureShiftLock()
        -- Leave shiftlock on if already active; otherwise toggle it on
        if aaIsShiftLockActive() then return end
        if VIM then
            pcall(function()
                VIM:SendKeyEvent(true,  Enum.KeyCode.LeftShift, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
            end)
        end
        task.wait(0.05)
    end

    local function aaPressKey(key, hold)
        hold = hold or 0.08
        if not VIM then return end
        pcall(function() VIM:SendKeyEvent(true,  key, false, game) end)
        task.wait(hold)
        pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
        task.wait(0.06)
    end

    local function aaPressWS()
        aaPressKey(Enum.KeyCode.W, 0.08)
        aaPressKey(Enum.KeyCode.S, 0.08)
    end

    local function runAutoArmor()
        if not AutoArmor.Enabled or aaIsDownOrDead() or aaBusy then return end
        if tick() - aaLastCharAddedAt < 1.2 then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local armor = getArmorValueSelf()
        if armor and armor >= AutoArmor.ArmorMax then return end
        local cd = getArmorShopClickDetector()
        if not cd then return end

        aaBusy = true
        local startCFrame = hrp.CFrame
        local armorBefore = armor or 0
        local cam = workspace.CurrentCamera
        local camType = cam and cam.CameraType
        local camSubject = cam and cam.CameraSubject
        local frozenCam = cam and cam.CFrame
        local camConn, camDeltaConn
        local usedGodFake = false

        if AutoArmor.Method == "Invis" and AutoArmor.GodMode then
            -- 1) FakePos ON first
            if not aaFakePosEnabled then aaStartFakePos() end
            usedGodFake = true
            -- 2) Shiftlock (keep if already on)
            aaEnsureShiftLock()
            -- 3) Press W and S
            aaPressWS()
            if not AutoArmor.Enabled or aaIsDownOrDead() then
                if usedGodFake then aaStopFakePos() end
                aaBusy = false
                return
            end
            hrp = aaGetHRP()
            if not hrp then
                if usedGodFake then aaStopFakePos() end
                aaBusy = false
                return
            end
            startCFrame = hrp.CFrame
            frozenCam = cam and cam.CFrame
            camType = cam and cam.CameraType
            camSubject = cam and cam.CameraSubject
        end

        -- Spoof camera
        if AutoArmor.UseSpoof and cam and frozenCam then
            camConn, camDeltaConn = aaStartCamSpoof(cam, frozenCam)
        end

        local aborted = false
        pcall(function()
            local startT = tick()
            hrp = aaGetHRP()
            if not hrp then aborted = true; return end

            hrp = aaGetHRP()
            if not hrp then aborted = true; return end

            -- Teleport to armor
            hrp.CFrame = AutoArmor.TargetPos
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero

            -- Invis: press W+S again after arriving at armor
            if AutoArmor.Method == "Invis" then
                aaPressWS()
                hrp = aaGetHRP()
                if not hrp then aborted = true; return end
            end

            if AutoArmor.Method == "Instant" then
                -- fast spam until armor >= ArmorMax (or timeout); never TP back early
                local gotArmor = false
                while AutoArmor.Enabled and tick() - startT < AutoArmor.BuyWindow do
                    if aaIsDownOrDead() then aborted = true; break end
                    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not h then aborted = true; break end
                    if (h.Position - AutoArmor.TargetPos.Position).Magnitude > 3 then
                        h.CFrame = AutoArmor.TargetPos
                    end
                    h.AssemblyLinearVelocity = Vector3.zero
                    if not cd or not cd.Parent then
                        aaCachedCD = nil
                        cd = getArmorShopClickDetector()
                        if not cd then break end
                    end
                    if not expensiveArmorBlocked(cd) then
                        for _ = 1, AutoArmor.Clicks do
                            pcall(fireclickdetector, cd)
                        end
                    end
                    local now = getArmorValueSelf()
                    if now and now >= AutoArmor.ArmorMax then
                        gotArmor = true
                        break
                    end
                    task.wait(AutoArmor.ClickWait)
                end
                if not gotArmor and not aborted then
                    local graceEnd = tick() + 1.0
                    while tick() < graceEnd do
                        local now = getArmorValueSelf()
                        if now and now >= AutoArmor.ArmorMax then gotArmor = true; break end
                        task.wait()
                    end
                end
                if not gotArmor then aborted = true end
            else
                -- Invis method: stay at shop until armor >= ArmorMax (or hard timeout)
                local hardTimeout = math.max(AutoArmor.BuyWindow, 8)
                local gotArmor = false
                while AutoArmor.Enabled and tick() - startT < hardTimeout do
                    if aaIsDownOrDead() then aborted = true; break end
                    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not h then aborted = true; break end
                    -- less aggressive correction for Invis (only if drifted far)
                    if (h.Position - AutoArmor.TargetPos.Position).Magnitude > 8 then
                        h.CFrame = AutoArmor.TargetPos
                    end
                    h.AssemblyLinearVelocity = Vector3.zero
                    if not cd or not cd.Parent then
                        aaCachedCD = nil
                        cd = getArmorShopClickDetector()
                        if not cd then break end
                    end
                    if not expensiveArmorBlocked(cd) then
                        for _ = 1, AutoArmor.Clicks do
                            pcall(fireclickdetector, cd)
                        end
                    end
                    local now = getArmorValueSelf()
                    -- armor over 199 => done, stop buying / stop correcting position
                    if now and now > 199 then
                        gotArmor = true
                        break
                    end
                    RunService.Heartbeat:Wait()
                end
                if not gotArmor and not aborted then
                    local graceEnd = tick() + 1.5
                    while tick() < graceEnd do
                        local now = getArmorValueSelf()
                        if now and now > 199 then gotArmor = true; break end
                        RunService.Heartbeat:Wait()
                    end
                end
                if not gotArmor then aborted = true end
            end
        end)

        -- TP back to start immediately once armor is above max (or after Instant attempt)
        -- Invis always returns home so FakePos can be turned off cleanly
        if not aaIsDownOrDead() and (not aborted or AutoArmor.Method == "Invis") then
            local c2 = LocalPlayer.Character
            local newHrp = c2 and c2:FindFirstChild("HumanoidRootPart")
            if newHrp then
                pcall(function()
                    newHrp.CFrame = startCFrame
                    newHrp.AssemblyLinearVelocity = Vector3.zero
                    newHrp.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end

        if camConn then camConn:Disconnect() end
        if camDeltaConn then camDeltaConn:Disconnect() end
        if AutoArmor.UseSpoof then aaRestoreCamera(cam, camType, camSubject) end

        -- Invis/God: turn FakePos OFF as soon as we are back (or aborted)
        if usedGodFake or (AutoArmor.Method == "Invis" and AutoArmor.GodMode) then
            aaStopFakePos()
        end

        aaBusy = false
    end

    local aaMasterOn = true
    local aaToggle
    aaToggle = MiscellaneousSection:Toggle({
        Name = "Auto Armor", Flag = "aa_enabled", Default = false,
        Callback = function(state)
            aaMasterOn = state and true or false
            AutoArmor.Enabled = state and true or false
            if not state then
                aaBusy = false
                if aaFakePosEnabled then aaStopFakePos() end
            end
        end,
    })
    aaToggle:Keybind({
        Flag = "aa_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not aaMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["aa_key"]
                if isKeybindNone(_kb) then return end
            end
            AutoArmor.Enabled = v
            if not v then
                aaBusy = false
                if aaFakePosEnabled then aaStopFakePos() end
            end
            if aaToggle and type(aaToggle.SetValue) == "function" then
                pcall(function() aaToggle:SetValue(v) end)
            end
        end,
    })

    task.spawn(function()
        while Alive do
            if not AutoArmor.Enabled then task.wait(0.2); continue end
            pcall(runAutoArmor)
            task.wait(0.5)
        end
    end)

    end -- closes runAutoArmorScope
    runAutoArmorScope()

    -- ============================================================
    -- AUTO FOOD — Instant / Hidden (isolated for Luau 200-local limit)
    -- ============================================================
    local function runAutoFoodScope()
    local CAS = game:GetService("ContextActionService")
    local setHiddenProp = sethiddenproperty or sethiddenprop or set_hidden_property

    local AutoFood = {
        Enabled      = false,
        Method       = "Instant",
        UseSpoof     = true,
        TargetCopies = 2,
        TPSettle     = 0.05,
        FireBurst    = 2,
        MaxStay      = 4,
        MaxRetries   = 2,
        MatchRange   = 60,
        ReturnHome   = true,
        SpamInterval = 0.15,
        RespawnDelay = 1.5,
        ComboPreWait = 0.50,
        DSpamInterval= 0.05,
        Debug        = false,
    }
    AutoFoodRef = AutoFood

    local AFUnloaded = false
    local AFBusy = false
    local PassPending, PassIndex = false, 1
    local PassFoods, StandDone = {}, {}
    local CurrentFood = nil
    local PrepFoods = nil
    local PassHome = nil
    local ComboStartCF = nil
    local ComboForceSpoofCF = nil
    local DSpamActive = false
    local AFConns = {}
    local function AFtrack(c) if c then table.insert(AFConns, c) end; return c end

    local FoodDefs = {
        { kind = "name",  shop = "[Donut] - $5",          tool = "[Donut]",          pos = Vector3.new(606, 49, -252) },
        { kind = "name",  shop = "[Starblox Latte] - $5", tool = "[Starblox Latte]", pos = Vector3.new(606, 49, -258) },
        { kind = "name",  shop = "[HotDog] - $8",         tool = "[HotDog]",         pos = Vector3.new(405, 39, -16) },
        { kind = "name",  shop = "[Pizza] - $5",          tool = "[Pizza]",          pos = Vector3.new(312, 53, -628) },
        { kind = "index", index = 44,                     tool = nil,                pos = Vector3.new(307, 53, -628) },
        { kind = "index", index = 61,                     tool = nil,                pos = Vector3.new(-282, 23, -809) },
        { kind = "index", index = 15,                     tool = nil,                pos = Vector3.new(-993, 25, -154) },
        { kind = "name",  shop = "[Taco] - $4",           tool = "[Taco]",           pos = Vector3.new(-601, 22, 240) },
        { kind = "index", index = 56,                     tool = nil,                pos = Vector3.new(-20, 36, -812) },
    }

    local KnownTools = {
        ["[Chicken]"] = true, ["[Cranberry]"] = true, ["[Da Milk]"] = true,
        ["[Donut]"] = true, ["[Hamburger]"] = true, ["[Meat]"] = true,
        ["[Pizza]"] = true, ["[Popcorn]"] = true, ["[Starblox Latte]"] = true,
        ["[Taco]"] = true, ["[HotDog]"] = true,
    }

    local function getShop()
        local ignored = workspace:FindFirstChild("Ignored")
        return ignored and ignored:FindFirstChild("Shop")
    end

    local function norm(s)
        s = tostring(s or ""):lower()
        local inner = s:match("%[(.-)%]")
        if inner then s = inner
        else s = s:match("^(.-)%s*%-%s*%$") or s end
        return (s:gsub("[^%w]", ""))
    end
    local function nameMatchesKeys(toolName, keys)
        local n = norm(toolName)
        if n == "" or not keys then return false end
        for _, k in ipairs(keys) do
            if n == k then return true end
            if #n >= 3 and #k >= 3 and (n:find(k, 1, true) or k:find(n, 1, true)) then return true end
        end
        return false
    end
    local function addKey(keys, name)
        local n = norm(name)
        if n == "" or #n < 3 then return end
        for _, k in ipairs(keys) do if k == n then return end end
        table.insert(keys, n)
    end
    local function keysFor(def, model)
        local keys = {}
        if def.tool then addKey(keys, def.tool) end
        if model then
            addKey(keys, model.Name)
            local mn = model.Name:lower()
            for tool in pairs(KnownTools) do
                local bare = tool:gsub("[%[%]]", ""):lower()
                if mn:find(bare, 1, true) then addKey(keys, tool) end
            end
        end
        return keys
    end

    local FrameId = 0
    AFtrack(RunService.Heartbeat:Connect(function() FrameId += 1 end))
    local OwnedCache, OwnedFrame = nil, -1
    local function ownedTools()
        if OwnedCache and OwnedFrame == FrameId then return OwnedCache end
        local list, seen = {}, {}
        local function add(item)
            if item and item:IsA("Tool") and not seen[item] then
                seen[item] = true; list[#list + 1] = item
            end
        end
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp then for _, item in ipairs(bp:GetChildren()) do add(item) end end
        local char = LocalPlayer.Character
        if char then for _, item in ipairs(char:GetChildren()) do add(item) end end
        OwnedCache, OwnedFrame = list, FrameId
        return list
    end
    local function countFood(food)
        if not food or #food.keys == 0 then return 0 end
        local n = 0
        for _, t in ipairs(ownedTools()) do
            if nameMatchesKeys(t.Name, food.keys) then n += 1 end
        end
        return n
    end
    local function belongsToOther(food, toolName)
        for _, other in ipairs(PassFoods) do
            if other ~= food and other.cd ~= food.cd and #other.keys > 0 and nameMatchesKeys(toolName, other.keys) then
                return true
            end
        end
        return false
    end

    local function pivotPos(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("PVInstance") then
            local ok, pv = pcall(function() return inst:GetPivot() end)
            if ok then return pv.Position end
        end
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end
    local function standModelOf(cd, shop)
        local m = cd.Parent
        while m and m.Parent and m.Parent ~= shop do m = m.Parent end
        return m or cd.Parent
    end
    local function clickDetectorOf(inst)
        if not inst then return nil end
        if inst:IsA("ClickDetector") then return inst end
        return inst:FindFirstChildOfClass("ClickDetector") or inst:FindFirstChildWhichIsA("ClickDetector", true)
    end
    local function resolveAll()
        local shop = getShop()
        local out = {}
        if not shop then return out end
        local children = shop:GetChildren()
        local allCDs = {}
        for _, d in ipairs(shop:GetDescendants()) do
            if d:IsA("ClickDetector") then table.insert(allCDs, d) end
        end
        local claimed = {}
        for i, def in ipairs(FoodDefs) do
            local target = def.pos
            local cd, model
            local cand
            if def.kind == "index" then
                cand = children[def.index]
            else
                local bestD = math.huge
                for _, c in ipairs(children) do
                    if c.Name == def.shop then
                        local p = pivotPos(c)
                        local d = p and (p - target).Magnitude or math.huge
                        if d < bestD or not cand then cand, bestD = c, d end
                    end
                end
            end
            local candCD = clickDetectorOf(cand)
            if candCD then
                local p = pivotPos(cand)
                if not p or (p - target).Magnitude <= AutoFood.MatchRange or def.kind == "name" then
                    cd, model = candCD, cand
                end
            end
            if not cd then
                local best, bestD, bestClaimedD, bestClaimed = nil, AutoFood.MatchRange, AutoFood.MatchRange, nil
                for _, c in ipairs(allCDs) do
                    local m = standModelOf(c, shop)
                    local p = pivotPos(c.Parent) or pivotPos(m)
                    if p then
                        local d = (p - target).Magnitude
                        if claimed[m] then
                            if d <= bestClaimedD then bestClaimed, bestClaimedD = c, d end
                        elseif d <= bestD then best, bestD = c, d end
                    end
                end
                cd = best or bestClaimed
                if cd then model = standModelOf(cd, shop) end
            end
            if not cd and candCD then cd, model = candCD, cand end
            if cd then
                claimed[model] = true
                table.insert(out, {
                    def = def, cd = cd, model = model,
                    keys = keysFor(def, model),
                    pos = CFrame.new(def.pos),
                    number = i,
                })
            end
        end
        return out
    end

    local function isDownOrDead()
        local char = LocalPlayer.Character
        if not char then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return true end
        local be = char:FindFirstChild("BodyEffects")
        if be then
            local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
            if ko and ko.Value then return true end
        end
        return false
    end
    local function setPhysicsRep(root, value)
        if type(setHiddenProp) == "function" and root then
            pcall(setHiddenProp, root, "PhysicsRepRootPart", value)
        end
    end

    local camConn, camDeltaConn
    local savedCamType, savedCamSubject, savedMouseBehavior
    local SINK_ACTION = "AutoFoodCamSink"
    local CamKeys = {
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
        Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Space,
    }
    local function startSpoof(freezeCF)
        if not AutoFood.UseSpoof and not freezeCF then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        savedCamType = cam.CameraType
        savedCamSubject = cam.CameraSubject
        savedMouseBehavior = UserInputService.MouseBehavior
        local frozen
        if freezeCF then
            local eye = freezeCF.Position + Vector3.new(0, 2.5, 0)
            frozen = CFrame.new(eye, eye + freezeCF.LookVector)
        else
            frozen = cam.CFrame
        end
        cam.CameraType = Enum.CameraType.Scriptable
        local look = frozen.LookVector
        local pitch = math.asin(math.clamp(look.Y, -1, 1))
        local yaw = math.atan2(-look.X, -look.Z)
        local pos = frozen.Position
        local accum = Vector2.zero
        local rmbLocked = false
        if camDeltaConn then camDeltaConn:Disconnect() end
        if camConn then camConn:Disconnect() end
        pcall(function()
            CAS:BindActionAtPriority(SINK_ACTION, function() return Enum.ContextActionResult.Sink end,
                false, Enum.ContextActionPriority.High.Value, table.unpack(CamKeys))
        end)
        camDeltaConn = UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                accum += Vector2.new(input.Delta.X, input.Delta.Y)
            end
        end)
        camConn = RunService.RenderStepped:Connect(function(dt)
            local typing = UserInputService:GetFocusedTextBox() ~= nil
            local rmb = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) and not typing
            if rmb then
                if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition then
                    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
                    rmbLocked = true
                end
            elseif rmbLocked then
                UserInputService.MouseBehavior = savedMouseBehavior or Enum.MouseBehavior.Default
                rmbLocked = false
            end
            local looking = rmb or UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default
            if looking and (accum.X ~= 0 or accum.Y ~= 0) then
                yaw -= accum.X * 0.006
                pitch = math.clamp(pitch - accum.Y * 0.006, -math.pi/2 + 0.05, math.pi/2 - 0.05)
            end
            accum = Vector2.zero
            local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
            if not typing and not DSpamActive then
                local dir = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += rot.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= rot.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += rot.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= rot.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.new(0, 1, 0) end
                if dir.Magnitude > 0 then pos += dir.Unit * 50 * dt end
            end
            cam.CFrame = CFrame.new(pos) * rot
        end)
    end
    local function stopSpoof()
        if camConn then camConn:Disconnect() camConn = nil end
        if camDeltaConn then camDeltaConn:Disconnect() camDeltaConn = nil end
        pcall(function() CAS:UnbindAction(SINK_ACTION) end)
        if savedMouseBehavior then
            UserInputService.MouseBehavior = savedMouseBehavior
            savedMouseBehavior = nil
        end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        cam.CameraType = (savedCamType and savedCamType ~= Enum.CameraType.Scriptable) and savedCamType or Enum.CameraType.Custom
        if hum then cam.CameraSubject = hum elseif savedCamSubject then cam.CameraSubject = savedCamSubject end
    end

    local function getHRP()
        local char = LocalPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local FakePosEnabled, FakePosBusy, FakePosCooldown = false, false, 0
    local FakePosServerPos = nil
    pcall(function() if setfflag then setfflag("S2PhysicsSenderRate", "1000") end end)
    local function StartFakePos()
        FakePosEnabled = true
        local root = getHRP()
        if root then FakePosServerPos = root.Position end
    end
    local function ReanchorFakePos()
        local root = getHRP()
        if root then FakePosServerPos = root.Position end
    end
    local function StopFakePos()
        local root = getHRP()
        if root then
            local keep = root.CFrame
            FakePosEnabled = false
            FakePosServerPos, FakePosBusy, FakePosCooldown = nil, false, 0
            root.CFrame = keep
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            setPhysicsRep(root, root)
            return
        end
        FakePosEnabled = false
        FakePosServerPos, FakePosBusy, FakePosCooldown = nil, false, 0
    end

    AFtrack(RunService.Heartbeat:Connect(function()
        if not Alive or AFUnloaded or not FakePosEnabled or type(setHiddenProp) ~= "function" then return end
        local root = getHRP()
        if not root or FakePosBusy then return end
        if FakePosCooldown <= 0 then
            FakePosBusy = true
            local before = root.Position
            setPhysicsRep(root, nil)
            task.wait(0.1)
            local after = root.Position
            setPhysicsRep(root, root)
            if (after - before).Magnitude > 10 then FakePosServerPos = after end
            FakePosBusy = false
            FakePosCooldown = 20
        else
            FakePosCooldown -= 1
            setPhysicsRep(root, root)
        end
    end))

    AFtrack(LocalPlayer.CharacterAdded:Connect(function()
        if not Alive or AFUnloaded then return end
        task.wait(0.35)
        if FakePosEnabled then StartFakePos() end
        -- re-run sweep on respawn
        task.delay(AutoFood.RespawnDelay, function()
            if not Alive or AFUnloaded or not AutoFood.Enabled then return end
            PassIndex = 1
            PassPending = true
        end)
    end))

    local function afIsShiftLockActive()
        return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
    end

    local function afEnsureShiftLock()
        if afIsShiftLockActive() then return end
        if VIM then
            pcall(function()
                VIM:SendKeyEvent(true,  Enum.KeyCode.LeftShift, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
            end)
        end
        task.wait(0.05)
    end

    local function afPressKey(key, hold)
        hold = hold or 0.08
        if not VIM then return end
        pcall(function() VIM:SendKeyEvent(true,  key, false, game) end)
        task.wait(hold)
        pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
        task.wait(0.06)
    end

    local function afPressWS()
        afPressKey(Enum.KeyCode.W, 0.08)
        afPressKey(Enum.KeyCode.S, 0.08)
    end

    local function afPressW()
        afPressKey(Enum.KeyCode.W, 0.08)
    end

    local function placeAt(cf)
        local h = getHRP()
        if not h or not cf then return end
        h.CFrame = cf
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
    end
    local function pinTo(food)
        local h = getHRP()
        if not h then return nil end
        if (h.Position - food.pos.Position).Magnitude > 1.5 then h.CFrame = food.pos end
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
        return h
    end
    local function teleportTo(food, settle)
        local h = getHRP()
        if not h then return nil end
        h.CFrame = food.pos
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
        settle = settle or 0
        if settle <= 0 then pinTo(food); return getHRP() end
        local untilT = tick() + settle
        while tick() < untilT do
            if isDownOrDead() or not AutoFood.Enabled then break end
            pinTo(food)
            RunService.Heartbeat:Wait()
        end
        return getHRP()
    end

    -- While invis auto-food is running, continuously spam W+S
    AFtrack(task.spawn(function()
        while Alive and not AFUnloaded do
            if DSpamActive and AutoFood.Enabled and not isDownOrDead() then
                afPressWS()
                task.wait(0.12)
            else
                task.wait(0.15)
            end
        end
    end))

    local function equippedFood(food)
        local char = LocalPlayer.Character
        if not char then return nil end
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and nameMatchesKeys(item.Name, food.keys) then return item end
        end
        return nil
    end
    local function equipNow(food)
        if #food.keys == 0 or equippedFood(food) then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        for _, t in ipairs(ownedTools()) do
            if t.Parent ~= char and nameMatchesKeys(t.Name, food.keys) then
                pcall(function() hum:EquipTool(t) end)
                return
            end
        end
    end
    local function buyUntilOwned(food, need, deadline)
        while tick() < deadline do
            if isDownOrDead() or not AutoFood.Enabled then return countFood(food) end
            local owned = countFood(food)
            if owned >= need then equipNow(food); return owned end
            pinTo(food)
            if food.cd and food.cd.Parent then
                for _ = 1, AutoFood.FireBurst do pcall(fireclickdetector, food.cd) end
            end
            if owned >= 1 then equipNow(food) end
            RunService.Heartbeat:Wait()
        end
        return countFood(food)
    end
    local function processFood(food)
        if not food or not food.cd then return 0, 0 end
        if not getHRP() then return 0, 0 end
        local need = AutoFood.TargetCopies
        local deadline = tick() + AutoFood.MaxStay
        food.keys = keysFor(food.def, food.model or food.cd.Parent)
        local had = countFood(food)
        teleportTo(food, AutoFood.TPSettle)
        if isDownOrDead() or not AutoFood.Enabled then return had, 0 end
        if had >= need then equipNow(food); return had, 0 end
        local owned = buyUntilOwned(food, need, deadline)
        equipNow(food)
        return had, math.max(0, owned - had)
    end
    local function visitStand(food)
        CurrentFood = food
        local had, bought = processFood(food)
        if not AutoFood.Enabled or isDownOrDead() then CurrentFood = nil; return false end
        local owned = countFood(food)
        if owned >= AutoFood.TargetCopies then StandDone[food.def] = true end
        -- Invis method: after the first food stand (donut / #1) is bought, hold D every teleport until home
        if AutoFood.Method == "Invis" and (food.number == 1 or (food.def and food.def.tool == "[Donut]")) then
            if owned >= 1 or bought > 0 or StandDone[food.def] then
                DSpamActive = true
            end
        end
        if AutoFood.Debug then
            print(("[Auto Food] #%d %s | had %d | bought %d | now %d | %s"):format(
                food.number or 0, food.model and food.model.Name or "?", had, bought, owned,
                StandDone[food.def] and "DONE" or "NOT FINISHED"))
        end
        CurrentFood = nil
        return true
    end

    local function runCycle()
        if AFBusy or not AutoFood.Enabled or not PassPending or isDownOrDead() then return end
        local hrp = getHRP()
        if not hrp then return end
        local foods = (PrepFoods and #PrepFoods > 0 and PassIndex == 1) and PrepFoods or resolveAll()
        PrepFoods = nil
        if #foods == 0 then return end
        PassFoods = foods
        if PassIndex == 1 then table.clear(StandDone) end
        AFBusy = true
        -- Only overwrite PassHome if it wasn't already set by startAutoFood
        if (PassIndex == 1 or not PassHome) and not ComboStartCF then PassHome = hrp.CFrame end
        if not PassHome then PassHome = ComboStartCF or hrp.CFrame end

        if ComboForceSpoofCF then
            AutoFood.UseSpoof = true
            startSpoof(ComboForceSpoofCF)
        elseif AutoFood.UseSpoof then
            startSpoof()
        end
        if not FakePosEnabled then setPhysicsRep(hrp, nil) end

        local ok, err = pcall(function()
            while PassIndex <= #foods do
                if not AutoFood.Enabled or isDownOrDead() then return end
                if not visitStand(foods[PassIndex]) then return end
                PassIndex += 1
            end
            for _ = 1, AutoFood.MaxRetries do
                local missed = {}
                for _, f in ipairs(foods) do
                    if not StandDone[f.def] then table.insert(missed, f) end
                end
                if #missed == 0 then break end
                for _, f in ipairs(missed) do
                    if not AutoFood.Enabled or isDownOrDead() then return end
                    if not visitStand(f) then return end
                end
            end
            PassPending = false
        end)
        if not ok and AutoFood.Debug then warn("[Auto Food] " .. tostring(err)) end

        local wasInvis = ComboForceSpoofCF ~= nil
        hrp = getHRP()
        if hrp and not isDownOrDead() then
            if AutoFood.ReturnHome and not PassPending and PassHome then
                hrp.CFrame = PassHome
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            if not FakePosEnabled then setPhysicsRep(hrp, hrp) end
        end
        CurrentFood = nil
        stopSpoof()
        if wasInvis then
            if FakePosEnabled then
                ReanchorFakePos()
                StopFakePos()
            end
            -- Turn off auto food (toggle mode: one sweep then done)
            AutoFood.Enabled = false
            DSpamActive = false
            PassPending = false
            PassIndex = 1
            ComboStartCF = nil
            ComboForceSpoofCF = nil
            PrepFoods = nil
            PassFoods = {}
            StandDone = {}
            -- Sync the UI toggle off
            if afToggle and type(afToggle.SetValue) == "function" then
                pcall(function() afToggle:SetValue(false) end)
            end
        end
        AFBusy = false
    end

    -- background fire on unfinished stands while a sweep is active
    AFtrack(task.spawn(function()
        while Alive and not AFUnloaded do
            if AutoFood.Enabled and AFBusy and not isDownOrDead() then
                for _, food in ipairs(PassFoods) do
                    if food ~= CurrentFood
                        and not StandDone[food.def]
                        and food.cd and food.cd.Parent
                        and not (#food.keys > 0 and countFood(food) >= AutoFood.TargetCopies) then
                        pcall(fireclickdetector, food.cd)
                    end
                end
                task.wait(AutoFood.SpamInterval)
            else
                task.wait(0.15)
            end
        end
    end))

    -- pump: starts a cycle whenever PassPending is true
    AFtrack(task.spawn(function()
        while Alive and not AFUnloaded do
            if AutoFood.Enabled and PassPending and not AFBusy and not isDownOrDead() then
                pcall(runCycle)
                task.wait(0.1)
            else
                task.wait(0.1)
            end
        end
    end))

    local function pressSTwice()
        for _ = 1, 2 do
            pcall(function() VIM:SendKeyEvent(true,  Enum.KeyCode.S, false, game) end)
            task.wait(0.08)
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.S, false, game) end)
            task.wait(0.12)
        end
    end
    local function spamAllClickDetectors(times)
        times = times or 3
        local foods = resolveAll()
        for _ = 1, times do
            for _, food in ipairs(foods) do
                if food.cd and food.cd.Parent then pcall(fireclickdetector, food.cd) end
            end
            task.wait(0.08)
        end
        return foods
    end

    local startAutoFood

    function stopAutoFood()
        AutoFood.Enabled = false
        DSpamActive = false
        PassPending = false
        PassIndex = 1
        AFBusy = false
        stopSpoof()
        if FakePosEnabled then ReanchorFakePos(); StopFakePos() end
        if ComboStartCF then placeAt(ComboStartCF) end
        ComboStartCF = nil
        ComboForceSpoofCF = nil
        AutoFood.UseSpoof = true
        PrepFoods = nil
        PassFoods = {}
        StandDone = {}
    end

    startAutoFood = function(method)
        if AutoFood.Enabled then return end
        AutoFood.Method = method or "Instant"
        AutoFood.Enabled = true
        AutoFood.UseSpoof = true
        AFUnloaded = false

        if AutoFood.Method == "Invis" then
            AFtrack(task.spawn(function()
                local hrp = getHRP()
                ComboStartCF = hrp and hrp.CFrame or nil
                PassHome = ComboStartCF
                PrepFoods = spamAllClickDetectors(3)
                if not AutoFood.Enabled or isDownOrDead() then AutoFood.Enabled = false; return end

                -- 1) FakePos ON
                StartFakePos()
                -- 2) Shiftlock (keep if already on)
                afEnsureShiftLock()
                if not AutoFood.Enabled then return end

                -- 3) Press W and S
                afPressWS()
                if not AutoFood.Enabled then return end

                -- 4) Teleport to first food
                local foods = PrepFoods
                if not foods or #foods == 0 then foods = resolveAll(); PrepFoods = foods end
                if foods and #foods > 0 then
                    placeAt(foods[1].pos)
                    RunService.Heartbeat:Wait()
                end
                if not AutoFood.Enabled then return end

                -- 5) Keep spamming W+S for the rest of the run while CDs are fired
                DSpamActive = true
                ComboForceSpoofCF = ComboStartCF
                AutoFood.UseSpoof = true
                PassIndex = 1
                PassPending = true
            end))
        else
            -- Instant: spoof only, no fake pos
            local hrp = getHRP()
            PassHome = hrp and hrp.CFrame or nil
            ComboForceSpoofCF = nil
            AutoFood.UseSpoof = true
            PassIndex = 1
            PassPending = true
        end
    end

    local afMasterOn = true
    local afToggle
    afToggle = MiscellaneousSection:Toggle({
        Name = "Auto Food", Flag = "af_enabled", Default = false,
        Callback = function(state)
            afMasterOn = state and true or false
            if state then startAutoFood(AutoFood.Method) else stopAutoFood() end
        end,
    })
    afToggle:Keybind({
        Flag = "af_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not afMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["af_key"]
                if isKeybindNone(_kb) then return end
            end
            if v then startAutoFood(AutoFood.Method) else stopAutoFood() end
            if afToggle and type(afToggle.SetValue) == "function" then
                pcall(function() afToggle:SetValue(v) end)
            end
        end,
    })

    -- Auto Eat (placed under Auto Food, toggle + keybind, 0ms delay)
    AutoEatCfg.Delay = 0
    aeToggle = MiscellaneousSection:Toggle({
        Name = "Auto Eat", Flag = "ae_enabled", Default = false,
        Callback = function(state) aeMasterOn = state and true or false; AutoEatCfg.Enabled = state and true or false end,
    })
    aeToggle:Keybind({
        Flag = "ae_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not aeMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["ae_key"]
                if isKeybindNone(_kb) then return end
            end
            AutoEatCfg.Enabled = v
            if aeToggle and type(aeToggle.SetValue) == "function" then
                pcall(function() aeToggle:SetValue(v) end)
            end
        end,
    })

    gnToggle = MiscellaneousSection:Toggle({
        Name = "Gun Noclip", Flag = "gn_enabled", Default = false,
        Callback = function(state)
            gnMasterOn = state and true or false
            gn_setEnabled(state)
        end,
    })
    gnToggle:Keybind({
        Flag = "gn_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not gnMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["gn_key"]
                if isKeybindNone(_kb) then return end
            end
            gn_setEnabled(v)
            if gnToggle and type(gnToggle.SetValue) == "function" then
                pcall(function() gnToggle:SetValue(v) end)
            end
        end,
    })

    layToggle = MiscellaneousSection:Toggle({
        Name = "Lay Macro", Flag = "lay_enabled", Default = false,
        Callback = function(state)
            layMasterOn = state and true or false
            if LayMacroRef then LayMacroRef.Enabled = state and true or false end
            if state and runLayMacro then runLayMacro() end
        end,
    })
    layToggle:Keybind({
        Flag = "lay_key", Default = Enum.KeyCode.Unknown, Mode = "Toggle",
        Callback = function(v)
            if type(v) ~= "boolean" then return end
            if not layMasterOn then return end
            do
                local _kb = Library and Library.Flags and Library.Flags["lay_key"]
                if isKeybindNone(_kb) then return end
            end
            if LayMacroRef then LayMacroRef.Enabled = v end
            if v and runLayMacro then runLayMacro() end
            if layToggle and type(layToggle.SetValue) == "function" then
                pcall(function() layToggle:SetValue(v) end)
            end
        end,
    })
    end
    runAutoFoodScope()
end

    -- Method dropdowns at bottom of Misc (match reference layout)
    MiscellaneousSection:Dropdown({
        Name = "Auto Armor Method", Flag = "aa_method",
        Items = {"Instant", "Invis"},
        Default = "Instant",
        Callback = function(v)
            if AutoArmorRef then AutoArmorRef.Method = v or "Instant" end
        end,
    })
    MiscellaneousSection:Dropdown({
        Name = "Auto Food Method", Flag = "af_method",
        Items = {"Instant", "Invis"},
        Default = "Instant",
        Callback = function(v)
            if AutoFoodRef and (v == "Instant" or v == "Invis") then AutoFoodRef.Method = v end
        end,
    })
end


-- ============================================================
-- SNAPLINE RENDER LOOP
-- ============================================================
do
    ensureSnaplines()

    trackConn(RunService.RenderStepped:Connect(function()
        if not Alive then return end

        -- Aimbot snapline
        local aimTarget = CurrentTarget
        if SnaplineState.Aim.Enabled and aimTarget and aimTarget.Character then
            local aimChar = aimTarget.Character
            local aimPart = aimChar:FindFirstChild(MouseLock.AimPart)
                         or aimChar:FindFirstChild("Head")
                         or aimChar:FindFirstChild("HumanoidRootPart")
            updateSnapline(_snaplineAim, _snaplineAimGlow, true, aimPart,
                SnaplineState.Aim.Color, SnaplineState.Aim.Thickness)
        else
            if _snaplineAim then pcall(function() _snaplineAim.Visible = false end) end
            if _snaplineAimGlow then pcall(function() _snaplineAimGlow.Visible = false end) end
        end

        -- Client Redirection snapline
        local crTarget = CR_State.ActiveTarget
        if SnaplineState.CR.Enabled and crTarget and crTarget.Character then
            local crChar = crTarget.Character
            local crPart = crChar:FindFirstChild("Head") or crChar:FindFirstChild("HumanoidRootPart")
            updateSnapline(_snaplineCR, _snaplineCRGlow, true, crPart,
                SnaplineState.CR.Color, SnaplineState.CR.Thickness)
        else
            if _snaplineCR then pcall(function() _snaplineCR.Visible = false end) end
            if _snaplineCRGlow then pcall(function() _snaplineCRGlow.Visible = false end) end
        end
    end))
end

-- ============================================================
-- UNLOAD — actual cleanup
-- ============================================================
function doUnload()
    if not Alive then return end
    Alive = false

    pcall(function() MouseLock.Enabled = false end)
    pcall(function() Triggerbot.Enabled = false end)
    pcall(function() GunMacro.Enabled = false; GunMacro.Active = false end)
    pcall(function() GunNoclip.Enabled = false; GunNoclip.Active = false end)
    pcall(function() WalkSpeed.Enabled = false end)
    pcall(function() JumpPower.Enabled = false end)
    pcall(function() KnifeJump.Enabled = false end)
    pcall(function() NoJumpCD.Enabled = false end)
    pcall(function() Config.Enabled = false end)
    pcall(function() RangeExtender.Enabled = false end)

    pcall(function()
        if re_restore then re_restore() end
    end)

    pcall(function()
        if cr_restore then cr_restore() end
    end)

    pcall(function()
        if hb_restore then hb_restore() end
    end)

    pcall(function()
        if stopInfiniteAmmo then stopInfiniteAmmo() end
    end)

    pcall(function() RunService:UnbindFromRenderStep(NoJumpCD.StepName) end)
    for _, c in ipairs(NoJumpCD.Conns) do
        pcall(function() c:Disconnect() end)
    end
    NoJumpCD.Conns = {}

    for _, c in ipairs(TrackedConns) do
        pcall(function() c:Disconnect() end)
    end
    TrackedConns = {}

    for _, d in ipairs(TrackedDrawings) do
        pcall(function() d.Visible = false end)
        pcall(function() d:Remove() end)
    end
    TrackedDrawings = {}

    for p, _ in pairs(ESPCache or {}) do
        pcall(function() destroy_esp(p) end)
    end

    for _, g in ipairs(TrackedGuis) do
        pcall(function() g:Destroy() end)
    end
    TrackedGuis = {}

    pcall(function() CurrentTarget = nil end)
    pcall(function() AimViewTarget = nil; SpectateTarget = nil end)
    pcall(function() if clearColorConnections then clearColorConnections() end end)
end

for _, name in ipairs({"Unload", "Destroy", "Dispose", "Shutdown"}) do
    if type(Library[name]) == "function" then
        local orig = Library[name]
        Library[name] = function(self, ...)
            pcall(doUnload)
            return orig(self, ...)
        end
    end
end

task.spawn(function()
    task.wait(0.5)
    if not Alive then return end
    local function findMainGui()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local containers = {CoreGui}
        if pg then table.insert(containers, pg) end
        for _, cont in ipairs(containers) do
            for _, d in ipairs(cont:GetChildren()) do
                if d:IsA("ScreenGui") then
                    local ok = pcall(function()
                        for _, c in ipairs(d:GetDescendants()) do
                            if c:IsA("TextLabel") and type(c.Text) == "string"
                               and (c.Text:find("/getelytra") or c.Text:find("getelytra")) then
                                return true
                            end
                        end
                    end)
                    if ok then
                        return d
                    end
                end
            end
        end
    end
    local gui = findMainGui()
    if gui then
        gui.Destroying:Connect(function() pcall(doUnload) end)
        gui.AncestryChanged:Connect(function()
            if not gui.Parent then pcall(doUnload) end
        end)
    end
end)

task.spawn(function()
    task.wait(1.5)
    if not Alive then return end
    local function scan(container)
        if not container then return end
        for _, d in ipairs(container:GetDescendants()) do
            if d:IsA("TextButton") and type(d.Text) == "string"
               and d.Text:lower():find("unload") then
                d.MouseButton1Click:Connect(function() pcall(doUnload) end)
            end
        end
    end
    pcall(scan, CoreGui)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then pcall(scan, pg) end
end)

Library:Notification("/getelytra we bypass anticheats.", 4)
