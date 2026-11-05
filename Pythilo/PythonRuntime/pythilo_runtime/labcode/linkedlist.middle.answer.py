# Node(value, next) is ready to use: node.value, node.next.


def middle(head):
    slow = fast = head
    while fast and fast.next:
        slow = slow.next
        fast = fast.next.next
    return slow
