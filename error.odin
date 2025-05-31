package templating

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
