package templating

import "base:runtime"
import "core:c"
import "core:os/os2"
import "core:strings"
import lua "vendor:lua/5.4"

Engine :: struct {
	L: ^lua.State,
}

@(private)
TEMPLATE :: #load("./lua/engine.lua", cstring)

@(private)
GLOBALS := [?]cstring{"pairs", "ipairs", "type", "table", "string", "math"}

@(private)
MANUAL_GLOBALS := [?]cstring{"date"}

@(private)
CTX := runtime.default_context()

@(require_results)
new_engine :: proc(template_dir: cstring) -> (engine: Engine, err: Run_Error) {
	L := lua.L_newstate()
	lua.L_openlibs(L)
	engine = Engine{L}

	clean_dir, clean_err := os2.clean_path(string(template_dir), context.allocator)
	if clean_err != nil {
		return engine, Load_Engine_Error{}
	}
	defer delete(clean_dir)

	absolute_dir, abs_err := os2.get_absolute_path(clean_dir, context.allocator)
	if abs_err != nil {
		return engine, Load_Engine_Error{}
	}
	defer delete(absolute_dir)

	abs_cstr, alloc_err := strings.clone_to_cstring(absolute_dir)
	if alloc_err != nil {
		return engine, Load_Engine_Error{}
	}
	defer delete(abs_cstr)

	lua.pushstring(L, abs_cstr)
	lua.setfield(L, lua.REGISTRYINDEX, "template_dir")

	if (lua.L_dostring(L, TEMPLATE) != 0) {
		return engine, Load_Engine_Error{}
	}

	lua.pushcfunction(L, read_template)
	lua.setfield(L, -2, "read_template")
	lua.setfield(L, lua.REGISTRYINDEX, "engine")

	return
}

delete_engine :: proc(engine: Engine) {
	lua.close(engine.L)
}

@(require_results)
run :: proc(
	engine: Engine,
	template: cstring,
	values: map[cstring]Value,
) -> (
	res: cstring,
	err: Run_Error,
) {
	L := engine.L

	size_before := lua.gettop(L)
	defer _clean_stack(L, size_before)

	lua.getfield(L, lua.REGISTRYINDEX, "engine")
	lua.getfield(L, -1, "compile")
	lua.pushstring(L, template)

	lua.newtable(L)
	_add_globals(L)
	_add_values(L, values, true) or_return

	if (lua.pcall(L, 2, lua.MULTRET, 0) != 0) {
		message := lua.tostring(L, -1)
		return res, Execute_Error{message}
	}

	res = lua.tostring(L, -1)

	return res, nil
}

@(private)
_add_globals :: proc(L: ^lua.State) {
	for name in GLOBALS {
		lua.getglobal(L, name)
		lua.setfield(L, -2, name)
	}

	lua.getglobal(L, "os")
	lua.getfield(L, -1, "date")
	lua.setfield(L, -3, "date")
	lua.pop(L, 1)
}

@(private)
_clean_stack :: proc(L: ^lua.State, size_before: c.int) {
	size_after := lua.gettop(L)
	size_diff := size_after - size_before
	if size_diff > 0 {
		lua.pop(L, size_diff)
	}
}

@(private)
read_template :: proc "c" (L: ^lua.State) -> c.int {
	context = CTX

	size: c.size_t
	path_cstr := lua.L_checkstring(L, -1, &size)
	path := string(path_cstr)
	lua.pop(L, 1)

	lua.getfield(L, lua.REGISTRYINDEX, "template_dir")
	template_dir := string(lua.tostring(L, -1))
	lua.pop(L, 1)

	joins_paths := [?]string{template_dir, path}
	path_joined, join_err := os2.join_path(joins_paths[:], context.allocator)
	if join_err != nil {
		lua.L_error(L, "error while joining template path with template dir path")
		return 0
	}
	defer delete(path_joined)

	path_absolute, path_abs_err := os2.get_absolute_path(path_joined, context.allocator)
	if path_abs_err != nil {
		lua.L_error(L, "error while resolving absolute template path")
		return 0
	}
	defer delete(path_absolute)

	rel_to_base_path, rel_err := os2.get_relative_path(
		template_dir,
		path_absolute,
		context.allocator,
	)
	if rel_err != nil {
		lua.L_error(L, "error while checking if template path is in the template dir")
		return 0
	}
	defer delete(rel_to_base_path)

	if strings.contains(rel_to_base_path, "..") {
		lua.L_error(L, "Trying to read template file that's outside of the template dir")
		return 0
	}

	file_data, read_err := os2.read_entire_file_from_path(path_absolute, context.allocator)
	if read_err != nil {
		lua.L_error(L, "Error while reading template file")
		return 0
	}
	defer delete(file_data)
	file_data_cstr := strings.clone_to_cstring(string(file_data), context.allocator)
	defer delete(file_data_cstr)

	lua.pushstring(L, file_data_cstr)

	return 1
}
