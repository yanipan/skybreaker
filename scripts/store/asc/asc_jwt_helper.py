#!/usr/bin/env python3
# usage: asc.py METHOD PATH [json-body-file]  -> prints status line + body
import sys, json, time, base64, subprocess, urllib.request, urllib.error
KEY="/Users/yanivshimoy/keys/mail-2026-10-27/AuthKey_A726RHWTX7.p8"; KID="A726RHWTX7"; ISS="f2fcaeb1-4500-4e62-89bc-83d05e013db3"
b64=lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def der2raw(d):
    assert d[0]==0x30; i=2 if d[1]<0x80 else 2+(d[1]&0x7f); out=b""
    for _ in range(2):
        assert d[i]==2; l=d[i+1]; v=d[i+2:i+2+l]; i+=2+l
        out+=v.lstrip(b"\x00").rjust(32,b"\x00")
    return out
def token():
    now=int(time.time())
    h=b64(json.dumps({"alg":"ES256","kid":KID,"typ":"JWT"}).encode()); p=b64(json.dumps({"iss":ISS,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}).encode())
    sig=subprocess.run(["openssl","dgst","-sha256","-sign",KEY],input=f"{h}.{p}".encode(),capture_output=True,check=True).stdout
    return f"{h}.{p}.{b64(der2raw(sig))}"
m,path=sys.argv[1],sys.argv[2]; body=open(sys.argv[3],"rb").read() if len(sys.argv)>3 else None
req=urllib.request.Request("https://api.appstoreconnect.apple.com"+path,data=body,method=m,headers={"Authorization":"Bearer "+token(),"Content-Type":"application/json"})
try:
    r=urllib.request.urlopen(req); print(r.status); sys.stdout.write(r.read().decode())
except urllib.error.HTTPError as e:
    print(e.code); sys.stdout.write(e.read().decode())
