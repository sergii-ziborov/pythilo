import guides from "../content/lab-guides.json" with { type: "json" };

/** The app's "About this algorithm" guide for a Lab: idea, steps, cost, uses and pitfalls. */
export type LabGuide = {
  idea: string;
  steps: string[];
  cost: { label: string; value: string }[];
  costNote: string;
  uses: string[];
  pitfalls: string[];
  watch: string;
};

export const labGuides = guides as Record<string, LabGuide>;

export const labGuide = (id: string): LabGuide | undefined => labGuides[id];

/** Guide text without its backticks, for descriptions and structured data. */
export const guidePlain = (text: string) => text.replace(/`/g, "").replace(/\s+/g, " ").trim();
