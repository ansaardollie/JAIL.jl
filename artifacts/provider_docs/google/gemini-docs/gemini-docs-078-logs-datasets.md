In this guide you'll learn how to
view logs from Gemini API usage in the Google AI Studio dashboard
to better understand model behavior and how users may be interacting with your
applications. Use logging to observe, debug, and *optionally share usage
feedback with Google to help improve Gemini across developer use cases* .^[\*](https://ai.google.dev/gemini-api/docs/logs-policy)^

All `GenerateContent`, `BatchGenerateContent`, `StreamGenerateContent` API
calls, and [Interactions](https://ai.google.dev/gemini-api/docs/interactions) API calls excluding
Managed Agents are supported. This includes calls made through
[OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai) endpoints.

> [!NOTE]
> **Note:** Storage for Gemini API logs are only available for projects on the Gemini API paid tier.

## Configure project logging

By default, the API stores all interaction objects (`store=true`) in order to
simplify use of server-side state management features. In contrast, the
Generate Content API does not store requests by default, and requires storage
to be enabled per-request or at the project-level from AI Studio.

In Google [AI Studio](https://aistudio.google.com/logs) you can enable or
disable logging for all projects or for specific projects and change these
preferences at any time through the **Settings** panel in the
[Logs and Datasets](https://aistudio.google.com/logs) page. Logging can be toggled on or off
independently for the `generateContent` API and the
[Interactions](https://ai.google.dev/gemini-api/docs/interactions) API
to change the default storage behavior for a project.

> [!WARNING]
> **Warning:** Toggling Interactions API logging *off* in the AI Studio **Settings** panel will prevent the API from automatically storing and retrieving conversation history unless explicitly overridden per-request.

### Request-level logging

Storage and logging behavior differs by API:

- **[Interactions API](https://ai.google.dev/gemini-api/docs/interactions):** Stores requests by default (`store=true`) to simplify server-side state management.
- **Generate Content API (`generateContent`):** Does not store requests by default (`store=false`).

Here is how you can set the `store` property:

**GenerateContent API**

### Python

    from google import genai

    client = genai.Client()

    response = client.models.generate_content(
        model='gemini-3.8-flash',
        contents='Explain quantum entanglement in simple terms.',
        config={'store': False} # Set to True to enable logging of this request
    )

    print(response.text)

### JavaScript

    import { GoogleGenAI } from '@google/genai';

    const client = new GoogleGenAI({});

    const response = await client.models.generateContent({
        model: 'gemini-3.8-flash',
        contents: 'Explain quantum entanglement in simple terms.',
        config: {
            store: false // Set to true to enable logging of this request
        }
    });

    console.log(response.text);

### Java

    import com.google.genai.Client;
    import com.google.genai.types.GenerateContentConfig;
    import com.google.genai.types.GenerateContentResponse;

    Client client = new Client();

    // The GenerateContent API does not store requests by default
    GenerateContentResponse response =
        client.models.generateContent(
            "gemini-3.8-flash",
            "Explain quantum entanglement in simple terms.",
            GenerateContentConfig.builder().build());

    System.out.println(response.text());

### Go

    package main

    import (
        "context"
        "fmt"
        "log"

        "google.golang.org/genai"
    )

    func main() {
        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        // The GenerateContent API does not store requests by default
        response, err := client.Models.GenerateContent(
            ctx,
            "gemini-3.8-flash",
            genai.Text("Explain quantum entanglement in simple terms."),
            &genai.GenerateContentConfig{},
        )
        if err != nil {
            log.Fatal(err)
        }
        fmt.Println(response.Text())
    }

**Interactions API**

### Python

    from google import genai

    client = genai.Client()

    interaction = client.interactions.create(
        model="gemini-3.8-flash",
        input="Explain quantum entanglement in simple terms.",
        store=True # Set to False to disable logging of this request
    )

    print(interaction.outputs[-1].text)

### JavaScript

    import { GoogleGenAI } from '@google/genai';

    const client = new GoogleGenAI({});

    const interaction = await client.interactions.create({
        model: 'gemini-3.8-flash',
        input: 'Explain quantum entanglement in simple terms.',
        store: true // Set to false to disable logging of this request
    });

    console.log(interaction.outputs[interaction.outputs.length - 1].text);

### Java

    import com.google.genai.Client;
    import com.google.genai.gaos.models.interactions.CreateModelInteraction;
    import com.google.genai.gaos.models.interactions.Interaction;
    import com.google.genai.gaos.models.interactions.InteractionsInput;
    import com.google.genai.gaos.models.interactions.Model;
    import com.google.genai.gaos.models.operations.CreateInteractionRequestBody;

    Client client = new Client();

    CreateModelInteraction params =
        CreateModelInteraction.builder()
            .model(Model.of("gemini-3.8-flash"))
            .input(InteractionsInput.of("Explain quantum entanglement in simple terms."))
            .store(true) // Set to false to disable logging of this request
            .build();

    Interaction interaction =
        client.interactions.create(CreateInteractionRequestBody.of(params)).interaction().get();

    System.out.println(interaction.outputText().orElse(""));

### Go

    package main

    import (
        "context"
        "fmt"
        "log"

        "google.golang.org/genai"
        "google.golang.org/genai/interactions/models/interactions"
        "google.golang.org/genai/interactions/models/operations"
    )

    func main() {
        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        res, err := client.Interactions.Create(ctx, operations.CreateInteractionRequest{
            Body: operations.NewCreateInteractionRequestBody(interactions.CreateModelInteraction{
                Model: interactions.Model("gemini-3.8-flash"),
                Input: interactions.NewInteractionsInput("Explain quantum entanglement in simple terms."),
                Store: genai.Ptr(true), // Set to false to disable logging of this request
            }),
        })
        if err != nil {
            log.Fatal(err)
        }
        if res.Interaction.OutputText != nil {
            fmt.Println(*res.Interaction.OutputText)
        }
    }

## View project logs in AI Studio

1. Go to the Logs page in [AI Studio](https://aistudio.google.com/logs).
2. Select a project from the drop-down.
3. Logs will appear in the table in reverse chronological order for the Interactions API, if they exist.
4. To observe project logs for the Generate Content API, first enable this in the [settings panel](https://ai.google.dev/gemini-api/docs/logs-datasets#configure-logging).

> [!NOTE]
> **Note:** A project requires at least one active API key for logs to be displayed. If all API keys in a project are deleted (for example, if a leaked key was deleted), you will lose visibility of the project's logs until an API key is available.

Click an entry for a preview of the payload. You can
inspect the full prompt and response from Gemini, and the context from the
previous turns. For **Interactions API** requests, logs also include a direct
link to the `previous_interaction_id`.

## Configure project storage retention

Logs will expire and be marked for deletion after a default retention window of
55 days (unless [saved to a dataset](https://ai.google.dev/gemini-api/docs/logs-datasets#create), which don't expire).
You can configure the retention window of a project's logs to 7, 14, 28, or 55
days max.

## Create and share datasets

You can save logs to datasets to organize and export them more effectively.

- From the [Logs page](https://aistudio.google.com/logs), locate the filter bar at the top to select a property to filter by.
- From your filtered view, use the checkboxes to select all or individual logs.
- Click the **Create dataset** button that appears at the top of the list.
- Give your new dataset a name and optional description.
- You will see the dataset you just created with the curated set of logs.
- Export your dataset for further analysis as CSV, JSONL files or to Google Sheets.

Datasets can be helpful for a number of different use cases.

- **Curate challenge sets:** Drive future improvements that target areas where you want your AI to improve.
- **Curate sample sets:** For example, a sample from real usage to generate responses from another model, or a collection of edge cases for routine checks before deployment.
- **Evaluation sets:** Sets that are representative of real usage across important capabilities, for comparison across other models or system instruction iterations.

You can contribute to Gemini research and development by choosing to share
your datasets with Google as demonstration examples.

## Limitations

Logging is not currently supported for the following:

- Imagen and Veo models
- Gemini embedding models
- Gemini Robotics model
- Inputs containing videos, GIFs or PDFs
- Public Preview Agents in the Gemini API

## What's next

- **Prototype with session history:** Use [AI Studio Build](https://aistudio.google.com/apps) to vibe code apps and add your API key to enable a history of Gemini API logs for AI features.
- **Re-run logs with the Gemini Batch API:** Use datasets for response sampling and evaluation of models or application logic by re-running logs with the [Gemini Batch API](https://github.com/google-gemini/cookbook/blob/main/examples/Datasets.ipynb).