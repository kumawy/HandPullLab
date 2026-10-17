import {Composition,Still} from 'remotion';
import {HandPull} from './HandPull';
import {ClothCleanPlate,HandPullCloth} from './Cloth';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="HandPull" component={HandPull} durationInFrames={144}
        fps={60} width={512} height={512}
        defaultProps={{handSize:360,travel:1,wristRotation:1}} />
      <Composition id="HandPullCloth" component={HandPullCloth} durationInFrames={144}
        fps={60} width={512} height={512} defaultProps={{relief:1}}/>
      <Still id="ClothCleanPlate" component={ClothCleanPlate} width={512} height={512}/>
    </>
  );
};
