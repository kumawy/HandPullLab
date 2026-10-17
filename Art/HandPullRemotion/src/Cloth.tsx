import React,{useEffect,useMemo,useState} from 'react';
import {ThreeCanvas} from '@remotion/three';
import {AbsoluteFill,cancelRender,continueRender,delayRender,staticFile,useCurrentFrame} from 'remotion';
import {ACESFilmicToneMapping,BufferAttribute,BufferGeometry,DataTexture,DoubleSide,LinearFilter,RedFormat,RepeatWrapping,UnsignedByteType} from 'three';
import {HandPull} from './HandPull';
import {handMotion} from './motion';

const N=81,VERTICES=N*N;
let sequence:Promise<Float32Array>|undefined;
const loadSequence=()=>sequence??=(fetch(staticFile('cloth/positions.bin'))
  .then(r=>{if(!r.ok)throw new Error('Cloth simulation is missing');return r.arrayBuffer();})
  .then(buffer=>new Float32Array(buffer)));

const weaveTexture=()=>{
  const size=128,data=new Uint8Array(size*size);
  for(let y=0;y<size;y++)for(let x=0;x<size;x++) {
    const warp=Math.sin(x*Math.PI/2),weft=Math.sin(y*Math.PI/2);
    const over=(Math.floor(x/2)+Math.floor(y/2))%2===0;
    const grain=Math.sin(x*12.9898+y*78.233)*43758.5453;
    data[y*size+x]=128+(over?warp:weft)*14+(grain-Math.floor(grain)-.5)*4;
  }
  const texture=new DataTexture(data,size,size,RedFormat,UnsignedByteType);
  texture.wrapS=texture.wrapT=RepeatWrapping;texture.repeat.set(48,48);
  texture.magFilter=texture.minFilter=LinearFilter;texture.needsUpdate=true;
  return texture;
};

const ClothMesh:React.FC<{positions:Float32Array;frame:number;relief:number}>=({positions,frame,relief})=>{
  const geometry=useMemo(()=>{
    const g=new BufferGeometry(),offset=frame*VERTICES*3;
    const vertices=positions.slice(offset,offset+VERTICES*3);
    for(let i=2;i<vertices.length;i+=3)vertices[i]*=relief;
    const indices:number[]=[],uv=new Float32Array(VERTICES*2);
    for(let y=0;y<N;y++)for(let x=0;x<N;x++) {
      const i=y*N+x;uv[i*2]=x/(N-1);uv[i*2+1]=1-y/(N-1);
      if(x<N-1&&y<N-1)indices.push(i,i+N,i+1,i+1,i+N,i+N+1);
    }
    g.setAttribute('position',new BufferAttribute(vertices,3));
    g.setAttribute('uv',new BufferAttribute(uv,2));g.setIndex(indices);g.computeVertexNormals();
    return g;
  },[positions,frame,relief]);
  const texture=useMemo(weaveTexture,[]);
  useEffect(()=>()=>geometry.dispose(),[geometry]);
  useEffect(()=>()=>texture.dispose(),[texture]);
  return <mesh geometry={geometry} castShadow receiveShadow>
    <meshPhysicalMaterial color="#fffefc" roughness={.96} metalness={0}
      sheen={.35} sheenColor="#ffffff" sheenRoughness={1} side={DoubleSide}
      bumpMap={texture} bumpScale={.035}/>
  </mesh>;
};

export type ClothProps={relief:number};
const ClothScene:React.FC<ClothProps&{showHand:boolean}>=({relief,showHand})=>{
  const frame=useCurrentFrame();
  const [positions,setPositions]=useState<Float32Array|null>(null);
  const [handle]=useState(()=>delayRender('Загрузка рассчитанной ткани'));
  useEffect(()=>{
    let alive=true;
    loadSequence().then(data=>{if(alive){setPositions(data);continueRender(handle);}})
      .catch(error=>cancelRender(error));
    return ()=>{alive=false;};
  },[handle]);
  if(!positions)return null;
  const contact=handMotion(frame,60).grip;
  return <AbsoluteFill style={{backgroundColor:'#faf9f7'}}>
    <ThreeCanvas width={512} height={512} orthographic camera={{position:[0,0,900],zoom:1,near:.1,far:1800}}
      dpr={1} shadows gl={{antialias:true,alpha:true,preserveDrawingBuffer:true,
        toneMapping:ACESFilmicToneMapping,toneMappingExposure:1.8}}>
      <ambientLight intensity={.9}/>
      <directionalLight position={[-220,260,380]} intensity={2.6} castShadow
        shadow-mapSize={[2048,2048]} shadow-camera-left={-380} shadow-camera-right={380}
        shadow-camera-top={380} shadow-camera-bottom={-380} shadow-camera-near={1}
        shadow-camera-far={1400} shadow-bias={-.0001} shadow-normalBias={.2} shadow-radius={4}/>
      <directionalLight position={[260,-90,340]} intensity={.65}/>
      <ClothMesh positions={positions} frame={Math.min(143,frame)} relief={relief}/>
    </ThreeCanvas>
    {showHand&&<AbsoluteFill style={{filter:`drop-shadow(2px 4px ${5-2*contact}px rgba(55,40,48,${.07+.12*contact}))`}}>
      <HandPull handSize={360} travel={1} wristRotation={1}/>
    </AbsoluteFill>}
  </AbsoluteFill>;
};

export const HandPullCloth:React.FC<ClothProps>=props=><ClothScene {...props} showHand/>;
export const ClothCleanPlate:React.FC=()=><ClothScene relief={1} showHand={false}/>;
