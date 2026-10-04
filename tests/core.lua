require('setupkoenv')
local root, fixture = assert(arg[1]), assert(arg[2])
package.path = root..'/?.lua;'..package.path
local json, lfs = require('json'), require('libs/libkoreader-lfs')
local Mail, IMAP, Store = require('sendtokoreader/mail'), require('sendtokoreader/imap'), require('sendtokoreader/store')
local function read(path) local f=assert(io.open(path,'rb')); local s=f:read('*a'); f:close(); return s end
local config=json.decode(read(fixture..'/config.json'))
local function check(v, message) assert(v,message); print('PASS '..message) end
check(Mail.decodeWords('=?UTF-8?B?5Lit5paHLnR4dA==?=') == '中文.txt','UTF-8 filename')
check(Mail.decodeWords('=?GB18030?B?1tDOxMu1w/cudHh0?=') == '中文说明.txt','GB18030 filename')
check(Mail.safeFilename('../../book.epub') == '_.._.._book.epub','path traversal filename')
check(not pcall(Mail.quote,'user\r\nLOGOUT'),'IMAP command injection rejected')
check(IMAP.hostnameMatches('imap.example.org','*.example.org') and not IMAP.hostnameMatches('a.b.example.org','*.example.org'),'TLS wildcard scope')
for _,encoding in ipairs({'base64','quoted-printable'}) do
    local out={}; local decode=Mail.decoder(encoding,function(s) out[#out+1]=s end)
    for c in (encoding=='base64' and 'SGVsbG8=\r\n' or 'Hello=20world=\r\n!'):gmatch('.') do decode(c) end
    decode(nil); check(table.concat(out)==(encoding=='base64' and 'Hello' or 'Hello world!'),'streaming '..encoding)
end
for _,case in ipairs({{'base64','===='},{'base64','SGk'},{'quoted-printable','bad=QZ'}}) do
    local decode=Mail.decoder(case[1],function() end)
    check(not pcall(function() decode(case[2]); decode(nil) end),'malformed '..case[1]..' rejected')
end
local bad={}; for k,v in pairs(config) do bad[k]=v end
bad.password='wrong'; local result,err=IMAP.run(bad,IMAP.list)
check(not result and err:find('登录失败',1,true),'authentication error')
bad.password=config.password; bad.ca_file=nil; result,err=IMAP.run(bad,IMAP.list)
check(not result and err:find('TLS',1,true),'untrusted CA rejected')
bad.ca_file=config.ca_file; bad.host='127.0.0.1'; result,err=IMAP.run(bad,IMAP.list)
check(not result and err:find('名称不匹配',1,true),'certificate hostname rejected')
local scan=assert(IMAP.run(config,IMAP.list))
check(#scan.items==5 and scan.validity==987 and scan.last_uid==6,'BODYSTRUCTURE lists ebooks and skips zip')
check(scan.items[1].name=='邮件收书测试.epub' and scan.items[2].name==scan.items[1].name and scan.items[3].name=='中文说明.txt','RFC2047 RFC2231 Chinese filenames')
local store=Store.open(fixture..'/core-state'); store:saveConfig(config); store:merge(scan)
local directory=fixture..'/core-books'
local paths={}
for _,item in ipairs({scan.items[1],scan.items[2]}) do
    local temp=store:prepare(item,directory)
    local bytes=assert(IMAP.run(config,IMAP.download,item,temp))
    local path=store:commit(item,temp,directory,bytes); paths[#paths+1]=path
    check(read(path)==read(fixture..'/expected.epub'),'EPUB bytes preserved')
end
check(paths[1]~=paths[2],'same filename never overwrites')
local reopened=Store.open(fixture..'/core-state')
check(reopened:isDownloaded(scan.items[1]),'download record survives reopen')
local incremental=assert(IMAP.run(config,IMAP.list,store.data))
check(#incremental.items==0 and incremental.last_uid==6,'incremental scan filters inverted UID range')
local broken=scan.items[5]; local temp=store:prepare(broken,directory)
result,err=IMAP.run(config,IMAP.download,broken,temp)
check(not result and err:find('附件传输中断',1,true) and not lfs.attributes(temp),'interrupted transfer removes partial file')
store:abort()
local old=store.data.last_uid
store.data.last_uid=4; local delta=assert(IMAP.run(config,IMAP.list,store.data))
check(#delta.items==1 and delta.items[1].uid==5,'new UID scan returns only new ebooks')
store.data.last_uid=old
-- Simulate interruption after rename but before the final record write.
local recovered=scan.items[3]
local pending=store:prepare(recovered,directory)
local bytes=assert(IMAP.run(config,IMAP.download,recovered,pending))
local destination=directory..'/recovery.txt'
store.data.inflight={key=recovered.key,temp=pending,destination=destination,bytes=bytes}
store:saveData(store.data); assert(os.rename(pending,destination))
store=Store.open(fixture..'/core-state')
check(store:isDownloaded(recovered),'completed rename recovered after restart')
local unfinished=store:prepare(broken,directory)
local part=assert(io.open(unfinished,'wb')); part:write('partial'); part:close()
store=Store.open(fixture..'/core-state')
check(not lfs.attributes(unfinished) and not store.data.inflight,'interrupted journal cleaned on restart')
local commands=read(fixture..'/commands.log')
check(not commands:find('SELECT INBOX',1,true) and not commands:find('BODY[',1,true) and not commands:find('STORE ',1,true),'mailbox stays read-only with BODY.PEEK')
print('ALL CORE CHECKS PASSED')
