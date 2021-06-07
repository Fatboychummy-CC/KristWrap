-- Authorization after kristwrap is running is not usually needed,
-- but on the off-chance you don't want to always be authorized
-- you can authorize and de-authorize whenever you wish.

local KristWrap = require "KristWrap"

local function main()
  parallel.waitForAny(
    function()
      KristWrap.useDefaultEndPoint()

      -- Here we have not passed an authorization token to KristWrap.run.
      KristWrap.run({"transactions"})
    end,
    function()
      KristWrap.Initialized:Wait()

      while true do
        local from, to, value, metadata = KristWrap.Transaction:Wait()

        KristWrap.setQueueEnabled(true)


        print(string.format("Received a transaction from %s going to %s, worth %d kst!", from, to, value))
        print(string.format("Metadata: %s", metadata))

        -- We want to echo the transaction back to them, but there's a problem -- we aren't authed!
        if not KristWrap.isAuthed() then -- check if we are authorized or not.
          -- Upgrade our websocket authorization, if we succeed, we will now be able to send transactions!
          local ok, address = KristWrap.upgradeWebsocket("authtoken")

          if ok then
            print(string.format("Authorized as %s.", address))
          else
            printError(string.format("Error when trying to authorize: %s", address))
          end
        end

        local ok, err = KristWrap.makeTransaction(from, value, metadata)
        if ok then
          print("Transaction echo sent!")
        else
          printError(string.format("Error when sending transaction: %s", err))
        end

        -- de-authorize.
        ok, err = KristWrap.downgradeWebsocket()
        if ok then
          print("Deauthorized.")
        else
          print(string.format("Error when trying to deauthorize: %s", err))\
        end


        KristWrap.setQueueEnabled(false)
      end
    end
  )
end

local ok, err = pcall(main)

KristWrap.close()

if not ok then
  printError(err)
end
