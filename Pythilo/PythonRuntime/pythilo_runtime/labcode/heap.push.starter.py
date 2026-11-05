# heap is a list where heap[i] <= heap[2*i + 1] and heap[i] <= heap[2*i + 2].


def push(heap, value):
    heap.append(value)
    # TODO: sift up. While the new item is smaller than its parent at
    # (i - 1) // 2, swap them.
