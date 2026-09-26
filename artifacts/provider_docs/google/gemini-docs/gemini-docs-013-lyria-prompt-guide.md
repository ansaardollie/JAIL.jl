The Gemini API offers two ways to generate music with Lyria:

- **Lyria 3.5 \& Lyria 3 Clip** : Non-streaming generation for 30-second clips or full-length songs with lyrics and vocals. See [Generate music with Lyria 3.5](https://ai.google.dev/gemini-api/docs/music-generation).
- **Lyria RealTime** : Real-time, interactive music streaming and live steering over WebSockets. See [Real-time music generation with Lyria RealTime](https://ai.google.dev/gemini-api/docs/realtime-music-generation).

Both models respond to descriptive text prompts, musical terminology, and structural directions. This guide covers how to write effective prompts for both batch generation and real-time steering.

## Prompt fundamentals

Your prompt can be a short phrase:

    A folk song about cute cats avoiding puddles, female vocals, acoustic guitar, sound of rain

Or a structured, detailed description:

    A 1980s-style synth-pop track with a driving beat, shimmering synthesizers, and a catchy, anthemic chorus. The song should have a retro-futuristic feel with modern production polish. Upbeat tempo around 120 BPM, clear verse-chorus structure, and a memorable instrumental hook. The lyrics describe getting ready for a party.

Both short and detailed prompts produce strong results. Use the following strategies to guide the model toward the exact sound you want.

## Genre and style

Lead your prompt with the primary genre. You can combine genres to create unique hybrids:

- A fusion of metal and hip-hop
- Death metal combined with operatic vocals
- Classical chamber music with dark electronic drone elements
- Modern electronic dance music (EDM) mixed with Europop

You can also specify a musical era or regional variant:

- Early 1990s boom-bap hip-hop
- 1960s French yé-yé pop
- 1980s post-punk and new wave
- 2000s mainstream R\&B
- Berlin minimal techno or Bay Area hyphy

### Genre keywords

Use these recognized genre terms in your prompts for Lyria 3.5 and Lyria RealTime:

- **Electronic \& Dance** : `Acid House, Breakbeat, Chillout, Chiptune, Deep House, Drum & Bass, Dubstep, EDM, Electro Swing, Glitch Hop, Hyperpop, Minimal Techno, Moombahton, Psytrance, Synthpop, Techno, Trance, Trip Hop, Vaporwave`
- **Hip-Hop \& R\&B** : `808 Hip Hop, Boom-Bap, Contemporary R&B, G-funk, Grime, Lo-Fi Hip Hop, Neo-Soul, New Jack Swing, Trap Beat`
- **Rock \& Alternative** : `Alternative Country, Blues Rock, Classic Rock, Funk Metal, Garage Rock, Indie Folk, Indie Pop, Post-Punk, 60s Psychedelic Rock, Shoegaze, Surf Rock`
- **Jazz, Soul \& Funk** : `Acid Jazz, Afrobeat, Bossa Nova, Disco Funk, Funk, Jazz Fusion, Latin Jazz`
- **Folk \& Traditional** : `Bengal Baul, Bhangra, Bluegrass, Celtic Folk, Cumbia, Indian Classical, Irish Folk, Merengue, Polka, Reggae, Reggaeton, Renaissance Music, Salsa`
- **Classical \& Acoustic** : `Baroque, Orchestral Score, Piano Ballad`

## Instruments and textures

Lyria selects appropriate instrumentation for the requested genre automatically. If you want specific instruments or unusual combinations, declare them explicitly:

    A dance track with a driving beat, shimmering synthesizers, and a catchy, anthemic chorus. A saxophone solo enters during the bridge.

Describe how instruments sound and interact to set mood and texture:

- A distorted 303 bassline cutting through crisp, tight hi-hats
- Warm, analog synth pads swelling beneath a dry, intimate acoustic guitar
- A wall of sound built from multiple layers of fuzz guitar, with distant, reverb-soaked vocals

### Instrument keywords

- **Keyboards \& Synths** : `Buchla Synths, Clavichord, Dirty Synths, Harpsichord, Mellotron, Moog Oscillations, Ragtime Piano, Rhodes Piano, Smooth Pianos, Spacey Synths, Synth Pads`
- **Bass \& Drums** : `303 Acid Bass, 808 Hip Hop Beat, Boomy Bass, Conga Drums, Drumline, Funk Drums, Precision Bass, Tabla, TR-909 Drum Machine`
- **Guitars \& Strings** : `Banjo, Balalaika, Bouzouki, Cello, Charango, Dulcimer, Fiddle, Flamenco Guitar, Guitar, Harp, Koto, Lyre, Mandolin, Pipa, Shamisen, Shredding Guitar, Sitar, Slide Guitar, Viola Ensemble, Warm Acoustic Guitar`
- **Wind \& Brass** : `Alto Saxophone, Bagpipes, Bass Clarinet, Didgeridoo, Harmonica, Ocarina, Trumpet, Tuba, Woodwinds`
- **Percussion** : `Bongos, Djembe, Glockenspiel, Hang Drum, Kalimba, Maracas, Marimba, Mbira, Steel Drum, Vibraphone`

## Song structure and timing

For Lyria 3.5, define song progression using tags or arrows:

- `[Intro] -> [Verse 1] -> [Chorus] -> [Verse 2] -> [Chorus] -> [Bridge] -> [Outro]`
- Start with a quiet piano intro, build into an energetic verse, pause for a moment of silence, then explode into the chorus.

You can direct energy dynamics and transitions:

- Build tension through the pre-chorus, then drop to silence before an explosive chorus
- Gradual crescendo throughout the song, adding one instrument per section
- A sudden stop after the bridge, followed by an a cappella chorus

You can also prompt specific timing markers:

- Build to a beat drop at 12 seconds
- Vocal sample repeats every 4 bars
- The chorus kicks in at 22 seconds

## Lyrics and vocals

Lyria 3.5 generates vocal tracks with lyrics by default. You can provide your own lyrics, ask the model to generate them, or request an instrumental track.

### Using your own lyrics

Include your lyrics directly in the prompt beneath a `Lyrics:` header. Tag each section to guide vocal delivery:

    Lyrics:

    [Intro]
    Ooooh, yeah

    [Verse 1]
    Early morning rain on the window pane
    City lights wash away the pain
    Walking down this empty street again

    [Chorus]
    We keep moving on (moving on)
    Until the morning light
    Everything will be alright

Use parentheses for backing vocals, echoes, or ad-libs, like `(moving on)`.

### Directing generated lyrics

When asking Lyria 3.5 to write lyrics, outline the narrative, emotion, or key phrases:

    The lyrics describe driving down the Pacific Coast Highway at sunset. The mood is nostalgic and reflective. Include an uplifting, anthemic chorus about second chances and starting over.

For electronic and dance genres, request short repeating vocal hooks:

    An upbeat dance-pop track with a repetitive, high-energy vocal hook: "Feel the rhythm all night long."

### Vocal delivery and singer profiles

Specify gender, vocal range, and timbre for precise delivery:

- **Female Soprano**: Clear, crystalline timbre with an agile, soaring delivery. Bright tone capable of airy, breathy textures.
- **Female Alto**: Rich, warm, and husky lower range. Smoky timbre with a soulful, resonant chest voice.
- **Male Tenor**: Bright, piercing, and energetic. Youthful timbre with high belting power that cuts through dense mixes.
- **Male Baritone**: Deep, velvet-smooth chest voice with a warm, soothing, crooning delivery.
- **Weathered Rocker**: Raspy, gritty timbre reminiscent of 1990s alternative rock. Raw emotional intensity with strained upper notes.

### Non-lyrical vocal effects

You can also prompt for spoken dialogue, vocal chops, and sampling effects:

- A vintage radio broadcast voice introduces the song before the beat kicks in
- A spoken voice whispers right before the drop, followed by high-energy synths
- Chopped, pitch-shifted vocal samples looping as an instrumental rhythm element

## Musical parameters

Refine your prompt with standard musical properties:

- **Tempo (BPM)** : Set the tempo directly (e.g. `120 BPM`, `slow tempo around 72 BPM`, `fast 160 BPM`).
- **Key and Scale** : Specify the root key and tonality (e.g. `in G major`, `in D minor`, `in C pentatonic`).
- **Mood and Atmosphere** : Use descriptive emotional adjectives: `Ambient, Bright, Chill, Dark, Dreamy, Emotional, Ethereal, Euphoric, Funky, Groovy, Melancholic, Nostalgic, Ominous, Psychedelic, Relaxed, Soulful, Triumphant, Upbeat, Whimsical`

## Prompting Lyria RealTime

Lyria RealTime uses **weighted prompts** rather than a single monolithic prompt string. This lets you blend multiple musical influences dynamically and steer music continuously over a WebSocket connection.

### Weighted prompt structure

Each weighted prompt consists of a descriptive text phrase and a floating-point weight:

    prompts = [
        types.WeightedPrompt(text="minimal techno", weight=1.0),
        types.WeightedPrompt(text="deep sub bass", weight=0.6),
        types.WeightedPrompt(text="shimmering hi-hats", weight=0.4),
    ]

### Real-time steering strategies

- **Blending genres** : Blend distinct styles by assigning balanced weights:
  - `ambient synth pads (weight: 0.8)` + `lo-fi hip-hop drums (weight: 0.6)`
  - `flamenco guitar (weight: 0.7)` + `deep house groove (weight: 0.5)`
- **Dynamic transitions** : To transition the music smoothly, adjust prompt weights over time:
  1. Start with `chill jazz piano (weight: 1.0)`.
  2. Gradually add `electronic breakbeat (weight: 0.3)`.
  3. Increase `electronic breakbeat` to `0.8` while lowering `chill jazz piano` to `0.3`.
- **Layering elements** : Keep instrument tags and mood tags separate so you can adjust them independently:
  - Prompt 1: `bossa nova guitar (weight: 0.9)`
  - Prompt 2: `warm acoustic bass (weight: 0.7)`
  - Prompt 3: `subtle vinyl crackle (weight: 0.3)`

## Example prompts

### Lyria 3.5 examples

- **Lo-Fi Study Beat** : `none
  A 30-second lofi hip hop beat with dusty vinyl crackle, mellow Rhodes piano chords, a relaxed boom-bap drum groove at 82 BPM, and a warm upright bassline. Instrumental only.`
- **Pop Anthem** : `none
  An upbeat, feel-good indie-pop song in G major at 122 BPM. Bright acoustic guitar strumming, driving kick drum, handclaps, and warm female vocal harmonies. The lyrics describe an unforgettable summer road trip with friends.`
- **Cinematic Cyberpunk** : `none
  Dark, cinematic cyberpunk synthwave at 110 BPM in D minor. Heavy distorted bass, ominous arpeggiated analog synthesizers, distant metallic percussion, and an ethereal female vocalise swelling during the climax.`

### Lyria RealTime steering set

    # Initial high-energy groove
    await session.set_weighted_prompts(
        prompts=[
            types.WeightedPrompt(text="techno groove", weight=1.0),
            types.WeightedPrompt(text="acid 303 bass", weight=0.8),
        ]
    )

    # Transition to a melodic breakdown
    await session.set_weighted_prompts(
        prompts=[
            types.WeightedPrompt(text="ambient synth pads", weight=1.0),
            types.WeightedPrompt(text="subtle reverberant piano", weight=0.7),
            types.WeightedPrompt(text="techno groove", weight=0.2),
        ]
    )

## What's next

- [Generate music with Lyria 3.5](https://ai.google.dev/gemini-api/docs/music-generation): Generate full songs and 30-second clips using the Interactions API.
- [Real-time music generation with Lyria RealTime](https://ai.google.dev/gemini-api/docs/realtime-music-generation): Build real-time, interactive music streaming applications over WebSockets.