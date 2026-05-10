-- ElvUI M+ Loot localization.
-- Loaded before ElvUI_MPlusLoot.lua; contains no loot, UI, slash command, or font logic.

local addon = _G.ElvUIMPlusLoot or {}
_G.ElvUIMPlusLoot = addon

local CLIENT_LOCALE = GetLocale()

local LOCALES = {
    deDE = {
        title = "Mythic+ Endkisten-Loot",
        headerItem = "Gegenstand",
        headerIlvl = "GS",
        headerTrack = "Aufwertung",
        headerLooter = "Spieler",
        whisper = "Flüstern",
        noLoot = "Noch kein Endkisten-Loot erkannt.",
        debugEnabled = "Debug-Modus aktiviert.",
        debugDisabled = "Debug-Modus deaktiviert.",
        loaded = "geladen. /mploot oder /mplusloot zum Öffnen.",
        testModeActive = "Testmodus aktiv. Nutze /mplootitem oder /mplootfake für Testitems.",
        noTestItems = "Keine angelegten Testitems gefunden.",
        noFakeItems = "Keine angelegten Items für /mplootfake gefunden.",
        fakeLootSimulated = "%d Fake-Lootmeldungen simuliert.",
        testItemsSimulated = "%d zufällige Testitems simuliert.",
        whisperCombatBlocked = "Flüstern kann während des Kampfes nicht geöffnet werden.",
        keystoneLootTierNice = "Nett",
        keystoneLootTierMust = "Wichtig",
        keystoneLootTierBiS = "BiS",
        keystoneLootWishlist = "KeystoneLoot-Wunschitem",
        keystoneLootWishlistTooltip = "Auf KeystoneLoot-Wunschliste",
    },
    enUS = {
        title = "Mythic+ End Chest Loot",
        headerItem = "Item",
        headerIlvl = "iLvl",
        headerTrack = "Track",
        headerLooter = "Looter",
        whisper = "Whisper",
        noLoot = "No end chest loot detected yet.",
        debugEnabled = "Debug mode enabled.",
        debugDisabled = "Debug mode disabled.",
        loaded = "loaded. Use /mploot or /mplusloot to open.",
        testModeActive = "Test mode active. Use /mplootitem or /mplootfake for test items.",
        noTestItems = "No equipped test items found.",
        noFakeItems = "No equipped items found for /mplootfake.",
        fakeLootSimulated = "%d fake loot messages simulated.",
        testItemsSimulated = "%d random test items simulated.",
        whisperCombatBlocked = "Cannot open whisper during combat.",
        keystoneLootTierNice = "Nice",
        keystoneLootTierMust = "Must",
        keystoneLootTierBiS = "BiS",
        keystoneLootWishlist = "KeystoneLoot wishlist item",
        keystoneLootWishlistTooltip = "On KeystoneLoot wishlist",
    },
    ruRU = {
        title = "Добыча с сундука в конце M+ подземелья",
        headerItem = "Предмет",
        headerIlvl = "Уровень предмета",
        headerTrack = "Отслеживание",
        headerLooter = "Кто получил",
        whisper = "Шёпот",
        noLoot = "Добыча из сундука пока не обнаружена.",
        debugEnabled = "Режим отладки вкл.",
        debugDisabled = "Режим отладки выкл.",
        loaded = "lзагружен. Используйте /mploot или /mplusloot, чтобы открыть.",
        testModeActive = "Тестовый режим активен. Используйте /mplootitem или /mplootfake для тестовых предметов.",
        noTestItems = "Не найдено экипированных тестовых предметов.",
        noFakeItems = "Не найдено экипированных предметов для /mplootfake.",
        fakeLootSimulated = "Смоделировано %d фальшивых сообщений о добыче.",
        testItemsSimulated = "Смоделировано %d случайных тестовых предметов.",
        whisperCombatBlocked = "Невозможно шептать во время боя.",
        keystoneLootTierNice = "Желательно",
        keystoneLootTierMust = "Обязательно",
        keystoneLootTierBiS = "БиС",
        keystoneLootWishlist = "Предмет из списка желаний KeystoneLoot",
        keystoneLootWishlistTooltip = "В списке желаний KeystoneLoot",
    },
}

local function T(key)
    local localeTable = LOCALES[CLIENT_LOCALE] or LOCALES.enUS
    return localeTable[key] or LOCALES.enUS[key] or key
end

addon.Locale = {
    CLIENT_LOCALE = CLIENT_LOCALE,
    LOCALES = LOCALES,
    T = T,
}
addon.T = T
