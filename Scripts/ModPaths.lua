MOD_PATH = "$CONTENT_DATA/"
LAYOUTS_PATH = "$CONTENT_DATA/Gui/Layouts/"

local Localization = {}
local cache = {}

local function getLanguage()
    if sm and sm.gui and sm.gui.getCurrentLanguage then
        if sm.gui.getCurrentLanguage() == "Russian" then
            return "Russian"
        end
    end
    return "English"
end

local function loadLanguage(language)
    if cache[language] ~= nil then
        return cache[language]
    end

    if not sm or not sm.json or not sm.json.open then
        cache[language] = {}
        return cache[language]
    end

    local paths = {
        "$CONTENT_DATA/Gui/Language/" .. language .. "/PlaneConstruct.json",
        "$MOD_DATA/Gui/Language/" .. language .. "/PlaneConstruct.json"
    }
    for _, path in ipairs(paths) do
        local ok, data = pcall(sm.json.open, path)
        if ok and type(data) == "table" then
            cache[language] = data
            return data
        end
    end

    cache[language] = {}
    return cache[language]
end

function Localization.get(key, ...)
    local language = getLanguage()
    local localized = loadLanguage(language)[key]

    if localized == nil and language ~= "English" then
        localized = loadLanguage("English")[key]
    end

    localized = localized or key

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, localized, ...)
        if ok then
            return formatted
        end
    end

    return localized
end

function Localization.layout(name)
    if getLanguage() == "Russian" then
        return "$CONTENT_DATA/Gui/Layouts/Russian/" .. name
    end
    return "$CONTENT_DATA/Gui/Layouts/" .. name
end

PlaneConstructLocalization = Localization
