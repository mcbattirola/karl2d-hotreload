package hotreload

// Inspired by
// https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/main/source/main_hot_reload/main_hot_reload.odin

import k2 "../karl2d"
import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:path/filepath"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

GAME_DLL_DIR :: "out/hotreload/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	copy_err := os2.copy_file(to, GAME_DLL_PATH)

	if copy_err != nil {
		fmt.printfln("Failed to copy " + GAME_DLL_PATH + " to {0}: %v", to, copy_err)
		return false
	}

	return true
}

Game_API :: struct {
	lib:                dynlib.Library,
	game_init:          proc(_: ^k2.State),
	game_shutdown:      proc(),
	game_should_run:    proc() -> bool,
	game_update:        proc(),
	game_memory:        proc() -> (rawptr, rawptr),
	game_memory_size:   proc() -> int,
	game_hot_reloaded:  proc(mem: rawptr, k2mem: rawptr),
	game_force_reload:  proc() -> bool,
	game_force_restart: proc() -> bool,
	modification_time:  os.File_Time,
	api_version:        int,
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name(GAME_DLL_PATH)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of " + GAME_DLL_PATH + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	game_dll_name := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api_version)
	copy_dll(game_dll_name) or_return
	fmt.printfln("game dll name: %s", game_dll_name)

	// This proc matches the names of the fields in Game_API to symbols in the
	// game DLL.
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln(
			"Failed to remove {0}game_{1}" + DLL_EXT + " copy",
			GAME_DLL_DIR,
			api.api_version,
		)
	}
}

main :: proc() {
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)

	context.logger = log.create_console_logger()

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)
	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1

	k2state := k2.init(800, 600, "Karl2D hot reload")

	game_api.game_init(k2state)

	old_game_apis := make([dynamic]Game_API, default_allocator)

	for game_api.game_should_run() {
		game_api.game_update()
		force_reload := game_api.game_force_reload()
		force_restart := game_api.game_force_restart()
		reload := force_reload || force_restart
		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(GAME_DLL_PATH)

		if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
			reload = true
		}

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version)

			if new_game_api_ok {
				force_restart =
					force_restart || game_api.game_memory_size() != new_game_api.game_memory_size()

				if !force_restart {
					// This does the normal hot reload

					// Note that we don't unload the old game APIs because that
					// would unload the DLL. The DLL can contain stored info
					// such as string literals. The old DLLs are only unloaded
					// on a full reset or on shutdown.
					append(&old_game_apis, game_api)
					game_memory, _ := game_api.game_memory()
					game_api = new_game_api
					game_api.game_hot_reloaded(game_memory, k2state)
				} else {
					// This does a full reset. That's basically like opening and
					// closing the game, without having to restart the executable.
					//
					// You end up in here if the game requests a full reset OR
					// if the size of the game memory has changed. That would
					// probably lead to a crash anyways.

					game_api.game_shutdown()

					for &g in old_game_apis {
						unload_game_api(&g)
					}

					clear(&old_game_apis)
					unload_game_api(&game_api)

					reset_tracking_allocator(&tracking_allocator)

					game_api = new_game_api

					game_api.game_init(k2state)
				}

				game_api_version += 1
			}
		}

		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}

			// This prevents the game from closing without you seeing the bad
			// frees. This is mostly needed because I use Sublime Text and my game's
			// console isn't hooked up into Sublime's console properly.
			libc.getchar()
			panic("Bad free detected")
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_api.game_shutdown()
	if reset_tracking_allocator(&tracking_allocator) {
		// This prevents the game from closing without you seeing the memory
		// leaks. This is mostly needed because I use Sublime Text and my game's
		// console isn't hooked up into Sublime's console properly.
		libc.getchar()
	}

	for &g in old_game_apis {
		unload_game_api(&g)
	}

	delete(old_game_apis)

	k2.shutdown()

	unload_game_api(&game_api)
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// Make game use good GPU on laptops.
@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
