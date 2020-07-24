# KristWrap
KristWrap is similar to tmpim's k.lua, but without the need to change your coding style to support jua.

# Warning
**This may contains bugs! I haven't yet had time to test it fully, but it should work overall.**

# About
Like stated above, this is similar to k.lua, but you don't need to change your coding style. Initially, this project will purely be for transactions and etc. It may get larger later (or I may forget about it, who knows?), but for now I'm building it for [Simplify Shop V2](https://github.com/Fatboychummy-CC/Simplify-Shop-V2/tree/RemakeAgainOrSomething).

# Usage
1. `wget https://raw.githubusercontent.com/Fatboychummy-CC/KristWrap/master/KristWrap.lua` or `wget https://raw.githubusercontent.com/Fatboychummy-CC/KristWrap/master/minified.lua`

2. Download rxi's json library, from https://github.com/rxi/json.lua

3. Download Anavrin's Sha256 library, from https://pastebin.com/6UV4qfNF

4. In your program, set the endpoint
  * If you don't know what this means, or you just wish to use "the normal krist", use `KristWrap.useDefaultEndPoint()`.

5. In parallel, you want to run `KristWrap.run` with the following arguments:
  * Table of strings
    * Each string is an event you want to subscribe to, like `"transactions"`, or `"blocks"`
  * (optional): Private key, in either raw or KristWalletFormat.

6. Write your code, I recommend using parallel.  Example follows:

```lua
local KristWrap = require "KristWrap"
local privatekey = "something"

parallel.waitForAny(
  function()
    KristWrap.useDefaultEndPoint()
    KristWrap.run({"transactions"}, privatekey)
  end,
  function()
    KristWrap.Initialized:Wait() -- wait for KristWrap.run to begin executing.

    while true do
      local to, from, value, metadata = KristWrap.Transaction:Wait()
      -- Do stuff with the transaction here.
    end
  end
)
```

For ~~all~~ some events, you can use either `KristWrap.Event:Wait([number timeout])` or `KristWrap.Event:Connect(<function callback>)`.  Use `Wait` for simplicity, or `Connect` if you wish for a more Jua-like usage (Or more roblox-like usage, if you're used to that).

**Note:** `Event:Connect` requires `KristWrap.run` to be ran in parallel.
