const _REPL_INSTALLED = Ref(false)

function _install_repl_modes(repl)
    _REPL_INSTALLED[] && return nothing
    initrepl(_model_mode_parser;
             repl,
             prompt_text = _model_prompt,
             prompt_color = :magenta,
             start_key = '|',
             mode_name = "jail_model",
             completion_provider = FunctionCompletionProvider(_complete_model_mode),
             startup_text = false)
    _REPL_INSTALLED[] = true
    return nothing
end

function _try_install_repl_modes(repl)
    repl isa REPL.LineEditREPL || return nothing
    try
        _install_repl_modes(repl)
    catch e
        @warn "JAIL could not install its REPL modes" exception = (e, catch_backtrace())
    end
    return nothing
end

function _init_repl_modes()
    _load_pref("repl_modes", true) === false && return nothing
    isinteractive() || return nothing
    if isdefined(Base, :active_repl)
        _try_install_repl_modes(Base.active_repl)
    else
        atreplinit(_try_install_repl_modes)
    end
    return nothing
end
