def plan_kv(requests, layers, kv_heads, head_dim, bytes_per_element, capacity):
    if any(type(v) is not int or v <= 0 for v in (layers, kv_heads, head_dim, bytes_per_element)):
        raise ValueError('positive integer cache dimensions required')
    if type(capacity) is not int or capacity < 0:
        raise ValueError('nonnegative byte capacity required')
    if len({request['id'] for request in requests}) != len(requests):
        raise ValueError('unique request identities required')
    if any(type(request[key]) is not int or request[key] < 0
           for request in requests for key in ('prompt', 'output')):
        raise ValueError('nonnegative integer token counts required')
    bytes_per_token = 2 * layers * kv_heads * head_dim * bytes_per_element
    admitted, rejected = [], []
    reserved = 0
    for request in requests:
        cost = (request['prompt'] + request['output']) * bytes_per_token
        if reserved + cost <= capacity:
            admitted.append(request['id'])
            reserved += cost
        else:
            rejected.append(request['id'])
    return {'admitted': admitted, 'rejected': rejected, 'reserved_bytes': reserved,
            'bytes_per_token': bytes_per_token}
