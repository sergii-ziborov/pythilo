---
title: "Gradient descent, momentum and Adam, one step at a time"
description: "Three optimisers in plain Python on a parabola and a narrow bowl, every step printed: learning rates that crawl or diverge, momentum's overshoot and Adam's bias correction as numbers you can check."
date: 2026-11-10
author: Pythilo
cover: /blog/gradient-descent-momentum-adam/cover.jpg
coverAlt: "Abstract illustration: thin concentric rings form a shallow bowl on a dark navy background, and a trail of yellow dots steps down from the rim to a glowing yellow ball resting at the lowest point."
tags: Optimization, Machine learning, Neural networks, Python
---

Training a neural network is one loop repeated many times: measure how wrong the model is, work out which way each of its numbers should move to make it less wrong, move them a little, and measure again. The part that decides how far to move is the optimiser. Its main setting, the learning rate, separates a model that learns in minutes from one that crawls and one whose loss runs off to infinity.

This post builds the three optimisers you are most likely to meet, plain gradient descent, gradient descent with momentum, and Adam, in a few lines of plain Python each. They run on two functions small enough to follow with a calculator: a parabola, and a bowl that is much steeper in one direction than the other. Every step is printed, so each claim below is a number you can check. The code uses only the standard library, and every block runs on its own.

Along the way you will see a learning rate that is too small, one that works and one that diverges. You will watch gradient descent zigzag across a narrow valley, work through Adam's first update with its bias correction, and count the steps each method needs to reach the same target. Not every result follows the textbook picture. On the first bowl, the usual momentum setting of 0.9 turns out slower than well-tuned plain gradient descent, and the numbers show why.

## A gradient says which way is uphill

Take the function `f(x) = x * x`. Its lowest point is at `x = 0`, but pretend that is unknown, and that all we can do is evaluate things at the point where we stand. In training, `f` is the loss and `x` is one of the model's weights.

The slope of `f` at a point says how fast `f` changes when `x` moves a little. For this function the slope is `2 * x`. At `x = 3` the slope is 6: nudge `x` up by 0.001 and `f` rises by about 0.006. A positive slope means uphill is to the right, so downhill is to the left. A negative slope means the opposite. Either way, moving **against** the slope goes down.

With more than one input there is one slope per input, each measured while the others are held still. The list of those slopes is the gradient. It points in the direction in which the function rises fastest, so the opposite direction is the fastest way down from where you stand.

A slope can be checked without any calculus: evaluate the function a little to each side of the point and divide the difference by the distance. The next block does that, then takes one step each way from `x = 3`.

```python
def f(x):
    return x * x

def slope(x):
    return 2 * x

h = 1e-6
for x in (3.0, 0.5, -2.0):
    measured = (f(x + h) - f(x - h)) / (2 * h)
    print(f"x = {x:4.1f}   formula {slope(x):5.1f}   measured {measured:9.6f}")

x, lr = 3.0, 0.1
against = x - lr * slope(x)
along = x + lr * slope(x)
print()
print(f"start at x = {x:.1f}          f = {f(x):.2f}")
print(f"step against, x = {against:.1f}    f = {f(against):.2f}")
print(f"step along,   x = {along:.1f}    f = {f(along):.2f}")
```

```text
x =  3.0   formula   6.0   measured  6.000000
x =  0.5   formula   1.0   measured  1.000000
x = -2.0   formula  -4.0   measured -4.000000

start at x = 3.0          f = 9.00
step against, x = 2.4    f = 5.76
step along,   x = 3.6    f = 12.96
```

The measured slopes match the formula. Stepping against the slope takes `f` from 9 down to 5.76. Stepping along it takes `f` up to 12.96. The whole method is one line:

```text
x = x - lr * slope(x)
```

Here `lr` is the learning rate, the fraction of the slope used as a step. Repeating that line is gradient descent.

Measuring a slope from both sides is also the standard test for a gradient you have derived by hand, and the [Numerical Gradient Check Lab](/labs/gradientcheck/) is built around it. In a neural network the slopes come from backpropagation, which [another post](/blog/backpropagation-by-hand/) works through by hand. Here the functions are simple enough to differentiate at sight.

## The learning rate on a parabola

On the parabola the update can be simplified. The slope is `2 * x`, so one step turns `x` into `x - lr * 2 * x`, which is `(1 - 2 * lr) * x`. Every step multiplies `x` by the same factor, and the whole behaviour of the run is in that one number.

```python
def slope(x):
    return 2 * x

def descend(lr, steps, x=5.0):
    path = [x]
    for _ in range(steps):
        x = x - lr * slope(x)
        path.append(x)
    return path

for lr in (0.01, 0.3, 1.1):
    print(f"lr = {lr}")
    print("  " + " ".join(f"{x:8.4f}" for x in descend(lr, 7)))

print()
for lr in (0.01, 0.1, 0.3, 0.5, 0.9, 1.0, 1.1):
    x = descend(lr, 20)[-1]
    print(f"lr = {lr:<4}  factor {1 - 2 * lr:5.2f}   x after 20 steps: {x:.3g}")
```

```text
lr = 0.01
    5.0000   4.9000   4.8020   4.7060   4.6118   4.5196   4.4292   4.3406
lr = 0.3
    5.0000   2.0000   0.8000   0.3200   0.1280   0.0512   0.0205   0.0082
lr = 1.1
    5.0000  -6.0000   7.2000  -8.6400  10.3680 -12.4416  14.9299 -17.9159

lr = 0.01  factor  0.98   x after 20 steps: 3.34
lr = 0.1   factor  0.80   x after 20 steps: 0.0576
lr = 0.3   factor  0.40   x after 20 steps: 5.5e-08
lr = 0.5   factor  0.00   x after 20 steps: 0
lr = 0.9   factor -0.80   x after 20 steps: 0.0576
lr = 1.0   factor -1.00   x after 20 steps: 5
lr = 1.1   factor -1.20   x after 20 steps: 192
```

With `lr = 0.01` the factor is 0.98, so each step removes 2% of the distance. After seven steps `x` has moved from 5 to 4.34, and after twenty it is still at 3.34. Nothing is wrong except the time it takes.

With `lr = 0.3` the factor is 0.4. Seven steps bring `x` to 0.0082, and twenty bring it to 0.000000055.

With `lr = 1.1` the factor is -1.2. Each step jumps over the minimum and lands farther away on the other side: 5, -6, 7.2, -8.64. After twenty steps `x` is at 192. Every one of those steps was in the downhill direction. It was just too long.

The second table fills in the cases between:

- A factor between 0 and 1, which means `lr` below 0.5, approaches the minimum from one side.
- A factor of exactly 0, at `lr = 0.5`, lands on the minimum in one step. That is a property of a perfect parabola, not something to expect elsewhere.
- A factor between -1 and 0, with `lr` between 0.5 and 1, overshoots every time but still closes in, alternating sides. `lr = 0.9` ends at the same 0.0576 as `lr = 0.1`.
- A factor of exactly -1, at `lr = 1.0`, bounces between 5 and -5 for ever.
- Beyond that the run diverges.

Two things here carry over to every later experiment. The first is that the limit depends on the function. The factor was `1 - 2 * lr` because the slope was `2 * x`. For a steeper parabola such as `25 * y * y`, with slope `50 * y`, the factor is `1 - 50 * lr`, and the run diverges above `lr = 0.04` instead of 1.0. The steeper the function, the smaller the largest safe learning rate. The second is that the two kinds of mistake are not equal. A learning rate that is too small costs time. One that is too large loses the run.

![A smooth blue curve shaped like a wide valley on a dark navy background. On the left slope a cloud of tiny pale dots creeps downwards, at the bottom a few evenly spaced yellow dots settle, and on the right slope a yellow staircase of linked dots climbs up and away.](/blog/gradient-descent-momentum-adam/learning-rate.webp "Three behaviours on one curve: many tiny steps that barely move, a few steps that settle at the bottom, and steps that climb away. An illustration, not a plot of the runs above.")

## A narrow valley

Now give the function two inputs with different steepness:

```text
f(x, y) = x*x + 25*y*y
```

This is a bowl with its minimum at (0, 0). Its contour lines are ellipses five times longer in `x` than in `y`, so from above it looks like a long, narrow valley. The gradient is the pair `(2 * x, 50 * y)`.

Start at (10, 1). The minimum is ten units away in `x` and only one in `y`, so it lies almost straight along the valley. The gradient at that point is (20, 50), and the downhill direction, (-20, -50), points mostly along `y`: across the valley towards its floor, not along it towards the minimum. Downhill and "towards the minimum" are different directions.

Each coordinate now has its own factor. A step multiplies `x` by `1 - 2 * lr` and `y` by `1 - 50 * lr`. One learning rate has to serve both.

```python
def f(x, y):
    return x * x + 25 * y * y

def grad(x, y):
    return 2 * x, 50 * y

x, y, h = 10.0, 1.0, 1e-6
print("formula :", grad(x, y))
print("measured:", (round((f(x + h, y) - f(x - h, y)) / (2 * h), 4),
                    round((f(x, y + h) - f(x, y - h)) / (2 * h), 4)))

lr = 0.035
print()
print("step       x        y       loss")
print(f"{0:4d} {x:8.4f} {y:8.4f} {f(x, y):10.4f}")
for step in range(1, 9):
    gx, gy = grad(x, y)
    x, y = x - lr * gx, y - lr * gy
    print(f"{step:4d} {x:8.4f} {y:8.4f} {f(x, y):10.4f}")

def steps_needed(lr, tol=1e-6, limit=5000):
    x, y = 10.0, 1.0
    for step in range(1, limit + 1):
        gx, gy = grad(x, y)
        x, y = x - lr * gx, y - lr * gy
        if f(x, y) < tol:
            return step
        if f(x, y) > 1e9:
            return "diverged"
    return f"not reached in {limit}"

print()
for lr in (0.005, 0.01, 0.02, 0.035, 0.038, 0.04, 0.041):
    print(f"lr = {lr:<5}  steps until loss < 0.000001: {steps_needed(lr)}")
```

```text
formula : (20.0, 50.0)
measured: (20.0, 50.0)

step       x        y       loss
   0  10.0000   1.0000   125.0000
   1   9.3000  -0.7500   100.5525
   2   8.6490   0.5625    82.7154
   3   8.0436  -0.4219    69.1485
   4   7.4805   0.3164    58.4610
   5   6.9569  -0.2373    49.8061
   6   6.4699   0.1780    42.6515
   7   6.0170  -0.1335    36.6498
   8   5.5958   0.1001    31.5637

lr = 0.005  steps until loss < 0.000001: 917
lr = 0.01   steps until loss < 0.000001: 456
lr = 0.02   steps until loss < 0.000001: 226
lr = 0.035  steps until loss < 0.000001: 127
lr = 0.038  steps until loss < 0.000001: 117
lr = 0.04   steps until loss < 0.000001: not reached in 5000
lr = 0.041  steps until loss < 0.000001: diverged
```

With `lr = 0.035` the factor for `y` is -0.75. Its sign flips on every step, 1, -0.75, 0.5625, so the point jumps from one side of the valley to the other. That is the zigzag. The factor for `x` is 0.93, so `x` loses 7% per step. After eight steps `y` is down to a tenth of its starting value, while `x` has covered less than half of its distance.

The second table counts steps until the loss is below one millionth. Small learning rates behave as they did on the parabola: halving the rate doubles the count, from 226 to 456 to 917. The count is lowest, 117, at 0.038, just under the limit. At 0.04 the factor for `y` is exactly -1, so `y` swaps between 1 and -1 for ever and the loss never gets below 25. At 0.041 the run diverges.

Look at `lr = 0.02`. There the factor for `y` is `1 - 50 * 0.02`, which is 0, so `y` is solved in a single step. The run still takes 226 steps, every one of them spent on `x`. That is the problem of a narrow valley in one line: the steep direction decides how large the learning rate may be, and the shallow direction then decides how long the run takes. A real network has a great many weights, its loss is far steeper along some directions than others, and plain gradient descent gives them all the same learning rate.

![Elongated concentric blue rings around a bright centre on a dark navy background. A yellow line zigzags sharply in from the left edge, its swings shrinking as it nears the centre, while a pale smooth curve glides to the same point without bouncing.](/blog/gradient-descent-momentum-adam/narrow-valley.webp "Two ways into the same valley: one path bounces from wall to wall, the other follows the floor. An illustration of the behaviour, not a trace of the printed numbers.")

## Momentum: keep a running velocity

Momentum changes one thing. Instead of stepping along the current gradient, it keeps a velocity, a decaying sum of all the gradients so far, and steps along that:

```text
v = beta * v + g
x = x - lr * v
```

`beta` says how much of the old velocity survives each step. A common value is 0.9, and `beta = 0` is plain gradient descent again. This is the form PyTorch's `SGD` uses when it is given `momentum=0.9`.

The sum behaves differently depending on whether the gradients agree. The block below first feeds the velocity thirty identical gradients, then thirty that alternate in sign. After that it runs the bowl with three values of `beta`.

```python
from itertools import islice

def f(x, y):
    return x * x + 25 * y * y

def grad(x, y):
    return 2 * x, 50 * y

def velocity_after(gradients, beta=0.9):
    v = 0.0
    for g in gradients:
        v = beta * v + g
    return v

same = [1.0] * 30
flipping = [(-1.0) ** i for i in range(30)]
print("after 30 gradients of +1:          v =", round(velocity_after(same), 3))
print("after 30 gradients of +1, -1, ...: v =", round(velocity_after(flipping), 3))

def momentum(lr, beta, x=10.0, y=1.0):
    vx = vy = 0.0
    while True:
        gx, gy = grad(x, y)
        vx, vy = beta * vx + gx, beta * vy + gy
        x, y = x - lr * vx, y - lr * vy
        yield x, y

print()
print("first 8 steps with lr = 0.035")
for beta in (0.0, 0.5, 0.9):
    path = list(islice(momentum(0.035, beta), 8))
    print(f"beta = {beta}")
    print("  x " + " ".join(f"{x:7.3f}" for x, _ in path))
    print("  y " + " ".join(f"{y:7.3f}" for _, y in path))

def steps_needed(lr, beta, tol=1e-6, limit=5000):
    for step, (x, y) in enumerate(momentum(lr, beta), start=1):
        if f(x, y) < tol:
            return step
        if step == limit:
            return f"over {limit}"

print()
print("steps until loss < 0.000001")
for lr in (0.01, 0.035):
    counts = "   ".join(f"beta {beta}: {steps_needed(lr, beta):>3}" for beta in (0.0, 0.5, 0.9))
    print(f"  lr = {lr:<5}  {counts}")
```

```text
after 30 gradients of +1:          v = 9.576
after 30 gradients of +1, -1, ...: v = -0.504

first 8 steps with lr = 0.035
beta = 0.0
  x   9.300   8.649   8.044   7.481   6.957   6.470   6.017   5.596
  y  -0.750   0.563  -0.422   0.316  -0.237   0.178  -0.133   0.100
beta = 0.5
  x   9.300   8.299   7.218   6.172   5.217   4.374   3.646   3.027
  y  -0.750  -0.312   0.453   0.043  -0.237   0.038   0.109  -0.046
beta = 0.9
  x   9.300   8.019   6.305   4.321   2.232   0.197  -1.649  -3.195
  y  -0.750  -1.012   0.523   0.990  -0.322  -0.939   0.149   0.868

steps until loss < 0.000001
  lr = 0.01   beta 0.0: 456   beta 0.5: 217   beta 0.9: 154
  lr = 0.035  beta 0.0: 127   beta 0.5:  49   beta 0.9: 148
```

Gradients that agree pile up. The velocity heads for ten times a single gradient, which is `1 / (1 - beta)`, and has reached 9.576 after thirty steps. Gradients that alternate cancel, and the velocity stays near half of one gradient. In the valley, the gradient along the floor keeps its sign while the gradient across it keeps flipping. So momentum lengthens the steps along the floor and holds back the steps across it, without being told which direction is which.

The three paths show how much of that is wanted. `beta = 0.0` repeats the plain run. With `beta = 0.5`, `x` is at 3.03 after eight steps instead of 5.60, and the swings in `y` have shrunk to 0.046 instead of 0.100. Both directions are better off. With `beta = 0.9`, `x` crosses the valley in six steps, reaching 0.197, and then cannot stop. It carries on to -3.2, because the velocity loses only a tenth of itself per step. Meanwhile `y` swings almost as widely at step eight, 0.868, as it did at the start.

The step counts say the same. At `lr = 0.035`, a moderate `beta` of 0.5 cuts the count from 127 to 49, and 0.9 raises it to 148. At the cautious `lr = 0.01`, where plain gradient descent needs 456 steps, `beta = 0.9` is the best of the three at 154.

Two numbers summarise this. Along a steady slope the step grows towards `lr / (1 - beta)`, ten times the plain step at 0.9 and twice at 0.5. That is where the speed comes from. And the velocity remembers roughly the last `1 / (1 - beta)` steps, ten at 0.9 and two at 0.5. That is how long it takes to brake. A long memory is worth having on a long, straight floor. On this bowl the floor is only ten units long, and at 0.9 most of the run is spent waiting for the swinging to stop.

## Adam: two running averages

Momentum still uses one learning rate for every coordinate. Adam gives each coordinate its own step size, by dividing by a running measure of how large that coordinate's gradients have been. It keeps two running averages per parameter:

- `m`, the average of recent gradients. This is momentum again, kept as an average instead of a sum.
- `v`, the average of recent squared gradients. Its square root is the typical size of the gradient.

The step is the learning rate times `m`, divided by the square root of `v`. The block below writes that out for a single number, then applies it to each coordinate of the bowl separately. That is all Adam does with a longer list of parameters: every one is updated on its own. The settings 0.9, 0.999 and `1e-8` are the usual defaults.

```python
import math

def adam_update(g, m, v, t, lr=0.1, b1=0.9, b2=0.999, eps=1e-8):
    m = b1 * m + (1 - b1) * g        # running average of the gradient
    v = b2 * v + (1 - b2) * g * g    # running average of its square
    m_hat = m / (1 - b1 ** t)        # bias correction
    v_hat = v / (1 - b2 ** t)
    step = lr * m_hat / (math.sqrt(v_hat) + eps)
    return m, v, m_hat, v_hat, step

m, v, m_hat, v_hat, step = adam_update(50.0, 0.0, 0.0, 1)
print(f"first update, g = 50:  m = {m:.3f}   v = {v:.3f}")
print(f"  corrected:    m_hat = {m_hat:.3f}   v_hat = {v_hat:.3f}   step = {step:.6f}")
print(f"  uncorrected:  lr * m / sqrt(v) = {0.1 * m / math.sqrt(v):.6f}")

print()
for g in (0.05, 20.0, 50.0, 50000.0):
    print(f"first step when g = {g:>8}: {adam_update(g, 0.0, 0.0, 1)[4]:.6f}")

print()
print("y coordinate of the bowl, gradient 50 * y")
print("   t       g        m        v    m_hat     v_hat    step        y")
y, m, v = 1.0, 0.0, 0.0
for t in range(1, 21):
    g = 50 * y
    m, v, m_hat, v_hat, step = adam_update(g, m, v, t)
    y -= step
    if t <= 5 or t in (11, 20):
        print(f"{t:4d} {g:7.3f} {m:8.3f} {v:8.3f} {m_hat:8.3f} {v_hat:9.3f} {step:7.4f} {y:8.4f}")

print()
print("x coordinate of the bowl, gradient 2 * x")
x, m, v = 10.0, 0.0, 0.0
for t in range(1, 301):
    m, v, m_hat, v_hat, step = adam_update(2 * x, m, v, t)
    x -= step
    if t in (1, 50, 100, 150, 200, 300):
        print(f"  t = {t:3d}   step = {step:.4f}   x = {x:.4f}")
```

```text
first update, g = 50:  m = 5.000   v = 2.500
  corrected:    m_hat = 50.000   v_hat = 2500.000   step = 0.100000
  uncorrected:  lr * m / sqrt(v) = 0.316228

first step when g =     0.05: 0.100000
first step when g =     20.0: 0.100000
first step when g =     50.0: 0.100000
first step when g =  50000.0: 0.100000

y coordinate of the bowl, gradient 50 * y
   t       g        m        v    m_hat     v_hat    step        y
   1  50.000    5.000    2.500   50.000  2500.000  0.1000   0.9000
   2  45.000    9.000    4.523   47.368  2262.381  0.0996   0.8004
   3  40.021   12.102    6.120   44.657  2041.917  0.0988   0.7016
   4  35.079   14.400    7.344   41.872  1838.773  0.0976   0.6039
   5  30.197   15.980    8.249   39.021  1653.018  0.0960   0.5080
  11   3.812   14.559    9.742   21.217   890.052  0.0711   0.0051
  20 -13.654   -0.391   10.527   -0.445   531.346 -0.0019  -0.2712

x coordinate of the bowl, gradient 2 * x
  t =   1   step = 0.1000   x = 9.9000
  t =  50   step = 0.0800   x = 5.3682
  t = 100   step = 0.0457   x = 2.2445
  t = 150   step = 0.0188   x = 0.7008
  t = 200   step = 0.0054   x = 0.1557
  t = 300   step = 0.0001   x = 0.0018
```

Start with the first update. The gradient is 50. Both averages start at zero, and each update lets in only a fraction of the new value: a tenth for `m`, a thousandth for `v`. So after one step `m` is 5 and `v` is 2.5, when the only gradient ever seen was 50 and its square was 2,500. The averages are biased towards the zero they started from.

Bias correction undoes that. It divides `m` by `1 - b1 ** t` and `v` by `1 - b2 ** t`, where `t` counts updates from 1. At `t = 1` those are 0.1 and 0.001, exactly the fractions that were let in, so `m_hat` is 50 and `v_hat` is 2,500. The step is `0.1 * 50 / 50`, which is 0.1. Without the correction it would have been `0.1 * 5 / sqrt(2.5)`, or 0.316: more than three times the learning rate, for no better reason than where the averages started. As `t` grows, `b1 ** t` and `b2 ** t` shrink towards zero and the correction fades away. By the second update the divisors are already 0.19 and 0.001999.

The next four lines show what that first step means. Whether the gradient is 0.05 or 50,000, the first step is 0.1, because `m_hat / sqrt(v_hat)` is the gradient divided by its own size, which is plus or minus one. Plain gradient descent would take a step a million times longer for the largest of those gradients than for the smallest. Adam's first step is the learning rate, against the gradient, and nothing else.

The table for `y` shows that this stays roughly true for a while. The steps are 0.1000, 0.0996, 0.0988, 0.0976, 0.0960. While the gradient keeps its sign and changes slowly, `m_hat` and the square root of `v_hat` are both about the size of the recent gradient, and their ratio stays near one. So early in a run every parameter moves by about the learning rate per step. On the bowl, `x` with its gradient of 20 and `y` with its gradient of 50 both move by 0.1 on the first step. For Adam the valley is not narrow at the start.

Two more rows complete the picture. At `t = 11` the gradient has fallen to 3.8, but `m` still holds the larger gradients before it, so the step is 0.0711 and `y` is carried through the minimum, to -0.27 by step 20. Adam has momentum inside it, and it overshoots as momentum does.

The table for `x` shows the opposite effect near the end. The learning rate never changes, yet the step shrinks from 0.1 to 0.0457 at step 100 and 0.0054 at step 200. As `x` nears the minimum its gradient shrinks. `m_hat` follows within a few tens of steps, but `v_hat`, with `b2 = 0.999`, averages over about a thousand steps and still remembers the large early gradients. The ratio falls, and Adam slows down as it arrives.

The last setting, `eps`, only keeps the division safe when `v_hat` is zero.

## Side by side

For a comparison, all three are written as functions with the same arguments, and `steps_needed` counts steps from (10, 1) until the loss first drops below one millionth. Momentum uses `beta = 0.9`.

```python
import math

def plain(p, g, state, t, lr):
    return [pi - lr * gi for pi, gi in zip(p, g)]

def momentum(p, g, state, t, lr, beta=0.9):
    v = state.setdefault("v", [0.0] * len(p))
    for i, gi in enumerate(g):
        v[i] = beta * v[i] + gi
    return [pi - lr * vi for pi, vi in zip(p, v)]

def adam(p, g, state, t, lr, b1=0.9, b2=0.999, eps=1e-8):
    m = state.setdefault("m", [0.0] * len(p))
    v = state.setdefault("v", [0.0] * len(p))
    new = []
    for i, gi in enumerate(g):
        m[i] = b1 * m[i] + (1 - b1) * gi
        v[i] = b2 * v[i] + (1 - b2) * gi * gi
        m_hat = m[i] / (1 - b1 ** t)
        v_hat = v[i] / (1 - b2 ** t)
        new.append(p[i] - lr * m_hat / (math.sqrt(v_hat) + eps))
    return new

def steps_needed(optimiser, lr, c=25, tol=1e-6, limit=5000):
    p, state = [10.0, 1.0], {}
    for t in range(1, limit + 1):
        g = [2 * p[0], 2 * c * p[1]]
        p = optimiser(p, g, state, t, lr)
        loss = p[0] * p[0] + c * p[1] * p[1]
        if loss < tol:
            return t
        if loss > 1e9:
            return "diverged"
    return f"over {limit}"

print("steps until loss < 0.000001 on x*x + 25*y*y")
print("     lr      plain   momentum       Adam")
for lr in (0.003, 0.01, 0.03, 0.1, 0.3, 1.0):
    row = [steps_needed(optimiser, lr) for optimiser in (plain, momentum, adam)]
    print(f"{lr:7}" + "".join(f"{str(n):>11}" for n in row))

rows = [
    ("plain, lr 0.038", plain, lambda c: 0.038),
    ("momentum, lr 0.038", momentum, lambda c: 0.038),
    ("plain, lr 0.95 / c", plain, lambda c: 0.95 / c),
    ("momentum, lr 0.95 / c", momentum, lambda c: 0.95 / c),
    ("Adam, lr 0.3", adam, lambda c: 0.3),
]
bowls = (25, 100, 400)
print()
print("the same count on narrower bowls, x*x + c*y*y")
print(" " * 22 + "".join(f"{'c = ' + str(c):>10}" for c in bowls))
for name, optimiser, lr in rows:
    counts = [steps_needed(optimiser, lr(c), c) for c in bowls]
    print(f"{name:22}" + "".join(f"{str(n):>10}" for n in counts))
```

```text
steps until loss < 0.000001 on x*x + 25*y*y
     lr      plain   momentum       Adam
  0.003       1531        146  over 5000
   0.01        456        154       3122
   0.03        149        158       1194
    0.1   diverged   diverged        310
    0.3   diverged   diverged        161
    1.0   diverged   diverged        151

the same count on narrower bowls, x*x + c*y*y
                          c = 25   c = 100   c = 400
plain, lr 0.038              117  diverged  diverged
momentum, lr 0.038           163  diverged  diverged
plain, lr 0.95 / c           117       481      1935
momentum, lr 0.95 / c        163       178       189
Adam, lr 0.3                 161       163       164
```

Read the first table down each column.

- **Plain gradient descent** speeds up in proportion to the learning rate, 1,531 steps, then 456, then 149, and then diverges. Its usable range is narrow and its best value sits at the top edge.
- **Momentum** needs about 150 steps across a tenfold range of learning rates. That is the braking time from two sections back: once the point is swinging, the learning rate hardly matters. It also diverges at 0.1.
- **Adam** works at 0.1, 0.3 and 1.0, where the other two diverge, and is slow at the small values where they do well. At 0.003 it has not arrived after 5,000 steps. That follows from its step being about the learning rate: ten units at 0.003 per step is more than 3,300 steps of travel.

The columns do not share a scale. A learning rate that suits one optimiser tells you nothing about another.

The second table changes the bowl. On the original, plain gradient descent tuned to just under its limit is the fastest of the three, at 117 steps. Then the valley is made four and sixteen times narrower. The old learning rate of 0.038 now diverges for plain gradient descent and for momentum, so both are retuned to 95% of the plain limit. That limit is `1 / c`, because `y` is multiplied by `1 - 2 * c * lr`. Retuned, plain gradient descent goes from 117 steps to 481 to 1,935, in step with the narrowness. Momentum goes from 163 to 178 to 189. Adam, with the same learning rate of 0.3 on every bowl, goes from 161 to 163 to 164.

That is the case for momentum and Adam. They are not faster on an easy problem. They are far less sensitive to how badly the problem is shaped, and Adam does not need its learning rate changed when the steepness changes.

One thing a count like this hides: momentum and Adam do not approach the minimum in a straight line, so the first time under the tolerance need not be the last. I let the Adam run with `lr = 0.1` continue past its 310 steps. The loss kept falling for thousands of steps, and then at step 7,069 it was back up at 0.198 before settling again. The division is the cause. After thousands of tiny gradients, `v_hat` has forgotten the large early ones, the same learning rate produces relatively larger steps, and the steep direction overshoots. When I also shrank the learning rate by 0.1% per step, the jump did not appear in 20,000 steps. Those two runs are not printed above.

## Mini-batches make the gradient noisy

Everything so far used the exact gradient. In training, the loss is an average over the whole dataset, and computing its gradient for every step costs too much. So each step uses a mini-batch, a small random sample of the examples. The gradient from a mini-batch is the true gradient plus an error from the luck of the sample, and the smaller the batch, the larger the error.

The bowl has no data, so the next block imitates the effect. Each example reports the true gradient plus its own random error, and a mini-batch averages the reports of its examples. The error of one example has a standard deviation of 20, as large as the true gradient in `x` at the start.

```python
import random

def f(x, y):
    return x * x + 25 * y * y

def noisy_grad(x, y, batch, rng, noise=20.0):
    # each example reports the true gradient plus its own error;
    # a mini-batch averages `batch` of those reports
    ex = sum(rng.gauss(0, noise) for _ in range(batch)) / batch
    ey = sum(rng.gauss(0, noise) for _ in range(batch)) / batch
    return 2 * x + ex, 50 * y + ey

def run(batch, schedule, steps=400, seed=7):
    rng = random.Random(seed)
    x, y, tail = 10.0, 1.0, []
    for step in range(steps):
        gx, gy = noisy_grad(x, y, batch, rng)
        lr = schedule(step)
        x, y = x - lr * gx, y - lr * gy
        if step >= steps - 100:
            tail.append(f(x, y))
    return sum(tail) / len(tail)

print("average loss over the last 100 of 400 steps, lr = 0.02")
for batch in (1, 4, 16, 64):
    print(f"  batch of {batch:2d}: {run(batch, lambda step: 0.02):.4f}")

print()
print("batch of 4, three learning-rate plans")
print(f"  0.02 throughout:        {run(4, lambda step: 0.02):.4f}")
print(f"  0.002 throughout:       {run(4, lambda step: 0.002):.4f}")
print(f"  0.02, then 0.002:       {run(4, lambda step: 0.02 if step < 200 else 0.002):.4f}")
```

```text
average loss over the last 100 of 400 steps, lr = 0.02
  batch of  1: 4.7408
  batch of  4: 1.3119
  batch of 16: 0.3241
  batch of 64: 0.0780

batch of 4, three learning-rate plans
  0.02 throughout:        1.3119
  0.002 throughout:       6.7274
  0.02, then 0.002:       0.3633
```

With noise, the loss no longer falls to zero. The point reaches the bottom of the bowl and is then pushed around it by the errors, so the loss hovers at a floor. The first table shows that the floor depends on the batch: 4.74 for single examples, 1.31 for batches of four, 0.32 for sixteen and 0.078 for sixty-four. Each time the batch is four times larger the floor is about four times lower, because the average of four independent errors has a quarter of the variance.

The learning rate sets the floor as well, since every step adds the learning rate times the error to the position. The second table tries three plans with a batch of four. A rate of 0.02 throughout ends at 1.31. A rate of 0.002 throughout ends at 6.73, which is worse, though not because its floor is higher: at that rate `x` shrinks by only 0.4% per step, and 400 steps are not enough to arrive. Starting at 0.02 and dropping to 0.002 halfway ends at 0.36. The large rate covers the distance and the small one settles closer to the minimum. That is the reason training schedules lower the learning rate as they go.

The exact figures depend on the seed. Over 200 different seeds, the four batch sizes came out in the same order every time, and the two-stage plan beat both constant rates in 197 of them.

![Concentric blue rings around a bright point on a dark navy background. Many small yellow arrows are scattered on one side, each pointing roughly but not exactly towards the centre, and one large yellow arrow among them points straight at it.](/blog/gradient-descent-momentum-adam/noisy-gradient.webp "Each small arrow stands for one noisy estimate of the downhill direction. Averaging a batch of them gives the steadier large arrow.")

## Choosing a learning rate

These are small experiments on tidy functions, and the particular numbers will not transfer to a real model. The habits they suggest do, and each one is backed by a result above.

1. **Search in multiples.** Useful learning rates here ran from 0.003 to 1.0 depending on the optimiser. Try values about three times apart, as the comparison table does, and refine only around the best one.
2. **With plain gradient descent, find where it diverges and back off.** The limit is set by the steepest direction: 1.0 on the parabola, 0.04 on the bowl, 0.0025 on the narrowest bowl. Half of the limit costs about twice the steps of the best value, 226 against 117. A rate 2.5% over the limit costs the run.
3. **Look at the first few steps.** Divergence shows at once: 5, -6, 7.2 on the parabola. If the loss grows step after step, divide the rate by three or by ten. With momentum, allow some wobble. In the `beta = 0.9` run the loss rose from 7.6 to 22.1 between steps five and six on its way down, as you can work out from the printed coordinates.
4. **Treat momentum and learning rate as one setting.** Adding `beta = 0.9` to a rate that was already near the limit made the run slower, 148 steps instead of 127. Adding it to a cautious rate made it three times faster, 154 instead of 456. With momentum on, the count stayed near 150 from 0.003 to 0.03, so the exact rate mattered much less.
5. **For Adam, think in distances.** Its learning rate is roughly how far each parameter moves per step at the start, whatever the gradients are. Compare that with how far the parameters have to travel. Here the start was ten units from the minimum, so 0.1 to 1.0 worked and 0.003 did not. Network weights are usually small numbers that move short distances, which is one reason the usual default for Adam is as small as 0.001.
6. **With mini-batches, plan to lower the rate.** A large rate covers ground and a small one settles. The two-stage plan ended at a loss of 0.36 where the constant rate ended at 1.31. A larger batch lowers the floor too, at the price of more work per step.

## Where to go next

The quickest way to make this stick is to change the numbers. Start the bowl from a different point, make it narrower, try `beta = 0.99`, or give the noisy run a different seed, and predict the result before you run it.

On Pythilo, the [Adam Optimizer Lab](/labs/adam/) asks you to write the update from this post, bias correction included, and the [Mini-batch SGD Lab](/labs/minibatch/) has you write one pass of mini-batch updates over a small dataset. The course [The mathematics of neural networks](/learn/math/) has lessons on derivatives, gradient checking, learning rate and curvature, and momentum and Adam. [Machine learning with PyTorch](/learn/ml/) then uses the same optimisers to train real models. The lessons run free in the browser, and the app runs them on iPhone and iPad, offline.
