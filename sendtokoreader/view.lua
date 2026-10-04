local gettext = require("sendtokoreader/i18n")
local BB = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HGroup = require("ui/widget/horizontalgroup")
local VGroup = require("ui/widget/verticalgroup")
local HSpan = require("ui/widget/horizontalspan")
local VSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
local TextBox = require("ui/widget/textboxwidget")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local Button = require("ui/widget/button")
local ProgressWidget = require("ui/widget/progresswidget")
local UIManager = require("ui/uimanager")
local Providers = require("sendtokoreader/providers")
local Mail = require("sendtokoreader/mail")
local Screen = Device.screen
local function px(n) return Screen:scaleBySize(n) end
local function space(n) return VSpan:new{width=px(n)} end
local function text(value,size,width,muted)
    return TextWidget:new{text=tostring(value),face=Font:getFace("cfont",size or 18),max_width=width,
        fgcolor=muted and BB.COLOR_DARK_GRAY or BB.COLOR_BLACK}
end
local function left(widget,width,height)
    return LeftContainer:new{dimen=Geom:new{w=width,h=height or widget:getSize().h},widget}
end
local function rule(width) return LineWidget:new{dimen=Geom:new{w=width,h=px(1)},background=BB.COLOR_GRAY} end
local function button(label,width,callback,primary,enabled)
    return Button:new{text=label,width=width,height=px(44),text_font_size=17,text_font_bold=false,
        padding=0,bordersize=px(1),radius=0,preselect=primary,enabled=enabled ~= false,callback=callback}
end

local TapArea = InputContainer:extend{}
function TapArea:init()
    self.dimen = Geom:new{w=self.width,h=self.height}
    self.ges_events = {
        Tap = {GestureRange:new{ges="tap",range=self.dimen}},
        Hold = {GestureRange:new{ges="hold",range=self.dimen}},
    }
end
function TapArea:onTap() if self.callback then self.callback() end; return true end
function TapArea:onHold() if self.hold_callback then self.hold_callback() end; return true end

local View = InputContainer:extend{covers_fullscreen=true}
function View:init()
    self.dimen = Screen:getSize()
    self.width = self.dimen.w-px(32)
    self.body = VGroup:new{align="left"}
    local p, width = self.plugin, self.width
    local welcome = self.mode == "inbox" and (not p.store.config.username or p.store.config.username == "")
    self.key_events.Back = {{Device.input.group.Back}}
    local heading = ({inbox=gettext("Mail inbox"),settings=gettext("Mail settings"),account=gettext("Link mailbox"),progress=gettext("Download ebooks"),result=gettext("Download results")})[self.mode]
    local labels = VGroup:new{align="left",text("sendtokoreader",12,width-px(155),true),space(3),text(heading,23,width-px(155))}
    local head = HGroup:new{left(labels,width-px(welcome and 50 or 144),px(65))}
    if not welcome then
        head[#head+1]=button(self.mode == "inbox" and gettext("Settings") or gettext("Back"),px(84),function()
            if self.mode == "inbox" then p:showSettings() else self:onBack() end
        end,false,not p.busy)
        head[#head+1]=HSpan:new{width=px(10)}
    end
    head[#head+1]=button("×",px(50),function() self:onBack() end)
    self.body[#self.body+1]=head
    self.body[#self.body+1]=rule(width)
    if self.mode == "inbox" then self:inbox()
    elseif self.mode == "settings" then self:settings()
    elseif self.mode == "account" then self:account()
    elseif self.mode == "progress" then self:progressPage()
    elseif self.mode == "result" then self:resultPage() end
    if self.bottom_space then
        self.bottom_space.width=math.max(px(12),self.dimen.h-px(32)-self.body:getSize().h)
        self.body:resetLayout()
    end
    self[1] = FrameContainer:new{width=self.dimen.w,height=self.dimen.h,padding=px(16),margin=0,bordersize=0,
        background=BB.COLOR_WHITE,self.body}
end

function View:add(widget)
    self.body[#self.body+1]=widget
    self.body:resetLayout()
end
function View:fillBottom()
    self.bottom_space=VSpan:new{width=0}
    self:add(self.bottom_space)
end

function View:onBack()
    local p = self.plugin
    if p.busy then p:cancelWork(self)
    elseif self.mode == "inbox" then p:closeWindow()
    elseif self.mode == "account" then p:show(p.store.config.username and p.store.config.username ~= "" and "settings" or "inbox")
    else p:show("inbox") end
    return true
end

function View:inbox()
    local p, width = self.plugin, self.width
    if not p.store.config.username or p.store.config.username == "" then
        self.bind_button=button(gettext("Link mailbox"),math.min(width,px(320)),function() p:editAccount() end,true)
        local guide=VGroup:new{align="center",
            text(gettext("Receive ebooks by email"),24,width),space(18),
            TextBox:new{text=gettext("Link your mailbox.\nSend ebooks as attachments and download them here."),
                face=Font:getFace("cfont",17),width=width,alignment="center"},
            space(28),self.bind_button,
        }
        self:add(CenterContainer:new{dimen=Geom:new{w=width,h=self.dimen.h-px(32)-self.body:getSize().h},guide})
        return
    end
    local data = p.store.data
    local check = p.busy and gettext("Checking mailbox…") or data.checked and string.format(gettext("Attachments: %d · Updated %s"),#data.items,os.date("%H:%M",data.checked)) or gettext("Inbox · Not checked yet")
    local mailbox = VGroup:new{align="left",text(p.store.config.username,18,width-px(55)),space(5),text(check,13,width-px(55),true)}
    local icon
    if p.busy then icon=text("■",22,px(44))
    else icon=ImageWidget:new{file=p.path .. "/icons/refresh.svg",width=px(24),height=px(24),is_icon=true} end
    local refresh = TapArea:new{width=px(44),height=px(54),callback=function()
        if p.busy then p:cancelWork(self) else p:checkInbox() end
    end,CenterContainer:new{dimen=Geom:new{w=px(44),h=px(54)},icon}}
    self.refresh_button=refresh
    self:add(space(8))
    self:add(HGroup:new{left(mailbox,width-px(44),px(62)),refresh})
    self:add(rule(width))
    local row_height=px(75)
    p.per_page=math.max(1,math.floor((self.dimen.h-px(32+65+72+195))/row_height))
    local pages=math.max(1,math.ceil(#data.items/p.per_page))
    p.page=math.min(p.page,pages)
    local first=(p.page-1)*p.per_page+1
    local available, selected_on_page=0,0
    self.rows={}
    for index=first,math.min(#data.items,first+p.per_page-1) do
        local item=data.items[index]
        local done=p.store:isDownloaded(item)
        local selected=p.selected[item.key] == true
        if not done then
            available=available+1
            if selected then selected_on_page=selected_on_page+1 end
        end
        local mark=FrameContainer:new{padding=0,margin=0,bordersize=done and 0 or px(1),
            background=BB.COLOR_WHITE,invert=selected and not done,
            CenterContainer:new{dimen=Geom:new{w=px(23),h=px(23)},text((selected or done) and "✓" or "",20,px(23))}}
        local detail=string.format(gettext("%s · %s · %s"),item.format,p.sizeText(item.size),done and gettext("Downloaded") or Mail.dateText(item.date))
        local copy=VGroup:new{align="left",text(item.name,19,width-px(42)),space(5),text(detail,13,width-px(42),true)}
        local row=TapArea:new{width=width,height=row_height,callback=function()
            if not p.busy then p:toggle(item) end
        end,hold_callback=function() p:info(item.name .. "\n" .. detail) end,
            left(HGroup:new{mark,HSpan:new{width=px(12)},copy},width,row_height-px(1))}
        self.rows[#self.rows+1]=row
        self:add(row); self:add(rule(width))
    end
    if #data.items == 0 then
        self:add(space(36))
        self:add(TextBox:new{text=gettext("No ebook attachments yet\n\nSend ebooks to this mailbox as regular attachments, then tap the refresh icon."),
            face=Font:getFace("cfont",19),width=width,alignment="center"})
        self:add(space(12)); self:add(text(gettext("Cloud links and oversized attachment links are not supported."),13,width,true))
    end
    self:fillBottom()
    if pages>1 then
        self.previous_button=Button:new{text=gettext("‹ Previous"),width=px(100),height=px(44),text_font_size=15,text_font_bold=false,
            padding=0,bordersize=0,enabled=p.page>1 and not p.busy,callback=function() p:changePage(-1) end}
        self.next_button=Button:new{text=gettext("Next ›"),width=px(100),height=px(44),text_font_size=15,text_font_bold=false,
            padding=0,bordersize=0,enabled=p.page<pages and not p.busy,callback=function() p:changePage(1) end}
        self:add(HGroup:new{self.previous_button,
            CenterContainer:new{dimen=Geom:new{w=width-px(200),h=px(44)},text(p.page .. " / " .. pages,13,nil,true)},
            self.next_button})
        self:add(space(8))
    end
    local count, size=p:selectionCount()
    local all=available>0 and selected_on_page==available
    local mark=FrameContainer:new{padding=0,margin=0,bordersize=px(1),background=BB.COLOR_WHITE,invert=all,
        CenterContainer:new{dimen=Geom:new{w=px(23),h=px(23)},text(all and "✓" or selected_on_page>0 and "−" or "",20,px(23))}}
    self.select_page=TapArea:new{width=px(160),height=px(44),callback=function()
        if available>0 and not p.busy then p:selectPage() end
    end,left(HGroup:new{mark,HSpan:new{width=px(12)},text(gettext("Select page"),15,px(120),available==0 or p.busy)},px(160),px(44))}
    self:add(HGroup:new{self.select_page,
        RightContainer:new{dimen=Geom:new{w=width-px(160),h=px(44)},
            text(string.format(gettext("Selected: %d · %s"),count,p.sizeText(size)),13,width-px(172),true)}})
    self:add(space(8))
    self.download_button=button(count>0 and string.format(gettext("Download selected (%d)"),count) or gettext("Select ebooks first"),width,function() p:downloadSelected() end,true,count>0 and not p.busy)
    self:add(self.download_button)
    self:add(space(8)); self:add(text(string.format(gettext("Save to: %s"),p:downloadDirectory()),12,width,true))
end

function View:setting(label, value, callback)
    self:add(space(18)); self:add(text(label,16,self.width)); self:add(space(7))
    if callback then self:add(button(value,self.width,callback)) else self:add(text(value,15,self.width,true)) end
    self:add(space(12)); self:add(rule(self.width))
end

function View:settings()
    local p=self.plugin
    self:setting(gettext("Mailbox"),p.store.config.username or gettext("Link mailbox"),function() p:editAccount() end)
    self:setting(gettext("Mail folder"),gettext("Inbox"))
    self:setting(gettext("Download folder"),p:downloadDirectory(),function() p:chooseDirectory() end)
    self:setting(gettext("Check for mail"),gettext("Manually · Last 30 days on first check"))
    self:add(space(18)); self:add(TextBox:new{text=gettext("Your emails and their read status are preserved."),face=Font:getFace("cfont",14),width=self.width})
    self:fillBottom(); self:add(button(gettext("Back to attachments"),self.width,function() p:show("inbox") end,true))
end

function View:account()
    local p=self.plugin
    local draft=p.draft
    local provider=Providers.get(draft.provider)
    self:setting(gettext("Mail provider"),gettext(provider.label),function() p:chooseProvider() end)
    self:setting(gettext("Email address"),draft.username ~= "" and draft.username or gettext("Tap to enter email address"),function() p:editField("username",gettext("Email address")) end)
    self:setting(gettext(provider.credential),draft.password ~= "" and "••••••••" or gettext("Tap to enter"),function() p:editField("password",gettext(provider.credential)) end)
    self:add(space(12)); self:add(button(gettext("How do I sign in?"),self.width,function()
        p:info(gettext(provider.help))
    end))
    self:add(space(10)); self:add(button(gettext("Server settings ›"),self.width,function() p:editServer() end))
    self:fillBottom(); self:add(button(gettext("Verify and save"),self.width,function() p:verifyAccount() end,true))
end

function View:progressPage()
    local p=self.plugin
    self:add(space(45)); self:add(text(p.job_title or gettext("Connecting to mailbox…"),22,self.width))
    self:add(space(20)); self:add(text(p.job_item and p.job_item.name or "",18,self.width))
    self:add(space(20))
    self.progress=ProgressWidget:new{width=self.width,height=px(14),percentage=0,bordersize=0,margin_h=0,margin_v=0,
        fillcolor=BB.COLOR_BLACK,bgcolor=BB.COLOR_LIGHT_GRAY}
    self:add(self.progress)
    self:add(space(15)); self.progress_text=text(gettext("Connecting…"),15,self.width,true); self:add(self.progress_text)
    self:fillBottom()
    self:add(button(gettext("Cancel"),self.width,function() p:cancelWork(self) end))
    self:add(space(12)); self:add(text(gettext("Completed downloads will be kept."),13,self.width,true))
end

function View:updateProgress(bytes,total)
    self.progress.percentage=math.min(.99,total>0 and bytes/total or 0)
    self.progress_text:setText(string.format(gettext("Received: %s"),self.plugin.sizeText(bytes)))
    UIManager:setDirty(self,"ui")
end

function View:resultPage()
    local p=self.plugin
    self:add(space(32)); self:add(text(p.result_title or gettext("Downloads complete"),23,self.width))
    self:add(space(16)); self:add(text(p.result_summary or "",17,self.width))
    self:add(space(25))
    -- Keep results within the small screen; complete details remain in the attachment list.
    for index=1,math.min(4,#p.results) do
        local result=p.results[index]
        self:add(text((result.ok and "✓ " or "! ") .. result.item.name,18,self.width))
        self:add(space(6)); self:add(text(result.ok and gettext("Saved") or result.error,13,self.width,true)); self:add(space(16))
    end
    self:add(text(string.format(gettext("Save to: %s"),p:downloadDirectory()),13,self.width,true))
    self:fillBottom()
    if #p.failed>0 then self:add(button(gettext("Retry failed downloads"),self.width,function() p:downloadItems(p.failed) end,true)); self:add(space(12)) end
    self:add(button(gettext("Back to attachments"),self.width,function() p:show("inbox") end,#p.failed==0))
end

return View
