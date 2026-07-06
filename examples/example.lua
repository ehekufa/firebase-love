local firebase = require("firebase")

firebase.init({
    apiKey = "",
    dbURL = "",
    verifySSL = false,
})

firebase.authAnonymous(function(ok, data)
    if ok then
        print("Auth OK", data.localId)
        firebase.put("test/hello", { message = "Hello from firebase-love!" })
    else
        print("Auth failed", data)
    end
end)

love.timer.sleep(1)
firebase.get("test", function(ok, data)
    print("Data:", data)
end)
