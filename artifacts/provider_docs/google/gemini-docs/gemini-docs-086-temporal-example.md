This tutorial walks you through building a durable AI agent that uses the Gemini
API for reasoning and [Temporal](https://temporal.io/) for durability. It uses
Temporal's built-in [Gemini SDK integration](https://github.com/temporalio/sdk-python/tree/main/temporalio/contrib/google_genai).

The agent can call tools, like looking up weather alerts or geolocating an IP
address, and will loop until it has enough information to respond.

What makes this different from a typical agent demo is **durability**. Every LLM
call and every tool invocation is persisted by Temporal. If the process crashes,
the network drops, or an API times out, Temporal automatically retries and
resumes from the last completed step. No conversation history is lost, and no
tool calls are incorrectly repeated.

## Architecture

The architecture consists of three parts:

- **Workflow:** A single `generate_content` call. The Gemini SDK's automatic function calling (AFC) loop runs *inside* the Workflow, and Temporal makes every step of it durable.
- **Activities:** Individual units of work that Temporal makes durable. The Gemini API calls become Activities automatically.
- **Worker:** The process that executes the Workflows and Activities, and the only place your API key lives.

In this example, you will place all three of these pieces in a single file
(`durable_agent_worker.py`). In a real-world implementation, you would separate
them to allow for various deployment and scalability advantages. You will supply
prompts to the agent with the Temporal CLI, so there is no client code to write.

## Prerequisites

To complete this guide, you'll need:

- A Gemini API key. You can create one for free in [Google AI Studio](https://aistudio.google.com/apikey).
- [Python](https://www.python.org/downloads/) version 3.10 or later.
- [uv](https://docs.astral.sh/uv/getting-started/installation/) for dependency management.
- The [Temporal CLI](https://docs.temporal.io/cli) for running a local development server and starting Workflows.

## Setup

Before you begin, ensure you have a
[Temporal development server](https://docs.temporal.io/cli#start-dev-server)
running locally:

    temporal server start-dev

Next, create a project and install the required dependencies:

    uv init durable-gemini-agent
    cd durable-gemini-agent
    uv add "temporalio[google-genai]" httpx python-dotenv

uv creates and manages the virtual environment for you, so every Python command
later in this tutorial runs through `uv run`.

Create a `.env` file in your project directory with your Gemini API key. You
can get an API key from
[Google AI Studio](https://aistudio.google.com/apikey).

    echo "GOOGLE_API_KEY=your-api-key-here" > .env

> [!NOTE]
> **Note:** Only the worker process needs the API key. Whatever starts the Workflow does not require it, and neither does the Workflow itself---the real `genai.Client` is constructed on the worker and never crosses into Workflow code, so no auth material can appear in Temporal's event history.

## Implementation

The rest of this tutorial walks through `durable_agent_worker.py` from top to
bottom, building up the agent piece by piece. Create the file and follow along.

> [!NOTE]
> **Note:** The `temporalio.contrib.google_genai` integration is experimental. Its API may change in future versions of the Temporal Python SDK.

### Imports and sandbox setup

Start with the imports that must be defined up-front. The
`workflow.unsafe.imports_passed_through()` block tells Temporal's Workflow
sandbox to let `httpx` pass through without restriction. Importing `httpx`
executes `class _CookieCompatRequest(urllib.request.Request)`, and the sandbox
blocks subclassing that stdlib class.

Your tools use `httpx`, and `activity_as_tool()` needs the Workflow to import
those tool functions so Gemini can derive their schemas from the signatures. So
`httpx` reaches the sandbox no matter how you split the files---moving the tools
into their own module doesn't avoid it.

    from temporalio import workflow

    with workflow.unsafe.imports_passed_through():
        import httpx

You don't need to list `google.genai` here. The Temporal plugin you configure
later adds it---along with `pydantic_core` and `annotated_types`---to the sandbox
passthrough set for you.

### System instructions

Next, define the agent's personality. The system instructions tell the model how
to behave. This agent is instructed to respond in haikus when no tools are
needed.

    SYSTEM_INSTRUCTIONS = """
    You are a helpful agent that can use tools to help the user.
    You will be given an input from the user and a list of tools to use.
    You may or may not need to use the tools to satisfy the user ask.
    If no tools are needed, respond in haikus.
    """

### Tool definitions

Now define the tools the agent can use. Each tool is an ordinary Temporal
Activity: an async function decorated with `@activity.defn`, with type-annotated
parameters and a descriptive docstring. Gemini builds the function declaration
from that signature and docstring, so document each parameter in the `Args`
section.

    import json

    from temporalio import activity

    NWS_API_BASE = "https://api.weather.gov"
    USER_AGENT = "weather-app/1.0"

    @activity.defn
    async def get_weather_alerts(state: str) -> str:
        """Get weather alerts for a US state.

        Args:
            state: Two-letter US state code (e.g. CA, NY)
        """
        headers = {"User-Agent": USER_AGENT, "Accept": "application/geo+json"}
        url = f"{NWS_API_BASE}/alerts/active/area/{state}"

        async with httpx.AsyncClient() as client:
            response = await client.get(url, headers=headers, timeout=5.0)
            response.raise_for_status()
            return json.dumps(response.json())

Next, define tools for IP address geolocation:

    @activity.defn
    async def get_ip_address() -> str:
        """Get the public IP address of the current machine."""
        async with httpx.AsyncClient() as client:
            response = await client.get("https://icanhazip.com")
            response.raise_for_status()
            return response.text.strip()

    @activity.defn
    async def get_location_info(ipaddress: str) -> str:
        """Get the location information for an IP address including city, state, and country.

        Args:
            ipaddress: An IP address to look up
        """
        async with httpx.AsyncClient() as client:
            response = await client.get(f"http://ip-api.com/json/{ipaddress}")
            response.raise_for_status()
            result = response.json()
            return f"{result['city']}, {result['regionName']}, {result['country']}"

That's the whole tool layer. There is no tool registry, no `FunctionDeclaration`
construction, and no dispatch table---the next section wraps these Activities with
`activity_as_tool()`, which passes each parameter through to the Activity
positionally. Tools with zero, one, or several parameters all work.

### The agent Workflow

Now you have all the pieces to finish building the agent. The `AgentWorkflow`
class makes one `generate_content` call. `TemporalAsyncClient` is a drop-in
`AsyncClient` whose every API call runs as a Temporal Activity, and
`activity_as_tool()` turns each of your Activities into a Gemini tool.

When the model asks for a tool, the SDK's AFC loop---running inside the
Workflow---dispatches it through `workflow.execute_activity`, appends the result
to the conversation, and calls the model again. That loop is the agent, and it
is durable because each step is an Activity recorded in Temporal's event
history.

    from datetime import timedelta

    from google.genai import types
    from temporalio.contrib.google_genai import TemporalAsyncClient, activity_as_tool
    from temporalio.workflow import ActivityConfig

    TOOL_CONFIG = ActivityConfig(start_to_close_timeout=timedelta(seconds=30))

    @workflow.defn
    class AgentWorkflow:
        """Agent workflow that uses Gemini for LLM calls and executes tools."""

        @workflow.run
        async def run(self, prompt: str) -> str:
            client = TemporalAsyncClient()

            response = await client.models.generate_content(
                model="gemini-3.8-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=SYSTEM_INSTRUCTIONS,
                    tools=[
                        activity_as_tool(get_weather_alerts, activity_config=TOOL_CONFIG),
                        activity_as_tool(get_ip_address, activity_config=TOOL_CONFIG),
                        activity_as_tool(get_location_info, activity_config=TOOL_CONFIG),
                    ],
                ),
            )

            # Leave this in place. You will un-comment it during a durability
            # test later on.
            # await workflow.sleep(timedelta(seconds=10))

            return response.text or ""

A few things to note:

- Construct `TemporalAsyncClient` **inside** the Workflow. It carries no credentials; it only knows how to turn API calls into Activity invocations.
- `activity_config` must set `start_to_close_timeout` or `schedule_to_close_timeout`. Temporal requires a timeout and there is no default for tool Activities.
- The Gemini API Activities default to a 60-second `start_to_close_timeout`. Override it with `TemporalAsyncClient(activity_config=...)` if your model calls need longer.

The agent is fully durable. If the worker crashes after several turns, Temporal
picks up exactly where it left off without re-invoking already executed LLM
calls or tool calls.

### Retries

Temporal owns retries, so don't enable the Gemini SDK's own retry loop. Set
retry behavior with a `retry_policy` on the Activity config instead:

    from temporalio.common import RetryPolicy

    TOOL_CONFIG = ActivityConfig(
        start_to_close_timeout=timedelta(seconds=30),
        retry_policy=RetryPolicy(maximum_attempts=3),
    )

API failures are also classified for you. Transient statuses (408, 429, 5xx)
stay retryable so the Activity's retry policy applies; other statuses (such as a
400 for a malformed request) are non-retryable, so the Workflow fails fast
instead of burning attempts on an error that won't resolve.

You can extend that classification. The integration surfaces each API failure as
an `ApplicationError` whose type is the Gemini exception class name---`ClientError`
for 4xx, `ServerError` for 5xx---so listing a name in
`non_retryable_error_types` moves it out of the transient set. For example, to
stop retrying Gemini-side outages and fail the Workflow on the first 5xx, apply
the policy to the Gemini API Activities through `TemporalAsyncClient`:

    from temporalio.common import RetryPolicy

    client = TemporalAsyncClient(
        activity_config=ActivityConfig(
            start_to_close_timeout=timedelta(seconds=60),
            retry_policy=RetryPolicy(
                maximum_attempts=5,
                non_retryable_error_types=["ServerError"],
            ),
        ),
    )

### Worker startup

Finally, wire everything together. The Temporal worker connects to the Temporal
service and acts as a scheduler for the Workflow and Activity tasks.

This is where the real `genai.Client` is created, with your API key.
`GoogleGenAIPlugin` takes that client and registers the Gemini API Activities,
installs the Pydantic data converter, and configures the Workflow sandbox.

    import asyncio
    import os

    from dotenv import load_dotenv
    from google import genai
    from temporalio.client import Client
    from temporalio.contrib.google_genai import GoogleGenAIPlugin
    from temporalio.envconfig import ClientConfig
    from temporalio.worker import Worker

    async def main():
        gemini = genai.Client(api_key=os.environ["GOOGLE_API_KEY"])
        plugin = GoogleGenAIPlugin(gemini)

        config = ClientConfig.load_client_connect_config()
        config.setdefault("target_host", "localhost:7233")
        client = await Client.connect(**config, plugins=[plugin])

        worker = Worker(
            client,
            task_queue="gemini-agent",
            workflows=[
                AgentWorkflow,
            ],
            activities=[
                get_weather_alerts,
                get_ip_address,
                get_location_info,
            ],
        )
        await worker.run()

    if __name__ == "__main__":
        load_dotenv()
        asyncio.run(main())

The plugin removes three pieces of boilerplate you would otherwise need here:

- No `data_converter=pydantic_data_converter`---the plugin installs the Pydantic payload converter itself.
- No `activity_executor=ThreadPoolExecutor`---every Activity is async.
- No Gemini Activities in the `activities` list---the plugin registers them. You only register your own tools.

## Run the agent

That's the entire agent. You don't need to write a client---the Temporal CLI can
start the Workflow for you.

If you haven't already, start the Temporal development server:

    temporal server start-dev

In a new terminal window, start the agent worker:

    uv run durable_agent_worker.py

In a third terminal window, submit a query to your agent:

    temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
        --input '"are there any weather alerts for where I am?"'

Note the task queue: it's the same one the worker polls. Starting the Workflow
dispatches a Workflow task carrying the user prompt to that queue, which is what
initiates the agent. `execute` blocks until the Workflow completes and prints the
result. If you'd rather not wait, use `temporal workflow start` with an explicit
`--workflow-id`, then collect the result later with
`temporal workflow result -w your-workflow-id`. Temporal generates the Workflow
ID for you when you omit `--workflow-id`.

`--input` takes JSON, so a bare string prompt needs its own quotes inside the
shell quotes. The CLI needs no Gemini API key, and no data converter
configuration either: the Workflow's argument and return value are both plain
strings, which the default JSON payload converter handles.

Open the Temporal UI at
`http://localhost:8233/namespaces/default/workflows` to watch the agentic loop
unfold. You'll see `gemini_api_client_async_request` Activities---one per model
turn---interleaved with one Activity per tool call, each labeled with a
`tool_call` summary. That interleaving *is* the AFC loop, made durable and
observable.

Try a few different prompts to see the agent reason and call tools. Each command
is the same as the one above with a new `--input`:

    temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
        --input '"are there any weather alerts for New York?"'
    temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
        --input '"where am I?"'
    temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
        --input '"what is my ip address?"'
    temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
        --input '"tell me a joke"'

The last prompt doesn't require any tools, so the agent responds in a haiku
based on the `SYSTEM_INSTRUCTIONS`.

## Test durability

Building on Temporal ensures your agent survives failures seamlessly. You can
test this using two distinct experiments.

### Simulating a network outage

In this test, you'll temporarily disable your computer's internet connection,
submit a Workflow, watch Temporal automatically retry, and then restore the
network to see it recover.

1. Disconnect your machine from the internet (for example, turn off your Wi-Fi).
2. Submit a Workflow:

       temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
           --input '"tell me a joke"'

3. Check the Temporal UI (`http://localhost:8233`). You will see the Gemini API
   Activity failing and Temporal automatically managing the retries in the
   background.

4. Reconnect to the internet.

5. The next automated retry will successfully reach the Gemini API, and your
   terminal will print the final result.

### Surviving a worker crash

In this test, you kill the worker mid-execution and restart it. Temporal replays
the Workflow history (event sourcing) and resumes from the last completed
Activity---already-completed LLM invocations and tool calls are not repeated.

1. To give yourself time to kill the worker, open `durable_agent_worker.py` and
   uncomment the durable timer in `AgentWorkflow.run`:

       await workflow.sleep(timedelta(seconds=10))

   `workflow.sleep` is a Temporal timer, not a local one. It is recorded in
   history and survives the restart, which is what makes this test reliable.
2. Restart the worker:

       uv run durable_agent_worker.py

3. Submit a query that triggers several tools:

       temporal workflow execute --type AgentWorkflow --task-queue gemini-agent \
           --input '"are there any weather alerts where I am?"'

4. Once the tool calls have completed and the timer is running, kill the worker
   process (`Ctrl-C` in the worker terminal, or `kill %1` if running in the
   background).

5. Restart the worker:

       uv run durable_agent_worker.py

Temporal replays the Workflow history. The LLM calls and tool invocations that
already completed are **not** re-executed---their results are instantly replayed
from history (the event log), the timer resumes, and the Workflow finishes
successfully.

## Going further

The integration supports more than this tutorial covers. See the
[plugin documentation](https://github.com/temporalio/sdk-python/tree/main/temporalio/contrib/google_genai)
for details:

- **Streaming.** Use `generate_content_stream` as usual. To let an external consumer (a chat UI) observe chunks in real time while the Workflow runs durably, set `TemporalAsyncClient(streaming_topic=...)` and host a `WorkflowStream` in the Workflow.
- **MCP.** Register a client-side MCP server on the worker with `GoogleGenAIPlugin(mcp_servers={...})` and reference it by name in the Workflow with `TemporalMcpClientSession`. Tool discovery and calls run as Activities against a pooled worker-side connection.
- **Vertex AI.** Pass `vertexai=True` to both the worker-side `genai.Client` and the Workflow-side `TemporalAsyncClient`, setting `project` and `location` explicitly on the Workflow side so replay stays deterministic.

## Further resources

- [Temporal documentation](https://docs.temporal.io/)
- [Temporal Python SDK](https://docs.temporal.io/develop/python)
- [Temporal Gemini SDK integration](https://docs.temporal.io/develop/python/integrations/google-genai)
- [Google GenAI SDK](https://googleapis.github.io/python-genai/)