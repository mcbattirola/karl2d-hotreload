package game

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import k2 "karl2d"
import vmem `core:mem/virtual`

Game :: struct {
	arena:         vmem.Arena,
	arena_buffer:  []u8,
	allocator:     runtime.Allocator,
	frame_arena:   vmem.Arena,
	player_pos:    k2.Vec2,
	terminate:     bool,
	enemy_pos:     k2.Vec2,
	// audio
	audio_enabled: bool,
	audio_buffer:  k2.Audio_Buffer,
	audio:         k2.Sound,
}

// global game instance
game: ^Game

@(export)
game_init :: proc(k2state: ^k2.State) {
	if k2state != nil {
		k2.set_internal_state(k2state)
	}


	// main arena, only gets cleaned up in the end of the game
	arena_size := size_of(Game) + size_of(vmem.Arena)
	arena_buffer := make([]u8, arena_size)
	arena := vmem.Arena{}
	_ = vmem.arena_init_buffer(&arena, arena_buffer)
	arena_allocator := vmem.arena_allocator(&arena)

	g, err := new(Game, allocator = arena_allocator)
	if err != nil {
		fmt.printfln("error creating game : %s", err)
		os.exit(1)
	}
	game = g

	game.arena = arena
	game.arena_buffer = arena_buffer
	game.allocator = arena_allocator

	game.player_pos = {100, 100}
	game.enemy_pos = {200, 200}

	game.audio_enabled = false
	game.audio_buffer = k2.load_audio_buffer_from_bytes(#load("../assets/jump.wav"))
	game.audio = k2.create_sound_from_audio_buffer(game.audio_buffer)
	k2.set_sound_volume(game.audio, 1)
}

@(export)
game_shutdown :: proc() {
	k2.destroy_sound(game.audio)
	k2.destroy_audio_buffer(game.audio_buffer)

	// unload arenas, fonts, etc.
	vmem.arena_free_all(&game.frame_arena)

	// Note: delete has to be the last thing,
	// since it deallocates the whole game object
	delete(game.arena_buffer)
}

@(export)
game_should_run :: proc() -> bool {
	return !game.terminate
}


@(export)
game_memory :: proc() -> (rawptr, rawptr) {
	return game, nil
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game)
}

@(export)
game_hot_reloaded :: proc(game_mem: rawptr, k2state: ^k2.State) {
	game = (^Game)(game_mem)
	k2.set_internal_state(k2state)
}

@(export)
game_force_reload :: proc() -> bool {
	return k2.key_went_down(.G)
}

@(export)
game_force_restart :: proc() -> bool {
	return k2.key_went_down(.T)
}

@(export)
game_update :: proc() {
	k2.reset_frame_allocator()
	k2.calculate_frame_time()
	k2.update_audio_mixer()
	k2.process_events()

	if k2.key_went_down(.Escape) {
		game.terminate = true
		return
	}

	move_direction: [2]f32

	if k2.key_is_held(.Up) || k2.gamepad_button_is_held(0, .Left_Face_Up) {
		move_direction.y = -1
	}

	if k2.key_is_held(.Down) || k2.gamepad_button_is_held(0, .Left_Face_Down) {
		move_direction.y = 1
	}

	if k2.key_is_held(.Left) || k2.gamepad_button_is_held(0, .Left_Face_Left) {
		move_direction.x = -1
	}

	if k2.key_is_held(.Right) || k2.gamepad_button_is_held(0, .Left_Face_Right) {
		move_direction.x = 1
	}

	if k2.key_went_down(.M) {
		game.audio_enabled = !game.audio_enabled
	}

	game.player_pos += normalize(move_direction) * 4

	game.enemy_pos += {-1, 0} * 8
	if game.enemy_pos.x < 0 {
		if game.audio_enabled {
			k2.play_sound(game.audio)
		}
		game.enemy_pos.x = 800
	}

	// Draw
	k2.clear(k2.LIGHT_BLUE)
	k2.draw_circle(game.player_pos, 10, {132, 59, 45, 255})
	k2.draw_circle(game.enemy_pos, 10, k2.LIGHT_BROWN)
	k2.present()
}

normalize :: proc(v: k2.Vec2) -> k2.Vec2 {
	if v.x * v.x + v.y * v.y <= 1e-12 {
		return v
	}
	return linalg.normalize(v)
}
