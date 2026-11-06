def citation_errors(claims,allowed):
    allowed=set(allowed);errors=[]
    for i,claim in enumerate(claims):
        refs=list(dict.fromkeys(claim['citations']))
        if not refs:errors.append(f'{i}:missing')
        errors.extend(f'{i}:unknown:{key}' for key in refs if key not in allowed)
    return errors
