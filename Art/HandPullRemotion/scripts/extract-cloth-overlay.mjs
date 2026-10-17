import sharp from 'sharp';
import {mkdir,copyFile} from 'node:fs/promises';
const iosDirectory = '../../HandPullLab/Resources/HandPullRemotion';
await mkdir('out/cloth/overlay',{recursive:true});
await mkdir(iosDirectory,{recursive:true});
const baseline=await sharp('review/cloth/clean-plate.png').ensureAlpha().raw().toBuffer();
for(let f=0;f<144;f++) {
 const name=`cloth_${String(f).padStart(3,'0')}.png`;
 const surface=await sharp(`out/cloth/surface/${name}`).ensureAlpha().raw().toBuffer();
 const mask=await sharp(`out/cloth/handmask/${name}`).ensureAlpha().raw().toBuffer();
 const out=Buffer.alloc(surface.length);
 for(let i=0;i<out.length;i+=4) {
  // Белые складки терялись на светлом фоне iOS. Усиливаем отклонение
  // от чистой ткани, сохраняя исходные цвета непрозрачной руки.
  const handAlpha=mask[i+3]/255;
  const strength=1+2.2*(1-handAlpha);
  const target=Array.from({length:3},(_,c)=>Math.max(0,Math.min(255,
    baseline[i+c]+(surface[i+c]-baseline[i+c])*strength)));
  let alpha=mask[i+3]/255,maxDelta=0;
  for(let c=0;c<3;c++) {
   const base=baseline[i+c],difference=target[c]-base;
   maxDelta=Math.max(maxDelta,Math.abs(surface[i+c]-base));
   alpha=Math.max(alpha,difference<0?-difference/Math.max(1,base):difference/Math.max(1,255-base));
  }
  if(mask[i+3]<3&&maxDelta<=2)continue;
  if(alpha<.012)continue;
  out[i+3]=Math.min(255,Math.ceil(alpha*255));
  alpha=out[i+3]/255;
  for(let c=0;c<3;c++)out[i+c]=Math.max(0,Math.min(255,Math.round((target[c]-(1-alpha)*baseline[i+c])/alpha)));
 }
 await sharp(out,{raw:{width:512,height:512,channels:4}}).png().toFile(`out/cloth/overlay/${name}`);
 await copyFile(`out/cloth/overlay/${name}`,`${iosDirectory}/remotion_${String(f).padStart(3,'0')}.png`);
}
console.log('Extracted 144 transparent overlays against a flat cloth clean plate.');
