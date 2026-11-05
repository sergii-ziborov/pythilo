import SwiftUI

/// One problem inside a lab. Its starter and answer live next to the Python that traces them,
/// in pythilo_runtime/labcode/<lab>.<variant>.starter.py and .answer.py.
struct LabVariant: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let prompt: String
    let file: String
    var scales = true
}

struct LabInfo: Codable, Identifiable, Hashable, Sendable {
    enum Section: String, Codable, CaseIterable, Sendable {
        case basics = "Basics"
        case structures = "Data structures"
        case algorithms = "Algorithms"
        case learning = "Machine learning"
        case intelligence = "Artificial intelligence"
    }

    let id: String
    let title: String
    let summary: String
    let symbol: String
    let tint: Tint
    let section: Section
    var variants: [LabVariant] = []

    /// The labs written before the shared engine have screens of their own.
    var isClassic: Bool { variants.isEmpty }

    enum Tint: String, Codable, Sendable { case run, blue, mint, violet, amber, coral }

    var color: Color {
        switch tint {
        case .run: AppTheme.run
        case .blue: AppTheme.blue
        case .mint: AppTheme.mint
        case .violet: AppTheme.violet
        case .amber: AppTheme.amber
        case .coral: AppTheme.coral
        }
    }
}

enum LabCatalog {
    enum Code: String { case starter, answer }

    static func code(_ lab: String, _ variant: String, _ kind: Code) -> String {
        let url = Bundle.main.bundleURL.appending(path: "app/pythilo_runtime/labcode/\(lab).\(variant).\(kind.rawValue).py")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "# The \(kind.rawValue) for this lab is missing from the app.\n"
    }

    static func lab(_ id: String) -> LabInfo? { all.first { $0.id == id } }

    private static let expanded: [LabInfo] = {
        let url = Bundle.main.bundleURL.appending(path: "app/pythilo_runtime/labcode/catalog-expansion.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LabInfo].self, from: data)) ?? []
    }()

    static let all: [LabInfo] = [
        // Basics
        LabInfo(id: "binsearch", title: "Binary Search", summary: "Watch lo, hi and mid close in on the target", symbol: "arrow.left.and.right.square", tint: .blue, section: .basics, variants: [
            LabVariant(id: "search", title: "Search", prompt: "binary_search(items, target) gives the index of target in the sorted list items, or -1. Each step should halve the part that is left.", file: "search.py"),
        ]),
        LabInfo(id: "window", title: "Two Pointers & Sliding Window", summary: "Grow and shrink a window instead of starting over", symbol: "rectangle.split.3x1", tint: .mint, section: .basics, variants: [
            LabVariant(id: "unique", title: "Longest unique", prompt: "longest_unique(text): the length of the longest stretch of text with no repeated character. The starter is right but slow; trace it, then see how it scales.", file: "window.py"),
        ]),
        LabInfo(id: "stackqueue", title: "Stacks & Queues", summary: "Match brackets with a stack, pass a potato with a queue", symbol: "square.stack", tint: .violet, section: .basics, variants: [
            LabVariant(id: "brackets", title: "Brackets", prompt: "balanced(text) is True when every (, [ and { is closed by its own kind, in the right order.", file: "brackets.py"),
            LabVariant(id: "queue", title: "Hot potato", prompt: "hot_potato(names, k): players stand in a queue. Pass the potato k times (front to back), then whoever holds it is out. Return the order they leave in.", file: "potato.py"),
        ]),
        LabInfo(id: "recursion", title: "Recursion Tree", summary: "See every call, the call stack, and what each call returns", symbol: "point.3.filled.connected.trianglepath.dotted", tint: .amber, section: .basics, variants: [
            LabVariant(id: "permutations", title: "Permutations", prompt: "permutations(items) returns every ordering of items as a list of lists. Each call fixes one item and asks for the orderings of the rest.", file: "permutations.py"),
            LabVariant(id: "mergesort", title: "Merge sort", prompt: "merge_sort(items) returns a sorted copy: sort each half, then merge the two sorted halves.", file: "merge_sort.py"),
        ]),
        // Data structures
        LabInfo(id: "linkedlist", title: "Linked Lists", summary: "Turn the arrows around with prev, current and next", symbol: "link", tint: .blue, section: .structures, variants: [
            LabVariant(id: "reverse", title: "Reverse", prompt: "reverse(head) turns every next arrow around and returns the new head. Node(value, next) is ready to use.", file: "linked.py"),
            LabVariant(id: "middle", title: "Middle", prompt: "middle(head) returns the middle node in one pass: slow moves one step while fast moves two.", file: "linked.py"),
        ]),
        LabInfo(id: "hash", title: "Search & Hashing", summary: "Build a hash table and see buckets fill and keys collide", symbol: "square.stack.3d.up.fill", tint: .mint, section: .structures),
        LabInfo(id: "bst", title: "Binary Search Trees", summary: "Insert and delete, smaller left and larger right", symbol: "arrow.triangle.branch", tint: .violet, section: .structures, variants: [
            LabVariant(id: "insert", title: "Insert", prompt: "insert(root, value) adds value where a search for it would end and returns the root. TreeNode(value) is ready to use.", file: "bst.py"),
            LabVariant(id: "delete", title: "Delete", prompt: "delete(root, value) removes value and returns the root. The hard case: a node with two children.", file: "bst.py"),
        ]),
        LabInfo(id: "heap", title: "Heaps & Priority Queues", summary: "Sift up and sift down, as a tree and as a list", symbol: "triangle", tint: .amber, section: .structures, variants: [
            LabVariant(id: "push", title: "Push", prompt: "push(heap, value) adds value to a min-heap kept in a plain list: append it, then sift it up past bigger parents.", file: "heap.py"),
            LabVariant(id: "pop", title: "Pop", prompt: "pop(heap) removes and returns the smallest item: move the last item to the top, then sift it down.", file: "heap.py"),
        ]),
        LabInfo(id: "trie", title: "Tries", summary: "Store words letter by letter, then autocomplete", symbol: "character.textbox", tint: .mint, section: .structures, variants: [
            LabVariant(id: "complete", title: "Autocomplete", prompt: "A Trie stores words as nested dicts, one letter per level, with \"$\" marking a word's end. complete(prefix) returns every stored word that starts with prefix, sorted.", file: "trie.py"),
        ]),
        LabInfo(id: "unionfind", title: "Union-Find", summary: "Merge sets and watch path compression flatten them", symbol: "circle.grid.cross", tint: .coral, section: .structures, variants: [
            LabVariant(id: "sets", title: "Find & union", prompt: "parent[x] is x's parent and a root names its set. find(parent, x) returns x's root; union(parent, a, b) joins their sets.", file: "union_find.py"),
        ]),
        LabInfo(id: "lru", title: "LRU Cache", summary: "Keep the recent keys, evict the one unused longest", symbol: "clock.arrow.circlepath", tint: .blue, section: .structures, variants: [
            LabVariant(id: "cache", title: "Cache", prompt: "LRUCache(capacity) with get(key) (None when missing) and put(key, value). When full, put evicts the key that was used least recently.", file: "lru.py"),
        ]),
        // Algorithms
        LabInfo(id: "sorting", title: "Sorting Bench", summary: "Trace your sort read by read, then see how it scales", symbol: "chart.bar.fill", tint: .run, section: .algorithms),
        LabInfo(id: "graph", title: "Graph Explorer", summary: "Watch your BFS, DFS or Dijkstra expand a grid, tree or random graph", symbol: "point.3.connected.trianglepath.dotted", tint: .blue, section: .algorithms),
        LabInfo(id: "dp", title: "Dynamic Programming", summary: "Count repeated calls, add a cache, fill the table cell by cell", symbol: "tablecells", tint: .violet, section: .algorithms),
        LabInfo(id: "queens", title: "Backtracking", summary: "Place N queens, hit a dead end, undo and try again", symbol: "crown", tint: .amber, section: .algorithms, variants: [
            LabVariant(id: "queens", title: "N-Queens", prompt: "solve(n) returns every way to put n queens on an n × n board so none attacks another: one per row, column and diagonal.", file: "queens.py"),
        ]),
        LabInfo(id: "matching", title: "String Matching", summary: "Slide a pattern along a text, naive and KMP", symbol: "text.magnifyingglass", tint: .mint, section: .algorithms, variants: [
            LabVariant(id: "naive", title: "Naive", prompt: "find_all(text, pattern) returns every index where pattern starts in text, overlaps included.", file: "match.py"),
            LabVariant(id: "kmp", title: "KMP", prompt: "The same find_all, but it must never step back in the text: after a mismatch, a failure table says how far the pattern can slide.", file: "match.py"),
        ]),
        LabInfo(id: "flood", title: "Flood Fill", summary: "Spread through a grid with a stack or a queue", symbol: "drop.fill", tint: .blue, section: .algorithms, variants: [
            LabVariant(id: "fill", title: "Fill", prompt: "fill(grid, row, col) paints every open cell (\".\") you can reach from (row, col) with \"o\", moving up, down, left and right.", file: "flood.py"),
            LabVariant(id: "islands", title: "Islands", prompt: "count_islands(grid): how many separate islands of land (\"L\") there are, where touching up, down, left or right joins land.", file: "islands.py"),
        ]),
        // Machine learning
        LabInfo(id: "descent", title: "Gradient Descent", summary: "Roll downhill on a loss surface, with and without momentum", symbol: "arrow.down.right.and.arrow.up.left", tint: .coral, section: .learning, variants: [
            LabVariant(id: "plain", title: "Descent", prompt: "step(x, y, gx, gy, lr) gets the gradient at (x, y) and returns the next point. The lab calls it 40 times and draws the path.", file: "descent.py", scales: false),
            LabVariant(id: "momentum", title: "Momentum", prompt: "step(x, y, gx, gy, vx, vy, lr, beta) also carries a velocity, so steps build speed along a long, shallow valley.", file: "momentum.py", scales: false),
        ]),
        LabInfo(id: "neural", title: "Neurons", summary: "A perceptron's line, then a small network learning XOR", symbol: "brain", tint: .violet, section: .learning, variants: [
            LabVariant(id: "perceptron", title: "Perceptron", prompt: "update(w, b, x, y, lr) is the perceptron rule: when point x with label y (+1 or -1) is on the wrong side of the line, move the line toward it.", file: "perceptron.py"),
            LabVariant(id: "xor", title: "XOR network", prompt: "train_step(net, X, y, lr) runs one step of training with numpy: forward, backward, then update every weight. No single line can split XOR; a hidden layer can.", file: "network.py"),
        ]),
        LabInfo(id: "genetic", title: "Genetic Algorithm", summary: "Evolve a population: fitness, selection, crossover, mutation", symbol: "leaf", tint: .mint, section: .learning, variants: [
            LabVariant(id: "strings", title: "Evolve a phrase", prompt: "Write fitness, crossover and mutate. Each generation keeps the fittest, breeds children from them, and mutates a letter now and then, until the phrase appears.", file: "evolve.py", scales: false),
            LabVariant(id: "tsp", title: "Shortest tour", prompt: "Evolve a short round trip through 12 cities. A child must still visit every city exactly once, so crossover needs care.", file: "tours.py", scales: false),
        ]),
        LabInfo(id: "kmeans", title: "k-means Clustering", summary: "Assign points, move centers, repeat until still", symbol: "circle.hexagongrid", tint: .blue, section: .learning, variants: [
            LabVariant(id: "kmeans", title: "k-means", prompt: "assign(points, centers) gives each point its nearest center; update(points, labels, centers) moves each center to the mean of its points.", file: "kmeans.py"),
        ]),
        LabInfo(id: "qlearning", title: "Q-learning", summary: "An agent learns a maze from rewards alone", symbol: "figure.walk", tint: .amber, section: .learning, variants: [
            LabVariant(id: "grid", title: "Grid world", prompt: "update(Q, state, action, reward, next_state, alpha, gamma) nudges Q[state][action] toward reward + gamma × the best value of the next state.", file: "qlearning.py", scales: false),
        ]),
    ] + expanded
}
