// This file is compiled as part of the `odin.dll` file. It contains the
// procs that `game_hot_reload.exe` will call, such as:
//
// game_init: Sets up the game state
// game_update: Run once per frame
// game_shutdown: Shuts down game and frees memory
// game_memory: Run just before a hot reload, so game.exe has a pointer to the
//		game's memory.
// game_hot_reloaded: Run after a hot reload so that the `g_mem` global variable
//		can be set to whatever pointer it was in the old DLL.
//
// Note: When compiled as part of the release executable this whole package is imported as a normal
// odin package instead of a DLL.

package game

import "core:fmt"
// import "core:math"
// import "core:math/linalg"
// import "core:os"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 320
PLAYER_RENDER_TEXTURE_SIZE :: 2048 // Adjust these sizes based on your needs
PLAYER_SEGMENT_SIZE :: 100
PLAYER_RENDER_SCALE :: 0.2
PLAYER_SEGMENT_DISTANCE :: 0.1
CHAIN_MULTIPLIER_MAX :: 1.5
MAX_LIVES :: 5

ScreenStates :: enum {
	Intro,
	Game,
	GameOver,
}

EntityType :: enum {
	Crate,
	Rock,
	Coin,
	Apple,
}

ENTITY_SPRITE_RECTS := [EntityType]rl.Rectangle {
	.Crate = {1, 1, 32, 32},
	.Rock  = {35, 1, 32, 32},
	.Coin  = {1, 35, 32, 32},
	.Apple = {35, 35, 32, 32},
}

Entity :: struct {
	is_active: bool,
	type:      EntityType,
	pos:       rl.Vector2,
	size:      rl.Vector2,
}

Game_Memory :: struct {
	player:                struct {
		pos:       rl.Vector2,
		speed:     f32,
		velocity:  f32,
		jumping:   bool,
		burrowing: bool,
	},
	textures:              struct {
		above_background: rl.Texture2D,
		underground:      rl.Texture2D,
		player:           rl.Texture2D,
		player_render:    rl.RenderTexture2D,
		entities:         rl.Texture2D,
	},
	backgrounds:           struct {
		above_background_positions: [AboveBackgroundSprites]rl.Vector2,
		underground_position:       rl.Vector2,
	},
	shaders:               struct {
		player: rl.Shader,
	},
	entities:              []Entity,
	release_decay_applied: bool,
	chain_multiplier:      f32,
	distance_travelled:    f64,
	segment_distance:      f32,
	previous_player_head:  int,
	previous_player:       []rl.Vector2,
	lives:                 int,
	score:                 int,
	screen_state:          ScreenStates,
}
g_mem: ^Game_Memory

AboveBackgroundSprites :: enum {
	Sky,
	DistantMountains,
	CloserMountains,
	Hills,
}

ABOVE_BACKGROUND_SPRITE_RECTS :: [AboveBackgroundSprites]rl.Rectangle {
	.Sky              = {1, 1, 320, 320},
	.DistantMountains = {323, 1, 320, 320},
	.CloserMountains  = {1, 323, 320, 320},
	.Hills            = {323, 323, 320, 320},
}

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom   = h / PIXEL_WINDOW_HEIGHT,
		target = {0, g_mem.player.pos.y},
		// target = g_mem.player.pos + {180, 0},
		offset = {w / 2, h / 2},
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {zoom = f32(rl.GetScreenHeight()) / PIXEL_WINDOW_HEIGHT}
}

update_player :: proc(dt: f32) {
	input_is_jumping :: proc() -> bool {
		return rl.IsKeyDown(.K) || rl.IsGamepadButtonDown(0, .RIGHT_FACE_RIGHT)
	}

	input_is_burrowing :: proc() -> bool {
		return rl.IsKeyDown(.J) || rl.IsGamepadButtonDown(0, .RIGHT_FACE_DOWN)
	}

	// [DEBUG]
	if rl.IsGamepadButtonDown(0, .LEFT_FACE_RIGHT) {
		g_mem.player.speed += 0.01
	}
	if rl.IsGamepadButtonDown(0, .LEFT_FACE_LEFT) {
		g_mem.player.speed -= 0.01
	}
	// [DEBUG]

	GRAVITY :: 0.2
	BURROW_GRAVITY :: 0.1
	FALL_MULTIPLIER :: 0.5
	JUMP_VELOCITY :: -5
	BURROW_VELOCITY :: 3
	RELEASE_DECAY :: 0.4
	BURROW_DECELERATION :: 0.2
	BURROW_JUMP_ACCELERATION :: 1.1
	CHAIN_MULTIPLIER_INCREMENT :: 0.05

	g_mem.player.speed += 0.0001 * dt

	if !g_mem.player.jumping && !g_mem.player.burrowing {
		if input_is_jumping() {
			if g_mem.player.pos.y == 0 {
				g_mem.player.jumping = true
				g_mem.player.velocity = JUMP_VELOCITY
			}
		}

		if input_is_burrowing() {
			if g_mem.player.pos.y == 0 {
				g_mem.player.burrowing = true
				g_mem.player.velocity = BURROW_VELOCITY
			}
		}
	}

	if g_mem.player.jumping {
		if !input_is_jumping() && !g_mem.release_decay_applied && g_mem.player.velocity < 0 {
			g_mem.player.velocity *= RELEASE_DECAY
			g_mem.release_decay_applied = true
		}

		g_mem.player.pos.y += g_mem.player.velocity * dt
		if g_mem.player.velocity > 0 {
			g_mem.player.velocity += GRAVITY * FALL_MULTIPLIER * dt
		} else {
			g_mem.player.velocity += GRAVITY * dt
		}
		if g_mem.player.pos.y >= 0 {
			g_mem.player.jumping = false
			if input_is_burrowing() {
				g_mem.chain_multiplier = min(
					g_mem.chain_multiplier + CHAIN_MULTIPLIER_INCREMENT,
					CHAIN_MULTIPLIER_MAX,
				)
				g_mem.player.burrowing = true
				fmt.println("DEBUG: previous velocity", g_mem.player.velocity)
				g_mem.player.velocity = BURROW_VELOCITY * g_mem.chain_multiplier
				fmt.println("DEBUG: new velocity", g_mem.player.velocity)
			} else {
				g_mem.player.pos.y = 0
				g_mem.chain_multiplier = 1.0
			}
		}
	}

	if g_mem.player.burrowing {
		if !input_is_burrowing() && !g_mem.release_decay_applied && g_mem.player.velocity > 0 {
			g_mem.player.velocity *= RELEASE_DECAY * dt
			g_mem.release_decay_applied = true
		}

		new_velocity := BURROW_GRAVITY * dt

		if input_is_jumping() {
			g_mem.player.velocity -= BURROW_JUMP_ACCELERATION * dt
		} else if g_mem.player.velocity < 0 && input_is_burrowing() {
			new_velocity *= BURROW_DECELERATION
		}

		g_mem.player.pos.y += g_mem.player.velocity * dt
		g_mem.player.velocity -= new_velocity
		if g_mem.player.pos.y <= 0 {
			g_mem.player.burrowing = false
			if input_is_jumping() {
				g_mem.chain_multiplier = min(
					g_mem.chain_multiplier + CHAIN_MULTIPLIER_INCREMENT,
					CHAIN_MULTIPLIER_MAX,
				)
				g_mem.player.jumping = true
				g_mem.player.velocity = JUMP_VELOCITY * g_mem.chain_multiplier
			} else {
				g_mem.player.pos.y = 0
				g_mem.chain_multiplier = 1.0
			}
		}
	}

	if g_mem.player.pos.y == 0 {
		g_mem.release_decay_applied = false
	}
}

update_player_segments :: proc(dt: f32) {
	for &pos in g_mem.previous_player {
		pos.x -= g_mem.player.speed * dt
	}

	g_mem.segment_distance += g_mem.player.speed * dt
	if g_mem.segment_distance >= PLAYER_SEGMENT_DISTANCE {
		g_mem.segment_distance -= PLAYER_SEGMENT_DISTANCE

		previous_head := g_mem.previous_player[g_mem.previous_player_head]

		g_mem.previous_player_head = (g_mem.previous_player_head + 1) % len(g_mem.previous_player)
		g_mem.previous_player[g_mem.previous_player_head] = (previous_head + g_mem.player.pos) / 2

		g_mem.previous_player_head = (g_mem.previous_player_head + 1) % len(g_mem.previous_player)
		g_mem.previous_player[g_mem.previous_player_head] = g_mem.player.pos
	}
}

update_backgrounds :: proc(dt: f32) {
	for &pos, bg in g_mem.backgrounds.above_background_positions {
		switch bg {
		case .Sky:
		// pos.x -= 0.02
		case .DistantMountains:
			pos.x -= 0.07 * g_mem.player.speed * dt
			pos.y = -(g_mem.player.pos.y / 60)
		case .CloserMountains:
			pos.x -= 0.1 * g_mem.player.speed * dt
			pos.y = -(g_mem.player.pos.y / 30)
		case .Hills:
			pos.x -= 0.3 * g_mem.player.speed * dt
			pos.y = -(g_mem.player.pos.y / 10) + 15
		}
		if pos.x < -320 {
			pos.x += 320
		}
	}

	g_mem.backgrounds.underground_position.x -= g_mem.player.speed * dt
	// g_mem.backgrounds.underground_position.y = -(g_mem.player.pos.y / 10) + 10
	if g_mem.backgrounds.underground_position.x < -320 {
		g_mem.backgrounds.underground_position.x += 320
	}
}

update_entities :: proc(dt: f32) {
	for &entity in g_mem.entities {
		if entity.is_active {
			entity.pos.x -= g_mem.player.speed * dt
			if entity.pos.x < -320 {
				entity.is_active = false
			} else {
				radius: f32 = 5 if entity.type == .Crate || entity.type == .Rock else 10
				if rl.CheckCollisionCircleRec(
					g_mem.player.pos,
					radius,
					{entity.pos.x, entity.pos.y, entity.size.x, entity.size.y},
				) {
					entity.is_active = false
					if entity.type == .Crate || entity.type == .Rock {
						g_mem.lives -= 1
						g_mem.score = max(g_mem.score - 50, 0)
					} else if entity.type == .Coin {
						g_mem.score += int(f32(100) * g_mem.player.speed * g_mem.chain_multiplier)
					} else if entity.type == .Apple {
						g_mem.lives += 1
					}
				}
			}
		}
	}

	// given a random chance, spawn an entity
	if rl.GetRandomValue(0, i32(200 * dt)) < 1 {
		// fmt.println("DEBUG: Spawning entity")
		type_random := rl.GetRandomValue(0, 100)
		type := EntityType.Crate
		if type_random < 8 && g_mem.lives < MAX_LIVES {
			type = EntityType.Apple
		} else if type_random < 20 {
			type = EntityType.Coin
		} else if type_random < 70 {
			type = EntityType.Rock
		}
		pos := rl.Vector2{320, 0}
		size := rl.Vector2{32, 32}
		variant := rl.GetRandomValue(0, 9)
		switch type {
		case .Crate:
			if variant < 5 {
				pos.y = f32(rl.GetRandomValue(-6, -80))
			} else {
				pos.y = -6
			}
			size = rl.Vector2{16, 16}
		case .Rock:
			if variant < 3 {
				pos.y = -22
			} else if variant < 5 {
				pos.y = 10
			} else {
				pos.y = f32(rl.GetRandomValue(10, 100))
			}
		case .Coin:
			pos.y = f32(rl.GetRandomValue(-50, -150))
			size = rl.Vector2{16, 16}
		case .Apple:
			pos.y = f32(rl.GetRandomValue(-6, -150))
			size = rl.Vector2{16, 16}
		}
		for &entity in g_mem.entities {
			if !entity.is_active {
				entity.is_active = true
				entity.type = type
				entity.pos = pos
				entity.size = size
				break
			}
		}
	}
}

update :: proc() {
	if g_mem.lives <= 0 {
		g_mem.screen_state = .GameOver
	}
	if rl.IsGamepadButtonPressed(0, .MIDDLE_RIGHT) {
		game_state_reset()
		g_mem.screen_state = .Game
	}
	if g_mem.screen_state != .Game {
		if rl.IsKeyPressed(.SPACE) {
			game_state_reset()
			g_mem.screen_state = .Game
		} else {
			return
		}
	}
	dt := rl.GetFrameTime() * 100

	g_mem.distance_travelled += f64(g_mem.player.speed * dt)

	update_player(dt)
	update_player_segments(dt)
	update_backgrounds(dt)
	update_entities(dt)
}

draw_backgrounds :: proc() {
	for rect, bg in ABOVE_BACKGROUND_SPRITE_RECTS {
		for i in -1 ..= 2 {
			rl.DrawTextureRec(
				g_mem.textures.above_background,
				rect,
				g_mem.backgrounds.above_background_positions[bg] + {rect.width * f32(i), -310},
				rl.WHITE,
			)
		}
	}

	for i in -1 ..= 2 {
		rl.DrawTextureV(
			g_mem.textures.underground,
			{
				g_mem.backgrounds.underground_position.x + 320 * f32(i),
				g_mem.backgrounds.underground_position.y + 10,
			},
			rl.WHITE,
		)
	}
}

render_player :: proc() {
	draw_player_segment :: proc(pos: rl.Vector2) {
		rl.DrawTexturePro(
			g_mem.textures.player,
			{0, 0, 100, 100},
			{
				(pos.x / PLAYER_RENDER_SCALE) - (PLAYER_SEGMENT_SIZE / 2),
				pos.y / PLAYER_RENDER_SCALE,
				PLAYER_SEGMENT_SIZE,
				PLAYER_SEGMENT_SIZE,
			},
			{PLAYER_SEGMENT_SIZE / 2, PLAYER_SEGMENT_SIZE / 2},
			0,
			rl.WHITE,
		)
		// debug rect
		// rl.DrawRectangleLinesEx(
		// 	{
		// 		pos.x - (PLAYER_SEGMENT_SIZE / 2),
		// 		pos.y - (PLAYER_SEGMENT_SIZE / 2),
		// 		PLAYER_SEGMENT_SIZE,
		// 		PLAYER_SEGMENT_SIZE,
		// 	},
		// 	1,
		// 	rl.RED,
		// )
	}

	get_x_pos :: proc(count: int) -> f32 {
		return -f32(f32(count) * (g_mem.player.speed * 4)) - PLAYER_SEGMENT_SIZE / 2
	}

	scale_y_pos :: proc(orig_y_pos: f32) -> f32 {
		return orig_y_pos / PLAYER_RENDER_SCALE
	}

	// // Begin drawing to render texture
	rl.BeginTextureMode(g_mem.textures.player_render)
	{
		rl.ClearBackground(rl.BLANK)

		// debug rectangle
		// rl.DrawRectangleLines(
		// 	1,
		// 	1,
		// 	PLAYER_RENDER_TEXTURE_SIZE - 1,
		// 	PLAYER_RENDER_TEXTURE_SIZE - 2,
		// 	rl.RED,
		// )

		camera := rl.Camera2D {
			offset = {
				f32(g_mem.textures.player_render.texture.width),
				f32(g_mem.textures.player_render.texture.height) / 2,
			},
			zoom   = 1.0,
		}

		rl.BeginMode2D(camera)
		{
			pos_count := 0

			draw_player_segment(g_mem.player.pos)
			pos_count += 1

			for i := g_mem.previous_player_head; i >= 0; i -= 1 {
				pp := g_mem.previous_player[i]
				draw_player_segment(pp)
				pos_count += 1
			}

			for i := len(g_mem.previous_player) - 1; i > g_mem.previous_player_head; i -= 1 {
				pp := g_mem.previous_player[i]
				draw_player_segment(pp)
				pos_count += 1
			}
		}
		rl.EndMode2D()
	}
	rl.EndTextureMode()
}

draw_player :: proc() {
	// Set the shader texture uniform to use our render texture
	rl.SetShaderValueTexture(
		g_mem.shaders.player,
		rl.GetShaderLocation(g_mem.shaders.player, "currentTexture"),
		g_mem.textures.player_render.texture,
	)
	rl.SetShaderValue(
		g_mem.shaders.player,
		rl.GetShaderLocation(g_mem.shaders.player, "texelSize"),
		&rl.Vector2 {
			1.0 / f32(g_mem.textures.player_render.texture.width),
			1.0 / f32(g_mem.textures.player_render.texture.height),
		},
		.VEC2,
	)
	// Now draw the combined texture with shader
	rl.BeginShaderMode(g_mem.shaders.player)
	{
		dest_rect: rl.Rectangle = {
			0,
			0,
			PLAYER_RENDER_TEXTURE_SIZE * PLAYER_RENDER_SCALE,
			PLAYER_RENDER_TEXTURE_SIZE * PLAYER_RENDER_SCALE,
		}
		seg_scaled := f32(PLAYER_SEGMENT_SIZE * PLAYER_RENDER_SCALE)
		origin: rl.Vector2 = {
			dest_rect.width - (seg_scaled - (seg_scaled / 4)),
			dest_rect.height / 2,
		}
		src_rect: rl.Rectangle = {
			0,
			0,
			f32(g_mem.textures.player_render.texture.width),
			-f32(g_mem.textures.player_render.texture.height),
		}
		rl.DrawTexturePro(
			g_mem.textures.player_render.texture,
			src_rect,
			dest_rect,
			origin,
			0,
			rl.WHITE,
		)
	}
	rl.EndShaderMode()

	// rl.DrawRectangleV(g_mem.player.pos, {10, 10}, rl.PURPLE)
}

draw_entities :: proc() {
	for &entity in g_mem.entities {
		if entity.is_active {
			pos := entity.pos
			// pos.y += -(g_mem.player.pos.y / 10)
			rl.DrawTexturePro(
				g_mem.textures.entities,
				ENTITY_SPRITE_RECTS[entity.type],
				{pos.x, pos.y, entity.size.x, entity.size.y},
				{0, 0},
				0,
				rl.WHITE,
			)

			// debug rect
			rl.DrawRectangleLinesEx({pos.x, pos.y, entity.size.x, entity.size.y}, 1, rl.RED)
		}
	}
}

draw :: proc() {
	render_player()

	rl.BeginDrawing()
	{
		rl.ClearBackground(rl.BLACK)

		if g_mem.screen_state == .Game {
			rl.BeginMode2D(game_camera())
			{
				draw_backgrounds()
				draw_entities()
				draw_player()
			}
			rl.EndMode2D()
		}

		ui_camera := ui_camera()
		rl.BeginMode2D(ui_camera)
		{
			ui_size := rl.GetScreenToWorld2D(
				{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
				ui_camera,
			)

			// draw big text in the middle of the screen
			if g_mem.screen_state == .GameOver {
				rl.DrawText(
					"Game Over",
					i32(ui_size.x) / 2 - 100,
					i32(ui_size.y) / 2 - 25,
					40,
					rl.WHITE,
				)
				rl.DrawText(
					"Press SPACE (or START) to restart",
					i32(ui_size.x) / 2 - 200,
					i32(ui_size.y) / 2 + 25,
					20,
					rl.WHITE,
				)
			}

			if g_mem.screen_state == .Game {
				// momentum bar
				rl.DrawRectangle(i32(ui_size.x) - 110, 10, 100, 15, rl.Fade(rl.SKYBLUE, 0.5))
				rl.DrawRectangle(
					i32(ui_size.x) - 110,
					10,
					i32(((0.999 - g_mem.chain_multiplier) / (1 - CHAIN_MULTIPLIER_MAX)) * 100),
					15,
					rl.Fade(rl.WHITE, 0.5),
				)
				rl.DrawText("momentum", i32(ui_size.x) - 85, 12, 10, rl.WHITE)

				// hp bar, middle of screen
				rl.DrawRectangle(i32(ui_size.x) / 2 - 50, 10, 100, 15, rl.Fade(rl.RED, 0.5))
				rl.DrawRectangle(
					i32(ui_size.x) / 2 - 50,
					10,
					i32((f32(g_mem.lives) / MAX_LIVES) * 100),
					15,
					rl.Fade(rl.GREEN, 0.5),
				)
				rl.DrawText("hp", i32(ui_size.x) / 2 - 5, 12, 10, rl.WHITE)

				// debug_stats := fmt.ctprintf(
				// 	"renderwidth: %v\nscreenwidth: %v",
				// 	ui_size.x,
				// 	rl.GetScreenWidth(),
				// )
				// rl.DrawText(debug_stats, 200, 5, 8, rl.WHITE)

				// Note: main_hot_reload.odin clears the temp allocator at end of frame.
				stats := fmt.ctprintf(
					"speed: %.2f\ndistance: %.0f\nlives: %d\tscore: %d",
					g_mem.player.speed,
					// g_mem.player.pos,
					// g_mem.player.velocity,
					// g_mem.chain_multiplier,
					g_mem.distance_travelled,
					g_mem.lives,
					g_mem.score,
				)
				rl.DrawText(stats, 5, 5, 8, rl.WHITE)

			}
		}
		rl.EndMode2D()
	}
	rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
	update()
	draw()
	return !rl.WindowShouldClose()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
}

game_state_reset :: proc() {
	g_mem.player = {
		speed = 1.0,
		pos   = {-120, 0},
	}
	g_mem.chain_multiplier = 1.0
	g_mem.distance_travelled = 0
	g_mem.lives = MAX_LIVES
	g_mem.score = 0
	delete(g_mem.previous_player)
	delete(g_mem.entities)
	g_mem.previous_player = make([]rl.Vector2, 256)
	g_mem.entities = make([]Entity, 64)

	for &pp in g_mem.previous_player {
		pp.x = -500
	}
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		// player = {speed = 1.0, pos = {-120, 0}},
		textures = {
			above_background = rl.LoadTexture("assets/above-background-sky.png"),
			underground = rl.LoadTexture("assets/underground.png"),
			player = rl.LoadTexture("assets/radial_gradient.png"),
			player_render = rl.LoadRenderTexture(
				PLAYER_RENDER_TEXTURE_SIZE,
				PLAYER_RENDER_TEXTURE_SIZE,
			),
			entities = rl.LoadTexture("assets/entities.png"),
		},
		shaders = {player = rl.LoadShader(nil, "assets/player.fs")},
		// chain_multiplier = 1.0,
		// previous_player = make([]rl.Vector2, 256),
		// entities = make([]Entity, 64),
		// lives = MAX_LIVES,
		screen_state = .Intro,
	}

	game_state_reset()

	rl.SetTextureWrap(g_mem.textures.player_render.texture, .CLAMP)
	rl.SetTextureFilter(g_mem.textures.player_render.texture, .TRILINEAR)

	game_hot_reloaded(g_mem)
}

@(export)
game_shutdown :: proc() {
	rl.UnloadRenderTexture(g_mem.textures.player_render)
	rl.UnloadTexture(g_mem.textures.above_background)
	rl.UnloadTexture(g_mem.textures.underground)
	rl.UnloadTexture(g_mem.textures.player)
	rl.UnloadTexture(g_mem.textures.entities)
	rl.UnloadShader(g_mem.shaders.player)
	delete(g_mem.previous_player)
	delete(g_mem.entities)
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}
