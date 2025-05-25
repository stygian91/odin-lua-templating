package template

import "core:slice"
import lua "vendor:lua/5.4"

Run_Error :: union {
  Prepare_Error,
  Execute_Error,
}

Prepare_Error :: enum {
	Load_Engine,
  Global_Variable_Name_Conflict,
}

Execute_Error :: struct {
  message: cstring
}

Nil :: distinct struct {}

Value :: union #no_nil {
	Nil,
	lua.Number,
	lua.Integer,
	cstring,
	b32,
}

TEMPLATE :: #load("./lua/engine.lua", cstring)

GLOBALS := [?]cstring{"pairs", "ipairs", "type", "table", "string", "math"}

run :: proc(template: cstring, values: map[cstring]Value) -> (res: cstring, err: Run_Error) {
	L := lua.L_newstate()
	defer lua.close(L)
	lua.L_openlibs(L)

	if (lua.L_dostring(L, TEMPLATE) != 0) {
		return res, .Load_Engine
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

	for name, value in values {
    if slice.contains(GLOBALS[:], name) {
      return res, .Global_Variable_Name_Conflict
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
		}

		lua.setfield(L, -2, name)
	}

	if (lua.pcall(L, 2, lua.MULTRET, 0) != 0) {
    message := lua.tostring(L, -1)
    return res, Execute_Error{message}
  }

  res = lua.tostring(L, -1)

  return res, nil
}
