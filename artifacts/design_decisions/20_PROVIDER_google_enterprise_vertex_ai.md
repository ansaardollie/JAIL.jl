# Decision: GoogleEnterprise (Vertex AI) as a distinct provider

| Field | Value |
|-------|-------|
| Artifact | `20_PROVIDER_google_enterprise_vertex_ai.md` |
| Category | design_decisions |
| Subject | `PROVIDER` |
| Date | 2026-09-29 |
| Area/Purpose scope | core ontology, provider config, auth |
| Related | `1_PROVIDER_configurable_instances.md`, `3_PREFERENCES_nested_layout.md` |
| Status | accepted |
| Decided by | user (type name, abstraction, config fields, token cache location, list_models behavior, staging); agent (wire-format reuse mechanics, internal helpers) |

## Context

The owner wants Google models reachable through both the Gemini Developer API (`Google`,
existing) and the Gemini Enterprise Agent Platform / Vertex AI on GCP. The owner supplied:
`libs/python-genai` (the canonical Python SDK, which supports both), an AI Platform v1 REST
discovery doc (`artifacts/provider_docs/google/ai-platform-spec.json`), and a new
`src/gcp_auth.jl` implementing GCP OAuth2 token retrieval (ADC / service account / metadata
server), asking for an `AccessKey`-style struct (token + expiry = generation time + 55 min) with
automatic refresh-on-use.

Investigation of `python-genai`'s `_api_client.py` and `_gaos/google_genai.py` showed the
Interactions API (the wire format `Google` already uses) is also reachable on Vertex AI: same
request/response schema, different base URL
(`https://{location}-aiplatform.googleapis.com`, or `https://aiplatform.googleapis.com` for
`location = "global"`), different `api_version` (`v1beta1` vs `v1beta`), a
`projects/{project}/locations/{location}/` path prefix, and Bearer-token auth instead of an
`x-goog-api-key` header. `ai-platform-spec.json` (the older public discovery doc) has no
`interactions` resource and no `publishers.models.list`; only `generateContent` /
`streamGenerateContent` / `publishers.models.get` are documented there. The owner confirmed
Interactions is still the intended wire format (citing `interactions.openapi.json`, v1beta).

## The Question

1. What is the new type called, and does it share an abstract parent with `Google`?
2. What connection config does it carry?
3. Where does the live access-token cache live, given providers are immutable value structs?
4. What does `list_models` do, given Vertex has no listing endpoint?
5. Build everything in one pass, or stage it?

## Options Considered

1. Type name: `GoogleEnterprise` (chosen) vs `GoogleVertex` vs `VertexAI`.
2. Abstraction: shared `AbstractGoogleProvider <: AbstractProvider` (rejected by the owner) vs
   fully independent `GoogleEnterprise <: AbstractProvider` (chosen), with wire-format code reused
   through plain `Union{Google,GoogleEnterprise}`-typed private functions instead of a type
   hierarchy.
3. Config fields: project+location only, auto-detected credentials (agent's first suggestion) vs
   **project + location + optional `service_account_path` override (chosen)** vs
   project + location + a `credentials_env` naming an env var.
4. Token cache: a `Base.RefValue` field on the provider struct, excluded from Preferences and
   from equality (chosen) vs a process-wide `Dict` keyed by (project, location).
5. `list_models`: throw a clear "not supported, construct a model directly" error (chosen) vs a
   hardcoded list of known ids.
   > **Erratum (2026-09-29):** the owner found the real endpoint by hand
   > (`GET /v1beta1/publishers/google/models`, global host, `x-goog-user-project` header,
   > page-token pagination, max `pageSize` 300) — see `work_history/15_PROVIDER_google_enterprise_list_models.md`.
   > `list_models(GoogleEnterprise())` now hits it for real instead of throwing. It has no
   > capability field (unlike the Developer API's `supportedGenerationMethods`), so results are
   > unfiltered.
6. Scope: stage it — text turns first, checkpoint, then tools, then streaming (chosen) vs the
   full surface in one pass.

## Decision

```julia
struct GoogleEnterprise <: AbstractProvider
    project::String
    location::String
    service_account_path::Union{Nothing,String}
    _token::Base.RefValue{Union{Nothing,_GCPAccessKey}}
end

GoogleEnterprise(; project = "acme", location = "us-central1")   # no built-in default; throws if unset
configure_provider!(GoogleEnterprise(; project = "acme", location = "us-central1"))  # persist
Model("google_enterprise/gemini-2.5-flash")
```

- `provider_name(::Type{GoogleEnterprise}) = "google_enterprise"`; `api_version = "v1beta1"`.
- Request URL: `https://{location}-aiplatform.googleapis.com/v1beta1/projects/{project}/locations/{location}/interactions`
  (`location == "global"` drops the region prefix from the host).
- Auth: `Authorization: Bearer <token>`, never an API key. Token source priority:
  `service_account_path` → `ENV["GOOGLE_APPLICATION_CREDENTIALS"]` → the well-known ADC file
  (`gcloud auth application-default login`) → the GCE/GKE metadata server (`gcp_auth.jl`,
  provider-agnostic). Cached on the instance, refreshed when `now() >= expires`; expiry is
  generation time + 55 minutes (fixed, per the owner's spec — not driven by the token response's
  `expires_in`).
- Wire format: `_request_body`, `_parse_reply` and `_GoogleStream`/`_stream_state` widened from
  `p::Google` to `p::Union{Google,GoogleEnterprise}` (they never touched provider-instance
  fields), so `GoogleEnterprise` gets tool calling, streaming and server-side chaining
  (`store`/`previous_interaction_id`) for free, unverified against a live Vertex project.
- Not in `_FIRST_PARTY`/`_FirstParty` (those assume a zero-arg constructor always succeeds, which
  `GoogleEnterprise` can't guarantee without a saved project). Instead it follows the
  `OpenAICompatible` pattern: discoverable via a `"type" => "google_enterprise"` marker in
  `providers.google_enterprise` Preferences, picked up by `_provider(name)` and `providers()`.
  Since there is only one such provider (no owner-chosen name like `OpenAICompatible`), no
  `register_provider!` step is needed — `configure_provider!` works directly.
- `Base.:(==)` is defined explicitly for `GoogleEnterprise` (ignoring `_token`), since the
  in-memory access-token cache must not affect provider identity (used by
  `set_default_model!`'s "is this the same instance the default names" check).
- `_settings(::GoogleEnterprise) = (:project, :location, :service_account_path)`; `project` and
  `location` can't be cleared to `nothing` via `configure_provider!` (no default to fall back
  to, matching `OpenAICompatible`'s `base_url` rule); `service_account_path` can.

## Consequences

- Dates.jl added as a dependency (stdlib) for the token's `expires::DateTime`.
- `gcp_auth.jl` rewritten from its initial draft: flattened out of its own submodule to match the
  rest of `src/` (single flat `JAIL` namespace), bugs fixed (missing `using` for
  `Base64`/`MbedTLS`/`Random`; `JSON.parsefile` returns a `Dict`, so `creds.client_id`-style
  dot-access was replaced with `creds["client_id"]`).
- `list_models`, tool calling and streaming are exercised for `Google` already; for
  `GoogleEnterprise` only the OAuth token fetch (real ADC on the dev machine) and the
  request-URL/body/config plumbing have been verified. Tool calling and streaming against a real
  Vertex AI project are explicitly deferred to the next stage.

## Revisit Trigger

- A live `chat!` call against a real Vertex AI project surfaces a wire-format difference from the
  Developer API (e.g. a field Vertex requires that the Developer API doesn't, or vice versa) —
  the shared `Union{Google,GoogleEnterprise}` functions would need to split.
- A need for the multi-regional `.rep.googleapis.com` routing or Vertex AI Express Mode (API-key
  auth on Vertex) that `python-genai`'s `_api_client.py` also implements but this decision
  skipped.
- A need for more than one `GoogleEnterprise` configuration at once (e.g. two GCP projects), which
  the current single well-known-name scheme (unlike `OpenAICompatible`) can't express.
