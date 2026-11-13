---
title: "asyncio from the inside: build a tiny event loop with generators"
description: "Build a small scheduler from generators, add a clock and a sleep, drive a real coroutine by hand, then see what asyncio.run does and why one slow call stalls every task."
date: 2026-11-09
author: Pythilo
cover: /blog/asyncio-from-the-inside/cover.jpg
coverAlt: "Abstract illustration: a thin glowing ring on a dark navy background with three blue and two yellow beads travelling around it, each leaving a short trail of light, and a small white dot at the centre."
tags: Python, asyncio, Concurrency
---

`async def` and `await` look like special machinery, and most explanations stop at "the event loop runs your coroutines". This post opens the box instead. You will write a scheduler that runs several functions in turn on one thread, in about twenty lines, using nothing but generators. You will give it a clock, so that tasks can sleep and wake in the right order without the program ever waiting. Then you will take a real `async def` function and drive it by hand, one `send` at a time.

After that, `asyncio.run`, `asyncio.gather` and `asyncio.sleep` read as larger and sturdier versions of code you have already written. That is worth more than curiosity. Two practical problems come up in every async program: the whole thing stalls because of one slow call, and somebody has to decide whether the code should be async at all. Both are easy to reason about once you can picture the loop.

Every program below is complete, and the output under it is what it really printed. None of them measures time. Concurrency shows in the order of the printed lines, which is the same on any machine.

## One thread, many slow things

A program that fetches three web pages spends nearly all of its time waiting. Say the replies take 3 seconds, 1 second and 2 seconds to arrive. Asked one after another, the program needs 3 + 1 + 2 = 6 seconds, and for almost all of that time the processor does nothing. If all three requests are sent first and each reply is handled when it arrives, the same work takes about 3 seconds, the length of the slowest reply.

The classic way to get there is one thread per request. That works, and a later section says when it is the right choice. But a thread is an expensive way to wait. Each one needs its own stack, and the operating system has to schedule it. Threads also switch at moments the operating system chooses, which can be halfway through an update to shared data.

The other way starts from a plain observation. Waiting does not use the processor, so one thread is enough, provided a function that has to wait can step aside. Stepping aside means three things: remember exactly where you were, hand control back, and carry on later from the same line with the same local variables. An ordinary function cannot do that. When it returns, its local variables are gone. Python has a kind of function that can, and it is older than `async`: the generator.

## A generator is a function that can pause

A function with `yield` in its body is a generator function. Calling it does not run it. The call returns a generator object, which holds the function's code, its local variables and a bookmark for the current line. Each time you ask the object to continue, it runs to the next `yield`, hands that value out and freezes again.

Most people meet generators in `for` loops, where values only come out. The other direction matters more here. `gen.send(value)` resumes the generator and makes `value` the result of the `yield` expression it was paused on. The first resume has no paused `yield` to receive anything, so it has to send `None`, and that is all `next(gen)` does.

```python
def greeter():
    print("  body: started")
    name = yield "who is there?"
    print(f"  body: received {name!r}")
    word = yield f"hello, {name}"
    print(f"  body: received {word!r}")
    return "finished"

gen = greeter()
print("created, and nothing has run yet")
print("1:", gen.send(None))        # the same as next(gen)
print("2:", gen.send("Ada"))
try:
    gen.send("bye")
except StopIteration as stop:
    print("3: StopIteration carrying", repr(stop.value))
```

```text
created, and nothing has run yet
  body: started
1: who is there?
  body: received 'Ada'
2: hello, Ada
  body: received 'bye'
3: StopIteration carrying 'finished'
```

Read the output against the code. Creating the generator printed nothing from the body. The first `send` ran the body to the first `yield` and came back with the question. The second `send` put `"Ada"` into `name`, ran to the second `yield` and came back with the greeting. The third ran off the end of the function. A generator that finishes raises `StopIteration`, and the value of its `return` statement rides on that exception as `stop.value`.

So a generator offers three things. It pauses with its state intact, the caller can pass a value in when resuming it, and it can hand back a final result. A scheduler needs nothing more. If generators are new to you, the [Python deeper course](/learn/deeper/) has lessons on them and on sending values in.

## A round-robin scheduler in about twenty lines

Treat each generator as a task, and each bare `yield` as the task saying "someone else can go now". The scheduler keeps the tasks in a queue. It takes the task at the front, runs it to its next `yield` and puts it at the back. A task that finishes is dropped.

```python
from collections import deque

def worker(name, steps):
    for i in range(1, steps + 1):
        print(f"{name} step {i}")
        yield                          # give the turn back
    return f"{name} finished"

def run(tasks):
    ready = deque(tasks)
    turns = 0
    while ready:
        task = ready.popleft()         # take the task at the front
        turns += 1
        try:
            next(task)                 # run it up to its next yield
        except StopIteration as stop:
            print("  ->", stop.value)  # it returned, so drop it
        else:
            ready.append(task)         # it paused, so back of the queue
    return turns

turns = run([worker("A", 3), worker("B", 1), worker("C", 2)])
print("turns:", turns)
```

```text
A step 1
B step 1
C step 1
A step 2
  -> B finished
C step 2
A step 3
  -> C finished
  -> A finished
turns: 9
```

Three tasks made progress in turn on one thread, with no threading module and no help from the operating system. `B` had one step, so it finished on its second turn, and after that `A` and `C` alternated. The loop took nine turns: six for the six steps, and one more for each task to find that it had nothing left to do.

Two properties of this small program are true of asyncio as well, so fix them in mind now.

- The switching is **cooperative**. The scheduler never interrupts a task. A task runs until it reaches a `yield`, and if it never reaches one, nothing else runs.
- Between two yields, a task has the thread to itself. No other task can change a variable while it is halfway through something. A whole class of thread bugs cannot happen here.

![A single horizontal ribbon of short segments that repeat blue, yellow and white, with thin curved lines merging into its left end, on a dark navy background.](/blog/asyncio-from-the-inside/interleaving.webp "One thread, three tasks. Their steps line up one after another on a single track, and each task gets its next turn after the others have had theirs.")

The proper name for `run` is an event loop, although so far it has no events. Every task is always ready, so the loop only spins through them. Real tasks spend most of their lives not ready: they are waiting for a reply, or for a moment in time. The next step teaches the loop about time.

## A clock that never waits

A task that wants to sleep should not be offered a turn until its time comes. So let a task say how long it wants to sleep by yielding a number: `yield 3` means "wake me in three seconds". The loop adds that to the current time and files the task under its wake-up time.

Among the sleeping tasks, the loop only ever needs the one that wakes soonest. A heap is the data structure for that job. Python's `heapq` module keeps a list arranged so that the smallest item is always at index 0, and adding or removing an item stays cheap with thousands of entries. Each entry here is a tuple: wake-up time, a running count, and the task. Tuples compare from the left, so the heap orders by time, and the count settles a tie in favour of the task that was filed first. The count has a second purpose. Without it, a tie on time would make Python compare two generators, which raises an error.

The clock is the neat part. It is a plain number, and nothing really waits. When the loop takes the next entry off the heap, it sets the clock to that entry's wake-up time. Time jumps straight to the next moment at which something happens.

```python
import heapq

class Loop:
    def __init__(self):
        self.now = 0
        self.heap = []                 # entries are (wake_time, count, task)
        self.count = 0

    def spawn(self, task, delay=0):
        heapq.heappush(self.heap, (self.now + delay, self.count, task))
        self.count += 1

    def run(self):
        while self.heap:
            self.now, _, task = heapq.heappop(self.heap)   # jump the clock
            try:
                delay = next(task)     # run until it asks to sleep
            except StopIteration:
                continue               # finished, nothing to put back
            self.spawn(task, delay)

loop = Loop()

def ticker(name, delay, times):
    for i in range(1, times + 1):
        yield delay                    # "wake me after this many seconds"
        print(f"t={loop.now}  {name} tick {i}")

loop.spawn(ticker("slow", 3, 2))
loop.spawn(ticker("fast", 1, 4))
loop.spawn(ticker("mid", 2, 2))
loop.run()
print("clock stopped at", loop.now)
print("one after another:", 3 * 2 + 1 * 4 + 2 * 2)
```

```text
t=1  fast tick 1
t=2  mid tick 1
t=2  fast tick 2
t=3  slow tick 1
t=3  fast tick 3
t=4  mid tick 2
t=4  fast tick 4
t=6  slow tick 2
clock stopped at 6
one after another: 14
```

Follow the first few lines. All three tasks start at time 0 and ask to sleep. `fast` asked for 1 second, so it wakes first, at `t=1`, and goes back to sleep until 2. At `t=2` two tasks are due. `mid` filed its entry before `fast` filed its second one, so `mid` goes first. The same rule produces every later line, until `slow` wakes for the last time at `t=6`.

The two numbers at the bottom are the reason people write async code. Done one after another, these sleeps add up to 3 × 2 + 1 × 4 + 2 × 2 = 14 seconds. Interleaved, the whole run fits into 6 seconds on the simulated clock, the length of the longest task, because the waits overlap.

![A pyramid of seven circles joined by thin lines, with a larger glowing yellow circle at the top and blue circles below it, beside a blank dial with a single hand, on a dark navy background.](/blog/asyncio-from-the-inside/timer-heap.webp "Sleeping tasks wait in a heap. Whichever wakes soonest sits at the top, so the loop always knows how far the clock has to move.")

A real event loop has the same two containers. asyncio keeps its ready callbacks in a `collections.deque` and its timers in a list managed with `heapq`. The difference is what happens when nothing is ready. Our loop jumps the clock. A real loop has to let real time pass, so it asks the operating system to put the thread to sleep until the earliest timer is due or until one of its network connections has something to report, whichever comes first. That single call is where an async program spends its idle time, and it is how one thread can watch thousands of connections.

A simulated clock is also a useful testing tool. Since nothing waits, code with hour-long timeouts can be tested in milliseconds, with the same result every time.

## From yield from to await

Real programs are more than one function deep. A task calls a function that calls another, and the pause happens at the bottom, in the function that does the waiting. A plain call does not work for that with generators, because calling a generator function only creates an object. The caller has to run the inner generator and pass each of its yields up towards the loop. Python has an expression for exactly this: `yield from`.

`result = yield from inner()` runs the inner generator to its end. Whatever the inner one yields goes straight out to whoever is driving the outer one. Whatever is sent in goes straight down to the inner one. When the inner one returns, its return value becomes `result`. A chain of generators joined by `yield from` behaves like one call stack that can pause as a whole, from the bottom.

That pattern became common enough to get its own syntax, and the mapping is direct:

- `async def` defines a coroutine function. Calling it returns a **coroutine object** and, as with a generator, runs none of the body.
- `await x` does the job of `yield from x`. It runs `x` until it is done, passes its pauses outward, and evaluates to its result.
- A coroutine object has `send`, `throw` and `close`, like a generator. It cannot be used in a `for` loop, and `next` refuses it, so nobody mistakes it for a sequence of values.

One piece is missing. A coroutine cannot use a bare `yield` to talk to the loop, because `yield` inside `async def` means something else. So an object at the bottom of every chain of awaits has to do the real pausing. That object has an `__await__` method. `__await__` is written as a generator, and its `yield` is the point where the whole chain stops and a value reaches the driver.

Here is about the smallest one possible, with a coroutine driven by hand and no event loop anywhere.

```python
class Ask:
    """The smallest awaitable: pass one value out to whoever drives us."""
    def __init__(self, question):
        self.question = question

    def __await__(self):
        answer = yield self.question   # travels out through every await
        return answer

async def double(label):
    number = await Ask(f"{label} wants a number")
    return number * 2

async def total():
    first = await double("first")
    second = await double("second")
    return first + second

coro = total()
print(type(coro).__name__)
print(coro.send(None))                 # run to the first Ask
print(coro.send(10))                   # answer it, run to the second
try:
    coro.send(11)                      # answer that, run to the end
except StopIteration as stop:
    print("result:", stop.value)
```

```text
coroutine
first wants a number
second wants a number
result: 42
```

`coro.send(None)` started `total`, which awaited `double("first")`, which awaited an `Ask`. The `yield` inside `Ask.__await__` paused all three layers at once, and its value came out of `send` at the top. Sending `10` resumed the chain at that same `yield`. The 10 travelled back in and was doubled, and `total` moved on to its second await. Sending `11` let everything finish. The final result arrived the way a generator's does, on `StopIteration`: 10 × 2 + 11 × 2 = 42.

Notice what `await double("first")` did not do. It did not pause anything by itself. It ran `double` much as a function call would, and the pause happened only because `double` reached an awaitable that yields. An `await` marks a place where a pause may happen. It does not force one.

Calling `send` again and again is what an event loop does. The clock loop from the previous section needs one changed line to run real coroutines: `next(task)` becomes `task.send(None)`. The sleep request moves into a small awaitable class.

```python
import heapq

class Sleep:
    def __init__(self, delay):
        self.delay = delay

    def __await__(self):
        yield self.delay               # the loop receives this number

class Loop:
    def __init__(self):
        self.now = 0
        self.heap = []
        self.count = 0

    def spawn(self, task, delay=0):
        heapq.heappush(self.heap, (self.now + delay, self.count, task))
        self.count += 1

    def run(self):
        while self.heap:
            self.now, _, task = heapq.heappop(self.heap)
            try:
                delay = task.send(None)     # the only changed line
            except StopIteration:
                continue
            self.spawn(task, delay)

loop = Loop()

async def fetch(name, delay):
    print(f"t={loop.now}  {name}: request sent")
    await Sleep(delay)
    print(f"t={loop.now}  {name}: reply arrived")
    return f"<{name}>"

async def page(name, delays):
    parts = []
    for i, delay in enumerate(delays, 1):
        parts.append(await fetch(f"{name}{i}", delay))
    print(f"t={loop.now}  page {name} complete: {' '.join(parts)}")

loop.spawn(page("a", [2, 2]))
loop.spawn(page("b", [1, 1, 1]))
loop.run()
print("clock stopped at", loop.now)
```

```text
t=0  a1: request sent
t=0  b1: request sent
t=1  b1: reply arrived
t=1  b2: request sent
t=2  a1: reply arrived
t=2  a2: request sent
t=2  b2: reply arrived
t=2  b3: request sent
t=3  b3: reply arrived
t=3  page b complete: <b1> <b2> <b3>
t=4  a2: reply arrived
t=4  page a complete: <a1> <a2>
clock stopped at 4
```

Two pages load at once. Page `a` makes two requests of 2 seconds each, and page `b` makes three of 1 second. Inside one page the requests happen in order, because each `await` finishes before the next line runs. Between the pages the work interleaves, and the run takes 4 simulated seconds instead of 2 + 2 + 1 + 1 + 1 = 7. `fetch` also hands its value back through the `await` with an ordinary `return`.

That is a working async runtime in about thirty lines. It lacks a great deal, but the shape is complete: coroutines that pause at the bottom of a chain of awaits, and a loop that decides who runs next.

## The real loop

asyncio is this design with the missing parts filled in. The match is close enough to state piece by piece.

- A **Task** wraps one coroutine, and it is the thing that calls `send(None)` on it. Each call runs the coroutine to its next real pause, as `run` did above.
- A **Future** is the awaitable at the bottom: a box for a result that does not exist yet. Its `__await__` yields the future itself. The task that receives it asks to be woken when the box is filled, and takes no more turns until then.
- `asyncio.sleep(delay)` creates a future and asks the loop to fill it after `delay` seconds. The loop keeps that timer in its heap.
- `asyncio.sleep(0)` is a special case. It is a bare `yield`, and a task that receives nothing from its coroutine puts itself at the back of the ready queue. That is the round-robin scheduler from earlier.
- `asyncio.run(main())` creates a loop, wraps `main()` in a task, runs the loop until that task is done, and closes the loop.

The part that trips people up is where the concurrency comes from. It does not come from `await`. `await worker()` runs `worker` inside the current task, like the chain in the last section, and the next line waits for it. To run things at the same time, each one needs its own task. `asyncio.gather` takes several awaitables, wraps each coroutine in a task, and finishes when all of them have finished.

```python
import asyncio

async def worker(name, steps):
    for i in range(1, steps + 1):
        print(f"{name} step {i}")
        await asyncio.sleep(0)         # give the turn back
    return f"{name} finished"

async def main():
    print("awaited one by one:")
    await worker("A", 2)
    await worker("B", 2)
    print("gathered:")
    results = await asyncio.gather(worker("A", 3), worker("B", 1), worker("C", 2))
    print(results)

asyncio.run(main())
```

```text
awaited one by one:
A step 1
A step 2
B step 1
B step 2
gathered:
A step 1
B step 1
C step 1
A step 2
C step 2
A step 3
['A finished', 'B finished', 'C finished']
```

The first half shows that `await` alone is sequential. `A` gives its turn back after every step, but no other task exists, so the loop hands the turn straight back, and `B` cannot start until `A` has returned. In the second half the steps come out in the same order as they did from the twenty-line scheduler: A, B, C, then A and C, then A. The last line shows one more detail. `gather` returns results in the order of its arguments, not the order of finishing, so `B finished` sits second in the list although `B` finished first.

What asyncio adds to the toy is what makes it fit for real work:

- **Input and output.** The loop waits on the operating system for network data as well as for timers.
- **Cancellation and timeouts.** A paused task can be cancelled. The loop uses `throw`, the third generator method, to raise an exception inside the coroutine at the `await` where it is paused.
- **Errors.** An exception travels up through a chain of awaits as it does through function calls, and `gather` and task groups decide what happens to the other tasks.
- **Coordination.** Locks, queues, semaphores and events are all built on futures.

The [Concurrency and async course](/learn/async/) has a lesson on each of these.

## What blocks the loop

The loop runs on one thread and switches only when the running task pauses. So everything depends on each task reaching its next pause quickly. A task that computes for a long time, or calls a function that waits without `await`, holds the thread, and the loop lives on that thread too. Timers are not checked, replies are not read, and no other task moves.

```python
import asyncio

def busy(n):
    total = 0
    for i in range(n):                 # plain Python, no await inside
        total += i * i
    return total

async def heartbeat():
    for i in range(1, 4):
        print(f"  beat {i}")
        await asyncio.sleep(0)

async def one_piece():
    busy(100_000)                      # nothing else can run meanwhile
    print("  one_piece done")

async def four_pieces():
    for _ in range(4):
        busy(25_000)                   # the same work in total
        await asyncio.sleep(0)         # with a gap after each piece
    print("  four_pieces done")

async def main():
    print("one piece:")
    await asyncio.gather(one_piece(), heartbeat())
    print("four pieces:")
    await asyncio.gather(four_pieces(), heartbeat())

asyncio.run(main())
```

```text
one piece:
  one_piece done
  beat 1
  beat 2
  beat 3
four pieces:
  beat 1
  beat 2
  beat 3
  four_pieces done
```

In the first run the heartbeat could not print a single line until `one_piece` had finished its loop. `gather` started `one_piece` first, and there was no pause inside it at which to switch. In the second run the same number of loop iterations is cut into four pieces with `await asyncio.sleep(0)` between them, and the heartbeat gets a turn in every gap.

![A circular track with one large yellow block sitting on it and a row of small blue beads bunched up closely behind the block, on a dark navy background.](/blog/asyncio-from-the-inside/blocked-loop.webp "A task that does not give way holds up every task behind it, however little the others need to do.")

The usual causes are few:

- **A long calculation.** Parsing a large file, resizing an image, a loop over a million rows.
- **A blocking sleep.** `time.sleep` puts the whole thread to sleep, loop included. In a coroutine it is always a mistake. `await asyncio.sleep(1)` pauses only the task.
- **A blocking library.** A database driver or HTTP client that was not written for asyncio waits inside an ordinary function call. One such call in a coroutine stalls every task for as long as the server takes to answer.

There are four remedies, in the order to try them:

1. Use the awaiting version where one exists: `asyncio.sleep`, an async HTTP client, an async database driver.
2. Hand a blocking call to a worker thread with `asyncio.to_thread`. The loop stays free, and the coroutine resumes when the thread has the answer.
3. Send heavy computation to another process through a process pool and `loop.run_in_executor`.
4. If a long loop has to stay on the loop's thread, cut it into pieces as `four_pieces` does. That keeps the other tasks responsive. It does not make the work any faster.

The second and third look like this inside a coroutine. They need real threads and processes, so run them with Python on a computer.

```text
# a blocking call, moved to a worker thread
text = await asyncio.to_thread(path.read_text)

# heavy computation, moved to another process
loop = asyncio.get_running_loop()
with concurrent.futures.ProcessPoolExecutor() as pool:
    total = await loop.run_in_executor(pool, busy, 50_000_000)
```

To find a blocking call that you cannot see, start the program with `asyncio.run(main(), debug=True)`. In debug mode asyncio logs a warning whenever a single step holds the loop for more than 100 milliseconds, and the warning names the task.

## When threads or processes are the better tool

asyncio is one of three tools, and the choice follows from what the program spends its time on.

**Use asyncio when the program waits on many things at once and its libraries are written for async.** A server holding thousands of open connections, a client making hundreds of requests, a crawler, a chat bot. A paused coroutine is a small object, so ten thousand of them are no burden. Switches happen only at an `await`, so shared data is far easier to reason about than with threads. One caution: across an `await` other tasks do run, so a value read before it may be out of date after it.

**Use threads when the waiting happens inside blocking code you cannot change**, or when there are only a handful of things to wait for. A thread pool around an ordinary function is less to learn than converting a program to async, and it works with any library. The price is that a switch can come between any two instructions, so data shared between threads needs locks.

**Use processes when the time goes on computing in Python.** In the standard build of CPython, a global lock lets only one thread run Python code at a time. Threads take turns at a calculation instead of spreading it over several cores, and asyncio has only the one thread to begin with. Separate processes each have their own interpreter and can use every core. The price is start-up time, and the cost of copying arguments and results between processes. CPython also has a free-threaded build without that lock, but it is not the default.

The three combine well. A common shape for a real service is an event loop for the network, `asyncio.to_thread` for the odd blocking call, and a process pool for heavy computation.

A wrong choice shows in recognisable ways. Async code that calls blocking functions is slower than the plain version and harder to read. And async gains nothing for a script that does one thing at a time: three awaits in a row take as long as three ordinary calls, as the first half of the `gather` example showed.

## Where to go next

The best next step is to change the programs above and predict the output before you run them. Three experiments are worth the time:

- Remove `await asyncio.sleep(0)` from `worker` in the `gather` example. Each task now runs to its end before the next one starts.
- Spawn `fast` before `slow` in the clock loop, and work out which lines swap at `t=3`.
- Give `total` a third `await double(...)` and drive it by hand. It needs one more `send`.

You can paste any of the programs into the [playground](/playground/) and run it there. In a browser, Python runs inside the browser's own event loop, so the two programs that call `asyncio.run` need a browser with WebAssembly stack switching, such as Chrome or Edge. The other five run anywhere.

From here, the Pythilo courses cover the same ground with exercises. [Concurrency and async](/learn/async/) starts with threads, pools and locks, then goes through `async` and `await`, tasks and `gather`, timeouts and cancellation, task groups, semaphores and `to_thread`. [Python: ownership and concurrency](/learn/python-runtime/) takes on the harder cases, such as cancelling a task you own and draining a queue before shutdown. The lessons run free in the browser, and the Pythilo app runs them on iPhone and iPad offline. For a real case of the threads option, [How real Python runs on an iPhone](/blog/how-python-runs-on-an-iphone/) describes four programs sharing one interpreter.
