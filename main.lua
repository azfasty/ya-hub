--[[
    YA HUB - Key System Loader
    Compatible Lua 5.1 / bit32
--]]

local API_URL     = "https://api-ya-omega.vercel.app"
local HMAC_SECRET = "PUOFZQGESQF454SGER6G4E64GE4GGG"

local Rayfield    = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

-- ─── BIT32 COMPAT ─────────────────────────────────────────────────────────────
local band   = bit32 and bit32.band   or bit.band
local bxor   = bit32 and bit32.bxor   or bit.bxor
local bor    = bit32 and bit32.bor    or bit.bor
local bnot   = bit32 and bit32.bnot   or bit.bnot
local rshift = bit32 and bit32.rshift or bit.rshift
local lshift = bit32 and bit32.lshift or bit.lshift

local function rrotate(x, n)
    return bor(rshift(x, n), lshift(x, 32 - n))
end
local function u32(x)
    return band(x, 0xFFFFFFFF)
end

-- ─── SHA256 ───────────────────────────────────────────────────────────────────
local SHA256_K = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function sha256(msg)
    local h = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
    }
    local len = #msg
    msg = msg .. "\x80"
    while #msg % 64 ~= 56 do msg = msg .. "\x00" end
    local bits = len * 8
    msg = msg .. "\x00\x00\x00\x00" .. string.char(
        band(rshift(bits, 24), 0xFF),
        band(rshift(bits, 16), 0xFF),
        band(rshift(bits,  8), 0xFF),
        band(bits, 0xFF)
    )
    for i = 1, #msg, 64 do
        local w = {}
        for j = 0, 15 do
            local b1,b2,b3,b4 = string.byte(msg, i+j*4, i+j*4+3)
            w[j+1] = bor(lshift(b1,24), lshift(b2,16), lshift(b3,8), b4)
        end
        for j = 17, 64 do
            local s0 = bxor(rrotate(w[j-15],7), rrotate(w[j-15],18), rshift(w[j-15],3))
            local s1 = bxor(rrotate(w[j-2],17), rrotate(w[j-2],19),  rshift(w[j-2],10))
            w[j] = u32(w[j-16] + s0 + w[j-7] + s1)
        end
        local a,b,c,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
        for j = 1, 64 do
            local S1  = bxor(rrotate(e,6), rrotate(e,11), rrotate(e,25))
            local ch  = bxor(band(e,f), band(bnot(e),g))
            local tmp1 = u32(hh + S1 + ch + SHA256_K[j] + w[j])
            local S0  = bxor(rrotate(a,2), rrotate(a,13), rrotate(a,22))
            local maj = bxor(band(a,b), band(a,c), band(b,c))
            local tmp2 = u32(S0 + maj)
            hh=g; g=f; f=e; e=u32(d+tmp1)
            d=c;  c=b; b=a; a=u32(tmp1+tmp2)
        end
        h[1]=u32(h[1]+a); h[2]=u32(h[2]+b); h[3]=u32(h[3]+c); h[4]=u32(h[4]+d)
        h[5]=u32(h[5]+e); h[6]=u32(h[6]+f); h[7]=u32(h[7]+g); h[8]=u32(h[8]+hh)
    end
    local out = ""
    for _,v in ipairs(h) do out = out .. string.format("%08x", v) end
    return out
end

local function hmacSha256(key, msg)
    local BLOCK = 64
    if #key > BLOCK then key = sha256(key) end
    local ipad, opad = "", ""
    for i = 1, BLOCK do
        local k = i <= #key and string.byte(key, i) or 0
        ipad = ipad .. string.char(bxor(k, 0x36))
        opad = opad .. string.char(bxor(k, 0x5C))
    end
    return sha256(opad .. sha256(ipad .. msg))
end

-- ─── SIGN PAYLOAD ─────────────────────────────────────────────────────────────
-- Reproduit exactement json.dumps(payload, sort_keys=True) de Python
-- Ordre alphabétique des clés : game_id, hwid, key
local function signPayload(key_str, hwid, game_id)
    local raw = '{"game_id":"' .. tostring(game_id) .. '","hwid":"' .. tostring(hwid) .. '","key":"' .. tostring(key_str) .. '"}'
    return hmacSha256(HMAC_SECRET, raw)
end

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
    local sig    = signPayload(userKey, hwid, gameId)

    notifySuccess("Verification...", "Validation de ta cle en cours...")

    local data, err = httpPost("/validate", {
        key     = userKey,
        hwid    = hwid,
        game_id = gameId,
        sig     = sig,
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
    Theme                  = "DarkBlue",
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
