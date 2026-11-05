def longest_unique(text):
    # Right, but slow: it starts again at every position.
    best = 0
    for left in range(len(text)):
        seen = set()
        right = left
        while right < len(text) and text[right] not in seen:
            seen.add(text[right])
            right += 1
        best = max(best, right - left)
    return best
