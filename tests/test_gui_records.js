// Verify dashboard record parsing and device identity handling.
'use strict';
// Simulates the data-loading UI with generated records; no browser or network.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const root = path.resolve(__dirname, '..');
function makeElement(){return {textContent:'',innerHTML:'',hidden:false,value:'',dataset:{},children:[],setAttribute(){},addEventListener(){},appendChild(c){this.children.push(c)},replaceChildren(){this.children=[]}};}
async function run(language){
 const html=fs.readFileSync(path.join(root,'payload','www',`index-${language}.html`),'utf8');
 const js=html.split('<script>')[1].split('</script>')[0];
 const elements={}; const get=id=>elements[id]||(elements[id]=makeElement());
 const api=['#SCAN\t'+Math.floor(Date.now()/1000),'#ERROR\t','#DEVICES',
  '30:48:7d:8c:02:be\t192.168.1.108\tlwip0\t1\t2\tonline\t0',
  '30:48:7d:8b:f1:d8\t192.168.1.104\tlwip0\t1\t2\tonline\t0',
  '30:48:7d:8c:02:be30:48:7d:8b:f1:d8\t192.168.1.104\tlwip0\t1\t2\tnon rilevato\t0',
  'aa:bb:cc:dd:ee:ff\t999.168.1.1\tbad\t1\t2\tonline\t0',
  '#EVENTS','1700000000\trilevato\t30:48:7d:8c:02:be\t192.168.1.108\tlwip0\t1700000000',
  '1700000000\tnon rilevato\taa:bb:cc:dd:ee:ff30:48:7d:8b:f1:d8\t192.168.1.9\tbad\t1',''].join('\n');
 const document={querySelector(s){return get(s.replace(/^#/,''))},getElementById:get,createElement:makeElement,documentElement:{dataset:{}}};
 const context={document,localStorage:{getItem(){return null},setItem(){}},fetch:async()=>({ok:true,text:async()=>api}),setInterval(){},Date,console};
 vm.runInNewContext(js,context); await new Promise(resolve=>setImmediate(resolve));
 assert.ok(!html.includes('id="total"'),`${language}: no cumulative device counter`);
 assert.equal(get('online').textContent,2);assert.equal(get('devices').children.length,2,`${language}: same hostname remains separate`);
 assert.equal(get('events').children.length,1);assert.equal(get('data-warning').hidden,false);
 assert.ok(get('data-warning').textContent.endsWith('3'),`${language}: invalid records reported`);
}
Promise.all(['it','en'].map(run)).then(()=>console.log('GUI record validation and same-name handling: OK')).catch(e=>{console.error(e);process.exitCode=1});
