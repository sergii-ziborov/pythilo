# parent[x] is x's parent; a root is its own parent and names its set.


def find(parent, x):
    root = x
    while parent[root] != root:
        root = parent[root]
    while parent[x] != root:  # path compression
        parent[x], x = root, parent[x]
    return root


def union(parent, a, b):
    parent[find(parent, a)] = find(parent, b)
