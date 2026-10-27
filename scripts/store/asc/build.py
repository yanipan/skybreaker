from asc import *
APP='6827568754'; VER='a2fa8b40-5824-45f0-ac2a-48b72eab9b43'
end=time.time()+25*60; b=None
while time.time()<end:
    st,j=call('GET',f'/v1/builds?filter[app]={APP}&filter[version]=1&sort=-uploadedDate&limit=5')
    if st==200 and j['data']:
        b=j['data'][0]; a=b['attributes']
        print(time.strftime('%H:%M:%S'),b['id'],a.get('processingState'),a.get('uploadedDate'),flush=True)
        if a.get('processingState') in ('VALID','FAILED','INVALID'): break
    else: print(time.strftime('%H:%M:%S'),'no build yet',st,flush=True)
    time.sleep(60)
if b and b['attributes'].get('processingState')=='VALID':
    bid=b['id']
    ok(*call('PATCH',f'/v1/builds/{bid}',{'data':{'type':'builds','id':bid,'attributes':{'usesNonExemptEncryption':False}}}),'encryption')
    ok(*call('PATCH',f'/v1/appStoreVersions/{VER}/relationships/build',{'data':{'type':'builds','id':bid}}),'attach build')
    st,j=call('GET',f'/v1/appStoreVersions/{VER}/build'); print('version build:',j.get('data',{}) and j['data']['id'], j.get('data',{}) and j['data']['attributes'].get('version'))
print('DONE')
