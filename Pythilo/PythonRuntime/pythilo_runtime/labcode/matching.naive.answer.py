def find_all(text, pattern):
    matches = []
    for start in range(len(text) - len(pattern) + 1):
        j = 0
        while j < len(pattern) and text[start + j] == pattern[j]:
            j += 1
        if j == len(pattern):
            matches.append(start)
    return matches
