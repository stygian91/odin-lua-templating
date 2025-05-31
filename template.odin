package templating

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os/os2"
import "core:slice"
import "core:strings"
import lua "vendor:lua/5.4"

Engine :: struct {
	L: ^lua.State,
}

Run_Error :: union {
	Load_Engine_Error,
	Global_Name_Conflict_Error,
	Execute_Error,
}

Load_Engine_Error :: distinct struct {}

Global_Name_Conflict_Error :: struct {
	name: cstring,
}

Execute_Error :: struct {
	message: cstring,
}

Nil :: distinct struct {}

Value :: union #no_nil {
	Nil,
	lua.Number,
	int,
	cstring,
	b32,
	map[cstring]Value,
	[]Value,
}

@(private)
TEMPLATE :: #load("./lua/engine.lua", cstring)

@(private)
GLOBALS := [?]cstring{"pairs", "ipairs", "type", "table", "string", "math"}

@(private)
MANUAL_GLOBALS := [?]cstring{"date", "include"}

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
	_add_values(L, values) or_return

	if (lua.pcall(L, 2, lua.MULTRET, 0) != 0) {
		message := lua.tostring(L, -1)
		return res, Execute_Error{message}
	}

	res = lua.tostring(L, -1)

	return res, nil
}

@(private)
@(require_results)
_add_values :: proc(L: ^lua.State, values: map[cstring]Value) -> (err: Run_Error) {
	for name, value in values {
		if slice.contains(GLOBALS[:], name) || slice.contains(MANUAL_GLOBALS[:], name) {
			return Global_Name_Conflict_Error{name}
		}

		switch v in value {
		case Nil:
			lua.pushnil(L)
		case lua.Number:
			lua.pushnumber(L, v)
		case int:
			lua.pushinteger(L, transmute(lua.Integer)v)
		case cstring:
			lua.pushstring(L, v)
		case b32:
			lua.pushboolean(L, v)
		case map[cstring]Value:
			lua.newtable(L)
			_add_values(L, v) or_return
		case []Value:
			lua.newtable(L)
			_add_array_values(L, v) or_return
		}

		lua.setfield(L, -2, name)
	}

	return nil
}

@(private)
@(require_results)
_add_array_values :: proc(L: ^lua.State, values: []Value) -> (err: Run_Error) {
	for value, i in values {
		switch v in value {
		case Nil:
			lua.pushnil(L)
		case lua.Number:
			lua.pushnumber(L, v)
		case int:
			lua.pushinteger(L, transmute(lua.Integer)v)
		case cstring:
			lua.pushstring(L, v)
		case b32:
			lua.pushboolean(L, v)
		case map[cstring]Value:
			lua.newtable(L)
			_add_values(L, v) or_return
		case []Value:
			lua.newtable(L)
			_add_array_values(L, v) or_return
		}

		lua.rawseti(L, -2, cast(lua.Integer)(i + 1))
	}

	return nil
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

	lua.pushcfunction(L, include)
	lua.setfield(L, -2, "include")
}

@(private)
include :: proc "c" (L: ^lua.State) -> c.int {
	context = CTX

	lua.getfield(L, lua.REGISTRYINDEX, "template_dir")
	template_dir := string(lua.tostring(L, -1))
	lua.pop(L, 1)

	size: c.size_t
	path_cstr := lua.L_checkstring(L, -2, &size)
	path := string(path_cstr)

	if !lua.istable(L, 2) {
		lua.L_error(L, "expected second argument to be a table")
		return 0
	}

	// TODO: this path handling is a bit messy, maybe put it in a private function
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

	lua.insert(L, -2)
	lua.pop(L, 1)

	lua.newtable(L)
	_add_globals(L)
	_shallow_merge(L, -2)

	// put table at the top
	lua.insert(L, -2)
	lua.pop(L, 1)

	// put file contents second
	lua.pushstring(L, file_data_cstr)
	lua.insert(L, -2)

	// get the compile function and put it at the bottom
	lua.getfield(L, lua.REGISTRYINDEX, "engine")
	lua.getfield(L, -1, "compile")
	lua.insert(L, -4)
	// remove the engine module
	lua.pop(L, 1)

	if (lua.pcall(L, 2, lua.MULTRET, 0) != 0) {
		message := lua.tostring(L, -1)
		lua.L_error(L, message)
		return 0
	}

	return 1
}

@(private)
_clean_stack :: proc(L: ^lua.State, size_before: c.int) {
	size_after := lua.gettop(L)
	size_diff := size_after - size_before
	if size_diff > 0 {
		lua.pop(L, size_diff)
	}
}

// Expects the destination table to be at the top
@(private)
_shallow_merge :: proc(L: ^lua.State, from_idx: c.int) {
	lua.pushnil(L)
	for lua.next(L, from_idx) != 0 {
		lua.pushvalue(L, -2)
		lua.insert(L, -2)
		lua.settable(L, -4)
	}
}
