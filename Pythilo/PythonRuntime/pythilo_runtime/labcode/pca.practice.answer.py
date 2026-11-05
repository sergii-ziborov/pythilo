def principal_axis(points, steps):
    import math
    mx = sum(p[0] for p in points) / len(points)
    my = sum(p[1] for p in points) / len(points)
    xx = sum((x-mx)**2 for x,y in points) / len(points)
    xy = sum((x-mx)*(y-my) for x,y in points) / len(points)
    yy = sum((y-my)**2 for x,y in points) / len(points)
    axis = [2 ** -.5, 2 ** -.5]
    for _ in range(steps):
        direction = [xx*axis[0]+xy*axis[1], xy*axis[0]+yy*axis[1]]
        norm = math.hypot(*direction)
        if not norm:
            direction = max(([xx,xy],[xy,yy]), key=lambda v: math.hypot(*v))
            norm = math.hypot(*direction)
            if not norm:
                return 0.0, 0.0
        axis = [value / norm for value in direction]
    if axis[0] < 0:
        axis = [-value for value in axis]
    return tuple(axis)
