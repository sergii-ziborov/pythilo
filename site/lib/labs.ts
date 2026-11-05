/** App labs, grouped as in Pythilo/UI/Labs/LabCatalog.swift. */
export const labGroups = [
  { title: "Basics", labs: [
    { id: "binsearch", title: "Binary Search", summary: "Watch lo, hi and mid close in on the target." },
    { id: "window", title: "Two Pointers & Sliding Window", summary: "Grow and shrink a window instead of starting over." },
    { id: "stackqueue", title: "Stacks & Queues", summary: "Match brackets with a stack and pass a potato with a queue." },
    { id: "recursion", title: "Recursion Tree", summary: "Follow every call, the call stack and each returned value." },
  ] },
  { title: "Data structures", labs: [
    { id: "linkedlist", title: "Linked Lists", summary: "Reverse the arrows or find the middle with two pointers." },
    { id: "hash", title: "Search & Hashing", summary: "Build a hash table and see buckets fill and keys collide." },
    { id: "bst", title: "Binary Search Trees", summary: "Insert and delete nodes, smaller left and larger right." },
    { id: "heap", title: "Heaps & Priority Queues", summary: "Sift up and down, as a tree and as a list." },
    { id: "trie", title: "Tries", summary: "Store words letter by letter, then autocomplete a prefix." },
    { id: "unionfind", title: "Union-Find", summary: "Merge sets and watch path compression flatten them." },
    { id: "lru", title: "LRU Cache", summary: "Keep recent keys and evict the one unused longest." },
  ] },
  { title: "Algorithms", labs: [
    { id: "sorting", title: "Sorting Bench", summary: "Trace your sort read by read, then see how it scales." },
    { id: "graph", title: "Graph Explorer", summary: "Follow BFS, DFS or Dijkstra across grids, trees and random graphs." },
    { id: "dp", title: "Dynamic Programming", summary: "Count repeated calls, add a cache and fill a table cell by cell." },
    { id: "queens", title: "Backtracking", summary: "Place N queens, reach a dead end, undo and try again." },
    { id: "matching", title: "String Matching", summary: "Slide a pattern through text with naive matching and KMP." },
    { id: "flood", title: "Flood Fill", summary: "Spread through a grid with a stack or queue and count islands." },
  ] },
  { title: "Machine learning", labs: [
    { id: "descent", title: "Gradient Descent", summary: "Roll downhill on a loss surface, with and without momentum." },
    { id: "neural", title: "Neurons", summary: "Train a perceptron, then a small network that learns XOR." },
    { id: "genetic", title: "Genetic Algorithm", summary: "Evolve a phrase or a short tour through fitness, selection and mutation." },
    { id: "kmeans", title: "k-means Clustering", summary: "Assign points, move centres and repeat until still." },
    { id: "qlearning", title: "Q-learning", summary: "Teach an agent to navigate a maze from rewards." },
  ] },
];

export const labCount = labGroups.reduce((total, group) => total + group.labs.length, 0);
