-- Reuse KOReader's MO reader; keep the plugin's translations in a separate table.
local core = require("gettext")
local directory = assert(debug.getinfo(1,"S").source:match("^@(.+)/sendtokoreader/i18n.lua$"))
local loaded, translation

return function(message)
    local language = G_reader_settings and G_reader_settings:readSetting("language") or core.current_lang
    language = (language or "en_US"):match("^[%w_-]+") or "en_US"
    if language ~= loaded then
        -- loadMO is synchronous and only changes these three fields. Restore even
        -- on failure, so KOReader's own catalog and plural rules remain untouched.
        local old_translation, old_context, old_plural = core.translation, core.context, rawget(core,"getPlural")
        core.translation, core.context = {}, {}
        local ok, found = pcall(core.loadMO,directory .. "/l10n/" .. language .. "/sendtokoreader.mo")
        translation = ok and found and core.translation or {}
        core.translation, core.context, core.getPlural = old_translation, old_context, old_plural
        loaded = language
    end
    return translation[message] or core.wrapUntranslated(message)
end
