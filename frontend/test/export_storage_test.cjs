const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../web/export_storage.js'), 'utf8');
function environment(fail = false) {
  const downloads = [], blobs = [], revoked = [], timers = [];
  let removed = 0;
  const window = {showDirectoryPicker:()=>{throw Error('Must never choose a folder');}};
  const document = {
    body: {appendChild(){}},
    createElement: () => ({click(){if(fail) throw Error('download blocked'); downloads.push(this.download);}, remove(){removed++;}}),
  };
  const url = {createObjectURL(blob){blobs.push(blob); return 'blob:test';}, revokeObjectURL(value){revoked.push(value);}};
  vm.runInNewContext(script, {window,document,atob,Uint8Array,Blob,URL:url,setTimeout:fn=>timers.push(fn)});
  return {api:window.posExportStorage,downloads,blobs,revoked,timers,removed:()=>removed};
}
test('one binary download per export, no picker, session history separated by account', async () => {
  const env=environment();
  await env.api.prepare('user-1');
  const result=JSON.parse(await env.api.save('user-1','AP+A','pos-report-1.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
  assert.equal(result.download,true);
  assert.equal(result.size,3);
  assert.deepEqual(env.downloads,['pos-report-1.xlsx']);
  assert.deepEqual([...new Uint8Array(await env.blobs[0].arrayBuffer())],[0,255,128]);
  assert.equal(JSON.parse(await env.api.list('user-1')).length,1);
  assert.deepEqual(JSON.parse(await env.api.list('user-2')),[]);
  assert.equal(env.removed(),1);
  env.timers.forEach(fn=>fn());
  assert.deepEqual(env.revoked,['blob:test']);
});
test('failed downloads and invalid filenames never add a history entry', async () => {
  const env=environment(true);
  await assert.rejects(env.api.save('user-1','AA==','pos-report-1.pdf','application/pdf'),/blocked/);
  assert.deepEqual(JSON.parse(await env.api.list('user-1')),[]);
  await assert.rejects(env.api.save('user-1','AA==','../bad.pdf','application/pdf'));
  await assert.rejects(env.api.prepare('../other'));
  assert.equal(env.removed(),1);
});
