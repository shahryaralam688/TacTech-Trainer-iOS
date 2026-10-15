import Foundation

/// Resolves TacTech `GET /exercises` → Form Studio 3D demo session.
///
/// Prefer backend `form3d` when present. Legacy local map remains for offline/dev
/// while the original bundled clips roll out on the API.
enum FormStudioExerciseMap {

    // MARK: - Session

    struct DemoSession: Equatable {
        let clipId: String
        let exerciseName: String
        /// Remote CDN URL (downloaded/cached before WebView open).
        let remoteAnimationURL: URL?
        let guide: [Form3DGuideStep]?
        let cues: [String]?
        let subtitle: String?
    }

    // MARK: - Bundled FBX inventory

    /// Filenames present under `FormStudioWeb/models/exercises/` that ship in the app.
    static let bundledClipFiles: Set<String> = [
        "Air_Squat.fbx",
        "Breathing_Idle.fbx",
        "Burpee.fbx",
        "Idle.fbx",
        "Jumping_Jacks.fbx",
        "Plank.fbx",
        "Push_Up.fbx",
        "Sit_To_Stand.fbx",
        "Situps.fbx",
        "Warming_Up.fbx"
    ]

    /// Form Studio id → relative FBX filename (must match `exercises.js` `file` basename).
    static let clipFileByFormStudioId: [String: String] = [
        "push_up": "Push_Up.fbx",
        "air_squat": "Air_Squat.fbx",
        "warming_up": "Warming_Up.fbx",
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

    private static let reuseFallback: [String: String] = [
        "goblet_squat_reuse": "air_squat",
        "hip_hinge": "romanian_deadlift"
    ]

    // MARK: - Legacy TacTech id map (offline / until backend seeds form3d)

    private static let tactechIdMap: [String: FormStudioTarget] = [
        "ex-pushup": .clip("push_up"),
        "ex-plank": .clip("plank"),
        "ex-squat": .reuse("air_squat", note: "Bodyweight squat pattern — barbell path not shown"),
        "ex-ai-goblet-s": .reuse("air_squat", note: "Goblet load not shown — squat pattern demo"),
        "ex-ai-goblet-b": .reuse("air_squat", note: "Box squat pattern approximated with air squat"),
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
        "ex-ai-seated-r": .clip("seated_row"),
        "ex-ai-seated-s": .clip("seated_shoulder_press"),
        "ex-ai-chest-pr": .clip("chest_press"),
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
        NameRule(formStudioId: "warming_up", tokens: ["warming up", "warm up", "warmup"]),
        NameRule(formStudioId: "burpee", tokens: ["burpee"])
    ]

    // MARK: - Public API (backend-aware)

    /// Whether Exercise Detail should show “3D Form Demo”.
    static func canShow3DDemo(for exercise: Exercise) -> Bool {
        demoSession(for: exercise) != nil
    }

    /// Resolved session for opening Form Studio. `nil` → hide button.
    static func demoSession(for exercise: Exercise) -> DemoSession? {
        if let form3d = exercise.form3d {
            if !form3d.enabled { return nil }

            // Prefer API clipId; else legacy map; else stable id from exercise for CDN-only rows.
            let clipId = normalizeClipId(form3d.clipId)
                ?? legacyClipId(for: exercise)
                ?? normalizeClipId(exercise.id)
            guard let clipId else { return nil }

            let remote = nonEmpty(form3d.animationUrl).flatMap { URL(string: $0) }
            let bundled = hasBundledClip(for: clipId)
            // CDN-only exercises need no local hardcode — URL alone is enough.
            guard remote != nil || bundled else { return nil }

            let apiGuide = form3d.guide.flatMap { $0.isEmpty ? nil : $0 }
            let apiCues = form3d.cues.flatMap { $0.isEmpty ? nil : $0 }

            return DemoSession(
                clipId: clipId,
                exerciseName: exercise.name,
                remoteAnimationURL: remote,
                guide: apiGuide,
                cues: apiCues,
                subtitle: nil
            )
        }

        // Missing form3d → legacy offline/dev fallback (bundled clips only).
        guard let clipId = formStudioId(for: exercise) else { return nil }
        return DemoSession(
            clipId: clipId,
            exerciseName: exercise.name,
            remoteAnimationURL: nil,
            guide: nil,
            cues: nil,
            subtitle: reuseNote(for: exercise)
        )
    }

    /// Legacy helper: Form Studio id only when a bundled (or reusable) FBX exists.
    static func formStudioId(for exercise: Exercise) -> String? {
        guard let resolved = resolve(id: exercise.id, name: exercise.name) else { return nil }
        guard hasBundledClip(for: resolved) else { return nil }
        return resolved == "sit_ups" ? "situps" : resolved
    }

    static func hasDemo(for exercise: Exercise) -> Bool {
        canShow3DDemo(for: exercise)
    }

    static func hasBundledClip(for formStudioId: String) -> Bool {
        let id = normalizeClipId(formStudioId) ?? formStudioId
        if let file = clipFileByFormStudioId[id], bundledClipFiles.contains(file) {
            return true
        }
        if id == "hip_hinge",
           let fallback = reuseFallback[id],
           let file = clipFileByFormStudioId[fallback],
           bundledClipFiles.contains(file) {
            return true
        }
        return false
    }

    static func mappedIdIgnoringBundle(for exercise: Exercise) -> String? {
        resolve(id: exercise.id, name: exercise.name)
    }

    static func reuseNote(for exercise: Exercise) -> String? {
        guard let target = tactechIdMap[exercise.id.lowercased()] else { return nil }
        if case let .reuse(_, note) = target { return note }
        return nil
    }

    // MARK: - Resolve

    private static func legacyClipId(for exercise: Exercise) -> String? {
        resolve(id: exercise.id, name: exercise.name).map { $0 == "sit_ups" ? "situps" : $0 }
    }

    private static func resolve(id: String?, name: String?) -> String? {
        if let raw = id?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let key = raw.lowercased()
            if let target = tactechIdMap[key] {
                switch target {
                case .none:
                    return nil
                case .clip(let fsId), .reuse(let fsId, _):
                    return effectiveId(fsId)
                }
            }
        }

        let haystack = normalize([id, name].compactMap { $0 }.joined(separator: " "))
        guard !haystack.isEmpty else { return nil }

        if haystack.contains("bike") || haystack.contains("hiking")
            || haystack.contains("zone 2") || haystack.contains("sun breath")
            || haystack.contains("easy walk") {
            return nil
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

    private static func effectiveId(_ formStudioId: String) -> String {
        let id = normalizeClipId(formStudioId) ?? formStudioId
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

    private static func normalizeClipId(_ value: String?) -> String? {
        guard var id = nonEmpty(value)?.lowercased() else { return nil }
        if id == "sit_ups" { id = "situps" }
        return id
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
