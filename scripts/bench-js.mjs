import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';
const [modulePath, path, operation, measurement, repetitionsText='1'] = process.argv.slice(2);
const api = await import(pathToFileURL(modulePath));
const input = readFileSync(path);
const prepared = ['write', 'compress'].includes(operation) ? api.prepare(input) : null;
const call = () => api[operation](prepared ?? input);
let checksum = 0;
const memory = measurement === 'memory';
const repetitions = memory ? 1 : Number(repetitionsText);
if (!Number.isInteger(repetitions) || repetitions < 1 || repetitions > 1024) throw new Error('Invalid benchmark repetition count');
if (!memory) for (let i = 0; i < 5; i++) checksum += call();
const samples = [];
const totals = [];
for (let i = 0; i < (memory ? 1 : 10); i++) {
  if (global.gc) global.gc();
  const start = performance.now();
  let value = 0;
  for (let j=0; j<repetitions; j++) value = call();
  const total = performance.now() - start;
  checksum += value;
  totals.push(total);
  samples.push(total/repetitions);
}
console.log(JSON.stringify({samples_ms: samples, peak_bytes: process.resourceUsage().maxRSS * 1024,
  samples_total_ms:totals, operations_per_sample:repetitions,
  checksum, input_bytes: input.length, gc_between_samples: true}));
