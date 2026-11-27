extends SceneTree
## Headless rigid test suite for EnemyReactionComponent (Bayonetta 2 / PlatinumGames Spec)
## Run with: godot --headless --script res://tests/test_enemy_reaction_system.gd

const ReactionComp = preload("res://combat/enemy_reaction_component.gd")

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run_all_tests")


func _assert_true(cond: bool, label: String) -> void:
	if not cond:
		_failures.append("FAIL: %s" % label)
		printerr("[FAIL] %s" % label)


func _assert_approx(actual: float, expected: float, tol: float, label: String) -> void:
	if absf(actual - expected) > tol:
		_failures.append("FAIL: %s (expected %.4f, got %.4f)" % [label, expected, actual])
		printerr("[FAIL] %s (expected %.4f, got %.4f)" % [label, expected, actual])


func _create_test_arena() -> Dictionary:
	var arena: Node3D = Node3D.new()
	root.add_child(arena)

	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(40.0, 2.0, 40.0)
	floor_col.shape = floor_box
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)

	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.0
	col.shape = cap
	col.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(col)

	var vis: Node3D = Node3D.new()
	body.add_child(vis)

	var hp: HealthComponent = HealthComponent.new()
	body.add_child(hp)

	var data: EnemyData = EnemyData.new()
	data.max_health = 500.0
	data.max_poise = 65.0
	data.dizzy_duration = 2.4
	data.hitstun_duration = 0.40
	data.knockback_resistance = 0.0
	data.gravity_scale_when_juggled = 0.22
	data.air_juggle_hover_impulse = 3.2
	data.hitstun_decay_factor = 0.95
	data.gravity_scaling_factor = 1.05
	data.max_ground_bounces = 1
	data.ground_bounce_velocity = 8.4
	data.knockdown_recovery_duration = 0.45
	data.air_breakaway_hit_threshold = 5
	data.air_breakaway_chance = 1.0
	data.air_tether_strength = 0.85
	hp.configure_max_health(data.max_health, true)

	var rc: ReactionComp = ReactionComp.new()
	body.add_child(rc)
	arena.add_child(body)
	rc.configure(body, vis, hp, data, 24.5)

	return {
		"arena": arena,
		"body": body,
		"vis": vis,
		"hp": hp,
		"data": data,
		"rc": rc,
	}


func _step_physics(rc: ReactionComp, body: CharacterBody3D, frames: int, delta: float = 1.0 / 60.0) -> void:
	for i: int in range(frames):
		if not rc.is_in_reaction():
			body.velocity.y = -1.0 if body.is_on_floor() else body.velocity.y - 24.5 * delta
			body.move_and_slide()
		else:
			rc.step_physics(delta)
		rc.tick_passive(delta)
		await physics_frame


func _make_hit(
	dmg: float,
	stagger: float,
	launch_vec: Vector3,
	is_launch: bool = false,
	is_air: bool = false,
	frames: int = 0,
	force_st: StringName = &"",
	tether_vel: Vector3 = Vector3.ZERO,
	imp_dir: Vector3 = Vector3.FORWARD
) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.amount = dmg
	info.stagger_power = stagger
	info.launch_vector = launch_vec
	info.knockback_vector = Vector3(launch_vec.x, 0.0, launch_vec.z)
	info.launch_force = launch_vec.y
	info.is_launcher = is_launch
	info.is_aerial = is_air
	info.hitstop_frames = frames
	info.hitstop_duration = 0.0
	info.hitstun_duration = 0.40
	info.force_state = force_st
	info.attacker_forward_velocity = tether_vel
	info.impact_direction = imp_dir
	return info


func _run_all_tests() -> void:
	await physics_frame
	await _test_1_poise_and_super_armor()
	await _test_2_hitstop_freeze_frames()
	await _test_3_progressive_decay_and_gravity_scaling()
	await _test_4_vertical_stall_and_tethering()
	await _test_5_ground_bounce_and_knockdown_recovery()
	await _test_6_anti_infinite_air_breakaway()
	await _test_7_procedural_directional_reaction()

	if _failures.is_empty():
		print("[ALL PASS] 7/7 EnemyReactionComponent tests passed!")
		quit(0)
	else:
		printerr("[FAILED] %d assertions failed." % _failures.size())
		quit(1)


func _test_1_poise_and_super_armor() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	# Hit 1: Stagger 30 < 65 Poise -> Super Armor absorbs Launch!
	var res1: Dictionary = rc.process_hit(_make_hit(20.0, 30.0, Vector3(0.0, 12.0, 0.0), true))
	_assert_true(not bool(res1["entered_reaction"]), "Test1: Poise > 0 blocks Launch in COMBAT_ACTIVE")
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.COMBAT_ACTIVE, "Test1: Remains COMBAT_ACTIVE")
	_assert_approx(rc.current_poise, 35.0, 0.01, "Test1: Poise reduced to 35")

	# Hit 2: Stagger 40 breaks remaining 35 Poise -> DIZZY + LAUNCHED!
	var res2: Dictionary = rc.process_hit(_make_hit(20.0, 40.0, Vector3(0.0, 12.0, 0.0), true))
	_assert_true(bool(res2["poise_broken"]), "Test1: Poise broken emitted")
	_assert_true(rc.is_dizzy, "Test1: Enemy enters DIZZY")
	_assert_true(bool(res2["entered_reaction"]), "Test1: Broken Poise allows Launch")
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.LAUNCHED, "Test1: State is LAUNCHED")

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 1: Poise / Super Armor & DIZZY")


func _test_2_hitstop_freeze_frames() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	# Break poise & launch with 5 freeze frames (5/60s)
	rc.process_hit(_make_hit(20.0, 80.0, Vector3(0.0, 10.0, 0.0), true, false, 5))
	var pos_before: Vector3 = body.global_position
	var vel_before: Vector3 = body.velocity

	# Step 3 frames (still inside 5-frame hitstop) -> velocity and position MUST remain frozen!
	await _step_physics(rc, body, 3)
	_assert_true(rc.is_in_hitstop(), "Test2: Still in hitstop after 3 of 5 frames")
	_assert_approx(body.global_position.y, pos_before.y, 0.0001, "Test2: Position frozen during hitstop")
	_assert_approx(body.velocity.y, vel_before.y, 0.0001, "Test2: Gravity paused during hitstop")

	# Step 4 more frames -> hitstop ends and enemy launches upward
	await _step_physics(rc, body, 4)
	_assert_true(not rc.is_in_hitstop(), "Test2: Hitstop finished")
	_assert_true(body.global_position.y > pos_before.y + 0.05, "Test2: Movement resumes after hitstop")

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 2: Hitstop Freeze Frames")


func _test_3_progressive_decay_and_gravity_scaling() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	rc.process_hit(_make_hit(10.0, 80.0, Vector3(0.0, 12.0, 0.0), true))
	await _step_physics(rc, body, 10)

	for n: int in range(1, 5):
		rc.process_hit(_make_hit(10.0, 10.0, Vector3(0.0, 2.0, 0.0), false, true), false)
		_assert_true(rc.combo_hit_count == n, "Test3: combo_hit_count == %d" % n)
		_assert_approx(rc.get_current_hitstun_multiplier(), pow(0.95, float(n)), 0.001, "Test3: Hitstun decay 0.95^%d" % n)
		_assert_approx(rc.get_current_juggle_gravity_scale(), 0.22 * pow(1.05, float(n)), 0.001, "Test3: Gravity scale 1.05^%d" % n)

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 3: Progressive Hitstun Decay (0.95^N) & Gravity Scaling (1.05^N)")


func _test_4_vertical_stall_and_tethering() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	# Launch high and let fall slightly so V.y is negative
	rc.process_hit(_make_hit(10.0, 80.0, Vector3(0.0, 10.0, 0.0), true))
	await _step_physics(rc, body, 30)
	_assert_true(body.velocity.y < 0.0, "Test4: Enemy is descending before air juggle hit")

	var attacker_vel: Vector3 = Vector3(0.0, 0.0, -6.0)
	rc.process_hit(_make_hit(10.0, 10.0, Vector3(0.0, 1.5, 0.0), false, true, 0, &"", attacker_vel), false)
	_assert_true(body.velocity.y > 0.0, "Test4: Vertical velocity stalled and reset to upward micro-impulse")
	_assert_true(body.velocity.z < -4.0, "Test4: Horizontal tether matches attacker forward velocity")
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.AIR_JUGGLE, "Test4: State is AIR_JUGGLE")

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 4: Vertical Velocity Stall & Tethering / Hit-Magnetism")


func _test_5_ground_bounce_and_knockdown_recovery() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var hp: HealthComponent = ctx["hp"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	# Launch into air first
	rc.process_hit(_make_hit(10.0, 80.0, Vector3(0.0, 10.0, 0.0), true))
	await _step_physics(rc, body, 15)

	# Spike slam down with FORCE_STATE_GROUND_BOUNCE
	rc.process_hit(_make_hit(20.0, 20.0, Vector3(0.0, -20.0, 0.0), false, true, 0, DamageInfo.FORCE_STATE_GROUND_BOUNCE), false)
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.AIR_FALLING, "Test5: Spike enters AIR_FALLING")

	# Step until ground impact triggers 1st Ground Bounce -> AIR_JUGGLE
	var bounced: bool = false
	for _f: int in range(60):
		await _step_physics(rc, body, 1)
		if rc.ground_bounces_used == 1 and rc.reaction_state == ReactionComp.ReactionState.AIR_JUGGLE:
			bounced = true
			break
	_assert_true(bounced, "Test5: 1st slam triggered Ground Bounce -> AIR_JUGGLE")

	# Second slam after bounce budget (max_ground_bounces=1) is exhausted -> KNOCKDOWN / GROUNDED_RECOVERY
	rc.process_hit(_make_hit(20.0, 20.0, Vector3(0.0, -20.0, 0.0), false, true, 0, DamageInfo.FORCE_STATE_GROUND_BOUNCE), false)
	var knocked_down: bool = false
	for _f2: int in range(60):
		await _step_physics(rc, body, 1)
		if rc.reaction_state == ReactionComp.ReactionState.KNOCKDOWN:
			knocked_down = true
			break
	_assert_true(knocked_down, "Test5: 2nd slam enters KNOCKDOWN / GROUNDED_RECOVERY")
	_assert_true(hp.is_invulnerable, "Test5: Enemy is invulnerable during GROUNDED_RECOVERY")

	# Wait out knockdown recovery -> returns to COMBAT_ACTIVE & invulnerability clears
	await _step_physics(rc, body, 35)
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.COMBAT_ACTIVE, "Test5: Returns to COMBAT_ACTIVE")
	_assert_true(not hp.is_invulnerable, "Test5: Invulnerability cleared after recovery")

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 5: Ground Bounce & Knockdown Recovery")


func _test_6_anti_infinite_air_breakaway() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	# Launch while NOT dizzy (e.g. Witch Time slow-mo, then restored to normal speed)
	rc.time_slow_multiplier = 0.5
	rc.process_hit(_make_hit(10.0, 10.0, Vector3(0.0, 12.0, 0.0), true))
	rc.time_slow_multiplier = 1.0
	rc.is_dizzy = false
	await _step_physics(rc, body, 10)

	# Build up to threshold (5 hits)
	for _i: int in range(4):
		rc.process_hit(_make_hit(5.0, 5.0, Vector3(0.0, 2.0, 0.0), false, true), false)

	# Hit 5 with breakaway allowed (chance=1.0 in test data) -> Breakaway triggers!
	var res_bw: Dictionary = rc.process_hit(_make_hit(5.0, 5.0, Vector3(0.0, 2.0, 0.0), false, true), true)
	_assert_true(bool(res_bw["breakaway"]), "Test6: Air Breakaway triggers at threshold when not Dizzy")
	_assert_true(rc.reaction_state == ReactionComp.ReactionState.COMBAT_ACTIVE, "Test6: Breakaway resets reaction to COMBAT_ACTIVE")

	# Verify breakaway is blocked when enemy IS DIZZY (break poise naturally so dizzy_timer starts)
	rc.current_poise = 10.0
	rc.is_dizzy = false
	rc.process_hit(_make_hit(10.0, 20.0, Vector3(0.0, 12.0, 0.0), true), false)
	_assert_true(rc.is_dizzy, "Test6: Enemy became DIZZY after Poise break")
	await _step_physics(rc, body, 8)
	rc.combo_hit_count = 6
	var res_dizzy: Dictionary = rc.process_hit(_make_hit(5.0, 5.0, Vector3(0.0, 2.0, 0.0), false, true), true)
	_assert_true(not bool(res_dizzy["breakaway"]), "Test6: DIZZY enemy cannot Air Breakaway")

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 6: Anti-Infinite Air Breakaway Rules")


func _test_7_procedural_directional_reaction() -> void:
	var ctx: Dictionary = _create_test_arena()
	var body: CharacterBody3D = ctx["body"]
	var vis: Node3D = ctx["vis"]
	var rc: ReactionComp = ctx["rc"]
	await _step_physics(rc, body, 3)

	# Strike from Left -> rolls visual_root negatively around Z
	rc.process_hit(_make_hit(30.0, 10.0, Vector3.ZERO, false, false, 0, &"", Vector3.ZERO, Vector3(1.0, 0.0, 0.0)))
	await _step_physics(rc, body, 3)
	var roll_from_left: float = vis.rotation.z
	_assert_true(roll_from_left < -0.02, "Test7: Impact from +X tilts visual_root.rotation.z negative")

	# Let spring settle back toward 0, then strike from Right (-X)
	await _step_physics(rc, body, 45)
	_assert_approx(vis.rotation.z, 0.0, 0.03, "Test7: Spring-damper returns visual_root to neutral")

	rc.process_hit(_make_hit(30.0, 10.0, Vector3.ZERO, false, false, 0, &"", Vector3.ZERO, Vector3(-1.0, 0.0, 0.0)))
	await _step_physics(rc, body, 3)
	var roll_from_right: float = vis.rotation.z
	_assert_true(roll_from_right > 0.02, "Test7: Impact from -X tilts visual_root.rotation.z positive")

	(ctx["arena"] as Node).queue_free()
	print("[PASS] Test 7: Procedural Directional Hit Reaction")
