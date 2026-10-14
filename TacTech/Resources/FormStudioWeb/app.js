import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
import { CSS2DRenderer, CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js';
import { EXERCISES, getExercise as getCatalogExercise } from './exercises.js';
import { GUIDE_VIEWS, enrichGuide } from './guide-data.js';

/** Runtime overrides from native (CDN clip URL, API guide/cues, synthetic catalog rows). */
const runtimeOverrides = new Map();

function getExercise( id ) {

	if ( id === 'sit_ups' ) id = 'situps';
	return runtimeOverrides.get( id ) || getCatalogExercise( id );

}

function defaultRuntimeGuide() {

	return [
		{
			focus: 'Setup',
			title: 'Start position',
			detail: 'Watch the coach set up the movement.',
			t: 0.08,
			camera: { pos: [ -1.5, 1.4, 3.0 ], target: [ 0, 1.0, 0 ] }
		},
		{
			focus: 'Mid',
			title: 'Key position',
			detail: 'Match this shape — control the path.',
			t: 0.45,
			camera: { pos: [ -1.6, 1.1, 2.8 ], target: [ 0, 0.8, 0 ] }
		},
		{
			focus: 'Finish',
			title: 'Finish tall',
			detail: 'Complete the rep with control.',
			t: 0.88,
			camera: { pos: [ -1.5, 1.4, 3.1 ], target: [ 0, 1.05, 0 ] }
		}
	];

}

/**
 * Flow: library → instruct → countdown → on-body GUIDE → full workout loop
 * Guide markers attach to Mixamo bones; camera frames that body region centered.
 */

const GUIDE_HOLD_MS = 3200;
const GUIDE_SCRUB_SPEED = 0.55; // clip seconds per real second while moving between cues

const state = {
	screen: 'library',
	selectedId: null,
	exerciseAction: null,
	idleAction: null,
	cueIndex: 0,
	cueTimer: null,
	countdownTimer: null,
	countdownGoTimer: null,
	guideAutoTimer: null,
	guideIndex: 0,
	guidePlaying: true,
	paused: false,
	savedTimeScale: 1,
	optionsOpen: false,
	characterCenter: new THREE.Vector3( 0, 1, 0 ),
	camFrom: new THREE.Vector3(),
	camTo: new THREE.Vector3(),
	targetFrom: new THREE.Vector3(),
	targetTo: new THREE.Vector3(),
	camTween: 1,
	workoutReframe: 0,
	userOrbiting: false,
	/** Once user drags the orbit, keep their angle — never auto-snap back */
	userCameraLock: false,
	guideSeeking: false,
	guideSeekTarget: 0,
	guideSeekView: 'full',
	guideHoldTimer: null
};

let scene, renderer, labelRenderer, camera, controls, mixer, clock, model, skeleton;
const exerciseClips = new Map();
const fbxLoader = new FBXLoader();
const activeMarkers = [];
const _boneWorld = new THREE.Vector3();
const _box = new THREE.Box3();
const _size = new THREE.Vector3();
const _center = new THREE.Vector3();

const els = {
	libraryScreen: document.getElementById( 'libraryScreen' ),
	instructScreen: document.getElementById( 'instructScreen' ),
	sessionDock: document.getElementById( 'sessionDock' ),
	guideDock: document.getElementById( 'guideDock' ),
	countdownOverlay: document.getElementById( 'countdownOverlay' ),
	countdownNumber: document.getElementById( 'countdownNumber' ),
	exerciseGrid: document.getElementById( 'exerciseGrid' ),
	statusLabel: document.getElementById( 'statusLabel' ),
	liveCue: document.getElementById( 'liveCue' ),
	workoutTitle: document.getElementById( 'workoutTitle' ),
	panel: document.getElementById( 'workoutPanel' ),
	loading: document.getElementById( 'loadingBadge' ),
	pauseBtn: document.getElementById( 'pauseBtn' ),
	settingsToggle: document.getElementById( 'settingsToggle' ),
	speedSlider: document.getElementById( 'speedSlider' ),
	speedValue: document.getElementById( 'speedValue' ),
	guideFocus: document.getElementById( 'guideFocus' ),
	guideCount: document.getElementById( 'guideCount' ),
	guideProgress: document.getElementById( 'guideProgress' ),
	guideTitle: document.getElementById( 'guideTitle' ),
	guideDetail: document.getElementById( 'guideDetail' ),
	guidePoints: document.getElementById( 'guidePoints' ),
	guideNextBtn: document.getElementById( 'guideNextBtn' ),
	guideBackBtn: document.getElementById( 'guideBackBtn' ),
	guidePlayBtn: document.getElementById( 'guidePlayBtn' )
};

initScene();
buildLibrary();
wireChrome();

async function initScene() {

	clock = new THREE.Clock();
	const container = document.getElementById( 'container' );

	scene = new THREE.Scene();
	scene.background = new THREE.Color( 0xF2F3F6 );
	scene.fog = new THREE.Fog( 0xF2F3F6, 18, 48 );

	scene.add( new THREE.HemisphereLight( 0xffffff, 0xd8dce4, 1.55 ) );
	const key = new THREE.DirectionalLight( 0xffffff, 2.1 );
	key.position.set( 3.2, 9, 6 );
	key.castShadow = true;
	key.shadow.mapSize.set( 1024, 1024 );
	scene.add( key );
	scene.add( new THREE.DirectionalLight( 0xb9d4f0, 0.55 ).translateX( - 4 ).translateY( 3 ).translateZ( - 2 ) );
	const rim = new THREE.DirectionalLight( 0xf38002, 0.28 );
	rim.position.set( 0, 2, - 4 );
	scene.add( rim );

	const ground = new THREE.Mesh(
		new THREE.CircleGeometry( 8, 64 ),
		new THREE.MeshStandardMaterial( { color: 0xe8eaef, roughness: 0.95, metalness: 0.02 } )
	);
	ground.rotation.x = - Math.PI / 2;
	ground.receiveShadow = true;
	scene.add( ground );

	const ring = new THREE.Mesh(
		new THREE.RingGeometry( 1.15, 1.22, 64 ),
		new THREE.MeshBasicMaterial( { color: 0xF38002, transparent: true, opacity: 0.35 } )
	);
	ring.rotation.x = - Math.PI / 2;
	ring.position.y = 0.012;
	scene.add( ring );

	renderer = new THREE.WebGLRenderer( { antialias: true } );
	renderer.setPixelRatio( Math.min( window.devicePixelRatio, 2 ) );
	renderer.setSize( window.innerWidth, window.innerHeight );
	renderer.shadowMap.enabled = true;
	container.appendChild( renderer.domElement );

	labelRenderer = new CSS2DRenderer();
	labelRenderer.setSize( window.innerWidth, window.innerHeight );
	labelRenderer.domElement.className = 'label-layer';
	document.body.appendChild( labelRenderer.domElement );

	camera = new THREE.PerspectiveCamera( 40, window.innerWidth / window.innerHeight, 0.1, 100 );

	controls = new OrbitControls( camera, renderer.domElement );
	controls.enablePan = false;
	controls.enableDamping = true;
	controls.dampingFactor = 0.08;
	controls.minDistance = 1.2;
	controls.maxDistance = 8;
	controls.maxPolarAngle = Math.PI * 0.49;
	controls.minPolarAngle = 0.15;
	controls.addEventListener( 'start', () => {

		state.userOrbiting = true;
		state.userCameraLock = true; // keep whatever angle the user leaves
		state.camTween = 1; // cancel any in-flight camera tween

	} );
	controls.addEventListener( 'end', () => {

		state.userOrbiting = false;
		// Do NOT auto-reframe — stay on the angle the user chose

	} );

	window.addEventListener( 'resize', onResize );

	els.loading.textContent = 'Loading character…';

	model = await fbxLoader.loadAsync( 'models/character/X_Bot.fbx' );
	model.scale.setScalar( 0.01 );
	model.traverse( ( child ) => {

		if ( child.isMesh ) {

			child.castShadow = true;
			child.receiveShadow = true;

		}

	} );
	scene.add( model );
	groundCharacter();
	refreshCharacterCenter();
	frameView( 'full' );

	skeleton = new THREE.SkeletonHelper( model );
	skeleton.visible = false;
	skeleton.material.linewidth = 2;
	scene.add( skeleton );

	mixer = new THREE.AnimationMixer( model );

	els.loading.textContent = 'Loading exercises…';
	await preloadClips();

	if ( exerciseClips.has( '__idle__' ) ) {

		state.idleAction = mixer.clipAction( exerciseClips.get( '__idle__' ) );
		state.idleAction.play();

	}

	// Re-center after idle binds
	mixer.update( 0 );
	groundCharacter();
	refreshCharacterCenter();
	frameView( 'full' );

	els.loading.classList.add( 'hidden' );
	els.statusLabel.textContent = 'Select a form';

	// TacTech / deep-link: open exercise after clips are ready.
	consumePendingExercise();

	renderer.setAnimationLoop( () => {

		const dt = clock.getDelta();
		if ( mixer ) mixer.update( dt );
		updateGuideSeek();
		updateCameraTween( dt );

		// Soft distance-only keep-in-frame while playing — never if user chose an angle
		if (
			state.screen === 'workout'
			&& ! state.paused
			&& ! state.userOrbiting
			&& ! state.userCameraLock
			&& state.camTween >= 1
		) {

			state.workoutReframe += dt;
			if ( state.workoutReframe > 0.45 ) {

				state.workoutReframe = 0;
				frameGuideBody( false );

			}

		}

		controls.update();
		renderer.render( scene, camera );
		labelRenderer.render( scene, camera );

	} );

}

function getStageSize() {

	const el = document.getElementById( 'container' );
	const w = el?.clientWidth || window.innerWidth;
	const h = el?.clientHeight || window.innerHeight;
	return { w: Math.max( 1, w ), h: Math.max( 1, h ) };

}

function syncStageSize() {

	const { w, h } = getStageSize();
	camera.aspect = w / h;
	camera.updateProjectionMatrix();
	renderer.setSize( w, h, false );
	renderer.domElement.style.width = '100%';
	renderer.domElement.style.height = '100%';
	labelRenderer.setSize( w, h );

}

function onResize() {

	syncStageSize();
	if ( state.screen === 'guide' || state.screen === 'workout' ) frameGuideBody( false );
	else frameView( 'full', false );

}

function groundCharacter() {

	model.updateMatrixWorld( true );
	_box.setFromObject( model );
	if ( Number.isFinite( _box.min.y ) ) model.position.y -= _box.min.y;

}

function refreshCharacterCenter() {

	model.updateMatrixWorld( true );
	_box.setFromObject( model );
	_box.getCenter( state.characterCenter );

}

function getBone( name ) {

	return model?.getObjectByName( name ) || null;

}

/**
 * GUIDE framing: always fit the FULL posed body inside the top stage.
 * Floor moves (push-up/plank) use a clear SIDE view so the whole line is readable.
 */
function frameGuideBody( animate = true, viewKey = 'full' ) {

	syncStageSize();
	model.updateMatrixWorld( true );
	_box.setFromObject( model );
	_box.getCenter( _center );
	_box.getSize( _size );

	const maxDim = Math.max( _size.x, _size.y, _size.z, 0.9 );
	const { h } = getStageSize();
	const fov = THREE.MathUtils.degToRad( camera.fov );
	let dist = ( maxDim * 0.55 ) / Math.tan( fov * 0.5 );
	dist *= 1.7; // extra padding so animated limbs never clip
	if ( h < 420 ) dist *= 1.15;

	const isHorizontal = _size.y < Math.max( _size.x, _size.z ) * 0.8;
	const view = GUIDE_VIEWS[ viewKey ] || GUIDE_VIEWS.full;
	const nextTarget = _center.clone();

	let nextCam;
	if ( isHorizontal ) {

		// Side profile — full plank / push-up line visible in stage
		const side = Math.max( dist, maxDim * 2.1 );
		nextCam = new THREE.Vector3(
			_center.x + side,
			_center.y + Math.max( 0.25, _size.y * 0.35 ),
			_center.z + side * 0.12
		);

	} else {

		const yaw = view.yaw ?? - 0.5;
		const pitch = Math.min( view.pitch ?? 0.16, 0.22 );
		const cp = Math.cos( pitch );
		nextCam = new THREE.Vector3(
			_center.x + Math.sin( yaw ) * dist * cp,
			_center.y + Math.sin( pitch ) * dist + 0.15,
			_center.z + Math.cos( yaw ) * dist * cp
		);

	}

	applyCamera( nextCam, nextTarget, animate );

}

function frameView( viewKey = 'full', animate = false ) {

	if ( state.screen === 'guide' ) {

		frameGuideBody( animate, viewKey );
		return;

	}

	syncStageSize();
	const view = GUIDE_VIEWS[ viewKey ] || GUIDE_VIEWS.full;
	refreshCharacterCenter();

	const bone = getBone( view.bone );
	if ( bone ) bone.getWorldPosition( _center );
	else _center.copy( state.characterCenter );
	_center.lerp( state.characterCenter, view.bodyMix ?? 0.45 );

	const dist = view.distance ?? 3.4;
	const yaw = view.yaw ?? - 0.5;
	const pitch = view.pitch ?? 0.18;
	const cp = Math.cos( pitch );

	const nextTarget = _center.clone();
	const nextCam = new THREE.Vector3(
		_center.x + Math.sin( yaw ) * dist * cp,
		_center.y + Math.sin( pitch ) * dist + 0.2,
		_center.z + Math.cos( yaw ) * dist * cp
	);

	applyCamera( nextCam, nextTarget, animate );

}

function applyCamera( nextCam, nextTarget, animate ) {

	// Respect user's orbit angle — never yank the camera back
	if ( state.userCameraLock ) return;

	if ( animate ) {

		state.camFrom.copy( camera.position );
		state.targetFrom.copy( controls.target );
		state.camTo.copy( nextCam );
		state.targetTo.copy( nextTarget );
		state.camTween = 0;

	} else {

		controls.target.copy( nextTarget );
		camera.position.copy( nextCam );
		controls.update();
		state.camTween = 1;

	}

}

function updateCameraTween( dt ) {

	if ( state.camTween >= 1 ) return;
	state.camTween = Math.min( 1, state.camTween + dt * 1.6 );
	const t = 1 - Math.pow( 1 - state.camTween, 3 );
	camera.position.lerpVectors( state.camFrom, state.camTo, t );
	controls.target.lerpVectors( state.targetFrom, state.targetTo, t );

}

function clearBodyMarkers() {

	while ( activeMarkers.length ) {

		const obj = activeMarkers.pop();
		obj.parent?.remove( obj );
		obj.element?.remove();

	}

}

/** Tiny numbered pins on bones — text stays in the caption (does not cover body) */
function showBodyMarkers( markers = [] ) {

	clearBodyMarkers();

	markers.forEach( ( m, i ) => {

		const bone = getBone( m.bone );
		if ( ! bone ) return;

		const el = document.createElement( 'div' );
		el.className = 'body-pin';
		el.textContent = String( i + 1 );

		const obj = new CSS2DObject( el );
		obj.position.set( 0, 6, 0 );
		bone.add( obj );
		activeMarkers.push( obj );

	} );

}

function fillGuideCaption( step ) {

	els.guideFocus.textContent = step.focus;
	els.guideTitle.textContent = step.title;
	els.guideDetail.textContent = step.detail;
	els.guidePoints.innerHTML = '';

	// Max 2 points — keep panel short so stage stays large
	( step.markers || [] ).slice( 0, 2 ).forEach( ( m, i ) => {

		const li = document.createElement( 'li' );
		li.innerHTML = `<span class="pin-no">${ i + 1 }</span><span><b>${ m.label }:</b> ${ m.tip }</span>`;
		els.guidePoints.appendChild( li );

	} );

}

async function preloadClips() {

	for ( const file of [ 'models/exercises/Breathing_Idle.fbx', 'models/exercises/Idle.fbx' ] ) {

		try {

			exerciseClips.set( '__idle__', await loadClip( file, 'idle' ) );
			break;

		} catch ( err ) {

			console.warn( 'Idle load failed', file, err );

		}

	}

	await Promise.all( EXERCISES.map( async ( ex ) => {

		try {

			exerciseClips.set( ex.id, await loadClip( ex.file, ex.id ) );

		} catch ( err ) {

			console.error( 'Failed to load', ex.id, err );

		}

	} ) );

}

async function loadClip( file, name ) {

	const obj = await fbxLoader.loadAsync( file );
	const clip = obj.animations[ 0 ];
	if ( ! clip ) throw new Error( `No animation in ${ file }` );
	clip.name = name;
	return clip;

}

function buildLibrary() {

	els.exerciseGrid.innerHTML = '';
	EXERCISES.forEach( ( ex, index ) => {

		const card = document.createElement( 'button' );
		card.type = 'button';
		card.className = 'exercise-card';
		card.dataset.id = ex.id;
		card.innerHTML = `
			<div class="card-top">
				<span class="card-index">${ String( index + 1 ).padStart( 2, '0' ) }</span>
				<span class="card-reps">${ ex.reps }</span>
			</div>
			<h3>${ ex.name }</h3>
			<p>${ ex.tagline }</p>
			<div class="card-tags">
				<span>${ ex.level }</span>
				${ ex.muscles.slice( 0, 2 ).map( ( m ) => `<span>${ m }</span>` ).join( '' ) }
			</div>
		`;
		card.addEventListener( 'click', () => openInstructions( ex.id ) );
		els.exerciseGrid.appendChild( card );

	} );

}

function wireChrome() {

	document.getElementById( 'backToLibrary' ).addEventListener( 'click', () => {

		if ( document.body.dataset.embedded === 'true' ) {

			closeToNative();
			return;

		}

		hardStopSession( { go: 'library' } );

	} );
	document.getElementById( 'startExerciseBtn' ).addEventListener( 'click', beginCountdown );
	document.getElementById( 'stopWorkoutBtn' ).addEventListener( 'click', () => hardStopSession( { go: 'instruct' } ) );
	document.getElementById( 'cancelCountdownBtn' ).addEventListener( 'click', () => hardStopSession( { go: 'instruct' } ) );
	document.getElementById( 'guideStopBtn' ).addEventListener( 'click', () => hardStopSession( { go: 'instruct' } ) );
	els.guideNextBtn.addEventListener( 'click', () => {

		state.guidePlaying = true;
		syncGuidePlayBtn();
		advanceGuide( 1 );

	} );
	els.guideBackBtn.addEventListener( 'click', () => {

		state.guidePlaying = true;
		syncGuidePlayBtn();
		advanceGuide( - 1 );

	} );
	els.guidePlayBtn.addEventListener( 'click', toggleGuidePlayback );
	document.getElementById( 'guideSkipBtn' ).addEventListener( 'click', finishGuideAndPlay );
	els.pauseBtn.addEventListener( 'click', togglePause );

	els.settingsToggle.addEventListener( 'click', () => {

		state.optionsOpen = ! state.optionsOpen;
		els.panel.classList.toggle( 'collapsed', ! state.optionsOpen );
		els.settingsToggle.setAttribute( 'aria-expanded', String( state.optionsOpen ) );
		els.settingsToggle.textContent = state.optionsOpen ? 'Hide' : 'Options';

	} );

	document.getElementById( 'skeletonBtn' ).addEventListener( 'click', ( e ) => {

		if ( ! skeleton ) return;
		skeleton.visible = ! skeleton.visible;
		e.currentTarget.classList.toggle( 'active', skeleton.visible );
		e.currentTarget.setAttribute( 'aria-pressed', String( skeleton.visible ) );

	} );

	els.speedSlider.addEventListener( 'input', () => applySpeed( Number( els.speedSlider.value ) ) );
	document.querySelectorAll( '[data-speed]' ).forEach( ( btn ) => {

		btn.addEventListener( 'click', () => {

			els.speedSlider.value = btn.dataset.speed;
			applySpeed( Number( btn.dataset.speed ) );

		} );

	} );

	for ( const id of [ 'libraryScreen', 'instructScreen', 'sessionDock', 'guideDock', 'countdownOverlay' ] ) {

		const node = document.getElementById( id );
		node.addEventListener( 'pointerdown', ( ev ) => ev.stopPropagation() );
		node.addEventListener( 'touchstart', ( ev ) => ev.stopPropagation(), { passive: true } );

	}

}

function applySpeed( speed ) {

	state.savedTimeScale = speed;
	els.speedValue.textContent = `${ speed.toFixed( 2 ) }×`;
	document.querySelectorAll( '.preset' ).forEach( ( btn ) => {

		btn.classList.toggle( 'active', Number( btn.dataset.speed ) === speed );

	} );
	if ( mixer && state.screen === 'workout' && ! state.paused ) mixer.timeScale = speed;

}

function togglePause() {

	if ( state.screen !== 'workout' || ! state.exerciseAction ) return;
	state.paused = ! state.paused;
	document.body.dataset.paused = String( state.paused );
	els.pauseBtn.setAttribute( 'aria-pressed', String( state.paused ) );
	els.pauseBtn.textContent = state.paused ? 'Resume' : 'Pause';

	if ( state.paused ) {

		if ( mixer ) mixer.timeScale = 0;
		clearInterval( state.cueTimer );
		els.statusLabel.textContent = 'Paused';

	} else {

		if ( mixer ) mixer.timeScale = state.savedTimeScale;
		els.statusLabel.textContent = `Live · ${ getExercise( state.selectedId )?.name || '' }`;
		startCueRotation( getExercise( state.selectedId ) );

	}

}

function showScreen( name ) {

	state.screen = name;
	els.libraryScreen.classList.toggle( 'hidden', name !== 'library' );
	els.instructScreen.classList.toggle( 'hidden', name !== 'instruct' );
	els.countdownOverlay.classList.toggle( 'hidden', name !== 'countdown' );
	els.guideDock.classList.toggle( 'hidden', name !== 'guide' );
	els.sessionDock.classList.toggle( 'hidden', name !== 'workout' );
	document.body.dataset.screen = name;
	if ( name !== 'workout' ) document.body.dataset.paused = 'false';
	if ( name !== 'guide' ) clearBodyMarkers();

	// Layout changes (split stage) — resize renderer to match container
	requestAnimationFrame( () => {

		syncStageSize();
		if ( name === 'guide' || name === 'workout' ) frameGuideBody( false );
		else frameView( 'full', false );

	} );

}

function syncSelectedCards( id ) {

	els.exerciseGrid.querySelectorAll( '.exercise-card' ).forEach( ( card ) => {

		card.classList.toggle( 'selected', card.dataset.id === id );

	} );

}

function openInstructions( id ) {

	const ex = getExercise( id );
	if ( ! ex ) return;
	state.selectedId = id;
	syncSelectedCards( id );
	document.getElementById( 'instructTitle' ).textContent = ex.name;
	document.getElementById( 'instructSummary' ).textContent = ex.summary;
	document.getElementById( 'instructMeta' ).textContent = `${ ex.level } · ${ ex.reps } · ${ ex.muscles.join( ' · ' ) }`;
	fillList( 'balanceList', ex.balance );
	fillList( 'stepsList', ex.steps, true );
	fillList( 'mistakesList', ex.mistakes );
	els.statusLabel.textContent = ex.name;
	clearBodyMarkers();
	if ( skeleton ) skeleton.visible = document.getElementById( 'skeletonBtn' ).classList.contains( 'active' );
	frameView( 'full' );
	showScreen( 'instruct' );

}

function fillList( id, items, numbered = false ) {

	const root = document.getElementById( id );
	root.innerHTML = '';
	items.forEach( ( text, i ) => {

		const li = document.createElement( 'li' );
		if ( numbered ) li.innerHTML = `<span class="num">${ i + 1 }</span><span>${ text }</span>`;
		else li.textContent = text;
		root.appendChild( li );

	} );

}

function beginCountdown() {

	const ex = getExercise( state.selectedId );
	if ( ! ex || ! exerciseClips.has( ex.id ) ) {

		els.statusLabel.textContent = 'Still loading — try again';
		return;

	}

	clearSessionTimers();
	showScreen( 'countdown' );
	els.statusLabel.textContent = 'Countdown';
	let n = 3;
	els.countdownNumber.textContent = String( n );

	state.countdownTimer = setInterval( () => {

		n -= 1;
		if ( n <= 0 ) {

			clearInterval( state.countdownTimer );
			state.countdownTimer = null;
			els.countdownNumber.textContent = 'GO';
			state.countdownGoTimer = setTimeout( () => startGuide( ex ), 320 );
			return;

		}

		els.countdownNumber.textContent = String( n );

	}, 700 );

}

function ensureExerciseAction( ex, { reset = false } = {} ) {

	const clip = exerciseClips.get( ex.id );
	const action = mixer.clipAction( clip );
	const alreadyBound = state.exerciseAction === action && action.isRunning();

	if ( state.idleAction?.isRunning() ) state.idleAction.fadeOut( 0.2 );

	action.enabled = true;
	action.setEffectiveWeight( 1 );
	action.setLoop( THREE.LoopOnce, 1 );
	action.clampWhenFinished = true;

	if ( ! alreadyBound || reset ) {

		action.reset();
		action.setEffectiveTimeScale( 1 );
		action.paused = false;
		action.play();

	}

	state.exerciseAction = action;
	return { clip, action };

}

/** Play / scrub the SAME clip between guide cue times (no pose flash). */
function updateGuideSeek() {

	if ( ! state.guideSeeking || ! state.exerciseAction ) return;

	const action = state.exerciseAction;
	const target = state.guideSeekTarget;
	const t = action.time;
	const goingForward = action.timeScale >= 0;
	const arrived = goingForward ? t >= target - 0.001 : t <= target + 0.001;

	if ( ! arrived ) return;

	action.time = target;
	action.paused = true;
	action.setEffectiveTimeScale( 1 );
	state.guideSeeking = false;
	mixer.update( 0 );
	model.updateMatrixWorld( true );
	groundCharacter();

	// Frame once when arriving — only if user has not taken camera control
	if ( ! state.userCameraLock ) {

		requestAnimationFrame( () => frameGuideBody( true, state.guideSeekView || 'full' ) );

	}

	scheduleGuideHold();

}

function scheduleGuideHold() {

	clearTimeout( state.guideHoldTimer );
	state.guideHoldTimer = null;
	if ( state.screen !== 'guide' || ! state.guidePlaying ) return;

	state.guideHoldTimer = setTimeout( () => advanceGuide( 1 ), GUIDE_HOLD_MS );

}

function seekGuideToTime( action, clip, targetNorm, viewKey ) {

	const target = Math.min( Math.max( targetNorm ?? 0.1, 0 ), 0.98 ) * clip.duration;
	const current = action.time;
	const delta = target - current;

	state.guideSeekView = viewKey || 'full';
	clearTimeout( state.guideAutoTimer );
	state.guideAutoTimer = null;
	clearTimeout( state.guideHoldTimer );
	state.guideHoldTimer = null;

	// Tiny jumps: settle instantly (still same clip, no reset flash)
	if ( Math.abs( delta ) < 0.04 ) {

		action.paused = true;
		action.time = target;
		action.setEffectiveTimeScale( 1 );
		state.guideSeeking = false;
		mixer.update( 0 );
		model.updateMatrixWorld( true );
		groundCharacter();
		if ( ! state.userCameraLock ) {

			requestAnimationFrame( () => frameGuideBody( true, state.guideSeekView ) );

		}

		scheduleGuideHold();
		return;

	}

	// Animate through the clip so limbs move into the next cue
	action.paused = false;
	action.enabled = true;
	action.setEffectiveWeight( 1 );
	action.setEffectiveTimeScale( delta >= 0 ? GUIDE_SCRUB_SPEED : - GUIDE_SCRUB_SPEED );
	state.guideSeekTarget = target;
	state.guideSeeking = true;

}

function currentGuideSteps( ex ) {

	if ( ex?._preferApiGuide && Array.isArray( ex.guide ) && ex.guide.length ) {

		return ex.guide;

	}

	return enrichGuide( ex ) || ex.guide || [];

}

function syncGuidePlayBtn() {

	els.guidePlayBtn.textContent = state.guidePlaying ? 'Pause' : 'Play';

}

function toggleGuidePlayback() {

	if ( state.screen !== 'guide' ) return;
	state.guidePlaying = ! state.guidePlaying;
	syncGuidePlayBtn();

	if ( state.guidePlaying ) {

		if ( state.guideSeeking ) return; // finish limb motion, then hold schedules next
		scheduleGuideHold();
		renderGuideProgress(
			currentGuideSteps( getExercise( state.selectedId ) ).length,
			state.guideIndex
		);

	} else {

		clearTimeout( state.guideAutoTimer );
		state.guideAutoTimer = null;
		clearTimeout( state.guideHoldTimer );
		state.guideHoldTimer = null;
		// Freeze mid-scrub if needed
		if ( state.guideSeeking && state.exerciseAction ) {

			state.exerciseAction.paused = true;
			state.exerciseAction.setEffectiveTimeScale( 1 );
			state.guideSeeking = false;

		}

		els.guideProgress.querySelectorAll( 'span.active i' ).forEach( ( el ) => {

			el.style.animation = 'none';
			el.style.width = '40%';

		} );

	}

}

function startGuide( ex ) {

	clearSessionTimers();
	state.guideIndex = 0;
	state.guidePlaying = true;
	state.userCameraLock = false;
	state.guideSeeking = false;
	syncGuidePlayBtn();
	ensureExerciseAction( ex, { reset: true } );
	if ( mixer ) mixer.timeScale = 1;
	showScreen( 'guide' );
	els.statusLabel.textContent = `Guide · ${ ex.name }`;
	showGuideStep( ex, 0, { first: true } );

}

function showGuideStep( ex, index, { first = false } = {} ) {

	const steps = currentGuideSteps( ex );
	const step = steps[ index ];
	if ( ! step ) return;

	state.guideIndex = index;
	clearTimeout( state.guideAutoTimer );
	state.guideAutoTimer = null;
	clearTimeout( state.guideHoldTimer );
	state.guideHoldTimer = null;

	const { clip, action } = ensureExerciseAction( ex, { reset: first } );

	const showBones = Boolean( step.showSkeleton );
	if ( skeleton ) {

		skeleton.visible = showBones || document.getElementById( 'skeletonBtn' ).classList.contains( 'active' );

	}

	// Tiny pins only — text is in the bottom panel (separate from 3D stage)
	showBodyMarkers( step.markers || [] );
	fillGuideCaption( step );

	els.guideCount.textContent = `${ index + 1 } / ${ steps.length }`;
	els.guideBackBtn.disabled = index === 0;
	els.guideBackBtn.style.opacity = index === 0 ? '0.45' : '1';
	els.guideNextBtn.textContent = index >= steps.length - 1 ? 'Demo' : 'Next';
	renderGuideProgress( steps.length, index );

	// Animate limbs through the clip to this cue (same model sequence)
	seekGuideToTime( action, clip, step.t ?? 0.1, step.view || 'full' );

}

function renderGuideProgress( total, activeIndex ) {

	els.guideProgress.innerHTML = '';
	for ( let i = 0; i < total; i ++ ) {

		const bar = document.createElement( 'span' );
		const fill = document.createElement( 'i' );
		bar.appendChild( fill );
		if ( i < activeIndex ) bar.classList.add( 'done' );
		if ( i === activeIndex ) bar.classList.add( 'active' );
		els.guideProgress.appendChild( bar );

	}

}

function advanceGuide( delta ) {

	const ex = getExercise( state.selectedId );
	if ( ! ex || state.screen !== 'guide' ) return;
	const steps = currentGuideSteps( ex );
	const next = state.guideIndex + delta;
	if ( next < 0 ) return;
	if ( next >= steps.length ) {

		finishGuideAndPlay();
		return;

	}

	showGuideStep( ex, next );

}

function finishGuideAndPlay() {

	clearTimeout( state.guideAutoTimer );
	state.guideAutoTimer = null;
	clearTimeout( state.guideHoldTimer );
	state.guideHoldTimer = null;
	state.guideSeeking = false;
	if ( state.exerciseAction ) {

		state.exerciseAction.paused = false;
		state.exerciseAction.setEffectiveTimeScale( 1 );

	}

	clearBodyMarkers();
	const ex = getExercise( state.selectedId );
	if ( ! ex ) return;
	startWorkout( ex );

}

function crossFadeTo( nextAction, duration = 0.3 ) {

	if ( ! nextAction ) return;
	nextAction.enabled = true;
	nextAction.setEffectiveTimeScale( 1 );
	nextAction.setEffectiveWeight( 1 );
	nextAction.reset();
	nextAction.time = 0;
	nextAction.paused = false;

	const from = state.exerciseAction && state.exerciseAction !== nextAction && state.exerciseAction.isRunning()
		? state.exerciseAction
		: ( state.idleAction && state.idleAction.isRunning() ? state.idleAction : null );

	if ( from ) from.crossFadeTo( nextAction, duration, false );
	else nextAction.fadeIn( duration );
	nextAction.play();

}

function startCueRotation( ex ) {

	clearInterval( state.cueTimer );
	if ( ! ex?.cues?.length ) return;
	state.cueTimer = setInterval( () => {

		if ( state.paused ) return;
		state.cueIndex = ( state.cueIndex + 1 ) % ex.cues.length;
		els.liveCue.textContent = ex.cues[ state.cueIndex ];

	}, 3500 );

}

function startWorkout( ex ) {

	clearSessionTimers();
	clearBodyMarkers();
	state.guideSeeking = false;
	state.userCameraLock = false;

	const clip = exerciseClips.get( ex.id );
	const action = mixer.clipAction( clip );
	action.paused = false;
	action.setEffectiveTimeScale( 1 );
	action.setLoop( THREE.LoopRepeat, Infinity );
	action.clampWhenFinished = false;
	crossFadeTo( action, 0.35 );
	state.exerciseAction = action;
	state.paused = false;
	state.optionsOpen = false;
	document.body.dataset.paused = 'false';

	if ( skeleton ) skeleton.visible = document.getElementById( 'skeletonBtn' ).classList.contains( 'active' );

	els.panel.classList.add( 'collapsed' );
	els.settingsToggle.setAttribute( 'aria-expanded', 'false' );
	els.settingsToggle.textContent = 'Options';
	els.pauseBtn.textContent = 'Pause';
	els.pauseBtn.setAttribute( 'aria-pressed', 'false' );
	els.workoutTitle.textContent = ex.name;
	els.liveCue.textContent = ex.cues?.[ 0 ] || '';
	state.cueIndex = 0;
	els.statusLabel.textContent = `Live · ${ ex.name }`;

	applySpeed( Number( els.speedSlider.value ) || 1 );
	if ( mixer ) mixer.timeScale = state.savedTimeScale || 1;
	startCueRotation( ex );

	mixer.update( 0 );
	groundCharacter();
	showScreen( 'workout' );
	requestAnimationFrame( () => {

		syncStageSize();
		frameGuideBody( false );
		setTimeout( () => {

			if ( ! state.userCameraLock ) frameGuideBody( true );

		}, 120 );

	} );

}

function clearSessionTimers() {

	clearInterval( state.cueTimer );
	clearInterval( state.countdownTimer );
	clearTimeout( state.countdownGoTimer );
	clearTimeout( state.guideAutoTimer );
	clearTimeout( state.guideHoldTimer );
	state.cueTimer = null;
	state.countdownTimer = null;
	state.countdownGoTimer = null;
	state.guideAutoTimer = null;
	state.guideHoldTimer = null;

}

function hardStopSession( { go } ) {

	clearSessionTimers();
	clearBodyMarkers();
	state.paused = false;
	state.guideIndex = 0;
	state.guideSeeking = false;
	state.userCameraLock = false;
	document.body.dataset.paused = 'false';
	els.pauseBtn.textContent = 'Pause';
	els.pauseBtn.setAttribute( 'aria-pressed', 'false' );
	if ( mixer ) mixer.timeScale = state.savedTimeScale || 1;

	if ( skeleton ) skeleton.visible = document.getElementById( 'skeletonBtn' ).classList.contains( 'active' );

	if ( state.exerciseAction ) {

		const prev = state.exerciseAction;
		prev.paused = false;
		state.exerciseAction = null;
		if ( state.idleAction ) {

			state.idleAction.reset();
			state.idleAction.setEffectiveWeight( 1 );
			prev.crossFadeTo( state.idleAction, 0.3, false );
			state.idleAction.play();

		} else {

			prev.fadeOut( 0.25 );
			prev.stop();

		}

	} else if ( state.idleAction && ! state.idleAction.isRunning() ) {

		state.idleAction.reset();
		state.idleAction.fadeIn( 0.2 );
		state.idleAction.play();

	}

	state.optionsOpen = false;
	els.panel.classList.add( 'collapsed' );
	els.settingsToggle.setAttribute( 'aria-expanded', 'false' );
	els.settingsToggle.textContent = 'Options';

	mixer?.update( 0 );
	groundCharacter();
	frameView( 'full' );

	if ( go === 'instruct' && state.selectedId ) openInstructions( state.selectedId );
	else if ( document.body.dataset.embedded === 'true' && state.selectedId ) {

		openInstructions( state.selectedId );

	} else {

		showScreen( 'library' );
		els.statusLabel.textContent = 'Select a form';

	}

}

// ---------------------------------------------------------------------------
// TacTech native bridge
// Phase 2: add Mixamo FBX under models/exercises/, extend exercises.js +
// guide-data.js, then FormStudioExerciseMap on iOS.
// ---------------------------------------------------------------------------

let pendingExerciseId = null;
let pendingExerciseOptions = null;
let assetsReady = false;

function readLaunchExerciseId() {

	try {

		const params = new URLSearchParams( window.location.search || '' );
		return params.get( 'exercise' );

	} catch ( _ ) {

		return null;

	}

}

pendingExerciseId = readLaunchExerciseId();
if ( pendingExerciseId ) document.body.dataset.embedded = 'true';

async function consumePendingExercise() {

	assetsReady = true;
	const id = pendingExerciseId;
	const opts = pendingExerciseOptions || {};
	pendingExerciseId = null;
	pendingExerciseOptions = null;
	if ( id ) {

		try {

			await openExercise( id, opts );

		} catch ( err ) {

			console.error( '[FormStudio] pending open failed', err );
			els.statusLabel.textContent = 'Couldn’t load 3D demo';

		}

	} else if ( document.body.dataset.embedded !== 'true' ) {

		els.statusLabel.textContent = 'Select a form';

	}

}

/**
 * Native / query bridge.
 * @param {string} id clipId
 * @param {{ animationUrl?: string, guide?: object[], cues?: string[], title?: string }} [options]
 */
async function openExercise( id, options = {} ) {

	if ( id === 'sit_ups' ) id = 'situps';
	options = options || {};

	let ex = getExercise( id );
	const hasApiGuide = Array.isArray( options.guide ) && options.guide.length > 0;
	const hasApiCues = Array.isArray( options.cues ) && options.cues.length > 0;

	if ( ! ex ) {

		if ( ! options.animationUrl ) {

			console.warn( '[FormStudio] Unknown exercise', id );
			return false;

		}

		ex = {
			id,
			name: options.title || id,
			tagline: 'Form demo',
			level: '',
			reps: '',
			file: options.animationUrl,
			muscles: [],
			summary: options.title || 'Follow the 3D coach.',
			balance: [],
			steps: [],
			cues: hasApiCues ? options.cues : [ 'Match the coach', 'Move with control' ],
			mistakes: [],
			guide: hasApiGuide ? options.guide : defaultRuntimeGuide(),
			_preferApiGuide: true
		};
		runtimeOverrides.set( id, ex );

	} else if ( options.title || hasApiGuide || hasApiCues || options.animationUrl ) {

		const merged = {
			...ex,
			name: options.title || ex.name,
			file: options.animationUrl || ex.file,
			cues: hasApiCues ? options.cues : ex.cues,
			guide: hasApiGuide ? options.guide : ex.guide,
			_preferApiGuide: hasApiGuide
		};
		runtimeOverrides.set( id, merged );
		ex = merged;

	}

	document.body.dataset.embedded = 'true';
	if ( ! assetsReady ) {

		pendingExerciseId = id;
		pendingExerciseOptions = options;
		return true;

	}

	if ( options.animationUrl ) {

		try {

			exerciseClips.set( id, await loadClip( options.animationUrl, id ) );

		} catch ( err ) {

			console.error( '[FormStudio] animationUrl load failed', id, err );
			throw err;

		}

	} else if ( ! exerciseClips.has( id ) && ex.file ) {

		try {

			exerciseClips.set( id, await loadClip( ex.file, id ) );

		} catch ( err ) {

			console.error( '[FormStudio] bundled clip load failed', id, err );
			throw err;

		}

	}

	openInstructions( id );
	return true;

}

function closeToNative() {

	try {

		if ( window.webkit?.messageHandlers?.formStudio ) {

			window.webkit.messageHandlers.formStudio.postMessage( { type: 'close' } );

		}

	} catch ( err ) {

		console.warn( '[FormStudio] close bridge failed', err );

	}

}

window.FormStudio = {
	openExercise,
	close: closeToNative,
	listIds: () => EXERCISES.map( ( e ) => e.id )
};
