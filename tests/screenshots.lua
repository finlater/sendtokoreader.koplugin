require('setupkoenv')
local root, language=assert(arg[1]),assert(arg[3])
G_defaults=require('luadefaults'):open()
local DataStorage=require('datastorage')
G_reader_settings=require('luasettings'):open(DataStorage:getDataDir()..'/settings.reader.lua')
require('gettext').changeLang(language)
local Device=require('device')
require('document/canvascontext'):init(Device)
require('ui/bidi').setup(language)
local UI=require('ui/uimanager')
local FileManager=require('apps/filemanager/filemanager')
FileManager:showFiles(DataStorage:getDataDir()..'/books')
local p=assert(require('pluginloader'):getPluginInstance('sendtokoreader'))
local Providers=require('sendtokoreader/providers')
local _=require('sendtokoreader/i18n')
local failed=false
local function snap(name)
    UI:forceRePaint(); UI:_repaint()
    Device.screen.bb:writePNG(root..'/tests/evidence/'..language..'-preview-'..name..'.png')
    assert(p.window.body:getSize().h <= Device.screen:getHeight()-32,'page overflow: '..name)
    print('PASS '..language..' preview '..name)
end
UI:scheduleIn(.2,function()
    local ok,err=xpcall(function()
        p:render('inbox'); snap('welcome')
        assert(p.window.bind_button.text==_('Link mailbox') and not p.window.refresh_button and not p.window.download_button,'welcome should contain only setup')
        p.draft={provider='netease',username='',password='',host='imap.163.com',port=993}
        for _,provider in ipairs(Providers) do
            Providers.select(p.draft,provider.id)
            p:render('account'); snap('account-'..provider.id)
        end
        p.store.config={username='books@example.test',download_dir='/mnt/us/documents/sendtokoreader'}
        p.store.data={items={},downloaded={},checked=os.time()}
        p:render('inbox'); snap('empty-inbox')
        for i=1,7 do
            p.store.data.items[i]={key=tostring(i),uid=i,name=(language=='zh_CN' and '收书示例 ' or 'Sample book ')..i..'.epub',format='EPUB',size=1048576+i*1024,date='04-Oct-2026 12:00:00 +0800'}
        end
        p.selected={['1']=true,['3']=true}
        p:render('inbox'); snap('inbox')
        assert(p.window.previous_button.text==_('‹ Previous') and p.window.next_button.text==_('Next ›'),'translated pagination')
        p:selectPage(); assert(p:selectionCount()==p.per_page,'page selection')
        p:selectPage(); assert(p:selectionCount()==0,'page deselection')
        p.store.data.items={p.store.data.items[1]}; p:render('inbox')
        assert(not p.window.previous_button and not p.window.next_button,'single page has no pagination')
        p.job_title=string.format(_('Downloading %d / %d'),1,2); p.job_item=p.store.data.items[1]
        p:render('progress'); p.window:updateProgress(524288,1048576); snap('progress')
        p:render('settings'); snap('settings')
        UI:scheduleIn(.1,function()
            p:render('account')
            -- Dismiss KOReader's first-run cache-migration notice in this fresh profile.
            for i=#UI._window_stack,1,-1 do
                local widget=UI._window_stack[i].widget
                if widget~=p.window and widget~=FileManager.instance then UI:close(widget) end
            end
            local dialog=p:chooseProvider()
            UI:scheduleIn(.2,function()
                local shown,detail=pcall(function()
                    assert(dialog:getSize().h > 0 and dialog:getSize().h <= Device.screen:getHeight(),'provider dialog overflow')
                    assert(UI._window_stack[#UI._window_stack].widget==dialog,'provider selector hidden behind plugin page')
                    snap('providers')
                    UI:close(dialog)
                    local editor=p:editField('username',_('Email address'))
                    local view_index, editor_index
                    for i,entry in ipairs(UI._window_stack) do
                        if entry.widget==p.window then view_index=i end
                        if entry.widget==editor then editor_index=i end
                    end
                    assert(editor_index and editor_index>view_index,'input dialog hidden behind plugin page')
                end)
                if not shown then failed=true; print('FAIL '..tostring(detail)) end
                UI:quit()
            end)
        end)
    end,debug.traceback)
    if not ok then failed=true; print('FAIL '..tostring(err)); UI:quit() end
end)
UI:run()
assert(not failed,'preview verification failed')
