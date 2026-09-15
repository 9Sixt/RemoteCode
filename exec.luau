local _ENV = (getgenv or getrenv or getfenv)()

local Port = 8765
local Url = `wss://glorious-engine-x5x9977wpqgx2p7p-{Port}.app.github.dev`

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Socket = _ENV.SOCKET

if Socket then
    local SocketUsable = pcall(function()
        Socket:Send("--@client-check")
    end)

    if not SocketUsable then
        Socket = nil
        _ENV.SOCKET = nil
    end
end

Socket = Socket or WebSocket.connect(Url)
_ENV.SOCKET = Socket
local MetricsRunning = true
local FrameCount = 0

local FrameSignal = RunService.RenderStepped or RunService.Heartbeat
FrameSignal:Connect(function()
    FrameCount += 1
end)

local Module = {}

Module.Hooked = (function()
    local Hooked = {}

    if not isfunctionhooked(print) then
        Hooked.Original = hookfunction(print, function(...)
            local Args = {...}
            local Output = {}

            for i, Value in Args do
                Output[i] = tostring(Value)
            end

            pcall(function()
                Socket:Send(table.concat(Output, "\t"))
            end)

            return Hooked.Original(...)
        end)
    end

    if not isfunctionhooked(decompile) then
        Hooked.decompile = hookfunction(decompile, function(...)
            local Args = {...}
            local Target = Args[1]
            local Source = Hooked.decompile(...)
            local ScriptName = "Unknown"

            if typeof(Target) == "Instance" then
                ScriptName = Target.Name
            end

            pcall(function()
                Socket:Send("--@cf-decompiled|" .. ScriptName .. "\n" .. Source)
            end)

            return Source
        end)
    end

    return Hooked
end)()

Module.Commands = (function()
    local Commands = {}

    local Functions = {
        ["$tags"] = function()
            local Tags = CollectionService:GetAllTags()
            local Result = table.concat(Tags, "\n")

            print("Found " .. #Tags .. " tags!")
            print(Result)

            pcall(function()
                Socket:Send("--@write-note\n" .. Result)
            end)
        end,

        ["$iy"] = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
            print("Execute Infinite Yield!")
        end,

        ["$dex"] = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"))()
            print("Execute Moondex!")
        end,

        ["$rspy"] = function()
            loadstring(game:HttpGet("https://gitlab.com/upio/cobalt/-/releases/permalink/latest/downloads/Cobalt.luau"))()
            print("Execute Remote Spy!")
        end,

        ["$rj"] = function()
            local TeleportService = game:GetService("TeleportService")
            local LocalPlayer = game:GetService("Players").LocalPlayer

            local Success, Error = pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)

            if not Success then
                warn("Rejoin failed: " .. tostring(Error))
            end
        end,

        ["$test"] = function()
            print("Test Client Connect Success :", tostring(workspace:GetServerTimeNow()))
        end,

        ["$deb"] = function()
            if type(keypress) ~= "function" then
                return warn("[deb] keypress is not available in this environment")
            end

            keypress(0x78)
            task.wait(0.1)

            if type(keyrelease) == "function" then
                keyrelease(0x78)
            end
        end,
    }

    function Commands:IsCommand(Message)
        return Functions[Message] ~= nil
    end

    function Commands:Exec(Message)
        local Callback = Functions[Message]

        if not Callback then
            return false
        end

        return Callback()
    end

    return Commands
end)()

Module.Socket = (function()
    local Functions = {
        ["@exec"] = function(Source)
            local Code = Source:gsub("^@exec%s*", "")
            local CompileSuccess, Chunk = pcall(loadstring, Code)

            if not CompileSuccess then
                return print("Compile Error: " .. tostring(Chunk))
            end

            local ExecuteSuccess, Result = pcall(Chunk)

            if ExecuteSuccess then
                print("Execute Success!")

                if Result ~= nil then
                    print("Result:", Result)
                end
            else
                print("Execute Error: " .. tostring(Result))
            end
        end
    }

    Socket.OnMessage:Connect(function(Source)
        if type(Source) ~= "string" then
            return
        end

        if Module.Commands:IsCommand(Source) then
            return Module.Commands:Exec(Source)
        end

        local Command = Source:match("^(@[%w_]+)")

        if Command then
            local Callback = Functions[Command]

            if Callback then
                return Callback(Source)
            end
        end
    end)

    Socket.OnClose:Connect(function()
        MetricsRunning = false
        if _ENV.SOCKET == Socket then
            _ENV.SOCKET = nil
        end
        print("Server Close")
    end)

end)()

task.spawn(function()
    while MetricsRunning do
        task.wait(1)

        local Ping = 0
        pcall(function()
            local PingStat = Stats.Network.ServerStatsItem["Data Ping"]
            local PingText = PingStat:GetValueString()
            Ping = tonumber(string.match(PingText, "%d+")) or 0
        end)

        local FPS = FrameCount
        FrameCount = 0

        local Sent, Error = pcall(function()
            Socket:Send(string.format(
                '--@metrics|{"ping":%d,"fps":%d}',
                Ping,
                FPS
            ))
        end)

        if not Sent then
            warn("[Metrics] Send failed: " .. tostring(Error))
        end
    end
end)

warn("[Metrics] Telemetry started")
print("# Client Start :", (gethwid and gethwid()) or "N/A")

task.spawn(function()
    local Success, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)

    if not Success then
        warn("[Notes UI] Failed to load WindUI: " .. tostring(WindUI))
        return
    end

    local NoteContent = ""
    local Window = WindUI:CreateWindow({
        Title = "GoodNotes",
        Icon = "solar:notes-bold",
        HideSearchBar = true,
        OpenButton = {
            Title = "Toggle Notes",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
        },
    })
    Window:SetToggleKey(Enum.KeyCode.RightShift)

    local NotesTab = Window:Tab({
        Title = "Notes",
        Icon = "solar:notes-bold",
    })

    NotesTab:Input({
        Title = "Client note",
        Desc = "Write a note and send it to the server",
        Type = "Textarea",
        Placeholder = "Enter note...",
        Callback = function(Value)
            NoteContent = tostring(Value or "")
        end,
    })

    NotesTab:Space()

    NotesTab:Button({
        Title = "Send Note",
        Icon = "solar:plain-2-bold",
        Callback = function()
            local Content = NoteContent:gsub("^%s+", ""):gsub("%s+$", "")
            if Content == "" then
                WindUI:Notify({
                    Title = "Note not sent",
                    Content = "Write something first.",
                })
                return
            end

            local Sent, Error = pcall(function()
                Socket:Send("--@write-note\n" .. Content)
            end)

            WindUI:Notify({
                Title = Sent and "Note sent" or "Note failed",
                Content = Sent and "Saved to the server notes folder." or tostring(Error),
            })
        end,
    })
end)
