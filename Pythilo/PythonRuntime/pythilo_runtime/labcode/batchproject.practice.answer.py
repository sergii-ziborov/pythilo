def batch_schedule(requests, max_active, capacity):
    if type(max_active) is not int or max_active < 1 or type(capacity) is not int or capacity < 1:
        raise ValueError('positive integer slot and token capacities required')
    if len({row['id'] for row in requests}) != len(requests):
        raise ValueError('unique request identities required')
    if any(not isinstance(row['id'], str) for row in requests):
        raise ValueError('string request identities required')
    for row in requests:
        if any(type(row[key]) is not int for key in ('arrival', 'deadline', 'prompt', 'output')):
            raise ValueError('integer scheduler inputs required')
        if row['arrival'] < 0 or row['deadline'] <= row['arrival'] or row['prompt'] < 0 or row['output'] < 1:
            raise ValueError('invalid arrival, deadline or token counts')
    rejected = sorted(row['id'] for row in requests if row['prompt'] + row['output'] > capacity)
    pending = sorted((dict(row) for row in requests if row['id'] not in rejected),
                     key=lambda row: (row['arrival'], row['id']))
    active, completed, cancelled, events = [], {}, [], []
    tick = 0
    while pending or active:
        if not active and pending and pending[0]['arrival'] > tick:
            tick = pending[0]['arrival']
        expired = sorted(row['id'] for row in pending + active if row['deadline'] <= tick)
        cancelled.extend(expired)
        pending = [row for row in pending if row['id'] not in expired]
        active = [row for row in active if row['id'] not in expired]
        admitted = []
        reserved = sum(row['prompt'] + row['output'] for row in active)
        while pending and pending[0]['arrival'] <= tick and len(active) < max_active:
            row = pending[0]
            cost = row['prompt'] + row['output']
            if reserved + cost > capacity:
                break
            pending.pop(0)
            row['remaining'] = row['output']
            active.append(row)
            reserved += cost
            admitted.append(row['id'])
        finished = []
        for row in active:
            row['remaining'] -= 1
            if row['remaining'] == 0:
                completed[row['id']] = tick + 1
                finished.append(row['id'])
        active = [row for row in active if row['id'] not in finished]
        events.append({'tick': tick, 'admitted': admitted, 'completed': finished,
                       'cancelled': expired, 'active': [row['id'] for row in active],
                       'reserved': reserved})
        tick += 1
    return {'completed': completed, 'cancelled': sorted(cancelled),
            'rejected': rejected, 'events': events}
