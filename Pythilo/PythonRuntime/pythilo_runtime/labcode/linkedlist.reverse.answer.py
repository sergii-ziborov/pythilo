# Node(value, next) is ready to use: node.value, node.next.


def reverse(head):
    prev = None
    current = head
    while current:
        nxt = current.next  # remember the rest before the link turns around
        current.next = prev
        prev = current
        current = nxt
    return prev
