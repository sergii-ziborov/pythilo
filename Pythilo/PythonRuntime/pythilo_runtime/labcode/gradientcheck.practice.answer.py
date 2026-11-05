def gradient_error(x, epsilon, derivative):
    def loss(value):
        return value ** 3 - 2 * value
    high = loss(x + epsilon)
    low = loss(x - epsilon)
    numerical = (high - low) / (2 * epsilon)
    error = abs(derivative - numerical)
    return error
