# Form Studio — Mixamo → CDN → API → iOS

How TacTech ships **3D Form Demo** clips for the exercise catalog.

## Pipeline

1. **Mixamo.com** — character **X Bot** → download FBX (Without Skin / 30 fps if offered)
2. **Upload** — ops puts the file on CDN (via backend admin) **or** drops into  
   `TacTech/Resources/FormStudioWeb/models/exercises/` for offline/dev
3. **Backend** — set on `GET /exercises` item:
   ```json
   "form3d": {
     "enabled": true,
     "clipId": "walking_lunge",
     "character": "x_bot",
     "animationUrl": "https://cdn.example.com/form3d/Walking_Lunge.fbx",
     "cues": ["Long step", "Front knee tracks toes"],
     "guide": [
       { "focus": "Setup", "title": "Stand tall", "detail": "Feet under hips.", "t": 0.08 }
     ]
   }
   ```
4. **iOS** — next fetch of `/exercises` shows **3D Form Demo** when  
   `form3d.enabled == true` **and** (`animationUrl` non-empty **or** bundled FBX for `clipId`)

App caches CDN FBX under `Caches/Form3D/` (keyed by `clipId` + URL hash).  
Guide/cues from API override local `exercises.js` / `guide-data.js` when non-empty.

## iOS behavior

| `form3d` | Result |
|----------|--------|
| missing | Legacy local map — bundled clips only (offline/dev) |
| `enabled: false` | Hide 3D button |
| `enabled: true` + URL | Download/cache → WebView `FBXLoader` |
| `enabled: true` + no URL + bundled `clipId` | Load local `models/exercises/*.fbx` |
| `enabled: true` + no URL + no bundle | Hide button (DEBUG hint only) |

No new Swift hardcode is required for a new backend-enabled exercise when `clipId` + `animationUrl` are set.

## Suggested Mixamo queries (24 catalog)

| # | Exercise | Suggested `clipId` | Mixamo search | Bundled today |
|---|----------|-------------------|---------------|---------------|
| 1 | Push Up | `push_up` | Push Up | Yes (`Push_Up.fbx`) |
| 2 | Plank | `plank` | Plank | Yes |
| 3 | Barbell / Goblet Squat | `air_squat` | Air Squat / Squat | Yes (reuse) |
| 4 | Jumping Jacks | `jumping_jacks` | Jumping Jacks | Yes |
| 5 | Sit-Ups | `situps` | Situps / Crunch | Yes |
| 6 | Burpee | `burpee` | Burpee | Yes |
| 7 | Sit to Stand | `sit_to_stand` | Sit To Stand / Stand Up | Yes |
| 8 | Walking Lunge | `walking_lunge` | Walking Lunge, Lunge | No |
| 9 | Romanian Deadlift | `romanian_deadlift` | Deadlift, Romanian Deadlift | No |
| 10 | Hip Hinge Drill | `hip_hinge` | Hip Hinge, Good Morning | No |
| 11 | Overhead Press | `overhead_press` | Overhead Press, Shoulder Press | No |
| 12 | Bent Over Row | `bent_over_row` | Bent Over Row, Rowing | No |
| 13 | Glute Bridge | `glute_bridge` | Bridge, Hip Bridge | No |
| 14 | Bird Dog | `bird_dog` | Bird Dog | No |
| 15 | Dead Bug | `dead_bug` | Dead Bug / Core | No |
| 16 | Cat Cow | `cat_cow` | Cat Cow, Cat Stretch | No |
| 17 | World’s Greatest Stretch | `worlds_greatest_stretch` | Lunge With Twist | No |
| 18 | Seated Row | `seated_row` | Seated Row, Rowing | No |
| 19 | Seated Shoulder Press | `seated_shoulder_press` | Seated Shoulder Press | No |
| 20 | Chest Press Machine | `chest_press` | Chest Press, Bench Press | No |
| 21 | Bike Sprint | — | — | No 3D |
| 22 | Zone 2 Bike | — | — | No 3D |
| 23 | Easy Walk / Hiking | — | — | No 3D |
| 24 | Sun Breath Flow | — | — | No 3D |

## Local drop-in (optional)

See `TacTech/Resources/FormStudioWeb/models/exercises/MIXAMO_DROP_IN.md`.  
After dropping an FBX, add the filename to `FormStudioExerciseMap.bundledClipFiles` for offline fallback.

## Do not

- Download from Adobe Mixamo inside the app
- Show 3D when `enabled != true` unless using the legacy missing-`form3d` bundled fallback
- Point a clip at an unrelated movement
