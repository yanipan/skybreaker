from asc import *
import os, hashlib, glob
LOC='5ac9a661-1031-4e9c-9c0e-929801a280aa'
DIRS={'APP_IPHONE_67':'/Users/yanivshimoy/Skybreaker/assets/store/screenshots/ios_phone','APP_IPAD_PRO_3GEN_129':'/Users/yanivshimoy/Skybreaker/assets/store/screenshots/ios_tablet'}
st,j=call('GET',f'/v1/appStoreVersionLocalizations/{LOC}/appScreenshotSets?limit=50')
sets={s['attributes']['screenshotDisplayType']:s['id'] for s in j.get('data',[])}
print('existing sets',sets)
for dt,d in DIRS.items():
    if dt not in sets:
        st,j=call('POST','/v1/appScreenshotSets',{'data':{'type':'appScreenshotSets','attributes':{'screenshotDisplayType':dt},'relationships':{'appStoreVersionLocalization':{'data':{'type':'appStoreVersionLocalizations','id':LOC}}}}})
        if not ok(st,j,'create set '+dt): continue
        sets[dt]=j['data']['id']
    sid=sets[dt]
    st,j=call('GET',f'/v1/appScreenshotSets/{sid}/appScreenshots?limit=50')
    have={x['attributes']['fileName'] for x in j.get('data',[])}
    for f in sorted(glob.glob(d+'/0*.png')):
        name=os.path.basename(f)
        if name in have: print('skip existing',dt,name); continue
        data=open(f,'rb').read()
        st,j=call('POST','/v1/appScreenshots',{'data':{'type':'appScreenshots','attributes':{'fileName':name,'fileSize':len(data)},'relationships':{'appScreenshotSet':{'data':{'type':'appScreenshotSets','id':sid}}}}})
        if not ok(st,j,'reserve '+name): continue
        shot=j['data']; good=True
        for op in shot['attributes']['uploadOperations']:
            chunk=data[op['offset']:op['offset']+op['length']]
            hdr={h['name']:h['value'] for h in op.get('requestHeaders',[])}
            req=urllib.request.Request(op['url'],data=chunk,method=op['method'],headers=hdr)
            try:
                with urllib.request.urlopen(req,timeout=120) as r: pass
            except Exception as e: print('upload part failed',name,e); good=False
        md5=hashlib.md5(data).hexdigest()
        ok(*call('PATCH',f'/v1/appScreenshots/{shot["id"]}',{'data':{'type':'appScreenshots','id':shot['id'],'attributes':{'uploaded':True,'sourceFileChecksum':md5}}}),f'commit {dt} {name} parts_ok={good}')
# poll
for i in range(30):
    pending=0; out=[]
    for dt,sid in sets.items():
        st,j=call('GET',f'/v1/appScreenshotSets/{sid}/appScreenshots?limit=50')
        for x in j.get('data',[]):
            ad=x['attributes'].get('assetDeliveryState') or {}
            s=ad.get('state'); out.append((dt,x['attributes']['fileName'],s,ad.get('errors')))
            if s not in ('COMPLETE','FAILED'): pending+=1
    if pending==0: break
    time.sleep(20)
for o in out: print(*o)
