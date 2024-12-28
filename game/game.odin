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

Obstacle :: struct {
	is_active: bool,
	pos:       rl.Vector2,
	size:      rl.Vector2,
}

Game_Memory :: struct {
	player_pos:                      rl.Vector2,
	player_speed:                    f32,
	player_velocity:                 f32,
	player_jumping:                  bool,
	player_burrowing:                bool,
	above_background_texture:        rl.Texture2D,
	background_positions:            [AboveBackgroundSprites]rl.Vector2,
	obstacles:                       [16]Obstacle,
	previous_player_y:               [128]f32,
	previous_player_y_head:          int,
	previous_player_y_snapshot_time: f64,
	player_shader:                   rl.Shader,
	player_texture:                  rl.Texture2D,
	player_render_texture:           rl.RenderTexture2D,
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
		target = g_mem.player_pos,
		// target = g_mem.player_pos + {180, 0},
		offset = {w / 2, h / 2},
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {zoom = f32(rl.GetScreenHeight()) / PIXEL_WINDOW_HEIGHT}
}

input_is_down :: proc() -> bool {
	return rl.IsKeyDown(.J) || rl.IsGamepadButtonDown(0, .RIGHT_FACE_RIGHT)
}

input_is_up :: proc() -> bool {
	return rl.IsKeyDown(.K) || rl.IsGamepadButtonDown(0, .RIGHT_FACE_DOWN)
}

update :: proc() {
	GRAVITY :: 0.2
	BURROW_GRAVITY :: 0.1
	FALL_MULTIPLIER :: 0.5
	JUMP_VELOCITY :: -5
	BURROW_VELOCITY :: 3

	dt := rl.GetFrameTime() * 100

	if !g_mem.player_jumping {
		if input_is_down() {
			if g_mem.player_pos.y == 0 {
				g_mem.player_jumping = true
				g_mem.player_velocity = JUMP_VELOCITY
			}
		}

		if input_is_up() {
			if g_mem.player_pos.y == 0 {
				g_mem.player_burrowing = true
				g_mem.player_velocity = BURROW_VELOCITY
			}
		}
	}

	if g_mem.player_jumping {
		g_mem.player_pos.y += g_mem.player_velocity * dt
		if g_mem.player_velocity > 0 {
			g_mem.player_velocity += GRAVITY * FALL_MULTIPLIER * dt
		} else {
			g_mem.player_velocity += GRAVITY * dt
		}
		if g_mem.player_pos.y >= 0 {
			g_mem.player_pos.y = 0
			g_mem.player_jumping = false
		}
	}

	if g_mem.player_burrowing {
		g_mem.player_pos.y += g_mem.player_velocity * dt
		g_mem.player_velocity -= BURROW_GRAVITY * dt
		if g_mem.player_pos.y <= 0 {
			g_mem.player_pos.y = 0
			g_mem.player_burrowing = false
		}
	}

	if rl.GetTime() - g_mem.previous_player_y_snapshot_time > f64(0.003 * g_mem.player_speed) {
		g_mem.previous_player_y_snapshot_time = rl.GetTime()
		g_mem.previous_player_y_head =
			(g_mem.previous_player_y_head + 1) % len(g_mem.previous_player_y)
		g_mem.previous_player_y[g_mem.previous_player_y_head] = g_mem.player_pos.y
	}

	// input = linalg.normalize0(input)
	// g_mem.player_pos += input * rl.GetFrameTime() * 100

	// g_mem.player_pos.y = f32(math.sin(rl.GetTime() * 1) * 75) - 75

	for &pos, bg in g_mem.background_positions {
		switch bg {
		case .Sky:
		// pos.x -= 0.02
		case .DistantMountains:
			pos.x -= 0.07 * g_mem.player_speed * dt
			pos.y = -(g_mem.player_pos.y / 60)
		case .CloserMountains:
			pos.x -= 0.1 * g_mem.player_speed * dt
			pos.y = -(g_mem.player_pos.y / 30)
		case .Hills:
			pos.x -= 0.3 * g_mem.player_speed * dt
			pos.y = -(g_mem.player_pos.y / 10)
		}
		if pos.x < -320 {
			pos.x += 320
		}
	}
}

draw_backgrounds :: proc() {
	for rect, bg in ABOVE_BACKGROUND_SPRITE_RECTS {
		for i in -1 ..= 2 {
			rl.DrawTextureRec(
				g_mem.above_background_texture,
				rect,
				g_mem.background_positions[bg] + {rect.width * f32(i), -310},
				rl.WHITE,
			)
		}
	}
}


render_player :: proc() {
	draw_player_segment :: proc(pos: rl.Vector2) {
		rl.DrawTexturePro(
			g_mem.player_texture,
			{0, 0, 100, 100},
			{pos.x, pos.y, PLAYER_SEGMENT_SIZE, PLAYER_SEGMENT_SIZE},
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
		return -f32(count * 10) - PLAYER_SEGMENT_SIZE / 2
	}

	scale_y_pos :: proc(orig_y_pos: f32) -> f32 {
		return orig_y_pos / PLAYER_RENDER_SCALE
	}

	// // Begin drawing to render texture
	rl.BeginTextureMode(g_mem.player_render_texture)
	{
		rl.ClearBackground(rl.BLANK)

		// debug rectangle
		rl.DrawRectangleLines(
			1,
			1,
			PLAYER_RENDER_TEXTURE_SIZE - 1,
			PLAYER_RENDER_TEXTURE_SIZE - 2,
			rl.RED,
		)

		camera := rl.Camera2D {
			offset = {
				f32(g_mem.player_render_texture.texture.width),
				f32(g_mem.player_render_texture.texture.height) / 2,
			},
			zoom   = 1.0,
		}

		rl.BeginMode2D(camera)
		{
			pos_count := 0

			draw_player_segment({get_x_pos(pos_count), scale_y_pos(g_mem.player_pos.y)})
			pos_count += 1

			for i := g_mem.previous_player_y_head; i >= 0; i -= 1 {
				draw_player_segment(
					{get_x_pos(pos_count), scale_y_pos(g_mem.previous_player_y[i])},
				)
				pos_count += 1
			}

			for i := len(g_mem.previous_player_y) - 1; i > g_mem.previous_player_y_head; i -= 1 {
				draw_player_segment(
					{get_x_pos(pos_count), scale_y_pos(g_mem.previous_player_y[i])},
				)
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
		g_mem.player_shader,
		rl.GetShaderLocation(g_mem.player_shader, "currentTexture"),
		g_mem.player_render_texture.texture,
	)

	// Now draw the combined texture with shader
	rl.BeginShaderMode(g_mem.player_shader)
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
			f32(g_mem.player_render_texture.texture.width),
			-f32(g_mem.player_render_texture.texture.height),
		}
		rl.DrawTexturePro(
			g_mem.player_render_texture.texture,
			src_rect,
			dest_rect,
			origin,
			0,
			rl.WHITE,
		)
	}
	rl.EndShaderMode()

	rl.DrawRectangleV(g_mem.player_pos, {10, 10}, rl.PURPLE)
}

draw :: proc() {
	render_player()

	rl.BeginDrawing()
	{
		rl.ClearBackground(rl.BLACK)

		rl.BeginMode2D(game_camera())
		{
			draw_backgrounds()

			rl.DrawLineEx({-150, 12.5}, {150, 12.5}, 5, rl.BROWN)
			// rl.DrawRectangleV({-150, 15}, {300, 80}, rl.DARKBROWN)

			// rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)
			// rl.DrawRectangleV({-30, -20}, {10, 10}, rl.GREEN)

			draw_player()
		}
		rl.EndMode2D()

		rl.BeginMode2D(ui_camera())
		{
			// Note: main_hot_reload.odin clears the temp allocator at end of frame.
			stats := fmt.ctprintf(
				"player_speed: %v\nplayer_pos: %v\nplayer_bg_pos: %v",
				g_mem.player_speed,
				g_mem.player_pos,
				g_mem.background_positions[.DistantMountains],
			)
			rl.DrawText(stats, 5, 5, 8, rl.WHITE)

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

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		player_speed                    = 1.0,
		above_background_texture        = rl.LoadTexture("assets/above-background-sky.png"),
		previous_player_y_snapshot_time = rl.GetTime(),
		player_shader                   = rl.LoadShader(nil, "assets/player.fs"),
		player_texture                  = rl.LoadTexture("assets/radial_gradient.png"),
		player_render_texture           = rl.LoadRenderTexture(
			PLAYER_RENDER_TEXTURE_SIZE,
			PLAYER_RENDER_TEXTURE_SIZE,
		),
	}

	game_hot_reloaded(g_mem)
}

@(export)
game_shutdown :: proc() {
	rl.UnloadRenderTexture(g_mem.player_render_texture)
	rl.UnloadTexture(g_mem.above_background_texture)
	rl.UnloadTexture(g_mem.player_texture)
	rl.UnloadShader(g_mem.player_shader)
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
