def update(Q, state, action, reward, next_state, alpha, gamma):
    # Q[state][action]: how good it is to take action in state, as learned so far.
    target = reward + gamma * max(Q[next_state])
    Q[state][action] += alpha * (target - Q[state][action])
