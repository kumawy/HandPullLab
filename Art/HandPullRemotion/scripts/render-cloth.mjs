import {bundle} from '@remotion/bundler';
import {renderFrames,selectComposition,stitchFramesToVideo,renderStill,openBrowser} from '@remotion/renderer';
import {resolve} from 'node:path';
import {mkdir,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {handMotion} from '../src/motion.ts';
const serveUrl=await bundle({entryPoint:'src/index.ts'});
const chromiumOptions={gl:'angle'};
await mkdir('review/cloth',{recursive:true});
for(const [id,folder]of [['HandPullCloth','surface'],['HandPull','handmask']]) {
 const outputDir=resolve(`out/cloth/${folder}`);
 await mkdir(outputDir,{recursive:true});
 const composition=await selectComposition({serveUrl,id,chromiumOptions});
 const {assetsInfo}=await renderFrames({serveUrl,composition,outputDir,imageFormat:'png',
   imageSequencePattern:'cloth_[frame].[ext]',concurrency:2,chromiumOptions,
   onFrameUpdate:count=>{if(count%36===0)console.log(`${id}: ${count}/144`);}});
 if(id==='HandPullCloth')await stitchFramesToVideo({assetsInfo,fps:60,width:512,height:512,codec:'gif',
   outputLocation:resolve('out/cloth/HandPullCloth.gif'),numberOfGifLoops:null});
}
const plate=await selectComposition({serveUrl,id:'ClothCleanPlate',chromiumOptions});
await renderStill({serveUrl,composition:plate,frame:0,output:resolve('review/cloth/clean-plate.png'),imageFormat:'png',chromiumOptions});
execFileSync(process.execPath,['scripts/extract-cloth-overlay.mjs'],{stdio:'inherit'});
await writeFile('out/cloth/animation.json',JSON.stringify({
 name:'HandPullCloth',width:512,height:512,fps:60,duration:2.4,frameCount:144,
 surface:'surface/cloth_%03d.png',transparentOverlay:'overlay/cloth_%03d.png',
 simulation:{method:'PBD + sub-grid buckling',grid:[81,81],substeps:4,iterations:10},
 hand:'Existing hand sprite poses, no redraw',nativeIntegration:true
 ,phaseFrames:{arrival:[0,18],descend:[24,48],pinch:[48,72],pullUp:[75,108],release:[112,126],departure:[126,143]},
 upwardPullPixels:72
},null,2));
await writeFile('out/cloth/timeline.json',JSON.stringify(Array.from({length:144},(_,frame)=>({
 frame,time:frame/60,...handMotion(frame,60)
})),null,2));
const browser=await openBrowser('chrome',{chromiumOptions});
try {
 const composition=await selectComposition({serveUrl,id:'HandPullCloth',puppeteerInstance:browser,chromiumOptions});
 for(const [name,frame]of [['seek-a',90],['seek-other',24],['seek-b',90]])
  await renderStill({serveUrl,composition,frame,output:resolve(`review/cloth/${name}.png`),imageFormat:'png',puppeteerInstance:browser,chromiumOptions});
}finally {await browser.close({silent:true});}
console.log('Cloth export complete.');
