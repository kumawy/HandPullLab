import {spring} from 'remotion';

export const springProgress = (frame:number, from:number, to:number, fps:number) => {
  if(frame<=from) return 0;
  if(frame>=to) return 1;
  return spring({frame:frame-from,fps,durationInFrames:to-from,
    config:{damping:26,stiffness:170,mass:1,overshootClamping:true}});
};

// A shorter settling threshold distributes the available finger poses across the
// entire phase; normalizing the endpoint keeps the transition continuous.
const fingerProgress = (frame:number,from:number,to:number,fps:number) => {
  if(frame<=from) return 0;
  if(frame>=to) return 1;
  const settings={fps,durationInFrames:to-from,durationRestThreshold:0.05,
    config:{damping:26,stiffness:170,mass:1,overshootClamping:true}};
  return Math.min(1,spring({...settings,frame:frame-from})/spring({...settings,frame:to-from}));
};

export const handMotion = (frame:number,fps:number) => {
  const descend=springProgress(frame,24,48,fps);
  const close=fingerProgress(frame,48,72,fps);
  const pull=fingerProgress(frame,75,108,fps);
  const release=fingerProgress(frame,112,126,fps);
  const arrival=springProgress(frame,0,18,fps);
  const departure=fingerProgress(frame,126,143,fps);
  const idleEnvelope=1-springProgress(frame,18,51,fps);
  const idleWave=Math.sin(Math.PI*2*frame/62);
  return {
    x:1.2*idleWave*idleEnvelope,
    y:22*descend-72*pull-315*(1-arrival)-310*departure
      +0.7*Math.sin(Math.PI*2*frame/48)*idleEnvelope,
    rotation:2.2*Math.sin(Math.PI*2*frame/68)*idleEnvelope-1.1*pull*(1-release),
    grip:Math.max(0,Math.min(1,close*(1-release))),
    opacity:springProgress(frame,0,6,fps)*(1-springProgress(frame,137,143,fps)),
    pullProgress:pull,
  };
};
