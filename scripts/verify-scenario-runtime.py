"""真实HTTP场景验收；只对显式初始化的scenario账号追加验收记录，不输出凭据。

python scripts/verify-scenario-runtime.py --credentials <ignored JSON> --output <directory>
凭据文件须有 baseUrl 和 password；输出中不包含请求头、密码或token。
"""
import argparse
import colorsys
import datetime as dt
import json
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    config = json.loads(pathlib.Path(args.credentials).read_text(encoding='utf-8-sig'))
    base = config['baseUrl'].rstrip('/')
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    results, tokens = [], {}
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=8)))
    today = now.date().isoformat()
    run = uuid.uuid4().hex[:10]

    def check(name, condition):
        results.append(dict(name=name, passed=bool(condition)))
        if not condition:
            raise AssertionError(name)

    def request(method, path, who=None, body=None, expected=(200,), key=None, raw=None, content_type=None):
        headers = {}
        if who:
            headers['Authorization'] = 'Bearer ' + tokens[who]
        if key:
            headers['Idempotency-Key'] = key
        if raw is not None:
            data = raw
            headers['Content-Type'] = content_type
        elif body is not None:
            data = json.dumps(body, ensure_ascii=False).encode()
            headers['Content-Type'] = 'application/json'
        else:
            data = None
        req = urllib.request.Request(base + path, data, headers, method=method)
        try:
            response = urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as error:
            response = error
        payload = response.read()
        kind = response.headers.get('Content-Type', '')
        value = json.loads(payload) if 'json' in kind else payload
        passed = response.code in expected
        results.append(dict(method=method, path=path, actor=who, status=response.code,
                            expected=list(expected), passed=passed,
                            errorCode=value.get('code') if isinstance(value, dict) else None))
        if not passed:
            raise AssertionError(f'{method} {path}: HTTP {response.code}, expected {expected}; {value}')
        return value

    def login(who, expected=(200,)):
        accounts = {'founder': 'boss', 'admin': 'admin', 'product-director': 'pd',
                    'engineering-director': 'rd', 'delivery-director': 'dd',
                    'product-lead': 'pl', 'design-lead': 'dl', 'backend-lead': 'bl',
                    'delivery-lead': 'tl', 'pending': 'new1', 'pending-delivery': 'new2',
                    'disabled': 'off', 'outsider': 'other'}
        response = request('POST', '/auth/login', body=dict(account=accounts.get(who, who),
                           password=config['password']), expected=expected)
        if 'token' in response:
            tokens[who] = response['token']
            expiry = dt.datetime.fromisoformat(response['expiresAt'].replace('Z', '+00:00'))
            check('session-168-hours-' + who, abs((expiry-dt.datetime.now(dt.timezone.utc)).total_seconds()/3600-168)<0.05)
        return response

    def event(task, who, action, text=None, version=None):
        command = dict(type=action, version=task['version'] if version is None else version)
        if text:
            command['text'] = text
        return request('POST', '/tasks/' + task['id'] + '/events', who, command)

    try:
        check('health-up', request('GET', '/health')['status'] == 'UP')
        for who in ['founder', 'admin', 'engineering-director', 'backend-lead', 'zhou', 'outsider', 'pending', 'pending-delivery']:
            login(who)
        login('disabled', (403,))
        request('GET', '/dashboard', 'pending-delivery', expected=(403,))
        labels = request('GET', '/task-labels', 'founder')['items']
        colors = {label['color'].upper() for label in labels}
        check('at-least-eight-distinct-label-colors', len(colors) >= 8)
        for color in colors:
            rgb = [int(color[i:i+2], 16)/255 for i in (1, 3, 5)]
            hue, lightness, saturation = colorsys.rgb_to_hls(*rgb)
            check('muted-label-' + color, saturation <= 0.4 and 0.7 <= lightness <= 0.9)
        for who in ['founder', 'admin', 'backend-lead', 'zhou']:
            request('GET', '/auth/me', who)
            request('GET', '/dashboard', who)
            request('GET', '/organization', who)
            request('GET', '/tasks?limit=100', who)
            request('GET', '/tasks/received-card?limit=100', who)
            request('GET', '/logs?date=' + today + '&period=month&limit=100', who)
            request('GET', '/analytics?date=' + today + '&period=month', who)
            request('GET', '/notifications', who)
        request('GET', '/profiles/scenario-zhou', 'zhou')
        request('GET', '/profiles/scenario-zhou', 'backend-lead')
        request('GET', '/profiles/scenario-zhou', 'outsider', expected=(403, 404))
        request('GET', '/tasks/scenario-task-09', 'outsider', expected=(403, 404))
        request('GET', '/logs/scenario-draft', 'founder', expected=(403, 404))
        request('GET', '/logs/scenario-draft', 'product-lead' if 'product-lead' in tokens else 'zhou', expected=(403, 404))
        request('GET', '/logs/subordinates?date=' + today + '&period=month', 'backend-lead')
        calendar = request('GET', '/logs/subordinates/calendar?ownerId=scenario-zhou&month=' + today[:7], 'backend-lead')
        check('calendar-has-submitted-days', 'SUBMITTED' in calendar['days'].values())
        request('GET', '/logs/subordinates', 'zhou', expected=(403,))
        request('GET', '/logs/subordinates/calendar?ownerId=scenario-chen&month=' + today[:7], 'backend-lead', expected=(403, 404))
        csv = request('GET', '/analytics/export?date=' + today + '&period=month&resource=logs', 'zhou')
        check('employee-export-no-other-author', '陈知夏'.encode() not in csv and '周启航'.encode() in csv)
        request('GET', '/analytics?date=' + today + '&period=month&ownerId=scenario-chen', 'zhou', expected=(403, 404))
        downloaded = request('GET', '/attachments/scenario-file-1', 'founder')
        check('seed-attachment-has-real-bytes', '商户经营看板'.encode() in downloaded)
        request('GET', '/attachments/scenario-file-1', 'outsider', expected=(403, 404))

        # 同一审核申请重放；审批前不存在正式任务，直属上级一次决定后才生效。
        deadline = (now + dt.timedelta(days=4)).isoformat()
        draft = dict(title='联调验收：核对退款指标与导出一致性 ' + run,
                     participants=['scenario-zhou', 'scenario-zhao'], deadline=deadline,
                     urgency='NORMAL', content='验收材料包含跨日退款、空数据和同公司授权范围。', attachments=[])
        key = 'scenario-runtime-' + run
        review = request('POST', '/tasks', 'backend-lead', draft, key=key)
        repeated = request('POST', '/tasks', 'backend-lead', draft, key=key)
        check('task-review-idempotency', repeated['id'] == review['id'])
        check('single-direct-reviewer', len(review['steps']) == 1 and review['reviewer_id'] == 'scenario-engineering-director')
        request('GET', '/tasks/' + review['target_id'], 'backend-lead', expected=(404,))
        decision = dict(approve=True, expectedVersion=review['expected_version'])
        request('POST', '/reviews/' + review['id'] + '/decision', 'backend-lead', decision, expected=(403,))
        request('POST', '/reviews/' + review['id'] + '/decision', 'engineering-director',
                dict(approve=True, expectedVersion=99), expected=(409,))
        request('POST', '/reviews/' + review['id'] + '/decision', 'engineering-director', decision)
        task = request('GET', '/tasks/' + review['target_id'], 'zhou')
        request('POST', '/tasks/' + task['id'] + '/events', 'zhou', dict(type='RECEIVED', version=99), expected=(409,))
        task = event(task, 'zhou', 'RECEIVED')
        task = event(task, 'zhou', 'FEEDBACK', '已核对退款归属日期；提交差异清单，等待复核。')
        task = event(task, 'backend-lead', 'RETURNED', '请补充空数据门店的导出样例。')
        task = event(task, 'zhou', 'FEEDBACK', '已补充空数据样例，指标与导出一致。')
        task = event(task, 'backend-lead', 'ACCEPTED')
        task = event(task, 'backend-lead', 'ARCHIVED')
        check('task-lifecycle-archived', task['events'][-1]['to_phase'] == 'ARCHIVED')
        comment = request('POST', '/tasks/' + task['id'] + '/comments', 'zhou', dict(text='联调验收完成，记录归档。'), key=key+'-comment')
        request('POST', '/tasks/' + task['id'] + '/comments', 'backend-lead',
                dict(text='已复核，保留本次验收材料。', parentId=comment['id']), key=key+'-reply')
        request('POST', '/tasks/' + task['id'] + '/comments', 'zhou', dict(text='缺少幂等键'), expected=(400,))
        founder = request('POST', '/tasks', 'founder', dict(title='联调验收：创始人确认上线检查 '+run,
                          participants=['scenario-backend-lead'], deadline=deadline, urgency='NORMAL'), key=key+'-founder')
        check('founder-exemption', founder['status'] == 'APPROVED' and founder['decision_source'] == 'FOUNDER_EXEMPT' and not founder['steps'])
        founder_task = request('GET', '/tasks/' + founder['target_id'], 'founder')
        event(founder_task, 'founder', 'WITHDRAWN', '本条用于本地链路验收，已完成检查。')

        # 当前日志正文接口、版本冲突、作者限制及旧路由404。
        logs = request('GET', '/logs?date=' + today + '&period=day', 'zhou')['items']
        log = next(x for x in logs if x['owner_id'] == 'scenario-zhou')
        previous = log['version']
        updated = request('PUT', '/logs/' + log['id'] + '/content', 'zhou',
                          dict(work=log['body']['work']+' 补充：已通过本地端到端接口复核。', version=previous))
        request('PUT', '/logs/' + log['id'] + '/content', 'zhou', dict(work='旧版本覆盖', version=previous), expected=(409,))
        request('PUT', '/logs/' + log['id'] + '/content', 'backend-lead', dict(work='上级修改正文', version=updated['version']), expected=(403,))
        comment = request('POST', '/logs/' + log['id'] + '/comments', 'backend-lead', dict(text='复核了关联任务，请保留差异记录。'))
        request('POST', '/logs/' + log['id'] + '/comments', 'zhou', dict(text='收到，已归档至任务。', parentId=comment['id']))
        versions = request('GET', '/logs/' + log['id'] + '/versions', 'zhou')
        check('direct-log-update-has-history', len(versions) >= 2)
        for suffix in ['read', 'revisions', 'withdraw']:
            request('POST', '/logs/' + log['id'] + '/' + suffix, 'zhou', dict(version=updated['version']), expected=(404,))
        tomorrow = (now.date() + dt.timedelta(days=1)).isoformat()
        future_logs = request('GET', '/logs?date=' + tomorrow + '&period=day', 'zhou')['items']
        existing_future = next((x for x in future_logs if x['owner_id'] == 'scenario-zhou'), None)
        future = request('PUT', '/logs/draft', 'zhou', dict(businessDate=tomorrow,
                         version=existing_future['version'] if existing_future else 0,
                         body=dict(work='明日计划草稿，不作为已提交日报。')))
        request('POST', '/logs/'+future['id']+'/submit', 'zhou', dict(version=future['version']), expected=(400,))
        request('GET', '/logs/'+future['id'], 'backend-lead', expected=(403, 404))

        # 成员确认仍由管理员决定；留一个待确认账号用于后续手工演示。
        membership = request('GET', '/reviews/scenario-pending-membership', 'admin')
        if membership['status'] == 'PENDING':
            request('POST', '/reviews/'+membership['id']+'/decision', 'admin', dict(approve=True, expectedVersion=membership['expected_version']))
        activated = request('GET', '/auth/me', 'pending')
        check('admin-membership-activation', activated['status'] == 'ACTIVE')
        request('GET', '/dashboard', 'pending')
        time.sleep(3)
        notices = request('GET', '/notifications', 'backend-lead')
        check('outbox-delivered-notifications', len(notices['items']) > 0)
        request('POST', '/auth/logout', 'outsider', {})
        request('GET', '/auth/me', 'outsider', expected=(401,))
    finally:
        summary = dict(run=run, baseUrl=base, checks=len(results), passed=sum(x['passed'] for x in results),
                       failed=sum(not x['passed'] for x in results), results=results)
        (output/'http-results.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({k: summary[k] for k in ['run', 'checks', 'passed', 'failed']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
