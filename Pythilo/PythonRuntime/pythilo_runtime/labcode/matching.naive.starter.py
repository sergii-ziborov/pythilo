def find_all(text, pattern):
    matches = []
    # TODO: is the last place the pattern can start included?
    for start in range(len(text) - len(pattern)):
        j = 0
        while j < len(pattern) and text[start + j] == pattern[j]:
            j += 1
        if j == len(pattern):
            matches.append(start)
    return matches
