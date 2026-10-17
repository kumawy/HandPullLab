import sharp from 'sharp';
import {mkdir, writeFile} from 'node:fs/promises';

// Registration uses the wrist, never each pose's moving silhouette bounds.
const input = 'public/source/hand-atlas-cleanup.png';
const {data, info} = await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject:true});
await mkdir('public/poses', {recursive:true});
await mkdir('review', {recursive:true});
const registrations = [];
for (let pose=0; pose<16; pose++) {
  const left=Math.round((pose%4)*info.width/4);
  const top=Math.round(Math.floor(pose/4)*info.height/4);
  const width=Math.round((pose%4+1)*info.width/4)-left;
  const height=Math.round((Math.floor(pose/4)+1)*info.height/4)-top;
  const pixels=Buffer.alloc(width*height*4);
  for (let y=0;y<height;y++) for(let x=0;x<width;x++) {
    const i=((top+y)*info.width+left+x)*4, j=(y*width+x)*4;
    data.copy(pixels,j,i,i+4);
    // Nearly invisible RGB debris in transparent pixels must not survive GIF quantization.
    pixels[j+3]=pixels[j+3]<=8?0:Math.min(255,Math.round(pixels[j+3]*255/253));
  }
  let cutY=0;
  for(let y=0;y<60;y++) {
    let count=0;
    for(let x=0;x<width;x++) if(pixels[(y*width+x)*4+3]>180) count++;
    if(count>60) {cutY=y+8;break;}
  }
  const wrist=[];
  for(let x=0;x<width;x++) if(pixels[(cutY*width+x)*4+3]>128) wrist.push(x);
  if(wrist.length<50) throw new Error(`Wrist not found for pose ${pose}`);
  const wristLeft=wrist[0], wristWidth=wrist.at(-1)-wristLeft+1;
  const centerX=(wrist[0]+wrist.at(-1))/2;
  const dx=Math.round(256-centerX), dy=150-cutY;
  const raw={raw:{width,height,channels:4}};
  const straightSection=36;
  const body=await sharp(pixels,raw).extract({left:0,top:cutY+straightSection,width,height:height-cutY-straightSection}).png().toBuffer();
  // Extend only the straight forearm. Retain its lighting gradient and original lower endpoint.
  const forearm=await sharp(pixels,raw).extract({left:0,top:cutY,width,height:straightSection})
    .resize(width,150+straightSection,{kernel:'cubic',fit:'fill'}).png().toBuffer();
  await sharp({create:{width:512,height:512,channels:4,background:'#00000000'}})
    .composite([{input:forearm,left:dx,top:0},{input:body,left:dx,top:150+straightSection}])
    .png().toFile(`public/poses/pose-${String(pose).padStart(2,'0')}.png`);
  registrations.push({pose,sourceCell:{left,top,width,height},cutY,dx,dy,wristWidth});
}
await writeFile('review/registration.json',JSON.stringify(registrations,null,2));
console.log('Prepared 16 registered poses. No per-pose scaling.');
