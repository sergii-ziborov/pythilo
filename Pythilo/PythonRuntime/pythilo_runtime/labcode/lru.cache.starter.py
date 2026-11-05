class LRUCache:
    def __init__(self, capacity):
        self.capacity = capacity
        self.items = {}  # dicts keep their order: oldest first

    def get(self, key):
        if key not in self.items:
            return None
        # TODO: reading a key makes it the most recently used.
        # Move it to the end.
        return self.items[key]

    def put(self, key, value):
        if key in self.items:
            del self.items[key]
        self.items[key] = value
        if len(self.items) > self.capacity:
            oldest = next(iter(self.items))
            del self.items[oldest]
