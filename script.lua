-- bobrcheats v22.8 
-- Xeno Executor

-- локализация: загружаем словарь из GitHub
local Locales = nil

do
  local LOCALES_URL = "https://raw.githubusercontent.com/K3rnyx0/bobrcheats/refs/heads/main/locales.lua?v=" .. tostring(tick())

    local function loadFromGitHub()
        local ok, response = pcall(function()
            return game:HttpGet(LOCALES_URL, true)
        end)
        if ok and type(response) == "string" and #response > 0 then
            local chunk = (loadstring or load)(response)
            if chunk then
                local ok2, result = pcall(chunk)
                if ok2 and type(result) == "table" then
                    return result
                end
            end
        end
        return nil
    end

    local dict = loadFromGitHub()

    if dict then
        local current = "en"

        Locales = {
            get = function() return current end,
            set = function(lang)
                if type(lang) ~= "string" then return false end
                local key = lang:lower()
                if key == "en" or key == "ru" then
                    current = key
                    return true
                end
                return false
            end,
            getLanguages = function()
                return {
                    { code = "en", name = "English" },
                    { code = "ru", name = "Русский" },
                }
            end,
            t = function(s, ...)
                if type(s) ~= "string" then return s end
                if current == "ru" then
                    if select("#", ...) > 0 then
                        local ok, r = pcall(string.format, s, ...)
                        if ok then return r end
                    end
                    return s
                end
                local langDict = dict[current] or dict.en or {}
                local translated = langDict[s] or s
                if select("#", ...) > 0 then
                    local ok, r = pcall(string.format, translated, ...)
                    if ok then return r end
                end
                return translated
            end,
        }
    else
        warn("[bobrcheats] Locales file not loaded from GitHub — using built-in RU fallback")
        Locales = {
            get = function() return "ru" end,
            set = function() return false end,
            getLanguages = function()
                return { { code = "ru", name = "Русский" } }
            end,
            t = function(s, ...)
                if type(s) ~= "string" then return s end
                if select("#", ...) > 0 then
                    local ok, r = pcall(string.format, s, ...)
                    if ok then return r end
                end
                return s
            end,
        }
    end
end

local savedLang = getgenv().BOBRCHEATS_LANG
if type(savedLang) == "string" then
    Locales.set(savedLang)
else
    Locales.set("en")
end

-- защита от двойного запуска
if getgenv().BOBRCHEATS_ACTIVE then
    warn(Locales.t("Обнаружен предыдущий запуск! Выгружаем старый экземпляр..."))
    if getgenv().BOBRCHEATS_UNLOAD then
        getgenv().BOBRCHEATS_UNLOAD()
    end
    task.wait(1.5)
    if getgenv().BOBRCHEATS_ACTIVE then
        getgenv().BOBRCHEATS_ACTIVE = false
        getgenv().BOBRCHEATS_UNLOAD = nil
    end
end
getgenv().BOBRCHEATS_ACTIVE = true
-- чистим мусор от прошлых запусков
pcall(function()
    for _, v in pairs(getgenv()) do
        if type(v) == "table" and rawget(v, "Remove") and rawget(v, "Visible") then
            pcall(function() v:Remove() end)
        end
    end
end)
pcall(function()
    local cg = game:GetService("CoreGui")
    if cg:FindFirstChild("_menu") then cg._menu:Destroy() end
    if cg:FindFirstChild("_load") then cg._load:Destroy() end
end)
pcall(function()
    if gethui then
        local h = gethui()
        if h:FindFirstChild("_menu") then h._menu:Destroy() end
        if h:FindFirstChild("_load") then h._load:Destroy() end
    end
end)
pcall(function()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then
            if h:FindFirstChild("_menu") then h._menu:Destroy() end
            if h:FindFirstChild("_load") then h._load:Destroy() end
            if h:FindFirstChild("_bobr_container") then h._bobr_container:Destroy() end
        end
    end
end)

-- сервисы
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local CoreGui = game:GetService("CoreGui")
local DefaultFOV = Camera.FieldOfView

-- объявляем заранее
local AntiCheatResult, antiCheatStatusLabel
local savedMouseBehavior
-- исключения для детектора, чтоб не ловил функции экзекутора
local antiCheatExclusions = {
    ["Animate"] = true,
    ["getexecutorname"] = true,
    ["isscriptable"] = true,
    ["setscriptable"] = true,
    ["getrunningscripts"] = true,
    ["identifyexecutor"] = true,
    ["getscripts"] = true,
    ["getscriptclosure"] = true,
    ["setscriptbytecode"] = true,
    ["getrbxscriptsignals"] = true,
    ["restorescriptbytecode"] = true,
    ["whatexecutor"] = true,
    ["getscripthash"] = true,
    ["getscriptfunction"] = true,
    ["getscriptbytecode"] = true,
    ["getcallingscript"] = true
}

local DeepCheckRunning = false
local DeepCheckCancelled = false
local DeepCheckStarting = false
-- античит детектор
local CollectionService = game:GetService("CollectionService")
AntiCheatResult = nil
antiCheatStatusLabel = nil

function UpdateAntiCheatStatus(text, color)
    if antiCheatStatusLabel then
        antiCheatStatusLabel.Text = text
        if color then
            antiCheatStatusLabel.TextColor3 = color
        end
    end
end

-- Быстрый детектор
function DetectAntiCheat()
local info = {Found = false, List = {}, Message = Locales.t("Сканирование...")}
    local nameKeywords = {
        "anticheat", "anti cheat", "anti-cheat", "watchdog", "sentry",
        "byfron", "hyperion", "bloxwatch", "adonis", "kohls admin",
        "hd admin", "rc7", "iac", "sentinel", "kronos", "vega",
        "criminality", "da hood anti cheat", "античит", "чит-детектор"
    }
    local codePatterns = {
        "kick player", "ban player", "kickplayer", "banplayer",
        "remotecheck", "clientcheck", "check remote", "check client",
        "getgc", "getgenv", "hookfunction", "firesignal",
        "loadstring", "newcclosure", "getfenv", "setfenv"
    }
    local foundObjects = {}
    local foundCount = 0

    local function checkObject(obj, containerName)
        if not obj or not obj.Parent then return end
        local score = 0
        local lowerName = obj.Name:lower()

        for _, kw in ipairs(nameKeywords) do
            if lowerName:find(kw, 1, true) then score = score + 2 break end
        end

        local attrs = {}
        pcall(function() attrs = obj:GetAttributes() end)
        for k, v in pairs(attrs) do
            if tostring(k):lower():find("anticheat") or tostring(v):lower():find("anticheat") then
                score = score + 3
                break
            end
        end

        local tags = {}
        pcall(function() tags = CollectionService:GetTags(obj) end)
        for _, tag in ipairs(tags) do
            if tag:lower():find("anticheat") then
                score = score + 2
                break
            end
        end

        if obj:IsA("LocalScript") or obj:IsA("Script") or obj:IsA("ModuleScript") then
            local src = nil
            pcall(function() src = obj.Source end)
            if src then
                local ss = src:lower()
                for _, pat in ipairs(codePatterns) do
                    if ss:find(pat, 1, true) then score = score + 4 break end
                end
            end
        elseif obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            if not obj.Parent then score = score + 3 end
        end

        if antiCheatExclusions[obj.Name] then return end
        if score >= 5 then
            foundCount = foundCount + 1
            table.insert(foundObjects, {Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName(), Container = containerName})
        end
    end

    local containers = {
        {"Workspace", workspace},
        {"ReplicatedStorage", game:GetService("ReplicatedStorage")},
        {"CoreGui", game:GetService("CoreGui")},
        {"PlayerGui (Local)", LocalPlayer:WaitForChild("PlayerGui", 5)},
        {"PlayerScripts (Local)", LocalPlayer:WaitForChild("PlayerScripts", 5)}
    }
    pcall(function() table.insert(containers, {"ServerScriptService", game:GetService("ServerScriptService")}) end)

    local maxObjects = 800
    local scanned = 0
    local batchSize = 50
    local pause = 0.02

    for _, cont in ipairs(containers) do
        local cname, inst = cont[1], cont[2]
        if inst then
            local descendants = inst:GetDescendants()
            local count = #descendants
            local i = 1
            while i <= count and scanned < maxObjects do
                local stop = math.min(i + batchSize - 1, count)
                for j = i, stop do
                    checkObject(descendants[j], cname)
                    scanned = scanned + 1
                end
                i = stop + 1
                task.wait(pause)
            end
        end
    end

    if foundCount > 0 then
        info.Found = true
        info.List = foundObjects
info.Message = Locales.t("⚠ Обнаружено подозрительных объектов: ") .. foundCount
    else
        info.Found = false
info.Message = Locales.t(" Античит не обнаружен")
    end

print(Locales.t("[bobrcheats] Быстрый детектор: ") .. info.Message)
    if info.Found then
        for i, item in ipairs(info.List) do
            print(string.format("  %d. [%s] %s (%s) -> %s", i, item.Container, item.Name, item.Class, item.Path))
        end
    end

    return info
end

-- Глубокий детектор (по кнопке, облегчённый)
function DeepDetectAntiCheat()
    DeepCheckStarting = true    -- Сообщение о запуске
    print(Locales.t("Глубокая проверка: Запуск..."))
    UpdateAntiCheatStatus(Locales.t("Запуск глубокой проверки..."), Color3.fromRGB(255, 255, 0))

    DeepCheckRunning = true
    DeepCheckCancelled = false

  local info = {Found = false, List = {}, Message = Locales.t("Сканирование...")}
    local totalObjects = 0
    local scannedObjects = 0

    local deepNameKeywords = {
        "anticheat", "anti cheat", "anti-cheat", "watchdog", "sentry", "byfron", "hyperion",
        "bloxwatch", "adonis", "kohls admin", "hd admin", "rc7", "iac", "sentinel", "kronos",
        "vega", "criminality", "da hood anti cheat", "античит", "чит-детектор",
        "remotecheck", "clientcheck", "ban system", "anti exploit"
    }

    local deepCodePatterns = {
        "kick player", "ban player", "kickplayer", "banplayer",
        "remotecheck", "clientcheck", "check remote", "check client",
        "getgc", "getgenv", "hookfunction", "firesignal",
        "loadstring", "newcclosure", "getfenv", "setfenv",
        "getrawmetatable", "setreadonly", "writefile", "readfile",
        "listfiles", "isfolder", "delfolder", "delfile", "loadfile"
    }

    local containers = {
        {"Workspace", workspace},
        {"ReplicatedStorage", game:GetService("ReplicatedStorage")},
        {"StarterGui", game:GetService("StarterGui")},
        {"StarterPack", game:GetService("StarterPack")},
        {"Lighting", Lighting},
        {"ServerScriptService", game:GetService("ServerScriptService")},
        {"CoreGui", game:GetService("CoreGui")},
        {"PlayerGui (Local)", LocalPlayer:WaitForChild("PlayerGui", 2)},
        {"PlayerScripts (Local)", LocalPlayer:WaitForChild("PlayerScripts", 2)},
        {"Backpack (Local)", LocalPlayer:WaitForChild("Backpack", 2)}
    }
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            pcall(function() table.insert(containers, {"PlayerGui ("..plr.Name..")", plr:WaitForChild("PlayerGui", 1)}) end)
            pcall(function() table.insert(containers, {"PlayerScripts ("..plr.Name..")", plr:WaitForChild("PlayerScripts", 1)}) end)
            pcall(function() table.insert(containers, {"Backpack ("..plr.Name..")", plr:WaitForChild("Backpack", 1)}) end)
        end
    end

    for _, cont in ipairs(containers) do
        local inst = cont[2]
        if inst then
            pcall(function()
                totalObjects = totalObjects + #inst:GetDescendants()
            end)
        end
    end
    if totalObjects == 0 then totalObjects = 1 end

    local foundObjects = {}
    local foundCount = 0
    local batchSize = 150
    local pause = 0.003

    local function checkObjectDeep(obj, containerName)
        if not obj or not obj.Parent then return end
        if antiCheatExclusions[obj.Name] then return end
 
        local score = 0
        local lowerName = obj.Name:lower()

        for _, kw in ipairs(deepNameKeywords) do
            if lowerName:find(kw, 1, true) then score = score + 2 break end
        end

        local attrs = {}
        pcall(function() attrs = obj:GetAttributes() end)
        for k, v in pairs(attrs) do
            if tostring(k):lower():find("anticheat") or tostring(v):lower():find("anticheat") then
                score = score + 3
                break
            end
        end

        local tags = {}
        pcall(function() tags = CollectionService:GetTags(obj) end)
        for _, tag in ipairs(tags) do
            if tag:lower():find("anticheat") then
                score = score + 2
                break
            end
        end

        if obj:IsA("LocalScript") or obj:IsA("Script") or obj:IsA("ModuleScript") then
            local src = nil
            pcall(function() src = obj.Source end)
            if src then
                local ss = src:lower()
                local patternsFound = 0
                for _, pat in ipairs(deepCodePatterns) do
                    if ss:find(pat, 1, true) then
                        patternsFound = patternsFound + 1
                        if patternsFound >= 10 then break end
                    end
                end
                score = score + patternsFound * 2
            end
        elseif obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            if lowerName:find("remotecheck", 1, true) or lowerName:find("clientcheck", 1, true) then
                score = score + 5
            end
            if not obj.Parent then score = score + 3 end
        end

        if score >= 6 then
            foundCount = foundCount + 1
            table.insert(foundObjects, {Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName(), Container = containerName})
        end
    end

print(Locales.t("Глубокая проверка: Сканирование..."))
    local lastPrintedPercent = -1
    for _, cont in ipairs(containers) do
        local cname, inst = cont[1], cont[2]
        if inst and not DeepCheckCancelled then
            local descendants = inst:GetDescendants()
            local count = #descendants
            local i = 1
            while i <= count and not DeepCheckCancelled do
                local stop = math.min(i + batchSize - 1, count)
                for j = i, stop do
                    if DeepCheckCancelled then break end
                    checkObjectDeep(descendants[j], cname)
                    scannedObjects = scannedObjects + 1
                end
                i = stop + 1
                local percent = math.floor(scannedObjects / totalObjects * 100)
if percent >= 95 then
UpdateAntiCheatStatus(Locales.t("Окончание..."), Color3.fromRGB(255, 255, 0))
else
    UpdateAntiCheatStatus(Locales.t("Проверка: ") .. percent .. "%", Color3.fromRGB(200, 200, 200))
end
                task.wait(pause)
            end
        end
        if DeepCheckCancelled then break end
    end

    if not DeepCheckCancelled then
        pcall(function()
            if getnilinstances then
                local nilInstances = getnilinstances()
                for _, obj in ipairs(nilInstances) do
                    if DeepCheckCancelled then break end
                    checkObjectDeep(obj, "Hidden (nil parent)")
                    task.wait(0.02)
                end
            end
        end)
    end

    if not DeepCheckCancelled then
        pcall(function()
            local genv = getgenv()
            local suspiciousKeys = {"anticheat", "ban", "kick", "remotecheck", "clientcheck", "watchdog", "sentry"}
            for key, value in pairs(genv) do
                if DeepCheckCancelled then break end
                local keyStr = tostring(key):lower()
                if not antiCheatExclusions[keyStr] then
                    for _, kw in ipairs(suspiciousKeys) do
                        if keyStr:find(kw, 1, true) then
                            foundCount = foundCount + 1
                            table.insert(foundObjects, {Name = keyStr, Class = "GlobalEnv", Path = "_G["..keyStr.."]", Container = "Глобальное окружение"})
                            break
                        end
                    end
                end
            end
        end)
    end

    if DeepCheckCancelled then
        info.Found = false
        info.Message = Locales.t("⏹ Проверка остановлена")
        print(Locales.t("Глубокая проверка остановлена пользователем."))
    else
        print(Locales.t("Глубокая проверка: Окончание..."))
        if foundCount > 0 then
            info.Found = true
            info.List = foundObjects
            info.Message = Locales.t("⚠ Обнаружено подозрительных объектов: ") .. foundCount
       else
           info.Message = Locales.t("✅ Античит не обнаружен")
       end
           print(Locales.t("Глубокая проверка завершена: ") .. info.Message)
        if info.Found then
            for i, item in ipairs(info.List) do
                print(string.format("  %d. [%s] %s (%s) -> %s", i, item.Container, item.Name, item.Class, item.Path))
            end
        end
    end

     UpdateAntiCheatStatus(Locales.t("Статус античита: ") .. info.Message, info.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100))
    DeepCheckRunning = false
    DeepCheckStarting = false
    return info
end


-- Запуск быстрого детектора при старте
task.spawn(function()
    task.wait(2)
    local success, result = pcall(DetectAntiCheat)
    if not success then
        warn(Locales.t("[bobrcheats] Ошибка быстрого детектора:"), result)
        UpdateAntiCheatStatus(Locales.t("Ошибка детектора"), Color3.fromRGB(255, 100, 100))
        return
    end
    AntiCheatResult = result
UpdateAntiCheatStatus(Locales.t("Статус античита: ") .. result.Message .. " " .. Locales.t("(приблизительно)"), result.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100))
print(Locales.t("[bobrcheats] Быстрый детектор завершён. Результат: ") .. result.Message)
end)

local RaycastParamsAvailable = pcall(function() return RaycastParams.new() end)
local RaycastParamsClass = RaycastParamsAvailable and RaycastParams or nil
local DrawingAvailable = pcall(function()
    local s = Drawing.new("Square")
    s:Remove()
    return true
end)

function safeRenderSetting(getter, default)
    local ok, val = pcall(getter)
    return ok and val or default
end
local DefaultQualityLevel = safeRenderSetting(function() return settings().Rendering.QualityLevel end, 10)
local DefaultMeshDetail = safeRenderSetting(function() return settings().Rendering.MeshPartDetailLevel end, Enum.MeshPartDetailLevel.Level02)

local DefaultLighting = {
    Brightness = Lighting.Brightness,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    ClockTime = Lighting.ClockTime,
    GlobalShadows = Lighting.GlobalShadows,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Ambient = Lighting.Ambient,
    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
    EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
}
local DefaultGravity = workspace.Gravity

-- настройки
local MAX_SAFE_SPEED = 1000
local MAX_SAFE_FLIGHT = 1000
local MAX_FULLBRIGHT_BRIGHTNESS = 50

local Settings = {
    MenuKey = Enum.KeyCode.Insert,
    ShowFPS = false,
    ShowPing = false,
    MenuTransparency = 0.05,
    AccentColor = Color3.fromRGB(255, 60, 60),
    DisableWarnings = false,

    ESP_Enabled = true,
    ESP_TeamCheck = true,
    ESP_Boxes = true,
    ESP_Tracers = false,
    ESP_Names = false,
    ESP_HealthMode = "Bar",
    ESP_Distance = false,
    ESP_VisibilityCheck = false,
    ESP_Chams = false,
    ESP_ChamsBrightness = 100,
    ESP_TeamColors = true,

    ESP_Trails = false,
    ESP_TrailPointDist = 1,
    ESP_TrailMaxPoints = 100,
    ESP_TrailThickness = 2,
    ESP_HealthTextSize = 12,
    ESP_HealthTextColor = Color3.fromRGB(255, 100, 100),

    ESP_NPCs = false,
    ESP_NPC_Names = false,
    ESP_NPC_HealthMode = "Bar",
    ESP_NPC_Tracers = false,
    ESP_NPC_Distance = false,
    ESP_NPC_MaxDistance = 500,
    ESP_NPC_CustomSizes = false,
    ESP_NPC_Chams = false,
    ESP_NPC_ChamsBrightness = 100,

    ESP_NPC_Trails = false,
    ESP_NPC_TrailPointDist = 1,
    ESP_NPC_TrailMaxPoints = 100,
    ESP_NPC_NameSize = 13,
    ESP_NPC_BoxThickness = 2,
    ESP_NPC_HealthTextSize = 12,
    ESP_NPC_HealthBarWidth = 4,
    ESP_NPC_HealthBarOffset = 4,
    ESP_NPC_DistanceSize = 12,

    ESP_BoxColor = Color3.fromRGB(255, 50, 50),
    ESP_TracerColor = Color3.fromRGB(255, 255, 255),
    ESP_NameColor = Color3.fromRGB(255, 255, 255),
    ESP_DistanceColor = Color3.fromRGB(200, 200, 200),
    NPC_BoxColor = Color3.fromRGB(255, 150, 0),
    NPC_NameColor = Color3.fromRGB(255, 150, 0),
    NPC_TracerColor = Color3.fromRGB(255, 150, 0),

    ESP_BoxThickness = 2,
    ESP_TracerThickness = 1,
    ESP_NameSize = 13,
    ESP_Skeleton = false,
    ESP_SkeletonColor = Color3.fromRGB(255, 255, 255),
    ESP_SkeletonThickness = 1.5,
    ESP_HealthBarWidth = 4,
    ESP_HealthBarOffset = 4,
    ESP_DistanceSize = 12,
    ESP_LimitDistance = false,
    ESP_MaxDistance = 5000,

    Speed_Enabled = false,
    Speed_Value = 16,
    Flight_Enabled = false,
    Flight_Speed = 50,
    Flight_Key = Enum.KeyCode.LeftControl,
    Noclip_Enabled = false,
    GodMode_Enabled = false,
    AntiAFK_Enabled = false,
    AntiAFK_Interval = 30,
    AntiAFK_StepDuration = 0.4,

    SmartAntiAFK_Enabled = false,
    SmartAntiAFK_IdleTime = 30,        
    SmartAntiAFK_TrackMouse = true,    
    SmartAntiAFK_TrackKeyboard = true, 
    SmartAntiAFK_TrackMouseMove = false,

    Freeze_Enabled = false,
    Freeze_Position = nil,
    Freeze_WasFlight = false,
    Freeze_WasNoclip = false,

    Gravity_Enabled = false,
    Gravity_Value = 196.2,

    Fullbright_Enabled = false,
    Fullbright_Brightness = 50,
    PotatoGraphics_Enabled = false,
    AtmosphereRemover_Enabled = false,
    ThirdPerson_Enabled = false,
    CursorUnlock_Enabled = false,
    FOV_Enabled = false,
    FOV_Value = 70,
    Cross_Enabled = false,
    Cross_Size = 15,
    Cross_Thickness = 2,
    Cross_Gap = 4,
    Cross_Color = Color3.fromRGB(0, 255, 0),
    Cross_Outline = true,
    Cross_OutlineThickness = 1,
    Cross_OutlineColor = Color3.fromRGB(0, 0, 0),
    Cross_Dot = false,
    Cross_DotSize = 2,
    Cross_HideTop = false,

    Aim_Enabled = false,
    Aim_AutoAim = false,
    Aim_Key = Enum.UserInputType.MouseButton2,
    AimKeyBind = nil,   
    Aim_Smoothness = 0.5,
    Aim_ReactionEnabled = false,
    Aim_ReactionDelay = 0,
    Aim_FOV = 200,
    Aim_Part = "Head",
    Aim_TeamCheck = true,
    Aim_TargetNPCs = false,
    Aim_VisibleCheck = true,
    Aim_ShowFOV = true,
    Aim_FOVColor = Color3.fromRGB(255, 60, 60),
    Aim_Realistic = false,
    Aim_IgnorePlayersInRaycast = false,
    Trigger_ReactionDelay = 0.05,
    Aim_PartAutoMargin = 5,

    Trigger_Enabled = false,
    Trigger_Delay = 0.1,
    Trigger_Mode = "Automatic",
    Trigger_VisibleCheck = false,
    Trigger_TargetNPCs = false,

    Highlight_Objects = false,
    Highlight_Distance = 300,
    Highlight_Color = Color3.fromRGB(0, 255, 200),
    Highlight_Names = true,
    Highlight_OnlyInteractive = true,
    Highlight_MaxSize = 13,

    Spectating = false,
    SpectateTarget = nil,
    SpectateIsNPC = false,
    SpectateTargetModel = nil,

    ClickTP_Enabled = false,
    ClickTP_Key = Enum.UserInputType.MouseButton1,
    ClickTP_MaxDistance = 500,

    SavedLocations = {},
    LastSavedPosition = nil,

    TP_TeamColorButtons = true,

        KeyBinds = {
        Visuals = nil,
        Speed = nil,
        Flight = nil,
        Noclip = nil,
        Aimbot = nil,
        Trigger = nil,
        AutoClicker = nil,
        ThirdPerson = nil,
        AimKeyBind = Enum.UserInputType.MouseButton2,
        CursorUnlock = Enum.KeyCode.RightControl,
        ClickTP_Key = Enum.UserInputType.MouseButton1,
        ClickTP = nil,
        BHop = nil,
        Freeze = nil
    },

    AutoClicker_Enabled = false,
    AutoClicker_Delay = 0.1,
    AutoClicker_HoldDuration = 0.05,
    BHop_Enabled = false,
    BHop_Delay = 0,
}

local FavoritePlayers = {}
local npcCacheData = {}

function ToggleFavorite(player)
    if FavoritePlayers[player] then FavoritePlayers[player] = nil
    else FavoritePlayers[player] = true end
    RefreshTPTab()
    RefreshSpectateList()
end
function IsFavorite(player) return FavoritePlayers[player] == true end

-- эмуляция клика мышью

local mouse1press, mouse1release

if syn and syn.cache then
    mouse1press = function() syn.cache.mouse1press() end
    mouse1release = function() syn.cache.mouse1release() end
elseif VIM then
    mouse1press = function()
        local mousePos = UserInputService:GetMouseLocation()
        VIM:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0)
    end
    mouse1release = function()
        local mousePos = UserInputService:GetMouseLocation()
        VIM:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0)
    end
else
    mouse1press = function() end
    mouse1release = function() end
end

local function fastClick()
    mouse1press()
    task.wait(0.01)
    mouse1release()
end

-- Ждём полной загрузки игры и CoreGui
if not game:IsLoaded() then
    game.Loaded:Wait()
end
task.wait(1) 

-- контейнер для нашего GUI
local SafeParent
do
    local target = LocalPlayer:WaitForChild("PlayerGui")

    local existing = target:FindFirstChild("_bobr_container")
    if existing then existing:Destroy() end

    local container = Instance.new("Folder")
    container.Name = "_bobr_container"
    container.Parent = target
    SafeParent = container
end


local LoadingGui = Instance.new("ScreenGui")
LoadingGui.Name = "_load"
LoadingGui.ResetOnSpawn = false
LoadingGui.Parent = SafeParent

local LoadingFrame = Instance.new("Frame")
LoadingFrame.Size = UDim2.new(0, 400, 0, 240)
LoadingFrame.Position = UDim2.new(0.5, -200, 0.5, -120)
LoadingFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
LoadingFrame.BackgroundTransparency = 1
LoadingFrame.BorderSizePixel = 0
LoadingFrame.ClipsDescendants = true
LoadingFrame.Parent = LoadingGui
Instance.new("UICorner", LoadingFrame).CornerRadius = UDim.new(0, 12)

-- Обводка рамки загрузки
local loadingFrameStroke = Instance.new("UIStroke")
loadingFrameStroke.Color = Settings.AccentColor
loadingFrameStroke.Thickness = 1
loadingFrameStroke.Transparency = 0.6
loadingFrameStroke.Parent = LoadingFrame

local LoadingLogo = Instance.new("TextLabel")
LoadingLogo.Size = UDim2.new(1, 0, 0, 50)
LoadingLogo.Position = UDim2.new(0, 0, 0.15, 0)
LoadingLogo.BackgroundTransparency = 1
LoadingLogo.Text = "BOBRCHEATS"
LoadingLogo.TextColor3 = Settings.AccentColor
LoadingLogo.Font = Enum.Font.GothamBold
LoadingLogo.TextSize = 36
LoadingLogo.Parent = LoadingFrame

-- Глянцевая обводка текста
local logoStroke = Instance.new("UIStroke")
logoStroke.Color = Color3.fromRGB(255, 255, 255)
logoStroke.Thickness = 1
logoStroke.Transparency = 0.5
logoStroke.Parent = LoadingLogo

local LoadingBarBg = Instance.new("Frame")
LoadingBarBg.Size = UDim2.new(0.8, 0, 0, 8)
LoadingBarBg.Position = UDim2.new(0.1, 0, 0.55, 0)
LoadingBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
LoadingBarBg.Parent = LoadingFrame
Instance.new("UICorner", LoadingBarBg).CornerRadius = UDim.new(1, 0)

-- Обводка прогресс-бара
local barStroke = Instance.new("UIStroke")
barStroke.Color = Settings.AccentColor
barStroke.Thickness = 1
barStroke.Transparency = 0.8
barStroke.Parent = LoadingBarBg

local LoadingBarFill = Instance.new("Frame")
LoadingBarFill.Size = UDim2.new(0, 0, 1, 0)
LoadingBarFill.BackgroundColor3 = Settings.AccentColor
LoadingBarFill.Parent = LoadingBarBg
Instance.new("UICorner", LoadingBarFill).CornerRadius = UDim.new(1, 0)

local LoadingPercent = Instance.new("TextLabel")
LoadingPercent.Size = UDim2.new(1, 0, 0, 30)
LoadingPercent.Position = UDim2.new(0, 0, 0.7, 0)
LoadingPercent.BackgroundTransparency = 1
LoadingPercent.Text = "0%"
LoadingPercent.TextColor3 = Color3.fromRGB(200, 200, 200)
LoadingPercent.Font = Enum.Font.Gotham
LoadingPercent.TextSize = 18
LoadingPercent.Parent = LoadingFrame

TweenService:Create(LoadingFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0.2}):Play()

-- главное окно
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "_menu"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = SafeParent
ScreenGui.Enabled = false



-- курсор
local CustomCursor = Instance.new("ImageLabel")
CustomCursor.Name = "BobrCursor"
CustomCursor.Size = UDim2.new(0, 24, 0, 24)
CustomCursor.BackgroundTransparency = 1
CustomCursor.Image = "rbxassetid://1352543873" -- стандартная иконка курсора
CustomCursor.Visible = false
CustomCursor.ZIndex = 999
CustomCursor.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 560, 0, 600)
MainFrame.Position = UDim2.new(0, 30, 0.5, -300)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
MainFrame.BackgroundTransparency = 1
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

-- Пульсирующая рамка
local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Settings.AccentColor
UIStroke.Thickness = 1.5
UIStroke.Parent = MainFrame
coroutine.wrap(function()
    while MainFrame and MainFrame.Parent do
        UIStroke.Thickness = 1.5 + math.sin(tick() * 3) * 0.5
        task.wait(0.05)
    end
end)()

-- Заголовок
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
TitleBar.BorderSizePixel = 0
TitleBar.ClipsDescendants = true
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12)
local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -60, 1, 0)
TitleText.Position = UDim2.new(0, 16, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "bobrcheats v22.8"
TitleText.TextColor3 = Settings.AccentColor
TitleText.Font = Enum.Font.GothamBold
TitleText.TextSize = 18
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = TitleBar
-- кнопки окна
function CreateWindowButton(parent, xOffset, isClose)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 28, 0, 28)
    btn.Position = UDim2.new(1, xOffset, 0, 7)
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    btn.BackgroundTransparency = 0.4
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

    -- Тонкая обводка
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 70, 70)
    stroke.Thickness = 1
    stroke.Transparency = 0.6
    stroke.Parent = btn

    local iconColor = Color3.fromRGB(170, 170, 170)

 
    local bar1, bar2, barMinus
    if isClose then
        bar1 = Instance.new("Frame")
        bar1.Size = UDim2.new(0, 12, 0, 2)
        bar1.AnchorPoint = Vector2.new(0.5, 0.5)
        bar1.Position = UDim2.new(0.5, 0, 0.5, 0)
        bar1.BackgroundColor3 = iconColor
        bar1.BorderSizePixel = 0
        bar1.Rotation = 45
        bar1.Parent = btn
        Instance.new("UICorner", bar1).CornerRadius = UDim.new(1, 0)

        bar2 = Instance.new("Frame")
        bar2.Size = UDim2.new(0, 12, 0, 2)
        bar2.AnchorPoint = Vector2.new(0.5, 0.5)
        bar2.Position = UDim2.new(0.5, 0, 0.5, 0)
        bar2.BackgroundColor3 = iconColor
        bar2.BorderSizePixel = 0
        bar2.Rotation = -45
        bar2.Parent = btn
        Instance.new("UICorner", bar2).CornerRadius = UDim.new(1, 0)
    else
        barMinus = Instance.new("Frame")
        barMinus.Size = UDim2.new(0, 12, 0, 2)
        barMinus.AnchorPoint = Vector2.new(0.5, 0.5)
        barMinus.Position = UDim2.new(0.5, 0, 0.5, 0)
        barMinus.BackgroundColor3 = iconColor
        barMinus.BorderSizePixel = 0
        barMinus.Parent = btn
        Instance.new("UICorner", barMinus).CornerRadius = UDim.new(1, 0)
    end

    -- Цвета при наведении
    local hoverBg    = isClose and Color3.fromRGB(200, 40, 40) or Settings.AccentColor
    local hoverLine  = isClose and Color3.fromRGB(255, 100, 100) or Settings.AccentColor
    local tweenI     = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, tweenI, {BackgroundColor3 = hoverBg, BackgroundTransparency = 0}):Play()
        TweenService:Create(stroke, tweenI, {Color = hoverLine, Transparency = 0}):Play()
        if bar1 then TweenService:Create(bar1, tweenI, {BackgroundColor3 = Color3.fromRGB(255, 255, 255)}):Play() end
        if bar2 then TweenService:Create(bar2, tweenI, {BackgroundColor3 = Color3.fromRGB(255, 255, 255)}):Play() end
        if barMinus then TweenService:Create(barMinus, tweenI, {BackgroundColor3 = Color3.fromRGB(255, 255, 255)}):Play() end
    end)

    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, tweenI, {BackgroundColor3 = Color3.fromRGB(35, 35, 35), BackgroundTransparency = 0.4}):Play()
        TweenService:Create(stroke, tweenI, {Color = Color3.fromRGB(70, 70, 70), Transparency = 0.6}):Play()
        if bar1 then TweenService:Create(bar1, tweenI, {BackgroundColor3 = iconColor}):Play() end
        if bar2 then TweenService:Create(bar2, tweenI, {BackgroundColor3 = iconColor}):Play() end
        if barMinus then TweenService:Create(barMinus, tweenI, {BackgroundColor3 = iconColor}):Play() end
    end)

    return btn
end

local CloseBtn    = CreateWindowButton(TitleBar, -36, true)
local MinimizeBtn = CreateWindowButton(TitleBar, -69, false)


local TabContainer = Instance.new("Frame")
TabContainer.Size = UDim2.new(1, -8, 0, 38)
TabContainer.Position = UDim2.new(0, 4, 0, 46)
TabContainer.BackgroundTransparency = 1
TabContainer.Parent = MainFrame
local TabButtons, TabPages = {}, {}
local TabNames = {"👁 ESP", "🤖 NPC", "🏃 MOVE", "🎯 AIM", "✚ VISUAL", "🔍 ITEMS", "⚡ TP", "👁 SPEC", "⚙ SETTINGS"}
local TabCount = #TabNames
local currentTabIndex = 1

local WarningFrame = Instance.new("Frame")
WarningFrame.Size = UDim2.new(1, -10, 1, -90)
WarningFrame.Position = UDim2.new(0, 5, 0, 85)
WarningFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
WarningFrame.BorderSizePixel = 0
WarningFrame.Visible = false
WarningFrame.ZIndex = 10
WarningFrame.Parent = MainFrame
Instance.new("UICorner", WarningFrame).CornerRadius = UDim.new(0, 8)
local warningTitle = Instance.new("TextLabel") warningTitle.Size=UDim2.new(1,0,0,30) warningTitle.Position=UDim2.new(0,0,0.25,0) warningTitle.BackgroundTransparency=1 warningTitle.Text="" warningTitle.TextColor3=Settings.AccentColor warningTitle.Font=Enum.Font.GothamBold warningTitle.TextSize=18 warningTitle.ZIndex=11 warningTitle.Parent=WarningFrame
local warningMsg = Instance.new("TextLabel") warningMsg.Size=UDim2.new(1,-20,0,50) warningMsg.Position=UDim2.new(0,10,0.4,0) warningMsg.BackgroundTransparency=1 warningMsg.Text="" warningMsg.TextColor3=Color3.fromRGB(200,200,200) warningMsg.Font=Enum.Font.Gotham warningMsg.TextSize=14 warningMsg.TextWrapped=true warningMsg.ZIndex=11 warningMsg.Parent=WarningFrame
local warningYes = Instance.new("TextButton") warningYes.Size=UDim2.new(0,120,0,35) warningYes.Position=UDim2.new(0.5,-140,0.8,0) warningYes.BackgroundColor3=Settings.AccentColor warningYes.Text="Да" warningYes.TextColor3=Color3.fromRGB(255,255,255) warningYes.Font=Enum.Font.GothamBold warningYes.TextSize=16 warningYes.ZIndex=11 warningYes.Parent=WarningFrame
local warningNo = Instance.new("TextButton") warningNo.Size=UDim2.new(0,120,0,35) warningNo.Position=UDim2.new(0.5,20,0.8,0) warningNo.BackgroundColor3=Color3.fromRGB(60,60,60) warningNo.Text="Нет" warningNo.TextColor3=Color3.fromRGB(255,255,255) warningNo.Font=Enum.Font.GothamBold warningNo.TextSize=16 warningNo.ZIndex=11 warningNo.Parent=WarningFrame
Instance.new("UICorner", warningYes).CornerRadius = UDim.new(0, 6)
Instance.new("UICorner", warningNo).CornerRadius = UDim.new(0, 6)
local warningCallbackYes = nil
warningYes.MouseButton1Click:Connect(function()
    WarningFrame.Visible = false
    for i, page in ipairs(TabPages) do page.Visible = (i == currentTabIndex) end
    if warningCallbackYes then warningCallbackYes() end
end)
warningNo.MouseButton1Click:Connect(function()
    WarningFrame.Visible = false
    for i, page in ipairs(TabPages) do page.Visible = (i == currentTabIndex) end
end)
local function ShowTabWarning(title, msg, onYes)
    if Settings.DisableWarnings then
        if onYes then onYes() end
        return
    end
    warningTitle.Text = title
    warningMsg.Text = msg
    WarningFrame.Visible = true
    warningCallbackYes = onYes
    for _, page in ipairs(TabPages) do page.Visible = false end
end



local function SelectTab(idx)
    currentTabIndex = idx
    WarningFrame.Visible = false
    for i, btn in ipairs(TabButtons) do
        local sel = (i == idx)
        TweenService:Create(btn, TweenInfo.new(0.25), {BackgroundColor3=sel and Settings.AccentColor or Color3.fromRGB(30,30,30), TextColor3=sel and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,150)}):Play()
        if TabPages[i] then TabPages[i].Visible = sel end
    end
    if idx == 7 then RefreshTPTab()
    elseif idx == 8 then RefreshSpectateList() end
end

for i, name in ipairs(TabNames) do
    local btn = Instance.new("TextButton") btn.Size=UDim2.new(1/TabCount,-2,1,0) btn.Position=UDim2.new((i-1)/TabCount,1,0,0)
    btn.BackgroundColor3 = (i==1) and Settings.AccentColor or Color3.fromRGB(30,30,30)
    btn.Text=name btn.TextColor3 = (i==1) and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,150)
    btn.Font=Enum.Font.GothamBold btn.TextSize=9 btn.Parent=TabContainer
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local page = Instance.new("ScrollingFrame") page.Size=UDim2.new(1,-8,1,-94) page.Position=UDim2.new(0,4,0,88) page.BackgroundTransparency=1 page.BorderSizePixel=0 page.ScrollBarThickness=3 page.ScrollBarImageColor3=Color3.fromRGB(60,60,60) page.CanvasSize=UDim2.new(0,0,0,0) page.Visible=(i==1) page.ClipsDescendants = true page.Parent=MainFrame
    local layout = Instance.new("UIListLayout") layout.Padding=UDim.new(0,6) layout.Parent=page
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() page.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10) end)
    btn.MouseButton1Click:Connect(function() SelectTab(i) end)
    TabButtons[i]=btn TabPages[i]=page
end

local accent = Settings.AccentColor
local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function CreateSection(parent)
    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.BackgroundColor3 = accent
    sep.BackgroundTransparency = 0.5
    sep.Parent = parent
end

function CreateToggle(parent, text, callback, default, warning)
    local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,30) frame.BackgroundTransparency=1 frame.Parent=parent
    local bg = Instance.new("Frame") bg.Size=UDim2.new(0,38,0,20) bg.Position=UDim2.new(0,6,0,5) bg.BackgroundColor3=default and accent or Color3.fromRGB(50,50,50) bg.Parent=frame
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1,0)
    local knob = Instance.new("Frame") knob.Size=UDim2.new(0,16,0,16) knob.Position=default and UDim2.new(1,-18,0,2) or UDim2.new(0,2,0,2) knob.BackgroundColor3=Color3.fromRGB(255,255,255) knob.Parent=bg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
    local label = Instance.new("TextLabel") label.Size=UDim2.new(1,-52,1,0) label.Position=UDim2.new(0,48,0,0) label.BackgroundTransparency=1 label.Text=text label.TextColor3=Color3.fromRGB(200,200,200) label.Font=Enum.Font.Gotham label.TextSize=13 label.TextXAlignment=Enum.TextXAlignment.Left label.Parent=frame
    local toggled = default
    local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,0,1,0) btn.BackgroundTransparency=1 btn.Text="" btn.Parent=frame
    local function setState(val)
        toggled = val
        TweenService:Create(bg, tweenInfo, {BackgroundColor3=val and accent or Color3.fromRGB(50,50,50)}):Play()
        TweenService:Create(knob, tweenInfo, {Position=val and UDim2.new(1,-18,0,2) or UDim2.new(0,2,0,2)}):Play()
    end
    btn.MouseButton1Click:Connect(function()
        if not toggled and warning and not Settings.DisableWarnings then
            ShowTabWarning("⚠ ВНИМАНИЕ", warning, function() setState(true) callback(true) end)
        else
            setState(not toggled)
            callback(toggled)
        end
    end)

    return { SetState = setState }
end

local ToggleRefs = {}
local openPalette = nil  -- текущая открытая палитра
local openPaletteData = nil

function CreateModeSwitch(parent, text, modes, default, callback)
    local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,48) frame.BackgroundTransparency=1 frame.Parent=parent
    local label = Instance.new("TextLabel") label.Size=UDim2.new(1,0,0,20) label.BackgroundTransparency=1 label.Text=text..": "..default label.TextColor3=Color3.fromRGB(200,200,200) label.Font=Enum.Font.Gotham label.TextSize=13 label.Parent=frame
    local btnsFrame = Instance.new("Frame") btnsFrame.Size=UDim2.new(1,0,0,24) btnsFrame.Position=UDim2.new(0,0,0,24) btnsFrame.BackgroundTransparency=1 btnsFrame.Parent=frame
    local buttons = {}
    for i, mode in ipairs(modes) do
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(0,80,0,24) btn.Position=UDim2.new(0,(i-1)*90,0,0) btn.BackgroundColor3=(mode==default) and accent or Color3.fromRGB(40,40,40) btn.Text=mode btn.TextColor3=Color3.fromRGB(255,255,255) btn.Font=Enum.Font.GothamBold btn.TextSize=12 btn.Parent=btnsFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        buttons[#buttons+1]=btn
        btn.MouseButton1Click:Connect(function()
            for _,b in ipairs(buttons) do TweenService:Create(b,tweenInfo,{BackgroundColor3=(b==btn) and accent or Color3.fromRGB(40,40,40)}):Play() end
            label.Text=text..": "..mode callback(mode)
        end)
    end

    return frame
end

function CreateSlider(parent, text, min, max, default, callback, precision)
    precision = precision or 1
    local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,48) frame.BackgroundTransparency=1 frame.Parent=parent
    local label = Instance.new("TextLabel") label.Size=UDim2.new(1,0,0,20) label.BackgroundTransparency=1 label.Text=text..": "..string.format("%."..precision.."f",default) label.TextColor3=Color3.fromRGB(200,200,200) label.Font=Enum.Font.Gotham label.TextSize=12 label.Parent=frame
    local bar = Instance.new("Frame") bar.Size=UDim2.new(1,-24,0,5) bar.Position=UDim2.new(0,12,0,26) bar.BackgroundColor3=Color3.fromRGB(50,50,50) bar.Parent=frame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)
    local pct = (default-min)/(max-min)
    local fill = Instance.new("Frame") fill.Size=UDim2.new(pct,0,1,0) fill.BackgroundColor3=accent fill.Parent=bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
    local knob = Instance.new("TextButton") knob.Size=UDim2.new(0,14,0,14) knob.Position=UDim2.new(pct,-7,0,-4) knob.BackgroundColor3=Color3.fromRGB(255,255,255) knob.Text="" knob.Parent=bar
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
    local drag = false
    local inputEndedCon, inputChangedCon
    local function updateKnobPos(p)
        local barWidth = bar.AbsoluteSize.X
        local knobHalf = knob.AbsoluteSize.X / 2
        local minP = knobHalf / barWidth
        local maxP = 1 - knobHalf / barWidth
        p = math.clamp(p, minP, maxP)
        fill.Size = UDim2.new(p, 0, 1, 0)
        knob.Position = UDim2.new(p, -knobHalf, 0, -4)
    end
    local function startDrag()
        if drag then return end
        drag = true
        if inputEndedCon then inputEndedCon:Disconnect() end
        if inputChangedCon then inputChangedCon:Disconnect() end
        inputEndedCon = UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = false
                if inputEndedCon then inputEndedCon:Disconnect() end
                if inputChangedCon then inputChangedCon:Disconnect() end
                inputEndedCon, inputChangedCon = nil, nil
            end
        end)
        inputChangedCon = UserInputService.InputChanged:Connect(function(inp)
            if not drag then return end
            if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                drag = false
                if inputEndedCon then inputEndedCon:Disconnect() end
                if inputChangedCon then inputChangedCon:Disconnect() end
                inputEndedCon, inputChangedCon = nil, nil
                return
            end
            if inp.UserInputType == Enum.UserInputType.MouseMovement then
                local mp = UserInputService:GetMouseLocation()
                local bp = bar.AbsolutePosition
                local bs = bar.AbsoluteSize
                local p = math.clamp((mp.X - bp.X) / bs.X, 0, 1)
                local val = min + (max - min) * p
                val = math.floor(val * (10^precision) + 0.5) / (10^precision)
                updateKnobPos(p)
                label.Text = text .. ": " .. string.format("%."..precision.."f", val)
                callback(val)
            end
        end)
    end
        knob.MouseButton1Down:Connect(startDrag)
    bar.InputBegan:Connect(function(inp) if inp.UserInputType == Enum.UserInputType.MouseButton1 then startDrag() end end)

    task.spawn(function()
        task.wait(0.2)  -- небольшая задержка, чтобы AbsoluteSize обновился
        updateKnobPos(pct)
    end)

    return frame
end
function CreateSliderInt(parent, text, min, max, default, callback)
    return CreateSlider(parent, text, min, max, default, callback, 0)
end

-- палитра
function CreateColorPicker(parent, text, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 48)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 20)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.Parent = frame

    local colorBtn = Instance.new("TextButton")
    colorBtn.Size = UDim2.new(0, 36, 0, 24)
    colorBtn.Position = UDim2.new(0, 0, 0, 24)
    colorBtn.BackgroundColor3 = default
    colorBtn.BorderSizePixel = 0
    colorBtn.Text = ""
    colorBtn.AutoButtonColor = false
    colorBtn.Parent = frame
    Instance.new("UICorner", colorBtn).CornerRadius = UDim.new(0, 6)

    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0, 20, 0, 24)
    resetBtn.Position = UDim2.new(0, 42, 0, 24)
    resetBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    resetBtn.Text = "X"
    resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 13
    resetBtn.Parent = frame
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 4)

 -- палитра
    local paletteFrame = Instance.new("Frame")
    paletteFrame.Size = UDim2.new(0, 165, 0, 200)
    paletteFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    paletteFrame.BorderSizePixel = 0
    paletteFrame.Visible = false
    paletteFrame.ZIndex = 100
    paletteFrame.ClipsDescendants = true
    paletteFrame.Parent = ScreenGui
    Instance.new("UICorner", paletteFrame).CornerRadius = UDim.new(0, 8)

    local paletteStroke = Instance.new("UIStroke")
    paletteStroke.Color = Settings.AccentColor
    paletteStroke.Thickness = 1
    paletteStroke.Transparency = 1
    paletteStroke.Parent = paletteFrame

    paletteFrame:SetAttribute("Open", false)

    local swatches = {}

    local colors = {
        Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 80, 0), Color3.fromRGB(255, 160, 0),
        Color3.fromRGB(255, 240, 0), Color3.fromRGB(160, 255, 0), Color3.fromRGB(0, 255, 0),
        Color3.fromRGB(0, 255, 160), Color3.fromRGB(0, 240, 255), Color3.fromRGB(0, 160, 255),
        Color3.fromRGB(0, 0, 255), Color3.fromRGB(160, 0, 255), Color3.fromRGB(255, 0, 240),
        Color3.fromRGB(255, 0, 80), Color3.fromRGB(128, 128, 128), Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(0, 0, 0),
        Color3.fromRGB(64, 0, 0), Color3.fromRGB(0, 64, 0), Color3.fromRGB(0, 0, 64),
        Color3.fromRGB(64, 64, 64),
        Color3.fromRGB(96, 0, 0), Color3.fromRGB(0, 96, 0), Color3.fromRGB(0, 0, 96),
        Color3.fromRGB(96, 96, 96), Color3.fromRGB(32, 32, 32),
        Color3.fromRGB(160, 0, 0), Color3.fromRGB(0, 160, 0), Color3.fromRGB(0, 0, 160),
        Color3.fromRGB(160, 160, 160), Color3.fromRGB(192, 192, 192),
    }

    local btnSize = 36
    local padding = 2
    local cols = 5
    local currentColor = default
    local closeTween = nil
    local openAnimToken = 0

    local function updateColor(col)
        currentColor = col
        colorBtn.BackgroundColor3 = col
        callback(col)
    end

    local function updatePalettePosition()
        local btnAbsPos = colorBtn.AbsolutePosition
        local btnAbsSize = colorBtn.AbsoluteSize
        paletteFrame.Position = UDim2.new(0, btnAbsPos.X + btnAbsSize.X + 5, 0, btnAbsPos.Y)
    end

    local closePalette

    -- Создание цветовых ячеек
    for i, col in ipairs(colors) do
        local row = math.floor((i-1) / cols)
        local colIdx = (i-1) % cols

        local colorSwatch = Instance.new("TextButton")
        colorSwatch:SetAttribute("Swatch", true)
        colorSwatch.AnchorPoint = Vector2.new(0.5, 0.5)
        colorSwatch.Size = UDim2.new(0, 0, 0, 0)
        colorSwatch.Position = UDim2.new(
            0, padding + colIdx * (btnSize + padding) + btnSize/2,
            0, padding + row * (btnSize + padding) + btnSize/2
        )
        colorSwatch.BackgroundColor3 = col
        colorSwatch.BackgroundTransparency = 1
        colorSwatch.BorderSizePixel = 0
        colorSwatch.Text = ""
        colorSwatch.AutoButtonColor = false
        colorSwatch.ZIndex = 101
        colorSwatch.Parent = paletteFrame
        Instance.new("UICorner", colorSwatch).CornerRadius = UDim.new(0, 4)

        table.insert(swatches, colorSwatch)

        colorSwatch.MouseButton1Click:Connect(function()
            updateColor(col)
            closePalette(paletteFrame)
        end)
    end

    closePalette = function(pal)
        if not pal or not pal.Parent then return end
        if not pal:GetAttribute("Open") then return end
        pal:SetAttribute("Open", false)

        if closeTween then closeTween:Cancel(); closeTween = nil end
        openAnimToken = openAnimToken + 1
        local myToken = openAnimToken

        local palSwatches = {}
        for _, d in ipairs(pal:GetDescendants()) do
            if d:IsA("TextButton") and d:GetAttribute("Swatch") then
                table.insert(palSwatches, d)
            end
        end

        for i = #palSwatches, 1, -1 do
            local sw = palSwatches[i]
            TweenService:Create(sw, TweenInfo.new(0.13, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                Size = UDim2.new(0, 0, 0, 0),
                BackgroundTransparency = 1
            }):Play()
        end

        local stroke = pal:FindFirstChildOfClass("UIStroke")
        if stroke then
            TweenService:Create(stroke, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                Transparency = 1
            }):Play()
        end

        task.delay(0.1, function()
            if not pal or not pal.Parent then return end
            if openAnimToken ~= myToken then return end
            if pal:GetAttribute("Open") then return end
            closeTween = TweenService:Create(pal, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 165, 0, 200)
            })
            closeTween:Play()
            closeTween.Completed:Connect(function()
                if not pal or not pal.Parent then return end
                if openAnimToken ~= myToken then return end
                if pal:GetAttribute("Open") then return end
                pal.Visible = false
                if openPalette == pal then
                    openPalette = nil
                    openPaletteData = nil
                end
            end)
        end)
    end

-- клик по кнопке цвета
    colorBtn.MouseButton1Click:Connect(function()
        if paletteFrame:GetAttribute("Open") == true then
            -- Повторный клик по этой же кнопке — запускаем полную анимацию закрытия
            closePalette(paletteFrame)
        else
            -- Мгновенно скрываем другую открытую палитру, чтобы не оставалось серого фона
            if openPalette and openPalette ~= paletteFrame and openPalette.Parent then
                local prev = openPalette
                prev:SetAttribute("Open", false)
                prev.Visible = false
            end

            openPalette = paletteFrame
            openPaletteData = { palette = paletteFrame, button = colorBtn }
            paletteFrame:SetAttribute("Open", true)
            paletteFrame.Visible = true
            updatePalettePosition()

            openAnimToken = openAnimToken + 1
            local myToken = openAnimToken
            if closeTween then closeTween:Cancel(); closeTween = nil end

            -- Сброс в стартовое состояние
            paletteFrame.BackgroundTransparency = 1
            paletteFrame.Size = UDim2.new(0, 165, 0, 200)
            paletteStroke.Transparency = 1
            for _, sw in ipairs(swatches) do
                sw.Size = UDim2.new(0, 0, 0, 0)
                sw.BackgroundTransparency = 1
            end

            TweenService:Create(paletteFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                BackgroundTransparency = 0,
                Size = UDim2.new(0, 198, 0, 236)
            }):Play()


            TweenService:Create(paletteStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Transparency = 0.55
            }):Play()

            task.spawn(function()
                for _, sw in ipairs(swatches) do
                    if myToken ~= openAnimToken or not paletteFrame.Visible then return end
                    task.wait(0.01)
                    TweenService:Create(sw, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                        Size = UDim2.new(0, btnSize, 0, btnSize),
                        BackgroundTransparency = 0
                    }):Play()
                end
            end)
        end
    end)

    resetBtn.MouseButton1Click:Connect(function()
        updateColor(default)
    end)

   
    local function tryHidePalette()
        if paletteFrame:GetAttribute("Open") then
            closePalette(paletteFrame)
        end
    end

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and paletteFrame:GetAttribute("Open") then
            local mousePos = UserInputService:GetMouseLocation()
            local absPos = paletteFrame.AbsolutePosition
            local absSize = paletteFrame.AbsoluteSize
            local btnPos = colorBtn.AbsolutePosition
            local btnSizeAbs = colorBtn.AbsoluteSize
            if (mousePos.X < absPos.X or mousePos.X > absPos.X + absSize.X or
                mousePos.Y < absPos.Y or mousePos.Y > absPos.Y + absSize.Y) and
               not (mousePos.X >= btnPos.X and mousePos.X <= btnPos.X + btnSizeAbs.X and
                    mousePos.Y >= btnPos.Y and mousePos.Y <= btnPos.Y + btnSizeAbs.Y) then
                tryHidePalette()
            end
        end
    end)

    return frame
end

function CreateKeyBind(parent, name, actionKey)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 120, 1, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local keyBtn = Instance.new("TextButton")
    keyBtn.Size = UDim2.new(0, 150, 1, 0)
    keyBtn.Position = UDim2.new(0, 130, 0, 0)
    keyBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    keyBtn.Text = Settings.KeyBinds[actionKey] and Settings.KeyBinds[actionKey].Name or "..."
    keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    keyBtn.Font = Enum.Font.Gotham
    keyBtn.TextSize = 13
    keyBtn.Parent = frame
    Instance.new("UICorner", keyBtn).CornerRadius = UDim.new(0, 4)

    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0, 20, 1, 0)
    clearBtn.Position = UDim2.new(0, 285, 0, 0) 
    clearBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    clearBtn.Text = "X"
    clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.TextSize = 13
    clearBtn.Parent = frame
    Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 4)

    local binding = false
    local con

    keyBtn.MouseButton1Click:Connect(function()
        if binding then return end
        binding = true
        keyBtn.Text = "..."

        con = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                Settings.KeyBinds[actionKey] = input.KeyCode
                keyBtn.Text = input.KeyCode.Name
                con:Disconnect()
                binding = false
            elseif input.UserInputType == Enum.UserInputType.MouseButton1 or
                   input.UserInputType == Enum.UserInputType.MouseButton2 or
                   input.UserInputType == Enum.UserInputType.MouseButton3 then
                Settings.KeyBinds[actionKey] = input.UserInputType
                keyBtn.Text = input.UserInputType.Name
                con:Disconnect()
                binding = false
            end
        end)
    end)

    clearBtn.MouseButton1Click:Connect(function()
        Settings.KeyBinds[actionKey] = nil
        keyBtn.Text = "..."
        if binding then
            binding = false
            if con then con:Disconnect() end
        end
    end)

    return frame
end

-- панель настроек
SettingsPanelUI = {
    Panel = nil, Stroke = nil, Scale = nil, Title = nil,
    Close = nil, Sep = nil, Content = nil, Layout = nil,
    Open = false, CurrentBtn = nil, AnimToken = 0,
}

SettingsPanelUI.Panel = Instance.new("Frame")
SettingsPanelUI.Panel.Name = "SettingsPanel"
SettingsPanelUI.Panel.Size = UDim2.new(1, -10, 1, -90)
SettingsPanelUI.Panel.Position = UDim2.new(0, 5, 0, 85)
SettingsPanelUI.Panel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
SettingsPanelUI.Panel.BackgroundTransparency = 1
SettingsPanelUI.Panel.BorderSizePixel = 0
SettingsPanelUI.Panel.Visible = false
SettingsPanelUI.Panel.ZIndex = 20
SettingsPanelUI.Panel.ClipsDescendants = true
SettingsPanelUI.Panel.Parent = MainFrame
Instance.new("UICorner", SettingsPanelUI.Panel).CornerRadius = UDim.new(0, 8)

SettingsPanelUI.Stroke = Instance.new("UIStroke")
SettingsPanelUI.Stroke.Color = accent
SettingsPanelUI.Stroke.Thickness = 1
SettingsPanelUI.Stroke.Transparency = 1
SettingsPanelUI.Stroke.Parent = SettingsPanelUI.Panel

SettingsPanelUI.Scale = Instance.new("UIScale")
SettingsPanelUI.Scale.Scale = 1
SettingsPanelUI.Scale.Parent = SettingsPanelUI.Panel

SettingsPanelUI.Title = Instance.new("TextLabel")
SettingsPanelUI.Title.Size = UDim2.new(1, -50, 0, 32)
SettingsPanelUI.Title.Position = UDim2.new(0, 12, 0, 0)
SettingsPanelUI.Title.BackgroundTransparency = 1
SettingsPanelUI.Title.Text = ""
SettingsPanelUI.Title.TextColor3 = accent
SettingsPanelUI.Title.Font = Enum.Font.GothamBold
SettingsPanelUI.Title.TextSize = 16
SettingsPanelUI.Title.TextXAlignment = Enum.TextXAlignment.Left
SettingsPanelUI.Title.ZIndex = 21
SettingsPanelUI.Title.Parent = SettingsPanelUI.Panel

SettingsPanelUI.Close = Instance.new("TextButton")
SettingsPanelUI.Close.Size = UDim2.new(0, 26, 0, 26)
SettingsPanelUI.Close.Position = UDim2.new(1, -32, 0, 3)
SettingsPanelUI.Close.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
SettingsPanelUI.Close.Text = "X"
SettingsPanelUI.Close.TextColor3 = Color3.fromRGB(255, 255, 255)
SettingsPanelUI.Close.Font = Enum.Font.GothamBold
SettingsPanelUI.Close.TextSize = 14
SettingsPanelUI.Close.ZIndex = 21
SettingsPanelUI.Close.Parent = SettingsPanelUI.Panel
Instance.new("UICorner", SettingsPanelUI.Close).CornerRadius = UDim.new(0, 4)

SettingsPanelUI.Sep = Instance.new("Frame")
SettingsPanelUI.Sep.Size = UDim2.new(1, -20, 0, 1)
SettingsPanelUI.Sep.Position = UDim2.new(0, 10, 0, 32)
SettingsPanelUI.Sep.BackgroundColor3 = accent
SettingsPanelUI.Sep.BackgroundTransparency = 0.5
SettingsPanelUI.Sep.BorderSizePixel = 0
SettingsPanelUI.Sep.ZIndex = 21
SettingsPanelUI.Sep.Parent = SettingsPanelUI.Panel

SettingsPanelUI.Content = Instance.new("ScrollingFrame")
SettingsPanelUI.Content.Size = UDim2.new(1, -16, 1, -42)
SettingsPanelUI.Content.Position = UDim2.new(0, 8, 0, 38)
SettingsPanelUI.Content.BackgroundTransparency = 1
SettingsPanelUI.Content.BorderSizePixel = 0
SettingsPanelUI.Content.ScrollBarThickness = 3
SettingsPanelUI.Content.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
SettingsPanelUI.Content.CanvasSize = UDim2.new(0, 0, 0, 0)
SettingsPanelUI.Content.ZIndex = 21
SettingsPanelUI.Content.Parent = SettingsPanelUI.Panel

SettingsPanelUI.Layout = Instance.new("UIListLayout")
SettingsPanelUI.Layout.Padding = UDim.new(0, 6)
SettingsPanelUI.Layout.Parent = SettingsPanelUI.Content
SettingsPanelUI.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    SettingsPanelUI.Content.CanvasSize = UDim2.new(0, 0, 0, SettingsPanelUI.Layout.AbsoluteContentSize.Y + 10)
end)

function ResetGearAppearance(btn)
    if not btn then return end
    local stroke = btn:FindFirstChildOfClass("UIStroke")
    TweenService:Create(btn, tweenInfo, {BackgroundColor3 = Color3.fromRGB(35,35,35), BackgroundTransparency = 0.4, TextColor3 = Color3.fromRGB(170,170,170)}):Play()
    if stroke then TweenService:Create(stroke, tweenInfo, {Color = Color3.fromRGB(70,70,70), Transparency = 0.6}):Play() end
end

function HighlightGear(btn)
    if not btn then return end
    local stroke = btn:FindFirstChildOfClass("UIStroke")
    TweenService:Create(btn, tweenInfo, {BackgroundColor3 = accent, BackgroundTransparency = 0, TextColor3 = Color3.fromRGB(255,255,255)}):Play()
    if stroke then TweenService:Create(stroke, tweenInfo, {Color = accent, Transparency = 0}):Play() end
end

function ClosePanel()
    if not SettingsPanelUI.Open then return end
    SettingsPanelUI.Open = false
    SettingsPanelUI.AnimToken = SettingsPanelUI.AnimToken + 1
    local myToken = SettingsPanelUI.AnimToken

    TweenService:Create(SettingsPanelUI.Panel, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
    TweenService:Create(SettingsPanelUI.Stroke, TweenInfo.new(0.18), {Transparency = 1}):Play()
    TweenService:Create(SettingsPanelUI.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Scale = 0.85}):Play()

    for _, d in ipairs(SettingsPanelUI.Content:GetDescendants()) do
        if d:IsA("GuiObject") then
            pcall(function() TweenService:Create(d, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play() end)
        end
    end

    if SettingsPanelUI.CurrentBtn then
        ResetGearAppearance(SettingsPanelUI.CurrentBtn)
        SettingsPanelUI.CurrentBtn = nil
    end

        task.delay(0.2, function()
            if SettingsPanelUI.AnimToken ~= myToken then return end
            if SettingsPanelUI.Open then return end
            SettingsPanelUI.Panel.Visible = false
            for _, child in ipairs(SettingsPanelUI.Content:GetChildren()) do
                if not child:IsA("UIListLayout") then child:Destroy() end
            end
            if TabPages[currentTabIndex] then
                TabPages[currentTabIndex].Visible = true
            end
        end)
    end

function OpenPanel(gearBtn, title, buildFn)
    ClosePanel()
    for _, child in ipairs(SettingsPanelUI.Content:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end

    if TabPages[currentTabIndex] then
        TabPages[currentTabIndex].Visible = false
    end

    SettingsPanelUI.Title.Text = title
    SettingsPanelUI.Panel.Visible = true
    SettingsPanelUI.Panel.BackgroundTransparency = 1
    SettingsPanelUI.Stroke.Transparency = 1
    SettingsPanelUI.Scale.Scale = 0.85

    buildFn(SettingsPanelUI.Content)

    for _, d in ipairs(SettingsPanelUI.Content:GetDescendants()) do
        if d:IsA("GuiObject") then
            d.ZIndex = (d.ZIndex or 1) + 30
        end
    end

    SettingsPanelUI.Open = true
    SettingsPanelUI.CurrentBtn = gearBtn
    SettingsPanelUI.AnimToken = SettingsPanelUI.AnimToken + 1

    TweenService:Create(SettingsPanelUI.Panel, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
    TweenService:Create(SettingsPanelUI.Stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Transparency = 0.5}):Play()
    TweenService:Create(SettingsPanelUI.Scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

    HighlightGear(gearBtn)
end

SettingsPanelUI.Close.MouseButton1Click:Connect(ClosePanel)

function CreateFunctionRow(parent, text, defaultVal, onToggle, buildFn, warning)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 38, 0, 20)
    bg.Position = UDim2.new(0, 6, 0, 5)
    bg.BackgroundColor3 = defaultVal and accent or Color3.fromRGB(50, 50, 50)
    bg.Parent = frame
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = defaultVal and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = bg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local labelOffset = buildFn and 100 or 52
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -labelOffset, 1, 0)
    label.Position = UDim2.new(0, 48, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, -labelOffset, 1, 0)
    toggleBtn.BackgroundTransparency = 1
    toggleBtn.Text = ""
    toggleBtn.Parent = frame

    local toggled = defaultVal
    local function setState(val)
        toggled = val
        TweenService:Create(bg, tweenInfo, {BackgroundColor3 = val and accent or Color3.fromRGB(50, 50, 50)}):Play()
        TweenService:Create(knob, tweenInfo, {Position = val and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)}):Play()
    end

    toggleBtn.MouseButton1Click:Connect(function()
        if not toggled and warning and not Settings.DisableWarnings then
            ShowTabWarning("⚠ ВНИМАНИЕ", warning, function() setState(true) onToggle(true) end)
        else
            setState(not toggled)
            onToggle(toggled)
        end
    end)

    local gearBtn = nil
    if buildFn then
        gearBtn = Instance.new("TextButton")
        gearBtn.Size = UDim2.new(0, 22, 0, 22)
        gearBtn.Position = UDim2.new(1, -26, 0, 4)
        gearBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        gearBtn.BackgroundTransparency = 0.4
        gearBtn.Text = "⚙"
        gearBtn.TextColor3 = Color3.fromRGB(170, 170, 170)
        gearBtn.Font = Enum.Font.GothamBold
        gearBtn.TextSize = 14
        gearBtn.AutoButtonColor = false
        gearBtn.Parent = frame
        Instance.new("UICorner", gearBtn).CornerRadius = UDim.new(1, 0)

        local gearStroke = Instance.new("UIStroke")
        gearStroke.Color = Color3.fromRGB(70, 70, 70)
        gearStroke.Thickness = 1
        gearStroke.Transparency = 0.6
        gearStroke.Parent = gearBtn

        gearBtn.MouseEnter:Connect(function()
            if SettingsPanelUI.CurrentBtn == gearBtn then return end
            HighlightGear(gearBtn)
        end)
        gearBtn.MouseLeave:Connect(function()
            if SettingsPanelUI.CurrentBtn == gearBtn then return end
            ResetGearAppearance(gearBtn)
        end)

        gearBtn.MouseButton1Click:Connect(function()
            if SettingsPanelUI.CurrentBtn == gearBtn and SettingsPanelUI.Open then
                ClosePanel()
            else
                OpenPanel(gearBtn, text, buildFn)
            end
        end)
    end

    return { SetState = setState, gearBtn = gearBtn }
end

local ButtonSetColors = setmetatable({}, {__mode = "k"})

function CreateButton(parent, text, onClick, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = color or Color3.fromRGB(40, 40, 40)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local baseColor = color or Color3.fromRGB(40, 40, 40)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, tweenInfo, {BackgroundColor3 = baseColor:Lerp(Color3.new(1,1,1), 0.15)}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, tweenInfo, {BackgroundColor3 = baseColor}):Play()
    end)
    btn.MouseButton1Click:Connect(onClick)

    ButtonSetColors[btn] = function(c)
        baseColor = c
        btn.BackgroundColor3 = c
    end

    return btn
end
-- цвет по команде

function GetTeamButtonColor(plr)
    if not Settings.TP_TeamColorButtons then
        return Color3.fromRGB(40, 40, 40), Color3.fromRGB(255, 255, 255)
    end
    if not plr or not plr.TeamColor then
        return Color3.fromRGB(40, 40, 40), Color3.fromRGB(255, 255, 255)
    end
    local c = plr.TeamColor.Color
    local r, g, b = math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255)
    if math.abs(r - g) < 20 and math.abs(g - b) < 20 and math.abs(r - b) < 20 then
        return Color3.fromRGB(40, 40, 40), Color3.fromRGB(255, 255, 255)
    end
    local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
    if lum > 0.55 then
        return c, Color3.fromRGB(20, 20, 20)
    end
    return c, Color3.fromRGB(255, 255, 255)
end

-- обёртки для локализации
local _CreateToggle = CreateToggle
CreateToggle = function(parent, text, cb, default, warning)
    return _CreateToggle(parent, Locales.t(text), cb, default,
        warning and Locales.t(warning) or nil)
end

local _CreateFunctionRow = CreateFunctionRow
CreateFunctionRow = function(parent, text, defaultVal, onToggle, buildFn, warning)
    return _CreateFunctionRow(parent, Locales.t(text), defaultVal, onToggle,
        buildFn, warning and Locales.t(warning) or nil)
end

local _CreateButton = CreateButton
CreateButton = function(parent, text, onClick, color)
    return _CreateButton(parent, Locales.t(text), onClick, color)
end

local _CreateSlider = CreateSlider
CreateSlider = function(parent, text, min, max, default, cb, precision)
    return _CreateSlider(parent, Locales.t(text), min, max, default, cb, precision)
end

local _CreateSliderInt = CreateSliderInt
CreateSliderInt = function(parent, text, min, max, default, cb)
    return _CreateSliderInt(parent, Locales.t(text), min, max, default, cb)
end

local _CreateModeSwitch = CreateModeSwitch
CreateModeSwitch = function(parent, text, modes, default, cb)
    return _CreateModeSwitch(parent, Locales.t(text), modes, default, cb)
end

local _CreateKeyBind = CreateKeyBind
CreateKeyBind = function(parent, name, actionKey)
    return _CreateKeyBind(parent, Locales.t(name), actionKey)
end

local _CreateColorPicker = CreateColorPicker
CreateColorPicker = function(parent, text, default, cb)
    return _CreateColorPicker(parent, Locales.t(text), default, cb)
end

local _ShowTabWarning = ShowTabWarning
ShowTabWarning = function(title, msg, onYes)
    return _ShowTabWarning(Locales.t(title), Locales.t(msg), onYes)
end

-- вкладки

local espPage = TabPages[1]
CreateSection(espPage)

ToggleRefs.ESP_Enabled = CreateFunctionRow(espPage, "ESP Вкл/Выкл", Settings.ESP_Enabled,
    function(v) Settings.ESP_Enabled = v end,
    function(panel)
        CreateSection(panel)
        CreateColorPicker(panel, "Цвет рамок", Settings.ESP_BoxColor, function(c) Settings.ESP_BoxColor=c end)
        CreateColorPicker(panel, "Цвет линий", Settings.ESP_TracerColor, function(c) Settings.ESP_TracerColor=c end)
        CreateColorPicker(panel, "Цвет имён", Settings.ESP_NameColor, function(c) Settings.ESP_NameColor=c end)
        CreateColorPicker(panel, "Цвет дистанции", Settings.ESP_DistanceColor, function(c) Settings.ESP_DistanceColor=c end)
        CreateSection(panel)
        CreateSliderInt(panel, "Толщина рамок", 1, 5, Settings.ESP_BoxThickness, function(v) Settings.ESP_BoxThickness=v end)
        CreateSliderInt(panel, "Толщина линий", 1, 3, Settings.ESP_TracerThickness, function(v) Settings.ESP_TracerThickness=v end)
        CreateSliderInt(panel, "Размер имён", 10, 20, Settings.ESP_NameSize, function(v) Settings.ESP_NameSize=v end)
        CreateSliderInt(panel, "Ширина HP Bar", 1, 10, Settings.ESP_HealthBarWidth, function(v) Settings.ESP_HealthBarWidth=v end)
        CreateSliderInt(panel, "Отступ HP Bar", 0, 10, Settings.ESP_HealthBarOffset, function(v) Settings.ESP_HealthBarOffset=v end)
        CreateSliderInt(panel, "Размер HP Text", 10, 20, Settings.ESP_HealthTextSize, function(v) Settings.ESP_HealthTextSize=v end)
        CreateSliderInt(panel, "Размер дистанции", 10, 20, Settings.ESP_DistanceSize, function(v) Settings.ESP_DistanceSize=v end)
        CreateSection(panel)
        CreateToggle(panel, "Skeleton ESP", function(v) Settings.ESP_Skeleton = v end, Settings.ESP_Skeleton)
        CreateSlider(panel, "Толщина скелета", 0.5, 4, Settings.ESP_SkeletonThickness, function(v) Settings.ESP_SkeletonThickness = v end, 1)
        CreateColorPicker(panel, "Цвет скелета", Settings.ESP_SkeletonColor, function(c) Settings.ESP_SkeletonColor = c end)
        CreateSection(panel)
        CreateToggle(panel, "Ограничить дистанцию ESP", function(v) Settings.ESP_LimitDistance = v end, Settings.ESP_LimitDistance)
        CreateSliderInt(panel, "Макс. дистанция (m)", 100, 10000, Settings.ESP_MaxDistance, function(v) Settings.ESP_MaxDistance=v end)
    end)

CreateToggle(espPage, "Только враги", function(v) Settings.ESP_TeamCheck=v end, Settings.ESP_TeamCheck)
CreateToggle(espPage, "Рамки", function(v) Settings.ESP_Boxes=v end, Settings.ESP_Boxes)
CreateToggle(espPage, "Линии", function(v) Settings.ESP_Tracers=v end, Settings.ESP_Tracers)
CreateToggle(espPage, "Имена", function(v) Settings.ESP_Names=v end, Settings.ESP_Names)
CreateModeSwitch(espPage, "Здоровье", {"Bar","Text","Off"}, Settings.ESP_HealthMode, function(v) Settings.ESP_HealthMode=v end)
CreateToggle(espPage, "Дистанция", function(v) Settings.ESP_Distance=v end, Settings.ESP_Distance)
CreateToggle(espPage, "Проверка видимости", function(v) Settings.ESP_VisibilityCheck=v end, Settings.ESP_VisibilityCheck)
CreateToggle(espPage, "Цвета команд", function(v) Settings.ESP_TeamColors=v end, Settings.ESP_TeamColors)

CreateSection(espPage)

CreateToggle(espPage, "Chams", function(v) Settings.ESP_Chams=v; UpdateChams() end, Settings.ESP_Chams)
CreateSliderInt(espPage, "Яркость Chams", 0, 100, Settings.ESP_ChamsBrightness, function(v) Settings.ESP_ChamsBrightness=v; UpdateChamsBrightness() end)

CreateSection(espPage)

CreateFunctionRow(espPage, "Trails (путь)", Settings.ESP_Trails,
    function(v) Settings.ESP_Trails=v end,
    function(panel)
        CreateSliderInt(panel, "Толщина линии", 1, 5, Settings.ESP_TrailThickness, function(v) Settings.ESP_TrailThickness=v end)
        CreateSliderInt(panel, "Макс. точек", 20, 500, Settings.ESP_TrailMaxPoints, function(v) Settings.ESP_TrailMaxPoints=v end)
    end)

local npcPage = TabPages[2]
CreateSection(npcPage)

CreateFunctionRow(npcPage, "ESP на NPC", Settings.ESP_NPCs,
    function(v) Settings.ESP_NPCs = v end,
    function(panel)
        CreateSection(panel)
        CreateColorPicker(panel, "Цвет рамок", Settings.NPC_BoxColor, function(c) Settings.NPC_BoxColor=c end)
        CreateColorPicker(panel, "Цвет имён", Settings.NPC_NameColor, function(c) Settings.NPC_NameColor=c end)
        CreateColorPicker(panel, "Цвет линий", Settings.NPC_TracerColor, function(c) Settings.NPC_TracerColor=c end)
        CreateSection(panel)
        CreateToggle(panel, "Свои размеры для NPC", function(v) Settings.ESP_NPC_CustomSizes = v end, Settings.ESP_NPC_CustomSizes)
        CreateSliderInt(panel, "Толщина рамок", 1, 5, Settings.ESP_NPC_BoxThickness, function(v) Settings.ESP_NPC_BoxThickness=v end)
        CreateSliderInt(panel, "Размер имён", 10, 20, Settings.ESP_NPC_NameSize, function(v) Settings.ESP_NPC_NameSize=v end)
        CreateSliderInt(panel, "Ширина HP Bar", 1, 10, Settings.ESP_NPC_HealthBarWidth, function(v) Settings.ESP_NPC_HealthBarWidth=v end)
        CreateSliderInt(panel, "Отступ HP Bar", 0, 10, Settings.ESP_NPC_HealthBarOffset, function(v) Settings.ESP_NPC_HealthBarOffset=v end)
        CreateSliderInt(panel, "Размер HP Text", 10, 20, Settings.ESP_NPC_HealthTextSize, function(v) Settings.ESP_NPC_HealthTextSize=v end)
        CreateSliderInt(panel, "Размер дистанции", 10, 20, Settings.ESP_NPC_DistanceSize, function(v) Settings.ESP_NPC_DistanceSize=v end)
    end)

-- Главные тумблеры NPC на вкладке
CreateToggle(npcPage, "Имена NPC", function(v) Settings.ESP_NPC_Names=v end, Settings.ESP_NPC_Names)
CreateModeSwitch(npcPage, "Здоровье NPC", {"Bar","Text","Off"}, Settings.ESP_NPC_HealthMode, function(v) Settings.ESP_NPC_HealthMode=v end)
CreateToggle(npcPage, "Линии к NPC", function(v) Settings.ESP_NPC_Tracers=v end, Settings.ESP_NPC_Tracers)
CreateToggle(npcPage, "Дистанция NPC", function(v) Settings.ESP_NPC_Distance=v end, Settings.ESP_NPC_Distance)
CreateSliderInt(npcPage, "Макс. дистанция", 100, 1000, Settings.ESP_NPC_MaxDistance, function(v) Settings.ESP_NPC_MaxDistance=v end)

CreateSection(npcPage)

CreateToggle(npcPage, "Chams NPC", function(v) Settings.ESP_NPC_Chams=v; UpdateNpcChams() end, Settings.ESP_NPC_Chams)
CreateSliderInt(npcPage, "Яркость Chams NPC", 0, 100, Settings.ESP_NPC_ChamsBrightness, function(v) Settings.ESP_NPC_ChamsBrightness=v; UpdateNpcChamsBrightness() end)

CreateSection(npcPage)

CreateFunctionRow(npcPage, "Trails (путь)", Settings.ESP_NPC_Trails,
    function(v) Settings.ESP_NPC_Trails=v end,
    function(panel)
        CreateSliderInt(panel, "Толщина линии", 1, 5, Settings.ESP_TrailThickness, function(v) Settings.ESP_TrailThickness=v end)
        CreateSliderInt(panel, "Макс. точек", 20, 500, Settings.ESP_NPC_TrailMaxPoints, function(v) Settings.ESP_NPC_TrailMaxPoints=v end)
    end)

local movePage = TabPages[3]
CreateSection(movePage)
ToggleRefs.Speed = CreateToggle(movePage, "Speed Hack", function(v) Settings.Speed_Enabled=v; UpdateSpeed() end, Settings.Speed_Enabled, "Speed Hack может вызвать кик или бан. Включить?")
CreateSliderInt(movePage, "Скорость бега", 16, 1000, Settings.Speed_Value, function(v) Settings.Speed_Value=v; if Settings.Speed_Enabled then UpdateSpeed() end end)
ToggleRefs.Flight = CreateToggle(movePage, "Flight", function(v) Settings.Flight_Enabled=v UpdateFlight() end, Settings.Flight_Enabled, "Полёт может быть обнаружен античитом. Включить?")
CreateSliderInt(movePage, "Скорость полёта", 10, 1000, Settings.Flight_Speed, function(v) Settings.Flight_Speed=v end)
ToggleRefs.Noclip = CreateToggle(movePage, "Noclip", function(v) Settings.Noclip_Enabled=v UpdateNoclip() end, Settings.Noclip_Enabled, "Noclip может вызвать кик или бан. Включить?")
CreateToggle(movePage, "God Mode", function(v) Settings.GodMode_Enabled=v UpdateGodMode() end, Settings.GodMode_Enabled, "God Mode может вызвать кик. Включить?")
CreateSection(movePage)
CreateFunctionRow(movePage, "Anti-AFK", Settings.AntiAFK_Enabled,
    function(v) Settings.AntiAFK_Enabled=v; UpdateAntiAFK() end,
    function(panel)
        CreateSliderInt(panel, "Интервал (сек)", 5, 120, Settings.AntiAFK_Interval, function(v) Settings.AntiAFK_Interval = v end)
        CreateSlider(panel, "Длит. шага (сек)", 0.1, 1.0, Settings.AntiAFK_StepDuration, function(v) Settings.AntiAFK_StepDuration = v end, 3)
    end)

ToggleRefs.SmartAntiAFK = CreateFunctionRow(movePage, "Smart Anti-AFK", Settings.SmartAntiAFK_Enabled,
    function(v) Settings.SmartAntiAFK_Enabled=v; UpdateSmartAntiAFK() end,
    function(panel)
        CreateSection(panel)
        CreateSliderInt(panel, "Бездействие до включения (сек)", 5, 600, Settings.SmartAntiAFK_IdleTime,
            function(v) Settings.SmartAntiAFK_IdleTime = v end)
        CreateSection(panel)
        CreateToggle(panel, "Считать за активность: клики мыши",
            function(v) Settings.SmartAntiAFK_TrackMouse = v end, Settings.SmartAntiAFK_TrackMouse)
        CreateToggle(panel, "Считать за активность: клавиатура",
            function(v) Settings.SmartAntiAFK_TrackKeyboard = v end, Settings.SmartAntiAFK_TrackKeyboard)
        CreateToggle(panel, "Считать за активность: движение мыши",
            function(v) Settings.SmartAntiAFK_TrackMouseMove = v end, Settings.SmartAntiAFK_TrackMouseMove)
    end)

CreateSection(movePage)
ToggleRefs.BHop = CreateToggle(movePage, "BHop (Bunny Hop)", function(v)
    Settings.BHop_Enabled = v
end, Settings.BHop_Enabled, "BHop может быть обнаружен античитом. Включить?")
CreateSlider(movePage, "Задержка прыжка", 0.0, 0.5, Settings.BHop_Delay, function(v) Settings.BHop_Delay = v end, 3)

CreateSection(movePage)
ToggleRefs.AutoClicker = CreateFunctionRow(movePage, "Auto Clicker", Settings.AutoClicker_Enabled,
    function(v) SetAutoClickerEnabled(v) end,
    function(panel)
        CreateSection(panel)
        CreateSlider(panel, "Задержка между кликами", 0.01, 1.0, Settings.AutoClicker_Delay, function(v)
            Settings.AutoClicker_Delay = v
            if Settings.AutoClicker_HoldDuration > v then
                Settings.AutoClicker_HoldDuration = v
            end
        end, 3)
        CreateSlider(panel, "Время нажатия", 0.01, 0.5, Settings.AutoClicker_HoldDuration, function(v)
            if v > Settings.AutoClicker_Delay then v = Settings.AutoClicker_Delay end
            Settings.AutoClicker_HoldDuration = v
        end, 3)
    end)

CreateSection(movePage)
ToggleRefs.CursorUnlock = CreateToggle(movePage, "Разблокировать курсор", function(v)
    Settings.CursorUnlock_Enabled = v
    if v then
        if not savedMouseBehavior then savedMouseBehavior = UserInputService.MouseBehavior end
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        CustomCursor.Visible = true
    else
        if savedMouseBehavior then pcall(function() UserInputService.MouseBehavior = savedMouseBehavior end) savedMouseBehavior = nil end
        CustomCursor.Visible = false
    end
end, Settings.CursorUnlock_Enabled)

CreateSection(movePage)
CreateToggle(movePage, "Freeze Character", function(v) Settings.Freeze_Enabled=v UpdateFreeze() end, Settings.Freeze_Enabled)
CreateSection(movePage)
CreateToggle(movePage, "Изменить гравитацию", function(v) Settings.Gravity_Enabled=v UpdateGravity() end, Settings.Gravity_Enabled)
CreateSlider(movePage, "Значение", 0, 500, Settings.Gravity_Value, function(v) Settings.Gravity_Value=v UpdateGravity() end, 1)
CreateSection(movePage)
ToggleRefs.ClickTP = CreateToggle(movePage, "Click TP (телепорт в точку клика)", function(v) Settings.ClickTP_Enabled = v end, Settings.ClickTP_Enabled)
CreateSliderInt(movePage, "Макс. дистанция TP", 50, 2000, Settings.ClickTP_MaxDistance, function(v) Settings.ClickTP_MaxDistance = v end)
CreateKeyBind(movePage, "Клавиша Click TP", "ClickTP_Key")

-- Suicide
CreateSection(movePage)
local suicideBtn = Instance.new("TextButton")
suicideBtn.Size = UDim2.new(1, 0, 0, 30)
suicideBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
suicideBtn.Text = Locales.t("Suicide (мгновенная смерть)")
suicideBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
suicideBtn.Font = Enum.Font.GothamBold
suicideBtn.TextSize = 13
suicideBtn.Parent = movePage
Instance.new("UICorner", suicideBtn).CornerRadius = UDim.new(0, 6)

suicideBtn.MouseButton1Click:Connect(function()
    ShowTabWarning("⚠ ВНИМАНИЕ", "Вы уверены, что хотите убить своего персонажа?", function()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChild("Humanoid")
        if hum and hum.Health > 0 then
            hum.Health = 0
        end
    end)
end)

local aimPage = TabPages[4]
CreateSection(aimPage)

ToggleRefs.Aimbot = CreateFunctionRow(aimPage, "Aimbot", Settings.Aim_Enabled,
    function(v) 
        Settings.Aim_Enabled = v
        if v then
            Settings.Aim_AutoAim = false
            if ToggleRefs.AutoAim then ToggleRefs.AutoAim.SetState(false) end
        end
    end,
    function(panel)
        -- Привязка клавиши аимбота (кнопка теперь широкая)
        CreateKeyBind(panel, "Клавиша аимбота", "AimKeyBind")
        CreateSection(panel)
        -- Выбор части тела
        CreateModeSwitch(panel, "Часть тела", {"Head","HumanoidRootPart","Auto"}, Settings.Aim_Part, function(v) Settings.Aim_Part = v end)
        -- Игнорирование игроков при проверке стен
        CreateToggle(panel, "Игнорировать игроков при проверке стен", function(v) Settings.Aim_IgnorePlayersInRaycast = v end, Settings.Aim_IgnorePlayersInRaycast)
        CreateToggle(panel, "Аим на NPC", function(v) Settings.Aim_TargetNPCs = v end, Settings.Aim_TargetNPCs)
        CreateSection(panel)
        -- FOV круг и его цвет
        CreateToggle(panel, "FOV круг", function(v) Settings.Aim_ShowFOV=v end, Settings.Aim_ShowFOV)
        CreateColorPicker(panel, "Цвет FOV", Settings.Aim_FOVColor, function(c) Settings.Aim_FOVColor=c end)
        CreateSection(panel)
        CreateToggle(panel, "Задержка реакции", function(v) Settings.Aim_ReactionEnabled = v end, Settings.Aim_ReactionEnabled)
        CreateSlider(panel, "Задержка (сек)", 0, 2, Settings.Aim_ReactionDelay, function(v) Settings.Aim_ReactionDelay = v end, 2)
    end)

ToggleRefs.AutoAim = CreateToggle(aimPage, "Auto Aim", function(v) 
    Settings.Aim_AutoAim = v
    if v then
        Settings.Aim_Enabled = false
        if ToggleRefs.Aimbot then ToggleRefs.Aimbot.SetState(false) end
    end
end, Settings.Aim_AutoAim, "Авто-наводка делает аим заметным. Включить?")

CreateSlider(aimPage, "Плавность", 0.1, 1.0, Settings.Aim_Smoothness, function(v) Settings.Aim_Smoothness=v end, 3)
CreateSliderInt(aimPage, "FOV", 10, 500, Settings.Aim_FOV, function(v) Settings.Aim_FOV=v end)
CreateToggle(aimPage, "Team Check", function(v) Settings.Aim_TeamCheck=v end, Settings.Aim_TeamCheck)
CreateToggle(aimPage, "Проверка стен", function(v) Settings.Aim_VisibleCheck=v end, Settings.Aim_VisibleCheck)
CreateToggle(aimPage, "Реалистичная наводка", function(v) Settings.Aim_Realistic=v end, Settings.Aim_Realistic)

CreateSection(aimPage)

ToggleRefs.Trigger = CreateFunctionRow(aimPage, "Triggerbot", Settings.Trigger_Enabled,
    function(v)
        Settings.Trigger_Enabled = v
    end,
    function(panel)
        CreateSection(panel)
        CreateModeSwitch(panel, "Режим", {"Single", "Automatic"}, Settings.Trigger_Mode, function(v) Settings.Trigger_Mode = v end)
        CreateSection(panel)
        CreateSlider(panel, "Задержка между выстрелами (сек)", 0.0, 1.0, Settings.Trigger_Delay, function(v) Settings.Trigger_Delay = v end, 3)
        CreateSlider(panel, "Задержка реакции (сек)", 0.0, 1.0, Settings.Trigger_ReactionDelay, function(v) Settings.Trigger_ReactionDelay = v end, 2)
        CreateSection(panel)
        CreateToggle(panel, "Проверка невидимости", function(v) Settings.Trigger_VisibleCheck = v end, Settings.Trigger_VisibleCheck)
        CreateToggle(panel, "Триггер на NPC", function(v) Settings.Trigger_TargetNPCs = v end, Settings.Trigger_TargetNPCs)
    end)

local visPage = TabPages[5]
CreateSection(visPage)
CreateToggle(visPage, "Fullbright", function(v) Settings.Fullbright_Enabled=v; ApplyVisuals() end, Settings.Fullbright_Enabled)
CreateSliderInt(visPage, "Яркость", 1, 100, Settings.Fullbright_Brightness, function(v) Settings.Fullbright_Brightness=v; ApplyVisuals() end)
CreateToggle(visPage, "FOV Changer", function(v)
    Settings.FOV_Enabled = v
    if not v then
        pcall(function() Camera.FieldOfView = DefaultFOV end)
    end
end, Settings.FOV_Enabled)
CreateSliderInt(visPage, "FOV", 30, 120, Settings.FOV_Value, function(v) Settings.FOV_Value=v end)

CreateToggle(visPage, "Картофель", function(v) Settings.PotatoGraphics_Enabled=v ApplyPotato() end, Settings.PotatoGraphics_Enabled)
CreateToggle(visPage, "Atmosphere Remover", function(v)
    Settings.AtmosphereRemover_Enabled = v
    if v then EnableAtmosphereRemover() else DisableAtmosphereRemover() end
end, Settings.AtmosphereRemover_Enabled)
CreateSection(visPage)
ToggleRefs.ThirdPerson = CreateToggle(visPage, "Третье лицо", function(v)
    if v then
        EnableThirdPerson()
    else
        DisableThirdPerson()
    end
end, Settings.ThirdPerson_Enabled)
CreateSection(visPage)
CreateFunctionRow(visPage, "Кастомный прицел", Settings.Cross_Enabled,
    function(v) Settings.Cross_Enabled=v end,
    function(panel)
        CreateSliderInt(panel, "Длина лучей", 1, 50, Settings.Cross_Size, function(v) Settings.Cross_Size=v end)
        CreateSliderInt(panel, "Толщина лучей", 1, 8, Settings.Cross_Thickness, function(v) Settings.Cross_Thickness=v end)
        CreateSliderInt(panel, "Отступ от центра", 0, 30, Settings.Cross_Gap, function(v) Settings.Cross_Gap=v end)
        CreateSection(panel)
        CreateToggle(panel, "Точка в центре", function(v) Settings.Cross_Dot=v end, Settings.Cross_Dot)
        CreateSliderInt(panel, "Размер точки", 1, 8, Settings.Cross_DotSize, function(v) Settings.Cross_DotSize=v end)
        CreateSection(panel)
        CreateToggle(panel, "T-стиль (скрыть верх)", function(v) Settings.Cross_HideTop=v end, Settings.Cross_HideTop)
        CreateSection(panel)
        CreateToggle(panel, "Обводка", function(v) Settings.Cross_Outline=v end, Settings.Cross_Outline)
        CreateSliderInt(panel, "Толщина обводки", 1, 3, Settings.Cross_OutlineThickness, function(v) Settings.Cross_OutlineThickness=v end)
        CreateColorPicker(panel, "Цвет обводки", Settings.Cross_OutlineColor, function(c) Settings.Cross_OutlineColor=c end)
        CreateColorPicker(panel, "Цвет прицела", Settings.Cross_Color, function(c) Settings.Cross_Color=c end)
    end)

local hlPage = TabPages[6]
CreateSection(hlPage)
CreateToggle(hlPage, "Подсветка предметов", function(v) Settings.Highlight_Objects=v end, Settings.Highlight_Objects)
CreateSliderInt(hlPage, "Дистанция", 10, 1000, Settings.Highlight_Distance, function(v) Settings.Highlight_Distance=v end)
CreateSliderInt(hlPage, "Размер текста", 10, 20, Settings.Highlight_MaxSize, function(v) Settings.Highlight_MaxSize=v end)
CreateColorPicker(hlPage, "Цвет", Settings.Highlight_Color, function(c) Settings.Highlight_Color=c end)
CreateToggle(hlPage, "Названия", function(v) Settings.Highlight_Names=v end, Settings.Highlight_Names)
CreateToggle(hlPage, "Только интерактивные", function(v) Settings.Highlight_OnlyInteractive=v end, Settings.Highlight_OnlyInteractive)

-- слежка за игроком
local spectateConnections = {}
local spectateSavedTransparencies = {}

function StartSpectatePlayer(player)
    if Settings.Spectating then StopSpectate() end
    local targetChar = player.Character
    if not targetChar or not targetChar:FindFirstChild("Humanoid") then return end
    local localChar = LocalPlayer.Character
    if localChar then
        spectateSavedTransparencies = {}
        for _, part in ipairs(localChar:GetDescendants()) do
            if part:IsA("BasePart") then
                spectateSavedTransparencies[part] = part.Transparency
                part.Transparency = 1
            end
        end
        local root = localChar:FindFirstChild("HumanoidRootPart")
        if root and not Settings.Freeze_Enabled then root.Anchored = true end
    end
    Camera.CameraSubject = targetChar.Humanoid
    Camera.CameraType = Enum.CameraType.Custom
    Settings.Spectating = true; Settings.SpectateIsNPC = false; Settings.SpectateTarget = player; Settings.SpectateTargetModel = nil
    if spectateConnections.player then spectateConnections.player:Disconnect() end
    spectateConnections.player = UserInputService.InputBegan:Connect(function(input) if input.KeyCode == Enum.KeyCode.Escape then StopSpectate() end end)
    UpdateSpectateHighlight()
end

function StartSpectateNPC(model)
    if Settings.Spectating then StopSpectate() end
    local hum = model and model:FindFirstChild("Humanoid")
    if not hum then return end
    local localChar = LocalPlayer.Character
    if localChar then
        spectateSavedTransparencies = {}
        for _, part in ipairs(localChar:GetDescendants()) do
            if part:IsA("BasePart") then
                spectateSavedTransparencies[part] = part.Transparency
                part.Transparency = 1
            end
        end
        local root = localChar:FindFirstChild("HumanoidRootPart")
        if root and not Settings.Freeze_Enabled then root.Anchored = true end
    end
    Camera.CameraSubject = hum; Camera.CameraType = Enum.CameraType.Custom
    Settings.Spectating = true; Settings.SpectateIsNPC = true; Settings.SpectateTargetModel = model; Settings.SpectateTarget = nil
    if spectateConnections.npc then spectateConnections.npc:Disconnect() end
    spectateConnections.npc = UserInputService.InputBegan:Connect(function(input) if input.KeyCode == Enum.KeyCode.Escape then StopSpectate() end end)
    UpdateSpectateHighlight()
end

function StopSpectate()
    if not Settings.Spectating then return end
    local localChar = LocalPlayer.Character
    if localChar then
        for part, trans in pairs(spectateSavedTransparencies) do
            pcall(function() part.Transparency = trans end)
        end
        spectateSavedTransparencies = {}
        local root = localChar:FindFirstChild("HumanoidRootPart")
        if root and not Settings.Freeze_Enabled then root.Anchored = false end
    end
    local myHum = localChar and localChar:FindFirstChild("Humanoid")
    if myHum then Camera.CameraSubject = myHum else Camera.CameraSubject = nil end
    Camera.CameraType = Enum.CameraType.Custom
    Settings.Spectating = false
    if spectateConnections.player then spectateConnections.player:Disconnect(); spectateConnections.player = nil end
    if spectateConnections.npc then spectateConnections.npc:Disconnect(); spectateConnections.npc = nil end
    Settings.SpectateTarget = nil; Settings.SpectateTargetModel = nil
    UpdateSpectateHighlight()
end

-- вкладка spectate
local specPage = TabPages[8]
local specTopFrame = Instance.new("Frame") specTopFrame.Size = UDim2.new(1, 0, 0, 60) specTopFrame.BackgroundTransparency = 1 specTopFrame.ZIndex = 100 specTopFrame.Parent = specPage
local stopBtn = Instance.new("TextButton") stopBtn.Size = UDim2.new(1, -10, 0, 25) stopBtn.Position = UDim2.new(0, 5, 0, 0) stopBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40) stopBtn.Text = Locales.t("⛔ Остановить") stopBtn.TextColor3 = Color3.fromRGB(255,255,255) stopBtn.Font = Enum.Font.GothamBold stopBtn.TextSize = 13 stopBtn.ZIndex = 101 stopBtn.Active = true stopBtn.Parent = specTopFrame Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 4)
local tpSpecBtn = Instance.new("TextButton") tpSpecBtn.Size = UDim2.new(1, -10, 0, 25) tpSpecBtn.Position = UDim2.new(0, 5, 0, 32) tpSpecBtn.BackgroundColor3 = Color3.fromRGB(40,40,40) tpSpecBtn.Text = Locales.t("ТП к цели") tpSpecBtn.TextColor3 = Color3.fromRGB(255,255,255) tpSpecBtn.Font = Enum.Font.GothamBold tpSpecBtn.TextSize = 13 tpSpecBtn.ZIndex = 101 tpSpecBtn.Active = true tpSpecBtn.Parent = specTopFrame Instance.new("UICorner", tpSpecBtn).CornerRadius = UDim.new(0, 4)
stopBtn.MouseButton1Click:Connect(StopSpectate)

tpSpecBtn.MouseButton1Click:Connect(function()
    if not Settings.Spectating then return end
    local myChar = LocalPlayer.Character
    if not myChar then return end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local wasAnchored = myRoot.Anchored
    myRoot.Anchored = false

    local targetPlr = Settings.SpectateTarget
    local targetModel = Settings.SpectateTargetModel
    local isNpc = Settings.SpectateIsNPC

    local success = false
    if not isNpc and targetPlr then
        local tChar = targetPlr.Character
        if tChar and tChar:FindFirstChild("HumanoidRootPart") then
            success = pcall(function()
                myRoot.CFrame = tChar.HumanoidRootPart.CFrame + Vector3.new(0, 3, 0)
            end)
        end
    elseif isNpc and targetModel and targetModel.Parent then
        local pos = Vector3.zero
        pcall(function() pos = targetModel:GetPivot().Position end)
        if pos == Vector3.zero and targetModel.PrimaryPart then
            pos = targetModel.PrimaryPart.Position
        end
        if pos ~= Vector3.zero then
            success = pcall(function()
                myRoot.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
            end)
        end
    end

    if success then
        StopSpectate()
    else
        myRoot.Anchored = wasAnchored
    end
end)

local specFavFrame = Instance.new("ScrollingFrame") specFavFrame.Size=UDim2.new(1,0,0,120) specFavFrame.BackgroundTransparency=1 specFavFrame.BorderSizePixel=0 specFavFrame.ScrollBarThickness=3 specFavFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) specFavFrame.CanvasSize=UDim2.new(0,0,0,0) specFavFrame.Parent=specPage
local specFavLayout = Instance.new("UIListLayout") specFavLayout.Padding=UDim.new(0,4) specFavLayout.Parent=specFavFrame
specFavLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() specFavFrame.CanvasSize=UDim2.new(0,0,0,specFavLayout.AbsoluteContentSize.Y+10) end)

local specListFrame = Instance.new("ScrollingFrame") specListFrame.Size=UDim2.new(1,0,0,200) specListFrame.BackgroundTransparency=1 specListFrame.BorderSizePixel=0 specListFrame.ScrollBarThickness=3 specListFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) specListFrame.CanvasSize=UDim2.new(0,0,0,0) specListFrame.ZIndex=1 specListFrame.Parent=specPage
local specLayout = Instance.new("UIListLayout") specLayout.Padding=UDim.new(0,4) specLayout.Parent=specListFrame
specLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() specListFrame.CanvasSize=UDim2.new(0,0,0,specLayout.AbsoluteContentSize.Y+10) end)

local specNpcListFrame = Instance.new("ScrollingFrame") specNpcListFrame.Size=UDim2.new(1,0,0,150) specNpcListFrame.BackgroundTransparency=1 specNpcListFrame.BorderSizePixel=0 specNpcListFrame.ScrollBarThickness=3 specNpcListFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) specNpcListFrame.CanvasSize=UDim2.new(0,0,0,0) specNpcListFrame.ZIndex=1 specNpcListFrame.Parent=specPage
local specNpcLayout = Instance.new("UIListLayout") specNpcLayout.Padding=UDim.new(0,4) specNpcLayout.Parent=specNpcListFrame
specNpcLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() specNpcListFrame.CanvasSize=UDim2.new(0,0,0,specNpcLayout.AbsoluteContentSize.Y+10) end)

local spectateButtons = {}; local spectateNpcButtons = {}
 -- обновление списков
function RefreshSpectateFavOnly()
    for _, child in ipairs(specFavFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    local favSorted = {}
    for player, _ in pairs(FavoritePlayers) do
        if player and player:IsA("Player") and player ~= LocalPlayer then
            table.insert(favSorted, player)
        end
    end
    table.sort(favSorted, function(a, b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(favSorted) do
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 30)
        frame.BackgroundTransparency = 1
        frame.Parent = specFavFrame

        local isActive = Settings.Spectating and not Settings.SpectateIsNPC and Settings.SpectateTarget == player
        local bgc, txtc
        if isActive then
            bgc, txtc = Color3.fromRGB(100, 200, 100), Color3.fromRGB(20, 20, 20)
        else
            bgc, txtc = GetTeamButtonColor(player)
        end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -30, 1, 0)
        btn.BackgroundColor3 = bgc
        btn.Text = "★ " .. player.DisplayName .. " (@" .. player.Name .. ")"
        btn.TextColor3 = txtc
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 12
        btn.Parent = frame
        local removeBtn = Instance.new("TextButton")
        removeBtn.Size = UDim2.new(0, 24, 0, 24)
        removeBtn.Position = UDim2.new(1, -26, 0, 3)
        removeBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
        removeBtn.Text = "X"
        removeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        removeBtn.Font = Enum.Font.GothamBold
        removeBtn.TextSize = 13
        removeBtn.Parent = frame
        local plrRef = player
        btn.MouseButton1Click:Connect(function()
            if Settings.Spectating and not Settings.SpectateIsNPC and Settings.SpectateTarget == plrRef then
                StopSpectate()
            else
                if Settings.Spectating then StopSpectate() end
                StartSpectatePlayer(plrRef)
            end
        end)
        removeBtn.MouseButton1Click:Connect(function()
            FavoritePlayers[plrRef] = nil
            RefreshSpectateFavOnly()
            RefreshPlayerList()
        end)
    end
end

function RefreshSpectatePlayersOnly()
    for _, child in ipairs(specListFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    spectateButtons = {}
    local sorted = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(sorted, p) end
    end
    table.sort(sorted, function(a, b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(sorted) do
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 30)
        frame.BackgroundTransparency = 1
        frame.Parent = specListFrame

        local isActive = Settings.Spectating and not Settings.SpectateIsNPC and Settings.SpectateTarget == player
        local bgc, txtc
        if isActive then
            bgc, txtc = Color3.fromRGB(100, 200, 100), Color3.fromRGB(20, 20, 20)
        else
            bgc, txtc = GetTeamButtonColor(player)
        end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -30, 1, 0)
        btn.BackgroundColor3 = bgc
        btn.Text = player.DisplayName .. " (@" .. player.Name .. ")"
        btn.TextColor3 = txtc
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 12
        btn.Parent = frame
        spectateButtons[player] = btn
        local plrRef = player
        btn.MouseButton1Click:Connect(function()
            if Settings.Spectating and not Settings.SpectateIsNPC and Settings.SpectateTarget == plrRef then
                StopSpectate()
            else
                if Settings.Spectating then StopSpectate() end
                StartSpectatePlayer(plrRef)
            end
        end)
        local starBtn = Instance.new("TextButton")
        starBtn.Size = UDim2.new(0, 24, 0, 24)
        starBtn.Position = UDim2.new(1, -26, 0, 3)
        starBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        starBtn.Text = IsFavorite(plrRef) and "★" or "☆"
        starBtn.TextColor3 = Color3.fromRGB(255, 255, 0)
        starBtn.Font = Enum.Font.GothamBold
        starBtn.TextSize = 13
        starBtn.Parent = frame
        starBtn.MouseButton1Click:Connect(function() ToggleFavorite(plrRef) end)
    end
end

function RefreshSpectateNpcOnly()
    for _, child in ipairs(specNpcListFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    spectateNpcButtons = {}
    if npcCacheData then
        for _, data in ipairs(npcCacheData) do
            local model = data.Model
            local name = data.Name
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 0, 30)
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            btn.Text = name
            btn.TextColor3 = Color3.fromRGB(255, 200, 100)
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 12
            btn.Parent = specNpcListFrame
            spectateNpcButtons[model] = btn
            local modelRef = model
            btn.MouseButton1Click:Connect(function()
                if Settings.Spectating and Settings.SpectateIsNPC and Settings.SpectateTargetModel == modelRef then
                    StopSpectate()
                else
                    if Settings.Spectating then StopSpectate() end
                    StartSpectateNPC(modelRef)
                end
            end)
        end
    end
end

-- подсветка цели
function UpdateSpectateHighlight()
    for player, btn in pairs(spectateButtons) do
        if not btn or not btn.Parent then continue end
        if Settings.Spectating and not Settings.SpectateIsNPC and Settings.SpectateTarget == player then
            btn.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
            btn.TextColor3 = Color3.fromRGB(20, 20, 20)
        else
            local bgc, txtc = GetTeamButtonColor(player)
            btn.BackgroundColor3 = bgc
            btn.TextColor3 = txtc
        end
    end
    for model, btn in pairs(spectateNpcButtons) do
        if not btn or not btn.Parent then continue end
        if Settings.Spectating and Settings.SpectateIsNPC and Settings.SpectateTargetModel == model then
            btn.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
            btn.TextColor3 = Color3.fromRGB(20, 20, 20)
        else
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            btn.TextColor3 = Color3.fromRGB(255, 200, 100)
        end
    end
end

-- обновление списка
spectatePlayerSig = ""
spectateNpcSig = ""
spectateFavSig = ""

function BuildSpectatePlayerSig()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(names, p.Name) end
    end
    table.sort(names)
    return table.concat(names, "|")
end

function BuildSpectateNpcSig()
    local names = {}
    for _, data in ipairs(npcCacheData) do
        if data.Model and data.Model.Parent then
            table.insert(names, data.Name)
        end
    end
    table.sort(names)
    return table.concat(names, "|")
end

function BuildSpectateFavSig()
    local names = {}
    for plr, _ in pairs(FavoritePlayers) do
        if plr and plr:IsA("Player") and plr ~= LocalPlayer then
            table.insert(names, plr.Name)
        end
    end
    table.sort(names)
    return table.concat(names, "|")
end

function RefreshSpectateIfChanged()
    local newFavSig = BuildSpectateFavSig()
    local newPlrSig = BuildSpectatePlayerSig()
    local newNpcSig = BuildSpectateNpcSig()

    local favChanged = (newFavSig ~= spectateFavSig)
    local plrChanged = (newPlrSig ~= spectatePlayerSig)
    local npcChanged = (newNpcSig ~= spectateNpcSig)

    if not (favChanged or plrChanged or npcChanged) then return end

    spectateFavSig    = newFavSig
    spectatePlayerSig = newPlrSig
    spectateNpcSig    = newNpcSig

    if favChanged then
        local p = specFavFrame.CanvasPosition
        pcall(RefreshSpectateFavOnly)
        pcall(function() specFavFrame.CanvasPosition = p end)
    end
    if plrChanged then
        local p = specListFrame.CanvasPosition
        pcall(RefreshSpectatePlayersOnly)
        pcall(function() specListFrame.CanvasPosition = p end)
        if Settings.Spectating then pcall(UpdateSpectateHighlight) end
    end
    if npcChanged then
        local p = specNpcListFrame.CanvasPosition
        pcall(refreshNpcCache)
        pcall(RefreshSpectateNpcOnly)
        pcall(function() specNpcListFrame.CanvasPosition = p end)
    end
end

function RefreshSpectateList()
    spectateFavSig    = ""
    spectatePlayerSig = ""
    spectateNpcSig    = ""
    RefreshSpectateFavOnly()
    RefreshSpectatePlayersOnly()
    RefreshSpectateNpcOnly()
    spectateFavSig    = BuildSpectateFavSig()
    spectatePlayerSig = BuildSpectatePlayerSig()
    spectateNpcSig    = BuildSpectateNpcSig()
end
 -- вкладка телепорт
local tpPage = TabPages[7]

local favListFrame = Instance.new("ScrollingFrame") favListFrame.Size=UDim2.new(1,0,0,100) favListFrame.BackgroundTransparency=1 favListFrame.BorderSizePixel=0 favListFrame.ScrollBarThickness=3 favListFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) favListFrame.CanvasSize=UDim2.new(0,0,0,0) favListFrame.Parent=tpPage
local favLayout = Instance.new("UIListLayout") favLayout.Padding=UDim.new(0,4) favLayout.Parent=favListFrame
favLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() favListFrame.CanvasSize=UDim2.new(0,0,0,favLayout.AbsoluteContentSize.Y+10) end)

local tpActionsFrame = Instance.new("Frame") tpActionsFrame.Size=UDim2.new(1,0,0,70) tpActionsFrame.BackgroundTransparency=1 tpActionsFrame.Parent=tpPage
local saveLocBtn = Instance.new("TextButton") saveLocBtn.Size=UDim2.new(1,-10,0,22) saveLocBtn.Position=UDim2.new(0,5,0,0) saveLocBtn.BackgroundColor3=Color3.fromRGB(40,40,40) saveLocBtn.Text=Locales.t("Сохранить позицию") saveLocBtn.TextColor3=Color3.fromRGB(255,255,255) saveLocBtn.Font=Enum.Font.GothamBold saveLocBtn.TextSize=11 saveLocBtn.Parent=tpActionsFrame
local tpLastBtn = Instance.new("TextButton") tpLastBtn.Size=UDim2.new(1,-10,0,22) tpLastBtn.Position=UDim2.new(0,5,0,28) tpLastBtn.BackgroundColor3=Color3.fromRGB(40,40,40) tpLastBtn.Text=Locales.t("ТП к последней сохр.") tpLastBtn.TextColor3=Color3.fromRGB(255,255,255) tpLastBtn.Font=Enum.Font.GothamBold tpLastBtn.TextSize=11 tpLastBtn.Parent=tpActionsFrame
local spawnBtn = Instance.new("TextButton") spawnBtn.Size=UDim2.new(1,-10,0,22) spawnBtn.Position=UDim2.new(0,5,0,56) spawnBtn.BackgroundColor3=Color3.fromRGB(40,40,40) spawnBtn.Text=Locales.t("ТП на спавн") spawnBtn.TextColor3=Color3.fromRGB(255,255,255) spawnBtn.Font=Enum.Font.GothamBold spawnBtn.TextSize=11 spawnBtn.Parent=tpActionsFrame

local playerListFrame = Instance.new("ScrollingFrame") playerListFrame.Size=UDim2.new(1,0,0,200) playerListFrame.BackgroundTransparency=1 playerListFrame.BorderSizePixel=0 playerListFrame.ScrollBarThickness=3 playerListFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) playerListFrame.CanvasSize=UDim2.new(0,0,0,0) playerListFrame.Parent=tpPage
local tpLayout = Instance.new("UIListLayout") tpLayout.Padding=UDim.new(0,4) tpLayout.Parent=playerListFrame
tpLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() playerListFrame.CanvasSize=UDim2.new(0,0,0,tpLayout.AbsoluteContentSize.Y+10) end)

local npcListFrame = Instance.new("ScrollingFrame") npcListFrame.Size=UDim2.new(1,0,0,150) npcListFrame.BackgroundTransparency=1 npcListFrame.BorderSizePixel=0 npcListFrame.ScrollBarThickness=3 npcListFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) npcListFrame.CanvasSize=UDim2.new(0,0,0,0) npcListFrame.Parent=tpPage
local npcLayout = Instance.new("UIListLayout") npcLayout.Padding=UDim.new(0,4) npcLayout.Parent=npcListFrame
npcLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() npcListFrame.CanvasSize=UDim2.new(0,0,0,npcLayout.AbsoluteContentSize.Y+10) end)

local savedFrame = Instance.new("Frame") savedFrame.Size=UDim2.new(1,0,0,150) savedFrame.BackgroundTransparency=1 savedFrame.Parent=tpPage
local clearSavedBtn = Instance.new("TextButton") clearSavedBtn.Size=UDim2.new(1,-10,0,22) clearSavedBtn.Position=UDim2.new(0,5,0,0) clearSavedBtn.BackgroundColor3=Color3.fromRGB(200,40,40) clearSavedBtn.Text=Locales.t("Очистить все сохр.") clearSavedBtn.TextColor3=Color3.fromRGB(255,255,255) clearSavedBtn.Font=Enum.Font.GothamBold clearSavedBtn.TextSize=11 clearSavedBtn.Parent=savedFrame
local savedListFrame = Instance.new("ScrollingFrame") savedListFrame.Size=UDim2.new(1,0,0,110) savedListFrame.Position=UDim2.new(0,0,0,26) savedListFrame.BackgroundTransparency=1 savedListFrame.BorderSizePixel=0 savedListFrame.ScrollBarThickness=3 savedListFrame.ScrollBarImageColor3=Color3.fromRGB(60,60,60) savedListFrame.CanvasSize=UDim2.new(0,0,0,0) savedListFrame.Parent=savedFrame
local savedLayout = Instance.new("UIListLayout") savedLayout.Padding=UDim.new(0,4) savedLayout.Parent=savedListFrame
savedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() savedListFrame.CanvasSize=UDim2.new(0,0,0,savedLayout.AbsoluteContentSize.Y+10) end)

local function tpWithWarning(action)
    if not Settings.DisableWarnings then
        ShowTabWarning("⚠ ТЕЛЕПОРТ", "Телепорт может вызвать кик. Продолжить?", action)
    else action() end
end
local function teleportTo(targetCFrame)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    char.HumanoidRootPart.CFrame = targetCFrame
end

saveLocBtn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local pos = char.HumanoidRootPart.CFrame
        Settings.LastSavedPosition = pos
        table.insert(Settings.SavedLocations, {Name = "Loc ".. #Settings.SavedLocations+1, CFrame = pos})
        RefreshSavedLocations()
    end
end)
tpLastBtn.MouseButton1Click:Connect(function()
    tpWithWarning(function()
        if Settings.LastSavedPosition then teleportTo(Settings.LastSavedPosition) end
    end)
end)
spawnBtn.MouseButton1Click:Connect(function()
    tpWithWarning(function()
        local spawns = workspace:FindFirstChild("SpawnLocation")
        if spawns then
            teleportTo(spawns.CFrame + Vector3.new(0,3,0))
        else
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("SpawnLocation") then
                    teleportTo(obj.CFrame + Vector3.new(0,3,0))
                    break
                end
            end
        end
    end)
end)
clearSavedBtn.MouseButton1Click:Connect(function()
    Settings.SavedLocations = {}
    Settings.LastSavedPosition = nil
    RefreshSavedLocations()
end)


function RefreshSavedLocations()
    for _, child in ipairs(savedListFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    for i, loc in ipairs(Settings.SavedLocations) do
        local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,28) frame.BackgroundTransparency=1 frame.Parent=savedListFrame
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,-30,1,0) btn.Position=UDim2.new(0,0,0,0) btn.BackgroundColor3=Color3.fromRGB(40,40,40) btn.Text=loc.Name btn.TextColor3=Color3.fromRGB(255,255,255) btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=frame
        local delBtn = Instance.new("TextButton") delBtn.Size=UDim2.new(0,24,0,24) delBtn.Position=UDim2.new(1,-26,0,2) delBtn.BackgroundColor3=Color3.fromRGB(200,40,40) delBtn.Text="X" delBtn.TextColor3=Color3.fromRGB(255,255,255) delBtn.Font=Enum.Font.GothamBold delBtn.TextSize=13 delBtn.Parent=frame
        local idx = i
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function() teleportTo(Settings.SavedLocations[idx].CFrame) end)
        end)
        delBtn.MouseButton1Click:Connect(function()
            if Settings.SavedLocations[idx] then table.remove(Settings.SavedLocations, idx); RefreshSavedLocations() end
        end)
    end
end

function RefreshFavorites()
    for _, child in ipairs(favListFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    local sorted = {}
    for player, _ in pairs(FavoritePlayers) do if player and player:IsA("Player") and player ~= LocalPlayer then table.insert(sorted, player) end end
    table.sort(sorted, function(a,b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(sorted) do
        local dist = ""; local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            dist = " ("..math.floor((char.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).Magnitude).."m)"
        end
        local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,28) frame.BackgroundTransparency=1 frame.Parent=favListFrame
        local bgc, txtc = GetTeamButtonColor(player)
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,-30,1,0) btn.Position=UDim2.new(0,0,0,0) btn.BackgroundColor3=bgc btn.Text="★ "..player.DisplayName.." (@"..player.Name..")"..dist btn.TextColor3=txtc btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=frame
        local removeBtn = Instance.new("TextButton") removeBtn.Size=UDim2.new(0,24,0,24) removeBtn.Position=UDim2.new(1,-26,0,2) removeBtn.BackgroundColor3=Color3.fromRGB(200,40,40) removeBtn.Text="X" removeBtn.TextColor3=Color3.fromRGB(255,255,255) removeBtn.Font=Enum.Font.GothamBold removeBtn.TextSize=13 removeBtn.Parent=frame
        local plrRef = player
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function()
                local c = LocalPlayer.Character; local tc = plrRef.Character
                if c and tc and c:FindFirstChild("HumanoidRootPart") and tc:FindFirstChild("HumanoidRootPart") then
                    teleportTo(tc.HumanoidRootPart.CFrame + Vector3.new(0,3,0))
                end
            end)
        end)
        removeBtn.MouseButton1Click:Connect(function()
            FavoritePlayers[plrRef] = nil
            RefreshFavorites()
            RefreshSpectateList()
        end)
    end
end

function RefreshPlayerList()
    for _, child in ipairs(playerListFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    local sorted = {}; for _, p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(sorted, p) end end
    table.sort(sorted, function(a,b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(sorted) do
        local dist = ""; local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            dist = " ("..math.floor((char.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).Magnitude).."m)"
        end
        local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,28) frame.BackgroundTransparency=1 frame.Parent=playerListFrame
        local bgc, txtc = GetTeamButtonColor(player)
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,-30,1,0) btn.Position=UDim2.new(0,0,0,0) btn.BackgroundColor3=bgc btn.Text=player.DisplayName.." (@"..player.Name..")"..dist btn.TextColor3=txtc btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=frame
        local plrRef = player
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function()
                local c = LocalPlayer.Character; local tc = plrRef.Character
                if c and tc and c:FindFirstChild("HumanoidRootPart") and tc:FindFirstChild("HumanoidRootPart") then
                    teleportTo(tc.HumanoidRootPart.CFrame + Vector3.new(0,3,0))
                end
            end)
        end)
        local starBtn = Instance.new("TextButton")
        starBtn.Size = UDim2.new(0, 24, 0, 24)
        starBtn.Position = UDim2.new(1, -26, 0, 2)
        starBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
        starBtn.Text = IsFavorite(plrRef) and "★" or "☆"
        starBtn.TextColor3 = Color3.fromRGB(255,255,0)
        starBtn.Font = Enum.Font.GothamBold
        starBtn.TextSize = 13
        starBtn.Parent = frame
        starBtn.MouseButton1Click:Connect(function()
            ToggleFavorite(plrRef)
        end)
    end
end

function refreshNpcCache()
    npcCacheData = {}
    local playerChars = {}
    for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then playerChars[plr.Character] = true end end
    local unnamedCount = 0
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and not playerChars[model] then
            local isNpc = false
            if model:FindFirstChild("Humanoid") then isNpc = true
            elseif model:FindFirstChildWhichIsA("IntValue") and model:FindFirstChildWhichIsA("IntValue").Name == "Health" then isNpc = true
            elseif model:FindFirstChildWhichIsA("NumberValue") and model:FindFirstChildWhichIsA("NumberValue").Name == "Health" then isNpc = true
            else
                local lower = model.Name:lower()
                if lower:find("npc") or lower:find("bot") then isNpc = true end
            end
            if isNpc then
                local name = model.Name
                if name == "" or name == " " then unnamedCount = unnamedCount + 1; name = "No name " .. unnamedCount end
                table.insert(npcCacheData, {Model = model, Name = name})
            end
        end
    end
end

function RefreshNPCList()
    for _, child in ipairs(npcListFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    for _, data in ipairs(npcCacheData) do
        local model = data.Model; local name = data.Name
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,0,0,28) btn.BackgroundColor3=Color3.fromRGB(40,40,40) btn.Text=name btn.TextColor3=Color3.fromRGB(255,200,100) btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=npcListFrame
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function()
                if model.Parent then
                    local pos = Vector3.zero
                    pcall(function() pos = model:GetPivot().Position end)
                    if pos == Vector3.zero and model.PrimaryPart then pos = model.PrimaryPart.Position end
                    teleportTo(CFrame.new(pos + Vector3.new(0,5,0)))
                end
            end)
        end)
    end
end

function RefreshTPTab()
    RefreshFavorites()
    RefreshPlayerList()
    RefreshNPCList()
    RefreshSavedLocations()
end

Players.PlayerAdded:Connect(function() if currentTabIndex == 7 then RefreshTPTab() end end)
Players.PlayerRemoving:Connect(function(plr)
    FavoritePlayers[plr] = nil
    if ESPBoxes[plr] then RemoveFullESP(ESPBoxes[plr]); ESPBoxes[plr] = nil end
    removeChamsForPlayer(plr)
    Trail.ClearPlayer(plr)
    if currentTabIndex == 7 then RefreshTPTab() end
end)

-- настройки (вкладка)
local setPage = TabPages[9]
CreateSection(setPage)
CreateToggle(setPage, "Показывать FPS", function(v)
    Settings.ShowFPS = v
    UpdateFPSPingDisplay()
end, Settings.ShowFPS)

CreateToggle(setPage, "Показывать пинг", function(v)
    Settings.ShowPing = v
    UpdateFPSPingDisplay()
end, Settings.ShowPing)

CreateToggle(setPage, "Кнопки игроков в цвет команды", function(v)
    Settings.TP_TeamColorButtons = v
    if currentTabIndex == 7 then RefreshTPTab()
    elseif currentTabIndex == 8 then RefreshSpectateList() end
end, Settings.TP_TeamColorButtons)

CreateToggle(setPage, "Прозрачность меню", function(v)
    Settings.MenuTransparency = v and 0.5 or 0.05
    MainFrame.BackgroundTransparency = Settings.MenuTransparency
end, false)

CreateToggle(setPage, "Отключить предупреждения", function(v)
    if v then
        ShowTabWarning("⚠ ВНИМАНИЕ", "Вы отключаете все предупреждения о риске бана. Продолжить?", function()
            Settings.DisableWarnings = true
        end)
    else
        Settings.DisableWarnings = false
    end
end, Settings.DisableWarnings)

-- Фоновая проверка античита
ToggleRefs.AutoCheck = CreateToggle(setPage, "Фоновая проверка античита", function(v)
    SetAutoCheckEnabled(v)
end, Settings.AutoAntiCheatCheck)

CreateSection(setPage)

-- Бинды клавиш
CreateKeyBind(setPage, "Visuals", "Visuals")
CreateKeyBind(setPage, "Speed Hack", "Speed")
CreateKeyBind(setPage, "Flight", "Flight")
CreateKeyBind(setPage, "Noclip", "Noclip")
CreateKeyBind(setPage, "Aimbot", "Aimbot")
CreateKeyBind(setPage, "Triggerbot", "Trigger")
CreateKeyBind(setPage, "Auto Clicker", "AutoClicker")
CreateKeyBind(setPage, "Третье лицо", "ThirdPerson")
CreateKeyBind(setPage, "Курсор", "CursorUnlock")
CreateKeyBind(setPage, "BHop", "BHop")
CreateKeyBind(setPage, "Freeze", "Freeze")
CreateKeyBind(setPage, "Click TP", "ClickTP")

CreateSection(setPage)

local langNames = {}
local currentLangName = ""
for _, l in ipairs(Locales.getLanguages()) do
    table.insert(langNames, l.name)
    if l.code == Locales.get() then currentLangName = l.name end
end

CreateModeSwitch(setPage, Locales.t("Язык"), langNames, currentLangName, function(v)
    for _, l in ipairs(Locales.getLanguages()) do
        if l.name == v and l.code ~= Locales.get() then
            getgenv().BOBRCHEATS_LANG = l.code
            print("[bobrcheats] Switching to " .. l.code .. "...")
            task.spawn(function()
                task.wait(0.15)
                local url = "https://raw.githubusercontent.com/K3rnyx0/bobrcheats/refs/heads/main/script.lua?v=" .. tostring(tick())
                local ok, code = pcall(function() return game:HttpGet(url, true) end)
                if ok and code then
                    local fn = loadstring(code)
                    if fn then
                        fn()
                    end
                end
            end)
            break
        end
    end
end)

-- античит и глубокая проверка
antiCheatStatusLabel = Instance.new("TextLabel")
antiCheatStatusLabel.Size = UDim2.new(1, -10, 0, 40)
antiCheatStatusLabel.Position = UDim2.new(0, 5, 1, -85)
antiCheatStatusLabel.BackgroundTransparency = 1
antiCheatStatusLabel.Text = Locales.t("Статус античита: Ожидание...")
antiCheatStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
antiCheatStatusLabel.Font = Enum.Font.Gotham
antiCheatStatusLabel.TextSize = 12
antiCheatStatusLabel.TextWrapped = true
antiCheatStatusLabel.Parent = setPage

-- Кнопка глубокой проверки
local deepCheckBtn = Instance.new("TextButton")
deepCheckBtn.Size = UDim2.new(0, 160, 0, 24)
deepCheckBtn.Position = UDim2.new(0, 5, 1, -110)
deepCheckBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
deepCheckBtn.Text = Locales.t("Глубокая проверка")
deepCheckBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
deepCheckBtn.Font = Enum.Font.Gotham
deepCheckBtn.TextSize = 11
deepCheckBtn.Parent = setPage
Instance.new("UICorner", deepCheckBtn).CornerRadius = UDim.new(0, 4)



deepCheckBtn.MouseButton1Click:Connect(function()
    if DeepCheckRunning or DeepCheckStarting then
        -- Остановка проверки
        DeepCheckCancelled = true
        DeepCheckStarting = false
        deepCheckBtn.Text = Locales.t("Остановка...")
        deepCheckBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        task.spawn(function()
            repeat task.wait(0.1) until not DeepCheckRunning and not DeepCheckStarting
            deepCheckBtn.Text = Locales.t("Глубокая проверка")
            deepCheckBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        end)
        return
    end

    -- Запуск проверки
    ShowTabWarning("⚠ ВНИМАНИЕ", "Глубокая проверка может вызвать лаги или кратковременное зависание Roblox. Продолжить?", function()
        DeepCheckStarting = true
        deepCheckBtn.Text = Locales.t("Остановка")
        deepCheckBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        UpdateAntiCheatStatus(Locales.t("Запуск глубокой проверки..."), Color3.fromRGB(255, 255, 0))

        task.spawn(function()
            local res = DeepDetectAntiCheat()
            AntiCheatResult = res

            -- Определяем текст статуса без "приблизительно" для остановки
local statusText = Locales.t("Статус античита: ") .. res.Message
if not res.Message:find(Locales.t("остановлена")) and not res.Message:find("stopped") then
    statusText = statusText .. " " .. Locales.t("(приблизительно)")
end
            UpdateAntiCheatStatus(statusText, res.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100))

            deepCheckBtn.Text = Locales.t("Глубокая проверка")
            deepCheckBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)

if res.Found then
    -- Отключаем все читы при обнаружении античита
    Settings.ESP_Enabled = false
    Settings.Speed_Enabled = false
    Settings.Flight_Enabled = false
    Settings.Noclip_Enabled = false
    Settings.Aim_Enabled = false
    Settings.Aim_AutoAim = false
    Settings.Trigger_Enabled = false
    Settings.AutoClicker_Enabled = false
    Settings.BHop_Enabled = false

    if ToggleRefs.ESP_Enabled then ToggleRefs.ESP_Enabled.SetState(false) end
    if ToggleRefs.Speed then ToggleRefs.Speed.SetState(false) end
    if ToggleRefs.Flight then ToggleRefs.Flight.SetState(false) end
    if ToggleRefs.Noclip then ToggleRefs.Noclip.SetState(false) end
    if ToggleRefs.Aimbot then ToggleRefs.Aimbot.SetState(false) end
    if ToggleRefs.AutoAim then ToggleRefs.AutoAim.SetState(false) end
    if ToggleRefs.Trigger then ToggleRefs.Trigger.SetState(false) end
    if ToggleRefs.AutoClicker then ToggleRefs.AutoClicker.SetState(false) end
    if ToggleRefs.BHop then ToggleRefs.BHop.SetState(false) end

    -- Принудительно применяем изменения к персонажу
    UpdateSpeed()
    UpdateFlight()
    UpdateNoclip()
    SetAutoClickerEnabled(false)
            end
        end)
    end)
end)

-- Если быстрый детектор уже завершился, обновим статус
if AntiCheatResult then
    UpdateAntiCheatStatus(
        Locales.t("Статус античита: ") .. AntiCheatResult.Message .. " " .. Locales.t("(приблизительно)"),
        AntiCheatResult.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100)
    )
end

-- анимации меню
local MenuLoaded = false

function ShowMainMenu()
    ScreenGui.Enabled = true
    MainFrame.BackgroundTransparency = 1
    MainFrame.Size = UDim2.new(0, 560, 0, 0)
    TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        BackgroundTransparency = Settings.MenuTransparency,
        Size = UDim2.new(0, 560, 0, 600)
    }):Play()
    MenuLoaded = true

end
local function HideMainMenu(callback)
    TweenService:Create(MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 560, 0, 0)
    }):Play()
    task.delay(0.4, function()
        ScreenGui.Enabled = false
        if callback then callback() end
    end)
end

CloseBtn.MouseButton1Click:Connect(function()
    HideMainMenu(function()
        FULL_UNLOAD()
    end)
end)

local origH = 600 local minH = 42
local tOpen = TweenService:Create(MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quart), {Size = UDim2.new(0,560,0,origH)})
local tClose = TweenService:Create(MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quart), {Size = UDim2.new(0,560,0,minH)})
local menuMin = false
MinimizeBtn.MouseButton1Click:Connect(function()
    menuMin = not menuMin
    if menuMin then
        tClose:Play()
    else
        tOpen:Play()
    end
end)

-- визуал
function ApplyVisuals()
    if Settings.Fullbright_Enabled then
        local brightnessVal = 1 + (Settings.Fullbright_Brightness - 1) * (MAX_FULLBRIGHT_BRIGHTNESS - 1) / 99
        pcall(function() Lighting.Brightness = math.min(brightnessVal, MAX_FULLBRIGHT_BRIGHTNESS) end)
    else
        pcall(function() Lighting.Brightness = DefaultLighting.Brightness end)
    end
end

function ApplyPotato()
    local rendering = settings().Rendering
    if Settings.PotatoGraphics_Enabled then
        pcall(function() rendering.QualityLevel = 1; rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01 end)
        Lighting.GlobalShadows = false
    else
        pcall(function() rendering.QualityLevel = DefaultQualityLevel; rendering.MeshPartDetailLevel = DefaultMeshDetail end)
        Lighting.GlobalShadows = true
    end
end

function UpdateGravity()
    workspace.Gravity = Settings.Gravity_Enabled and Settings.Gravity_Value or DefaultGravity
end

-- убираем атмосферу
local AtmosphereRemover = {
    Enabled = false,
    OrigLight = {},
    SavedSky = {},
    Watching = {},
    Connections = {}
}

function EnableAtmosphereRemover()
    if AtmosphereRemover.Enabled then return end
    AtmosphereRemover.Enabled = true
    
    AtmosphereRemover.OrigLight = {
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        GeographicLatitude = Lighting.GeographicLatitude,
        ExposureCompensation = Lighting.ExposureCompensation,
        GlobalShadows = Lighting.GlobalShadows,
        OutdoorAmbient = Lighting.OutdoorAmbient
    }
    
    AtmosphereRemover.SavedSky = {}
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("BlurEffect") or child:IsA("SunRaysEffect") or child:IsA("ColorCorrectionEffect") or child:IsA("DepthOfFieldEffect") then
            table.insert(AtmosphereRemover.SavedSky, child)
            pcall(function() child.Parent = nil end)
        end
    end
    
    Lighting.FogEnd = 100000
    Lighting.FogStart = 100000
    Lighting.Brightness = 2
    Lighting.ClockTime = 12
    Lighting.GeographicLatitude = 0
    Lighting.ExposureCompensation = 0.5
    Lighting.GlobalShadows = false
    Lighting.OutdoorAmbient = Color3.fromRGB(200,200,200)
    
    local function hideObj(obj)
        if AtmosphereRemover.Watching[obj] then return end
        local success, err = pcall(function()
            if obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") or obj:IsA("Fire") or obj:IsA("Smoke") then
                AtmosphereRemover.Watching[obj] = {t = "eff", e = obj.Enabled}
                obj.Enabled = false
            elseif obj:IsA("BasePart") then
                local n = obj.Name:lower()
                if n:find("rain") or n:find("fog") or n:find("cloud") or n:find("mist") or n:find("smoke") or n:find("haze") then
                    AtmosphereRemover.Watching[obj] = {t = "part", tr = obj.Transparency, cc = obj.CanCollide}
                    obj.Transparency = 1
                    obj.CanCollide = false
                end
            end
        end)
        if not success then warn("AtmRemover hideObj error:", err) end
    end
    
    local function scanWorldAsync()
        local all = workspace:GetDescendants()
        local total = #all
        local index = 1
        local step = 200
        while index <= total do
            for i = index, math.min(index + step - 1, total) do
                hideObj(all[i])
            end
            index = index + step
            if index <= total then task.wait() end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            local char = p.Character
            if char then
                for _, v in ipairs(char:GetDescendants()) do
                    hideObj(v)
                end
            end
        end
    end
    
    AtmosphereRemover.Connections[1] = workspace.DescendantAdded:Connect(hideObj)
    AtmosphereRemover.Connections[2] = Lighting.DescendantAdded:Connect(function(child)
        if child:IsA("Sky") or child:IsA("Atmosphere") then
            pcall(function() child.Parent = nil end)
            table.insert(AtmosphereRemover.SavedSky, child)
        end
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local char = p.Character
            table.insert(AtmosphereRemover.Connections, char.DescendantAdded:Connect(hideObj))
        end
        p.CharacterAdded:Connect(function(char)
            table.insert(AtmosphereRemover.Connections, char.DescendantAdded:Connect(hideObj))
        end)
    end
    table.insert(AtmosphereRemover.Connections, Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function(char)
            table.insert(AtmosphereRemover.Connections, char.DescendantAdded:Connect(hideObj))
        end)
    end))
    
    task.spawn(scanWorldAsync)
end

function DisableAtmosphereRemover()
    if not AtmosphereRemover.Enabled then return end
    AtmosphereRemover.Enabled = false
    
    pcall(function()
        if AtmosphereRemover.OrigLight then
            Lighting.FogEnd = AtmosphereRemover.OrigLight.FogEnd
            Lighting.FogStart = AtmosphereRemover.OrigLight.FogStart
            Lighting.Brightness = AtmosphereRemover.OrigLight.Brightness
            Lighting.ClockTime = AtmosphereRemover.OrigLight.ClockTime
            Lighting.GeographicLatitude = AtmosphereRemover.OrigLight.GeographicLatitude
            Lighting.ExposureCompensation = AtmosphereRemover.OrigLight.ExposureCompensation
            Lighting.GlobalShadows = AtmosphereRemover.OrigLight.GlobalShadows
            Lighting.OutdoorAmbient = AtmosphereRemover.OrigLight.OutdoorAmbient
        end
        for _, s in ipairs(AtmosphereRemover.SavedSky) do
            pcall(function() s.Parent = Lighting end)
        end
        for obj, data in pairs(AtmosphereRemover.Watching) do
            if obj and obj.Parent then
                if data.t == "eff" then obj.Enabled = data.e
                elseif data.t == "part" then obj.Transparency, obj.CanCollide = data.tr, data.cc end
            end
        end
    end)
    
    for _, c in ipairs(AtmosphereRemover.Connections) do
        pcall(function() c:Disconnect() end)
    end
    AtmosphereRemover.Connections = {}
    AtmosphereRemover.Watching = {}
    AtmosphereRemover.SavedSky = {}
end

function CleanupAtmosphereRemover()
    DisableAtmosphereRemover()
end
 -- третье лицо
local thirdPersonDist = 10
local thirdPersonMinDist = 1
local thirdPersonMaxDist = 1000
local thirdPersonZoomSpeed = 30
local thirdPersonConnection = nil
local thirdPersonSaved = nil

function SaveThirdPerson()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local curDist = 10
    if root then
        curDist = (Camera.CFrame.Position - root.Position).Magnitude
    end
    thirdPersonSaved = {
        CameraType = Camera.CameraType,
        CameraSubject = Camera.CameraSubject,
        CameraMode = LocalPlayer.CameraMode,
        MinZoom = LocalPlayer.CameraMinZoomDistance,
        MaxZoom = LocalPlayer.CameraMaxZoomDistance,
        Distance = curDist,
    }
end

function RestoreThirdPerson()
    if not thirdPersonSaved then return end
    local s = thirdPersonSaved
    thirdPersonSaved = nil
    Camera.CameraType = s.CameraType
    Camera.CameraSubject = s.CameraSubject
    LocalPlayer.CameraMode = s.CameraMode
    LocalPlayer.CameraMaxZoomDistance = s.Distance
    LocalPlayer.CameraMinZoomDistance = s.Distance
    task.spawn(function()
        RunService.RenderStepped:Wait()
        if not Settings.ThirdPerson_Enabled and thirdPersonSaved == nil then
            LocalPlayer.CameraMaxZoomDistance = s.MaxZoom
            LocalPlayer.CameraMinZoomDistance = s.MinZoom
        end
    end)
end

function ThirdPersonRenderStep(dt)
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if UserInputService:IsKeyDown(Enum.KeyCode.PageUp) then
        thirdPersonDist = math.min(thirdPersonMaxDist, thirdPersonDist + thirdPersonZoomSpeed * dt)
    elseif UserInputService:IsKeyDown(Enum.KeyCode.PageDown) then
        thirdPersonDist = math.max(thirdPersonMinDist, thirdPersonDist - thirdPersonZoomSpeed * dt)
    end
    LocalPlayer.CameraMaxZoomDistance = thirdPersonDist
    LocalPlayer.CameraMinZoomDistance = thirdPersonDist
end

function EnableThirdPerson()
    if Settings.ThirdPerson_Enabled then return end
    Settings.ThirdPerson_Enabled = true
    SaveThirdPerson()
    local char = LocalPlayer.Character
    
    LocalPlayer.CameraMaxZoomDistance = thirdPersonDist
    LocalPlayer.CameraMinZoomDistance = thirdPersonDist
    if thirdPersonConnection then thirdPersonConnection:Disconnect() end
    thirdPersonConnection = RunService.RenderStepped:Connect(ThirdPersonRenderStep)
end

function DisableThirdPerson()
    if not Settings.ThirdPerson_Enabled then return end
    Settings.ThirdPerson_Enabled = false
    if thirdPersonConnection then
        thirdPersonConnection:Disconnect()
        thirdPersonConnection = nil
    end
    RestoreThirdPerson()
end

function ToggleThirdPerson()
    if Settings.ThirdPerson_Enabled then
        DisableThirdPerson()
    else
        EnableThirdPerson()
    end
    if ToggleRefs.ThirdPerson then
        ToggleRefs.ThirdPerson.SetState(Settings.ThirdPerson_Enabled)
    end
end

-- автокликер
local autoClickerConnection, autoClickerLastClick = nil, 0
local lastAutoClickerEnableTime = 0

function SetAutoClickerEnabled(val)
    if val then
        lastAutoClickerEnableTime = tick()
        if autoClickerConnection then autoClickerConnection:Disconnect() end
        autoClickerLastClick = tick()
        autoClickerPointIndex = 0
        autoClickerConnection = RunService.RenderStepped:Connect(function()
            if not Settings.AutoClicker_Enabled then return end
            local currentTime = tick()
            if currentTime - autoClickerLastClick >= Settings.AutoClicker_Delay then
                fastClick()
                autoClickerLastClick = currentTime
            end
        end)
        Settings.AutoClicker_Enabled = true
        if ToggleRefs.AutoClicker then ToggleRefs.AutoClicker.SetState(true) end
    end
end

-- ESP
local ESPBoxes, NPC_ESP = {}, {}

local SKELETON_BONES = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"LowerTorso", "LeftUpperLeg"}, {"LowerTorso", "RightUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
    {"UpperTorso", "LeftUpperArm"}, {"UpperTorso", "RightUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
    {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
}

function CreateFullESP()
    if not DrawingAvailable then return {} end
    local esp = {}
    pcall(function() esp.Box = Drawing.new("Square"); esp.Box.Visible = false; esp.Box.Filled = false end)
    pcall(function() esp.Tracer = Drawing.new("Line"); esp.Tracer.Visible = false end)
    pcall(function() esp.Name = Drawing.new("Text"); esp.Name.Visible = false; esp.Name.Center = true; esp.Name.Outline = true end)
    pcall(function() esp.HealthBar = Drawing.new("Line"); esp.HealthBar.Visible = false end)
    pcall(function() esp.HealthText = Drawing.new("Text"); esp.HealthText.Visible = false; esp.HealthText.Center = true; esp.HealthText.Outline = true end)
    pcall(function() esp.Distance = Drawing.new("Text"); esp.Distance.Visible = false; esp.Distance.Center = true; esp.Distance.Outline = true end)
    esp.Skeleton = {}
    for _ = 1, #SKELETON_BONES do
        local line
        pcall(function() line = Drawing.new("Line"); line.Visible = false end)
        table.insert(esp.Skeleton, line)
    end
    return esp
end

function RemoveFullESP(esp)
    if not esp then return end
    pcall(function() if esp.Box then esp.Box:Remove() end end)
    pcall(function() if esp.Tracer then esp.Tracer:Remove() end end)
    pcall(function() if esp.Name then esp.Name:Remove() end end)
    pcall(function() if esp.HealthBar then esp.HealthBar:Remove() end end)
    pcall(function() if esp.HealthText then esp.HealthText:Remove() end end)
    pcall(function() if esp.Distance then esp.Distance:Remove() end end)
    if esp.Skeleton then
        for _, line in ipairs(esp.Skeleton) do pcall(function() line:Remove() end) end
    end
end

-- chams
local chamsHighlights = {}; local playerChams = {}
local chamsCharConnections = {}  -- player -> RBXScriptConnection
local chamsDeathConnections = {} -- player -> RBXScriptConnection

function removeCham(player)
    if playerChams[player] then
        pcall(function() playerChams[player]:Destroy() end)
        for i, h in ipairs(chamsHighlights) do
            if h == playerChams[player] then table.remove(chamsHighlights, i); break end
        end
        playerChams[player] = nil
    end
end

function addCham(player)
    if not player or player == LocalPlayer or not Settings.ESP_Chams then return end
    local char = player.Character
    if not char then return end
    if playerChams[player] and playerChams[player].Parent == char then return end
    removeCham(player)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = Settings.AccentColor
    highlight.OutlineColor = Settings.AccentColor
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = char
    playerChams[player] = highlight
    table.insert(chamsHighlights, highlight)
    UpdateChamsBrightness()
end

function setupChamsForPlayer(plr)
    if not plr or plr == LocalPlayer then return end
    if chamsCharConnections[plr] then
        pcall(function() chamsCharConnections[plr]:Disconnect() end)
        chamsCharConnections[plr] = nil
    end
    if chamsDeathConnections[plr] then
        pcall(function() chamsDeathConnections[plr]:Disconnect() end)
        chamsDeathConnections[plr] = nil
    end
    -- Подписка на респавн
    chamsCharConnections[plr] = plr.CharacterAdded:Connect(function(char)
        task.wait(0.3)
        if Settings.ESP_Chams then addCham(plr) end
        local cleanup
        cleanup = char.AncestryChanged:Connect(function()
            if not char.Parent and cleanup then
                cleanup:Disconnect()
                removeCham(plr)
            end
        end)
    end)
    -- Пытаемся применить сразу
    if Settings.ESP_Chams then addCham(plr) end
end

function removeChamsForPlayer(plr)
    if chamsCharConnections[plr] then
        pcall(function() chamsCharConnections[plr]:Disconnect() end)
        chamsCharConnections[plr] = nil
    end
    if chamsDeathConnections[plr] then
        pcall(function() chamsDeathConnections[plr]:Disconnect() end)
        chamsDeathConnections[plr] = nil
    end
    removeCham(plr)
end

function UpdateChams()
    for _, h in ipairs(chamsHighlights) do pcall(function() h:Destroy() end) end
    chamsHighlights = {}; playerChams = {}
    if not Settings.ESP_Chams then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            setupChamsForPlayer(plr)
        end
    end
end

function UpdateChamsBrightness()
    local brightness = Settings.ESP_ChamsBrightness / 100
    for _, h in ipairs(chamsHighlights) do
        pcall(function()
            h.FillTransparency = 1 - brightness * 0.5
            h.OutlineTransparency = 1 - brightness
        end)
    end
end

-- chams для нпс
local npcChamsHighlights = {}
function updateNpcChamsForModel(model)
    if not Settings.ESP_NPC_Chams or not model or not model.Parent then return end
    -- Проверяем, есть ли уже Highlight у этой модели
    for _, h in ipairs(npcChamsHighlights) do
        if h.Parent == model then return end
    end
    local highlight = Instance.new("Highlight")
    highlight.FillColor = Settings.AccentColor
    highlight.OutlineColor = Settings.AccentColor
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = model
    table.insert(npcChamsHighlights, highlight)
    UpdateNpcChamsBrightness()
end

function UpdateNpcChams()
    for _, h in ipairs(npcChamsHighlights) do pcall(function() h:Destroy() end) end
    npcChamsHighlights = {}
    if not Settings.ESP_NPC_Chams then return end
    for _, data in ipairs(npcCacheData) do
        updateNpcChamsForModel(data.Model)
    end
end

function UpdateNpcChamsBrightness()
    local brightness = Settings.ESP_NPC_ChamsBrightness / 100
    -- Чистим мёртвые ссылки
    local alive = {}
    for _, h in ipairs(npcChamsHighlights) do
        if h and h.Parent then
            pcall(function()
                h.FillTransparency = 1 - brightness * 0.5
                h.OutlineTransparency = 1 - brightness
            end)
            table.insert(alive, h)
        end
    end
    npcChamsHighlights = alive
end

-- подписки
-- Ко всем текущим игрокам
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then setupChamsForPlayer(plr) end
end
-- К новым
Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then
        setupChamsForPlayer(plr)
    end
end)
-- Отписка при выходе
Players.PlayerRemoving:Connect(function(plr)
    removeChamsForPlayer(plr)
end)
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if Settings.ESP_Chams then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then addCham(plr) end
        end
    end
    if Settings.ESP_NPC_Chams then
        UpdateNpcChams()
    end
end)

-- Отписки и очистка при выходе игрока
Players.PlayerRemoving:Connect(function(plr)
    if ESPBoxes[plr] then RemoveFullESP(ESPBoxes[plr]); ESPBoxes[plr] = nil end
    removeChamsForPlayer(plr)
    FavoritePlayers[plr] = nil
    Trail.ClearPlayer(plr)
end)

local highlightDrawings = {}; local itemObjects = {}; local lastHighlightUpdate = 0
local itemDescendantAddedCon
function addItemToCache(obj)
    if itemObjects[obj] then return end
    local char = LocalPlayer.Character; if char and (obj:IsDescendantOf(char) or obj == char) then return end
    local pos = nil; local name = obj.Name
    if obj:IsA("Tool") and obj:FindFirstChild("Handle") then pos = obj.Handle.Position
    elseif obj:IsA("Model") and obj:FindFirstChild("Handle") then pos = obj.Handle.Position
    elseif obj:IsA("BasePart") then
        local hasClick = false; pcall(function() hasClick = obj:FindFirstChildWhichIsA("ClickDetector", true) or obj:FindFirstChildWhichIsA("ProximityPrompt", true) end)
        if hasClick or not Settings.Highlight_OnlyInteractive then pos = obj.Position end
    end
    if pos then itemObjects[obj] = {pos = pos, name = name} end
end
function refreshItemCache()
    local toRemove = {}
    for obj, data in pairs(itemObjects) do
        if not obj or not obj.Parent then table.insert(toRemove, obj)
        else
            local newPos = nil
            if obj:IsA("Tool") or obj:IsA("Model") then local handle = obj:FindFirstChild("Handle"); if handle then newPos = handle.Position end
            elseif obj:IsA("BasePart") then newPos = obj.Position end
            if newPos then data.pos = newPos else table.insert(toRemove, obj) end
        end
    end
    for _, obj in ipairs(toRemove) do itemObjects[obj] = nil end
end
function UpdateHighlights()
    if not DrawingAvailable then return end
    local now = tick()
    if now - lastHighlightUpdate < 0.1 then return end
    lastHighlightUpdate = now
    refreshItemCache()
    for _, d in pairs(highlightDrawings) do pcall(function() d:Remove() end) end; highlightDrawings = {}
    if not Settings.Highlight_Objects then return end
    local char = LocalPlayer.Character; if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local myPos = char.HumanoidRootPart.Position
    for obj, data in pairs(itemObjects) do
        local pos = data.pos; if pos then
            local dist = (myPos - pos).Magnitude
            if dist <= Settings.Highlight_Distance then
                local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                if onScreen then
                    pcall(function()
                        local d = Drawing.new("Text")
                        d.Visible = true
                        d.Position = Vector2.new(screenPos.X, screenPos.Y)
                        d.Text = Settings.Highlight_Names and (data.name .. " [" .. math.floor(dist) .. "m]") or "⚡"
                        d.Color = Settings.Highlight_Color
                        d.Size = Settings.Highlight_MaxSize
                        d.Center = true
                        d.Outline = true
                        d.OutlineColor = Color3.new()
                        table.insert(highlightDrawings, d)
                    end)
                end
            end
        end
    end
end

-- основные функции
function UpdateSpeed()
    local char = LocalPlayer.Character; if not char or not char:FindFirstChild("Humanoid") then return end
    char.Humanoid.WalkSpeed = Settings.Speed_Enabled and math.min(Settings.Speed_Value, MAX_SAFE_SPEED) or 16
end

local noclipConnection
function UpdateNoclip()
    if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end

    if not Settings.Noclip_Enabled then
        local char = LocalPlayer.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                root.CFrame = root.CFrame + Vector3.new(0, 3, 0)
                task.wait(0.05)  -- даём физике обновиться
            end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end
        return
    end

    noclipConnection = RunService.RenderStepped:Connect(function()
        if not Settings.Noclip_Enabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end
local flightConnection, flightGyro, flightVel
function UpdateFlight()
    if flightConnection then flightConnection:Disconnect(); flightConnection = nil end
    if flightGyro then pcall(function() flightGyro:Destroy() end); flightGyro = nil end
    if flightVel then pcall(function() flightVel:Destroy() end); flightVel = nil end

    local char = LocalPlayer.Character
    if not char or not Settings.Flight_Enabled then
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                root.Anchored = true
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                task.wait(0.05)
                root.Anchored = false
            end
            local hum = char:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = Settings.Speed_Enabled and math.min(Settings.Speed_Value, MAX_SAFE_SPEED) or 16 end
        end
        return
    end

    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    hum.WalkSpeed = 0
    flightGyro = Instance.new("BodyGyro")
    flightGyro.MaxTorque = Vector3.new(1e5,1e5,1e5)
    flightGyro.CFrame = root.CFrame
    flightGyro.Parent = root
    flightVel = Instance.new("BodyVelocity")
    flightVel.MaxForce = Vector3.new(1e5,1e5,1e5)
    flightVel.Velocity = Vector3.zero
    flightVel.Parent = root

    flightConnection = RunService.RenderStepped:Connect(function()
        if not Settings.Flight_Enabled or not root or not flightGyro then return end
        local moveDir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += Camera.CFrame.RightVector end
        local upDown = Vector3.zero
        if UserInputService:IsKeyDown(Settings.Flight_Key) then upDown += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then upDown += Vector3.new(0,-1,0) end
        local totalDir = moveDir + upDown
        local spd = math.min(Settings.Flight_Speed, MAX_SAFE_FLIGHT)
        flightVel.Velocity = totalDir.Magnitude > 0 and (totalDir.Unit * spd) or Vector3.zero
        local tiltAngle = 0
        if moveDir.Magnitude > 0 then
            tiltAngle = -root.CFrame.LookVector:Dot(moveDir.Unit) * 0.8
        end
        flightGyro.CFrame = root.CFrame * CFrame.Angles(tiltAngle, 0, 0)
    end)
end

local godConnection
function UpdateGodMode()
    if godConnection then godConnection:Disconnect(); godConnection = nil end
    if not Settings.GodMode_Enabled then return end
    godConnection = RunService.RenderStepped:Connect(function()
        if not Settings.GodMode_Enabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChild("Humanoid")
        if not hum then return end
        if hum.Health > 0 then
            if hum.Health < hum.MaxHealth then
                hum.Health = math.min(hum.MaxHealth, hum.Health + 1)
            end
        end
    end)
end


local antiAfkConnection, antiAfkMoving = nil, false
function UpdateAntiAFK()
    if antiAfkConnection then antiAfkConnection:Disconnect(); antiAfkConnection = nil end
    antiAfkMoving = false
    if not Settings.AntiAFK_Enabled then return end
    local lastMove = tick() - Settings.AntiAFK_Interval
    antiAfkConnection = RunService.RenderStepped:Connect(function()
        if not Settings.AntiAFK_Enabled then return end
        local char = LocalPlayer.Character; if not char then return end
        local hum = char:FindFirstChild("Humanoid"); if not hum or hum.Health <= 0 then return end
        if tick() - lastMove >= Settings.AntiAFK_Interval and not antiAfkMoving then
            antiAfkMoving = true
            lastMove = tick()
            task.spawn(function()
                if VIM then
                    VIM:SendKeyEvent(true, Enum.KeyCode.W, false, nil); task.wait(Settings.AntiAFK_StepDuration); VIM:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
                    task.wait(0.1)
                    VIM:SendKeyEvent(true, Enum.KeyCode.S, false, nil); task.wait(Settings.AntiAFK_StepDuration); VIM:SendKeyEvent(false, Enum.KeyCode.S, false, nil)
                end
                antiAfkMoving = false
            end)
        end
    end)
end

-- умный anti-afk
local smartAFKConns = {}
local smartAFKLastActivity = tick()
local smartAFKActive = false
local smartAFKLastMousePos = nil
local smartAFKManualBefore = false

local function DisconnectSmartAFK()
    for _, c in ipairs(smartAFKConns) do
        pcall(function() c:Disconnect() end)
    end
    smartAFKConns = {}
end

function UpdateSmartAntiAFK()
    DisconnectSmartAFK()

    if not Settings.SmartAntiAFK_Enabled then
        smartAFKActive = false
        smartAFKLastMousePos = nil
        Settings.AntiAFK_Enabled = smartAFKManualBefore
        UpdateAntiAFK()
        return
    end

    smartAFKManualBefore = Settings.AntiAFK_Enabled

    smartAFKLastActivity = tick()
    smartAFKActive = false
    Settings.AntiAFK_Enabled = false
    UpdateAntiAFK()

    local function MarkActivity()
        smartAFKLastActivity = tick()
    end

    table.insert(smartAFKConns, UserInputService.InputBegan:Connect(function(input, gp)
        if not Settings.SmartAntiAFK_Enabled then return end
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.MouseButton2
           or input.UserInputType == Enum.UserInputType.MouseButton3 then
            if Settings.SmartAntiAFK_TrackMouse then MarkActivity() end
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            if Settings.SmartAntiAFK_TrackKeyboard then MarkActivity() end
        end
    end))

    table.insert(smartAFKConns, RunService.RenderStepped:Connect(function()
        if not Settings.SmartAntiAFK_Enabled then return end

        if Settings.SmartAntiAFK_TrackMouseMove then
            local mp = UserInputService:GetMouseLocation()
            if smartAFKLastMousePos == nil then
                smartAFKLastMousePos = mp
            elseif (mp - smartAFKLastMousePos).Magnitude > 2 then
                smartAFKLastMousePos = mp
                MarkActivity()
            else
                smartAFKLastMousePos = mp
            end
        else
            smartAFKLastMousePos = nil
        end

        local idle = tick() - smartAFKLastActivity
        local idleTime = tonumber(Settings.SmartAntiAFK_IdleTime) or 30

        if idle >= idleTime and not smartAFKActive then
            -- Пользователь отошёл — включаем Anti-AFK
            smartAFKActive = true
            Settings.AntiAFK_Enabled = true
            UpdateAntiAFK()
        elseif idle < idleTime and smartAFKActive then
            -- Пользователь вернулся — выключаем Anti-AFK
            smartAFKActive = false
            Settings.AntiAFK_Enabled = false
            UpdateAntiAFK()
        end
    end))
end

local freezeConnection
function UpdateFreeze()
    if freezeConnection then freezeConnection:Disconnect(); freezeConnection = nil end
        if not Settings.Freeze_Enabled then
        local char = LocalPlayer.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root and not Settings.Spectating then
                root.Anchored = false
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end
        Settings.Freeze_Position = nil
        if Settings.Freeze_WasFlight then Settings.Flight_Enabled = true; UpdateFlight(); if ToggleRefs.Flight then ToggleRefs.Flight.SetState(true) end end
        if Settings.Freeze_WasNoclip then Settings.Noclip_Enabled = true; UpdateNoclip(); if ToggleRefs.Noclip then ToggleRefs.Noclip.SetState(true) end end
        Settings.Freeze_WasFlight = false; Settings.Freeze_WasNoclip = false
        return
    end
    Settings.Freeze_WasFlight = Settings.Flight_Enabled
    Settings.Freeze_WasNoclip = Settings.Noclip_Enabled
    if Settings.Flight_Enabled then Settings.Flight_Enabled = false; UpdateFlight(); if ToggleRefs.Flight then ToggleRefs.Flight.SetState(false) end end
    if Settings.Noclip_Enabled then Settings.Noclip_Enabled = false; UpdateNoclip(); if ToggleRefs.Noclip then ToggleRefs.Noclip.SetState(false) end end

    local char = LocalPlayer.Character; if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
    root.Anchored = true
    Settings.Freeze_Position = root.CFrame
    freezeConnection = RunService.RenderStepped:Connect(function()
        if not Settings.Freeze_Enabled then return end
        local c = LocalPlayer.Character
        if not c then Settings.Freeze_Enabled = false; UpdateFreeze(); return end
        local h = c:FindFirstChild("Humanoid")
        if h and h.Health <= 0 then Settings.Freeze_Enabled = false; UpdateFreeze(); return end
        local r = c:FindFirstChild("HumanoidRootPart")
        if r and Settings.Freeze_Position then
            r.CFrame = Settings.Freeze_Position
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end

-- аим и триггер

local lastShot = 0
local triggerFired = false

-- Триггербот
local triggerDot = nil
local triggerReactionStart = nil
local triggerLastTarget = nil
local mouse1Held = false

-- Реалистичная наводка
local aimRealisticState = {
    angularVelocity = Vector3.zero,
    targetPrevPos = nil,
    targetPrevTime = nil,
    targetVelocity = Vector3.zero,
    noiseSeed = math.random(),
    lastTarget = nil,
    reactionTimer = 0,
}

local aimVisibilityCache = {}
local lastBHopJump = 0
function IsAimVisible(part)

    if not Settings.Aim_VisibleCheck then return true end
    if not RaycastParamsClass then return true end
    local char = part.Parent
    if not char then return false end
    local lc = LocalPlayer.Character
    if not lc or not lc:FindFirstChild("Head") then return false end

    local cached = aimVisibilityCache[part]
    if cached and (tick() - cached.time) < 0.15 then
        return cached.value
    end

    local origin = Camera.CFrame.Position
    local direction = part.Position - origin
    local distance = direction.Magnitude
    if distance < 0.01 then
        aimVisibilityCache[part] = {value = true, time = tick()}
        return true
    end

    local rayParams = RaycastParamsClass.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local ignoreList = {lc}
    if Settings.Aim_IgnorePlayersInRaycast then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character and plr.Character ~= lc then
                table.insert(ignoreList, plr.Character)
            end
        end
    end
    rayParams.FilterDescendantsInstances = ignoreList

    local result = workspace:Raycast(origin, direction.Unit * distance, rayParams)
    local visible = (result == nil or result.Instance:IsDescendantOf(char))
    aimVisibilityCache[part] = {value = visible, time = tick()}
    return visible
end

function GetTarget()
    local mp = UserInputService:GetMouseLocation()
    local bestTarget = nil
    local bestScreenDist = Settings.Aim_FOV
    local bestWorldDist = math.huge

    local localChar = LocalPlayer.Character
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

    local function processTargetChar(char)
        if not char then return end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local candidateParts = {}
        if Settings.Aim_Part == "Auto" then
            local allParts = {}
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and not part:IsA("Accessory") then
                    local sp, onScr = Camera:WorldToViewportPoint(part.Position)
                    if onScr and IsAimVisible(part) then
                        table.insert(allParts, {part = part, screenPos = Vector2.new(sp.X, sp.Y)})
                    end
                end
            end
            if #allParts > 0 then
                local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
                for _, cand in ipairs(allParts) do
                    minX = math.min(minX, cand.screenPos.X)
                    maxX = math.max(maxX, cand.screenPos.X)
                    minY = math.min(minY, cand.screenPos.Y)
                    maxY = math.max(maxY, cand.screenPos.Y)
                end
                local bboxW, bboxH = maxX - minX, maxY - minY
                local margin = (bboxW > 20 or bboxH > 20) and Settings.Aim_PartAutoMargin or 0
                for _, cand in ipairs(allParts) do
                    local isMarginX = (cand.screenPos.X - minX < margin) or (maxX - cand.screenPos.X < margin)
                    local isMarginY = (cand.screenPos.Y - minY < margin) or (maxY - cand.screenPos.Y < margin)
                    if not (isMarginX or isMarginY) then
                        table.insert(candidateParts, cand)
                    end
                end
                if #candidateParts == 0 then
                    candidateParts = allParts
                end
            end
        else
            local part = char:FindFirstChild(Settings.Aim_Part)
            if part then
                local sp, onScr = Camera:WorldToViewportPoint(part.Position)
                if onScr and IsAimVisible(part) then
                    table.insert(candidateParts, {part = part, screenPos = Vector2.new(sp.X, sp.Y)})
                end
            end
        end

        for _, cand in ipairs(candidateParts) do
            local screenDist = (cand.screenPos - mp).Magnitude
            if screenDist < bestScreenDist then
                local worldDist = math.huge
                if localRoot and char:FindFirstChild("HumanoidRootPart") then
                    worldDist = (localRoot.Position - char.HumanoidRootPart.Position).Magnitude
                end
                local threshold = 5
                if (screenDist < bestScreenDist - threshold) or
                   (math.abs(screenDist - bestScreenDist) <= threshold and worldDist < bestWorldDist) then
                    bestTarget = cand.part
                    bestScreenDist = screenDist
                    bestWorldDist = worldDist
                end
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local teamCheckPass = not Settings.Aim_TeamCheck or (not LocalPlayer.Team or not plr.Team or (plr.Team ~= LocalPlayer.Team))
            if teamCheckPass then
                processTargetChar(plr.Character)
            end
        end
    end

    if Settings.Aim_TargetNPCs then
        for _, data in ipairs(npcCacheData) do
            processTargetChar(data.Model)
        end
    end

    return bestTarget
end

function GetTriggerTarget()
    local mousePos = UserInputService:GetMouseLocation()
    local radius = 10  -- радиус точки (в пикселях)
    local bestDist = radius
    local bestPart = nil

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local teamCheckPass = not Settings.Aim_TeamCheck or (not LocalPlayer.Team or not plr.Team or (plr.Team ~= LocalPlayer.Team))
            if teamCheckPass then
                local char = plr.Character
                if char then
                    local hum = char:FindFirstChild("Humanoid")
                    if hum and hum.Health > 0 then
                        for _, part in ipairs(char:GetDescendants()) do
                            if part:IsA("BasePart") and not part:IsA("Accessory") then
                                local sp, onScr = Camera:WorldToViewportPoint(part.Position)
                                if onScr then
                                    local screenDist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                                    if screenDist <= radius and screenDist < bestDist then
                                        if not Settings.Trigger_VisibleCheck or IsAimVisible(part) then
                                            bestDist = screenDist
                                            bestPart = part
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

    if Settings.Trigger_TargetNPCs then
        for _, data in ipairs(npcCacheData) do
            local model = data.Model
            if model and model.Parent then
                local hum = model:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 then
                    for _, part in ipairs(model:GetDescendants()) do
                        if part:IsA("BasePart") and not part:IsA("Accessory") then
                            local sp, onScr = Camera:WorldToViewportPoint(part.Position)
                            if onScr then
                                local screenDist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                                if screenDist <= radius and screenDist < bestDist then
                                    if not Settings.Trigger_VisibleCheck or IsAimVisible(part) then
                                        bestDist = screenDist
                                        bestPart = part
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return bestPart
end

-- trails

Trail = {
    players = {},
    npcs = {},
    lastCameraCF = nil,
    totalLines = 0,
}

function Trail.CameraMoved(cf)
    if not Trail.lastCameraCF then return true end
    local dp = (cf.Position - Trail.lastCameraCF.Position).Magnitude
    if dp > 0.05 then return true end
    if cf.LookVector:Dot(Trail.lastCameraCF.LookVector) < 0.9999 then return true end
    return false
end

function Trail.ClearPlayer(plr)
    local t = Trail.players[plr]
    if not t then return end
    for _, line in ipairs(t.lines) do
        pcall(function() line:Remove() end)
    end
    Trail.totalLines = math.max(0, Trail.totalLines - #t.lines)
    Trail.players[plr] = nil
end

function Trail.ClearNpc(model)
    local t = Trail.npcs[model]
    if not t then return end
    for _, line in ipairs(t.lines) do
        pcall(function() line:Remove() end)
    end
    Trail.totalLines = math.max(0, Trail.totalLines - #t.lines)
    Trail.npcs[model] = nil
end

function Trail.Project(trail, cameraCF)
    local positions = trail.positions
    local lines = trail.lines
    local n = #positions
    if n < 2 then return end

    local scr = {}
    local anyFront = false
    for i = 1, n do
        local s, on = Camera:WorldToViewportPoint(positions[i])
        if s.Z > 0 then
            scr[i] = Vector2.new(s.X, s.Y)
            anyFront = true
        else
            scr[i] = false
        end
    end

    if not anyFront then
        for i = 1, #lines do
            if lines[i].Visible then lines[i].Visible = false end
        end
        return
    end

    local color = trail.color
    local thickness = trail.thickness
    for i = 1, #lines do
        local line = lines[i]
        local s1, s2 = scr[i], scr[i + 1]
        if s1 and s2 and s1 ~= false and s2 ~= false then
            line.From = s1
            line.To = s2
            if not line.Visible then line.Visible = true end
        else
            if line.Visible then line.Visible = false end
        end
        if line.Color ~= color then line.Color = color end
        if line.Thickness ~= thickness then line.Thickness = thickness end
    end
end

function Trail.UpdatePlayers(cameraMoved, cameraCF)
    if not DrawingAvailable then return end

    if not Settings.ESP_Trails then
        if next(Trail.players) then
            for plr, _ in pairs(Trail.players) do Trail.ClearPlayer(plr) end
        end
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and root and IsEnemy(plr) then
                local color = Settings.ESP_TracerColor
                if Settings.ESP_TeamColors and plr.Team then
                    color = plr.Team.TeamColor.Color
                end
                local thickness = Settings.ESP_TrailThickness
                local pointDist = Settings.ESP_TrailPointDist
                local maxPoints = Settings.ESP_TrailMaxPoints

                local pos = root.Position
                local t = Trail.players[plr]
                if not t then
                    t = { positions = {}, lines = {}, lastPos = nil, color = color, thickness = thickness }
                    Trail.players[plr] = t
                end

                local colorChanged = (t.color ~= color) or (t.thickness ~= thickness)
                t.color = color
                t.thickness = thickness

                local added = false
                if (not t.lastPos) or (pos - t.lastPos).Magnitude >= pointDist then
                    table.insert(t.positions, pos)
                    t.lastPos = pos
                    added = true

                    if #t.positions >= 2 then
                        local newLine = nil
                        pcall(function() newLine = Drawing.new("Line") end)
                        if newLine then
                            newLine.Visible = false
                            newLine.Thickness = thickness
                            newLine.Color = color
                            table.insert(t.lines, newLine)
                            Trail.totalLines = Trail.totalLines + 1
                        end
                    end

                    while #t.positions > maxPoints do
                        table.remove(t.positions, 1)
                        local oldLine = table.remove(t.lines, 1)
                        if oldLine then
                            pcall(function() oldLine:Remove() end)
                            Trail.totalLines = math.max(0, Trail.totalLines - 1)
                        end
                    end
                end

                if colorChanged then
                    for i = 1, #t.lines do
                        t.lines[i].Color = color
                        t.lines[i].Thickness = thickness
                    end
                end

                if cameraMoved or added then
                    Trail.Project(t, cameraCF)
                end
            else
                if Trail.players[plr] then Trail.ClearPlayer(plr) end
            end
        end
    end

    for plr, _ in pairs(Trail.players) do
        if not plr.Parent then Trail.ClearPlayer(plr) end
    end
end

function Trail.UpdateNpcs(cameraMoved, cameraCF)
    if not DrawingAvailable then return end

    if not Settings.ESP_NPC_Trails then
        if next(Trail.npcs) then
            for model, _ in pairs(Trail.npcs) do Trail.ClearNpc(model) end
        end
        return
    end

    for _, data in ipairs(npcCacheData) do
        local model = data.Model
        if model and model.Parent then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local root = model.PrimaryPart or (hum and hum.RootPart)
            if hum and hum.Health > 0 and root then
                local color = Settings.NPC_TracerColor
                local thickness = Settings.ESP_TrailThickness
                local pointDist = Settings.ESP_NPC_TrailPointDist
                local maxPoints = Settings.ESP_NPC_TrailMaxPoints

                local pos = root.Position
                local t = Trail.npcs[model]
                if not t then
                    t = { positions = {}, lines = {}, lastPos = nil, color = color, thickness = thickness }
                    Trail.npcs[model] = t
                end

                local colorChanged = (t.color ~= color) or (t.thickness ~= thickness)
                t.color = color
                t.thickness = thickness

                local added = false
                if (not t.lastPos) or (pos - t.lastPos).Magnitude >= pointDist then
                    table.insert(t.positions, pos)
                    t.lastPos = pos
                    added = true

                    if #t.positions >= 2 then
                        local newLine = nil
                        pcall(function() newLine = Drawing.new("Line") end)
                        if newLine then
                            newLine.Visible = false
                            newLine.Thickness = thickness
                            newLine.Color = color
                            table.insert(t.lines, newLine)
                            Trail.totalLines = Trail.totalLines + 1
                        end
                    end

                    while #t.positions > maxPoints do
                        table.remove(t.positions, 1)
                        local oldLine = table.remove(t.lines, 1)
                        if oldLine then
                            pcall(function() oldLine:Remove() end)
                            Trail.totalLines = math.max(0, Trail.totalLines - 1)
                        end
                    end
                end

                if colorChanged then
                    for i = 1, #t.lines do
                        t.lines[i].Color = color
                        t.lines[i].Thickness = thickness
                    end
                end

                if cameraMoved or added then
                    Trail.Project(t, cameraCF)
                end
            else
                if Trail.npcs[model] then Trail.ClearNpc(model) end
            end
        else
            if model then Trail.ClearNpc(model) end
        end
    end

    for model, _ in pairs(Trail.npcs) do
        if not model.Parent then Trail.ClearNpc(model) end
    end
end

function Trail.Update()
    if not DrawingAvailable then return end
    local cameraCF = Camera.CFrame
    local moved = Trail.CameraMoved(cameraCF)
    Trail.lastCameraCF = cameraCF

    Trail.UpdatePlayers(moved, cameraCF)
    Trail.UpdateNpcs(moved, cameraCF)
end


-- главный цикл
local FOVCircle
if DrawingAvailable then pcall(function() FOVCircle = Drawing.new("Circle") end) end
if FOVCircle then FOVCircle.Visible = false; FOVCircle.Thickness = 1.5; FOVCircle.NumSides = 60; FOVCircle.Filled = false end
 -- прицел
Crosshair = {
    Outline = {},  
    Main = {},
    DotOutline = nil,
    DotFill = nil,
}
if DrawingAvailable then
    for i = 1, 4 do
        local o
        pcall(function() o = Drawing.new("Line"); o.Visible = false end)
        Crosshair.Outline[i] = o
    end
    for i = 1, 4 do
        local m
        pcall(function() m = Drawing.new("Line"); m.Visible = false end)
        Crosshair.Main[i] = m
    end
    pcall(function()
        Crosshair.DotOutline = Drawing.new("Circle")
        Crosshair.DotOutline.Visible = false
        Crosshair.DotOutline.Filled = false
        Crosshair.DotOutline.NumSides = 24
    end)
    pcall(function()
        Crosshair.DotFill = Drawing.new("Circle")
        Crosshair.DotFill.Visible = false
        Crosshair.DotFill.Filled = true
        Crosshair.DotFill.NumSides = 24
    end)
end

local fpsText
if DrawingAvailable then pcall(function() fpsText = Drawing.new("Text") end) end
if fpsText then fpsText.Visible = false; fpsText.Position = Vector2.new(10,10); fpsText.Size = 18; fpsText.Color = Color3.new(0,1,0); fpsText.Outline = true end

local fpsFrames = 0; local fpsTime = tick(); local frameCounter = 0; local npcFrameCounter = 0
local lastTabListRefresh = 0
local tpRefreshStep = 0
local specRefreshStep = 0
function UpdateFPSPingDisplay()
    if not fpsText then return end
    local text = ""
    if Settings.ShowFPS then
        text = text .. "FPS: " .. fpsFrames
    end
    if Settings.ShowPing then
        local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
        if text ~= "" then text = text .. " | " end
        text = text .. "Ping: " .. ping .. "ms"
    end
    fpsText.Text = text
    fpsText.Visible = (Settings.ShowFPS or Settings.ShowPing)
end
function IsEnemy(player)
    if not Settings.ESP_TeamCheck then return true end
    local myTeam = LocalPlayer.Team; local plrTeam = player.Team; if not myTeam or not plrTeam then return true end
    return myTeam ~= plrTeam
end

local visibilityCache = {}
local function IsVisible(part)
    if not Settings.ESP_VisibilityCheck then return true end
    if not RaycastParamsClass then return true end
    local char = part.Parent; if not char then return false end
    local lc = LocalPlayer.Character; if not lc or not lc:FindFirstChild("Head") then return false end
    local key = part
    local cache = visibilityCache[key]
    if cache and tick() - cache.time < 0.1 then return cache.value end
    local origin = Camera.CFrame.Position; local direction = (part.Position - origin); local distance = direction.Magnitude
    if distance < 0.01 then visibilityCache[key] = {value = true, time = tick()}; return true end
    local rayParams = RaycastParamsClass.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {lc}
    local result = workspace:Raycast(origin, direction.Unit * distance, rayParams)
    local val = result and result.Instance:IsDescendantOf(char) or not result
    visibilityCache[key] = {value = val, time = tick()}
    return val
end

savedMouseBehavior = nil

function FormatHPText(hum)
    return tostring(math.floor(hum.Health)) .. " HP"
end
local mainRenderConnection
mainRenderConnection = RunService.RenderStepped:Connect(function(dt)
    local ___ok, ___err = pcall(function()
    if not MenuLoaded then return end
    if CustomCursor and CustomCursor.Visible then
        local mousePos = UserInputService:GetMouseLocation()
        CustomCursor.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
    end
    if Settings.BHop_Enabled then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local spaceHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space)
                local onGround = (hum.FloorMaterial ~= Enum.Material.Air)
                if spaceHeld and onGround then
                    if tick() - lastBHopJump >= Settings.BHop_Delay then
                        lastBHopJump = tick()
                        pcall(function()
                            hum:ChangeState(Enum.HumanoidStateType.Jumping)
                        end)
                    end
                end
            end
        end
    end
    if openPaletteData and openPaletteData.palette.Visible then
        local btn = openPaletteData.button
        local pal = openPaletteData.palette
        local btnPos = btn.AbsolutePosition
        local btnSize = btn.AbsoluteSize
        local palSize = Vector2.new(198, 236)  

        local screenSize = Camera.ViewportSize

        local desiredX = btnPos.X + btnSize.X + 5
        local desiredY = btnPos.Y

        local maxX = screenSize.X - palSize.X - 5
        local minX = 5
        if desiredX > maxX then desiredX = maxX end
        if desiredX < minX then desiredX = minX end

        local maxY = screenSize.Y - palSize.Y - 5
        local minY = 5
        if desiredY > maxY then desiredY = maxY end
        if desiredY < minY then desiredY = minY end

        pal.Position = UDim2.new(0, desiredX, 0, desiredY)
    end  

  
    frameCounter = frameCounter + 1    npcFrameCounter = npcFrameCounter + 1
            fpsFrames = fpsFrames + 1
    if tick() - fpsTime >= 1 then
        UpdateFPSPingDisplay()
        fpsFrames = 0
        fpsTime = tick()
    end

    if Settings.Fullbright_Enabled then
        local brightnessVal = 1 + (Settings.Fullbright_Brightness - 1) * (MAX_FULLBRIGHT_BRIGHTNESS - 1) / 99
        pcall(function() Lighting.Brightness = math.min(brightnessVal, MAX_FULLBRIGHT_BRIGHTNESS) end)
    end

    -- FOV Changer
    if Settings.FOV_Enabled then
        if Camera.FieldOfView ~= Settings.FOV_Value then
            Camera.FieldOfView = Settings.FOV_Value
        end
    end

    if Settings.CursorUnlock_Enabled then
        if not savedMouseBehavior then
            savedMouseBehavior = UserInputService.MouseBehavior
        end
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if not ESPBoxes[plr] then ESPBoxes[plr] = CreateFullESP() end
        end
    end
    for plr, esp in pairs(ESPBoxes) do
        if not Players:FindFirstChild(plr.Name) or plr == LocalPlayer then RemoveFullESP(esp); ESPBoxes[plr] = nil end
    end

    if frameCounter % 2 == 0 and Settings.ESP_Enabled then
        local lc = LocalPlayer.Character
        for plr, esp in pairs(ESPBoxes) do
            if not esp then continue end
            if esp.Skeleton then
                for _, line in ipairs(esp.Skeleton) do
                    if line.Visible then line.Visible = false end
                end
            end
            local char = plr.Character
            local passDistance = true

            if Settings.ESP_LimitDistance and char and lc and lc:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("HumanoidRootPart") then
                passDistance = (lc.HumanoidRootPart.Position - char.HumanoidRootPart.Position).Magnitude <= Settings.ESP_MaxDistance
            end
            if not IsEnemy(plr) or not char or not passDistance then
                pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                if esp.Skeleton then for _, line in ipairs(esp.Skeleton) do line.Visible = false end end
            else
                local hum = char:FindFirstChild("Humanoid"); if not hum or hum.Health <= 0 then
                    pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                    pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                    pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                    if esp.Skeleton then for _, line in ipairs(esp.Skeleton) do line.Visible = false end end
                else
                    local head = char:FindFirstChild("Head")
                    if not head then
                        pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                        pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                        pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                        if esp.Skeleton then for _, line in ipairs(esp.Skeleton) do line.Visible = false end end
                    else
                        if Settings.ESP_VisibilityCheck and not IsVisible(head) then
                            pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                            pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                            pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                            if esp.Skeleton then for _, line in ipairs(esp.Skeleton) do line.Visible = false end end
                        else
                            local top = head.Position + Vector3.new(0, head.Size.Y/2, 0)
                            local root = char:FindFirstChild("HumanoidRootPart")
                            local bot = root and (root.Position - Vector3.new(0, hum.HipHeight, 0))
                            if not root or not bot then
                                pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                                pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                                pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                            else
                                local sTop, vTop = Camera:WorldToViewportPoint(top)
                                local sBot, vBot = Camera:WorldToViewportPoint(bot)
                                if not vTop or not vBot then
                                    pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                                    pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                                    pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                                else
                                    local boxTop, boxBot = sTop.Y, sBot.Y
                                    local boxH = math.abs(boxBot - boxTop)
                                    local boxW = boxH * 0.4
                                    local boxLeft = sTop.X - boxW/2
                                    local viewport = Camera.ViewportSize
                                    if boxLeft > viewport.X or (boxLeft + boxW) < 0 or boxTop > viewport.Y or (boxBot) < 0 then
                                        pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                                        pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                                        pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                                        if esp.Skeleton then for _, line in ipairs(esp.Skeleton) do line.Visible = false end end
                                    else
                                        local hpPct = hum.Health / hum.MaxHealth
                                        pcall(function()
                                            if Settings.ESP_Boxes then
                                                esp.Box.Visible = true; esp.Box.Position = Vector2.new(boxLeft, boxTop); esp.Box.Size = Vector2.new(boxW, boxH)
                                                local c = Settings.ESP_BoxColor
                                                if Settings.ESP_TeamColors then local tc; pcall(function() tc = plr.TeamColor and plr.TeamColor.Color end); if tc then c = tc end end
                                                esp.Box.Color = c; esp.Box.Thickness = Settings.ESP_BoxThickness
                                            else esp.Box.Visible = false end
                                        end)
                                        pcall(function()
                                            if Settings.ESP_Distance and lc and lc:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("HumanoidRootPart") then
                                                local dist = math.floor((lc.HumanoidRootPart.Position - char.HumanoidRootPart.Position).Magnitude)
                                                esp.Distance.Visible = true; esp.Distance.Position = Vector2.new(sTop.X, boxBot + 17)
                                                esp.Distance.Text = dist .. "m"; esp.Distance.Size = Settings.ESP_DistanceSize; esp.Distance.Color = Settings.ESP_DistanceColor
                                            else esp.Distance.Visible = false end
                                        end)
                                        -- SKELETON ESP
                                        if esp.Skeleton then
                                            if Settings.ESP_Skeleton then
                                                local partCache = {}
                                                for _, part in ipairs(char:GetChildren()) do
                                                    if part:IsA("BasePart") then partCache[part.Name] = part end
                                                end
                                                for i, bone in ipairs(SKELETON_BONES) do
                                                    local a = partCache[bone[1]]
                                                    local b = partCache[bone[2]]
                                                    local line = esp.Skeleton[i]
                                                    if line and a and b then
                                                        local s1, v1 = Camera:WorldToViewportPoint(a.Position)
                                                        local s2, v2 = Camera:WorldToViewportPoint(b.Position)
                                                        if v1 and v2 then
                                                            line.From = Vector2.new(s1.X, s1.Y)
                                                            line.To = Vector2.new(s2.X, s2.Y)
                                                            line.Color = Settings.ESP_SkeletonColor
                                                            line.Thickness = Settings.ESP_SkeletonThickness
                                                            line.Visible = true
                                                        else
                                                            line.Visible = false
                                                        end
                                                    elseif line then
                                                        line.Visible = false
                                                    end
                                                end
                                            else
                                                for _, line in ipairs(esp.Skeleton) do line.Visible = false end
                                            end
                                        end
                                        pcall(function()
                                            if Settings.ESP_Tracers then
                                                esp.Tracer.Visible = true; esp.Tracer.From = Vector2.new(viewport.X/2, viewport.Y); esp.Tracer.To = Vector2.new(sTop.X, boxBot)
                                                esp.Tracer.Color = Settings.ESP_TracerColor; esp.Tracer.Thickness = Settings.ESP_TracerThickness
                                            else esp.Tracer.Visible = false end
                                        end)
                                        pcall(function()
                                            if Settings.ESP_Names then
                                                esp.Name.Visible = true; esp.Name.Position = Vector2.new(sTop.X, boxTop - 16); esp.Name.Text = plr.DisplayName
                                                esp.Name.Size = Settings.ESP_NameSize; esp.Name.Color = Settings.ESP_NameColor
                                            else esp.Name.Visible = false end
                                        end)
                                        pcall(function()
                                            if Settings.ESP_HealthMode == "Bar" then
                                                local barX = boxLeft - Settings.ESP_HealthBarWidth - Settings.ESP_HealthBarOffset
                                                local healthY = boxBot + (boxTop - boxBot) * hpPct
                                                local color = hpPct > 0.5 and Color3.new(1 - (hpPct-0.5)*2, 1, 0) or Color3.new(1, hpPct*2, 0)
                                                esp.HealthBar.Visible = true; esp.HealthBar.From = Vector2.new(barX, boxBot); esp.HealthBar.To = Vector2.new(barX, healthY)
                                                esp.HealthBar.Color = color; esp.HealthBar.Thickness = Settings.ESP_HealthBarWidth
                                                esp.HealthText.Visible = false
                                            elseif Settings.ESP_HealthMode == "Text" then
                                                esp.HealthText.Visible = true; esp.HealthText.Position = Vector2.new(sTop.X, boxBot + 4)

esp.HealthText.Text = FormatHPText(hum); esp.HealthText.Size = Settings.ESP_HealthTextSize; esp.HealthText.Color = Settings.ESP_HealthTextColor
                                                esp.HealthBar.Visible = false
                                            else
                                                esp.HealthBar.Visible = false; esp.HealthText.Visible = false
                                            end
                                        end)
                                        pcall(function()
                                            if Settings.ESP_Distance and lc and lc:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("HumanoidRootPart") then
                                                local dist = math.floor((lc.HumanoidRootPart.Position - char.HumanoidRootPart.Position).Magnitude)
                                                esp.Distance.Visible = true; esp.Distance.Position = Vector2.new(sTop.X, boxBot + 17)
                                                esp.Distance.Text = dist .. "m"; esp.Distance.Size = Settings.ESP_DistanceSize; esp.Distance.Color = Settings.ESP_DistanceColor
                                            else esp.Distance.Visible = false end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        else
        if not Settings.ESP_Enabled then
            for _, esp in pairs(ESPBoxes) do
                pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                if esp.Skeleton then for _, line in ipairs(esp.Skeleton) do line.Visible = false end end
            end
        end
    end

    if Settings.ESP_NPCs and npcFrameCounter % 3 == 0 then
        local lc = LocalPlayer.Character
        for _, data in ipairs(npcCacheData) do
            local model = data.Model
            if model.Parent then
                if not NPC_ESP[model] then NPC_ESP[model] = CreateFullESP() end
                local esp = NPC_ESP[model]
                if not esp then continue end
                local hum = model:FindFirstChild("Humanoid")
                local health = hum and hum.Health or 100
                if hum and health > 0 or not hum then
                    local pos = Vector3.zero
                    if model.PrimaryPart then pos = model.PrimaryPart.Position
                    else pcall(function() pos = model:GetPivot().Position end) end
                    local dist = (lc and lc:FindFirstChild("HumanoidRootPart") and (lc.HumanoidRootPart.Position - pos).Magnitude) or 0
                    if dist <= Settings.ESP_NPC_MaxDistance then
                        local head = model:FindFirstChild("Head")
                        local top, bot
                        if head then
                            top = head.Position + Vector3.new(0, head.Size.Y/2, 0)
                            bot = head.Position - Vector3.new(0, 2, 0)
                        elseif model.PrimaryPart then
                            top = model.PrimaryPart.Position + Vector3.new(0, 2, 0)
                            bot = model.PrimaryPart.Position - Vector3.new(0, 2, 0)
                        end
                        if top and bot and (not Settings.ESP_VisibilityCheck or IsVisible(head or model.PrimaryPart)) then
                            local szBoxThick     = Settings.ESP_NPC_CustomSizes and Settings.ESP_NPC_BoxThickness or Settings.ESP_BoxThickness
                            local szNameSize     = Settings.ESP_NPC_CustomSizes and Settings.ESP_NPC_NameSize or Settings.ESP_NameSize
                            local szHealthBarW   = Settings.ESP_NPC_CustomSizes and Settings.ESP_NPC_HealthBarWidth or Settings.ESP_HealthBarWidth
                            local szHealthBarOff = Settings.ESP_NPC_CustomSizes and Settings.ESP_NPC_HealthBarOffset or Settings.ESP_HealthBarOffset
                            local szHealthTextSz = Settings.ESP_NPC_CustomSizes and Settings.ESP_NPC_HealthTextSize or Settings.ESP_HealthTextSize
                            local szDistanceSz   = Settings.ESP_NPC_CustomSizes and Settings.ESP_NPC_DistanceSize or Settings.ESP_DistanceSize
                            local sTop, vTop = Camera:WorldToViewportPoint(top); local sBot, vBot = Camera:WorldToViewportPoint(bot)

                            if vTop and vBot then
                                local boxTop, boxBot = sTop.Y, sBot.Y
                                local boxH = math.abs(boxBot - boxTop); local boxW = boxH * 0.4; local boxLeft = sTop.X - boxW/2
                                local viewport = Camera.ViewportSize
                                if not (boxLeft > viewport.X or (boxLeft + boxW) < 0 or boxTop > viewport.Y or boxBot < 0) then
                                    pcall(function() esp.Box.Visible = true; esp.Box.Position = Vector2.new(boxLeft, boxTop); esp.Box.Size = Vector2.new(boxW, boxH); esp.Box.Color = Settings.NPC_BoxColor; esp.Box.Thickness = szBoxThick end)

                                    pcall(function() if Settings.ESP_NPC_Tracers then esp.Tracer.Visible = true; esp.Tracer.From = Vector2.new(viewport.X/2, viewport.Y); esp.Tracer.To = Vector2.new(sTop.X, boxBot); esp.Tracer.Color = Settings.NPC_TracerColor; esp.Tracer.Thickness = Settings.ESP_TracerThickness else esp.Tracer.Visible = false end end)
                                    pcall(function() if Settings.ESP_NPC_Names then esp.Name.Visible = true; esp.Name.Position = Vector2.new(sTop.X, boxTop - 16); esp.Name.Text = data.Name; esp.Name.Size = szNameSize; esp.Name.Color = Settings.NPC_NameColor else esp.Name.Visible = false end end)
                                    pcall(function()          
                                        local npcMaxHp = (hum and hum.MaxHealth) or 100
                                        local hpPct = math.clamp(health / npcMaxHp, 0, 1)
                                        if Settings.ESP_NPC_HealthMode == "Bar" then
                                            local barX = boxLeft - szHealthBarW - szHealthBarOff
                                            local healthY = boxBot + (boxTop - boxBot) * hpPct
                                            local color = hpPct > 0.5 and Color3.new(1 - (hpPct-0.5)*2, 1, 0) or Color3.new(1, hpPct*2, 0)
                                            esp.HealthBar.Visible = true
                                            esp.HealthBar.From = Vector2.new(barX, boxBot)
                                            esp.HealthBar.To = Vector2.new(barX, healthY)
                                            esp.HealthBar.Color = color
                                            esp.HealthBar.Thickness = szHealthBarW
                                            esp.HealthText.Visible = false
                                        elseif Settings.ESP_NPC_HealthMode == "Text" then
                                            esp.HealthText.Visible = true
                                            esp.HealthText.Position = Vector2.new(sTop.X, boxBot + 4)
                                            esp.HealthText.Text = tostring(math.floor(health)) .. " HP"
                                            esp.HealthText.Size = szHealthTextSz
                                            esp.HealthText.Color = Settings.ESP_HealthTextColor
                                            esp.HealthBar.Visible = false
                                        else
                                            esp.HealthBar.Visible = false
                                            esp.HealthText.Visible = false
                                        end
                                    end)

                                    pcall(function()
                                        if Settings.ESP_NPC_Distance then
                                            esp.Distance.Visible = true
                                            esp.Distance.Position = Vector2.new(sTop.X, boxBot + 17)
                                            esp.Distance.Text = math.floor(dist) .. "m"
                                            esp.Distance.Size = szDistanceSz
                                            esp.Distance.Color = Settings.ESP_DistanceColor
                                        else
                                            esp.Distance.Visible = false
                                        end
                                    end)
                                else
                                    pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                                    pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                                    pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                                end
                            else
                                pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                                pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                                pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                            end
                        else
                            pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                            pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                            pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                        end
                    else
                        pcall(function() esp.Box.Visible = false end); pcall(function() esp.Tracer.Visible = false end)
                        pcall(function() esp.Name.Visible = false end); pcall(function() esp.HealthBar.Visible = false end)
                        pcall(function() esp.HealthText.Visible = false end); pcall(function() esp.Distance.Visible = false end)
                    end
                else
                    RemoveFullESP(esp); NPC_ESP[model] = nil
                end
            else
                if NPC_ESP[model] then RemoveFullESP(NPC_ESP[model]); NPC_ESP[model] = nil end
            end
        end
    else
        if not Settings.ESP_NPCs then
            for model, esp in pairs(NPC_ESP) do RemoveFullESP(esp) end; NPC_ESP = {}
        end
    end

    if FOVCircle then
        FOVCircle.Visible = Settings.Aim_ShowFOV and (Settings.Aim_Enabled or Settings.Aim_AutoAim)
        if FOVCircle.Visible then FOVCircle.Position = UserInputService:GetMouseLocation(); FOVCircle.Radius = Settings.Aim_FOV; FOVCircle.Color = Settings.Aim_FOVColor end
    end
-- рисуем прицел
    if DrawingAvailable and Crosshair then
        if Settings.Cross_Enabled then
            local vp = Camera.ViewportSize
            local cx, cy = vp.X / 2, vp.Y / 2
            local gap = Settings.Cross_Gap
            local len = Settings.Cross_Size
            local thick = Settings.Cross_Thickness
            local color = Settings.Cross_Color
            local doOutline = Settings.Cross_Outline
            local oThick = Settings.Cross_OutlineThickness
            local oColor = Settings.Cross_OutlineColor

            local segments = {
                { Vector2.new(cx, cy - gap), Vector2.new(cx, cy - gap - len) },
                { Vector2.new(cx, cy + gap), Vector2.new(cx, cy + gap + len) },
                { Vector2.new(cx - gap, cy), Vector2.new(cx - gap - len, cy) },
                { Vector2.new(cx + gap, cy), Vector2.new(cx + gap + len, cy) },
            }
            local show = { not Settings.Cross_HideTop, true, true, true }

            for i = 1, 4 do
                local o = Crosshair.Outline[i]
                if o then
                    if doOutline and show[i] then
                        o.From = segments[i][1]
                        o.To = segments[i][2]
                        o.Color = oColor
                        o.Thickness = thick + oThick * 2
                        o.Visible = true
                    else
                        o.Visible = false
                    end
                end
            end

            -- Основные линии
            for i = 1, 4 do
                local m = Crosshair.Main[i]
                if m then
                    if show[i] then
                        m.From = segments[i][1]
                        m.To = segments[i][2]
                        m.Color = color
                        m.Thickness = thick
                        m.Visible = true
                    else
                        m.Visible = false
                    end
                end
            end

            -- Точка в центре
            if Crosshair.DotFill and Crosshair.DotOutline then
                if Settings.Cross_Dot then
                    local dpos = Vector2.new(cx, cy)
                    if doOutline then
                        Crosshair.DotOutline.Position = dpos
                        Crosshair.DotOutline.Radius = Settings.Cross_DotSize + oThick
                        Crosshair.DotOutline.Color = oColor
                        Crosshair.DotOutline.Thickness = 1
                        Crosshair.DotOutline.Visible = true
                    else
                        Crosshair.DotOutline.Visible = false
                    end
                    Crosshair.DotFill.Position = dpos
                    Crosshair.DotFill.Radius = Settings.Cross_DotSize
                    Crosshair.DotFill.Color = color
                    Crosshair.DotFill.Visible = true
                else
                    Crosshair.DotFill.Visible = false
                    Crosshair.DotOutline.Visible = false
                end
            end
        else
            for i = 1, 4 do
                if Crosshair.Main[i] then Crosshair.Main[i].Visible = false end
                if Crosshair.Outline[i] then Crosshair.Outline[i].Visible = false end
            end
            if Crosshair.DotFill then Crosshair.DotFill.Visible = false end
            if Crosshair.DotOutline then Crosshair.DotOutline.Visible = false end
        end
    end

   local function IsAimKeyPressed()
   local key = Settings.KeyBinds.AimKeyBind or Settings.Aim_Key
        if typeof(key) == "EnumItem" then
            if key.EnumType == Enum.UserInputType then
                return UserInputService:IsMouseButtonPressed(key)
            elseif key.EnumType == Enum.KeyCode then
                return UserInputService:IsKeyDown(key)
            end
        end
        return false
    end

-- реалистичная наводка
local function UpdateRealisticAim(dt, targetPart)
    if Settings.Aim_ReactionEnabled then
        local targetChar = targetPart.Parent
        if aimRealisticState.lastTarget ~= targetChar then
            aimRealisticState.lastTarget = targetChar
            aimRealisticState.reactionTimer = tick() + Settings.Aim_ReactionDelay
        end
        if tick() < aimRealisticState.reactionTimer then
            return
        end
    end

    local stiffness = 60
    local damping = 6
    local maxAngularSpeed = 40
    local maxAngularAcceleration = 120
    local leadFactor = 0.15

    local targetPos = targetPart.Position

    local now = tick()
    if aimRealisticState.targetPrevPos and aimRealisticState.targetPrevTime then
        local dtReal = now - aimRealisticState.targetPrevTime
        if dtReal > 0.001 then
            local instantVel = (targetPos - aimRealisticState.targetPrevPos) / dtReal
            aimRealisticState.targetVelocity = aimRealisticState.targetVelocity:Lerp(instantVel, 0.2)
        end
    end
    aimRealisticState.targetPrevPos = targetPos
    aimRealisticState.targetPrevTime = now

    local predictedPos = targetPos + aimRealisticState.targetVelocity * leadFactor

    aimRealisticState.noiseSeed = aimRealisticState.noiseSeed + dt * 15
    local noiseX = math.noise(aimRealisticState.noiseSeed, 0, 0) - 0.5
    local noiseY = math.noise(0, aimRealisticState.noiseSeed, 0) - 0.5
    local noiseZ = math.noise(0, 0, aimRealisticState.noiseSeed) - 0.5
    local noiseOffset = Vector3.new(noiseX, noiseY, noiseZ) * 0.05
    predictedPos = predictedPos + noiseOffset

    local cameraPos = Camera.CFrame.Position
    local currentLook = Camera.CFrame.LookVector
    local desiredLook = (predictedPos - cameraPos).Unit
    local dot = math.clamp(currentLook:Dot(desiredLook), -1, 1)
    local angle = math.acos(dot)

    if angle < 0.005 then
        aimRealisticState.angularVelocity = Vector3.zero
        return
    end

    local axis = currentLook:Cross(desiredLook)
    if axis.Magnitude < 0.0001 then
        return
    end
    local axisUnit = axis.Unit

    local angularAcceleration = axisUnit * (stiffness * angle) - aimRealisticState.angularVelocity * damping

    local accelMag = angularAcceleration.Magnitude
    if accelMag > maxAngularAcceleration then
        angularAcceleration = angularAcceleration / accelMag * maxAngularAcceleration
    end

    aimRealisticState.angularVelocity = aimRealisticState.angularVelocity + angularAcceleration * dt

    if angle < 0.02 then
        local factor = (angle / 0.02) ^ 0.5
        aimRealisticState.angularVelocity = aimRealisticState.angularVelocity * factor
    end

    local speedMag = aimRealisticState.angularVelocity.Magnitude
    if speedMag > maxAngularSpeed then
        aimRealisticState.angularVelocity = aimRealisticState.angularVelocity / speedMag * maxAngularSpeed
    end

    local deltaAngle = aimRealisticState.angularVelocity.Magnitude * dt
    if deltaAngle > 0.0001 then
        local rotationAxis = aimRealisticState.angularVelocity.Unit
        local rotationCF = CFrame.fromAxisAngle(rotationAxis, deltaAngle)
        Camera.CFrame = CFrame.new(cameraPos, cameraPos + rotationCF * currentLook)
    end
end

-- логика аима
    local shouldAim = Settings.Aim_AutoAim or (Settings.Aim_Enabled and IsAimKeyPressed())
    if shouldAim then
        local target = GetTarget()
        if target then
            if Settings.Aim_Realistic then
                UpdateRealisticAim(dt, target)
            else
                local canAim = true
                if Settings.Aim_ReactionEnabled then
                    local targetChar = target.Parent
                    if aimRealisticState.lastTarget ~= targetChar then
                        aimRealisticState.lastTarget = targetChar
                        aimRealisticState.reactionTimer = tick() + Settings.Aim_ReactionDelay
                    end
                    canAim = tick() >= aimRealisticState.reactionTimer
                end
                if canAim then
                    local aimPos = target.Position
                    local smooth = Settings.Aim_Smoothness * 0.6
                    Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, aimPos), smooth)
                end
            end
        end
        else
    aimRealisticState.angularVelocity = Vector3.zero
    aimRealisticState.reactionTimer = 0
    aimRealisticState.lastTarget = nil
    aimRealisticState.targetPrevPos = nil
    aimRealisticState.targetPrevTime = nil
    aimRealisticState.targetVelocity = Vector3.zero
end

-- триггербот
        if Settings.Trigger_Enabled then
        if triggerDot then
            triggerDot.Position = UserInputService:GetMouseLocation()
        end

        local targetPart = GetTriggerTarget()
        if targetPart then
            if not triggerReactionStart then
                triggerReactionStart = tick()
                triggerFired = false
            end
            local elapsed = tick() - triggerReactionStart
            if elapsed >= Settings.Trigger_ReactionDelay then
                if Settings.Trigger_Mode == "Single" then
                    if not triggerFired and targetPart ~= triggerLastTarget then
                        fastClick()
                        triggerFired = true
                        triggerLastTarget = targetPart
                    end
                else
                    if Settings.Trigger_Delay <= 0 then
                        if not mouse1Held then
                            mouse1press()
                            mouse1Held = true
                        end
                    else
                        if tick() - lastShot >= Settings.Trigger_Delay then
                            fastClick()
                            lastShot = tick()
                        end
                    end
                end
            end
        else
            if mouse1Held then
                mouse1release()
                mouse1Held = false
            end
            triggerReactionStart = nil
            triggerFired = false
            triggerLastTarget = nil
        end
    else
        if triggerDot then triggerDot.Visible = false end
        if mouse1Held then
            mouse1release()
            mouse1Held = false
        end
        triggerReactionStart = nil
        triggerFired = false
        triggerLastTarget = nil
    end               

    UpdateHighlights()

-- рефреш списков tp/spec
    if currentTabIndex == 7 or currentTabIndex == 8 then
    if tick() - lastTabListRefresh >= 0.35 then
        lastTabListRefresh = tick()

        if currentTabIndex == 7 then
            tpRefreshStep = (tpRefreshStep % 4) + 1
            if tpRefreshStep == 1 then
                local p = favListFrame.CanvasPosition
                task.spawn(function()
                    pcall(RefreshFavorites)
                    pcall(function() favListFrame.CanvasPosition = p end)
                end)
            elseif tpRefreshStep == 2 then
                local p = savedListFrame.CanvasPosition
                task.spawn(function()
                    pcall(RefreshSavedLocations)
                    pcall(function() savedListFrame.CanvasPosition = p end)
                end)
            elseif tpRefreshStep == 3 then
                local p = playerListFrame.CanvasPosition
                task.spawn(function()
                    pcall(RefreshPlayerList)
                    pcall(function() playerListFrame.CanvasPosition = p end)
                end)
            elseif tpRefreshStep == 4 then
                local p = npcListFrame.CanvasPosition
                task.spawn(function()
                    pcall(refreshNpcCache)
                    pcall(RefreshNPCList)
                    pcall(function() npcListFrame.CanvasPosition = p end)
                end)
            end
        elseif currentTabIndex == 8 then
            task.spawn(function()
                pcall(RefreshSpectateIfChanged)
            end)
        end
    end
    end 
        if frameCounter % 2 == 0 then
        Trail.Update()
    end               

    end)         

    if not ___ok and ___err and not getgenv()._BC_ERR_LOG then
        getgenv()._BC_ERR_LOG = true
        warn("[bobrcheats] Ошибка в главном цикле :", ___err)
    end
end)



-- стартовая загрузка

scriptActive  = true
task.spawn(function()
    task.wait(2)
    task.wait(1)
    pcall(refreshNpcCache)
    task.wait(1)
    for _, obj in ipairs(workspace:GetDescendants()) do addItemToCache(obj) end
    if not itemDescendantAddedCon then
        itemDescendantAddedCon = workspace.DescendantAdded:Connect(function(obj)
            if scriptActive then addItemToCache(obj) end
        end)
    end
    while scriptActive do
        task.wait(5)
        if Settings.ESP_NPCs or currentTabIndex == 7 or currentTabIndex == 8 then pcall(refreshNpcCache) end
    end
end)

 -- обработка игрока
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    UpdateFlight(); UpdateSpeed()
    if Settings.Noclip_Enabled then UpdateNoclip() end
    if Settings.AntiAFK_Enabled then UpdateAntiAFK() end
    if Settings.AutoClicker_Enabled then SetAutoClickerEnabled(true) end
    if Settings.Freeze_Enabled then UpdateFreeze() end
end)

-- тп по клику
clickTPConnection  = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not Settings.ClickTP_Enabled then return end

    local key = Settings.KeyBinds.ClickTP_Key or Settings.ClickTP_Key
    if not key or typeof(key) ~= "EnumItem" then return end

    local matches = false
    if key.EnumType == Enum.KeyCode then
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key then
            matches = true
        end
    elseif key.EnumType == Enum.UserInputType then
        if input.UserInputType == key then
            matches = true
        end
    end
    if not matches then return end

    if gameProcessed then return end

    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local mousePos = UserInputService:GetMouseLocation()
    local unitRay = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local rayParams = nil
    if RaycastParamsClass then
        rayParams = RaycastParamsClass.new()
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
        rayParams.FilterDescendantsInstances = {char}
    end
    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * Settings.ClickTP_MaxDistance, rayParams)
    if result then
        root.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
    end
end)

-- бинды
function onKeyBind(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Settings.MenuKey then MainFrame.Visible = not MainFrame.Visible; return end
    local key = input.KeyCode
    for action, bindKey in pairs(Settings.KeyBinds) do
        if bindKey and key == bindKey then
            if action == "Visuals" then Settings.ESP_Enabled = not Settings.ESP_Enabled; if ToggleRefs.ESP_Enabled then ToggleRefs.ESP_Enabled.SetState(Settings.ESP_Enabled) end
            elseif action == "Speed" then Settings.Speed_Enabled = not Settings.Speed_Enabled; UpdateSpeed(); if ToggleRefs.Speed then ToggleRefs.Speed.SetState(Settings.Speed_Enabled) end
            elseif action == "Flight" then Settings.Flight_Enabled = not Settings.Flight_Enabled; UpdateFlight(); if ToggleRefs.Flight then ToggleRefs.Flight.SetState(Settings.Flight_Enabled) end
            elseif action == "Noclip" then Settings.Noclip_Enabled = not Settings.Noclip_Enabled; UpdateNoclip(); if ToggleRefs.Noclip then ToggleRefs.Noclip.SetState(Settings.Noclip_Enabled) end
            elseif action == "Aimbot" then Settings.Aim_Enabled = not Settings.Aim_Enabled; if Settings.Aim_Enabled then Settings.Aim_AutoAim = false end; if ToggleRefs.Aimbot then ToggleRefs.Aimbot.SetState(Settings.Aim_Enabled) end
            elseif action == "Trigger" then Settings.Trigger_Enabled = not Settings.Trigger_Enabled; if ToggleRefs.Trigger then ToggleRefs.Trigger.SetState(Settings.Trigger_Enabled) end
            elseif action == "AutoClicker" then
                SetAutoClickerEnabled(not Settings.AutoClicker_Enabled)
            elseif action == "ThirdPerson" then
                ToggleThirdPerson()
            elseif action == "CursorUnlock" then
                Settings.CursorUnlock_Enabled = not Settings.CursorUnlock_Enabled
                if Settings.CursorUnlock_Enabled then
                    if not savedMouseBehavior then savedMouseBehavior = UserInputService.MouseBehavior end
                    pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
                else
                    if savedMouseBehavior then pcall(function() UserInputService.MouseBehavior = savedMouseBehavior end) savedMouseBehavior = nil end
                end
                if ToggleRefs.CursorUnlock then ToggleRefs.CursorUnlock.SetState(Settings.CursorUnlock_Enabled) end
            elseif action == "BHop" then
                Settings.BHop_Enabled = not Settings.BHop_Enabled
                if ToggleRefs.BHop then ToggleRefs.BHop.SetState(Settings.BHop_Enabled) end
            elseif action == "Freeze" then
                Settings.Freeze_Enabled = not Settings.Freeze_Enabled
                UpdateFreeze()
            elseif action == "ClickTP" then
                Settings.ClickTP_Enabled = not Settings.ClickTP_Enabled
                if ToggleRefs.ClickTP then ToggleRefs.ClickTP.SetState(Settings.ClickTP_Enabled) end
            end
        end
    end
end
keyBindConnection  = UserInputService.InputBegan:Connect(onKeyBind)

-- выгрузка
FullCleanupDone = false

function FULL_UNLOAD()
    if FullCleanupDone then return end
    FullCleanupDone = true


    getgenv().BOBRCHEATS_ACTIVE = false
    scriptActive = false
    DeepCheckCancelled = true
    DeepCheckRunning = false
    DeepCheckStarting = false


    -- Визуальные настройки
    if Settings.Fullbright_Enabled then
        Settings.Fullbright_Enabled = false
        ApplyVisuals()
    end
    if Settings.PotatoGraphics_Enabled then
        Settings.PotatoGraphics_Enabled = false
        ApplyPotato()
    end
    if Settings.AtmosphereRemover_Enabled then
        DisableAtmosphereRemover()
    end

    -- Гравитация
    if Settings.Gravity_Enabled then
        Settings.Gravity_Enabled = false
        UpdateGravity()
    end

    -- Freeze
    if Settings.Freeze_Enabled then
        Settings.Freeze_Enabled = false
        UpdateFreeze()
    end

    -- Flight
    if Settings.Flight_Enabled then
        Settings.Flight_Enabled = false
        UpdateFlight()
    end

    -- Noclip
    if Settings.Noclip_Enabled then
        Settings.Noclip_Enabled = false
        UpdateNoclip()
    end

    -- GodMode
    if Settings.GodMode_Enabled then
        Settings.GodMode_Enabled = false
        UpdateGodMode()
    end

    -- AntiAFK
    if Settings.AntiAFK_Enabled then
        Settings.AntiAFK_Enabled = false
        UpdateAntiAFK()
    end

    -- AutoClicker
    if Settings.AutoClicker_Enabled then
        SetAutoClickerEnabled(false)
    end

    -- BHop
    Settings.BHop_Enabled = false

    -- FOV
    if Settings.FOV_Enabled then
        Settings.FOV_Enabled = false
        pcall(function() Camera.FieldOfView = DefaultFOV end)
    end

    -- ThirdPerson
    if Settings.ThirdPerson_Enabled then
        DisableThirdPerson()  
    end

    -- Spectator
    if Settings.Spectating then
        StopSpectate()  
    end

    -- CursorUnlock
    if Settings.CursorUnlock_Enabled then
        Settings.CursorUnlock_Enabled = false
        if savedMouseBehavior then
            pcall(function() UserInputService.MouseBehavior = savedMouseBehavior end)
            savedMouseBehavior = nil
        end
    end

    if mainRenderConnection then mainRenderConnection:Disconnect(); mainRenderConnection = nil end
    if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
    if flightConnection then flightConnection:Disconnect(); flightConnection = nil end
    if godConnection then godConnection:Disconnect(); godConnection = nil end
    if antiAfkConnection then antiAfkConnection:Disconnect(); antiAfkConnection = nil end
    if freezeConnection then freezeConnection:Disconnect(); freezeConnection = nil end
    if thirdPersonConnection then thirdPersonConnection:Disconnect(); thirdPersonConnection = nil end
    if itemDescendantAddedCon then itemDescendantAddedCon:Disconnect(); itemDescendantAddedCon = nil end
    if keyBindConnection then keyBindConnection:Disconnect(); keyBindConnection = nil end
    if spectateConnections.player then spectateConnections.player:Disconnect(); spectateConnections.player = nil end
    if spectateConnections.npc then spectateConnections.npc:Disconnect(); spectateConnections.npc = nil end
    if autoClickerConnection then autoClickerConnection:Disconnect(); autoClickerConnection = nil end
    if clickTPConnection then clickTPConnection:Disconnect(); clickTPConnection = nil end

    if flightGyro then pcall(function() flightGyro:Destroy() end); flightGyro = nil end
    if flightVel then pcall(function() flightVel:Destroy() end); flightVel = nil end

    if FOVCircle then pcall(function() FOVCircle:Remove() end); FOVCircle = nil end
    if triggerDot then pcall(function() triggerDot:Remove() end); triggerDot = nil end
    if Crosshair then
        for _, l in ipairs(Crosshair.Main or {}) do pcall(function() l:Remove() end) end
        for _, l in ipairs(Crosshair.Outline or {}) do pcall(function() l:Remove() end) end
        if Crosshair.DotFill then pcall(function() Crosshair.DotFill:Remove() end) end
        if Crosshair.DotOutline then pcall(function() Crosshair.DotOutline:Remove() end) end
        Crosshair = nil
    end
    if fpsText then pcall(function() fpsText:Remove() end); fpsText = nil end
    for _, d in pairs(highlightDrawings) do pcall(function() d:Remove() end) end
    highlightDrawings = {}

    for _, h in ipairs(chamsHighlights) do pcall(function() h:Destroy() end) end
    chamsHighlights = {}
    playerChams = {}
    for _, h in ipairs(npcChamsHighlights) do pcall(function() h:Destroy() end) end
    npcChamsHighlights = {}

    for plr, esp in pairs(ESPBoxes) do RemoveFullESP(esp) end
    ESPBoxes = {}
    for model, esp in pairs(NPC_ESP) do RemoveFullESP(esp) end
    NPC_ESP = {}

    for plr, _ in pairs(Trail.players) do Trail.ClearPlayer(plr) end
    Trail.players = {}
    for model, _ in pairs(Trail.npcs) do Trail.ClearNpc(model) end
    Trail.npcs = {}

    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            root.Anchored = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        local hum = char:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = 16
            hum.JumpPower = 50
        end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end

    mouse1Held = false
    triggerReactionStart = nil
    triggerLastTarget = nil
    triggerFired = false
    lastShot = 0
    lastBHopJump = 0
    aimVisibilityCache = {}
    visibilityCache = {}
    openPalette = nil
    openPaletteData = nil
    savedMouseBehavior = nil
    npcCacheData = {}
    itemObjects = {}
    FavoritePlayers = {}
    Settings.Spectating = false
    Settings.SpectateTarget = nil
    Settings.SpectateTargetModel = nil

    AntiCheatResult = nil
    antiCheatStatusLabel = nil
    DeepCheckRunning = false
    DeepCheckStarting = false
    DeepCheckCancelled = false

    if CustomCursor then
        CustomCursor:Destroy()
        CustomCursor = nil
    end
    if LoadingGui then
        LoadingGui:Destroy()
        LoadingGui = nil
    end
    if ScreenGui then
        ScreenGui:Destroy()
        ScreenGui = nil
    end

    pcall(function() workspace.Gravity = DefaultGravity end)
    pcall(function() Lighting.Brightness = DefaultLighting.Brightness end)
    pcall(function() Lighting.FogEnd = DefaultLighting.FogEnd end)
    pcall(function() Lighting.FogStart = DefaultLighting.FogStart end)
    pcall(function() Lighting.ClockTime = DefaultLighting.ClockTime end)
    pcall(function() Lighting.GlobalShadows = DefaultLighting.GlobalShadows end)
    pcall(function() Lighting.OutdoorAmbient = DefaultLighting.OutdoorAmbient end)
    pcall(function() Lighting.Ambient = DefaultLighting.Ambient end)
    pcall(function() Lighting.EnvironmentDiffuseScale = DefaultLighting.EnvironmentDiffuseScale end)
    pcall(function() Lighting.EnvironmentSpecularScale = DefaultLighting.EnvironmentSpecularScale end)

    getgenv().BOBRCHEATS_ACTIVE = false
    getgenv().BOBRCHEATS_UNLOAD = nil

    task.delay(0.5, function()
        local plr = game:GetService("Players").LocalPlayer
        local char = plr and plr.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        root.Anchored = false
        root.CFrame = root.CFrame + Vector3.new(0, 3, 0)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    print(Locales.t("[bobrcheats] выгрузка завершена"))
end

 -- фоновая проверка
lastBackgroundCheck  = tick() - 90

function SetAutoCheckEnabled(val)
    Settings.AutoAntiCheatCheck = val
    print(Locales.t("Фоновая проверка теперь: ") .. tostring(val))
    if ToggleRefs.AutoCheck then
        ToggleRefs.AutoCheck.SetState(val)
    end
    if val then
        lastBackgroundCheck = 0
    end
end

function LightDetectAntiCheat()
    if DeepCheckRunning or DeepCheckStarting then
        return nil
    end

local info = {Found = false, List = {}, Message = Locales.t("Сканирование...")}
    local nameKeywords = {
        "anticheat", "anti cheat", "anti-cheat", "watchdog", "sentry",
        "byfron", "hyperion", "bloxwatch", "adonis", "kohls admin",
        "hd admin", "rc7", "iac", "sentinel", "kronos", "vega",
        "criminality", "da hood anti cheat", "античит", "чит-детектор",
        "remotecheck", "clientcheck", "ban system", "anti exploit"
    }
    local codePatterns = {
        "kick player", "ban player", "kickplayer", "banplayer",
        "remotecheck", "clientcheck", "getgc", "getgenv", "hookfunction",
        "firesignal", "loadstring", "newcclosure", "getfenv", "setfenv"
    }
    local foundObjects = {}
    local foundCount = 0
    local maxObjects = 300
    local scanned = 0
    local pause = 0.01

    local containers = {
        {"ReplicatedStorage", game:GetService("ReplicatedStorage")},
        {"PlayerScripts (Local)", LocalPlayer:WaitForChild("PlayerScripts", 2)},
        {"PlayerGui (Local)", LocalPlayer:WaitForChild("PlayerGui", 2)},
        {"CoreGui", game:GetService("CoreGui")},
        {"StarterGui", game:GetService("StarterGui")},
        {"StarterPack", game:GetService("StarterPack")}
    }

    for _, cont in ipairs(containers) do
        if DeepCheckRunning or DeepCheckStarting then
            return nil
        end
        local cname, inst = cont[1], cont[2]
        if inst and scanned < maxObjects then
            local descendants = inst:GetDescendants()
            for _, obj in ipairs(descendants) do
                if DeepCheckRunning or DeepCheckStarting then
                    return nil
                end
                if scanned >= maxObjects then break end

                if obj:IsA("LocalScript") or obj:IsA("Script") or obj:IsA("ModuleScript") or obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                    if not antiCheatExclusions[obj.Name] then
                        local lowerName = obj.Name:lower()
                        local score = 0
                        for _, kw in ipairs(nameKeywords) do
                            if lowerName:find(kw, 1, true) then score = score + 2 break end
                        end
                        if obj:IsA("LocalScript") or obj:IsA("Script") or obj:IsA("ModuleScript") then
                            local src = nil
                            pcall(function() src = obj.Source end)
                            if src then
                                local ss = src:lower()
                                for _, pat in ipairs(codePatterns) do
                                    if ss:find(pat, 1, true) then score = score + 3 break end
                                end
                            end
                        end
                        if score >= 4 then
                            foundCount = foundCount + 1
                            table.insert(foundObjects, {Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName(), Container = cname})
                        end
                    end
                end
                scanned = scanned + 1
                task.wait(pause)
            end
        end
    end

        if foundCount > 0 then
        info.Found = true
        info.List = foundObjects
        info.Message = Locales.t("⚠ Подозрительные объекты: ") .. foundCount
    else
        info.Found = false
        info.Message = Locales.t("✅ Античит не обнаружен")
    end
    return info
end

task.spawn(function()
    while scriptActive do
        task.wait(1)

        if Settings.AutoAntiCheatCheck and not DeepCheckRunning and not DeepCheckStarting and (tick() - lastBackgroundCheck >= 120) then
            lastBackgroundCheck = tick()

            local res = LightDetectAntiCheat()
            if res then
                AntiCheatResult = res
UpdateAntiCheatStatus(
    Locales.t("Фон. проверка: ") .. res.Message .. " " .. Locales.t("(приблизительно)"),
    res.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100)
)
print(Locales.t("[bobrcheats] Фоновая проверка завершена: ") .. res.Message)

                if res.Found then
                    Settings.ESP_Enabled = false
                    Settings.Speed_Enabled = false
                    Settings.Flight_Enabled = false
                    Settings.Noclip_Enabled = false
                    Settings.Aim_Enabled = false
                    Settings.Aim_AutoAim = false
                    Settings.Trigger_Enabled = false
                    Settings.AutoClicker_Enabled = false
                    Settings.BHop_Enabled = false

                    if ToggleRefs.ESP_Enabled then ToggleRefs.ESP_Enabled.SetState(false) end
                    if ToggleRefs.Speed then ToggleRefs.Speed.SetState(false) end
                    if ToggleRefs.Flight then ToggleRefs.Flight.SetState(false) end
                    if ToggleRefs.Noclip then ToggleRefs.Noclip.SetState(false) end
                    if ToggleRefs.Aimbot then ToggleRefs.Aimbot.SetState(false) end
                    if ToggleRefs.AutoAim then ToggleRefs.AutoAim.SetState(false) end
                    if ToggleRefs.Trigger then ToggleRefs.Trigger.SetState(false) end
                    if ToggleRefs.AutoClicker then ToggleRefs.AutoClicker.SetState(false) end
                    if ToggleRefs.BHop then ToggleRefs.BHop.SetState(false) end

                    UpdateSpeed()
                    UpdateFlight()
                    UpdateNoclip()
                    SetAutoClickerEnabled(false)
                end
            end
        end
    end
end)


if AntiCheatResult then
    UpdateAntiCheatStatus(
        Locales.t("Статус античита: ") .. AntiCheatResult.Message .. " " .. Locales.t("(приблизительно)"),
        AntiCheatResult.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100)
    )
end

getgenv().BOBRCHEATS_UNLOAD = FULL_UNLOAD
-- запуск
task.spawn(function()
    local totalTime = 5
    local step = totalTime / 100
    for i = 0, 100 do
        LoadingBarFill.Size = UDim2.new(i/100, 0, 1, 0)
        LoadingPercent.Text = i .. "%"
        task.wait(step)
    end
    TweenService:Create(LoadingFrame, TweenInfo.new(0.5), {
        BackgroundTransparency = 1,
        Position = LoadingFrame.Position + UDim2.new(0, 0, 0, 50)
    }):Play()
    task.wait(0.5)
    LoadingGui:Destroy()
    ShowMainMenu()
    print(Locales.t("[bobrcheats v22.8] Меню загружено."))
end)

print(Locales.t("[bobrcheats v22.8] Загрузка..."))