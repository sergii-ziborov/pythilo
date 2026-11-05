def softmax(logits, temperature):
    import math
    if not logits:
        return []
    maximum = max(logits)
    weights = [math.exp((x-maximum)/temperature) for x in logits]
    total = sum(weights)
    probabilities = [weight / total for weight in weights]
    return probabilities
