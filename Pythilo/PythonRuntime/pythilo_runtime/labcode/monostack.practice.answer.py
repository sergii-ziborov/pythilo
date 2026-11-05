def warmer_days(temperatures):
    waits = [0] * len(temperatures)
    pending = []
    for i, temperature in enumerate(temperatures):
        while pending and temperatures[pending[-1]] < temperature:
            previous = pending.pop()
            waits[previous] = i - previous
        pending.append(i)
    return waits
