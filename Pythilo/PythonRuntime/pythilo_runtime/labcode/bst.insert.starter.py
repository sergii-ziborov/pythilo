# TreeNode(value) is ready to use: node.value, node.left, node.right.


def insert(root, value):
    if root is None:
        return TreeNode(value)
    # TODO: smaller values belong on the left, larger ones on the right.
    root.left = insert(root.left, value)
    return root
