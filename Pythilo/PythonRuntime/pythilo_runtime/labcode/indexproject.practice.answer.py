import copy
import hashlib
import json


def update_index(state, events, expected_version):
    if type(expected_version) is not int or expected_version != state['version']:
        raise ValueError('index compare-and-swap version mismatch')
    candidate = copy.deepcopy(state)
    changed = False
    for event in events:
        if set(event) - {'tenant', 'event', 'id', 'revision', 'op', 'text', 'roles'}:
            raise ValueError('unknown index event fields')
        if event['tenant'] != state['tenant'] or not isinstance(event['id'], str) or not event['id']:
            raise ValueError('tenant-scoped document identity required')
        if not isinstance(event['event'], str) or not event['event'] or event['op'] not in ('upsert', 'delete'):
            raise ValueError('valid event identity and operation required')
        if type(event['revision']) is not int or event['revision'] <= 0:
            raise ValueError('positive document revision required')
        if event['op'] == 'upsert' and (not isinstance(event.get('text'), str)
                or not isinstance(event.get('roles'), list)
                or any(not isinstance(role, str) for role in event['roles'])):
            raise ValueError('upsert requires text and string roles')
        canonical = json.dumps(event, sort_keys=True, separators=(',', ':'), allow_nan=False)
        digest = hashlib.sha256(canonical.encode()).hexdigest()
        seen = candidate['seen'].get(event['event'])
        if seen is not None:
            if seen != digest:
                raise ValueError('conflicting replay of an index event')
            continue
        previous = candidate['documents'].get(event['id'])
        if previous is not None and event['revision'] <= previous['revision']:
            raise ValueError('document revision must advance, including after deletion')
        candidate['documents'][event['id']] = {
            'revision': event['revision'], 'deleted': event['op'] == 'delete',
            'text': event.get('text', '') if event['op'] == 'upsert' else '',
            'roles': sorted(set(event.get('roles', []))) if event['op'] == 'upsert' else []}
        candidate['seen'][event['event']] = digest
        changed = True
    if changed:
        candidate['version'] += 1
    return candidate
