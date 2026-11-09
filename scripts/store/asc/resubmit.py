"""Swap the App Store review submission to another build.

    python3 scripts/store/asc/resubmit.py <build number> [description.txt] [review_notes.txt]

Cancels the open review submission (if any), waits until the version can be
edited, optionally replaces the en-US description and the review notes,
attaches the build, then creates and submits a new review submission. The
screen-recording attachment on the review detail is left as it is.
Cancelling puts the app at the back of the review queue: only run this when
the release build really has to change.
"""
import sys, time
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from asc import call

APP = '6827568754'
VER = 'a2fa8b40-5824-45f0-ac2a-48b72eab9b43'
build_no = sys.argv[1]
desc = open(sys.argv[2]).read().strip() if len(sys.argv) > 2 else None
notes = open(sys.argv[3]).read().strip() if len(sys.argv) > 3 else None

def must(st, j, what, ok=(200, 201, 204)):
    print(f'{what}: HTTP {st}')
    if st not in ok:
        print(j)
        sys.exit(f'FAILED at: {what}')
    return j

st, j = call('GET', f'/v1/builds?filter[app]={APP}&filter[version]={build_no}&limit=1')
must(st, j, 'find build')
assert j['data'] and j['data'][0]['attributes']['processingState'] == 'VALID', 'build not VALID yet'
bid = j['data'][0]['id']

def version_state():
    st, j = call('GET', f'/v1/appStoreVersions/{VER}')
    return j['data']['attributes'].get('appVersionState') or j['data']['attributes'].get('appStoreState')

print('version state before:', version_state())
st, j = call('GET', f'/v1/apps/{APP}/reviewSubmissions?limit=5')
for r in must(st, j, 'list submissions')['data']:
    if r['attributes'].get('state') in ('WAITING_FOR_REVIEW', 'READY_FOR_REVIEW', 'UNRESOLVED_ISSUES'):
        st2, j2 = call('PATCH', f"/v1/reviewSubmissions/{r['id']}", {'data': {'type': 'reviewSubmissions', 'id': r['id'], 'attributes': {'canceled': True}}})
        must(st2, j2, f"cancel submission {r['id'][:8]} ({r['attributes'].get('state')})")

EDITABLE = ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY')
for i in range(40):
    state = version_state()
    if state in EDITABLE:
        break
    time.sleep(6)
print('version state after cancel:', state)
assert state in EDITABLE, 'version did not become editable'

if desc is not None:
    st, j = call('GET', f'/v1/appStoreVersions/{VER}/appStoreVersionLocalizations')
    loc = [l for l in j['data'] if l['attributes']['locale'] == 'en-US'][0]
    st, j = call('PATCH', f"/v1/appStoreVersionLocalizations/{loc['id']}", {'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id'], 'attributes': {'description': desc}}})
    must(st, j, 'update description')
if notes is not None:
    st, j = call('GET', f'/v1/appStoreVersions/{VER}/appStoreReviewDetail')
    rid = j['data']['id']
    st, j = call('PATCH', f'/v1/appStoreReviewDetails/{rid}', {'data': {'type': 'appStoreReviewDetails', 'id': rid, 'attributes': {'notes': notes}}})
    must(st, j, 'update review notes')

st, j = call('PATCH', f'/v1/appStoreVersions/{VER}/relationships/build', {'data': {'type': 'builds', 'id': bid}})
must(st, j, f'attach build {build_no}')

st, j = call('POST', '/v1/reviewSubmissions', {'data': {'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'}, 'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})
sub = must(st, j, 'create submission')['data']['id']
st, j = call('POST', '/v1/reviewSubmissionItems', {'data': {'type': 'reviewSubmissionItems', 'relationships': {
    'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sub}},
    'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': VER}}}}})
must(st, j, 'add version to submission')
st, j = call('PATCH', f'/v1/reviewSubmissions/{sub}', {'data': {'type': 'reviewSubmissions', 'id': sub, 'attributes': {'submitted': True}}})
must(st, j, 'submit')

# read back
st, j = call('GET', f'/v1/reviewSubmissions/{sub}')
print('submission', sub, j['data']['attributes'].get('state'))
st, j = call('GET', f'/v1/appStoreVersions/{VER}/build')
print('version 1.0 build:', j['data']['attributes'].get('version'))
print('version state:', version_state())
st, j = call('GET', f'/v1/appStoreVersions/{VER}/appStoreReviewDetail?include=appStoreReviewAttachments')
print('review attachments:', [(a['attributes'].get('fileName'), (a['attributes'].get('assetDeliveryState') or {}).get('state')) for a in j.get('included', [])])
