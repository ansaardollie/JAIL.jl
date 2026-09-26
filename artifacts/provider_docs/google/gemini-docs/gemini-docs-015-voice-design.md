Voice design lets you create a brand-new, persistent vocal persona from a
natural-language description using the Gemini API Voices endpoint
(`POST /v1beta/voices`). Instead of being limited to prebuilt voices or
recording reference audio, you can describe a character's age, vocal timbre,
accent, and baseline delivery, and receive a reusable `voice_...` ID saved to
your project.

The fastest way to design, audition, and iterate on custom voices is with the
interactive **Voice Design** studio in
[Google AI Studio](https://aistudio.google.com/generate-speech). You can
generate custom personas from text prompts, test them with sample scripts, and
copy the resulting `voice_...` ID directly into your application code.
[Try in Google AI Studio](https://aistudio.google.com/generate-speech)

Both [Gemini 3.8 Flash TTS](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash-tts)
(`gemini-3.8-flash-tts`) and
[Gemini 3.8 Flash-Lite TTS](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash-lite-tts)
(`gemini-3.8-flash-lite-tts`) support Voice design.

## Create a designed voice

Use the Google GenAI SDK (`google-genai` 2.25.0+ / `@google/genai` 2.24.0+) or REST API
to create a custom voice from a text description. For `"prompted"` voices, both
`voices.create` (`CreateVoice`) and `voices.get` (`GetVoice`) return an
output-only `sample_audio` field (`mime_type: "audio/wav"`, base64-encoded
`data`) so you can immediately audition the generated voice:

### Python

    import base64
    from google import genai

    client = genai.Client()

    # 1. Design a custom voice persona from natural language
    created_voice = client.voices.create(
        store=True,
        voice={
            "model": "gemini-3.8-flash-tts",
            "type": "prompted",
            "display_name": "Warm British Astronomer",
            "gender": "male",
            "language_code": "en-GB",
            "prompted": {
                "input": (
                    "A warm, thoughtful astronomer in his late 60s with a gentle"
                    " British accent, speaking with quiet wonder."
                )
            },
        },
    )

    print(f"Created voice ID: {created_voice.id}")

    # Save the generated sample_audio preview (audio/wav) returned by CreateVoice
    if created_voice.sample_audio and created_voice.sample_audio.data:
        with open("voice_preview.wav", "wb") as f:
            f.write(base64.b64decode(created_voice.sample_audio.data))

### JavaScript

    import * as fs from "node:fs";
    import { GoogleGenAI } from "@google/genai";

    const ai = new GoogleGenAI();

    // 1. Design a custom voice persona from natural language
    const createdVoice = await ai.voices.create({
      store: true,
      voice: {
        model: "gemini-3.8-flash-tts",
        type: "prompted",
        display_name: "Warm British Astronomer",
        gender: "male",
        language_code: "en-GB",
        prompted: {
          input:
            "A warm, thoughtful astronomer in his late 60s with a gentle British accent, speaking with quiet wonder.",
        },
      },
    });

    console.log(`Created voice ID: ${createdVoice.id}`);

    // Save the generated sample_audio preview (audio/wav) returned by CreateVoice
    if (createdVoice.sample_audio?.data) {
      fs.writeFileSync(
        "voice_preview.wav",
        Buffer.from(createdVoice.sample_audio.data, "base64")
      );
    }

### REST

    curl "https://generativelanguage.googleapis.com/v1beta/voices" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -X POST \
      -d '{
        "store": true,
        "voice": {
          "model": "gemini-3.8-flash-tts",
          "type": "prompted",
          "display_name": "Warm British Astronomer",
          "gender": "male",
          "language_code": "en-GB",
          "prompted": {
            "input": "A warm, thoughtful astronomer in his late 60s with a gentle British accent, speaking with quiet wonder."
          }
        }
      }' | tee created_voice.json | jq -r '.sample_audio.data' | base64 --decode > voice_preview.wav

## How Voice design works

1. **Create a prompted voice:** Call `voices.create` (`POST /v1beta/voices`) with `type="prompted"` and `store=True`.
2. **Receive a persistent `voice_id` and `sample_audio` preview:** The API generates the vocal identity, stores it in your project, and returns a permanent ID (for example, `voice_abc123...`) along with `sample_audio` (`mime_type: "audio/wav"`, base64-encoded `data`) containing the generated preview audio for the voice.
3. **Synthesize speech:** Pass the `voice_id` anywhere a voice name is accepted in your synthesis requests.

## Synthesize speech with your designed voice

Once you have created a voice, pass its `id` (`voice_...`) to the Interactions
API to generate speech:

### Python

    import base64
    from google import genai

    client = genai.Client()

    interaction = client.interactions.create(
        model="gemini-3.8-flash-tts",
        input=[{
            "type": "user_input",
            "content": [{
                "type": "text",
                "text": (
                    "Look out past the rings of Saturn. Those faint photons left"
                    " their source millions of years ago."
                ),
                "annotations": [{
                    "type": "speech_metadata",
                    "style": "reflective and awe-inspired",
                }],
            }],
        }],
        response_format={"type": "audio"},
        generation_config={
            "speech_config": [
                {"voice": created_voice.id},
            ]
        },
    )

    with open("designed_voice.wav", "wb") as f:
        f.write(base64.b64decode(interaction.output_audio.data))

### JavaScript

    import * as fs from "node:fs";
    import { GoogleGenAI } from "@google/genai";

    const ai = new GoogleGenAI();

    const interaction = await ai.interactions.create({
      model: "gemini-3.8-flash-tts",
      input: [{
        type: "user_input",
        content: [{
          type: "text",
          text: "Look out past the rings of Saturn. Those faint photons left their source millions of years ago.",
          annotations: [{
            type: "speech_metadata",
            style: "reflective and awe-inspired",
          }],
        }],
      }],
      response_format: { type: "audio" },
      generation_config: {
        speech_config: [
          { voice: createdVoice.id },
        ],
      },
    });

    fs.writeFileSync("designed_voice.wav", Buffer.from(interaction.output_audio.data, "base64"));

### REST

    curl "https://generativelanguage.googleapis.com/v1beta/interactions" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -X POST \
      -d '{
        "model": "gemini-3.8-flash-tts",
        "input": [{
          "type": "user_input",
          "content": [{
            "type": "text",
            "text": "Look out past the rings of Saturn. Those faint photons left their source millions of years ago.",
            "annotations": [{
              "type": "speech_metadata",
              "style": "reflective and awe-inspired"
            }]
          }]
        }],
        "response_format": {"type": "audio"},
        "generation_config": {
          "speech_config": [
            {"voice": "voice_YOUR_DESIGNED_VOICE_ID"}
          ]
        }
      }' | jq -r '[.steps[] | select(.type=="model_output") | .content[] | select(.type=="audio")] | last | .data' | base64 --decode > out.wav

## Manage your voices

You can list, filter, inspect, and delete your stored voices at any time using
the Voices API (see
[Extended Voice Library and filtering](https://ai.google.dev/gemini-api/docs/speech-generation#voice-library)
for all filter parameters).

- **Storage limits and TTL:** Stateful voices (`store=True`, shared across prompted and replicated voices) have a limit of **200 voices per project** and a **1-year TTL** (time-to-live).
- **`sample_audio` availability:** `voices.create()` (`CreateVoice`) and
  `voices.get()` (`GetVoice`) populate `sample_audio` (`mime_type:
  "audio/wav"`, base64-encoded `data`) for `"prompted"` voices. To keep
  listing lightweight, `voices.list()` (`ListVoices`) omits `sample_audio`
  (and `sample_audio` is unset for `"replicated"` and `"prebuilt"` voices).

### Python

    from google import genai

    client = genai.Client()

    # List stored prompted voices in your project filtered by language
    response = client.voices.list(
        type_=["prompted"],
        language_code=["en-US", "en-GB"],
    )
    for voice in response.voices or []:
        print(voice.id, voice.display_name, voice.type)

    # Retrieve a specific voice by ID
    voice_details = client.voices.get(id=created_voice.id)

    # Delete a stored custom voice
    client.voices.delete(id=created_voice.id)

### JavaScript

    import { GoogleGenAI } from "@google/genai";

    const ai = new GoogleGenAI();

    // List stored prompted voices in your project filtered by language
    const response = await ai.voices.list({
      type: ["prompted"],
      language_code: ["en-US", "en-GB"],
    });
    for (const voice of response.voices ?? []) {
      console.log(voice.id, voice.display_name, voice.type);
    }

    // Retrieve a specific voice by ID
    const voiceDetails = await ai.voices.get(createdVoice.id);

    // Delete a stored custom voice
    await ai.voices.delete(createdVoice.id);

### REST

    # List stored prompted voices filtered by language
    curl -G "https://generativelanguage.googleapis.com/v1beta/voices" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      --data-urlencode "type=prompted" \
      --data-urlencode "language_code=en-US" \
      --data-urlencode "language_code=en-GB"

    # Retrieve a specific voice by ID
    curl "https://generativelanguage.googleapis.com/v1beta/voices/voice_YOUR_DESIGNED_VOICE_ID" \
      -H "x-goog-api-key: $GEMINI_API_KEY"

    # Delete a stored custom voice
    curl -X DELETE "https://generativelanguage.googleapis.com/v1beta/voices/voice_YOUR_DESIGNED_VOICE_ID" \
      -H "x-goog-api-key: $GEMINI_API_KEY"

## Prompting best practices for Voice design

- **Put permanent vocal traits in Voice design, not `style`:** Define immutable characteristics---such as age, gender, timbre, vocal texture, and regional accent---when creating the voice in `voices.create`.
- **Reserve `speech_metadata.style` for situational emotion:** Once your custom voice is created, use short `style` prompts (for example, `"whispered urgently"` or `"cheerful and energetic"`) to steer turn-by-turn acting without altering the speaker's core identity.
- **Be specific and concise:** A clear 1--2 sentence description (such as *"A crisp, energetic sports announcer in her 30s with a slight Midwestern
  accent"*) produces cleaner, more consistent results than contradictory or overly long paragraphs.

## What's next

- Learn how to replicate an existing speaker's voice in [Voice replication](https://ai.google.dev/gemini-api/docs/voice-replication).
- Explore turn-level styling, inline tags, and multi-speaker dialogue in the [Text-to-speech guide](https://ai.google.dev/gemini-api/docs/speech-generation).