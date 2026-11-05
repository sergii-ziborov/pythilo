# TreeNode(value) is ready to use: node.value, node.left, node.right.


def delete(root, value):
    if root is None:
        return None
    if value < root.value:
        root.left = delete(root.left, value)
    elif value > root.value:
        root.right = delete(root.right, value)
    else:
        if root.left is None:
            return root.right
        if root.right is None:
            return root.left
        # TODO: two children. Copy the smallest value of the right subtree
        # into this node, then delete that value from the right subtree.
        return root.left
    return root
