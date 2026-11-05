def range_sums(values, queries):
    prefix = [0]
    for value in values:
        prefix.append(prefix[-1] + value)
    answers = []
    for left, right in queries:
        answers.append(prefix[right] - prefix[left])
    return answers
