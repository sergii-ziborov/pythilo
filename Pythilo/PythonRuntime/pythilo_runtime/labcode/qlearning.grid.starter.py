def update(Q, state, action, reward, next_state, alpha, gamma):
    # Q[state][action]: how good it is to take action in state, as learned so far.
    # TODO: this only learns the reward of one move, so nothing tells a cell
    # far from the goal which way is good. Add what the next state promises:
    # target = reward + gamma * max(Q[next_state]).
    target = reward
    Q[state][action] += alpha * (target - Q[state][action])
