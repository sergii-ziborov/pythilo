# heap is a list where heap[i] <= heap[2*i + 1] and heap[i] <= heap[2*i + 2].


def pop(heap):
    top = heap[0]
    last = heap.pop()
    if heap:
        heap[0] = last
        # TODO: sift down. Swap heap[i] with its smaller child while that
        # child is smaller.
    return top
