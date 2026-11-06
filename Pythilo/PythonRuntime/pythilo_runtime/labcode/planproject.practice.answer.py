import copy
import hashlib
import json


def execute_plan(state, plan, tenant, scopes, approved, max_steps):
    if type(max_steps) is not int or max_steps < 0:
        raise ValueError('nonnegative execution budget required')
    ids = [op['id'] for op in plan]
    if len(ids) != len(set(ids)) or any(not isinstance(key, str) or not key for key in ids):
        raise ValueError('unique nonempty operation identities required')
    by_id = {op['id']: op for op in plan}
    fingerprints = {}
    for op in plan:
        if set(op) != {'id', 'tool', 'args', 'deps'} or op['tool'] not in ('read', 'set'):
            raise ValueError('unknown operation or tool')
        if not isinstance(op['deps'], list) or len(op['deps']) != len(set(op['deps'])):
            raise ValueError('unique dependency identities required')
        if any(dep not in by_id or dep == op['id'] for dep in op['deps']):
            raise ValueError('unknown or self dependency')
        args = op['args']
        keys = {'key'} if op['tool'] == 'read' else {'key', 'value'}
        if not isinstance(args, dict) or set(args) != keys or not isinstance(args['key'], str):
            raise ValueError('exact tool argument schema required')
        if op['tool'] == 'set' and type(args['value']) not in (str, int, float, bool, type(None)):
            raise ValueError('this local tool accepts JSON scalar values only')
        encoded = json.dumps({'tenant': tenant, **op}, sort_keys=True, separators=(',', ':'), allow_nan=False)
        if len(encoded.encode()) > 4096:
            raise ValueError('operation payload exceeds the local byte limit')
        fingerprints[op['id']] = hashlib.sha256(encoded.encode()).hexdigest()
        required = 'records:read' if op['tool'] == 'read' else 'records:write'
        if required not in scopes:
            raise PermissionError('current trusted scope does not permit this tool')
        if op['tool'] == 'set' and fingerprints[op['id']] not in approved:
            raise PermissionError('exact operation was not approved by the trusted controller')
    pending, order = set(ids), []
    while pending:
        ready = sorted(key for key in pending if set(by_id[key]['deps']) <= set(order))
        if not ready:
            raise ValueError('dependency cycle in the plan')
        chosen = ready[0]
        order.append(chosen)
        pending.remove(chosen)
    candidate = copy.deepcopy(state)
    receipts = candidate.setdefault('receipts', {}).setdefault(tenant, {})
    new = []
    for key in order:
        if key in receipts and receipts[key]['fingerprint'] != fingerprints[key]:
            raise ValueError('conflicting operation replay')
        if key not in receipts:
            new.append(key)
    if len(new) > max_steps:
        raise ValueError('execution budget would be exceeded')
    records = candidate.setdefault('records', {}).setdefault(tenant, {})
    outputs = {}
    for key in order:
        if key in receipts:
            outputs[key] = receipts[key]['result']
            continue
        op = by_id[key]
        if op['tool'] == 'read':
            result = records[op['args']['key']]
        else:
            records[op['args']['key']] = op['args']['value']
            result = op['args']['value']
        receipts[key] = {'fingerprint': fingerprints[key], 'result': result}
        outputs[key] = result
    return {'state': candidate, 'order': order, 'outputs': outputs, 'executed': len(new)}
