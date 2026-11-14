'use strict';
// Exercise freshness and theme behavior using a fake DOM and in-memory responses.
const assert=require('assert');
const fs=require('fs');
const vm=require('vm');
const path=require('path');
const root=path.resolve(__dirname,'..');
const realNow=Date.now();
function element(){return {textContent:'',innerHTML:'',hidden:false,value:'',dataset:{},attrs:{},children:[],handlers:{},setAttribute(k,v){this.attrs[k]=v},addEventListener(k,v){this.handlers[k]=v},appendChild(c){this.children.push(c)},replaceChildren(){this.children=[]}}}
async function check(lang,mode){
 const html=fs.readFileSync(path.join(root,'payload','www',`index-${lang}.html`),'utf8');
 const js=html.split('<script>')[1].split('</script>')[0];
 assert.ok(html.includes('@media(max-width:400px){.stats{grid-template-columns:1fr}'),`${lang}: narrow-screen cards`);
 assert.ok(html.includes('width:44px;height:44px'),`${lang}: accessible theme button`);
 assert.ok(html.includes('mancata risposta ripetuta')||html.includes('repeatedly not responding'),`${lang}: offline definition`);
 const els={};const get=k=>els[k]||(els[k]=element());
 const doc={querySelector(s){return get(s.replace(/^#/,''))},getElementById:get,createElement:element,documentElement:{dataset:{}}};
 const age=mode==='stale'?601:mode==='future'?-121:20;
 const stamp=mode==='initial'?0:Math.floor(realNow/1000)-age;
 const err=mode==='error'?'internal error with secret detail':'';
 const data=['#SCAN\t'+stamp,'#ERROR\t'+err,'#DEVICES','00:11:22:33:44:55\t192.168.7.9\ttest\t1\t2\tonline\t0','#EVENTS',''].join('\n');
 let value='light';
 const context={document:doc,localStorage:{getItem(){return value},setItem(k,v){value=v}},fetch:async()=>{if(mode==='unreachable')throw Error();return {ok:true,text:async()=>mode==='invalid'?'#SCAN\t123\n#DEVICES\n':data}},setInterval(){},Date,console};
 vm.runInNewContext(js,context);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(doc.documentElement.dataset.theme,'light');
 assert.ok(get('theme-toggle').innerHTML.includes('<circle'),`${lang}: sun icon`);
 get('theme-toggle').handlers.click();
 assert.equal(doc.documentElement.dataset.theme,'dark');assert.equal(value,'dark');
 assert.ok(get('theme-toggle').innerHTML.includes('<path'),`${lang}: moon icon`);
 if(mode==='fresh'){
  assert.equal(get('online').textContent,1,`${lang}: fresh online count`);
  assert.equal(get('offline').textContent,0);
  assert.equal(get('freshness-note').hidden,true);
 } else {
  assert.equal(get('online').textContent,'—',`${lang}: do not imply current online count for ${mode}`);
  assert.equal(get('offline').textContent,'—');
  assert.equal(get('freshness-note').hidden,false);
  assert.ok(!get('status').textContent.includes('secret detail'),`${lang}: do not expose backend error`);
  if(mode==='stale'||mode==='error'||mode==='future') assert.ok(get('devices').children[0].children[0].children[0].textContent.includes(lang==='it'?'Ultimo:':'Last:'),`${lang}: row is last-known`);
 }
}
(async()=>{for(const lang of ['it','en'])for(const mode of ['fresh','stale','error','initial','future','unreachable','invalid'])await check(lang,mode);console.log('GUI freshness, last-known state, theme and responsive checks: OK')})().catch(e=>{console.error(e);process.exitCode=1});
