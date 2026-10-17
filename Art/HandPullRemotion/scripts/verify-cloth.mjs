import assert from 'node:assert/strict';
import sharp from 'sharp';
import {readFile,readdir,writeFile} from 'node:fs/promises';
const simulation=JSON.parse(await readFile('public/cloth/simulation.json','utf8'));
const bytes=await readFile('public/cloth/positions.bin');
const positions=new Float32Array(bytes.buffer,bytes.byteOffset,bytes.byteLength/4);
assert.equal(positions.length,144*81*81*3);
assert(positions.every(Number.isFinite));
assert.equal(simulation.metrics[0].maxZ,0);
assert(simulation.metrics[90].maxZ>25);
assert(simulation.metrics[130].maxZ>0,'Fabric should keep responding after fingers release');
assert(simulation.metrics[108].y<simulation.metrics[75].y-60,'Cloth grip must move UP with the hand');
for(let f=75;f<=112;f++)assert.equal(simulation.metrics[f].grip,1,'Do not release the cloth during the upward pull');
assert.equal(simulation.metrics[143].maxZ,0);
let contactError=0;
for(const frame of [75,90,108,112]) {
 const {x,y}=simulation.metrics[frame];let cx=0,cy=0;
 for(const index of simulation.grabbed) {
  const i=(frame*6561+index)*3;cx+=positions[i]+256;cy+=256-positions[i+1];
 }
 cx/=simulation.grabbed.length;cy/=simulation.grabbed.length;
 contactError=Math.max(contactError,Math.hypot(cx-x,cy-y));
}
assert(contactError<4,'Grip should remain under the fingertips');
const report={simulation:{vertices:6561,frames:144,finite:true,contactErrorPx:contactError,
 upwardTravelPx:simulation.metrics[75].y-simulation.metrics[108].y,
 releaseHeight:simulation.metrics[130].maxZ},exports:{}};
for(const mode of ['surface','overlay']) {
 const folder=`out/cloth/${mode}`;
 const files=(await readdir(folder)).filter(n=>/^cloth_\d{3}\.png$/.test(n)).sort();
 assert.equal(files.length,144);
 let minTransparent=512*512;
 for(const file of files) {
  const {data,info}=await sharp(`${folder}/${file}`).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  assert.equal(info.width,512);assert.equal(info.height,512);
  let transparent=0;for(let i=3;i<data.length;i+=4)if(data[i]===0)transparent++;
  minTransparent=Math.min(minTransparent,transparent);
 }
 const first=await sharp(`${folder}/cloth_000.png`).ensureAlpha().raw().toBuffer();
 const last=await sharp(`${folder}/cloth_143.png`).ensureAlpha().raw().toBuffer();
 let error=0;for(let i=0;i<first.length;i++)error+=Math.abs(first[i]-last[i]);
 const loopMeanDifference=error/first.length;
 assert(loopMeanDifference<1,'Loop endpoint discontinuity');
 if(mode==='overlay')assert(minTransparent>512*512*.25,'Overlay must retain substantial transparency');
 report.exports[mode]={frames:144,canvas:[512,512],loopMeanDifference,minTransparentPixels:minTransparent};
}
const a=await sharp('review/cloth/seek-a.png').raw().toBuffer();
const b=await sharp('review/cloth/seek-b.png').raw().toBuffer();
assert(a.equals(b),'Revisiting a frame must produce identical pixels');
report.seekDeterministic=true;
const gif=await sharp('out/cloth/HandPullCloth.gif',{animated:true}).metadata();
report.gif={frames:gif.pages,durationMs:gif.delay.reduce((a,b)=>a+b,0)};
assert.equal(report.gif.frames,144);assert.equal(report.gif.durationMs,2400);
const samples=[18,48,60,75,90,108,112,120,130,143],layers=[];
for(let i=0;i<samples.length;i++)layers.push({input:await sharp(`out/cloth/surface/cloth_${String(samples[i]).padStart(3,'0')}.png`).resize(240,240).toBuffer(),left:i%5*240,top:Math.floor(i/5)*240});
await sharp({create:{width:1200,height:480,channels:4,background:'#faf9f7'}}).composite(layers).png().toFile('review/cloth/cycle.png');
await writeFile('review/cloth/verification.json',JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
