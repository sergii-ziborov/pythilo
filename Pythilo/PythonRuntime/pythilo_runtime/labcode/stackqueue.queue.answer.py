from collections import deque


def hot_potato(names, k):
    queue = deque(names)
    out = []
    while queue:
        for _ in range(k):
            queue.append(queue.popleft())
        out.append(queue.popleft())
    return out
