import assert from 'node:assert/strict';
import sharp from 'sharp';
import {readFile} from 'node:fs/promises';
const root = new URL('../../../HandPullLab/Resources/', import.meta.url);
const descriptor = JSON.parse(await readFile(new URL('HandAnimation.json', root)));
for (const name of descriptor.frameNames) {
  const metadata = await sharp(new URL(`${descriptor.frameDirectory}/${name}.png`, root).pathname).metadata();
  assert.equal(metadata.width, 512);
  assert.equal(metadata.height, 512);
  assert(metadata.hasAlpha);
}
for (const frame of ['000', '143']) {
  const data = await sharp(new URL(`HandPullRemotion/remotion_${frame}.png`, root).pathname)
    .ensureAlpha().raw().toBuffer();
  assert(data.every((value, index) => index % 4 !== 3 || value === 0), 'Крайний кадр должен быть прозрачным');
}
// Область складок под кистью, без пикселей самой руки. На светлом фоне
// тени должны различаться и после уменьшения изображения до экрана iPhone.
const data = await sharp(new URL('HandPullRemotion/remotion_085.png', root).pathname)
  .flatten({background: '#f8f8f8'}).raw().toBuffer();
let visibleShadowPixels = 0;
for (let y = 275; y < 390; y++) for (let x = 95; x < 205; x++) {
  const i = (y * 512 + x) * 3;
  if ((data[i] + data[i + 1] + data[i + 2]) / 3 < 220) visibleShadowPixels++;
}
assert(visibleShadowPixels > 100, `Складки теряются на светлом фоне: ${visibleShadowPixels} различимых пикселей`);
console.log(`144 PNG: холст и прозрачность корректны; различимых пикселей складок: ${visibleShadowPixels}.`);
