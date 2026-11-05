def nucleus(probabilities, p):
    ordered = sorted(enumerate(probabilities), key=lambda pair: (-pair[1], pair[0]))
    chosen = []
    mass = 0.0
    for index, probability in ordered:
        chosen.append((index, probability))
        mass += probability
        if mass >= p - 1e-12:
            break
    return [(index, probability/mass) for index,probability in chosen]
