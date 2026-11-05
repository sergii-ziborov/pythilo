def find_all(text, pattern):
    # Right, but on a mismatch it slides one step and compares again
    # from the start of the pattern. TODO: rewrite it as KMP.
    matches = []
    for start in range(len(text) - len(pattern) + 1):
        j = 0
        while j < len(pattern) and text[start + j] == pattern[j]:
            j += 1
        if j == len(pattern):
            matches.append(start)
    return matches
