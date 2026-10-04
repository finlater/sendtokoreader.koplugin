local gettext = require("sendtokoreader/i18n")
local ffi = require("ffi")
local bit = require("bit")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local util = require("util")
local Mail = require("sendtokoreader/mail")
require("ffi/posix")
pcall(ffi.cdef, "int chmod(const char *path, unsigned int mode);")
local Store = {}
Store.__index = Store

local function read(path)
    local file = io.open(path,"rb")
    if not file then return {} end
    local text = file:read("*a"); file:close()
    local ok, data = pcall(json.decode,text)
    assert(ok and type(data) == "table", string.format(gettext("Mailbox settings or download history are damaged. Keep the file and check: %s"),path))
    return data
end

function Store.write(path, data)
    local temp = path .. ".tmp"
    local file = assert(io.open(temp,"wb"), gettext("Could not write mailbox settings."))
    ffi.C.chmod(temp,384) -- 0600; FAT-backed Kindle storage may not enforce POSIX modes.
    local ok, err = pcall(function()
        assert(file:write(json.encode(data)), gettext("Could not write download history."))
        assert(file:flush(), gettext("Could not write download history."))
        ffiutil.fsyncOpenedFile(file)
    end)
    local closed = file:close()
    if not ok or not closed then os.remove(temp); error(err or gettext("Could not close the history file."),0) end
    assert(os.rename(temp,path), gettext("Could not save mailbox settings."))
    ffiutil.fsyncDirectory(path)
end

local function identity(config)
    return (config.host or ""):lower() .. ":" .. tostring(config.port) .. ":" .. (config.username or "")
end

function Store.open(directory)
    util.makePath(directory)
    local self = setmetatable({directory=directory},Store)
    self.config = read(directory .. "/sendtokoreader-account.json")
    self.data = read(directory .. "/sendtokoreader-state.json")
    self.data.items = self.data.items or {}
    self.data.downloaded = self.data.downloaded or {}
    local pending = self.data.inflight
    if pending then
        if pending.destination and pending.bytes and not lfs.attributes(pending.temp)
                and lfs.attributes(pending.destination,"size") == pending.bytes then
            self.data.downloaded[pending.key] = {path=pending.destination,size=pending.bytes}
        elseif pending.destination and lfs.attributes(pending.destination,"size") == 0 then
            os.remove(pending.destination)
        end
        if pending.temp then os.remove(pending.temp) end
        self.data.inflight = nil
        self:saveData(self.data)
    end
    if self.config.username and self.data.identity ~= identity(self.config) then
        self:saveData({identity=identity(self.config),items={},downloaded={}})
    end
    return self
end

function Store:saveData(data)
    Store.write(self.directory .. "/sendtokoreader-state.json",data)
    self.data = data
end

function Store:saveConfig(config)
    Store.write(self.directory .. "/sendtokoreader-account.json",config)
    self.config = config
    local account = identity(config)
    if self.data.identity ~= account then
        self:saveData({identity=account,items={},downloaded={}})
    end
end

function Store:merge(result)
    local data = json.decode(json.encode(self.data))
    if data.validity ~= result.validity then data.items = {} end
    local seen = {}
    for _, item in ipairs(data.items) do seen[item.key] = true end
    for _, item in ipairs(result.items) do
        if not seen[item.key] then data.items[#data.items+1]=item; seen[item.key]=true end
    end
    table.sort(data.items,function(a,b) if a.uid == b.uid then return a.section < b.section end; return a.uid > b.uid end)
    data.validity, data.last_uid, data.checked = result.validity, result.last_uid, os.time()
    self:saveData(data)
end

function Store:isDownloaded(item)
    local saved = self.data.downloaded[item.key]
    return saved and lfs.attributes(saved.path,"size") == saved.size
end

function Store:prepare(item, directory)
    assert(type(directory) == "string" and directory ~= "", gettext("Choose a download folder."))
    util.makePath(directory)
    local _, available = ffiutil.df(directory)
    assert(available > item.wire_size + 1024*1024, gettext("Not enough space in the download folder."))
    local temp = directory .. "/.sendtokoreader-" .. tostring(ffi.C.getpid()) .. ".part"
    self.data.inflight = {key=item.key,temp=temp}
    self:saveData(self.data)
    return temp
end

function Store:abort()
    local pending = self.data.inflight
    if pending then
        os.remove(pending.temp)
        if pending.destination and lfs.attributes(pending.destination,"size") == 0 then os.remove(pending.destination) end
        self.data.inflight = nil
        self:saveData(self.data)
    end
end

function Store:commit(item, temp, directory, bytes)
    assert(lfs.attributes(temp,"size") == bytes, gettext("The downloaded file size does not match."))
    local name = Mail.safeFilename(item.name)
    local base, extension = name:match("^(.*)(%.[^.]+)$")
    base, extension = base or name, extension or ""
    local destination
    local exclusive = ffi.os == "OSX" and 2048 or 128 -- O_EXCL
    for n=0,9999 do
        local candidate = directory .. "/" .. base .. (n == 0 and "" or " (" .. n .. ")") .. extension
        local fd = ffi.C.open(candidate,bit.bor(ffi.C.O_WRONLY,ffi.C.O_CREAT,exclusive),ffi.cast("mode_t",420))
        if fd >= 0 then ffi.C.close(fd); destination=candidate; break end
        assert(ffi.errno() == 17, gettext("Could not create a file in the download folder.")) -- EEXIST
    end
    assert(destination, gettext("Too many files with the same name."))
    self.data.inflight = {key=item.key,temp=temp,destination=destination,bytes=bytes}
    self:saveData(self.data)
    assert(os.rename(temp,destination), gettext("Could not finalize the downloaded attachment."))
    ffiutil.fsyncDirectory(destination)
    self.data.downloaded[item.key] = {path=destination,size=bytes}
    self.data.inflight = nil
    self:saveData(self.data)
    return destination
end

return Store
