'use strict';
// The dashboard is read-only: it must not expose interval selection or settings requests.
const assert=require('assert'),fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(__dirname,'..');
function element(){return {textContent:'',innerHTML:'',hidden:false,value:'',dataset:{},children:[],setAttribute(){},addEventListener(){},appendChild(c){this.children.push(c)},replaceChildren(){this.children=[]}}}
async function check(lang){
 const html=fs.readFileSync(path.join(root,'payload','www',`index-${lang}.html`),'utf8');
 assert.ok(!html.includes('settings-form'));assert.ok(!html.includes('scan-interval'));assert.ok(!html.includes('/cgi-bin/settings'));
 const js=html.split('<script>')[1].split('</script>')[0],els={},get=id=>els[id]||(els[id]=element()),calls=[];
 const document={querySelector(s){return get(s.replace(/^#/,''))},getElementById:get,createElement:element,documentElement:{dataset:{}}};
 const fetch=async(url,options)=>{calls.push([url,options]);return {ok:true,text:async()=>['#SCAN\t0','#ERROR\t','#DEVICES','#EVENTS',''].join('\n')}};
 vm.runInNewContext(js,{document,fetch,setInterval(){},localStorage:{getItem(){return null},setItem(){}},Date,console});
 await new Promise(resolve=>setImmediate(resolve));assert.ok(calls.length>=1);assert.ok(calls.every(([url])=>url==='/cgi-bin/status'));
}
Promise.all(['it','en'].map(check)).then(()=>console.log('Dashboard read-only, no interval API: OK')).catch(e=>{console.error(e);process.exitCode=1});
