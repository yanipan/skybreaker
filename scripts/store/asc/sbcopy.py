import re
t=open('/Users/yanivshimoy/Skybreaker/docs/APP_STORE_COPY.md').read()
def block(after):
    i=t.index(after); m=re.search(r'```\n(.*?)\n```',t[i:],re.S); return m.group(1)
DESC=block('## Full description'); KW=block('## Keywords'); WN=block("## What's New"); SUB=block('**App Store subtitle')
