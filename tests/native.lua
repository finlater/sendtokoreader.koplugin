-- Native KOReader integration: real PluginLoader, widgets, Trapper children and TLS.
io.stdout:setvbuf('line')
require('setupkoenv')
local root, fixture=assert(arg[1]),assert(arg[2])
G_defaults=require('luadefaults'):open()
local DataStorage=require('datastorage')
G_reader_settings=require('luasettings'):open(DataStorage:getDataDir()..'/settings.reader.lua')
local language=assert(arg[3])
require('gettext').changeLang(language)
local Device=require('device')
require('document/canvascontext'):init(Device)
require('ui/bidi').setup(language)
local UI=require('ui/uimanager')
local FileManager=require('apps/filemanager/filemanager')
FileManager:showFiles(DataStorage:getDataDir()..'/books')
local p=assert(require('pluginloader'):getPluginInstance('sendtokoreader'),'PluginLoader did not load plugin')
local original_info=p.info
function p:info(message) print('PLUGIN INFO '..tostring(message)); original_info(self,message) end
local Store=require('sendtokoreader/store')
local json=require('json')
local function read(path) local f=assert(io.open(path,'rb')); local s=f:read('*a'); f:close(); return s end
local config=json.decode(read(fixture..'/config.json'))
config.download_dir=DataStorage:getDataDir()..'/books/收书'
local failed=false
local function snap(name)
    UI:forceRePaint(); UI:_repaint()
    Device.screen.bb:writePNG(root..'/tests/evidence/'..language..'-'..name..'.png')
    assert(p.window.body:getSize().h <= Device.screen:getHeight()-32,'page overflow: '..name)
    print('PASS native '..name)
end
local function check(fn) return function()
    local ok,err=xpcall(fn,debug.traceback)
    if not ok then failed=true; print('FAIL '..tostring(err)); UI:quit() end
end end
local function later(fn) UI:scheduleIn(.3,check(fn)) end
local function waitIdle(next_step)
    UI:scheduleIn(.2,check(function() if p.busy then waitIdle(next_step) else next_step() end end))
end
UI:scheduleIn(50,check(function() error('native integration timeout') end))
UI:scheduleIn(.2,check(function()
    p:render('inbox'); snap('01-empty')
    p.window.bind_button:onTapSelectButton()
    later(function()
    assert(p.window.mode=='account','bind button did not open account page')
    p.draft=config; p:render('account'); snap('02-account')
    p:verifyAccount()
    later(function() waitIdle(function()
        assert(p.store.config.username==config.username,'account verification did not persist')
        for i=#UI._window_stack,1,-1 do
            local widget=UI._window_stack[i].widget
            if widget~=p.window and widget~=FileManager.instance then UI:close(widget) end
        end
        p:render('settings'); snap('03-settings')
        p:render('inbox'); p.window.refresh_button:onTap()
        later(function() waitIdle(function()
            assert(#p.store.data.items==5,'refresh did not list five ebooks'); snap('04-inbox')
            local item
            for _,v in ipairs(p.store.data.items) do if v.uid==4 then item=v end end
            p.window.rows[2]:onTap()
            later(function()
                assert(p.selected[item.key] and p:selectionCount()==1,'row selection failed')
                snap('04-selected'); p.window.download_button:onTapSelectButton()
            end)
            UI:scheduleIn(2,check(function()
                assert(p.busy and p.window.mode=='progress','download not running'); snap('05-progress')
                p:cancelWork(p.window)
                later(function() waitIdle(function()
                    assert(p.result_title==require('sendtokoreader/i18n')('Download cancelled') and not p.store.data.inflight,'cancel failed'); snap('06-cancelled')
                    local items={}
                    for _,v in ipairs(p.store.data.items) do if v.uid~=4 then items[#items+1]=v end end
                    p:downloadItems(items)
                    later(function() waitIdle(function()
                        assert(#p.failed==1 and p.failed[1].uid==5,'failure isolation failed'); snap('07-partial-result')
                        Store.write(fixture..'/control.json',{max_uid=6,fail_uid=0,slow=true})
                        p:downloadItems(p.failed)
                        later(function() waitIdle(function()
                            assert(#p.failed==0,'retry failed'); snap('08-retry-success')
                            p:render('inbox'); snap('09-downloaded')
                            local book
                            for _,v in ipairs(p.store.data.items) do if v.uid==1 then book=v end end
                            p:toggle(book)
                            UI:scheduleIn(2,check(function()
                                assert(require('apps/reader/readerui').instance,'downloaded EPUB did not open')
                                UI:forceRePaint(); UI:_repaint(); Device.screen.bb:writePNG(root..'/tests/evidence/'..language..'-10-reader.png')
                                print('PASS native EPUB opens in ReaderUI')
                                UI:quit()
                            end))
                        end) end)
                    end) end)
                end) end)
            end))
        end) end)
    end) end)
    end)
end))
UI:run()
assert(not failed,'native integration failed')
print('ALL NATIVE CHECKS PASSED')
