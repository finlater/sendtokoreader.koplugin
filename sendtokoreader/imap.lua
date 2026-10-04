local gettext = require("sendtokoreader/i18n")
local socket = require("socket")
local ssl = require("ssl")
local Mail = require("sendtokoreader/mail")
local IMAP = {}
IMAP.__index = IMAP

local function fail(message) error(message,0) end

function IMAP.hostnameMatches(host, name)
    if type(name) ~= "string" or name:find("%z") then return false end
    host, name = host:lower():gsub("%.$", ""), name:lower():gsub("%.$", "")
    if host == name then return true end
    -- Only a complete left-most DNS label may be a wildcard; never match IP literals.
    local suffix = name:match("^%*%.([^*]+%.[^*]+)$")
    return suffix ~= nil and not host:match("^[%d.]+$") and host:match("^[^.]+%.(.+)$") == suffix
end

local function verifyHost(conn, host)
    local cert = conn:getpeercertificate()
    if not cert then fail(gettext("The server did not provide a TLS certificate.")) end
    local san = cert:extensions()["2.5.29.17"] or {}
    local names = host:match("^[%d.]+$") and san.iPAddress or san.dNSName
    for _, name in ipairs(names or {}) do if IMAP.hostnameMatches(host,name) then return end end
    fail(gettext("The TLS certificate does not match the mail server name."))
end

function IMAP.validate(config)
    assert(type(config) == "table", gettext("Set up a mailbox first."))
    assert(type(config.host) == "string" and config.host:match("^[%w.-]+$") and #config.host < 254,
        gettext("Enter the IMAP hostname without a URL or port."))
    assert(type(config.port) == "number" and config.port >= 1 and config.port <= 65535 and config.port%1 == 0, gettext("Invalid port"))
    assert(type(config.username) == "string" and config.username ~= "", gettext("Enter your email address."))
    assert(type(config.password) == "string" and config.password ~= "", gettext("Enter your password or app password."))
    Mail.quote(config.username); Mail.quote(config.password)
end

function IMAP.connect(config)
    IMAP.validate(config)
    local self = setmetatable({tag=0},IMAP)
    local ok, err = pcall(function()
        self.conn = assert(socket.tcp(),gettext("Could not initialize a secure connection."))
        self.conn:settimeout(20)
        assert(self.conn:connect(config.host,config.port), gettext("Could not connect to the mail server."))
        local params = {
            mode="client", protocol="any", verify="peer",
            options={"all","no_sslv2","no_sslv3","no_tlsv1","no_tlsv1_1"},
            cafile=config.ca_file or "data/ca-bundle.crt",
        }
        local secured = ssl.wrap(self.conn,params)
        if not secured then fail(gettext("Could not initialize a secure connection.")) end
        self.conn = secured
        self.conn:settimeout(20)
        self.conn:sni(config.host)
        local handshake = self.conn:dohandshake()
        if not handshake then fail(gettext("TLS verification failed. Check the server name, system date and CA certificates.")) end
        verifyHost(self.conn,config.host)
        local greeting = self:line()
        if not greeting:match("^%* OK") then fail(gettext("The mail server did not return an IMAP ready response.")) end
        -- Do not include command text or the server's authentication response in errors/logs.
        self:command("LOGIN " .. Mail.quote(config.username) .. " " .. Mail.quote(config.password), gettext("Sign-in failed. Check IMAP access and your password or app password."))
        local caps = table.concat(self:command("CAPABILITY")," "):upper()
        if (" " .. caps .. " "):find(" ID ",1,true) then
            self:command('ID ("name" "sendtokoreader" "version" "0.1.0" "vendor" "KOReader plugin")')
        end
        local lines = self:command("EXAMINE INBOX", gettext("Could not open the inbox in read-only mode."))
        for _, line in ipairs(lines) do
            self.validity = tonumber(line:match("%[UIDVALIDITY (%d+)%]")) or self.validity
            self.next_uid = tonumber(line:match("%[UIDNEXT (%d+)%]")) or self.next_uid
        end
        assert(self.validity, gettext("The server did not provide UIDVALIDITY. Download history cannot be tracked safely."))
    end)
    if not ok then self:close(); return nil, tostring(err) end
    return self
end

function IMAP:close()
    if self.conn then pcall(self.conn.close,self.conn); self.conn=nil end
end

function IMAP:line()
    local line = self.conn:receive("*l")
    if not line then fail(gettext("The mail connection was interrupted or timed out.")) end
    if #line > 1024*1024 then fail(gettext("The mail server response is too large.")) end
    return line
end

function IMAP:command(command, public_error, consume)
    self.tag = self.tag + 1
    local tag = string.format("S%05d",self.tag)
    local wire, offset = tag .. " " .. command .. "\r\n", 1
    while offset <= #wire do
        local sent = self.conn:send(wire,offset)
        if not sent then fail(gettext("Could not send the mail request.")) end
        offset = sent + 1
    end
    local lines, total = {}, 0
    while true do
        local line = self:line()
        if line:sub(1,#tag+1) == tag .. " " then
            if not line:match("^" .. tag .. " OK") then fail(public_error or gettext("The mail server rejected the request.")) end
            lines[#lines+1] = line
            return lines
        end
        if line:match("^%* BYE") then fail(gettext("The mail server closed the connection.")) end
        if line:sub(1,1) == "+" then fail(gettext("The server requires an unsupported authentication method.")) end
        while line:match("{%d+}%s*$") do
            local size = tonumber(line:match("{(%d+)}%s*$"))
            local parts = {}
            if not consume and size > 1024*1024 then fail(gettext("The message metadata is too large.")) end
            local left = size
            while left > 0 do
                local chunk = self.conn:receive(math.min(left,16384))
                if not chunk then fail(gettext("Attachment transfer interrupted. Please retry.")) end
                left = left - #chunk
                if consume then consume(chunk,size,line) else parts[#parts+1] = chunk end
            end
            local literal = consume and "NIL" or ('"' .. table.concat(parts):gsub("\\","\\\\"):gsub('"','\\"') .. '"')
            line = line:gsub("{%d+}%s*$", "") .. literal .. self:line()
        end
        total = total + #line
        if total > 8*1024*1024 then fail(gettext("The mail server response exceeded the safety limit.")) end
        lines[#lines+1] = line
    end
end

local function fetchAttributes(lines)
    local result = {}
    for _, line in ipairs(lines) do
        if line:match("^%* %d+ FETCH ") then
            local parsed = Mail.parse(line)
            local attrs, fields = parsed[4], {}
            assert(type(attrs) == "table", gettext("Invalid FETCH response"))
            for i=1,#attrs-1,2 do fields[tostring(attrs[i]):upper()] = attrs[i+1] end
            result[#result+1] = fields
        end
    end
    return result
end

function IMAP:list(cursor)
    cursor = cursor or {}
    local last = cursor.validity == self.validity and tonumber(cursor.last_uid) or nil
    local query
    if last then query = "UID " .. (last+1) .. ":*"
    else
        local date = os.date("!*t",os.time()-30*86400)
        local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
        query = string.format("SINCE %02d-%s-%04d",date.day,months[date.month],date.year)
    end
    local ids = {}
    for _, line in ipairs(self:command("UID SEARCH " .. query)) do
        local values = line:match("^%* SEARCH(.*)")
        if values then for uid in values:gmatch("%d+") do
            uid = tonumber(uid)
            if not last or uid > last then ids[#ids+1] = uid end
        end end
    end
    table.sort(ids)
    if #ids > 10000 then fail(gettext("More than 10,000 new messages. Please use a dedicated mailbox for ebooks.")) end
    local items, high = {}, last or 0
    for _, uid in ipairs(ids) do
        local records = fetchAttributes(self:command("UID FETCH " .. uid .. " (UID INTERNALDATE BODYSTRUCTURE)"))
        for _, fields in ipairs(records) do
            if tonumber(fields.UID) == uid then
                assert(type(fields.BODYSTRUCTURE) == "table", gettext("The message is missing its attachment structure."))
                for _, item in ipairs(Mail.attachments(fields.BODYSTRUCTURE)) do
                    item.uid, item.validity = uid, self.validity
                    item.key = tostring(self.validity) .. ":" .. uid .. ":" .. item.section
                    item.date = type(fields.INTERNALDATE) == "string" and fields.INTERNALDATE or ""
                    items[#items+1] = item
                end
            end
        end
        high = math.max(high,uid)
    end
    -- UIDNEXT is a snapshot from EXAMINE, not a value queried after the scan.
    if self.next_uid then high = math.max(high,self.next_uid-1) end
    return {items=items,validity=self.validity,last_uid=high}
end

function IMAP:download(item, path)
    assert(item.validity == self.validity, gettext("Mailbox identifiers changed. Please refresh the inbox."))
    assert(type(item.uid) == "number" and item.uid%1 == 0 and item.uid > 0, gettext("Invalid UID"))
    assert(type(item.section) == "string" and item.section:match("^%d+[.%d]*$"), gettext("Invalid MIME section"))
    local file = assert(io.open(path,"wb"), gettext("Could not create the temporary download file."))
    local bytes, wire_bytes, literals = 0, 0, 0
    local ok, err = pcall(function()
        local decode = Mail.decoder(item.encoding,function(chunk)
            assert(file:write(chunk), gettext("Not enough storage space, or writing failed."))
            bytes = bytes + #chunk
        end)
        local lines = self:command("UID FETCH " .. item.uid .. " (UID BODY.PEEK[" .. item.section .. "])", nil,
            function(chunk,size,prefix)
                assert(prefix:find("BODY[" .. item.section .. "]",1,true), gettext("Unexpected attachment response"))
                if wire_bytes == 0 then literals = literals + 1 end
                assert(size == item.wire_size, gettext("Attachment size changed. Please refresh the inbox."))
                decode(chunk); wire_bytes = wire_bytes + #chunk
            end)
        local matched = false
        for _, fields in ipairs(fetchAttributes(lines)) do if tonumber(fields.UID) == item.uid then matched=true end end
        assert(matched and literals == 1 and wire_bytes == item.wire_size, gettext("The attachment is missing or incomplete."))
        decode(nil)
        assert(file:flush(), gettext("Could not write the attachment."))
        require("ffi/util").fsyncOpenedFile(file)
    end)
    local closed = file:close()
    if not ok or not closed then os.remove(path); return nil, tostring(err or gettext("Could not write the attachment.")) end
    return bytes
end

function IMAP.run(config, method, ...)
    local client, err = IMAP.connect(config)
    if not client then return nil, err end
    local ok, result, detail = pcall(method,client,...)
    client:close()
    if not ok then return nil, tostring(result) end
    return result, detail
end

return IMAP
