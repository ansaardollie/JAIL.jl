# Preferences are always read at call time so edits apply without a restart.

_load_pref(key::AbstractString, default = nothing) = load_preference(@__MODULE__, key, default)
_save_pref!(key::AbstractString, value) = set_preferences!(@__MODULE__, key => value; force = true)
_delete_pref!(key::AbstractString) = delete_preferences!(@__MODULE__, key; force = true)

# deepcopy: the loaded Dict is Base's cached TOML and must not be mutated
_provider_prefs() = Dict{String,Any}(deepcopy(_load_pref("providers", Dict{String,Any}())))
_provider_prefs(name::AbstractString) = get(_provider_prefs(), name, Dict{String,Any}())

# set_preferences! replaces the whole table rather than merging, so write it back in full
function _save_provider_prefs!(name::AbstractString, table::AbstractDict)
    all = _provider_prefs()
    isempty(table) ? delete!(all, name) : (all[name] = Dict{String,Any}(table))
    isempty(all) ? _delete_pref!("providers") : _save_pref!("providers", all)
    return nothing
end
