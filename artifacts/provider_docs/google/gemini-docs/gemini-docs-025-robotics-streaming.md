<br />

> [!NOTE]
> **Note:** Robotics with streaming requires `gemini-robotics-er-2-streaming-preview`. It is not available on ER 1.6 or the standard `gemini-robotics-er-2-preview` model endpoint.

The `gemini-robotics-er-2-streaming-preview` model endpoint exposes a dedicated
streaming endpoint that integrates with the [Live
API](https://ai.google.dev/gemini-api/docs/live-api/get-started-sdk), enabling real-time,
bidirectional interaction between your application and the robot. This makes it
suited for agents that need fast feedback loops and reactive responses to the
environment.
[Try in Google AI Studio](https://aistudio.google.com/prompts/new_chat?model=gemini-robotics-er-2-streaming-preview) [Clone example apps from GitHub](https://github.com/google-gemini/robotics-samples/tree/main/live-api)

## Use cases

- **Multi-robot coordination**: Multiple robots that communicate task state and delegate subtasks through a shared session.
- **Continuous monitoring**: Robots that observe a scene and trigger actions when specific events occur, such as a container reaching a fill level.
- **Warehouse and logistics**: Pick-and-pack agents that verify items visually, track packing progress, and recover from errors.

## Technical specifications

The following table outlines the technical specifications for the
Live API:

| Category | Details |
|---|---|
| Input modalities | Audio (raw 16-bit PCM audio, 16kHz, little-endian), images (JPEG \<= 1FPS), text |
| Output modalities | Text |
| Protocol | Stateful WebSocket connection (WSS) |

## Build an agentic setup

Every robotics agent built on the Live API follows three steps:

1. **Declare robot capabilities as tools.** Each action the robot can perform --- navigate, grasp, speak --- becomes a function declaration with a name, description, and parameter schema. Physical actions must use `"behavior": "BLOCKING"` so the model waits for the robot to finish before choosing the next step.
2. **Stream multimodal input into a persistent session.** Open a `live.connect` session and keep it open for the life of the task. Send video frames, audio, or text as they arrive from your robot's sensors.
3. **Handle tool calls in a receive loop.** Each time the model selects an action, it sends a `tool_call` message. Your receive loop executes the function against your robot SDK and sends back a `tool_response`. The session stays open, and the model picks the next action based on the result.

> [!NOTE]
> **Note:** Only blocking function calls are supported when using the Live API for robotics. See the [Live API tools guide](https://ai.google.dev/gemini-api/docs/live-api/tools) for details.

The following sections show how to apply these steps to three common patterns:
a baseline agent loop, proactive scene monitoring with a heartbeat, and routing
speech through TTS as a tool.

## Orchestrate a robot through function calling

The following example shows all three steps wired together in a single Python
script.

Step 1 --- tool definitions --- declares robot capabilities as function
declarations. The `navigate` function uses `"behavior": "BLOCKING"` so the
model waits for the robot to reach the waypoint before calling another tool.
Add more function declarations in the same list to expose additional robot
capabilities.

Step 2 --- input helpers --- shows three functions that stream different modality
inputs into the session: `send_text` for commands, `send_image` for camera
frames with an optional text prompt, and `send_audio` for raw PCM audio from a
microphone.

Step 3 --- the receive loop --- runs concurrently and handles two kinds of messages:
`server_content` messages (the model's text output) and `tool_call` messages
(the model requesting a robot action). When a tool call arrives, the loop calls
`execute_tool` --- a stub you replace with your real robot SDK --- then sends back a
`tool_response` so the model can select the next action.

    import asyncio
    from google import genai
    from google.genai import types

    MODEL = "gemini-robotics-er-2-streaming-preview"

    # ── Tool definitions ─────────────────────────────────────────────────────────
    tools = [
       {
           "function_declarations": [
               {
                   "name": "navigate",
                   "description": "Navigate the robot to a named waypoint.",
                   "behavior": "BLOCKING",
                   "parameters": {
                       "type": "OBJECT",
                       "properties": {"name": {"type": "STRING"}},
                       "required": ["name"],
                   },
               },
               # Add more function definitions here
           ]
       }
    ]

    # ── Stub tool executor (replace with real robot SDK calls) ───────────────────
    def execute_tool(name: str, args: dict) -> dict:
       print(f"  [Tool] {name}({args})")
       return {"status": "success"}

    # ── Input helpers ────────────────────────────────────────────────────────────
    def send_text(session, text: str):
       """Send a text turn."""
       return session.send_client_content(
           turns=types.Content(role="user", parts=[types.Part(text=text)]),
           turn_complete=True,
       )

    def send_image(session, image_bytes: bytes, prompt: str = ""):
       """Send a JPEG image with an optional text prompt."""
       parts = [
           types.Part(
               inline_data=types.Blob(data=image_bytes, mime_type="image/jpeg")
           )
       ]
       if prompt:
           parts.append(types.Part(text=prompt))
       return session.send_client_content(
           turns=types.Content(role="user", parts=parts),
           turn_complete=True,
       )

    def send_audio(session, audio_chunk: bytes):
       """Stream a chunk of raw PCM audio (16-bit, 16 kHz, mono)."""
       return session.send_realtime_input(
           media=types.Blob(data=audio_chunk, mime_type="audio/pcm;rate=16000")
       )

    # ── Receive loop ─────────────────────────────────────────────────────────────
    async def receive_loop(session):
       """Print model text and handle tool calls until the session ends."""
       async for message in session.receive():
           if message.server_content:
               sc = message.server_content
               if sc.model_turn and sc.model_turn.parts:
                   for part in sc.model_turn.parts:
                       if part.text:
                           print(f"Model: {part.text}", end="", flush=True)
               if sc.turn_complete:
                   print("\n[Turn Complete]")
           elif message.tool_call:
               responses = []
               for call in message.tool_call.function_calls:
                   print(f"\n[Tool Call] {call.name}({call.args})")
                   result = execute_tool(call.name, call.args)
                   responses.append(
                       types.FunctionResponse(
                           name=call.name,
                           response=result,
                           id=call.id,
                       )
                   )
               await session.send_tool_response(function_responses=responses)

    # ── Main ─────────────────────────────────────────────────────────────────────
    async def main():
       client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
       config = types.LiveConnectConfig(
           response_modalities=["TEXT"],
           tools=tools,
           system_instruction=types.Content(
               parts=[types.Part(text="You are a robot controller. Use tools to execute commands.")]
           ),
       )
       async with client.aio.live.connect(model=MODEL, config=config) as session:
           recv_task = asyncio.create_task(receive_loop(session))
           # Connect robot perception callbacks and user inputs to the helpers above.
           recv_task.cancel()

    asyncio.run(main())

The receive loop stays active after each tool response. The model constructs
and revises a long-horizon plan without you encoding the entire action sequence
in advance.

## Proactive spatial-temporal reasoning

The Live API streams video in, but video frames alone do
not trigger a new reasoning turn. Video frames must be accompanied by a
text or audio prompt to trigger a model response. See
[Live API capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities) for
more details.

To enable proactive reasoning, implement a **heartbeat**: periodically send the
latest camera frame followed by a short text prompt that forces the model to
inspect the scene and make an explicit decision. Video input is rate-limited to
one frame per second.

### Implement the heartbeat

The heartbeat coroutine runs as a separate `asyncio` task in the same session.
It opportunistically targets a 1 Hz cadence (matching the video input rate limit)
while waiting for each turn to complete (`er_turn_done`) to avoid interrupting
in-flight reasoning:

    async def heartbeat(session, camera, er_turn_done: asyncio.Event):
        TARGET_INTERVAL_SEC = 1.0

        while True:
            start_time = asyncio.get_running_loop().time()

            frame = await camera.latest_jpeg()
            await session.send_realtime_input(
                video=types.Blob(data=frame, mime_type="image/jpeg")
            )
            await session.send_realtime_input(
                text=(
                    "[HEARTBEAT] If no task is active, call 'ack' and wait for user"
                    " input. If a task is active: observe the scene. If the current"
                    " step is progressing correctly, call 'ack'. If the current step"
                    " is complete, call 'run_instruction' with the next step. If the"
                    " overall goal is achieved, call 'reset' and inform the user."
                )
            )

            # Wait for the model to finish responding before sending the next heartbeat
            await er_turn_done.wait()
            er_turn_done.clear()

            # Sleep only the remaining time to maintain ~1 Hz cadence
            elapsed = asyncio.get_running_loop().time() - start_time
            remaining = TARGET_INTERVAL_SEC - elapsed
            if remaining > 0:
                await asyncio.sleep(remaining)

> [!CAUTION]
> **Caution:** Sending a new prompt while the model is generating acts as an interruption (barge-in), which cancels in-flight reasoning and tool calls. If you fire heartbeats on a blind timer without waiting for the previous turn to complete, you may trap the model in a cancellation loop, making it appear unresponsive. See the [Live API guide on interruptions](https://ai.google.dev/gemini-api/docs/live-api/capabilities#interruptions) for more details.

### Update the receive loop

To signal when the model has completed its turn, update your `receive_loop`
to set `er_turn_done`:

    # In receive_loop: signal when the model finishes its turn
    if sc.turn_complete:
        er_turn_done.set()

## Audio output through external TTS

Gemini Robotics ER 2 returns text. Your application routes completed responses
to a separate TTS provider (such as
[Gemini TTS](https://ai.google.dev/gemini-api/docs/speech-generation)) via an injected callback.
This keeps speech latency, voice selection, and interruption behavior under your
control, and lets you swap TTS backends without changing agent logic.

You can also declare TTS as a tool so the model treats "say something" the same
as "move the arm." Add the following function declaration to your `tools` list
from the first section:

    TOOLS = [
        {
            "name": "send_message",
            "description": (
                "Speak a message aloud via TTS, then deliver it to the"
                " specified target. Use target='user' to speak directly"
                " to the user, or a peer agent name (e.g., 'duo') to"
                " communicate with another robot."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "target": {
                        "type": "string",
                        "description": "Recipient: 'user' or a peer agent name.",
                    },
                    "message": {
                        "type": "string",
                        "description": "The message to speak and deliver.",
                    },
                },
                "required": ["target", "message"],
            },
        },
    ]

By wrapping TTS in a function declaration, the model handles speech through the
same tool-call path as any other robot action. Your application fulfills the
call with an injected callback.

## Examples on GitHub

For full working examples including the Spot robot snack-fetch demo and Tinybot
pan-tilt hello world, see
[Robotics Live API examples](https://github.com/google-gemini/robotics-samples/tree/main/live-api).

## What's next

- [Video understanding](https://ai.google.dev/gemini-api/docs/robotics-video-progress) --- moment finding and progress classification.
- [Task orchestration](https://ai.google.dev/gemini-api/docs/robotics-orchestration) --- long-horizon tasks without streaming.
- [Live API overview](https://ai.google.dev/gemini-api/docs/live-api/get-started-sdk) --- full Live API documentation.