import math


def validate_output(value, schema):
    supported = {'object', 'array', 'string', 'integer', 'number', 'boolean', 'null'}
    allowed = {'type', 'properties', 'required', 'additionalProperties', 'items', 'maxItems', 'maxLength', 'enum'}
    def check_schema(node):
        if not isinstance(node, dict) or node.get('type') not in supported or set(node) - allowed:
            raise ValueError('unsupported schema vocabulary')
        kind = node['type']
        permitted = {'type', 'enum'} | ({'properties', 'required', 'additionalProperties'} if kind == 'object'
                    else {'items', 'maxItems'} if kind == 'array' else {'maxLength'} if kind == 'string' else set())
        if set(node) - permitted:
            raise ValueError('schema keyword does not apply to this type')
        if 'enum' in node and (not isinstance(node['enum'], list) or not node['enum']):
            raise ValueError('enum must contain choices')
        if kind == 'object':
            props = node.get('properties', {})
            required = node.get('required', [])
            if not isinstance(props, dict) or not isinstance(required, list) or any(key not in props for key in required):
                raise ValueError('invalid object schema')
            if node.get('additionalProperties', False) is not False:
                raise ValueError('this subset requires closed objects')
            for child in props.values():
                check_schema(child)
        if kind == 'array':
            check_schema(node.get('items'))
        for key in ('maxItems', 'maxLength'):
            if key in node and (type(node[key]) is not int or node[key] < 0):
                raise ValueError('nonnegative integer limit required')
    check_schema(schema)
    errors = []
    def visit(item, node, path):
        kind = node['type']
        valid = {'object': isinstance(item, dict), 'array': isinstance(item, list),
                 'string': isinstance(item, str), 'integer': type(item) is int,
                 'number': type(item) in (int, float), 'boolean': type(item) is bool,
                 'null': item is None}[kind]
        if not valid or (kind == 'number' and not math.isfinite(item)):
            errors.append(path + ':type')
            return
        if 'enum' in node and not any(type(item) is type(choice) and item == choice for choice in node['enum']):
            errors.append(path + ':enum')
        if kind == 'object':
            props = node.get('properties', {})
            errors.extend(path + '.' + key + ':missing' for key in sorted(set(node.get('required', [])) - item.keys()))
            for key in sorted(item):
                if key not in props:
                    errors.append(path + '.' + key + ':extra')
                else:
                    visit(item[key], props[key], path + '.' + key)
        if kind == 'array':
            if len(item) > node.get('maxItems', len(item)):
                errors.append(path + ':length')
            for index, child in enumerate(item):
                visit(child, node['items'], path + '[' + str(index) + ']')
        if kind == 'string' and len(item) > node.get('maxLength', len(item)):
            errors.append(path + ':length')
    visit(value, schema, '$')
    return errors
