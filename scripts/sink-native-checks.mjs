import {readFileSync,writeFileSync,mkdirSync,mkdtempSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {root,toolchain} from './moon.mjs';
import {nativeEnv} from './build-native.mjs';
const directory=mkdtempSync(join(root,'verification/local/sink-native-faults-'));
mkdirSync(directory,{recursive:true});
let source=readFileSync(join(root,'src/cmd/moonmat/io.c'),'utf8');
source='static int fail_close_once,close_attempts;\nstatic int fault_close(int);\n'+source;
source=source.replace('#define CLOSE _close','#define CLOSE fault_close').replace('#define CLOSE close','#define CLOSE fault_close');
source+=String.raw`
#include <assert.h>
/* Unused argv/read transports must never run in this C-only sink harness. */
void moonbit_incref(void *obj) { (void)obj; abort(); }
void moonbit_decref(void *obj) { (void)obj; abort(); }
moonbit_string_t moonbit_make_string_raw(int32_t n) { (void)n;abort();return NULL; }
moonbit_bytes_t moonbit_make_bytes(int32_t n,int value) { (void)n;(void)value;abort();return NULL; }
static int fault_close(int fd) {
  ++close_attempts;
#ifdef _WIN32
  int actual = _close(fd);
#else
  int actual = close(fd);
#endif
  if (fail_close_once) { fail_close_once = 0; errno = EIO; return -1; }
  return actual;
}
static int present(const char *name) { struct stat status; return !stat(name,&status); }
static void marker(void) { FILE *f=fopen("output.mat","wb"); assert(f); assert(fwrite("keep",1,4,f)==4);assert(!fclose(f)); }
static void retained(void) { char text[4];FILE *f=fopen("output.mat","rb");assert(f);assert(fread(text,1,4,f)==4);assert(!memcmp(text,"keep",4));assert(!fclose(f)); }
static int start(void) {int slot=moonmat_sink_begin((moonbit_bytes_t)"output.mat");assert(slot>=0);return slot;}
static void output(int slot) {unsigned char data[128]={0};assert(moonmat_sink_write(slot,0,data,0,128)==128);}
int main(void) {
  assert(!present("output.mat"));
  int slot=start();output(slot);assert(!moonmat_sink_finish(slot,1,128));assert(present("output.mat"));assert(!remove("output.mat"));
  marker();slot=start();unsigned char data[128]={0};assert(moonmat_sink_write(slot,0,data,0,128)==-1);assert(moonmat_sink_finish(slot,0,0)==3);retained();assert(!remove("output.mat"));
  slot=start();output(slot);char temp[2048];assert(strlen(sink_slots[slot].temp)<sizeof(temp));strcpy(temp,sink_slots[slot].temp);
  int before=close_attempts;fail_close_once=1;assert(moonmat_sink_finish(slot,1,128)==1);assert(close_attempts==before+1);assert(!present("output.mat")&&!present(temp));
  slot=start();output(slot);strcpy(temp,sink_slots[slot].temp);assert(moonmat_sink_finish(slot,1,129)==1);assert(!present("output.mat")&&!present(temp));
  slot=start();output(slot);strcpy(temp,sink_slots[slot].temp);marker();assert(moonmat_sink_finish(slot,1,128)==3);retained();assert(!present(temp));assert(!remove("output.mat"));
  slot=start();output(slot);strcpy(temp,sink_slots[slot].temp);assert(!moonmat_sink_finish(slot,0,0));assert(!present("output.mat")&&!present(temp));
  for(int i=0;i<16;++i)assert(!sink_slots[i].active);
  puts("Native sink transport: six failure/success cases passed");return 0;
}
`;
const file=join(directory,'faults.c');writeFileSync(file,source);
const t=toolchain();const windows=process.platform==='win32';
const binary=join(directory,windows?'faults.exe':'faults');
const home=t.env.MOON_HOME;
const args=windows?['/nologo','/O2','/Gy','/MT','/I'+join(home,'include'),file,'/Fe:'+binary,'/link','/OPT:REF']:
 ['-O2','-ffunction-sections','-fdata-sections','-I'+join(home,'include'),file,'-Wl,--gc-sections','-o',binary];
function run(exe,args){const p=spawnSync(exe,args,{cwd:directory,env:{...t.env,...nativeEnv()},encoding:'utf8',timeout:120000});if(p.error||p.status!==0)throw new Error(p.error?.message||p.stdout+p.stderr);return p.stdout;}
run(windows?'cl.exe':(t.config.gcc||'cc'),args);
console.log(run(binary,[]).trim());
