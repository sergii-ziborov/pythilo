def balanced(text):
    depth = 0
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return False
    # TODO: a count cannot tell ( from [. Keep a stack of the open ones.
    return depth == 0
