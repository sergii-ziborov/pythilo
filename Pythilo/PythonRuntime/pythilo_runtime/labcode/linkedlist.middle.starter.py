# Node(value, next) is ready to use: node.value, node.next.


def middle(head):
    slow = fast = head
    while fast and fast.next:
        slow = slow.next
        fast = fast.next  # TODO: fast should move two steps for every one of slow.
    return slow
