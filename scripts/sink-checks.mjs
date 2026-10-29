import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,existsSync,readdirSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {root,version} from './moon.mjs';
const api=await import(pathToFileURL(join(root,'_build/js/release/build/bridge/bridge.js')));
const directory=mkdtempSync(join(root,'verification/local/sink-checks-'));
const cli=join(root,'scripts/cli.mjs');
const fixture=join(root,'examples/mixed/research-mixed-compressed.mat');
const input=readFileSync(fixture);
function status(result){const s=JSON.parse(result);if(s.status==='error')throw new Error(JSON.stringify(s));return s;}
const old=api.roundtrip_mat(input);status(api.result_status(old));const expected=api.result_bytes(old);
for(const short of [1,3,1048576]){
 const output=Buffer.alloc(expected.length);let requests=0,largest=0;
 const sink=api.make_sink((offset,buffer,start,count)=>{const n=Math.min(short,count);output.set(buffer.subarray(start,start+n),offset);requests++;largest=Math.max(largest,count);return n;});
 assert.equal(status(api.roundtrip_mat_to(input,sink)).bytes,output.length);
 assert.deepEqual(output,Buffer.from(expected));assert.ok(requests>0&&largest<=1048576);
}
for(const mode of [0,-1,2]){
 const sink=api.make_sink((_,__,___,n)=>mode===2?n+1:mode);
 assert.equal(JSON.parse(api.roundtrip_mat_to(input,sink)).code,'io-error');
}
let calls=0;
const sink=api.make_sink((_,__,___,n)=>{calls++;return n;});
assert.equal(JSON.parse(api.tree_snapshot_to_sink('{',sink)).status,'error');assert.equal(calls,0);
const hook=join(directory,'fault-host.mjs');
writeFileSync(hook,String.raw`
import fs from 'node:fs';import {syncBuiltinESMExports} from 'node:module';import {pathToFileURL} from 'node:url';
const [mode,cli,input,output,command='roundtrip']=process.argv.slice(2);
const open=fs.openSync,close=fs.closeSync,write=fs.writeSync,link=fs.linkSync;
let outputFd=null,writes=0;
fs.openSync=(path,flags,...rest)=>{
 if(flags==='wx+'&&mode==='collision'){fs.writeFileSync(path,'collision',{flag:'wx'});throw Object.assign(new Error('collision'),{code:'EEXIST'});}
 const fd=open(path,flags,...rest);if(flags==='wx+')outputFd=fd;return fd;
};
fs.closeSync=fd=>{const result=close(fd);if(fd===outputFd&&mode==='close')throw Object.assign(new Error('close failure'),{code:'EIO'});return result;};
fs.writeSync=(fd,buffer,start,length,position)=>{
 if(fd===outputFd){writes++;if(mode==='write'&&writes>1)throw Object.assign(new Error('write failure'),{code:'EIO'});if(mode==='short'||mode==='write')length=Math.min(7,length);}
 return write(fd,buffer,start,length,position);
};
fs.linkSync=(from,to)=>{if(mode==='publish')throw Object.assign(new Error('publish failure'),{code:'EACCES'});return link(from,to);};
syncBuiltinESMExports();process.argv=[process.argv[0],cli,command,input,output];await import(pathToFileURL(cli));
`);
const checks=[];
for(const operation of ['roundtrip','compress']) for(const mode of ['short','write','close','publish','collision']){
 const folder=join(directory,operation+'-'+mode);mkdirSync(folder);const output=join(folder,'output.mat');
 const r=spawnSync(process.execPath,[hook,mode,cli,fixture,output,operation],{cwd:root,encoding:'utf8',timeout:60000});
 assert.equal(r.status,mode==='short'?0:1,r.stdout+r.stderr);
 const members=readdirSync(folder);
 if(mode==='short'){if(operation==='roundtrip')assert.deepEqual(readFileSync(output),Buffer.from(expected));else assert.equal(JSON.parse(api.inspect_mat(readFileSync(output))).status,'ok');assert.deepEqual(members,['output.mat']);}
 else if(mode==='collision'){assert.equal(members.length,1);assert.equal(readFileSync(join(folder,members[0]),'utf8'),'collision');assert.ok(!existsSync(output));}
 else assert.equal(members.length,0,'Failed output left a final or temporary file');
 checks.push({operation,mode,status:'passed'});
}
const report={status:'passed',version,checks,short_write_counts:[1,3,1048576],invalid_counts:[0,-1,'request+1'],source_sha256:createHash('sha256').update(input).digest('hex'),output_sha256:createHash('sha256').update(expected).digest('hex'),scope:'JS callback byte identity and independent Node filesystem failure injection. Native close/size/publish failures have a separate C-only transport harness; basic-class interoperability is checked by the SciPy/Octave suites.'};
writeFileSync(join(root,`verification/reports/sink-operations-v${version}.json`),JSON.stringify(report,null,2)+'\n');
console.log('Sink callbacks and ten Node file fault cases passed');
