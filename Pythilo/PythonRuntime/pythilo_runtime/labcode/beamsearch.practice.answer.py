def beam_search(transitions, start, steps, width):
    import math
    beam = [(0.0, (start,))]
    for _ in range(steps):
        candidates = []
        for score, path in beam:
            for token, probability in transitions[path[-1]]:
                candidates.append((score+math.log(probability), path+(token,)))
        beam = sorted(candidates, key=lambda item: (-item[0], item[1]))[:width]
    return list(beam[0][1])
