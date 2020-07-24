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

  tLib.close()

  local tResponse, sErr = httpPost(
    sHttpEP .. "/ws/start",
    {
      privatekey = sKey and tLib.toKristWalletFormat(sKey)
    }
  )
  if tResponse then
    local tData = json.decode(tResponse.readAll())
    tResponse.close()
    if tData.ok then
      local sResponse, sErr2 = http.websocket(tData.url)
      if sResponse then
        ws = sResponse
      else
        error(string.format("Websocket connection failure: %s", sErr2))
      end
    else
      error(string.format("Websocket failure: %s", tData.error), 2)
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

  for i = 1, #tSubscriptions do
    local bOk, tResponse = wsRequest({
      type = "subscribe",
      event = tSubscriptions[i],
      id = wsID
    })
    if not bOk then
      local sError = tResponse.error
      if not sError then
        -- we need to go deeper, soon...
        sError = "Unknown"
      end
      error(string.format("Failed to subscribe to %s: %s"), tSubscriptions[i], sError)
    end
    wsID = wsID + 1
  end
end

--[[
  @function makeTransaction Make a transaction (If logged in.)
  @param sTo The address to send krist to.
  @param iAmount The amount of krist to send. This value will be math.floor'd
  @param sMeta Optional The metadata to send with.
  @returns 1 (value=true) If the transaction was successful
  @returns 2 (value=false), (string error) If the transaction failed
]]
function tLib.makeTransaction(sTo, iAmount, sMeta)
  expect(1, sTo, "string")
  expect(2, iAmount, "number")
  iAmount = math.floor(iAmount)
  expect(3, sMeta, "string", "nil")

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
end

--[[
  @function toKristWalletFormat Converts a raw privatekey to a kristwallet format
  @param sKey The key to be converted. If it's already in KristWallet format, nothing will happen.
  @returns 1 (string KristWallet format privatekey) Always
]]
function tLib.toKristWalletFormat(sKey)
  expect(1, sKey, "string")
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

  sKey = tLib.toKristWalletFormat(sKey)

  local tResponse, sErr = httpPost(sHttpEP .. "/v2", {privatekey = sKey})
  if tResponse then
    tResponse = json.decode(tResponse.readAll())
    return tResponse.address
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
  wsStart(sHttpEP, sAuth)

  -- subscribe to subscriptions
  subscribe(tSubscriptions or {})

  local function loop()
    local iFailCount = 0
    while true do
      local sData = ws.receive()
      local bOk, tData = pcall(json.decode, sData)
      if bOk then
        iFailCount = 0
        os.queueEvent("websocket_message_decoded", tData)
      else
        iFailCount = iFailCount + 1
        if iFailCount > 10 then
          error("Failed to decode data from websocket over ten times, stopping.")
        end
      end
    end
  end

  local bOk, sErr = pcall(loop)
  ws.close()
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

  if _sEndPoint:sub(#_sEndPoint, #_sEndPoint) == "/" then
    _sEndPoint = _sEndPoint:sub(1, #_sEndPoint - 1)
  end
  sEndPoint = string.gsub(_sEndPoint, "https?%:%/%/", "")
  sEndPoint = string.gsub(sEndPoint, "wss?:%/%/", "")
  sWsEP = "ws://" .. sEndPoint
  sHttpEP = "https://" .. sEndPoint
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
  @function close Closes the websocket, if it is opened.
]]
function tLib.close()
  if ws then ws.close() end
end

return tLib
