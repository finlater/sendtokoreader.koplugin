local gettext = require("sendtokoreader/i18n")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local Trapper = require("ui/trapper")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local Store = require("sendtokoreader/store")
local IMAP = require("sendtokoreader/imap")
local View = require("sendtokoreader/view")
local Providers = require("sendtokoreader/providers")

-- macOS initializes resolver sorting via libSystem; do it before Trapper forks.
-- Otherwise the first getaddrinfo in a child of the SDL process may crash.
if require("ffi").os == "OSX" then require("socket").dns.getaddrinfo("localhost") end

local Plugin = WidgetContainer:extend{name="sendtokoreader",is_doc_only=false}

function Plugin:init()
    self.store=Store.open(DataStorage:getSettingsDir())
    self.selected={}; self.page=1; self.per_page=5
    self.ui.menu:registerToMainMenu(self)
    Dispatcher:registerAction("sendtokoreader",{category="none",event="SendToKOReader",title=gettext("Mail inbox"),general=true})
end

function Plugin:addToMainMenu(items)
    items.sendtokoreader={text=gettext("sendtokoreader · Mail inbox"),sorting_hint="more_tools",callback=function() self:onSendToKOReader() end}
end

function Plugin:onSendToKOReader() self:show("inbox"); return true end
function Plugin.info(_self, message) UIManager:show(InfoMessage:new{text=tostring(message)}) end
function Plugin:defer(fn)
    UIManager:nextTick(function()
        local ok, err=pcall(fn)
        if not ok then self:info(err) end
    end)
end

function Plugin:render(mode)
    if self.window then UIManager:close(self.window) end
    self.window=View:new{plugin=self,mode=mode or "inbox"}
    UIManager:show(self.window)
    return self.window
end

function Plugin:show(mode) self:defer(function() if not self.busy then self:render(mode) end end) end
function Plugin:showSettings() self:show("settings") end
function Plugin:closeWindow()
    self:defer(function() if self.window and not self.busy then UIManager:close(self.window); self.window=nil end end)
end

function Plugin.sizeText(size)
    if size < 1024 then return string.format(gettext("%d B"),size) end
    if size < 1024*1024 then return string.format(gettext("%.1f KB"),size/1024) end
    return string.format(gettext("%.1f MB"),size/1024/1024)
end

function Plugin:downloadDirectory()
    if self.store.config.download_dir then return self.store.config.download_dir end
    local base=G_reader_settings:readSetting("download_dir") or G_reader_settings:readSetting("home_dir")
    if not base then base=lfs.attributes("/mnt/us/documents","mode") == "directory" and "/mnt/us/documents" or DataStorage:getDataDir() .. "/books" end
    return base .. "/sendtokoreader"
end

function Plugin:selectionCount()
    local count, size=0,0
    for _,item in ipairs(self.store.data.items) do
        if self.selected[item.key] and not self.store:isDownloaded(item) then count=count+1; size=size+item.size end
    end
    return count,size
end

function Plugin:toggle(item)
    if self.store:isDownloaded(item) then
        self:defer(function()
            local path=self.store.data.downloaded[item.key].path
            if self.window then UIManager:close(self.window); self.window=nil end
            require("apps/reader/readerui"):showReader(path)
        end)
    else self.selected[item.key]=not self.selected[item.key]; self:show("inbox") end
end

function Plugin:changePage(delta) self.page=math.max(1,self.page+delta); self:show("inbox") end
function Plugin:selectPage()
    local first=(self.page-1)*self.per_page+1
    local all=true
    for index=first,math.min(#self.store.data.items,first+self.per_page-1) do
        local item=self.store.data.items[index]
        if not self.store:isDownloaded(item) and not self.selected[item.key] then all=false end
    end
    for index=first,math.min(#self.store.data.items,first+self.per_page-1) do
        local item=self.store.data.items[index]
        if not self.store:isDownloaded(item) then self.selected[item.key]=not all end
    end
    self:show("inbox")
end

function Plugin:editAccount()
    local c=self.store.config
    self.draft={provider=c.provider or "netease",username=c.username or "",password=c.password or "",host=c.host or "imap.163.com",port=c.port or 993,download_dir=c.download_dir,ca_file=c.ca_file}
    self:show("account")
end

function Plugin:chooseProvider()
    local dialog
    local rows={}
    for _,provider in ipairs(Providers) do
        rows[#rows+1]={{text=gettext(provider.label),callback=function()
            Providers.select(self.draft,provider.id)
            UIManager:close(dialog); self:show("account")
        end}}
    end
    rows[#rows+1]={{text=gettext("Outlook / Exchange support"),callback=function() self:info(Providers.oauthNotice()) end}}
    dialog=ButtonDialog:new{title=gettext("Mail provider"),buttons=rows}
    UIManager:show(dialog)
    return dialog
end

function Plugin:editField(key, title)
    local dialog
    dialog=InputDialog:new{title=title,input=self.draft[key],input_hint=title,input_type="text",
        text_type=key == "password" and "password" or nil,
        buttons={{{text=gettext("Cancel"),id="close",callback=function() UIManager:close(dialog) end},
            {text=gettext("Save"),is_enter_default=true,callback=function()
                self.draft[key]=dialog:getInputText()
                UIManager:close(dialog); self:show("account")
            end}}}}
    UIManager:show(dialog); dialog:onShowKeyboard()
    return dialog
end

function Plugin:editServer()
    local dialog
    dialog=MultiInputDialog:new{title=gettext("Server settings · TLS"),fields={
        {description=gettext("IMAP server"),text=self.draft.host},
        {description=gettext("Port"),text=tostring(self.draft.port),input_type="number"}},
        buttons={{{text=gettext("Cancel"),id="close",callback=function() UIManager:close(dialog) end},
            {text=gettext("Save"),callback=function()
                local fields=dialog:getFields()
                self.draft.host=fields[1]; self.draft.port=tonumber(fields[2])
                UIManager:close(dialog); self:show("account")
            end}}}}
    UIManager:show(dialog); dialog:onShowKeyboard()
end

function Plugin:chooseDirectory()
    require("ui/downloadmgr"):new{onConfirm=function(path)
        self.store.config.download_dir=path
        self.store:saveConfig(self.store.config)
        self:show("settings")
    end}:chooseDir(self:downloadDirectory())
end

function Plugin:cancelWork(window)
    self:defer(function()
        if self.busy and window == self.window and window.dismiss_callback then window.dismiss_callback() end
    end)
end

function Plugin:startWork(fn)
    self:defer(function()
        if self.busy then return end
        if NetworkMgr:willRerunWhenConnected(function() self:startWork(fn) end) then return end
        Trapper:wrap(function()
            self.busy=true
            local ok,err=pcall(fn)
            self.busy=false
            if not ok then
                pcall(self.store.abort,self.store)
                if self.poll_progress then UIManager:unschedule(self.poll_progress); self.poll_progress=nil end
                self:render("inbox")
                self:info(err)
            end
        end)
    end)
end

function Plugin:verifyAccount()
    local ok,err=pcall(IMAP.validate,self.draft)
    if not ok then self:info(err); return end
    self:startWork(function()
        self.job_title=gettext("Verifying mailbox…"); self.job_item=nil
        local window=self:render("progress")
        local completed,result,message=Trapper:dismissableRunInSubprocess(function()
            return IMAP.run(self.draft,function() return true end)
        end,window)
        self.busy=false
        if completed and result then
            self.store:saveConfig(self.draft); self.selected={}; self.page=1
            self:render("settings"); self:info(gettext("Mailbox connected. Settings saved."))
        else self:render("account"); if completed then self:info(message or gettext("Verification failed. Please try again.")) end end
    end)
end

function Plugin:checkInbox()
    if not self.store.config.username then self:editAccount(); return end
    self:startWork(function()
        local window=self:render("inbox")
        local completed,result,message=Trapper:dismissableRunInSubprocess(function()
            return IMAP.run(self.store.config,IMAP.list,self.store.data)
        end,window)
        if completed and result then self.store:merge(result) end
        self.busy=false; self:render("inbox")
        if completed and not result then self:info(message or gettext("Could not check the mailbox. Please try again.")) end
    end)
end

function Plugin:downloadSelected()
    local items={}
    for _,item in ipairs(self.store.data.items) do
        if self.selected[item.key] and not self.store:isDownloaded(item) then items[#items+1]=item end
    end
    self:downloadItems(items)
end

function Plugin:downloadItems(items)
    if #items == 0 then return end
    self:startWork(function()
        self.results={}; self.failed={}
        local cancelled=false
        local directory=self:downloadDirectory()
        for index,item in ipairs(items) do
            if not self.store:isDownloaded(item) then
                local temp=self.store:prepare(item,directory)
                self.job_title=string.format(gettext("Downloading %d / %d"),index,#items); self.job_item=item
                local window=self:render("progress")
                self.poll_progress=function()
                    if self.busy and self.window == window then
                        window:updateProgress(lfs.attributes(temp,"size") or 0,item.size)
                        UIManager:scheduleIn(1,self.poll_progress)
                    end
                end
                UIManager:scheduleIn(1,self.poll_progress)
                local completed,bytes,message=Trapper:dismissableRunInSubprocess(function()
                    return IMAP.run(self.store.config,IMAP.download,item,temp)
                end,window)
                UIManager:unschedule(self.poll_progress); self.poll_progress=nil
                if completed and bytes then
                    self.store:commit(item,temp,directory,bytes)
                    self.selected[item.key]=nil
                    self.results[#self.results+1]={item=item,ok=true}
                else
                    self.store:abort()
                    if not completed then cancelled=true; break end
                    self.results[#self.results+1]={item=item,ok=false,error=message or gettext("Download failed")}
                    self.failed[#self.failed+1]=item
                end
            end
        end
        local success=0
        for _,result in ipairs(self.results) do if result.ok then success=success+1 end end
        self.result_title=cancelled and gettext("Download cancelled") or #self.failed>0 and gettext("Some downloads failed") or gettext("Downloads complete")
        self.result_summary=string.format(gettext("%d saved · %d failed"),success,#self.failed)
        self.busy=false; self:render("result")
    end)
end

return Plugin
