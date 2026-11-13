---
title: "Big-O you can count: lists, dicts, sets and heaps in Python"
description: "Learn complexity by counting comparisons and element moves instead of timing code: lists, sets, dicts, bisect, deque, sorted and heapq, each measured as n doubles."
date: 2026-11-08
author: Pythilo
cover: /blog/big-o-you-can-count/cover.jpg
coverAlt: "Abstract illustration: glowing blue and yellow curves with dots along them start from one point on a faint grid. One stays flat along the bottom, one rises a little and levels off, and the others climb more and more steeply out of the top of the frame."
tags: Python, Algorithms, Data structures
---

Most explanations of Big-O reach for a stopwatch. Time a loop over a thousand items, then over a million, and look at the curve. The trouble is that a stopwatch measures the machine as much as the code: the cache, the other programs running, the battery saver. Run the same test twice and you get two different answers.

This article uses a different instrument. Instead of asking how long an operation took, it asks how many basic steps the operation made, and counts them exactly. You will build a small key class that counts every comparison made with it, hand it to Python's own `list`, `set`, `dict`, `bisect`, `sorted` and `heapq`, and read the counter. The same program on the same Python prints the same count on a laptop, on a phone and in a browser, so you can check every number below yourself.

Counting also gives the notation a sharper meaning. O(1), O(log n) and O(n) stop being labels to memorise and become the answer to one question: when the input doubles, what happens to the count? By the end you will be able to answer that for the structures you use every day, and to choose between them by the work they do.

## A key that counts comparisons

Python's containers do not look inside your objects. To find, store or sort a value they call three special methods on it: `__eq__` for `==`, `__lt__` for `<` and `__hash__` for `hash()`. A class that defines those methods, and adds one to a counter in each comparison, sees every comparison a container makes.

Here it is, put to work on the most common question in programming: is this value in the collection? The loop builds a list and a set from the same n keys, then looks for one value that is absent and one that sits in the middle.

```python
class Key:
    """A value that counts every == and < made with it."""
    comparisons = 0

    def __init__(self, value):
        self.value = value

    def __eq__(self, other):
        Key.comparisons += 1
        return self.value == other.value

    def __lt__(self, other):
        Key.comparisons += 1
        return self.value < other.value

    def __hash__(self):
        return hash(self.value)


def counted(action):
    """Run action() and return how many comparisons it made."""
    Key.comparisons = 0
    action()
    return Key.comparisons


print("     n  list miss  list hit  set miss  set hit")
for n in (1000, 2000, 4000):
    as_list = [Key(v) for v in range(n)]
    as_set = set(as_list)
    absent = Key(-1)
    middle = Key(n // 2)          # equal to one item, but a new object
    print(f"{n:6}"
          f"{counted(lambda: absent in as_list):11}"
          f"{counted(lambda: middle in as_list):10}"
          f"{counted(lambda: absent in as_set):10}"
          f"{counted(lambda: middle in as_set):9}")
```

```text
     n  list miss  list hit  set miss  set hit
  1000       1000       501         0        1
  2000       2000      1001         0        1
  4000       4000      2001         0        1
```

Read the list columns first. To learn that a value was absent, the list compared it with all 1,000 items. With 2,000 items it made 2,000 comparisons, and with 4,000 it made 4,000. The value in the middle cost 501, 1,001 and 2,001: half the list, plus the one comparison that matched. A list has no idea where a value might be, so `in` starts at the front and checks each item until one is equal.

The set made one comparison for a hit and none at all for a miss, at every size. The section after next explains where the work went.

Two details of the experiment matter. The search uses `Key(n // 2)`, a new object that is equal to a stored one, because `in` tries `is` before `==`, and an identity match would never reach the counter. And `counted` takes a function, so the counter is reset just before the operation and read just after it. Each block below repeats the few lines of `Key` it needs, so every block runs on its own. You can paste any of them into the [playground](/playground/) and change the sizes. The numbers here come from CPython 3.14. A detail such as the exact number of comparisons in a sort can shift a little between Python versions. The pattern of growth does not.

## What doubling tells you

The useful thing in that output is not any single number. It is how each column changes from one row to the next, as n doubles.

- If the count stays the same, the operation is **O(1)**, constant. The set columns read 1, 1, 1.
- If the count goes up by a fixed amount, it is **O(log n)**, logarithmic. You will see 11, 12, 13 further down.
- If the count doubles, it is **O(n)**, linear. The list columns read 1,000, 2,000, 4,000.
- If the count a little more than doubles, it is **O(n log n)**. Sorting behaves this way.
- If the count is multiplied by four, it is **O(n²)**, quadratic. This appears as soon as a linear step sits inside a loop.

Big-O names the shape of the growth and drops constant factors. The list's miss column is n and its hit column is about half of n, and both are O(n), because both double when n doubles. That is deliberate. The constant depends on your data and your machine. The shape does not, and the shape decides what happens when the input gets large: the gap between the list and the set is as big as the list itself, and it keeps growing with it.

One more habit: say which case you mean. Finding a value in a list costs one comparison if the value is first, n if it is last or absent, and about half of n for a value somewhere in the middle. A Big-O statement usually describes the worst case or the average case, and a careful one says which.

## Why a set barely has to look

A list searches. A set calculates. It turns the key into a number with `hash()`, uses that number to pick one slot in a table, and looks there. It works like a cloakroom ticket: the number says which hook, however many coats are hanging.

![A funnel above a row of eight open compartments. Thin yellow lines curve from the funnel towards glowing yellow balls in the compartments. Two compartments are empty, most hold one ball, and one holds two balls stacked.](/blog/big-o-you-can-count/buckets.webp "A hash sends each key straight to a slot, often called a bucket. Two keys that want the same slot are a collision, and one of them has to look further.")

A model small enough to read makes this concrete. The table below is a plain list of slots. A value goes to slot `hash(value) % slots`. If that slot is taken, which is called a collision, the value tries the next slot along. A lookup follows the same path until it finds the value, or reaches an empty slot, which proves the value is absent. For small whole numbers `hash(v)` is just `v`, so you can check the arithmetic by hand.

```python
import random


def build(values, slots):
    table = [None] * slots
    for value in values:
        i = hash(value) % slots          # the hash picks the slot
        while table[i] is not None:      # taken: a collision
            i = (i + 1) % slots          # try the next slot along
        table[i] = value
    return table


def slots_visited(table, value):
    i = hash(value) % len(table)
    visited = 1
    while table[i] is not None and table[i] != value:
        i = (i + 1) % len(table)
        visited += 1
    return visited


def report(label, values, slots):
    table = build(values, slots)
    visits = [slots_visited(table, value) for value in values]
    average = sum(visits) / len(visits)
    print(f"{label:10} n={len(values):4}"
          f"  average {average:6.2f}  worst {max(visits):4}")


print(build([3, 11, 20, 42, 7, 19], 8))

random.seed(7)
for n in (1000, 2000, 4000):
    report("half full", random.sample(range(10**9), n), 2 * n)
for n in (1000, 2000, 4000):
    report("95% full", random.sample(range(10**9), n), n * 100 // 95)
for n in (250, 500, 1000):
    report("one slot", [v * 2 * n for v in range(n)], 2 * n)
```

```text
[None, None, 42, 3, 11, 20, 19, 7]
half full  n=1000  average   1.40  worst   10
half full  n=2000  average   1.55  worst   18
half full  n=4000  average   1.50  worst   22
95% full   n=1000  average   7.15  worst  306
95% full   n=2000  average   9.88  worst  303
95% full   n=4000  average   9.59  worst  781
one slot   n= 250  average 125.50  worst  250
one slot   n= 500  average 250.50  worst  500
one slot   n=1000  average 500.50  worst 1000
```

The first line is a table of eight slots after storing 3, 11, 20, 42, 7 and 19. The value 3 goes to slot 3. Then 11 also wants slot 3, because 11 % 8 is 3, finds it taken and settles in slot 4. Then 20 wants slot 4, now held by 11, and moves on to 5. The values 42 and 7 go straight to slots 2 and 7. Last, 19 wants slot 3 again and has to walk past three occupied slots to reach 6. Looking up 19 later repeats that walk: four slots visited.

Now the three experiments. With the table half full and the values well spread, a lookup visits 1.40, 1.55 and 1.50 slots on average for n = 1,000, 2,000 and 4,000. That is the whole claim about hash tables in three numbers: the average does not grow with n. The worst lookup in each table visited 10, 18 and 22 slots, so "constant" describes the average, not a promise for every key.

Fill the same kind of table to 95% and collisions pile up: between 7 and 10 slots on average, and worst cases of 306, 303 and 781. This is why Python never lets a table get that full. A dict moves to a larger table rather than let more than two thirds of its slots fill up, and a set follows a similar rule. Moving means placing every key again, which costs n steps, but it happens so rarely that the cost averaged over all insertions stays constant. The price is memory: a dict or a set always carries empty slots.

The last three lines break the model on purpose. Every value is a multiple of the table size, so every value wants slot 0. The table is still half empty, yet the average lookup visits 125.5, 250.5 and 500.5 slots, which is half of n. The sizes are smaller here for a reason: building such a table already takes about n²/2 steps. A hash table whose keys all land in one place is just a slow list.

### What breaks the promise in real Python

CPython's dict and set work like the model, with two refinements. After a collision they try further slots in a more scrambled order than "the next one along", which keeps clumps from growing. And they store each key's hash beside it and compare hashes first, calling `==` only when two hashes are equal. That is why the set in the first experiment made no counted comparisons on a miss: no stored key had the same hash, so `__eq__` was never needed. A hit needed one, to confirm that the equal hash was not a coincidence. A dict is the same table with a value stored next to each key.

So the thing to protect is the hash. Here is the counting key again, with a subclass whose `__hash__` returns the same number for every key, both used as dict keys.

```python
class Key:
    comparisons = 0

    def __init__(self, value):
        self.value = value

    def __eq__(self, other):
        Key.comparisons += 1
        return self.value == other.value

    def __hash__(self):
        return hash(self.value)


class SameHash(Key):
    def __hash__(self):
        return 42                     # legal, and a disaster


def counted(action):
    Key.comparisons = 0
    action()
    return Key.comparisons


for kind in (Key, SameHash):
    for n in (100, 200, 400):
        keys = [kind(v) for v in range(n)]
        build = counted(lambda: dict.fromkeys(keys))
        table = dict.fromkeys(keys)
        hit = counted(lambda: kind(n // 2) in table)
        miss = counted(lambda: kind(-1) in table)
        print(f"{kind.__name__:8} n={n}"
              f"  build {build:5}  hit {hit:3}  miss {miss:3}")
```

```text
Key      n=100  build     0  hit   1  miss   0
Key      n=200  build     0  hit   1  miss   0
Key      n=400  build     0  hit   1  miss   0
SameHash n=100  build  5039  hit  52  miss 101
SameHash n=200  build 20089  hit 102  miss 201
SameHash n=400  build 80131  hit 201  miss 400
```

With a sensible hash, building the dict needs no comparisons and a lookup needs at most one. With the constant hash, every key collides with every other. A miss is compared with every key in the dict: 101, 201 and 400 comparisons. The probing order can pass the same slot twice, which is why 100 keys cost 101. Building the dict takes 5,039, then 20,089, then 80,131 comparisons, four times more each time n doubles. The dict still gives correct answers. It gives them at the speed of a list, or worse.

Nobody writes `return 42` on purpose. The realistic versions are quieter:

- A `__hash__` that uses only a coarse field, such as the year of a date or the first letter of a name, so thousands of keys share a handful of hash values.
- A key that is expensive to hash. Hashing a long string reads every character, and hashing a tuple hashes every item in it. O(1) counts steps in the table, not the size of the key.
- A key that changes after it is stored. Its hash now points to a different slot and the dict can no longer find it. This is why a list cannot be a key, and why your own classes should hash only fields that never change.

The safe pattern for your own class is to build the hash from the same fields that `__eq__` compares, for example `hash((self.name, self.day))`, or to use a frozen dataclass and let Python write both methods.

## Binary search: halve, then halve again

A set answers "is it here?". It cannot answer "what is the nearest value below this one?" or "which items lie between these two?", because hashing scatters neighbours all over the table. Questions about order need ordered data, and ordered data allows a different trick.

In a sorted list, one comparison with the middle item tells you which half the target is in. The other half is discarded without being looked at. Then you repeat on the half that is left.

![Six rows of squares on a dark background. Each row has fewer filled blue squares than the row above, shrinking by about half each time, and the last row is a single glowing yellow square.](/blog/big-o-you-can-count/halving.webp "Each comparison discards about half of what is left. A few rows later, one candidate remains.")

The standard library has this as `bisect`. It calls `<` on our keys, so the counter works unchanged. The block compares it with a plain scan, looking for the last item, which is the worst case for the scan.

```python
import bisect
import math


class Key:
    comparisons = 0

    def __init__(self, value):
        self.value = value

    def __eq__(self, other):
        Key.comparisons += 1
        return self.value == other.value

    def __lt__(self, other):
        Key.comparisons += 1
        return self.value < other.value


def linear_index(items, target):
    for i, item in enumerate(items):
        if item == target:
            return i
    return -1


def binary_index(items, target):
    i = bisect.bisect_left(items, target)    # first place target could go
    if i < len(items) and items[i] == target:
        return i
    return -1


def counted(action):
    Key.comparisons = 0
    result = action()
    return result, Key.comparisons


for n in (1000, 2000, 4000):
    items = [Key(2 * v) for v in range(n)]   # sorted even numbers
    target = Key(2 * (n - 1))                # the last one: worst for a scan
    at_a, linear = counted(lambda: linear_index(items, target))
    at_b, binary = counted(lambda: binary_index(items, target))
    assert at_a == at_b == n - 1
    print(f"n={n}  linear {linear:4}  binary {binary}"
          f"  log2(n) {math.log2(n):.2f}")

big = range(0, 2_000_000_000, 2)             # a billion numbers, never stored
target = Key(1_234_567_890)
where, steps = counted(lambda: bisect.bisect_left(big, target, key=Key))
print(f"n={len(big):,}  binary {steps}  log2(n) {math.log2(len(big)):.2f}")
print(f"found at index {where:,}: {big[where]:,}")
```

```text
n=1000  linear 1000  binary 11  log2(n) 9.97
n=2000  linear 2000  binary 12  log2(n) 10.97
n=4000  linear 4000  binary 13  log2(n) 11.97
n=1,000,000,000  binary 30  log2(n) 29.90
found at index 617,283,945: 1,234,567,890
```

The scan needed 1,000, 2,000 and 4,000 comparisons. Binary search needed 11, 12 and 13: ten, eleven and twelve halvings inside `bisect_left`, plus one `==` at the end to confirm that the item at that position really is the target and not just the place where it would go. Doubling the list added one comparison. That is what O(log n) looks like, and it explains the base of the logarithm: log2(n) is the number of times you can halve n before you reach 1.

The last two lines push the idea further. A `range` is a sorted sequence that stores nothing, so `bisect` can search a billion even numbers without building them. The argument `key=Key` wraps each number that `bisect` inspects, so those comparisons are counted too. It found the position of 1,234,567,890 in 30 comparisons. A scan from the front would have made more than 617 million.

Binary search has a condition and a cost. The data must be sorted, and sorting costs more than one scan, as a later section counts. It pays off when you search the same data many times. Keeping a list sorted while you add to it is not free either: `bisect.insort` finds the place in O(log n) comparisons and then has to make room for the new item. Making room is the slow part of a list.

## The expensive end of a list

A Python list keeps its items side by side in one block of memory, in numbered slots. That is what makes `items[i]` instant: the place of slot i is simple arithmetic. It also means there is no gap at the front. To insert at position 0, every item already in the list moves one slot to the right. To remove the first item, every remaining item moves one slot to the left.

Comparisons are the wrong thing to count here, so the next block counts moves. `ModelList` does by hand what a real list does internally.

```python
from collections import deque


class ModelList:
    """Items sit side by side in numbered slots, as in a real list."""

    def __init__(self, items):
        self.slots = list(items)
        self.moves = 0

    def pop_back(self):
        return self.slots.pop()                  # nothing else has to move

    def pop_front(self):
        first = self.slots[0]
        for i in range(1, len(self.slots)):
            self.slots[i - 1] = self.slots[i]    # each later item moves left
            self.moves += 1
        self.slots.pop()
        return first

    def insert_front(self, item):
        self.slots.append(None)
        for i in range(len(self.slots) - 1, 0, -1):
            self.slots[i] = self.slots[i - 1]    # each item moves right
            self.moves += 1
        self.slots[0] = item


print("  n  pop back  pop front  insert front")
for n in (100, 200, 400):
    back = ModelList(range(n))
    while back.slots:
        back.pop_back()

    front = ModelList(range(n))
    order = []
    while front.slots:
        order.append(front.pop_front())

    grow = ModelList([])
    for item in range(n):
        grow.insert_front(item)

    queue = deque(range(n))                      # the real tool for this job
    assert [queue.popleft() for _ in range(n)] == order
    print(f"{n:3}{back.moves:10}{front.moves:11}{grow.moves:14}")
```

```text
  n  pop back  pop front  insert front
100         0       4950          4950
200         0      19900         19900
400         0      79800         79800
```

Emptying the list from the back moved nothing. Emptying it from the front moved 4,950 items for n = 100, 19,900 for n = 200 and 79,800 for n = 400. Each `pop_front` moves everything that is left, so the total for 100 items is 99 + 98 + ... + 1, which is n(n - 1)/2. Double n and the total is multiplied by four. One such operation is O(n), and a loop of n of them is O(n²). Building a list by inserting at the front costs exactly the same.

A real list moves its items with one fast memory copy instead of a Python loop, so `pop(0)` on a short list is nothing to worry about. The count is still n per call. By the same formula, draining a queue of a hundred thousand items with `pop(0)` moves about five billion references.

The end of a list is cheap because Python keeps some spare slots there. `append` usually writes into a free one. Now and then the spare room runs out and the whole list is copied to a larger block, but those copies are rare enough that the average cost of an `append` stays constant. The name for this is amortised O(1).

`collections.deque` fixes the front. It stores its items in a chain of small blocks with room at both ends, so `appendleft` and `popleft` move nothing, just as `append` and `pop` move nothing. The assert in the block checks that a deque hands back the same items in the same order as the model's `pop_front`. The trade is that a deque is poor at reaching into its middle: an index far from both ends has to walk along the chain. Use a list as a stack and a deque as a queue.

## Sorting, counted

Sorting is where the counter is most revealing, because `sorted` asks only one question of your data: is this item less than that one? Count the calls to `__lt__` and you have counted the sort.

```python
import math
import random


class Key:
    comparisons = 0

    def __init__(self, value):
        self.value = value

    def __lt__(self, other):
        Key.comparisons += 1
        return self.value < other.value


def comparisons_to_sort(values):
    items = [Key(v) for v in values]
    Key.comparisons = 0
    result = sorted(items)
    assert [key.value for key in result] == sorted(values)
    return Key.comparisons


random.seed(1)
print("     n  shuffled  n*log2(n)  ratio  log2(n!)  in order  reversed")
for n in (1000, 2000, 4000):
    values = list(range(n))
    random.shuffle(values)
    shuffled = comparisons_to_sort(values)
    in_order = comparisons_to_sort(range(n))
    backwards = comparisons_to_sort(range(n, 0, -1))
    n_log_n = n * math.log2(n)
    floor = math.log2(math.factorial(n))
    print(f"{n:6}{shuffled:10}{n_log_n:11.0f}{shuffled / n_log_n:7.2f}"
          f"{floor:10.0f}{in_order:10}{backwards:10}")
```

```text
     n  shuffled  n*log2(n)  ratio  log2(n!)  in order  reversed
  1000      8649       9966   0.87      8529       999       999
  2000     19333      21932   0.88     19053      1999      1999
  4000     42662      47863   0.89     42100      3999      3999
```

For shuffled data, `sorted` made 8,649 comparisons at n = 1,000, then 19,333 at 2,000 and 42,662 at 4,000. Each doubling multiplies the count by about 2.2: more than linear, and far less than the fourfold jump of n². The formula n·log2(n) gives 9,966, 21,932 and 47,863, and the ratio of the real count to the formula stays between 0.87 and 0.89. That steady ratio is what "sorting is O(n log n)" means. The formula is not the exact count. It has the right shape.

The `log2(n!)` column is a floor that no method can get under. There are n! possible orders of n items. Each yes-or-no comparison can at best rule out half of the orders that are still possible, so telling them all apart takes at least log2(n!) comparisons in the worst case. For 1,000 items that is 8,529. Python used 8,649, about 1.4% more. There is very little left to gain by sorting more cleverly. The gains are in not sorting at all.

The last two columns show the other side. Data that is already in order costs 999, 1,999 and 3,999 comparisons, which is n - 1, and so does data in exactly reverse order. Python's sort, an algorithm called Timsort, begins by looking for runs that already ascend or descend, and a fully ordered list is one long run. Real data is often partly ordered, like a log file with a few late entries, and then the cost lands somewhere between the two. O(n log n) is the worst case and the typical case for shuffled input. It is not the cost of every call.

## The k smallest without sorting everything

A common request: the ten cheapest offers, the ten nearest points, the ten slowest requests. The obvious code is `sorted(items)[:10]`. It puts all n items in perfect order and then throws nearly all of that work away.

A heap does less. It is a list arranged to keep one promise: no item is smaller than its parent, where the parent of the item at index i sits at index `(i - 1) // 2`. The smallest item is therefore always at index 0. Nothing else is promised. Two items on the same level can be in either order, and that looseness is what makes a heap cheap to build and cheap to repair.

![Seven balls joined by thin lines into a small binary tree: one yellow ball at the top, two blue balls below it and four blue balls along the bottom row.](/blog/big-o-you-can-count/heap.webp "A heap pictured as a tree. The item on top is the smallest, and the levels below it are only loosely ordered.")

The block finds the ten smallest of n keys in three ways and counts each.

```python
import heapq
import random


class Key:
    comparisons = 0

    def __init__(self, value):
        self.value = value

    def __lt__(self, other):
        Key.comparisons += 1
        return self.value < other.value


def counted(action):
    Key.comparisons = 0
    result = action()
    return [key.value for key in result], Key.comparisons


def pop_k(items, k):
    heap = list(items)
    heapq.heapify(heap)                  # the smallest item is now heap[0]
    return [heapq.heappop(heap) for _ in range(k)]


random.seed(3)
k = 10
print("     n  sort it all  heapify, 10 pops  nsmallest(10)")
for n in (1000, 2000, 4000):
    items = [Key(v) for v in random.sample(range(10 * n), n)]
    by_sort, sort_cost = counted(lambda: sorted(items)[:k])
    by_pops, pops_cost = counted(lambda: pop_k(items, k))
    by_heap, heap_cost = counted(lambda: heapq.nsmallest(k, items))
    assert by_sort == by_pops == by_heap
    print(f"{n:6}{sort_cost:13}{pops_cost:18}{heap_cost:15}")
```

```text
     n  sort it all  heapify, 10 pops  nsmallest(10)
  1000         8663              1732           1230
  2000        19299              3404           2206
  4000        42657              6712           4271
```

All three methods return the same ten values, and the assert checks that. Sorting everything costs about what the previous section measured: 42,657 comparisons at n = 4,000.

`heapify` followed by ten `heappop` calls costs 1,732, 3,404 and 6,712. That column roughly doubles when n doubles. Arranging a whole list into a heap is O(n), and each pop afterwards is O(log n), the work of repairing the heap once its top is removed.

`heapq.nsmallest(10, items)` does better still: 1,230, 2,206 and 4,271. It never builds a heap of everything. It keeps a small heap of the ten best candidates so far, with the worst of them on top. Each new item is compared once with that worst candidate, and most items lose and are dropped on the spot. Only an item that wins triggers a few more comparisons to put it in its place. So the cost is n plus a little: 230, 206 and 271 extra comparisons here. At n = 4,000 that is about ten times fewer comparisons than the full sort.

Two notes on using it. When k gets close to n, sorting is the better tool again, and for k = 1 plain `min()` is. And a one-off top ten is not the main job of a heap. Its main job is a queue ordered by priority while items keep arriving: `heappush` adds one in O(log n), `heappop` removes the smallest in O(log n), and `heap[0]` reads it for free.

## A cost list, and how to choose

The counts above generalise into a short list. Here n is the number of items in the container.

- `len(x)` is O(1) for every built-in container. The size is stored, not counted.
- `items[i]` and `items[i] = x` on a list are O(1).
- `items.append(x)` and `items.pop()` are O(1), amortised in the case of `append`.
- `items.insert(0, x)`, `items.pop(0)`, `del items[i]` and `items.remove(x)` are O(n), because the items after that position move.
- `x in items`, `items.index(x)`, `items.count(x)`, `min(items)`, `max(items)` and `sum(items)` are O(n). They may have to look at every item.
- A slice `items[a:b]` and `items.copy()` cost one step per item copied.
- `key in d`, `d[key]`, `d[key] = value`, `del d[key]`, `x in s`, `s.add(x)` and `s.discard(x)` are O(1) on average, given a good hash.
- `append`, `appendleft`, `pop` and `popleft` on a deque are O(1). Indexing the middle of a deque is O(n).
- `bisect.bisect_left(sorted_items, x)` is O(log n). `bisect.insort` is O(log n) comparisons plus O(n) moves.
- `sorted(items)` and `items.sort()` are O(n log n), and close to O(n) when the data is already nearly in order.
- `heapq.heapify(items)` is O(n). `heappush` and `heappop` are O(log n). Reading `heap[0]` is O(1).

Two lines of that list are behind a great many slow programs: `x in items` inside a loop, and `pop(0)` or `insert(0, x)` inside a loop. Each is a linear step repeated n times, so the count grows with n². The first is fixed by building a set once, before the loop. The second is fixed by a deque.

### Start from the question you ask most

Choosing a structure is easier from the other direction. Do not start from what the data is. Start from the question the program asks most often, and take the structure that answers it without searching.

- "Is x here?" Use a set.
- "What belongs to x?" Use a dict.
- "What is at position i?", or "give me everything in order". Use a list.
- "What arrived first?" Use a deque.
- "What is the smallest right now?", while items keep arriving. Use a heap.
- "Where does x fall among the others?", such as the nearest value or everything in a range. Keep a sorted list and use `bisect`.

Often one program needs two of these answers. Then it is normal to keep two structures over the same items: a list for the order and a set for membership, or a dict from id to record beside a heap of priorities. The extra memory is usually a fair price for removing a search from inside a loop.

When you are not sure, count. Wrap the keys, run the operation at n, 2n and 4n, and read how the count grows. Three rows are enough to tell constant from logarithmic from linear from quadratic.

## Where to go next

The counting key works on anything that compares. Try it on `list.index`, on `max`, on `bisect.insort`, or on a class of your own with a hash you are unsure about.

The [Algorithms and data structures course](/learn/algorithms/) takes these ideas one lesson at a time, including binary search, trading memory for speed with a dictionary, keeping a min-heap in a plain list and picking the k smallest with `heapq`, and each lesson has a Lab that traces the algorithm step by step. [Algorithm patterns](/learn/algorithm-patterns/) continues with prefix tables, monotonic stacks and binary-search boundaries, techniques that remove a factor of n by remembering work already done. The [Prefix Sums Lab](/labs/prefix/) builds cumulative totals in one pass and then answers any range sum with two lookups. The [Monotonic Stack Lab](/labs/monostack/) resolves every waiting item in a single pass, because each item is pushed once and popped at most once. The full list is on the [Labs](/labs/) page.

The lessons run free in the browser, and the Pythilo app runs them on iPhone and iPad offline.
