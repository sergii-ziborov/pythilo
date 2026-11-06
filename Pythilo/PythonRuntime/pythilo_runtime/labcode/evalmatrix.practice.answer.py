def evaluation_matrix(expected, results):
    if not expected:
        raise ValueError('a nonempty versioned evaluation inventory is required')
    expected_ids = [row['id'] for row in expected]
    result_ids = [row['id'] for row in results]
    if len(set(expected_ids)) != len(expected_ids) or len(set(result_ids)) != len(result_ids):
        raise ValueError('duplicate case identities are not extra evidence')
    if set(expected_ids) != set(result_ids):
        raise ValueError('missing or unexpected evaluation cases')
    if any(type(row['passed']) is not bool for row in results):
        raise ValueError('explicit boolean outcomes required')
    by_id = {row['id']: row['passed'] for row in results}
    categories = {}
    for row in expected:
        categories.setdefault(row['category'], []).append(row['id'])
    report = {}
    for category in sorted(categories):
        ids = sorted(categories[category])
        failed = [key for key in ids if not by_id[key]]
        report[category] = {'total': len(ids), 'passed': len(ids) - len(failed),
                            'rate': (len(ids) - len(failed)) / len(ids), 'failed': failed}
    return report
