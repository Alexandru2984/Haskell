#!/usr/bin/env python3
"""HTTP integration tests. Run only against an isolated loopback test instance."""
import base64
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get('TEST_BASE_URL', 'http://127.0.0.1:19060').rstrip('/')
assert urllib.parse.urlsplit(BASE).hostname in ('127.0.0.1', 'localhost', '::1'), 'Tests require an isolated loopback instance'
assert urllib.parse.urlsplit(BASE).port != 3060, 'Refusing the production port'
TOKEN = base64.b64encode((os.environ['TEST_USERNAME'] + ':' + os.environ['TEST_PASSWORD']).encode()).decode()
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None
OPENER = urllib.request.build_opener(NoRedirect)
COUNT = 0

def request(path, data=None, origin=BASE, auth=True, content_type='application/x-www-form-urlencoded'):
    headers = {}
    if auth: headers['Authorization'] = 'Basic ' + TOKEN
    if origin is not None: headers['Origin'] = origin
    if data is not None: headers['Content-Type'] = content_type
    req = urllib.request.Request(BASE + path, data=data, headers=headers)
    try: response = OPENER.open(req, timeout=15)
    except urllib.error.HTTPError as error: response = error
    return response.status, response.headers, response.read()

def check(condition, message):
    global COUNT
    assert condition, message
    COUNT += 1

status, headers, body = request('/', auth=False)
check(status == 401, 'Private dashboard requires authentication')
check(headers.get('Cache-Control') == 'no-store', 'Errors also have no-store')
check(headers.get('X-Frame-Options') == 'DENY', 'Framing is denied')
for path in ['/', '/?hours=168', '/?hours=720', '/endpoints', '/endpoints/new', '/incidents', '/playground']:
    status, headers, body = request(path)
    check(status == 200 and b'<html' in body, 'Page renders: ' + path)
check(request('/?hours=1')[0] == 400, 'Unsupported windows rejected')
check(request('/endpoints/999999999')[0] == 404, 'Missing monitors are 404')
check(json.loads(request('/health')[2])['status'] == 'ok', 'Health probes database')
check(b'api_monitor_latency_p95_ms' in request('/metrics')[2], 'Prometheus exposes percentile')
for name, mime in [('app.css','text/css'), ('app.js','text/javascript'), ('favicon.svg','image/svg+xml')]:
    status, headers, body = request('/assets/' + name)
    check(status == 200 and headers.get('Content-Type','').startswith(mime) and len(body) > 50, 'Static asset ' + name)
check(request('/.env')[0] == 404, 'Environment file is not served')
for origin in [None, 'null', 'https://evil.example', 'http://127.0.0.1:19060.evil.example']:
    check(request('/endpoints/create', b'name=attacker', origin=origin)[0] == 403, 'Forged write refused: ' + str(origin))
check(request('/endpoints/create', b'x' * 131073)[0] == 413, 'Oversized bodies rejected')

def form(**changes):
    values = dict(name='Integration monitor', project='Test suite', url='http://127.0.0.1:19061/health', method='GET', contract=json.dumps({'type':'object', 'required':{'status':{'type':'string'}}, 'allow_extra_fields':True}))
    values.update(changes)
    return urllib.parse.urlencode(values).encode()

for changes in [dict(name=''),dict(name='x'*121),dict(method='DELETE'),dict(url='file:///etc/passwd'),dict(url='http://u:p@127.0.0.1/'),dict(contract='{"type":"typo"}'),dict(contract='bad-json')]:
    check(request('/endpoints/create', form(**changes))[0] == 400, 'Invalid definition refused: ' + str(list(changes)))
status, headers, body = request('/endpoints/create', form(name='<script>alert(1)</script>'))
check(status == 303, 'Create uses POST/redirect/GET')
location = headers['Location']
try:
    status, headers, body = request(location)
    check(status == 200 and b'&lt;script&gt;' in body and b'<script>alert(1)</script>' not in body, 'Monitor names are escaped')
    check(request(location + '/toggle', b'')[0] == 303, 'Monitor can be paused')
    check(request(location + '/check', b'')[0] == 409, 'Paused monitor cannot run')
    check(request(location + '/toggle', b'')[0] == 303, 'Monitor can be resumed')
    check(request(location + '/check', b'')[0] == 303, 'Manual check persisted')
    check(request(location + '/check', b'')[0] == 429, 'Manual cooldown enforced')
    status, headers, body = request(location + '/export.csv')
    check(status == 200 and 'attachment' in headers['Content-Disposition'] and b'time_utc' in body, 'CSV exported as attachment')
    check(request(location + '/update', form(name='Updated monitor'))[0] == 303, 'Monitor can be edited')
finally:
    check(request(location + '/delete', b'')[0] == 303, 'Fixture cleaned up')
check(request(location)[0] == 404, 'Deleted monitor is no longer visible')
# A result started before pause/resume must not overwrite the new revision.
time.sleep(5.05)
status, headers, _ = request('/endpoints/create', form(name='Revision race', url='http://127.0.0.1:19061/slow'))
check(status == 303, 'Create race fixture')
race_location = headers['Location']
try:
    with ThreadPoolExecutor(max_workers=1) as worker:
        pending = worker.submit(request, race_location + '/check', b'')
        time.sleep(.3)
        check(request(race_location + '/toggle', b'')[0] == 303, 'Pause during in-flight check')
        check(request(race_location + '/toggle', b'')[0] == 303, 'Resume with a new revision')
        check(pending.result()[0] == 409, 'Stale in-flight result is discarded')
    csv = request(race_location + '/export.csv')[2].decode().strip().splitlines()
    check(len(csv) == 1, 'Stale result was not persisted')
finally:
    request(race_location + '/delete', b'')

for contract, response, valid in [({'type':'string'},'ok',True),({'type':'integer'},'oops',False),({'type':'typo'},None,False),({'type':'number','minimum':5},1,False)]:
    payload=json.dumps(dict(contract=contract,response=response)).encode()
    status, headers, body=request('/api/validate', payload, content_type='application/json')
    check(status == 200 and json.loads(body)['valid'] == valid, 'Playground validates schemas and responses')
print(f'{COUNT} HTTP integration assertions passed')
