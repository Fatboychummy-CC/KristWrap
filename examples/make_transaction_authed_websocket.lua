-- This example shows you how to echo transactions back to whomever sent you a transaction.

local KristWrap = require "KristWrap"

local function main()
  parallel.waitForAny(
    function()
      KristWrap.useDefaultEndPoint()
      KristWrap.run({"transactions"}, "authtoken")
    end,
    function()
      KristWrap.Initialized:Wait()

      while true do
        local from, to, value, metadata = KristWrap.Transaction:Wait()

        KristWrap.setQueueEnabled(true)


        print(string.format("Received a transaction from %s going to %s, worth %d kst!", from, to, value))
        print(string.format("Metadata: %s", metadata))

        -- let's echo the transaction back to the sender.
        -- It is quite easy.
        local ok, err = KristWrap.makeTransaction(from, value, meta)

        -- It returns two values, first is if it succeeded, second is if it failed, the error.
        if ok then
          print("Transaction echoed!")
        else
          printError(string.format("Error while sending transaction: ", err))
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
