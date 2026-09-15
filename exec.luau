local _ENV = (getgenv or getrenv or getfenv)()

local Port = 8765
local Url = `wss://glorious-engine-x5x9977wpqgx2p7p-{Port}.app.github.dev`

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Socket = _ENV.SOCKET or WebSocket.connect(Url)
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
            print("Remote Spy is loaded from server/src/Cobalt.lua")
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
