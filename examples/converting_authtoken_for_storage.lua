-- This example shows you how to convert an authorization token to KristWallet format
-- for saving to disk. It is better to store auth-tokens this way, as this operation
-- is non-reversible, meaning even if the computer is compromised, your password is safe.

-- The attacker can still use your auth-token, but if you used the same password elsewhere,
-- the attacker will not know.

local KristWrap = require "KristWrap"

-- ask user for privatekey.
print("Enter privatekey: ")
local privatekey = read('*') -- read('*') will display all characters as *

-- convert the privatekey to KristWallet format.
local token = KristWrap.toKristWalletFormat(privatekey)

-- save the token to disk.
local file = io.open(".token", 'w')
if file then
  file:write(token)
  file:close()
  print("Wrote token to '.token'.")
else
  printError("Failed to write file.")
end
