import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';
const [modulePath, path, operation, measurement] = process.argv.slice(2);
const api = await import(pathToFileURL(modulePath));
const input = readFileSync(path);
const prepared = ['write', 'compress'].includes(operation) ? api.prepare(input) : null;
const call = () => api[operation](prepared ?? input);
let checksum = 0;
const memory = measurement === 'memory';
if (!memory) for (let i = 0; i < 5; i++) checksum += call();
const samples = [];
for (let i = 0; i < (memory ? 1 : 10); i++) {
  if (global.gc) global.gc();
  const start = performance.now();
  checksum += call();
  samples.push(performance.now() - start);
}
console.log(JSON.stringify({samples_ms: samples, peak_bytes: process.resourceUsage().maxRSS * 1024,
  checksum, input_bytes: input.length, gc_between_samples: true}));
