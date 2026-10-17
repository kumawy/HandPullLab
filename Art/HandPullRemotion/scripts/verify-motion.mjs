import assert from 'node:assert/strict';
import {handMotion} from '../src/motion.ts';
const at=frame=>handMotion(frame,60);
assert(at(108).y<at(75).y-60,'During the grip, the hand must pull UP by at least 60px');
for(let frame=75;frame<=108;frame++) {
 assert.equal(at(frame).grip,1,'Grip must remain closed throughout the upward pull');
 assert(at(frame).y<=at(frame-1).y+.01,'Pull must not reverse downward');
}
assert.equal(at(112).grip,1,'Keep the grip until the upward pull finishes');
assert(at(120).grip<1&&at(126).grip===0,'Release only after the pull');
assert.equal(at(0).opacity,0,'Start hidden for a clean one-shot/loop');
assert.equal(at(143).opacity,0,'Leave upward and end hidden');
assert.equal(at(75).pullProgress,0);
assert.equal(at(108).pullProgress,1);
assert.equal(at(143).pullProgress,1,'Catalog return progress must not reverse during departure');
console.log('Motion verified: upward pull, closed grip, delayed release, hidden endpoints.');
