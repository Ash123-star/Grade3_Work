"""Real OCR/DeepSeek acceptance on disposable Docker data; no formal AI writes.

Run after the standard backend checks and sandbox image build. The manifest is
synthetic, expectations are independent of provider output, and empty plans do
not count as successful extraction. Credentials never enter the evidence report.
"""
import argparse
import hashlib
from decimal import Decimal
import importlib.util
import json
import os
import secrets
import statistics
import subprocess
import time
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def docker(*args, **kwargs):
    return subprocess.check_output(['docker', *args], **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--image', default='workpanel-backend:ai-work-assistant')
    parser.add_argument('--output', default='output/ai-work-corpus')
    parser.add_argument('--case',type=int,action='append',help='Diagnostic subset; never counts as complete corpus acceptance')
    parser.add_argument('--chain',choices=['intake','knowledge','delivery'],help='Affected chain recheck; incomplete coverage on its own')
    args = parser.parse_args()
    if not args.container.startswith('workpanel-it-data-'):
        raise SystemExit('Disposable acceptance data container required')
    out = (ROOT/args.output).resolve()
    if not out.is_relative_to(ROOT/'output'):
        raise SystemExit('Evidence must stay within output')
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('corpus', ROOT/'scripts/ai-work-acceptance-corpus.py')
    corpus = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(corpus)
    cases = corpus.generate(out/'materials')
    if args.case:
        cases=[case for case in cases if case['index'] in args.case]
    if args.chain:
        cases=[case for case in cases if case['chain']==args.chain]
    if not cases:
        raise SystemExit('No matching acceptance cases')
    meta = json.loads(docker('inspect', args.container))[0]
    settings = dict(v.split('=', 1) for v in meta['Config']['Env'] if '=' in v)

    def sql(statement):
        result = subprocess.run(['docker', 'exec', '-i', args.container, 'psql', '-U', settings['POSTGRES_USER'], '-d', 'workpanel_test', '-v', 'ON_ERROR_STOP=1', '-tA'], input=statement.encode(), capture_output=True)
        if result.returncode:
            raise RuntimeError('Isolated fixture SQL failed: '+result.stderr.decode(errors='replace')[:500])
        return result.stdout.decode().strip()

    def literal(value):
        return "'"+str(value).replace("'", "''")+"'"

    config = dict(DB_URL=f'jdbc:postgresql://{args.container}:5432/workpanel_test', DB_USER=settings['POSTGRES_USER'], DB_PASSWORD=settings['POSTGRES_PASSWORD'], REDIS_HOST=args.container, REDIS_PORT='6379', REDIS_PASSWORD=settings['REDIS_PASSWORD'], NEO4J_URI=f'bolt://{args.container}:7687', NEO4J_PASSWORD=settings['NEO4J_PASSWORD'], AI_WORK_EXECUTION_ENABLED='false', AI_OCR_ENABLED='true', AI_OCR_URL='http://workpanel-ai-ocr:8000', AI_DAILY_TOKENS='500000', JAVA_TOOL_OPTIONS='-XX:MaxRAMPercentage=70 -XX:ActiveProcessorCount=2')
    for line in (ROOT/'output/stage-demo/stage.env').read_text(encoding='utf-8-sig').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            if key in ('DEEPSEEK_API_KEY', 'DEEPSEEK_BASE_URL', 'DEEPSEEK_MODEL'):
                config[key] = value.strip().strip('"\'')
    if not config.get('DEEPSEEK_API_KEY'):
        raise SystemExit('Provider configuration unavailable')
    balance_base=config.get('DEEPSEEK_BASE_URL','https://api.deepseek.com').rstrip('/')
    def balance():
        try:
            with urllib.request.urlopen(urllib.request.Request(balance_base+'/user/balance',headers={'Authorization':'Bearer '+config['DEEPSEEK_API_KEY']}),timeout=15) as response:
                result=json.load(response)
            return {r['currency']:str(r['total_balance']) for r in result.get('balance_infos',[])}
        except Exception:
            return {}
    initial_balance=balance()
    # Only synthetic acceptance traffic passes this local audit gateway. Capture
    # provider JSON for schema diagnosis without writing authorization headers.
    provider_base = config.get('DEEPSEEK_BASE_URL','https://api.deepseek.com').rstrip('/')
    class ProviderAudit(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_POST(self):
            if self.path!='/chat/completions' or self.headers.get('Authorization')!='Bearer '+config['DEEPSEEK_API_KEY']:
                self.send_error(404)
                return
            payload=self.rfile.read(int(self.headers['Content-Length']))
            status=200
            try:
                with urllib.request.urlopen(urllib.request.Request(provider_base+self.path,data=payload,headers={'Content-Type':'application/json','Authorization':'Bearer '+config['DEEPSEEK_API_KEY']}),timeout=60) as response:
                    content=response.read()
            except urllib.error.HTTPError as error:
                status,content=error.code,error.read()
            except Exception:
                self.send_error(503)
                return
            trace=out/('provider-'+secrets.token_hex(8)+'.json')
            trace.write_text(json.dumps(dict(request=json.loads(payload),status=status,response=json.loads(content)),ensure_ascii=False,indent=2),encoding='utf-8')
            self.send_response(status)
            self.send_header('Content-Type','application/json')
            self.end_headers()
            self.wfile.write(content)
    audit=ThreadingHTTPServer(('0.0.0.0',0),ProviderAudit)
    threading.Thread(target=audit.serve_forever,daemon=True).start()
    config['DEEPSEEK_BASE_URL']=f'http://host.docker.internal:{audit.server_port}'
    network = 'workpanel-ai-service'
    subprocess.run(['docker', 'network', 'connect', network, args.container], capture_output=True)
    name = 'workpanel-it-corpus-'+secrets.token_hex(4)
    command = ['docker', 'run', '-d', '--name', name, '--network', network, '--memory', '768m', '--cpus', '2', '-p', '127.0.0.1::8080']
    for key in config:
        command += ['--env', key]
    command += [args.image, '--app.jobs-enabled=false', '--app.memory-extract-enabled=false']
    subprocess.run(command, env={**os.environ, **config}, check=True, capture_output=True)
    subprocess.run(['docker', 'network', 'connect', 'workpanel-ai-parser', name], check=True, capture_output=True)
    port = json.loads(docker('inspect', name))[0]['NetworkSettings']['Ports']['8080/tcp'][0]['HostPort']

    def request(token, method, path, body=None, raw=None, mime=None, key=None):
        headers = {'Authorization': 'Bearer '+token, 'Idempotency-Key': key or secrets.token_hex(16)}
        if body is not None:
            raw = json.dumps(body, ensure_ascii=False).encode()
            headers['Content-Type'] = 'application/json'
        if mime:
            headers['Content-Type'] = mime
        with urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{port}/api'+path, data=raw, headers=headers, method=method), timeout=60) as response:
            return json.load(response)

    rows = []
    try:
        for _ in range(90):
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/health', timeout=2):
                    break
            except Exception:
                time.sleep(1)
        else:
            raise RuntimeError('Acceptance service did not become healthy')
        for case in cases:
            started = time.perf_counter()
            row = {k: case[k] for k in ('index', 'chain', 'variant')}
            try:
                company = 'corpus-'+secrets.token_hex(6)
                leader, owner = company+'-leader', company+'-owner'
                token = secrets.token_hex(32)
                sql(f"INSERT INTO companies(id,name) VALUES ('{company}','合成材料验收'); INSERT INTO departments(id,company_id,name) VALUES ('{company}-d','{company}','测试部'); INSERT INTO teams(id,company_id,department_id,name) VALUES ('{company}-t','{company}','{company}-d','测试组'); INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,dispatch_enabled) VALUES ('{leader}','{company}','{leader}','disabled','{leader}','验收负责人','{company}-d','{company}-t','LEADER','ACTIVE',true),('{owner}','{company}','{owner}','disabled','{owner}','周宁','{company}-d','{company}-t','EMPLOYEE','ACTIVE',false); INSERT INTO sessions(token_hash,user_id,expires_at) VALUES ('{hashlib.sha256(token.encode()).hexdigest()}','{leader}',now()+interval '4 hours');")
                if case['variant'] == 'duplicate_name':
                    sql(f"INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status) VALUES ('{owner}-2','{company}','{owner}-2','disabled','{owner}-2','周宁','{company}-d','{company}-t','EMPLOYEE','ACTIVE');")
                document = company+'-rule'
                if case['chain'] == 'knowledge' and case['variant'] != 'absent':
                    for i in range(2 if case['variant'] == 'conflict' else 1):
                        doc = document+str(i)
                        body = dict(title=case['title']+'制度'+str(i), type='POLICY', scopeKind='COMPANY', content=case['policyContent'] if i == 0 else case['title']+'无需提供成本明细与复核记录。')
                        effective = "now()-interval '2 days',now()-interval '1 day'" if case['variant'] == 'expired' else 'now(),NULL'
                        sql(f"INSERT INTO procedure_documents(id,company_id,owner_id,type,title,scope_kind,state,active_version) VALUES ('{doc}','{company}','{leader}','POLICY',{literal(body['title'])},'COMPANY','PUBLISHED',1); INSERT INTO procedure_versions(company_id,document_id,version,body,effective_from,effective_to) VALUES ('{company}','{doc}',1,{literal(json.dumps(body,ensure_ascii=False))}::jsonb,{effective});")
                path = Path(case['path'])
                boundary = secrets.token_hex(16)
                raw = f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{path.name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()+path.read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
                file = request(token, 'POST', '/attachments?purpose=AI_WORK', raw=raw, mime='multipart/form-data; boundary='+boundary)
                body = {'text': '请根据材料整理任务，缺少必要信息时请追问。' if case['chain']=='intake' else f"查找{case['title']}适用的公司正式制度和办理材料" if case['chain']=='knowledge' else '只检查这份材料，不提交。', 'attachmentIds': [file['id']]}
                if case['chain']=='delivery':
                    requirement = dict(id='cost', title='成本核对', required=True, field='成本', expected=case['amount'], unit='元')
                    checklist = [requirement]
                    if case['variant']=='signature':
                        checklist.append(dict(id='signature', title='核实签字真实性', required=True))
                    task = request(token, 'POST', '/tasks', dict(title=case['title'], ownerId=owner, deadline=case['deadline']+':00+08:00', acceptanceChecklist=checklist))
                    body.update(taskId=task['id'], taskVersion=task['version'])
                item = request(token, 'POST', '/ai/work-items', body)
                end = time.monotonic()+240
                while item['state'] in ('QUEUED','PREPARING','EXECUTING') and time.monotonic()<end:
                    time.sleep(.5)
                    item = request(token,'GET','/ai/work-items/'+item['id'])
                plan = item.get('plan', {})
                actions = plan.get('actions', [])
                questions = plan.get('questions', [])
                row.update(state=item['state'], questions=len(questions), actions=len(actions), workId=item['id'], criticalMismatch=False)
                extraction = json.loads(sql(f"SELECT coalesce(jsonb_agg(body),'[]') FROM ai_file_extractions WHERE company_id='{company}';"))
                parts = [part for f in extraction for part in f.get('parts', [])]
                row['locatedParts'] = sum(bool(p.get('locator')) for p in parts)
                row['extractedParts'] = len(parts)
                row['fileFieldsCorrect'] = sum(any(value in p.get('text','') for p in parts) for value in [case['title']] + ([case['amount']] if case['chain']!='knowledge' and case['variant'] not in ('mismatch','missing_field') else []))
                row['fileFieldsTotal'] = 1+(case['chain']!='knowledge' and case['variant'] not in ('mismatch','missing_field'))
                if case['chain']=='intake':
                    create = [a for a in actions if a['type']=='CREATE_TASK']
                    row['criticalMismatch'] = any(a['type']!='CREATE_TASK' for a in actions) or any(a['payload'].get('ownerId')!=owner or a['payload'].get('deadline','')[:16]!=case['deadline'] for a in create) or bool(case['expectedClarification'] and create)
                    row['expectationMet'] = bool(questions) and not create if case['expectedClarification'] else bool(create) or (case['variant']=='blur' and bool(questions))
                    row['fieldsCorrect'] = sum(a['payload'].get('ownerId')==owner for a in create)+sum(a['payload'].get('deadline','')[:16]==case['deadline'] for a in create)
                    row['fieldsTotal'] = 0 if case['expectedClarification'] else 2
                elif case['chain']=='knowledge':
                    refs = plan.get('sources', [])
                    row['expectationMet'] = bool(refs) and (bool(questions) if case['variant']=='conflict' else bool(plan.get('answer'))) if case['variant'] not in ('absent','expired') else not refs and '没有找到' in plan.get('answer','')
                    row['criticalMismatch'] = bool(actions) or bool(refs and case['variant'] in ('absent','expired'))
                    row['fieldsCorrect'] = int(row['expectationMet'])
                    row['fieldsTotal'] = 1
                    row['sourceLocators'] = sum(bool(e.get('locator')) for ref in refs for e in ref.get('excerpts', []))
                else:
                    reports = [r.get('result',{}).get('report',{}) for r in item.get('receipts',[]) if r.get('result',{}).get('kind')=='DELIVERY_CHECKED']
                    report = reports[0] if reports else {}
                    expected = 'NEEDS_FIX' if case['variant']=='mismatch' else 'UNVERIFIABLE' if case['variant'] in ('missing_field','formula','signature','blur') else 'PASS'
                    row.update(expectedCheck=expected, actualCheck=report.get('state'), findings=report.get('findings', []))
                    # Unreadable or explicitly absent data may stop before the
                    # report. An absent value additionally needs a targeted
                    # question and independent evidence in the uploaded text.
                    missing_cost = case['variant']=='missing_field' and any('成本尚未填写' in p.get('text','') for p in parts) and any('成本' in q and '补充' in q for q in questions)
                    safe_pause = expected=='UNVERIFIABLE' and item['state']=='WAITING_INPUT' and bool(questions) and not reports and (any(f.get('unverifiable') for f in extraction) or missing_cost)
                    row['safelyPausedForUnverifiableMaterial']=bool(safe_pause)
                    row['expectationMet'] = report.get('state')==expected or safe_pause
                    row['criticalMismatch'] = (expected!='PASS' and report.get('state')=='PASS') or any(a['type']!='CHECK_DELIVERY' for a in actions)
                    row['fieldsCorrect'],row['fieldsTotal'] = int(row['expectationMet']),1
                row['tokens'] = int(sql(f"SELECT coalesce(sum(tokens),0) FROM memory_model_calls WHERE company_id='{company}';"))
                row['providerCalls'] = int(sql(f"SELECT count(*) FROM memory_model_calls WHERE company_id='{company}' AND state='SUCCEEDED';"))
                row['formalWrites'] = int(sql(f"SELECT count(*) FROM ai_action_receipts WHERE work_id='{item['id']}' AND result->>'kind'<>'DELIVERY_CHECKED';"))
                row['passed'] = row['expectationMet'] and not row['criticalMismatch'] and row['providerCalls']>0 and item['state']!='FAILED' and row['formalWrites']==0
                (out/f"response-{case['index']:02}.json").write_text(json.dumps(item,ensure_ascii=False,indent=2),encoding='utf-8')
            except Exception as error:
                row.update(passed=False,error=type(error).__name__+': '+str(error)[:500])
            row['observedAccountBalance']=balance()
            row['seconds'] = round(time.perf_counter()-started,3)
            rows.append(row)
            summary = dict(synthetic=True, productionAccuracyClaim=False, executionEnabled=False, completed=len(rows), passed=sum(r['passed'] for r in rows), criticalMismatches=sum(r.get('criticalMismatch',False) for r in rows), tokens=sum(r.get('tokens',0) for r in rows), observedAccountDeduction={currency:str(Decimal(value)-Decimal(row['observedAccountBalance'][currency])) for currency,value in initial_balance.items() if currency in row['observedAccountBalance']}, costNote='Observed account balance change during this run; includes concurrent account traffic and provider billing precision. Not an exact per-request invoice.', medianSeconds=statistics.median(r['seconds'] for r in rows), p95Seconds=sorted(r['seconds'] for r in rows)[max(0,int(len(rows)*.95)-1)], fieldAccuracy=sum(r.get('fieldsCorrect',0) for r in rows)/max(1,sum(r.get('fieldsTotal',0) for r in rows)), extractionFieldAccuracy=sum(r.get('fileFieldsCorrect',0) for r in rows)/max(1,sum(r.get('fileFieldsTotal',0) for r in rows)), clarificationRate=sum(r.get('questions',0)>0 for r in rows)/len(rows), locationRate=sum(r.get('locatedParts',0) for r in rows)/max(1,sum(r.get('extractedParts',0) for r in rows)), imageId=json.loads(docker('inspect',name))[0]['Image'], samples=rows)
            (out/'result.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps(row,ensure_ascii=False),flush=True)
    finally:
        (out/'server.log').write_bytes(docker('logs',name,stderr=subprocess.STDOUT))
        subprocess.run(['docker','rm','-f',name],capture_output=True)
        audit.shutdown()
    # Subsets have an explicit completed count in result.json; success here only
    # means the selected run passed, never that full corpus coverage was met.
    return 0 if len(rows)==len(cases) and all(r['passed'] for r in rows) else 1


if __name__=='__main__':
    raise SystemExit(main())
