# Open-source Bevy games: reference library for Moonsplice

Compiled 2026-10-06. Current Bevy is 0.19.1 (released 2026-08-13; 0.20.0-rc.2 is out).

**How each field was verified.** Licenses come from the GitHub license API, then the LICENSE file and the README when the
API returned NOASSERTION or nothing. Asset licenses come from the README, CREDITS or LICENSE text. Bevy versions come
from `Cargo.toml` at HEAD, including workspace and sub-crate manifests. "Upd 25-26" means the last push to the default
branch was on or after 2025-01-01; a push can be only a dependency bump. Sources were the bevy-assets `Apps/Games`
list (98 entries), the itch.io results pages for Bevy Jams 1 to 7, and GitHub topic searches. No code was downloaded
or run.

**Legend.**
- *Code / assets*: **none** means no license file and no license statement, so all rights are reserved by default;
  treat the project as inspiration only. "assets: not stated" means no separate asset license was found, so do not
  reuse the assets without asking.
- *2D/3D*: taken from the README or description; "?" means it was not verified.
- *Notable* summarizes the README or description. Nothing in it comes from playing the game.

Repos looked at and rejected: `fishfolk/drifty` and `CoCoSol007/beats-into-shapes` are Godot projects, and
`kuviman/extremely-extreme-sports` uses the geng engine. **Tiny Glade** is commercial and has no public source (it
uses Bevy's ECS with a custom Vulkan renderer). **Unbox** is unverified: no Bevy game by that name was found.

---

## 1. Racing, driving, flight

| Name | Repo | Play | Code / assets license | Bevy | Upd 25-26 | 2D/3D | Notable | Eval idea |
|---|---|---|---|---|---|---|---|---|
| Combine Racers (Bevy Jam #2) | https://github.com/rparrett/combine-racers | https://euclidean-whale.itch.io/combine-racers | MIT/Apache-2.0 (LICENSE) / author says all assets are original, with a commissioned track and an OFL font, but gives no explicit asset license | 0.14 | no (2024-08) | 2.5D | Side-scrolling trick racer where varied tricks give speed boosts; online leaderboard | "A trick that boosts speed lands with a burst and a speed-line streak readable on the contact sheet" |
| Bevy Kart | https://github.com/Sigma-dev/bevy_kart | none | **none** (no LICENSE) | **0.19** | yes (2026-09) | 2D top-down | Kart racer with 3 laps, item pickups, a built-in track editor and WebRTC rollback netcode; native and browser | "Gate/checkpoint pass lands with a flash and a lap counter tick" |
| Postman's Speed Race (BJ #5) | https://github.com/Instelce/postman-speed-race | https://instelce.itch.io/postman-speed-race | MIT/Apache-2.0 (LICENSE-MIT, LICENSE-Apache-2.0) / `credits` file present, asset license not stated | 0.14 | no (2024-07) | ? | Bicycle courier dodges obstacles and throws letters while riding | "A throw that hits a mailbox at speed reads clearly: arc, impact, score pop" |
| Road on Road (BJ #5) | https://github.com/didibear/road-on-road | https://didibear.itch.io/road-on-road | README: MIT or Apache-2.0 / **assets CC BY 4.0** (no LICENSE file) | 0.14 | no (2024-10) | ? | Each trip has to avoid the ghost replays of your earlier trips | "Ghost replays of earlier runs are a pure function of t and stay legible when several overlap" |
| Drone Agility Challenge | https://github.com/Samuel-Bowden/drone-agility-challenge | releases on GitHub | Apache-2.0 / assets not stated | 0.10.1 | no (2024-06) | ? | Thruster-driven drone flies from a red podium to a green one without collisions | "Thruster flame scales with thrust; a near-miss gives a camera nudge" |
| Bevy Tanks | https://github.com/LioQing/bevy-tanks | https://lio-qing.itch.io/bevy-tanks | **none** | 0.15 | yes (2025-05) | 3D | Simple 3D tank game | "Turret recoil plus muzzle flash plus a dust puff on every shot" |
| limbo pass | https://github.com/shnewto/limbo_pass | https://limbopass.drinkspiller.com/ | MIT / assets (Blender scene, OP-1 music) are in the repo, but the README does not license them separately | 0.17 | yes (2025-12) | 3D | glTF Blender terrain; a ghost follows the terrain surface; smooth-bevy-cameras and rapier3d | "Camera follow over uneven terrain without jitter across 60 frames" |
| Ace of the Heavens | https://github.com/PraxTube/ace-of-the-heavens | https://rancic.itch.io/ace-of-the-heavens | MIT (applies to anything not licensed elsewhere) / third-party assets listed in CREDITS.md | 0.11.2 | no (2024-01) | 2D top-down | Fast 1v1 online plane dogfight | "A bullet hit on a plane flashes white for one frame and leaves a smoke trail" |

## 2. Boats, water, sea

| Name | Repo | Play | Code / assets license | Bevy | Upd 25-26 | 2D/3D | Notable | Eval idea |
|---|---|---|---|---|---|---|---|---|
| Pirate Sea Jam | https://github.com/claudijo/pirate-sea-jam | https://claudijo.itch.io/pirate-sea-jam | LICENSE is Bevy's MIT/Apache-2.0 text / assets not stated | 0.13.2 | no (2024-07) | 3D | Dynamic water waves, buoyancy, an infinite ocean, WebGPU ocean shaders, a sailing simulation, a third-person camera and cannons | "Add a wake that reads at speed; the hull rides the swell without clipping" |
| Shanty Quest: Treble at Sea (BJ #2, 3rd) | https://github.com/jabuwu/shanty-quest | https://jabuwu.itch.io/shanty-quest | README: MIT/Apache-2.0, "no attribution necessary" / **assets CC BY 3.0** | 0.11 | no (2023-07) | ? | Pirate game where you combine magical instruments; branches kept for each Bevy version | "Each instrument attack has its own readable shape and colour" |
| Sushi Boat (BJ #2) | https://github.com/didibear/sushi-boat | https://didibear.itch.io/sushi-boat | **conflict**: GitHub detects GPL-3.0, but README says MIT or Apache-2.0 / **assets CC BY 4.0** | 0.8 | no (2022) | ? | Item-combining game built around a sushi boat; a puzzle, not a boat sim | "A combine lands with a pop and a merge tween" |
| entities' repose / charon (BJ #4, 3rd) | https://github.com/eerii/charon | https://eerii.itch.io/charon | MIT/Apache-2.0 (LICENSE_MIT, LICENSE_APACHE) / assets not stated | 0.12 | no (2023-12) | 2D | Traffic management: you build river paths that carry spirits through the underworld | "Flow along a drawn river path stays smooth and its rate is readable" |
| lifecycler (BJ #5) | https://github.com/cxreiff/lifecycler | https://cxreiff.itch.io/lifecycler | MIT/Apache-2.0/CC0 license files / assets not stated | 0.16.0 | yes (2025-05) | 3D rendered to the terminal | Aquarium rendered to the terminal through bevy_ratatui_camera, with day and night modes | "Day-to-night transition holds palette contrast at low resolution" |
| Bevy-Boat-Sim | https://github.com/rhaskia/Bevy-Boat-Sim | none | **none** | 0.10.1 | no (2023) | ? | Small boat-sim experiment; the README is minimal (unverified) | "Boat yaw lags the steering input believably (rudder inertia)" |
| i sjön kan ingen höra dig skrika | https://gitlab.com/TheZoq2/i_sjon_kan_ingen_hora_dig_skrika | none | **unverified** (no license seen on GitLab page) | **unverified** | no (2020) | ? | "Swedish rowing boat pirate simulator", 4 commits | "Oar strokes leave paired ripples" |

## 3. Arcade, shmup, action (juice)

| Name | Repo | Play | Code / assets license | Bevy | Upd 25-26 | 2D/3D | Notable | Eval idea |
|---|---|---|---|---|---|---|---|---|
| Bevy showcase examples (breakout, alien_cake_addict, desk_toy, game_menu) + `camera/2d_screen_shake.rs`, `animation/eased_motion.rs`, `3d/motion_blur.rs` | https://github.com/bevyengine/bevy/tree/v0.19.1/examples | https://bevy.org/examples/ | MIT/Apache-2.0 / Bevy's own assets (CREDITS.md in repo) | **0.19.1 exactly** | yes | 2D and 3D | Canonical small games plus engine-blessed screen shake, easing and motion blur at Moonsplice's exact version | "Golden-render diff: rebuild breakout as a comp and match the official frame at t" |
| Kataster | https://github.com/BorisBoutillier/Kataster | none | MIT/Apache-2.0 / **Kenney Space Shooter Redux and smoke particle pack** (Kenney packs are CC0) | 0.17 | yes (2025-10) | 2D | Single-screen space shooter for beginners; smoke particles; bevy_remote | "Asteroid break spawns debris plus smoke that fades by frame N" |
| Thetawave | https://github.com/thetawavegame/thetawave | https://thetawave.metalmancy.tech | MIT / assets not in the repo (downloaded from release tarballs; license not stated) | 0.14.2 (workspace) | no (2024-12) | 2D | Physics-based roguelite vertical shooter with HUD bars and pickups | "Defense bar drains with an eased tween and flashes when it is low" |
| Super Kaizen Overloaded (BJ #1) | https://github.com/djeedai/super-kaizen-overloaded | none | MIT/Apache-2.0 (the LICENSE text names LibraCity by mistake) / assets not stated | 0.7 | no (2024-07) | 2D | Shmup by the author of bevy_hanabi (GPU particles) | "Enemy death emits a particle burst sized to the enemy" |
| Insta Kill | https://github.com/PraxTube/insta-kill | https://rancic.itch.io/insta-kill | MIT / third-party assets in CREDITS.md (author: "similar to CC0"); music from shononoki's bullet-hell pack | 0.12.1 | no (2024-06) | 2D | One-hit-kill arcade game with a self-hosted leaderboard | "Hit-stop: on a kill the frame holds 3 frames, then resumes" |
| Bevyroids | https://github.com/reu/bevyroids | https://reu.github.io/bevyroids/ | MIT / assets not stated | 0.11.3 | no (2024-03) | 2D | Asteroids clone with a web build | "Screen wraps without popping; thrust flame flickers" |
| Bullet Heaven (BJ #5) | https://github.com/robertdodd/bevy_jam_5 | https://robertdodd.itch.io/bevy-jam-5-reverse-bullet-hell | MIT/Apache-2.0/CC0 license files / assets not stated | 0.14 | no (2024-07) | ? | Cycles of enemy waves around a cyclical planet, with level-up upgrades | "A wave start is announced with a radial pulse" |
| A Fistful of Boomerangs (BJ #6, **1st**) | https://github.com/4D4XFUN/bevy-jam-6 | https://4d4xfun.itch.io/bevy-jam-6 | **none** / freesound sounds credited in README | 0.16.1 | yes (2025-06) | ? | Bevy Jam 6 winner; chain-reaction boomerangs | "A chain of ricochets stays readable as one causal line" |
| Live. Die. Repeat. (BJ #5, 2nd) | https://github.com/4D4XFUN/bevy-jam-5 | https://4d4xfun.itch.io/bevy-jam-5 | MIT/Apache-2.0/CC0 license files / CREDITS.md, asset license not stated | 0.14 | no (2024-07) | ? | Built from the Bevy Flock template | "Death-and-respawn loop has a clear rewind transition" |
| brkrs | https://github.com/cleder/brkrs | https://brkrs.readthedocs.io/ | AGPL-3.0 / assets not stated | 0.17.3 | yes (2026-10) | ? | Arkanoid/Breakout game with documentation; under active development | "A brick break shakes the screen with a decaying amplitude" |
| dodge_ball | https://github.com/LunaticDancer/dodge_ball | https://lunaticdancer.itch.io/dodge-ball | MIT / font credited | 0.17.2 | yes (2025-12) | 2D | Small bullet hell built with core plugins only | "Bullet density ramps over time and stays legible" |
| Zenith | https://github.com/selenebun/zenith (archived) | none | MIT / assets not stated | 0.5 | no (2021) | 2D | Space shmup; very old Bevy | "Starfield parallax at 3 depths" |
| Chain Reaction | https://github.com/sibevin/chain-reaction | https://sibevin.itch.io/chain-reaction | GPL-3.0 / fonts credited | 0.12.1 | no (2024-07) | 2D | Dodge particles that set off chain reactions | "A chain reaction propagates visibly, frame by frame" |
| Jump Jump | https://github.com/NightsWatchGames/jump-jump | https://nightswatchgames.github.io/games/jump-jump/ | MIT / assets not stated | 0.15 | no (2024-12) | 3D | WeChat jump game: jump animation, charge squash, **charge particles**, fall effect, **camera follow**, procedural platforms | "Charging squashes the character and the platform; landing pops a score" |
| Screen Ball | https://github.com/NightsWatchGames/screen-ball | none | MIT / assets not stated | 0.15 | no (2024-12) | ? | "Work and play" desktop ball game | "Ball bounces off the screen edges with a squash" |
| Battle City | https://github.com/NightsWatchGames/battle-city | https://nightswatchgames.github.io/games/battle-city/ | MIT / assets not stated | 0.15 | no (2024-12) | 2D | Tank classic built with rapier2d and LDtk levels | "Explosion sprite-sheet timing matches the impact frame" |
| Pacman | https://github.com/Warhorst/pacman | none | **none** / Press Start 2P font | 0.18 | yes (2026-05) | 2D | Arcade Pac-Man recreation | "Ghost frightened mode flashes before it ends" |
| Not Snake | https://github.com/ramirezmike/not_snake_game | https://ramirezmike2.itch.io/not-snake | MIT/Apache-2.0 / `credits` file | 0.7.0 | no (2022) | 3D | Snake where you are the food; 3D | "A 3D grid stays readable from a fixed camera" |
| ¿Quién es el MechaBurro? (BJ #1, 2nd) | https://github.com/ramirezmike/quien_es_el_mechaburro | https://ramirezmike2.itch.io/quien-es-el-mechaburro | MIT/Apache-2.0 / font credited | 0.11.2 | no (2023-09) | 3D | Twin-stick shooter with local multiplayer | "A hit bursts into confetti and the camera shakes a little" |
| USA Football League Scouting Combine XLV (BJ #2, **1st**) | https://github.com/ramirezmike/USA-Football-League-Scouting-Combine-XLV | https://ramirezmike2.itch.io/usa-football-league-scouting-combine-xlv | MIT/Apache-2.0 / assets not stated | 0.8.0 | no (2023-03) | ? | Bevy Jam 2 winner | "Event title cards slam in with a timing curve" |
| Flappy Bird (tutorial) | https://github.com/LiamGallagher737/bevy_flappy_bird | https://liamgallagher737.github.io/bevy_flappy_bird | **none** / assets zip offered in the README (sprites look like Flappy Bird's own; do not reuse) | 0.13 | no (2024-04) | 2D | Clean tutorial-sized flappy clone | "A pipe pass adds a point with a pop" |
| flappy_bevy | https://github.com/TanTanDev/flappy_bevy | none | MIT/Apache-2.0 / assets not stated | git rev (~0.5) | no (2021) | 2D | TanTan's flappy clone | "Parallax background stays seamless across a loop" |
| Typey Birb (BJ #1) | https://github.com/rparrett/typey_birb | https://euclidean-whale.itch.io/typey-birb | MIT/Apache-2.0 / Amatic font OFL | 0.17 | yes (2025-10) | ? | Flappy flight steered by typing words | "A correct word gives the bird a visible lift" |
| ascii-bomb-ecs | https://github.com/aleksa2808/ascii-bomb-ecs | https://aleksa2808.github.io/ascii-bomb-ecs/ | MIT (code only) / **assets explicitly excluded** | 0.11 | yes (2026-01) | 2D | ASCII Bomberman with several modes and mobile web controls | "A blast cross propagates tile by tile" |
| Fish Folk: Bomby | https://github.com/fishfolk/bomby | none | MIT/Apache-2.0 / **assets CC BY-NC 4.0** | 0.15 | yes (2025-01) | 2D | Bomberman with LDtk levels | "Bomb fuse pulses faster as it nears 0" |
| Fish Folk: Jumpy | https://github.com/fishfolk/jumpy | https://fishfolk.org/games/jumpy/ | MIT/Apache-2.0 / **assets CC BY-NC 4.0** | Bones framework on a Bevy 0.11 renderer | yes (2026-01) | 2D | Tactical pixel shooter with online play | "A weapon pickup pops in and the hand pose changes the same frame" |
| Fish Folk: Punchy | https://github.com/fishfolk/punchy | https://fishfolk.github.io/punchy/player/latest | MIT/Apache-2.0 / **assets CC BY-NC 4.0** | 0.9 | no (2024-06) | 2.5D | Beat-em-up with bevy-parallax and rapier2d | "Punch impact gives hit-flash and knockback" |
| Golab | https://github.com/NiiightmareXD/golab | none | MIT / third-party assets (Sketchfab CC BY, Poly Pizza) listed in CREDITS.md | 0.18.1 | yes (2026-05) | 3D | Blobby multiplayer shooter using Lightyear | "Soft-body squish on hit reads at 1x" |
| Tower Thrower (BJ #4) | https://github.com/lucasmerlin/towerthrower | https://lucasmerlin.itch.io/tower-thrower | **no repo license**; README lists CC BY 4.0 third-party assets | 0.12 | no (2023-12) | 2D | Physics tower stacking in the style of Tricky Towers | "Tower wobble settles in under 1 s" |

## 4. Rhythm and music

| Name | Repo | Play | Code / assets license | Bevy | Upd 25-26 | 2D/3D | Notable | Eval idea |
|---|---|---|---|---|---|---|---|---|
| One-Click Ninja | https://github.com/fluffysquirrels/one-click-ninja | none | MIT / music by David Dawn and HYPERMUSIC (license not stated) | 0.5.0 | no (2022) | 2D | One-button rhythm game (1-Button Jam 2021) | "A beat-timed hit lands exactly on the beat frame" |
| Blobo Party (BJ #5, 4th) | https://github.com/benfrankel/blobo_party | https://pyrious.itch.io/blobo-party | MIT/Apache-2.0 / art and fonts by the author (license not stated) | 0.15 | yes (2025-03) | 2D | Musical roguelike deckbuilder | "Everything on screen pulses with the beat" |
| phase / shift (BJ #5) | https://github.com/philiplinden/bevy-jam-5 | none | MIT / ATTRIBUTION.md | 0.14.0 | no (2024-08) | 2D | Bullet-hell rhythm game with custom shaders | "Bullet spawns are quantized to the beat grid" |
| Loop Tunes (BJ #5) | https://github.com/bcmpinc/looptunes | none | MIT/Apache-2.0/CC0 / assets not stated | 0.14 | no (2024-07) | 2D | Chiptune creation sandbox | "Playhead sweep and note flash stay in sync" |
| gdclone | https://github.com/opstic/gdclone | https://opstic.github.io/gdclone/ | MPL-2.0 / requires a Geometry Dash install (assets are RobTop's) | 0.13 | no (2024-06) | 2D | Geometry Dash level renderer (rhythm platformer); renders levels fast | "Pulse effects keyed to music time" |
| phichain | https://github.com/Ivan-1F/phichain | https://phichain.rs | LGPL-3.0 / respack assets CC BY-NC 4.0 | 0.18.1 | yes (2026-10) | 2D | Charting editor for the Phigros rhythm game; keyframed judgment-line motion | "Keyframed line motion matches a chart and notes land on the line" |

## 5. Puzzle

| Name | Repo | Play | Code / assets license | Bevy | Upd 25-26 | 2D/3D | Notable | Eval idea |
|---|---|---|---|---|---|---|---|---|
| Simon Says (BJ #5, **1st**) | https://github.com/DylanRJohnston/simon_says | https://dylanrjohnston.itch.io/simon-says | MIT/Apache-2.0 / FontAwesome icons | 0.16.1 | yes (2026-01) | ? | Jam winner; you follow an unseen voice's commands; uses bevy_firework and a video-glitch effect | "Firework burst on level clear" |
| Abiogenesis (BJ #6, 4th) | https://github.com/DylanRJohnston/abiogenesis | https://dylanrjohnston.itch.io/abiogenesis | MIT/Apache-2.0 / music by Meydän, FlatIcon icons | 0.16 | yes (2025-07) | ? | Particle Life sandbox with emergent behaviour | "Deterministic particle-life frame at t matches the golden render" |
| ::maligna kodera; (BJ #7, 4th) | https://github.com/Krzyhau/maligna-kodera-classic | https://krzyhau.itch.io/maligna-kodera | MIT / assets not stated | 0.18.0 | yes (2026-03) | ? | Recent puzzle prototype | "A wrong move reverts with a clear rewind" |
| Pixie Wrangler | https://github.com/rparrett/pixie_wrangler | https://euclidean-whale.itch.io/pixie-wrangler | MIT/Apache-2.0 (LICENSE) / assets not stated | 0.17 | yes (2025-10) | 2D | Circuit-board routing puzzle that runs a traffic sim | "Pixies flow along drawn traces with no overlap" |
| LinkSider (BJ #3, **1st**) | https://github.com/kuviman/linksider-bevy | https://kuviman.itch.io/linksider | MIT / assets not stated | 0.10.1 | no (2024-10) | 2D | Jam winner; attach effects to the player's sides; the commercial version is now private | "Side-effect icons stay readable as the block rolls" |
| LibraCity | https://github.com/djeedai/libracity | none | MIT/Apache-2.0 / assets not stated | 0.7 | no (2023) | ? | City built on a needle; balance tilt | "Tilt angle is readable and tweened, not snapped" |
| sokoban-rs | https://github.com/ShenMian/sokoban-rs | none | Apache-2.0 / assets not stated | **0.19** | yes (2026-07) | 2D | Sokoban with an automatic solver | "Solver path replays as a comp at fixed fps" |
| Cube Collection | https://github.com/wiryls/cube-collection | https://wiryls.github.io/cube-collection | LGPL-3.0 (repo) and MIT for the `cube-collection` crate, per README | **0.19.0** | yes (2026-07) | 2D | Minimal cube-merging puzzle with a web build | "A merge tween lands in 8 frames" |
| Blockout | https://github.com/boleque/blockout | none | MIT / assets not stated | **0.19.0** | yes (2026-08) | 3D | 3D Tetris viewed down into a pit | "Layer clear gives a flash and the layers above drop with ease-out" |
| projectris | https://github.com/bonsairobo/projectris | none | **none** | 0.15 | yes (2025-04) | 3D | Tetris where you play the piece's shadow | "Shadow projection matches the 3D piece every frame" |
| Tetris (NightsWatch) | https://github.com/NightsWatchGames/tetris | https://nightswatchgames.github.io/games/tetris/ | MIT / assets not stated | 0.16 | yes (2025-08) | 2D | Clean classic Tetris | "Line clear flashes before collapse" |
| Rubik's Cube | https://github.com/NightsWatchGames/rubiks-cube | https://nightswatchgames.github.io/games/rubiks-cube/ | MIT / assets not stated | 0.15 | no (2024-12) | 3D | Rubik's cube simulator | "A face turn is a 90-degree eased rotation of exactly 9 cubies" |
| taileater | https://github.com/szunami/taileater | https://szunami.itch.io/taileater | Apache-2.0 / assets not stated | 0.5 | no (2023) | 2D | Snake puzzle where you eat your own tail | "Undo is readable" |
| Warlock's Gambit (BJ #1) | https://github.com/team-plover/warlocks-gambit | https://gibonus.itch.io/warlocks-gambit | MIT/Apache-2.0 / **assets all rights reserved** | 0.8 | no (2022) | ? | Card-cheating game | "A hidden card slide is readable but subtle" |
| chainmailer (BJ #6) | https://github.com/cxreiff/chainmailer | https://cxreiff.itch.io/chainmailer | MIT/Apache-2.0 / assets not stated | 0.17 | yes (2025-11) | ? | Chain-letter themed jam game | "Fan-out of letters along a chain is legible" |
| Atominoes (BJ #6) | https://github.com/Louis-Tarvin/Atominoes | https://louisnivrat.itch.io/atominoes | README: MIT or Apache-2.0 (no LICENSE file) / assets not stated | 0.16 | yes (2025-06) | ? | Domino-style atomic chain reaction | "Dominoes topple in sequence at a constant rhythm" |

## 6. Reference projects, templates, larger games

| Name | Repo | Play | Code / assets license | Bevy | Upd 25-26 | 2D/3D | Notable | Eval idea |
|---|---|---|---|---|---|---|---|---|
| Foxtrot | https://github.com/janhohenheim/foxtrot | https://janhohenheim.itch.io/foxtrot | MIT (MIT/Apache-2.0/CC0 files) / assets not separately stated | 0.18 | yes (2026-02) | 3D | 3D reference project: TrenchBroom levels, character controller, menus | "First-person camera bob stays under X px and does not sicken" |
| bevy_new_2d (Bevy Flock template) | https://github.com/TheBevyFlock/bevy_new_2d | https://the-bevy-flock.itch.io/bevy-new-2d | CC0/MIT/Apache-2.0 / **assets third-party**, see the credits menu in `src/menus/credits.rs` | **0.19** | yes (2026-08) | 2D | Official community jam template: screens, audio, asset tracking | "A screen transition fades over a set number of frames" |
| The Lob (BJ #7) | https://github.com/Aceeri/lobs | https://aceeri.itch.io/the-lob | MIT/Apache-2.0 / assets not stated | 0.18 | yes (2026-02) | 3D | Built on Foxtrot | "A lob arc shows its landing marker before impact" |
| Pyraxia (BJ #7) | https://github.com/DGriffin91/BevyJam7 | https://dgriffin.itch.io/pyraxia | MIT/Apache-2.0 / assets not stated | 0.18.0 | yes (2026-02) | 3D? | By a Bevy rendering contributor (DGriffin91) | "Fire/glow emissive reads under bloom" |
| Digital Extinction | https://github.com/DigitalExtinction/Game (archived) | https://de-game.org | AGPL-3.0 / assets in `/assets`, covered by the AGPL according to the README | 0.13 | no (2024-09, archived) | 3D | Open 3D RTS with terrain and unit selection | "Selection ring and move-order ping" |
| Unhaunter | https://github.com/deavid/unhaunter | http://www.unhaunter.com/ | Apache-2.0 / assets not stated | 0.16 | yes (2026-07) | 2D isometric | Ghost investigation with lighting and darkness | "Flashlight cone shows correct falloff" |
| BevyRoguelike | https://github.com/thephet/BevyRoguelike | none | **none** | 0.17 | yes (2026-01) | 2D ASCII | Roguelike following a book; 256 stars | "Field of view reveal" |
| Magus Parvus | https://github.com/PraxTube/magus-parvus | https://rancic.itch.io/magus-parvus | MIT / third-party assets in CREDITS.md | 0.16 | yes (2025-09) | 2D | Cozy top-down mage game; spell effects | "A spell cast gives an anticipation frame, then a burst" |
| Enty TD (BJ #4, 5th) | https://github.com/rparrett/entytd | https://euclidean-whale.itch.io/enty-td | MIT/Apache-2.0 / tileset **CC0** (vurmux), pickaxe sound **CC BY 4.0**, rest original | 0.16 | yes (2025-10) | 2D | Mining tower defense with many entities | "Hundreds of entities stay readable on one contact sheet" |
| Taipo | https://github.com/rparrett/taipo | https://euclidean-whale.itch.io/taipo | MIT/Apache-2.0 / **BrowserQuest art CC BY-SA 3.0, other assets CC BY-SA 4.0** | 0.16 | yes (2025-05) | 2D | Typing tower defense for learning Japanese | "A typed word fires a projectile within 2 frames" |
| Dark Wisps Defence | https://github.com/Arrekin/dark-wisps-defence | none | **no license**: README allows personal learning only | **0.19** | yes (2026-10) | 2D | Open-grid tower defense; active | inspiration only |
| Bevy Jam Simulator (BJ #4, 2nd) | https://github.com/benfrankel/bevy_jam_simulator | https://pyrious.itch.io/bevy-jam-simulator | MIT/Apache-2.0 / music **CC BY-NC-SA 4.0**, sound effects **CC0** | 0.12 | no (2024-01) | 2D | Incremental game whose entity count explodes | "Counter roll-up eases to its value" |
| Petty Party (BJ #1, **1st**) | https://github.com/jabuwu/petty-party | https://jabuwu.itch.io/petty-party | README: MIT/Apache-2.0, no attribution needed / assets not stated | 0.6.1 | no (2022) | 2D | Board game against a cheating opponent, with minigames | "Dice roll settles on a face" |
| Build A Better Buddy (BJ #1) | https://github.com/cart/build_a_better_buddy | none | MIT/Apache-2.0 / assets not stated | 0.6 | no (2022) | 2D | Auto-battler by Bevy's creator | "Attack lunge has anticipation and follow-through" |
| Hug | https://github.com/Hihaheho/Hug | https://hug.hihaheho.com | **none** | 0.5 | yes (2025-02) | 3D | Active-ragdoll hugging with rapier | "Ragdoll settles without explosion" |
| Wisphaven | https://github.com/jim-works/Wisphaven | none | GPL-3.0 / assets not stated | 0.15.1 | yes (2025-05) | 3D voxel | Voxel village defense | "Voxel break scatters particle cubes" |
| Lost In Time | https://github.com/RaminKav/LostInTime | none | **All Rights Reserved** (LICENSE.md) | 0.10.1 | yes (2026-09) | 2D | Feature-rich rogue-like survival; 151 stars | inspiration only |

---

## Best 10 for Moonsplice evals

1. **Bevy 0.19.1 showcase examples** (breakout, alien_cake_addict, desk_toy, plus `2d_screen_shake`,
   `eased_motion` and `motion_blur`). They are on Moonsplice's exact Bevy version and licensed MIT/Apache-2.0, so they
   are the only references here whose golden renders Moonsplice can reproduce frame for frame. Start eval baselines
   here: rebuild breakout as a comp and diff the contact sheet.
2. **Pirate Sea Jam**. It is the only project found with real water: dynamic waves, buoyancy, an infinite ocean and a
   third-person camera. That makes it the reference for the boat and wake evals ("a wake that reads at speed", "the
   hull rides the swell"). The code license is MIT/Apache-2.0, but the asset license is not stated, so mine it for
   ideas only.
3. **Combine Racers**. A short, replayable 2.5D racer where speed comes from tricks. Its central moment, a trick that
   lands and boosts speed, is the kind of beat a critic can judge on a contact sheet. The code is MIT/Apache-2.0 and
   the assets are original to the author.
4. **Bevy Kart**. A top-down kart racer on Bevy 0.19 with laps, item pickups and a track editor. It is the closest
   mechanic match for "a gate pass lands with a flash" and "lap tick" evals. It has **no license**, so use it as
   inspiration only.
5. **Jump Jump**. 3D and MIT, and its README lists a juice checklist: charge squash, charge particles, fall effect,
   camera follow and procedural platforms. Each item maps to one eval with a clear oracle.
6. **Kataster**. A single-screen shooter on Bevy 0.17 with MIT/Apache-2.0 code and Kenney assets (CC0). Its assets
   are safe to reuse in comps, which makes it the best source of shmup sprites and smoke particles.
7. **Blockout**. 3D, Bevy 0.19, MIT. A fixed camera looking down into a pit, layer clears and falling pieces are
   simple systems of (t, state), which suits "layer clear flash, then the rows above drop with ease-out".
8. **Thetawave**. A full-featured MIT shooter with physics, pickups and HUD bars. It is a good source for HUD-tween
   and low-health-flash evals. Its assets live outside the repo and carry no stated license.
9. **Simon Says** (Bevy Jam 5 winner). On Bevy 0.16, licensed MIT/Apache-2.0, and uses fireworks and video-glitch
   effects. It shows what jam judges reward in a week of work, so use it for "level-clear celebration" evals.
10. **Enty TD / Taipo** (rparrett). Both are on Bevy 0.16 with code under MIT/Apache-2.0 and asset licenses stated
    file by file (CC0, CC BY, CC BY-SA). They are the cleanest projects for reusing assets with attribution, and Enty
    TD's large entity counts test whether a contact sheet stays readable when many things are on screen.

Runners-up: Shanty Quest (boat combat, assets CC BY 3.0), Insta Kill (hit-stop juice), Foxtrot (3D reference on Bevy
0.18), bevy_new_2d (template on Bevy 0.19), sokoban-rs and Cube Collection (both Bevy 0.19, deterministic puzzle
replays).
