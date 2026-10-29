import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';
const [modulePath,path,implementation,encoding,scope,kind,target]=process.argv.slice(2);
const api=await import(pathToFileURL(modulePath));
const prepared=path==='@large'?api.sink_large():api.sink_prepare(fs.readFileSync(path));
const before=process.resourceUsage().maxRSS*1024;
let owned=false,stats,output;
function run(){
 let fd=null,temporary=null,created=false;
 stats={requests:0,max_request:0,written_bytes:0};
 try{
  const writer=(offset,buffer,start,count)=>{
   stats.requests++;stats.max_request=Math.max(stats.max_request,count);
   try{
    if(scope==='file'&&fd===null){temporary=target+'.tmp';fd=fs.openSync(temporary,'wx+');created=true;}
    const n=scope==='file'?fs.writeSync(fd,buffer,start,count,offset):count;
    stats.written_bytes+=n;return n;
   }catch{return -1;}
  };
  const result=JSON.parse(api.sink_run(prepared,implementation==='old',encoding==='compressed',writer,writer));
  if(result.status!=='ok')throw Object.assign(new Error(result.code),{matCode:result.code});
  if(scope==='file'){
   if(fs.fstatSync(fd).size!==result.bytes)throw new Error('size mismatch');
   const closing=fd;fd=null;fs.closeSync(closing);fs.linkSync(temporary,target);owned=true;
  }
  return result.bytes;
 }finally{
  try{if(fd!==null)fs.closeSync(fd);}finally{if(created)fs.unlinkSync(temporary);}
 }
}
const samples=[];
try{
 for(let i=0;i<(kind==='memory'?1:15);i++){
  if(owned){fs.unlinkSync(target);owned=false;}
  global.gc?.();const start=performance.now();output=run();const elapsed=performance.now()-start;
  if(kind==='memory'||i>=5)samples.push(elapsed);
 }
 console.log(JSON.stringify({status:'ok',samples_ms:samples,peak_bytes:process.resourceUsage().maxRSS*1024,peak_before_bytes:before,output_bytes:output,...stats}));
}catch(error){console.log(JSON.stringify({status:'error',code:error.matCode??error.message}));process.exitCode=error.matCode?0:1;}
