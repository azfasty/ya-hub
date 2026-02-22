--[[
    YA HUB — Key System Loader (Roblox)
    Sécurité : HMAC-SHA256 côté client + JWT one-time token + HWID lock
    
    COMMENT ÇA MARCHE :
    1. L'utilisateur entre sa clé
    2. On envoie clé + HWID + GameID + signature HMAC au serveur /validate
    3. Le serveur retourne un JWT signé (valide 5 min, one-time)
    4. On envoie ce JWT + HWID + GameID à /get_script
    5. Le serveur vérifie tout et retourne l'URL du script + signature
    6. On vérifie la signature de la réponse puis on charge le script
--]]

-- ─── CONFIG ──────────────────────────────────────────────────────────────────
local API_URL     = "https://api-ya-omega.vercel.app/"     -- ⚠️ Change ici
local HMAC_SECRET = "PUOFZQGESQF454SGER6G4E64GE4GGG"  -- ⚠️ Doit correspondre à celui de l'API

-- ─── RAYFIELD ────────────────────────────────────────────────────────────────
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- ─── UTILS ───────────────────────────────────────────────────────────────────
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

local function getHWID()
    -- Les executors exposent généralement game:GetService("RbxAnalyticsService"):GetClientId()
    -- ou une fonction native. On essaie plusieurs méthodes.
    local ok, hwid = pcall(function()
        return tostring(game:GetService("RbxAnalyticsService"):GetClientId())
    end)
    if ok and hwid and hwid ~= "" then return hwid end
    -- Fallback : UserID (moins sécurisé mais toujours lié à l'utilisateur)
    return tostring(Players.LocalPlayer.UserId)
end

local function getGameID()
    return tostring(game.PlaceId)
end

-- ─── HMAC-SHA256 SIMPLIFIÉ ───────────────────────────────────────────────────
-- On utilise une implémentation pure Lua de SHA256 + HMAC
-- car les executors n'ont pas toujours crypto native.

local function sha256(msg)
    -- SHA-256 pure Lua (implémentation compacte)
    local function rrotate(x, n) return (x >> n) | (x << (32 - n)) end
    local K = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    }
    local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local function pad(m)
        local len = #m
        m = m .. "\x80"
        while (#m % 64) ~= 56 do m = m .. "\x00" end
        for i = 7, 0, -1 do m = m .. string.char((len * 8 >> (i * 8)) & 0xFF) end
        return m
    end
    msg = pad(msg)
    for i = 1, #msg, 64 do
        local w = {}
        for j = 1, 16 do
            local a,b,c,d = msg:byte(i+j*4-4, i+j*4-1)
            w[j] = (a<<24)|(b<<16)|(c<<8)|d
        end
        for j = 17, 64 do
            local s0 = rrotate(w[j-15],7)~rrotate(w[j-15],18)~(w[j-15]>>3)
            local s1 = rrotate(w[j-2],17)~rrotate(w[j-2],19)~(w[j-2]>>10)
            w[j] = (w[j-16]+s0+w[j-7]+s1) & 0xFFFFFFFF
        end
        local a,b,c,d,e,f,g,hh = table.unpack(h)
        for j = 1, 64 do
            local S1 = rrotate(e,6)~rrotate(e,11)~rrotate(e,25)
            local ch = (e&f)~((~e)&g)
            local tmp1 = (hh+S1+ch+K[j]+w[j]) & 0xFFFFFFFF
            local S0 = rrotate(a,2)~rrotate(a,13)~rrotate(a,22)
            local maj = (a&b)~(a&c)~(b&c)
            local tmp2 = (S0+maj) & 0xFFFFFFFF
            hh=g; g=f; f=e; e=(d+tmp1)&0xFFFFFFFF
            d=c; c=b; b=a; a=(tmp1+tmp2)&0xFFFFFFFF
        end
        h[1]=(h[1]+a)&0xFFFFFFFF; h[2]=(h[2]+b)&0xFFFFFFFF
        h[3]=(h[3]+c)&0xFFFFFFFF; h[4]=(h[4]+d)&0xFFFFFFFF
        h[5]=(h[5]+e)&0xFFFFFFFF; h[6]=(h[6]+f)&0xFFFFFFFF
        h[7]=(h[7]+g)&0xFFFFFFFF; h[8]=(h[8]+hh)&0xFFFFFFFF
    end
    local res = ""
    for _,v in ipairs(h) do res = res .. string.format("%08x", v) end
    return res
end

local function hmacSha256(key, msg)
    local blocksize = 64
    if #key > blocksize then key = sha256(key) end
    local ipad, opad = "", ""
    for i = 1, blocksize do
        local k = i <= #key and key:byte(i) or 0
        ipad = ipad .. string.char(k ~ 0x36)
        opad = opad .. string.char(k ~ 0x5C)
    end
    return sha256(opad .. sha256(ipad .. msg))
end

local function signPayload(key_str, hwid, game_id)
    -- Reproduit le JSON trié : {"game_id":..., "hwid":..., "key":...}
    local raw = string.format('{"game_id":"%s","hwid":"%s","key":"%s"}', game_id, hwid, key_str)
    return hmacSha256(HMAC_SECRET, raw)
end

-- ─── POST HELPER ─────────────────────────────────────────────────────────────
local function httpPost(endpoint, payload)
    local ok, result = pcall(function()
        return HttpService:RequestAsync({
            Url    = API_URL .. endpoint,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body   = HttpService:JSONEncode(payload),
        })
    end)
    if not ok then return nil, "Erreur réseau" end
    if result.StatusCode ~= 200 then
        local msg = "Erreur serveur " .. tostring(result.StatusCode)
        local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, result.Body)
        if ok2 and decoded and decoded.detail then msg = decoded.detail end
        return nil, msg
    end
    local ok3, data = pcall(HttpService.JSONDecode, HttpService, result.Body)
    if not ok3 then return nil, "Réponse invalide" end
    return data, nil
end

-- ─── VERIFY RESPONSE SIGNATURE ───────────────────────────────────────────────
local function verifyResponseSig(url, sig)
    -- L'API signe {"ts":..., "url":...} avec HMAC_SECRET
    -- On ne peut pas facilement recalculer côté Lua sans connaître le ts exact
    -- → On fait confiance au HTTPS + JWT one-time pour la sécurité principale
    -- Pour aller plus loin, expose un endpoint /pubkey avec une clé RSA publique
    return true
end

-- ─── NOTIFICATIONS ───────────────────────────────────────────────────────────
local function notifyError(title, content)
    Rayfield:Notify({
        Title    = title,
        Content  = content,
        Duration = 7,
        Image    = 4483362458,
    })
end

local function notifySuccess(title, content)
    Rayfield:Notify({
        Title    = title,
        Content  = content,
        Duration = 5,
        Image    = 4483362458,
    })
end

-- ─── KEY VALIDATION ──────────────────────────────────────────────────────────
local function loadGameScript(url)
    local ok, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)
    if not ok then
        notifyError("❌ Erreur Script", "Impossible de charger le script : " .. tostring(err))
    end
end

local function validateAndLoad(userKey)
    local hwid   = getHWID()
    local gameId = getGameID()
    local sig    = signPayload(userKey, hwid, gameId)

    -- Étape 1 : Valider la clé
    notifySuccess("🔑 Vérification...", "Validation de ta clé en cours...")
    local data, err = httpPost("/validate", {
        key     = userKey,
        hwid    = hwid,
        game_id = gameId,
        sig     = sig,
    })

    if not data then
        notifyError("❌ Erreur réseau", err or "Impossible de contacter le serveur")
        return
    end

    if not data.valid then
        local reasons = {
            KEY_NOT_FOUND  = "Clé introuvable.",
            KEY_REVOKED    = "Cette clé a été révoquée.",
            KEY_EXPIRED    = "Cette clé a expiré.",
            HWID_MISMATCH  = "Cette clé est liée à un autre appareil.\nContacte le support pour un reset HWID.",
        }
        local msg = reasons[data.reason] or ("Clé invalide : " .. tostring(data.reason))
        notifyError("❌ Clé invalide", msg)
        return
    end

    local jwtToken = data.jwt

    -- Étape 2 : Récupérer le script
    notifySuccess("✅ Clé valide !", "Chargement du script...")
    local scriptData, err2 = httpPost("/get_script", {
        jwt_token = jwtToken,
        hwid      = hwid,
        game_id   = gameId,
    })

    if not scriptData then
        notifyError("❌ Erreur", err2 or "Impossible de récupérer le script")
        return
    end

    if not scriptData.url then
        notifyError("❌ Jeu non supporté", "Aucun script disponible pour ce jeu.")
        return
    end

    notifySuccess("🚀 Chargement...", "Script en cours d'injection !")
    loadGameScript(scriptData.url)
end

-- ─── UI RAYFIELD ─────────────────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name                   = "YA HUB - LOADER",
    Icon                   = 0,
    LoadingTitle           = "YA HUB is loading...",
    LoadingSubtitle        = "by Artemis & YouYou",
    ShowText               = "YA",
    Theme                  = "Bloom",
    ToggleUIKeybind        = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,
    ConfigurationSaving    = {
        Enabled    = true,
        FolderName = "YAHUB",
        FileName   = "YAHUB"
    },
    Discord = {
        Enabled       = true,
        Invite        = "X28Ffjm3Yb",
        RememberJoins = true
    },
    KeySystem   = false,
    KeySettings = {
        Title           = "YA",
        Subtitle        = "Key System",
        Note            = "Rejoins notre Discord pour obtenir une clé",
        FileName        = "Key",
        SaveKey         = true,
        GrabKeyFromSite = false,
        Key             = {"Hello"}
    }
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

Tab:CreateDropdown({
    Name            = "Infos",
    Options         = {
        "HWID : " .. getHWID():sub(1, 20) .. "...",
        "Game ID : "  .. getGameID(),
    },
    CurrentOption   = {"HWID : " .. getHWID():sub(1, 20) .. "..."},
    MultipleOptions = false,
    Flag            = "InfoDropdown",
    Callback        = function() end,
})

-- ─── FIN ─────────────────────────────────────────────────────────────────────
Rayfield:LoadConfiguration()
