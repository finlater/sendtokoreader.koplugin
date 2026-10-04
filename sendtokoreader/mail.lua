-- IMAP BODYSTRUCTURE and MIME filename/transfer decoding. No whole-message buffering.
local mime = require("mime")
local Mail = {}

function Mail.quote(value)
    assert(type(value) == "string" and not value:find("[%z\r\n]"), "Invalid IMAP string")
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function Mail.parse(text)
    local i, count = 1, 0
    local function value(depth)
        assert(depth < 40, "IMAP nesting limit exceeded")
        while text:sub(i,i):match("%s") do i = i + 1 end
        count = count + 1
        assert(count < 100000, "IMAP token limit exceeded")
        local c = text:sub(i,i)
        if c == "(" then
            i = i + 1
            local list = {}
            while true do
                while text:sub(i,i):match("%s") do i = i + 1 end
                if text:sub(i,i) == ")" then i = i + 1; return list end
                assert(i <= #text, "Incomplete IMAP list")
                list[#list+1] = value(depth+1)
            end
        elseif c == '"' then
            local out = {}
            i = i + 1
            while i <= #text do
                c = text:sub(i,i); i = i + 1
                if c == '"' then return table.concat(out) end
                if c == "\\" then c = text:sub(i,i); i = i + 1 end
                out[#out+1] = c
            end
            error("Incomplete IMAP string")
        end
        local start = i
        while i <= #text and not text:sub(i,i):match("[%s()]") do i = i + 1 end
        assert(i > start, "Invalid IMAP token")
        local atom = text:sub(start,i-1)
        if atom:upper() == "NIL" then return false end
        return tonumber(atom) or atom
    end
    local result = {}
    while i <= #text do
        if text:sub(i):match("^%s*$") then break end
        result[#result+1] = value(0)
    end
    return result
end

local function charset_utf8(text, charset)
    charset = (charset or "utf-8"):lower()
    if charset == "utf-8" or charset == "utf8" or charset == "us-ascii" then return text end
    -- iconv is provided by macOS/libc on the supported simulator/Kindle targets.
    local ok, converted = pcall(function()
        local ffi = require("ffi")
        pcall(ffi.cdef, [[
            void *iconv_open(const char *, const char *);
            size_t iconv(void *, char **, size_t *, char **, size_t *);
            int iconv_close(void *);
        ]])
        local lib = ffi.os == "OSX" and ffi.load("iconv") or ffi.C
        local prefix = "iconv"
        local handle = lib[prefix .. "_open"]("UTF-8", charset)
        assert(handle ~= ffi.cast("void *", -1), "Unsupported charset")
        local input = ffi.new("char[?]", #text+1, text)
        local output = ffi.new("char[?]", #text*4+16)
        local src, dst = ffi.new("char *[1]", input), ffi.new("char *[1]", output)
        local src_n, dst_n = ffi.new("size_t[1]", #text), ffi.new("size_t[1]", #text*4+16)
        local status = lib[prefix](handle,src,src_n,dst,dst_n)
        lib[prefix .. "_close"](handle)
        assert(status ~= ffi.cast("size_t",-1), "Invalid filename encoding")
        return ffi.string(output,#text*4+16-tonumber(dst_n[0]))
    end)
    -- Preserve an ASCII extension even on platforms without this charset converter.
    return ok and converted or (text:gsub("[\128-\255]", "_"))
end

function Mail.decodeWords(text)
    text = tostring(text or "")
    text = text:gsub("(%?=)%s+(=%?)", "%1%2")
    return (text:gsub("=%?([^?]+)%?([bBqQ])%?([^?]*)%?=", function(charset, encoding, data)
        if encoding:lower() == "b" then data = mime.unb64(data) or data
        else data = data:gsub("_"," "):gsub("=(%x%x)",function(h) return string.char(tonumber(h,16)) end) end
        return charset_utf8(data,charset)
    end))
end

local function parameters(list)
    local result = {}
    if type(list) == "table" then
        for i=1,#list-1,2 do
            if type(list[i]) == "string" then result[list[i]:lower()] = list[i+1] end
        end
    end
    return result
end

local function paramName(params, key)
    local encoded = params[key .. "*"]
    if not encoded and params[key .. "*0*"] then
        local pieces, i = {}, 0
        while params[key .. "*" .. i .. "*"] or params[key .. "*" .. i] do
            pieces[#pieces+1] = params[key .. "*" .. i .. "*"] or params[key .. "*" .. i]
            i = i + 1
        end
        encoded = table.concat(pieces)
    end
    if type(encoded) == "string" then
        local charset, data = encoded:match("^([^']*)'[^']*'(.*)$")
        data = (data or encoded):gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end)
        return charset_utf8(data,charset)
    end
    if params[key .. "*0"] then
        local pieces, i = {}, 0
        while params[key .. "*" .. i] do pieces[#pieces+1] = params[key .. "*" .. i]; i = i + 1 end
        return Mail.decodeWords(table.concat(pieces))
    end
    return type(params[key]) == "string" and Mail.decodeWords(params[key]) or nil
end

local supported = {epub=true,pdf=true,mobi=true,azw=true,azw3=true,fb2=true,txt=true,djvu=true,djv=true,cbz=true,cbr=true}

function Mail.safeFilename(name)
    name = name:gsub("[%z\1-\31\127/\\:*?\"<>|]", "_"):gsub("^%s+", ""):gsub("[%s.]+$", "")
    if name:sub(1,1) == "." then name = "_" .. name end
    local base, ext = name:match("^(.*)(%.[^.]+)$")
    if #name > 180 and base then
        base = base:sub(1,180-#ext):gsub("[\194-\244][\128-\191]*$", "")
        name = base .. ext
    end
    return name ~= "" and name or "attachment"
end

function Mail.attachments(body)
    local files = {}
    local function walk(part, section)
        if type(part) ~= "table" then return end
        if type(part[1]) == "table" then
            local n = 1
            while type(part[n]) == "table" do
                walk(part[n],section == "" and tostring(n) or section .. "." .. n)
                n = n + 1
            end
            return
        end
        local kind = tostring(part[1]):upper()
        -- Do not download attachments inside attached/forwarded message/rfc822 documents.
        if kind == "MESSAGE" then return end
        local disposition = part[kind == "TEXT" and 10 or 9]
        local name = type(disposition) == "table" and paramName(parameters(disposition[2]),"filename")
            or nil
        name = name or paramName(parameters(part[3]),"name")
        if not name then return end
        name = Mail.safeFilename(name)
        local ext = name:match("%.([^.]+)$")
        local encoding = tostring(part[6]):lower()
        if ext and supported[ext:lower()] and tonumber(part[7]) then
            files[#files+1] = {
                name=name, format=ext:upper(), section=section == "" and "1" or section,
                encoding=encoding, wire_size=tonumber(part[7]),
                size=encoding == "base64" and math.floor(tonumber(part[7])*3/4) or tonumber(part[7]),
            }
        end
    end
    walk(body,"")
    return files
end

function Mail.decoder(encoding, write)
    local carry, ended = "", false
    return function(chunk)
        if encoding == "base64" then
            local data = carry .. (chunk or ""):gsub("%s", "")
            assert(not data:find("[^A-Za-z0-9+/=]"), "Invalid base64 attachment")
            assert(not ended or data == "", "Data after base64 padding")
            local n = chunk and (#data - #data%4) or #data
            local full = data:sub(1,n)
            carry = data:sub(n+1)
            if not chunk then assert(#full%4 == 0, "Truncated base64 attachment") end
            if full ~= "" then
                assert(not full:find("=[^=]"), "Invalid base64 padding")
                local padding = full:find("=",1,true)
                if padding then assert(#full-padding < 2, "Invalid base64 padding"); ended = true end
                local decoded = mime.unb64(full)
                assert(decoded, "Invalid base64 attachment")
                write(decoded)
            end
        elseif encoding == "quoted-printable" then
            local data = carry .. (chunk or "")
            carry = ""
            if chunk then
                local tail = data:match("(=[^=\r\n]?)$") or data:match("(=\r)$")
                if tail then carry=tail; data=data:sub(1,#data-#tail) end
            end
            local plain = data:gsub("=\r?\n", ""):gsub("=%x%x", "")
            assert(not plain:find("=",1,true), "Invalid quoted-printable attachment")
            data = data:gsub("=\r?\n", ""):gsub("=(%x%x)",function(h) return string.char(tonumber(h,16)) end)
            write(data)
        elseif encoding == "7bit" or encoding == "8bit" or encoding == "binary" then
            if chunk then write(chunk) end
        else error("Unsupported attachment encoding: " .. tostring(encoding)) end
    end
end

return Mail
