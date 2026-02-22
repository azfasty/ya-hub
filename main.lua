--[[
    YA HUB - Key System Loader
    Compatible Lua 5.1 / bit32
--]]

local API_URL     = "https://api-ya-omega.vercel.app"

local Rayfield    = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

-- ─── UTILS ────────────────────────────────────────────────────────────────────
local function getHWID()
    local ok, hwid = pcall(function()
        return tostring(game:GetService("RbxAnalyticsService"):GetClientId())
    end)
    if ok and hwid and hwid ~= "" then return hwid end
    return tostring(Players.LocalPlayer.UserId)
end

local function getGameID()
    return tostring(game.PlaceId)
end

-- ─── HTTP POST ────────────────────────────────────────────────────────────────
local function httpPost(endpoint, payload)
    local body = HttpService:JSONEncode(payload)
    local url  = API_URL .. endpoint

    local ok, result = pcall(function()
        return request({
            Url     = url,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = body,
        })
    end)

    if not ok then
        ok, result = pcall(function()
            return http.request({
                Url     = url,
                Method  = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body    = body,
            })
        end)
    end

    if not ok then
        ok, result = pcall(function()
            return HttpService:RequestAsync({
                Url     = url,
                Method  = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body    = body,
            })
        end)
    end

    if not ok then return nil, "Erreur reseau : " .. tostring(result) end

    local status = result.StatusCode or result.status_code or result.statusCode or 0
    if status ~= 200 then
        local msg = "Erreur serveur " .. tostring(status)
        local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, result.Body or result.body or "")
        if ok2 and decoded and decoded.detail then msg = decoded.detail end
        return nil, msg
    end

    local ok3, data = pcall(HttpService.JSONDecode, HttpService, result.Body or result.body or "")
    if not ok3 then return nil, "Reponse invalide" end
    return data, nil
end

-- ─── NOTIFICATIONS ────────────────────────────────────────────────────────────
local function notifyError(title, content)
    Rayfield:Notify({ Title = title, Content = content, Duration = 7, Image = 4483362458 })
end
local function notifySuccess(title, content)
    Rayfield:Notify({ Title = title, Content = content, Duration = 5, Image = 4483362458 })
end

-- ─── LOAD GAME SCRIPT ─────────────────────────────────────────────────────────
local function loadGameScript(url)
    local ok, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)
    if not ok then
        notifyError("Erreur Script", tostring(err))
    end
end

-- ─── VALIDATE AND LOAD ────────────────────────────────────────────────────────
local function validateAndLoad(userKey)
    local hwid   = getHWID()
    local gameId = getGameID()
    notifySuccess("Verification...", "Validation de ta cle en cours...")

    local data, err = httpPost("/validate", {
        key     = userKey,
        hwid    = hwid,
        game_id = gameId,
    })

    if not data then
        notifyError("Erreur reseau", err or "Impossible de contacter le serveur")
        return
    end

    if not data.valid then
        local reasons = {
            KEY_NOT_FOUND = "Cle introuvable.",
            KEY_REVOKED   = "Cette cle a ete revoquee.",
            KEY_EXPIRED   = "Cette cle a expire.",
            HWID_MISMATCH = "Cle liee a un autre appareil. Contacte le support.",
        }
        notifyError("Cle invalide", reasons[data.reason] or tostring(data.reason))
        return
    end

    notifySuccess("Cle valide !", "Chargement du script...")

    local scriptData, err2 = httpPost("/get_script", {
        jwt_token = data.jwt,
        hwid      = hwid,
        game_id   = gameId,
    })

    if not scriptData then
        notifyError("Erreur", err2 or "Impossible de recuperer le script")
        return
    end

    if not scriptData.url then
        notifyError("Jeu non supporte", "Aucun script pour ce jeu.")
        return
    end

    notifySuccess("Chargement...", "Injection en cours !")
    loadGameScript(scriptData.url)
end

-- ─── UI RAYFIELD ──────────────────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name                   = "YA HUB - LOADER",
    Icon                   = 0,
    LoadingTitle           = "YA HUB is loading...",
    LoadingSubtitle        = "by Artemis & YouYou",
    ShowText               = "YA",
    Theme                  = "AmberGlow",
    ToggleUIKeybind        = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,
    ConfigurationSaving    = {
        Enabled    = true,
        FolderName = "YAHUB",
        FileName   = "YAHUB",
    },
    Discord = {
        Enabled       = true,
        Invite        = "X28Ffjm3Yb",
        RememberJoins = true,
    },
    KeySystem   = false,
    KeySettings = {
        Title           = "YA",
        Subtitle        = "Key System",
        Note            = "Rejoins notre Discord pour obtenir une cle",
        FileName        = "Key",
        SaveKey         = true,
        GrabKeyFromSite = false,
        Key             = {"Hello"},
    },
})

local Tab = Window:CreateTab("KEY SYSTEM", 4483362458)

Tab:CreateSection("Activation")

local savedKey = ""

Tab:CreateInput({
    Name                     = "Entrez votre cle",
    CurrentValue             = "",
    PlaceholderText          = "LIFETIME-XXXX / MONTH-XXXX / WEEK-XXXX / 8H-XXXX",
    RemoveTextAfterFocusLost = false,
    Flag                     = "KeyInput",
    Callback                 = function(Text)
        savedKey = Text
    end,
})

Tab:CreateButton({
    Name     = "Valider la cle",
    Callback = function()
        if savedKey == "" then
            notifyError("Cle vide", "Entre ta cle avant de valider.")
            return
        end
        validateAndLoad(savedKey)
    end,
})

Tab:CreateSection("Informations")
Tab:CreateLabel("HWID : " .. getHWID():sub(1, 24) .. "...", 4483362458)
Tab:CreateLabel("Game ID : " .. getGameID(), 4483362458)

Rayfield:LoadConfiguration()
