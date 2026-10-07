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
    # ReplMaker warns that '}' (bracket auto-close) is "overwritten"; it still runs on non-empty lines.
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        chat = initrepl(_chat_mode_parser;
                        repl,
                        prompt_text = _CHAT_PROMPT,
                        prompt_color = :cyan,
                        start_key = '}',
                        mode_name = "jail_chat",
                        completion_provider = FunctionCompletionProvider(_complete_chat_mode),
                        startup_text = false)
        _add_newline_keys!(chat)
    end
    agent = initrepl(_agent_mode_parser;
                     repl,
                     prompt_text = _agent_prompt,
                     prompt_color = :green,
                     start_key = '&',
                     mode_name = "jail_agent",
                     completion_provider = FunctionCompletionProvider(_complete_agent_mode),
                     startup_text = false)
    # ReplMaker only takes named/256 colors; the Julia logo purple needs 24-bit color.
    repl.hascolor && (agent.prompt_prefix = _rgb_escape(_CHAT_COLOR))
    _add_newline_keys!(agent)
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
