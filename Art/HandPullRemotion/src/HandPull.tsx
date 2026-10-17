import React from 'react';
import {AbsoluteFill,CanvasImage,staticFile,useCurrentFrame,useVideoConfig} from 'remotion';
import {handMotion} from './motion';

export type HandPullProps = {handSize:number; travel:number; wristRotation:number};

// The near-identical opening poses are omitted to avoid incidental finger flutter.
const poses=[4,5,6,7,8,9,11,12,13,14,15];

export const HandPull:React.FC<HandPullProps> = ({handSize,travel,wristRotation}) => {
  const frame=useCurrentFrame();
  const {fps,width}=useVideoConfig();
  const motion=handMotion(frame,fps);
  const pose=poses[Math.round(motion.grip*(poses.length-1))];
  return <AbsoluteFill style={{overflow:'hidden',backgroundColor:'transparent'}}>
    <div style={{position:'absolute',left:(width-handSize)/2,top:-46,
      width:handSize,height:handSize,
      opacity:motion.opacity,
      transformOrigin:'50% 0%',
      translate:`${motion.x}px ${motion.y*travel}px`,
      rotate:`${motion.rotation*wristRotation}deg`}}>
      <CanvasImage name="Рука — исходные позы" src={staticFile(`poses/pose-${String(pose).padStart(2,'0')}.png`)}
        style={{width:handSize,height:handSize}} />
    </div>
  </AbsoluteFill>;
};
