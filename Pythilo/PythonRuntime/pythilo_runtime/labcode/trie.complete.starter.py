class Trie:
    def __init__(self):
        self.root = {}  # letter -> child node; "$" marks the end of a word

    def insert(self, word):
        node = self.root
        for ch in word:
            node = node.setdefault(ch, {})
        node["$"] = True

    def complete(self, prefix):
        node = self.root
        for ch in prefix:
            if ch not in node:
                return []
            node = node[ch]
        # TODO: collect every word below node, in sorted order,
        # not only the prefix itself.
        return [prefix] if "$" in node else []
