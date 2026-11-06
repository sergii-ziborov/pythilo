def tool_allowed(call,tenant,scopes,policy):
    name=call.get('tool')
    known=name in policy
    same_tenant=call.get('tenant')==tenant
    granted=known and policy[name] in set(scopes)
    result=known and same_tenant and granted
    return result
