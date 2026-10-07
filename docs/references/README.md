# References: open Bevy work, assets and eval designs for the studio

A library for Tablua's studio world (the agent builds Moonsplice games and motion pieces; Bevy 0.19.1 draws the 3D).
It serves four uses: ideas for asks and treatments, assets a comp may use, renders to compare outputs against
(goldens), and evals to try the agent on. Compiled 2026-10-06 from web and GitHub research; licenses and Bevy
versions were read from each repo or crate, nothing was downloaded or run, and anything unchecked is marked.

| file | what |
|---|---|
| `games.md` | about 80 open Bevy games by genre (racing, boats and water, arcade, rhythm, puzzle, reference), each with code and asset licenses, Bevy version, what is notable, one eval idea; ends with the best 10 |
| `motion.md` | motion graphics and type, tweening and springs, VFX and particles: about 30 crates |
| `look.md` | water and sky, post, camera, generative, Bevy's own CI goldens; ends with the 10 best golden sources and how to capture each |
| `assets-and-evals.md` | openly licensed assets (Part A), how visual work is tested and agent benchmarks (Part B), 20 eval ideas each with ask, seed, oracle and assets |

## The license rule

Code to read is not code to copy, and a reference is not an asset. A comp, a golden or a binary takes only what is
CC0, CC-BY (credit kept), OFL, or MIT/Apache with assets stated as such. Flagged in the files and worth remembering:

- No license means all rights reserved: Bevy Kart, A Fistful of Boomerangs and others are inspiration only.
- GPL-3.0 (bevy_oceansim, bevy-open-world): technique only.
- Fish Folk assets are CC BY-NC; Warlock's Gambit's are all rights reserved.
- Pixabay, Pexels and LottieFiles free assets are not CC0: no raw files in a repo or binary.
- Quaternius moved from CC0 to its own QAL on 2026-08-28 (as the research found): newer downloads not standalone.
- Bevy's own assets are licensed file by file (CREDITS.md); the Fox is CC-BY 4.0.

Safe base: Kenney, Poly Haven, ambientCG, CC0 Freesound, NASA footage on Wikimedia, Blender open films with their
credit line, Google Fonts.

## Where to start

1. Goldens on Moonsplice's exact Bevy: the 0.19.1 examples (breakout, `testbed_2d`, `testbed_3d`, `easing_functions`,
   `atmosphere` at dawn, noon and dusk), captured with a fixed frame time through `CI_TESTING_CONFIG` (`look.md`).
2. A golden contact sheet in the critic's own form: bevy_motiongfx sequences seeked to fixed times (`look.md`).
3. The harbour evals: Pirate Sea Jam (the only real water found) for the wake and swell; Bevy Kart and Combine Racers
   for gate passes that land (`games.md`).
4. Eval shapes that fit Tablua's outcome rule (`assets-and-evals.md`, Part B): an ask written as checkable motion
   predicates (MoVer), so each failing predicate is a finding a move can close; a start scene and goal render with
   distance after every move (BlenderGym); oracles proved against broken copies of the golden (GameLogicBench), as
   Tablua's red proofs are.
5. Eval 2 of the 20 is a regression for studio trial 1's hidden title (opacity 0, no finding saw it).

Evals and goldens themselves live in Moonsplice (`cadence/evals`); this library is where they are drawn from.
