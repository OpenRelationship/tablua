# Assets and evals for Moonsplice: reference notes

Researched 2026-10-06 with web search. Nothing was downloaded. "Verified" means the license was read on the
source's own page or repository; "reported" means it comes from a secondary source or a summary and should be
checked before a file is committed. Moonsplice renders 3D through Bevy 0.19.1, so glTF 2.0 (.gltf/.glb) loads
directly; everything else needs conversion or Moonsplice's own loaders (2D vector, type, footage).

## Part A: openly licensed assets

### Summary table

| Source | License | Formats | Repo/binary redistribution |
|---|---|---|---|
| Kenney | CC0 1.0 (verified) | glTF 2.0, FBX, OBJ, PNG, audio (OGG/WAV) | Yes |
| Quaternius | **Quaternius Asset License v1.0 since 2026-08-28** (verified); older copies CC0 | glTF/GLB, FBX, OBJ, Blend | **No for new downloads as loose files**; yes for pre-change CC0 copies |
| Poly Haven | CC0 (verified) | HDRI (.hdr/.exr), PBR textures, models (glTF, FBX, USD, Blend) | Yes |
| ambientCG | CC0 1.0 (verified) | PBR maps (JPG/PNG), HDRI (EXR), some models, USDZ | Yes |
| Poly Pizza | Per model: CC0 or CC-BY (reported) | GLB, FBX, OBJ | Yes, with credit for CC-BY ones |
| Khronos glTF-Sample-Assets | Per model; repo itself CC-BY 4.0 (verified) | glTF/GLB (+ variants) | Mostly yes; **some models are not** |
| Bevy `assets/` | No blanket license; per-file in CREDITS.md (verified) | glTF, KTX2, HDR, OGG, TTF, PNG | Per file |
| Sketchfab | Per model; filter "CC0 Public Domain" (verified) | Original + auto-converted glTF/GLB/USDZ | CC0 ones yes; others per license |
| OpenGameArt | Per asset: CC0, CC-BY, CC-BY-SA, OGA-BY, GPL (verified) | Anything | CC0 yes; filter by license |
| Freesound | Per sound: CC0, CC-BY, CC-BY-NC, (old) Sampling+ (verified) | WAV/FLAC/AIFF/MP3/OGG | CC0 yes; **NC no for commercial** |
| Pixabay video | Pixabay Content License, **not CC0** (verified) | MP4 | **No standalone redistribution** |
| Pexels video | Pexels License, **not CC0** (verified) | MP4 | **No resale unaltered; no re-hosting on stock platforms** |
| Wikimedia Commons | Per file: PD, CC0, CC-BY, CC-BY-SA (verified) | WebM (VP8/VP9/AV1), Ogg Theora, images | PD/CC0 yes; BY-SA is copyleft |
| Blender open movies | CC-BY (3.0 for Big Buck Bunny; see below) | MP4/MKV, PNG frame sequences, production .blend | Yes, with the credit line |
| LottieFiles free | Lottie Simple License, **not CC0** (verified) | Lottie JSON, dotLottie | **No standalone redistribution of the files** |
| Google Fonts | Mostly SIL OFL 1.1; some Apache 2.0, Ubuntu Font License (verified) | TTF/OTF, variable fonts | Yes (cannot sell the fonts alone; Reserved Font Names) |

### Details per source

**Kenney** - https://kenney.nl/assets, license statement https://kenney.nl/support ("all game assets on the
asset pages are public domain licensed (CC0)"). 3D kits ship OBJ, FBX and glTF 2.0 plus PNG textures and preview
renders. Relevant kits: Watercraft Kit (45+ boats, buoys, docks; https://kenney.nl/assets/watercraft-kit, mirrored
at https://opengameart.org/content/watercraft-kit), Racing Kit (roads, borders, tents, pitstop, flags, billboards,
bridges; https://opengameart.org/content/racing-kit), City Kit (Commercial / Suburban / Roads), Car Kit, Pirate Kit,
Space Kit, Food Kit, Nature Kit, plus 2D UI packs, game icons and audio packs (Interface/Impact/RPG sounds, OGG).
Bevy fit: best of the lot. Kenney models are low-poly with a shared palette texture, so they load as plain glTF with
`StandardMaterial`, render cheaply, and Bevy's own examples already use several Kenney kits (CREDITS.md). Use these
as the default 3D library for goldens.

**Quaternius** - https://quaternius.com, license https://quaternius.com/license.html. **Flag:** the site now
publishes the Quaternius Asset License (QAL) v1.0, effective 2026-08-28. It allows use in any "Product" (game, film,
video, render), commercially, without credit, but forbids redistributing the assets "as a standalone asset, asset
pack, stock file, template, or similar product". A public repo of loose GLBs, or a binary that ships them as a
reference library the agent pulls from, plausibly counts as standalone redistribution. The license says changes are
not retroactive, and CC0 cannot be revoked, so packs obtained before 2026-08-28 under CC0 (e.g. the OpenGameArt and
itch.io mirrors that state CC0, and Sketchfab uploads marked CC0) remain usable; keep the source page and its date
with each file. Formats: glTF/GLB, FBX, OBJ, Blend; many packs are rigged and animated (walk/run/idle), which is the
main reason to want them in Bevy (glTF skins and animation clips load natively).

**Poly Haven** - https://polyhaven.com, license https://polyhaven.com/license (CC0; "You can redistribute them").
HDRIs (.hdr and .exr up to 16K+), PBR texture sets (diffuse/normal/rough/AO/displacement, PNG/EXR/JPG, up to 8K),
520+ models (glTF, FBX, USD, Blend). Public API at https://api.polyhaven.com, no key; the ToS forbids scraping, so use
the API. Bevy fit: models are glTF with separate texture files; pick 1K/2K for goldens. HDRIs are equirectangular,
while Bevy's `EnvironmentMapLight` takes prefiltered cubemaps (KTX2), so an HDRI needs a conversion step (e.g. with
KhronosGroup glTF-IBL-Sampler or Filament's cmgen), or Bevy's runtime-filtered environment map from a cubemap;
check what 0.19 accepts before choosing. Bevy's own example environment maps come from Poly Haven (HDRIHaven).

**ambientCG** - https://ambientcg.com, license https://docs.ambientcg.com/license/ (CC0 1.0 Universal; credit
optional). 2,000+ PBR materials (JPG/PNG maps at 1K-8K, usually with both OpenGL and DirectX normal maps; pick
OpenGL for Bevy, which expects +Y), 400+ HDRIs (EXR), some models and decals. Keyless API. Bevy fit: maps go into a
`StandardMaterial` by hand or into a glTF the agent writes; not glTF itself.

**Poly Pizza** - https://poly.pizza (10,700+ low-poly models, many from Google Poly's archive). Each model is labeled
CC0 or CC-BY 3.0/4.0 (reported; the license page and API docs did not render in fetch, confirm per model). GLB, FBX,
OBJ downloads; API at https://poly.pizza/docs/api/v1.1 needs a free account key. Bevy fit: GLB loads directly;
CC-BY models need a credits file entry carried with any piece that uses them. Filter to CC0 for goldens.

**Khronos glTF-Sample-Assets** - https://github.com/KhronosGroup/glTF-Sample-Assets. The repository is "CC-BY-4.0
International", but each model has its own license in its README. Most are CC0 or CC-BY 4.0. **Flag these:** Duck
(SCEA Shared Source License 1.0, Sony), BrainStem (Poser EULA), EnvironmentTest (Adobe Stock license), a few
CC-BY-NC models, and several models with "non-Khronos mark" trademark notes (e.g. Cesium logos on CesiumMan,
BoxTextured). Models-testing.md and Models-core.md list license per model. Bevy fit: this is the conformance set; use
it for loader goldens (MetalRoughSpheres, TextureCoordinateTest, AlphaBlendModeTest, AnimatedMorphCube, Fox,
DamagedHelmet, Sponza, FlightHelmet; check each one's README first).

**Bevy's own assets folder** - https://github.com/bevyengine/bevy/tree/main/assets. The Bevy README says the assets
"typically fall under different open licenses ... they are not distributed in the published bevy crates. See
CREDITS.md". There is no folder-wide license; the code's MIT/Apache-2.0 does not cover them. CREDITS.md lists: Kenney
kits (CC0), HDRIHaven environment maps (CC0), Generic RPG Pack (CC0), the glTF fox (model CC0 by PixelMannen,
rigging/animation CC-BY 4.0 by @tomkranis), FiraSans/FiraMono (SIL OFL 1.1), MorphStressTest.gltf (CC-BY 4.0),
acoustic guitar sample (CC0), epic orchestra sample (CC-BY 4.0), barycentric mesh (MIT OR Apache-2.0). Files not in
CREDITS.md were presumably made for Bevy and fall under the repo's MIT/Apache-2.0, but that is an inference: copy
only listed files, with their credit.

**Sketchfab** - https://sketchfab.com/search?features=downloadable&type=models, then the "CC0 Public Domain" license
filter (https://sketchfab.com/blogs/community/refine-downloadable-model-searches-with-new-license-filters). Each model has its own
license (CC0, CC-BY, CC-BY-SA, CC-BY-NC, ...). Every downloadable model is auto-converted to glTF, GLB (several
texture sizes) and USDZ besides the original upload. Downloads need an account; the Download API needs OAuth.
Bevy fit: glTF native, but auto-converted files vary in quality (huge textures, unapplied transforms, unlit
materials); verify each one renders in Bevy before it becomes a golden. Only CC0 avoids per-piece credits.

**OpenGameArt** - https://opengameart.org, licenses https://opengameart.org/content/faq. Accepts CC0, CC-BY 3.0/4.0,
CC-BY-SA 3.0/4.0, OGA-BY 3.0/4.0, GPL 2.0/3.0, and per asset. Search can filter by license
(https://opengameart.org/art-search-advanced, "CC0"). Hosts Kenney mirrors and older CC0 Quaternius packs. Formats are
whatever the author uploaded (PNG sprites, OGG/WAV, Blend, OBJ, sometimes glTF). Bevy fit: sprites and audio more than
3D. **Flag:** CC-BY-SA and GPL items impose share-alike on derivatives; keep them out of the shipped library.

**Freesound** - https://freesound.org, licenses https://freesound.org/help/faq/. Per sound: CC0, CC-BY, CC-BY-NC
(and legacy Sampling+). Filter "Creative Commons 0" in search. Example leads: ship foghorns by digifishmusic and
hoersturz (check license per sound), "LargeWoodenShip" by PimFeijen (reported CC0); search "splash", "bell", "ship
horn", "buoy bell" with the CC0 filter. The API needs a token; original-quality downloads need OAuth2 (previews are
lossy MP3/OGG). Bevy fit: Bevy plays OGG/Vorbis by default, WAV/FLAC/MP3 behind features; transcode to OGG.
**Flag:** CC-BY-NC sounds and Sampling+ cannot go in a commercial binary.

**Pixabay video** - https://pixabay.com/videos/, license https://pixabay.com/service/license-summary/. Not CC0.
Free use, no attribution, modification allowed; prohibited: to "sell or distribute Content (either in digital or
physical form) on a Standalone basis" (no creative effort applied, substantially unchanged), commercial use of
content showing brands for goods/services, trademark use, misleading use. **Flag:** committing raw clips to a public
repo or shipping them in a binary as stock the user can pull out is standalone redistribution. Rendered pieces that
use a clip are fine. Avoid for goldens.

**Pexels video** - https://www.pexels.com/videos/, license https://www.pexels.com/license/. Not CC0. Free use, no
attribution, modification allowed; prohibited: selling unaltered copies, redistributing or selling "on other stock
photo or wallpaper platforms", implying endorsement, trademark use, showing identifiable people in a bad light.
**Flag:** an asset library of raw Pexels clips shipped with Moonsplice is close to re-hosting stock; avoid for goldens.

**Wikimedia Commons stock footage** - https://commons.wikimedia.org/wiki/Commons:Free_media_resources/Video and
categories such as Category:Videos_by_NASA and Category:Public_domain_videos. License is per file, on the file page
(PD-USGov-NASA, PD-self, CC0, CC-BY, CC-BY-SA). NASA footage is public domain in the US unless noted (e.g. "ISS 4K Crew
Earth Observations.webm", "Horizon to full Galaxy (SVS127).webm"). Formats: WebM (VP8/VP9/AV1, Opus/Vorbis), Ogg
Theora; transcodes on upload.wikimedia.org. This is what the eval media list already uses; it suits goldens because
PD files can be committed. **Flag:** CC-BY-SA clips are copyleft (a piece made from one must be shared alike), and
"public domain in the US" is not worldwide for some government works; record the license template per file.

**Blender open movies** - https://studio.blender.org/films/. Credit line: "(CC) Blender Foundation |
studio.blender.org". Big Buck Bunny (2008): CC-BY 3.0 (verified via Wikipedia's list of open-source films; also
Sintel and Tears of Steel CC-BY 3.0, Spring CC-BY 4.0, Coffee Run CC-BY 4.0). Sprite Fright (2021): the film's
about page states "Creative Commons Attribution 1.0" as fetched, which looks like a typo for 4.0; confirm on
https://studio.blender.org/films/sprite-fright/pages/about before relying on the version. Charge (2022): no license
statement found in this search (the premiere post states none); treat as unverified until the film's licensing page
is read. Formats: MP4/MKV masters up to 4K, some as PNG/EXR frame sequences; production files (.blend) partly behind
the Blender Studio subscription. Bevy fit: footage only (Moonsplice's footage path); .blend files would need export to
glTF, and Studio-gated files are not openly downloadable. CC-BY is fine for repo and binary with the credit line kept.

**LottieFiles free animations** - https://lottiefiles.com/free-animations, license
https://lottiefiles.com/page/license (Lottie Simple License), summary at
https://help.lottiefiles.com/animation-licensing-basics-. Not CC0. Allowed: free, commercial, modify, use in your
products, no attribution required. Prohibited: compiling or scraping animations to make a competing service,
redistributing "as standalone animation files", reselling the originals; distributions must carry the same terms.
**Flag:** a repo or binary that ships a library of raw LottieFiles JSON for an agent to reuse is both standalone
redistribution and arguably a compiled collection. Use them only inside rendered pieces. For goldens prefer Lottie
files under a code license (e.g. test files in airbnb/lottie-web, Samsung/rlottie or Skia's Skottie resources; check
each repo's license and whether the JSON was contributed under it) or author the goldens in-house.

**Google Fonts** - https://fonts.google.com, files at https://github.com/google/fonts (each family's directory has its
LICENSE: `ofl/`, `apache/`, `ufl/`). OFL 1.1 allows bundling, embedding and redistributing with any software,
including commercial, but not selling the fonts by themselves; modified versions may not use Reserved Font Names.
Formats: TTF (many variable), some OTF. Bevy fit: Bevy's text renders TTF/OTF; variable-font axes may not all be
exposed, so pin static instances for goldens. Keep each LICENSE/OFL.txt next to the font.

### What forbids redistribution in a repo or binary

1. **Pixabay** and **Pexels**: standalone redistribution / re-hosting prohibited. Fine inside a rendered piece.
2. **LottieFiles free animations**: standalone redistribution and compiling collections prohibited.
3. **Quaternius after 2026-08-28** (QAL v1.0): standalone redistribution prohibited. Pre-change CC0 copies are fine.
4. **Khronos sample models** under SCEA (Duck), Poser EULA (BrainStem), Adobe Stock (EnvironmentTest), CC-BY-NC, and
   the trademark-noted models.
5. **Per-item non-commercial or share-alike**: Freesound CC-BY-NC and Sampling+, OpenGameArt CC-BY-SA/GPL,
   Wikimedia CC-BY-SA, Sketchfab NC/SA models.
6. **Bevy assets**: fine per CREDITS.md, but three items are CC-BY 4.0 (fox animation, MorphStressTest, orchestra
   sample) and need credit; FiraSans is OFL.

Recommended golden library: Kenney (3D kits, UI, audio), Poly Haven (HDRIs, a few models), ambientCG (materials),
CC0 Khronos samples (loader checks), CC0 Freesound sfx, Wikimedia PD footage, Blender CC-BY films (credit kept),
Google Fonts OFL, and in-house Lottie. Keep a `CREDITS` row per file: source URL, license, date fetched.

## Part B: how visual work is tested, and agent benchmarks

### Rendering tests in engines and renderers

**Bevy example screenshots + Pixel Eagle.** Bevy's CI runs examples under `.github/example-run/*.ron` configs on
macOS/Metal, Linux/Vulkan and Windows/DX12, takes screenshots at fixed frames, and uploads them to Pixel Eagle
(https://pixel-eagle.com, by Vleue), which compares a PR's run against main (PR #13248 "Compare screenshots with main
on PRs"; #15894, #16655, #17125, #17573 "Smarter testbeds"). Pixel Eagle offers exact XOR comparison (any single
pixel change), NVIDIA FLIP perceptual comparison, metadata pairing (platform, resolution, API) and a "golden record"
baseline per project that changes only by approval. Testbeds are small purpose-built scenes (2D, 3D, UI) rather than
every example. Lesson: deterministic frame numbers, per-platform baselines, a human approves new baselines.

**wgpu** (`wgpu_test::image`, https://wgpu.rs/doc/src/wgpu_test/image.rs.html) compares a test render to a PNG
reference with NVIDIA FLIP through the `nv-flip` crate. FLIP gives a per-pixel error in [0,1]; the errors go into a
weighted histogram and the test fails by `ComparisonType::Mean(threshold)` or `Percentile { percentile, threshold }`.
Suggested thresholds are 0.01-0.1; high percentiles (95%/99%) catch failures concentrated in a small area. On failure
it writes the actual image and a FLIP error map colored with the magma LUT; missing references are generated.

**Vello** (`vello_tests`) has property tests on CPU and GPU, snapshot tests with a non-exact comparison (Apple "fast
math" differs), CPU-vs-GPU comparison tests, a small always-on `smoke_snapshots` set in the repo and the rest in
git LFS, and xtask commands that use Kompari (Linebender's image-diff/report tool) to produce snapshot and comparison
reports.

**NVIDIA ꟻLIP** (https://github.com/NVlabs/flip, BSD-3-Clause; Andersson et al., HPG 2020). Full-reference
difference evaluator for rendered images vs. ground truth, modelling what a viewer sees when flipping between the
two at a given viewing distance (pixels per degree). LDR-FLIP and HDR-FLIP; outputs a per-pixel map, a weighted
histogram or a mean. C++, CUDA, Python, PyTorch; Rust via `nv-flip`. Best fit for engine goldens because it was built
for rendering artifacts (aliasing, fireflies, color shifts) and gives a map that can be localised to nodes.

**SSIM** (Wang et al. 2004) compares local luminance, contrast and structure; cheap, deterministic, but insensitive to
color shifts and sensitive to sub-pixel shifts. **LPIPS** (Zhang et al., CVPR 2018) is a learned distance on deep
features (AlexNet/VGG), close to human judgments of "similar", but needs a network, is not a regression metric for
exact rendering, and is blind to small but important errors (a missing small title). Use FLIP or exact hashes for
regressions; LPIPS/SSIM only as soft "close to reference" scores.

### Agent and LLM benchmarks for games, motion and 3D (2024-2026)

| Benchmark | Output | How it is judged | Carries over |
|---|---|---|---|
| **BlenderGym** (CVPR 2025, arXiv 2504.01786) | Edits to a Blender scene via Python | 245 start/goal scene pairs in 5 kinds (procedural geometry 50, lighting 40, procedural material 40, blend shapes 75, placement 40). Metrics: photometric loss, N-CLIP (1 - CLIP score), Chamfer distance on geometry. No LLM judge. Generator (brainstormer + code editor, b=4 proposals) and verifier (pairwise tournament), depth 3 | **Start/goal goldens**: give the agent a comp and a goal render; score the distance after each move. Moves that reduce the distance are progress, which gives the "complete" label an engine-measured meaning |
| **SceneCraft** (ICML 2024, arXiv 2403.01248) | Blender Python for scenes up to ~100 assets | Scene graph as blueprint, relations to numeric constraints; constraint satisfaction on synthetic queries with known constraints, CLIP score, human ratings; VLM critique loop; library learning | Write the ask's relations as **constraints the engine can check** (left-of, on-top, inside-frame) |
| **3D-GPT** (arXiv 2310.12945) | Infinigen parameters via multi-agent LLM | Mostly qualitative, CLIP, user study | Procedural parameters as moves; weak eval, little to copy |
| **3DCodeBench** (arXiv 2606.01057) | Blender scripts for procedural objects (Infinigen factories) | 212 categories, human-verified triplets; multi-turn refinement with runtime feedback helps | Runtime feedback (our findings) as the refinement signal |
| **V-GameGym** (arXiv 2509.20136) | Pygame games | 2,219 samples; three 0-100 scores: code (Qwen3-Coder judge), screenshot (Qwen2.5-VL), gameplay video (Qwen2.5-VL), each four 0-25 sub-scores; top model ~45% | Separating static-frame and motion scores; but all-LLM judging is what to avoid |
| **WebGameBench** (arXiv 2605.17637) | Browser games from specs | 111 tasks; an evaluator plays the game in a real browser and labels EXCELLENT / USABLE / UNUSABLE, validated against human play; best 76.9% usable, 20.2% excellent | A three-way label like ours; "usable" vs "excellent" gap mirrors gate vs critic |
| **GameASG-Bench** (arXiv 2609.21293) | Browser games, 2D and 3D | 47 tasks; an interface spec declared before generation (start states, player actions, stable snapshots, rejections, invariants); L1 source checks, L2 browser runs with real input; best strict success 55.3% though L2 check pass 93.2% | **Declare the probes before the work**: a comp's ask comes with named snapshots and invariants |
| **GameLogicBench** (arXiv 2609.21562) | Godot gameplay logic | 72 tasks, 1,451 seeded cases; assertions on game state at two or more ticks, checked at every tick; deterministic judge, no LLM; evaluator validated by rejecting mutants with one capability removed; best 52.8% | **Tick-level assertions** and **mutant validation of the oracle** (our `.robot/mutate.lua` idea, applied to evals) |
| **OpenGame / OpenGame-Bench, PlaytestArena** (2026; see github.com/imclab/awesome-game-gen) | Web games | Headless browser + VLM judge; PlaytestArena plays against rubrics | Rubric-per-ask for the critic |
| **Orak, GVGAI-LLM, gg-bench** | Agents playing games | Win rate, scores | Not generation; skip |
| **SVGenius** (arXiv 2506.03139) | SVG understand/edit/generate | 2,377 queries, 8 task kinds, 18 metrics, complexity tiers; degradation with complexity | **Editing tasks with exact expected diffs**; tier asks by complexity |
| **StarVector / SVG-Bench** (CVPR 2025) | SVG from images/text | Image metrics vs. target (from memory: DinoScore, LPIPS, MSE; not rechecked), 10 datasets | Image-to-vector goldens |
| **VectorGym** (arXiv 2603.29852) | SVG: sketch-to-SVG, editing, text-to-SVG, captioning | Multitask | Same |
| **MoVer** (SIGGRAPH 2025, TOG 44(4), arXiv 2502.13372) | SVG motion graphics from text | A first-order-logic DSL over spatio-temporal predicates (direction, timing, relative position, order); the LLM writes the animation and a MoVer program; failed predicates fed back. 5,600 prompts: 58.8% correct at once, 93.6% with up to 50 correction rounds | **The closest fit**: predicates over keys and node tracks are engine-checkable; each failed predicate is a finding the next move can close |
| **LogoMotion** (2024; from memory, not rechecked) | Animated logos in HTML/JS | Visually grounded code synthesis, VLM check | Critic-in-the-loop for motion |
| **OmniLottie** (CVPR 2026, arXiv 2603.02138), **LottieGPT** (CVPR 2026) | Lottie JSON | MMLottie-2M dataset and MMLottieBench; LottieAnimation-660K | Lottie corpora; metrics not confirmed here |
| **Code2Video / MMMC** (Show Lab, arXiv 2510.01174) | Manim educational videos | Planner/coder/critic agents; MMMC from 3Blue1Brown-style topics; aesthetics, efficiency, and TeachQuiz (a model unlearns a concept, watches the video, is quizzed) | Critic with **visual anchor** prompts for layout; outcome measured by what the piece achieves |
| **HeyGen Code2Video Benchmark** (2026-09-18) | HTML/React motion graphics for product launches | 168 briefs in 8 categories (hook, problem, product intro, feature, benefits, social proof, CTA, outro); five axes (engagement, prompt-intent, composition, temporal, craft); a judge trained on human preferences, 82% human agreement vs 75% for general VLMs; Elo from pairwise | Our six critic dims; **pairwise judging is more reliable than absolute 1-5** |
| **Timeline-Bench** (arXiv 2609.35143, 2026-09-28) | Finished edits from raw footage | 56 tasks; tests for delivery format (codec, fps, duration, audio), content defects (silence, frozen frames, repeated footage, face cropping), brief compliance (frame/sound matching, OCR, speech-to-text), and a quality test by three VLM judges calibrated on 2,582 blind pairwise judgments by 43 editors (agent-level ρ 0.93, per-edit κ 0.15); best 26.8%; 562 of 771 failures fail only quality | **Layered oracles**: deterministic tests first, critic last; critic is reliable across many pieces, not per piece |
| **AgenticVBench** (arXiv 2605.27705) | Post-production tasks | 100 tasks from 20 professionals; programmatic verifiers plus expert rubrics; best ~30%; the harness changes results | Report harness with model |

### What carries over to move-by-move patching

Moonsplice judges each move as complete, neutral, no effect or broken, from the engine's findings, and judges the
piece with the gate and the critic's six dims. Ideas worth taking:

1. **Goal-state goldens (BlenderGym).** Pair a seed comp with a goal comp. After each move, measure distance in the
   engine: node/prop diff on rows, FLIP mean on sampled frames. A move that lowers the distance is progress; one that
   leaves it the same is neutral even if no finding moved. This gives "neutral" an oracle the findings lack.
2. **Predicates as findings (MoVer, GameASG, GameLogicBench).** Write each ask's requirements as checkable predicates
   over the comp's tracks: "title enters from left between 0.2 s and 0.6 s", "boat stays inside frame", "bell sound
   within 1 frame of buoy bob peak". Each failed predicate is an open finding; a move that closes one is complete.
   This fixes the trial-1 problem (opacity 0 hid a title and no finding saw it).
3. **Tick-level assertions.** Check predicates at every sampled frame, not only at the end; motion errors live between
   keys.
4. **Validate the oracle with mutants (GameLogicBench).** For each golden, apply mutants (drop a key, zero an opacity,
   swap two nodes' z) and require the oracle to fail on each. An oracle that passes a mutant is not a test.
5. **Declare probes before the work (GameASG-Bench).** The ask ships named snapshot times and invariants; the agent
   cannot move the goalposts.
6. **Layer the judges (Timeline-Bench).** Delivery checks (duration, fps, audio present) and defect checks (frozen
   frames, silence, off-frame text) are deterministic and come first; the vision critic is last, scores pairwise
   against a reference where possible, and is trusted in aggregate across runs, not per step.
7. **Pairwise over absolute (HeyGen, Timeline-Bench).** A critic asked "is A better than B on composition" agrees more
   with people than one asked for a 1-5 score. For move outcomes, compare before/after sheets.
8. **FLIP for render regressions (wgpu, Bevy/Pixel Eagle).** Mean and 99th-percentile FLIP per frame against a
   golden; frame hashes for exact determinism on one platform; per-platform baselines.
9. **Usable vs excellent (WebGameBench).** Report two rates: gate passes (usable) and all six critic dims >= 3
   (excellent), the same split as `pass`.
10. **Report harness and seed.** Results vary with harness (AgenticVBench); log seed, model, decider and ranker mode.

## 20 eval ideas for Moonsplice

Each: **ask** (what the agent is told), **seed** (starting comp), **pass oracle** (engine-measurable unless marked
critic), **assets**. "Frame t" means the engine's rendered frame at time t; FLIP thresholds follow wgpu's 0.01-0.1
guidance and need calibrating per golden.

1. **Title in, hold, out.** Ask: a 4 s title card, text slides in from the left over 0.5 s, holds, fades out by 4 s.
   Seed: empty comp, 1920x1080, 30 fps. Oracle: text node's bbox x at 0 s is off-frame left, inside the safe area from
   0.5 s to 3.5 s; opacity 1 at 2 s and 0 at 4 s; no text overflow finding. Assets: Google Fonts (Inter or Roboto, OFL).
2. **Hidden title (regression for trial 1).** Ask: make the title readable. Seed: a comp whose title has opacity 0, or
   same color as the background, or z behind a full-frame rect. Oracle: title glyph pixels differ from background by
   contrast ratio >= 4.5:1 at frame 1 s; title bbox not occluded (z-order check). Mutants: each of the three hides.
   Assets: Google Fonts.
3. **Boat crosses the bay.** Ask: a low-poly boat crosses the frame left to right in 6 s on water, camera fixed.
   Seed: comp with a 3D camera and a water plane. Oracle: boat node world x increases monotonically; boat bbox inside
   frame from 1 s to 5 s; boat y within 0.1 m of water height. Assets: Kenney Watercraft Kit (CC0, glTF), Poly Haven
   HDRI.
4. **Buoy bob with bell.** Ask: buoy bobs with a 2 s period; a bell sounds at each peak. Seed: buoy on water. Oracle:
   buoy y is periodic with period 2 s +- 1 frame; audio onsets within 1 frame of y maxima. Assets: Kenney Watercraft
   (buoy), Freesound CC0 bell.
5. **Horn on arrival.** Ask: the ship sounds its horn when it reaches the dock. Seed: ship path to a dock, no audio.
   Oracle: horn onset within 2 frames of ship-dock bbox contact; horn duration 1-3 s; no clipping (peak < 0 dBFS).
   Assets: Kenney Watercraft, Freesound CC0 horn.
6. **Splash on impact.** Ask: a crate drops into the water and splashes. Seed: crate above water. Oracle: crate y
   crosses water height at time T; a particle/splash node becomes visible within 1 frame of T; splash sound onset
   within 2 frames of T. Assets: Kenney (crate), Freesound CC0 splash.
7. **Match the goal render (BlenderGym-style, placement).** Ask: make this scene match the reference frame. Seed: a
   racing-kit scene with three props moved; a goal render. Oracle: per-node position error < 0.05 m against the goal
   comp, and FLIP mean < 0.02 at the goal frame. Assets: Kenney Racing Kit.
8. **Match the goal render (lighting).** Ask: relight to match the reference. Seed: city block, sun at wrong angle and
   color. Oracle: directional light angle within 5 degrees, color within delta-E 3 of the goal; FLIP mean < 0.05.
   Assets: Kenney City Kit, Poly Haven HDRI.
9. **Material swap.** Ask: make the floor weathered concrete. Seed: plane with a flat grey `StandardMaterial`.
   Oracle: material has base color, normal and roughness textures bound; normal map is OpenGL convention (engine
   check on green channel or metadata); no missing-texture finding. Assets: ambientCG concrete (CC0).
10. **glTF loader conformance.** Ask: place these sample models on a turntable, 360 degrees in 8 s. Seed: empty 3D
    comp. Oracle: each model loads with no error finding; each rotation key reaches 360 degrees at 8 s; FLIP mean vs
    per-model golden at 0 s < 0.02. Assets: Khronos CC0/CC-BY samples (MetalRoughSpheres, AlphaBlendModeTest,
    TextureCoordinateTest), not Duck or BrainStem.
11. **Skinned animation playback.** Ask: the fox walks across the frame, then runs. Seed: fox glTF loaded, idle.
    Oracle: active clip is Walk during 0-3 s and Run after; root x velocity higher in the run phase; feet stay above
    ground plane. Assets: Bevy's fox (model CC0, animation CC-BY 4.0, credit kept) or a pre-2026-08-28 CC0 Quaternius
    animal.
12. **Lower-third over footage.** Ask: add a lower-third name and title over this clip, in for 4 s, never covering a
    face. Seed: comp with a Wikimedia PD clip on track 1. Oracle: lower-third bbox in the bottom third and inside the
    title-safe area; on screen 4 s +- 1 frame; contrast >= 4.5:1 against the footage under it on every sampled frame;
    face overlap measured by a detector, or critic if none. Assets: Wikimedia Commons PD footage (NASA), Google Fonts.
13. **Cut on the beat.** Ask: cut between three clips on the music's beats. Seed: three footage clips and a music
    track. Oracle: every cut lies within 1 frame of a detected beat onset; no clip shorter than 12 frames; no frozen
    frames (frame-hash runs). Assets: Blender open movies (CC-BY, credit), Freesound CC0 or Kenney music loop.
14. **Credit line present.** Ask: finish this edit of Big Buck Bunny for publishing. Seed: a trimmed BBB comp without
    credit. Oracle: a text node containing "Blender Foundation" and "studio.blender.org" is visible for >= 2 s
    (OCR on the frame or the node's text plus visibility). Tests that license duties are honored. Assets: Big Buck
    Bunny (CC-BY 3.0).
15. **Lottie in a comp.** Ask: place this loader animation centered and loop it 3 times in 6 s. Seed: comp with an
    in-house Lottie JSON. Oracle: node centered within 2 px; loop count 3 (frame hash at t and t + 2 s equal); scale
    keeps aspect. Assets: in-house Lottie (not LottieFiles raw JSON in the repo).
16. **Logo build (MoVer-style predicates).** Ask: the three shapes of the logo arrive one after another, top to
    bottom, each with an ease-out, done by 1.5 s. Seed: three static vector shapes. Oracle: start times strictly
    ordered by y; each entry's velocity decreasing near its end (ease-out); all at rest by 1.5 s; no subpixel_drift
    warning at rest. Assets: none (vector).
17. **Arcade loop: catch the falling.** Ask: a small game; the player paddle catches falling items, score shows top
    right. Seed: empty game comp. Oracle (tick-level, scripted input): with a recorded input that moves under each item,
    score increments by 1 per catch at the catch tick; with no input, score stays 0 and items despawn below frame;
    score text bbox top-right. Mutant check: removing the despawn system must fail. Assets: Kenney 2D sprites (CC0),
    Kenney Interface Sounds.
18. **Racing lap timer.** Ask: a top-down car follows the track and a lap timer shows lap times. Seed: Kenney racing
    track, car, no systems. Oracle: car stays within track bounds on every tick of the scripted lap; the timer resets
    when the car crosses the start line; lap time shown equals measured crossing interval +- 1 frame. Assets: Kenney
    Racing Kit or Car Kit.
19. **Fix the broken comp.** Ask: make it render. Seed: comp with three injected errors (a key on a missing prop, a bind
    to a removed node, a derive with a quoted number). Oracle: gate passes (no error findings); the moves that close
    each error are labeled complete; no new findings opened; output frames match a golden with FLIP mean < 0.01.
    Assets: any of the above. Tests the outcome labels directly.
20. **Polish without regressions.** Ask: improve composition and pacing without changing the story. Seed: a passing
    30 s piece (gate clean) with a golden scene graph. Oracle: gate stays clean on every step; node set and scene order
    unchanged (row diff); critic pairwise preference for the final over the seed on composition and temporal dims (critic,
    judged blind, 3 samples); frame-hash diff shows the change touched >= 1 s of frames (not neutral). Assets: Kenney
    3D kits, Poly Haven HDRI, Google Fonts, Wikimedia PD footage.

## Sources

- Kenney: https://kenney.nl/support, https://kenney.nl/assets/watercraft-kit, https://opengameart.org/content/racing-kit
- Quaternius: https://quaternius.com/license.html
- Poly Haven: https://polyhaven.com/license, https://docs.polyhaven.com/en/faq
- ambientCG: https://docs.ambientcg.com/license/
- Poly Pizza: https://poly.pizza
- Khronos: https://github.com/KhronosGroup/glTF-Sample-Assets, .../Models/Models-testing.md, .../Models/Duck/README.md
- Bevy: https://github.com/bevyengine/bevy/blob/main/README.md, https://github.com/bevyengine/bevy/blob/main/CREDITS.md,
  https://github.com/bevyengine/bevy/pull/13248, https://github.com/bevyengine/bevy/pull/17573, https://pixel-eagle.com/features/
- Sketchfab: https://sketchfab.com/blogs/community/refine-downloadable-model-searches-with-new-license-filters
- OpenGameArt: https://opengameart.org/content/faq
- Freesound: https://freesound.org/help/faq/
- Pixabay: https://pixabay.com/service/license-summary/
- Pexels: https://www.pexels.com/license/
- Wikimedia: https://commons.wikimedia.org/wiki/Commons:Free_media_resources/Video
- Blender films: https://studio.blender.org/films/sprite-fright/pages/about, https://en.wikipedia.org/wiki/List_of_open-source_films
- LottieFiles: https://help.lottiefiles.com/animation-licensing-basics-, https://lottiefiles.com/page/license
- Google Fonts: https://github.com/google/fonts
- wgpu: https://wgpu.rs/doc/src/wgpu_test/image.rs.html, https://docs.rs/nv-flip
- Vello: https://github.com/linebender/vello/tree/main/vello_tests
- FLIP: https://github.com/NVlabs/flip, https://research.nvidia.com/publication/flip
- LPIPS: https://github.com/richzhang/PerceptualSimilarity
- BlenderGym: https://arxiv.org/abs/2504.01786; SceneCraft: https://arxiv.org/abs/2403.01248; 3D-GPT: https://arxiv.org/abs/2310.12945;
  3DCodeBench: https://arxiv.org/abs/2606.01057
- V-GameGym: https://arxiv.org/abs/2509.20136; WebGameBench: https://arxiv.org/abs/2605.17637; GameASG-Bench:
  https://arxiv.org/abs/2609.21293; GameLogicBench: https://arxiv.org/abs/2609.21562; awesome-game-gen:
  https://github.com/imclab/awesome-game-gen
- SVGenius: https://arxiv.org/abs/2506.03139; StarVector: https://arxiv.org/abs/2312.11556; VectorGym: https://arxiv.org/abs/2603.29852
- MoVer: https://arxiv.org/abs/2502.13372; OmniLottie: https://arxiv.org/abs/2603.02138
- Code2Video (Show Lab): https://arxiv.org/abs/2510.01174; HeyGen Code2Video Benchmark:
  https://www.heygen.com/research/introducing-code2video-benchmark
- Timeline-Bench: https://arxiv.org/abs/2609.35143; AgenticVBench: https://arxiv.org/abs/2605.27705
