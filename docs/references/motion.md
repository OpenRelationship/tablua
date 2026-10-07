# Bevy motion, VFX and rendering references

A reference library for the Moonsplice agent (Bevy 0.19.1 for 3D). Compiled 2026-10-06.

## How this was verified

- **Bevy version** comes from the `bevy` dependency of the newest published crate on crates.io (API, 2026-10-06),
  or from `Cargo.toml` on the default branch when there is no crate or the branch is ahead. `^0.19` covers 0.19.1.
  For context: Bevy 0.19.0 shipped 2026-06-18, 0.19.1 on 2026-08-13, and 0.20.0-rc.2 on 2026-09-28.
- **License** comes from the crate's `license` field (crates.io) and the GitHub-detected license file. GitHub
  often reports only "Apache-2.0" for a dual MIT/Apache repo; the crate field is the authority for code.
  Asset licenses are noted only where the README or a CREDITS file states them. "Unverified" means not checked.
- **Golden** answers whether a still frame at a fixed time is reproducible. Bevy's own CI makes frames
  reproducible by setting `TimeUpdateStrategy::ManualDuration` through `CI_TESTING_CONFIG`; see the end.
  GPU output still differs across vendors and drivers, so goldens are per platform and compared with a tolerance
  (Bevy's CI keeps separate macOS Metal and Linux Vulkan baselines on Pixel Eagle).
- No code was downloaded or run. The eval ideas are untested proposals.

Critic axes referenced in the eval ideas: rule, relationship, rhythm, memorability, craft.

---

## 1. Motion graphics and presentation

### MotionGfx / bevy_motiongfx
- Repo: https://github.com/voxell-tech/motiongfx (moved from nixon-voxell/bevy_motiongfx)
- License: MIT OR Apache-2.0 (crate and README). Bevy: `bevy_motiongfx` 0.4.0 (2026-10-02) needs bevy ^0.19.
- Technique: Motion Canvas/Manim-style framework. Scenes are plain Rust: relative actions on field paths with
  eases, composed with `ord_chain` and similar, then compiled into a timeline that can seek to any frame in
  either direction without re-simulating. It also has a visual editor (Moxie) and `velyst_motiongfx` for Typst text.
- Golden: **yes**. Seeking is a pure function of time, the same model as Moonsplice's (t, state) systems.
- Eval: "Rebuild the ten-bar hero (bars grow one after another, then reverse) as a comp; judge rhythm by the
  stagger intervals and whether the reverse mirrors the forward pass frame for frame."

### Velyst
- Repo: https://github.com/voxell-tech/velyst
- License: MIT OR Apache-2.0. Bevy: 0.0.1 (2026-09-28) needs bevy ^0.19.
- Technique: renders Typst documents through Vello inside Bevy, with interactive Typst functions as content.
- Golden: yes for static Typst layouts (vector output, no time dependence).
- Eval: "Typeset a title card with a formula and a caption; judge the typographic hierarchy (rule) and the
  baseline alignment between formula and caption (craft)."

### bevy_vello
- Repo: https://github.com/linebender/bevy_vello
- License: MIT OR Apache-2.0. Bevy: 0.14.0 (2026-08-21) needs bevy ^0.19.0.
- Technique: GPU compute 2D vector rendering (Vello) in Bevy world or UI space. It renders scenes, SVG, Lottie
  (via velato) and text (via parley). Examples include `lottie_player`, `svg`, `text` and a `headless` example.
- Golden: yes for SVG and scene examples. Lottie is deterministic if frame time is fixed.
- Eval: "Play a Lottie loader icon and a hand-built equivalent side by side; judge whether the eases match the
  Lottie's timing (rhythm)."

### Vello
- Repo: https://github.com/linebender/vello
- License: Apache-2.0 OR MIT. Not a Bevy crate (0.11.0, 2026-10-02).
- Technique: compute-centric 2D renderer, with CPU, GPU and hybrid sparse-strip backends.
- Golden: **yes**. `vello_tests/snapshots` is a corpus of reference images rendered per backend by the
  `#[vello_test]` macro.
- Eval: "Draw a filled-and-stroked badge; diff it against a CPU render of the same path to catch AA or
  stroke-join faults (craft)."

### bevy_prototype_lyon
- Repo: https://github.com/rparrett/bevy_prototype_lyon (formerly Nilirad)
- License: MIT OR Apache-2.0. Bevy: 0.17.0 (2026-06-22) needs bevy ^0.19.0.
- Technique: tessellates 2D paths (fills, strokes, Béziers) into meshes with lyon.
- Golden: yes. The output is static meshes.
- Eval: "Animate a path drawing itself on (trim 0 to 1) around a logo; judge whether the stroke's leading end
  moves with a constant visual speed (rhythm)."

### lyon
- Repo: https://github.com/nical/lyon
- License: MIT OR Apache-2.0 (crate; GitHub reports NOASSERTION). Not Bevy-specific (1.0.19).
- Technique: path tessellation, flattening and geometry math. It underlies bevy_prototype_lyon.
- Golden: yes. Tessellation is CPU-side and deterministic.
- Eval: "Morph a circle into a star with matched vertex counts; judge whether the in-between frames stay convex
  and readable (craft)."

### bevy_vector_shapes
- Repo: https://github.com/james-j-obrien/bevy_vector_shapes
- License: MIT OR Apache-2.0 (crate). Bevy: 0.13.1 (2026-07-09) needs bevy ^0.19.
- Technique: immediate-mode and retained SDF-style lines, discs, arcs, rects and polygons with thickness and
  caps, in 2D or 3D.
- Golden: yes.
- Eval: "Build a radial progress dial whose arc eases to 72%; judge the arc end cap against the tick marks
  (relationship)."

### bevy_smud
- Repo: https://github.com/johanhelsing/bevy_smud
- License: MIT OR Apache-2.0 (crate). Bevy: 0.14.0 (2026-06-19) needs bevy ^0.19.
- Technique: 2D shapes as signed distance functions written in WGSL, plus fill functions (outline, glow).
- Golden: yes.
- Eval: "Make a blob logo that smooth-unions two circles as they pass; judge whether the merge reads as one
  gesture (memorability)."

### bevy_alight_motion
- Repo: https://github.com/Bli-AIk/bevy_alight_motion
- License: MIT OR Apache-2.0. Bevy: 0.5.1 (2026-07-01) needs bevy ^0.18 (not yet 0.19).
- Technique: loads and plays Alight Motion (mobile motion-design app) project files in Bevy.
- Golden: probably, given fixed time (unverified).
- Eval: "Import an exported project and reproduce one layer as rows; judge keyframe timing against the source."

### Typography and text animation

#### cosmic-text
- Repo: https://github.com/pop-os/cosmic-text
- License: MIT OR Apache-2.0. Not a Bevy crate (0.19.0). Note that Bevy's own `bevy_text` on main now uses
  parley (seen in `parley_context` in `crates/bevy_text/src/lib.rs`); which text stack 0.19.1 ships is unverified.
- Technique: shaping, layout, font fallback and rasterization of multi-line text.
- Golden: yes. Layout is deterministic for a fixed font file.
- Eval: "Set a two-line headline with tight leading; judge the line spacing and rag (craft)."

#### bevy_pretty_text
- Repo: https://github.com/void-scape/pretty-text
- License: MIT OR Apache-2.0. Bevy: 0.4.1 (2026-02-11) needs bevy ^0.18 (not yet 0.19).
- Technique: per-glyph text effects (wave, shake and others) and a typewriter reveal, written inline.
- Golden: only with fixed time. Shake effects may use randomness (unverified).
- Eval: "Reveal a subtitle with a typewriter at 30 chars/s while one word waves; judge whether the effect
  points at the key word (relationship), not decoration."

#### bevy_text_animation
- Repo: https://github.com/ffunatsu/bevy_text_animation (crate repository field says funatsufumiya)
- License: WTFPL OR 0BSD (crate; GitHub reports 0BSD). Bevy: 0.7.0 (2026-09-14) needs bevy ^0.19.
- Technique: typewriter-style text animation for Text2d and UI.
- Golden: yes with fixed time.
- Eval: "Type a three-line kicker so each line lands on a beat; judge rhythm against a 120 BPM grid."

#### Bevy built-in text examples
- Repo: https://github.com/bevyengine/bevy/tree/main/examples/ui/text and `examples/2d/text2d.rs`
- License: MIT OR Apache-2.0 (code); FiraMono is SIL OFL 1.1 (CREDITS.md).
- Technique: `letter_spacing`, `font_weights`, `font_variations`, `strikethrough_and_underline`,
  `text_background_colors`. The `text2d` example shows anchors and justification.
- Golden: yes (static); `testbed_2d` captures a Text scene in CI.
- Eval: "Animate letter spacing from tight to airy on a title; judge whether the word stays centered (rule)."

---

## 2. Tweening, curves and springs

### bevy_tweening
- Repo: https://github.com/djeedai/bevy_tweening
- License: MIT OR Apache-2.0. Bevy: 0.16.0 (2026-06-28) needs bevy ^0.19.
- Technique: component and asset tweens with ease functions, sequences, delays, repeat and ping-pong modes.
- Golden: yes. Tweens are a function of elapsed time.
- Eval: "Chain move, then scale, then fade on a card with overlapping eases; judge whether the overlap reads as
  one motion or three (rhythm)."

### bevy_tween
- Repo: https://github.com/Multirious/bevy_tween
- License: MIT OR Apache-2.0. Bevy: 0.13.0 (2026-07-03) needs bevy ^0.19.0.
- Technique: an animator is an entity tree on `bevy_time_runner`, with time scaling, seeking, any interpolation
  curve and events fired at arbitrary times. It is the closest crate to a seekable timeline of rows.
- Golden: yes.
- Eval: "Seek the same comp to t = 0.5 s forwards and backwards; the frames must be identical (consistency check)."

### bevy_easings
- Repo: https://github.com/vleue/bevy_easings
- License: MIT OR Apache-2.0 (crate; GitHub detects none). Bevy: 0.19.0 (2026-06-24) needs bevy ^0.19.0.
- Technique: `Transform` and `Sprite` easing chains, using the `interpolation` crate's ease functions.
- Golden: yes.
- Eval: "Bounce a ball in with ease-out-bounce; judge whether the last bounce height is under a fifth of the
  first (craft)."

### bevy_lookup_curve
- Repo: https://github.com/villor/bevy_lookup_curve
- License: MIT OR Apache-2.0. Bevy: 0.12.0 (2026-06-27) needs bevy ^0.19.
- Technique: editable lookup curves (an egui editor and asset), like Unity's AnimationCurve.
- Golden: yes.
- Eval: "Author an anticipation-overshoot curve and apply it to a logo pop; judge the anticipation dip at
  10 to 15% of duration (craft)."

### bevy_animation_graph
- Repo: https://github.com/mbrea-c/bevy_animation_graph
- License: MIT OR Apache-2.0. Bevy: 0.11.0 (2026-07-11) needs bevy ^0.19.
- Technique: a node-graph animation system with an editor: blends, state machines and IK.
- Golden: yes with fixed time.
- Eval: "Blend a walk cycle into a run over 0.4 s; judge foot sliding on the contact sheet (craft)."

### Bevy animation and curves (built in)
- Repo: https://github.com/bevyengine/bevy/tree/main/examples/animation
- License: code MIT OR Apache-2.0. The Fox model is CC0 for the mesh and CC-BY 4.0 for rigging and
  animation (CREDITS.md).
- Technique: `easing_functions.rs` (a grid of every `EaseFunction`), `eased_motion.rs` (`EasingCurve` on a
  transform), `animated_transform.rs` (AnimationClip curves), `animation_graph.rs` (blend weights),
  `animation_masks.rs`, `color_animation.rs` (curves in color spaces), `animated_ui.rs`, `morph_targets.rs`.
  `examples/math/cubic_splines.rs` covers Bézier, Hermite, Cardinal and B-spline curves.
- Golden: **yes**. `easing_functions` is a static plot of each ease, and `color_animation` is deterministic at fixed t.
- Eval: "For each ease used in a comp, match its sampled curve against Bevy's `EaseFunction` of the same name;
  the error must be under 1e-3 (rule)."

### Springs
- **animato** (https://github.com/AarambhDevHub/animato): MIT OR Apache-2.0. It has spring, tween, timeline and
  stagger crates; `animato-bevy` 1.7.2 needs bevy_app/bevy_ecs ^0.18.1 (not 0.19). Golden: yes if springs are
  integrated with a fixed step (unverified).
- **springy** (https://github.com/aceeri/springy): MIT OR Apache-2.0, stable springs. Its last crate (0.2.0,
  2024) needs bevy ^0.14, so it is stale.
- **Built in**: Bevy's `StableInterpolate::smooth_nudge` (exponential decay toward a target) is used in the
  camera examples. A critically damped spring is easy to write as a pure function of t.
- Eval: "Drop a card with a spring (zeta 0.5, then 1.0); judge whether the overshoot count matches the damping
  ratio, and whether the underdamped version adds energy without jitter (rhythm)."

---

## 3. VFX and particles

### bevy_hanabi
- Repo: https://github.com/djeedai/bevy_hanabi
- License: MIT OR Apache-2.0. Bevy: 0.19.0 (2026-06-27) needs bevy ^0.19. Main tracks Bevy 0.19.
- Technique: GPU compute particles with an expression graph for attributes, and built-in trails and ribbons
  (`ribbon.rs`: emitters on Lissajous and spirograph curves, `Attribute::RIBBON_ID`). Other examples include
  `firework`, `portal`, `lightning`, `worms`, `force_field` and `gradient`. Each example has a `.txt` description.
- Golden: **partly**. `EffectAsset::prng_seed` and `ParticleEffect::prng_seed` fix the RNG (src/asset.rs).
  With a fixed frame time, frames should repeat on one GPU; across GPUs they will not be bit-exact (unverified).
- Eval: "Make a firework that bursts on a beat; judge the shape of the burst at peak (radial symmetry) and
  whether the trails fade before the next burst (rhythm)."

### bevy_enoki
- Repo: https://github.com/Lommix/bevy_enoki
- License: MIT. Bevy: 0.7.0 (2026-06-22) needs bevy_app/bevy_ecs/bevy_render ^0.19.
- Technique: 2D CPU particles with custom material traits, built for WebGL2 and mobile. It has a hot-reloadable
  particle-effect asset format.
- Golden: only with a fixed seed and step (whether a seed is exposed is unverified).
- Eval: "Make a hit spark that sells impact in six frames; judge whether the contact sheet's first frame is the
  brightest (craft)."

### bevy_firework
- Repo: https://github.com/mbrea-c/bevy_firework
- License: MIT OR Apache-2.0. Bevy: 0.10.0 (2026-07-08) needs bevy ^0.19.
- Technique: CPU-simulated, batch-rendered particles with PBR materials and collisions.
- Golden: with a fixed step (seeding unverified).
- Eval: "Dust puffs on landing; judge whether the dust settles on the ground plane rather than floating (rule)."

### berdicles
- Repo: https://github.com/mintlu8/berdicles
- License: MIT OR Apache-2.0. Bevy: 0.3.0 needs bevy 0.15 (stale).
- Technique: an expressive CPU particle system with trail support.
- Golden: unverified.
- Eval: technique reference only.

### bevy_particle_systems
- Repo: https://github.com/abnormalbrain/bevy_particle_systems
- License: MIT. Bevy: 0.13.0 (2024) needs bevy ^0.14 (stale).
- Technique: CPU particles with WASM support and curves over particle lifetime.
- Golden: unverified. Reference only.

### bevy_polyline
- Repo: https://github.com/fslabs/bevy_polyline (ForesightMiningSoftwareCorporation)
- License: MIT OR Apache-2.0. Bevy: 0.14.1 (2026-10-02) needs bevy ^0.18 (0.19 port not yet published).
- Technique: instanced thick polylines in 3D. Useful for trails, orbit paths and motion lines.
- Golden: yes.
- Eval: "Draw the path of a moving object as a trail that thins with age; judge whether the trail leads the eye
  to the object (relationship)."

### Decals
- **Bevy built-in**: `examples/3d/decal.rs` (forward decals), `clustered_decals.rs` and `clustered_decal_maps.rs`.
  Code is MIT OR Apache-2.0. Golden: yes (static).
- **bevy_contact_projective_decals** (https://github.com/naasblod/bevy_contact_projective_decals): GitHub
  detects Apache-2.0; the Cargo.toml has no license field (unverified). It needs bevy 0.16 and was last pushed
  2025-04, so it is likely superseded by the built-in decals.
- Eval: "Put a scorch decal under an explosion; judge whether it conforms to the ground and does not float
  (craft)."

### bevy-vfx-bag
- Repo: https://github.com/torsteingrindvik/bevy-vfx-bag
- License: MIT OR Apache-2.0. Bevy: 0.2.0 needs bevy ^0.10 (stale).
- Technique: a bag of post effects (LUT, chromatic aberration, wave, flip, pixelate, raindrops). A technique
  reference only.

---

