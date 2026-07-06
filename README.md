# firebase-love

Firebase Realtime Database client for LÖVE.

## Usage

```lua
local firebase = require("firebase")

firebase.init({
    apiKey = "your-api-key",
    dbURL = "https://your-project.firebaseio.com",
    verifySSL = false, -- set true for desktop
})

firebase.authAnonymous(function(success, data)
    if success then
        print("Auth OK", data.localId)
    end
end)

firebase.put("players/123", { x = 100, y = 200 })
firebase.get("players", function(ok, data) print(data) end)
firebase.delete("players/123")
