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
        words = []
        todo = [(node, prefix)]
        while todo:
            node, word = todo.pop()
            if "$" in node:
                words.append(word)
            for ch in node:
                if ch != "$":
                    todo.append((node[ch], word + ch))
        return sorted(words)
