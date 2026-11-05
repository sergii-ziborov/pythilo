def solve(n):
    solutions = []
    queens = []  # queens[row] is the column of the queen in that row

    def safe(col):
        row = len(queens)
        for r, c in enumerate(queens):
            if c == col:
                return False
            # TODO: queens also attack along diagonals.
        return True

    def place():
        if len(queens) == n:
            solutions.append(list(queens))
            return
        for col in range(n):
            if safe(col):
                queens.append(col)
                place()
                queens.pop()  # backtrack: undo and try the next column

    place()
    return solutions
