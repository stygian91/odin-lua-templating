package templating

import "core:slice"
import "core:c"
import lua "vendor:lua/5.4"

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
	lua.Integer,
	cstring,
	b32,
	map[cstring]Value,
}

TEMPLATE :: #load("./lua/engine.lua", cstring)

GLOBALS := [?]cstring{"pairs", "ipairs", "type", "table", "string", "math"}

run :: proc(template: cstring, values: map[cstring]Value) -> (res: cstring, err: Run_Error) {
	L := lua.L_newstate()
	defer lua.close(L)
	lua.L_openlibs(L)

	if (lua.L_dostring(L, TEMPLATE) != 0) {
		return res, Load_Engine_Error{}
	}

	lua.getfield(L, -1, "compile")
	lua.pushstring(L, template)

	lua.newtable(L)
	for name in GLOBALS {
		lua.getglobal(L, name)
		lua.setfield(L, -2, name)
	}

	lua.getglobal(L, "os")
	lua.getfield(L, -1, "date")
	lua.setfield(L, -3, "date")
	lua.pop(L, 1)

	_add_values(L, values) or_return

	if (lua.pcall(L, 2, lua.MULTRET, 0) != 0) {
		message := lua.tostring(L, -1)
		return res, Execute_Error{message}
	}

	res = lua.tostring(L, -1)

	return res, nil
}

@(private)
_add_values :: proc(L: ^lua.State, values: map[cstring]Value) -> (err: Run_Error) {
	for name, value in values {
		if slice.contains(GLOBALS[:], name) {
			return Global_Name_Conflict_Error{name}
		}

		switch v in value {
		case Nil:
			lua.pushnil(L)
		case lua.Number:
			lua.pushnumber(L, v)
		case lua.Integer:
			lua.pushinteger(L, v)
		case cstring:
			lua.pushstring(L, v)
		case b32:
			lua.pushboolean(L, v)
		case map[cstring]Value:
			lua.newtable(L)
			_add_values(L, v) or_return
		}

		lua.setfield(L, -2, name)
	}

	return nil
}
