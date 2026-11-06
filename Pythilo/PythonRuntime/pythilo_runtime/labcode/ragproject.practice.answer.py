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


def rag_response(documents, request, output):
    if set(request) != {'tenant', 'roles', 'query', 'k', 'word_budget'}:
        raise ValueError('exact trusted request schema required')
    budget = request['word_budget']
    if type(budget) is not int or budget < 0:
        raise ValueError('nonnegative context word budget required')
    ranked = secure_bm25(documents, request['tenant'], request['roles'], request['query'], request['k'])
    by_id = {doc['id']: doc for doc in documents if doc['tenant'] == request['tenant']
             and (not doc['roles'] or set(doc['roles']) & set(request['roles']))}
    context, used = {}, 0
    for item in ranked:
        doc = by_id[item['id']]
        words = len(doc['text'].split())
        if used + words <= budget:
            context[doc['id']] = doc['text']
            used += words
    if not isinstance(output, dict) or set(output) != {'claims'} or not isinstance(output['claims'], list):
        raise ValueError('structured provider output with claims required')
    accepted = []
    for claim in output['claims']:
        if set(claim) != {'text', 'source', 'start', 'end', 'quote'}:
            raise ValueError('exact claim schema required')
        if not isinstance(claim['text'], str) or not claim['text']:
            raise ValueError('nonempty claim text required')
        if claim['source'] not in context:
            raise PermissionError('citation is outside the admitted context')
        source = context[claim['source']]
        start, end = claim['start'], claim['end']
        if type(start) is not int or type(end) is not int or not 0 <= start < end <= len(source):
            raise ValueError('citation offsets must be valid code-point positions')
        if source[start:end] != claim['quote']:
            raise ValueError('quoted evidence does not match the context')
        accepted.append(claim['text'])
    return {'context_ids': list(context), 'words': used, 'claims': accepted,
            'answer': ' '.join(accepted), 'abstained': not accepted}
