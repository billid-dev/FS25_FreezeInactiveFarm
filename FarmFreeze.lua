-- Farm Freeze: gdy zaden kierownik danej farmy nie jest online, farma jest zamrozona (tylko serwer).
-- Zamrazane: konto, kredyt, wiek i motogodziny maszyn, czas zwierzat (starzenie, rozmnazanie, zdrowie),
-- pasza, woda i sloma w oborach oraz produkcja obor (jajka, mleko, welna, gnojowica itp.).

FarmFreeze = {}
FarmFreeze.VERSION = "1.0.7.0"
FarmFreeze.DEBUG = false      -- true wlacza dodatkowe komunikaty diagnostyczne w log.txt
FarmFreeze.CHECK_INTERVAL = 1000 -- ms
FarmFreeze.timer = 0
FarmFreeze.frozen = {}        -- [farmId] = true
FarmFreeze.snap = {}          -- [farmId] = zapamietany stan farmy w chwili zamrozenia
FarmFreeze.errorSeen = {}
FarmFreeze.debugUpdates = {}      -- licznik wywolan updateOutput na zamrozonych farmach (tylko debug)
FarmFreeze.debugUpdatesLast = {}  -- ostatnie argumenty updateOutput (tylko debug)
FarmFreeze.debugBlocked = {}      -- licznik zablokowanych zdarzen obor (tylko debug)
FarmFreeze.debugKeys = {}
FarmFreeze.clientFrozen = {}  -- [farmId] = true; stan odebrany od serwera (tylko klienci)
FarmFreeze.clientSnap = {}    -- [farmId] = { [pojazd] = { age, operatingTime } } (tylko klienci)

local function log(...)
    if FarmFreeze.DEBUG then
        print("[FarmFreeze] " .. string.format(...))
    end
end

-- Bledy wypisujemy zawsze, ale kazdy rodzaj tylko raz (zeby nie zasmiecac logu)
local function logError(name, err)
    if not FarmFreeze.errorSeen[name] then
        FarmFreeze.errorSeen[name] = true
        print(string.format("[FarmFreeze] BLAD (%s): %s", name, tostring(err)))
    end
end

local function fillTypeName(fillType)
    local ok, name = pcall(function() return g_fillTypeManager:getFillTypeNameByIndex(fillType) end)
    return tostring(ok and name or fillType)
end

-- DIAGNOSTYKA: wypisuje pola liczbowe (do 2 poziomow w glab) tabeli, w tym tabele zwiazane z poziomami
local function describeNumbers(t, depth)
    local parts = {}
    for k, v in pairs(t) do
        if type(v) == "number" then
            table.insert(parts, string.format("%s=%.3f", tostring(k), v))
        elseif type(v) == "table" and depth > 0 then
            local lname = tostring(k):lower()
            if lname:find("fill") or lname:find("liters") or lname:find("heap") or lname:find("storage") then
                for _, sub in ipairs(describeNumbers(v, depth - 1)) do
                    table.insert(parts, tostring(k) .. "." .. sub)
                end
            end
        end
    end
    table.sort(parts)
    return parts
end

local function getPlaceables()
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    return (ps ~= nil and ps.placeables) or {}
end

--------------------------------------------------------------------------------
-- Ustawienia (wartosciami steruje serwer; zmieniac moze tylko admin)
--------------------------------------------------------------------------------
FarmFreeze.SETTING_KEYS = { "enabled", "freezeMoney", "freezeLoan", "freezeVehicles", "freezeAnimalTime", "freezeAnimalFeed", "freezeManure" }
FarmFreeze.settings = {
    enabled = true,          -- caly mod
    freezeMoney = true,      -- konto bankowe
    freezeLoan = true,       -- kredyty
    freezeVehicles = true,   -- wiek i motogodziny maszyn
    freezeAnimalTime = true, -- starzenie, rozmnazanie, zdrowie zwierzat
    freezeAnimalFeed = true, -- pasza, woda, slomka i produkcja obor (jajka, mleko, welna)
    freezeManure = true      -- obornik i gnojowica w oborach (osobny przelacznik)
}

function FarmFreeze:getSettingsPath()
    return getUserProfileAppPath() .. "modSettings/FS25_FreezeInactiveFarm.xml"
end

function FarmFreeze:loadSettings()
    local ok, err = pcall(function()
        local path = self:getSettingsPath()
        if not fileExists(path) then return end
        local xml = loadXMLFile("farmFreezeSettings", path)
        if xml == nil or xml == 0 then return end
        for _, key in ipairs(self.SETTING_KEYS) do
            local value = getXMLBool(xml, "farmFreeze." .. key)
            if value ~= nil then self.settings[key] = value end
        end
        delete(xml)
    end)
    if not ok then logError("wczytywanie ustawien", err) end
end

function FarmFreeze:saveSettings()
    local ok, err = pcall(function()
        createFolder(getUserProfileAppPath() .. "modSettings/")
        local xml = createXMLFile("farmFreezeSettings", self:getSettingsPath(), "farmFreeze")
        for _, key in ipairs(self.SETTING_KEYS) do
            setXMLBool(xml, "farmFreeze." .. key, self.settings[key] == true)
        end
        saveXMLFile(xml)
        delete(xml)
    end)
    if not ok then logError("zapis ustawien", err) end
end

-- Wywolywane na serwerze i klientach po zmianie ustawien
function FarmFreeze:applySettings(newSettings)
    for _, key in ipairs(self.SETTING_KEYS) do
        if newSettings[key] ~= nil then self.settings[key] = newSettings[key] end
    end
end

--------------------------------------------------------------------------------
-- Zamrazanie i odmrazanie
--------------------------------------------------------------------------------

-- Czy ktorykolwiek kierownik tej farmy jest teraz polaczony z serwerem
function FarmFreeze:isManagerOnline(farm)
    local users = g_currentMission.userManager:getUsers()
    for _, user in ipairs(users) do
        if farm:isUserFarmManager(user:getId()) then
            return true
        end
    end
    return false
end

function FarmFreeze:getVehicles()
    local mission = g_currentMission
    if mission.vehicleSystem ~= nil and mission.vehicleSystem.vehicles ~= nil then
        return mission.vehicleSystem.vehicles
    end
    return mission.vehicles or {}
end

function FarmFreeze:freeze(farm)
    self.frozen[farm.farmId] = true
    self.snap[farm.farmId] = {
        money = farm:getBalance(),
        loan = farm.loan,
        vehicles = {},
        food = {},
        water = {},
        straw = {},
        pallets = {},
        manure = {}
    }
    log("Farma %d zamrozona (saldo=%s, kredyt=%s, kasa=%s, kredyty=%s, maszyny=%s, zwierzeta=%s, pasza=%s)",
        farm.farmId, tostring(farm:getBalance()), tostring(farm.loan),
        tostring(self.settings.freezeMoney), tostring(self.settings.freezeLoan), tostring(self.settings.freezeVehicles),
        tostring(self.settings.freezeAnimalTime), tostring(self.settings.freezeAnimalFeed))
    self:broadcastState()
end

function FarmFreeze:unfreeze(farm)
    self.frozen[farm.farmId] = nil
    self.snap[farm.farmId] = nil
    log("Farma %d odmrozona", farm.farmId)
    self:broadcastState()
end

-- Lista zamrozonych farm (do wyslania klientom)
function FarmFreeze:getFrozenIds()
    local ids = {}
    for farmId, isFrozen in pairs(self.frozen) do
        if isFrozen then table.insert(ids, farmId) end
    end
    table.sort(ids)
    return ids
end

-- Serwer informuje klientow, ktore farmy sa zamrozone (klienci licza wiek maszyn lokalnie)
function FarmFreeze:broadcastState()
    if g_server ~= nil and FarmFreezeStateEvent ~= nil then
        g_server:broadcastEvent(FarmFreezeStateEvent.new(self:getFrozenIds()))
    end
end

-- Klient: odebranie listy zamrozonych farm
function FarmFreeze:applyClientFrozen(ids)
    local newSet = {}
    for _, farmId in ipairs(ids) do newSet[farmId] = true end
    for farmId in pairs(self.clientSnap) do
        if not newSet[farmId] then self.clientSnap[farmId] = nil end
    end
    self.clientFrozen = newSet
end

-- Klient: przywracanie wieku i motogodzin maszyn zamrozonych farm
-- (na serwerze dedykowanym klient sam dolicza wiek, a serwer tego nie widzi)
function FarmFreeze:updateClient(dt)
    self.clientTimer = (self.clientTimer or 0) + dt
    if self.clientTimer < self.CHECK_INTERVAL then
        return
    end
    self.clientTimer = 0

    if not (self.settings.enabled and self.settings.freezeVehicles) then
        self.clientSnap = {}
        return
    end

    for _, vehicle in pairs(self:getVehicles()) do
        if vehicle.getOwnerFarmId ~= nil then
            local farmId = vehicle:getOwnerFarmId()
            if self.clientFrozen[farmId] then
                self.clientSnap[farmId] = self.clientSnap[farmId] or {}
                local store = self.clientSnap[farmId]
                local vs = store[vehicle]
                if vs == nil then
                    store[vehicle] = { age = vehicle.age, operatingTime = vehicle.operatingTime }
                else
                    if vehicle.age ~= vs.age then
                        log("Klient: wiek maszyny farmy %d zmienil sie %s -> %s, przywracam",
                            farmId, tostring(vs.age), tostring(vehicle.age))
                    end
                    vehicle.age = vs.age
                    vehicle.operatingTime = vs.operatingTime
                end
            end
        end
    end
end

-- Dolewa do obory przez funkcje gry. Probuje dwoch metod i zwraca true, jesli ktoras podniosla poziom.
function FarmFreeze:addFillLevel(placeable, farmId, fillType, delta, spec)
    local function level()
        return placeable:getHusbandryFillLevel(fillType, farmId) or 0
    end
    local before = level()

    if placeable.addHusbandryFillLevelFromTool ~= nil then
        pcall(placeable.addHusbandryFillLevelFromTool, placeable, farmId, delta, fillType, nil, nil, nil)
        if level() > before + 0.001 then return true end
    end

    if type(addHusbandryFillLevel) == "function" and spec.husbandryId ~= nil then
        pcall(addHusbandryFillLevel, spec.husbandryId, fillType, delta)
        if level() > before + 0.001 then return true end
    end
    return false
end

-- Odejmuje z obory (zbiornik obornika / gnojowicy) przez funkcje gry. Zwraca true, jesli poziom spadl.
function FarmFreeze:removeFillLevel(placeable, farmId, fillType, delta, husbandryId)
    local function level()
        return placeable:getHusbandryFillLevel(fillType, farmId) or 0
    end
    local before = level()

    if placeable.addHusbandryFillLevelFromTool ~= nil then
        pcall(placeable.addHusbandryFillLevelFromTool, placeable, farmId, -delta, fillType, nil, nil, nil)
        if level() < before - 0.001 then return true end
    end

    if type(addHusbandryFillLevel) == "function" and husbandryId ~= nil then
        pcall(addHusbandryFillLevel, husbandryId, fillType, -delta)
        if level() < before - 0.001 then return true end
    end
    return false
end

-- Obornik i gnojowica w oborach: dodatkowe zabezpieczenie obok zerowania produkcji.
-- Zapamietuje poziom przy zamrozeniu i usuwa kazdy wzrost (spadki, np. odbior gnojowicy, sa akceptowane).
function FarmFreeze:restoreManure(farm, store)
    local fillTypes = { FillType.MANURE, FillType.LIQUIDMANURE }

    for _, placeable in pairs(getPlaceables()) do
        if placeable.getHusbandryFillLevel ~= nil and placeable.getOwnerFarmId ~= nil
            and placeable:getOwnerFarmId() == farm.farmId
            and (placeable.spec_husbandryLiquidManure ~= nil or placeable.spec_husbandryManure ~= nil) then

            local husbandryId = nil
            for _, specName in ipairs({ "spec_husbandryLiquidManure", "spec_husbandryManure", "spec_husbandry" }) do
                local spec = placeable[specName]
                if spec ~= nil and spec.husbandryId ~= nil then
                    husbandryId = spec.husbandryId
                    break
                end
            end

            store[placeable] = store[placeable] or {}
            local snap = store[placeable]
            for _, fillType in ipairs(fillTypes) do
                local current = placeable:getHusbandryFillLevel(fillType, farm.farmId) or 0
                local old = snap[fillType]
                if old == nil then
                    snap[fillType] = current
                elseif current > old + 0.01 then
                    local removed = self:removeFillLevel(placeable, farm.farmId, fillType, current - old, husbandryId)
                    log("Obora '%s': %s wzrosl o %.3f na zamrozonej farmie, cofniecie: %s",
                        tostring(placeable:getName()), fillTypeName(fillType), current - old, removed and "TAK" or "NIE")
                elseif current < old then
                    snap[fillType] = current
                end
            end
        end
    end
end

-- Pasza w korycie obor: zapamietuje poziom przy zamrozeniu i cofa kazdy spadek
-- (wzrost, np. dowiezienie paszy, staje sie nowym poziomem bazowym).
function FarmFreeze:restoreFood(farm, store)
    for _, placeable in pairs(getPlaceables()) do
        local food = placeable.spec_husbandryFood
        if food ~= nil and type(food.fillLevels) == "table"
            and placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() == farm.farmId then

            local snap = store[placeable]
            if snap == nil then
                snap = {}
                for fillType, level in pairs(food.fillLevels) do snap[fillType] = level end
                store[placeable] = snap
            else
                local changed = false
                for fillType, level in pairs(food.fillLevels) do
                    local old = snap[fillType] or 0
                    if level < old - 0.001 then
                        food.fillLevels[fillType] = old
                        changed = true
                    elseif level > old then
                        snap[fillType] = level
                    end
                end
                if changed and food.dirtyFlagFillLevel ~= nil and placeable.raiseDirtyFlags ~= nil then
                    placeable:raiseDirtyFlags(food.dirtyFlagFillLevel)
                end
            end
        end
    end
end

-- Woda i slomka: poziom trzyma silnik gry, wiec odczyt i zapis idzie przez funkcje obory.
function FarmFreeze:restoreLevel(farm, store, specName, defaultFillType)
    for _, placeable in pairs(getPlaceables()) do
        local spec = placeable[specName]
        if spec ~= nil and placeable.getHusbandryFillLevel ~= nil
            and placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() == farm.farmId then

            local fillType = spec.fillType or defaultFillType
            local current = placeable:getHusbandryFillLevel(fillType, farm.farmId) or 0
            local snap = store[placeable]

            if snap == nil then
                store[placeable] = current
            elseif current < snap - 0.01 then
                self:addFillLevel(placeable, farm.farmId, fillType, snap - current, spec)
            elseif current > snap then
                store[placeable] = current
            end
        end
    end
end

-- Obornik i gnojowica (osobny przelacznik): zerowanie stawek produkcji w oborach.
-- Dodatkowo restoreManure usuwa kazdy wzrost poziomu w zbiorniku obory.
function FarmFreeze:zeroManure(farm)
    local outputSpecs = { "spec_husbandryLiquidManure", "spec_husbandryManure" }

    for _, placeable in pairs(getPlaceables()) do
        if placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() == farm.farmId then
            -- obornik powstaje w specyfikacji slomy: stawka produkcji to outputLitersPerHour
            local strawSpec = placeable.spec_husbandryStraw
            if strawSpec ~= nil and type(strawSpec.outputLitersPerHour) == "number" and strawSpec.outputLitersPerHour ~= 0 then
                strawSpec.outputLitersPerHour = 0
            end

            for _, specName in ipairs(outputSpecs) do
                local spec = placeable[specName]
                if spec ~= nil then
                    if type(spec.litersPerHour) == "table" then
                        for fillType, value in pairs(spec.litersPerHour) do
                            if value ~= 0 then spec.litersPerHour[fillType] = 0 end
                        end
                    elseif type(spec.litersPerHour) == "number" and spec.litersPerHour ~= 0 then
                        spec.litersPerHour = 0
                    end
                end
            end
        end
    end
end

-- Produkcja obor (jajka, mleko, welna itp.):
--  * stawki produkcji (litersPerHour) specyfikacji wyjscia ustawiamy na zero,
--  * palety: cofamy kazdy wzrost fillLevels i fillLevelsPending (spadki, np. odbior produktu, sa akceptowane).
function FarmFreeze:zeroProduction(farm, store)
    local outputSpecs = { "spec_husbandryPallets", "spec_husbandryMilk" }

    for _, placeable in pairs(getPlaceables()) do
        if placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() == farm.farmId then
            for _, specName in ipairs(outputSpecs) do
                local spec = placeable[specName]
                if spec ~= nil then
                    if type(spec.litersPerHour) == "table" then
                        for fillType, value in pairs(spec.litersPerHour) do
                            if value ~= 0 then spec.litersPerHour[fillType] = 0 end
                        end
                    elseif type(spec.litersPerHour) == "number" and spec.litersPerHour ~= 0 then
                        spec.litersPerHour = 0
                    end
                end
            end

            local pallets = placeable.spec_husbandryPallets
            if pallets ~= nil then
                local snap = store[placeable]
                if snap == nil then
                    snap = { fillLevels = {}, pending = {} }
                    for fillType, v in pairs(pallets.fillLevels or {}) do snap.fillLevels[fillType] = v end
                    for fillType, v in pairs(pallets.fillLevelsPending or {}) do snap.pending[fillType] = v end
                    store[placeable] = snap
                else
                    for _, pair in ipairs({ { "fillLevels", "fillLevels" }, { "fillLevelsPending", "pending" } }) do
                        local current = pallets[pair[1]]
                        local base = snap[pair[2]]
                        if type(current) == "table" then
                            for fillType, v in pairs(current) do
                                local old = base[fillType] or 0
                                if v > old + 0.001 then
                                    current[fillType] = old
                                elseif v < old then
                                    base[fillType] = v
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- DIAGNOSTYKA (tylko DEBUG): poziomy obornika/gnojowicy/slomy i stawki w specyfikacjach obory
function FarmFreeze:dumpManure(farm)
    for _, placeable in pairs(getPlaceables()) do
        if placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() == farm.farmId
            and placeable.spec_husbandryAnimals ~= nil then

            local levels = {}
            for _, fillType in ipairs({ FillType.MANURE, FillType.LIQUIDMANURE, FillType.STRAW }) do
                local level = 0
                if placeable.getHusbandryFillLevel ~= nil then
                    level = placeable:getHusbandryFillLevel(fillType, farm.farmId) or 0
                end
                table.insert(levels, string.format("%s=%.2f", fillTypeName(fillType), level))
            end

            local specs = {}
            for k, _ in pairs(placeable) do
                if type(k) == "string" and k:find("^spec_husbandry") then table.insert(specs, k) end
            end
            table.sort(specs)
            log("DIAG-OBORNIK '%s' (farma %d): %s | specyfikacje: %s", tostring(placeable:getName()), farm.farmId,
                table.concat(levels, ", "), table.concat(specs, ", "))

            for _, specName in ipairs({ "spec_husbandryStraw", "spec_husbandryLiquidManure", "spec_husbandryManure" }) do
                local spec = placeable[specName]
                if spec ~= nil then
                    local parts = {}
                    for k, v in pairs(spec) do
                        if type(v) == "number" then
                            table.insert(parts, string.format("%s=%.4f", tostring(k), v))
                        elseif type(v) == "table" then
                            local lname = tostring(k):lower()
                            if lname:find("liters") or lname:find("fill") or lname:find("rate") then
                                for ft, value in pairs(v) do
                                    if type(value) == "number" then
                                        table.insert(parts, string.format("%s[%s]=%.4f", tostring(k), fillTypeName(ft), value))
                                    end
                                end
                            end
                        end
                    end
                    table.sort(parts)
                    log("   %s: %s", specName, table.concat(parts, ", "))

                    local id = tostring(placeable) .. specName
                    if not self.debugKeys[id] then
                        self.debugKeys[id] = true
                        local keys = {}
                        for k, _ in pairs(spec) do table.insert(keys, tostring(k)) end
                        table.sort(keys)
                        log("   pola %s: %s", specName, table.concat(keys, ", "))
                    end
                end
            end
        end
    end
end

-- DIAGNOSTYKA (tylko DEBUG): halda / plyta obornikowa i inne obiekty powiazane z obornikiem
function FarmFreeze:dumpManureHeaps(farm)
    for _, placeable in pairs(getPlaceables()) do
        if placeable.getOwnerFarmId ~= nil and placeable:getOwnerFarmId() == farm.farmId then
            for specName, spec in pairs(placeable) do
                if type(specName) == "string" and specName:find("^spec_") and not specName:find("^spec_husbandry")
                    and specName:lower():find("manure") and type(spec) == "table" then

                    local parts = describeNumbers(spec, 2)
                    while #parts > 40 do table.remove(parts) end
                    log("DIAG-HALDA '%s' (farma %d) %s: %s", tostring(placeable:getName()), farm.farmId,
                        specName, table.concat(parts, ", "))

                    local id = tostring(placeable) .. specName
                    if not self.debugKeys[id] then
                        self.debugKeys[id] = true
                        local keys = {}
                        for k, v in pairs(spec) do table.insert(keys, tostring(k) .. "(" .. type(v) .. ")") end
                        table.sort(keys)
                        log("   pola %s: %s", specName, table.concat(keys, ", "))
                    end
                end
            end
        end
    end
end

-- DIAGNOSTYKA (tylko DEBUG, jednorazowo): systemy i klasy gry zwiazane z obornikiem
function FarmFreeze:dumpManureSystems()
    if self.debugKeys["manureSystems"] then return end
    self.debugKeys["manureSystems"] = true

    local names = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and name:lower():find("manure") and type(value) == "table" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    log("DIAG globalne klasy z 'manure': %s", table.concat(names, ", "))

    for _, name in ipairs(names) do
        local fns = {}
        for k, v in pairs(_G[name]) do
            if type(k) == "string" and type(v) == "function" then table.insert(fns, k) end
        end
        table.sort(fns)
        log("   %s: %s", name, table.concat(fns, ", "))
    end

    local ms = g_currentMission ~= nil and g_currentMission.manureSystem or nil
    if ms ~= nil then
        local keys = {}
        for k, v in pairs(ms) do
            local info = type(v)
            if type(v) == "table" then
                local n = 0
                for _ in pairs(v) do n = n + 1 end
                info = "table[" .. n .. "]"
            end
            table.insert(keys, tostring(k) .. "(" .. info .. ")")
        end
        table.sort(keys)
        log("DIAG pola g_currentMission.manureSystem: %s", table.concat(keys, ", "))
    else
        log("DIAG brak g_currentMission.manureSystem")
    end
end

-- DIAGNOSTYKA (tylko DEBUG): co 10 s raport dla zamrozonych farm
function FarmFreeze:debugReport()
    for key, count in pairs(self.debugBlocked) do
        log("DIAG zablokowano zdarzen (ost. 10 s) %s x%d", key, count)
    end
    self.debugBlocked = {}
    for key, count in pairs(self.debugUpdates) do
        log("DIAG updateOutput (ost. 10 s) %s x%d, ostatnie argumenty: %s", key, count, tostring(self.debugUpdatesLast[key]))
    end
    self.debugUpdates = {}
    self.debugUpdatesLast = {}

    self:safe("diagnostyka systemow obornika", self.dumpManureSystems)

    for farmId, isFrozen in pairs(self.frozen) do
        if isFrozen then
            local farm = g_farmManager:getFarmById(farmId)
            if farm ~= nil then
                self:safe("diagnostyka obornika", self.dumpManure, farm)
                self:safe("diagnostyka hald", self.dumpManureHeaps, farm)
            end
        end
    end
end

-- Wykonuje funkcje w pcall; blad jest logowany raz na rodzaj
function FarmFreeze:safe(name, fn, ...)
    local ok, err = pcall(fn, self, ...)
    if not ok then logError(name, err) end
end

function FarmFreeze:applyFreeze(farm)
    local s = self.snap[farm.farmId]
    if s == nil then return end

    -- Konto: cofamy wszelkie zmiany salda (koszty dzienne, odsetki, utrzymanie itp.)
    if self.settings.freezeMoney then
        local diff = s.money - farm:getBalance()
        if diff ~= 0 then
            log("Farma %d: saldo zmienilo sie o %s, przywracam", farm.farmId, tostring(-diff))
            g_currentMission:addMoney(diff, farm.farmId, MoneyType.OTHER, false, false)
        end
    else
        s.money = farm:getBalance()
    end

    -- Kredyt: bez naliczania odsetek
    if self.settings.freezeLoan then
        if farm.loan ~= s.loan then
            log("Farma %d: kredyt zmienil sie %s -> %s, przywracam", farm.farmId, tostring(s.loan), tostring(farm.loan))
            if farm.setLoan ~= nil then
                farm:setLoan(s.loan)
            else
                farm.loan = s.loan
            end
        end
    else
        s.loan = farm.loan
    end

    -- Pasza, woda, slomka i produkcja obor
    if self.settings.freezeAnimalFeed then
        self:safe("pasza", self.restoreFood, farm, s.food)
        self:safe("woda", self.restoreLevel, farm, s.water, "spec_husbandryWater", FillType.WATER)
        self:safe("sloma", self.restoreLevel, farm, s.straw, "spec_husbandryStraw", FillType.STRAW)
        self:safe("produkcja", self.zeroProduction, farm, s.pallets)
    else
        s.food, s.water, s.straw, s.pallets = {}, {}, {}, {}
    end

    -- Obornik i gnojowica (osobny przelacznik)
    if self.settings.freezeManure then
        self:safe("obornik - stawki", self.zeroManure, farm)
        self:safe("obornik", self.restoreManure, farm, s.manure)
    else
        s.manure = {}
    end

    -- Maszyny: wiek i motogodziny
    if self.settings.freezeVehicles then
        for _, vehicle in pairs(self:getVehicles()) do
            if vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farm.farmId then
                local vs = s.vehicles[vehicle]
                if vs == nil then
                    s.vehicles[vehicle] = { age = vehicle.age, operatingTime = vehicle.operatingTime }
                else
                    if vehicle.age ~= vs.age then
                        log("Serwer: wiek maszyny farmy %d zmienil sie %s -> %s, przywracam",
                            farm.farmId, tostring(vs.age), tostring(vehicle.age))
                    end
                    vehicle.age = vs.age
                    vehicle.operatingTime = vs.operatingTime
                end
            end
        end
    else
        s.vehicles = {}
    end
end

function FarmFreeze:update(dt)
    if g_currentMission == nil then
        return
    end
    if not g_currentMission:getIsServer() then
        self:safe("klient", self.updateClient, dt)
        return
    end

    self.timer = self.timer + dt
    if self.timer < self.CHECK_INTERVAL then
        return
    end
    self.timer = 0

    if self.DEBUG then
        self.debugTimer = (self.debugTimer or 0) + self.CHECK_INTERVAL
        if self.debugTimer >= 10000 then
            self.debugTimer = 0
            self:safe("raport diagnostyczny", self.debugReport)
        end
    end

    -- BankCredit moze zostac wczytany pozniej niz ten mod: ponawiamy zalozenie hooka przez pierwsza minute
    if not self.bankHooked and (self.bankTries or 0) < 60 then
        self.bankTries = (self.bankTries or 0) + 1
        self:hookBankCredit()
    end

    for _, farm in ipairs(g_farmManager:getFarms()) do
        if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID and not farm.isSpectator then
            local offline = not self:isManagerOnline(farm)
            if not self.settings.enabled then offline = false end
            local isFrozen = self.frozen[farm.farmId] == true

            if offline and not isFrozen then
                self:freeze(farm)
            elseif not offline and isFrozen then
                self:unfreeze(farm)
            end

            if self.frozen[farm.farmId] then
                self:safe("zamrazanie farmy", self.applyFreeze, farm)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Blokady zdarzen obor (starzenie, rozmnazanie, zdrowie, przeliczanie stawek zuzycia i produkcji)
--------------------------------------------------------------------------------
function FarmFreeze:hookAnimals()
    local events = { "onHourChanged", "onDayChanged", "onPeriodChanged", "onHusbandryAnimalsUpdate" }
    local classes = {
        "PlaceableHusbandryAnimals",
        "PlaceableHusbandryFood",
        "PlaceableHusbandryWater",
        "PlaceableHusbandryStraw",
        "PlaceableHusbandryMilk",
        "PlaceableHusbandryPallets",
        "PlaceableHusbandryLiquidManure"
    }

    for _, className in ipairs(classes) do
        local cls = _G[className]
        if cls ~= nil then
            for _, fn in ipairs(events) do
                if cls[fn] ~= nil then
                    local settingKey = (fn == "onHusbandryAnimalsUpdate") and "freezeAnimalFeed" or "freezeAnimalTime"
                    if className == "PlaceableHusbandryLiquidManure" and fn == "onHusbandryAnimalsUpdate" then
                        settingKey = "freezeManure"
                    end
                    cls[fn] = Utils.overwrittenFunction(cls[fn], function(self, superFunc, ...)
                        if FarmFreeze.settings[settingKey] and self.getOwnerFarmId ~= nil
                            and FarmFreeze.frozen[self:getOwnerFarmId()] then
                            if FarmFreeze.DEBUG then
                                local blockedKey = className .. "." .. fn
                                FarmFreeze.debugBlocked[blockedKey] = (FarmFreeze.debugBlocked[blockedKey] or 0) + 1
                            end
                            return
                        end
                        return superFunc(self, ...)
                    end)
                end
            end
        end
    end
end

-- Obornik powstaje w specyfikacji slomy (outputLitersPerHour). Gra przelicza te stawke przy kazdym
-- zdarzeniu onHusbandryAnimalsUpdate, wiec po jego wykonaniu zerujemy ja ponownie dla zamrozonej farmy.
function FarmFreeze:hookStrawManure()
    local cls = _G.PlaceableHusbandryStraw
    if cls == nil or cls.onHusbandryAnimalsUpdate == nil then
        return
    end
    cls.onHusbandryAnimalsUpdate = Utils.overwrittenFunction(cls.onHusbandryAnimalsUpdate, function(self, superFunc, ...)
        local result = superFunc(self, ...)
        if FarmFreeze.settings.freezeManure and self.getOwnerFarmId ~= nil
            and FarmFreeze.frozen[self:getOwnerFarmId()] then
            local spec = self.spec_husbandryStraw
            if spec ~= nil and type(spec.outputLitersPerHour) == "number" then
                spec.outputLitersPerHour = 0
            end
        end
        return result
    end)
end

-- Zgodnosc z modem Bank & Credit (FS25_BankCredit): ten mod zastepuje standardowe kredyty wlasnymi
-- i co miesiac pobiera rate oraz jednoczesnie zmniejsza saldo kredytu.
-- Zasady dla zamrozonej farmy:
--  * rata / odsetki / prowizja sa pomijane w calosci, gdy wlaczone jest "Zamrazaj kredyty" LUB
--    "Zamrazaj konto bankowe" (przy zamrozonym koncie pieniadze by wrocily, a saldo kredytu juz by
--    zmalalo, czyli kredyt splacalby sie za darmo),
--  * reczne operacje na kredycie (nowy kredyt, splata, wyplata z linii odnawialnej) sa blokowane
--    z tego samego powodu; zamkniecie linii odnawialnej (bez ruchu pieniedzy) tylko przy "Zamrazaj kredyty".
function FarmFreeze:isLoanFrozen(farmId, includesMoney)
    if farmId == nil or not self.frozen[farmId] then
        return false
    end
    if includesMoney then
        return self.settings.freezeLoan or self.settings.freezeMoney
    end
    return self.settings.freezeLoan
end

-- Szuka klasy LoanService z modu Bank & Credit. W FS25 kazdy mod moze miec wlasne srodowisko globalne,
-- wiec zwykla zmienna globalna LoanService bywa z innego moda niewidoczna. Probujemy kolejno:
--  1) zmienna globalna, 2) srodowisko moda (_G["FS25_BankCredit"]), 3) metatabele instancji uslugi
--  (g_currentMission.bankManager.loanService, tworzona dopiero po starcie mapy).
function FarmFreeze:findLoanServiceClass()
    if type(LoanService) == "table" then
        return LoanService, "globalna"
    end
    local env = _G["FS25_BankCredit"]
    if type(env) == "table" and type(env.LoanService) == "table" then
        return env.LoanService, "srodowisko moda"
    end
    local manager = g_currentMission ~= nil and g_currentMission.bankManager or nil
    local instance = manager ~= nil and manager.loanService or nil
    if instance ~= nil then
        local mt = getmetatable(instance)
        if type(mt) == "table" then
            if type(mt.__index) == "table" then
                return mt.__index, "instancja uslugi"
            end
            return mt, "instancja uslugi"
        end
    end
    return nil
end

function FarmFreeze:hookBankCredit()
    if self.bankHooked then
        return true
    end
    local cls = self:findLoanServiceClass()
    if cls == nil or type(cls.collectMonthlyPayment) ~= "function" then
        return false
    end

    cls.collectMonthlyPayment = Utils.overwrittenFunction(cls.collectMonthlyPayment,
        function(self, superFunc, loan, ...)
            if loan ~= nil and FarmFreeze:isLoanFrozen(loan.farmId, true) then
                log("BankCredit: pominieto rate kredytu #%s farmy %s", tostring(loan.id), tostring(loan.farmId))
                return
            end
            return superFunc(self, loan, ...)
        end)

    -- operacje, ktorych pierwszym argumentem jest kredyt
    local function guardByLoan(name, defaultResult, includesMoney)
        local original = cls[name]
        if type(original) ~= "function" then return end
        cls[name] = Utils.overwrittenFunction(original, function(self, superFunc, loan, ...)
            if loan ~= nil and FarmFreeze:isLoanFrozen(loan.farmId, includesMoney) then
                log("BankCredit: zablokowano %s dla zamrozonej farmy %s", name, tostring(loan.farmId))
                return defaultResult
            end
            return superFunc(self, loan, ...)
        end)
    end
    guardByLoan("earlyRepayment", 0, true)
    guardByLoan("repayRevolving", nil, true)
    guardByLoan("drawRevolving", nil, true)
    guardByLoan("closeRevolving", nil, false)

    -- nowy kredyt: pierwszym argumentem jest farmId
    if type(cls.disburse) == "function" then
        cls.disburse = Utils.overwrittenFunction(cls.disburse,
            function(self, superFunc, farmId, ...)
                if FarmFreeze:isLoanFrozen(farmId, true) then
                    log("BankCredit: zablokowano nowy kredyt dla zamrozonej farmy %s", tostring(farmId))
                    return nil
                end
                return superFunc(self, farmId, ...)
            end)
    end

    self.bankHooked = true
    local _, method = self:findLoanServiceClass()
    print(string.format("[FarmFreeze] Zgodnosc z Bank & Credit: aktywna (%s).", tostring(method)))
    return true
end

function FarmFreeze:loadMap()
    if g_currentMission:getIsServer() then
        self:loadSettings()
        self:hookAnimals()
        self:hookStrawManure()
        self:hookBankCredit()
    end
    print(string.format("[FarmFreeze] Mod zaladowany (wersja %s).", self.VERSION))
end

--------------------------------------------------------------------------------
-- updateOutput przeklada stawki produkcji na realne ilosci (jajka, mleko...). Wrappery zakladamy przy
-- wczytywaniu pliku (przed finalizacja typow obor). Dla farm zamrozonych zerujemy czynniki produkcji
-- (productionFactor i globalProductionFactor), ale lancuch wywolan zostaje nienaruszony.
--------------------------------------------------------------------------------
local unpackFn = unpack or table.unpack

local PRODUCTION_CLASSES = {
    PlaceableHusbandryPallets = "freezeAnimalFeed",
    PlaceableHusbandryMilk = "freezeAnimalFeed",
    PlaceableHusbandryLiquidManure = "freezeManure",
    PlaceableHusbandryManure = "freezeManure",
    PlaceableHusbandryStraw = "freezeManure"   -- obornik powstaje w specyfikacji slomy
}

local function wrapUpdateOutput(cls, className)
    local settingKey = PRODUCTION_CLASSES[className]
    if cls == nil or type(cls.updateOutput) ~= "function" then
        return
    end
    if settingKey == nil and not FarmFreeze.DEBUG then
        return
    end

    cls.updateOutput = Utils.overwrittenFunction(cls.updateOutput, function(self, superFunc, ...)
        local farmId = (self.getOwnerFarmId ~= nil) and self:getOwnerFarmId() or nil
        local isFrozen = farmId ~= nil and FarmFreeze.frozen[farmId] == true

        if FarmFreeze.DEBUG and isFrozen then
            local nums = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "number" then table.insert(nums, string.format("%.3f", v)) end
            end
            local okN, nm = pcall(function() return self:getName() end)
            local zeroed = (settingKey ~= nil and FarmFreeze.settings[settingKey]) and " [czynniki zerowane]" or " [bez zmian]"
            local key = string.format("'%s' %s%s", okN and tostring(nm) or "?", className, zeroed)
            FarmFreeze.debugUpdates[key] = (FarmFreeze.debugUpdates[key] or 0) + 1
            FarmFreeze.debugUpdatesLast[key] = table.concat(nums, "/")
        end

        if settingKey ~= nil and isFrozen and FarmFreeze.settings[settingKey] then
            local n = select("#", ...)
            local args = { ... }
            -- argumenty to (foodFactor, productionFactor, globalProductionFactor),
            -- ewentualnie z lancuchem superFunc na poczatku
            local offset = (type(args[1]) == "function") and 1 or 0
            if type(args[offset + 2]) == "number" then args[offset + 2] = 0 end
            if type(args[offset + 3]) == "number" then args[offset + 3] = 0 end
            return superFunc(self, unpackFn(args, 1, n))
        end
        return superFunc(self, ...)
    end)
end

pcall(function()
    for name, cls in pairs(_G) do
        if type(name) == "string" and name:find("^PlaceableHusbandry") and type(cls) == "table" then
            wrapUpdateOutput(cls, name)
        end
    end
end)

addModEventListener(FarmFreeze)
