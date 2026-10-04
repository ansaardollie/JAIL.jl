# Google ADC invalid_rapt reauthentication hint

| Field | Value |
|-------|-------|
| Artifact | `20_PROVIDER_google_adc_reauth.md` |
| Category | work_history |
| Subject | `PROVIDER` — Google Enterprise authentication |
| Date | 2026-10-04 |
| Area/Purpose scope | provider authentication, diagnostics |
| Related | `design_decisions/20_PROVIDER_google_enterprise_vertex_ai.md`, `design_decisions/21_PROVIDER_google_enterprise_generate_content.md` |

## Scope of This Unit of Work

The owner requested actionable guidance when Google Enterprise's Application Default Credentials token refresh fails with HTTP 400 and Google's `invalid_rapt` reauthentication error. Existing Google Enterprise auth behavior and credential sources remain unchanged.

## What Changed

| File | Change |
|-------|--------|
| `src/gcp_auth.jl` | Added `_gcp_adc_token_error(status, body)` and used it in `_gcp_token_from_adc`. For HTTP 400 JSON containing `error_subtype = "invalid_rapt"` or an `error_description` containing `invalid_rapt`, the existing error text is retained and a message advises running `gcloud auth application-default login`. Other statuses and unrelated errors keep the existing generic error text. |

## Design Decisions Made

No public API or architectural decision was needed. Detection is limited to the ADC refresh path; service-account and metadata-server failures are untouched. Malformed response JSON and HTTP 400 errors without `invalid_rapt` retain the generic error.

## Verification

Julia REPL check:

```julia
using JAIL
body = """{
  "error": "invalid_grant",
  "error_description": "reauth related error (invalid_rapt)",
  "error_uri": "https://support.google.com/a/answer/9368756",
  "error_subtype": "invalid_rapt"
}"""
matched = JAIL._gcp_adc_token_error(400, body)
@assert occursin("gcloud auth application-default login", matched)
@assert occursin("HTTP 400", matched)
@assert !occursin("gcloud auth application-default login", JAIL._gcp_adc_token_error(400, "{\"error\":\"invalid_grant\"}"))
@assert !occursin("gcloud auth application-default login", JAIL._gcp_adc_token_error(401, body))
println("ADC invalid_rapt diagnostic checks passed")
```

Output:

```text
ADC invalid_rapt diagnostic checks passed
Failed to fetch access token (HTTP 400): {
  "error": "invalid_grant",
  "error_description": "reauth related error (invalid_rapt)",
  "error_uri": "https://support.google.com/a/answer/9368756",
  "error_subtype": "invalid_rapt"
}
Google Application Default Credentials require reauthentication. Run `gcloud auth application-default login` in your terminal, then retry.
```

`get_errors` reported no errors in `src/gcp_auth.jl`.

## Known Limitations

No live Google token request was made. The response matching and non-matching cases were checked directly through the formatter.

## Todos

- Completed: none.
- Created: none.

## Next Steps

1. None for this change.
