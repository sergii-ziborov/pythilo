from collections import deque


def hot_potato(names, k):
    queue = deque(names)
    out = []
    while queue:
        # TODO: pass the potato k times: take from the front, add to the back.
        out.append(queue.popleft())
    return out
