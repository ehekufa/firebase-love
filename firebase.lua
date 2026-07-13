local firebase = {}

local config = {
    apiKey = nil,
    dbURL = nil,
    authToken = nil,
    timeout = 5,
    verifySSL = false,
}

local activeListeners = {}

local function hasHttps()
    local ok, _ = pcall(require, "ssl.https")
    return ok
end

local function hasSocket()
    local ok, _ = pcall(require, "socket.http")
    return ok
end

local function encodeJSON(data)
    if type(data) == "string" then
        return '"' .. data:gsub('"', '\\"') .. '"'
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "boolean" then
        return data and "true" or "false"
    elseif type(data) == "table" then
        local parts = {}
        for k, v in pairs(data) do
            local key = type(k) == "string" and '"' .. k .. '"' or tostring(k)
            table.insert(parts, key .. ":" .. encodeJSON(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return "null"
    end
end

local function decodeJSON(json)
    local ok, data = pcall(love.data.decode, "string", "json", json)
    if ok then return data end
    return nil
end

local function request(method, path, data, callback)
    if not config.dbURL then
        error("firebase: not initialized")
    end
    
    local url = config.dbURL .. "/" .. path .. ".json"
    if config.authToken then
        url = url .. "?auth=" .. config.authToken
    end
    
    local body = data and encodeJSON(data) or nil
    
    if hasHttps() then
        local https = require("ssl.https")
        local ltn12 = require("ltn12")
        local response_body = {}
        
        local options = {
            url = url,
            method = method,
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(body and #body or 0)
            },
            source = body and ltn12.source.string(body) or nil,
            sink = ltn12.sink.table(response_body),
            timeout = config.timeout,
            verify = config.verifySSL,
        }
        
        local res, code, headers = https.request(options)
        local response = table.concat(response_body)
        
        if code and code >= 200 and code < 300 then
            local decoded = decodeJSON(response)
            if callback then callback(true, decoded or response) end
        else
            if callback then callback(false, "HTTP Error: " .. tostring(code)) end
        end
        return
    end
    
    if hasSocket() then
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local response_body = {}
        
        local options = {
            url = url,
            method = method,
            headers = {
                ["Content-Type"] = "application/json",
            },
            source = body and ltn12.source.string(body) or nil,
            sink = ltn12.sink.table(response_body),
            timeout = config.timeout,
        }
        
        local res, code, headers = http.request(options)
        local response = table.concat(response_body)
        
        if code and code >= 200 and code < 300 then
            local decoded = decodeJSON(response)
            if callback then callback(true, decoded or response) end
        else
            if callback then callback(false, "HTTP Error: " .. tostring(code)) end
        end
        return
    end
    
    error("firebase: No HTTP module available")
end

function firebase.init(options)
    if not options.apiKey then error("firebase.init: apiKey required") end
    if not options.dbURL then error("firebase.init: dbURL required") end
    config.apiKey = options.apiKey
    config.dbURL = options.dbURL
    config.timeout = options.timeout or 5
    config.verifySSL = options.verifySSL or false
end

function firebase.authAnonymous(callback)
    if not config.apiKey then
        error("firebase.authAnonymous: Call firebase.init() first")
    end
    
    local authUrl = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" .. config.apiKey
    local body = '{"returnSecureToken":true}'
    
    if hasHttps() then
        local https = require("ssl.https")
        local ltn12 = require("ltn12")
        local response_body = {}
        
        local res, code = https.request{
            url = authUrl,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#body)
            },
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(response_body),
            timeout = config.timeout,
        }
        
        local response = table.concat(response_body)
        if code == 200 then
            local data = decodeJSON(response)
            if data and data.idToken then
                config.authToken = data.idToken
                if callback then callback(true, data) end
            else
                if callback then callback(false, "Missing idToken") end
            end
        else
            if callback then callback(false, "Auth failed: " .. tostring(code)) end
        end
        return
    end
    
    if hasSocket() then
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local response_body = {}
        
        local res, code = http.request{
            url = authUrl,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
            },
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(response_body),
            timeout = config.timeout,
        }
        
        local response = table.concat(response_body)
        if code == 200 then
            local data = decodeJSON(response)
            if data and data.idToken then
                config.authToken = data.idToken
                if callback then callback(true, data) end
            else
                if callback then callback(false, "Missing idToken") end
            end
        else
            if callback then callback(false, "Auth failed: " .. tostring(code)) end
        end
        return
    end
    
    error("firebase.authAnonymous: No HTTP module available")
end

function firebase.setToken(token)
    config.authToken = token
end

function firebase.getToken()
    return config.authToken
end

function firebase.get(path, callback)
    request("GET", path, nil, callback)
end

function firebase.put(path, data, callback)
    request("PUT", path, data, callback)
end

function firebase.patch(path, data, callback)
    request("PATCH", path, data, callback)
end

function firebase.post(path, data, callback)
    request("POST", path, data, callback)
end

function firebase.delete(path, callback)
    request("DELETE", path, nil, callback)
end

function firebase.listen(path, callback)
    if activeListeners[path] then
        activeListeners[path].connection:close()
        activeListeners[path] = nil
    end

    if not config.authToken then
        error("firebase.listen: Not authenticated")
    end

    local url = config.dbURL .. "/" .. path .. ".json?auth=" .. config.authToken
    local socket = require("socket")
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local req = {
        url = url,
        method = "GET",
        headers = {
            ["Accept"] = "text/event-stream",
        },
        sink = ltn12.sink.table({}),
        create = function()
            local sock = socket.tcp()
            sock:settimeout(0)
            return sock
        end,
    }

    local conn = http.request(req)
    if not conn then
        callback(false, "Failed to connect")
        return
    end

    activeListeners[path] = {
        callback = callback,
        connection = conn,
    }

    local function reader()
        while true do
            local chunk, err = conn:receive("*l")
            if err then
                firebase.listen(path, callback)
                break
            end
            if chunk and chunk ~= "" and chunk:match("^data: ") then
                local jsonData = chunk:sub(7)
                local ok, data = pcall(love.data.decode, "string", "json", jsonData)
                if ok and data then
                    callback(true, data)
                end
            end
        end
    end

    local co = coroutine.create(reader)
    activeListeners[path].coroutine = co
    coroutine.resume(co)
end

function firebase.unlisten(path)
    if activeListeners[path] then
        activeListeners[path].connection:close()
        activeListeners[path] = nil
    end
end

function firebase.update()
    for path, listener in pairs(activeListeners) do
        if listener.coroutine then
            local status = coroutine.status(listener.coroutine)
            if status == "suspended" then
                coroutine.resume(listener.coroutine)
            elseif status == "dead" then
                activeListeners[path] = nil
            end
        end
    end
end

function firebase.closeAll()
    for path, listener in pairs(activeListeners) do
        listener.connection:close()
    end
    activeListeners = {}
end

return firebase
