def find_all(text, pattern):
    if not pattern:
        return list(range(len(text) + 1))
    # fail[j]: the longest proper prefix of pattern[:j + 1] that is also its suffix
    fail = [0] * len(pattern)
    k = 0
    for i in range(1, len(pattern)):
        while k and pattern[i] != pattern[k]:
            k = fail[k - 1]
        if pattern[i] == pattern[k]:
            k += 1
        fail[i] = k
    matches = []
    j = 0
    for i, ch in enumerate(text):  # each character of the text is read once
        while j and ch != pattern[j]:
            j = fail[j - 1]  # slide the pattern; i never goes back
        if ch == pattern[j]:
            j += 1
        if j == len(pattern):
            matches.append(i - j + 1)
            j = fail[j - 1]
    return matches
