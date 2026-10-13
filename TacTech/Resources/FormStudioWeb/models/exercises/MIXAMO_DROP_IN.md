# Form Studio — Mixamo FBX drop-in pack

Drop Mixamo animations here so TacTech **3D Form Demo** unlocks for more exercises.

Scaffolding already exists in `exercises.js` + `guide-data.js`.  
After you add a file with the **exact filename**, add that filename to `FormStudioExerciseMap.bundledClipFiles` in Swift and rebuild.

## Human steps

1. Go to [mixamo.com](https://www.mixamo.com) → log in  
2. Select character **X Bot** (same as existing clips)  
3. Search the animation terms below  
4. Download **FBX** — match existing clips’ convention (Without Skin / 30 fps if offered)  
5. Save into this folder: `TacTech/Resources/FormStudioWeb/models/exercises/`  
6. Add the filename to `FormStudioExerciseMap.bundledClipFiles`  
7. Rebuild the TacTech app (folder reference already copies `FormStudioWeb`)

Do **not** invent or rename past the table — filenames must match `exercises.js`.

---

## Already bundled (do not replace unless upgrading)

| File | Form Studio id |
|------|----------------|
| `Push_Up.fbx` | `push_up` |
| `Air_Squat.fbx` | `air_squat` |
| `Jumping_Jacks.fbx` | `jumping_jacks` |
| `Plank.fbx` | `plank` |
| `Situps.fbx` | `situps` |
| `Burpee.fbx` | `burpee` |
| `Idle.fbx` / `Breathing_Idle.fbx` | idle only |
| `Sit_To_Stand.fbx` | `sit_to_stand` |

---

## P0 — drop these first

| Exact filename | Form Studio id | Mixamo search terms (try in order) | TacTech exercises unlocked |
|----------------|----------------|-------------------------------------|----------------------------|
| `Walking_Lunge.fbx` | `walking_lunge` | `Walking Lunge`, `Lunge`, `Alternate Lunge` | Walking Lunge (`ex-lunge`) |
| `Romanian_Deadlift.fbx` | `romanian_deadlift` | `Deadlift`, `Romanian Deadlift`, `Hip Hinge` | Romanian Deadlift (`ex-rdl`); also unlocks Hip Hinge until dedicated clip exists |
| `Hip_Hinge.fbx` | `hip_hinge` | `Hip Hinge`, `Good Morning`, `Deadlift` | Hip Hinge Drill (`ex-hiphinge`) — optional if RDL already dropped |
| `Overhead_Press.fbx` | `overhead_press` | `Standing Overhead Press`, `Shoulder Press`, `Military Press` | Overhead Press (`ex-ohp`) |
| `Bent_Over_Row.fbx` | `bent_over_row` | `Bent Over Row`, `Rowing`, `Dumbbell Row` | Bent Over Row (`ex-row`) |
| `Glute_Bridge.fbx` | `glute_bridge` | `Bridge`, `Hip Bridge`, `Glute Bridge` | Glute Bridge (`ex-ai-glute-br`) |
| `Bird_Dog.fbx` | `bird_dog` | `Bird Dog`, `Opposite Arm And Leg Balance` | Bird Dog (`ex-ai-bird-dog`) |
| `Dead_Bug.fbx` | `dead_bug` | `Dead Bug`, `Core Stability` (pick closest supine limb reach) | Dead Bug (`ex-ai-dead-bug`) |
| `Cat_Cow.fbx` | `cat_cow` | `Cat Cow`, `Cat Stretch`, `Cow Pose` | Cat Cow (`ex-ai-cat-cow`) |
| `Worlds_Greatest_Stretch.fbx` | `worlds_greatest_stretch` | `Worlds Greatest Stretch`, `Lunge With Twist`, `Spiderman Lunge` | World's Greatest Stretch (`ex-ai-world-s-`) |

---

## P2 — machines (optional)

| Exact filename | Form Studio id | Mixamo search terms | TacTech |
|----------------|----------------|---------------------|---------|
| `Seated_Row.fbx` | `seated_row` | `Seated Row`, `Rowing` | Seated Row |
| `Seated_Shoulder_Press.fbx` | `seated_shoulder_press` | `Seated Shoulder Press`, `Overhead Press` | Seated Shoulder Press |
| `Chest_Press.fbx` | `chest_press` | `Chest Press`, `Bench Press` (standing/mimic OK) | Chest Press Machine |

---

## No 3D (do not fake)

| TacTech | Reason |
|---------|--------|
| Bike Sprint, Zone 2 Bike | Machine cardio — no honest Mixamo clip |
| Easy Walk, Hiking Intervals | Locomotion outdoors — skip for Phase 1 |
| Sun Breath Flow | Breath/yoga flow — skip unless you add a dedicated yoga clip later |

---

## Reuse (no new FBX needed)

| TacTech | Uses Form Studio id | Note |
|---------|---------------------|------|
| Barbell Squat | `air_squat` | Bodyweight squat pattern |
| Goblet Squat / Goblet Box Squat | `air_squat` | Load/box not shown |
| Push Up / Plank | `push_up` / `plank` | Exact |

---

## QA checklist (after each drop)

- [ ] File name exact (case-sensitive on device)  
- [ ] Filename added to `FormStudioExerciseMap.bundledClipFiles`  
- [ ] Rebuild TacTech  
- [ ] Open exercise in Workout → **3D Form Demo** visible  
- [ ] Instruct → countdown → guide → live loop  
- [ ] Existing 6 demos still open (Push Up, Air Squat, …)  
- [ ] Exercises without FBX: no 3D button / no crash  

## Status summary (shipping scaffold)

| TacTech name | id | Form Studio id | Status |
|--------------|-----|----------------|--------|
| Push Up | ex-pushup | push_up | **bundled** |
| Plank | ex-plank | plank | **bundled** |
| Barbell Squat | ex-squat | air_squat | **reuse (bundled)** |
| Goblet Squat | ex-ai-goblet-s | air_squat | **reuse (bundled)** |
| Goblet Box Squat | ex-ai-goblet-b | air_squat | **reuse (bundled)** |
| Walking Lunge | ex-lunge | walking_lunge | **needs FBX** |
| Romanian Deadlift | ex-rdl | romanian_deadlift | **needs FBX** |
| Hip Hinge Drill | ex-hiphinge | hip_hinge | **needs FBX** (or RDL reuse) |
| Overhead Press | ex-ohp | overhead_press | **needs FBX** |
| Bent Over Row | ex-row | bent_over_row | **needs FBX** |
| Glute Bridge | ex-ai-glute-br | glute_bridge | **needs FBX** |
| Bird Dog | ex-ai-bird-dog | bird_dog | **needs FBX** |
| Dead Bug | ex-ai-dead-bug | dead_bug | **needs FBX** |
| Cat Cow | ex-ai-cat-cow | cat_cow | **needs FBX** |
| Sit to Stand | ex-ai-sit-to-s | sit_to_stand | **bundled** |
| World's Greatest Stretch | ex-ai-world-s- | worlds_greatest_stretch | **needs FBX** |
| Seated Row | ex-ai-seated-r | seated_row | **needs FBX** |
| Seated Shoulder Press | ex-ai-seated-s | seated_shoulder_press | **needs FBX** |
| Chest Press Machine | ex-ai-chest-pr | chest_press | **needs FBX** |
| Bike Sprint | ex-hiit | — | **no-3D** |
| Zone 2 Bike | ex-ai-zone-2-b | — | **no-3D** |
| Easy Walk | ex-ai-easy-wal | — | **no-3D** |
| Hiking Intervals | ex-ai-hiking-i | — | **no-3D** |
| Sun Breath Flow | ex-ai-sun-brea | — | **no-3D** |
