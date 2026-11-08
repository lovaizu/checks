# Reads the syntax tree that `shfmt --to-json` makes of a shell script, and
# prints its prose, each line as {line, text}: its comments, and the quoted
# words that echo and printf show. The first line #! and a directive of
# shellcheck are for a program, not a reader. An echo or a printf that
# writes to a file writes data, not a message. An expansion, such as $cmd,
# reads as `x`, so that Vale takes it as code. A text with no letter holds
# no prose.

def text:
  if .Type == "Lit" then .Value // ""
  elif .Type == "SglQuoted" then .Value // ""
  elif .Type == "DblQuoted" then [.Parts[]? | if .Type == "Lit" then (.Value // "") | gsub("\\\\(?<c>[\"\\\\$`])"; .c) else text end] | join("")
  else "`x`" end;

# A word that's all or partly quoted, as messages are.
def quoted: any(.Parts[]?; .Type == "SglQuoted" or .Type == "DblQuoted");
def message: select(quoted) | {line: .Pos.Line, text: ([.Parts[] | text] | join("") | gsub("\n"; " "))};

# A redirect to a file, not to the terminal: >, >>, &> and the like, but not
# >&2, nor /dev/stdout, /dev/stderr or /dev/tty.
def to_file:
  ([.Word.Parts[]? | text] | join("")) as $to |
  (.Op | tostring | test(">")) and ($to | test("^([0-9]+|-|/dev/(stdout|stderr|tty))$") | not);

[
  (.. | objects | (.Comments[]?, .Last[]?) | .Text //= "" |
    select(.Hash.Line == 1 and (.Text | startswith("!")) | not) |
    select(.Text | test("^\\s*shellcheck\\s") | not) |
    {line: .Hash.Line, text: (.Text | sub("^ "; ""))}),
  (.. | objects | select(.Cmd?.Type == "CallExpr") | select(any(.Redirs[]?; to_file) | not) | .Cmd |
    ([.Args[0]?.Parts[]? | text] | join("")) as $name |
    if $name == "echo" then .Args[1:][] | message
    elif $name == "printf" then
      # The conversions and escapes of the format, such as %s and \n, are
      # for printf, not for a reader.
      (.Args[1]? | message | .text |= gsub("%[-+ #0]*[0-9*]*(\\.[0-9*]*)?[a-zA-Z%]|\\\\([0-7]{1,3}|.)"; " ")),
      (.Args[2:][] | message)
    else empty end)
] | map(select(.text | test("\\p{L}")))
