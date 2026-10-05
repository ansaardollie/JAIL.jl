# Built-in tools

```@meta
CurrentModule = JAIL
```

The tools listed by [`builtin_tools`](@ref), grouped as in the
[Tools guide](guide/tools.md#Built-in-tools), where their security levels, the workspace and
protected-path rules, and opting in are explained. They are not exported; their docstrings are
the descriptions the model sees.

## read

```@docs
read_file
list_dir
find_files
grep_files
check_julia_syntax
git_changes
```

## inspect

```@docs
julia_source_method
julia_source_methods
julia_source_struct
julia_source_module
julia_docs
find_julia_symbols
pkg_status
repl_history
last_result
```

## edit

```@docs
create_file
create_directory
replace_in_file
replace_in_files
```

## execute

```@docs
execute_julia_code
run_shell
run_tests
pkg_add
```

## web

```@docs
fetch_url
```

## interact

```@docs
ask_user
```
