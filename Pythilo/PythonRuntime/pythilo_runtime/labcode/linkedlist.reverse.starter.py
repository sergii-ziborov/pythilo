# Node(value, next) is ready to use: node.value, node.next.


def reverse(head):
    prev = None
    current = head
    while current:
        current.next = prev  # TODO: this cuts off the rest of the list. Save it first.
        prev = current
        current = current.next
    return prev
