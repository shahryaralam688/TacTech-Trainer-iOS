/** Bodyweight exercise catalog + Mixamo clips + guided form tours */

export const EXERCISES = [
	{
		id: 'push_up',
		name: 'Push-Ups',
		tagline: 'Chest, arms & core strength',
		level: 'Beginner+',
		reps: '8–12 reps',
		file: 'models/exercises/Push_Up.fbx',
		muscles: [ 'Chest', 'Shoulders', 'Triceps', 'Core' ],
		summary: 'A floor pressing move. You hold a straight body line and lower/raise your chest with arm control — no machine needed.',
		balance: [
			'Hands under shoulders, fingers slightly out.',
			'Body forms one straight line: head → hips → heels.',
			'Brace your core so hips do not sag or pike up.',
			'Feet together or hip-width for stability.'
		],
		steps: [
			'Start in a high plank: arms straight, shoulders over wrists.',
			'Lock your body — squeeze glutes and pull belly in.',
			'Bend elbows (~45°) and lower chest toward the floor with control.',
			'Pause briefly just above the floor without collapsing.',
			'Press the floor away and fully extend arms without locking hard.',
			'Breathe: inhale down, exhale as you push up.'
		],
		cues: [
			'Keep a rigid plank line',
			'Elbows ~45°, not flared wide',
			'Chest leads — not the hips',
			'Full range, controlled tempo'
		],
		mistakes: [
			'Hips sagging (hurts lower back)',
			'Head dropping or looking forward too hard',
			'Partial reps / bouncing off the floor'
		],
		guide: [
			{
				focus: 'Hands',
				title: 'Plant your hands',
				detail: 'Place hands under shoulders, fingers slightly out. Wrists stack under shoulders for a strong base.',
				t: 0.08,
				camera: { pos: [ -1.2, 1.1, 2.4 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Legs',
				title: 'Lock the leg line',
				detail: 'Feet together or hip-width. Legs stay long and active — squeeze quads so hips do not sag.',
				t: 0.18,
				camera: { pos: [ -2.2, 0.9, 2.8 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Core',
				title: 'Brace the whole body',
				detail: 'Ribs down, glutes on. Build one straight line from head to heels before you bend the elbows.',
				t: 0.28,
				camera: { pos: [ -1.8, 1.2, 3.0 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Chest',
				title: 'Lower the chest',
				detail: 'Bend elbows about 45°. Lower chest toward the floor with control — chest leads, not the hips.',
				t: 0.48,
				camera: { pos: [ -1.5, 0.85, 2.5 ], target: [ 0, 0.45, 0 ] }
			},
			{
				focus: 'Elbows',
				title: 'Bottom position',
				detail: 'Pause just above the floor. Keep elbows tracking, neck neutral, body still in one plank line.',
				t: 0.62,
				camera: { pos: [ -1.3, 0.7, 2.2 ], target: [ 0, 0.35, 0 ] }
			},
			{
				focus: 'Arms',
				title: 'Press back up',
				detail: 'Push the floor away, exhale, and fully extend arms without slamming or losing the plank.',
				t: 0.82,
				camera: { pos: [ -1.7, 1.15, 2.9 ], target: [ 0, 0.75, 0 ] }
			}
		]
	},
	{
		id: 'air_squat',
		name: 'Air Squats',
		tagline: 'Legs & glutes, bodyweight only',
		level: 'Beginner',
		reps: '12–15 reps',
		file: 'models/exercises/Air_Squat.fbx',
		muscles: [ 'Quads', 'Glutes', 'Hamstrings', 'Core' ],
		summary: 'Sit back and down with your own body weight, then stand tall. Great for legs, balance, and daily movement strength.',
		balance: [
			'Feet about shoulder-width, toes slightly out.',
			'Weight through mid-foot / heels — not only toes.',
			'Chest up, eyes forward — spine stays long.',
			'Knees track over toes; do not cave inward.'
		],
		steps: [
			'Stand tall, brace core, arms forward for counterbalance if needed.',
			'Push hips back as if sitting onto a chair.',
			'Bend knees and descend until thighs are at least parallel (mobility allowing).',
			'Keep heels planted and knees aligned.',
			'Drive through the floor to stand — squeeze glutes at the top.',
			'Breathe: inhale down, exhale up.'
		],
		cues: [
			'Hips back, then down',
			'Heels stay grounded',
			'Knees track over toes',
			'Stand tall every rep'
		],
		mistakes: [
			'Knees collapsing inward',
			'Rounding the lower back',
			'Rising onto the toes'
		],
		guide: [
			{
				focus: 'Feet',
				title: 'Set your stance',
				detail: 'Feet about shoulder-width, toes slightly out. Feel the whole foot — especially heels.',
				t: 0.05,
				camera: { pos: [ -1.4, 1.2, 2.8 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Hips',
				title: 'Hips go back first',
				detail: 'Push hips back like sitting to a chair. Chest stays proud; do not fold forward.',
				t: 0.25,
				camera: { pos: [ -1.8, 1.1, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Knees',
				title: 'Track the knees',
				detail: 'Knees follow the toes. Do not let them cave inward as you descend.',
				t: 0.42,
				camera: { pos: [ -1.2, 0.85, 2.6 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Depth',
				title: 'Find your depth',
				detail: 'Lower until thighs are near parallel (or your safe depth). Heels stay planted.',
				t: 0.58,
				camera: { pos: [ -1.6, 0.9, 2.7 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Chest',
				title: 'Keep the chest tall',
				detail: 'Spine long, eyes forward. Avoid rounding the lower back at the bottom.',
				t: 0.68,
				camera: { pos: [ -1.5, 1.35, 2.5 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Stand',
				title: 'Drive up strong',
				detail: 'Push the floor away, squeeze glutes at the top, and finish tall before the next rep.',
				t: 0.88,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'jumping_jacks',
		name: 'Jumping Jacks',
		tagline: 'Cardio warm-up & coordination',
		level: 'Beginner',
		reps: '30–45 sec',
		file: 'models/exercises/Jumping_Jacks.fbx',
		muscles: [ 'Full body', 'Calves', 'Shoulders', 'Cardio' ],
		summary: 'A rhythmic jump that opens and closes arms and legs together. Raises heart rate and wakes up coordination.',
		balance: [
			'Land soft on the balls of your feet, then whole foot.',
			'Keep a slight knee bend on every landing.',
			'Stay upright — do not lean forward.',
			'Arms and legs move as one rhythm.'
		],
		steps: [
			'Start feet together, arms by your sides.',
			'Jump feet out to shoulder/hip-width while raising arms overhead.',
			'Jump back to start: feet together, arms down.',
			'Keep jumps light and springy — not stomping.',
			'Find a steady breath pattern; do not hold your breath.',
			'If impact is high, step jacks out instead of jumping.'
		],
		cues: [
			'Soft landings',
			'Same rhythm: arms + legs',
			'Stay tall through the torso',
			'Light and quick feet'
		],
		mistakes: [
			'Locking knees on landing',
			'Arms unfinished / lazy range',
			'Holding breath'
		],
		guide: [
			{
				focus: 'Start',
				title: 'Ready stance',
				detail: 'Feet together, arms relaxed by your sides. Soft knees — ready to spring.',
				t: 0.05,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Legs',
				title: 'Open the feet',
				detail: 'Jump feet out to about shoulder width. Land light on the balls of the feet.',
				t: 0.28,
				camera: { pos: [ -1.7, 1.0, 2.9 ], target: [ 0, 0.6, 0 ] }
			},
			{
				focus: 'Arms',
				title: 'Arms go overhead',
				detail: 'Raise both arms in the same beat as the feet open. Finish with hands high.',
				t: 0.4,
				camera: { pos: [ -1.4, 1.6, 2.6 ], target: [ 0, 1.35, 0 ] }
			},
			{
				focus: 'Landing',
				title: 'Soft landing',
				detail: 'Keep a slight knee bend. Never lock the knees when you hit the floor.',
				t: 0.55,
				camera: { pos: [ -1.6, 0.95, 2.7 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Close',
				title: 'Return to center',
				detail: 'Jump feet together and bring arms down together — one clean rhythm.',
				t: 0.75,
				camera: { pos: [ -1.5, 1.35, 2.9 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Breath',
				title: 'Stay tall & breathe',
				detail: 'Torso upright, steady breathing. Light and springy — not stomping.',
				t: 0.9,
				camera: { pos: [ -1.6, 1.45, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'plank',
		name: 'Plank Hold',
		tagline: 'Core stability & body line',
		level: 'Beginner+',
		reps: '20–40 sec',
		file: 'models/exercises/Plank.fbx',
		muscles: [ 'Core', 'Shoulders', 'Glutes', 'Back' ],
		summary: 'An isometric hold. You balance in a straight line and resist gravity — teaching the body how to stay stable.',
		balance: [
			'Elbows under shoulders (forearm plank) or hands under shoulders.',
			'Neutral neck: look at the floor just ahead of hands.',
			'Squeeze glutes; do not let hips drop or rise.',
			'Push the floor away so upper back stays active.'
		],
		steps: [
			'Set hands/forearms and step feet back into a straight line.',
			'Brace core like someone will tap your stomach.',
			'Create full-body tension: legs, glutes, shoulders.',
			'Hold steady — small breaths, no collapsing.',
			'If form breaks, rest, then restart with shorter holds.',
			'Exit by dropping knees down with control.'
		],
		cues: [
			'Straight line head to heels',
			'Glutes on, ribs down',
			'Push floor away',
			'Breathe in short steady cycles'
		],
		mistakes: [
			'Hips sagging or piking',
			'Shoulders shrugging to ears',
			'Holding breath until shake-collapse'
		],
		guide: [
			{
				focus: 'Hands',
				title: 'Set the base',
				detail: 'Hands or forearms under shoulders. Push the floor away so shoulders stay active.',
				t: 0.12,
				camera: { pos: [ -1.2, 0.9, 2.3 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Legs',
				title: 'Step into the line',
				detail: 'Feet back, legs long. Create a straight rail from heels through hips to head.',
				t: 0.28,
				camera: { pos: [ -2.1, 0.85, 2.8 ], target: [ 0, 0.5, 0 ] }
			},
			{
				focus: 'Hips',
				title: 'Hips neither up nor down',
				detail: 'Squeeze glutes. If hips sag or pike, reset — the goal is a flat body line.',
				t: 0.45,
				camera: { pos: [ -1.7, 1.0, 2.6 ], target: [ 0, 0.65, 0 ] }
			},
			{
				focus: 'Core',
				title: 'Brace like armor',
				detail: 'Pull belly in gently, ribs quiet. Full-body tension — not just “hanging”.',
				t: 0.6,
				camera: { pos: [ -1.5, 1.05, 2.5 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Neck',
				title: 'Neutral head',
				detail: 'Look at the floor just ahead of your hands. Do not crane the neck up.',
				t: 0.75,
				camera: { pos: [ -1.1, 1.1, 2.2 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Hold',
				title: 'Breathe and own it',
				detail: 'Short steady breaths. If form breaks, rest — then restart with a shorter hold.',
				t: 0.9,
				camera: { pos: [ -1.8, 1.1, 3.0 ], target: [ 0, 0.7, 0 ] }
			}
		]
	},
	{
		id: 'situps',
		name: 'Sit-Ups',
		tagline: 'Core flexion on the floor',
		level: 'Beginner+',
		reps: '10–15 reps',
		file: 'models/exercises/Situps.fbx',
		muscles: [ 'Abs', 'Hip flexors', 'Core' ],
		summary: 'Lie down, then sit up with control. Focus on curling the torso — not yanking with the neck.',
		balance: [
			'Feet planted; knees bent comfortably.',
			'Lower back starts in contact with the floor.',
			'Chin slightly tucked — fist-distance from chest.',
			'Move evenly; avoid twisting to one side.'
		],
		steps: [
			'Lie on your back, knees bent, feet down.',
			'Hands at temples or crossed on chest (avoid pulling the head).',
			'Engage abs and curl torso up toward thighs.',
			'Pause briefly at the top without jerking.',
			'Lower with control until shoulders touch the floor.',
			'Exhale on the way up, inhale on the way down.'
		],
		cues: [
			'Curl, do not yank the neck',
			'Abs initiate the move',
			'Control the lowering',
			'Smooth tempo each rep'
		],
		mistakes: [
			'Pulling head/neck with hands',
			'Using momentum / swinging',
			'Feet lifting wildly every rep'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Lie down correctly',
				detail: 'Back on the floor, knees bent, feet planted. Lower back starts in contact with the floor.',
				t: 0.08,
				camera: { pos: [ -1.6, 1.2, 2.8 ], target: [ 0, 0.4, 0 ] }
			},
			{
				focus: 'Hands',
				title: 'Place the hands',
				detail: 'Hands at temples or crossed on chest. Do not yank the head forward.',
				t: 0.22,
				camera: { pos: [ -1.2, 1.0, 2.3 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Abs',
				title: 'Abs start the curl',
				detail: 'Exhale and curl the torso up. Think “ribs toward hips”, not “head first”.',
				t: 0.4,
				camera: { pos: [ -1.5, 0.95, 2.5 ], target: [ 0, 0.5, 0 ] }
			},
			{
				focus: 'Top',
				title: 'Pause at the top',
				detail: 'Sit tall enough to finish the curl. Brief pause — no swinging or twisting.',
				t: 0.58,
				camera: { pos: [ -1.4, 1.15, 2.6 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Lower',
				title: 'Lower with control',
				detail: 'Inhale and reverse slowly until shoulders touch the floor. Own the eccentric.',
				t: 0.78,
				camera: { pos: [ -1.55, 1.0, 2.7 ], target: [ 0, 0.45, 0 ] }
			},
			{
				focus: 'Neck',
				title: 'Protect the neck',
				detail: 'Chin gently tucked. If the neck strains, cross arms on chest and shorten the range.',
				t: 0.9,
				camera: { pos: [ -1.1, 1.05, 2.2 ], target: [ 0, 0.65, 0 ] }
			}
		]
	},
	{
		id: 'burpee',
		name: 'Burpees',
		tagline: 'Full-body conditioner',
		level: 'Intermediate',
		reps: '6–10 reps',
		file: 'models/exercises/Burpee.fbx',
		muscles: [ 'Full body', 'Chest', 'Legs', 'Cardio' ],
		summary: 'Squat → plank → push-up pattern → jump. High effort, zero equipment. Quality beats speed.',
		balance: [
			'Soft knees on the jump landing.',
			'Hands plant under shoulders when you go to plank.',
			'Keep core braced during the kick-back.',
			'Stand fully before the next jump.'
		],
		steps: [
			'Stand tall, then squat and place hands on the floor.',
			'Jump or step feet back into a strong plank.',
			'Optional: perform one controlled push-up.',
			'Jump or step feet forward toward hands.',
			'Explode upward into a small jump, arms up.',
			'Land soft and immediately set up the next rep with control.'
		],
		cues: [
			'Plank line before you push',
			'Soft landings',
			'Full stand between reps',
			'Own the tempo — do not rush form'
		],
		mistakes: [
			'Collapsing in the plank',
			'Hard heel-stomping landings',
			'Sacrificing form only for speed'
		],
		guide: [
			{
				focus: 'Stand',
				title: 'Start tall',
				detail: 'Stand ready. Soft knees. You will move squat → plank → stand → jump.',
				t: 0.05,
				camera: { pos: [ -1.5, 1.45, 3.0 ], target: [ 0, 1.05, 0 ] }
			},
			{
				focus: 'Hands',
				title: 'Squat & plant hands',
				detail: 'Drop into a squat and place hands on the floor under shoulders.',
				t: 0.22,
				camera: { pos: [ -1.5, 1.0, 2.7 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Plank',
				title: 'Kick to a strong plank',
				detail: 'Jump or step feet back. Body line must be solid before any push-up.',
				t: 0.4,
				camera: { pos: [ -1.9, 0.95, 2.9 ], target: [ 0, 0.55, 0 ] }
			},
			{
				focus: 'Chest',
				title: 'Optional push-up',
				detail: 'If you add a push-up, keep hips level and chest controlled — no collapse.',
				t: 0.55,
				camera: { pos: [ -1.4, 0.75, 2.4 ], target: [ 0, 0.4, 0 ] }
			},
			{
				focus: 'Feet',
				title: 'Feet jump forward',
				detail: 'Bring feet toward hands under control, ready to stand tall.',
				t: 0.72,
				camera: { pos: [ -1.6, 1.05, 2.7 ], target: [ 0, 0.65, 0 ] }
			},
			{
				focus: 'Jump',
				title: 'Explode & land soft',
				detail: 'Jump up, arms high, then land with soft knees before the next rep.',
				t: 0.9,
				camera: { pos: [ -1.55, 1.55, 3.1 ], target: [ 0, 1.15, 0 ] }
			}
		]
	},
	{
		id: 'walking_lunge',
		name: 'Walking Lunges',
		tagline: 'Single-leg strength & balance',
		level: 'Beginner+',
		reps: '8–12 / leg',
		file: 'models/exercises/Walking_Lunge.fbx',
		muscles: [ 'Quads', 'Glutes', 'Hamstrings', 'Core' ],
		summary: 'Step forward into a long lunge, drop the back knee with control, then drive up into the next step. Great for legs, hips, and balance.',
		balance: [
			'Long step — front shin vertical at the bottom.',
			'Torso tall; ribs stacked over hips.',
			'Front knee tracks over mid-foot.',
			'Soft front foot — do not slam the heel.'
		],
		steps: [
			'Stand tall, feet under hips, brace lightly.',
			'Step one foot forward into a long stride.',
			'Lower until front thigh is near parallel and back knee hovers.',
			'Drive through the front mid-foot to stand.',
			'Step the rear leg through into the next lunge.',
			'Alternate sides with even tempo.'
		],
		cues: [
			'Long step',
			'Tall torso',
			'Knee tracks toes',
			'Controlled depth'
		],
		mistakes: [
			'Short choppy steps',
			'Front knee collapsing in',
			'Leaning the chest forward'
		],
		guide: [
			{
				focus: 'Feet',
				title: 'Set up for walking',
				detail: 'Stand tall, feet under hips, brace lightly.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Hips',
				title: 'Step one foot forward into a long stride',
				detail: 'Step one foot forward into a long stride.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Knee',
				title: 'Lower until front thigh is near parallel',
				detail: 'Lower until front thigh is near parallel and back knee hovers.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Torso',
				title: 'Drive through the front mid-foot to stan',
				detail: 'Drive through the front mid-foot to stand.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Drive',
				title: 'Step the rear leg through into the next ',
				detail: 'Step the rear leg through into the next lunge.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Step',
				title: 'Alternate sides with even tempo.',
				detail: 'Alternate sides with even tempo.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'romanian_deadlift',
		name: 'Romanian Deadlift',
		tagline: 'Hip hinge for posterior chain',
		level: 'Intermediate',
		reps: '8–12 reps',
		file: 'models/exercises/Romanian_Deadlift.fbx',
		muscles: [ 'Hamstrings', 'Glutes', 'Erectors', 'Core' ],
		summary: 'Push the hips back while keeping a long spine, feel the hamstrings load, then drive the hips forward to stand tall.',
		balance: [
			'Soft knees — not locked.',
			'Weight mid-foot / heels.',
			'Spine long; shoulders packed.',
			'Bar or hands stay close to the legs.'
		],
		steps: [
			'Stand tall holding weight (or miming the bar path).',
			'Brace core; soft bend in the knees.',
			'Push hips back as the torso tips forward.',
			'Keep the spine long until you feel hamstring tension.',
			'Drive hips forward to stand — squeeze glutes at the top.',
			'Reset and repeat with control.'
		],
		cues: [
			'Hips back',
			'Spine long',
			'Bar close',
			'Stand tall'
		],
		mistakes: [
			'Rounding the low back',
			'Squatting the move',
			'Letting weight drift forward'
		],
		guide: [
			{
				focus: 'Feet',
				title: 'Set up for romanian',
				detail: 'Stand tall holding weight (or miming the bar path).',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Hips',
				title: 'Brace core; soft bend in the knees.',
				detail: 'Brace core; soft bend in the knees.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Spine',
				title: 'Push hips back as the torso tips forward',
				detail: 'Push hips back as the torso tips forward.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Hamstrings',
				title: 'Keep the spine long until you feel hamst',
				detail: 'Keep the spine long until you feel hamstring tension.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Glutes',
				title: 'Drive hips forward to stand — squeeze gl',
				detail: 'Drive hips forward to stand — squeeze glutes at the top.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Stand',
				title: 'Reset and repeat with control.',
				detail: 'Reset and repeat with control.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'hip_hinge',
		name: 'Hip Hinge Drill',
		tagline: 'Learn the hinge pattern',
		level: 'Beginner',
		reps: '8–10 reps',
		file: 'models/exercises/Hip_Hinge.fbx',
		muscles: [ 'Hamstrings', 'Glutes', 'Core' ],
		summary: 'Practice pushing the hips back with a tall chest — the foundation for deadlifts and good lifting posture.',
		balance: [
			'Feet hip-width, soft knees.',
			'Chest proud; eyes forward.',
			'Hips travel back, not down like a squat.',
			'Feel stretch in the hamstrings.'
		],
		steps: [
			'Stand tall with hands on hips or a dowel on the back.',
			'Brace lightly through the midsection.',
			'Push hips back while the torso tips forward.',
			'Stop when hamstrings load or torso nears parallel.',
			'Drive hips forward to return to standing.',
			'Keep the spine angle consistent — no rounding.'
		],
		cues: [
			'Hips back first',
			'Soft knees',
			'Long spine',
			'Stand by driving hips'
		],
		mistakes: [
			'Turning it into a squat',
			'Rounding the back',
			'Locking the knees hard'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Set up for hip',
				detail: 'Stand tall with hands on hips or a dowel on the back.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Brace',
				title: 'Brace lightly through the midsection.',
				detail: 'Brace lightly through the midsection.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Hips',
				title: 'Push hips back while the torso tips forw',
				detail: 'Push hips back while the torso tips forward.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Stretch',
				title: 'Stop when hamstrings load or torso nears',
				detail: 'Stop when hamstrings load or torso nears parallel.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Drive',
				title: 'Drive hips forward to return to standing',
				detail: 'Drive hips forward to return to standing.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Reset',
				title: 'Keep the spine angle consistent — no rou',
				detail: 'Keep the spine angle consistent — no rounding.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'overhead_press',
		name: 'Overhead Press',
		tagline: 'Shoulders & upper body press',
		level: 'Intermediate',
		reps: '6–10 reps',
		file: 'models/exercises/Overhead_Press.fbx',
		muscles: [ 'Shoulders', 'Triceps', 'Upper back', 'Core' ],
		summary: 'Press a load from the shoulders to full lockout overhead while keeping ribs down and glutes on.',
		balance: [
			'Feet under hips; glutes lightly squeezed.',
			'Ribs stacked — avoid flaring the chest.',
			'Wrists stacked over elbows under the load.',
			'Head stays neutral; chin slightly tucked.'
		],
		steps: [
			'Start with hands at shoulder height, elbows under wrists.',
			'Brace core and squeeze glutes.',
			'Press vertically until arms lock out overhead.',
			'Keep the head path clear — move head slightly through at the top if needed.',
			'Lower with control back to the shoulders.',
			'Reset brace before the next rep.'
		],
		cues: [
			'Ribs down',
			'Press up, not forward',
			'Lock out tall',
			'Control the descent'
		],
		mistakes: [
			'Excessive back arch',
			'Flaring elbows wide',
			'Pressing in front of the face'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Set up for overhead',
				detail: 'Start with hands at shoulder height, elbows under wrists.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Brace',
				title: 'Brace core and squeeze glutes.',
				detail: 'Brace core and squeeze glutes.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Press',
				title: 'Press vertically until arms lock out ove',
				detail: 'Press vertically until arms lock out overhead.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Lockout',
				title: 'Keep the head path clear — move head sli',
				detail: 'Keep the head path clear — move head slightly through at the top if needed.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Lower',
				title: 'Lower with control back to the shoulders',
				detail: 'Lower with control back to the shoulders.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Reset',
				title: 'Reset brace before the next rep.',
				detail: 'Reset brace before the next rep.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'bent_over_row',
		name: 'Bent Over Row',
		tagline: 'Pull for back thickness',
		level: 'Intermediate',
		reps: '8–12 reps',
		file: 'models/exercises/Bent_Over_Row.fbx',
		muscles: [ 'Lats', 'Rhomboids', 'Rear delts', 'Biceps' ],
		summary: 'Hinge to a stable torso angle, then row elbows back toward the hips while keeping the spine long.',
		balance: [
			'Hinge first — torso ~45° or parallel as mobility allows.',
			'Soft knees; weight mid-foot.',
			'Neutral neck; eyes slightly ahead on the floor.',
			'Shoulders packed before you pull.'
		],
		steps: [
			'Hinge hips back to set your row angle.',
			'Let arms hang long under the shoulders.',
			'Pull elbows back toward the hips.',
			'Squeeze shoulder blades briefly at the top.',
			'Lower with control to a full hang.',
			'Keep the torso quiet — no bounce.'
		],
		cues: [
			'Torso still',
			'Elbows to hips',
			'Squeeze the back',
			'Full hang between reps'
		],
		mistakes: [
			'Yank with the lower back',
			'Shrugging the traps',
			'Rounding the spine'
		],
		guide: [
			{
				focus: 'Hinge',
				title: 'Set up for bent',
				detail: 'Hinge hips back to set your row angle.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Hang',
				title: 'Let arms hang long under the shoulders.',
				detail: 'Let arms hang long under the shoulders.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Pull',
				title: 'Pull elbows back toward the hips.',
				detail: 'Pull elbows back toward the hips.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Squeeze',
				title: 'Squeeze shoulder blades briefly at the t',
				detail: 'Squeeze shoulder blades briefly at the top.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Lower',
				title: 'Lower with control to a full hang.',
				detail: 'Lower with control to a full hang.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Brace',
				title: 'Keep the torso quiet — no bounce.',
				detail: 'Keep the torso quiet — no bounce.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'glute_bridge',
		name: 'Glute Bridge',
		tagline: 'Posterior activation on the floor',
		level: 'Beginner',
		reps: '10–15 reps',
		file: 'models/exercises/Glute_Bridge.fbx',
		muscles: [ 'Glutes', 'Hamstrings', 'Core' ],
		summary: 'Lie on your back, drive through the heels, and lift the hips until the body forms a straight line from knees to shoulders.',
		balance: [
			'Feet flat, hip-width, heels under knees.',
			'Arms by sides for stability.',
			'Ribs down — do not flare into the ribcage.',
			'Squeeze glutes at the top.'
		],
		steps: [
			'Lie on your back, knees bent, feet planted.',
			'Brace lightly and press heels into the floor.',
			'Lift hips until knees, hips, and shoulders align.',
			'Pause and squeeze the glutes.',
			'Lower with control without collapsing.',
			'Repeat for smooth reps.'
		],
		cues: [
			'Drive heels',
			'Ribs quiet',
			'Squeeze glutes',
			'Controlled lower'
		],
		mistakes: [
			'Overarching the low back',
			'Pushing through the toes',
			'Rushing the top'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Set up for glute',
				detail: 'Lie on your back, knees bent, feet planted.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Feet',
				title: 'Brace lightly and press heels into the f',
				detail: 'Brace lightly and press heels into the floor.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Drive',
				title: 'Lift hips until knees, hips, and shoulde',
				detail: 'Lift hips until knees, hips, and shoulders align.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Top',
				title: 'Pause and squeeze the glutes.',
				detail: 'Pause and squeeze the glutes.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Lower',
				title: 'Lower with control without collapsing.',
				detail: 'Lower with control without collapsing.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Breath',
				title: 'Repeat for smooth reps.',
				detail: 'Repeat for smooth reps.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'bird_dog',
		name: 'Bird Dog',
		tagline: 'Anti-rotation core control',
		level: 'Beginner',
		reps: '6–8 / side',
		file: 'models/exercises/Bird_Dog.fbx',
		muscles: [ 'Core', 'Glutes', 'Shoulders', 'Back' ],
		summary: 'From all fours, reach opposite arm and leg long while keeping hips level — a classic stability drill.',
		balance: [
			'Hands under shoulders, knees under hips.',
			'Spine neutral — no sagging belly.',
			'Reach long, do not lift high.',
			'Hips stay square to the floor.'
		],
		steps: [
			'Set up on all fours with a braced midsection.',
			'Slide one hand forward and the opposite foot back.',
			'Reach until arm and leg are long without rotating.',
			'Pause briefly while staying level.',
			'Return hand and knee under the body with control.',
			'Switch sides.'
		],
		cues: [
			'Long reach',
			'Hips level',
			'Quiet torso',
			'Slow returns'
		],
		mistakes: [
			'Hiking one hip',
			'Arching the low back',
			'Rushing side to side'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Set up for bird',
				detail: 'Set up on all fours with a braced midsection.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Reach',
				title: 'Slide one hand forward and the opposite ',
				detail: 'Slide one hand forward and the opposite foot back.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Level',
				title: 'Reach until arm and leg are long without',
				detail: 'Reach until arm and leg are long without rotating.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Hold',
				title: 'Pause briefly while staying level.',
				detail: 'Pause briefly while staying level.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Return',
				title: 'Return hand and knee under the body with',
				detail: 'Return hand and knee under the body with control.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Switch',
				title: 'Switch sides.',
				detail: 'Switch sides.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'dead_bug',
		name: 'Dead Bug',
		tagline: 'Core bracing on your back',
		level: 'Beginner',
		reps: '6–8 / side',
		file: 'models/exercises/Dead_Bug.fbx',
		muscles: [ 'Core', 'Hip flexors', 'Shoulders' ],
		summary: 'Lie on your back with arms and legs up, then slowly extend opposite arm and leg while keeping the low back glued to the floor.',
		balance: [
			'Low back pressed gently into the floor.',
			'Ribs down toward the pelvis.',
			'Move slow — quality over range.',
			'Exhale as limbs extend.'
		],
		steps: [
			'Lie on your back; arms to the ceiling, knees over hips.',
			'Brace so the low back stays quiet.',
			'Extend opposite arm and leg toward the floor.',
			'Stop before the back arches.',
			'Return to the start position.',
			'Alternate sides with control.'
		],
		cues: [
			'Back flat',
			'Slow limbs',
			'Ribs down',
			'Exhale out'
		],
		mistakes: [
			'Arching the low back',
			'Holding the breath',
			'Moving both limbs too far too fast'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Set up for dead',
				detail: 'Lie on your back; arms to the ceiling, knees over hips.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Brace',
				title: 'Brace so the low back stays quiet.',
				detail: 'Brace so the low back stays quiet.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Extend',
				title: 'Extend opposite arm and leg toward the f',
				detail: 'Extend opposite arm and leg toward the floor.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Control',
				title: 'Stop before the back arches.',
				detail: 'Stop before the back arches.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Return',
				title: 'Return to the start position.',
				detail: 'Return to the start position.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Switch',
				title: 'Alternate sides with control.',
				detail: 'Alternate sides with control.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'cat_cow',
		name: 'Cat Cow',
		tagline: 'Spinal mobility flow',
		level: 'Beginner',
		reps: '6–10 cycles',
		file: 'models/exercises/Cat_Cow.fbx',
		muscles: [ 'Spine', 'Core', 'Shoulders' ],
		summary: 'On all fours, alternate arching and rounding the spine with the breath to wake up mobility.',
		balance: [
			'Hands under shoulders, knees under hips.',
			'Move segment by segment through the spine.',
			'Match breath to motion.',
			'Keep shoulders away from the ears.'
		],
		steps: [
			'Start on all fours in a neutral spine.',
			'Inhale into Cow — lift the chest and sit bones, soft belly.',
			'Exhale into Cat — round the back, tuck the pelvis, chin soft.',
			'Flow smoothly between the two shapes.',
			'Keep wrists stacked; do not dump into the shoulders.',
			'Finish in neutral.'
		],
		cues: [
			'Breath leads',
			'Move the whole spine',
			'Soft neck',
			'Quiet shoulders'
		],
		mistakes: [
			'Only moving the neck',
			'Locking the elbows hard',
			'Rushing without breath'
		],
		guide: [
			{
				focus: 'Neutral',
				title: 'Set up for cat',
				detail: 'Start on all fours in a neutral spine.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Cow',
				title: 'Inhale into Cow — lift the chest and sit',
				detail: 'Inhale into Cow — lift the chest and sit bones, soft belly.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Cat',
				title: 'Exhale into Cat — round the back, tuck t',
				detail: 'Exhale into Cat — round the back, tuck the pelvis, chin soft.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Flow',
				title: 'Flow smoothly between the two shapes.',
				detail: 'Flow smoothly between the two shapes.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Shoulders',
				title: 'Keep wrists stacked; do not dump into th',
				detail: 'Keep wrists stacked; do not dump into the shoulders.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Finish',
				title: 'Finish in neutral.',
				detail: 'Finish in neutral.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'sit_to_stand',
		name: 'Sit to Stand',
		tagline: 'Functional squat pattern',
		level: 'Beginner',
		reps: '8–12 reps',
		file: 'models/exercises/Sit_To_Stand.fbx',
		muscles: [ 'Quads', 'Glutes', 'Core' ],
		summary: 'Stand up from a seat without using momentum, then sit back with control — everyday strength.',
		balance: [
			'Feet flat under knees.',
			'Chest tall as you rise.',
			'Weight through mid-foot / heels.',
			'Hands free or light assistance only if needed.'
		],
		steps: [
			'Sit tall near the edge of a seat.',
			'Plant feet; lean slightly forward from the hips.',
			'Drive through the floor to stand fully.',
			'Pause tall at the top.',
			'Push hips back and sit with control.',
			'Lightly tap the seat and repeat.'
		],
		cues: [
			'Nose over toes to stand',
			'Drive the floor',
			'Tall finish',
			'Soft sit'
		],
		mistakes: [
			'Plopping onto the seat',
			'Knees caving in',
			'Using momentum from the arms'
		],
		guide: [
			{
				focus: 'Sit',
				title: 'Set up for sit',
				detail: 'Sit tall near the edge of a seat.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Lean',
				title: 'Plant and lean',
				detail: 'Plant feet; lean slightly forward from the hips.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Stand',
				title: 'Drive through the floor to stand fully.',
				detail: 'Drive through the floor to stand fully.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Tall',
				title: 'Pause tall at the top.',
				detail: 'Pause tall at the top.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Sit back',
				title: 'Push hips back and sit with control.',
				detail: 'Push hips back and sit with control.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Control',
				title: 'Lightly tap the seat and repeat.',
				detail: 'Lightly tap the seat and repeat.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'worlds_greatest_stretch',
		name: 'World\'s Greatest Stretch',
		tagline: 'Full-body mobility sequence',
		level: 'Beginner+',
		reps: '4–6 / side',
		file: 'models/exercises/Worlds_Greatest_Stretch.fbx',
		muscles: [ 'Hips', 'Thoracic spine', 'Hamstrings', 'Shoulders' ],
		summary: 'A flowing lunge + twist + hamstring stretch used to open hips and mid-back before training.',
		balance: [
			'Long lunge stance with front foot flat.',
			'Back knee soft or down for support.',
			'Rotate through the mid-back, not the low back.',
			'Move slowly — this is mobility, not speed work.'
		],
		steps: [
			'Step into a long lunge with hands on the floor.',
			'Drop the back knee if needed for balance.',
			'Reach the inside arm to the ceiling and rotate open.',
			'Return the hand down; optionally elbow toward the floor.',
			'Straighten the front leg for a hamstring stretch.',
			'Step forward and switch sides.'
		],
		cues: [
			'Long lunge',
			'Rotate the chest',
			'Soft breath',
			'Switch with control'
		],
		mistakes: [
			'Collapsing the front arch',
			'Twisting only the neck',
			'Rushing through positions'
		],
		guide: [
			{
				focus: 'Lunge',
				title: 'Set up for world\'s',
				detail: 'Step into a long lunge with hands on the floor.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Plant',
				title: 'Drop the back knee if needed for balance',
				detail: 'Drop the back knee if needed for balance.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Rotate',
				title: 'Reach the inside arm to the ceiling and ',
				detail: 'Reach the inside arm to the ceiling and rotate open.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Open',
				title: 'Return the hand down; optionally elbow t',
				detail: 'Return the hand down; optionally elbow toward the floor.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Hamstring',
				title: 'Straighten the front leg for a hamstring',
				detail: 'Straighten the front leg for a hamstring stretch.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Switch',
				title: 'Step forward and switch sides.',
				detail: 'Step forward and switch sides.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'seated_row',
		name: 'Seated Row',
		tagline: 'Machine / cable horizontal pull',
		level: 'Beginner+',
		reps: '8–12 reps',
		file: 'models/exercises/Seated_Row.fbx',
		muscles: [ 'Lats', 'Rhomboids', 'Biceps', 'Rear delts' ],
		summary: 'Sit tall and pull handles toward the ribs while squeezing the shoulder blades — a controlled horizontal pull.',
		balance: [
			'Sit tall; feet planted.',
			'Shoulders packed before the pull.',
			'Elbows drive back beside the ribs.',
			'Do not lean excessively to yank the weight.'
		],
		steps: [
			'Sit with a long spine and arms extended.',
			'Brace lightly through the core.',
			'Pull elbows back toward the hips.',
			'Squeeze the mid-back at the end range.',
			'Extend arms with control.',
			'Repeat without bouncing the torso.'
		],
		cues: [
			'Tall sit',
			'Elbows back',
			'Squeeze blades',
			'Control out'
		],
		mistakes: [
			'Rounding the upper back',
			'Using momentum',
			'Shrugging every rep'
		],
		guide: [
			{
				focus: 'Sit',
				title: 'Set up for seated',
				detail: 'Sit with a long spine and arms extended.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Reach',
				title: 'Brace lightly through the core.',
				detail: 'Brace lightly through the core.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Pull',
				title: 'Pull elbows back toward the hips.',
				detail: 'Pull elbows back toward the hips.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Squeeze',
				title: 'Squeeze the mid-back at the end range.',
				detail: 'Squeeze the mid-back at the end range.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Extend',
				title: 'Extend arms with control.',
				detail: 'Extend arms with control.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Breath',
				title: 'Repeat without bouncing the torso.',
				detail: 'Repeat without bouncing the torso.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'seated_shoulder_press',
		name: 'Seated Shoulder Press',
		tagline: 'Supported overhead press',
		level: 'Beginner+',
		reps: '8–12 reps',
		file: 'models/exercises/Seated_Shoulder_Press.fbx',
		muscles: [ 'Shoulders', 'Triceps', 'Upper back' ],
		summary: 'From a supported seat, press overhead to lockout while keeping ribs down and head neutral.',
		balance: [
			'Back supported; feet planted.',
			'Wrists stacked over elbows.',
			'Ribs quiet against the pad.',
			'Full lockout without shrugging into the ears.'
		],
		steps: [
			'Start with hands at shoulder height.',
			'Brace and keep the head neutral.',
			'Press to full overhead lockout.',
			'Pause briefly without shrugging.',
			'Lower to the shoulders with control.',
			'Reset before the next press.'
		],
		cues: [
			'Press up',
			'Ribs down',
			'Lockout tall',
			'Soft lower'
		],
		mistakes: [
			'Flaring the ribs',
			'Partial lockouts',
			'Bouncing out of the bottom'
		],
		guide: [
			{
				focus: 'Setup',
				title: 'Set up for seated',
				detail: 'Start with hands at shoulder height.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Brace',
				title: 'Brace and keep the head neutral.',
				detail: 'Brace and keep the head neutral.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Press',
				title: 'Press to full overhead lockout.',
				detail: 'Press to full overhead lockout.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Lockout',
				title: 'Pause briefly without shrugging.',
				detail: 'Pause briefly without shrugging.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Lower',
				title: 'Lower to the shoulders with control.',
				detail: 'Lower to the shoulders with control.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Reset',
				title: 'Reset before the next press.',
				detail: 'Reset before the next press.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	},
	{
		id: 'chest_press',
		name: 'Chest Press Machine',
		tagline: 'Supported horizontal press',
		level: 'Beginner',
		reps: '8–12 reps',
		file: 'models/exercises/Chest_Press.fbx',
		muscles: [ 'Chest', 'Shoulders', 'Triceps' ],
		summary: 'From a machine seat, press the handles forward until arms extend, then return with control.',
		balance: [
			'Back against the pad; feet planted.',
			'Handles start near mid-chest height.',
			'Shoulders stay down and packed.',
			'Do not lock elbows aggressively.'
		],
		steps: [
			'Sit tall with handles at chest level.',
			'Brace and keep shoulder blades lightly set.',
			'Press handles forward to nearly full extension.',
			'Pause without losing shoulder position.',
			'Return until elbows bend under control.',
			'Repeat smooth reps.'
		],
		cues: [
			'Pad contact',
			'Press forward',
			'Soft lockout',
			'Control return'
		],
		mistakes: [
			'Shrugging the shoulders',
			'Bouncing the stack',
			'Flaring elbows excessively'
		],
		guide: [
			{
				focus: 'Sit',
				title: 'Set up for chest',
				detail: 'Sit tall with handles at chest level.',
				t: 0.08,
				camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
			},
			{
				focus: 'Set',
				title: 'Brace and keep shoulder blades lightly s',
				detail: 'Brace and keep shoulder blades lightly set.',
				t: 0.22,
				camera: { pos: [ -1.7, 1.1, 2.8 ], target: [ 0, 0.75, 0 ] }
			},
			{
				focus: 'Press',
				title: 'Press handles forward to nearly full ext',
				detail: 'Press handles forward to nearly full extension.',
				t: 0.38,
				camera: { pos: [ -1.6, 1.0, 2.7 ], target: [ 0, 0.7, 0 ] }
			},
			{
				focus: 'Extend',
				title: 'Pause without losing shoulder position.',
				detail: 'Pause without losing shoulder position.',
				t: 0.55,
				camera: { pos: [ -1.8, 1.15, 2.9 ], target: [ 0, 0.85, 0 ] }
			},
			{
				focus: 'Return',
				title: 'Return until elbows bend under control.',
				detail: 'Return until elbows bend under control.',
				t: 0.72,
				camera: { pos: [ -1.55, 1.25, 3.0 ], target: [ 0, 0.9, 0 ] }
			},
			{
				focus: 'Breath',
				title: 'Repeat smooth reps.',
				detail: 'Repeat smooth reps.',
				t: 0.9,
				camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
			}
		]
	}
];

export function getExercise( id ) {

	// Alias used by TacTech map (sit_ups) → catalog id (situps)
	if ( id === 'sit_ups' ) id = 'situps';
	return EXERCISES.find( ( item ) => item.id === id ) || null;

}
