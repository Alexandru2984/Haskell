#!/usr/bin/env python3
"""Run integration checks against a disposable app process and a dedicated test DB."""
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
database = os.environ['TEST_DATABASE_URL']
if '://' in database:
    dbname = urllib.parse.urlsplit(database).path.lstrip('/')
else:
    dbname = next((part.split('=',1)[1] for part in database.split() if part.startswith('dbname=')), '')
assert any(marker in dbname for marker in ('_test','_review')), 'Refusing a database without a test/review name'
assert len(sys.argv) == 2, 'Usage: TEST_DATABASE_URL=... python3 scripts/test_instance.py /absolute/path/to/binary'
binary = str(Path(sys.argv[1]).resolve())
user, password = 'reviewer', secrets.token_urlsafe(32)
env = os.environ.copy()
env.update(APP_HOST='127.0.0.1', APP_PORT='19060', APP_ENV='development', DATABASE_URL=database,
           ALLOW_PRIVATE_TARGETS='true', MAX_RESPONSE_BYTES='1048576', DEFAULT_TIMEOUT_SECONDS='3',
           DEFAULT_CHECK_INTERVAL_SECONDS='86400', MAX_CONCURRENT_CHECKS='2', APP_BASIC_AUTH_ENABLED='true',
           APP_USERNAME=user, APP_PASSWORD=password, APP_ORIGIN='http://127.0.0.1:19060', RETENTION_DAYS='0', MAX_ENDPOINTS='200',
           TEST_BASE_URL='http://127.0.0.1:19060', TEST_USERNAME=user, TEST_PASSWORD=password)
# Refuse to send tests to an unrelated local process occupying either test port.
for test_port in (19060,19061):
    with socket.socket() as probe:
        probe.bind(('127.0.0.1',test_port))
children=[]
with tempfile.TemporaryDirectory(prefix='haskell-pulse-test-') as directory:
    location = Path(directory)
    (location/'public').symlink_to(ROOT/'public', target_is_directory=True)
    (location/'.env').touch(mode=0o600)
    log = (ROOT/'artifacts')
    log.mkdir(exist_ok=True)
    with (log/'integration-server.log').open('w') as output:
        try:
            children.append(subprocess.Popen([sys.executable,str(ROOT/'scripts/fixture_server.py')],env=env,stdout=output,stderr=output))
            children.append(subprocess.Popen([binary],cwd=directory,env=env,stdout=output,stderr=output))
            token=base64.b64encode((user+':'+password).encode()).decode()
            for attempt in range(100):
                if children[-1].poll() is not None:
                    raise RuntimeError('Test server exited; inspect artifacts/integration-server.log')
                try:
                    urllib.request.urlopen(urllib.request.Request(env['TEST_BASE_URL']+'/health',headers={'Authorization':'Basic '+token}),timeout=1)
                    break
                except (OSError,urllib.error.URLError):
                    time.sleep(.1)
            else: raise RuntimeError('Test server did not start')
            subprocess.run([sys.executable,str(ROOT/'scripts/smoke_test.py')],cwd=ROOT,env=env,check=True)
            # Seed synthetic monitor definitions and check history for browser inspection.
            for name,project,path in [('Storefront health','Commerce','/health'),('Payments API','Commerce','/fail'),('User directory','Platform','/health')]:
                values=urllib.parse.urlencode(dict(name=name,project=project,url='http://127.0.0.1:19061'+path,method='GET',contract=json.dumps({'type':'object','allow_extra_fields':True}))).encode()
                request=urllib.request.Request(env['TEST_BASE_URL']+'/endpoints/create',data=values,headers={'Authorization':'Basic '+token,'Origin':env['TEST_BASE_URL']})
                response=urllib.request.urlopen(request,timeout=5)
                endpoint_path=urllib.parse.urlsplit(response.url).path
                # Cooldown is reset before these manually triggered fixture checks by waiting.
                time.sleep(5.05)
                urllib.request.urlopen(urllib.request.Request(env['TEST_BASE_URL']+endpoint_path+'/check',data=b'',headers={'Authorization':'Basic '+token,'Origin':env['TEST_BASE_URL']}),timeout=10)
            if os.environ.get('RUN_BROWSER_TESTS') == '1':
                subprocess.run(['npm','run','test:browser'],cwd=ROOT,env=env,check=True)
        finally:
            for child in reversed(children):
                child.terminate()
            for child in reversed(children):
                try: child.wait(timeout=10)
                except subprocess.TimeoutExpired: child.kill(); child.wait()
