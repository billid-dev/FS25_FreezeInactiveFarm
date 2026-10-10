-- FarmFreezeGui: menu w Ustawieniach gry + synchronizacja ustawien w multiplayerze.
-- Zmieniac ustawienia moze tylko admin serwera (master user). Reszta widzi je jako nieaktywne.

local function log(...)
    if FarmFreeze.DEBUG then
        print("[FarmFreeze] " .. string.format(...))
    end
end

-- Bledy menu wypisujemy zawsze (raz na rodzaj), zeby dalo sie je zgloszic
local errorSeen = {}
local function logError(message)
    if not errorSeen[message] then
        errorSeen[message] = true
        print("[FarmFreeze] BLAD menu: " .. tostring(message))
    end
end

--------------------------------------------------------------------------------
-- Event synchronizujacy ustawienia
--------------------------------------------------------------------------------
FarmFreezeSettingsEvent = {}
local FarmFreezeSettingsEvent_mt = Class(FarmFreezeSettingsEvent, Event)
InitEventClass(FarmFreezeSettingsEvent, "FarmFreezeSettingsEvent")

function FarmFreezeSettingsEvent.emptyNew()
    return Event.new(FarmFreezeSettingsEvent_mt)
end

function FarmFreezeSettingsEvent.new(settings)
    local self = FarmFreezeSettingsEvent.emptyNew()
    self.settings = settings
    return self
end

function FarmFreezeSettingsEvent:writeStream(streamId, connection)
    for _, key in ipairs(FarmFreeze.SETTING_KEYS) do
        streamWriteBool(streamId, self.settings[key] == true)
    end
end

function FarmFreezeSettingsEvent:readStream(streamId, connection)
    self.settings = {}
    for _, key in ipairs(FarmFreeze.SETTING_KEYS) do
        self.settings[key] = streamReadBool(streamId)
    end
    self:run(connection)
end

function FarmFreezeSettingsEvent:run(connection)
    if not connection:getIsServer() then
        -- Serwer dostal zmiane od klienta: sprawdz uprawnienia admina
        local allowed = false
        local ok, user = pcall(function()
            return g_currentMission.userManager:getUserByConnection(connection)
        end)
        if ok and user ~= nil and user.getIsMasterUser ~= nil then
            allowed = user:getIsMasterUser()
        end
        if not allowed then
            log("Odrzucono zmiane ustawien od uzytkownika bez uprawnien admina")
            return
        end
        FarmFreeze:applySettings(self.settings)
        FarmFreeze:saveSettings()
        g_server:broadcastEvent(FarmFreezeSettingsEvent.new(FarmFreeze.settings))
    else
        -- Klient dostal aktualne ustawienia od serwera
        FarmFreeze:applySettings(self.settings)
    end
end

-- Wyslij aktualne ustawienia dolaczajacemu graczowi
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
    function(self, connection, user, farm)
        connection:sendEvent(FarmFreezeSettingsEvent.new(FarmFreeze.settings))
    end)

--------------------------------------------------------------------------------
-- Menu w Ustawieniach gry
--------------------------------------------------------------------------------

-- Teksty menu: polskie, gdy gra ma jezyk polski, w kazdym innym przypadku angielskie.
local TEXTS = {
    en = {
        header = "Farm Freeze",
        off = "Off",
        on = "On",
        title_enabled = "Farm Freeze: mod enabled",
        tip_enabled = "Farm Freeze: mod enabled - master switch of the mod. When it is off, no farm is frozen, regardless of the other settings below.",
        title_freezeMoney = "Freeze bank balance",
        tip_freezeMoney = "Freeze bank balance - controls whether, while a farm's managers are offline in multiplayer, the farm's bank balance is frozen (income, costs and fees do not change the balance).",
        title_freezeLoan = "Freeze loans",
        tip_freezeLoan = "Freeze loans - controls whether, while a farm's managers are offline in multiplayer, the farm's loan is frozen (interest and payments are not charged, also in the Bank & Credit mod).",
        title_freezeVehicles = "Freeze vehicle age",
        tip_freezeVehicles = "Freeze vehicle age - controls whether, while a farm's managers are offline in multiplayer, the age and operating hours of the farm's vehicles are frozen.",
        title_freezeAnimalTime = "Freeze animal time",
        tip_freezeAnimalTime = "Freeze animal time - controls whether, while a farm's managers are offline in multiplayer, time stops for the farm's animals (aging, reproduction and health changes).",
        title_freezeAnimalFeed = "Freeze feed, water and husbandry production",
        tip_freezeAnimalFeed = "Freeze feed, water and husbandry production - controls whether, while a farm's managers are offline in multiplayer, the consumption of feed, water and straw in the farm's husbandries and the production of milk, eggs and wool are stopped.",
        title_freezeManure = "Freeze manure and slurry",
        tip_freezeManure = "Freeze manure and slurry - controls whether, while a farm's managers are offline in multiplayer, the production of manure and slurry in the farm's husbandries is stopped (their amount in the husbandry does not increase)."
    },
    pl = {
        header = "Farm Freeze",
        off = "Wyłączone",
        on = "Włączone",
        title_enabled = "Farm Freeze: mod aktywny",
        tip_enabled = "Farm Freeze: mod aktywny - główny włącznik moda. Gdy jest wyłączony, żadne gospodarstwo nie jest zamrażane, niezależnie od pozostałych ustawień poniżej.",
        title_freezeMoney = "Zamrażaj konto bankowe",
        tip_freezeMoney = "Zamrażaj konto bankowe - ta opcja służy do sterowania, czy podczas nieobecności kierownika gospodarstwa w trybie multiplayer ma zostać zamrożony stan konta bankowego tego gospodarstwa (przychody, koszty i opłaty nie zmieniają salda).",
        title_freezeLoan = "Zamrażaj kredyty",
        tip_freezeLoan = "Zamrażaj kredyty - ta opcja służy do sterowania, czy podczas nieobecności kierownika gospodarstwa w trybie multiplayer ma zostać zamrożona wysokość kredytu tego gospodarstwa (odsetki i raty nie są naliczane, także w modzie Bank & Credit).",
        title_freezeVehicles = "Zamrażaj wiek maszyn",
        tip_freezeVehicles = "Zamrażaj wiek maszyn - ta opcja służy do sterowania, czy podczas nieobecności kierownika gospodarstwa w trybie multiplayer ma zostać zamrożony wiek i liczba przepracowanych motogodzin maszyn należących do tego gospodarstwa.",
        title_freezeAnimalTime = "Zamrażaj czas zwierząt",
        tip_freezeAnimalTime = "Zamrażaj czas zwierząt - ta opcja służy do sterowania, czy podczas nieobecności kierownika gospodarstwa w trybie multiplayer ma zostać zatrzymany upływ czasu dla zwierząt tego gospodarstwa (starzenie się, rozmnażanie i zmiany zdrowia).",
        title_freezeAnimalFeed = "Zamrażaj pasze, wodę i produkcję obór",
        tip_freezeAnimalFeed = "Zamrażaj pasze, wodę i produkcję obór - ta opcja służy do sterowania, czy podczas nieobecności kierownika gospodarstwa w trybie multiplayer ma zostać zatrzymane zużycie paszy, wody i słomy w oborach tego gospodarstwa oraz produkcja mleka, jajek i wełny.",
        title_freezeManure = "Zamrażaj obornik i gnojowicę",
        tip_freezeManure = "Zamrażaj obornik i gnojowicę - ta opcja służy do sterowania, czy podczas nieobecności kierownika gospodarstwa w trybie multiplayer ma zostać zatrzymana produkcja obornika i gnojowicy w oborach tego gospodarstwa (ich ilość w oborze nie rośnie)."
    }
}

local function currentLanguage()
    local ok, language = pcall(function() return g_languageShort end)
    if ok and language == "pl" then
        return "pl"
    end
    return "en"
end

local function T(key)
    local texts = TEXTS[currentLanguage()] or TEXTS.en
    return texts[key] or TEXTS.en[key] or key
end

FarmFreezeGui = {}

FarmFreezeGui.ENTRIES = {
    { key = "enabled" },
    { key = "freezeMoney" },
    { key = "freezeLoan" },
    { key = "freezeVehicles" },
    { key = "freezeAnimalTime" },
    { key = "freezeAnimalFeed" },
    { key = "freezeManure" }
}

-- Szuka w ukladzie gotowego wiersza z przelacznikiem Tak/Nie oraz naglowka sekcji
local function findTemplates(layout)
    local rowTemplate, headerTemplate
    for _, child in ipairs(layout.elements) do
        if rowTemplate == nil and child.elements ~= nil then
            for _, sub in ipairs(child.elements) do
                if sub.setIsChecked ~= nil then
                    rowTemplate = child
                    break
                end
            end
        end
        if headerTemplate == nil and child.setText ~= nil and (child.elements == nil or #child.elements == 0)
            and type(child.profile) == "string" and child.profile:lower():find("header") then
            headerTemplate = child
        end
    end
    return rowTemplate, headerTemplate
end

FarmFreezeGui.updating = false -- true, gdy menu samo ustawia przelaczniki (to nie jest klikniecie)

function FarmFreezeGui.onOptionChanged(self, state, element)
    local key = element ~= nil and element.farmFreezeKey or nil
    if key == nil then return end
    if FarmFreezeGui.updating then return end

    local wanted = (state == BinaryOptionElement.STATE_RIGHT)
    if FarmFreeze.settings[key] == wanted then return end
    log("Menu: klikniecie %s -> %s", key, tostring(wanted))

    local newSettings = {}
    for k, v in pairs(FarmFreeze.settings) do newSettings[k] = v end
    newSettings[key] = (state == BinaryOptionElement.STATE_RIGHT)

    if g_currentMission:getIsServer() then
        FarmFreeze:applySettings(newSettings)
        FarmFreeze:saveSettings()
        g_server:broadcastEvent(FarmFreezeSettingsEvent.new(FarmFreeze.settings))
    else
        g_client:getServerConnection():sendEvent(FarmFreezeSettingsEvent.new(newSettings))
    end
end

function FarmFreezeGui.refresh(frame)
    local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser == true
    FarmFreezeGui.updating = true
    for _, opt in ipairs(frame.farmFreezeOptions or {}) do
        FarmFreezeGui.setOptionState(opt, FarmFreeze.settings[opt.farmFreezeKey] == true)
        opt:setDisabled(not isAdmin)
    end
    FarmFreezeGui.updating = false
    log("Menu odswiezone: wlaczony=%s kasa=%s kredyt=%s maszyny=%s zwierzeta-czas=%s zwierzeta-pasza=%s (admin=%s)",
        tostring(FarmFreeze.settings.enabled), tostring(FarmFreeze.settings.freezeMoney),
        tostring(FarmFreeze.settings.freezeLoan), tostring(FarmFreeze.settings.freezeVehicles),
        tostring(FarmFreeze.settings.freezeAnimalTime), tostring(FarmFreeze.settings.freezeAnimalFeed),
        tostring(isAdmin))
end

-- Opis ustawienia (wyswietlany po prawej, gdy opcja jest zaznaczona) to tekst dziecka opcji.
-- Szukamy go po nazwie, po profilu, a w ostatecznosci bierzemy pierwsze dziecko z setText.
function FarmFreezeGui.setTooltip(option, entry)
    local found = nil
    for _, sub in ipairs(option.elements or {}) do
        local profile = type(sub.profile) == "string" and sub.profile:lower() or ""
        if sub.setText ~= nil and (sub.name == "toolTip" or profile:find("tooltip")) then
            found = sub
            break
        end
    end
    if found == nil and option.elements ~= nil and option.elements[1] ~= nil
        and option.elements[1].setText ~= nil then
        found = option.elements[1]
    end

    local tip = T("tip_" .. entry.key)
    option.toolTipText = tip
    if found ~= nil then
        found:setText(tip)
        log("Opis ustawiony dla %s (element: %s)", entry.key, tostring(found.name or found.profile))
    else
        log("UWAGA: nie znaleziono elementu opisu dla %s", entry.key)
    end
end

-- Ustawia przelacznik na wlaczony/wylaczony i sprawdza, czy stan faktycznie sie zmienil
function FarmFreezeGui.setOptionState(opt, on)
    local wanted = on and BinaryOptionElement.STATE_RIGHT or BinaryOptionElement.STATE_LEFT
    if opt.setIsChecked ~= nil then
        opt:setIsChecked(on, true)
    end
    if opt.getState ~= nil and opt:getState() ~= wanted and opt.setState ~= nil then
        opt:setState(wanted, false)
    end
    local actual = opt.getState ~= nil and opt:getState() or "?"
    log("Opcja %s: oczekiwany stan=%s, faktyczny=%s", tostring(opt.farmFreezeKey), tostring(wanted), tostring(actual))
end

function FarmFreezeGui.build(frame)
    local layout = frame.gameSettingsLayout or frame.settingsLayout or frame.generalSettingsLayout
    if layout == nil then
        logError("nie znaleziono ukladu ustawien w InGameMenuSettingsFrame - menu niedostepne")
        return
    end

    local rowTemplate, headerTemplate = findTemplates(layout)
    if rowTemplate == nil then
        logError("nie znaleziono wzoru wiersza ustawien - menu niedostepne")
        return
    end

    if headerTemplate ~= nil then
        local header = headerTemplate:clone(layout)
        header:setText(T("header"))
    end

    frame.farmFreezeOptions = {}
    for _, entry in ipairs(FarmFreezeGui.ENTRIES) do
        local row = rowTemplate:clone(layout)
        local option, title
        for _, sub in ipairs(row.elements) do
            if sub.setIsChecked ~= nil then
                option = sub
            elseif sub.setText ~= nil and title == nil then
                title = sub
            end
        end
        if option ~= nil then
            option.id = nil
            option.farmFreezeKey = entry.key
            option.target = FarmFreezeGui
            option.onClickCallback = FarmFreezeGui.onOptionChanged
            if option.setTexts ~= nil then
                option:setTexts({ T("off"), T("on") })
            end
            if title ~= nil then title:setText(T("title_" .. entry.key)) end
            FarmFreezeGui.setTooltip(option, entry)
            table.insert(frame.farmFreezeOptions, option)
        end
    end

    layout:invalidateLayout()
    log("Menu Farm Freeze dodane do ustawien (%d opcji)", #frame.farmFreezeOptions)
end

InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function(self)
    if not self.farmFreezeBuilt then
        self.farmFreezeBuilt = true
        FarmFreezeGui.updating = true
        local ok, err = pcall(FarmFreezeGui.build, self)
        FarmFreezeGui.updating = false
        if not ok then logError("budowanie menu: " .. tostring(err)) end
    end
    local ok, err = pcall(FarmFreezeGui.refresh, self)
    if not ok then logError("odswiezanie menu: " .. tostring(err)) end
end)
