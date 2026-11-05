def task_order(graph):
    from collections import deque
    degree = dict.fromkeys(graph, 0)
    for neighbours in graph.values():
        for node in neighbours:
            degree[node] += 1
    ready = deque(node for node in graph if degree[node] == 0)
    order = []
    while ready:
        node = ready.popleft()
        order.append(node)
        for other in graph[node]:
            degree[other] -= 1
            if degree[other] == 0:
                ready.append(other)
    return order if len(order) == len(graph) else None
