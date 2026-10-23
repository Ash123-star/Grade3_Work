import {workFixture, workPage, workCapabilities} from './workFixtures';
import {test, expect, type Page} from '@playwright/test';
import {readWorkEvents, WorkEventCursor} from '../src/workEvents';

test('stream parses split UTF8 and CRLF and rejects duplicate or older cursors', async () => {
  const text=': connected\r\n\r\nid: 9007199254740993\r\nevent: change\r\ndata:{"version":4,\r\ndata: "title":"报价单 hello world"}\r\n\r\n';
  const bytes=new TextEncoder().encode(text);
  const body=new ReadableStream<Uint8Array>({start(controller){for(let i=0;i<bytes.length;i+=2)controller.enqueue(bytes.slice(i,i+2));controller.close();}});
  const events:any[]=[];
  await readWorkEvents(new Response(body,{headers:{'Content-Type':'text/event-stream'}}),new AbortController().signal,event=>events.push(event));
  expect(events).toHaveLength(1);
  expect(JSON.parse(events[0].data).title).toBe('报价单 hello world');
  const cursor=new WorkEventCursor();
  expect(cursor.accept(events[0])).toBe(true);
  expect(cursor.accept(events[0])).toBe(false);
  expect(cursor.accept({...events[0],id:'9007199254740992'})).toBe(false);
  expect(cursor.accept({...events[0],id:'wrong'})).toBe(false);
  expect(cursor.value).toBe('9007199254740993');
});

async function prepareStream(page:Page){
  await page.addInitScript(()=>{
    sessionStorage.setItem('workpanel-token','first-token');
    const original=window.fetch.bind(window), streams:any[]=[];
    (window as any).workStreams=streams;
    window.fetch=(input,init)=>{
      const path=String(input);
      if(!path.endsWith('/stream'))return original(input,init);
      const body=new ReadableStream<Uint8Array>({start(controller){streams.push({controller,path,headers:init?.headers});}});
      return Promise.resolve(new Response(body,{headers:{'Content-Type':'text/event-stream'}}));
    };
  });
}
async function emit(page:Page,event:string){await page.evaluate(value=>{const streams=(window as any).workStreams;streams[streams.length-1].controller.enqueue(new TextEncoder().encode(value));},event);}
const base={id:'work-live',title:'交付事项',state:'WAITING_INPUT',version:3,messages:[{id:'private',body:{text:'私人材料内容'}}],plan:{},steps:[],receipts:[],result:{summary:'请补充日期'}};

test('live work keeps newest state, ignores replay and clears all content on stream denial', async ({page},info)=>{
  await prepareStream(page);let item:any=base,gets=0;
  await page.route('**/api/**',async route=>{
    const path=new URL(route.request().url()).pathname;let data:any={};
    if(path==='/api/admin/workspace/ai-maps/development')data={scopes:[],analysis:{}};
    else if(path==='/api/auth/me')data={role:'ADMIN',must_change_password:false};
    else if(path==='/api/admin/workspace/ai/work-items')data=workPage([item]);
    else if(path==='/api/admin/workspace/ai/work-items/work-live'){gets++;data=workFixture(item);}
    await route.fulfill({contentType:'application/json',body:JSON.stringify(data)});
  });
  await page.goto('/');await page.getByRole('button',{name:/交付事项/}).click();
  await expect.poll(()=>gets).toBeGreaterThanOrEqual(2);
  await expect(page.getByText('请补充日期',{exact:true})).toBeVisible();
  const headers=await page.evaluate(()=>(window as any).workStreams[0]);
  expect(headers.path).toBe('/api/admin/workspace/ai/work-items/work-live/stream');expect(headers.headers.Authorization).toBe('Bearer first-token');expect(headers.headers['Last-Event-ID']).toBe('0');
  item={...base,version:5,state:'SUCCEEDED',result:{summary:'任务已创建'}};
  await emit(page,'id: 12\nevent: change\ndata: {"version":5}\n\n');
  await expect(page.getByText('任务已创建',{exact:true})).toBeVisible();const count=gets;
  await emit(page,'id: 12\nevent: change\ndata: {"version":5}\n\nid: 8\nevent: change\ndata: {"version":2}\n\n');
  // 用后续同一流的有效事件作同步屏障。
  item={...base,version:2,result:{summary:'过时的结果'}};
  await emit(page,'id: 13\nevent: change\ndata: {"version":2}\n\n');
  await expect.poll(()=>gets).toBe(count+1);
  await expect(page.getByText('任务已创建',{exact:true})).toBeVisible();expect(await page.getByText('过时的结果').count()).toBe(0);
  await page.evaluate(()=>{const streams=(window as any).workStreams;streams[streams.length-1].controller.close();});
  await expect.poll(()=>page.evaluate(()=>(window as any).workStreams.length)).toBe(2);
  expect(await page.evaluate(()=>(window as any).workStreams[1].headers['Last-Event-ID'])).toBe('13');
  await expect(page.getByText('任务已创建',{exact:true})).toBeVisible();
  item={...base,version:5,state:'SUCCEEDED',plan:{},result:{summary:'依据已更新，请重新核对'}};
  await emit(page,'event: refresh\ndata: {"version":5}\n\n');
  await expect(page.getByText('依据已更新，请重新核对',{exact:true})).toBeVisible();
  await page.getByRole('textbox',{name:'要办什么'}).fill('未发送的私人内容');
  await emit(page,'event: access-lost\ndata: {"status":404}\n\n');
  await expect(page.getByRole('alert')).toContainText('无法查看');
  await expect(page.getByText('私人材料内容')).toHaveCount(0);await expect(page.getByText('依据已更新，请重新核对')).toHaveCount(0);
  await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('');
  await page.screenshot({path:info.outputPath('stream-access-cleared.png'),fullPage:true});
});

test('logout fences a delayed private response before the next account signs in',async({page})=>{
  await prepareStream(page);let hold=false,release:()=>void=()=>{};
  const gate=new Promise<void>(resolve=>release=resolve);let pending=false;
  await page.route('**/api/**',async route=>{
    const path=new URL(route.request().url()).pathname,token=route.request().headers().authorization;let data:any={};
    if(path==='/api/admin/workspace/ai-maps/development')data={scopes:[],analysis:{}};
    else if(path==='/api/auth/me')data={role:'ADMIN',must_change_password:false};
    else if(path==='/api/auth/login')data={token:'second-token',user:{role:'ADMIN',must_change_password:false}};
    else if(path==='/api/admin/workspace/ai/work-items')data=workPage(token==='Bearer first-token'?[base]:[]);
    else if(path==='/api/admin/workspace/ai/work-items/work-live'){if(hold){pending=true;await gate;}data=workFixture({...base,result:{summary:'旧账号的延迟响应'}});}
    await route.fulfill({contentType:'application/json',body:JSON.stringify(data)}).catch(()=>{});
  });
  await page.goto('/');await page.getByRole('button',{name:/交付事项/}).click();
  await expect(page.getByText('私人材料内容')).toBeVisible();
  hold=true;await emit(page,'id: 20\nevent: change\ndata: {"version":7}\n\n');await expect.poll(()=>pending).toBe(true);
  await page.getByRole('button',{name:'退出',exact:true}).click();
  await page.getByRole('textbox',{name:'账号',exact:true}).fill('second');await page.getByLabel('密码',{exact:true}).fill('test-password');
  await page.getByRole('button',{name:'登录',exact:true}).click();
  await expect(page.getByRole('heading',{name:'把事情交给我'})).toBeVisible();release();
  await expect(page.getByText('旧账号的延迟响应')).toHaveCount(0);await expect(page.getByText('私人材料内容')).toHaveCount(0);
  await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('');
});
