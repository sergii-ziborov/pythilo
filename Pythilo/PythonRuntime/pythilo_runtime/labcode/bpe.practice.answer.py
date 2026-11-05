def merge_pair(tokens):
    if len(tokens) < 2:
        return list(tokens), None
    counts = {}
    for pair in zip(tokens, tokens[1:]):
        counts[pair] = counts.get(pair, 0) + 1
    pair = min(counts, key=lambda p: (-counts[p], p))
    result = []
    i = 0
    while i < len(tokens):
        if i+1 < len(tokens) and (tokens[i], tokens[i+1]) == pair:
            result.append(tokens[i]+tokens[i+1])
            i += 2
        else:
            result.append(tokens[i])
            i += 1
    return result, pair
