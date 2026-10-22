"""Twenty real JVM crashes before commit and twenty after commit, isolated DB only.

The PG barrier proves that the worker reached the business transaction. A forced
process kill aborts it. Lease expiry is deliberately advanced after the crash;
the restarted service must recover through its normal persistent worker path.
"""
import argparse
import hashlib
import json
import os
import secrets
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import psycopg2

ROOT = Path(__file__).resolve().parents[1]


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        value = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        data = json.loads(value['messages'][1]['content'])
        person = next(p for p in data['people'] if p['name']=='周宁')
        plan = dict(summary='恢复验收', answer='', questions=[], sourceIds=[], actions=[dict(type='CREATE_TASK', title='重启成本表', requirements='提交成本明细', ownerId=person['id'], ownerEvidence='周宁', deadline='2099-11-01T17:00:00+08:00', deadlineEvidence='2099年11月1日17:00')])
        body = json.dumps(dict(choices=[dict(message=dict(content=json.dumps(plan,ensure_ascii=False)))], usage=dict(total_tokens=100)),ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(body)


def main():
    args = argparse.ArgumentParser()
    args.add_argument('--container',required=True)
    args.add_argument('--output',default='output/ai-work-restarts')
    args.add_argument('--jar',default='server/target/collaboration-server-1.0.0.jar')
    options = args.parse_args()
    if not options.container.startswith('workpanel-it-data-'):
        raise SystemExit('Disposable acceptance data required')
    out=(ROOT/options.output).resolve()
    if not out.is_relative_to(ROOT/'output'):
        raise SystemExit('Invalid output path')
    out.mkdir(parents=True,exist_ok=True)
    meta=json.loads(subprocess.check_output(['docker','inspect',options.container]))[0]
    settings=dict(x.split('=',1) for x in meta['Config']['Env'] if '=' in x)
    port=lambda n:meta['NetworkSettings']['Ports'][f'{n}/tcp'][0]['HostPort']
    db=psycopg2.connect(host='127.0.0.1',port=port(5432),dbname='workpanel_test',user=settings['POSTGRES_USER'],password=settings['POSTGRES_PASSWORD'])
    db.autocommit=True
    def sql(query,params=(),one=False):
        with db.cursor() as cursor:
            cursor.execute(query,params)
            if cursor.description:
                rows=cursor.fetchall()
                return rows[0][0] if one else rows
    company='restart-'+secrets.token_hex(5)
    leader,owner=company+'-leader',company+'-owner'
    token=secrets.token_hex(32)
    sql("INSERT INTO companies(id,name) VALUES (%s,'进程故障验收'); INSERT INTO departments(id,company_id,name) VALUES (%s,%s,'测试部'); INSERT INTO teams(id,company_id,department_id,name) VALUES (%s,%s,%s,'测试组');",(company,company+'-d',company,company+'-t',company,company+'-d'))
    for user,name,role in [(leader,'负责人','LEADER'),(owner,'周宁','EMPLOYEE')]:
        sql("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,dispatch_enabled) VALUES (%s,%s,%s,'disabled',%s,%s,%s,%s,%s,'ACTIVE',true)",(user,company,user,user,name,company+'-d',company+'-t',role))
    sql("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES (%s,%s,now()+interval '4 hours')",(hashlib.sha256(token.encode()).hexdigest(),leader))
    provider=ThreadingHTTPServer(('127.0.0.1',0),Provider)
    threading.Thread(target=provider.serve_forever,daemon=True).start()
    env={**os.environ,'DB_URL':f'jdbc:postgresql://127.0.0.1:{port(5432)}/workpanel_test','DB_USER':settings['POSTGRES_USER'],'DB_PASSWORD':settings['POSTGRES_PASSWORD'],'REDIS_HOST':'127.0.0.1','REDIS_PORT':port(6379),'REDIS_PASSWORD':settings['REDIS_PASSWORD'],'NEO4J_URI':f'bolt://127.0.0.1:{port(7687)}','NEO4J_PASSWORD':settings['NEO4J_PASSWORD'],'DEEPSEEK_API_KEY':'isolated-controlled-provider','DEEPSEEK_BASE_URL':f'http://127.0.0.1:{provider.server_port}','AI_WORK_EXECUTION_ENABLED':'true','AI_DAILY_TOKENS':'500000','TEMP':str(ROOT/'output/ai-work-acceptance-temp'),'TMP':str(ROOT/'output/ai-work-acceptance-temp')}
    api_port=58086
    process=None
    log=(out/'server.log').open('wb')
    def request(method,path,body=None,key=None):
        headers={'Authorization':'Bearer '+token,'Idempotency-Key':key or secrets.token_hex(12),'Content-Type':'application/json'}
        data=json.dumps(body).encode() if body is not None else None
        with urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{api_port}/api'+path,data=data,headers=headers,method=method),timeout=15) as response:
            return json.load(response)
    def start():
        nonlocal process
        process=subprocess.Popen(['java','-Xmx384m','-XX:ActiveProcessorCount=2','-jar',str(ROOT/options.jar),f'--server.port={api_port}','--app.jobs-enabled=false','--app.memory-extract-enabled=false','--app.ai-work-poll-ms=100'],env=env,stdout=log,stderr=subprocess.STDOUT)
        for _ in range(90):
            if process.poll() is not None:
                raise RuntimeError('Restarted JVM exited')
            try:
                request('GET','/ai/work-capabilities')
                return
            except Exception:
                time.sleep(.5)
        raise RuntimeError('JVM health timeout')
    def kill():
        if process and process.poll() is None:
            process.kill()
            process.wait(15)
    def await_state(work,state):
        end=time.monotonic()+30
        while time.monotonic()<end:
            item=request('GET','/ai/work-items/'+work)
            if item['state']==state:
                return item
            if item['state']=='FAILED':
                raise RuntimeError('Work failed: '+json.dumps(item.get('result')))
            time.sleep(.15)
        raise RuntimeError('Work state timeout: '+item['state'])
    rows=[]
    try:
        start()
        for index in range(20):
            sql("UPDATE tasks SET title='历史恢复夹具-'||id WHERE company_id=%s",(company,))
            # Reset only this isolated actor's rate counter; no provider budget bypass.
            subprocess.run(['docker','exec',options.container,'redis-cli','-a',settings['REDIS_PASSWORD'],'DEL','workpanel:memory-model:'+leader,'workpanel:api:'+leader],capture_output=True,check=True)
            work=request('POST','/ai/work-items',dict(text='整理周宁在2099年11月1日17:00交付成本表的要求'))['id']
            ready=await_state(work,'WAITING_CONFIRMATION')
            body={k:ready[k] for k in ('version','planVersion','planHash','confirmationId')}
            body['actions']=['action-1']
            key=secrets.token_hex(16)
            barrier=730000+index
            function='restart_barrier_'+secrets.token_hex(5)
            sql(f"CREATE FUNCTION {function}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.work_id='{work}' THEN PERFORM pg_advisory_xact_lock({barrier}); END IF; RETURN NEW; END $$; CREATE TRIGGER {function} BEFORE INSERT ON ai_action_receipts FOR EACH ROW EXECUTE FUNCTION {function}();")
            sql('SELECT pg_advisory_lock(%s)',(barrier,))
            payload=json.dumps(body).encode()
            with socket.create_connection(('127.0.0.1',api_port),timeout=5) as wire:
                wire.sendall((f'POST /api/ai/work-items/{work}/confirm HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\nIdempotency-Key: {key}\r\nContent-Type: application/json\r\nContent-Length: {len(payload)}\r\nConnection: close\r\n\r\n').encode()+payload)
                # Connection ends without consuming the commit acknowledgement.
            end=time.monotonic()+15
            while not sql("SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND objid=%s::oid AND NOT granted",(barrier,),True):
                if time.monotonic()>end:
                    raise RuntimeError('Business transaction did not reach PG barrier')
                time.sleep(.05)
            kill()
            sql('SELECT pg_advisory_unlock(%s)',(barrier,))
            sql(f'DROP TRIGGER {function} ON ai_action_receipts; DROP FUNCTION {function}();')
            before=sql('SELECT count(*) FROM ai_action_receipts WHERE work_id=%s',(work,),True)
            assert before==0
            sql("UPDATE ai_work_steps SET lease_until=now()-interval '1 second' WHERE work_id=%s AND state='RUNNING'",(work,))
            start()
            done=await_state(work,'SUCCEEDED')
            task=done['receipts'][0]['result']['taskId']
            kill()
            start()
            for _ in range(20):
                request('POST','/ai/work-items/'+work+'/confirm',body,key)
            counts=sql("SELECT (SELECT count(*) FROM ai_action_receipts WHERE work_id=%s),(SELECT count(*) FROM task_events WHERE task_id=%s AND type='DISPATCHED'),(SELECT count(*) FROM audit_records WHERE object_id=%s AND type='AI_WORK_ACTION'),(SELECT count(*) FROM outbox_events WHERE object_id=%s AND type='TASK_DISPATCHED')",(work,task,work,task))[0]
            assert counts==(1,1,1,1),counts
            row=dict(iteration=index+1,preCommitCrashRolledBack=True,postCommitCrashReplayed=True,replays=20,receiptTaskAuditOutbox=list(counts))
            rows.append(row)
            (out/'result.json').write_text(json.dumps(dict(passed=len(rows)==20,physicalProcessKills=len(rows)*2,iterations=rows),indent=2),encoding='utf-8')
            print(json.dumps(row),flush=True)
    finally:
        kill()
        provider.shutdown()
        db.close()
        log.close()
    return 0


if __name__=='__main__':
    raise SystemExit(main())
