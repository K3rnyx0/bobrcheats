-- bobrcheats v23.3 
-- Xeno Executor

-- локализация: загружаем словарь из GitHub

local CRIT_ERRORS = {}
local CRIT_READY = false

function CritError(source, reason)
    local entry = { source = tostring(source), reason = tostring(reason), time = tick() }
    warn(string.format("[bobrcheats][CRIT] %s: %s", entry.source, entry.reason))
    if CRIT_READY and Notify and NotifyList and NotifyList.Parent then
        pcall(Notify, "error", "Крит: " .. entry.source, entry.reason, 8)
        return
    end
    table.insert(CRIT_ERRORS, entry)
end

function FlushCritErrors()
    CRIT_READY = true
    if not Notify or not NotifyList or not NotifyList.Parent then return end
    for _, e in ipairs(CRIT_ERRORS) do
        pcall(Notify, "error", "Крит: " .. e.source, e.reason, 8)
    end
    CRIT_ERRORS = {}
end

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
    local translated = langDict[s]
    if not translated then
        -- Префикс-перевод для динамических строк: "Найдено: 5", "Скорость: 50"
        for key, val in pairs(langDict) do
            if key ~= s and #key > 3 and s:sub(1, #key) == key then
                translated = val .. s:sub(#key + 1)
                break
            end
        end
    end
    translated = translated or s
    if select("#", ...) > 0 then
        local ok, r = pcall(string.format, translated, ...)
        if ok then return r end
    end
    return translated
end,
        }
    else
        warn("[bobrcheats] Locales file not loaded from GitHub — using built-in RU fallback")
        CritError("Locales", "Не удалось загрузить словарь с GitHub — используется встроенный RU")
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
if not LocalPlayer then CritError("LocalPlayer", "LocalPlayer не найден — скрипт не будет работать") end
local Camera = workspace.CurrentCamera
if not Camera then CritError("Camera", "CurrentCamera не найден") end
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local CoreGui = game:GetService("CoreGui")
local DefaultFOV = Camera.FieldOfView
local RAYCAST_EXCLUDE
do
    local ok, v = pcall(function() return Enum.RaycastFilterType.Exclude end)
    RAYCAST_EXCLUDE = ok and v or Enum.RaycastFilterType.Blacklist
end

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
        task.defer(function()
            if NotifyList and NotifyList.Parent then
                Notify("success", "Античит", "Не обнаружен")
            end
        end)
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
            task.defer(function()
                if NotifyList and NotifyList.Parent then
                    Notify("error", "Античит", "Найдено: " .. foundCount, 6)
                end
            end)
       else
           info.Message = Locales.t("✅ Античит не обнаружен")
           task.defer(function()
               if NotifyList and NotifyList.Parent then
                   Notify("success", "Античит", "Не обнаружен")
               end
           end)
       end           print(Locales.t("Глубокая проверка завершена: ") .. info.Message)
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
        Notify("error", "Детектор", "Ошибка: " .. tostring(result))
        UpdateAntiCheatStatus(Locales.t("Ошибка детектора"), Color3.fromRGB(255, 100, 100))
        CritError("DetectAntiCheat", tostring(result))
        return
    end
    AntiCheatResult = result
UpdateAntiCheatStatus(Locales.t("Статус античита: ") .. result.Message .. " " .. Locales.t("(приблизительно)"), result.Found and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 200, 100))
print(Locales.t("[bobrcheats] Быстрый детектор завершён. Результат: ") .. result.Message)
end)

local RaycastParamsAvailable = pcall(function() return RaycastParams.new() end)
local RaycastParamsClass = RaycastParamsAvailable and RaycastParams or nil
if not RaycastParamsAvailable then
    CritError("RaycastParams", "Недоступен RaycastParams.new — проверки стен и видимости работать не будут")
end

local DrawingAvailable = pcall(function()
    local s = Drawing.new("Square")
    s:Remove()
    return true
end)
if not DrawingAvailable then
    CritError("Drawing", "Экзекутор не поддерживает Drawing — ESP, прицел, FOV-круг отключены")
end

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
    ESP_ViewDir = false,
    ESP_ViewDirLength = 8,
    ESP_ViewDirColor = Color3.fromRGB(255, 200, 60),
    ESP_ViewDirOnlyEnemies = true,
    ESP_ViewDirMarkLooking = true,
    ESP_ViewDirFOV = 45,
    ESP_Chams = false,
    ESP_ChamsBrightness = 100,
    ESP_TeamColors = true,

    ESP_Trails = false,
    ESP_TrailPointDist = 1,
    ESP_TrailMaxPoints = 100,
    ESP_TrailThickness = 2,
    ESP_HealthTextSize = 12,
    ESP_HealthTextColor = Color3.fromRGB(255, 100, 100),

    ESP_HeadDot = false,
    ESP_HeadDotColor = Color3.fromRGB(255, 255, 255),
    ESP_HeadDotOutline = true,
    ESP_HeadDotOutlineColor = Color3.fromRGB(0, 0, 0),
    ESP_HeadDotThickness = 1,
    ESP_HeadDotNumSides = 30,
    ESP_HeadDotFilled = false,
    ESP_HeadDotRadiusMode = "Авто",
    ESP_HeadDotFixedRadius = 5,

    ESP_Rainbow = false,
    ESP_RainbowOutline = false,
    ESP_RainbowSpeed = 1,

    ESP_TracerPosition = 1,
    ESP_HealthBarPosition = 3,
    ESP_HealthBarBlue = 0,

    ESP_OutlineMaster = true,
    ESP_BoxOutline = true,
    ESP_BoxOutlineColor = Color3.fromRGB(0, 0, 0),
    ESP_BoxOutlineThickness = 2,
    ESP_TracerOutline = false,
    ESP_TracerOutlineColor = Color3.fromRGB(0, 0, 0),
    ESP_TracerOutlineThickness = 2,
    ESP_HealthBarOutline = false,
    ESP_HealthBarOutlineColor = Color3.fromRGB(0, 0, 0),


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
    ESP_NPC_TracerPosition = 1,
    ESP_NPC_HealthBarPosition = 3,
    ESP_NPC_FrozenDetection = false,
    ESP_NPC_FrozenColor = Color3.fromRGB(120, 120, 120),
    ESP_NPC_FrozenQuickTime = 3,
    ESP_NPC_FrozenSlowTime = 30,
    ESP_NPC_FrozenMoveThreshold = 0.1,
    ESP_NPC_FrozenHideESP = false,
    ESP_NPC_Skeleton = false,
    ESP_NPC_SkeletonColor = Color3.fromRGB(255, 150, 0),
    ESP_NPC_SkeletonThickness = 1.5,

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
    Aim_MouseGain = 0.5,
    Aim_MinPixel = 2.0,
    Aim_AnchorSnapDist = 5.0,
    Aim_LockTarget = false,

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
    AutoAntiCheatCheck = false,
}
local mousemoverelFn
pcall(function() mousemoverelFn = getgenv().mousemoverel or getgenv().MouseMove end)
if not mousemoverelFn then
    CritError("MouseMove", "Функция mousemoverel отсутствует — аим и реалистичная наводка работать не будут")
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function verifyFeature(name, key, ref, check, disable)
    task.delay(0.35, function()
        if not Settings[key] then return end
        local reason = check()
        if reason then
            Notify("error", name, reason)
            Settings[key] = false
            if ref and ref.SetState then pcall(function() ref.SetState(false) end) end
            if disable then pcall(disable) end
        else
            Notify("success", name, "Включён")
        end
    end)
end

local FeatureHealth = {
    list = {},
    running = false,
    startTime = tick(),
}

function FeatureHealth.Register(key, name, check, ref, disable)
    table.insert(FeatureHealth.list, {
        key = key, name = name, check = check,
        ref = ref, disable = disable,
        fails = 0, lastWarn = 0,
    })
end

function FeatureHealth.Start()
    if FeatureHealth.running then return end
    FeatureHealth.running = true
    task.spawn(function()
        while FeatureHealth.running do
            task.wait(1.2)
            if tick() - FeatureHealth.startTime >= 2 then
                for _, item in ipairs(FeatureHealth.list) do
                    if Settings[item.key] then
                        local ok, reason = item.check()
                        if ok then
                            item.fails = 0
                        else
                            item.fails = item.fails + 1
                            if item.fails >= 2 and tick() - item.lastWarn > 8 then
                                item.lastWarn = tick()
                                item.fails = 0
                                Notify("error", item.name, reason or "Функция перестала работать")
                                Settings[item.key] = false
                                if item.ref and item.ref.SetState then
                                    pcall(function() item.ref.SetState(false) end)
                                end
                                if item.disable then pcall(item.disable) end
                            end
                        end
                    else
                        item.fails = 0
                    end
                end
            end
        end
    end)
end

local SmartAim = {
    Anchor = nil, AnchorChar = nil,
    LockedChar = nil, LockedPart = nil, LockedLost = 0,
    LastAimedPart = nil,
    CharCache = {}, VisCache = {},
    TargetPart = nil, TargetChar = nil,
}

local SA_RP, SA_FILTER
pcall(function()
    if RaycastParams and RaycastParams.new then
        SA_RP = RaycastParams
        SA_FILTER = RAYCAST_EXCLUDE
    end
end)

local function SA_Visible(part, char)
    if not Settings.Aim_VisibleCheck then return true end
    if not part or not char or not char.Parent then return false end
    if not SA_RP then return true end
    local c = SmartAim.VisCache[part]
    if c and tick() - c.t < 0.12 then return c.v end
    local origin = Camera.CFrame.Position
    local dir = part.Position - origin
    local dist = dir.Magnitude
    if dist < 0.5 then SmartAim.VisCache[part] = {v=true, t=tick()}; return true end
    local rp = SA_RP.new()
    rp.FilterType = SA_FILTER
    rp.FilterDescendantsInstances = {LocalPlayer.Character}
    rp.IgnoreWater = true
    local hit = workspace:Raycast(origin, dir.Unit * dist, rp)
    local val = (not hit) or (hit.Instance and (hit.Instance:IsDescendantOf(char) or hit.Instance == char))
    SmartAim.VisCache[part] = {v=val, t=tick()}
    return val
end

local function SA_ScorePart(part, root)
    if not part or not part:IsA("BasePart") then return nil end
    if part:IsA("Accessory") or part:IsA("Tool") then return nil end
    if (part.Transparency or 0) >= 0.99 then return nil end
    if (part.LocalTransparencyModifier or 0) >= 0.99 then return nil end
    local sz = part.Size
    local vol = sz.X * sz.Y * sz.Z
    if vol < 0.1 or vol > 3000 then return nil end
    local s = 50
    local nm = part.Name:lower()
    if nm:find("head")    then s = s + 40 end
    if nm:find("neck")    then s = s + 35 end
    if nm:find("torso")   then s = s + 30 end
    if nm:find("chest")   then s = s + 28 end
    if nm:find("hitbox")  then s = s + 60 end
    if nm:find("hurtbox") then s = s + 60 end
    if nm:find("arm")     then s = s - 10 end
    if nm:find("leg")     then s = s - 15 end
    if nm:find("hand")    then s = s - 25 end
    if nm:find("foot")    then s = s - 25 end
    if root and root.Parent then
        if (part.Position - root.Position).Magnitude < 2 then s = s + 15 end
    end
    return s
end

local function SA_ScanChar(char)
    if not char or not char.Parent then return {} end
    local c = SmartAim.CharCache[char]
    if c and tick() - c.t < 2 then
        local a = {}
        for _, p in ipairs(c.parts) do if p and p.Parent then table.insert(a, p) end end
        if #a > 0 then c.parts = a; return a end
    end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
              or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    local scored = {}
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            local s = SA_ScorePart(p, root)
            if s then table.insert(scored, {p = p, s = s}) end
        end
    end
    table.sort(scored, function(a, b) return a.s > b.s end)
    local out = {}
    for _, e in ipairs(scored) do table.insert(out, e.p) end
    SmartAim.CharCache[char] = {parts = out, t = tick()}
    return out
end

local function SA_PickPart(char, mp)
    if not char or not char.Parent then return nil end

    if Settings.Aim_Part == "Head" then
        local h = char:FindFirstChild("Head")
        if h and h:IsA("BasePart") then return h end
        return nil
    end

    if Settings.Aim_Part == "HumanoidRootPart" then
        local r = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
        if r and r:IsA("BasePart") then return r end
        return nil
    end

    local parts = SA_ScanChar(char)
    if #parts == 0 then return nil end

    if not mp then return parts[1] end

    local best, bestDist = nil, math.huge
    for _, p in ipairs(parts) do
        if p.Parent then
            local sp, on = Camera:WorldToViewportPoint(p.Position)
            if on and sp.Z > 0 then
                local d = (Vector2.new(sp.X, sp.Y) - mp).Magnitude
                if d < bestDist then
                    bestDist, best = d, p
                end
            end
        end
    end
    return best or parts[1]
end

local function SA_IsTeammate(plr)
    if not Settings.Aim_TeamCheck then return false end
    if not plr or not plr.Team or not LocalPlayer.Team then return false end
    return plr.Team == LocalPlayer.Team
end

local function SA_IsAlive(char)
    if not char or not char.Parent then return false end
    local h = char:FindFirstChildOfClass("Humanoid")
    if h then return h.Health > 0 end
    return char.PrimaryPart ~= nil
end

local function SA_GatherTargets()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and not SA_IsTeammate(p) then
            local c = p.Character
            if c and SA_IsAlive(c) then table.insert(out, c) end
        end
    end
    if Settings.Aim_TargetNPCs then
        for _, m in ipairs(workspace:GetChildren()) do
            if m:IsA("Model") and not Players:GetPlayerFromCharacter(m)
               and SA_IsAlive(m) and m:FindFirstChildOfClass("Humanoid") then
                table.insert(out, m)
            end
        end
    end
    return out
end

local function SA_GetTarget()
    local mp = UserInputService:GetMouseLocation()

    if Settings.Aim_LockTarget and SmartAim.LockedChar and SmartAim.LockedChar.Parent and SA_IsAlive(SmartAim.LockedChar) then
        local p = SmartAim.LockedPart
        if p and p.Parent then
            local sp, on = Camera:WorldToViewportPoint(p.Position)
            if on and sp.Z > 0 then
                local d = (Vector2.new(sp.X, sp.Y) - mp).Magnitude
                if d <= Settings.Aim_FOV * 1.4 then
                    SmartAim.LockedLost = 0
                    return p, SmartAim.LockedChar
                end
            end
        end
        if SmartAim.LockedLost == 0 then SmartAim.LockedLost = tick()
        elseif tick() - SmartAim.LockedLost > 0.4 then
            SmartAim.LockedChar, SmartAim.LockedPart, SmartAim.LockedLost = nil, nil, 0
        end
    else
        SmartAim.LockedChar, SmartAim.LockedPart, SmartAim.LockedLost = nil, nil, 0
    end

    local best, bestChar, bestScore = nil, nil, math.huge
    local lRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    for _, c in ipairs(SA_GatherTargets()) do
        local cRoot = c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
        local worldDist = 0
        if cRoot and lRoot then worldDist = (cRoot.Position - lRoot.Position).Magnitude end
        if worldDist <= 5000 then
        local p = SA_PickPart(c, mp)
            if p and p.Parent and SA_Visible(p, c) then
                local sp, on = Camera:WorldToViewportPoint(p.Position)
                if on and sp.Z > 0 then
                    local sd = (Vector2.new(sp.X, sp.Y) - mp).Magnitude
                    if sd <= Settings.Aim_FOV then
                        local score = sd + worldDist * 0.35
                        if score < bestScore then bestScore, best, bestChar = score, p, c end
                    end
                end
            end
        end
    end
    if best and Settings.Aim_LockTarget then
        SmartAim.LockedChar, SmartAim.LockedPart, SmartAim.LockedLost = bestChar, best, 0
    end
    return best, bestChar
end

local function SA_UpdateAnchor(part, char, dt)
    if SmartAim.AnchorChar ~= char or not SmartAim.Anchor then
        SmartAim.Anchor = part.Position
        SmartAim.AnchorChar = char
        return
    end
    local raw = part.Position
    local snap = Settings.Aim_AnchorSnapDist or 5.0
    if (raw - SmartAim.Anchor).Magnitude > snap then SmartAim.Anchor = raw; return end
    local smooth = clamp(Settings.Aim_Smoothness or 0.5, 0.01, 0.95)
    local k = 1 - math.exp(-(1 - smooth) * 20 * dt)
    SmartAim.Anchor = SmartAim.Anchor:Lerp(raw, k)
end

local function SA_MoveMouse(worldPos)
    if not mousemoverelFn then return end
    local sp, on = Camera:WorldToViewportPoint(worldPos)
    if not on or sp.Z <= 0 then return end
    local mp = UserInputService:GetMouseLocation()
    local dx = sp.X - mp.X
    local dy = sp.Y - mp.Y
    local dist = math.sqrt(dx*dx + dy*dy)
    local minPix = Settings.Aim_MinPixel or 2.0
    if dist < minPix then return end
    local g = Settings.Aim_MouseGain or 0.5
    pcall(mousemoverelFn, dx * g, dy * g)
end

local FavoritePlayers = {}
local npcCacheData = {}

function refreshNpcCache()
    local cache = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local root = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart")
                if root then
                    table.insert(cache, {Model = obj, Name = obj.Name})
                end
            end
        end
    end
    for i = #npcCacheData, 1, -1 do
        table.remove(npcCacheData, i)
    end
    for _, v in ipairs(cache) do
        table.insert(npcCacheData, v)
    end
end

function ToggleFavorite(player)
    if FavoritePlayers[player] then
        FavoritePlayers[player] = nil
        Notify("info", "Избранное", player.DisplayName .. " удалён из избранных", 2)
    else
        FavoritePlayers[player] = true
        Notify("success", "Избранное", player.DisplayName .. " добавлен в избранные", 2)
    end
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
    CritError("MouseClick", "Ни syn.cache, ни VirtualInputManager недоступны — автокликер и триггербот не кликают")
end

local function fastClick(holdTime)
    holdTime = holdTime or 0.01
    mouse1press()
    task.wait(holdTime)
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
    local guiParent = CoreGui
    pcall(function()
        if gethui then guiParent = gethui() end
    end)

    local existing = guiParent:FindFirstChild("_bobr_container")
    if existing then existing:Destroy() end

    local container = Instance.new("Folder")
    container.Name = "_bobr_container"
    container.Parent = guiParent
    SafeParent = container
end

local LOAD = {}
LOAD.Gui = Instance.new("ScreenGui")
LOAD.Gui.Name = "_load"
LOAD.Gui.ResetOnSpawn = false
LOAD.Gui.DisplayOrder = 2147483646
LOAD.Gui.IgnoreGuiInset = true
LOAD.Gui.Parent = SafeParent

LOAD.Frame = Instance.new("Frame")
LOAD.Frame.Size = UDim2.new(0, 400, 0, 240)
LOAD.Frame.Position = UDim2.new(0.5, -200, 0.5, -120)
LOAD.Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
LOAD.Frame.BackgroundTransparency = 1
LOAD.Frame.BorderSizePixel = 0
LOAD.Frame.ClipsDescendants = true
LOAD.Frame.Parent = LOAD.Gui
Instance.new("UICorner", LOAD.Frame).CornerRadius = UDim.new(0, 12)

LOAD.FrameStroke = Instance.new("UIStroke")
LOAD.FrameStroke.Color = Settings.AccentColor
LOAD.FrameStroke.Thickness = 1
LOAD.FrameStroke.Transparency = 0.6
LOAD.FrameStroke.Parent = LOAD.Frame

LOAD.Logo = Instance.new("TextLabel")
LOAD.Logo.Size = UDim2.new(1, 0, 0, 50)
LOAD.Logo.Position = UDim2.new(0, 0, 0.15, 0)
LOAD.Logo.BackgroundTransparency = 1
LOAD.Logo.Text = "BOBRCHEATS"
LOAD.Logo.TextColor3 = Settings.AccentColor
LOAD.Logo.Font = Enum.Font.GothamBold
LOAD.Logo.TextSize = 36
LOAD.Logo.Parent = LOAD.Frame

LOAD.LogoStroke = Instance.new("UIStroke")
LOAD.LogoStroke.Color = Color3.fromRGB(255, 255, 255)
LOAD.LogoStroke.Thickness = 1
LOAD.LogoStroke.Transparency = 0.5
LOAD.LogoStroke.Parent = LOAD.Logo

LOAD.BarBg = Instance.new("Frame")
LOAD.BarBg.Size = UDim2.new(0.8, 0, 0, 8)
LOAD.BarBg.Position = UDim2.new(0.1, 0, 0.55, 0)
LOAD.BarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
LOAD.BarBg.Parent = LOAD.Frame
Instance.new("UICorner", LOAD.BarBg).CornerRadius = UDim.new(1, 0)

LOAD.BarStroke = Instance.new("UIStroke")
LOAD.BarStroke.Color = Settings.AccentColor
LOAD.BarStroke.Thickness = 1
LOAD.BarStroke.Transparency = 0.8
LOAD.BarStroke.Parent = LOAD.BarBg

LOAD.BarFill = Instance.new("Frame")
LOAD.BarFill.Size = UDim2.new(0, 0, 1, 0)
LOAD.BarFill.BackgroundColor3 = Settings.AccentColor
LOAD.BarFill.Parent = LOAD.BarBg
Instance.new("UICorner", LOAD.BarFill).CornerRadius = UDim.new(1, 0)

LOAD.Percent = Instance.new("TextLabel")
LOAD.Percent.Size = UDim2.new(1, 0, 0, 30)
LOAD.Percent.Position = UDim2.new(0, 0, 0.7, 0)
LOAD.Percent.BackgroundTransparency = 1
LOAD.Percent.Text = "0%"
LOAD.Percent.TextColor3 = Color3.fromRGB(200, 200, 200)
LOAD.Percent.Font = Enum.Font.Gotham
LOAD.Percent.TextSize = 18
LOAD.Percent.Parent = LOAD.Frame

TweenService:Create(LOAD.Frame, TweenInfo.new(0.3), {BackgroundTransparency = 0.2}):Play()

-- главное окно
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "_menu"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 2147483647
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = SafeParent
ScreenGui.Enabled = false

NotifyList = Instance.new("Frame")
NotifyList.Name = "NotifyList"
NotifyList.Size = UDim2.new(0, 300, 1, -60)
NotifyList.Position = UDim2.new(1, -340, 0, 30)
NotifyList.BackgroundTransparency = 1
NotifyList.ZIndex = 500
NotifyList.Parent = ScreenGui

local notifyLayout = Instance.new("UIListLayout", NotifyList)
notifyLayout.Padding = UDim.new(0, 8)
notifyLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifyLayout.SortOrder = Enum.SortOrder.LayoutOrder

local notifyStyle = {
    info    = {color = Color3.fromRGB(90, 150, 240),  icon = "i"},
    success = {color = Color3.fromRGB(80, 210, 130),  icon = "✓"},
    warn    = {color = Color3.fromRGB(255, 180, 60),  icon = "!"},
    error   = {color = Color3.fromRGB(230, 80, 80),   icon = "X"},
}

local activeNotifs = {}

function Notify(kind, title, body, duration)
    kind = kind or "info"
    duration = duration or 4
    if type(title) == "string" then title = Locales.t(title) end
    if type(body)  == "string" then body  = Locales.t(body)  end
    local style = notifyStyle[kind] or notifyStyle.info

    for _, n in ipairs(activeNotifs) do
        if n:GetAttribute("title") == title and n:GetAttribute("body") == body then
            return
        end
    end

    task.spawn(function()
        local notif = Instance.new("Frame")
        notif.Size = UDim2.new(1, 0, 0, 0)
        notif.AutomaticSize = Enum.AutomaticSize.Y
        notif.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
        notif.BackgroundTransparency = 1
        notif.BorderSizePixel = 0
        notif.Position = UDim2.new(1, 0, 0, 0)
        notif.ZIndex = 500
        notif.ClipsDescendants = true
        notif:SetAttribute("title", title)
        notif:SetAttribute("body", body)
        notif:SetAttribute("hovered", false)
        notif.Parent = NotifyList
        Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 10)

        local scale = Instance.new("UIScale", notif)
        scale.Scale = 0.9

        local stroke = Instance.new("UIStroke", notif)
        stroke.Color = style.color
        stroke.Thickness = 1
        stroke.Transparency = 1


        local accent = Instance.new("Frame", notif)
        accent.Size = UDim2.new(0, 3, 0, 0)
        accent.Position = UDim2.new(0, 6, 0.5, 0)
        accent.AnchorPoint = Vector2.new(0, 0.5)
        accent.BackgroundColor3 = style.color
        accent.BorderSizePixel = 0
        accent.ZIndex = 501
        Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

        local iconBg = Instance.new("Frame", notif)
        iconBg.Size = UDim2.new(0, 28, 0, 28)
        iconBg.Position = UDim2.new(0, 16, 0, 12)
        iconBg.BackgroundColor3 = style.color
        iconBg.BackgroundTransparency = 0.85
        iconBg.BorderSizePixel = 0
        iconBg.ZIndex = 501
        Instance.new("UICorner", iconBg).CornerRadius = UDim.new(1, 0)

        local iconStroke = Instance.new("UIStroke", iconBg)
        iconStroke.Color = style.color
        iconStroke.Thickness = 1
        iconStroke.Transparency = 1

        local iconScale = Instance.new("UIScale", iconBg)
        iconScale.Scale = 0.4

        local icon = Instance.new("TextLabel", iconBg)
        icon.Size = UDim2.new(1, 0, 1, 0)
        icon.BackgroundTransparency = 1
        icon.Text = style.icon
        icon.TextColor3 = style.color
        icon.Font = Enum.Font.GothamBold
        icon.TextSize = 16
        icon.TextTransparency = 1
        icon.ZIndex = 502

        local titleLbl = Instance.new("TextLabel", notif)
        titleLbl.Size = UDim2.new(1, -60, 0, 18)
        titleLbl.Position = UDim2.new(0, 44, 0, 10)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = title
        titleLbl.TextColor3 = style.color
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.TextSize = 13
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.TextTransparency = 1
        titleLbl.ZIndex = 501

        local bodyLbl = Instance.new("TextLabel", notif)
        bodyLbl.Size = UDim2.new(1, -60, 0, 0)
        bodyLbl.AutomaticSize = Enum.AutomaticSize.Y
        bodyLbl.Position = UDim2.new(0, 44, 0, 30)
        bodyLbl.BackgroundTransparency = 1
        bodyLbl.Text = body
        bodyLbl.TextColor3 = Color3.fromRGB(200, 200, 205)
        bodyLbl.Font = Enum.Font.Gotham
        bodyLbl.TextSize = 12
        bodyLbl.TextWrapped = true
        bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
        bodyLbl.TextTransparency = 1
        bodyLbl.ZIndex = 501

        local pad = Instance.new("UIPadding", notif)
        pad.PaddingBottom = UDim.new(0, 14)
        pad.PaddingRight  = UDim.new(0, 14)


        local shine = Instance.new("Frame", notif)
        shine.Size = UDim2.new(0, 40, 1, 0)
        shine.Position = UDim2.new(-0.2, 0, 0, 0)
        shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        shine.BackgroundTransparency = 0.92
        shine.BorderSizePixel = 0
        shine.ZIndex = 500
        shine.Rotation = 12
        Instance.new("UICorner", shine).CornerRadius = UDim.new(1, 0)

        table.insert(activeNotifs, notif)

        TweenService:Create(notif, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 0.25
        }):Play()
        TweenService:Create(scale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Scale = 1
        }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Quart), { Transparency = 0.35 }):Play()

        task.delay(0.1, function()
            if notif.Parent then
                TweenService:Create(accent, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Size = UDim2.new(0, 3, 1, -16)
                }):Play()
            end
        end)

        task.delay(0.15, function()
            if not notif.Parent then return end
            TweenService:Create(iconScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            TweenService:Create(iconStroke, TweenInfo.new(0.4), { Transparency = 0.3 }):Play()
            TweenService:Create(icon, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
        end)

        task.delay(0.2, function()
            if not notif.Parent then return end
            TweenService:Create(titleLbl, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                TextTransparency = 0,
                Position = UDim2.new(0, 52, 0, 10)
            }):Play()
        end)

        task.delay(0.28, function()
            if not notif.Parent then return end
            TweenService:Create(bodyLbl, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                TextTransparency = 0,
                Position = UDim2.new(0, 52, 0, 30)
            }):Play()
        end)



        task.delay(0.5, function()
            if not notif.Parent then return end
            TweenService:Create(shine, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.new(1.2, 0, 0, 0)
            }):Play()
        end)

        task.delay(0.65, function()
            if not notif.Parent then return end
            TweenService:Create(iconScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
            task.delay(0.18, function()
                if not notif.Parent then return end
                TweenService:Create(iconScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Scale = 1 }):Play()
            end)
        end)

        local hovered = false
        local pausedTotal = 0
        local pauseStart = 0

        notif.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseMovement then
                hovered = true
                notif:SetAttribute("hovered", true)
                pauseStart = tick()
                TweenService:Create(notif, TweenInfo.new(0.2), {
                    BackgroundColor3 = Color3.fromRGB(24, 24, 28),
                    BackgroundTransparency = 0.1
                }):Play()
                TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0 }):Play()
            end
        end)

        notif.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseMovement and hovered then
                hovered = false
                notif:SetAttribute("hovered", false)
                pausedTotal = pausedTotal + (tick() - pauseStart)
                TweenService:Create(notif, TweenInfo.new(0.2), {
                    BackgroundColor3 = Color3.fromRGB(18, 18, 20),
                    BackgroundTransparency = 0.25
                }):Play()
                TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.35 }):Play()
            end
        end)

        local startTime = tick()
        local lastTick = startTime

        while true do
            task.wait(0.05)
            if not notif.Parent then return end
            local now = tick()
            local elapsed = now - startTime - pausedTotal
            if hovered then
                pausedTotal = pausedTotal + (now - lastTick)
            end
            lastTick = now
            local remaining = duration - elapsed
            if remaining <= 0 then break end
        end

        for i, n in ipairs(activeNotifs) do
            if n == notif then table.remove(activeNotifs, i) break end
        end

        TweenService:Create(notif, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            Position = UDim2.new(1, 20, 0, 0),
            BackgroundTransparency = 1
        }):Play()
        TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
        TweenService:Create(titleLbl, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        TweenService:Create(bodyLbl, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        TweenService:Create(icon, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()

        task.wait(0.45)
        if notif.Parent then notif:Destroy() end
    end)
end

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
TitleText.Text = "bobrcheats v23.3"
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

WARN = {}
WARN.Frame = Instance.new("Frame")
WARN.Frame.Size = UDim2.new(1, -10, 1, -90)
WARN.Frame.Position = UDim2.new(0, 5, 0, 85)
WARN.Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
WARN.Frame.BorderSizePixel = 0
WARN.Frame.Visible = false
WARN.Frame.ZIndex = 10
WARN.Frame.Parent = MainFrame
Instance.new("UICorner", WARN.Frame).CornerRadius = UDim.new(0, 8)

WARN.Title = Instance.new("TextLabel")
WARN.Title.Size = UDim2.new(1,0,0,30)
WARN.Title.Position = UDim2.new(0,0,0.25,0)
WARN.Title.BackgroundTransparency = 1
WARN.Title.Text = ""
WARN.Title.TextColor3 = Settings.AccentColor
WARN.Title.Font = Enum.Font.GothamBold
WARN.Title.TextSize = 18
WARN.Title.ZIndex = 11
WARN.Title.Parent = WARN.Frame

WARN.Msg = Instance.new("TextLabel")
WARN.Msg.Size = UDim2.new(1,-20,0,50)
WARN.Msg.Position = UDim2.new(0,10,0.4,0)
WARN.Msg.BackgroundTransparency = 1
WARN.Msg.Text = ""
WARN.Msg.TextColor3 = Color3.fromRGB(200,200,200)
WARN.Msg.Font = Enum.Font.Gotham
WARN.Msg.TextSize = 14
WARN.Msg.TextWrapped = true
WARN.Msg.ZIndex = 11
WARN.Msg.Parent = WARN.Frame

WARN.Yes = Instance.new("TextButton")
WARN.Yes.Size = UDim2.new(0,120,0,35)
WARN.Yes.Position = UDim2.new(0.5,-140,0.8,0)
WARN.Yes.BackgroundColor3 = Settings.AccentColor
WARN.Yes.Text = Locales.t("Да")
WARN.Yes.TextColor3 = Color3.fromRGB(255,255,255)
WARN.Yes.Font = Enum.Font.GothamBold
WARN.Yes.TextSize = 16
WARN.Yes.ZIndex = 11
WARN.Yes.Parent = WARN.Frame

WARN.No = Instance.new("TextButton")
WARN.No.Size = UDim2.new(0,120,0,35)
WARN.No.Position = UDim2.new(0.5,20,0.8,0)
WARN.No.BackgroundColor3 = Color3.fromRGB(60,60,60)
WARN.No.Text = Locales.t("Нет")
WARN.No.TextColor3 = Color3.fromRGB(255,255,255)
WARN.No.Font = Enum.Font.GothamBold
WARN.No.TextSize = 16
WARN.No.ZIndex = 11
WARN.No.Parent = WARN.Frame

Instance.new("UICorner", WARN.Yes).CornerRadius = UDim.new(0, 6)
Instance.new("UICorner", WARN.No).CornerRadius = UDim.new(0, 6)

WARN.Callback = nil

WARN.Yes.MouseButton1Click:Connect(function()
    WARN.Frame.Visible = false
    for i, page in ipairs(TabPages) do page.Visible = (i == currentTabIndex) end
    if WARN.Callback then WARN.Callback() end
end)
WARN.No.MouseButton1Click:Connect(function()
    WARN.Frame.Visible = false
    for i, page in ipairs(TabPages) do page.Visible = (i == currentTabIndex) end
end)

local function ShowTabWarning(title, msg, onYes)
    if Settings.DisableWarnings then
        if onYes then onYes() end
        return
    end
    WARN.Title.Text = title
    WARN.Msg.Text = msg
    WARN.Frame.Visible = true
    WARN.Callback = onYes
    for _, page in ipairs(TabPages) do page.Visible = false end
end

local function SelectTab(idx)
    currentTabIndex = idx
    WARN.Frame.Visible = false
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

SettingsPanelUI.ContentGroup = Instance.new("CanvasGroup")
SettingsPanelUI.ContentGroup.Size = UDim2.new(1, -16, 1, -42)
SettingsPanelUI.ContentGroup.Position = UDim2.new(0, 8, 0, 38)
SettingsPanelUI.ContentGroup.BackgroundTransparency = 1
SettingsPanelUI.ContentGroup.GroupTransparency = 1
SettingsPanelUI.ContentGroup.ZIndex = 21
SettingsPanelUI.ContentGroup.Parent = SettingsPanelUI.Panel

SettingsPanelUI.Content = Instance.new("ScrollingFrame")
SettingsPanelUI.Content.Size = UDim2.new(1, 0, 1, 0)
SettingsPanelUI.Content.Position = UDim2.new(0, 0, 0, 0)
SettingsPanelUI.Content.BackgroundTransparency = 1
SettingsPanelUI.Content.BorderSizePixel = 0
SettingsPanelUI.Content.ScrollBarThickness = 3
SettingsPanelUI.Content.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
SettingsPanelUI.Content.CanvasSize = UDim2.new(0, 0, 0, 0)
SettingsPanelUI.Content.ZIndex = 21
SettingsPanelUI.Content.Parent = SettingsPanelUI.ContentGroup

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

    if TabPages[currentTabIndex] then
        TabPages[currentTabIndex].Visible = true
    end

    if SettingsPanelUI.CurrentBtn then
        ResetGearAppearance(SettingsPanelUI.CurrentBtn)
        SettingsPanelUI.CurrentBtn = nil
    end

    local fi = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    local panelTween = TweenService:Create(SettingsPanelUI.Panel, fi, {BackgroundTransparency = 1})
    panelTween:Play()

    TweenService:Create(SettingsPanelUI.Stroke, fi, {Transparency = 1}):Play()
    TweenService:Create(SettingsPanelUI.Sep, fi, {BackgroundTransparency = 1}):Play()
    TweenService:Create(SettingsPanelUI.Title, fi, {TextTransparency = 1}):Play()
    TweenService:Create(SettingsPanelUI.Close, fi, {BackgroundTransparency = 1}):Play()
    TweenService:Create(SettingsPanelUI.Close, fi, {TextTransparency = 1}):Play()

    if SettingsPanelUI.ContentGroup then
        TweenService:Create(SettingsPanelUI.ContentGroup, fi, {GroupTransparency = 1}):Play()
    end

    TweenService:Create(SettingsPanelUI.Scale, fi, {Scale = 0.97}):Play()

    panelTween.Completed:Connect(function()
        if SettingsPanelUI.AnimToken ~= myToken then return end
        if SettingsPanelUI.Open then return end

        SettingsPanelUI.Panel.Visible = false
        for _, child in ipairs(SettingsPanelUI.Content:GetChildren()) do
            if not child:IsA("UIListLayout") then child:Destroy() end
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
    SettingsPanelUI.Sep.BackgroundTransparency = 1
    SettingsPanelUI.Title.TextTransparency = 1
    SettingsPanelUI.Close.BackgroundTransparency = 1
    SettingsPanelUI.Close.TextTransparency = 1
    SettingsPanelUI.Scale.Scale = 0.95
    if SettingsPanelUI.ContentGroup then
        SettingsPanelUI.ContentGroup.GroupTransparency = 1
    end

    buildFn(SettingsPanelUI.Content)

    for _, d in ipairs(SettingsPanelUI.Content:GetDescendants()) do
        if d:IsA("GuiObject") then
            d.ZIndex = (d.ZIndex or 1) + 30
        end
    end

    SettingsPanelUI.Open = true
    SettingsPanelUI.CurrentBtn = gearBtn
    SettingsPanelUI.AnimToken = SettingsPanelUI.AnimToken + 1

    local fi = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

    TweenService:Create(SettingsPanelUI.Panel, fi, {BackgroundTransparency = 0}):Play()
    TweenService:Create(SettingsPanelUI.Stroke, fi, {Transparency = 0.5}):Play()
    TweenService:Create(SettingsPanelUI.Sep, fi, {BackgroundTransparency = 0.5}):Play()
    TweenService:Create(SettingsPanelUI.Title, fi, {TextTransparency = 0}):Play()
    TweenService:Create(SettingsPanelUI.Close, fi, {BackgroundTransparency = 0}):Play()
    TweenService:Create(SettingsPanelUI.Close, fi, {TextTransparency = 0}):Play()

    if SettingsPanelUI.ContentGroup then
        TweenService:Create(SettingsPanelUI.ContentGroup, fi, {GroupTransparency = 0}):Play()
    end

    TweenService:Create(SettingsPanelUI.Scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

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

-- вкладки

local espPage = TabPages[1]
CreateSection(espPage)

ToggleRefs.ESP_Enabled = CreateFunctionRow(espPage, "ESP Вкл/Выкл", Settings.ESP_Enabled,
    function(v)
        Settings.ESP_Enabled = v
        if not v then Notify("info", "ESP", "Выключен") return end
        if not DrawingAvailable then
            Notify("error", "ESP", "Drawing недоступен")
            Settings.ESP_Enabled = false
            ToggleRefs.ESP_Enabled.SetState(false)
            return
        end
        if not Camera then
            Notify("error", "ESP", "Камера недоступна")
            Settings.ESP_Enabled = false
            ToggleRefs.ESP_Enabled.SetState(false)
            return
        end
        Notify("success", "ESP", "Включён")
    end,
    function(panel)
        -- rainbow
        CreateSection(panel)
        CreateToggle(panel, "Rainbow", function(v) Settings.ESP_Rainbow = v end, Settings.ESP_Rainbow)
        CreateSlider(panel, "Rainbow Speed (higher = slower)", 0.2, 5, Settings.ESP_RainbowSpeed, function(v) Settings.ESP_RainbowSpeed = v end, 2)

        -- skeleton
        CreateSection(panel)
        CreateToggle(panel, "Skeleton ESP", function(v) Settings.ESP_Skeleton = v end, Settings.ESP_Skeleton)
        CreateColorPicker(panel, "Цвет скелета", Settings.ESP_SkeletonColor, function(c) Settings.ESP_SkeletonColor = c end)
        CreateSlider(panel, "Толщина скелета", 0.5, 4, Settings.ESP_SkeletonThickness, function(v) Settings.ESP_SkeletonThickness = v end, 1)

        -- limit
        CreateSection(panel)
        CreateToggle(panel, "Ограничить дистанцию ESP", function(v) Settings.ESP_LimitDistance = v end, Settings.ESP_LimitDistance)
        CreateSliderInt(panel, "Макс. дистанция (m)", 100, 10000, Settings.ESP_MaxDistance, function(v) Settings.ESP_MaxDistance = v end)

        -- позиции
        CreateSection(panel)
        CreateModeSwitch(panel, "Tracer Position", {"Bottom","Center","Mouse"}, "Bottom",
            function(v)
                if v == "Bottom" then Settings.ESP_TracerPosition = 1
                elseif v == "Center" then Settings.ESP_TracerPosition = 2
                else Settings.ESP_TracerPosition = 3 end
            end)
        CreateModeSwitch(panel, "Health Bar Position", {"Top","Bottom","Left","Right"}, "Left",
            function(v)
                if v == "Top" then Settings.ESP_HealthBarPosition = 1
                elseif v == "Bottom" then Settings.ESP_HealthBarPosition = 2
                elseif v == "Left" then Settings.ESP_HealthBarPosition = 3
                else Settings.ESP_HealthBarPosition = 4 end
            end)

        -- цвета
        CreateSection(panel)
        CreateColorPicker(panel, "Цвет рамок", Settings.ESP_BoxColor, function(c) Settings.ESP_BoxColor = c end)
        CreateColorPicker(panel, "Цвет линий", Settings.ESP_TracerColor, function(c) Settings.ESP_TracerColor = c end)
        CreateColorPicker(panel, "Цвет имён", Settings.ESP_NameColor, function(c) Settings.ESP_NameColor = c end)
        CreateColorPicker(panel, "Цвет дистанции", Settings.ESP_DistanceColor, function(c) Settings.ESP_DistanceColor = c end)

        -- ползунки
        CreateSection(panel)
        CreateSliderInt(panel, "Толщина рамок", 1, 5, Settings.ESP_BoxThickness, function(v) Settings.ESP_BoxThickness = v end)
        CreateSliderInt(panel, "Толщина линий", 1, 3, Settings.ESP_TracerThickness, function(v) Settings.ESP_TracerThickness = v end)
        CreateSliderInt(panel, "Размер имён", 10, 20, Settings.ESP_NameSize, function(v) Settings.ESP_NameSize = v end)
        CreateSliderInt(panel, "Ширина HP Bar", 1, 10, Settings.ESP_HealthBarWidth, function(v) Settings.ESP_HealthBarWidth = v end)
        CreateSliderInt(panel, "Отступ HP Bar", 0, 10, Settings.ESP_HealthBarOffset, function(v) Settings.ESP_HealthBarOffset = v end)
        CreateSliderInt(panel, "Размер HP Text", 10, 20, Settings.ESP_HealthTextSize, function(v) Settings.ESP_HealthTextSize = v end)
        CreateSliderInt(panel, "Размер дистанции", 10, 20, Settings.ESP_DistanceSize, function(v) Settings.ESP_DistanceSize = v end)
    end)
CreateToggle(espPage, "Только враги", function(v) Settings.ESP_TeamCheck=v end, Settings.ESP_TeamCheck)
CreateToggle(espPage, "Рамки", function(v) Settings.ESP_Boxes=v end, Settings.ESP_Boxes)
CreateToggle(espPage, "Линии", function(v) Settings.ESP_Tracers=v end, Settings.ESP_Tracers)
CreateToggle(espPage, "Имена", function(v) Settings.ESP_Names=v end, Settings.ESP_Names)
CreateModeSwitch(espPage, "Здоровье", {"Bar","Text","Off"}, Settings.ESP_HealthMode, function(v) Settings.ESP_HealthMode=v end)
CreateToggle(espPage, "Дистанция", function(v) Settings.ESP_Distance=v end, Settings.ESP_Distance)
CreateToggle(espPage, "Проверка видимости", function(v) Settings.ESP_VisibilityCheck=v end, Settings.ESP_VisibilityCheck)
CreateFunctionRow(espPage, "Точка на голове", Settings.ESP_HeadDot,
    function(v) Settings.ESP_HeadDot = v end,
    function(panel)
        CreateSection(panel)
        CreateToggle(panel, "Обводка", function(v) Settings.ESP_HeadDotOutline = v end, Settings.ESP_HeadDotOutline)
        CreateColorPicker(panel, "Цвет", Settings.ESP_HeadDotColor, function(c) Settings.ESP_HeadDotColor = c end)
        CreateColorPicker(panel, "Цвет обводки", Settings.ESP_HeadDotOutlineColor, function(c) Settings.ESP_HeadDotOutlineColor = c end)
        CreateSection(panel)
        CreateSliderInt(panel, "Толщина", 1, 5, Settings.ESP_HeadDotThickness, function(v) Settings.ESP_HeadDotThickness = v end)
        CreateSliderInt(panel, "Стороны", 6, 60, Settings.ESP_HeadDotNumSides, function(v) Settings.ESP_HeadDotNumSides = v end)
        CreateModeSwitch(panel, "Радиус", {"Авто","Фиксированный"}, Settings.ESP_HeadDotRadiusMode, function(v) Settings.ESP_HeadDotRadiusMode = v end)
        CreateSliderInt(panel, "Фиксированный радиус", 1, 20, Settings.ESP_HeadDotFixedRadius, function(v) Settings.ESP_HeadDotFixedRadius = v end)
        CreateToggle(panel, "Заполнение", function(v) Settings.ESP_HeadDotFilled = v end, Settings.ESP_HeadDotFilled)
    end)

CreateFunctionRow(espPage, "Направление взгляда", Settings.ESP_ViewDir,
    function(v) Settings.ESP_ViewDir = v end,
    function(panel)
        CreateSection(panel)
        CreateSliderInt(panel, "Длина линии (м)", 2, 50, Settings.ESP_ViewDirLength,
            function(v) Settings.ESP_ViewDirLength = v end)
        CreateColorPicker(panel, "Цвет линии и отметки", Settings.ESP_ViewDirColor,
            function(c) Settings.ESP_ViewDirColor = c end)
        CreateSection(panel)
        CreateToggle(panel, "Только на врагов",
            function(v) Settings.ESP_ViewDirOnlyEnemies = v end, Settings.ESP_ViewDirOnlyEnemies)
        CreateSection(panel)
        CreateToggle(panel, "Отметка 👁 если видит тебя",
            function(v) Settings.ESP_ViewDirMarkLooking = v end, Settings.ESP_ViewDirMarkLooking)
        CreateSliderInt(panel, "Угол обзора (°)", 10, 90, Settings.ESP_ViewDirFOV,
            function(v) Settings.ESP_ViewDirFOV = v end)
    end)

CreateFunctionRow(espPage, "Обводка ESP", Settings.ESP_OutlineMaster,
    function(v) Settings.ESP_OutlineMaster = v end,
    function(panel)
        CreateSection(panel)
        CreateToggle(panel, "Обводка рамок", function(v) Settings.ESP_BoxOutline = v end, Settings.ESP_BoxOutline)
        CreateColorPicker(panel, "Цвет обводки рамок", Settings.ESP_BoxOutlineColor, function(c) Settings.ESP_BoxOutlineColor = c end)
        CreateSlider(panel, "Толщина обводки рамок", 0, 8, Settings.ESP_BoxOutlineThickness, function(v) Settings.ESP_BoxOutlineThickness = v end, 2)
        CreateSection(panel)
        CreateSliderInt(panel, "Синий канал HP бара", 0, 255, Settings.ESP_HealthBarBlue, function(v) Settings.ESP_HealthBarBlue = v end)
    end)
CreateToggle(espPage, "Цвета команд", function(v) Settings.ESP_TeamColors=v end, Settings.ESP_TeamColors)

CreateSection(espPage)

CreateToggle(espPage, "Chams", function(v)
    Settings.ESP_Chams = v
    UpdateChams()
    if v then
        Notify("success", "Chams", "Подсветка включена")
    else
        Notify("info", "Chams", "Выключено")
    end
end, Settings.ESP_Chams)
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

ToggleRefs.NPC_ESP_Enabled = CreateFunctionRow(npcPage, "ESP на NPC", Settings.ESP_NPCs,
    function(v)
        Settings.ESP_NPCs = v
        if v then
            Notify("success", "NPC ESP", "Включён")
        else
            Notify("info", "NPC ESP", "Выключен")
        end
    end,
    function(panel)
        -- skeleton
        CreateSection(panel)
        CreateToggle(panel, "Skeleton NPC", function(v) Settings.ESP_NPC_Skeleton = v end, Settings.ESP_NPC_Skeleton)
        CreateColorPicker(panel, "Цвет скелета NPC", Settings.ESP_NPC_SkeletonColor, function(c) Settings.ESP_NPC_SkeletonColor = c end)
        CreateSlider(panel, "Толщина скелета NPC", 0.5, 4, Settings.ESP_NPC_SkeletonThickness, function(v) Settings.ESP_NPC_SkeletonThickness = v end, 1)
        -- позиции
        CreateSection(panel)
        CreateModeSwitch(panel, "Позиция линий", {"Низ","Центр","Мышь"}, "Низ",
            function(v)
                if v == "Низ" then Settings.ESP_NPC_TracerPosition = 1
                elseif v == "Центр" then Settings.ESP_NPC_TracerPosition = 2
                else Settings.ESP_NPC_TracerPosition = 3 end
            end)
        CreateModeSwitch(panel, "Позиция HP бара", {"Сверху","Снизу","Слева","Справа"}, "Слева",
            function(v)
                if v == "Сверху" then Settings.ESP_NPC_HealthBarPosition = 1
                elseif v == "Снизу" then Settings.ESP_NPC_HealthBarPosition = 2
                elseif v == "Слева" then Settings.ESP_NPC_HealthBarPosition = 3
                else Settings.ESP_NPC_HealthBarPosition = 4 end
            end)

        -- цвета
        CreateSection(panel)
        CreateColorPicker(panel, "Цвет рамок", Settings.NPC_BoxColor, function(c) Settings.NPC_BoxColor=c end)
        CreateColorPicker(panel, "Цвет имён", Settings.NPC_NameColor, function(c) Settings.NPC_NameColor=c end)
        CreateColorPicker(panel, "Цвет линий", Settings.NPC_TracerColor, function(c) Settings.NPC_TracerColor=c end)

        -- ползунки
        CreateSection(panel)
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
CreateFunctionRow(npcPage, "Frozen Detection", Settings.ESP_NPC_FrozenDetection,
    function(v)
        Settings.ESP_NPC_FrozenDetection = v
        if not v then
            for m, _ in pairs(npcFrozenState) do npcFrozenState[m] = nil end
        end
    end,
    function(panel)
        CreateSection(panel)
        CreateColorPicker(panel, "Цвет заморозки", Settings.ESP_NPC_FrozenColor, function(c) Settings.ESP_NPC_FrozenColor = c end)
        CreateSliderInt(panel, "Быстрый порог (не двигался) сек", 1, 60, Settings.ESP_NPC_FrozenQuickTime, function(v) Settings.ESP_NPC_FrozenQuickTime = v end)
        CreateSliderInt(panel, "Медленный порог (двигался) сек", 5, 300, Settings.ESP_NPC_FrozenSlowTime, function(v) Settings.ESP_NPC_FrozenSlowTime = v end)
        CreateSection(panel)
CreateToggle(panel, "Убирать ESP у остановившихся NPC", function(v) Settings.ESP_NPC_FrozenHideESP = v end, Settings.ESP_NPC_FrozenHideESP)
    end)
CreateToggle(npcPage, "Линии к NPC", function(v) Settings.ESP_NPC_Tracers=v end, Settings.ESP_NPC_Tracers)
CreateToggle(npcPage, "Дистанция NPC", function(v) Settings.ESP_NPC_Distance=v end, Settings.ESP_NPC_Distance)
CreateSliderInt(npcPage, "Макс. дистанция", 100, 5000, Settings.ESP_NPC_MaxDistance, function(v) Settings.ESP_NPC_MaxDistance=v end)

CreateSection(npcPage)

CreateToggle(npcPage, "Chams NPC", function(v)
    Settings.ESP_NPC_Chams = v
    UpdateNpcChams()
    if v then
        Notify("success", "Chams NPC", "Включено")
    else
        Notify("info", "Chams NPC", "Выключено")
    end
end, Settings.ESP_NPC_Chams)
CreateSliderInt(npcPage, "Яркость Chams NPC", 0, 100, Settings.ESP_NPC_ChamsBrightness, function(v) Settings.ESP_NPC_ChamsBrightness=v; UpdateNpcChamsBrightness() end)

CreateSection(npcPage)

CreateFunctionRow(npcPage, "Trails (путь)", Settings.ESP_NPC_Trails,
    function(v)
        Settings.ESP_NPC_Trails = v
        if v then
            Notify("success", "NPC Trails", "Включено")
        else
            Notify("info", "NPC Trails", "Выключено")
        end
    end,
    function(panel)
        CreateSliderInt(panel, "Толщина линии", 1, 5, Settings.ESP_TrailThickness, function(v) Settings.ESP_TrailThickness=v end)
        CreateSliderInt(panel, "Макс. точек", 20, 500, Settings.ESP_NPC_TrailMaxPoints, function(v) Settings.ESP_NPC_TrailMaxPoints=v end)
    end)

local movePage = TabPages[3]
CreateSection(movePage)
ToggleRefs.Speed = CreateToggle(movePage, "Speed Hack", function(v)
    Settings.Speed_Enabled = v
    UpdateSpeed()
    if not v then Notify("info", "Speed Hack", "Выключен") return end
    verifyFeature("Speed Hack", "Speed_Enabled", ToggleRefs.Speed, function()
        local c = LocalPlayer.Character
        if not c then return "Персонажа нет" end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not c:FindFirstChild("HumanoidRootPart") then return "Персонаж ещё не прогрузился" end
        if h.Health <= 0 then return "Персонаж мёртв" end
        local target = math.min(Settings.Speed_Value, MAX_SAFE_SPEED)
        if math.abs(h.WalkSpeed - target) > 1 then
            return Settings.Speed_Value > MAX_SAFE_SPEED and "Скорость выше лимита" or "Сервер блокирует WalkSpeed"
        end
    end, function() UpdateSpeed() end)
end, Settings.Speed_Enabled, "Speed Hack может вызвать кик или бан. Включить?")
CreateSliderInt(movePage, "Скорость бега", 16, 1000, Settings.Speed_Value, function(v) Settings.Speed_Value=v; if Settings.Speed_Enabled then UpdateSpeed() end end)
ToggleRefs.Flight = CreateToggle(movePage, "Flight", function(v)
    Settings.Flight_Enabled = v
    UpdateFlight()
    if not v then Notify("info", "Flight", "Выключен") return end
    verifyFeature("Flight", "Flight_Enabled", ToggleRefs.Flight, function()
        local c = LocalPlayer.Character
        if not c then return "Персонажа нет" end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then return "Тело персонажа не загрузилось" end
        if h.Health <= 0 then return "Персонаж мёртв" end
        if not c:FindFirstChild("HumanoidRootPart") then return "Персонаж ещё не прогрузился" end
    end, function() UpdateFlight() end)
end, Settings.Flight_Enabled, "Полёт может быть обнаружен античитом. Включить?")
CreateSliderInt(movePage, "Скорость полёта", 10, 1000, Settings.Flight_Speed, function(v) Settings.Flight_Speed=v end)
ToggleRefs.Noclip = CreateToggle(movePage, "Noclip", function(v)
    Settings.Noclip_Enabled = v
    UpdateNoclip()
    if not v then Notify("info", "Noclip", "Выключен") return end
    verifyFeature("Noclip", "Noclip_Enabled", ToggleRefs.Noclip, function()
        local c = LocalPlayer.Character
        if not c then return "Персонажа нет" end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                return "Сервер возвращает CanCollide"
            end
        end
    end, function() UpdateNoclip() end)
end, Settings.Noclip_Enabled, "Noclip может вызвать кик или бан. Включить?")
CreateToggle(movePage, "God Mode", function(v)
    Settings.GodMode_Enabled = v
    UpdateGodMode()
    if not v then Notify("info", "God Mode", "Выключен") return end
    task.delay(0.6, function()
        if not Settings.GodMode_Enabled then return end
        local c = LocalPlayer.Character
        if not c then Notify("error", "God Mode", "Персонажа нет") Settings.GodMode_Enabled = false return end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then Notify("error", "God Mode", "Тело персонажа не загрузилось") Settings.GodMode_Enabled = false return end
        if h.Health <= 0 then Notify("error", "God Mode", "Персонаж мёртв") Settings.GodMode_Enabled = false return end
        if h.Health >= h.MaxHealth then
            Notify("success", "God Mode", "Включён")
        else
            Notify("warn", "God Mode", "Сервер блокирует лечение")
        end
    end)
end, Settings.GodMode_Enabled, "God Mode может вызвать кик. Включить?")
CreateSection(movePage)
CreateFunctionRow(movePage, "Anti-AFK", Settings.AntiAFK_Enabled,
    function(v)
        Settings.AntiAFK_Enabled = v
        UpdateAntiAFK()
        if v then
            Notify("success", "Anti-AFK", "Активен")
        else
            Notify("info", "Anti-AFK", "Выключен")
        end
    end,
    function(panel)
        CreateSliderInt(panel, "Интервал (сек)", 5, 120, Settings.AntiAFK_Interval, function(v) Settings.AntiAFK_Interval = v end)
        CreateSlider(panel, "Длит. шага (сек)", 0.1, 1.0, Settings.AntiAFK_StepDuration, function(v) Settings.AntiAFK_StepDuration = v end, 3)
    end)

ToggleRefs.SmartAntiAFK = CreateFunctionRow(movePage, "Smart Anti-AFK", Settings.SmartAntiAFK_Enabled,
    function(v)
        Settings.SmartAntiAFK_Enabled = v
        UpdateSmartAntiAFK()
        if v then
            Notify("success", "Smart Anti-AFK", "Активен")
        else
            Notify("info", "Smart Anti-AFK", "Выключен")
        end
    end,
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
    if v then
        Notify("warn", "BHop", "Активен")
    else
        Notify("info", "BHop", "Выключен")
    end
end, Settings.BHop_Enabled, "BHop может быть обнаружен античитом. Включить?")
CreateSlider(movePage, "Задержка прыжка", 0.0, 0.5, Settings.BHop_Delay, function(v) Settings.BHop_Delay = v end, 3)

CreateSection(movePage)
ToggleRefs.AutoClicker = CreateFunctionRow(movePage, "Auto Clicker", Settings.AutoClicker_Enabled,
    function(v)
        SetAutoClickerEnabled(v)
    end,
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

function SetCursorUnlocked(state)
    state = state and true or false
    Settings.CursorUnlock_Enabled = state
    if state then
        if not savedMouseBehavior then
            savedMouseBehavior = UserInputService.MouseBehavior
        end
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        if CustomCursor then CustomCursor.Visible = true end
    else
        if savedMouseBehavior then
            pcall(function() UserInputService.MouseBehavior = savedMouseBehavior end)
        else
            pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end)
        end
        savedMouseBehavior = nil
        if CustomCursor then CustomCursor.Visible = false end
    end
    if ToggleRefs and ToggleRefs.CursorUnlock then
        pcall(function() ToggleRefs.CursorUnlock.SetState(state) end)
    end
end

CreateSection(movePage)
ToggleRefs.CursorUnlock = CreateToggle(movePage, "Разблокировать курсор", function(v)
    SetCursorUnlocked(v)
    if v then
        Notify("success", "Курсор", "Разблокирован")
    else
        Notify("info", "Курсор", "Заблокирован")
    end
end, Settings.CursorUnlock_Enabled)

CreateSection(movePage)
CreateToggle(movePage, "Freeze Character", function(v)
    Settings.Freeze_Enabled = v
    UpdateFreeze()
    if not v then Notify("info", "Freeze", "Выключен") return end
    task.delay(0.2, function()
        if not Settings.Freeze_Enabled then return end
        local c = LocalPlayer.Character
        if not c then Notify("error", "Freeze", "Персонажа нет") Settings.Freeze_Enabled = false return end
        local r = c:FindFirstChild("HumanoidRootPart")
        if not r then Notify("error", "Freeze", "Персонаж ещё не прогрузился") Settings.Freeze_Enabled = false return end
        if not r.Anchored then
            Notify("error", "Freeze", "Сервер снимает Anchored")
        else
            Notify("success", "Freeze", "Включён")
        end
    end)
end, Settings.Freeze_Enabled)
CreateSection(movePage)
CreateToggle(movePage, "Изменить гравитацию", function(v)
    Settings.Gravity_Enabled = v
    UpdateGravity()
    if v then
        Notify("warn", "Гравитация", "Изменена на " .. Settings.Gravity_Value)
    else
        Notify("info", "Гравитация", "Восстановлена")
    end
end, Settings.Gravity_Enabled)
CreateSlider(movePage, "Значение", 0, 500, Settings.Gravity_Value, function(v) Settings.Gravity_Value=v UpdateGravity() end, 1)
CreateSection(movePage)
ToggleRefs.ClickTP = CreateToggle(movePage, "Click TP (телепорт в точку клика)", function(v)
    Settings.ClickTP_Enabled = v
    if v then
        Notify("warn", "Click TP", "Включён")
    else
        Notify("info", "Click TP", "Выключен")
    end
end, Settings.ClickTP_Enabled)
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
            Notify("warn", "Suicide", "Персонаж убит")
        end
    end)
end)

local aimPage = TabPages[4]
CreateSection(aimPage)

ToggleRefs.Aimbot = CreateFunctionRow(aimPage, "Aimbot", Settings.Aim_Enabled,
    function(v)
        Settings.Aim_Enabled = v
        if not v then Notify("info", "Aimbot", "Выключен") return end
        Settings.Aim_AutoAim = false
        if ToggleRefs.AutoAim then ToggleRefs.AutoAim.SetState(false) end
        if not mousemoverelFn then
            Notify("error", "Aimbot", "mousemoverel недоступен")
            Settings.Aim_Enabled = false
            ToggleRefs.Aimbot.SetState(false)
            return
        end
        if not LocalPlayer.Character then
            Notify("error", "Aimbot", "Персонажа нет")
            Settings.Aim_Enabled = false
            ToggleRefs.Aimbot.SetState(false)
            return
        end
        task.delay(0.5, function()
            if not Settings.Aim_Enabled then return end
            local n = 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local c = p.Character
                    local h = c and c:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then n = n + 1 end
                end
            end
            if n == 0 then
                Notify("warn", "Aimbot", "Включён, но целей нет")
            else
                Notify("success", "Aimbot", "Включён")
            end
        end)
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
        CreateSection(panel)
        CreateSlider(panel, "Сила мыши", 0.1, 1.0, Settings.Aim_MouseGain, function(v) Settings.Aim_MouseGain = v end, 2)
        CreateSlider(panel, "Мёртвая зона (px)", 0.5, 6, Settings.Aim_MinPixel, function(v) Settings.Aim_MinPixel = v end, 1)
        CreateSlider(panel, "Порог якоря (snap)", 1, 20, Settings.Aim_AnchorSnapDist, function(v) Settings.Aim_AnchorSnapDist = v end, 1)
        CreateToggle(panel, "Удерживать цель", function(v) Settings.Aim_LockTarget = v end, Settings.Aim_LockTarget)
    end)


ToggleRefs.AutoAim = CreateToggle(aimPage, "Auto Aim", function(v) 
    Settings.Aim_AutoAim = v
    if not v then Notify("info", "Auto Aim", "Выключен") return end
    Settings.Aim_Enabled = false
    if ToggleRefs.Aimbot then ToggleRefs.Aimbot.SetState(false) end
    if not mousemoverelFn then
        Notify("error", "Auto Aim", "mousemoverel недоступен")
        Settings.Aim_AutoAim = false
        ToggleRefs.AutoAim.SetState(false)
        return
    end
    if not LocalPlayer.Character then
        Notify("error", "Auto Aim", "Персонажа нет")
        Settings.Aim_AutoAim = false
        ToggleRefs.AutoAim.SetState(false)
        return
    end
    Notify("warn", "Auto Aim", "Включён")
end, Settings.Aim_AutoAim, "Auto Aim делает аим заметным. Включить?")

CreateSlider(aimPage, "Плавность", 0.1, 1.0, Settings.Aim_Smoothness, function(v) Settings.Aim_Smoothness=v end, 3)
CreateSliderInt(aimPage, "FOV", 10, 500, Settings.Aim_FOV, function(v) Settings.Aim_FOV=v end)
CreateToggle(aimPage, "Team Check", function(v) Settings.Aim_TeamCheck=v end, Settings.Aim_TeamCheck)
CreateToggle(aimPage, "Проверка стен", function(v) Settings.Aim_VisibleCheck=v end, Settings.Aim_VisibleCheck)
CreateToggle(aimPage, "Реалистичная наводка", function(v) Settings.Aim_Realistic=v end, Settings.Aim_Realistic)

CreateSection(aimPage)

ToggleRefs.Trigger = CreateFunctionRow(aimPage, "Triggerbot", Settings.Trigger_Enabled,
    function(v)
        Settings.Trigger_Enabled = v
        if not v then Notify("info", "Triggerbot", "Выключен") return end
        if not mouse1press then
            Notify("error", "Triggerbot", "Эмуляция кликов недоступна")
            Settings.Trigger_Enabled = false
            ToggleRefs.Trigger.SetState(false)
            return
        end
        if not LocalPlayer.Character then
            Notify("error", "Triggerbot", "Персонажа нет")
            Settings.Trigger_Enabled = false
            ToggleRefs.Trigger.SetState(false)
            return
        end
        Notify("warn", "Triggerbot", "Включён")
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
CreateToggle(visPage, "Fullbright", function(v)
    Settings.Fullbright_Enabled = v
    ApplyVisuals()
    if v then
        Notify("success", "Fullbright", "Включён")
    else
        Notify("info", "Fullbright", "Выключен")
    end
end, Settings.Fullbright_Enabled)
CreateSliderInt(visPage, "Яркость", 1, 100, Settings.Fullbright_Brightness, function(v) Settings.Fullbright_Brightness=v; ApplyVisuals() end)
CreateToggle(visPage, "FOV Changer", function(v)
    Settings.FOV_Enabled = v
    if not v then
        pcall(function() Camera.FieldOfView = DefaultFOV end)
        Notify("info", "FOV", "Восстановлен")
    else
        Notify("success", "FOV", "Установлен: " .. Settings.FOV_Value)
    end
end, Settings.FOV_Enabled)
CreateSliderInt(visPage, "FOV", 30, 120, Settings.FOV_Value, function(v) Settings.FOV_Value=v end)

CreateToggle(visPage, "Картофель", function(v)
    Settings.PotatoGraphics_Enabled = v
    ApplyPotato()
    if v then
        Notify("success", "Картофель", "Графика упрощена")
    else
        Notify("info", "Картофель", "Графика восстановлена")
    end
end, Settings.PotatoGraphics_Enabled)
CreateToggle(visPage, "Atmosphere Remover", function(v)
    Settings.AtmosphereRemover_Enabled = v
    if v then
        EnableAtmosphereRemover()
        Notify("success", "Атмосфера", "Убрана")
    else
        DisableAtmosphereRemover()
        Notify("info", "Атмосфера", "Восстановлена")
    end
end, Settings.AtmosphereRemover_Enabled)
CreateSection(visPage)
ToggleRefs.ThirdPerson = CreateToggle(visPage, "Третье лицо", function(v)
    if v then
        EnableThirdPerson()
        Notify("warn", "Третье лицо", "Включено")
    else
        DisableThirdPerson()
        Notify("info", "Третье лицо", "Выключено")
    end
end, Settings.ThirdPerson_Enabled)
CreateSection(visPage)
CreateFunctionRow(visPage, "Кастомный прицел", Settings.Cross_Enabled,
    function(v)
        Settings.Cross_Enabled = v
        if v then
            Notify("success", "Прицел", "Включён")
        else
            Notify("info", "Прицел", "Выключен")
        end
    end,
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
CreateToggle(hlPage, "Подсветка предметов", function(v)
    Settings.Highlight_Objects = v
    if v then
        Notify("success", "Items", "Подсветка включена")
    else
        Notify("info", "Items", "Выключена")
    end
end, Settings.Highlight_Objects)
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
    if not player or not player.Parent then
        Notify("error", "Spectate", "Игрок недоступен", 2)
        return
    end
    local targetChar = player.Character
    if not targetChar or not targetChar:FindFirstChild("Humanoid") then
        Notify("error", "Spectate", "Цель недоступна (нет персонажа)", 2)
        return
    end
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
    spectateConnections.player = nil
    UpdateSpectateHighlight()
    Notify("success", "Spectate", "Слежка: " .. player.DisplayName, 2)
end

function StartSpectateNPC(model)
    if Settings.Spectating then StopSpectate() end
    if not model or not model.Parent then
        Notify("error", "Spectate", "NPC недоступен", 2)
        return
    end
    local hum = model:FindFirstChild("Humanoid")
    if not hum then
        Notify("error", "Spectate", "У NPC нет Humanoid", 2)
        return
    end
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
    spectateConnections.npc = nil
    UpdateSpectateHighlight()
    Notify("success", "Spectate", "Слежка за NPC: " .. model.Name, 2)
end

function StopSpectate(silent)
    if not Settings.Spectating then return end
    local _wasNpc = Settings.SpectateIsNPC
    local _target = Settings.SpectateTarget
    local _model = Settings.SpectateTargetModel
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
    if not silent then
        if _wasNpc and _model then
            Notify("info", "Spectate", "Слежка за NPC прекращена", 2)
        elseif _target then
            Notify("info", "Spectate", "Слежка прекращена", 2)
        end
    end
end

-- вкладка spectate
SPEC = {}
do
    SPEC.Page = TabPages[8]
    SPEC.TopFrame = Instance.new("Frame")
    SPEC.TopFrame.Size = UDim2.new(1, 0, 0, 60)
    SPEC.TopFrame.BackgroundTransparency = 1
    SPEC.TopFrame.ZIndex = 100
    SPEC.TopFrame.Parent = SPEC.Page

    SPEC.StopBtn = Instance.new("TextButton")
    SPEC.StopBtn.Size = UDim2.new(1, -10, 0, 25)
    SPEC.StopBtn.Position = UDim2.new(0, 5, 0, 0)
    SPEC.StopBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    SPEC.StopBtn.Text = Locales.t("⛔ Остановить")
    SPEC.StopBtn.TextColor3 = Color3.fromRGB(255,255,255)
    SPEC.StopBtn.Font = Enum.Font.GothamBold
    SPEC.StopBtn.TextSize = 13
    SPEC.StopBtn.ZIndex = 101
    SPEC.StopBtn.Active = true
    SPEC.StopBtn.Parent = SPEC.TopFrame
    Instance.new("UICorner", SPEC.StopBtn).CornerRadius = UDim.new(0, 4)

    SPEC.TpBtn = Instance.new("TextButton")
    SPEC.TpBtn.Size = UDim2.new(1, -10, 0, 25)
    SPEC.TpBtn.Position = UDim2.new(0, 5, 0, 32)
    SPEC.TpBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
    SPEC.TpBtn.Text = Locales.t("ТП к цели")
    SPEC.TpBtn.TextColor3 = Color3.fromRGB(255,255,255)
    SPEC.TpBtn.Font = Enum.Font.GothamBold
    SPEC.TpBtn.TextSize = 13
    SPEC.TpBtn.ZIndex = 101
    SPEC.TpBtn.Active = true
    SPEC.TpBtn.Parent = SPEC.TopFrame
    Instance.new("UICorner", SPEC.TpBtn).CornerRadius = UDim.new(0, 4)

    SPEC.StopBtn.MouseButton1Click:Connect(StopSpectate)

    SPEC.TpBtn.MouseButton1Click:Connect(function()
        if not Settings.Spectating then
            Notify("error", "Spectate", "Вы не в режиме слежки", 2)
            return
        end
        local myChar = LocalPlayer.Character
        if not myChar then
            Notify("error", "Spectate", "Персонаж не найден", 2)
            return
        end
        local myRoot = myChar:FindFirstChild("HumanoidRootPart")
        if not myRoot then
            Notify("error", "Spectate", "HumanoidRootPart не найден", 2)
            return
        end
        local wasAnchored = myRoot.Anchored
        myRoot.Anchored = false
        local oldPos = myRoot.Position
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
            task.wait(0.1)
            local moved = (myRoot.Position - oldPos).Magnitude
            StopSpectate(true)
            if moved < 1 then
                Notify("error", "Spectate", "Перемещение заблокировано (карта/античит)")
            else
                Notify("success", "Spectate", "Перемещён к цели")
            end
        else
            myRoot.Anchored = wasAnchored
            Notify("error", "Spectate", "Не удалось переместиться к цели")
        end
    end)

    SPEC.FavFrame = Instance.new("ScrollingFrame")
    SPEC.FavFrame.Size = UDim2.new(1,0,0,120)
    SPEC.FavFrame.BackgroundTransparency = 1
    SPEC.FavFrame.BorderSizePixel = 0
    SPEC.FavFrame.ScrollBarThickness = 3
    SPEC.FavFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    SPEC.FavFrame.CanvasSize = UDim2.new(0,0,0,0)
    SPEC.FavFrame.Parent = SPEC.Page

    SPEC.FavLayout = Instance.new("UIListLayout")
    SPEC.FavLayout.Padding = UDim.new(0,4)
    SPEC.FavLayout.Parent = SPEC.FavFrame
    SPEC.FavLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SPEC.FavFrame.CanvasSize = UDim2.new(0,0,0, SPEC.FavLayout.AbsoluteContentSize.Y + 10)
    end)

    SPEC.ListFrame = Instance.new("ScrollingFrame")
    SPEC.ListFrame.Size = UDim2.new(1,0,0,200)
    SPEC.ListFrame.BackgroundTransparency = 1
    SPEC.ListFrame.BorderSizePixel = 0
    SPEC.ListFrame.ScrollBarThickness = 3
    SPEC.ListFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    SPEC.ListFrame.CanvasSize = UDim2.new(0,0,0,0)
    SPEC.ListFrame.ZIndex = 1
    SPEC.ListFrame.Parent = SPEC.Page

    SPEC.ListLayout = Instance.new("UIListLayout")
    SPEC.ListLayout.Padding = UDim.new(0,4)
    SPEC.ListLayout.Parent = SPEC.ListFrame
    SPEC.ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SPEC.ListFrame.CanvasSize = UDim2.new(0,0,0, SPEC.ListLayout.AbsoluteContentSize.Y + 10)
    end)

    SPEC.NpcFrame = Instance.new("ScrollingFrame")
    SPEC.NpcFrame.Size = UDim2.new(1,0,0,150)
    SPEC.NpcFrame.BackgroundTransparency = 1
    SPEC.NpcFrame.BorderSizePixel = 0
    SPEC.NpcFrame.ScrollBarThickness = 3
    SPEC.NpcFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    SPEC.NpcFrame.CanvasSize = UDim2.new(0,0,0,0)
    SPEC.NpcFrame.ZIndex = 1
    SPEC.NpcFrame.Parent = SPEC.Page

    SPEC.NpcLayout = Instance.new("UIListLayout")
    SPEC.NpcLayout.Padding = UDim.new(0,4)
    SPEC.NpcLayout.Parent = SPEC.NpcFrame
    SPEC.NpcLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SPEC.NpcFrame.CanvasSize = UDim2.new(0,0,0, SPEC.NpcLayout.AbsoluteContentSize.Y + 10)
    end)

    SPEC.Buttons = {}
    SPEC.NpcButtons = {}
end

function RefreshSpectateFavOnly()
    for _, child in ipairs(SPEC.FavFrame:GetChildren()) do
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
        frame.Parent = SPEC.FavFrame
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
    for _, child in ipairs(SPEC.ListFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    SPEC.Buttons = {}
    local sorted = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(sorted, p) end
    end
    table.sort(sorted, function(a, b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(sorted) do
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 30)
        frame.BackgroundTransparency = 1
        frame.Parent = SPEC.ListFrame
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
        SPEC.Buttons[player] = btn
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
    for _, child in ipairs(SPEC.NpcFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    SPEC.NpcButtons = {}
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
            btn.Parent = SPEC.NpcFrame
            SPEC.NpcButtons[model] = btn
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

function UpdateSpectateHighlight()
    for player, btn in pairs(SPEC.Buttons) do
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
    for model, btn in pairs(SPEC.NpcButtons) do
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
        local p = SPEC.FavFrame.CanvasPosition
        pcall(RefreshSpectateFavOnly)
        pcall(function() SPEC.FavFrame.CanvasPosition = p end)
    end
    if plrChanged then
        local p = SPEC.ListFrame.CanvasPosition
        pcall(RefreshSpectatePlayersOnly)
        pcall(function() SPEC.ListFrame.CanvasPosition = p end)
        if Settings.Spectating then pcall(UpdateSpectateHighlight) end
    end
    if npcChanged then
        local p = SPEC.NpcFrame.CanvasPosition
        pcall(refreshNpcCache)
        pcall(RefreshSpectateNpcOnly)
        pcall(function() SPEC.NpcFrame.CanvasPosition = p end)
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
TP = {}
do
    TP.Page = TabPages[7]

    TP.FavListFrame = Instance.new("ScrollingFrame")
    TP.FavListFrame.Size = UDim2.new(1,0,0,100)
    TP.FavListFrame.BackgroundTransparency = 1
    TP.FavListFrame.BorderSizePixel = 0
    TP.FavListFrame.ScrollBarThickness = 3
    TP.FavListFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    TP.FavListFrame.CanvasSize = UDim2.new(0,0,0,0)
    TP.FavListFrame.Parent = TP.Page

    TP.FavLayout = Instance.new("UIListLayout")
    TP.FavLayout.Padding = UDim.new(0,4)
    TP.FavLayout.Parent = TP.FavListFrame
    TP.FavLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        TP.FavListFrame.CanvasSize = UDim2.new(0,0,0, TP.FavLayout.AbsoluteContentSize.Y + 10)
    end)

    TP.ActionsFrame = Instance.new("Frame")
    TP.ActionsFrame.Size = UDim2.new(1,0,0,70)
    TP.ActionsFrame.BackgroundTransparency = 1
    TP.ActionsFrame.Parent = TP.Page

    TP.SaveLocBtn = Instance.new("TextButton")
    TP.SaveLocBtn.Size = UDim2.new(1,-10,0,22)
    TP.SaveLocBtn.Position = UDim2.new(0,5,0,0)
    TP.SaveLocBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
    TP.SaveLocBtn.Text = Locales.t("Сохранить позицию")
    TP.SaveLocBtn.TextColor3 = Color3.fromRGB(255,255,255)
    TP.SaveLocBtn.Font = Enum.Font.GothamBold
    TP.SaveLocBtn.TextSize = 11
    TP.SaveLocBtn.Parent = TP.ActionsFrame

    TP.TpLastBtn = Instance.new("TextButton")
    TP.TpLastBtn.Size = UDim2.new(1,-10,0,22)
    TP.TpLastBtn.Position = UDim2.new(0,5,0,28)
    TP.TpLastBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
    TP.TpLastBtn.Text = Locales.t("ТП к последней сохр.")
    TP.TpLastBtn.TextColor3 = Color3.fromRGB(255,255,255)
    TP.TpLastBtn.Font = Enum.Font.GothamBold
    TP.TpLastBtn.TextSize = 11
    TP.TpLastBtn.Parent = TP.ActionsFrame

    TP.SpawnBtn = Instance.new("TextButton")
    TP.SpawnBtn.Size = UDim2.new(1,-10,0,22)
    TP.SpawnBtn.Position = UDim2.new(0,5,0,56)
    TP.SpawnBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
    TP.SpawnBtn.Text = Locales.t("ТП на спавн")
    TP.SpawnBtn.TextColor3 = Color3.fromRGB(255,255,255)
    TP.SpawnBtn.Font = Enum.Font.GothamBold
    TP.SpawnBtn.TextSize = 11
    TP.SpawnBtn.Parent = TP.ActionsFrame

    TP.PlayerListFrame = Instance.new("ScrollingFrame")
    TP.PlayerListFrame.Size = UDim2.new(1,0,0,200)
    TP.PlayerListFrame.BackgroundTransparency = 1
    TP.PlayerListFrame.BorderSizePixel = 0
    TP.PlayerListFrame.ScrollBarThickness = 3
    TP.PlayerListFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    TP.PlayerListFrame.CanvasSize = UDim2.new(0,0,0,0)
    TP.PlayerListFrame.Parent = TP.Page

    TP.TpLayout = Instance.new("UIListLayout")
    TP.TpLayout.Padding = UDim.new(0,4)
    TP.TpLayout.Parent = TP.PlayerListFrame
    TP.TpLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        TP.PlayerListFrame.CanvasSize = UDim2.new(0,0,0, TP.TpLayout.AbsoluteContentSize.Y + 10)
    end)

    TP.NpcListFrame = Instance.new("ScrollingFrame")
    TP.NpcListFrame.Size = UDim2.new(1,0,0,150)
    TP.NpcListFrame.BackgroundTransparency = 1
    TP.NpcListFrame.BorderSizePixel = 0
    TP.NpcListFrame.ScrollBarThickness = 3
    TP.NpcListFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    TP.NpcListFrame.CanvasSize = UDim2.new(0,0,0,0)
    TP.NpcListFrame.Parent = TP.Page

    TP.NpcLayout = Instance.new("UIListLayout")
    TP.NpcLayout.Padding = UDim.new(0,4)
    TP.NpcLayout.Parent = TP.NpcListFrame
    TP.NpcLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        TP.NpcListFrame.CanvasSize = UDim2.new(0,0,0, TP.NpcLayout.AbsoluteContentSize.Y + 10)
    end)

    TP.SavedFrame = Instance.new("Frame")
    TP.SavedFrame.Size = UDim2.new(1,0,0,150)
    TP.SavedFrame.BackgroundTransparency = 1
    TP.SavedFrame.Parent = TP.Page

    TP.ClearSavedBtn = Instance.new("TextButton")
    TP.ClearSavedBtn.Size = UDim2.new(1,-10,0,22)
    TP.ClearSavedBtn.Position = UDim2.new(0,5,0,0)
    TP.ClearSavedBtn.BackgroundColor3 = Color3.fromRGB(200,40,40)
    TP.ClearSavedBtn.Text = Locales.t("Очистить все сохр.")
    TP.ClearSavedBtn.TextColor3 = Color3.fromRGB(255,255,255)
    TP.ClearSavedBtn.Font = Enum.Font.GothamBold
    TP.ClearSavedBtn.TextSize = 11
    TP.ClearSavedBtn.Parent = TP.SavedFrame

    TP.SavedListFrame = Instance.new("ScrollingFrame")
    TP.SavedListFrame.Size = UDim2.new(1,0,0,110)
    TP.SavedListFrame.Position = UDim2.new(0,0,0,26)
    TP.SavedListFrame.BackgroundTransparency = 1
    TP.SavedListFrame.BorderSizePixel = 0
    TP.SavedListFrame.ScrollBarThickness = 3
    TP.SavedListFrame.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    TP.SavedListFrame.CanvasSize = UDim2.new(0,0,0,0)
    TP.SavedListFrame.Parent = TP.SavedFrame

    TP.SavedLayout = Instance.new("UIListLayout")
    TP.SavedLayout.Padding = UDim.new(0,4)
    TP.SavedLayout.Parent = TP.SavedListFrame
    TP.SavedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        TP.SavedListFrame.CanvasSize = UDim2.new(0,0,0, TP.SavedLayout.AbsoluteContentSize.Y + 10)
    end)
end

local function tpWithWarning(action)
    if not Settings.DisableWarnings then
        ShowTabWarning("⚠ ТЕЛЕПОРТ", "Телепорт может вызвать кик. Продолжить?", action)
    else action() end
end
local function teleportTo(targetCFrame)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        Notify("error", "Телепорт", "Персонаж не найден", 2)
        return
    end
    local oldPos = char.HumanoidRootPart.Position
    local ok = pcall(function() char.HumanoidRootPart.CFrame = targetCFrame end)
    if not ok then
        Notify("error", "Телепорт", "Ошибка перемещения", 2)
        return
    end
    task.wait(0.1)
    if (char.HumanoidRootPart.Position - oldPos).Magnitude < 1 then
        Notify("error", "Телепорт", "Перемещение заблокировано (карта/античит)", 2)
    else
        Notify("success", "Телепорт", "Перемещение выполнено", 2)
    end
end

    TP.SaveLocBtn.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local pos = char.HumanoidRootPart.CFrame
            table.insert(Settings.SavedLocations, {Name = "Loc ".. #Settings.SavedLocations+1, CFrame = pos})
            RefreshSavedLocations()
            Notify("success", "Позиция сохранена", "Слот " .. #Settings.SavedLocations)
        end
    end)
    TP.TpLastBtn.MouseButton1Click:Connect(function()
        local last = Settings.SavedLocations[#Settings.SavedLocations]
        if not last then
            Notify("error", "Телепорт", "Нет сохранённой позиции")
            return
        end
        tpWithWarning(function()
            teleportTo(last.CFrame)
        end)
    end)
    TP.SpawnBtn.MouseButton1Click:Connect(function()
    tpWithWarning(function()
        local found = false
        local spawns = workspace:FindFirstChild("SpawnLocation")
        if spawns then
            teleportTo(spawns.CFrame + Vector3.new(0,3,0))
            found = true
        else
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("SpawnLocation") then
                    teleportTo(obj.CFrame + Vector3.new(0,3,0))
                    found = true
                    break
                end
            end
        end
        if not found then
            Notify("error", "Телепорт", "Спавн не найден")
        end
    end)
end)
TP.ClearSavedBtn.MouseButton1Click:Connect(function()
    Settings.SavedLocations = {}
    Settings.LastSavedPosition = nil
    RefreshSavedLocations()
end)

function RefreshSavedLocations()
    for _, child in ipairs(TP.SavedListFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    for i, loc in ipairs(Settings.SavedLocations) do
        local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,28) frame.BackgroundTransparency=1 frame.Parent=TP.SavedListFrame
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
    for _, child in ipairs(TP.FavListFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    local sorted = {}
    for player, _ in pairs(FavoritePlayers) do if player and player:IsA("Player") and player ~= LocalPlayer then table.insert(sorted, player) end end
    table.sort(sorted, function(a,b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(sorted) do
        local dist = ""; local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            dist = " ("..math.floor((char.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).Magnitude).."m)"
        end
        local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,28) frame.BackgroundTransparency=1 frame.Parent=TP.FavListFrame
        local bgc, txtc = GetTeamButtonColor(player)
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,-30,1,0) btn.Position=UDim2.new(0,0,0,0) btn.BackgroundColor3=bgc btn.Text="★ "..player.DisplayName.." (@"..player.Name..")"..dist btn.TextColor3=txtc btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=frame
        local removeBtn = Instance.new("TextButton") removeBtn.Size=UDim2.new(0,24,0,24) removeBtn.Position=UDim2.new(1,-26,0,2) removeBtn.BackgroundColor3=Color3.fromRGB(200,40,40) removeBtn.Text="X" removeBtn.TextColor3=Color3.fromRGB(255,255,255) removeBtn.Font=Enum.Font.GothamBold removeBtn.TextSize=13 removeBtn.Parent=frame
        local plrRef = player
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function()
                local c = LocalPlayer.Character
                if not c or not c:FindFirstChild("HumanoidRootPart") then
                    Notify("error", "Телепорт", "Ваш персонаж не найден")
                    return
                end
                if not plrRef or not plrRef.Parent then
                    Notify("error", "Телепорт", "Игрок вышел из игры")
                    return
                end
                local tc = plrRef.Character
                if not tc or not tc:FindFirstChild("HumanoidRootPart") then
                    Notify("error", "Телепорт", "Цель недоступна (нет персонажа)")
                    return
                end
                local fromPos = c.HumanoidRootPart.Position
                local ok = pcall(function()
                    c.HumanoidRootPart.CFrame = tc.HumanoidRootPart.CFrame + Vector3.new(0,3,0)
                end)
                if not ok then
                    Notify("error", "Телепорт", "Ошибка перемещения")
                    return
                end
                task.wait(0.1)
                if (c.HumanoidRootPart.Position - fromPos).Magnitude < 1 then
                    Notify("error", "Телепорт", "Перемещение заблокировано (карта/античит)")
                else
                    Notify("success", "Телепорт", "Перемещён к " .. plrRef.DisplayName)
                end
            end)
        end)
        removeBtn.MouseButton1Click:Connect(function()
            FavoritePlayers[plrRef] = nil
            RefreshFavorites()
            RefreshPlayerList()
        end)
    end
end

function RefreshPlayerList()

    for _, child in ipairs(TP.PlayerListFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    local sorted = {}; for _, p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(sorted, p) end end
    table.sort(sorted, function(a,b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
    for _, player in ipairs(sorted) do
        local dist = ""; local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            dist = " ("..math.floor((char.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).Magnitude).."m)"
        end
        local frame = Instance.new("Frame") frame.Size=UDim2.new(1,0,0,28) frame.BackgroundTransparency=1 frame.Parent=TP.PlayerListFrame
        local bgc, txtc = GetTeamButtonColor(player)
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,-30,1,0) btn.Position=UDim2.new(0,0,0,0) btn.BackgroundColor3=bgc btn.Text=player.DisplayName.." (@"..player.Name..")"..dist btn.TextColor3=txtc btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=frame
        local plrRef = player
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function()
                local c = LocalPlayer.Character
                local tc = plrRef and plrRef.Character
                if not c or not c:FindFirstChild("HumanoidRootPart") then
                    Notify("error", "Телепорт", "Ваш персонаж не найден", 2)
                    return
                end
                if not plrRef or not plrRef.Parent then
                    Notify("error", "Телепорт", "Игрок вышел из игры", 2)
                    return
                end
                if not tc or not tc:FindFirstChild("HumanoidRootPart") then
                    Notify("error", "Телепорт", "Цель недоступна (нет персонажа)", 2)
                    return
                end
                teleportTo(tc.HumanoidRootPart.CFrame + Vector3.new(0,3,0))
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

function RefreshNPCList()
    for _, child in ipairs(TP.NpcListFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    for _, data in ipairs(npcCacheData) do
        local model = data.Model; local name = data.Name
        local btn = Instance.new("TextButton") btn.Size=UDim2.new(1,0,0,28) btn.BackgroundColor3=Color3.fromRGB(40,40,40) btn.Text=name btn.TextColor3=Color3.fromRGB(255,200,100) btn.Font=Enum.Font.Gotham btn.TextSize=12 btn.Parent=TP.NpcListFrame
        btn.MouseButton1Click:Connect(function()
            tpWithWarning(function()
                local c = LocalPlayer.Character
                if not c or not c:FindFirstChild("HumanoidRootPart") then
                    Notify("error", "Телепорт", "Ваш персонаж не найден")
                    return
                end
                if not model or not model.Parent then
                    Notify("error", "Телепорт", "NPC больше не существует")
                    return
                end
                local pos = Vector3.zero
                pcall(function() pos = model:GetPivot().Position end)
                if pos == Vector3.zero and model.PrimaryPart then pos = model.PrimaryPart.Position end
                if pos == Vector3.zero then
                    Notify("error", "Телепорт", "Не удалось определить позицию NPC")
                    return
                end
                local fromPos = c.HumanoidRootPart.Position
                pcall(function() c.HumanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0,5,0)) end)
                task.wait(0.1)
                if (c.HumanoidRootPart.Position - fromPos).Magnitude < 1 then
                    Notify("error", "Телепорт", "Перемещение заблокировано")
                else
                    Notify("success", "Телепорт", "Перемещён к NPC")
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

-- настройки (вкладка)
local setPage = TabPages[9]
CreateSection(setPage)
CreateToggle(setPage, "Показывать FPS", function(v)
    Settings.ShowFPS = v
    UpdateFPSPingDisplay()
    if v then
        Notify("info", "FPS", "Отображение включено")
    else
        Notify("info", "FPS", "Отображение выключено")
    end
end, Settings.ShowFPS)

CreateToggle(setPage, "Показывать пинг", function(v)
    Settings.ShowPing = v
    UpdateFPSPingDisplay()
    if v then
        Notify("info", "Пинг", "Отображение включено")
    else
        Notify("info", "Пинг", "Отображение выключено")
    end
end, Settings.ShowPing)

CreateToggle(setPage, "Кнопки игроков в цвет команды", function(v)
    Settings.TP_TeamColorButtons = v
    if currentTabIndex == 7 then RefreshTPTab()
    elseif currentTabIndex == 8 then RefreshSpectateList() end
    if v then
        Notify("info", "Кнопки", "В цвет команды")
    else
        Notify("info", "Кнопки", "Обычный цвет")
    end
end, Settings.TP_TeamColorButtons)

CreateToggle(setPage, "Прозрачность меню", function(v)
    Settings.MenuTransparency = v and 0.5 or 0.05
    MainFrame.BackgroundTransparency = Settings.MenuTransparency
    if v then
        Notify("info", "Меню", "Повышенная прозрачность")
    else
        Notify("info", "Меню", "Обычная прозрачность")
    end
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
        Notify("info", "Проверка", "Глубокая проверка запущена", 3)
        UpdateAntiCheatStatus(Locales.t("Запуск глубокой проверки..."), Color3.fromRGB(255, 255, 0))

        task.spawn(function()
            local ok, res = pcall(DeepDetectAntiCheat)
            if not ok or type(res) ~= "table" then
                CritError("DeepDetectAntiCheat", tostring(res))
                deepCheckBtn.Text = Locales.t("Глубокая проверка")
                deepCheckBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                return
            end
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
    pcall(function() Camera.CameraType = s.CameraType end)
    pcall(function() Camera.CameraSubject = s.CameraSubject end)
    pcall(function() LocalPlayer.CameraMode = s.CameraMode end)
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

function SetAutoClickerEnabled(val, force)
    if not val and not force and tick() - lastAutoClickerEnableTime < 1.0 then
        Settings.AutoClicker_Enabled = true
        if ToggleRefs.AutoClicker then ToggleRefs.AutoClicker.SetState(true) end
        Notify("warn", "Auto Clicker", "Подожди секунду", 2)
        return false
    end
    if val and not mouse1press then
        Notify("error", "Auto Clicker", "Эмуляция кликов недоступна")
        return false
    end
    Settings.AutoClicker_Enabled = val
    if val then
        lastAutoClickerEnableTime = tick()
        if autoClickerConnection then autoClickerConnection:Disconnect() end
        autoClickerLastClick = tick()
        autoClickerConnection = RunService.RenderStepped:Connect(function()
            if not Settings.AutoClicker_Enabled then return end
            local now = tick()
            if now - autoClickerLastClick >= Settings.AutoClicker_Delay then
                fastClick(Settings.AutoClicker_HoldDuration)
                autoClickerLastClick = now
            end
        end)
        if ToggleRefs.AutoClicker then ToggleRefs.AutoClicker.SetState(true) end
        Notify("success", "Auto Clicker", "Включён")
    else
        if autoClickerConnection then autoClickerConnection:Disconnect() autoClickerConnection = nil end
        if ToggleRefs.AutoClicker then ToggleRefs.AutoClicker.SetState(false) end
    end
    return true
end

-- ESP
local ESPBoxes, NPC_ESP = {}, {}
local npcFrozenState = {}
local ESPSelfCheck = {
    player = { armed = false, drew = false, armedAt = 0, lastWarn = 0 },
    npc    = { armed = false, drew = false, armedAt = 0, lastWarn = 0 },
    graceTime = 3,
    cooldown  = 20,
}

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

    -- контуры
    pcall(function() esp.BoxOutline = Drawing.new("Square"); esp.BoxOutline.Visible = false; esp.BoxOutline.Filled = false end)
    pcall(function() esp.TracerOutline = Drawing.new("Line"); esp.TracerOutline.Visible = false end)
    pcall(function()
        esp.HeadDotOutline = Drawing.new("Circle")
        esp.HeadDotOutline.Visible = false
        esp.HeadDotOutline.NumSides = Settings.ESP_HeadDotNumSides
        esp.HeadDotOutline.Filled = false
    end)

    -- основное
    pcall(function() esp.Box = Drawing.new("Square"); esp.Box.Visible = false; esp.Box.Filled = false end)
    pcall(function() esp.Tracer = Drawing.new("Line"); esp.Tracer.Visible = false end)
    pcall(function() esp.Name = Drawing.new("Text"); esp.Name.Visible = false; esp.Name.Center = true; esp.Name.Outline = true end)
    pcall(function() esp.HealthBar = Drawing.new("Line"); esp.HealthBar.Visible = false end)
    pcall(function() esp.HealthText = Drawing.new("Text"); esp.HealthText.Visible = false; esp.HealthText.Center = true; esp.HealthText.Outline = true end)
    pcall(function() esp.Distance = Drawing.new("Text"); esp.Distance.Visible = false; esp.Distance.Center = true; esp.Distance.Outline = true end)
    pcall(function()
        esp.HeadDot = Drawing.new("Circle")
        esp.HeadDot.Visible = false
        esp.HeadDot.NumSides = Settings.ESP_HeadDotNumSides
    end)

    pcall(function() esp.ViewDir = Drawing.new("Line"); esp.ViewDir.Visible = false end)
    pcall(function()
        esp.ViewDirMark = Drawing.new("Text")
        esp.ViewDirMark.Visible = false
        esp.ViewDirMark.Center = true
        esp.ViewDirMark.Outline = true
        esp.ViewDirMark.OutlineColor = Color3.fromRGB(0, 0, 0)
    end)

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
    pcall(function() if esp.BoxOutline then esp.BoxOutline:Remove() end end)
    pcall(function() if esp.TracerOutline then esp.TracerOutline:Remove() end end)
    pcall(function() if esp.HealthBarOutline then esp.HealthBarOutline:Remove() end end)
    pcall(function() if esp.HeadDot then esp.HeadDot:Remove() end end)
    pcall(function() if esp.HeadDotOutline then esp.HeadDotOutline:Remove() end end)
    pcall(function() if esp.ViewDir then esp.ViewDir:Remove() end end)
    pcall(function() if esp.ViewDirMark then esp.ViewDirMark:Remove() end end)
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
    if playerChams[player] and playerChams[player].Parent == char then
        UpdateChamsBrightness()
        return
    end
    removeCham(player)
    local brightness = Settings.ESP_ChamsBrightness / 100
    local highlight = Instance.new("Highlight")
    highlight.FillColor = Settings.AccentColor
    highlight.OutlineColor = Settings.AccentColor
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 1 - brightness * 0.5
    highlight.OutlineTransparency = 1 - brightness
    highlight.Parent = char
    playerChams[player] = highlight
    table.insert(chamsHighlights, highlight)
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
    if not model or not model.Parent then return end
    local already = nil
    for h, m in pairs(npcChamsHighlights) do
        if m == model and h.Parent == model then already = h break end
    end
    if already then
        if not Settings.ESP_NPC_Chams then already.Enabled = false end
        return
    end
    if not Settings.ESP_NPC_Chams then return end
    local brightness = Settings.ESP_NPC_ChamsBrightness / 100
    local highlight = Instance.new("Highlight")
    highlight.FillColor = Settings.AccentColor
    highlight.OutlineColor = Settings.AccentColor
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 1 - brightness * 0.5
    highlight.OutlineTransparency = 1 - brightness
    highlight.Parent = model
    npcChamsHighlights[highlight] = model
end

function UpdateNpcChams()
    for h, _ in pairs(npcChamsHighlights) do
        pcall(function() h:Destroy() end)
    end
    npcChamsHighlights = {}
    if not Settings.ESP_NPC_Chams then return end
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                updateNpcChamsForModel(model)
            end
        end
    end
end

function UpdateNpcChamsBrightness()
    local brightness = Settings.ESP_NPC_ChamsBrightness / 100
    for h, m in pairs(npcChamsHighlights) do
        if h and h.Parent and m and m.Parent then
            pcall(function()
                h.FillTransparency = 1 - brightness * 0.5
                h.OutlineTransparency = 1 - brightness
            end)
        else
            if h then pcall(function() h:Destroy() end) end
            npcChamsHighlights[h] = nil
        end
    end
end

-- подписки
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then setupChamsForPlayer(plr) end
end
Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then
        setupChamsForPlayer(plr)
    end
end)
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
workspace.DescendantAdded:Connect(function(obj)
    if not Settings.ESP_NPC_Chams then return end
    if not obj:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(obj) then return end
    task.wait(0.5)
    if not obj.Parent then return end
    local hum = obj:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        updateNpcChamsForModel(obj)
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if ESPBoxes[plr] then RemoveFullESP(ESPBoxes[plr]); ESPBoxes[plr] = nil end
    removeChamsForPlayer(plr)
    FavoritePlayers[plr] = nil
    if Trail and Trail.ClearPlayer then Trail.ClearPlayer(plr) end
    if currentTabIndex == 7 then RefreshTPTab() end
end)

local highlightDrawings = {}; local itemObjects = {}; local lastHighlightUpdate = 0
local itemDescendantAddedCon
function addItemToCache(obj)
    if itemObjects[obj] then return end
    local char = LocalPlayer.Character
    if char and (obj:IsDescendantOf(char) or obj == char) then return end

    local pos = nil
    local name = obj.Name

    if obj:IsA("Tool") or obj:IsA("Model") then
        local handle = obj:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            pos = handle.Position
        end
    elseif obj:IsA("BasePart") then
        local hasClick = false
        pcall(function()
            hasClick = obj:FindFirstChildWhichIsA("ClickDetector", true)
                    or obj:FindFirstChildWhichIsA("ProximityPrompt", true)
        end)
        if hasClick or not Settings.Highlight_OnlyInteractive then
            pos = obj.Position
        end
    end

    if pos then itemObjects[obj] = {pos = pos, name = name} end
end
function refreshItemCache()
    local toRemove = {}
    for obj, data in pairs(itemObjects) do
        if not obj or not obj.Parent then table.insert(toRemove, obj)
        else
            local newPos = nil
            if obj:IsA("Tool") or obj:IsA("Model") then
                local handle = obj:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then newPos = handle.Position end
            elseif obj:IsA("BasePart") then
                newPos = obj.Position
            end
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


-- наводка от центра (frame-independent + cap)
local function v26_smoothAim(goalVec, dt)
    local cp = Camera.CFrame.Position
    local dir = goalVec - cp
    if dir.Magnitude < 0.01 then return end

    local desired = CFrame.new(cp, cp + dir.Unit)

    local raw = math.clamp(Settings.Aim_Smoothness or 0.5, 0.05, 1.0)
    local smooth = math.clamp(1 - raw, 0, 0.95)

    local k = 1 - math.exp(-(1 - smooth) * 25 * dt)
    local target = Camera.CFrame:Lerp(desired, k)

    local maxSpeed = 10
    local curLook = Camera.CFrame.LookVector
    local newLook = target.LookVector
    local dot = math.clamp(curLook:Dot(newLook), -1, 1)
    local ang = math.acos(dot)
    if ang > 0.0005 then
        local maxStep = maxSpeed * dt
        if ang > maxStep then
            local ax = curLook:Cross(newLook)
            if ax.Magnitude > 0.0001 then
                ax = ax.Unit
                newLook = CFrame.fromAxisAngle(ax, maxStep) * curLook
                target = CFrame.new(cp, cp + newLook)
            end
        end
    end

    Camera.CFrame = target
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
    rayParams.FilterType = RAYCAST_EXCLUDE

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
RENDER = {}
do
    RENDER.FPSFrames = 0
    RENDER.FPSTime = tick()
    RENDER.FrameCounter = 0
    RENDER.NpcFrameCounter = 0
    RENDER.LastTabListRefresh = 0
    RENDER.TpRefreshStep = 0
    RENDER.SpecRefreshStep = 0

    if DrawingAvailable then
        pcall(function() RENDER.FOVCircle = Drawing.new("Circle") end)
        if RENDER.FOVCircle then
            RENDER.FOVCircle.Visible = false
            RENDER.FOVCircle.Thickness = 1.5
            RENDER.FOVCircle.NumSides = 60
            RENDER.FOVCircle.Filled = false
        end
    end
end

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

if DrawingAvailable then pcall(function() RENDER.FPS = Drawing.new("Text") end) end
if RENDER.FPS then
    RENDER.FPS.Visible = false
    RENDER.FPS.Position = Vector2.new(10,10)
    RENDER.FPS.Size = 18
    RENDER.FPS.Color = Color3.new(0,1,0)
    RENDER.FPS.Outline = true
end

function UpdateFPSPingDisplay()
    if not RENDER.FPS then return end
    local text = ""
    if Settings.ShowFPS then
        text = text .. "FPS: " .. RENDER.FPSFrames
    end
    if Settings.ShowPing then
        local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
        if text ~= "" then text = text .. " | " end
        text = text .. "Ping: " .. ping .. "ms"
    end
    RENDER.FPS.Text = text
    RENDER.FPS.Visible = (Settings.ShowFPS or Settings.ShowPing)
end

local function GetESPColor(baseColor, teamColorOverride)
    if Settings.ESP_Rainbow then
        local s = math.max(0.1, Settings.ESP_RainbowSpeed)
        return Color3.fromHSV((tick() % s) / s, 1, 1)
    end
    if Settings.ESP_TeamColors and teamColorOverride then
        return teamColorOverride
    end
    return baseColor
end

local function HidePlayerESP(esp)
    if not esp then return end
    if esp.Box then pcall(function() esp.Box.Visible = false end) end
    if esp.Tracer then pcall(function() esp.Tracer.Visible = false end) end
    if esp.Name then pcall(function() esp.Name.Visible = false end) end
    if esp.HealthBar then pcall(function() esp.HealthBar.Visible = false end) end
    if esp.HealthText then pcall(function() esp.HealthText.Visible = false end) end
    if esp.Distance then pcall(function() esp.Distance.Visible = false end) end
    if esp.BoxOutline then pcall(function() esp.BoxOutline.Visible = false end) end
    if esp.TracerOutline then pcall(function() esp.TracerOutline.Visible = false end) end
    if esp.HealthBarOutline then pcall(function() esp.HealthBarOutline.Visible = false end) end
    if esp.HeadDot then pcall(function() esp.HeadDot.Visible = false end) end
    if esp.HeadDotOutline then pcall(function() esp.HeadDotOutline.Visible = false end) end
    if esp.ViewDir then pcall(function() esp.ViewDir.Visible = false end) end
    if esp.ViewDirMark then pcall(function() esp.ViewDirMark.Visible = false end) end
    if esp.Skeleton then
        for _, line in ipairs(esp.Skeleton) do pcall(function() line.Visible = false end) end
    end
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
    rayParams.FilterType = RAYCAST_EXCLUDE
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

local function _IsAimKeyPressed()
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

local UpdateRealisticAimRef

local function _RunSmartAim(dt)
    local shouldAim = Settings.Aim_AutoAim or (Settings.Aim_Enabled and _IsAimKeyPressed())
    if shouldAim then
        local part, char = SA_GetTarget()
        if part and char then
            SmartAim.TargetPart = part
            SmartAim.TargetChar = char
            SmartAim.LastAimedPart = part

            if Settings.Aim_Realistic and UpdateRealisticAimRef then
                pcall(UpdateRealisticAimRef, dt, part)
            else
                SA_UpdateAnchor(part, char, dt)
                if SmartAim.Anchor then
                    pcall(SA_MoveMouse, SmartAim.Anchor)
                end
            end
        else
            SmartAim.TargetPart = nil
            SmartAim.TargetChar = nil
            SmartAim.Anchor = nil
            SmartAim.AnchorChar = nil
            SmartAim.LastAimedPart = nil
        end
    else
        SmartAim.TargetPart = nil
        SmartAim.TargetChar = nil
        SmartAim.Anchor = nil
        SmartAim.AnchorChar = nil
        SmartAim.LastAimedPart = nil
        SmartAim.LockedChar = nil
        SmartAim.LockedPart = nil
        SmartAim.LockedLost = 0
    end
end

-- реалистичная наводка
local function UpdateRealisticAim(dt, targetPart)
    if not mousemoverelFn then return end
    if not targetPart or not targetPart.Parent then return end

    -- Задержка реакции
    if Settings.Aim_ReactionEnabled then
        local tc = targetPart.Parent
        if aimRealisticState.lastTarget ~= tc then
            aimRealisticState.lastTarget = tc
            aimRealisticState.reactionTimer = tick() + Settings.Aim_ReactionDelay
        end
        if tick() < aimRealisticState.reactionTimer then return end
    end

    -- Куда надо попасть (экранные координаты цели)
    local sp, on = Camera:WorldToViewportPoint(targetPart.Position)
    if not on or sp.Z <= 0 then return end

    -- Куда сейчас указывает мышь
    local mp = UserInputService:GetMouseLocation()
    local dx = sp.X - mp.X
    local dy = sp.Y - mp.Y
    local dist = math.sqrt(dx*dx + dy*dy)

    -- Мёртвая зона
    if dist < (Settings.Aim_MinPixel or 2.0) then return end

    -- «Дрожание» руки — синусоидальный шум
    aimRealisticState.noiseSeed = aimRealisticState.noiseSeed + dt * 4
    local wobX = (math.noise(aimRealisticState.noiseSeed, 0, 0) - 0.5) * 2
    local wobY = (math.noise(0, aimRealisticState.noiseSeed, 0) - 0.5) * 2

    -- Скорость зависит от «Плавности»: smooth=0.5 → ~12% пути за кадр
    local smooth = clamp(Settings.Aim_Smoothness or 0.5, 0.05, 0.95)
    local baseStep = (1 - smooth) * 0.30

    -- Шум пропорционален расстоянию — вблизи почти исчезает
    local jitterScale = math.min(dist / 80, 1) * 6
    local stepX = dx * baseStep + wobX * jitterScale
    local stepY = dy * baseStep + wobY * jitterScale

    -- Иногда «промах» — перелёт, потом плавная коррекция
    if math.random() < 0.10 and dist > 30 then
        stepX = stepX * 1.5
        stepY = stepY * 1.5
    end

    -- Жёсткий предел: не больше 22 пикселей за кадр (иначе рывок)
    local maxStep = 22
    local mag = math.sqrt(stepX*stepX + stepY*stepY)
    if mag > maxStep then
        stepX = stepX / mag * maxStep
        stepY = stepY / mag * maxStep
    end

    -- Иногда пауза (2% случаев) — имитация «задумался»
    if math.random() < 0.02 then return end

    pcall(mousemoverelFn, stepX, stepY)
end
UpdateRealisticAimRef = UpdateRealisticAim

FeatureHealth.Register("Speed_Enabled", "Speed Hack", function()
    local c = LocalPlayer.Character
    if not c then return false, "Персонаж не найден" end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return false, "Тело персонажа не загрузилось" end
    if h.Health <= 0 then return false, "Персонаж мёртв" end
    local target = math.min(Settings.Speed_Value, MAX_SAFE_SPEED)
    if math.abs(h.WalkSpeed - target) > 2 then
        return false, "Игра сбрасывает WalkSpeed (сервер/античит)"
    end
    return true
end, ToggleRefs.Speed, function() UpdateSpeed() end)

FeatureHealth.Register("Flight_Enabled", "Flight", function()
    local c = LocalPlayer.Character
    if not c then return false, "Персонаж не найден" end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return false, "Тело персонажа не загрузилось" end
    if h.Health <= 0 then return false, "Персонаж мёртв" end
    local root = c:FindFirstChild("HumanoidRootPart")
    if not root then return false, "Персонаж ещё не прогрузился" end
    if not flightGyro then return false, "BodyGyro не создан" end
    if not flightGyro.Parent then return false, "BodyGyro удалён игрой" end
    if flightGyro.Parent ~= root then return false, "BodyGyro оторван от персонажа" end
    if not flightVel then return false, "BodyVelocity не создан" end
    if not flightVel.Parent then return false, "BodyVelocity удалён игрой" end
    if flightVel.Parent ~= root then return false, "BodyVelocity оторван от персонажа" end
    if h.WalkSpeed ~= 0 then
        return false, "Игра сбрасывает WalkSpeed во время полёта"
    end
    return true
end, ToggleRefs.Flight, function() UpdateFlight() end)

FeatureHealth.Register("Noclip_Enabled", "Noclip", function()
    local c = LocalPlayer.Character
    if not c then return true end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            return false, "Сервер возвращает CanCollide"
        end
    end
    return true
end, ToggleRefs.Noclip, function() UpdateNoclip() end)

FeatureHealth.Register("GodMode_Enabled", "God Mode", function()
    local c = LocalPlayer.Character
    if not c then return false, "Персонаж не найден" end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return false, "Тело персонажа не загрузилось" end
    if h.Health <= 0 then return false, "Персонаж погиб несмотря на God Mode" end
    return true
end, nil, nil)

FeatureHealth.Register("Freeze_Enabled", "Freeze", function()
    local c = LocalPlayer.Character
    if not c then return false, "Персонаж не найден" end
    local r = c:FindFirstChild("HumanoidRootPart")
    if not r then return false, "HumanoidRootPart не найден" end
    if not r.Anchored then return false, "Сервер снимает Anchored" end
    return true
end, nil, function() UpdateFreeze() end)

FeatureHealth.Register("AutoClicker_Enabled", "Auto Clicker", function()
    if not autoClickerConnection then
        return false, "Соединение сломано"
    end
    if not mouse1press then
        return false, "Эмуляция кликов стала недоступна"
    end
    return true
end, ToggleRefs.AutoClicker, function() SetAutoClickerEnabled(false, true) end)

FeatureHealth.Register("Aim_Enabled", "Aimbot", function()
    if not mousemoverelFn then return false, "mousemoverel недоступен" end
    if not LocalPlayer.Character then return false, "Персонаж не найден" end
    return true
end, ToggleRefs.Aimbot, nil)

FeatureHealth.Register("Aim_AutoAim", "Auto Aim", function()
    if not mousemoverelFn then return false, "mousemoverel недоступен" end
    if not LocalPlayer.Character then return false, "Персонаж не найден" end
    return true
end, ToggleRefs.AutoAim, nil)

FeatureHealth.Register("Trigger_Enabled", "Triggerbot", function()
    if not mouse1press then return false, "Эмуляция кликов недоступна" end
    if not LocalPlayer.Character then return false, "Персонаж не найден" end
    return true
end, ToggleRefs.Trigger, nil)

mainRenderConnection = RunService.RenderStepped:Connect(function(dt)
    if not MenuLoaded then return end
    if #CRIT_ERRORS > 0 then
        for _, e in ipairs(CRIT_ERRORS) do
            pcall(Notify, "error", "Крит: " .. e.source, e.reason, 8)
        end
        CRIT_ERRORS = {}
    end
    do
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local wantSpeed
                if Settings.Flight_Enabled then
                    wantSpeed = 0
                elseif Settings.Speed_Enabled then
                    wantSpeed = math.min(Settings.Speed_Value, MAX_SAFE_SPEED)
                end
                if wantSpeed and hum.WalkSpeed ~= wantSpeed then
                    hum.WalkSpeed = wantSpeed
                end
            end
        end
    end
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
    if openPaletteData and openPaletteData.palette
       and openPaletteData.palette.Parent
       and openPaletteData.palette.Visible then
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

      RENDER.FrameCounter = RENDER.FrameCounter + 1
    RENDER.NpcFrameCounter = RENDER.NpcFrameCounter + 1
    RENDER.FPSFrames = RENDER.FPSFrames + 1
    if tick() - RENDER.FPSTime >= 1 then
        UpdateFPSPingDisplay()
        RENDER.FPSFrames = 0
        RENDER.FPSTime = tick()
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

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if not ESPBoxes[plr] then ESPBoxes[plr] = CreateFullESP() end
        end
    end
    for plr, esp in pairs(ESPBoxes) do
        if not Players:FindFirstChild(plr.Name) or plr == LocalPlayer then RemoveFullESP(esp); ESPBoxes[plr] = nil end
    end
  
 -- ================= PLAYER ESP =================
    local espMyChar = LocalPlayer.Character
    local espMyRoot = espMyChar and espMyChar:FindFirstChild("HumanoidRootPart")
    local espViewport = Camera.ViewportSize

    if Settings.ESP_Enabled then
        for plr, esp in pairs(ESPBoxes) do
            if esp then
                if esp.Skeleton then
                    for _, line in ipairs(esp.Skeleton) do
                        if line and line.Visible then line.Visible = false end
                    end
                end

                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local head = char and char:FindFirstChild("Head")
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local show = true

                if not char or not hum or hum.Health <= 0 or not head or not root then show = false end
                if show and not IsEnemy(plr) then show = false end
                if show and Settings.ESP_VisibilityCheck and not IsVisible(head) then show = false end
                if show and Settings.ESP_LimitDistance and espMyRoot then
                    if (espMyRoot.Position - root.Position).Magnitude > Settings.ESP_MaxDistance then show = false end
                end

                if not show then
                    HidePlayerESP(esp)
                else
                    ESPSelfCheck.player.drew = true
                    local top = head.Position + Vector3.new(0, head.Size.Y/2, 0)                    local bot = root.Position - Vector3.new(0, hum.HipHeight, 0)
                    local sTop, vTop = Camera:WorldToViewportPoint(top)
                    local sBot, vBot = Camera:WorldToViewportPoint(bot)

                    if not vTop or not vBot then
                        HidePlayerESP(esp)
                    else
                        local boxTop, boxBot = sTop.Y, sBot.Y
                        local boxH = math.abs(boxBot - boxTop)
                        local boxW = boxH * 0.4
                        local boxLeft = sTop.X - boxW / 2

                        if boxLeft > espViewport.X or (boxLeft + boxW) < 0 or boxTop > espViewport.Y or boxBot < 0 then
                            HidePlayerESP(esp)
                        else
                            local hpPct = hum.Health / hum.MaxHealth
                            local tc = plr.TeamColor and plr.TeamColor.Color

                            -- BOX
                            if Settings.ESP_Boxes and esp.Box then
                                local boxColor = GetESPColor(Settings.ESP_BoxColor, tc)
                                if Settings.ESP_OutlineMaster and Settings.ESP_BoxOutline and esp.BoxOutline then
                                    local ot = Settings.ESP_BoxOutlineThickness or 1.5
                                    esp.BoxOutline.Visible = true
                                    esp.BoxOutline.Position = Vector2.new(boxLeft - ot, boxTop - ot)
                                    esp.BoxOutline.Size = Vector2.new(boxW + ot*2, boxH + ot*2)
                                    esp.BoxOutline.Color = Settings.ESP_BoxOutlineColor
                                    esp.BoxOutline.Thickness = ot
                                elseif esp.BoxOutline then
                                    esp.BoxOutline.Visible = false
                                end
                                esp.Box.Visible = true
                                esp.Box.Position = Vector2.new(boxLeft, boxTop)
                                esp.Box.Size = Vector2.new(boxW, boxH)
                                esp.Box.Color = boxColor
                                esp.Box.Thickness = Settings.ESP_BoxThickness
                            else
                                if esp.Box then esp.Box.Visible = false end
                                if esp.BoxOutline then esp.BoxOutline.Visible = false end
                            end

                            -- TRACER
                            if Settings.ESP_Tracers and esp.Tracer then
                                local tracerColor = GetESPColor(Settings.ESP_TracerColor, tc)
                                local fromPos
                                if Settings.ESP_TracerPosition == 2 then
                                    fromPos = Vector2.new(espViewport.X/2, espViewport.Y/2)
                                elseif Settings.ESP_TracerPosition == 3 then
                                    fromPos = UserInputService:GetMouseLocation()
                                else
                                    fromPos = Vector2.new(espViewport.X/2, espViewport.Y)
                                end
                                esp.Tracer.Visible = true
                                esp.Tracer.From = fromPos
                                esp.Tracer.To = Vector2.new(sTop.X, boxBot)
                                esp.Tracer.Color = tracerColor
                                esp.Tracer.Thickness = Settings.ESP_TracerThickness
                            elseif esp.Tracer then
                                esp.Tracer.Visible = false
                            end

                            -- NAME
                            if Settings.ESP_Names and esp.Name then
                                esp.Name.Visible = true
                                esp.Name.Position = Vector2.new(sTop.X, boxTop - 16)
                                esp.Name.Text = plr.DisplayName
                                esp.Name.Size = Settings.ESP_NameSize
                                esp.Name.Color = Settings.ESP_NameColor
                            elseif esp.Name then
                                esp.Name.Visible = false
                            end

                            -- HEALTH
                            if esp.HealthBar then
                                if Settings.ESP_HealthMode == "Bar" then
                                    local bt = Settings.ESP_HealthBarWidth
                                    local off = Settings.ESP_HealthBarOffset
                                    local blue = Settings.ESP_HealthBarBlue or 0
                                    local hc = Color3.fromRGB(math.floor(255 - hpPct*255), math.floor(hpPct*255), blue)
                                    local fV, tV
                                    if Settings.ESP_HealthBarPosition == 1 then
                                        local y = boxTop - off - bt/2
                                        fV = Vector2.new(boxLeft, y); tV = Vector2.new(boxLeft + boxW*hpPct, y)
                                    elseif Settings.ESP_HealthBarPosition == 2 then
                                        local y = boxBot + off + bt/2
                                        fV = Vector2.new(boxLeft, y); tV = Vector2.new(boxLeft + boxW*hpPct, y)
                                    elseif Settings.ESP_HealthBarPosition == 4 then
                                        local x = boxLeft + boxW + off + bt/2
                                        fV = Vector2.new(x, boxBot); tV = Vector2.new(x, boxBot + (boxTop-boxBot)*hpPct)
                                    else
                                        local x = boxLeft - off - bt/2
                                        fV = Vector2.new(x, boxBot); tV = Vector2.new(x, boxBot + (boxTop-boxBot)*hpPct)
                                    end
                                    esp.HealthBar.Visible = true
                                    esp.HealthBar.From = fV
                                    esp.HealthBar.To = tV
                                    esp.HealthBar.Color = hc
                                    esp.HealthBar.Thickness = bt
                                    if esp.HealthText then esp.HealthText.Visible = false end
                                elseif Settings.ESP_HealthMode == "Text" and esp.HealthText then
                                    esp.HealthText.Visible = true
                                    esp.HealthText.Position = Vector2.new(sTop.X, boxBot + 4)
                                    esp.HealthText.Text = FormatHPText(hum)
                                    esp.HealthText.Size = Settings.ESP_HealthTextSize
                                    esp.HealthText.Color = Settings.ESP_HealthTextColor
                                    esp.HealthBar.Visible = false
                                else
                                    esp.HealthBar.Visible = false
                                    if esp.HealthText then esp.HealthText.Visible = false end
                                end
                            end

                            -- DISTANCE
                            if Settings.ESP_Distance and esp.Distance and espMyRoot then
                                local dist = math.floor((espMyRoot.Position - root.Position).Magnitude)
                                esp.Distance.Visible = true
                                esp.Distance.Position = Vector2.new(sTop.X, boxBot + 17)
                                esp.Distance.Text = dist .. "m"
                                esp.Distance.Size = Settings.ESP_DistanceSize
                                esp.Distance.Color = Settings.ESP_DistanceColor
                            elseif esp.Distance then
                                esp.Distance.Visible = false
                            end

                            -- HEAD DOT
                            if esp.HeadDot then
                                if Settings.ESP_HeadDot then
                                    local hs, hv = Camera:WorldToViewportPoint(head.Position)
                                    if hv then
                                        local dotColor = GetESPColor(Settings.ESP_HeadDotColor, tc)
                                        local radius
                                        if Settings.ESP_HeadDotRadiusMode == "Фиксированный" then
                                            radius = Settings.ESP_HeadDotFixedRadius
                                        else
                                            radius = math.max(3, math.abs(sTop.Y - sBot.Y) * 0.15)
                                        end
                                        esp.HeadDot.Visible = true
                                        esp.HeadDot.Position = Vector2.new(hs.X, hs.Y)
                                        esp.HeadDot.Radius = radius
                                        esp.HeadDot.Color = dotColor
                                        esp.HeadDot.Thickness = Settings.ESP_HeadDotThickness
                                        esp.HeadDot.NumSides = Settings.ESP_HeadDotNumSides
                                        esp.HeadDot.Filled = Settings.ESP_HeadDotFilled
                                        if Settings.ESP_OutlineMaster and Settings.ESP_HeadDotOutline and esp.HeadDotOutline then
                                            esp.HeadDotOutline.Visible = true
                                            esp.HeadDotOutline.Position = Vector2.new(hs.X, hs.Y)
                                            esp.HeadDotOutline.Radius = radius + 1
                                            esp.HeadDotOutline.Color = Settings.ESP_HeadDotOutlineColor
                                            esp.HeadDotOutline.Thickness = Settings.ESP_HeadDotThickness + 1
                                            esp.HeadDotOutline.NumSides = Settings.ESP_HeadDotNumSides
                                        elseif esp.HeadDotOutline then
                                            esp.HeadDotOutline.Visible = false
                                        end
                                    else
                                        esp.HeadDot.Visible = false
                                        if esp.HeadDotOutline then esp.HeadDotOutline.Visible = false end
                                    end
                                else
                                    esp.HeadDot.Visible = false
                                    if esp.HeadDotOutline then esp.HeadDotOutline.Visible = false end
                                end
                            end

                            -- SKELETON
                            if esp.Skeleton and Settings.ESP_Skeleton then
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
                            end

                            if esp.ViewDir and Settings.ESP_ViewDir and head then
                                if not Settings.ESP_ViewDirOnlyEnemies or IsEnemy(plr) then
                                    local startPos = head.Position
                                    local endPos = startPos + head.CFrame.LookVector * Settings.ESP_ViewDirLength
                                    local s1, v1 = Camera:WorldToViewportPoint(startPos)
                                    local s2, v2 = Camera:WorldToViewportPoint(endPos)
                                    if v1 and v2 and s1.Z > 0 and s2.Z > 0 then
                                        esp.ViewDir.Visible = true
                                        esp.ViewDir.From = Vector2.new(s1.X, s1.Y)
                                        esp.ViewDir.To = Vector2.new(s2.X, s2.Y)
                                        esp.ViewDir.Color = Settings.ESP_ViewDirColor
                                        esp.ViewDir.Thickness = 1
                                    else
                                        esp.ViewDir.Visible = false
                                    end
                                else
                                    esp.ViewDir.Visible = false
                                end
                            elseif esp.ViewDir then
                                esp.ViewDir.Visible = false
                            end


                            if esp.ViewDirMark then
                                local showMark = false
                                if Settings.ESP_ViewDir and Settings.ESP_ViewDirMarkLooking
                                   and head and IsEnemy(plr) then
                                    local myChar = LocalPlayer.Character
                                    local myHead = myChar and myChar:FindFirstChild("Head")
                                    if myHead then
                                        local lookVec = head.CFrame.LookVector
                                        local toMe = myHead.Position - head.Position
                                        local dist = toMe.Magnitude
                                        if dist > 1 then
                                            local dot = lookVec:Dot(toMe.Unit)
                                            local threshold = math.cos(math.rad(Settings.ESP_ViewDirFOV))
                                            if dot >= threshold and RaycastParamsClass then
                                                local rp = RaycastParamsClass.new()
                                                rp.FilterType = RAYCAST_EXCLUDE
                                                rp.FilterDescendantsInstances = {char, myChar}
                                                local hit = workspace:Raycast(head.Position, toMe, rp)
                                                local clear = (hit == nil) or (hit.Instance:IsDescendantOf(myChar))
                                                if clear then
                                                    local hs, hv = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 2.5, 0))
                                                    if hv then
                                                        esp.ViewDirMark.Visible = true
                                                        esp.ViewDirMark.Position = Vector2.new(hs.X, hs.Y)
                                                        esp.ViewDirMark.Text = "👁"
                                                        esp.ViewDirMark.Size = 16
                                                        esp.ViewDirMark.Color = Settings.ESP_ViewDirColor
                                                        showMark = true
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                                if not showMark then
                                    esp.ViewDirMark.Visible = false
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        for _, esp in pairs(ESPBoxes) do
            HidePlayerESP(esp)
        end
    end

--NPC ESP
    if Settings.ESP_NPCs then
        for _, esp in pairs(NPC_ESP) do
            if esp then
                if esp.Box then esp.Box.Visible = false end
                if esp.Tracer then esp.Tracer.Visible = false end
                if esp.Name then esp.Name.Visible = false end
                if esp.HealthBar then esp.HealthBar.Visible = false end
                if esp.Distance then esp.Distance.Visible = false end
                if esp.Skeleton then
                    for _, line in ipairs(esp.Skeleton) do
                        if line then line.Visible = false end
                    end
                end
            end
        end

        local liveNpcs = {}
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    table.insert(liveNpcs, obj)
                end
            end
        end

        for _, model in ipairs(liveNpcs) do
            if not NPC_ESP[model] then NPC_ESP[model] = CreateFullESP() end
            local esp = NPC_ESP[model]
            if esp then
                ESPSelfCheck.npc.drew = true
                local hum = model:FindFirstChildOfClass("Humanoid")
                local health = hum.Health
                local pos = Vector3.zero
                if model.PrimaryPart then pos = model.PrimaryPart.Position
                else pcall(function() pos = model:GetPivot().Position end) end
                local dist = (espMyRoot and (espMyRoot.Position - pos).Magnitude) or 0
                local isNpcFrozen = false
                if Settings.ESP_NPC_FrozenDetection then
                    local state = npcFrozenState[model]
                    if not state then
                        state = {lastPos = pos, lastMoveTime = tick(), everMoved = false}
                        npcFrozenState[model] = state
                    end
                    local moved = (pos - state.lastPos).Magnitude > (Settings.ESP_NPC_FrozenMoveThreshold or 0.1)
                    if moved then
                        state.lastPos = pos
                        state.lastMoveTime = tick()
                        state.everMoved = true
                    end
                    local idleTime = tick() - state.lastMoveTime
                    local requiredTime = state.everMoved
                        and (Settings.ESP_NPC_FrozenSlowTime or 30)
                        or (Settings.ESP_NPC_FrozenQuickTime or 3)
                    isNpcFrozen = idleTime >= requiredTime
                end
                local hideFrozen = Settings.ESP_NPC_FrozenDetection and Settings.ESP_NPC_FrozenHideESP and isNpcFrozen
                if dist <= Settings.ESP_NPC_MaxDistance and not hideFrozen then
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
                        local sTop, vTop = Camera:WorldToViewportPoint(top)
                        local sBot, vBot = Camera:WorldToViewportPoint(bot)
                        if vTop and vBot then
                            local boxTop, boxBot = sTop.Y, sBot.Y
                            local boxH = math.abs(boxBot - boxTop)
                            local boxW = boxH * 0.4
                            local boxLeft = sTop.X - boxW/2
                            if not (boxLeft > espViewport.X or (boxLeft + boxW) < 0 or boxTop > espViewport.Y or boxBot < 0) then
                                local npcBoxColor = Settings.NPC_BoxColor
                                if Settings.ESP_NPC_FrozenDetection and isNpcFrozen then
                                    npcBoxColor = Settings.ESP_NPC_FrozenColor
                                end
                                if esp.Box then
                                    esp.Box.Visible = true
                                    esp.Box.Position = Vector2.new(boxLeft, boxTop)
                                    esp.Box.Size = Vector2.new(boxW, boxH)
                                    esp.Box.Color = npcBoxColor
                                    esp.Box.Thickness = Settings.ESP_NPC_BoxThickness
                                end
                                if esp.Tracer and Settings.ESP_NPC_Tracers then
                                    local fromPos
                                    if Settings.ESP_NPC_TracerPosition == 2 then
                                        fromPos = Vector2.new(espViewport.X/2, espViewport.Y/2)
                                    elseif Settings.ESP_NPC_TracerPosition == 3 then
                                        fromPos = UserInputService:GetMouseLocation()
                                    else
                                        fromPos = Vector2.new(espViewport.X/2, espViewport.Y)
                                    end
                                    esp.Tracer.Visible = true
                                    esp.Tracer.From = fromPos
                                    esp.Tracer.To = Vector2.new(sTop.X, boxBot)
                                    esp.Tracer.Color = Settings.NPC_TracerColor
                                    esp.Tracer.Thickness = Settings.ESP_TracerThickness
                                end
                                if esp.Name and Settings.ESP_NPC_Names then
                                    esp.Name.Visible = true
                                    esp.Name.Position = Vector2.new(sTop.X, boxTop - 16)
                                    esp.Name.Text = model.Name
                                    esp.Name.Size = Settings.ESP_NPC_NameSize
                                    esp.Name.Color = Settings.NPC_NameColor
                                end
                                if esp.HealthBar and Settings.ESP_NPC_HealthMode == "Bar" then
                                    local hpPct = math.clamp(health / hum.MaxHealth, 0, 1)
                                    local fV, tV
                                    if Settings.ESP_NPC_HealthBarPosition == 1 then
                                        local y = boxTop - Settings.ESP_NPC_HealthBarOffset - Settings.ESP_NPC_HealthBarWidth/2
                                        fV = Vector2.new(boxLeft, y); tV = Vector2.new(boxLeft + boxW*hpPct, y)
                                    elseif Settings.ESP_NPC_HealthBarPosition == 2 then
                                        local y = boxBot + Settings.ESP_NPC_HealthBarOffset + Settings.ESP_NPC_HealthBarWidth/2
                                        fV = Vector2.new(boxLeft, y); tV = Vector2.new(boxLeft + boxW*hpPct, y)
                                    elseif Settings.ESP_NPC_HealthBarPosition == 4 then
                                        local x = boxLeft + boxW + Settings.ESP_NPC_HealthBarOffset + Settings.ESP_NPC_HealthBarWidth/2
                                        fV = Vector2.new(x, boxBot); tV = Vector2.new(x, boxBot + (boxTop-boxBot)*hpPct)
                                    else
                                        local x = boxLeft - Settings.ESP_NPC_HealthBarOffset - Settings.ESP_NPC_HealthBarWidth/2
                                        fV = Vector2.new(x, boxBot); tV = Vector2.new(x, boxBot + (boxTop-boxBot)*hpPct)
                                    end
                                    local color = hpPct > 0.5 and Color3.new(1 - (hpPct-0.5)*2, 1, 0) or Color3.new(1, hpPct*2, 0)
                                    esp.HealthBar.Visible = true
                                    esp.HealthBar.From = fV
                                    esp.HealthBar.To = tV
                                    esp.HealthBar.Color = color
                                    esp.HealthBar.Thickness = Settings.ESP_NPC_HealthBarWidth
                                end
                                if esp.Distance and Settings.ESP_NPC_Distance then
                                    esp.Distance.Visible = true
                                    esp.Distance.Position = Vector2.new(sTop.X, boxBot + 17)
                                    esp.Distance.Text = math.floor(dist) .. "m"
                                    esp.Distance.Size = Settings.ESP_NPC_DistanceSize
                                    esp.Distance.Color = Settings.ESP_DistanceColor
                                end
                                if esp.Skeleton and Settings.ESP_NPC_Skeleton then
                                    local partCache = {}
                                    for _, part in ipairs(model:GetChildren()) do
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
                                                line.Color = Settings.ESP_NPC_SkeletonColor
                                                line.Thickness = Settings.ESP_NPC_SkeletonThickness
                                                line.Visible = true
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

        local liveSet = {}
        for _, m in ipairs(liveNpcs) do liveSet[m] = true end
        for model, esp in pairs(NPC_ESP) do
            if not liveSet[model] then
                RemoveFullESP(esp)
                NPC_ESP[model] = nil
                npcFrozenState[model] = nil
            end
        end
    else
        for model, esp in pairs(NPC_ESP) do RemoveFullESP(esp) end
        NPC_ESP = {}
        npcFrozenState = {}
    end

    if RENDER.FOVCircle then
        RENDER.FOVCircle.Visible = Settings.Aim_ShowFOV and (Settings.Aim_Enabled or Settings.Aim_AutoAim)
        if RENDER.FOVCircle.Visible then
            RENDER.FOVCircle.Position = UserInputService:GetMouseLocation()
            RENDER.FOVCircle.Radius = Settings.Aim_FOV
            RENDER.FOVCircle.Color = Settings.Aim_FOVColor
        end
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

-- логика аима — SmartAim
    _RunSmartAim(dt)

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
    if tick() - RENDER.LastTabListRefresh >= 0.35 then
        RENDER.LastTabListRefresh = tick()

        if currentTabIndex == 7 then
            RENDER.TpRefreshStep = (RENDER.TpRefreshStep % 4) + 1
            if RENDER.TpRefreshStep == 1 then
                local p = TP.FavListFrame.CanvasPosition
                task.spawn(function()
                    pcall(RefreshFavorites)
                    pcall(function() TP.FavListFrame.CanvasPosition = p end)
                end)
            elseif RENDER.TpRefreshStep == 2 then
                local p = TP.SavedListFrame.CanvasPosition
                task.spawn(function()
                    pcall(RefreshSavedLocations)
                    pcall(function() TP.SavedListFrame.CanvasPosition = p end)
                end)
            elseif RENDER.TpRefreshStep == 3 then
                local p = TP.PlayerListFrame.CanvasPosition
                task.spawn(function()
                    pcall(RefreshPlayerList)
                    pcall(function() TP.PlayerListFrame.CanvasPosition = p end)
                end)
            elseif RENDER.TpRefreshStep == 4 then
                local p = TP.NpcListFrame.CanvasPosition
                task.spawn(function()
                    pcall(refreshNpcCache)
                    pcall(RefreshNPCList)
                    pcall(function() TP.NpcListFrame.CanvasPosition = p end)
                end)
            end
        elseif currentTabIndex == 8 then
            task.spawn(function()
                pcall(RefreshSpectateIfChanged)
            end)
        end
    end
    end 
    if RENDER.FrameCounter % 2 == 0 then
        Trail.Update()
    end

    if RENDER.FrameCounter % 60 == 0 then
        if Settings.ESP_Enabled then
            if not ESPSelfCheck.player.armed then
                ESPSelfCheck.player.armed = true
                ESPSelfCheck.player.drew = false
                ESPSelfCheck.player.armedAt = tick()
            elseif tick() - ESPSelfCheck.player.armedAt >= ESPSelfCheck.graceTime then
                if not ESPSelfCheck.player.drew then
                    local anyEnemy = false
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer and IsEnemy(p) then
                            local c = p.Character
                            if c and c:FindFirstChildOfClass("Humanoid") and c.Humanoid.Health > 0 then
                                anyEnemy = true break
                            end
                        end
                    end
                    if anyEnemy and (tick() - ESPSelfCheck.player.lastWarn) > ESPSelfCheck.cooldown then
                        ESPSelfCheck.player.lastWarn = tick()
                        if not DrawingAvailable then
                            Notify("error", "ESP", "ESP включён, но Drawing недоступен в экзекуторе", 8)
                        elseif not Camera then
                            Notify("error", "ESP", "ESP включён, но камера недоступна", 8)
                        else
                            Notify("error", "ESP", "ESP включён, враги есть, но ничего не рисуется", 8)
                        end
                        CritError("ESP_SelfCheck", "player ESP not drawing")
                    end
                end
                ESPSelfCheck.player.armed = false
            end
        else
            ESPSelfCheck.player.armed = false
        end

        if Settings.ESP_NPCs then
            if not ESPSelfCheck.npc.armed then
                ESPSelfCheck.npc.armed = true
                ESPSelfCheck.npc.drew = false
                ESPSelfCheck.npc.armedAt = tick()
            elseif tick() - ESPSelfCheck.npc.armedAt >= ESPSelfCheck.graceTime then
                if not ESPSelfCheck.npc.drew then
                    local anyNpc = false
                    for _, obj in ipairs(workspace:GetChildren()) do
                        if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
                            local h = obj:FindFirstChildOfClass("Humanoid")
                            if h and h.Health > 0 then anyNpc = true break end
                        end
                    end
                    if anyNpc and (tick() - ESPSelfCheck.npc.lastWarn) > ESPSelfCheck.cooldown then
                        ESPSelfCheck.npc.lastWarn = tick()
                        if not DrawingAvailable then
                            Notify("error", "NPC ESP", "NPC ESP включён, но Drawing недоступен", 8)
                        else
                            Notify("error", "NPC ESP", "NPC ESP включён, NPC есть, но ничего не рисуется", 8)
                        end
                        CritError("NPCESP_SelfCheck", "npc ESP not drawing")
                    end
                end
                ESPSelfCheck.npc.armed = false
            end
        else
            ESPSelfCheck.npc.armed = false
        end
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
        SmartAim.CharCache = {}
        SmartAim.VisCache  = {}
    end
end)

 -- обработка игрока
LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid", 5)
    task.wait(0.3)
    UpdateSpeed()
    UpdateFlight()
    if Settings.Noclip_Enabled then UpdateNoclip() end
    if Settings.AntiAFK_Enabled then UpdateAntiAFK() end
    if Settings.AutoClicker_Enabled then SetAutoClickerEnabled(true) end
    if Settings.Freeze_Enabled then UpdateFreeze() end
    -- переприменяем ещё раз через секунду, чтобы перебить игровой сброс
    task.delay(1.0, function()
        if char == LocalPlayer.Character then
            UpdateSpeed()
            UpdateFlight()
        end
    end)
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
        rayParams.FilterType = RAYCAST_EXCLUDE
        rayParams.FilterDescendantsInstances = {char}
    end
    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * Settings.ClickTP_MaxDistance, rayParams)
    if not result then
        Notify("error", "Click TP", "Не найдена точка для телепорта")
        return
    end
    local oldPos = root.Position
    local ok = pcall(function() root.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0)) end)
    if not ok then
        Notify("error", "Click TP", "Ошибка перемещения")
        return
    end
    task.delay(0.15, function()
        local c = LocalPlayer.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if not r then return end
        if (r.Position - oldPos).Magnitude < 1 then
            Notify("error", "Click TP", "Перемещение заблокировано (карта/античит)")
        end
    end)
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
            elseif action == "Trigger" then
                Settings.Trigger_Enabled = not Settings.Trigger_Enabled
                if ToggleRefs.Trigger then ToggleRefs.Trigger.SetState(Settings.Trigger_Enabled) end
            elseif action == "AutoClicker" then
                SetAutoClickerEnabled(not Settings.AutoClicker_Enabled)
            elseif action == "ThirdPerson" then
                ToggleThirdPerson()
            elseif action == "CursorUnlock" then
                SetCursorUnlocked(not Settings.CursorUnlock_Enabled)
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

    pcall(function()
        local CAS = game:GetService("ContextActionService")
        CAS:UnbindAction("BobrEscapeToggle")
    end)

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
        SetAutoClickerEnabled(false, true)
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

    if Settings.CursorUnlock_Enabled then
        SetCursorUnlocked(false)
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

    if RENDER.FOVCircle then pcall(function() RENDER.FOVCircle:Remove() end); RENDER.FOVCircle = nil end
    if triggerDot then pcall(function() triggerDot:Remove() end); triggerDot = nil end
    if Crosshair then
        for _, l in ipairs(Crosshair.Main or {}) do pcall(function() l:Remove() end) end
        for _, l in ipairs(Crosshair.Outline or {}) do pcall(function() l:Remove() end) end
        if Crosshair.DotFill then pcall(function() Crosshair.DotFill:Remove() end) end
        if Crosshair.DotOutline then pcall(function() Crosshair.DotOutline:Remove() end) end
        Crosshair = nil
    end
    if RENDER.FPS then pcall(function() RENDER.FPS:Remove() end); RENDER.FPS = nil end
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
    if LOAD.Gui then
        LOAD.Gui:Destroy()
        LOAD.Gui = nil
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
    getgenv()._BC_ERR_LOG = nil

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
        LOAD.BarFill.Size = UDim2.new(i/100, 0, 1, 0)
        LOAD.Percent.Text = i .. "%"
        task.wait(step)
    end
    TweenService:Create(LOAD.Frame, TweenInfo.new(0.5), {
        BackgroundTransparency = 1,
        Position = LOAD.Frame.Position + UDim2.new(0, 0, 0, 50)
    }):Play()
    task.wait(0.5)
    LOAD.Gui:Destroy()
    ShowMainMenu()
    print(Locales.t("[bobrcheats v23.3] Меню загружено."))
end)

local ContextActionService = game:GetService("ContextActionService")

local function BobrEscape(actionName, inputState, inputObject)
    if inputState ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end

    SetCursorUnlocked(not Settings.CursorUnlock_Enabled)

    if Settings.CursorUnlock_Enabled then
        if MenuLoaded and ScreenGui and not ScreenGui.Enabled then
            ShowMainMenu()
        end
    end

    return Enum.ContextActionResult.Sink
end

pcall(function()
    ContextActionService:BindActionAtPriority(
        "BobrEscapeToggle",
        BobrEscape,
        false,
        4000,
        Enum.KeyCode.Escape
    )
end)

task.spawn(function()
    task.wait(6.5)
    FlushCritErrors()
end)
FeatureHealth.Start()

print(Locales.t("[bobrcheats v23.3] Загрузка..."))