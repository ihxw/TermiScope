import sys

file_path = "c:\\Users\\hbyjw\\code\\github\\TermiScope\\internal\\handlers\\monitor.go"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

# Extract lines 1131 to 1181 (0-indexed: 1131:1182)
# Since the previous view_file had 1132 as "// TriggerAgentUpdate", its index is 1131.
start_idx = 1131
end_idx = 1182

extracted = lines[start_idx:end_idx]
del lines[start_idx:end_idx]

# Append extracted lines to the end of the file
lines.extend(["\n"])
lines.extend(extracted)

with open(file_path, "w", encoding="utf-8", newline="") as f:
    f.writelines(lines)

print("Fixed monitor.go")
