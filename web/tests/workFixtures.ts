// 受控 HTTP 用例仍使用正式 v1 响应结构，不替客户端补齐生产响应。
export const workCapabilities={contractVersion:1,enabled:true,configured:true,executionEnabled:false,imageEnabled:true,canCreateTask:true,actions:['CREATE_TASK','CHECK_DELIVERY'],limits:{text:10000,files:5,fileBytes:10485760,totalBytes:31457280,formats:['png','jpg','jpeg','pdf','docx','xlsx']}};
export function workFixture(value:Record<string,any>){
  const item=structuredClone({contractVersion:1,planVersion:0,eventsCursor:0,result:{},messages:[],steps:[],receipts:[],...value});
  item.messages=item.messages.map((message:any)=>({...message,body:{attachmentIds:[],...message.body}}));
  for(const result of [item.result,...item.receipts.map((receipt:any)=>receipt.result)])if(result?.report)result.report={findings:[],...result.report};
  return item;
}
export const workPage=(items:Record<string,any>[]=[],nextCursor=-1)=>({contractVersion:1,nextCursor,items:items.map(workFixture)});
