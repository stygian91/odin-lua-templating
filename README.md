# What?
This is an Odin port of John Schember's small Lua template renderer, described in this article: https://nachtimwald.com/2014/08/06/using-lua-as-a-templating-engine/
A new addition that's not in the post is template nesting via the new `include` function.

Supports:
 * `{{ var }}` for printing variables.
 * `{% func }}` for running Lua functions (and code blocks in general).

Use `\{` to use a literal `{` in the template.

Multi-line strings in Lua blocks are supported but `[[` is not allowed. Use `[=[` or some other variation.

Template nesting is possible thanks to the provided C function: `include`. It takes 2 arguments:
 1. The template path (relative to the template root, that's provided in `new_engine`).
 2. A table of data, whose values will be available as global variables inside the nested template.

It returns a string with the result of applying the template. This string can then be used inside a `{% }}` block as any other Lua string, or it could be used inside a `{{ }}` block to render the nested template directly.

# Minimum supported lua version - 5.2

# Example

main.odin:
```Odin
#+feature dynamic-literals

package main

import "core:fmt"
// We're assuming that you've cloned the library in this directory
import t "./vendor/templating"

main :: proc() {
	template: cstring = `
You have access to the regular Lua globals. For example math.abs(-5) = {{ math.abs(-5) }}.
You also have access to any of the values you passed in from Odin. The meaning of life is {{ answer }}.
foo.bar = {{ foo.bar }}
Are hexagons the bestagons: {% if bestagons then }} true {% else }} false {% end }}

Loop:
{%
-- anything inside here is just a regular Lua block
for i, v in ipairs(arr) do }}i: {{ i }}; v: {{ v }}; {% end }}

Nesting: {{ include('foo.txt', {val = 69}) }}
Assigning the result of include to a variable: {% local res = include('foo.txt', {val=420}) }}
{{ res }}
{{ res }}
`

	arr := [?]t.Value{42, 3.14159}

	values := map[cstring]t.Value {
		"answer" = 42,
		"foo" = map[cstring]t.Value {"bar" = 6.9},
		"arr" = arr[:],
		"bestagons" = true,
	}
	defer delete(values["foo"].(map[cstring]t.Value))
	defer delete(values)

	// Note that calling `include` from within the template will be relative to this directory
	// An error will be returned if the path is outside of it
	engine, init_err := t.new_engine("./templates")
	if init_err != nil {
		fmt.printfln("init err: %s", init_err)
		return
	}
	defer t.delete_engine(engine)

	out, err := t.run(engine, template, values)
	if err != nil {
		fmt.printfln("err: %s", err)
		return
	}

	fmt.println(out)
}
```

templates/foo.txt:
```
val = {{ val }}
```
