import Foundation

/// Maps TacTech `GET /exercises` → Form Studio Mixamo clip ids.
///
/// `hasDemo` is true only when the resolved clip’s `.fbx` is in `bundledClipFiles`
/// (keep that set in sync with `Resources/FormStudioWeb/models/exercises/`).
///
/// Phase 2 — add more clips:
/// 1. Mixamo: same **X Bot**, download FBX (see `models/exercises/MIXAMO_DROP_IN.md`)
/// 2. Drop file with the exact filename into `models/exercises/`
/// 3. Add the filename to `bundledClipFiles` below
/// 4. Rebuild (folder reference already copies Web content)
enum FormStudioExerciseMap {

    // MARK: - Bundled FBX inventory (filesystem truth for gating UI)

    /// Filenames present under `FormStudioWeb/models/exercises/` that ship in the app.
    /// Update whenever you drop a new Mixamo FBX and rebuild.
    static let bundledClipFiles: Set<String> = [
        "Air_Squat.fbx",
        "Breathing_Idle.fbx",
        "Burpee.fbx",
        "Idle.fbx",
        "Jumping_Jacks.fbx",
        "Plank.fbx",
        "Push_Up.fbx",
        "Sit_To_Stand.fbx",
        "Situps.fbx"
    ]

    /// Form Studio id → relative FBX filename (must match `exercises.js` `file` basename).
    static let clipFileByFormStudioId: [String: String] = [
        "push_up": "Push_Up.fbx",
        "air_squat": "Air_Squat.fbx",
        "jumping_jacks": "Jumping_Jacks.fbx",
        "plank": "Plank.fbx",
        "situps": "Situps.fbx",
        "burpee": "Burpee.fbx",
        "walking_lunge": "Walking_Lunge.fbx",
        "romanian_deadlift": "Romanian_Deadlift.fbx",
        "hip_hinge": "Hip_Hinge.fbx",
        "overhead_press": "Overhead_Press.fbx",
        "bent_over_row": "Bent_Over_Row.fbx",
        "glute_bridge": "Glute_Bridge.fbx",
        "bird_dog": "Bird_Dog.fbx",
        "dead_bug": "Dead_Bug.fbx",
        "cat_cow": "Cat_Cow.fbx",
        "sit_to_stand": "Sit_To_Stand.fbx",
        "worlds_greatest_stretch": "Worlds_Greatest_Stretch.fbx",
        "seated_row": "Seated_Row.fbx",
        "seated_shoulder_press": "Seated_Shoulder_Press.fbx",
        "chest_press": "Chest_Press.fbx"
    ]

    /// Honest reuse: if dedicated clip missing, fall back to a bundled similar pattern.
    private static let reuseFallback: [String: String] = [
        // Goblet / box squat → bodyweight squat pattern (bundled)
        "goblet_squat_reuse": "air_squat",
        // Hip hinge drill may reuse RDL once that FBX is dropped
        "hip_hinge": "romanian_deadlift"
    ]

    // MARK: - TacTech id → Form Studio id (source of truth for staging catalog)

    private static let tactechIdMap: [String: FormStudioTarget] = [
        // Exact / strong match (bundled today)
        "ex-pushup": .clip("push_up"),
        "ex-plank": .clip("plank"),

        // Honest reuse of bundled air squat
        "ex-squat": .reuse("air_squat", note: "Bodyweight squat pattern — barbell path not shown"),
        "ex-ai-goblet-s": .reuse("air_squat", note: "Goblet load not shown — squat pattern demo"),
        "ex-ai-goblet-b": .reuse("air_squat", note: "Box squat pattern approximated with air squat"),

        // P0 — need Mixamo FBX drop-in
        "ex-lunge": .clip("walking_lunge"),
        "ex-rdl": .clip("romanian_deadlift"),
        "ex-hiphinge": .clip("hip_hinge"),
        "ex-ohp": .clip("overhead_press"),
        "ex-row": .clip("bent_over_row"),
        "ex-ai-glute-br": .clip("glute_bridge"),
        "ex-ai-bird-dog": .clip("bird_dog"),
        "ex-ai-dead-bug": .clip("dead_bug"),
        "ex-ai-cat-cow": .clip("cat_cow"),
        "ex-ai-sit-to-s": .clip("sit_to_stand"),
        "ex-ai-world-s-": .clip("worlds_greatest_stretch"),

        // P2 — need Mixamo FBX
        "ex-ai-seated-r": .clip("seated_row"),
        "ex-ai-seated-s": .clip("seated_shoulder_press"),
        "ex-ai-chest-pr": .clip("chest_press"),

        // No honest 3D clip (cardio / flow)
        "ex-hiit": .none,
        "ex-ai-zone-2-b": .none,
        "ex-ai-easy-wal": .none,
        "ex-ai-hiking-i": .none,
        "ex-ai-sun-brea": .none
    ]

    private enum FormStudioTarget {
        case clip(String)
        case reuse(String, note: String)
        case none
    }

    private struct NameRule {
        let formStudioId: String
        let tokens: [String]
    }

    /// Name-token fallback when API id is unknown / renamed.
    private static let nameRules: [NameRule] = [
        NameRule(formStudioId: "push_up", tokens: ["push up", "pushup", "push-up"]),
        NameRule(formStudioId: "plank", tokens: ["plank"]),
        NameRule(formStudioId: "walking_lunge", tokens: ["walking lunge", "lunge"]),
        NameRule(formStudioId: "romanian_deadlift", tokens: ["romanian deadlift", "rdl"]),
        NameRule(formStudioId: "hip_hinge", tokens: ["hip hinge"]),
        NameRule(formStudioId: "overhead_press", tokens: ["overhead press", "ohp"]),
        NameRule(formStudioId: "bent_over_row", tokens: ["bent over row"]),
        NameRule(formStudioId: "glute_bridge", tokens: ["glute bridge"]),
        NameRule(formStudioId: "bird_dog", tokens: ["bird dog"]),
        NameRule(formStudioId: "dead_bug", tokens: ["dead bug"]),
        NameRule(formStudioId: "cat_cow", tokens: ["cat cow", "cat-cow"]),
        NameRule(formStudioId: "sit_to_stand", tokens: ["sit to stand", "sit-to-stand"]),
        NameRule(formStudioId: "worlds_greatest_stretch", tokens: ["world", "greatest stretch"]),
        NameRule(formStudioId: "seated_row", tokens: ["seated row"]),
        NameRule(formStudioId: "seated_shoulder_press", tokens: ["seated shoulder press"]),
        NameRule(formStudioId: "chest_press", tokens: ["chest press"]),
        NameRule(formStudioId: "air_squat", tokens: ["goblet squat", "goblet box", "barbell squat", "air squat", "squat"]),
        NameRule(formStudioId: "situps", tokens: ["sit up", "situp", "sit-up", "crunch"]),
        NameRule(formStudioId: "jumping_jacks", tokens: ["jumping jack"]),
        NameRule(formStudioId: "burpee", tokens: ["burpee"])
    ]

    // MARK: - Public API

    /// Form Studio id to open, only if a bundled (or reusable bundled) FBX exists.
    static func formStudioId(for exercise: Exercise) -> String? {
        guard let resolved = resolve(id: exercise.id, name: exercise.name) else { return nil }
        guard hasBundledClip(for: resolved) else { return nil }
        // `resolve` already remaps hip_hinge → romanian_deadlift when that FBX is the only one present.
        return resolved == "sit_ups" ? "situps" : resolved
    }

    static func hasDemo(for exercise: Exercise) -> Bool {
        formStudioId(for: exercise) != nil
    }

    static func hasBundledClip(for formStudioId: String) -> Bool {
        let id = formStudioId == "sit_ups" ? "situps" : formStudioId
        if let file = clipFileByFormStudioId[id], bundledClipFiles.contains(file) {
            return true
        }
        // Dedicated hip_hinge missing → reuse Romanian_Deadlift.fbx when present
        if id == "hip_hinge",
           let fallback = reuseFallback[id],
           let file = clipFileByFormStudioId[fallback],
           bundledClipFiles.contains(file) {
            return true
        }
        return false
    }

    /// Resolved Form Studio id even if FBX is missing (for DEBUG / docs). Prefer `formStudioId(for:)`.
    static func mappedIdIgnoringBundle(for exercise: Exercise) -> String? {
        resolve(id: exercise.id, name: exercise.name)
    }

    /// Optional UI subtitle when demo reuses a similar clip.
    static func reuseNote(for exercise: Exercise) -> String? {
        guard let target = tactechIdMap[exercise.id.lowercased()] else { return nil }
        if case let .reuse(_, note) = target { return note }
        return nil
    }

    // MARK: - Resolve

    private static func resolve(id: String?, name: String?) -> String? {
        if let raw = id?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let key = raw.lowercased()
            if let target = tactechIdMap[key] {
                switch target {
                case .none:
                    return nil
                case .clip(let fsId):
                    return effectiveId(fsId)
                case .reuse(let fsId, _):
                    return effectiveId(fsId)
                }
            }
        }

        let haystack = normalize([id, name].compactMap { $0 }.joined(separator: " "))
        guard !haystack.isEmpty else { return nil }

        // Skip known no-3D cardio / flow by name
        let skipTokens = ["bike", "walk", "hiking", "zone 2", "sun breath", "sprint"]
        if skipTokens.contains(where: { haystack.contains($0) }) {
            // Allow "sit to stand" etc. — only skip if purely cardio phrases
            if haystack.contains("bike") || haystack.contains("hiking")
                || haystack.contains("zone 2") || haystack.contains("sun breath")
                || haystack.contains("easy walk") {
                return nil
            }
        }

        let ordered = nameRules.sorted {
            ($0.tokens.map(\.count).max() ?? 0) > ($1.tokens.map(\.count).max() ?? 0)
        }
        for rule in ordered {
            for token in rule.tokens {
                let needle = normalize(token)
                if haystack == needle || haystack.contains(needle) {
                    return effectiveId(rule.formStudioId)
                }
            }
        }
        return nil
    }

    /// Prefer dedicated clip; for hip_hinge use RDL file id when only that FBX exists.
    private static func effectiveId(_ formStudioId: String) -> String {
        let id = formStudioId == "sit_ups" ? "situps" : formStudioId
        if let file = clipFileByFormStudioId[id], bundledClipFiles.contains(file) {
            return id
        }
        if id == "hip_hinge",
           let fallback = reuseFallback[id],
           let file = clipFileByFormStudioId[fallback],
           bundledClipFiles.contains(file) {
            return fallback
        }
        return id
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
