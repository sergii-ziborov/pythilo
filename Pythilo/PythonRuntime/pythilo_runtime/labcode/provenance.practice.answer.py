import hashlib


def verify_provenance(claims, sources, tenant, version):
    if len({source['id'] for source in sources}) != len(sources):
        raise ValueError('source identities must be unique')
    by_id = {source['id']: source for source in sources}
    report = []
    for claim in claims:
        errors = []
        if not claim['citations']:
            errors.append('missing')
        for citation in claim['citations']:
            key = citation['source']
            source = by_id.get(key)
            if source is None:
                errors.append(key + ':unknown')
                continue
            if source['tenant'] != tenant or source['version'] != version:
                errors.append(key + ':scope')
                continue
            digest = hashlib.sha256(source['text'].encode('utf8')).hexdigest()
            if digest != source['sha256']:
                errors.append(key + ':digest')
                continue
            start, end = citation['start'], citation['end']
            if type(start) is not int or type(end) is not int or not 0 <= start < end <= len(source['text']):
                errors.append(key + ':range')
            elif source['text'][start:end] != citation['quote']:
                errors.append(key + ':quote')
        report.append({'ok': not errors, 'errors': sorted(set(errors))})
    return report
