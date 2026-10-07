# Bevy look references: water, sky, post, camera, generative, goldens

The second half of motion.md (split to stay under 400 lines); how it was verified is there.

## 4. Water, ocean, sky and atmosphere

### bevy_water
- Repo: https://github.com/Neopallium/bevy_water
- License: MIT OR Apache-2.0 (crate; GitHub detects none). The pirates example's ship is from Poly Haven (CC0).
  Bevy: 0.18.1 (2026-02-02) needs bevy ^0.18 (no 0.19 release yet).
- Technique: a tileable water material with vertex-displaced waves, normals from height, and
  `get_wave_point` so objects can bob on the surface.
- Golden: yes. Waves are a function of time.
- Eval: "Float a buoy so it rides the swell with a lag; judge whether its pitch follows the wave slope
  (relationship)."

### bevy-aqua
- Repo: https://github.com/sayhisam1/bevy-aqua
- License: MIT OR Apache-2.0. Bevy: 0.1.3 (2026-08-31) needs bevy ^0.19.
- Technique: camera-centered ocean with Gerstner and FFT waves (JONSWAP spectrum), Crest-style ring geometry,
  and GPU-sampled displacement probes.
- Golden: likely, given fixed time and seed (unverified).
- Eval: "Light the buoy so it reads at dusk; judge it by contrast against the sky and the water."

### bevy_fft
- Repo: https://github.com/mate-h/bevy_fft
- License: MIT. Bevy: 0.1.0 (2026-07-01) needs bevy ^0.19.0.
- Technique: GPU FFT for frequency-domain filtering and synthesis (ocean spectra, convolution bloom). Its author
  is also working on Bevy's atmosphere and volumetrics.
- Golden: yes as math; renders unverified.

### bevy_oceansim
- Repo: https://github.com/SolidStateDj/bevy_oceansim
- License: **GPL-3.0**. Bevy 0.12.1 (stale, experimental).
- Technique: Tessendorf FFT ocean in compute shaders. Use it only to read the technique; do not copy code.

### bevy_atmosphere
- Repo: https://github.com/JonahPlusPlus/bevy_atmosphere
- License: MIT OR Apache-2.0. Bevy: 0.13.0 (2025-05-06) needs bevy ^0.16 (stale; Bevy's own atmosphere replaces it).
- Technique: procedural sky models (Nishita, Gradient) rendered to a skybox cube by compute shaders.
- Golden: yes.

### Bevy built-in atmosphere and fog
- Repo: `examples/3d/atmosphere.rs`, `atmospheric_fog.rs`, `fog.rs`, `fog_volumes.rs`, `volumetric_fog.rs`,
  `scrolling_fog.rs`, `skybox.rs`, `auto_exposure.rs`. Code is MIT OR Apache-2.0. Environment maps are from
  HDRI Haven (CC0).
- Technique: physically based atmosphere (Hillaire-style LUTs and scattering media), distance and height fog,
  and raymarched fog volumes with light shafts.
- Golden: atmosphere with a fixed sun is yes. Volumetric fog is jittered and `auto_exposure` adapts over time,
  so they need many frames or a fixed frame count (Bevy issue #17895 notes that FogVolume does not jitter samples
  and bands; behavior in 0.19.1 is unverified).
- Eval: "Set the sun to 2 degrees above the horizon; judge whether the sky gradient runs warm at the horizon to
  cool at the zenith, and whether the scene's key light matches it (relationship)."

### bevy-volumetric-clouds
- Repo: https://github.com/evroon/bevy-volumetric-clouds
- License: MIT. Bevy: crate 0.2.0 needs bevy ^0.18; the default branch's Cargo.toml is on bevy 0.19.0
  (pushed 2026-08-24, unreleased). A 0.19 fork exists at whatthexampp/bevy-volumetric-clouds-019.
- Technique: Horizon Zero Dawn-style raymarched clouds on a skybox. It does not yet integrate with Bevy's atmosphere.
- Golden: yes with fixed time and fixed noise.
- Eval: "Frame a title against clouds; judge whether the title sits over a low-detail cloud region (rule: the
  figure needs a quiet ground)."

### bevy_sky_gradient
- Repo: https://github.com/TanTanDev/bevy_sky_gradient
- License: MIT or Apache-2.0 (crate). Bevy: 0.4.0 (2026-08-09) needs bevy ^0.19.
- Technique: a stylized sky gradient with aurora and stars, and a day/night cycle.
- Golden: yes at fixed time of day.
- Eval: "Cut between noon and dusk with the gradient; judge whether the palette shift carries the mood without
  a jump in exposure (craft)."

### bevy_starfield
- Repo: https://github.com/fintelia/bevy_starfield. License: MIT OR Apache-2.0. Bevy ^0.10.1 (stale).
- Technique: a procedural night sky. Reference only.

---

## 5. Post-processing and look

### Bevy built-in post stack
- Repo: `examples/3d/bloom_3d.rs`, `2d/bloom_2d.rs`, `tonemapping.rs`, `depth_of_field.rs`, `motion_blur.rs`,
  `ssao.rs`, `ssr.rs`, `color_grading.rs`, `post_processing.rs` (chromatic aberration), `anti_aliasing.rs`
  (FXAA, SMAA, TAA, CAS), `auto_exposure.rs`, `transmission.rs`, `order_independent_transparency.rs`, `solari.rs`
  (ray-traced lighting). The custom pass is in `shader_advanced/custom_post_processing.rs`.
- License: MIT OR Apache-2.0 (code); assets per CREDITS.md.
- Technique: HDR bloom (energy-conserving and additive), tonemappers (AgX, TonyMcMapface, ACES and others), Bokeh
  and Gaussian DOF, per-object motion blur, GTAO, color grading (exposure, temperature, tint, shadows, midtones
  and highlights).
- Golden: bloom, tonemapping, color grading and DOF give **yes** at a static frame. Motion blur needs motion
  between frames, so it is deterministic only with a fixed step. TAA and SSAO noise converge over frames.
- Eval: "Grade the same comp three ways (cool thriller, warm nostalgia, neutral); judge whether the grade alone
  changes the read while key contrast is kept (memorability)."

### bevy_mod_outline
- Repo: https://github.com/komadori/bevy_mod_outline
- License: MIT OR Apache-2.0. Bevy: 0.13.0 (2026-07-09) needs bevy ^0.19.0.
- Technique: mesh outlines by vertex extrusion (a jump-flood mode is unverified). Examples include `shapes`, `animated_fox`,
  `flying_objects`, `hollow` and `ui_aa`.
- Golden: yes (static examples).
- Eval: "Outline the hero object only; judge whether its outline weight is distinct from background weights
  (rule: one emphasis)."

### bevy_mesh_outline
- Repo: https://github.com/gylleus/bevy_mesh_outline
- License: MIT OR Apache-2.0 (crate). Bevy: 0.4.2 (2026-10-05) needs bevy ^0.19.0.
- Technique: 3D mesh outlines. Golden: yes.

### bevy_edge_detection_outline
- Repo: https://github.com/Mediocre-AI/bevy_edge_detection_outline
- License: MIT OR Apache-2.0 (crate). Bevy: 0.4.1 (2026-07-12) needs bevy ^0.19.
- Technique: post-process outlines from depth, normals and/or color (Sobel, Roberts and others).
- Golden: yes.
- Eval: "Make a line-art look for a product turntable; judge whether silhouette lines are heavier than interior
  creases (craft)."

### Toon shaders
- **bevy_toon_shader** (https://github.com/tbillington/bevy_toon_shader): MIT OR Apache-2.0. Crate 0.3.0 needs
  bevy 0.12; the branch is on 0.14 (stale). A banded-diffuse cel material.
- **bevy_wind_waker_shader** (https://github.com/janhohenheim/bevy_wind_waker_shader): MIT OR Apache-2.0,
  0.6.0 needs bevy ^0.18. A Wind Waker-style character toon.
- Golden: yes (static lighting).
- Eval: "Light a character with two cel bands; judge whether the terminator falls where it defines the form
  (craft)."

### rust-adventure/bevy-examples and bevy_shader_utils
- Repo: https://github.com/rust-adventure/bevy-examples
- License: crate `bevy_shader_utils` is MIT (0.11.0 needs bevy ^0.19.0); the workspace declares MIT OR Apache-2.0;
  GitHub detects MIT. Workspace examples are on bevy 0.18.
- Technique: shader cookbook covering dissolve (custom prepass), fresnel, vertex-wave cubes, Sobel edge
  detection from a custom render phase with artist vertex colors, and noise helpers in WGSL.
- Golden: yes for most demos at fixed time.
- Eval: "Dissolve a logo out with a noise edge glow; judge whether the glow edge stays one consistent width
  (craft)."

---

## 6. Camera

### bevy_dolly (and dolly)
- Repo: https://github.com/BlackPhlox/bevy_dolly. Upstream: https://github.com/h3r2tic/dolly
- License: MIT OR Apache-2.0 (both). Bevy: 0.0.5 (2024-12-21) needs bevy ^0.15; last push 2025-05 (stale for 0.19).
- Technique: composable camera rigs (Position, YawPitch, Smooth, Arm, LookAt) with exponential smoothing.
  A good model for camera-as-rows.
- Golden: yes. Rigs are deterministic for a fixed dt.
- Eval: "Dolly in on a subject with an Arm rig; judge whether the subject stays on a third line throughout
  (rule)."

### bevy_trauma_shake
- Repo: https://github.com/johanhelsing/bevy_trauma_shake
- License: MIT OR Apache-2.0. Bevy: 0.8.0 (2026-06-20) needs bevy ^0.19.
- Technique: trauma-based shake for 2D cameras: trauma decays over time and drives noise offsets (the
  trauma-squared and noise details follow the common GDC 'juice' formulation; unverified against the source).
- Golden: yes. Noise is deterministic given time.
- Eval: "Shake on impact for 0.3 s; judge whether the frame-to-frame displacement decays (rhythm) and whether
  the title stays legible (rule)."

### bevy_camera_shake
- Repo: https://github.com/Andrewp2/bevy_camera_shake. License: MIT OR Apache-2.0. 7.0.0 needs bevy ^0.16.
- Technique: 2D and 3D camera shake. Reference only.

### bevy_panorbit_camera
- Repo: https://github.com/Plonq/bevy_panorbit_camera
- License: MIT OR Apache-2.0. Bevy: 0.35.1 (2026-09-05) needs bevy ^0.19.
- Technique: pan and orbit with smoothing; targets can be set programmatically for an orbit turntable.
- Golden: yes for scripted orbits.
- Eval: "Do a 3-second 90 degree turntable; judge whether angular speed eases in and out (rhythm)."

### smooth-bevy-cameras
- Repo: https://github.com/bonsairobo/smooth-bevy-cameras
- License: MIT. Bevy: crate 0.14.0 needs bevy ^0.16; the branch is at 0.15.0 (stale for 0.19).
- Technique: exponentially smoothed orbit, FPS and unreal-style controllers.

### Bevy built-in camera examples
- Repo: `examples/camera/2d_screen_shake.rs`, `2d_top_down_camera.rs` (smooth follow with `smooth_nudge`),
  `camera_orbit.rs`, `pan_orbit_camera_*`, `projection_zoom.rs`, `first_person_view_model.rs`. MIT OR Apache-2.0.
- Golden: yes with fixed time.
- Eval: "Follow a player with a lag of about 150 ms; judge whether the camera settles without overshoot when
  the player stops (craft)."

---

## 7. Procedural, generative and creative coding

### nannou
- Repo: https://github.com/nannou-org/nannou
- License: MIT OR Apache-2.0 (crate; GitHub detects none). Bevy: nannou 0.20.0 (2026-06-22) needs bevy ^0.19.0.
  It has been rebuilt on Bevy.
- Technique: a creative-coding framework (Processing/openFrameworks-like) with a draw API and many generative
  sketches in its examples.
- Golden: yes for seeded sketches at fixed frame.
- Eval: "Port a nannou flow-field sketch to a comp; judge whether the density gradient leads to the focal
  point (relationship)."

### bevy_generative
- Repo: https://github.com/manankarnik/bevy_generative
- License: MIT OR Apache-2.0. Bevy: 0.4.0 (2025-10-08) needs bevy ^0.16.1 (stale for 0.19).
- Technique: noise maps, textures, terrain and planets generated in real time with gradients.
- Golden: yes with a seed.
- Eval: "Generate a planet for a title card; judge whether its terminator and rim light separate it from space
  (craft)."

### noisy_bevy and noiz
- **noisy_bevy** (https://github.com/johanhelsing/noisy_bevy): MIT (crate). 0.14.0 needs bevy ^0.19. Simplex
  and fBm noise with matching CPU (Rust) and GPU (WGSL) functions.
- **noiz** (https://github.com/ElliottjPierce/noiz): MIT OR Apache-2.0. 0.5.0 needs bevy ^0.19. Configurable
  noise built on Bevy math.
- Golden: yes (pure functions).
- Eval: "Drift a background with 3-octave fBm; judge whether motion stays below the threshold that competes
  with foreground text (rule)."

### bevy_symbios_texture
- Repo: https://github.com/TheJanusStream/bevy_symbios_texture
- License: MIT. Bevy: 0.12.0 (2026-09-09) needs bevy ^0.19.
- Technique: algorithmic texture generation (bark, rock, tiles and so on).
- Golden: yes with a seed (unverified).

### bevy-procedural/meshes
- Repo: https://github.com/bevy-procedural/meshes (org: https://github.com/bevy-procedural)
- License: GitHub detects Apache-2.0; the crate license is unverified. Bevy version unverified.
- Technique: a procedural mesh builder (half-edge, extrude, loft). Related repos cover modelling, vegetation
  and render-to-texture.
- Golden: yes (CPU geometry).

### bevy_gaussian_splatting
- Repo: https://github.com/mosure/bevy_gaussian_splatting
- License: MIT OR Apache-2.0. Bevy: 8.0.2 (2026-08-31) needs bevy ^0.19.0.
- Technique: 3D and 4D Gaussian splat rendering with GPU sorting.
- Golden: mostly yes. Sort order on the GPU may cause small differences (unverified).
- Eval: "Composite a splat scan behind a vector title; judge depth separation (relationship)."

### 2D lighting
- **bevy_light_2d** (https://github.com/jgayfer/bevy_light_2d): MIT. 0.10.0 (2026-09-16) needs bevy ^0.19.
  Point lights and occluders in 2D.
- **bevy-magic-light-2d** (https://github.com/zaycev/bevy-magic-light-2d): GitHub detects Apache-2.0; crates.io
  says "non-standard" (unverified). The branch is on bevy 0.17. Raymarched 2D global illumination.
- Golden: bevy_light_2d yes; magic-light is temporally accumulated, so unverified.
- Eval: "Light a 2D night scene with one lantern; judge whether the brightest pixel is on the subject (rule)."

### bevy_infinite_grid
- Repo: https://github.com/ForesightMiningSoftwareCorporation/bevy_infinite_grid
- License: MIT OR Apache-2.0. Bevy: 0.18.0 needs bevy ^0.18.
- Technique: an anti-aliased infinite ground grid with distance fade. Useful as a technical-look backdrop.
- Golden: yes.

### Bevy built-in generative and shader examples
- Repo: `examples/shader/compute_shader_game_of_life.rs`, `animate_shader.rs`, `shader_material_2d.rs`,
  `shader_advanced/deferred_raymarch.rs`, `compute_mesh.rs`, `examples/3d/generate_custom_mesh.rs`,
  `examples/math/random_sampling.rs`, `render_primitives.rs`.
- License: MIT OR Apache-2.0.
- Golden: `render_primitives` and `generate_custom_mesh` yes. Game of life is random-seeded (unverified).
- Eval: "Make a looping shader background that is seamless at t = period; judge the first and last frames for
  a pixel match."

### Unverified or weaker leads (not counted above)
- `bevy-open-world` (evroon): GPL-3.0, open-world rendering crates.
- `bevy_weather` (etwodev): day/night and weather; license and Bevy version unverified.
- `bevy_compute_noise`: bevy 0.15, stale.
- `bevy_retro_shaders`, `bevy_crt`, `bevy_dither_post_process`: retro post effects; versions unverified.

---

## 8. Bevy's own goldens: example showcase and testbed

- **Testbed** (https://github.com/bevyengine/bevy/tree/main/examples/testbed): `2d.rs` cycles Shapes, Bloom,
  Text, Sprite, SpriteSlicing, Gizmos, TextureAtlasBuilder and ColorConsistency. `3d.rs` cycles Light, Bloom,
  Gltf, Animation, Gizmos, GltfCoordinateConversion, WhiteFurnaceSolidColorLight,
  WhiteFurnaceEnvironmentMapLight and RenderLayers. `ui.rs` and `full_ui.rs` cover UI.
  `helpers.rs::switch_scene_in_ci` takes a `NamedScreenshot` 100 frames after each scene change, then exits
  once every scene has been visited.
- **CI** (`.github/workflows/example-run.yml`): runs each `.github/example-run/*.ron` with
  `CI_TESTING_CONFIG=<file> cargo run --example <name> --features "bevy_ci_testing,..."` on macOS Metal and
  Linux Vulkan (under xvfb), collects `screenshot-*.png`, and sends them to Pixel Eagle
  (`send-screenshots-to-pixeleagle.yml`) for comparison against main. Pushes to main update the references.
- **CiTestingConfig** (`crates/bevy_dev_tools/src/ci_testing/config.rs`): `setup.fixed_frame_time` sets
  `TimeUpdateStrategy::ManualDuration`. The events are `(frame, Screenshot | ScreenshotAndExit |
  NamedScreenshot(name) | AppExit | StartScreenRecording | StopScreenRecording | MoveCamera{..} | Custom(..))`.
  The variant names come from the doc comments; check the exact RON spelling before use.
- **Example showcase** (`tools/example-showcase`): builds every example for bevy.org/examples (WebGL2 and
  WebGPU) and screenshots them, with patches that fix window position and size and disable audio. The images
  on bevy.org/examples are its output.
- Note: the ui/text and color_consistency scenes are the closest thing in Bevy to a text-rendering and
  color-pipeline golden.

---

## Golden candidates

The ten best sources of deterministic reference renders, and how to capture each. Capture each on the same
GPU and backend as Moonsplice's renderer, store per platform, and compare with a perceptual tolerance
(for example FLIP or SSIM), not bit equality.

1. **Bevy `testbed_2d`** (Shapes, Bloom, Text, Sprite, Gizmos, ColorConsistency).
   Capture: in a Bevy v0.19.1 checkout, run
   `CI_TESTING_CONFIG=.github/example-run/testbed_2d.ron cargo run --example testbed_2d --features bevy_ci_testing`.
   The PNGs are `screenshot-<Scene>.png`. Pixel Eagle holds the upstream reference runs.
2. **Bevy `testbed_3d`** (Light, Bloom, Gltf, Animation, white-furnace energy tests). Capture the same way.
   The white-furnace scenes are a physically meaningful check: a correct render is uniform.
3. **Bevy `animation/easing_functions`**: a static plot of every `EaseFunction`. Capture with a config of
   `fixed_frame_time: Some(0.0166667)` and `(10, ScreenshotAndExit)`. Use it to check the agent's eases
   numerically as well as visually.
4. **Bevy `3d/tonemapping` and `3d/color_grading`**: one capture per tonemapper and grading preset.
   Drive the selection with `Custom` events or small forks, using a fixed frame time, screenshot at frame 60.
   These are references for the "look" axis.
5. **Bevy `3d/atmosphere`** at fixed sun elevations (dawn, noon, dusk): a fixed frame time and a screenshot after
   LUTs settle (about 30 frames). This is the sky reference for buoy-at-dusk evals.
6. **bevy_motiongfx examples**: the timeline seeks to exact times without re-simulating. Capture a contact
   sheet by seeking to t = 0, 0.25 ... 1.0 of each sequence and screenshotting. This gives a golden contact
   sheet in the same form the critic judges.
7. **Vello `vello_tests/snapshots`**: checked-in reference PNGs for 2D vector rendering (fills, strokes,
   gradients, clips), generated by `#[vello_test]` per backend. Use them directly to verify vector craft
   (AA and stroke joins).
8. **bevy_vello `headless`, `svg` and `lottie` examples**: render a fixed SVG or Lottie frame headless at a
   set resolution. The Lottie at fixed frame numbers gives a motion-design golden with an external authoring
   source.
9. **bevy_hanabi examples** (`ribbon`, `firework`, `portal`): set `prng_seed` on the effect plus a fixed
   frame time, then screenshot at fixed frames. Expect per-GPU differences and use a looser tolerance.
   This is the VFX reference.
10. **bevy_mod_outline `shapes` and Bevy `3d/bloom_3d` / `2d/bloom_2d`**: static scenes for outline weight and
    bloom falloff. Capture with a fixed frame time and a screenshot at frame 30.

Runner-up: `bevy_water` at fixed t (wave displacement is a function of time), `bevy_trauma_shake` (noise
deterministic in t), and `examples/math/cubic_splines`.
