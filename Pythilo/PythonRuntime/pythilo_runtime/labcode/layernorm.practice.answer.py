def layer_norm(values, gain, bias, epsilon):
    import math
    mean = sum(values) / len(values)
    variance = sum((value-mean)**2 for value in values) / len(values)
    scale = math.sqrt(variance + epsilon)
    output = [g*(value-mean)/scale+b for value,g,b in zip(values,gain,bias)]
    return output
