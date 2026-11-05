def longest_unique(text):
    last = {}  # character -> where it was seen last
    best = left = 0
    for right, ch in enumerate(text):
        if ch in last and last[ch] >= left:
            left = last[ch] + 1  # jump past the earlier copy
        last[ch] = right
        best = max(best, right - left + 1)
    return best
