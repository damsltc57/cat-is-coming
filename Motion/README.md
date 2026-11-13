# Cat notification animation

The two clips use the original cat illustration and a matching keyboard drawn underneath. The HyperFrames composition is 256 × 256 and each clip runs for two seconds. The `departure` variable switches between arrival and departure.

From the repository root, with Node.js 22+, Chrome and FFmpeg installed:

```sh
work=$(mktemp -d)
npm install --prefix "$work" hyperframes@0.9.15
mkdir -p "$work/composition/assets"
cp Motion/index.html "$work/composition/"
cp Sources/Assets.xcassets/CatArtwork.imageset/cat.png "$work/composition/assets/"
cp "$work/node_modules/hyperframes/dist/vendor/npm/gsap@3.15.0/dist/gsap.min.js" "$work/composition/assets/"
hf="$work/node_modules/.bin/hyperframes"
"$hf" check "$work/composition"
"$hf" render "$work/composition" --format mov -o "$PWD/Sources/Animations/CatArrives.mov"
"$hf" render "$work/composition" --format mov --variables '{"departure":true}' -o "$PWD/Sources/Animations/CatLeaves.mov"
```

The MOVs use ProRes 4444 so the rounded illustration stays transparent around its edges in the notification.
