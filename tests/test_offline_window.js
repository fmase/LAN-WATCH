'use strict';
// Offline visibility is rolling and display-only. No network or router is used.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const root = path.resolve(__dirname, '..');
const NOW = 1794600000;
class FrozenDate extends Date { static now() { return NOW * 1000; } }
function element() {
  return {textContent:'',innerHTML:'',hidden:false,value:'',dataset:{},attrs:{},children:[],handlers:{},
    setAttribute(k,v){this.attrs[k]=v},addEventListener(k,v){this.handlers[k]=v},
    appendChild(c){this.children.push(c)},replaceChildren(){this.children=[]}};
}
function device(mac,ip,name,last,state) {
  return [mac,ip,name,NOW-100000,last,state,0].join('\t');
}
function event(ts,state,mac,ip,name,last) {
  return [ts,state,mac,ip,name,last].join('\t');
}
async function run(language,mode) {
  const html=fs.readFileSync(path.join(root,'payload','www',`index-${language}.html`),'utf8');
  const js=html.split('<script>')[1].split('</script>')[0];
  const recent='02:00:00:00:00:01';
  const boundary='02:00:00:00:00:02';
  const old='02:00:00:00:00:03';
  const future='02:00:00:00:00:04';
  const zero='02:00:00:00:00:05';
  const invalid='02:00:00:00:00:06';
  const online='02:00:00:00:00:07';
  const sameName='02:00:00:00:00:08';
  const restored='02:00:00:00:00:09';
  const lines=['#SCAN\t'+(mode==='stale'?NOW-601:NOW),'#ERROR\t'+(mode==='error'?'scanner failed':''),'#DEVICES',
    device(recent,'192.168.7.1','recent',NOW-86399,'non rilevato'),
    device(boundary,'192.168.7.2','exact-boundary',NOW-86400,'non rilevato'),
    device(old,'192.168.7.3','old',NOW-90000,'non rilevato'),
    device(future,'192.168.7.4','future',NOW+1,'non rilevato'),
    device(zero,'192.168.7.5','zero',0,'non rilevato'),
    device(invalid,'192.168.7.6','invalid','not-a-time','non rilevato'),
    device(online,'192.168.7.7','identical',NOW,'online'),
    device(sameName,'192.168.7.8','identical',NOW,'online'),
    device(restored,'192.168.7.9','restored',NOW,'online'),
    '#EVENTS',
    event(NOW-90000,'non rilevato',old,'192.168.7.3','old',NOW-90001),
    event(NOW-50,'non rilevato',restored,'192.168.7.9','restored',NOW-60),
    event(NOW-20,'rilevato',restored,'192.168.7.9','restored',NOW-20),''].join('\n');
  const els={};const get=id=>els[id]||(els[id]=element());
  const document={querySelector(s){return get(s.replace(/^#/,''))},getElementById:get,
    createElement:element,documentElement:{dataset:{}}};
  const fetch=async url => url.includes('/settings')
    ? {ok:true,json:async()=>({interval:120})}
    : {ok:true,text:async()=>lines};
  const context={document,localStorage:{getItem(){return null},setItem(){}},fetch,setInterval(){},Date:FrozenDate,console};
  vm.runInNewContext(js,context);
  await new Promise(resolve=>setImmediate(resolve));
  // A displayed row contains cells: status, name, IP, MAC, last seen.
  const displayed=()=>get('devices').children.map(row=>row.children[3].textContent);
  assert.deepEqual(displayed().sort(),[recent,online,sameName,restored].sort(),`${language}/${mode}: visibility incl. strict 24h boundary and invalid/future timestamps`);
  if(mode==='fresh') {
    assert.equal(get('online').textContent,3,`${language}: duplicate names are separate MACs`);
    assert.equal(get('offline').textContent,1,`${language}: count matches visible recent offline devices`);
  } else {
    assert.equal(get('online').textContent,'—',`${language}/${mode}: stale counts hidden`);
    assert.equal(get('offline').textContent,'—',`${language}/${mode}: stale counts hidden`);
  }
  assert.equal(get('events').children.length,3,`${language}/${mode}: filtering devices must not remove historical events`);
  get('search').value='recent';get('search').oninput();
  assert.deepEqual(displayed(),[recent],`${language}/${mode}: search narrows only visible rows`);
  assert.equal(get('online').textContent,mode==='fresh'?3:'—',`${language}/${mode}: online count independent of search`);
  assert.equal(get('offline').textContent,mode==='fresh'?1:'—',`${language}/${mode}: offline count independent of search`);
}
(async()=>{for(const lang of ['it','en'])for(const mode of ['fresh','stale','error'])await run(lang,mode);console.log('Offline rolling window, boundary, history and search: OK')})().catch(e=>{console.error(e);process.exitCode=1});
