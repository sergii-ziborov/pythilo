---
title: "Backpropagation by hand: train a neural network in plain Python"
description: "Build a nine-number network that learns XOR with only lists and math. Work one gradient by hand, check it by measurement, then see what PyTorch's autograd automates."
date: 2026-11-11
author: Pythilo
cover: /blog/backpropagation-by-hand/cover.jpg
coverAlt: "Abstract illustration of a small neural network: two glowing yellow circles on the left, two pale blue circles in the middle and one larger bright blue circle on the right, joined by thin yellow and blue lines on a dark navy background."
tags: Neural networks, Machine learning, Python
---

A neural network is a function with adjustable numbers in it. Training is the search for numbers that make the function give the right answers. The method that drives that search is backpropagation. It works out, for every adjustable number at once, which way to move it and how much that will help.

Frameworks do this for you, which is why many people who train networks have never watched it happen. This post does it in the open. You will build a network with nine adjustable numbers, using only Python lists and the `math` module, and teach it XOR: the output should be 1 when exactly one of two inputs is 1. You will work one gradient out by hand with real numbers, check it by measurement, write the whole backward pass and watch the loss fall.

XOR is a good target because it is one of the smallest problems that a single neuron cannot solve. The same four rows of data show how training works and why networks need a hidden layer. Every code block is a complete program, so you can run each one as you read and change its numbers.

## What a neuron computes

A neuron takes some numbers in and gives one number out. It does three things. It multiplies each input by a **weight**. It adds the results together, along with one extra number called the **bias**. Then it passes that sum through a fixed curve called the **activation function**.

The weights and the bias are the adjustable numbers. The activation function used here is the sigmoid, `1 / (1 + e^-z)`, which squeezes any sum into the range from 0 to 1.

![Three thin blue lines curve in from the left and meet a glowing blue circle. Inside the circle is a yellow S-shaped curve, and a single yellow line leaves the circle to the right.](/blog/backpropagation-by-hand/neuron.webp "A neuron: weighted inputs are added up, the sum is bent through an S-shaped curve, and one number goes out.")

```python
import math

def sigmoid(z):
    return 1 / (1 + math.exp(-z))

inputs = [1.0, 0.0]
weights = [0.5, -0.4]
bias = 0.1

z = sum(w * x for w, x in zip(weights, inputs)) + bias
print("weighted sum z:", round(z, 4))
print("output sigmoid(z):", round(sigmoid(z), 4))

for z in (-6, -2, 0, 2, 6):
    print(f"sigmoid({z:>2}) = {sigmoid(z):.4f}")
```

```text
weighted sum z: 0.6
output sigmoid(z): 0.6457
sigmoid(-6) = 0.0025
sigmoid(-2) = 0.1192
sigmoid( 0) = 0.5000
sigmoid( 2) = 0.8808
sigmoid( 6) = 0.9975
```

With inputs 1 and 0, the sum is `0.5 * 1 + -0.4 * 0 + 0.1 = 0.6`, and the sigmoid turns 0.6 into 0.6457. The last five lines trace the shape of the curve. Large negative sums give outputs near 0, large positive sums give outputs near 1, and a sum of 0 gives exactly 0.5. The curve is steepest in the middle and almost flat at both ends.

The curve is not decoration. Without it a neuron is only a weighted sum, and a stack of weighted sums can always be rewritten as a single weighted sum. The bend is what lets several neurons together do something that one cannot.

## The forward pass, with real numbers

The network has two inputs, two hidden neurons and one output neuron, which people write as 2-2-1. Each hidden neuron reads both inputs, so it has two weights and a bias. The output neuron reads the two hidden outputs, so it also has two weights and a bias. That makes nine numbers, called the **parameters**:

- `w11`, `w12` and `b1` are hidden neuron 1's weights for input 1 and input 2, and its bias.
- `w21`, `w22` and `b2` are the same three for hidden neuron 2.
- `v1`, `v2` and `c` are the output neuron's weights for the two hidden outputs, and its bias.

Running the network from inputs to output is called the **forward pass**. Here it is as one function. The nine starting values are made up, and chosen to be easy to follow by eye.

```python
import math

def sigmoid(z):
    return 1 / (1 + math.exp(-z))

def forward(p, x):
    w11, w12, b1, w21, w22, b2, v1, v2, c = p
    h1 = sigmoid(w11 * x[0] + w12 * x[1] + b1)
    h2 = sigmoid(w21 * x[0] + w22 * x[1] + b2)
    y = sigmoid(v1 * h1 + v2 * h2 + c)
    return h1, h2, y

#    w11   w12   b1   w21  w22   b2    v1    v2    c
p = [0.5, -0.4, 0.1, 0.3, 0.8, -0.2, 0.7, -0.6, 0.05]

h1, h2, y = forward(p, (1, 0))
print(f"h1 = {h1:.4f}")
print(f"h2 = {h2:.4f}")
print(f"y  = {y:.4f}")
print(f"loss for target 1 = {(y - 1) ** 2:.4f}")

data = [((0, 0), 0), ((0, 1), 1), ((1, 0), 1), ((1, 1), 0)]
total = 0.0
for x, target in data:
    y = forward(p, x)[2]
    total += (y - target) ** 2
    print(x, "target", target, f"output {y:.4f}")
print(f"mean loss = {total / 4:.4f}")
```

```text
h1 = 0.6457
h2 = 0.5250
y  = 0.5466
loss for target 1 = 0.2056
(0, 0) target 0 output 0.5368
(0, 1) target 1 output 0.4901
(1, 0) target 1 output 0.5466
(1, 1) target 0 output 0.5021
mean loss = 0.2514
```

You can check the first three lines with a calculator. Hidden neuron 1 is the neuron from the previous section, so `h1` is 0.6457. Hidden neuron 2 computes `0.3 * 1 + 0.8 * 0 - 0.2 = 0.1`, and the sigmoid of 0.1 is 0.5250. The output neuron computes `0.7 * 0.6457 - 0.6 * 0.5250 + 0.05 = 0.1870`, and the sigmoid of that is 0.5466.

The list called `data` holds the four rows of XOR, each as a pair of inputs and a target. An untrained network answers roughly 0.5 to all of them. It has no opinion yet.

## The loss: one number for how wrong

Training needs a single number that says how wrong the network is, so that "better" has a meaning. That number is the **loss**. This post uses the squared error: subtract the target from the output and square the result.

For the input `(1, 0)` the target is 1 and the output is 0.5466, so the loss is `(0.5466 - 1)^2 = 0.2056`. Squaring does two jobs. It makes the loss positive whichever side the error is on, and it punishes a large miss far more than a small one. A perfect answer has a loss of 0.

The loss for the whole data set is the mean over the four rows, which is 0.2514 in the output above. A network that answered exactly 0.5 to every row would score 0.25, so the made-up parameters are slightly worse than knowing nothing. Training means changing the nine parameters so that the mean loss moves towards 0. The work is in finding out which way to change each one.

## The chain rule: what one number does to the loss

Take one parameter, `v1`. The thing to find out is how much the loss changes when `v1` goes up by a tiny amount. That quantity, the change in loss divided by the change in `v1`, is the **gradient** of the loss with respect to `v1`. A gradient of -0.15 means that raising `v1` by 0.01 lowers the loss by about 0.0015. The sign says which way to move the parameter. The size says how much the loss cares.

There are two ways to get the number.

The first is to measure it. Raise `v1` a little and run the forward pass. Lower it a little and run it again. Divide the difference between the two losses by the distance between the two values of `v1`. This is called a **finite difference**. It needs no calculus and it is hard to get wrong.

The second is to calculate it. `v1` does not touch the loss directly. It changes the output neuron's weighted sum, the sum changes `y`, and `y` changes the loss. The **chain rule** says that the effect along a chain like this is the product of the effects of its links. Here there are three:

1. Loss per unit of `y`. The loss is `(y - target)^2`, and its slope is `2 * (y - target)`. With our numbers that is `2 * (0.5466 - 1) = -0.9068`.
2. `y` per unit of the output sum. The slope of the sigmoid has a convenient form, `y * (1 - y)`, which here is `0.5466 * 0.4534 = 0.2478`.
3. Output sum per unit of `v1`. The sum is `v1 * h1 + v2 * h2 + c`, so raising `v1` by one raises the sum by `h1`, which is 0.6457.

Multiply the three: `-0.9068 * 0.2478 * 0.6457 = -0.1451`. That is the gradient for `v1`, worked by hand. It is negative, so raising `v1` lowers the loss. That makes sense: the target is 1, the output is too low, and `v1` multiplies a positive number on its way to the output.

A weight in the hidden layer sits further from the loss, so its chain is longer. For `w11` the first two links are the same. Then come three more. The output sum per unit of `h1` is `v1`, which is 0.7. `h1` per unit of its own weighted sum is `h1 * (1 - h1)`. And that sum per unit of `w11` is the first input, which is 1.

The next block does both calculations for both weights and prints each hand result beside its measurement.

```python
import math

def sigmoid(z):
    return 1 / (1 + math.exp(-z))

def loss(p, x, target):
    w11, w12, b1, w21, w22, b2, v1, v2, c = p
    h1 = sigmoid(w11 * x[0] + w12 * x[1] + b1)
    h2 = sigmoid(w21 * x[0] + w22 * x[1] + b2)
    y = sigmoid(v1 * h1 + v2 * h2 + c)
    return (y - target) ** 2

def measured(p, i, x, target, eps=1e-5):
    up, down = p.copy(), p.copy()
    up[i] += eps
    down[i] -= eps
    return (loss(up, x, target) - loss(down, x, target)) / (2 * eps)

p = [0.5, -0.4, 0.1, 0.3, 0.8, -0.2, 0.7, -0.6, 0.05]
x, target = (1, 0), 1

# The forward pass again, keeping every intermediate number.
h1 = sigmoid(0.5 * 1 + -0.4 * 0 + 0.1)
h2 = sigmoid(0.3 * 1 + 0.8 * 0 - 0.2)
y = sigmoid(0.7 * h1 - 0.6 * h2 + 0.05)

# The chain for v1: loss <- y <- output sum <- v1.
loss_per_y = 2 * (y - target)
y_per_sum = y * (1 - y)
sum_per_v1 = h1
grad_v1 = loss_per_y * y_per_sum * sum_per_v1
print(f"links: {loss_per_y:.4f}  {y_per_sum:.4f}  {sum_per_v1:.4f}")
print(f"v1  by hand  {grad_v1:.8f}")
print(f"v1  measured {measured(p, 6, x, target):.8f}")

# The chain for w11 is two links longer: it goes through h1.
sum_per_h1 = 0.7              # v1
h1_per_z1 = h1 * (1 - h1)
z1_per_w11 = x[0]
grad_w11 = (loss_per_y * y_per_sum * sum_per_h1
            * h1_per_z1 * z1_per_w11)
print(f"w11 by hand  {grad_w11:.8f}")
print(f"w11 measured {measured(p, 0, x, target):.8f}")
```

```text
links: -0.9068  0.2478  0.6457
v1  by hand  -0.14509615
v1  measured -0.14509615
w11 by hand  -0.03598973
w11 measured -0.03598973
```

The hand calculation and the measurement agree in all eight decimal places shown. This comparison is called a **gradient check**, and it is the standard test for a backward pass you have written yourself. If the two numbers disagree in the third decimal place, the derivation has a mistake. The [Numerical Gradient Check](/labs/gradientcheck/) Lab shows what a deliberately wrong derivative looks like under this test.

Compare the sizes as well: -0.036 for `w11` against -0.145 for `v1`. The longer chain made the gradient about a quarter of the size. The slope of a sigmoid is never more than 0.25, so every sigmoid in a chain shrinks the gradient that passes through it.

## The full backward pass

Nine parameters mean nine chains, but the chains share most of their links. All nine begin with the same two factors: loss per unit of `y`, and `y` per unit of the output sum. The three chains for hidden neuron 1's parameters share two more. So there is no need to work each chain out separately. Start at the loss and walk backwards through the network, computing each shared piece once and handing it on. That is backpropagation, and it is where the name comes from.

In the code, each name that starts with `d_` holds the gradient of the loss with respect to one weighted sum: `d_out` for the output neuron's sum, `d_h1` and `d_h2` for the two hidden neurons' sums. The gradient of each parameter is then one of those three numbers, multiplied by whatever the parameter was multiplied by in the forward pass.

```python
import math

def sigmoid(z):
    return 1 / (1 + math.exp(-z))

def forward(p, x):
    w11, w12, b1, w21, w22, b2, v1, v2, c = p
    h1 = sigmoid(w11 * x[0] + w12 * x[1] + b1)
    h2 = sigmoid(w21 * x[0] + w22 * x[1] + b2)
    y = sigmoid(v1 * h1 + v2 * h2 + c)
    return h1, h2, y

def backward(p, x, target):
    w11, w12, b1, w21, w22, b2, v1, v2, c = p
    h1, h2, y = forward(p, x)
    d_out = 2 * (y - target) * y * (1 - y)
    d_h1 = d_out * v1 * h1 * (1 - h1)
    d_h2 = d_out * v2 * h2 * (1 - h2)
    return [d_h1 * x[0], d_h1 * x[1], d_h1,
            d_h2 * x[0], d_h2 * x[1], d_h2,
            d_out * h1, d_out * h2, d_out]

def measured(p, i, x, target, eps=1e-5):
    up, down = p.copy(), p.copy()
    up[i] += eps
    down[i] -= eps
    loss_up = (forward(up, x)[2] - target) ** 2
    loss_down = (forward(down, x)[2] - target) ** 2
    return (loss_up - loss_down) / (2 * eps)

names = ["w11", "w12", "b1", "w21", "w22", "b2", "v1", "v2", "c"]
p = [0.5, -0.4, 0.1, 0.3, 0.8, -0.2, 0.7, -0.6, 0.05]

for name, g in zip(names, backward(p, (1, 0), 1)):
    print(f"{name:>3} {g:+z.6f}")   # z prints -0.0 as 0.0

data = [((0, 0), 0), ((0, 1), 1), ((1, 0), 1), ((1, 1), 0)]
worst = 0.0
for x, target in data:
    grads = backward(p, x, target)
    for i in range(9):
        gap = abs(grads[i] - measured(p, i, x, target))
        worst = max(worst, gap)
print(f"largest gap in 36 checks: {worst:.1e}")
```

```text
w11 -0.035990
w12 +0.000000
 b1 -0.035990
w21 +0.033625
w22 +0.000000
 b2 +0.033625
 v1 -0.145096
 v2 -0.117977
  c -0.224727
largest gap in 36 checks: 6.9e-12
```

The values for `v1` and `w11` match the hand calculation. Three other things in the table are worth reading.

- `w12` and `w22` have a gradient of exactly zero. They multiply the second input, which is 0 in this row, so they had no say in the output and changing them would not change the loss.
- Each bias has the same gradient as the `d_` value of its neuron. A bias behaves like a weight on an input that is always 1.
- `w21` has a positive gradient while `w11` has a negative one. Hidden neuron 2 reaches the output through `v2`, which is negative, so making that neuron more active pushes the output the wrong way for this row.

The last line is the gradient check for all nine parameters on all four rows. The largest disagreement is a few parts in a trillion, which is the rounding error of the measurement itself. The exact digits of that tiny number can differ from one machine to another.

Now compare the cost of the two methods. Measuring one gradient takes two forward passes, so nine parameters take eighteen. `backward` takes one forward pass and a few more lines of arithmetic, and it returns all nine at once. With nine parameters the saving hardly matters. A network with ten million parameters would need twenty million forward passes to measure its gradients once, and still only one forward pass and one backward pass to calculate them. That is the reason large networks can be trained at all. Measurement keeps one job, which is checking the calculation.

## The training loop

A gradient says how the loss responds when its parameter goes up. So move each parameter a small step in the opposite direction, and the loss should go down a little. Then compute new gradients and step again. This is **gradient descent**. With backpropagation supplying the gradients, it is the whole of training.

![Five yellow dots joined by a thin line step down from the upper left towards the bottom of a valley drawn as soft blue contour lines on a dark navy background.](/blog/backpropagation-by-hand/descent.webp "Gradient descent as a picture: each step moves a little further downhill on the loss.")

Each step below runs the backward pass on all four rows, averages the gradients and moves every parameter against its average gradient. The size of the move is set by the **learning rate**. The parameters start as random numbers between -1 and 1, and `random.seed(0)` makes the run repeatable.

```python
import math
import random

def sigmoid(z):
    return 1 / (1 + math.exp(-z))

def forward(p, x):
    w11, w12, b1, w21, w22, b2, v1, v2, c = p
    h1 = sigmoid(w11 * x[0] + w12 * x[1] + b1)
    h2 = sigmoid(w21 * x[0] + w22 * x[1] + b2)
    y = sigmoid(v1 * h1 + v2 * h2 + c)
    return h1, h2, y

def backward(p, x, target):
    w11, w12, b1, w21, w22, b2, v1, v2, c = p
    h1, h2, y = forward(p, x)
    d_out = 2 * (y - target) * y * (1 - y)
    d_h1 = d_out * v1 * h1 * (1 - h1)
    d_h2 = d_out * v2 * h2 * (1 - h2)
    return [d_h1 * x[0], d_h1 * x[1], d_h1,
            d_h2 * x[0], d_h2 * x[1], d_h2,
            d_out * h1, d_out * h2, d_out]

data = [((0, 0), 0), ((0, 1), 1), ((1, 0), 1), ((1, 1), 0)]

def mean_loss(p):
    return sum((forward(p, x)[2] - t) ** 2 for x, t in data) / 4

random.seed(0)
p = [random.uniform(-1, 1) for _ in range(9)]
rate = 1.0

print(f"step    0  loss {mean_loss(p):.4f}")
for step in range(1, 3001):
    total = [0.0] * 9
    for x, target in data:
        grads = backward(p, x, target)
        total = [a + g for a, g in zip(total, grads)]
    p = [w - rate * g / 4 for w, g in zip(p, total)]
    if step % 300 == 0:
        print(f"step {step:>4}  loss {mean_loss(p):.4f}")

print("x1 x2     h1     h2      y  target")
for x, target in data:
    h1, h2, y = forward(p, x)
    print(f" {x[0]}  {x[1]}  {h1:.3f}  {h2:.3f}  {y:.3f}  {target}")
print(f"v1 {p[6]:.2f}  v2 {p[7]:.2f}  c {p[8]:.2f}")
```

```text
step    0  loss 0.2509
step  300  loss 0.2406
step  600  loss 0.1767
step  900  loss 0.0381
step 1200  loss 0.0103
step 1500  loss 0.0054
step 1800  loss 0.0036
step 2100  loss 0.0026
step 2400  loss 0.0021
step 2700  loss 0.0017
step 3000  loss 0.0014
x1 x2     h1     h2      y  target
 0  0  0.070  0.002  0.041  0
 0  1  0.969  0.104  0.964  1
 1  0  0.969  0.104  0.964  1
 1  1  1.000  0.868  0.038  0
v1 8.17  v2 -8.84  c -3.72
```

The loss barely moves for the first 300 steps, falls steeply between steps 300 and 1,200, and then creeps down. That shape is common. At the start the network answers about 0.5 to everything, and the four rows pull the parameters in opposing directions, so their gradients nearly cancel when averaged. Once the hidden neurons begin to respond differently to different rows, the output neuron has something to work with and the loss drops quickly.

After 3,000 steps the four outputs are 0.041, 0.964, 0.964 and 0.038. Rounded, that is 0, 1, 1, 0: the network has learned XOR. The outputs will never be exactly 0 or 1, because a sigmoid approaches those values without reaching them. That is also why the loss keeps shrinking slowly and never arrives at zero.

Two choices in that code deserve a comment.

The learning rate of 1.0 is larger than the values in most tutorials. It works here because the gradients are small: every one of them is a product that includes at least one sigmoid slope. With a rate of 0.1 the same run has barely moved after 3,000 steps, with a loss of 0.2405. Do not carry the number over to other networks. The right rate depends on the size of the gradients, and many networks need a far smaller one.

The random start matters in two ways. If the two hidden neurons started as exact copies of each other, with the same weights going in and the same weight going out, they would receive identical gradients at every step and remain copies for ever. The network would behave as if it had one hidden neuron. Randomness breaks the tie. Randomness also means luck. Change the seed to 2 and the same code stalls: after 3,000 steps the loss is still 0.127, with two of the four rows stuck near 0.5. Of the seeds 0 to 19, four stall in this way. Gradient descent only walks downhill from where it starts, and from some starting points downhill leads somewhere poor. A network this small has few ways to succeed. With a third hidden neuron, all twenty of those seeds learn XOR.

## Why one line cannot solve XOR, and a hidden layer can

A single neuron draws a straight line. Its output is above 0.5 exactly when `w1 * x1 + w2 * x2 + b` is positive, and the points where that sum is zero form a straight line across the plane of inputs. Everything on one side of the line is called 1, and everything on the other side is called 0.

Put the four XOR rows at the corners of a square. The two corners that should be 1, `(0, 1)` and `(1, 0)`, sit diagonally opposite each other, and so do the two that should be 0. No straight line has one diagonal pair on each side. The algebra agrees. To get all four rows right, a single neuron would need:

- `b < 0`, so that `(0, 0)` gives 0
- `w1 + b > 0`, so that `(1, 0)` gives 1
- `w2 + b > 0`, so that `(0, 1)` gives 1
- `w1 + w2 + b < 0`, so that `(1, 1)` gives 0

Add the two middle lines and you get `w1 + w2 + 2b > 0`. Since `b` is negative, taking one `b` away from the left side only makes it larger, so `w1 + w2 + b` is positive too. The last line demands that it be negative. No three numbers satisfy all four conditions, so there is nothing for training to find. The next block trains a single neuron on XOR with the same loop, to show what happens instead.

```python
import math
import random

def sigmoid(z):
    return 1 / (1 + math.exp(-z))

data = [((0, 0), 0), ((0, 1), 1), ((1, 0), 1), ((1, 1), 0)]

random.seed(0)
w1, w2, b = [random.uniform(-1, 1) for _ in range(3)]
rate = 1.0

for step in range(3000):
    g1 = g2 = gb = 0.0
    for (x1, x2), target in data:
        y = sigmoid(w1 * x1 + w2 * x2 + b)
        d = 2 * (y - target) * y * (1 - y)
        g1 += d * x1
        g2 += d * x2
        gb += d
    w1 -= rate * g1 / 4
    w2 -= rate * g2 / 4
    b -= rate * gb / 4

loss = 0.0
for (x1, x2), target in data:
    y = sigmoid(w1 * x1 + w2 * x2 + b)
    loss += (y - target) ** 2 / 4
    print(f"{x1} {x2}  output {y:.3f}  target {target}")
print(f"w1 {w1:z.3f}  w2 {w2:z.3f}  b {b:z.3f}")   # z: no -0.000
print(f"mean loss {loss:.4f}")
```

```text
0 0  output 0.500  target 0
0 1  output 0.500  target 1
1 0  output 0.500  target 1
1 1  output 0.500  target 0
w1 0.000  w2 0.000  b 0.000
mean loss 0.2500
```

Gradient descent drives all three parameters to zero. The neuron answers 0.5 to every row and the loss is 0.25, the score for knowing nothing. With no line that separates the rows, the best it finds is to sit on the fence.

Now look back at the table printed by the training run, at the `h1` and `h2` columns. `h1` is close to 0 for `(0, 0)` and close to 1 for the other three rows. That neuron has learned OR: at least one input is on. `h2` is high only for `(1, 1)`. It has learned something close to AND: both inputs are on. The output neuron has a large positive weight on `h1`, 8.17, and a large negative weight on `h2`, -8.84. So it fires when at least one input is on, but not both. That is XOR, assembled from two simpler questions that single neurons can answer.

Nobody told the network about OR and AND. Gradient descent arrived there because that arrangement lowers the loss. A different seed can find a different arrangement that works just as well.

There is a geometric way to say the same thing. The output neuron never sees the inputs. It sees the pair `(h1, h2)`. In that new space the four rows sit at about `(0.07, 0.00)`, `(0.97, 0.10)`, `(0.97, 0.10)` and `(1.00, 0.87)`. The two rows that should give 1 have landed on the same spot, and one straight line now separates that spot from the other two points. The hidden layer has moved the points until the problem became one that a single neuron can solve.

![On the left, four dots at the corners of a square, yellow at top left and bottom right, blue at top right and bottom left, with a horizontal line between the rows that fails to separate the colours. A curved arrow points to the right, where two yellow dots sit together above a line and two blue dots sit together below it.](/blog/backpropagation-by-hand/xor.webp "The idea in a picture: no single line splits the colours on the left. Once the points have been moved, one line does.")

## What PyTorch automates, and what stays the same

Writing `backward` by hand was manageable for nine parameters. It does not scale. Every change to the shape of the network means deriving the gradients again, and a wrong sign does not crash. It only trains badly. Frameworks such as PyTorch take this job away with automatic differentiation, usually called **autograd**. The idea fits in about forty lines of Python.

Each number becomes an object that remembers which numbers it was made from, and its slope with respect to each of them. Running the forward pass therefore records every link of every chain. Calling `backward()` on the loss walks that record from the loss towards the parameters, multiplying slopes and adding up the results. It is the chain rule, applied mechanically.

```python
import math

class Value:
    def __init__(self, data, parents=(), slopes=()):
        self.data = data
        self.grad = 0.0
        self.parents = parents   # the Values this one was made from
        self.slopes = slopes     # its slope with respect to each

    def __add__(self, other):
        return Value(self.data + other.data, (self, other),
                     (1.0, 1.0))

    def __mul__(self, other):
        return Value(self.data * other.data, (self, other),
                     (other.data, self.data))

    def __sub__(self, other):
        return self + other * Value(-1.0)

    def sigmoid(self):
        s = 1 / (1 + math.exp(-self.data))
        return Value(s, (self,), (s * (1 - s),))

    def backward(self):
        order, seen = [], set()

        def visit(node):
            if node not in seen:
                seen.add(node)
                for parent in node.parents:
                    visit(parent)
                order.append(node)

        visit(self)
        self.grad = 1.0
        for node in reversed(order):
            for parent, slope in zip(node.parents, node.slopes):
                parent.grad += slope * node.grad

names = ["w11", "w12", "b1", "w21", "w22", "b2", "v1", "v2", "c"]
p = [Value(n) for n in
     (0.5, -0.4, 0.1, 0.3, 0.8, -0.2, 0.7, -0.6, 0.05)]
w11, w12, b1, w21, w22, b2, v1, v2, c = p
x1, x2, target = Value(1.0), Value(0.0), Value(1.0)

h1 = (w11 * x1 + w12 * x2 + b1).sigmoid()
h2 = (w21 * x1 + w22 * x2 + b2).sigmoid()
y = (v1 * h1 + v2 * h2 + c).sigmoid()
error = y - target
loss = error * error

loss.backward()
print(f"loss {loss.data:.4f}")
for name, value in zip(names, p):
    print(f"{name:>3} {value.grad:+.6f}")
```

```text
loss 0.2056
w11 -0.035990
w12 +0.000000
 b1 -0.035990
w21 +0.033625
w22 +0.000000
 b2 +0.033625
 v1 -0.145096
 v2 -0.117977
  c -0.224727
```

These are the nine gradients that the hand-written `backward` produced, digit for digit, and this time nobody derived anything. The forward pass is written as ordinary arithmetic. The `Value` class knows the slope of an addition, a multiplication and a sigmoid, and that is enough to differentiate any formula built from those three. The `visit` function lists the values so that each one comes after everything it was made from. Walking that list in reverse means a value's own gradient is complete before it is passed on to its parents.

PyTorch's tensors do the same bookkeeping for whole arrays at once, with the arithmetic in compiled code. The calculation above looks like this in PyTorch:

```text
import torch

p = torch.tensor([0.5, -0.4, 0.1, 0.3, 0.8, -0.2, 0.7, -0.6, 0.05],
                 requires_grad=True)
h1 = torch.sigmoid(p[0] * 1.0 + p[1] * 0.0 + p[2])
h2 = torch.sigmoid(p[3] * 1.0 + p[4] * 0.0 + p[5])
y = torch.sigmoid(p[6] * h1 + p[7] * h2 + p[8])
loss = (y - 1.0) ** 2
loss.backward()     # fills p.grad with the nine gradients
print(p.grad)
```

```text
tensor([-0.0360,  0.0000, -0.0360,  0.0336,  0.0000,  0.0336, -0.1451, -0.1180,
        -0.2247])
```

PyTorch prints four decimal places by default, and to four places these are the same nine numbers, in the same order. The lines that compute `h1`, `h2`, `y` and the loss are the forward pass, written once. Nothing in the snippet describes how to go backwards.

In a real project you go one step further and let the framework hold the parameters and apply the update as well. The body of the loop then has four lines:

```text
for step in range(3000):
    loss = loss_fn(model(inputs), targets)   # forward pass and loss
    optimizer.zero_grad()                    # clear the old gradients
    loss.backward()                          # backward pass
    optimizer.step()                         # move against the gradients
```

Set that beside the plain Python loop and the list of what is automated is short: the bookkeeping of the backward pass, fast arithmetic on large arrays, and the update rule, which is packaged as an optimiser.

Everything else in this post stays the same. There is a forward pass that turns inputs into outputs. There is a loss that scores them with one number. Each parameter gets a gradient, and it still means "how much the loss changes if this number changes". Each step moves the parameters against their gradients, scaled by a learning rate. A run that stalls, a learning rate that is too small and an unlucky starting point look the same in PyTorch as they do here. And when a gradient looks wrong, the test is still to nudge the number and measure.

## Where to go next

The quickest way to make this stick is to break it. Flip a sign in `backward` and watch the gradient check catch it. Set the learning rate to 0.1 and see how long the flat start lasts. Try seed 2, then add a third hidden neuron and its four parameters, and check your new `backward` against the measurement before you train with it.

To go further:

- [The mathematics of neural networks](/learn/math/) works through derivatives, the chain rule, gradient checking and backpropagation by hand in NumPy.
- [Machine learning with PyTorch](/learn/ml/) starts with tensors, autograd and training loops, and builds up to convolutional networks and transformers.
- The [Logistic Regression](/labs/logistic/) Lab shows a single sigmoid neuron learning a boundary between two classes, one step at a time.
- [Attention, one query at a time](/blog/attention-in-small-python/) takes the same small-numbers approach to the operation at the centre of a transformer, a network trained by the same backward pass.

The courses and Labs are part of Pythilo. The lessons run free in the browser, and the app runs them on iPhone and iPad offline.
