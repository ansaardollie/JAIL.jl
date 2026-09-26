<br />

> [!NOTE]
> **Note:** Video understanding requires Gemini Robotics ER 2 (`gemini-robotics-er-2-preview`). It is not available on ER 1.6.

Gemini Robotics ER 2 can track task progress from continuous video feeds using
two capabilities:

- Moment finding: identifies the precise timestamp where a key event occurs.
- Progress classification: assigns each video to one of five completion brackets (0--20%, 20--40%, 40--60%, 60--80%, 80--100%).

## Moment finding

Moment finding identifies the exact video frame where a critical event occurs ---
for example, when a cup is full or a knot is tied. Robots use this to verify
success, sequence steps, and trigger corrections.

The following example prompt asks the model to identify the completion moment
for a given task in a video:

    from google import genai

    client = genai.Client()

    uploaded_file = client.files.upload(file="task_video.mp4")

    prompt = """
    At what timestamp (in seconds) does the task reach successful completion?
    Return a JSON object: {"completion_time_seconds": <float>}.
    If the task is not completed, return {"completion_time_seconds": null}.
    """

    interaction = client.interactions.create(
        model="gemini-robotics-er-2-preview",
        input=[
            {
                "type": "video",
                "uri": uploaded_file.uri,
                "mime_type": uploaded_file.mime_type
            },
            {"type": "text", "text": prompt}
        ],
    )

    print(interaction.output_text)

The following shows example frames from a moment-finding video, with the
model identifying the task completion timestamp:

![Example video frames showing the moment finding output with a timestamp overlay](https://ai.google.dev/static/gemini-api/docs/images/robotics/video-moment-finding.png)

## Progress classification

Progress classification assigns a video to one of five completion brackets:
0--20%, 20--40%, 40--60%, 60--80%, or 80--100%. This gives robots real-time
situational awareness so they can adjust actions or retry failed steps without
restarting an entire workflow.

The following example prompt asks the model to classify the current progress
level from a video:

    from google import genai

    client = genai.Client()

    uploaded_file = client.files.upload(file="task_video.mp4")

    prompt = """
    Watch this video and classify the task progress level at the final frame.
    Return a JSON object with the progress bracket:
    {"progress_level": "0-20" | "20-40" | "40-60" | "60-80" | "80-100"}.
    """

    interaction = client.interactions.create(
        model="gemini-robotics-er-2-preview",
        input=[
            {
                "type": "video",
                "uri": uploaded_file.uri,
                "mime_type": uploaded_file.mime_type
            },
            {"type": "text", "text": prompt}
        ],
    )

    print(interaction.output_text)

The following shows example frames from a progress classification video, with
the model assigning a progress bracket:

![Example video frames showing the progress classification output with a progress bracket label](https://ai.google.dev/static/gemini-api/docs/images/robotics/video-progress-classification.png)

## Examples

For full runnable examples including multi-step task tracking, see the
[Robotics cookbook](https://github.com/google-gemini/robotics-samples/blob/main/Getting%20Started/gemini_robotics_er.ipynb).

## What's next

- [Live API for robotics](https://ai.google.dev/gemini-api/docs/robotics-streaming) --- real-time bidirectional streaming.
- [Task orchestration](https://ai.google.dev/gemini-api/docs/robotics-orchestration) --- long-horizon tasks with spatial reasoning.
- [Gemini Robotics ER overview](https://ai.google.dev/gemini-api/docs/robotics-overview) --- model comparison and capabilities.