import collections
import math
import re


def secure_bm25(documents, tenant, roles, query, k):
    if type(k) is not int or k < 0:
        raise ValueError('nonnegative integer result cutoff required')
    identities = [(doc['tenant'], doc['id']) for doc in documents]
    if len(identities) != len(set(identities)):
        raise ValueError('unique tenant/document identities required')
    allowed = [doc for doc in documents if doc['tenant'] == tenant
               and (not doc['roles'] or set(doc['roles']) & set(roles))]
    terms = sorted(set(re.findall(r'[a-z0-9]+', query.lower())))
    if not allowed or not terms or k == 0:
        return []
    counters = [collections.Counter(re.findall(r'[a-z0-9]+', doc['text'].lower())) for doc in allowed]
    lengths = [sum(counter.values()) for counter in counters]
    average = sum(lengths) / len(lengths)
    if not average:
        return []
    frequencies = {term: sum(term in counter for counter in counters) for term in terms}
    ranked = []
    for doc, counter, length in zip(allowed, counters, lengths):
        score = 0.0
        for term in terms:
            frequency = counter[term]
            document_frequency = frequencies[term]
            idf = math.log(1 + (len(allowed) - document_frequency + .5) / (document_frequency + .5))
            denominator = frequency + 1.2 * (1 - .75 + .75 * length / average)
            score += idf * frequency * 2.2 / denominator
        if score > 0:
            ranked.append({'id': doc['id'], 'score': score})
    ranked.sort(key=lambda item: (-item['score'], item['id']))
    return ranked[:k]
