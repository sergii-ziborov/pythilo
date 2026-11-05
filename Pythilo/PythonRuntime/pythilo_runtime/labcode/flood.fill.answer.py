# grid is a list of rows; "." is open, "#" is a wall. Paint open cells "o".
from collections import deque


def fill(grid, row, col):
    if grid[row][col] != ".":
        return
    queue = deque([(row, col)])  # a queue fills in rings; a stack dives deep
    grid[row][col] = "o"
    while queue:
        r, c = queue.popleft()
        for nr, nc in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
            if 0 <= nr < len(grid) and 0 <= nc < len(grid[0]) and grid[nr][nc] == ".":
                grid[nr][nc] = "o"
                queue.append((nr, nc))
