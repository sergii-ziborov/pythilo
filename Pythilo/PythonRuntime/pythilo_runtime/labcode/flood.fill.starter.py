# grid is a list of rows; "." is open, "#" is a wall. Paint open cells "o".


def fill(grid, row, col):
    if grid[row][col] != ".":
        return
    stack = [(row, col)]
    grid[row][col] = "o"
    while stack:
        r, c = stack.pop()
        # TODO: also go up and left.
        for nr, nc in ((r + 1, c), (r, c + 1)):
            if 0 <= nr < len(grid) and 0 <= nc < len(grid[0]) and grid[nr][nc] == ".":
                grid[nr][nc] = "o"
                stack.append((nr, nc))
