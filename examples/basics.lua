-- This example contains the basics of using KristWrap.
-- Nearly every example will contain this structure, however, they will only comment upon the newly introduced items.

local KristWrap = require "KristWrap"


-- ##### Initialization #####
-- You need to initialize a few things for KristWrap to know what is going on.


-- ## Endpoint ##
-- This will be your endpoint for everything, usually.
KristWrap.useDefaultEndPoint()

-- If you're running your own krist node and wish to connect to it instead, use the following function
-- Note: Kristwrap will automatically append and prepend anything it needs, do not include http/https directive or trailing `/`, it will be removed anyways.
KristWrap.setEndPoint("krist.ceriat.net") -- krist.ceriat.net is the default endpoint.

-- For debugging purposes, returns the current endpoint you are using.
KristWrap.getEndPoint()


-- ##### Main program #####

local function main()
  -- These functions need to be called in parallel.
  parallel.waitForAny(
    function()
      -- To run kristwrap in websocket mode, you pass KristWrap.run a table containing krist events you want to listen to, and an auth token, if needed.
      -- Note: An auth token is needed if you wish to send transactions, but is not needed to only listen.
      -- Note 2: The auth token can be either raw, or already in kristwallet-format.
      KristWrap.run({"transactions"}, "authtoken")
    end,
    function()
      -- This is your main function, make it do what you want. It will run in parallel to KristWrap.

      -- Wait for KristWrap to be ready (connection to krist node + authorization).
      KristWrap.Initialized:Wait()

      while true do
        -- Wait for a transaction to occur, then save the information about it.
        local from, to, value, metadata = KristWrap.Transaction:Wait()

        -- This is not explicitly required, but it is highly recommended.
        -- setQueueEnabled tells one of KristWrap's coroutines to cache incoming transactions, as we are currently processing a transaction.
        -- The queue allows transactions to be received even if KristWrap is processing something else (ie: sending a transaction).
        -- Without it, you may miss transaction events!
        KristWrap.setQueueEnabled(true)

        -- process the transaction.
        print(string.format("Received a transaction from %s going to %s, worth %d kst!", from, to, value))
        print(string.format("Metadata: %s", metadata))

        -- If you enabled the queue, be sure to disable it. You will get duplicated transaction events if you don't.
        KristWrap.setQueueEnabled(false)
      end
    end
  )
end

-- For the unaware, pcall is "protected call"
-- it calls a function, and if it errors, will return `false, "The error"`.
-- otherwise it returns true.
-- It is good for catching issues and handling a safe shutdown.
local ok, err = pcall(main)

-- If your program ever crashes, you should ensure that you call KristWrap.close(), just like a file handle.
KristWrap.close()

if not ok then
  printError(err)
end
