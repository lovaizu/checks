# Reads the syntax tree that `shfmt --to-json` makes of a shell script, and
# prints the messages that the script shows: the quoted words given to
# warn, echo and printf, the quoted values of the variables reason and
# message, and the items added to the array notes. Each message is
# {line, text}. An expansion, such as $cmd, reads as `x`, so that Vale
# takes it as code.

def text:
  if .Type == "Lit" then .Value
  elif .Type == "SglQuoted" then .Value
  elif .Type == "DblQuoted" then [.Parts[]? | if .Type == "Lit" then .Value | gsub("\\\\(?<c>[\"\\\\$`])"; .c) else text end] | join("")
  else "`x`" end;

# A word that's all or partly quoted, as messages are.
def quoted: any(.Parts[]?; .Type == "SglQuoted" or .Type == "DblQuoted");
def message: select(quoted) | {line: .Pos.Line, text: ([.Parts[] | text] | join("") | gsub("\n"; " "))};

[.. | objects |
  if .Type == "CallExpr" then
    ([.Args[0]?.Parts[]? | text] | join("")) as $name |
    (select(any(["warn", "echo", "printf"][]; . == $name)) | .Args[1:][] | message),
    (.Assigns[]? | select(.Name.Value == "reason" or .Name.Value == "message") | .Value | select(. != null) | message),
    (.Assigns[]? | select(.Name.Value == "notes" and .Append) | .Array.Elems[]?.Value | message)
  else empty end]
