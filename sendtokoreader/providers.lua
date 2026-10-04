local gettext = require("sendtokoreader/i18n")
local function N_(message) return message end
local Providers = {
    {id="icloud",label=N_("iCloud"),host="imap.mail.me.com",credential=N_("App password"),
        help=N_("Enable two-factor authentication for your Apple Account, then create an app-specific password at account.apple.com. Enter your full iCloud Mail address and that password. Your regular Apple Account password will not work.")},
    {id="gmail",label=N_("Google (Gmail)"),host="imap.gmail.com",credential=N_("App password"),
        help=N_("Enable 2-Step Verification in your Google Account, then create an app password at myaccount.google.com/apppasswords. Use your full email address. If app passwords are unavailable or your administrator requires OAuth, this account is not supported yet.")},
    {id="yahoo",label=N_("Yahoo Mail"),host="imap.mail.yahoo.com",credential=N_("App password"),
        help=N_("In Yahoo Account Security, generate a third-party app password. Enter your full email address and that password. If Yahoo does not allow your account to generate app passwords, this account is not supported yet.")},
    {id="aol",label=N_("AOL Mail"),host="imap.aol.com",credential=N_("App password"),
        help=N_("In AOL Account Security, generate a third-party app password. Enter your full email address and that password. If AOL does not allow your account to generate app passwords, this account is not supported yet.")},
    {id="netease",label=N_("163 Mail"),host="imap.163.com",credential=N_("Authorization code"),
        help=N_("In 163 webmail settings, enable IMAP/SMTP and generate a client authorization code. Enter your full email address and the authorization code, not your webmail password.")},
    {id="netease126",label=N_("126 Mail"),host="imap.126.com",credential=N_("Authorization code"),
        help=N_("In 126 webmail settings, enable IMAP/SMTP and generate a client authorization code. Enter your full email address and the authorization code, not your webmail password.")},
    {id="qq",label=N_("QQ Mail"),host="imap.qq.com",credential=N_("Authorization code"),
        help=N_("In QQ Mail settings, enable IMAP/SMTP and generate an authorization code. Enter your full email address and the authorization code, not your QQ password.")},
    {id="custom",label=N_("Other mailbox"),host="",credential=N_("Password or app password"),
        help=N_("Ask your provider for its IMAP hostname, TLS port and password or app password. Only implicit TLS with password authentication is supported. Self-hosted Exchange works only if its administrator enables compatible IMAP access. OAuth, Exchange Web Services and ActiveSync are not supported.")},
}

function Providers.get(id)
    for _, provider in ipairs(Providers) do if provider.id == id then return provider end end
    return Providers[#Providers]
end

function Providers.select(draft, id)
    local provider = Providers.get(id)
    if draft.provider ~= provider.id then
        draft.password = "" -- Never reuse credentials with a different provider.
        draft.host, draft.port = provider.host, 993
        draft.ca_file = nil
    end
    draft.provider = provider.id
end

function Providers.oauthNotice()
    return gettext("Outlook.com and Exchange Online require OAuth sign-in, which is not supported in this version. App passwords do not replace OAuth for these services. Use another mailbox for now. For self-hosted Exchange, ask your administrator whether password-based IMAP over TLS is available, then choose Other mailbox.")
end

return Providers
