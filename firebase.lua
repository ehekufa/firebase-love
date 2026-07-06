local firebase = {}

local config = {
    apiKey = nil,
    dbURL = nil,
    authToken = nil,
    timeout = 3,
    verifySSL = false,
}

local function hasHttps()
    local ok, _ = pcall(require, "https")
    return ok
end

local function request(method, path, data, callback)
    if not config.dbURL then
        error("firebase: not initialized")
    end
    local url = config.dbURL .. "/" .. path .. ".json"
    if config.authToken then
        url = url .. "?auth=" .. config.authToken
    end
    local options = {
        method = method,
        headers = { ["Content-Type"] = "application/json" },
        timeout = config.timeout,
        verify = config.verifySSL,
    }
    if data then
        options.data = data
    end
    local ok, code, body
    if hasHttps() then
        local https = require("https")
        ok, code, body = pcall(https.request, url, options)
    else
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local response = {}
        local res, code, headers = http.request {
            url = url,
            method = method,
            headers = options.headers,
            source = options.data and ltn12.source.string(options.data) or nil,
            sink = ltn12.sink.table(response),
            timeout = options.timeout,
        }
        if code and code >= 200 and code < 300 then
            ok, code, body = true, code, table.concat(response)
        else
            ok, code, body = false, code, "HTTP error"
        end
    end
    if ok and code and code >= 200 and code < 300 then
        if callback then callback(true, body) end
    else
        if callback then callback(false, "Error: " .. tostring(code) .. " " .. tostring(body)) end
    end
end

function firebase.init(options)
    config.apiKey = options.apiKey or error("apiKey required")
    config.dbURL = options.dbURL or error("dbURL required")
    config.timeout = options.timeout or 3
    config.verifySSL = options.verifySSL or false
end

function firebase.authAnonymous(callback)
    if not config.apiKey then
        error("apiKey not set")
    end
    local authUrl = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" .. config.apiKey
    local options = {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        data = '{"returnSecureToken":true}',
        timeout = config.timeout,
        verify = config.verifySSL,
    }
    local ok, code, body
    if hasHttps() then
        local https = require("https")
        ok, code, body = pcall(https.request, authUrl, options)
    else
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local response = {}
        local res, code, headers = http.request {
            url = authUrl,
            method = "POST",
            headers = options.headers,
            source = ltn12.source.string(options.data),
            sink = ltn12.sink.table(response),
            timeout = options.timeout,
        }
        if code and code == 200 then
            ok, code, body = true, code, table.concat(response)
        else
            ok, code, body = false, code, "HTTP error"
        end
    end
    if ok and code == 200 then
        local data = love.data.decode("json", body)
        if data and data.idToken then
            config.authToken = data.idToken
            if callback then callback(true, data) end
        else
            if callback then callback(false, "Missing idToken") end
        end
    else
        if callback then callback(false, "Auth error: " .. tostring(code)) end
    end
end

function firebase.setToken(token)
    config.authToken = token
end

function firebase.get(path, callback)
    request("GET", path, nil, function(success, data)
        if success then
            local decoded = love.data.decode("json", data)
            if callback then callback(true, decoded) end
        else
            if callback then callback(false, data) end
        end
    end)
end

function firebase.put(path, data, callback)
    local jsonData = love.data.encode("json", data)
    request("PUT", path, jsonData, function(success, body)
        if callback then callback(success, body) end
    end)
end

function firebase.patch(path, data, callback)
    local jsonData = love.data.encode("json", data)
    request("PATCH", path, jsonData, function(success, body)
        if callback then callback(success, body) end
    end)
end

function firebase.post(path, data, callback)
    local jsonData = love.data.encode("json", data)
    request("POST", path, jsonData, function(success, body)
        if callback then callback(success, body) end
    end)
end

function firebase.delete(path, callback)
    request("DELETE", path, nil, function(success, body)
        if callback then callback(success, body) end
    end)
end

function firebase.getToken()
    return config.authToken
end

return firebase
