import assert from 'node:assert/strict';
import {parseCompiler} from './toolchain.mjs';
for (const value of ['v0.10.14+old', 'v0.10.15', 'v0.9.99', 'moon 0.1.20261028', 'unknown']) {
  assert.throws(() => parseCompiler(value));
}
assert.equal(parseCompiler('v0.10.16+b1a0e846e (2026-10-16)'), '0.10.16+b1a0e846e');
assert.equal(parseCompiler('v0.11.0'), '0.11.0');
assert.equal(parseCompiler('v1.0.0'), '1.0.0');
console.log('Actual compiler minimum/version parsing: passed');
