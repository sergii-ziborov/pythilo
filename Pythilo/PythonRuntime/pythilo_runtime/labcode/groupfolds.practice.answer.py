def group_folds(groups,k):
    names=sorted(set(groups))
    if not 2<=k<=len(names):raise ValueError('insufficient groups')
    assignment={g:i%k for i,g in enumerate(names)};folds=[[] for _ in range(k)]
    for i,g in enumerate(groups):folds[assignment[g]].append(i)
    return folds
