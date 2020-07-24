--[[
  MIT License
  Copyright 2020 Fatboychummy

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]

local expect = require("cc.expect").expect
local json   = require("json")   -- Recommended use rxi's version at https://github.com/rxi/json.lua
local sha256 = require("sha256") -- Recommended use Anavrin's version at https://pastebin.com/6UV4qfNF
                                 -- May not be compatible with other versions of these modules.
local tLib = {}
local wsID = 1
local sEndPoint, ws, sWsEP, sHttpEP
local isAuthed, running = false, false

local tConnections = {}

--[[
  @local-function eventify create a thing that can wait for events similar to roblox's events
  @param sEvent the event to listen for
  @returns 1 (table Wait/Connect methods)
]]
local function eventify(sEvent)
  expect(1, sEvent, "string")
  return {
      --[[
        @function Fire fires the event
        @params event arguments
      ]]
      Fire = function(self, ...)
        os.queueEvent(sEvent, ...)
      end,

      --[[
        @function Wait waits for an event to occur, then returns it and it's data
        @param self the event
        @param nTimeout timeout, in seconds
        @returns any If the event was received
        @returns nil If the timeout was hit
      ]]
      Wait = function(self, nTimeout)
        expect(1, self, "table")
        expect(2, nTimeout, "number", "nil")

        if nTimeout then
          nTimeout = os.startTimer(nTimeout)
        end
        while true do
          local tEvent = table.pack(os.pullEvent())
          if tEvent[1] == "timer" and tEvent[2] == nTimeout then
            return
          elseif tEvent[1] == sEvent then
            return table.unpack(tEvent, 2, tEvent.n)
          end
        end
      end,

      --[[
        @function Connect whenever this event occurs, call callback
        @param self the event
        @param fCallback the callback function to be called with event data
        @returns 1 (table with Disconnect to disconnect from the event)
      ]]
      Connect = function(self, fCallback)
        expect(1, self, "table")
        expect(2, fCallback, "function")

        if not tConnections[sEvent] then
          tConnections[sEvent] = {}
        end
        local i = #tConnections[sEvent] + 1
        tConnections[sEvent][i] = fCallback
        return {
          Disconnect = function()
            for i = 1, #tConnections[sEvent] do
              if tConnections[sEvent][i] == fCallback then
                table.remove(tConnections[sEvent], i)
                break
              end
            end
          end
        }
      end
    }
end


--[[
  @local-function checkWS checks if the websocket has been set yet, throws an error if not.
]]
local function checkWS()
  if not ws then
    error("Websocket not initialized!", 3)
  end
end

--[[
  @local-function checkEndPoint checks if the endpoint has been set yet, throws an error if not.
]]
local function checkEndPoint()
  if not sEndPoint then
    error("Endpoint not set!", 3)
  end
end

--[[
  @local-function httpPost Post data converted to json
  @param sTo The url to post to
  @param tData The data to be converted to json
  @param tHeaders Any extra headers to be added ("Content-Type"="application/json" is automatically added.)
  @returns whatever http.post returns
]]
local function httpPost(sTo, tData, tHeaders)
  expect(1, sTo, "string")
  expect(2, tData, "table", "nil")
  expect(3, tHeaders, "table", "nil")

  tData = tData or {}
  tHeaders = tHeaders or {}
  tHeaders["Content-Type"] = "application/json"

  return http.post(sTo, json.encode(tData), tHeaders)
end

--[[
  @local-function wsRequest make a websocket request
  @param tData Optional, The data to be sent.
  @returns 2 (boolean response OK), (table response) Always
]]
local function wsRequest(tData)
  expect(1, tData, "table", "nil")
  checkWS() -- ensure websocket is initialized

  local iID = wsID -- get the current id and save it
  wsID = wsID + 1  -- increment the id so other threads wont screw up

  tData = tData or {}
  tData.id = iID              -- set the id of our request
  ws.send(json.encode(tData)) -- send our request

  while true do
    local sResponse = ws.receive()     -- get websocket message
    tResponse = json.decode(sResponse) -- decode it
    if tResponse.id == iID then        -- if it's a response to the message we sent
      return tResponse.ok, tResponse   -- return the response
    end
  end
end

--[[
  @local-function wsStart Make the initial connection to the websocket via endpoint provided
  @short sets the environment-local variable 'ws' to the websocket.
  @param sAuth Optional, Authorize this connection.
]]
local function wsStart(sAuth)
  expect(1, sAuth, "string", "nil")
  checkEndPoint()

  tLib.close() -- close the old websocket session if there's one already running.

  -- if we want to authorize, convert the input key to krist wallet format.
  if sAuth then
    sAuth = tLib.toKristWalletFormat(sAuth)
  end

  -- POST to /ws/start
  local tResponse, sErr = httpPost(
    sHttpEP .. "/ws/start",
    {
      privatekey = sAuth
    }
  )

  -- if we received a response
  if tResponse then
    -- decode the response.
    local bOk, tData = pcall(json.decode, tResponse.readAll())
    tResponse.close() -- close the http handle

    -- if we successfully decoded the response
    if bOk then
      -- and if the response was ok
      if tData.ok then
        -- if we wanted to authorize
        if sAuth then
          -- assume we've authorized properly
          isAuthed = true
        end

        -- attempt websocket connection
        local sResponse, sErr2 = http.websocket(tData.url)

        -- if we got a response
        if sResponse then
          -- set the environment-local ws variable
          ws = sResponse
        else
          error(string.format("Websocket connection failure: %s", sErr2))
        end
      else
        error(string.format("Websocket failure: %s", tData.error), 2)
      end
    else
      error(string.format("Websocket init decode failure: %s", tData), 2)
    end
  else
    error(string.format("Websocket creation failure: %s", sErr), 2)
  end
end

--[[
  @local-function subscribe Subscribe to subscriptions provided
  @param tSubscriptions Subscriptions to subscribe to
]]
local function subscribe(tSubscriptions)
  expect(1, tSubscriptions, "table")

  -- for each subscription
  for i = 1, #tSubscriptions do
    -- request a subscription to it
    local bOk, tResponse = wsRequest({
      type = "subscribe",
      event = tSubscriptions[i]
    })

    -- if we failed to subscribe to it
    if not bOk then
      -- get the error
      local sError = tResponse.error
      if not sError then
        -- we need to go deeper, soon...
        sError = "Unknown"
      end

      -- throw the error
      error(string.format("Failed to subscribe to %s: %s", tSubscriptions[i], sError), 2)
    end
  end
end

--[[
  @function makeTransaction Make a transaction (If logged in.)
  @param sTo The address to send krist to.
  @param iAmount The amount of krist to send. This value will be math.floor'd
  @param sMeta Optional The metadata to send with.
  @param sAuth Optional If KristWrap is not running, you can use this to authorize the transaction
  @returns 1 (value=true) If the transaction was successful
  @returns 2 (value=false), (string error) If the transaction failed
]]
function tLib.makeTransaction(sTo, iAmount, sMeta, sAuth)
  expect(1, sTo,     "string")
  expect(2, iAmount, "number")
  iAmount = math.floor(iAmount)
  expect(3, sMeta,   "string", "nil")
  expect(4, sAuth,   "string", "nil")

  -- check if websocket mode is authed (if in websocket mode)
  if running and not isAuthed then
    error("KristWrap is not authorized to make a transaction in websocket mode! Authorize before attempting to make a transaction!", 2)
  end

  -- check if http mode and if auth key supplied
  if not running and not sAuth then
    error("KristWrap requires an authorization key (4th argument) to make a transaction if KristWrap is not running in websocket mode and authorized.", 2)
  end

  if running then -- websocket request
    local bOk, tResponse = wsRequest({
      type = "make_transaction",
      to = sTo,
      amount = iAmount,
      metadata = sMeta
    })

    if bOk then
      return true
    end
    return false, tResponse.error
  else -- http request
    local tResponse, sErr, tErrorHandle = httpPost(
      sHttpEP .. "/transactions/",
      {
        privatekey = tLib.toKristWalletFormat(sAuth),
        to = sTo,
        amount = iAmount,
        metadata = sMeta
      }
    )

    if not tResponse then
      error(string.format("Bad response. sErr:(%s), handleAll:(%s)", sErr, tErrorHandle.readAll()))
    end

    local ok, tAll = pcall(json.decode, tResponse.readAll())
    tResponse.close()
    return tAll.ok, tAll.error
  end
end

--[[
  @function toKristWalletFormat Converts a raw privatekey to a kristwallet format
  @param sKey The key to be converted. If it's already in KristWallet format, nothing will happen.
  @returns 1 (string KristWallet format privatekey) Always
]]
function tLib.toKristWalletFormat(sKey)
  expect(1, sKey, "string")

  -- assume any key ending with "-000" is already in kristwallet format.
  if sKey:sub(#sKey - 3) == "-000" then
    return sKey
  end
  return sha256.digest("KRISTWALLET" .. sKey):toHex() .. "-000"
end

--[[
  @function getV2Address Uses the krist endpoint to convert a pkey to a v2 krist address
  @param sKey The privatekey you wish to use (Can be in RAW or KristWallet format)
  @returns nil If there was a failure.
  @returns 1 (string Address) If everything was ok.
]]
function tLib.getV2Address(sKey)
  expect(1, sKey, "string")
  checkEndPoint()

  -- convert to kristwallet format
  sKey = tLib.toKristWalletFormat(sKey)

  -- ask for the v2 address
  local tResponse, sErr = httpPost(sHttpEP .. "/v2", {privatekey = sKey})

  -- return the response if we got one, otherwise return nil
  if tResponse then
    tData = json.decode(tResponse.readAll())
    tResponse.close()
    return tData.address
  end
end

--[[
  @function run Connects to and runs the background conversion of websocket_message to websocket_message_decoded
  @param tSubscriptions Table of subscriptions to subscribe to (transactions, blocks, etc)
  @param sAuth Optional, supply with a KristWallet format private-key to elevate status (allows for sending krist from an address)
  @queues websocket_message_decoded whenever a websocket message arrives for our websocket.
]]
function tLib.run(tSubscriptions, sAuth)
  expect(1, tSubscriptions, "table", "nil")
  expect(2, sAuth, "string", "nil")

  checkEndPoint()

  -- Make the connection to the krist endpoint
  wsStart(sAuth)

  -- subscribe to subscriptions
  subscribe(tSubscriptions or {})

  -- recognized types
  local tRecognized = {
    -- event, currently only supporting "transaction" events.
    event = function(tData)
      -- determine what event it is
      local sEvent = tData.event

      -- if transaction event
      if sEvent == "transaction" then
        -- get event information
        local t = tData.transaction
        local ok, meta = pcall(json.decode, t.metadata)
        if not ok then meta = t.metadata end

        -- queue transaction event.
        tLib.Transaction:Fire(t.from, t.to, t.value, meta)
      end
    end
  }

  -- main loop
  local function loop1()
    -- set running
    running = true
    local iFailCount = 0
    tLib.Initialized:Fire()

    -- actual main loop
    while true do
      -- listen for websocket messages
      local sData = ws.receive()

      -- attempt decode
      local bOk, tData = pcall(json.decode, sData)

      -- if we decoded properly
      if bOk then
        iFailCount = 0

        -- queue a decoded message
        tLib.websocket_message_decoded:Fire(tData)

        -- check if the type is recognized (so an extra event can be generated)
        if tRecognized[tData.type] then
          tRecognized[tData.type](tData)
        end
      else
        -- allow up to 10 failures, after which the system will error.
        iFailCount = iFailCount + 1
        if iFailCount > 10 then
          error("Failed to decode data from websocket over ten times, stopping.")
        end
      end
    end
  end

  -- connections loop
  local function loop2()
    while true do
      local tEvent = table.pack(os.pullEvent())
      local sEvent = tEvent[1]
      if tConnections[sEvent] then
        for i = 1, #tConnections[sEvent] do
          tConnections[sEvent][i](table.unpack(tEvent, 2, tEvent.n))
        end
      end
    end
  end

  -- pcall main loop so if it stops we can close the websocket, and set running to false.
  local bOk, sErr = pcall(parallel.waitForAny, loop1, loop2)
  ws.close()
  running = false
  if not bOk then
    error(sErr)
  end
end

--[[
  @function setEndPoint sets the endpoint
  @short Removes preceding http:// or ws:// and trailing /
  @param _sEndPoint The endpoint to be used.
]]
function tLib.setEndPoint(_sEndPoint)
  expect(1, _sEndPoint, "string")

  -- check if the last character is a '/' and remove it
  if _sEndPoint:sub(#_sEndPoint, #_sEndPoint) == "/" then
    _sEndPoint = _sEndPoint:sub(1, #_sEndPoint - 1)
  end

  -- check if the start begins with "https://" or "http://"
  sEndPoint = string.gsub(_sEndPoint, "https?%:%/%/", "")

  -- check if the start begins with "wss://" or "ws://"
  sEndPoint = string.gsub(sEndPoint, "wss?:%/%/", "")

  -- set endpoints with ws:// and https://
  sWsEP = "ws://" .. sEndPoint
  sHttpEP = "https://" .. sEndPoint
end

--[[
  @function useDefaultEndPoint sets the endpoint to the default krist endpoint (krist.ceriat.net)
]]
function tLib.useDefaultEndPoint()
  tLib.setEndPoint("krist.ceriat.net")
end

--[[
  @function getEndPoint Gets the current endpoint in use.
  @returns 1 (string The endpoint) If the endpoint has been set
  @returns nil If the endpoint has not yet been set.
]]
function tLib.getEndPoint()
  return sEndPoint
end

--[[
  @Event Initialized
  @short Fired when
]]
tLib.Initialized = eventify("KristWrap_Initialized")

tLib.Transaction = eventify("KristWrap_Transaction")

tLib.websocket_message_decoded = eventify("websocket_message_decoded")

--[[
  @function close Closes the websocket, if it is opened.
]]
function tLib.close()
  if ws then ws.close() end
end

return tLib
