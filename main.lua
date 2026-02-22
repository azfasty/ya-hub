local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
   Name = "YA HUB - LOADER",
   Icon = 0,
   LoadingTitle = "YA HUB is loading...",
   LoadingSubtitle = "by Artemis & YouYou",
   ShowText = "YA",
   Theme = "DarkBlue",
   ToggleUIKeybind = "K",
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   ConfigurationSaving = {
      Enabled = true,
      FolderName = "YAHUB",
      FileName = "YAHUB"
   },
   Discord = {
      Enabled = true,
      Invite = "X28Ffjm3Yb",
      RememberJoins = true
   },
   KeySystem = false,
   KeySettings = {
      Title = "YA",
      Subtitle = "Key System",
      Note = "No method of obtaining the key is provided",
      FileName = "Key",
      SaveKey = true,
      GrabKeyFromSite = false,
      Key = {"Hello"}
   }
})

local Tab = Window:CreateTab("KEY SYSTEM", 4483362458)
local Section = Tab:CreateSection("KEY")
