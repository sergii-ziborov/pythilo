export type LabCatalogCard = {
  id: string;
  title: string;
  summary: string;
  section: string;
  topic: string;
  topicTitle: string;
  runtime: 'browser' | 'pytorch';
};
export type LabTopic = { id: string; title: string; section: string };
export type LabCatalogFilter = { query: string; section: string; runtime: string };

export function filterLabCatalog(labs: LabCatalogCard[], filter: LabCatalogFilter) {
  const words = filter.query.toLowerCase().trim().split(/\s+/).filter(Boolean);
  return labs.filter(lab => {
    if (filter.section && lab.section !== filter.section) return false;
    if (filter.runtime && lab.runtime !== filter.runtime) return false;
    const text = `${lab.title} ${lab.summary} ${lab.topicTitle}`.toLowerCase();
    return words.every(word => text.includes(word));
  });
}
