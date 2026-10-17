import {mkdir,writeFile} from 'node:fs/promises';
import {handMotion} from '../src/motion.ts';

const N=81,SIZE=576,MIN=-32,FPS=60,FRAMES=144,SUBSTEPS=4,DT=1/(FPS*SUBSTEPS);
const count=N*N,step=SIZE/(N-1);
const p=new Float64Array(count*3),previous=new Float64Array(count*3),rest=new Float64Array(count*3);
const mass=new Float64Array(count),edges=[];
const smooth=x=>{const t=Math.max(0,Math.min(1,x));return t*t*(3-2*t);};
for(let y=0;y<N;y++)for(let x=0;x<N;x++) {
 const i=y*N+x,k=i*3;
 rest[k]=MIN+x*step;rest[k+1]=MIN+y*step;rest[k+2]=0;
 mass[i]=(x<2||y<2||x>N-3||y>N-3)?0:1;
}
p.set(rest);previous.set(rest);
const add=(a,b,strength)=>edges.push([a*3,b*3,Math.hypot(rest[a*3]-rest[b*3],rest[a*3+1]-rest[b*3+1]),strength,mass[a],mass[b]]);
for(let y=0;y<N;y++)for(let x=0;x<N;x++) {
 const i=y*N+x;
 if(x<N-1)add(i,i+1,.9);
 if(y<N-1)add(i,i+N,.9);
 if(x<N-1&&y<N-1){add(i,i+N+1,.35);add(i+1,i+N,.35);}
 if(x<N-2)add(i,i+2,.022);
 if(y<N-2)add(i,i+2*N,.022);
}
const base={x:242,y:254};
const grabbed=[];
for(let i=0;i<count;i++) {
 const x=rest[i*3]-base.x,y=rest[i*3+1]-base.y;
 if(x*x+y*y<13*13)grabbed.push({i,x,y});
}
function anchor(frame) {
 const m=handMotion(frame,FPS),s=360/512,a=m.rotation*Math.PI/180;
 const lx=(236-256)*s,ly=395*s;
 return {x:256+lx*Math.cos(a)-ly*Math.sin(a)+m.x,y:-46+lx*Math.sin(a)+ly*Math.cos(a)+m.y,grip:m.grip,pullProgress:m.pullProgress};
}
const all=new Float32Array(FRAMES*count*3),metrics=[];
// Sub-grid buckling: the coarse PBD mesh handles mass and strain; these curved
// ridges recover folds below its resolution. Propagation is delayed with distance.
const envelopes=[];let envelope=0,envelopeVelocity=0;
for(let f=0;f<FRAMES;f++) {
 const target=smooth((anchor(f).grip-.2)/.8);
 envelopeVelocity+=(target-envelope)*290/FPS;
 envelopeVelocity*=Math.exp(-23/FPS);
 envelope=Math.max(0,envelope+envelopeVelocity/FPS);
 envelopes.push(envelope);
}
const folds=[
 [-1.03,158,8.0,8,.10],[-.72,207,12,11,-.11],[-.38,184,9,8,.13],
 [.04,224,13,12,-.09],[.42,192,10,10,.13],[.82,161,7,8,-.12],
 [-1.34,94,3.5,5,-.08],[1.2,112,4.5,6,.09]
];
let foldAnchor=anchor(72);
for(let f=0;f<FRAMES;f++) {
 for(let sub=0;sub<SUBSTEPS;sub++) {
  const time=Math.max(0,f-1+(sub+1)/SUBSTEPS);
  const a=anchor(time),grip=smooth((a.grip-.25)/.75);
  const lifting=36*grip;
  // Verlet integration: gravity, gentle positional recovery and low bending rigidity.
  for(let i=0;i<count;i++) {
   if(!mass[i])continue;
   const k=i*3;
   for(let c=0;c<3;c++) {
    const current=p[k+c],velocity=(current-previous[k+c])*.986;
    previous[k+c]=current;
    p[k+c]=current+velocity+((rest[k+c]-current)*(c===2?0:5)-(c===2?480:0))*DT*DT;
   }
   if(a.grip>.25&&a.grip<.6) {
    const dx=rest[k]-base.x,dy=rest[k+1]-base.y;
    p[k+2]+=.018*Math.exp(-(dx*dx+dy*dy)/14000)*(1+Math.sin(i*2.399));
   }
   p[k+2]=Math.max(0,p[k+2]);
  }
  for(let iter=0;iter<10;iter++) {
   for(let e=0;e<edges.length;e++) {
    const [a,b,len,strength,wa,wb]=edges[(iter%2)?edges.length-1-e:e];
    const weights=wa+wb;if(!weights)continue;
    const dx=p[b]-p[a],dy=p[b+1]-p[a+1],dz=p[b+2]-p[a+2];
    const distance=Math.sqrt(dx*dx+dy*dy+dz*dz)||1;
    const compression=distance<len?.55:1;
    const correction=(distance-len)/distance*strength*compression/weights;
    p[a]+=dx*correction*wa;p[a+1]+=dy*correction*wa;p[a+2]+=dz*correction*wa;
    p[b]-=dx*correction*wb;p[b+1]-=dy*correction*wb;p[b+2]-=dz*correction*wb;
   }
   if(grip>0)for(const {i,x,y} of grabbed) {
    const k=i*3,weight=Math.min(1,grip*2.5);
    const squeeze=1-.82*grip;
    p[k]+=(a.x+x*squeeze-p[k])*weight;
    p[k+1]+=(a.y+y*squeeze-p[k+1])*weight;
    p[k+2]+=(lifting+(y/13)*2*grip-p[k+2])*weight;
   }
   for(let i=0;i<count;i++)if(p[i*3+2]<0)p[i*3+2]=0;
  }
 }
 const settle=1-smooth((f-127)/16);
 const currentAnchor=anchor(f);
 if(currentAnchor.grip>.4)foldAnchor=currentAnchor;
 let maxZ=0;
 for(let i=0;i<count;i++) {
  const k=i*3,j=f*count*3+k;
  const dx=p[k]-foldAnchor.x,dy=p[k+1]-foldAnchor.y;
  const radius=Math.hypot(dx,dy),theta=Math.atan2(dx,dy);
  const lag=Math.min(f,Math.round(radius*.035));
  const strength=envelopes[Math.max(0,f-lag)];
  let wrinkles=0;
  for(const [angle,length,height,width,bend] of folds) {
   const t=radius/length;
   if(t>=1||t<=0)continue;
   const curve=angle+bend*Math.sin(Math.PI*t)*Math.sin(1.3+2*t);
   let delta=theta-curve;
   while(delta>Math.PI)delta-=Math.PI*2;
   while(delta<-Math.PI)delta+=Math.PI*2;
   const distance=delta*radius;
   const w=2.8+width*Math.pow(t,.68);
   const ridge=Math.exp(-((distance/w)**2));
   const trough=.28*Math.exp(-(((distance-w*1.6)/(w*1.2))**2));
   const lengthFade=Math.pow(Math.sin(Math.PI*t),.85)*smooth(radius/17);
   wrinkles+=strength*height*lengthFade*(ridge-trough);
  }
  all[j]=rest[k]+(p[k]-rest[k])*settle-256;
  all[j+1]=256-rest[k+1]-(p[k+1]-rest[k+1])*settle;
  all[j+2]=Math.max(0,p[k+2]+wrinkles)*settle;
  maxZ=Math.max(maxZ,all[j+2]);
  if(!Number.isFinite(all[j]+all[j+1]+all[j+2]))throw new Error('Non-finite cloth vertex');
 }
 metrics.push({frame:f,...anchor(f),maxZ});
 if(f%36===0)console.log(`Simulated ${f}/144`);
}
await mkdir('public/cloth',{recursive:true});
await writeFile('public/cloth/positions.bin',Buffer.from(all.buffer));
await writeFile('public/cloth/simulation.json',JSON.stringify({N,SIZE,MIN,fps:FPS,frameCount:FRAMES,vertexCount:count,substeps:SUBSTEPS,iterations:10,grabbed:grabbed.map(p=>p.i),metrics},null,2));
console.log(`Baked ${count} vertices, ${edges.length} constraints, ${(all.byteLength/1024/1024).toFixed(1)} MiB.`);
