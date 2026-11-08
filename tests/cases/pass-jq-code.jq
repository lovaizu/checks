# Reads the tree of a script.
[.. | objects | select(.Type == "CallExpr; e.g. # this")] | map(.Args[0]?)
