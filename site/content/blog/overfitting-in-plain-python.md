---
title: "Overfitting, seen in numbers: train, validation and regularisation in plain Python"
description: "Fit polynomials to fourteen noisy points in plain Python and watch training error fall while validation error climbs. Then measure what ridge, early stopping and more data change."
date: 2026-11-07
author: Pythilo
cover: /blog/overfitting-in-plain-python/cover.jpg
coverAlt: "Abstract illustration: a smooth glowing blue wave crosses a dark navy background, and a thin yellow zigzag line joins a row of white dots that swing far above and below the wave."
tags: Machine learning, Evaluation, Python
---

A model that scores well on the data it was trained on has proved very little. It may have learned the pattern behind the data, or it may have memorised the examples, noise and all. The two look the same until you ask about a point the model has not seen, and then they look very different. Overfitting is the second case, and it is how a model comes to be much worse than its own numbers say.

This post makes overfitting visible with an experiment small enough to read in full. We take fourteen noisy points from a smooth curve and fit polynomials of rising degree to them, with a least-squares solver written out in plain Python. There is no NumPy and no plotting. For each degree the program prints two errors: one on the fourteen points it was fitted to, and one on points it never saw. The first keeps falling. The second falls, turns, and ends more than five hundred times worse than its best.

Then the same few functions measure the standard remedies: a validation set to choose with, a test set that is opened once, ridge regularisation, early stopping and more data. The last section puts the words bias and variance on what the tables show. Every number below was printed by a program, nearly always the block just above it, and every code block is a complete program that runs on its own.

## Fourteen points and a least-squares fit

The data comes from a curve we choose ourselves, `sin(3x)` for x between -1 and 1. It dips to -1, climbs to 1 and comes part of the way back. Each point is the curve's value plus random noise with a standard deviation of 0.25. Knowing the true curve is the luxury of a made-up experiment: later we can check what a model got right and what it invented.

The model is a polynomial, `w0 + w1*x + w2*x**2` and so on up to some degree. Fitting means choosing the coefficients `w` that make the sum of squared differences between the polynomial and the training points as small as possible. A straight line has two coefficients. Setting the slope of that sum to zero in each of them gives two linear equations:

```text
 n * w0  +  Sx * w1  =  Sy
Sx * w0  + Sxx * w1  =  Sxy
```

Here `n` is the number of points, `Sx` is the sum of the x values, `Sxx` the sum of their squares, `Sy` the sum of the y values and `Sxy` the sum of the products of x and y. A higher degree works the same way with more unknowns: the entry in row `i` and column `j` is the sum of `x**(i + j)` over the points, and the right-hand side of row `i` is the sum of `x**i * y`. These are called the normal equations. The function `fit` builds them and `solve` solves them by Gaussian elimination. For each column it swaps the row with the largest entry into place, subtracts multiples of that row from the rows below until they hold zero in that column, and then works back up from the last unknown.

One detail keeps the arithmetic healthy. Because x stays between -1 and 1, every power of x does too. If x ran up to 100, `x**9` would reach 10 to the power 18 and those sums would lose precision. With real inputs, rescale them first, using a centre and spread computed from the training data only. The [Train-only Standardization Lab](/labs/standardize/) practises exactly that step.

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(col + 1, n):
            factor = m[r][col] / m[col][col]
            for c in range(col, n + 1):
                m[r][c] -= factor * m[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][c] * x[c] for c in range(r + 1, n))) / m[r][r]
    return x

def fit(points, degree):
    k = degree + 1
    rows = [[x ** j for j in range(k)] for x, _ in points]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * y for r, (_, y) in zip(rows, points)) for i in range(k)]
    return solve(a, b)

def predict(w, x):
    return sum(c * x ** j for j, c in enumerate(w))

def mse(w, points):
    return sum((predict(w, x) - y) ** 2 for x, y in points) / len(points)

pool = make_points(74, seed=219)
train = pool[:14]

print("2x2 check:", solve([[2, 1], [1, 3]], [5, 10]))
print("first points:", [(round(x, 3), round(y, 3)) for x, y in train[:3]])

n = len(train)
sx = sum(x for x, _ in train)
sxx = sum(x * x for x, _ in train)
sy = sum(y for _, y in train)
sxy = sum(x * y for x, y in train)
print(f"sums: n={n}  Sx={sx:.4f}  Sxx={sxx:.4f}  Sy={sy:.4f}  Sxy={sxy:.4f}")
print("line by hand:", [round(c, 4) for c in solve([[n, sx], [sx, sxx]], [sy, sxy])])

for degree in (1, 3):
    w = fit(train, degree)
    print(f"degree {degree}: {[round(c, 4) for c in w]}  training error {mse(w, train):.4f}")
```

```text
2x2 check: [1.0, 3.0]
first points: [(0.396, 0.89), (0.427, 1.019), (-0.793, -0.741)]
sums: n=14  Sx=0.2654  Sxx=5.6775  Sy=2.5203  Sxy=5.9423
line by hand: [0.1603, 1.0391]
degree 1: [0.1603, 1.0391]  training error 0.1878
degree 3: [0.0495, 2.6306, 0.0653, -2.4999]  training error 0.0389
```

The first line checks the solver on a system you can do in your head: `2x + y = 5` and `x + 3y = 10` give x = 1 and y = 3. The sums are the numbers of the straight-line equations, and solving those by hand gives the same line as `fit` does, `0.1603 + 1.0391x`. Its error is 0.1878. Error in this post always means mean squared error: the average of the squared differences between prediction and data. The cubic bends where the line cannot, and gets 0.0389.

One reference value is worth keeping in mind. Noise with a standard deviation of 0.25 has a mean square of 0.25 squared, which is 0.0625. On new points no model can be expected to beat that, because the noise in a new point cannot be predicted.

The program drew 74 points and used the first fourteen. The other sixty are held back for the next two sections. Each program below repeats the helpers so that it runs alone, and the new part is always at the bottom.

## Training error falls, validation error turns back up

Now fit every degree from 1 to 12 to the same fourteen points, and measure each fit twice: on the training points, and on the next thirty points of the pool, which no fit has seen. Those thirty are the validation set. The table also shows the largest coefficient of each polynomial, ignoring its sign and leaving out the constant term, and a final row for the true curve itself. The output below the main table is used a little further down.

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(col + 1, n):
            factor = m[r][col] / m[col][col]
            for c in range(col, n + 1):
                m[r][c] -= factor * m[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][c] * x[c] for c in range(r + 1, n))) / m[r][r]
    return x

def fit(points, degree):
    k = degree + 1
    rows = [[x ** j for j in range(k)] for x, _ in points]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * y for r, (_, y) in zip(rows, points)) for i in range(k)]
    return solve(a, b)

def predict(w, x):
    return sum(c * x ** j for j, c in enumerate(w))

def mse(w, points):
    return sum((predict(w, x) - y) ** 2 for x, y in points) / len(points)

pool = make_points(74, seed=219)
train, validation = pool[:14], pool[14:44]

def curve_error(points):
    return sum((math.sin(3 * x) - y) ** 2 for x, y in points) / len(points)

fits = {degree: fit(train, degree) for degree in range(1, 13)}

print("degree   train   validation   largest coefficient")
for degree, w in fits.items():
    largest = max(abs(c) for c in w[1:])
    print(f"{degree:6d}  {mse(w, train):.4f}  {mse(w, validation):11.4f}  {largest:20.1f}")
print(f" curve  {curve_error(train):.4f}  {curve_error(validation):11.4f}")

print()
print("training x:", [round(x, 2) for x, _ in sorted(train)])
print()
print("     x   true curve   degree 3   degree 9   degree 12")
for x in (-0.97, 0.2, 0.75):
    print(f"{x:6.2f}  {math.sin(3 * x):11.3f}  {predict(fits[3], x):9.3f}"
          f"  {predict(fits[9], x):9.3f}  {predict(fits[12], x):10.3f}")

def squared_miss(point):
    return (predict(fits[9], point[0]) - point[1]) ** 2

worst = max(validation, key=squared_miss)
share = squared_miss(worst) / sum(squared_miss(p) for p in validation)
print()
print(f"validation point at x = {worst[0]:.3f}: {share:.0%} of the degree 9 validation error")
```

```text
degree   train   validation   largest coefficient
     1  0.1878       0.2578                   1.0
     2  0.1832       0.2691                   1.0
     3  0.0389       0.0735                   2.6
     4  0.0347       0.0867                   2.7
     5  0.0339       0.0927                   2.6
     6  0.0334       0.0878                   2.5
     7  0.0258       0.1468                  25.4
     8  0.0116       0.3233                  55.7
     9  0.0092       0.4433                 127.7
    10  0.0034       1.2527                 683.0
    11  0.0023       2.0200                 694.7
    12  0.0003      39.2471               21041.1
 curve  0.0520       0.0560

training x: [-0.92, -0.86, -0.79, -0.73, -0.34, -0.27, 0.04, 0.4, 0.41, 0.43, 0.46, 0.62, 0.85, 0.96]

     x   true curve   degree 3   degree 9   degree 12
 -0.97       -0.230     -0.159      2.795      16.894
  0.20        0.565      0.558      0.493      -2.917
  0.75        0.778      1.005      0.851      12.453

validation point at x = -0.973: 78% of the degree 9 validation error
```

Read the training column first. It falls at every step, from 0.1878 to 0.0003. It has to. A polynomial of degree 4 can do everything a polynomial of degree 3 can, by setting its extra coefficient to zero, so the best fit of degree 4 is never worse on the training points. That holds whether or not the extra flexibility is of any use, which is why training error cannot tell you when to stop.

The validation column tells a different story. Degree 1 scores 0.1878 on training and 0.2578 on validation, and degree 2 is no better. A line or a parabola cannot make the shape of this curve, so both errors are high. That is underfitting. Degree 3 can make the shape, and validation error drops to 0.0735, close to the noise level of 0.0625. Up to degree 6 it hovers between 0.0867 and 0.0927. Then it climbs: 0.1468 at degree 7, 0.4433 at degree 9, 39.2471 at degree 12. Between degree 3 and degree 12 the training error improved more than a hundredfold, and the validation error became more than five hundred times worse.

![Two glowing curves start together at the top left of a dark navy background. The blue curve keeps falling all the way to the bottom right. The yellow curve falls to a low point marked with a white dot, then climbs to the top right.](/blog/overfitting-in-plain-python/train-validation-gap.webp "The shape to look for as a model gets more flexible. One error keeps falling, the other reaches a lowest point and climbs again. An illustration, not a plot of the table above.")

### What a model fits when it fits noise

The last row of the main table explains why the two columns part ways. The true curve, the one that generated the data, scores 0.0520 on the training points and 0.0560 on the validation points. That is the noise, and nothing can remove it honestly. So a model with a training error below 0.0520 is not closer to the truth than the truth is. It has started to reproduce the particular noise in these fourteen points. The cubic does a little of that, at 0.0389, as any fit with free coefficients will. Degree 12 has thirteen coefficients for fourteen points and uses them to pass almost exactly through every noisy value, at 0.0003.

The noise in the training points is not in the validation points, which have their own. So that effort is wasted at best. In fact it does damage, and the coefficient column shows how. To thread through fourteen scattered values, the polynomial needs large coefficients of opposite signs that nearly cancel at the training points. The largest is 2.6 at degree 3, 127.7 at degree 9 and 21041.1 at degree 12. Away from the training points they do not cancel.

The second table looks at three places away from the training points, whose positions are printed above it. At x = 0.2, in the gap between the training points at 0.04 and 0.4, the true curve is at 0.565 and the cubic says 0.558. Degree 12 says -2.917. At x = 0.75, between the training points at 0.62 and 0.85, it says 12.453 where the curve is at 0.778.

The third place, x = -0.97, lies just beyond the leftmost training point at -0.92. Degree 9 predicts 2.795 there, for a curve value of -0.230. The validation set happens to contain a point close by, at x = -0.973, and the last line of the output says what it costs: that one point supplies 78% of the degree 9 validation error. High-degree polynomials are at their worst at the edges of the data and beyond, where no training point holds them down.

Two things limit how far these digits can be trusted. The first is the seed, 219, which was picked so that the table is easy to read. Other seeds move the numbers but not the shape. Rerunning the table with every seed from 1 to 300 puts the lowest validation error at degree 3 in 172 runs, and at degree 3, 4 or 5 in 265.

The second is arithmetic. With thirteen coefficients the equations are close to having no single solution, and rounding in the sixteenth significant digit of the sums reaches the fourth decimal of the answer. The output above comes from Python on a laptop. Under Pyodide, the Python that runs in a browser, the same program prints 39.2470 for the degree 12 validation error, and the degree 12 entries of the later tables differ in their last digit in the same way. Every other number agrees to the last digit.

## Three piles of data, and a test set opened once

The validation set did its job: it showed what the training error hid. It could do that because its points played no part in the fit. Training error measures how well the model remembers. Only points the model has not seen measure what you care about, which is the error on the next input.

But the validation set has now been used as well. We looked at twelve validation errors and would naturally keep the smallest. The degree has become a number chosen to suit those thirty points, in the same way that the coefficients were chosen to suit the training points. The smallest of twelve noisy numbers is partly small by luck, so the winner's validation error flatters it a little.

The answer is a third pile, the test set. It is used for nothing: no fitting, no choosing. When every decision has been made, it is opened once, and the error on it is the number you report. The last thirty points of the pool have been waiting for this.

![Three trays in a row on a dark navy surface: a large tray filled with blue balls, a smaller tray of yellow balls, and a small tray holding a few white balls under a clear glass dome.](/blog/overfitting-in-plain-python/three-piles.webp "Three piles with three jobs: a large one to fit on, a smaller one to choose with, and a small one kept under cover until the end.")

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(col + 1, n):
            factor = m[r][col] / m[col][col]
            for c in range(col, n + 1):
                m[r][c] -= factor * m[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][c] * x[c] for c in range(r + 1, n))) / m[r][r]
    return x

def fit(points, degree):
    k = degree + 1
    rows = [[x ** j for j in range(k)] for x, _ in points]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * y for r, (_, y) in zip(rows, points)) for i in range(k)]
    return solve(a, b)

def predict(w, x):
    return sum(c * x ** j for j, c in enumerate(w))

def mse(w, points):
    return sum((predict(w, x) - y) ** 2 for x, y in points) / len(points)

pool = make_points(74, seed=219)
train, validation, test = pool[:14], pool[14:44], pool[44:]

fits = {degree: fit(train, degree) for degree in range(1, 13)}
by_train = min(fits, key=lambda d: mse(fits[d], train))
by_validation = min(fits, key=lambda d: mse(fits[d], validation))

print("chosen by          degree   that error   test error")
for name, degree, data in (("training error", by_train, train),
                           ("validation error", by_validation, validation)):
    w = fits[degree]
    print(f"{name:18s} {degree:6d}  {mse(w, data):11.4f}  {mse(w, test):11.4f}")
```

```text
chosen by          degree   that error   test error
training error         12       0.0003      64.2511
validation error        3       0.0735       0.0828
```

Choosing by training error picks degree 12, whose own score of 0.0003 says nothing about its test error of 64.2511. Choosing by validation error picks degree 3, with a test error of 0.0828. That is the honest estimate of how this model will do on new points. It is a little higher than the validation error of 0.0735, which is the direction to expect, although with thirty points in each pile part of the difference is ordinary sampling luck.

The test set stays honest only while it stays unused. If you look at 0.0828, go back, change the degree and look again, the test set has turned into a second validation set, and its number starts to flatter the model too. There is no fourth pile to rescue you. This program scored two models on the test set only to show what the bad choice costs.

Three practical notes. First, with real data you get one dataset and cut it yourself: shuffle it, or split by time if the order matters, and give most of it to training. Here the training set is kept at fourteen points on purpose, so that overfitting is easy to provoke, and the generator supplies validation and test points for free. Second, anything fitted to data must be fitted to the training part alone, including the mean and spread used for scaling. [A validation score you can trust](/blog/validation-without-leakage/) follows that rule through with four numbers. Third, when data is too scarce for a steady validation pile, cross-validation rotates the role, so that each part of the data takes a turn as the validation set. The [Cross-validation Folds Lab](/labs/crossvalidation/) builds the index bookkeeping for it.

## Ridge: a price on large coefficients

Choosing a lower degree is one way to restrain a model. Another way keeps the flexible model and makes wild coefficients expensive. Ridge regression, also called L2 regularisation, adds a penalty to the quantity being minimised: the sum of squared errors, plus a penalty strength times the sum of the squared coefficients. A coefficient may still grow, but only if it buys a larger reduction in error than it costs in penalty.

In the normal equations this changes one thing: the penalty strength is added to each entry on the diagonal. That is the two-line loop in `fit` below. The constant term is left out of the penalty, because it only moves the whole curve up or down and there is no reason to pull the curve towards zero. The penalty treats all the other coefficients alike, which is fair only when the features have similar sizes. Here every power of x lies between -1 and 1. Real features should be standardised first. The [Ridge Regression Lab](/labs/ridge/) has you write the one-feature version, where the whole effect is one extra term in a division.

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(col + 1, n):
            factor = m[r][col] / m[col][col]
            for c in range(col, n + 1):
                m[r][c] -= factor * m[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][c] * x[c] for c in range(r + 1, n))) / m[r][r]
    return x

def fit(points, degree, penalty=0.0):
    k = degree + 1
    rows = [[x ** j for j in range(k)] for x, _ in points]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * y for r, (_, y) in zip(rows, points)) for i in range(k)]
    for j in range(1, k):        # ridge: the penalty goes on the diagonal,
        a[j][j] += penalty       # for every coefficient except the constant
    return solve(a, b)

def predict(w, x):
    return sum(c * x ** j for j, c in enumerate(w))

def mse(w, points):
    return sum((predict(w, x) - y) ** 2 for x, y in points) / len(points)

pool = make_points(74, seed=219)
train, validation = pool[:14], pool[14:44]

print("penalty   train   validation   largest coefficient")
for penalty in (0, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1, 10, 100):
    w = fit(train, 9, penalty)
    largest = max(abs(c) for c in w[1:])
    print(f"{penalty:7g}  {mse(w, train):.4f}  {mse(w, validation):11.4f}  {largest:20.2f}")

print()
for penalty in (0, 1e-2, 100):
    print(f"{penalty:g}:", [round(c, 2) for c in fit(train, 9, penalty)])
```

```text
penalty   train   validation   largest coefficient
      0  0.0092       0.4433                127.66
  1e-06  0.0097       0.3674                 61.02
  1e-05  0.0113       0.2888                 44.67
 0.0001  0.0187       0.1694                 13.46
  0.001  0.0282       0.1040                  3.33
   0.01  0.0329       0.0999                  2.32
    0.1  0.0425       0.1150                  1.90
      1  0.1376       0.2136                  1.05
     10  0.3491       0.3884                  0.33
    100  0.5634       0.5169                  0.05

0: [0.27, 1.57, -5.65, 13.37, 34.58, -74.72, -68.78, 127.66, 42.49, -70.95]
0.01: [0.11, 2.32, -0.2, -1.3, -0.25, -0.54, 0.07, -0.3, 0.79, -0.45]
100: [0.19, 0.05, -0.01, 0.03, -0.01, 0.02, -0.0, 0.01, -0.0, 0.01]
```

This is the degree 9 polynomial throughout, and the first row is the unpenalised fit from the earlier table. As the penalty grows, the largest coefficient shrinks from 127.66 to 3.33 at a penalty of 0.001, and to 0.05 at a penalty of 100. Training error rises all the way, from 0.0092 to 0.5634, because the fit is now asked to care about something other than the training points. Validation error improves from 0.4433 to 0.0999 at a penalty of 0.01, more than four times better, and then gets worse again. At a penalty of 100 every coefficient except the constant is close to zero, the polynomial is nearly a flat line at 0.19, and the model underfits. It is the same turn as before, traced along the penalty instead of the degree.

The three coefficient lists show what the penalty did. Without it the coefficients swing between -74.72 and 127.66. At 0.01 the two largest are 2.32 for x and -1.3 for x cubed, and every other one is below 0.8 in size. That is the outline of the cubic from the first section, whose coefficients for x and x cubed were 2.6306 and -2.4999.

The penalty strength is chosen as the degree was, by validation error, so the caution about the test set applies to it too. It is also worth being plain about the result. The best ridge fit, at 0.0999, beats the unpenalised degree 9 by a wide margin and still loses to simply choosing degree 3, at 0.0735. On this problem there is a short list of models in a natural order, and picking the right size works well. Ridge earns its place when there is no such list: many features, no obvious order among them, and no way to know which to drop. The same idea is called weight decay when training neural networks.

## Early stopping: the same idea, measured in steps

The solver jumps straight to the coefficients with the lowest training error. Gradient descent walks there instead. It starts with every coefficient at zero, and at each step it moves each one a little in the direction that reduces the training error. A walk can be stopped before it arrives, and that turns out to be a third way to restrain a model.

One change makes the walk practical. On raw powers gradient descent crawls, because columns such as `x**7` and `x**9` are almost copies of each other. In a trial run it had only reached a training error of 0.0243 after 50,000 steps, against the solver's 0.0092. So the code below describes the same degree 9 polynomial as a weighted sum of the first ten Legendre polynomials: 1, x, `(3*x**2 - 1) / 2` and so on, each built from the two before it. Every one of them is an ordinary polynomial, so the family of curves and the least-squares answer are the same as before. Only the route changes.

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def legendre(x, k):
    p = [1.0, x]
    for n in range(1, k - 1):
        p.append(((2 * n + 1) * x * p[n] - n * p[n - 1]) / (n + 1))
    return p[:k]

def error(w, rows, ys):
    return sum((sum(c * f for c, f in zip(w, row)) - y) ** 2
               for row, y in zip(rows, ys)) / len(ys)

pool = make_points(74, seed=219)
train, validation = pool[:14], pool[14:44]
k = 10                                    # ten coefficients: degree 9
rows = [legendre(x, k) for x, _ in train]
ys = [y for _, y in train]
val_rows = [legendre(x, k) for x, _ in validation]
val_ys = [y for _, y in validation]

w = [0.0] * k
rate = 0.3
best_error, best_step, best_w = float("inf"), 0, w
print("  step   train   validation")
for step in range(1, 2001):
    residuals = [sum(c * f for c, f in zip(w, row)) - y for row, y in zip(rows, ys)]
    gradient = [2 * sum(e * row[j] for e, row in zip(residuals, rows)) / len(rows)
                for j in range(k)]
    w = [c - rate * g for c, g in zip(w, gradient)]
    val_error = error(w, val_rows, val_ys)
    if val_error < best_error:
        best_error, best_step, best_w = val_error, step, w
    if step in (1, 3, 10, 30, 100, 300, 1000, 2000):
        print(f"{step:6d}  {error(w, rows, ys):.4f}  {val_error:11.4f}")

print(f"lowest validation error {best_error:.4f} at step {best_step}")
print(f"kept weights: train {error(best_w, rows, ys):.4f},"
      f" validation {error(best_w, val_rows, val_ys):.4f}")
```

```text
  step   train   validation
     1  0.4017       0.3917
     3  0.1971       0.2544
    10  0.0685       0.1289
    30  0.0312       0.0908
   100  0.0192       0.1371
   300  0.0122       0.2442
  1000  0.0094       0.3800
  2000  0.0092       0.4297
lowest validation error 0.0905 at step 27
kept weights: train 0.0330, validation 0.0905
```

Training error falls at every checkpoint, and with a step size this small it falls at every single step. Validation error falls with it for a while, reaches 0.0905 at step 27, and then climbs: 0.1371 at step 100, 0.2442 at step 300, 0.4297 at step 2000. The last row is almost the degree 9 row of the first table, 0.0092 and 0.4433. Gradient descent is heading for the same overfitted answer as the solver. It gets the broad shape of the curve first, because that reduces the error most, and spends the remaining steps bending towards individual noisy points.

Early stopping means keeping the coefficients from the step with the lowest validation error, here 0.0905 on validation with a training error of 0.0330. In a real run you cannot see the later steps. You stop when the validation error has not improved for a set number of steps, called the patience, and go back to the best coefficients seen. The number of steps has become one more setting tuned on the validation set.

It resembles ridge for a reason. The coefficients start at zero and grow as training continues, so stopping early also keeps them small.

## What more data does

Everything so far worked on the model. The other lever is the data. Keep the same fourteen training points, add 46 new ones from the same generator, and repeat the first experiment with all 60. The gap in the tables is validation error minus training error.

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(col + 1, n):
            factor = m[r][col] / m[col][col]
            for c in range(col, n + 1):
                m[r][c] -= factor * m[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][c] * x[c] for c in range(r + 1, n))) / m[r][r]
    return x

def fit(points, degree):
    k = degree + 1
    rows = [[x ** j for j in range(k)] for x, _ in points]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * y for r, (_, y) in zip(rows, points)) for i in range(k)]
    return solve(a, b)

def predict(w, x):
    return sum(c * x ** j for j, c in enumerate(w))

def mse(w, points):
    return sum((predict(w, x) - y) ** 2 for x, y in points) / len(points)

pool = make_points(74, seed=219)
train, validation = pool[:14], pool[14:44]
extra = make_points(46, seed=222)
bigger = train + extra                    # the same 14 points and 46 new ones

print("          14 points                    60 points")
print("degree    train  validation      gap   train  validation      gap")
for degree in (1, 3, 6, 9, 12):
    line = f"{degree:6d}"
    for data in (train, bigger):
        w = fit(data, degree)
        gap = mse(w, validation) - mse(w, data)
        line += f"   {mse(w, data):.4f}  {mse(w, validation):10.4f}  {gap:7.4f}"
    print(line)

print()
print("degree 9 as the training set grows")
print("points    train  validation      gap")
for n in (14, 20, 30, 45, 60):
    data = bigger[:n]
    w = fit(data, 9)
    gap = mse(w, validation) - mse(w, data)
    print(f"{n:6d}   {mse(w, data):.4f}  {mse(w, validation):10.4f}  {gap:7.4f}")
```

```text
          14 points                    60 points
degree    train  validation      gap   train  validation      gap
     1   0.1878      0.2578   0.0700   0.2255      0.2308   0.0053
     3   0.0389      0.0735   0.0346   0.0481      0.0605   0.0124
     6   0.0334      0.0878   0.0545   0.0448      0.0568   0.0120
     9   0.0092      0.4433   0.4342   0.0447      0.0576   0.0128
    12   0.0003     39.2471  39.2468   0.0441      0.0606   0.0165

degree 9 as the training set grows
points    train  validation      gap
    14   0.0092      0.4433   0.4342
    20   0.0258      0.0836   0.0578
    30   0.0322      0.0681   0.0359
    45   0.0400      0.0607   0.0207
    60   0.0447      0.0576   0.0128
```

The right half of the first table is a different world. With 60 points the degree 9 gap shrinks from 0.4342 to 0.0128, and the degree 12 gap from 39.2468 to 0.0165. From degree 3 to degree 12, the validation errors shown now sit between 0.0568 and 0.0606. The choice of degree, which decided everything with fourteen points, hardly matters.

Notice that the training error went up, from 0.0092 to 0.0447 at degree 9. That is good news. Ten coefficients could chase fourteen points one by one. They cannot chase sixty, so the fit is forced towards what the points have in common, which is the curve. The second table shows it happening as points are added. Training error rises, validation error falls towards the 0.0560 that the true curve itself scores on those thirty points, and the gap closes from 0.4342 through 0.0578 and 0.0359 to 0.0128.

More data does not fix everything. Degree 1 still scores 0.2308 on validation with 60 points, because a straight line cannot follow this curve however many points it sees. A small gap with a large error on both sides, 0.2255 and 0.2308, is the signature of underfitting, and the cure for that is a more flexible model. What matters is the amount of data relative to the flexibility of the model: ten coefficients against fourteen points is a very different situation from ten coefficients against sixty.

## Bias and variance in plain words

The tables mix two different ways of being wrong, and each has a name. Bias is error that stays the same whichever training set you happened to get. The model family cannot express the truth, so it is wrong in the same way every time. Variance is error that comes from the particular training set. The model follows its noise, so a different sample gives a different answer.

To see them separately, repeat the experiment many times. The program below keeps the fourteen training positions, draws fresh noise 200 times, refits each time, and records what each fit predicts at nineteen positions from -0.9 to 0.9. Bias squared is how far the average prediction lies from the true curve, squared. Variance is how much the 200 predictions scatter around their own average.

```python
import math
import random

def make_points(n, seed):
    rng = random.Random(seed)
    points = []
    for _ in range(n):
        x = rng.uniform(-1, 1)
        points.append((x, math.sin(3 * x) + rng.gauss(0, 0.25)))
    return points

def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(col + 1, n):
            factor = m[r][col] / m[col][col]
            for c in range(col, n + 1):
                m[r][c] -= factor * m[col][c]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][c] * x[c] for c in range(r + 1, n))) / m[r][r]
    return x

def fit(points, degree):
    k = degree + 1
    rows = [[x ** j for j in range(k)] for x, _ in points]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * y for r, (_, y) in zip(rows, points)) for i in range(k)]
    return solve(a, b)

def predict(w, x):
    return sum(c * x ** j for j, c in enumerate(w))

pool = make_points(74, seed=219)
xs = [x for x, _ in pool[:14]]            # keep the fourteen training positions
grid = [i / 10 for i in range(-9, 10)]    # compare predictions at -0.9, -0.8, ... 0.9
rng = random.Random(1)

print("                                      predictions at x = -0.5")
print("degree   bias^2  variance     sum     lowest     mean  highest")
for degree in (1, 3, 9):
    runs = []
    for _ in range(200):                  # same positions, fresh noise
        points = [(x, math.sin(3 * x) + rng.gauss(0, 0.25)) for x in xs]
        w = fit(points, degree)
        runs.append([predict(w, x) for x in grid])
    bias2 = variance = 0.0
    for i, x in enumerate(grid):
        column = [run[i] for run in runs]
        mean = sum(column) / len(column)
        bias2 += (mean - math.sin(3 * x)) ** 2 / len(grid)
        variance += sum((p - mean) ** 2 for p in column) / len(column) / len(grid)
    at = [run[4] for run in runs]         # grid[4] is x = -0.5
    print(f"{degree:6d}   {bias2:.4f}    {variance:.4f}  {bias2 + variance:.4f}"
          f"   {min(at):8.3f} {sum(at) / len(at):8.3f} {max(at):8.3f}")
print(f"true curve at x = -0.5: {math.sin(3 * -0.5):.3f}")
```

```text
                                      predictions at x = -0.5
degree   bias^2  variance     sum     lowest     mean  highest
     1   0.1595    0.0078  0.1674     -0.597   -0.365   -0.172
     3   0.0027    0.0166  0.0193     -1.397   -1.004   -0.677
     9   0.0004    0.1379  0.1383     -3.312   -0.953    0.832
true curve at x = -0.5: -0.997
```

Look at x = -0.5 first, where the true curve is at -0.997. The 200 straight lines all predict between -0.597 and -0.172. They agree with each other and are all wrong in the same direction: that is bias. The 200 fits of degree 9 average -0.953, which is nearly right, but individual fits range from -3.312 to 0.832. Being right on average is no comfort when you only ever get one training set: that is variance. The cubic averages -1.004 and stays between -1.397 and -0.677.

![Two targets made of thin concentric rings with a bright white centre, side by side on a dark navy background. On the left target a tight cluster of blue dots sits away from the centre, up and to the right. On the right target yellow dots are scattered across all the rings around the centre.](/blog/overfitting-in-plain-python/bias-variance-targets.webp "Left: shots that agree with each other and all miss in the same direction, which is bias. Right: shots centred on the middle that land all over the target, which is variance. An illustration of the two kinds of error.")

Averaged over the nineteen positions, bias squared falls as the degree rises, 0.1595, 0.0027, 0.0004, and variance rises, 0.0078, 0.0166, 0.1379. Their sum is what counts, and it is smallest in the middle: 0.1674, 0.0193 and 0.1383. The expected squared error on a new point is that sum plus the noise, 0.0625, which no model can remove.

This gives the remedies a common description. Ridge and early stopping accept a little bias in return for a large cut in variance. More data cuts variance without adding bias. A more flexible model cuts bias and adds variance. So the useful first question about a disappointing model is which of the two it suffers from, and the two errors answer it. High error on both training and validation data points to bias. A low training error with a much higher validation error points to variance.

## A short checklist

- Split the data before anything else, into training, validation and test. Fit everything on the training part only, scaling included.
- Print training and validation error side by side for every model you try. One of them alone cannot show overfitting.
- If both errors are high, the model underfits. Make it more flexible or give it better features.
- If training error is low and validation error is much higher, the model overfits. Simplify it, regularise it or get more data.
- Choose the degree, the penalty and the number of steps by validation error, never by training error.
- Look at the coefficients. Very large values of opposite signs are a model cancelling itself out to hit noisy points.
- Distrust predictions at the edges of the training data and beyond them.
- Open the test set once, report that number, and stop.

## Where to go next

Change the programs and watch the tables move. Raise the noise from 0.25 to 0.5 and see where the validation error turns. Try another seed. Search over degree and penalty together, and check the winner on the test set, once.

For guided practice, the [ML evaluation course](/learn/ml-evaluation/) works through train-only standardisation, cross-validation folds and ridge regression as small experiments, and [Machine learning in practice](/learn/ml-practice/) includes a lesson on stopping training with patience. The lessons run free in the browser, and the Pythilo app runs them on iPhone and iPad offline.
