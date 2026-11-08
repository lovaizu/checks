# Checks the prose.
message = "It is the best; e.g. this"
pattern = r"^e\.g\.; (this)$"  # noqa: E501 (e.g.)
print(f"e.g. {message}; that")
