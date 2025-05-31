package templating

import "core:slice"
import lua "vendor:lua/5.4"

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
