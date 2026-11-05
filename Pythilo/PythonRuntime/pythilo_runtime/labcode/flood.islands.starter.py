# grid is a list of rows; "L" is land, "." is water.


def count_islands(grid):
    count = 0
    for r in range(len(grid)):
        for c in range(len(grid[0])):
            # TODO: this counts land with no land above or to the left,
            # which splits U-shaped islands. Flood each new island instead.
            if grid[r][c] == "L":
                up = r > 0 and grid[r - 1][c] == "L"
                left = c > 0 and grid[r][c - 1] == "L"
                if not up and not left:
                    count += 1
    return count
