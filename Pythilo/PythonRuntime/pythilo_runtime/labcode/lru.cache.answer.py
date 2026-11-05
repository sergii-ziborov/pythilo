class LRUCache:
    def __init__(self, capacity):
        self.capacity = capacity
        self.items = {}  # dicts keep their order: oldest first

    def get(self, key):
        if key not in self.items:
            return None
        value = self.items.pop(key)  # take it out...
        self.items[key] = value      # ...and put it back at the newest end
        return value

    def put(self, key, value):
        if key in self.items:
            del self.items[key]
        self.items[key] = value
        if len(self.items) > self.capacity:
            oldest = next(iter(self.items))
            del self.items[oldest]
