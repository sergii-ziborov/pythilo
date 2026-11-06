'use client';

import Link from 'next/link';
import { useState } from 'react';
import { filterLabCatalog, type LabCatalogCard, type LabTopic } from '@/lib/lab-catalog';
import { LabProgress } from './lab-progress';

export function CatalogBrowser({ labs, topics }: { labs: LabCatalogCard[]; topics: LabTopic[] }) {
  const [query, setQuery] = useState('');
  const [section, setSection] = useState('');
  const [runtime, setRuntime] = useState('');
  const [expanded, setExpanded] = useState<string[]>([]);
  const [collapsedSearch, setCollapsedSearch] = useState<string[]>([]);
  const matches = filterLabCatalog(labs, { query, section, runtime });
  const searching = query.trim().length > 0;
  const sections = [...new Set(topics.map(topic => topic.section))].filter(name => labs.some(lab => lab.section === name));
  function toggle(id: string) {
    if (searching) {
      setCollapsedSearch(current => current.includes(id) ? current.filter(value => value !== id) : [...current, id]);
      return;
    }
    setExpanded(current => current.includes(id) ? current.filter(value => value !== id) : [...current, id]);
  }
  return <section className="lab-catalog" aria-label="Browse Labs by topic">
    <div className="lab-catalog-filters">
      <label>Search Labs<input type="search" value={query} onChange={event => { setQuery(event.target.value); setCollapsedSearch([]); }} placeholder="PyTorch, attention, training…" /></label>
      <label>Section<select value={section} onChange={event => setSection(event.target.value)}><option value="">All sections</option>{sections.map(value => <option key={value}>{value}</option>)}</select></label>
      <label>Run location<select value={runtime} onChange={event => setRuntime(event.target.value)}><option value="">All runtimes</option><option value="browser">Runs in this browser</option><option value="pytorch">PyTorch in the app</option></select></label>
    </div>
    <p className="lab-catalog-count" role="status">{matches.length} of {labs.length} Labs shown · choose a topic to expand</p>
    {matches.length === 0 ? <div className="lab-catalog-empty"><p>No Labs match these filters.</p><button type="button" onClick={() => { setQuery(''); setSection(''); setRuntime(''); }}>Clear filters</button></div> : null}
    {sections.map(name => {
      const groups = topics.filter(topic => topic.section === name).map(topic => ({ topic, labs: matches.filter(lab => lab.topic === topic.id) })).filter(group => group.labs.length > 0);
      if (groups.length === 0) return null;
      return <section className="labs-group" key={name} aria-label={name}><h2>{name}</h2>{groups.map(({ topic, labs: entries }) => {
        const open = searching ? !collapsedSearch.includes(topic.id) : expanded.includes(topic.id);
        return <div className="lab-topic" key={topic.id}>
          <h3><button type="button" className="lab-topic-toggle" aria-expanded={open} aria-controls={`topic-${topic.id}`} onClick={() => toggle(topic.id)}><span>{topic.title}</span><span>{entries.length} {entries.length === 1 ? 'Lab' : 'Labs'} <span aria-hidden="true">{open ? '−' : '+'}</span></span></button></h3>
          <div id={`topic-${topic.id}`} hidden={!open} className="labs-cards">{entries.map(lab => <Link href={`/labs/${lab.id}/`} key={lab.id}>
            <span className="lab-card-kind">{lab.runtime === 'pytorch' ? 'PYTORCH · APP REQUIRED' : 'PYTHON · RUNS HERE'}{lab.runtime === 'browser' ? <LabProgress id={lab.id} /> : null}</span>
            <h4>{lab.title}</h4><p>{lab.summary}</p><span className="lab-card-link">{lab.runtime === 'pytorch' ? 'View Lab and lesson' : 'Open Lab'} <span aria-hidden="true">↗</span></span>
          </Link>)}</div>
        </div>;
      })}</section>;
    })}
  </section>;
}
