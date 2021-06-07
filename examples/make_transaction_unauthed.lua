-- This example shows you how to send a transaction if you are not authorized (and websocket mode is not running)

local KristWrap = require "KristWrap"

-- when unauthorized, we need to include the authorization token as a fourth argument.
local ok, err = KristWrap.makeTransaction("kbielbeajd", 100, "metadata!", "authtoken")

-- It returns two values, first is if it succeeded, second is if it failed, the error.
if ok then
  print("Transaction succeeded!")
else
  printError(string.format("Error while sending transaction: ", err))
end
