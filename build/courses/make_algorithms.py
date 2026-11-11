"""Writes Pythilo/Resources/Courses/39-algorithms.json: classic algorithms and data
structures, one lesson per idea, each paired with the Lab that traces it.

Run: python3 build/courses/make_algorithms.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Pythilo" / "Resources" / "Courses" / "39-algorithms.json"

CLOSING = ("Work through the example by hand before changing the starter. Decide what should "
           "happen for an empty input, a single value and a repeated value where those cases apply. "
           "The checks use several inputs so a hard-coded answer cannot stand in for the rule.")

LESSONS = []
# lesson id -> Lab ids it pairs with (written into the Lab catalogs)
LABS = {}


def lesson(id, title, intro, example, think, task, starter, solution, checks, hints, labs=()):
    body = f"# {title}\n\n{intro}\n\n```python\n{example.strip()}\n```\n\n## Think before coding\n\n{think} {CLOSING}\n"
    LESSONS.append({
        "id": id, "title": title, "body": body, "task": task,
        "starter": starter.strip() + "\n", "solution": solution.strip() + "\n",
        "checks": [{"name": name, "code": code.strip() + "\n"} for name, code in checks],
        "hints": hints, "explanation": think,
    })
    for lab in labs:
        LABS.setdefault(lab, []).append(id)


# ---------------------------------------------------------------- searching and pointers

lesson("binary-search", "Halve a sorted list with binary search",
 "A sorted list lets you discard half of the remaining items with one comparison. Keep two bounds, lo and hi, around the part that can still contain the target. Look at the middle, then move one bound past it.",
 """
items = [2, 5, 8, 13, 21]
lo, hi = 0, len(items) - 1
mid = (lo + hi) // 2   # 2 -> items[2] is 8
""",
 "Each step removes at least the middle item, so the loop ends after about log2(n) steps. Use lo <= hi with inclusive bounds and move to mid + 1 or mid - 1, never to mid itself, or a two-item range can loop forever.",
 "Write binary_search(items, target) for a sorted list. Return an index where items holds target, or -1 when it is absent.",
 "def binary_search(items, target):\n    pass",
 """
def binary_search(items, target):
    lo, hi = 0, len(items) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if items[mid] == target:
            return mid
        if items[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1
""",
 [("found", "assert binary_search([2,5,8,13,21], 13) == 3"),
  ("first and last", "assert binary_search([2,5,8], 2) == 0 and binary_search([2,5,8], 8) == 2"),
  ("missing", "assert binary_search([2,5,8], 6) == -1 and binary_search([], 1) == -1"),
  ("large list", "big = list(range(0, 2_000_000, 2)); assert binary_search(big, 1_999_998) == 999_999 and binary_search(big, 7) == -1")],
 ["Start with lo = 0 and hi = len(items) - 1.", "Compare items[mid] with target to decide which half survives.", "Move lo to mid + 1 or hi to mid - 1 so the range always shrinks."],
 labs=["binsearch"])

lesson("pair-sum-pointers", "Meet in the middle with two pointers",
 "In a sorted list, a pair that sums too low needs a larger left value and a pair that sums too high needs a smaller right value. Two indices moving toward each other test every useful pair once.",
 """
items = [1, 3, 4, 6, 9]
left, right = 0, len(items) - 1
print(items[left] + items[right])   # 10
""",
 "When the sum is too small, no pair using the current left value can work with any smaller right value, so the left value is finished. The symmetric argument retires the right value. The scan is linear instead of quadratic.",
 "Write pair_with_sum(items, target) for a sorted list. Return a tuple of two indices (i, j) with i < j whose values add up to target, or None.",
 "def pair_with_sum(items, target):\n    return (0, 1)",
 """
def pair_with_sum(items, target):
    left, right = 0, len(items) - 1
    while left < right:
        total = items[left] + items[right]
        if total == target:
            return (left, right)
        if total < target:
            left += 1
        else:
            right -= 1
    return None
""",
 [("finds a pair", "i, j = pair_with_sum([1,3,4,6,9], 10); assert i < j and [1,3,4,6,9][i] + [1,3,4,6,9][j] == 10"),
  ("no pair", "assert pair_with_sum([1,2,3], 100) is None"),
  ("one value cannot pair with itself", "assert pair_with_sum([5], 10) is None and pair_with_sum([], 0) is None"),
  ("duplicates", "assert pair_with_sum([2,2,7], 4) == (0, 1)")],
 ["Start with one index at each end.", "Compare the sum with target.", "Move left up when the sum is small, right down when it is large."],
 labs=["window"])

lesson("longest-unique-window", "Slide a window over the longest unique run",
 "A window is a slice described by two indices. Grow it on the right one character at a time. When the new character is already inside, move the left edge just past its previous position instead of starting over.",
 """
last = {}
text = "abcab"
# at index 3, 'a' was seen at 0
# so left moves to 1
""",
 "Remember where each character was last seen. The left edge only moves forward, so each index enters and leaves the window once and the whole scan is linear. Take the maximum width after each step.",
 "Write longest_unique(text) returning the length of the longest substring with no repeated character.",
 "def longest_unique(text):\n    return len(set(text))",
 """
def longest_unique(text):
    last = {}
    left = best = 0
    for right, char in enumerate(text):
        if char in last and last[char] >= left:
            left = last[char] + 1
        last[char] = right
        best = max(best, right - left + 1)
    return best
""",
 [("classic", "assert longest_unique('abcabcbb') == 3"),
  ("all same", "assert longest_unique('bbbb') == 1"),
  ("empty", "assert longest_unique('') == 0"),
  ("repeat outside window", "assert longest_unique('abba') == 2 and longest_unique('pwwkew') == 3")],
 ["Keep a dictionary from character to its last index.", "Move left only when the repeat is inside the window.", "Update the best width after storing the new index."],
 labs=["window"])

lesson("merge-intervals", "Merge overlapping intervals after sorting",
 "Overlapping meetings, ranges of free memory and booked dates all reduce to intervals. Sorting by start puts every overlap next to each other, so one pass can merge them.",
 """
spans = sorted([(5, 8), (1, 3), (2, 4)])
print(spans)   # [(1, 3), (2, 4), (5, 8)]
""",
 "After sorting, an interval either starts inside the last merged one, which extends its end, or starts after it, which closes it and opens a new one. Use max for the end, because a short interval can sit entirely inside a longer one.",
 "Write merge(intervals) taking (start, end) tuples. Return the merged, sorted list; touching intervals such as (1, 2) and (2, 3) merge too. Leave the input list unchanged.",
 "def merge(intervals):\n    return intervals",
 """
def merge(intervals):
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged
""",
 [("overlap", "assert merge([(5,8),(1,3),(2,4)]) == [(1,4),(5,8)]"),
  ("contained", "assert merge([(1,10),(2,3)]) == [(1,10)]"),
  ("touching", "assert merge([(1,2),(2,3)]) == [(1,3)]"),
  ("empty and input intact", "a=[(3,4),(1,2)]; assert merge(a) == [(1,2),(3,4)] and a == [(3,4),(1,2)] and merge([]) == []")],
 ["Sort a copy by start.", "Compare each start with the end of the last merged interval.", "Extend with max(end) or append a new interval."])

# ---------------------------------------------------------------- stacks, queues, recursion

lesson("balanced-brackets", "Match brackets with a stack",
 "The most recently opened bracket must close first. That last-in, first-out order is exactly what a stack gives you: push every opener, and every closer must match the top.",
 """
stack = []
for char in "([])":
    print(char, stack)
""",
 "A closer is wrong when the stack is empty or its top is a different kind. At the end, anything still on the stack was never closed. Other characters are ignored, so the same check works on code or formulas.",
 "Write balanced(text) returning True when every (, [ and { is closed by its own kind in the right order. Ignore all other characters.",
 "def balanced(text):\n    return text.count('(') == text.count(')')",
 """
def balanced(text):
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    for char in text:
        if char in '([{':
            stack.append(char)
        elif char in pairs:
            if not stack or stack.pop() != pairs[char]:
                return False
    return not stack
""",
 [("nested", "assert balanced('{[()()]}') and balanced('f(a[1]) + {x}')"),
  ("wrong order", "assert not balanced('([)]')"),
  ("unclosed and extra closer", "assert not balanced('((') and not balanced('())')"),
  ("empty", "assert balanced('')")],
 ["Push each opening bracket.", "On a closer, pop and compare with its partner.", "The text is balanced only if the stack ends empty."],
 labs=["stackqueue"])

lesson("queue-elimination", "Rotate a queue to eliminate players",
 "A queue serves items in arrival order. collections.deque removes from the front in constant time, unlike list.pop(0), which shifts every remaining item.",
 """
from collections import deque
line = deque(["Ann", "Bob", "Cy"])
line.rotate(-1)
print(line)   # deque(['Bob', 'Cy', 'Ann'])
""",
 "Passing the item k times is the same as moving k people from the front to the back. The person now at the front is out. Repeat until the queue is empty, recording the order people leave.",
 "Write elimination_order(names, k): pass k times around the queue, remove whoever is at the front, and repeat. Return the names in the order they leave. Do not modify names.",
 "def elimination_order(names, k):\n    return list(names)",
 """
from collections import deque

def elimination_order(names, k):
    line = deque(names)
    order = []
    while line:
        line.rotate(-k)
        order.append(line.popleft())
    return order
""",
 [("three players", "assert elimination_order(['A','B','C'], 1) == ['B','A','C']"),
  ("k zero keeps order", "assert elimination_order(['A','B','C'], 0) == ['A','B','C']"),
  ("large k", "assert elimination_order(['A','B'], 5) == ['B','A']"),
  ("input intact", "n=['x','y']; elimination_order(n, 1); assert n == ['x','y'] and elimination_order([], 3) == []")],
 ["Copy names into a deque.", "rotate(-k) moves k people from front to back.", "popleft() removes the player who is out."],
 labs=["stackqueue"])

lesson("recursive-permutations", "Build permutations by fixing one item",
 "A recursive function solves a problem by trusting a smaller copy of itself. To order n items, choose which item goes first, then ask for every ordering of the remaining items.",
 """
def count(n):
    return 1 if n <= 1 else n * count(n - 1)
print(count(4))   # 24 orderings
""",
 "The base case is an empty list, which has exactly one ordering: the empty one. Each level loops over the items, removes one and prefixes it to every smaller ordering. Removing by position keeps repeated values correct.",
 "Write permutations(items) returning every ordering of items as a list of lists, in the order produced by choosing positions left to right.",
 "def permutations(items):\n    return [list(items)]",
 """
def permutations(items):
    if not items:
        return [[]]
    result = []
    for i, first in enumerate(items):
        rest = items[:i] + items[i + 1:]
        for tail in permutations(rest):
            result.append([first] + tail)
    return result
""",
 [("three items", "assert permutations([1,2,3]) == [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]"),
  ("empty", "assert permutations([]) == [[]]"),
  ("count", "assert len(permutations(list(range(5)))) == 120"),
  ("repeated values kept", "assert permutations([7,7]) == [[7,7],[7,7]]")],
 ["Return [[]] for an empty list.", "Loop over positions and remove that item.", "Prefix it to each permutation of the rest."],
 labs=["recursion"])

lesson("power-set", "List every subset with include or skip",
 "Every item faces one decision: in the subset or out. Two choices for each of n items give `2 ** n` subsets. Recursion makes the decision for the first item and lets a smaller call handle the rest.",
 """
items = ["a", "b"]
# skip a: [], [b]   take a: [a], [a, b]
""",
 "The subsets of the rest appear twice: once unchanged and once with the first item added in front. Keeping the skip branch first gives a predictable order, which helps when you compare results.",
 "Write subsets(items) returning all `2 ** n` subsets as lists, skip branch first, preserving item order inside each subset.",
 "def subsets(items):\n    return [list(items)]",
 """
def subsets(items):
    if not items:
        return [[]]
    rest = subsets(items[1:])
    return rest + [[items[0]] + subset for subset in rest]
""",
 [("two items", "assert subsets(['a','b']) == [[], ['b'], ['a'], ['a','b']]"),
  ("empty", "assert subsets([]) == [[]]"),
  ("count", "assert len(subsets(list(range(10)))) == 1024"),
  ("order inside subsets", "assert all(s == sorted(s) for s in subsets([1,2,3]))")],
 ["The empty list has one subset.", "Compute the subsets of items[1:] once.", "Return those, then the same with items[0] in front."],
 labs=["recursion"])

# ---------------------------------------------------------------- sorting

lesson("insertion-sort", "Insert each item into a sorted prefix",
 "Insertion sort keeps the left part of the list sorted. Each new item slides left past larger neighbours until it reaches its place, like sorting a hand of cards.",
 """
hand = [3, 7, 9, 4]
# 4 moves past 9 and 7, then stops after 3
""",
 "It takes about n squared steps in the worst case, yet it is fast on nearly sorted data and stable: equal items keep their order because an item stops at the first neighbour that is not larger.",
 "Write insertion_sort(items) returning a new sorted list, without calling sorted or list.sort, and without changing items.",
 "def insertion_sort(items):\n    return list(items)",
 """
def insertion_sort(items):
    result = list(items)
    for i in range(1, len(result)):
        value = result[i]
        j = i - 1
        while j >= 0 and result[j] > value:
            result[j + 1] = result[j]
            j -= 1
        result[j + 1] = value
    return result
""",
 [("mixed", "assert insertion_sort([3,7,9,4,1]) == [1,3,4,7,9]"),
  ("empty and single", "assert insertion_sort([]) == [] and insertion_sort([5]) == [5]"),
  ("stable", "pairs=[(1,'b'),(0,'x'),(1,'a')]; import functools\nclass K:\n    def __init__(s,p): s.p=p\n    def __gt__(s,o): return s.p[0] > o.p[0]\nassert [k.p for k in insertion_sort([K(p) for p in pairs])] == [(0,'x'),(1,'b'),(1,'a')]"),
  ("input intact", "a=[2,1]; insertion_sort(a); assert a == [2,1]")],
 ["Copy the list first.", "Hold result[i] aside and shift larger items right.", "Drop the held value into the gap."],
 labs=["sorting"])

lesson("merge-sort", "Sort by splitting and merging",
 "Merge sort splits the list in half, sorts each half recursively and merges the two sorted halves. Merging needs only one pass because the smallest remaining item is always at the front of one half.",
 """
left, right = [1, 4], [2, 3]
# take 1, then 2, then 3, then 4
""",
 "There are about log2(n) levels of splitting and each level merges n items, so the total is n log n. Taking from the left half when values are equal keeps the sort stable.",
 "Write merge_sort(items) returning a new sorted list using merge sort, without sorted or list.sort.",
 "def merge_sort(items):\n    return list(items)",
 """
def merge_sort(items):
    if len(items) <= 1:
        return list(items)
    middle = len(items) // 2
    left, right = merge_sort(items[:middle]), merge_sort(items[middle:])
    merged, i, j = [], 0, 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            merged.append(left[i]); i += 1
        else:
            merged.append(right[j]); j += 1
    return merged + left[i:] + right[j:]
""",
 [("mixed", "assert merge_sort([5,2,9,1,5,6]) == [1,2,5,5,6,9]"),
  ("empty and single", "assert merge_sort([]) == [] and merge_sort([3]) == [3]"),
  ("negative and sorted", "assert merge_sort([-1,-3,2]) == [-3,-1,2] and merge_sort([1,2,3]) == [1,2,3]"),
  ("larger", "import random; r=random.Random(4); a=[r.randint(-50,50) for _ in range(500)]; assert merge_sort(a) == sorted(a)")],
 ["Lists of length 0 or 1 are already sorted.", "Sort both halves recursively.", "Merge by repeatedly taking the smaller front item."],
 labs=["recursion", "sorting"])

lesson("quicksort-partition", "Partition around a pivot for quicksort",
 "Quicksort picks a pivot, moves smaller items before it and larger items after it, then sorts the two sides. The pivot is already in its final place after partitioning.",
 """
items = [7, 2, 9, 4]
pivot = items[-1]                     # 4
less = [x for x in items if x < pivot]
print(less)   # [2]
""",
 "With a fair pivot, each level halves the work and the total is n log n. Grouping values equal to the pivot separately prevents the slowdown on lists full of duplicates.",
 "Write quicksort(items) returning a new sorted list. Partition into less, equal and greater lists around a pivot and recurse on less and greater.",
 "def quicksort(items):\n    return list(items)",
 """
def quicksort(items):
    if len(items) <= 1:
        return list(items)
    pivot = items[len(items) // 2]
    less = [x for x in items if x < pivot]
    equal = [x for x in items if x == pivot]
    greater = [x for x in items if x > pivot]
    return quicksort(less) + equal + quicksort(greater)
""",
 [("mixed", "assert quicksort([7,2,9,4,4,1]) == [1,2,4,4,7,9]"),
  ("all equal", "assert quicksort([3]*1000) == [3]*1000"),
  ("empty", "assert quicksort([]) == []"),
  ("random", "import random; r=random.Random(9); a=[r.random() for _ in range(300)]; assert quicksort(a) == sorted(a)")],
 ["Pick a pivot from the middle.", "Build less, equal and greater lists.", "Concatenate the sorted sides around equal."],
 labs=["sorting"])

# ---------------------------------------------------------------- linked lists and hashing

LINKED = "class Node:\n    def __init__(self, value, next=None):\n        self.value = value\n        self.next = next\n\n"
TO_LIST = "def values(node):\n    out = []\n    while node:\n        out.append(node.value); node = node.next\n    return out\ndef build(xs):\n    head = None\n    for x in reversed(xs):\n        head = Node(x, head)\n    return head\n"

lesson("reverse-linked-list", "Reverse a linked list in place",
 "A singly linked list stores each value with a pointer to the next node. Reversing it means turning every arrow around. Three names track the work: the previous node, the current one and the next one you are about to lose.",
 """
class Node:
    def __init__(self, value, next=None):
        self.value, self.next = value, next
head = Node(1, Node(2, Node(3)))
""",
 "Save current.next before overwriting it, point current back at prev, then step both forward. When current becomes None, prev is the new head. No new nodes are created, so memory stays constant.",
 "Node(value, next) is provided. Write reverse(head) that reverses the list in place and returns the new head (None for an empty list).",
 LINKED + "def reverse(head):\n    return head",
 LINKED + """
def reverse(head):
    prev = None
    current = head
    while current:
        following = current.next
        current.next = prev
        prev, current = current, following
    return prev
""",
 [("three nodes", TO_LIST + "assert values(reverse(build([1,2,3]))) == [3,2,1]"),
  ("empty and single", TO_LIST + "assert reverse(None) is None and values(reverse(build([7]))) == [7]"),
  ("same nodes reused", TO_LIST + "h=build([1,2]); second=h.next; r=reverse(h); assert r is second and r.next is h and h.next is None")],
 ["Start with prev = None and current = head.", "Save current.next before changing it.", "Return prev when current runs out."],
 labs=["linkedlist"])

lesson("linked-list-middle", "Find the middle with slow and fast pointers",
 "You do not need the length of a linked list to find its middle. Move one pointer one step and another two steps at a time. When the fast one reaches the end, the slow one is halfway.",
 """
# 1 -> 2 -> 3 -> 4 -> 5
# slow: 1, 2, 3   fast: 1, 3, 5
""",
 "The same two-speed idea detects cycles, because a fast pointer inside a loop eventually laps the slow one. For an even number of nodes, this version returns the second of the two middle nodes.",
 "Node(value, next) is provided. Write middle(head) returning the middle node in one pass; for an even length return the second middle. Return None for an empty list.",
 LINKED + "def middle(head):\n    return head",
 LINKED + """
def middle(head):
    slow = fast = head
    while fast and fast.next:
        slow = slow.next
        fast = fast.next.next
    return slow
""",
 [("odd", TO_LIST + "assert middle(build([1,2,3,4,5])).value == 3"),
  ("even", TO_LIST + "assert middle(build([1,2,3,4])).value == 3"),
  ("short", TO_LIST + "assert middle(None) is None and middle(build([9])).value == 9")],
 ["Start both pointers at head.", "Loop while fast and fast.next exist.", "Move slow once and fast twice per step."],
 labs=["linkedlist"])

lesson("hash-two-sum", "Trade memory for speed with a dictionary",
 "Checking every pair of numbers is quadratic. A dictionary remembers values you have already seen and answers \"have I seen x?\" in constant time on average, so one pass is enough.",
 """
seen = {}
for index, value in enumerate([2, 7, 11]):
    seen[value] = index
print(9 - 7 in seen)   # True
""",
 "For each value, the partner you need is target minus value. Look it up before storing the current value, so an item is never paired with itself, and duplicates still find each other.",
 "Write two_sum(items, target) returning indices (i, j) with i < j and items[i] + items[j] == target, choosing the pair whose j is smallest. Return None when no pair exists. The list is not sorted.",
 "def two_sum(items, target):\n    for i in range(len(items)):\n        for j in range(len(items)):\n            if items[i] + items[j] == target:\n                return (i, j)",
 """
def two_sum(items, target):
    seen = {}
    for j, value in enumerate(items):
        if target - value in seen:
            return (seen[target - value], j)
        seen.setdefault(value, j)
    return None
""",
 [("basic", "assert two_sum([2,7,11,15], 9) == (0,1)"),
  ("not with itself", "assert two_sum([3,4], 6) is None"),
  ("duplicates", "assert two_sum([3,3], 6) == (0,1)"),
  ("unsorted and missing", "assert two_sum([8,1,5,3], 4) == (1,3) and two_sum([], 1) is None")],
 ["Map each seen value to its index.", "Before storing, look up target - value.", "Return the stored index and the current one."],
 labs=["hash"])

# ---------------------------------------------------------------- trees and heaps

TREE = "class TreeNode:\n    def __init__(self, value):\n        self.value = value\n        self.left = None\n        self.right = None\n\n"
INORDER = "def inorder(n):\n    return inorder(n.left) + [n.value] + inorder(n.right) if n else []\n"

lesson("bst-insert", "Insert into a binary search tree",
 "In a binary search tree every value in a node's left subtree is smaller and every value in its right subtree is larger. Inserting walks down as a search would and attaches a new node where the search falls off the tree.",
 """
# 8 has 3 on the left and 10 on the right
# inserting 6: 6 < 8 go left, 6 > 3 go right
""",
 "Returning the root from the recursive call lets an empty subtree become a new node without special cases. Ignoring duplicates keeps every value unique. An in-order walk of the result lists the values in sorted order.",
 "TreeNode(value) is provided. Write insert(root, value) returning the root after inserting value; insert into None to start a tree. Ignore a value that is already present.",
 TREE + "def insert(root, value):\n    return root",
 TREE + """
def insert(root, value):
    if root is None:
        return TreeNode(value)
    if value < root.value:
        root.left = insert(root.left, value)
    elif value > root.value:
        root.right = insert(root.right, value)
    return root
""",
 [("sorted in order", INORDER + "r=None\nfor v in [8,3,10,1,6,14]: r=insert(r,v)\nassert inorder(r) == [1,3,6,8,10,14]"),
  ("shape", "r=None\nfor v in [8,3,10]: r=insert(r,v)\nassert r.value == 8 and r.left.value == 3 and r.right.value == 10"),
  ("duplicates ignored", INORDER + "r=None\nfor v in [5,5,5]: r=insert(r,v)\nassert inorder(r) == [5]")],
 ["An empty tree becomes TreeNode(value).", "Go left for smaller values and right for larger ones.", "Assign the recursive result back to root.left or root.right."],
 labs=["bst"])

lesson("bst-delete", "Delete from a binary search tree",
 "Deleting a leaf or a node with one child is easy: replace it with that child. A node with two children needs a stand-in that keeps the ordering, and the smallest value in its right subtree fits exactly.",
 """
# delete 3 from: 3 has children 1 and 6
# successor: smallest in right subtree -> 6
""",
 "Copy the successor's value into the node, then delete that successor from the right subtree. The successor has no left child, so the second deletion is always one of the easy cases.",
 "TreeNode(value) is provided. Write delete(root, value) returning the root after removing value. Leave the tree unchanged if value is absent.",
 TREE + INORDER + "def insert(root, value):\n    if root is None:\n        return TreeNode(value)\n    if value < root.value:\n        root.left = insert(root.left, value)\n    elif value > root.value:\n        root.right = insert(root.right, value)\n    return root\n\ndef delete(root, value):\n    return root",
 TREE + INORDER + """
def insert(root, value):
    if root is None:
        return TreeNode(value)
    if value < root.value:
        root.left = insert(root.left, value)
    elif value > root.value:
        root.right = insert(root.right, value)
    return root

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
        successor = root.right
        while successor.left:
            successor = successor.left
        root.value = successor.value
        root.right = delete(root.right, successor.value)
    return root
""",
 [("two children", "r=None\nfor v in [8,3,10,1,6,14,4,7]: r=insert(r,v)\nr=delete(r,3)\nassert inorder(r) == [1,4,6,7,8,10,14]"),
  ("root and leaf", "r=None\nfor v in [5,2,9]: r=insert(r,v)\nr=delete(r,5); r=delete(r,2)\nassert inorder(r) == [9]"),
  ("missing and empty", "r=insert(None,1)\nassert inorder(delete(r,42)) == [1] and delete(None, 3) is None")],
 ["Search for the node, assigning recursive results back.", "With at most one child, return that child.", "With two, copy the right subtree's minimum and delete it there."],
 labs=["bst"])

lesson("heap-push-pop", "Keep a min-heap in a plain list",
 "A heap is a tree stored in a list: the children of index i sit at 2i+1 and 2i+2, and every parent is no larger than its children. The smallest item is always at index 0.",
 """
heap = [1, 4, 2, 9]
i = 3
print((i - 1) // 2)   # parent index 1
""",
 "Push appends and sifts the new item up while it is smaller than its parent. Pop moves the last item to the root and sifts it down, swapping with the smaller child. Both take about log2(n) swaps.",
 "Write push(heap, value) and pop(heap) for a min-heap kept in a list, without the heapq module. pop removes and returns the smallest item.",
 "def push(heap, value):\n    heap.append(value)\n\ndef pop(heap):\n    return heap.pop()",
 """
def push(heap, value):
    heap.append(value)
    i = len(heap) - 1
    while i > 0 and heap[(i - 1) // 2] > heap[i]:
        parent = (i - 1) // 2
        heap[i], heap[parent] = heap[parent], heap[i]
        i = parent

def pop(heap):
    last = heap.pop()
    if not heap:
        return last
    smallest, heap[0] = heap[0], last
    i = 0
    while True:
        child = 2 * i + 1
        if child >= len(heap):
            break
        if child + 1 < len(heap) and heap[child + 1] < heap[child]:
            child += 1
        if heap[i] <= heap[child]:
            break
        heap[i], heap[child] = heap[child], heap[i]
        i = child
    return smallest
""",
 [("sorted output", "h=[]\nfor v in [5,1,8,3,9,2]: push(h,v)\nassert [pop(h) for _ in range(6)] == [1,2,3,5,8,9]"),
  ("heap property", "h=[]\nfor v in [7,3,5,1]: push(h,v)\nassert all(h[(i-1)//2] <= h[i] for i in range(1,len(h)))"),
  ("duplicates and single", "h=[]\nfor v in [4,4,1]: push(h,v)\nassert [pop(h),pop(h),pop(h)] == [1,4,4] and h == []"),
  ("random", "import random; r=random.Random(2); h=[]; a=[r.randint(0,99) for _ in range(200)]\nfor v in a: push(h,v)\nassert [pop(h) for _ in a] == sorted(a)")],
 ["Parent of i is (i - 1) // 2.", "Sift up after push while the parent is larger.", "After moving the last item to the root, swap with the smaller child."],
 labs=["heap"])

lesson("k-smallest", "Pick the k smallest with heapq",
 "Python's heapq module implements the heap from the previous lesson on plain lists. heapify arranges a list in linear time, and heappop returns the smallest item in logarithmic time.",
 """
import heapq
scores = [42, 7, 19, 3]
heapq.heapify(scores)
print(heapq.heappop(scores))   # 3
""",
 "Sorting everything costs n log n even when you need three items. Popping k times from a heap costs n plus k log n. Copy the input first, because heapify rearranges the list it is given.",
 "Write k_smallest(items, k) returning the k smallest values in ascending order using heapq, without modifying items. If k exceeds the length, return all values sorted.",
 "def k_smallest(items, k):\n    return items[:k]",
 """
import heapq

def k_smallest(items, k):
    heap = list(items)
    heapq.heapify(heap)
    return [heapq.heappop(heap) for _ in range(min(k, len(heap)))]
""",
 [("basic", "assert k_smallest([42,7,19,3,8], 3) == [3,7,8]"),
  ("k too large", "assert k_smallest([2,1], 5) == [1,2]"),
  ("zero and empty", "assert k_smallest([5], 0) == [] and k_smallest([], 2) == []"),
  ("input intact", "a=[3,1,2]; k_smallest(a,2); assert a == [3,1,2]")],
 ["Copy the list.", "heapq.heapify the copy.", "heappop min(k, len) times."],
 labs=["heap"])

lesson("trie-prefix", "Store words letter by letter in a trie",
 "A trie is a tree of nested dictionaries, one letter per level. Words that share a prefix share the path for it, so finding every word that starts with \"ca\" means walking two steps and collecting what lies below.",
 """
root = {}
node = root
for letter in "cat":
    node = node.setdefault(letter, {})
node["$"] = True   # a word ends here
""",
 "The end marker distinguishes a stored word from a mere prefix: \"car\" can be a word while \"ca\" is not. Collect words with a depth-first walk that carries the letters so far, then sort the result for a stable order.",
 "Write a Trie class with add(word), contains(word) and complete(prefix). complete returns every stored word starting with prefix, sorted.",
 "class Trie:\n    def __init__(self):\n        self.words = []\n    def add(self, word):\n        pass\n    def contains(self, word):\n        return False\n    def complete(self, prefix):\n        return []",
 """
class Trie:
    def __init__(self):
        self.root = {}

    def add(self, word):
        node = self.root
        for letter in word:
            node = node.setdefault(letter, {})
        node["$"] = True

    def _find(self, prefix):
        node = self.root
        for letter in prefix:
            if letter not in node:
                return None
            node = node[letter]
        return node

    def contains(self, word):
        node = self._find(word)
        return bool(node and node.get("$"))

    def complete(self, prefix):
        found = []
        def walk(node, letters):
            for key, child in node.items():
                if key == "$":
                    found.append(letters)
                else:
                    walk(child, letters + key)
        start = self._find(prefix)
        if start is not None:
            walk(start, prefix)
        return sorted(found)
""",
 [("complete", "t=Trie()\nfor w in ['car','cat','cart','dog']: t.add(w)\nassert t.complete('ca') == ['car','cart','cat']"),
  ("prefix is not a word", "t=Trie(); t.add('car')\nassert t.contains('car') and not t.contains('ca')"),
  ("no match", "t=Trie(); t.add('a')\nassert t.complete('b') == [] and t.complete('') == ['a']"),
  ("empty word", "t=Trie(); t.add('')\nassert t.contains('') and t.complete('') == ['']")],
 ["Walk or create one dict per letter.", "Mark the end of a word with '$'.", "Walk from the prefix node and collect letters until each '$'."],
 labs=["trie"])

lesson("union-find", "Join sets quickly with union-find",
 "Union-find tracks which items belong together, such as connected computers or merged accounts. Each item points to a parent; following parents reaches a root that names the whole set.",
 """
parent = {x: x for x in "abc"}
parent["b"] = "a"      # b joins a's set
""",
 "Path compression makes every node on a find path point straight at the root, so later finds are almost instant. Union just points one root at the other. Two items are connected when their roots are equal.",
 "Write a UnionFind class built from an iterable of items, with find(x), union(a, b) and connected(a, b). Use path compression in find.",
 "class UnionFind:\n    def __init__(self, items):\n        self.parent = {x: x for x in items}\n    def find(self, x):\n        return x\n    def union(self, a, b):\n        pass\n    def connected(self, a, b):\n        return a == b",
 """
class UnionFind:
    def __init__(self, items):
        self.parent = {x: x for x in items}

    def find(self, x):
        root = x
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[x] != root:
            self.parent[x], x = root, self.parent[x]
        return root

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra

    def connected(self, a, b):
        return self.find(a) == self.find(b)
""",
 [("joins", "u=UnionFind('abcd'); u.union('a','b'); u.union('c','d')\nassert u.connected('a','b') and not u.connected('a','c')"),
  ("transitive", "u=UnionFind(range(5)); u.union(0,1); u.union(1,2)\nassert u.connected(0,2)"),
  ("compression", "u=UnionFind(range(4)); u.parent={0:0,1:0,2:1,3:2}\nassert u.find(3) == 0 and u.parent[3] == 0 and u.parent[2] == 0"),
  ("self", "u=UnionFind([7]); u.union(7,7); assert u.connected(7,7)")],
 ["Follow parent links until a node is its own parent.", "Point every node on the path at that root.", "Union links one root under the other."],
 labs=["unionfind"])

lesson("lru-cache", "Evict the least recently used key",
 "A cache keeps a limited number of results. When it is full, a least recently used policy drops the key nobody has touched for the longest time. OrderedDict remembers order and can move a key to the end in constant time.",
 """
from collections import OrderedDict
recent = OrderedDict(a=1, b=2)
recent.move_to_end("a")
print(list(recent))   # ['b', 'a']
""",
 "Treat the end of the dictionary as most recent. Both get and put on an existing key move it there. When an insert exceeds capacity, popitem(last=False) removes the oldest key from the front.",
 "Write LRUCache(capacity) with get(key), returning None when missing, and put(key, value). A full cache evicts the least recently used key.",
 "class LRUCache:\n    def __init__(self, capacity):\n        self.data = {}\n    def get(self, key):\n        return self.data.get(key)\n    def put(self, key, value):\n        self.data[key] = value",
 """
from collections import OrderedDict

class LRUCache:
    def __init__(self, capacity):
        self.capacity = capacity
        self.data = OrderedDict()

    def get(self, key):
        if key not in self.data:
            return None
        self.data.move_to_end(key)
        return self.data[key]

    def put(self, key, value):
        self.data[key] = value
        self.data.move_to_end(key)
        if len(self.data) > self.capacity:
            self.data.popitem(last=False)
""",
 [("evicts oldest", "c=LRUCache(2); c.put('a',1); c.put('b',2); c.put('c',3)\nassert c.get('a') is None and c.get('c') == 3"),
  ("get refreshes", "c=LRUCache(2); c.put('a',1); c.put('b',2); c.get('a'); c.put('c',3)\nassert c.get('b') is None and c.get('a') == 1"),
  ("update refreshes", "c=LRUCache(2); c.put('a',1); c.put('b',2); c.put('a',9); c.put('c',3)\nassert c.get('a') == 9 and c.get('b') is None"),
  ("missing", "assert LRUCache(1).get('x') is None")],
 ["Keep the data in an OrderedDict.", "move_to_end on every get hit and put.", "popitem(last=False) when over capacity."],
 labs=["lru"])

# ---------------------------------------------------------------- graphs

lesson("bfs-shortest-path", "Find the fewest steps with breadth-first search",
 "Breadth-first search explores a graph in rings: every node one step away, then every node two steps away. The first time it reaches a node, it has used the fewest possible edges.",
 """
graph = {"a": ["b", "c"], "b": ["d"],
         "c": ["d"], "d": []}
# ring 0: a   ring 1: b, c   ring 2: d
""",
 "Use a deque as the queue and mark nodes when they are added, not when they are taken out, so nothing is queued twice. Store each node's parent to rebuild the path backwards from the goal.",
 "Write shortest_path(graph, start, goal) for an adjacency dict. Return the list of nodes on a path with the fewest edges, or None when goal cannot be reached. Visit neighbours in listed order.",
 "def shortest_path(graph, start, goal):\n    return [start, goal]",
 """
from collections import deque

def shortest_path(graph, start, goal):
    parent = {start: None}
    queue = deque([start])
    while queue:
        node = queue.popleft()
        if node == goal:
            path = []
            while node is not None:
                path.append(node)
                node = parent[node]
            return path[::-1]
        for neighbour in graph.get(node, []):
            if neighbour not in parent:
                parent[neighbour] = node
                queue.append(neighbour)
    return None
""",
 [("diamond", "g={'a':['b','c'],'b':['d'],'c':['d'],'d':[]}\nassert shortest_path(g,'a','d') == ['a','b','d']"),
  ("start is goal", "assert shortest_path({'a':[]}, 'a', 'a') == ['a']"),
  ("unreachable", "assert shortest_path({'a':['b'],'b':[],'c':[]}, 'a', 'c') is None"),
  ("cycle and shortcut", "g={1:[2,4],2:[3],3:[1,5],4:[5],5:[]}\nassert shortest_path(g,1,5) == [1,4,5]")],
 ["Queue the start and record its parent as None.", "Record a parent when you first see a neighbour.", "Walk parents back from the goal and reverse."],
 labs=["graph"])

lesson("dfs-components", "Count connected groups with depth-first search",
 "Depth-first search follows one path as far as it goes before backing up. Started from every unvisited node, it splits an undirected graph into connected components, such as friend circles or separate road networks.",
 """
stack = ["a"]
seen = {"a"}
node = stack.pop()
# push a's unseen neighbours next
""",
 "An explicit stack avoids Python's recursion limit on long chains. Every node is pushed at most once because it is marked when pushed, so the whole count is linear in nodes plus edges.",
 "Write count_components(graph) for an undirected adjacency dict (every edge listed both ways). Return the number of connected components.",
 "def count_components(graph):\n    return len(graph)",
 """
def count_components(graph):
    seen = set()
    count = 0
    for start in graph:
        if start in seen:
            continue
        count += 1
        seen.add(start)
        stack = [start]
        while stack:
            node = stack.pop()
            for neighbour in graph[node]:
                if neighbour not in seen:
                    seen.add(neighbour)
                    stack.append(neighbour)
    return count
""",
 [("two groups", "g={1:[2],2:[1,3],3:[2],4:[5],5:[4]}\nassert count_components(g) == 2"),
  ("isolated nodes", "assert count_components({'a':[],'b':[],'c':[]}) == 3"),
  ("empty", "assert count_components({}) == 0"),
  ("long chain", "n=50000; g={i:[] for i in range(n)}\nfor i in range(n-1): g[i].append(i+1); g[i+1].append(i)\nassert count_components(g) == 1")],
 ["Loop over every node as a possible start.", "Each unseen start begins a new component.", "Use a stack to mark everything reachable from it."],
 labs=["graph", "flood"])

lesson("dijkstra", "Find cheapest routes with Dijkstra's algorithm",
 "When edges have costs, the fewest edges is not the cheapest route. Dijkstra's algorithm always settles the closest unsettled node next, using a heap of tentative distances.",
 """
import heapq
frontier = [(0, "a")]
cost, node = heapq.heappop(frontier)
""",
 "With non-negative costs, the cheapest entry in the heap can never be improved later, so it is final. Skip stale heap entries whose cost is larger than the best known distance instead of deleting them.",
 "Write distances(graph, start) where graph maps a node to a list of (neighbour, cost) pairs with non-negative costs. Return a dict of the cheapest cost to every reachable node.",
 "def distances(graph, start):\n    return {start: 0}",
 """
import heapq

def distances(graph, start):
    best = {start: 0}
    heap = [(0, start)]
    while heap:
        cost, node = heapq.heappop(heap)
        if cost > best[node]:
            continue
        for neighbour, weight in graph.get(node, []):
            candidate = cost + weight
            if candidate < best.get(neighbour, float("inf")):
                best[neighbour] = candidate
                heapq.heappush(heap, (candidate, neighbour))
    return best
""",
 [("cheaper detour", "g={'a':[('b',5),('c',1)],'c':[('b',1)],'b':[]}\nassert distances(g,'a') == {'a':0,'c':1,'b':2}"),
  ("unreachable left out", "assert distances({'a':[],'z':[('a',1)]}, 'a') == {'a':0}"),
  ("zero cost and cycle", "g={1:[(2,0)],2:[(1,0),(3,4)],3:[]}\nassert distances(g,1) == {1:0,2:0,3:4}"),
  ("grid", "g={}\nfor r in range(10):\n    for c in range(10):\n        g[(r,c)]=[((r+dr,c+dc),1) for dr,dc in ((1,0),(0,1),(-1,0),(0,-1)) if 0<=r+dr<10 and 0<=c+dc<10]\nassert distances(g,(0,0))[(9,9)] == 18")],
 ["Start with best = {start: 0} and a heap of (0, start).", "Skip popped entries worse than best[node].", "Push a neighbour whenever its cost improves."],
 labs=["graph"])

lesson("flood-fill-islands", "Count islands on a grid",
 "A grid is a graph in disguise: each cell is a node and its up, down, left and right neighbours are edges. Counting islands of land is counting connected components of land cells.",
 """
grid = ["LL.",
        ".L.",
        "..L"]
# two islands: diagonal cells do not touch
""",
 "Scan every cell. When an unvisited land cell appears, count a new island and flood from it, marking every land cell you can reach. Check the bounds before indexing so the edges of the grid are safe.",
 "Write count_islands(grid), where grid is a list of equal-length strings with \"L\" for land and \".\" for water. Neighbours touch up, down, left or right.",
 "def count_islands(grid):\n    return sum(row.count('L') for row in grid)",
 """
def count_islands(grid):
    rows = len(grid)
    cols = len(grid[0]) if grid else 0
    seen = set()
    islands = 0
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] != "L" or (r, c) in seen:
                continue
            islands += 1
            stack = [(r, c)]
            seen.add((r, c))
            while stack:
                y, x = stack.pop()
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < rows and 0 <= nx < cols and grid[ny][nx] == "L" and (ny, nx) not in seen:
                        seen.add((ny, nx))
                        stack.append((ny, nx))
    return islands
""",
 [("diagonal does not join", "assert count_islands(['LL.','.L.','..L']) == 2"),
  ("all water and empty", "assert count_islands(['...']) == 0 and count_islands([]) == 0"),
  ("one big island", "assert count_islands(['LLL','L.L','LLL']) == 1"),
  ("large", "assert count_islands(['L'*300]*300) == 1")],
 ["Visit every cell once in a double loop.", "Each new unvisited L starts an island.", "Flood with a stack over the four neighbours inside the grid."],
 labs=["flood"])

lesson("bellman-ford", "Handle negative costs with Bellman-Ford",
 "Dijkstra's algorithm breaks when an edge can lower a cost after a node is settled. Bellman-Ford instead relaxes every edge again and again. A shortest path uses at most n - 1 edges, so n - 1 rounds are enough.",
 """
edges = [("a", "b", 4), ("a", "c", 2),
         ("c", "b", -3)]
# a -> c -> b costs -1, cheaper than a -> b
""",
 "If any edge still improves a distance after n - 1 rounds, a cycle with negative total cost is reachable and no cheapest path exists. Report that instead of returning wrong numbers.",
 "Write bellman_ford(nodes, edges, start) with edges as (u, v, cost). Return a dict of cheapest costs to reachable nodes, or None when a negative cycle is reachable from start.",
 "def bellman_ford(nodes, edges, start):\n    return {start: 0}",
 """
def bellman_ford(nodes, edges, start):
    best = {start: 0}
    for _ in range(len(nodes) - 1):
        changed = False
        for u, v, cost in edges:
            if u in best and best[u] + cost < best.get(v, float("inf")):
                best[v] = best[u] + cost
                changed = True
        if not changed:
            break
    for u, v, cost in edges:
        if u in best and best[u] + cost < best.get(v, float("inf")):
            return None
    return best
""",
 [("negative edge", "assert bellman_ford('abc', [('a','b',4),('a','c',2),('c','b',-3)], 'a') == {'a':0,'c':2,'b':-1}"),
  ("negative cycle", "assert bellman_ford('abc', [('a','b',1),('b','c',-2),('c','b',1)], 'a') is None"),
  ("unreachable cycle ignored", "assert bellman_ford('axy', [('x','y',-1),('y','x',-1)], 'a') == {'a':0}"),
  ("chain", "n=list(range(6)); e=[(i,i+1,-1) for i in range(5)]\nassert bellman_ford(n,e,0)[5] == -5")],
 ["Repeat len(nodes) - 1 rounds of relaxing every edge.", "Only relax from nodes that already have a cost.", "One more improving edge afterwards means a negative cycle."],
 labs=["bellmanford"])

# ---------------------------------------------------------------- dynamic programming and search

lesson("memoized-stairs", "Remember answers with memoization",
 "Counting the ways to climb n stairs taking one or two steps repeats the same subproblems many times. Store each answer the first time it is computed and the exponential tree collapses to a straight line.",
 """
from functools import cache

@cache
def ways(n):
    if n <= 1:
        return 1
    return ways(n - 1) + ways(n - 2)
""",
 "The last step was either one stair or two, so ways(n) = ways(n - 1) + ways(n - 2). A table filled from the bottom gives the same numbers without recursion and works for very large n.",
 "Write climb_ways(n) returning the number of ways to climb n stairs with steps of 1 or 2. climb_ways(0) is 1. It must handle n = 5000 quickly.",
 "def climb_ways(n):\n    if n <= 1:\n        return 1\n    return climb_ways(n - 1) + climb_ways(n - 2)",
 """
def climb_ways(n):
    previous, current = 1, 1
    for _ in range(n - 1):
        previous, current = current, previous + current
    return current
""",
 [("small", "assert [climb_ways(n) for n in range(6)] == [1,1,2,3,5,8]"),
  ("forty", "assert climb_ways(40) == 165580141"),
  ("large is fast", "assert climb_ways(5000) % 1000 == climb_ways(5000) % 1000 and len(str(climb_ways(5000))) == 1045")],
 ["ways(n) = ways(n - 1) + ways(n - 2).", "Keep only the last two answers.", "Loop upward instead of recursing."],
 labs=["dp"])

lesson("coin-change", "Fill a table for the fewest coins",
 "Greedy change fails for coins 1, 3 and 4 with amount 6: taking 4 first needs three coins, while 3 + 3 needs two. Dynamic programming tries every last coin for every smaller amount.",
 """
coins = [1, 3, 4]
# fewest coins for amounts 0..4
best = [0, 1, 2, 1, 1]
""",
 "best[a] is one plus the smallest best[a - coin] over coins that fit. Fill amounts from zero upward so every smaller answer is ready. Amounts no combination reaches stay infinite and become -1.",
 "Write fewest_coins(coins, amount) returning the minimum number of coins summing to amount, with unlimited coins of each value, or -1 if impossible.",
 "def fewest_coins(coins, amount):\n    count = 0\n    for coin in sorted(coins, reverse=True):\n        count += amount // coin\n        amount %= coin\n    return count",
 """
def fewest_coins(coins, amount):
    inf = float("inf")
    best = [0] + [inf] * amount
    for value in range(1, amount + 1):
        for coin in coins:
            if coin <= value and best[value - coin] + 1 < best[value]:
                best[value] = best[value - coin] + 1
    return best[amount] if best[amount] != inf else -1
""",
 [("greedy trap", "assert fewest_coins([1,3,4], 6) == 2"),
  ("impossible", "assert fewest_coins([2], 3) == -1"),
  ("zero amount", "assert fewest_coins([5], 0) == 0"),
  ("larger", "assert fewest_coins([1,5,10,25], 99) == 9")],
 ["best[0] is 0 and everything else starts infinite.", "For each amount try every coin that fits.", "Return -1 if the final entry is still infinite."],
 labs=["dp"])

lesson("longest-common-subsequence", "Compare two strings with a 2D table",
 "A subsequence keeps characters in order but may skip some. The longest common subsequence of two texts measures how similar they are, and diff tools build on the same table.",
 """
a, b = "abcde", "ace"
# common subsequence: "ace", length 3
""",
 "Cell (i, j) holds the answer for the first i characters of a and the first j of b. Equal last characters extend the diagonal answer by one; otherwise take the better of dropping a character from either text.",
 "Write lcs_length(a, b) returning the length of the longest common subsequence of two strings.",
 "def lcs_length(a, b):\n    return len(set(a) & set(b))",
 """
def lcs_length(a, b):
    table = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            if a[i - 1] == b[j - 1]:
                table[i][j] = table[i - 1][j - 1] + 1
            else:
                table[i][j] = max(table[i - 1][j], table[i][j - 1])
    return table[len(a)][len(b)]
""",
 [("classic", "assert lcs_length('abcde','ace') == 3"),
  ("order matters", "assert lcs_length('abc','cba') == 1"),
  ("repeats", "assert lcs_length('aaaa','aa') == 2"),
  ("empty", "assert lcs_length('','abc') == 0 and lcs_length('', '') == 0")],
 ["Make a (len(a)+1) by (len(b)+1) table of zeros.", "Matching characters add one to the diagonal cell.", "Otherwise copy the larger of the cell above and to the left."],
 labs=["dp"])

lesson("n-queens", "Backtrack through N queens",
 "Backtracking builds a solution one choice at a time and undoes a choice as soon as it cannot lead anywhere. For N queens, place one queen per row and reject any column or diagonal already under attack.",
 """
cols, diag1, diag2 = set(), set(), set()
row, col = 2, 1
print(row - col, row + col)   # 1 3
""",
 "Cells on one diagonal share row - col; cells on the other share row + col. Three sets make each safety check constant time. After exploring a placement, remove it from the sets so the next column starts clean.",
 "Write solve(n) returning every solution as a list of column indices, one per row, in lexicographic order.",
 "def solve(n):\n    return [list(range(n))]",
 """
def solve(n):
    solutions = []
    placed = []
    cols, diag1, diag2 = set(), set(), set()

    def place(row):
        if row == n:
            solutions.append(list(placed))
            return
        for col in range(n):
            if col in cols or row - col in diag1 or row + col in diag2:
                continue
            cols.add(col); diag1.add(row - col); diag2.add(row + col); placed.append(col)
            place(row + 1)
            cols.remove(col); diag1.remove(row - col); diag2.remove(row + col); placed.pop()

    place(0)
    return solutions
""",
 [("four", "assert solve(4) == [[1,3,0,2],[2,0,3,1]]"),
  ("counts", "assert [len(solve(n)) for n in range(1,9)] == [1,0,0,2,10,4,40,92]"),
  ("valid", "for s in solve(6):\n    assert len(set(s)) == 6 and len({r-c for r,c in enumerate(s)}) == 6 and len({r+c for r,c in enumerate(s)}) == 6")],
 ["Place one queen per row, trying columns left to right.", "Track used columns and both diagonals in sets.", "Undo the placement after the recursive call."],
 labs=["queens"])

lesson("kmp-search", "Never step back with Knuth-Morris-Pratt",
 "Naive matching restarts after every mismatch and can compare the same text characters many times. Knuth-Morris-Pratt first studies the pattern: for each prefix it records the longest proper prefix that is also a suffix.",
 """
pattern = "abab"
failure = [0, 0, 1, 2]
# after a full "abab" match,
# "ab" counts toward the next one
""",
 "On a mismatch, fall back through the failure table instead of moving backwards in the text. Each text character is read once, so the search is linear in text plus pattern, and overlapping matches are found naturally.",
 "Write find_all(text, pattern) returning every start index of pattern in text, overlaps included, in linear time. A non-empty pattern is guaranteed.",
 "def find_all(text, pattern):\n    return [text.find(pattern)]",
 """
def find_all(text, pattern):
    failure = [0] * len(pattern)
    k = 0
    for i in range(1, len(pattern)):
        while k and pattern[i] != pattern[k]:
            k = failure[k - 1]
        if pattern[i] == pattern[k]:
            k += 1
        failure[i] = k
    matches = []
    k = 0
    for i, char in enumerate(text):
        while k and char != pattern[k]:
            k = failure[k - 1]
        if char == pattern[k]:
            k += 1
        if k == len(pattern):
            matches.append(i - k + 1)
            k = failure[k - 1]
    return matches
""",
 [("overlaps", "assert find_all('abababa', 'aba') == [0,2,4]"),
  ("none", "assert find_all('hello', 'xyz') == [] and find_all('', 'a') == []"),
  ("whole text", "assert find_all('aaaa', 'aaaa') == [0]"),
  ("long", "t='a'*20000+'b'; assert find_all(t, 'a'*1000+'b') == [19000]")],
 ["Build failure[i]: longest proper prefix of pattern[:i+1] that is also its suffix.", "On mismatch set k = failure[k - 1] instead of moving back.", "After a full match record it and continue from failure[k - 1]."],
 labs=["matching"])

lesson("topological-order", "Order tasks with depth-first topological sort",
 "Build steps, course prerequisites and spreadsheet formulas form directed graphs without cycles. A topological order lists every task after everything it depends on.",
 """
needs = {"test": ["build"],
         "build": ["fetch"], "fetch": []}
# fetch, build, test
""",
 "Depth-first search can emit a node after all of its dependencies have been emitted. Three states detect cycles: unvisited, in progress and done. Meeting a node that is still in progress means a cycle, so no order exists.",
 "Write build_order(needs) where needs maps each task to the tasks it depends on. Return a list with dependencies first, visiting tasks and dependencies in the given order, or raise ValueError on a cycle.",
 "def build_order(needs):\n    return list(needs)",
 """
def build_order(needs):
    state = {}
    order = []

    def visit(task):
        if state.get(task) == "done":
            return
        if state.get(task) == "active":
            raise ValueError(f"cycle at {task}")
        state[task] = "active"
        for dependency in needs.get(task, []):
            visit(dependency)
        state[task] = "done"
        order.append(task)

    for task in needs:
        visit(task)
    return order
""",
 [("chain", "assert build_order({'test':['build'],'build':['fetch'],'fetch':[]}) == ['fetch','build','test']"),
  ("shared dependency once", "o=build_order({'a':['c'],'b':['c'],'c':[]}); assert o == ['c','a','b']"),
  ("cycle", "raised = False\ntry:\n    build_order({'a':['b'],'b':['a']})\nexcept ValueError:\n    raised = True\nassert raised, 'cycle not reported'"),
  ("undeclared dependency", "assert build_order({'app':['lib']}) == ['lib','app']")],
 ["Track each task as active or done.", "Visit every dependency before appending the task.", "Seeing an active task again means a cycle."],
 labs=["topological"])


def main():
    course = {
        "id": "algorithms",
        "title": "Algorithms and data structures",
        "summary": "Searching, sorting, stacks, trees, heaps, graphs, dynamic programming and backtracking, one idea per lesson, each with a Lab that traces it step by step.",
        "kind": "path",
        "lessons": LESSONS,
    }
    OUT.write_text(json.dumps(course, indent=1, ensure_ascii=False) + "\n")
    links = ROOT / "build" / "courses" / "algorithms-lab-links.json"
    links.write_text(json.dumps(LABS, indent=1) + "\n")
    print(f"{len(LESSONS)} lessons -> {OUT.relative_to(ROOT)}; {len(LABS)} Labs linked")


if __name__ == "__main__":
    main()
