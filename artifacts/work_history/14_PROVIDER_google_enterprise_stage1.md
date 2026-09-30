# GoogleEnterprise (Vertex AI) — stage 1: config, auth, text-turn wire format

| Field | Value |
|-------|-------|
| Artifact | `14_PROVIDER_google_enterprise_stage1.md` |
| Category | work_history |
| Subject | `PROVIDER` |
| Date | 2026-09-29 |
| Area/Purpose scope | core ontology, provider config, auth, examples |
| Related | `design_decisions/20_PROVIDER_google_enterprise_vertex_ai.md` |

## Scope of This Unit of Work

User request: support the Gemini Enterprise Agent Platform (Vertex AI / GCP) as a second Google
provider flavor, alongside the existing Developer API `Google`. Context supplied: `libs/python-genai`
(reference SDK covering both), `artifacts/provider_docs/google/ai-platform-spec.json` (AI Platform
v1 REST discovery doc), and a draft `src/gcp_auth.jl` for GCP OAuth2 token retrieval (ADC / service
account / metadata server) with a token+expiry cache (expiry = fetch time + 55 min, refreshed
automatically on use). Staged per the owner's answer: this unit covers config, auth and text
turns; tool calling and streaming against a live Vertex project are explicitly deferred.

## What Changed

| File | Change |
|-------|--------|
| `src/gcp_auth.jl` | Rewritten: flattened out of its own submodule (matches the rest of `src/`'s single flat `JAIL` namespace); fixed missing `using Base64`/`MbedTLS`/`Random`; fixed `JSON.parsefile` (returns a `Dict`, so `creds.client_id` → `creds["client_id"]`). New `_GCPAccessKey` (token + expiry), `_is_expired`, `_fetch_gcp_access_token(path)` (priority: explicit path → `GOOGLE_APPLICATION_CREDENTIALS` → well-known ADC file → GCE/GKE metadata server) |
| `src/providers/google.jl` | New `GoogleEnterprise <: AbstractProvider` (`project`, `location`, `service_account_path`, cached `_token::Base.RefValue`); custom `Base.:(==)` ignoring the token cache; `provider_name`, `api_version = "v1beta1"`, `_gcp_location_url`, `_gcp_access_token` (cache/refresh), `_auth_headers` (Bearer token), `_request_url` (project/location-scoped Interactions path), `_has_store_field`/`_supports_chaining`/`_supports_streaming = true`, `_list_models` throws (no Vertex listing endpoint). `_request_body`, `_parse_reply`, `_stream_state` widened from `p::Google` to `p::Union{Google,GoogleEnterprise}` (unchanged bodies — they never read provider-instance fields) |
| `src/configuration.jl` | `_provider`/`providers()` extended with a `"type" => "google_enterprise"` branch (mirrors the `OpenAICompatible` marker pattern, but no `register_provider!` step — single well-known provider, not owner-named); `_to_prefs`/`_settings`/`_with` overloads for `GoogleEnterprise`; `configure_provider!` docstring updated |
| `src/JAIL.jl` | `include("gcp_auth.jl")` (before `providers/google.jl`); exports `GoogleEnterprise`; `Pkg.add("Dates")` (stdlib, for the token's `DateTime` expiry) |
| `examples/providers_and_models.jl` | New sections: constructing `GoogleEnterprise`, the "no project/location saved" error, `configure_provider!` round-trip, `project`/`location` not clearable, `Model("google_enterprise/...")`, `list_models` unsupported error. Also moved `show_error`'s definition before its first use (pre-existing ordering bug that blocked running the file top-to-bottom in one pass) |
| `artifacts/design_decisions/20_PROVIDER_google_enterprise_vertex_ai.md` | Records the type name, abstraction choice (independent type, not a shared `AbstractGoogleProvider`), config fields, token-cache location, `list_models` behavior, and staging, all via ask-questions |

## Verification

Julia 1.13.0, `JAIL.jl` project. `import JAIL` failed to precompile once (forward reference:
`GoogleEnterprise` used in a `Union` signature before its `struct` was defined further down the
file) — fixed by moving the struct + `==` above the shared functions; then:

```julia
julia --project=. -e 'using JAIL; println("OK")'   # OK
```

Restarted the REPL, then (with the owner's real `LocalPreferences.toml` snapshotted via
`JAIL._load_pref("providers"/"default_model")` and restored afterwards — see the repo-memory note
this added about that):

```julia
p = GoogleEnterprise(; project="my-proj", location="us-central1")
JAIL._request_url(p)
# "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/my-proj/locations/us-central1/interactions"
p == GoogleEnterprise(; project="my-proj", location="us-central1")   # true (token cache ignored)
p === GoogleEnterprise(; project="my-proj", location="us-central1")  # false

GoogleEnterprise()   # ArgumentError: GoogleEnterprise needs a project; ...
configure_provider!(GoogleEnterprise(; project="acme", location="global"))
GoogleEnterprise()   # now loads project/location from Preferences
Model("google_enterprise/gemini-2.5-flash")   # Model("google_enterprise/gemini-2.5-flash")
[provider_name(pp) for pp in providers()]     # [..., "google_enterprise"]

# Real OAuth token fetch (the dev machine has `gcloud auth application-default login` set up):
JAIL._gcp_access_token(p)      # a real ~250-char access token, via the ADC file path
p._token[].expires - now()     # ≈ 55 minutes
```

Ran the full `examples/providers_and_models.jl` (via a `LIVE = false` copy, to avoid real network
calls against OpenAI/Anthropic/Google) — every `@show`/`show_error` line, including all the new
`GoogleEnterprise` ones, produced the expected output with no exceptions escaping the intended
error demos. `LocalPreferences.toml` snapshotted before and restored to byte-identical content
after (confirmed by re-reading the file).

## Note

Mid-session, an early interactive test called `configure_provider!` against the *real*
`LocalPreferences.toml` (not a sandbox) and then `JAIL._delete_pref!("providers")`, which wiped the
owner's existing `anthropic`/`google`/`openai` `default_model` entries. Caught immediately and
restored from the values read at the start of the session; `git diff LocalPreferences.toml` shows
no residual change. Added a repo-memory note (`/memories/repo/jail-notes.md`) to snapshot/restore
around any Preferences-mutating call in this workspace going forward.

## Gaps / Next Stage

- Tool calling and streaming reuse `Google`'s code via the widened `Union` signatures but are
  **unverified against a live Vertex AI project** — only the OAuth token fetch and the URL/config
  plumbing were exercised for real.
- No live `chat!` call was attempted (would need a real GCP project with Vertex AI enabled and the
  owner's go-ahead per the mode's "live calls only when asked" rule).
- Vertex AI Express Mode (API-key auth on Vertex) and multi-regional `.rep.googleapis.com` routing,
  both present in `python-genai`, were not implemented — out of scope per the chosen config fields
  (project + location + optional service-account path only).
