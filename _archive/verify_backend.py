import urllib.request
import json
import urllib.error
import sys

BASE_URL = 'http://127.0.0.1:8001/api/v1/ecg'

def make_request(url, method='GET', data=None):
    print(f'\n--- {method} {url} ---')
    try:
        headers = {'Content-Type': 'application/json'} if data else {}
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req) as r:
            print(f'Status: {r.status}')
            resp_body = r.read().decode()
            print(f'Response: {resp_body[:200]}')
            return r.status, resp_body
    except urllib.error.HTTPError as e:
        print(f'HTTPError: {e.code} {e.reason}')
        if e.code == 307:
            loc = e.headers.get('Location')
            print(f'Redirect Location: {loc}')
            # Manually follow redirect for POST if needed
            if method == 'POST':
                print(f'Following redirect to {loc} with POST...')
                return make_request(loc, method='POST', data=data)
            elif method == 'GET':
                 print(f'Following redirect to {loc} with GET...')
                 return make_request(loc, method='GET')
        try:
            print(f'Error Body: {e.read().decode()}')
        except:
            pass
        return e.code, None
    except Exception as e:
        print(f'Exception: {e}')
        return None, None

# 1. Test GET /sessions
limit = 5
url = f'{BASE_URL}/sessions?limit={limit}'
status, body = make_request(url)

# 2. Test POST /sessions
session_data = {
    'name': 'Verification Session',
    'sampling_rate_hz': 360,
    'source': 'mock'
}
json_data = json.dumps(session_data).encode('utf-8')
url = f'{BASE_URL}/sessions'
status, body = make_request(url, method='POST', data=json_data)

if status in (200, 201) and body:
    s = json.loads(body)
    sid = s.get('id')
    print(f'Created Session ID: {sid}')
    
    # 3. Test Mock Sample Upload
    if sid:
        url = f'{BASE_URL}/sessions/{sid}/mock-sample'
        make_request(url, method='POST')

print('\nDone.')
