def binary_search(items, target):
    lo, hi = 0, len(items) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if items[mid] == target:
            return mid
        # TODO: items is sorted. If items[mid] < target, everything up to mid
        # is too small: move lo past mid. Otherwise move hi below mid.
        lo += 1
    return -1
