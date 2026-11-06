def stream_decode(chunks, stops, max_tokens):
    if type(max_tokens) is not int or max_tokens < 0:
        raise ValueError('nonnegative output token budget required')
    if any(not stop for stop in stops):
        raise ValueError('stop sequences must not be empty')
    if any(type(token) is not int or token < 0 for part in chunks + stops for token in part):
        raise ValueError('nonnegative integer token identities required')
    output = []
    consumed = 0
    if max_tokens == 0:
        return {'tokens': output, 'reason': 'budget', 'consumed': consumed}
    for chunk in chunks:
        for token in chunk:
            output.append(token)
            consumed += 1
            matches = [stop for stop in stops if len(stop) <= len(output) and output[-len(stop):] == stop]
            if matches:
                longest = max(matches, key=len)
                return {'tokens': output[:-len(longest)], 'reason': 'stop', 'consumed': consumed}
            if len(output) >= max_tokens:
                return {'tokens': output, 'reason': 'budget', 'consumed': consumed}
    return {'tokens': output, 'reason': 'eof', 'consumed': consumed}
