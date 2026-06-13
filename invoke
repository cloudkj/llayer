#!/usr/bin/env python3
import sys
import json
import os

def main():
    tool_calls = 0
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            
            # Silently pass through everything that isn't a tool call
            if event.get("type") != "tool_call":
                continue

            tool_calls += 1
            call = event["payload"]
            # Extract the tool details (assuming the payload matches Ollama's tool output format)
            tool_name = call.get("name")
            tool_args = call.get("arguments", {})
            
            if tool_name == "list_directory":
                target_path = tool_args.get("path", ".")
                
                try:
                    # Safely list directory contents using Python's native OS library
                    files = os.listdir(target_path)
                    result_text = f"Contents of '{target_path}':\n" + "\n".join(files)
                    
                except Exception as e:
                    result_text = f"Error reading directory '{target_path}': {str(e)}"
                
                # Emit the result back into the pipeline
                result_event = {
                    "type": "tool_result",
                    "source": "tool",
                    "payload": {
                        "tool_name": tool_name,
                        "text": result_text
                    }
                }
                print(json.dumps(result_event))
                
        except Exception as e:
            sys.stderr.write(f"Tool Exec Error: {e}\n")

    return tool_calls

if __name__ == "__main__":
    sys.exit(main())
