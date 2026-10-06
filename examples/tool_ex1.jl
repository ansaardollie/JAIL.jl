using JAIL

"""
    list_directory()

List the names of the files and folders in the current working directory.
"""
list_directory() = readdir(pwd())


"""
    read_file_contents

Returns the content of `file` who's path is relative to the current working directory.

# Arguments
- `file::String`: path of the file to read, e.g. "src/JAIL.jl"
"""
function read_file_contents(file::String)
  isfile(file) || throw(error("`$file` does not exist"))
  return read(file, String)
end

@tool list_directory read_file_contents           # or: @tool list_directory

# A session that offers only this tool (needs e.g. ANTHROPIC_API_KEY in ENV)
s = Session("anthropic/claude-sonnet-4-5"; name = "ls-test", tools = [list_directory])
tools(s)                                  # [ToolSpec(list_directory())]

# Ask the model; agent! runs the tool call and sends the result back until it answers
reply = agent!(s, "What files are in my current directory? Use the tool, then summarise.";
              stream = true)              # prints → list_directory() and ← [...] lines

# Inspect each step of the flow
for m in s.messages
    show(stdout, MIME"text/plain"(), m); println("\n---")
end
# UserMessage → AssistantMessage (:tool_use, → list_directory()) →
# ToolResultMessage (← ["LICENSE", ...]) → AssistantMessage (:end_turn, the summary)

reply.stop_reason                         # :end_turn