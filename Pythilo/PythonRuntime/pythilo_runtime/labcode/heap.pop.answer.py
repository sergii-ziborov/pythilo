# heap is a list where heap[i] <= heap[2*i + 1] and heap[i] <= heap[2*i + 2].


def pop(heap):
    top = heap[0]
    last = heap.pop()
    if heap:
        heap[0] = last
        i = 0
        while True:
            smallest = i
            for child in (2 * i + 1, 2 * i + 2):
                if child < len(heap) and heap[child] < heap[smallest]:
                    smallest = child
            if smallest == i:
                break
            heap[i], heap[smallest] = heap[smallest], heap[i]
            i = smallest
    return top
