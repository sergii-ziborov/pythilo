# parent[x] is x's parent; a root is its own parent and names its set.


def find(parent, x):
    while parent[x] != x:
        x = parent[x]
    # TODO: right, but slow on long chains. Point the nodes you walked
    # past straight at the root.
    return x


def union(parent, a, b):
    parent[find(parent, a)] = find(parent, b)
