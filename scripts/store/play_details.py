import sys, json
sys.argv=['x','none']
src=open('/private/tmp/claude-501/-Users-yanivshimoy/8a2e45bd-9aa7-423c-a190-2e4aa669295b/scratchpad/play.py').read().split("mode=sys.argv[1]")[0]
exec(src)
B='https://androidpublisher.googleapis.com/androidpublisher/v3/applications/'
e=req('POST',B+'com.shimonster.englishadventures/edits',{})['id']
try: d=req('GET',B+f'com.shimonster.englishadventures/edits/{e}/details'); print('shimmy details',d)
finally: req('DELETE',B+f'com.shimonster.englishadventures/edits/{e}'); print('shimmy edit deleted')
body={'defaultLanguage':'en-US','contactEmail':d['contactEmail']}
if d.get('contactWebsite'): body['contactWebsite']=d['contactWebsite']
e2=req('POST',API+'/edits',{})['id']; print('sky edit',e2)
print('update',req('PUT',f'{API}/edits/{e2}/details',body))
print('commit',req('POST',f'{API}/edits/{e2}:commit'))
e3=req('POST',API+'/edits',{})['id']; print('verify',req('GET',f'{API}/edits/{e3}/details')); req('DELETE',f'{API}/edits/{e3}')
