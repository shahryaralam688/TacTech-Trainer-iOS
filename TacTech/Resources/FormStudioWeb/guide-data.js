/**
 * On-body guide markers + camera focus for each exercise step.
 * Bones use Mixamo names (mixamorig:*).
 */

/** Pulled-back views so full body stays readable; screenLift pushes body above caption bar */
export const GUIDE_VIEWS = {
	full: { bone: 'mixamorig:Hips', distance: 3.6, yaw: -0.5, pitch: 0.18, screenLift: 0.45 },
	face: { bone: 'mixamorig:Head', distance: 1.85, yaw: -0.3, pitch: 0.05, screenLift: 0.2, bodyMix: 0.55 },
	hands: { bone: 'mixamorig:LeftHand', distance: 2.6, yaw: -0.7, pitch: 0.28, screenLift: 0.55, bodyMix: 0.55 },
	legs: { bone: 'mixamorig:LeftUpLeg', distance: 2.8, yaw: -0.55, pitch: 0.32, screenLift: 0.65, bodyMix: 0.5 },
	spine: { bone: 'mixamorig:Spine1', distance: 3.0, yaw: -0.45, pitch: 0.12, screenLift: 0.4, bodyMix: 0.4 },
	chest: { bone: 'mixamorig:Spine2', distance: 2.9, yaw: -0.4, pitch: 0.14, screenLift: 0.4, bodyMix: 0.45 },
	feet: { bone: 'mixamorig:LeftFoot', distance: 2.7, yaw: -0.6, pitch: 0.38, screenLift: 0.7, bodyMix: 0.55 }
};

/** Enrich built-in exercise guides with body markers */
export function enrichGuide( ex ) {

	const packs = GUIDE_PACKS[ ex.id ];
	if ( ! packs || ! ex.guide ) return ex.guide;

	return ex.guide.map( ( step, i ) => ( {
		...step,
		...( packs[ i ] || {} )
	} ) );

}

const GUIDE_PACKS = {
	push_up: [
		{
			view: 'hands',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftHand', label: 'Left hand', tip: 'Flat on floor · under shoulder · fingers slightly out' },
				{ bone: 'mixamorig:RightHand', label: 'Right hand', tip: 'Same angle · wrist stacks under shoulder' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Left leg', tip: 'Long & active · do not bend soft' },
				{ bone: 'mixamorig:RightUpLeg', label: 'Right leg', tip: 'Hip-width or together · squeeze quads' },
				{ bone: 'mixamorig:LeftFoot', label: 'Feet', tip: 'Toes plant · heels slightly lifted OK' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Backbone', tip: 'One straight rail · head → hips → heels' },
				{ bone: 'mixamorig:Hips', label: 'Hips', tip: 'Neither sag nor pike · brace glutes' },
				{ bone: 'mixamorig:Spine2', label: 'Core brace', tip: 'Ribs quiet · belly lightly drawn in' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Chest', tip: 'Lower toward floor · chest leads the move' },
				{ bone: 'mixamorig:LeftForeArm', label: 'Elbow ~45°', tip: 'Not flared wide · track back ~45°' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Bottom', tip: 'Pause just above floor · body still a plank' },
				{ bone: 'mixamorig:Head', label: 'Neck', tip: 'Neutral · look slightly ahead on floor' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Breath', tip: 'Exhale as you press up · inhale on the way down' },
				{ bone: 'mixamorig:LeftArm', label: 'Press', tip: 'Push floor away · arms extend without collapse' }
			]
		}
	],
	air_squat: [
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Left foot', tip: 'Shoulder-width · toes slightly out' },
				{ bone: 'mixamorig:RightFoot', label: 'Right foot', tip: 'Weight mid-foot / heels · not only toes' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Hips back', tip: 'Sit back first · like to a chair' },
				{ bone: 'mixamorig:Spine2', label: 'Chest tall', tip: 'Do not fold forward as hips go back' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftLeg', label: 'Knee track', tip: 'Knee follows toes · no cave-in' },
				{ bone: 'mixamorig:RightLeg', label: 'Knee track', tip: 'Same path · keep alignment' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Depth', tip: 'Thighs near parallel · heels stay down' },
				{ bone: 'mixamorig:LeftFoot', label: 'Heels', tip: 'Planted · do not rise onto toes' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine long', tip: 'Neutral back · avoid rounding' },
				{ bone: 'mixamorig:Head', label: 'Eyes forward', tip: 'Head follows spine · not looking down hard' }
			]
		},
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Stand tall', tip: 'Drive floor away · squeeze glutes at top' },
				{ bone: 'mixamorig:Head', label: 'Breath', tip: 'Exhale up · inhale down' }
			]
		}
	],
	jumping_jacks: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Ready', tip: 'Feet together · soft knees · arms by sides' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Open legs', tip: 'Jump out to shoulder width' },
				{ bone: 'mixamorig:LeftFoot', label: 'Soft land', tip: 'Balls of feet first · light impact' }
			]
		},
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftHand', label: 'Arms up', tip: 'Same beat as feet · finish overhead' },
				{ bone: 'mixamorig:RightHand', label: 'Arms up', tip: 'Reach high · no lazy range' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftLeg', label: 'Soft knees', tip: 'Never lock on landing' },
				{ bone: 'mixamorig:RightLeg', label: 'Soft knees', tip: 'Springy · not stomping' }
			]
		},
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Close', tip: 'Feet together + arms down · one rhythm' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Breath', tip: 'Steady breathing · stay tall through torso' }
			]
		}
	],
	plank: [
		{
			view: 'hands',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftHand', label: 'Base', tip: 'Under shoulders · push floor away' },
				{ bone: 'mixamorig:RightHand', label: 'Base', tip: 'Active shoulders · no shrug to ears' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Leg line', tip: 'Long legs · heels in the plank rail' },
				{ bone: 'mixamorig:RightFoot', label: 'Feet', tip: 'Step back until body is one line' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Hips', tip: 'Not up · not down · squeeze glutes' },
				{ bone: 'mixamorig:Spine', label: 'Backbone', tip: 'Straight rail head to heels' }
			]
		},
		{
			view: 'chest',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core armor', tip: 'Brace like a tap on the stomach' },
				{ bone: 'mixamorig:Spine1', label: 'Ribs', tip: 'Quiet ribs · full-body tension' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Head / neck', tip: 'Neutral · look just ahead on the floor' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Breath', tip: 'Short steady breaths · do not hold air' }
			]
		}
	],
	situps: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Back on floor · knees bent · feet planted' },
				{ bone: 'mixamorig:Spine', label: 'Low back', tip: 'Starts in contact with the floor' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftHand', label: 'Hands', tip: 'Temples or crossed on chest · never yank head' },
				{ bone: 'mixamorig:Head', label: 'Chin', tip: 'Slight tuck · fist-distance from chest' }
			]
		},
		{
			view: 'chest',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Abs start', tip: 'Curl ribs toward hips · not head first' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Top', tip: 'Brief pause · no swing or twist' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Lower slow', tip: 'Control the way down · shoulders kiss floor' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Breath + neck', tip: 'Exhale up · inhale down · protect the neck' }
			]
		}
	],
	burpee: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Stand ready', tip: 'Soft knees · next: squat → plank → jump' }
			]
		},
		{
			view: 'hands',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftHand', label: 'Plant hands', tip: 'Squat down · hands under shoulders' },
				{ bone: 'mixamorig:RightHand', label: 'Plant hands', tip: 'Strong floor contact before kick-back' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Plank line', tip: 'Feet back · backbone straight before push-up' },
				{ bone: 'mixamorig:Hips', label: 'Hips', tip: 'Level · no collapse' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Chest', tip: 'Optional push-up · keep hips level' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Feet forward', tip: 'Jump/step toward hands under control' },
				{ bone: 'mixamorig:RightFoot', label: 'Feet forward', tip: 'Ready to stand tall' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Jump + breath', tip: 'Explode up · land soft knees · exhale on jump' },
				{ bone: 'mixamorig:LeftHand', label: 'Arms', tip: 'Reach overhead on the jump' }
			]
		}
	],
	walking_lunge: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Long step' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Tall torso' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Knee tracks toes' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Controlled depth' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Long step' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Tall torso' }
			]
		}
	],
	romanian_deadlift: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Hips back' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Spine long' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Bar close' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Stand tall' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Hips back' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Spine long' }
			]
		}
	],
	hip_hinge: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Hips back first' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Soft knees' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Long spine' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Stand by driving hips' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Hips back first' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Soft knees' }
			]
		}
	],
	overhead_press: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Ribs down' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Press up, not forward' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Lock out tall' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Control the descent' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Ribs down' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Press up, not forward' }
			]
		}
	],
	bent_over_row: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Torso still' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Elbows to hips' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Squeeze the back' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Full hang between reps' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Torso still' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Elbows to hips' }
			]
		}
	],
	glute_bridge: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Drive heels' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Ribs quiet' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Squeeze glutes' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Controlled lower' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Drive heels' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Ribs quiet' }
			]
		}
	],
	bird_dog: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Long reach' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Hips level' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Quiet torso' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Slow returns' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Long reach' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Hips level' }
			]
		}
	],
	dead_bug: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Back flat' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Slow limbs' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Ribs down' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Exhale out' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Back flat' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Slow limbs' }
			]
		}
	],
	cat_cow: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Breath leads' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Move the whole spine' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Soft neck' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Quiet shoulders' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Breath leads' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Move the whole spine' }
			]
		}
	],
	sit_to_stand: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Seat edge', tip: 'Sit tall near the edge · ready to lean' },
				{ bone: 'mixamorig:Spine2', label: 'Chest', tip: 'Tall torso · do not collapse into the seat' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Left foot', tip: 'Flat under knee · mid-foot / heel ready' },
				{ bone: 'mixamorig:RightFoot', label: 'Right foot', tip: 'Same plant · avoid tip-toeing up' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Drive', tip: 'Push the floor away · stand without a hop' },
				{ bone: 'mixamorig:LeftUpLeg', label: 'Quads', tip: 'Knees track over toes · no cave-in' },
				{ bone: 'mixamorig:RightUpLeg', label: 'Quads', tip: 'Even push · hips rise with the chest' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Tall finish', tip: 'Stand fully · ribs over hips' },
				{ bone: 'mixamorig:Head', label: 'Head', tip: 'Neutral · look ahead not at the floor' }
			]
		},
		{
			view: 'legs',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Hips back', tip: 'Sit by pushing hips back · control the drop' },
				{ bone: 'mixamorig:Spine2', label: 'Chest', tip: 'Stay tall as you lower · no soft collapse' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Soft sit', tip: 'Lightly tap the seat · then rise again' },
				{ bone: 'mixamorig:Head', label: 'Breath', tip: 'Exhale to stand · inhale as you sit' }
			]
		}
	],
	worlds_greatest_stretch: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Long lunge' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Rotate the chest' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Soft breath' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Switch with control' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Long lunge' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Rotate the chest' }
			]
		}
	],
	seated_row: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Tall sit' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Elbows back' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Squeeze blades' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Control out' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Tall sit' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Elbows back' }
			]
		}
	],
	seated_shoulder_press: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Press up' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Ribs down' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Lockout tall' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Soft lower' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Press up' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Ribs down' }
			]
		}
	],
	chest_press: [
		{
			view: 'full',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Hips', label: 'Setup', tip: 'Pad contact' }
			]
		},
		{
			view: 'feet',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:LeftFoot', label: 'Base', tip: 'Press forward' }
			]
		},
		{
			view: 'legs',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:LeftUpLeg', label: 'Legs', tip: 'Soft lockout' }
			]
		},
		{
			view: 'spine',
			showSkeleton: true,
			markers: [
				{ bone: 'mixamorig:Spine', label: 'Spine', tip: 'Control return' }
			]
		},
		{
			view: 'chest',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Spine2', label: 'Core', tip: 'Pad contact' }
			]
		},
		{
			view: 'face',
			showSkeleton: false,
			markers: [
				{ bone: 'mixamorig:Head', label: 'Finish', tip: 'Press forward' }
			]
		}
	]
};
