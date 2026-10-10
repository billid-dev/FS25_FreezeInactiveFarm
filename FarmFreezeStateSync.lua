-- FarmFreezeStateSync: serwer przekazuje klientom liste zamrozonych farm.
-- Na serwerze dedykowanym klient sam dolicza wiek maszyn, wiec musi wiedziec, ktore farmy przywracac.

FarmFreezeStateEvent = {}
local FarmFreezeStateEvent_mt = Class(FarmFreezeStateEvent, Event)
InitEventClass(FarmFreezeStateEvent, "FarmFreezeStateEvent")

function FarmFreezeStateEvent.emptyNew()
    return Event.new(FarmFreezeStateEvent_mt)
end

function FarmFreezeStateEvent.new(frozenIds)
    local self = FarmFreezeStateEvent.emptyNew()
    self.ids = frozenIds or {}
    return self
end

function FarmFreezeStateEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, #self.ids)
    for _, farmId in ipairs(self.ids) do
        streamWriteUInt8(streamId, farmId)
    end
end

function FarmFreezeStateEvent:readStream(streamId, connection)
    local count = streamReadUInt8(streamId)
    self.ids = {}
    for _ = 1, count do
        table.insert(self.ids, streamReadUInt8(streamId))
    end
    self:run(connection)
end

function FarmFreezeStateEvent:run(connection)
    -- Zdarzenie ma sens tylko po stronie klienta (odebrane od serwera)
    if connection:getIsServer() then
        FarmFreeze:applyClientFrozen(self.ids)
    end
end

-- Dolaczajacy gracz od razu dostaje aktualna liste zamrozonych farm
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
    function(self, connection, user, farm)
        connection:sendEvent(FarmFreezeStateEvent.new(FarmFreeze:getFrozenIds()))
    end)
